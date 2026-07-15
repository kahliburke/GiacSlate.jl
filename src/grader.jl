# ---------------------------------------------------------------------------
# GiacSlate lesson autograder
#
# Students fill in `missing` stubs inside a Slate notebook, then reactive
# `check(:key, answer)` / `grade(:section; ...)` cells call in here. All answer
# keys and reference solutions live in the package, never in the notebook — the
# reader only ever sees their own code and a self-updating score card.
#
# Design follows HeliumPhysics.jl's grader, with two additions:
#   * `expect_symbolic` grades a *symbolic* answer by asking Giac whether
#     (student − reference) simplifies to zero — exact algebra, not tolerance.
#   * `course_report(...)` rolls every section up into one progress overview.
# ---------------------------------------------------------------------------

using Giac
using Giac.Commands: simplify, normal

# ---- primitives -----------------------------------------------------------

struct Check
    pass::Bool
    label::String
    detail::String
end
Check(pass::Bool, label::AbstractString) = Check(pass, String(label), "")

"""A passing/failing check with a short label and optional detail line."""
pass(label, detail = "") = Check(true, String(label), String(detail))
fail(label, detail = "") = Check(false, String(label), String(detail))

struct Exercise
    key::Symbol        # the keyword a reader passes to `check` / `grade`
    title::String
    hint::String
    run::Function      # answer -> Vector{Check}
end

struct Section
    id::Symbol
    title::String
    blurb::String      # shown when the whole section is solved
    exercises::Vector{Exercise}
end

const SECTIONS = Dict{Symbol,Section}()
const SECTION_ORDER = Symbol[]

"Register (or replace) a section so `check`/`grade`/`course_report` can find it."
function register!(sec::Section)
    haskey(SECTIONS, sec.id) || push!(SECTION_ORDER, sec.id)
    SECTIONS[sec.id] = sec
    sec
end

# ---- sandboxing & comparison ---------------------------------------------

# Call a student's function without letting a throw or an unfilled `missing`
# stub take down the grader.
function trycall(f, args...; kwargs...)
    try
        v = f(args...; kwargs...)
        v === missing ? (:missing, nothing) : (:ok, v)
    catch err
        (:error, err)
    end
end

approxeq(a, b; atol = 1e-6, rtol = 1e-6) = _approxeq(a, b, atol, rtol)
_approxeq(a::Number, b::Number, atol, rtol) = isapprox(a, b; atol, rtol)
_approxeq(a::AbstractArray, b::AbstractArray, atol, rtol) =
    size(a) == size(b) && isapprox(a, b; atol, rtol)
_approxeq(a::Tuple, b::Tuple, atol, rtol) =
    length(a) == length(b) && all(_approxeq(x, y, atol, rtol) for (x, y) in zip(a, b))
_approxeq(a, b, atol, rtol) = a == b

preview(x::AbstractFloat) = string(round(x; sigdigits = 6))
preview(x::Integer) = string(x)
preview(x::Complex) = string(round(x; sigdigits = 5))
function preview(x)
    s = string(x)
    length(s) > 90 ? first(s, 87) * "…" : s
end
argstr(args) = join((preview(a) for a in args), ", ")

# ---- Giac symbolic equality ----------------------------------------------

_as_giac(x::GiacExpr) = x
_as_giac(x) = Giac.giac_eval(string(x))

# Two encodings of the SAME symbol a reader may enter: the math field emits the
# unicode `ω`, while `\omega` / typed-out `omega` parse to the ASCII identifier
# `omega`. Fold the unicode glyph onto the ASCII spelling so both read as one
# variable — this unifies encodings, it does NOT alias distinct letters together.
const _SYMBOL_ALIASES = ("ω" => "omega",)

function _canon(e)
    for (from, to) in _SYMBOL_ALIASES
        e = try
            Giac.giac_eval("subst($(string(e)), $from=$to)")
        catch
            e   # if the substitution can't be expressed, compare as-is
        end
    end
    e
end

# Does the Giac expression reduce to exactly zero?
function giac_iszero(e)
    for f in (simplify, normal)
        try
            s = strip(string(f(e)))
            (s == "0" || s == "0.0" || s == "0.") && return true
        catch
            # fall through to the next reducer
        end
    end
    false
end

# ---- combinators ----------------------------------------------------------

"""
    expect(label, impl, ref, cases; atol, rtol, hint, reveal)

Run the student function `impl` on each argument tuple in `cases` and compare
against `ref` with numeric tolerance. Emits one `Check` per case.
"""
function expect(label, impl, ref, cases; atol = 1e-6, rtol = 1e-6, hint = "", reveal = true)
    checks = Check[]
    for (i, args) in enumerate(cases)
        tag = length(cases) == 1 ? label : "$label — case $i"
        status, got = trycall(impl, args...)
        if status === :missing
            push!(checks, fail("$tag: not implemented yet",
                isempty(hint) ? "replace the `missing` with your code" : hint))
            continue
        elseif status === :error
            push!(checks, fail("$tag: threw an error",
                "on input ($(argstr(args)))  —  $(sprint(showerror, got))"))
            continue
        end
        want = ref(args...)
        if approxeq(got, want; atol, rtol)
            push!(checks, pass(tag))
        else
            det = reveal ?
                  "input ($(argstr(args)))  →  got $(preview(got)), expected $(preview(want))" :
                  "input ($(argstr(args)))  →  got $(preview(got)); not the expected value"
            push!(checks, fail("$tag: not quite", det))
        end
    end
    checks
