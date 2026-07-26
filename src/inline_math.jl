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

Extended characters typed straight into the literal (a Greek glyph `ω`, a subscript `x₀`) are
canonicalised to GIAC's ASCII source (`_canon_src`) at macro-expansion, so a directly-typed
`giac"ω"` is the same symbol as a keyboard-entered ω — see the canonicalisation note in
`mathfield.jl`.
"""
macro giac_str(s)
    isempty(strip(s)) ? :(missing) : :($(Giac.giac_eval)($(_canon_src(s))))
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
    g = Giac.giac_eval(_canon_src(String(src)))    # canonicalise so a typed ω displays as \omega
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

# ── The inline-math PACKAGE-GLOBAL front-end (editor extension + giac bridge) ─────────────────
# The inline-math editor renders `giac"…"` literals as live MathLive fields in every code cell — it
# isn't tied to any `@bind`, so it rides SlateExtensionsBase's package-global hook rather than a boot
# cell. Slate calls `__slate_frontend(slate_on)` once per drain for every loaded module that defines it
# (see `ensure_module_frontends!`), so `using GiacSlate` alone wires the whole thing up:
#   • `assets/inline_math_editor.js` self-registers via `window.slateRegisterEditorExtension`, delivered
#     through the extension manifest (process-global, deduped by id);
#   • the two JS→Julia bridge handlers — `giac_tex` (giac source → LaTeX, the display side) and
#     `giac_src` (MathLive MathJSON → giac source, the write-back side) — register into THIS notebook's
#     handler table via the injected `slate_on`.
# Slate fires this once per namespace generation (not every drain — it guards the work), and re-fires
# after a namespace rebuild to re-install the handlers into the fresh handler table.
# A per-cell toolbar button that drops a fresh inline math field into a code cell's editor — the
# clickable twin of the editor's Cmd-M (`insertGiac`, exposed as `window.slateGiacInsert`). Authored
# the blessed way, mirroring `to_widget(s) = auto_widget(s)`: a typed action whose fields ARE the wire
# spec, reflected by `auto_cell_action` (id namespaced by `kind_for` ⇒ "GiacSlate.MathfieldButton").
Base.@kwdef struct MathfieldButton
    icon::String    = "∫"
    title::String   = "insert a math field (⌘M)"
    show::String    = "cell.kind === 'code'"          # code cells only — where giac\"…\" lives
    onclick::String = "window.slateGiacInsert(cellId)"
end
SlateExtensionsBase.to_cell_action(a::MathfieldButton) = auto_cell_action(a)

function __slate_frontend(slate_on)
    # The inline-math editor extension — a classic script that self-registers via
    # `window.slateRegisterEditorExtension`; `@pkg_asset` reads it from the package's `assets/` dir.
    provide_frontend!(@pkg_asset("assets/inline_math_editor.js"); id = "GiacSlate.inline_math_editor")
    # …and its clickable counterpart in every code cell's header toolbar (host seam:
    # `window.slateRegisterCellAction`). Deduped by the action's namespaced id.
    register_cell_action!(MathfieldButton())
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
    return nothing
end
