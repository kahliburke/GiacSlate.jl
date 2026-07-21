try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Giac
using Giac.Commands: factor, expand, simplify, solve, integrate, diff, limit,
                     partfrac, normal, laplace, ilaplace
using Markdown

# Symbolic variables shared across the notebook
@giac_var x
@giac_var a
@giac_var t
@giac_var s

# Rendering helpers: turn Giac expressions into typeset math.
tex(e) = strip(sprint(show, MIME("text/latex"), e), ['$', '\n', ' '])
# Stack labeled "lhs &= rhs" rows into one aligned display block.
mathblock(rows) = Markdown.parse(
    "\$\$\\begin{aligned}" * join(rows, " \\\\[6pt] ") * "\\end{aligned}\$\$")

# Taylor polynomial of `expr` about x=0 to order n (drops the O() remainder).
taylor_poly(expr, n) =
    Giac.giac_eval("convert(series($(string(expr)), x=0, $n), polynom)")

"Giac ready — variables x, a, t, s; helpers tex / mathblock / taylor_poly loaded."

#%% md id=title title
@md"""
# Symbolic Computation with Giac.jl

## A computer algebra system, live in a Slate notebook

Giac (the engine behind Xcas) gives us exact algebra, calculus, and linear
algebra. Here we drive it from Julia through
[`Giac.jl`](https://github.com/s-celles/Giac.jl) and let Slate render every
result as typeset mathematics — no floating-point roundoff anywhere below.
"""

#%% md id=algebra_md
@md"""
## 1. Algebra — exact, not approximate

Factoring, expanding, simplifying, and partial-fraction decomposition all
return closed forms, which Slate typesets directly.
"""

#%% code id=algebra_demo
mathblock([
    "x^4 - 1 &= " * tex(factor(x^4 - 1)),
    "(x+2)^4 &= " * tex(expand((x + 2)^4)),
    "\\frac{x^2+3x+2}{x+1} &= " * tex(simplify((x^2 + 3x + 2) / (x + 1))),
    "\\frac{1}{x^2-1} &= " * tex(partfrac(1 / (x^2 - 1))),
])

#%% md id=solve_md
@md"""
Equation solving returns **exact** roots — rational, irrational, and complex.
"""

#%% code id=solve_demo
# Exact roots, including irrational and complex ones
mathblock([
    "x^2 - 5x + 6 = 0 &\\;\\Rightarrow\\; x \\in " * tex(solve(x^2 - 5x + 6, x)),
    "x^2 - 2 = 0 &\\;\\Rightarrow\\; x \\in " * tex(solve(x^2 - 2, x)),
    "x^2 + 1 = 0 &\\;\\Rightarrow\\; x \\in " * tex(solve(x^2 + 1, x)),
    "x^3 - x = 0 &\\;\\Rightarrow\\; x \\in " * tex(solve(x^3 - x, x)),
])

#%% md id=calculus_md
@md"""
## 2. Calculus — derivatives, integrals, limits

The engine differentiates and integrates in closed form and evaluates limits,
including improper ones.
"""

#%% code id=calculus_demo
f = x * sin(x)
mathblock([
    "\\frac{d}{dx}\\,x\\sin x &= " * tex(diff(f, x)),
    "\\int x\\,e^{x}\\,dx &= " * tex(integrate(x * exp(x), x)),
    "\\int_{0}^{\\pi}\\sin x\\,dx &= " * tex(integrate(sin(x), x, 0, Giac.giac_eval("pi"))),
    "\\lim_{x\\to 0}\\frac{\\sin x}{x} &= " * tex(limit(sin(x) / x, x, 0)),
    "\\lim_{x\\to\\infty}\\left(1+\\tfrac{1}{x}\\right)^{x} &= " * tex(limit((1 + 1/x)^x, x, Inf)),
])

#%% md id=taylor_md
@md"""
## 3. Interactive: Taylor series, live

Pick a function and a truncation order. Giac computes the Taylor polynomial about
$x = 0$ **symbolically**; we compile it to a Julia function with `build_function`
and plot it against the exact curve. Push the order up and watch the polynomial
hug the true function — then notice how $\arctan x$ still diverges past its
radius of convergence $|x| = 1$, no matter how many terms you add.
"""

