if (!document.querySelector('script[data-id="giacslate-importmap"]')) {
  const map = {
    "imports": {
      "mathlive": "https://esm.sh/mathlive@0.100.0",
      "@cortex-js/compute-engine": "https://esm.sh/@cortex-js/compute-engine@0.26.4",
      "htm/preact": "https://esm.sh/htm@3.1.1/preact?external=preact",
      "@codemirror/state": "https://esm.sh/@codemirror/state@6.5.2",
      "@codemirror/view": "https://esm.sh/@codemirror/view@6.36.5?deps=@codemirror/state@6.5.2",
      "@codemirror/commands": "https://esm.sh/@codemirror/commands@6.7.1?deps=@codemirror/state@6.5.2",
      "@codemirror/language": "https://esm.sh/@codemirror/language@6.10.8?deps=@codemirror/state@6.5.2",
      "@codemirror/legacy-modes/mode/julia": "https://esm.sh/@codemirror/legacy-modes@6.4.2/mode/julia?deps=@codemirror/state@6.5.2"
    }
  };
  const script = document.createElement('script');
  script.type = 'importmap';
  script.setAttribute('data-id', 'giacslate-importmap');
  script.textContent = JSON.stringify(map);
  document.head.appendChild(script);
}
