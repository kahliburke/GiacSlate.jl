try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Giac
using GiacSlate
using Giac.Commands: expand, factor, simplify, normal, partfrac, collect,
    diff, integrate, limit, series, taylor, solve, csolve, linsolve, desolve,
    laplace, ilaplace, fourier, ifactor, isprime, nextprime, trigexpand,
    texpand, tlin, tcollect, eigenvalues, eigenvectors, charpoly, rref

# Working symbols. Anything you type into a giac"…" field is full Xcas source,
# so every one of Giac's ~1800 commands is available inside a field too.
@giac_var x; @giac_var y; @giac_var z
@giac_var t; @giac_var s; @giac_var a; @giac_var b; @giac_var k; @giac_var n

"ready — Giac (Xcas engine) + inline-math controls loaded; symbols x y z t s a b k n"

#%% code id=boot hidecode nocache
# Every giac"…" literal below is a live, click-to-edit math field. Edit the
# input and the cell re-runs — the whole tour is a playground.
GiacSlate.inline_math_boot(slate_on)

#%% md id=title title
@md"""
# A Tour of GIAC

## The whole Xcas computer-algebra engine, through live math fields
"""

#%% md id=intro
@md"""
Every boxed expression below is a **live math field** (the `giac"…"` inline
control). Click one, edit the math, press <kbd>Enter</kbd> — the cell recomputes
and the answer updates. Each `giac"…"` is ordinary Xcas source, so all ~1800
GIAC commands are one keystroke away.

This is a working map of what the engine does well — algebra, calculus, linear
algebra, number theory, transforms — and, at the end, an honest **"here be
dragons"** list of the sharp edges I hit while building it.
"""

#%% md id=s_algebra
@md"""
## 1 · Algebra

The bread and butter: expand, factor, and simplify. The field holds the **input**;
the cell's output is what GIAC makes of it. Try editing an exponent.
"""

#%% code id=alg_factor
factor(giac"x^6 - 1")

#%% code id=alg_expand
expand(giac"(x + 2*y - 1)^3")

#%% code id=alg_simplify
simplify(giac"(x^3 - x)/(x^2 - 1) + (2*x)/(x+1)")

#%% code id=alg_partfrac
partfrac(giac"(2*x + 3)/(x^2 - 3*x + 2)")

#%% md id=s_calc
@md"""
## 2 · Calculus

Derivatives, indefinite and definite integrals, limits, and series — the engine
does them symbolically and exactly.
"""

#%% code id=calc_diff
diff(giac"x^x + ln(x)*sin(x)", x)

#%% code id=calc_int
integrate(giac"1/(x^2 + x + 1)", x)

#%% code id=calc_defint hidecode
gauss = integrate(giac"exp(-x^2)", x, giac"-inf", giac"inf")
basel = giac"sum(1/k^2, k, 1, inf)"
(gauss, basel)

#%% md id=calc_defint_md
@md"""
Two classics, evaluated exactly and dropped straight into prose by double-brace
interpolation: the Gaussian integral $\int_{-\infty}^{\infty} e^{-x^2}\,dx = {{ gauss }}$
and the Basel sum $\sum_{k=1}^{\infty} \tfrac{1}{k^2} = {{ basel }}$.
"""

#%% code id=calc_series
taylor(giac"exp(sin(x))", x, 0, 6)

#%% md id=s_solve
@md"""
## 3 · Solving equations & ODEs

`solve` handles polynomial and transcendental equations (real roots); `csolve`
finds complex ones; `desolve` integrates differential equations, initial
conditions and all.
"""

#%% code id=solve_poly
solve(giac"x^3 - 6*x^2 + 11*x - 6 = 0", x)

#%% code id=solve_trig
csolve(giac"x^4 + 1 = 0", x)

#%% code id=solve_ode
# Damped oscillator released from rest at y=1:  y'' + y' + 4y = 0.
# The whole call lives in one field so the `and`-joined conditions reach
# desolve unevaluated (see the "dragons" note at the end).
giac"desolve(y''+y'+4*y=0 and y(0)=1 and y'(0)=0, y(t))"

#%% md id=s_linalg
@md"""
## 4 · Linear algebra

Matrices are just nested lists, `[[…],[…]]`, and they typeset as real matrices.
Determinant, inverse, reduced row echelon form, eigenvalues, characteristic
polynomial — all exact.
"""

#%% code id=la_inv
giac"inv([[1, 2, 0], [0, 1, 3], [2, 0, 1]])"

