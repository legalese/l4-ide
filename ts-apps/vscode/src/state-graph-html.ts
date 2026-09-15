/**
 * The state-graph pane's document, kept apart from `state-graph-panel.ts`
 * (which needs the `vscode` API) so it can be unit-tested under `node --test`.
 */

/** What the webview shows: the picture when Graphviz drew one, else why not. */
export interface StateGraphPayload {
  name: string
  dot: string
  svg?: string
  error?: string
}

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

/**
 * The webview's CSP: nothing may load from anywhere; inline styles for our own
 * `<style>` block; one nonce'd inline script. The SVG needs none of it —
 * Graphviz writes presentation attributes (`fill=`, `stroke-dasharray=`), not
 * `style=`, and the picture arrives as markup, not as a resource.
 */
export const stateGraphCsp = (nonce: string): string =>
  `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';`

/**
 * The initial document. The picture is inlined as markup (Graphviz has
 * XML-escaped every label, and the emitter's DOT never asks for `<script>`,
 * `<a>` or `<foreignObject>`); the payload also travels as JSON in a
 * non-executed `<script type="application/json">` so the page's script can
 * wire the copy button and, on `update` messages, replace the picture in
 * place without a reload. An `update` that carries an `error` and no `svg`
 * (Graphviz refused the DOT the server sent after an edit) keeps the last
 * picture, dimmed, under the error text — deliberately, like the `stale`
 * notice keeps it undimmed; a redraw after a successful render undims it.
 */
export function renderStateGraphHtml(payload: StateGraphPayload): string {
  const nonce = Math.random().toString(36).slice(2)
  const payloadJson = JSON.stringify(payload).replace(/<\//g, '<\\/')
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="${stateGraphCsp(nonce)}">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>L4 State Graph</title>
  <style>
    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); padding: 0 1em 1em; }
    h1 { font-size: 1.1em; font-weight: 600; margin: 1em 0 0.25em; }
    p.note { margin: 0.25em 0 0.75em; opacity: 0.8; font-size: 0.9em; }
    p.stale { margin: 0.25em 0 0.75em; font-size: 0.9em; color: var(--vscode-editorWarning-foreground); }
    p.error { margin: 0.25em 0 0.75em; color: var(--vscode-errorForeground); white-space: pre-wrap; }
    #picture { overflow: auto; }
    /* An update whose render failed keeps the last picture but dims it, so
       an old drawing is not mistaken for the rule as it now stands. */
    #picture.faded { opacity: 0.35; }
    #picture svg { max-width: 100%; height: auto; }
    /* Graphviz draws on white with black text and black default strokes.
       The white canvas is stripped before the SVG gets here; recolour what
       would sit on the theme background (title, edge labels, plain strokes)
       to the theme foreground. Text inside a node keeps Graphviz's black:
       the node fills are pastel in every theme. */
    #picture g.graph > text, #picture g.edge text { fill: var(--vscode-foreground); }
    #picture g.node [stroke="black"], #picture g.edge [stroke="black"] { stroke: var(--vscode-foreground); }
    #picture g.edge [fill="black"] { fill: var(--vscode-foreground); }
    details { margin-top: 1em; }
    summary { cursor: pointer; opacity: 0.8; font-size: 0.9em; }
    button { font: inherit; padding: 0.3em 0.8em; margin: 0.75em 0;
             color: var(--vscode-button-foreground); background: var(--vscode-button-background);
             border: none; border-radius: 2px; cursor: pointer; }
    button:hover { background: var(--vscode-button-hoverBackground); }
    pre { font-family: var(--vscode-editor-font-family); font-size: var(--vscode-editor-font-size);
          background: var(--vscode-textCodeBlock-background); padding: 0.75em; overflow: auto;
          white-space: pre; user-select: text; }
  </style>
</head>
<body>
  <h1 id="title">State graph: ${escapeHtml(payload.name)}</h1>
  <p class="note">The action plane of this rule: states, and the actions that move between them.
  It does not show who is obliged to do what at any moment. Redraws as you edit.</p>
  <p class="stale" id="stale" hidden></p>
  <p class="error" id="error"${payload.error ? '' : ' hidden'}>${escapeHtml(payload.error ?? '')}</p>
  <div id="picture">${payload.svg ?? ''}</div>
  <details>
    <summary>DOT source</summary>
    <button id="copy">Copy DOT</button>
    <pre id="dot"></pre>
  </details>
  <script type="application/json" id="payload">${payloadJson}</script>
  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    let dot = JSON.parse(document.getElementById('payload').textContent).dot;
    const el = (id) => document.getElementById(id);
    el('dot').textContent = dot;
    el('copy').addEventListener('click', () => {
      vscode.postMessage({ type: 'copy', text: dot });
      el('copy').textContent = 'Copied';
      setTimeout(() => { el('copy').textContent = 'Copy DOT'; }, 1500);
    });
    window.addEventListener('message', (ev) => {
      const msg = ev.data || {};
      if (msg.type === 'update') {
        dot = msg.dot;
        el('title').textContent = 'State graph: ' + msg.name;
        el('dot').textContent = dot;
        el('stale').hidden = true;
        el('error').hidden = !msg.error;
        el('error').textContent = msg.error || '';
        // No svg means Graphviz refused this DOT: keep the last picture,
        // dimmed under the error, rather than blanking the pane.
        if (msg.svg) { el('picture').innerHTML = msg.svg; }
        el('picture').classList.toggle('faded', !msg.svg);
      } else if (msg.type === 'stale') {
        el('stale').textContent = msg.reason;
        el('stale').hidden = false;
      }
    });
  </script>
</body>
</html>`
}
