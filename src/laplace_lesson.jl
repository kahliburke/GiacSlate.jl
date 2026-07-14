# ---------------------------------------------------------------------------
# Content + reference solutions for the Laplace-transform physics lesson.
#
# Students never see this file. Symbolic answers are graded by Giac against the
# closed forms built here as `giac_eval` strings (identifiers match the reader's
# `@giac_var`s by NAME, so no shared bindings are needed). Numeric answers are
# graded by calling the reader's function against a reference on fixed cases.
# ---------------------------------------------------------------------------

# Convenience: a reference symbolic expression from a Giac source string.
_ref(str) = Giac.giac_eval(str)

# === Section 1 — the transform itself ======================================

register!(Section(:transforms, "Section 1 · Meeting the transform",
    "You can move a signal into the s-domain and back. That round trip is the whole game.",
    [
        Exercise(:lap_exp, "1.1 · Transform of a decaying exponential",
            raw"From the definition $\mathcal{L}\{f\}=\int_0^\infty f(t)e^{-st}dt$, the integral of " *
            raw"$e^{-at}e^{-st}$ is a geometric-style decay. The pole sits at $s=-a$.",
            ans -> expect_symbolic(raw"$\mathcal{L}\{e^{-at}\}$", ans, _ref("1/(s+a)"))),

        Exercise(:lap_sin, "1.2 · Transform of a sine",
            raw"Write $\sin(\omega t)=\tfrac{1}{2i}(e^{i\omega t}-e^{-i\omega t})$ and transform each " *
            raw"exponential, or recall the standard pair. The denominator is $s^2+\omega^2$.",
            ans -> expect_symbolic(raw"$\mathcal{L}\{\sin\omega t\}$", ans, _ref("w/(s^2+w^2)"))),

        Exercise(:inv_lap, "1.3 · An inverse transform",
            raw"Which time signal has transform $\dfrac{s}{s^2+\omega^2}$? Differentiate your Section-1.2 " *
            raw"answer, or match the standard pair — no extra $1/\omega$ this time.",
            ans -> expect_symbolic(raw"$\mathcal{L}^{-1}\{s/(s^2+\omega^2)\}$", ans, _ref("cos(w*t)"))),
    ]))

# === Section 2 — first-order: decay & the RC circuit =======================

register!(Section(:firstorder, "Section 2 · First-order systems — decay",
    "Radioactive decay and an RC circuit are the same equation. Laplace turns the ODE into algebra.",
    [
        Exercise(:decay_transform, "2.1 · Transform the decay law",
            raw"Radioactive decay obeys $\dot N=-aN,\;N(0)=N_0$. Transforming gives " *
            raw"$sN(s)-N_0=-aN(s)$. Solve that algebraic equation for $N(s)$.",
            ans -> expect_symbolic(raw"$N(s)$", ans, _ref("N0/(s+a)"))),

        Exercise(:decay_solution, "2.2 · Invert to the time domain",
            raw"Take $\mathcal{L}^{-1}$ of your $N(s)=N_0/(s+a)$. It is the exponential-decay pair from 1.1, " *
            raw"scaled by $N_0$.",
            ans -> expect_symbolic(raw"$N(t)$", ans, _ref("N0*exp(-a*t)"))),

        Exercise(:half_life, "2.3 · Half-life (numeric)",
            raw"Write `half_life(a)` returning the time for $N$ to fall to $N_0/2$: solve " *
            raw"$e^{-a t}=\tfrac12$ for $t$. Answer in the same time units as $1/a$.",
            ans -> expect(raw"half-life $t_{1/2}=\ln 2/a$", ans,
                a -> log(2) / a, [(0.5,), (2.0,), (0.1,)]; atol = 1e-8)),
    ]))

# === Section 3 — second-order: the damped oscillator =======================

register!(Section(:secondorder, "Section 3 · Second-order systems — oscillation",
    "The damped harmonic oscillator is the archetype of every resonant system. Its poles tell the story.",
    [
        Exercise(:transfer_fn, "3.1 · Transfer function of the oscillator",
            raw"For $m\ddot x+b\dot x+kx=F(t)$ at rest, transforming gives $(ms^2+bs+k)X(s)=F(s)$. " *
            raw"The transfer function is $H(s)=X(s)/F(s)$.",
            ans -> expect_symbolic(raw"$H(s)$", ans, _ref("1/(m*s^2+b*s+k)"))),

        Exercise(:nat_freq, "3.2 · Natural frequency (numeric)",
            raw"Write `omega_n(k, m)` for the undamped natural frequency $\omega_n=\sqrt{k/m}$.",
            ans -> expect(raw"$\omega_n=\sqrt{k/m}$", ans,
                (k, m) -> sqrt(k / m), [(4.0, 1.0), (10.0, 2.5), (1.0, 1.0)]; atol = 1e-9)),

        Exercise(:damping_ratio, "3.3 · Damping ratio (numeric)",
            raw"Write `zeta(b, k, m)` for the damping ratio $\zeta=\dfrac{b}{2\sqrt{km}}$.",
            ans -> expect(raw"$\zeta=b/(2\sqrt{km})$", ans,
                (b, k, m) -> b / (2 * sqrt(k * m)),
                [(1.0, 4.0, 1.0), (4.0, 4.0, 1.0), (0.5, 1.0, 1.0)]; atol = 1e-9)),

        Exercise(:classify, "3.4 · Classify the response",
            raw"Write `classify(z)` returning `\"underdamped\"`, `\"critically damped\"`, or " *
            raw"`\"overdamped\"` from the damping ratio $\zeta$ (boundaries at $\zeta=1$).",
            ans -> expect("regime from ζ", ans,
                z -> z < 1 ? "underdamped" : z == 1 ? "critically damped" : "overdamped",
                [(0.3,), (1.0,), (2.5,)]; hint = "compare ζ to 1")),
    ]))
