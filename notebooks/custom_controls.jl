try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro
@md"""
# New Notebook
"""

#%% md id=title title
@md"""
# Custom Controls Playground

## Experimenting with Slate widget plugins + the math keyboard

A scratchpad for the `slateRegisterWidget` extension point: the MathLive math
field, and whether GIAC commands can run *inside* it.
"""

#%% code id=setup hidecode
using Giac
using Giac.Commands: expand, factor, simplify, diff, integrate, limit, solve, partfrac
using GiacSlate
using Markdown

@giac_var x
@giac_var y
@giac_var s
@giac_var a

tex(e) = strip(sprint(show, MIME("text/latex"), e), ['$', '\n', ' '])
"ready — Giac, GiacSlate, commands loaded; variables x, y, s, a"

#%% code id=boot hidecode
GiacSlate.mathfield_boot()

#%% md id=calc_md
@md"""
## GIAC calculator — expression × operation

MathLive is a *math-notation* editor, not a code editor: typing a command like
`factor(...)` gets tokenized as multiplication (`f·a·c·t·o·r`). So instead: type
the **expression** in the field (use the palette for fractions, powers, ∫), pick a
**GIAC operation**, and it runs live.
"""

#%% code id=calc_input
@bind calc_mj custom_widget("mathfield"; label = "calc")

#%% code id=calc_op
@bind op Select(["eval" => "evaluate", "factor" => "factor", "expand" => "expand",
                 "simplify" => "simplify", "diff" => "d/dx", "integrate" => "∫ dx",
                 "partfrac" => "partial fractions"]; label = "operation")

#%% code id=calc_out
operand = GiacSlate.mathfield_to_giac(calc_mj)
out = if operand === missing
    Markdown.parse("*type an expression above*")
else
    r = try
        o = string(op)
        if o == "eval";        Giac.Commands.simplify(operand)
        elseif o == "diff";      Giac.invoke_cmd(:diff, operand, x)
        elseif o == "integrate"; Giac.invoke_cmd(:integrate, operand, x)
        else                     Giac.invoke_cmd(Symbol(o), operand)
        end
    catch e
        sprint(showerror, e)
    end
    Markdown.parse("\$\$$(op.label)\\left($(tex(operand))\\right) = $(r isa AbstractString ? r : tex(r))\$\$")
end

#%% md id=cmd_md
@md"""
## Type GIAC commands directly

Commands are *code*, not notation — so give them a code input, not the math
editor. Type any GIAC command and press **Enter**; `giac_eval` executes it and the
result is typeset. Try `factor(x^4-1)`, `diff(x*sin(x),x)`, `integrate(1/x,x)`,
`limit(sin(x)/x,x,0)`, `solve(x^2-5*x+6,x)`, `series(exp(x),x=0,5)`.
"""

#%% code id=cmd_boot hidecode
# Register a "giaccmd" widget: a monospace command line that pushes its value on Enter.
# (Inline registration, exactly how a plugin package would ship it.)
WebPage(js = raw"""
  window.slateRegisterWidget('giaccmd', {
    wire(el, api) {
      if (el._inp) return;
      const inp = document.createElement('input');
      inp.type = 'text';
      inp.placeholder = (api.params && api.params.placeholder) || 'GIAC command — Enter to run';
      inp.spellcheck = false; inp.autocapitalize = 'off'; inp.autocomplete = 'off';
      inp.style.cssText = 'font-family:ui-monospace,SFMono-Regular,Menlo,monospace;' +
        'font-size:1rem;padding:7px 11px;min-width:340px;border:1px solid #30363d;' +
        'border-radius:8px;background:#0d1117;color:#e6edf3;outline:none';
      inp.addEventListener('focus', () => inp.style.borderColor = '#58a6ff');
      inp.addEventListener('blur',  () => inp.style.borderColor = '#30363d');
      el.appendChild(inp); el._inp = inp;
      inp.addEventListener('keydown', e => {
        if (e.key === 'Enter') { e.preventDefault(); api.push(inp.value); }
      });
    },
    sync(el, v) { if (el._inp && document.activeElement !== el._inp) el._inp.value = (v == null ? '' : String(v)); }
  });
""")

#%% code id=cmd_input
@bind cmd custom_widget("giaccmd"; label = "giac>", placeholder = "factor(x^4-1)")

#%% code id=cmd_out
cmd_result = if isempty(strip(cmd))
    Markdown.parse("*type a command and press Enter*")
else
    r = try tex(Giac.giac_eval(String(cmd))) catch e; nothing end
    r === nothing ?
        Markdown.parse("⚠️ `$cmd` — not a valid GIAC command") :
        Markdown.parse("\$\$\\texttt{$(replace(cmd, "\\" => "\\backslash "))} \\;\\Rightarrow\\; $r\$\$")
end

#%% md id=mathcode_md
@md"""
## 🧪 Sandbox: live math *inline* in a code editor

Our own isolated CodeMirror 6 editor (esm.sh — not Slate's cell editor, no core
changes). The `math"…"` literals render as **live, always-editable math fields
right in the code**. Edit a field and watch the backing source update below.
Press **Ctrl/Cmd-M** to drop a fresh math field at the cursor.
"""

#%% code id=mathcode_eval_handler hidecode
# Bridge: the sandbox editor's "Run" button calls this. It evaluates the Julia code
# (with each math"…" already substituted for a GiacExpr) in this notebook's module and
# returns the result as LaTeX (for a GiacExpr) or text.
let mod = @__MODULE__
    slate_on("mathcode_eval", args -> begin
        try
            v = include_string(mod, String(args.code))
            v isa GiacExpr ? Dict("ok" => true, "latex" => tex(v)) :
                             Dict("ok" => true, "text" => string(v))
        catch e
            Dict("ok" => false, "error" => sprint(showerror, e))
        end
    end)
end
"mathcode_eval handler registered"

#%% code id=mathcode_mount
WebPage(
  html = """
    <div id="mathcode-host"></div>
    <div style="margin-top:10px;display:flex;gap:12px;align-items:center;flex-wrap:wrap">
      <button id="mathcode-run" style="font:13px/1 inherit;padding:6px 14px;cursor:pointer;
        color:#fff;background:var(--accent,#6cb6ff);border:none;border-radius:7px">Run ▶</button>
      <math-field id="mathcode-result" read-only style="display:none"></math-field>
      <span id="mathcode-err" style="font:12px monospace"></span>
    </div>
    <div style="margin-top:10px;color:var(--text,#d7dae1);opacity:.5;font:12px monospace">backing source:</div>
    <pre id="mathcode-doc" style="margin:2px 0;color:var(--text,#d7dae1);opacity:.6;font:12px monospace;white-space:pre-wrap"></pre>
  """,
  js = @asset("assets/mathcode.js"),
)
