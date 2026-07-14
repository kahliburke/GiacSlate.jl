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

# MathJSON node → Giac source string.
function _giac_src(x)::String
    if x isa Bool
        return x ? "true" : "false"
    elseif x isa Number
        return string(x)
    elseif x isa AbstractString
        return get(_MJ_CONST, x, x)                    # symbol or named constant
    elseif x isa AbstractDict
        haskey(x, "num") && return _num_src(x["num"])
        haskey(x, "sym") && return get(_MJ_CONST, x["sym"], x["sym"])
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
    else
        # Best-effort fallback: treat the head as a lowercase Giac function.
        return lowercase(head) * "(" * join(args, ",") * ")"
    end
end

"""
    mathfield_to_giac(mathjson) -> GiacExpr | missing

Convert a MathLive `<math-field>` MathJSON payload (a raw JSON string, or the
already-parsed value) into a `GiacExpr`. An empty field yields `missing`, so it
flows through the autograder as "not answered yet".
"""
# ── Front-end registration for the "mathfield" widget kind ──────────────────
# Pairs with Julia's `custom_widget("mathfield")` bind. `mathfield_boot()` returns a
# value that renders as a one-time <script> registering the widget with Slate's
# `slateRegisterWidget` extension point: it imports MathLive + the CortexJS Compute
# Engine, then teaches Slate how to mount and wire a <math-field> whose MathJSON is
# pushed straight into the bound variable. GiacSlate defines its own displayable type
# so it needs no dependency on KaimonSlate.
struct MathfieldBoot end

const _MATHFIELD_JS = raw"""
(async () => {
  const [m, ce] = await Promise.all([
    import('https://esm.sh/mathlive@0.100.0'),
    import('https://esm.sh/@cortex-js/compute-engine@0.26.4'),
  ]);
  if (m.MathfieldElement) {
    m.MathfieldElement.fontsDirectory  = 'https://cdn.jsdelivr.net/npm/mathlive@0.100.0/dist/fonts';
    m.MathfieldElement.soundsDirectory = null;
    if (ce.ComputeEngine) m.MathfieldElement.computeEngine = new ce.ComputeEngine();
  }
  window.slateRegisterWidget('mathfield', {
    wire(el, api) {
      if (el._mf) return;                                   // already mounted
      const mf = document.createElement('math-field');
      mf.style.cssText = 'font-size:1.4rem;padding:6px 10px;min-width:260px;' +
        'border:1px solid #30363d;border-radius:8px;background:#0d1117;color:#e6edf3';
      el.appendChild(mf); el._mf = mf;
      mf.addEventListener('input', () => {
        let mj = mf.getValue('math-json');
        if (typeof mj !== 'string') mj = JSON.stringify(mj);
        if (mj.indexOf('"Error"') !== -1) return;           // engine not ready / invalid — skip
        api.push(mj);
      });
    },
    sync() {},                                              // authored in the field; ignore server echoes
  });
})();
"""

Base.show(io::IO, ::MIME"text/html", ::MathfieldBoot) =
    print(io, "<script>", _MATHFIELD_JS, "</script>")

"""
    mathfield_boot()

One-time front-end registration for the `mathfield` widget kind. Put it in a (hidecode)
cell ABOVE any `@bind ans custom_widget("mathfield")` — it imports MathLive + the CortexJS
Compute Engine and registers the widget with Slate via `slateRegisterWidget`.
"""
mathfield_boot() = MathfieldBoot()

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