#%% code id=taylor_explorer
@bind fkey Select(["sin(x)" => "sin x", "cos(x)" => "cos x",
                   "exp(x)" => "exp x", "atan(x)" => "arctan x"];
                  label="f(x)")
@bind ord Slider(1:2:15; default=5, label="order n")

fexpr  = Giac.giac_eval(fkey.value)
poly   = taylor_poly(fexpr, ord)
approx = build_function(poly, x)
truef  = build_function(fexpr, x)

xs   = collect(range(-3, 3; length=241))
ytru = truef.(xs)
yapp = approx.(xs)

# keep the view framed on the true curve even when the series runs off
ymax = maximum(abs, ytru) * 1.6
yapp = clamp.(yapp, -ymax, ymax)

echart(series(:line, xs, ytru; name="f(x) = $(fkey.value)", smooth=true, symbol="none"),
       series(:line, xs, yapp; name="Taylor, order $ord", smooth=true, symbol="none",
              lineStyle=(type=:dashed, width=2));
       legend=true, title="Taylor approximation about x = 0",
       yAxis=(min=round(-ymax; digits=2), max=round(ymax; digits=2)),
       height=420)

#%% code id=taylor_symbolic
mathblock(["f(x) = $(fkey.value) &\\approx " * tex(poly)])

#%% md id=laplace_md
@md"""
## 4. Laplace transforms

Giac transforms between the time domain $t$ and the complex frequency domain
$s$ exactly. `laplace` carries $f(t)$ to $F(s)$; `ilaplace` inverts it. This is
the workhorse of linear-systems and control theory — and a round trip should
return where it started.
"""

#%% code id=laplace_forward
# Forward transforms:  f(t)  ⟶  F(s) = ∫₀^∞ f(t) e^{-st} dt
mathblock([
    "\\mathcal{L}\\{1\\} &= " * tex(laplace(Giac.giac_eval("1"), t, s)),
    "\\mathcal{L}\\{t^{2}\\} &= " * tex(laplace(t^2, t, s)),
    "\\mathcal{L}\\{e^{-2t}\\sin 3t\\} &= " * tex(laplace(exp(-2t) * sin(3t), t, s)),
    "\\mathcal{L}\\{t\\,e^{-t}\\} &= " * tex(laplace(t * exp(-t), t, s)),
])

#%% code id=laplace_inverse
# Inverse transforms:  F(s)  ⟶  f(t).  A partial-fraction split makes the
# underlying second-order system's response transparent.
F = (s + 3) / (s^2 + 2s + 5)
mathblock([
    "F(s) &= " * tex(F),
    "\\mathcal{L}^{-1}\\!\\left\\{\\tfrac{1}{s^{2}+4}\\right\\} &= " *
        tex(ilaplace(1 / (s^2 + 4), s, t)),
    "\\mathcal{L}^{-1}\\{F(s)\\} &= " * tex(ilaplace(F, s, t)),
])

#%% code id=laplace_roundtrip
# Round trip: transform, invert, and simplify back to the original signal.
g       = exp(-t) * cos(2t)
G       = laplace(g, t, s)
back    = simplify(ilaplace(G, s, t))
mathblock([
    "g(t) &= " * tex(g),
    "\\mathcal{L}\\{g\\} = G(s) &= " * tex(G),
    "\\mathcal{L}^{-1}\\{G\\} &= " * tex(back),
])

#%% md id=system_md
@md"""
## 5. A second-order system, end to end

The canonical control-theory system

$$H(s) = \frac{\omega_n^{2}}{s^{2} + 2\zeta\omega_n s + \omega_n^{2}}$$

has behaviour governed entirely by its **damping ratio** $\zeta$ and **natural
frequency** $\omega_n$. Giac inverts $H(s)/s$ *symbolically* to get the exact
step response $y(t)$ — no numerical ODE solver. Drag the sliders: the closed
form, the pole locations in the complex $s$-plane, and the time response all
update together. Watch the poles split into a complex-conjugate pair as $\zeta$
drops below $1$ and the response begins to ring.
"""

#%% code id=system_controls
@bind ζ  Slider(0.1, 2.0, 0.3; step=0.05, label="damping ζ")
@bind ωn Slider(0.5, 4.0, 2.0; step=0.1, label="natural freq ωₙ")

