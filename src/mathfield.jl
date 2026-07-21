# ---------------------------------------------------------------------------
# MathLive → Giac bridge (proof-of-concept).
#
# A MathLive `<math-field>` emits the reader's expression as Compute-Engine
# MathJSON (via `mf.getValue('math-json')`). This walks that JSON directly into
# Giac/Xcas source text and parses it with `giac_eval`, returning a `GiacExpr`
# (or `missing` for an empty field, so the autograder reads it as unanswered).
#
# This is the lightweight PoC path — no MathJSON.jl dependency. The robust
# route (MathJSON.jl typed tree → `Giac.to_giac`) can replace `_giac_src` later
# without changing `mathfield_to_giac`'s contract.
# ---------------------------------------------------------------------------

using JSON

# MathJSON symbols → Giac identifiers/constants.
const _MJ_CONST = Dict(
    "Pi" => "pi", "ExponentialE" => "exp(1)", "ImaginaryUnit" => "i",
    "GoldenRatio" => "((1+sqrt(5))/2)", "Half" => "(1/2)",
    "True" => "true", "False" => "false",
    "PositiveInfinity" => "inf", "NegativeInfinity" => "-inf",
)

# MathJSON function heads → Giac function names (n-ary, comma-joined args).
const _MJ_FUN = Dict(
    "Sin" => "sin", "Cos" => "cos", "Tan" => "tan", "Cot" => "cot",
    "Sec" => "sec", "Csc" => "csc",
    "Arcsin" => "asin", "Arccos" => "acos", "Arctan" => "atan",
    "Sinh" => "sinh", "Cosh" => "cosh", "Tanh" => "tanh",
    "Exp" => "exp", "Ln" => "ln", "Log" => "log", "Lg" => "log10", "Lb" => "log2",
    "Abs" => "abs", "Sign" => "sign", "Floor" => "floor", "Ceil" => "ceil",
    "Gamma" => "Gamma", "Factorial" => "factorial",
)

_num_src(s::AbstractString) = replace(s, "+" => "")   # "+3.14" → "3.14"
_num_src(x) = string(x)

# Math keyboards emit Greek letters as their unicode glyph (ω, α, θ, …), but to GIAC those
# glyphs are DISTINCT symbols from its ASCII identifiers — `omega - ω` doesn't cancel — and only
# the ASCII spelling both computes together and renders back as Greek (`omega` → `\omega` → ω).
# So fold every Greek glyph onto its Xcas name right at the MathJSON→source boundary: a
# keyboard `ω` and a typed `omega` become one variable everywhere (value, algebra, display).
const _GREEK = Dict{Char,String}(
    'α'=>"alpha",  'β'=>"beta",   'γ'=>"gamma",  'δ'=>"delta",   'ε'=>"epsilon", 'ϵ'=>"epsilon",
    'ζ'=>"zeta",   'η'=>"eta",    'θ'=>"theta",  'ϑ'=>"theta",   'ι'=>"iota",    'κ'=>"kappa",
    'ϰ'=>"kappa",  'λ'=>"lambda", 'μ'=>"mu",     'µ'=>"mu", 'ν'=>"nu",      'ξ'=>"xi",
    'ο'=>"omicron",'π'=>"pi",     'ϖ'=>"pi",     'ρ'=>"rho",     'ϱ'=>"rho",     'σ'=>"sigma",
    'ς'=>"sigma",  'τ'=>"tau",    'υ'=>"upsilon",'φ'=>"phi",     'ϕ'=>"phi",     'χ'=>"chi",
    'ψ'=>"psi",    'ω'=>"omega",
    'Γ'=>"Gamma",  'Δ'=>"Delta",  'Θ'=>"Theta",  'Λ'=>"Lambda",  'Ξ'=>"Xi",      'Π'=>"Pi",
    'Σ'=>"Sigma",  'Φ'=>"Phi",    'Ψ'=>"Psi",    'Ω'=>"Omega",   'Ω'=>"Omega",
)

