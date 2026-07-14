try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Giac
using Giac.Commands: laplace, ilaplace, simplify, factor, partfrac, solve
using GiacSlate          # the lesson's autograder: check / grade / course_report
using Markdown

# Domains
@giac_var t              # time
@giac_var s              # complex frequency

# Symbolic parameters you'll use when writing answers
@giac_var a              # decay rate  (Sections 1–2)
@giac_var w              # angular frequency ω
@giac_var N0             # initial amount
@giac_var m; @giac_var b; @giac_var k   # mass, damping, stiffness

tex(e) = strip(sprint(show, MIME("text/latex"), e), ['$', '\n', ' '])

# Stack "lhs = rhs" rows as native display-math blocks. Each row is written
# `"lhs &= rhs"` (the `&` is dropped here) and rendered as its own `$$…$$` so it
# typesets both live (MathJax) and in the PDF/Typst export.
mathblock(rows) = Markdown.parse(
    join(("\$\$" * replace(r, "&" => "") * "\$\$" for r in rows), "\n\n"))

"Kernel ready — domains t, s; parameters a, w, N0, m, b, k; grader loaded."

#%% md id=title title
@md"""
# The Laplace Transform

## An interactive physics lesson, with graded exercises

A working introduction for students: learn the Laplace transform by using it to
solve real physics problems — decaying charge on a capacitor, a damped
oscillator, driven resonance — then check your understanding with exercises that
grade themselves. Every symbolic result below is computed live by the
[Giac](https://github.com/s-celles/Giac.jl) computer algebra system, so you can
change a number and watch the mathematics follow.
"""

#%% md id=intro_md
@md"""
### What is the Laplace transform?

The Laplace transform sends a function of time $f(t)$ to a function of a complex
variable $s$:

$$F(s) \;=\; \mathcal{L}\{f\}(s) \;=\; \int_0^{\infty} f(t)\,e^{-st}\,dt .$$

Its superpower for physics is this: **differentiation in time becomes
multiplication by $s$.** A differential equation — the language of every
mechanical, electrical, and thermal system — turns into ordinary algebra. Solve
the algebra in the $s$-domain, then transform back to get the motion $x(t)$, the
charge $q(t)$, the temperature $T(t)$.

We'll build the idea up through three physical systems: exponential decay, a
first-order RC circuit, and the damped harmonic oscillator.

> **How the exercises work.** Each exercise has a cell with `missing` in it.
> Replace `missing` with your answer — a symbolic expression (using the variables
> `s`, `t`, `a`, `w`, …) or a small function — and the **check cell just below it
> re-runs automatically** and grades you. Symbolic answers are checked by the
> Giac algebra system, so *any* algebraically-equivalent form counts. Green ✓ means
> you've got it. A running score sits at the very bottom.
"""

#%% md id=s1_md
@md"""
## Section 1 · Meeting the transform

Let's compute a couple of transforms straight from the definition so you can see
the machine turning. Giac evaluates the integral $\int_0^\infty f(t)e^{-st}dt$
for us — but the point is the *pattern*, so keep the definition in mind.
"""

#%% code id=s1_worked
# Two transforms computed live, straight from f(t):
L1  = tex(laplace(Giac.giac_eval("1"), t, s))
Lt  = tex(laplace(t, t, s))
Lt2 = tex(laplace(t^2, t, s))
Markdown.parse("""
\$\$\\mathcal{L}\\{1\\} = $L1 \\qquad \\mathcal{L}\\{t\\} = $Lt \\qquad \\mathcal{L}\\{t^{2}\\} = $Lt2\$\$
""")

#%% md id=ex1_1_md
@md"""
**Exercise 1.1 — the exponential.** A decaying exponential $e^{-at}$ (a
radioactive sample, a discharging capacitor) is the most important signal in
physics. Give its Laplace transform as an expression in `s` and `a`.
"""

#%% code id=ex1_1
# Replace `missing` with L{e^{-a t}} as an expression in s and a:
L_exp = laplace(exp(-a*t), t, s)

#%% code id=check1_1
check(:lap_exp, L_exp)

#%% md id=ex1_2_md
@md"""
**Exercise 1.2 — the oscillation.** Oscillations are the other half of physics.
Give the Laplace transform of $\sin(\omega t)$ as an expression in `s` and `w`
(use `w` for $\omega$).
"""

#%% code id=ex1_2
# Replace `missing` with L{sin(w t)} as an expression in s and w:
L_sin = missing

#%% code id=check1_2
check(:lap_sin, L_sin)