end

"""
    expect_symbolic(label, student, reference; hint, reveal)

Grade a *symbolic* answer: pass iff Giac simplifies `student - reference` to 0.
By default the correct closed form is NOT revealed on a wrong answer (the point
of the exercise) — set `reveal = true` to show it.
"""
function expect_symbolic(label, student, reference; hint = "", reveal = false)
    student === missing && return Check[fail("$label: not answered yet",
        isempty(hint) ? "type your answer into the math field above" : hint)]
    diff = try
        _canon(_as_giac(student)) - _canon(_as_giac(reference))
    catch err
        return Check[fail("$label: couldn't read your expression", sprint(showerror, err))]
    end
    if giac_iszero(diff)
        Check[pass(label)]
    else
        det = reveal ?
              "you have $(string(simplify(_as_giac(student)))); expected $(string(reference))" :
              "not equivalent to the correct expression — check your algebra" *
              (isempty(hint) ? "" : ".  $hint")
        Check[fail("$label: not equivalent", det)]
    end
end

"""A single boolean assertion as a `Check`."""
property(label, ok::Bool, detail = "") = ok ? pass(label) : fail(label, detail)

# ---- results & reports ----------------------------------------------------

struct ExResult
    key::Symbol
    title::String
    hint::String
    provided::Bool
    checks::Vector{Check}
end
solved(r::ExResult) = r.provided && !isempty(r.checks) && all(c -> c.pass, r.checks)

struct GradeReport
    section::Section
    results::Vector{ExResult}
    single::Bool
end
nsolved(r::GradeReport) = count(solved, r.results)
ntotal(r::GradeReport) = length(r.results)

struct CourseReport
    sections::Vector{GradeReport}
end

function _run_exercise(ex::Exercise, answer, provided::Bool)
    checks = if !provided
        Check[]
    else
        try
            Vector{Check}(ex.run(answer))
        catch err
            Check[fail("grader error while checking", sprint(showerror, err))]
        end
    end
    ExResult(ex.key, ex.title, ex.hint, provided, checks)
end

function _results_for(sec::Section, provided::AbstractDict)
    [_run_exercise(ex, get(provided, ex.key, nothing), haskey(provided, ex.key))
     for ex in sec.exercises]
end

"""
    grade(section_id; key1 = answer1, key2 = answer2, ...) -> GradeReport

Grade a whole section. Each keyword maps an exercise `key` to the reader's
answer; omitted exercises show as "not attempted".
"""
function grade(section_id::Symbol; kwargs...)
    sec = get(SECTIONS, section_id, nothing)
    sec === nothing &&
        error("unknown section :$section_id  (known: $(join(SECTION_ORDER, ", ")))")
    GradeReport(sec, _results_for(sec, Dict(kwargs)), false)
end

function _find_exercise(key::Symbol)
    hits = [(sid, ex) for sid in SECTION_ORDER
            for ex in SECTIONS[sid].exercises if ex.key == key]
    isempty(hits) && error("no exercise :$key is registered")
    length(hits) > 1 &&
        error("exercise :$key appears in several sections; use check(:section, :$key, answer)")
    hits[1]
end

_single_report(sec, ex, answer) =
    GradeReport(Section(sec.id, sec.title, sec.blurb, [ex]),
        [_run_exercise(ex, answer, true)], true)

"""
    check(key, answer) -> GradeReport

Instant single-exercise check. Drop this one-liner in a cell below your answer;
because the cell reads your binding, Slate re-runs it every time you edit.
"""
function check(key::Symbol, answer)
    sid, ex = _find_exercise(key)
    _single_report(SECTIONS[sid], ex, answer)
end

"Disambiguated single check when a key is shared across sections."
function check(section_id::Symbol, key::Symbol, answer)
    sec = get(SECTIONS, section_id, nothing)
    sec === nothing && error("unknown section :$section_id")
    idx = findfirst(e -> e.key == key, sec.exercises)
    idx === nothing && error("section :$section_id has no exercise :$key")
    _single_report(sec, sec.exercises[idx], answer)
end

"""
    course_report(; key1 = answer1, ...) -> CourseReport

Roll every registered section into one progress overview. Pass every answer you
have by keyword; the card shows overall completion plus a bar per section.
"""
function course_report(; kwargs...)
    provided = Dict(kwargs)
    CourseReport([GradeReport(SECTIONS[sid], _results_for(SECTIONS[sid], provided), false)
                  for sid in SECTION_ORDER])
end

# ---- rendering ------------------------------------------------------------

