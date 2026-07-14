// Sandbox prototype: an isolated CodeMirror 6 editor (our own, NOT Slate's cell
// editor) where a live MathLive <math-field> sits INLINE in the code. The document
// text is Julia with `math"…latex…"` literals; a replace-decoration swaps each such
// literal for a live, always-editable math field. Editing the field writes the new
// LaTeX straight back into the document. Ctrl-M inserts a fresh inline field.
//
// Milestone 1: prove the inline-live-math mechanic + round-trip to backing text.
// (Evaluating `math"…"` as a GiacExpr in Julia is a later milestone.)
(async () => {
  const host = document.getElementById('mathcode-host');
  const dbg  = document.getElementById('mathcode-doc');
  if (!host || host._mounted) return;
  host._mounted = true;

  if (!document.getElementById('mathcode-style')) {
    const st = document.createElement('style');
    st.id = 'mathcode-style';
    st.textContent = `
      /* Colours come from Slate's own theme tokens (--bg/--text/--accent/--border),
         so the sandbox follows whatever Slate theme is active — light or dark — with
         no JS. color-mix derives the few shades Slate doesn't expose directly. */
      .mathchip { display:inline-block; vertical-align:middle; margin:0 1px; padding:0 5px;
        border:1px solid var(--border,#33373f); border-radius:6px;
        background:color-mix(in srgb, var(--accent,#6cb6ff) 8%, var(--bg,#15171c));
        transition:border-color .1s, box-shadow .1s; }
      .mathchip:focus-within { border-color:var(--accent,#6cb6ff);
        box-shadow:0 0 0 2px color-mix(in srgb, var(--accent,#6cb6ff) 30%, transparent); }
      .mathchip math-field { font-size:1rem; color:var(--text,#d7dae1); background:transparent;
        border:none; min-width:24px;
        /* MathLive's own defaults are light-themed; map them onto Slate's tokens so
           selection/containment highlights never white-out the text. */
        --caret-color:var(--accent,#6cb6ff);
        --primary-color:var(--accent,#6cb6ff);
        --text-color:var(--text,#d7dae1);
        --selection-background-color:color-mix(in srgb, var(--accent,#6cb6ff) 32%, transparent);
        --selection-color:var(--text,#d7dae1);
        --contains-highlight-background-color:color-mix(in srgb, var(--accent,#6cb6ff) 16%, transparent);
        --placeholder-color:color-mix(in srgb, var(--text,#d7dae1) 45%, transparent);
        --placeholder-opacity:0.7;
        --smart-fence-color:color-mix(in srgb, var(--text,#d7dae1) 55%, transparent);
        --correct-color:#56d364;
        --incorrect-color:#f56c6c; }
      .mathchip math-field::part(menu-toggle),
      .mathchip math-field::part(virtual-keyboard-toggle) { display:none; }
    `;
    document.head.appendChild(st);
  }

  // All @codemirror/* pinned to one @codemirror/state so there's a single instance.
  const S = 'https://esm.sh/@codemirror/state@6.5.2';
  const dep = '?deps=@codemirror/state@6.5.2';
  const [state, view, commands, language, legacy] = await Promise.all([
    import(S),
    import('https://esm.sh/@codemirror/view@6.36.5' + dep),
    import('https://esm.sh/@codemirror/commands@6.7.1' + dep),
    import('https://esm.sh/@codemirror/language@6.10.8' + dep),
    import('https://esm.sh/@codemirror/legacy-modes@6.4.2/mode/julia' + dep),
    import('https://esm.sh/mathlive@0.100.0'),          // defines <math-field>
    import('https://esm.sh/@cortex-js/compute-engine@0.26.4'),
  ]);
  const { EditorState, Compartment } = state;
  const { EditorView, Decoration, WidgetType, ViewPlugin, keymap, lineNumbers } = view;
  const { defaultKeymap, history, historyKeymap } = commands;
  const { StreamLanguage } = language;
  const juliaLang = StreamLanguage.define(legacy.julia);

  // The inline-math literal: OPEN + <LaTeX> + CLOSE. Everything derives from these two
  // strings — no hand-counted offsets — so the delimiter could change (e.g. giac"…")
  // in one place. `emptyLit()` builds a blank one; `HEAD` (the `d` flag) hands back the
  // inner-LaTeX range as capture-group indices, so we never add magic numbers.
  const OPEN = 'math"', CLOSE = '"';
  const emptyLit = () => OPEN + CLOSE;
  const RE = new RegExp(OPEN.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '([^"]*)' + CLOSE, 'g');   // scan
  const HEAD = new RegExp('^' + OPEN.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '([^"]*)' + CLOSE, 'd');

  // A live math field standing in for one `math"…"` literal. `from`/`to` bound the
  // WHOLE literal (used only for eq()/atomic ranges); the WRITE range is read live.
  // KEY: we do NOT write to the doc on every keystroke — that would rebuild the
  // decoration and destroy the field you're typing in. The field owns its content
  // while focused; we sync back to the source only when you LEAVE it (blur / Enter /
  // Escape / arrowing out). So typing is stable and the caret never jumps.
  class MathWidget extends WidgetType {
    constructor(latex, from, to) { super(); this.latex = latex; this.from = from; this.to = to; }
    eq(o) { return o.latex === this.latex && o.from === this.from; }
    ignoreEvent() { return true; }                     // the field handles its own events
    toDOM(cmView) {
      const wrap = document.createElement('span');
      wrap.className = 'mathchip';
      const mf = document.createElement('math-field');
      mf.setAttribute('math-virtual-keyboard-policy', 'manual');
      mf.value = this.latex;

      let exiting = false;
      // The widget's CURRENT inner-LaTeX range, read LIVE from its DOM position — never
      // stored from/to (which go stale the moment the doc shifts). `inner` is the
      // capture-group span (the LaTeX between the quotes); `end` is just past CLOSE.
      // Returns null if the widget is gone or the literal no longer parses.
      const liveRange = () => {
        if (!mf.isConnected) return null;
        let start;
        try { start = cmView.posAtDOM(wrap); } catch (e) { return null; }
        const rest = cmView.state.doc.sliceString(start, Math.min(start + 8192, cmView.state.doc.length));
        const m = HEAD.exec(rest);
        if (!m) return null;
        const [is, ie] = m.indices[1];                 // inner-LaTeX span, relative to start
        return { innerFrom: start + is, innerTo: start + ie, end: start + m[0].length };
      };
      // Write the field's LaTeX back into the backing literal. With `dir`, also move the
      // CM caret out into the code. Deferred (this can fire during a CM update — a rebuild
      // destroying this field — where an immediate dispatch throws "update in progress").
      const sync = dir => {
        if (!dir && !mf.isConnected) return;   // teardown blur, not a user commit
        requestAnimationFrame(() => {
          const r = liveRange();
          if (!r) return;
          const latex = mf.value;
          const tr = { changes: { from: r.innerFrom, to: r.innerTo, insert: latex } };
          if (dir) {
            const end = r.innerFrom + latex.length + CLOSE.length;   // just past CLOSE
            tr.selection = { anchor: dir === 'backward' ? r.innerFrom - OPEN.length : end };
          }
          try { cmView.dispatch(tr); if (dir) cmView.focus(); } catch (e) {}
        });
      };
      const exit = dir => { exiting = true; sync(dir || 'forward'); };

      // Leave via Enter / Escape / Tab.
      mf.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === 'Escape' || e.key === 'Tab') {
          e.preventDefault(); e.stopPropagation();
          exit(e.shiftKey ? 'backward' : 'forward');
        }
      }, true);
      // Arrow past an edge → flow out into the code (MathLive emits `move-out`).
      mf.addEventListener('move-out', e => {
        const d = e.detail && e.detail.direction;
        exit(d === 'backward' || d === 'upward' ? 'backward' : 'forward');
      });
      // Click-away commits, without moving the caret.
      mf.addEventListener('focusout', () => { if (exiting) { exiting = false; return; } sync(); });

      wrap.appendChild(mf);
      return wrap;
    }
  }

  function buildDecos(cmView) {
    const b = [];
    for (const { from, to } of cmView.visibleRanges) {
      const text = cmView.state.doc.sliceString(from, to);
      let m;
      RE.lastIndex = 0;
      while ((m = RE.exec(text))) {
        const s = from + m.index, e = s + m[0].length;
        b.push(Decoration.replace({ widget: new MathWidget(m[1], s, e) }).range(s, e));
      }
    }
    return Decoration.set(b, true);
  }

  const mathPlugin = ViewPlugin.fromClass(class {
    constructor(v) { this.decorations = buildDecos(v); }
    update(u) { if (u.docChanged || u.viewportChanged) this.decorations = buildDecos(u.view); }
  }, { decorations: v => v.decorations });

  // Ctrl-M: insert an empty inline math field at the cursor and focus it.
  const insertMath = cmView => {
    const pos = cmView.state.selection.main.head;
    cmView.dispatch({ changes: { from: pos, insert: emptyLit() }, selection: { anchor: pos + OPEN.length } });
    // focus the freshly-mounted (empty) field on the next frame
    requestAnimationFrame(() => {
      const empties = [...host.querySelectorAll('.mathchip math-field')].filter(m => !m.value);
      (empties[empties.length - 1] || null)?.focus();
    });
    return true;
  };

  // Treat each `math"…"` literal as ONE unit for caret motion (arrow keys jump over it).
  const atomic = EditorView.atomicRanges.of(v => {
    const p = v.plugin(mathPlugin);
    return (p && p.decorations) || Decoration.none;
  });

  // Delete the WHOLE literal as a unit. Without this, Backspace from the code just
  // after a widget eats only the closing `"`, so `math"…"` no longer matches and the
  // raw text reappears. `side`: 'end' → range ending at caret (Backspace); 'start' →
  // range starting at caret (Delete).
  const mathRangeAt = (cmView, side, pos) => {
    const decos = cmView.plugin(mathPlugin) && cmView.plugin(mathPlugin).decorations;
    if (!decos) return null;
    let found = null;
    decos.between(0, cmView.state.doc.length, (from, to) => {
      if ((side === 'end' ? to : from) === pos) { found = { from, to }; return false; }
    });
    return found;
  };
  const delMath = side => cmView => {
    const sel = cmView.state.selection.main;
    if (!sel.empty) return false;
    const r = mathRangeAt(cmView, side, sel.head);
    if (!r) return false;
    cmView.dispatch({ changes: { from: r.from, to: r.to }, selection: { anchor: r.from } });
    return true;
  };

  // Is the active Slate theme dark? Derived from the page background's luminance
  // (works for any theme name). A tiny core hook exposing an explicit dark/light flag
  // would let us drop this heuristic.
  const isDarkNow = () => {
    const m = (getComputedStyle(document.body).backgroundColor || '').match(/\d+/g);
    if (!m) return true;
    const [r, g, b] = m.map(Number);
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.5;
  };
  const themeComp = new Compartment();

  // Editor chrome from Slate's theme tokens → follows any Slate theme live. The only
  // thing that isn't a colour is CM's internal dark/light flag (drives a few
  // selection-layer defaults); we derive it from the page background's luminance and
  // reconfigure it when Slate's theme attribute changes.
  const mkTheme = () => EditorView.theme({
    '&': { backgroundColor: 'var(--bg,#15171c)', color: 'var(--text,#d7dae1)',
           border: '1px solid var(--border,#33373f)', borderRadius: '8px', fontSize: '14px' },
    '.cm-content': { fontFamily: 'ui-monospace,SFMono-Regular,Menlo,monospace', padding: '10px' },
    '.cm-gutters': { backgroundColor: 'var(--bg,#15171c)',
                     color: 'color-mix(in srgb, var(--text,#d7dae1) 45%, transparent)', border: 'none' },
    '.cm-cursor, .cm-dropCursor': { borderLeftColor: 'var(--accent,#6cb6ff)' },
    '.cm-selectionBackground, ::selection': { backgroundColor: 'color-mix(in srgb, var(--accent,#6cb6ff) 28%, transparent)' },
    '&.cm-focused': { outline: 'none', borderColor: 'var(--accent,#6cb6ff)' },
  }, { dark: isDarkNow() });

  const startDoc = 'expr = math"(x+1)^3"\nexpand(expr)\n';

  const view_ = new EditorView({
    parent: host,
    state: EditorState.create({
      doc: startDoc,
      extensions: [
        lineNumbers(), history(), juliaLang, themeComp.of(mkTheme()), mathPlugin, atomic,
        keymap.of([
          { key: 'Mod-m', run: insertMath },
          { key: 'Backspace', run: delMath('end') },
          { key: 'Delete', run: delMath('start') },
          ...defaultKeymap, ...historyKeymap,
        ]),
        EditorView.updateListener.of(u => { if (u.docChanged && dbg) dbg.textContent = u.state.doc.toString(); }),
      ],
    }),
  });
  if (dbg) dbg.textContent = view_.state.doc.toString();
  window._mathcodeView = view_;   // handy for poking from eval_js

  // Follow Slate theme switches: the colours are CSS vars (auto), but CM's dark/light
  // flag needs a reconfigure. MathLive's vars are CSS too, so they follow for free.
  new MutationObserver(() => view_.dispatch({ effects: themeComp.reconfigure(mkTheme()) }))
    .observe(document.documentElement, { attributes: true, attributeFilter: ['data-slate-theme'] });

  // ── Run: substitute each math"…" with a GiacExpr and eval in the notebook kernel ──
  const runBtn = document.getElementById('mathcode-run');
  const resultMf = document.getElementById('mathcode-result');
  const errSpan = document.getElementById('mathcode-err');
  if (resultMf) {                                   // theme the read-only result field
    resultMf.style.cssText = 'font-size:1.1rem;color:var(--text,#d7dae1);background:transparent;' +
      'border:none;--caret-color:transparent;--selection-background-color:transparent;' +
      '--contains-highlight-background-color:transparent';
  }
  if (runBtn) runBtn.addEventListener('click', async () => {
    // Fields render in document order, so they zip with the math"…" matches in order.
    const fields = [...host.querySelectorAll('.mathchip math-field')];
    let i = 0;
    RE.lastIndex = 0;
    const code = view_.state.doc.toString().replace(RE, () => {
      const mf = fields[i++];
      let mj = mf ? mf.getValue('math-json') : '';
      if (typeof mj !== 'string') mj = JSON.stringify(mj);
      return 'GiacSlate.mathfield_to_giac(raw"""' + mj + '""")';
    });
    if (errSpan) { errSpan.textContent = ''; errSpan.style.color = 'var(--text,#d7dae1)'; }
    if (resultMf) resultMf.style.display = 'none';
    try {
      const res = await window.slateCall('mathcode_eval', { code });
      if (res && res.ok && res.latex != null && resultMf) {
        resultMf.value = res.latex; resultMf.style.display = '';
      } else if (res && res.ok) {
        if (errSpan) errSpan.textContent = '= ' + res.text;
      } else if (errSpan) {
        errSpan.style.color = '#f56c6c'; errSpan.textContent = '⚠ ' + ((res && res.error) || 'error');
      }
    } catch (e) { if (errSpan) { errSpan.style.color = '#f56c6c'; errSpan.textContent = '⚠ ' + e.message; } }
  });
})();