#%% code id=la_eig
# Eigenvalues of a symmetric matrix (exact, with multiplicity)
eigenvalues(giac"[[2, 1, 0], [1, 2, 1], [0, 1, 2]]")

#%% code id=la_charpoly
# Characteristic polynomial in λ (here written l)
charpoly(giac"[[2, 1, 0], [1, 2, 1], [0, 1, 2]]", giac"l")

#%% md id=s_numth
@md"""
## 5 · Number theory & exact arithmetic

Arbitrary-precision integers, primes, totients, the Chinese remainder theorem —
and `gcd` even works on *polynomials*.
"""

#%% code id=nt_polygcd
# The SAME gcd, on polynomials instead of integers:
giac"gcd(x^4 - 1, x^6 - 1)"

#%% code id=nt_bignum
# Exact big integers: the next prime after a quintillion (10^18):
giac"nextprime(10^18)"

#%% code id=nt_crt
# Chinese remainder theorem: the x with x≡2 (mod 3), x≡3 (mod 5), x≡2 (mod 7).
# Result [r, m] means x ≡ r (mod m).
giac"chrem([2, 3, 2], [3, 5, 7])"

#%% md id=s_transforms
@md"""
## 6 · Integral transforms

Laplace (and its inverse), Fourier, and the z-transform — the machinery behind
the [Laplace lesson](/n/laplace_lesson).
"""

#%% code id=tr_laplace
# Laplace transform of a damped oscillation:
laplace(giac"exp(-a*t)*cos(b*t)", t, s)

#%% code id=tr_fourier
# Fourier transform of a Gaussian is a Gaussian:
fourier(giac"exp(-x^2)", x, s)

#%% md id=s_trig
@md"""
## 7 · Trigonometry

GIAC pivots freely between product, sum, and exponential forms — `trigexpand`
opens multiple angles, `tlin` linearises products into sums.
"""

#%% code id=trig_expand
trigexpand(giac"cos(3*x)")

#%% code id=trig_lin
# Linearise a product of sines into a sum:
tlin(giac"sin(x)*sin(2*x)*sin(3*x)")

#%% md id=s_complex
@md"""
## 8 · Complex numbers

`i` is the imaginary unit. Split into real and imaginary parts, take moduli and
arguments, or watch Euler's identity fall out.
"""

#%% code id=cx_parts
# Real and imaginary parts of a complex quotient:
giac"re((3 + 4*i)/(1 - 2*i)) + i*im((3 + 4*i)/(1 - 2*i))"

#%% code id=cx_euler
# A root of unity, in exact rectangular form:
giac"exp(i*pi/3)"

#%% md id=s_dragons
@md"""
## 9 · 🐉 Here be dragons

The engine is enormous and mostly delightful, but building this tour turned up
real sharp edges — worth knowing before you trust a result:

- **`ifactor` renders as the original number.** `ifactor(360)` *computes*
  `2³·3²·5`, but its LaTeX prints `360` — the factorisation is lost in the math
  field (see the cell below). Use **`ifactors(360)`** → `[2,3, 3,2, 5,1]` (prime,
  exponent pairs), which survives typesetting.
- **`desolve` is picky, and fails *silently*.** Passing conditions as a list,
  `desolve([ode, y(0)=1], y)`, returns an empty `[]` rather than erroring. Join
  them with `and`: `desolve(ode and y(0)=1 and y'(0)=0, y(t))`. And keep the whole
  call inside **one** `giac"…"` field — the `command(giac"…")` form evaluates the
  `and`-conditions to `false` before `desolve` ever sees them.
- **Singular integrals are taken at face value.** `integrate(1/x, x, -1, 1)`
  returns `0`. The integrand blows up at `0`; GIAC hands back the (formal)
  principal value with no warning.
- **`mod` is a residue *class*, not a remainder.** `173 mod 12` is `5 % 12`, a
  live modular object — arithmetic stays in ℤ/12. For the plain integer `5`, use
  `irem(173, 12)`.
- **Bare symbols are assumed real.** `conj(y)` gives `y` and `im(y)` gives `0`
  until you declare `assume(y, complex)`.
- **Series carry their remainder.** `taylor`/`series` results include an
  `order_size(x)` tail marking the truncation order.

The field below *looks* unfactored — but the cell's value really is $2^3\cdot
3^2\cdot 5$. That gap between what the field shows and what the value is, is the trap:
"""

#%% code id=dragon_ifactor
# Reads as "360" in the field, but the value is the factorisation. `ifactors`
# (with the s) returns [prime, exponent, …] pairs that DO survive typesetting.
giac"ifactor(360)"

#%% code id=dragon_ifactors
giac"ifactors(360)"
