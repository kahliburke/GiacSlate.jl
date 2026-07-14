try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

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

#%% md id=mdmath_hdr
@md"""
## Giac math variables inside markdown

Define a math variable in a code cell, then reference it in **prose** — inline
and display — via `{{ gmath(…) }}` / `{{ gdisplay(…) }}`. It renders through the
giac→LaTeX conversion and re-renders when the variable changes.
"""

#%% code id=mdmath_vars
Hs = giac"1/(s^2 + 2*s + 5)"                       # a transfer function
yt = giac"ilaplace(1/(s*(s^2+2*s+5)), s, t)"       # its step response
(string(Hs), string(yt))

#%% md id=mdmath_prose
@md"""
The system has transfer function {{ gmath(Hs) }}, a second-order response. Its
unit-step response, computed by Giac's inverse Laplace transform, is

{{ gdisplay(yt) }}

which settles to {{ gmath(giac"limit(1/(s^2+2*s+5)*5, s, 0)/5") }} as $t \to \infty$.
"""

#%% md id=celled_md
@md"""
## 🎯 The real thing — `giac"…"` live in a code cell

No sandbox. The boot cell below registers an **editor extension** (via the new
`slateRegisterEditorExtension` hook) + two giac↔LaTeX bridge handlers. After a
reload, any `giac"…"` literal in a **real code cell** renders as a live math field —
and the cell still runs natively (`@giac_str`). Ctrl/Cmd-M inserts one.
"""

#%% code id=celled_boot hidecode nocache
# Bridge handlers (giac source ↔ LaTeX / MathJSON), then register the editor extension.
slate_on("giac_tex", a -> Dict("latex" => GiacSlate.giac_src_to_tex(String(a.src))))
slate_on("giac_src", a -> Dict("src"   => GiacSlate.mathjson_to_giac_src(String(a.mj))))
GiacSlate.inline_math_boot()

#%% code id=celled_demo
@bind num Slider(1:5)

#%% code id=a8e696
# After reload, the giac"…" below renders as a live math field — and this cell runs.
H = giac"(x+19)"
ex = expand(1 / H^num)
ex2 = expand((x+num)^3)
ex3=giac"((1)/((x+39)))^(3)"
expand(giac"((x+6))^(5)")

#%% md id=aaa081
@md"""

Here is some inline math ${{ ex }}$ and some display math $${{ ex }}$$

and ex2: 

{{ex2}}

ex3:
1. Bullet
2. Math ${{ ex3 }}$
"""