# Giac inverts the step response Y(s) = H(s)/s to y(t), exactly.
ystep = Giac.giac_eval(
    "ilaplace($(ωn)^2/(s*(s^2+2*$(ζ)*$(ωn)*s+$(ωn)^2)), s, t)")
yfun  = build_function(ystep, t)

# Poles = roots of s² + 2ζωₙs + ωₙ²
disc  = complex(ζ^2 - 1)
poles = [-ζ*ωn + ωn*sqrt(disc), -ζ*ωn - ωn*sqrt(disc)]
regime = ζ < 1 ? "under-damped (ringing)" : ζ ≈ 1 ? "critically damped" : "over-damped"

mathblock(["y(t) &= " * tex(Giac.Commands.simplify(ystep))])

#%% code id=system_poles
# Pole map in the complex s-plane. Poles in the left half-plane ⇒ stable;
# imaginary part ⇒ oscillation.
R  = ωn * 1.3
px = real.(poles); py = imag.(poles)

echart(series(:scatter, px, py; name="poles", symbol="path://M0,-1 L0,1 M-1,0 L1,0",
              symbolSize=18, itemStyle=(color="#f56c6c",));
       title="Poles in the s-plane — $regime",
       xAxis=(name="Re(s)", min=-R, max=R, axisLine=(onZero=true,)),
       yAxis=(name="Im(s)", min=-R, max=R, axisLine=(onZero=true,)),
       grid=(left=60, right=30, top=50, bottom=50),
       tooltip=(formatter="Re {@[0]}, Im {@[1]}",),
       height=360)

#%% code id=system_step
# Exact step response y(t), sampled from Giac's symbolic solution.
tmax = clamp(8 / (ζ * ωn), 4, 40)
ts   = collect(range(0, tmax; length=400))
ys   = yfun.(ts)

echart(:line, ts, ys; title="Step response y(t)  —  ζ = $ζ, ωₙ = $ωn",
       smooth=true, symbol="none", areaStyle=(opacity=0.12,),
       xAxis=(name="t",), yAxis=(name="y",),
       markLine=(silent=true, symbol="none",
                 data=[(yAxis=1, lineStyle=(type=:dashed, color="#888"))]),
       height=360)

#%% md id=linalg_md
@md"""
## 6. Symbolic linear algebra

Matrices with symbolic entries carry through determinants, inverses, and
eigenvalues as exact expressions in the parameter $a$.
"""

#%% code id=linalg_demo
M   = GiacMatrix(Giac.giac_eval("[[a,1],[1,a]]"))
det = Giac.invoke_cmd(:det, M)
inv = Giac.invoke_cmd(:inverse, M)
eig = Giac.invoke_cmd(:eigenvalues, M)
mathblock([
    "A &= " * tex(M),
    "\\det A &= " * tex(det),
    "A^{-1} &= " * tex(inv),
    "\\operatorname{eig}(A) &= " * tex(eig),
])

#%% code id=55ed4b
# Giac symbolic output embedded inline in markdown prose.
# `tex(e)` renders any Giac expression to a LaTeX string; drop it into a
# Markdown.parse string and it typesets alongside ordinary text.
let
    fac  = factor(x^4 - 1)
    dsol = solve(x^2 - 5x + 6, x)
    ig   = integrate(x * exp(x), x)

    Markdown.parse("""
    We can weave Giac's **symbolic output** straight into markdown prose.

    - The quartic factors as \$x^4 - 1 = $(tex(fac))\$.
    - Solving \$x^2 - 5x + 6 = 0\$ gives \$x \\in $(tex(dsol))\$.
    - And \$\\displaystyle\\int x\\,e^{x}\\,dx = $(tex(ig)) + C\$.

    The same aligned `mathblock` also renders as markdown:

    \$\$\\begin{aligned}
    x^4 - 1 &= $(tex(fac)) \\\\[6pt]
    \\int x\\,e^{x}\\,dx &= $(tex(ig)) + C
    \\end{aligned}\$\$
    """)
end

#%% code id=a7acdb
begin
    h = 10
    y = 2
end

# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Giac 0.14.1 e4421f97-9838-4fd0-9fa5-94f11373bf78
# ╚═╡
# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 79775588-7259-4986-bd79-49c25256ea0e
# ╚═╡