#%% md id=ex1_3_md
@md"""
**Exercise 1.3 — going back.** The transform is only useful if you can return to
the time domain. What time signal $f(t)$ has transform $\dfrac{s}{s^{2}+\omega^{2}}$?
Give $f(t)$ as an expression in `t` and `w`.
"""

#%% code id=ex1_3
# Replace `missing` with the inverse transform f(t), in terms of t and w:
f_cos = missing

#%% code id=check1_3
check(:inv_lap, f_cos)

#%% md id=s2_md
@md"""
## Section 2 · First-order systems — decay

Now the payoff. A radioactive sample loses atoms at a rate proportional to how
many remain; a capacitor bleeds charge through a resistor the same way. Both obey

$$\dot y(t) = -a\,y(t), \qquad y(0) = y_0 .$$

The key transform rule is $\mathcal{L}\{\dot y\} = sY(s) - y(0)$ — the initial
condition rides along for free. So the whole ODE becomes the algebraic equation

$$sY(s) - y_0 = -a\,Y(s).$$

**Worked example.** A hot object cools as $\dot T = -\tfrac12 T$, $T(0)=100$.
Watch Giac solve it by the Laplace method:
"""

#%% code id=s2_worked
# Solve  T' = -½T,  T(0)=100  via Laplace, step by step.
Ts   = Giac.giac_eval("100/(s + 1/2)")        # T(s), from sT(s) - 100 = -½T(s)
Tt   = ilaplace(Ts, s, t)                       # back to the time domain
mathblock([
    "sT(s) - 100 &= -\\tfrac{1}{2}T(s)",
    "T(s) &= " * tex(Ts),
    "T(t) = \\mathcal{L}^{-1}\\{T(s)\\} &= " * tex(Tt),
])

#%% md id=ex2_1_md
@md"""
**Exercise 2.1 — solve for $N(s)$.** Now do it in general. For radioactive decay
$\dot N = -aN,\; N(0)=N_0$, the transform gives $sN(s) - N_0 = -a\,N(s)$. Solve
that for $N(s)$ (an expression in `s`, `a`, and `N0`).
"""

#%% code id=ex2_1
# Solve sN(s) - N0 = -a N(s) for N(s), in terms of s, a, N0:
N_s = missing

#%% code id=check2_1
check(:decay_transform, N_s)

#%% md id=ex2_2_md
@md"""
**Exercise 2.2 — back to time.** Invert your $N(s) = N_0/(s+a)$ to get $N(t)$.
You already found this pair in Exercise 1.1 — just carry the $N_0$ along. Give
$N(t)$ as an expression in `t`, `a`, `N0`.
"""

#%% code id=ex2_2
# Invert N(s) = N0/(s+a) to N(t), in terms of t, a, N0:
N_t = missing

#%% code id=check2_2
check(:decay_solution, N_t)

#%% md id=ex2_3_md
@md"""
**Exercise 2.3 — half-life (a function).** The *half-life* is the time for $N$ to
fall to $N_0/2$. Solve $e^{-a t_{1/2}} = \tfrac12$ for $t_{1/2}$, then write it as
a Julia function of the decay rate `a`.
"""

#%% code id=ex2_3
# Return the half-life for decay rate a.  Replace `missing` with your formula.
function half_life(a)
    missing
end

#%% code id=check2_3
check(:half_life, half_life)

#%% md id=s3_md
@md"""
## Section 3 · Second-order systems — oscillation

A mass on a spring with friction — and, by analogy, an RLC circuit, a suspension,
a tuned instrument — obeys

$$m\ddot x + b\dot x + k x = F(t).$$

Transforming (at rest) gives $(ms^2 + bs + k)\,X(s) = F(s)$, so the system's
entire personality lives in its **transfer function** $H(s) = X(s)/F(s)$ and the
**poles** — the roots of $ms^2+bs+k$. Two numbers set the behaviour: the natural
frequency $\omega_n=\sqrt{k/m}$ and the damping ratio $\zeta=\dfrac{b}{2\sqrt{km}}$.

**Explore first.** Below, Giac inverts the free response $X(s)=\dfrac{s+2\zeta\omega_n}{s^2+2\zeta\omega_n s + \omega_n^2}$
(release from $x=1$ at rest) *symbolically*, and we plot it. Slide $\zeta$ through
$1$ and watch oscillation give way to a dead crawl.
"""

#%% code id=s3_explore
@bind ζv  Slider(0.1, 2.0, 0.25; step=0.05, label="damping ζ")
@bind ωnv Slider(0.5, 4.0, 2.0;  step=0.1,  label="natural freq ωₙ")

