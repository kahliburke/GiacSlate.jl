// GiacSlate inline-math editor extension.
//
// Registered via `slateRegisterEditorExtension`, this renders `giac"…"` literals in
// REAL Slate code cells as live MathLive fields — no sandbox, no per-cell scaffolding.
// Backing is GIAC source (the cell runs natively); display goes through giac→LaTeX and
// edits through MathLive→MathJSON→giac source, both via the notebook's `slate_on` bridge
// (registered by the boot cell): `giac_tex` (src→LaTeX) and `giac_src` (mathjson→src).
//
// Built against window.CM6 (the bundle) — needs the WidgetType export.
(async () => {
  const CM = window.CM6;
  if (!CM || !CM.WidgetType) { console.error('giac inline math: CM6.WidgetType missing'); return; }
  const { EditorView, Decoration, WidgetType, ViewPlugin, keymap } = CM;

  // MathLive + Compute Engine (once).
  const [ml, ce] = await Promise.all([
    import('https://esm.sh/mathlive@0.100.0'),
    import('https://esm.sh/@cortex-js/compute-engine@0.26.4'),
  ]);
  if (ml.MathfieldElement) {
    ml.MathfieldElement.fontsDirectory  = 'https://cdn.jsdelivr.net/npm/mathlive@0.100.0/dist/fonts';
    ml.MathfieldElement.soundsDirectory = null;
    if (ce.ComputeEngine) ml.MathfieldElement.computeEngine = new ce.ComputeEngine();
  }

  // Add a "matrices / templates" tab to the virtual keyboard (a GLOBAL palette setting, so
  // it shows for every math field). Templates insert with #? placeholders you tab through;
  // the row/column keys use MathLive's matrix-editing commands (they act inside a matrix).
  try {
    window.mathVirtualKeyboard.layouts = ['numeric', 'symbols', 'alphabetic', 'greek', {
      label: '⎡ ⎤',
      tooltip: 'matrices & templates',
      rows: [[
        { label: '[2×2]', latex: '\\begin{pmatrix}#?&#?\\\\#?&#?\\end{pmatrix}', width: 2 },
        { label: '[3×3]', latex: '\\begin{pmatrix}#?&#?&#?\\\\#?&#?&#?\\\\#?&#?&#?\\end{pmatrix}', width: 2 },
        { label: 'col', latex: '\\begin{pmatrix}#?\\\\#?\\end{pmatrix}', width: 1.5 },
        { label: 'cases', latex: '\\begin{cases}#? & #?\\\\#? & #?\\end{cases}', width: 2 },
      ], [
        { label: '+row', command: 'addRowAfter', width: 1.5 },
        { label: '+col', command: 'addColumnAfter', width: 1.5 },
        { label: '−row', command: 'removeRow', width: 1.5 },
        { label: '−col', command: 'removeColumn', width: 1.5 },
      ]],
    }];
  } catch (e) {}

  // Palette policy: `_giacKbdWanted` is the SESSION PREFERENCE (do you want the palette
  // while editing math) — set only by your explicit toggle clicks. `setKbd` shows/hides it
  // programmatically WITHOUT touching that preference (guarded by `_giacProg`), so
  // closing it when you exit to code doesn't forget that you'd turned it on.
  const setKbd = show => {
    try {
      window._giacProg = true;
      show ? window.mathVirtualKeyboard.show() : window.mathVirtualKeyboard.hide();
    } catch (e) {} finally { setTimeout(() => { window._giacProg = false; }, 0); }
  };
  const isGiacField = el => !!(el && el.closest && el.closest('.giacchip'));
  if (!window._giacKbdListener) {
    try {
      window.mathVirtualKeyboard.addEventListener('virtual-keyboard-toggle', () => {
        if (!window._giacProg) window._giacKbdWanted = !!window.mathVirtualKeyboard.visible;   // your click
      });
      window._giacKbdListener = true;
    } catch (e) {}
  }

  {
    let st = document.getElementById('giac-inline-style');
    if (!st) { st = document.createElement('style'); st.id = 'giac-inline-style'; document.head.appendChild(st); }
    st.textContent = `
      .giacchip { display:inline-block; vertical-align:middle; margin:0 1px; padding:0 4px;
        border:1px solid var(--border,#33373f); border-radius:6px;
        background:color-mix(in srgb, var(--accent,#6cb6ff) 8%, transparent); }
      /* single clean focus ring on the chip; MathLive's own inner outline is suppressed
         below so the two don't nest/overlap */
      .giacchip:focus-within { border-color:transparent;
        box-shadow:0 0 0 2px color-mix(in srgb, var(--accent,#6cb6ff) 55%, transparent); }
      .giacchip math-field { font-size:1em; color:var(--text,#d7dae1); background:transparent;
        border:none; outline:none; min-width:22px;
        --caret-color:var(--accent,#6cb6ff); --primary-color:var(--accent,#6cb6ff);
        --text-color:var(--text,#d7dae1); --selection-color:var(--text,#d7dae1);
        --selection-background-color:color-mix(in srgb, var(--accent,#6cb6ff) 32%, transparent);
        --contains-highlight-background-color:color-mix(in srgb, var(--accent,#6cb6ff) 16%, transparent);
        --placeholder-color:color-mix(in srgb, var(--text,#d7dae1) 45%, transparent); }
      .giacchip math-field::part(menu-toggle),
      .giacchip math-field::part(virtual-keyboard-toggle) { display:none; }
      /* only the ⌨ palette toggle appears (while editing); the ≡ menu stays off the
         field — it's on right-click / long-press. */
      .giacchip math-field:focus-within::part(virtual-keyboard-toggle) { display:flex; }`;
  }

  const OPEN = 'giac"', CLOSE = '"';
  const rx = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const RE   = new RegExp(rx(OPEN) + '([^"]*)' + rx(CLOSE), 'g');       // scan
  const HEAD = new RegExp('^' + rx(OPEN) + '([^"]*)' + rx(CLOSE), 'd'); // at a start, capture indices
  const emptyLit = () => OPEN + CLOSE;
  let _focusOn = -1;   // doc position of a just-inserted literal → its widget focuses on mount

  // ── bridge to Julia (slate_on handlers the boot cell registers) ──
  const texCache = new Map();                     // giac source → LaTeX (display)
  const giacTex = async src => {
    if (texCache.has(src)) return texCache.get(src);
    let latex = '';
    try { const r = await window.slateCall('giac_tex', { src }); latex = (r && r.latex) || ''; } catch (e) {}
    texCache.set(src, latex); return latex;
  };
  const giacSrc = async mj => {                    // MathJSON → giac source (write-back)
    try { const r = await window.slateCall('giac_src', { mj }); return (r && r.src) || ''; } catch (e) { return ''; }
  };

  // A live math field standing in for one giac"…" literal. `src` is the GIAC source.
  class GiacWidget extends WidgetType {
    constructor(src, from) { super(); this.src = src; this.from = from; }
    eq(o) { return o.src === this.src && o.from === this.from; }
    ignoreEvent() { return true; }
    toDOM(cmView) {
      const wrap = document.createElement('span');
      wrap.className = 'giacchip';
      const mf = document.createElement('math-field');
      mf.setAttribute('math-virtual-keyboard-policy', 'manual');
      giacTex(this.src).then(latex => { mf.value = latex; });   // async: giac source → LaTeX

      // current inner-source range, read LIVE from the DOM position (never stale offsets)
      const liveRange = () => {
        if (!mf.isConnected) return null;
        let start; try { start = cmView.posAtDOM(wrap); } catch (e) { return null; }
        const rest = cmView.state.doc.sliceString(start, Math.min(start + 8192, cmView.state.doc.length));
        const m = HEAD.exec(rest);
        if (!m) return null;
        const [is, ie] = m.indices[1];
        return { innerFrom: start + is, innerTo: start + ie };
      };
      let exiting = false;
      // MathLive → MathJSON → giac source, written back to the literal (deferred + async).
      const sync = dir => {
        if (!dir && !mf.isConnected) return;
        let mj = mf.getValue('math-json'); if (typeof mj !== 'string') mj = JSON.stringify(mj);
        if (mj.indexOf('"Error"') !== -1) return;
        giacSrc(mj).then(src => {
          requestAnimationFrame(() => {
            const r = liveRange(); if (!r) return;
            const tr = { changes: { from: r.innerFrom, to: r.innerTo, insert: src } };
            if (dir) {
              const end = r.innerFrom + src.length + CLOSE.length;
              tr.selection = { anchor: dir === 'backward' ? r.innerFrom - OPEN.length : end };
            }
            try { cmView.dispatch(tr); if (dir) cmView.focus(); } catch (e) {}
          });
        });
      };
      const exit = dir => { exiting = true; sync(dir || 'forward'); };
      mf.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === 'Escape' || e.key === 'Tab') {
          e.preventDefault(); e.stopPropagation(); exit(e.shiftKey ? 'backward' : 'forward');
        }
      }, true);
      mf.addEventListener('move-out', e => {
        const d = e.detail && e.detail.direction;
        exit(d === 'backward' || d === 'upward' ? 'backward' : 'forward');
      });
      // Bring the palette back when a field is focused (if you'd left it on); close it once
      // focus leaves the math widgets entirely (back to the code).
      mf.addEventListener('focusin', () => { if (window._giacKbdWanted) setKbd(true); });
      mf.addEventListener('focusout', () => {
        if (exiting) { exiting = false; } else { sync(); }
        setTimeout(() => { if (!isGiacField(document.activeElement)) setKbd(false); }, 0);
      });
      wrap.appendChild(mf);
      // The literal Cmd-M just inserted focuses itself once it's in the DOM.
      if (this.from === _focusOn) { _focusOn = -1; requestAnimationFrame(() => mf.focus()); }
      return wrap;
    }
  }

  const buildDecos = v => {
    const b = [];
    for (const { from, to } of v.visibleRanges) {
      const text = v.state.doc.sliceString(from, to);
      let m; RE.lastIndex = 0;
      while ((m = RE.exec(text))) {
        const s = from + m.index, e = s + m[0].length;
        b.push(Decoration.replace({ widget: new GiacWidget(m[1], s) }).range(s, e));
      }
    }
    return Decoration.set(b, true);
  };
  const plugin = ViewPlugin.fromClass(class {
    constructor(v) { this.decorations = buildDecos(v); }
    update(u) { if (u.docChanged || u.viewportChanged) this.decorations = buildDecos(u.view); }
  }, { decorations: v => v.decorations });

  const atomic = EditorView.atomicRanges.of(v => (v.plugin(plugin) && v.plugin(plugin).decorations) || Decoration.none);

  const rangeAt = (v, side, pos) => {
    const d = v.plugin(plugin) && v.plugin(plugin).decorations; if (!d) return null;
    let f = null; d.between(0, v.state.doc.length, (from, to) => { if ((side === 'end' ? to : from) === pos) { f = { from, to }; return false; } });
    return f;
  };
  const delGiac = side => v => {
    const sel = v.state.selection.main; if (!sel.empty) return false;
    const r = rangeAt(v, side, sel.head); if (!r) return false;
    v.dispatch({ changes: { from: r.from, to: r.to }, selection: { anchor: r.from } });
    return true;
  };
  // Cmd-M: wrap the SELECTION as giac"…" (giac interprets it → fractions etc.), or drop
  // an empty field at the cursor. Focus the freshly-created field.
  const insertGiac = v => {
    const sel = v.state.selection.main;
    const inner = sel.empty ? '' : v.state.sliceDoc(sel.from, sel.to);
    _focusOn = sel.from;                              // the new widget at sel.from will focus itself
    v.dispatch({ changes: { from: sel.from, to: sel.to, insert: OPEN + inner + CLOSE },
                 selection: { anchor: sel.from + OPEN.length + inner.length } });
    return true;
  };

  // Find the math-field at a doc position (a literal's start).
  const fieldAt = (v, from) => {
    for (const w of v.dom.querySelectorAll('.giacchip')) {
      try { if (v.posAtDOM(w) === from) return w.querySelector('math-field'); } catch (e) {}
    }
    return null;
  };
  // Arrow INTO a field at its boundary — Right where a literal starts at the caret enters at
  // its start; Left where one ends at the caret enters at its end. Pairs with move-out for a
  // continuous caret path through code and math. Returns false elsewhere (normal arrow motion).
  const enterGiac = dir => v => {
    const sel = v.state.selection.main; if (!sel.empty) return false;
    const r = rangeAt(v, dir === 'right' ? 'start' : 'end', sel.head);
    if (!r) return false;
    const mf = fieldAt(v, r.from); if (!mf) return false;
    mf.focus();
    requestAnimationFrame(() => { try { mf.executeCommand(dir === 'right' ? 'moveToMathfieldStart' : 'moveToMathfieldEnd'); } catch (e) {} });
    return true;
  };

  const km = keymap.of([
    { key: 'Mod-m', run: insertGiac },
    { key: 'Backspace', run: delGiac('end') },
    { key: 'Delete', run: delGiac('start') },
    { key: 'ArrowRight', run: enterGiac('right') },
    { key: 'ArrowLeft', run: enterGiac('left') },
  ]);

  // Only code cells (markdown editors have no giac"…"). Re-registerable: drop any prior
  // giac extension first, so re-running the boot cell after an edit swaps it cleanly and
  // the registry reconfigures open editors — no page reload needed to iterate.
  window._slateEditorExts = [];   // giac is the only editor extension here; drop stale re-run copies
  const extFn = ctx => ctx.markdown ? [] : [plugin, atomic, km];
  extFn._giacInline = true;
  window.slateRegisterEditorExtension(extFn);
})();
