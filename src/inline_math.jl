# ---------------------------------------------------------------------------
# Inline math in cells + markdown.
#
#   giac"1/(s+a)"        a string macro → a GiacExpr (runs natively via giac_eval).
#                        The inline-math editor renders it as a live math field.
#   gmath(e) / gdisplay(e)   render a GiacExpr as LaTeX for markdown `{{ … }}`
#                        interpolation — inline ($…$) and display ($$…$$).
#
# The two conversion directions the editor bridge needs are here too:
#   giac_src_to_tex     giac source  → LaTeX   (display)
#   mathjson_to_giac_src  MathLive MathJSON → giac source  (write-back)
# ---------------------------------------------------------------------------

"""
    giac"…"

Parse and evaluate GIAC source into a `GiacExpr`, e.g. `giac"1/(s+a)"`, `giac"diff(sin(x),x)"`.
The inline-math editor renders such a literal as a live, editable math field.

An **empty** literal (`giac""`, the state of a blank math field) evaluates to `missing`
rather than throwing — so a blank field reads cleanly as "not filled in yet" (e.g. an
unanswered exercise flows through an autograder as `missing`) instead of breaking the cell.
"""
macro giac_str(s)
    isempty(strip(s)) ? :(missing) : :($(Giac.giac_eval)($s))
end

# GiacExpr → inner LaTeX (no surrounding $).
_giac_tex(e) = strip(sprint(show, MIME("text/latex"), e), ['$', '\n', ' '])

"""
    gmath(e)  ·  gdisplay(e)

Render a `GiacExpr` (or anything with a `text/latex` show) as a LaTeX string wrapped for
markdown: `gmath` inline (`\$…\$`), `gdisplay` as a display block (`\$\$…\$\$`). Use inside
a markdown cell's `{{ … }}` interpolation to typeset a code-cell math variable — e.g.
`The transfer function is {{ gmath(H) }}.` The cell re-renders when the variable changes.
"""
gmath(e)    = "\$" * _giac_tex(e) * "\$"
gdisplay(e) = "\$\$" * _giac_tex(e) * "\$\$"

# giac source → LaTeX (display side of the editor bridge). GIAC is lenient — it returns
# `undef` for malformed input instead of throwing — so treat that as an error too.
function giac_src_to_tex(src::AbstractString)
    isempty(strip(src)) && return ""
    g = Giac.giac_eval(String(src))
    strip(string(g)) == "undef" && error("not a valid GIAC expression")
    _giac_tex(g)
end

# MathLive MathJSON → giac SOURCE string (write-back side). Empty / error payloads → "".
function mathjson_to_giac_src(json::AbstractString)
    isempty(strip(json)) && return ""
    x = JSON.parse(json)
    (x === nothing || x == "Nothing") && return ""
    (x isa AbstractVector && !isempty(x) && x[1] == "Error") && return ""
    String(strip(_giac_src(x)))
end

# ── Front-end registration for the inline-math EDITOR extension ──────────────
# `inline_math_boot()` renders as a <script> that registers assets/inline_math_editor.js
# with Slate's editor-extension registry, so `giac"…"` renders live in every code cell.
# Pair it in a (hidecode) boot cell with the two bridge handlers the extension calls:
#   slate_on("giac_tex", a -> Dict("latex" => giac_src_to_tex(String(a.src))))
#   slate_on("giac_src", a -> Dict("src"   => mathjson_to_giac_src(String(a.mj))))
struct InlineMathBoot end
_inline_math_js() = read(joinpath(@__DIR__, "..", "assets", "inline_math_editor.js"), String)
Base.show(io::IO, ::MIME"text/html", ::InlineMathBoot) = print(io, "<script>", _inline_math_js(), "</script>")

"One-time registration of the inline-math editor extension; see the module docs for the boot cell."
inline_math_boot() = InlineMathBoot()

"""
    inline_math_boot(slate_on)

One-line setup for a notebook cell. Registers the giac↔LaTeX bridge handlers through the
notebook's injected `slate_on` (the package can't reach it directly), then returns the
editor-extension registration to render. Use it in a (hidecode) cell as:

    GiacSlate.inline_math_boot(slate_on)
"""
function inline_math_boot(slate_on)
    slate_on("giac_tex", a -> begin
        try
            Dict("latex" => giac_src_to_tex(String(a.src)), "ok" => true)
        catch e
            Dict("latex" => "", "ok" => false, "error" => sprint(showerror, e))
        end
    end)
    slate_on("giac_src", a -> begin
        try
            Dict("src" => mathjson_to_giac_src(String(a.mj)), "ok" => true)
        catch e
            Dict("src" => "", "error" => sprint(showerror, e))
        end
    end)
    return InlineMathBoot()
end