const _C_GOOD = "#56d364"
const _C_WARN = "#e3b341"
const _C_BAD  = "#f56c6c"
const _C_MUTE = "#8b949e"
const _C_CARD = "#161b22"
const _C_EDGE = "#30363d"
const _C_HINT = "#a371f7"

htmlesc(s) = replace(string(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

_accent(pct) = pct >= 100 ? _C_GOOD : pct <= 0 ? _C_BAD : _C_WARN

function _bar_html(pct, accent)
    """<div style="background:#0d1117;border-radius:6px;height:9px;overflow:hidden;margin:8px 0 2px">
       <div style="width:$(pct)%;height:100%;background:$(accent);transition:width .3s"></div></div>"""
end

function _exercise_row_html(r::ExResult)
    if !r.provided
        glyph, gcol, status = "○", _C_MUTE, "not attempted"
    elseif solved(r)
        glyph, gcol, status = "✓", _C_GOOD, "solved"
    else
        glyph, gcol, status = "✗", _C_BAD, "keep going"
    end
    io = IOBuffer()
    print(io, """<div style="margin:10px 0 4px"><span style="color:$gcol;font-weight:700">$glyph</span>
        <span style="color:#e6edf3;font-weight:600"> $(htmlesc(r.title))</span>
        <span style="color:$_C_MUTE;font-size:12px"> — $status</span></div>""")
    for c in r.checks
        c.pass && continue
        print(io, """<div style="margin:2px 0 2px 20px;color:$_C_BAD;font-size:13px">✗ $(htmlesc(c.label))</div>""")
        isempty(c.detail) ||
            print(io, """<div style="margin:0 0 2px 34px;color:$_C_MUTE;font-size:12px">$(htmlesc(c.detail))</div>""")
    end
    if r.provided && !solved(r) && !isempty(r.hint)
        print(io, """<div style="margin:6px 0 2px 20px;padding:7px 10px;border-left:3px solid $_C_HINT;
            background:rgba(163,113,247,.08);color:#d2c4f5;font-size:12.5px;border-radius:3px">
            💡 <b>Hint:</b> $(htmlesc(r.hint))</div>""")
    end
    String(take!(io))
end

function Base.show(io::IO, ::MIME"text/html", r::GradeReport)
    n, tot = nsolved(r), ntotal(r)
    pct = tot == 0 ? 0 : round(Int, 100n / tot)
    accent = _accent(pct)
    header = r.single ? r.section.title : r.section.title
    print(io, """<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
        background:$_C_CARD;border:1px solid $_C_EDGE;border-radius:10px;padding:16px 18px;max-width:680px">
        <div style="color:#e6edf3;font-weight:700;font-size:15px">$(htmlesc(header))</div>
        <div style="color:$accent;font-weight:600;font-size:13px;margin-top:2px">$(r.single ? "check" : "$n / $tot solved  ·  $pct%")</div>
        $(_bar_html(pct, accent))""")
    for res in r.results
        print(io, _exercise_row_html(res))
    end
    if pct >= 100
        msg = r.single ? "✓ Looks right." : "🎉 $(htmlesc(r.section.blurb))"
        print(io, """<div style="margin-top:10px;color:$_C_GOOD;font-weight:600;font-size:13px">$msg</div>""")
    end
    print(io, "</div>")
end

function Base.show(io::IO, ::MIME"text/html", cr::CourseReport)
    tot = sum(ntotal, cr.sections; init = 0)
    done = sum(nsolved, cr.sections; init = 0)
    pct = tot == 0 ? 0 : round(Int, 100done / tot)
    accent = _accent(pct)
    print(io, """<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
        background:$_C_CARD;border:1px solid $_C_EDGE;border-radius:10px;padding:16px 18px;max-width:680px">
        <div style="color:#e6edf3;font-weight:700;font-size:16px">📊 Course progress</div>
        <div style="color:$accent;font-weight:600;font-size:13px;margin-top:2px">$done / $tot exercises  ·  $pct%</div>
        $(_bar_html(pct, accent))""")
    for sr in cr.sections
        n, t = nsolved(sr), ntotal(sr)
        p = t == 0 ? 0 : round(Int, 100n / t)
        a = _accent(p)
        print(io, """<div style="margin:12px 0 2px;color:#e6edf3;font-weight:600;font-size:13px">
            $(htmlesc(sr.section.title))
            <span style="color:$_C_MUTE;font-weight:500"> — $n/$t</span></div>$(_bar_html(p, a))""")
    end
    print(io, "</div>")
end

# Plain-text fallback (REPL / logs / non-HTML export).
function Base.show(io::IO, ::MIME"text/plain", r::GradeReport)
    n, tot = nsolved(r), ntotal(r)
    println(io, r.section.title, "  (", n, "/", tot, " solved)")
    for res in r.results
        g = !res.provided ? "○" : solved(res) ? "✓" : "✗"
        println(io, "  ", g, " ", res.title)
        for c in res.checks
            c.pass && continue
            println(io, "      ✗ ", c.label, isempty(c.detail) ? "" : "  —  " * c.detail)
        end
    end
end