const _SUBDIGIT = Dict('₀'=>'0','₁'=>'1','₂'=>'2','₃'=>'3','₄'=>'4',
                       '₅'=>'5','₆'=>'6','₇'=>'7','₈'=>'8','₉'=>'9')

"""
    _canon_src(s) -> String

Fold the extended characters we understand onto GIAC's ASCII source: Greek glyphs → Xcas names
(`ω`→`omega`), and runs of unicode subscript digits → GIAC's `_n` subscript (`x₀`→`x_0`). ASCII
is left untouched. Best-effort — anything unmapped is passed through; the strict MathJSON
boundary (`_clean_symbol`) additionally rejects leftover non-ASCII. This is the single
normaliser shared by every ingress: the MathJSON bridge, the giac"…" macro, the editor's
display path, and the grader.
"""
function _canon_src(s::AbstractString)
    s2 = any(c -> haskey(_GREEK, c), s) ?
         sprint(io -> for c in s; print(io, get(_GREEK, c, c)); end) : String(s)
    occursin(r"[₀-₉]", s2) || return s2
    replace(s2, r"[₀-₉]+" => m -> "_" * map(c -> _SUBDIGIT[c], m))
end

# A single MathJSON symbol → canonical GIAC identifier. Fold what we can, then REFUSE anything
# still non-ASCII (a decorated/blackboard/script glyph GIAC has no clean symbol for) instead of
# minting a bogus symbol that silently won't match or compute.
function _clean_symbol(sym::AbstractString)
    c = _canon_src(sym)
    isascii(c) || error("unsupported symbol \"$sym\" — use a plain name (a letter, Greek, or x_1)")
    c
end

# MathJSON node → Giac source string.
function _giac_src(x)::String
    if x isa Bool
        return x ? "true" : "false"
    elseif x isa Number
        return string(x)
    elseif x isa AbstractString
        return haskey(_MJ_CONST, x) ? _MJ_CONST[x] : _clean_symbol(x)   # named constant or symbol
    elseif x isa AbstractDict
        haskey(x, "num") && return _num_src(x["num"])
        haskey(x, "sym") && return haskey(_MJ_CONST, x["sym"]) ? _MJ_CONST[x["sym"]] : _clean_symbol(x["sym"])
        haskey(x, "str") && error("string literals aren't valid math input")
        haskey(x, "fn") && return _giac_fn(x["fn"])
        error("unrecognized MathJSON node: $x")
    elseif x isa AbstractVector
        return _giac_fn(x)
    end
    error("unrecognized MathJSON value: $(typeof(x))")
end

function _giac_fn(v::AbstractVector)::String
    isempty(v) && return ""
    head = String(v[1])
    args = String[_giac_src(a) for a in @view v[2:end]]
    if head == "Add"
        return "(" * join(args, "+") * ")"
    elseif head == "Subtract"
        return "(" * args[1] * "-" * args[2] * ")"
    elseif head == "Negate"
        return "(-(" * args[1] * "))"
    elseif head == "Multiply" || head == "InvisibleOperator"
        return "(" * join(args, "*") * ")"
    elseif head == "Divide" || head == "Rational"
        return "(" * args[1] * ")/(" * args[2] * ")"
    elseif head == "Power"
        return "(" * args[1] * ")^(" * args[2] * ")"
    elseif head == "Subscript"
        # x_1, ω_n → GIAC's native subscript (one symbol, typesets as x₁). Only simple
        # index tokens make a valid identifier; anything else has no GIAC symbol.
        length(args) == 2 && occursin(r"^[A-Za-z0-9]+$", args[2]) ||
            error("only simple subscripts like x_1 are supported")
        return args[1] * "_" * args[2]
    elseif head == "Square"
        return "(" * args[1] * ")^2"
    elseif head == "Sqrt"
        return "sqrt(" * args[1] * ")"
    elseif head == "Root"
        return "(" * args[1] * ")^(1/(" * args[2] * "))"
    elseif head == "Delimiter" || head == "Sequence"
        return isempty(args) ? "" : args[1]            # unwrap grouping
    elseif head == "List"
        return "[" * join(args, ",") * "]"
    elseif head == "Equal"
        return args[1] * "=" * args[2]
    elseif haskey(_MJ_FUN, head)
        return _MJ_FUN[head] * "(" * join(args, ",") * ")"
    elseif head in _DECORATIONS
        # An accented/decorated variable (x̂, x̄, x⃗, ẋ) — GIAC has no matching symbol, so refuse
        # rather than invent a bogus `hat(x)` function that won't compute or compare.
        error("decorated symbols like $head aren't supported — use a plain name (e.g. xhat, xbar)")
    else
        # Best-effort fallback: treat the head as a lowercase Giac function.
        return lowercase(head) * "(" * join(args, ",") * ")"
    end
