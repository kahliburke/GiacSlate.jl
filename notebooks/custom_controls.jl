try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=title title
@md"""
# Custom Controls Playground

## Experimenting with Slate widget plugins + the math keyboard

A scratchpad for the `slateRegisterWidget` extension point: the MathLive math
field, and whether GIAC commands can run *inside* it.
"""

#%% code id=setup
using Giac
using Giac.Commands: expand, factor, simplify, diff, integrate, limit, solve, partfrac
using GiacSlate
using Markdown

@giac_var x
@giac_var y
@giac_var s
@giac_var a

"ready — Giac, GiacSlate, commands loaded; variables x, y, s, a"

#%% md id=mdmath_hdr
@md"""
## Giac math variables inside markdown

A math variable defined in a code cell can be dropped into **prose** and typeset —
`gmath(x)` renders it inline, `gdisplay(x)` as a display block. Put the call inside
Slate's double-curly-brace interpolation; it runs through the giac→LaTeX conversion
and re-renders when the variable changes. The sentence below is a live example.
"""

#%% code id=mdmath_vars
Hs = giac"1/(s^2 + 2*s + 5)"                       # a transfer function
yt = giac"((-(((1)/(10)*sin((2*t))*(exp(1))^((-(t))))))+(-(((1)/(5)*cos((2*t))*(exp(1))^((-(t))))))+(1)/(5))"       # its step response
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
# One-liner: registers the giac↔LaTeX bridge handlers + the editor extension.
GiacSlate.inline_math_boot(slate_on)

#%% code id=celled_demo
@bind num Slider(1:5)

#%% code id=a8e696
# After reload, the giac"…" below renders as a live math field — and this cell runs.
H = giac"(x+19)"
ex = expand(1 / H^num)
ex2 = expand((x+num)^3)
ex3=giac"(5+111)" + factor(giac"((x)^(4)+-1)") - Giac.det(giac"matrix([[1,2,4],[5,6,1],[4,6,1]])")

expand(giac"((x+6))^(5)")

@show ex3

#%% code id=19094f
search_commands_by_description("matrix", n=10)

#%% md id=aaa081
@md"""

Here is some inline math ${{ ex }}$ and some display math $${{ ex }}$$

and ex2: 

{{ex2}}

ex3:
1. Bullet
2. Math ${{ ex3 }}$
"""