# Free response X(s) = (s + 2ζωₙ) / (s² + 2ζωₙ s + ωₙ²), inverted by Giac.
Xs = Giac.giac_eval(
    "(s + 2*$(ζv)*$(ωnv)) / (s^2 + 2*$(ζv)*$(ωnv)*s + $(ωnv)^2)")
xt = build_function(ilaplace(Xs, s, t), t)

ts = collect(range(0, 12; length=400))
xs = clamp.(xt.(ts), -1.5, 1.5)
regime = ζv < 1 ? "under-damped" : ζv ≈ 1 ? "critically damped" : "over-damped"

echart(:line, ts, xs; title="Free response x(t) — $regime  (ζ=$ζv, ωₙ=$ωnv)",
       smooth=true, symbol="none", areaStyle=(opacity=0.1,),
       xAxis=(name="t",), yAxis=(name="x", min=-1.1, max=1.2),
       markLine=(silent=true, symbol="none",
                 data=[(yAxis=0, lineStyle=(type=:dashed, color="#888"))]),
       height=380)

#%% md id=ex3_1_md
@md"""
**Exercise 3.1 — the transfer function.** From $(ms^2+bs+k)X(s)=F(s)$, write the
transfer function $H(s)=X(s)/F(s)$ as an expression in `s`, `m`, `b`, `k`.
"""

#%% code id=ex3_1
# Transfer function H(s) = X(s)/F(s), in terms of s, m, b, k:
H = missing

#%% code id=check3_1
check(:transfer_fn, H)

#%% md id=ex3_2_md
@md"""
**Exercise 3.2 — natural frequency.** Write `omega_n(k, m)` returning the
undamped natural frequency $\omega_n=\sqrt{k/m}$.
"""

#%% code id=ex3_2
function omega_n(k, m)
    missing
end

#%% code id=check3_2
check(:nat_freq, omega_n)

#%% md id=ex3_3_md
@md"""
**Exercise 3.3 — damping ratio.** Write `zeta(b, k, m)` returning the damping
ratio $\zeta=\dfrac{b}{2\sqrt{km}}$.
"""

#%% code id=ex3_3
function zeta(b, k, m)
    missing
end

#%% code id=check3_3
check(:damping_ratio, zeta)

#%% md id=ex3_4_md
@md"""
**Exercise 3.4 — name the regime.** The damping ratio decides everything. Write
`classify(z)` returning the string `"underdamped"`, `"critically damped"`, or
`"overdamped"` depending on whether $\zeta$ is below, equal to, or above $1$.
"""

#%% code id=ex3_4
function classify(z)
    missing
end

#%% code id=check3_4
check(:classify, classify)

#%% md id=progress_md
@md"""
## Your progress

This card tallies every exercise in the lesson and refreshes the moment you
change any answer above. Fill the bar to complete the course.
"""

#%% code id=progress
course_report(;
    lap_exp        = L_exp,
    lap_sin        = L_sin,
    inv_lap        = f_cos,
    decay_transform = N_s,
    decay_solution  = N_t,
    half_life       = half_life,
    transfer_fn     = H,
    nat_freq        = omega_n,
    damping_ratio   = zeta,
    classify        = classify,
)

#%% md id=mf_md
@md"""
## 🧪 Experimental — type your answer with a math keyboard

Instead of writing Julia, type the Laplace transform of $e^{-at}$ as **real
notation** in the field below (use the on-screen keyboard or type `1/(s+a)`).
The math field emits MathJSON, `GiacSlate.mathfield_to_giac` turns it into a
`GiacExpr`, and the same autograder checks it.
"""

#%% code id=mf_target
# A first-class math-keyboard bind — the `mathfield` widget kind, registered above.
@bind ans_mj custom_widget("mathfield"; label = "your answer")

#%% code id=mf_widget hidecode
# Register the `mathfield` widget with Slate (imports MathLive + Compute Engine).
# This is a plugin: it uses the `slateRegisterWidget` extension point — no core Slate
# changes per widget.
GiacSlate.mathfield_boot()

#%% code id=mf_expr
# Parse the math-field's MathJSON into a Giac expression (reactive on ans_mj).
mf_answer = GiacSlate.mathfield_to_giac(ans_mj)

#%% code id=mf_check
check(:lap_exp, mf_answer)

# ╔═╡ Slate.env · notebook packages (auto-maintained — manage via the package panel)
#   Giac 0.14.1 e4421f97-9838-4fd0-9fa5-94f11373bf78
# ╚═╡