end

# MathJSON heads for accents/decorations on a variable — no clean GIAC symbol exists for these.
const _DECORATIONS = Set([
    "Hat", "OverHat", "Vec", "OverVec", "Bar", "OverBar", "Overline",
    "Tilde", "OverTilde", "Dot", "OverDot", "DoubleDot", "Prime", "Overscript", "Underscript",
])

"""
    mathfield_to_giac(mathjson) -> GiacExpr | missing

Convert a MathLive `<math-field>` MathJSON payload (a raw JSON string, or the
already-parsed value) into a `GiacExpr`. An empty field yields `missing`, so it
flows through the autograder as "not answered yet".
"""
# ── The `Mathfield` @bind control ─────────────────────────────────────────────
# `Mathfield()` is a typed `@bind` control via SlateExtensionsBase's `to_widget` seam: the reader
# edits a MathLive `<math-field>` and the bound variable receives their expression as MathJSON (a
# String) — convert it with `mathfield_to_giac`. Its front-end (a Preact component in
# `assets/mathfield.js`) loads LAZILY the first time a `Mathfield` is bound, via `required_assets` —
# no boot cell. The value is a plain String, so the SDK's type-driven coerce/reconcile defaults are
# exactly right (the answer is kept across a bind-cell re-run).
struct Mathfield
    label::Union{Nothing,String}
    default::String
end
"""
    Mathfield(; label = nothing, default = "")

A MathLive `<math-field>` `@bind` control binding the reader's expression as MathJSON:
`@bind ans Mathfield(label = "your answer")`, then `mathfield_to_giac(ans)`. The front-end loads
on first use (`using GiacSlate` is all the setup needed — no boot cell).
"""
Mathfield(; label = nothing, default = "") =
    Mathfield(label === nothing ? nothing : String(label), String(default))
# Reflect the struct into a Widget: kind `GiacSlate.Mathfield` (namespaced via `kind_for`), `default`
# as the bound value, and a `label` param when set (an unset `nothing` field is dropped by `auto_widget`).
SlateExtensionsBase.to_widget(m::Mathfield) = auto_widget(m)
# The component this widget's kind needs — loaded once, the first time a `Mathfield` is bound.
SlateExtensionsBase.required_assets(::Type{Mathfield}) = @pkg_asset("assets/mathfield.js")

function mathfield_to_giac(json::AbstractString)
    isempty(strip(json)) && return missing
    _mf_value(JSON.parse(json))          # parse the JSON exactly once
end
mathfield_to_giac(parsed) = _mf_value(parsed)

# Walk an already-parsed MathJSON value (never re-parses strings as JSON).
function _mf_value(x)
    (x === nothing || x == "Nothing") && return missing
    # MathLive emits ["Error", …] for empty/invalid input or an unready engine.
    (x isa AbstractVector && !isempty(x) && x[1] == "Error") && return missing
    src = strip(_giac_src(x))
    isempty(src) ? missing : Giac.giac_eval(String(src))
end
