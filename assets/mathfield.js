// GiacSlate `Mathfield` @bind renderer — a MathLive `<math-field>` whose value is the reader's
// expression as Compute-Engine MathJSON (a String). Authored as a Slate widget COMPONENT: it imports
// only `@slate/widget` (the shared Preact/signals instance) and is loaded lazily the first time a
// `Mathfield` is bound (via `required_assets(::Type{Mathfield})`) — no boot cell.
//
// `<math-field>` is a self-owned custom element, so instead of rendering it declaratively we mount it
// imperatively through a callback ref: Preact hands us the host node on mount, and we create + wire the
// field into it once. The initial value is read with `value.peek()` (a non-reactive read) so a server
// echo of the bound value can't clobber what the reader is typing — matching the old widget's `sync(){}`.

import { html } from "@slate/widget";

// MathLive + the CortexJS Compute Engine, imported once per page and shared across every field.
let _mathlive;
const loadMathlive = () =>
  (_mathlive ??= Promise.all([
    import("mathlive"),
    import("@cortex-js/compute-engine"),
  ]).then(([ml, ce]) => {
    if (ml.MathfieldElement) {
      ml.MathfieldElement.fontsDirectory  = "https://cdn.jsdelivr.net/npm/mathlive/dist/fonts";
      ml.MathfieldElement.soundsDirectory = null;
      if (ce.ComputeEngine) ml.MathfieldElement.computeEngine = new ce.ComputeEngine();
    }
    return ml;
  }));

export default ({ value, set }) => {
  const mount = el => {
    if (!el || el._mf) return;                              // unmount (null) or already wired
    loadMathlive().then(() => {
      if (el._mf) return;
      const mf = document.createElement("math-field");
      mf.style.cssText = "font-size:1.4rem;padding:6px 10px;min-width:260px;" +
        "border:1px solid #30363d;border-radius:8px;background:#0d1117;color:#e6edf3";
      el.appendChild(mf);
      el._mf = mf;
      // Restore the prior answer on (re-)mount without subscribing to `value` — a bind rebuild
      // preserves what the reader wrote, but a later server echo won't reset the field mid-edit.
      const init = value.peek ? value.peek() : value.value;
      if (init) { try { mf.setValue(String(init), { format: "math-json" }); } catch (e) {} }
      mf.addEventListener("input", () => {
        let mj = mf.getValue("math-json");
        if (typeof mj !== "string") mj = JSON.stringify(mj);
        if (mj.indexOf('"Error"') !== -1) return;           // engine not ready / invalid — skip
        set(mj);
      });
    });
  };
  return html`<span ref=${mount}></span>`;
};
