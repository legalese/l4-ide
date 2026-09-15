import * as vscode from 'vscode'

/**
 * The pane the "Show state graph" code lens opens.
 *
 * The language server answers `l4.stateGraph` with the graph as GraphViz DOT
 * source. Nothing in this repository renders DOT (no viz.js, d3-graphviz or
 * @hpcc-js/wasm anywhere in the lockfile — checked 2026-09-15), and adding a
 * renderer is a lockfile change with its own review, so step 1 is the honest
 * one: show the DOT, let the reader copy it into any Graphviz. See
 * `doc/reference/regulative/STATE-GRAPH.md` for what it does and does
 * not say, and LTS-VISUALISER.md §4.8 for why the entry point is worth having
 * before the picture is.
 *
 * One panel is reused across clicks; a new click replaces its contents.
 */
export class StateGraphPanel {
  static readonly viewType = 'l4StateGraph'

  #panel: vscode.WebviewPanel | undefined

  constructor(private readonly output: vscode.OutputChannel) {}

  /** Show `dot` for the rule called `name`, creating the pane if needed. */
  show(name: string, dot: string): void {
    if (!this.#panel) {
      this.#panel = vscode.window.createWebviewPanel(
        StateGraphPanel.viewType,
        'L4 State Graph',
        { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true },
        { enableScripts: true, retainContextWhenHidden: true }
      )
      this.#panel.onDidDispose(() => {
        this.#panel = undefined
      })
      this.#panel.webview.onDidReceiveMessage(
        async (msg: { type?: string; text?: string }) => {
          if (msg?.type === 'copy' && typeof msg.text === 'string') {
            await vscode.env.clipboard.writeText(msg.text)
            this.output.appendLine('[state graph] DOT copied to clipboard')
          }
        }
      )
    } else {
      this.#panel.reveal(undefined, /* preserveFocus */ true)
    }
    this.#panel.title = `L4 State Graph: ${name}`
    this.#panel.webview.html = renderHtml(name, dot)
  }
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}

function renderHtml(name: string, dot: string): string {
  const nonce = Math.random().toString(36).slice(2)
  const csp = `default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';`
  // The DOT travels to the script as JSON inside a <script type="application/json">,
  // which the browser does not execute, so no escaping of the DOT itself is
  // needed beyond closing-tag safety.
  const dotJson = JSON.stringify(dot).replace(/<\//g, '<\\/')
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="Content-Security-Policy" content="${csp}">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>L4 State Graph</title>
  <style>
    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); padding: 0 1em 1em; }
    h1 { font-size: 1.1em; font-weight: 600; margin: 1em 0 0.25em; }
    p.note { margin: 0.25em 0 0.75em; opacity: 0.8; font-size: 0.9em; }
    button { font: inherit; padding: 0.3em 0.8em; margin-bottom: 0.75em;
             color: var(--vscode-button-foreground); background: var(--vscode-button-background);
             border: none; border-radius: 2px; cursor: pointer; }
    button:hover { background: var(--vscode-button-hoverBackground); }
    pre { font-family: var(--vscode-editor-font-family); font-size: var(--vscode-editor-font-size);
          background: var(--vscode-textCodeBlock-background); padding: 0.75em; overflow: auto;
          white-space: pre; user-select: text; }
  </style>
</head>
<body>
  <h1>State graph: ${escapeHtml(name)}</h1>
  <p class="note">The action plane of this rule as GraphViz DOT: states, and the actions that move between them.
  It does not show who is obliged to do what at any moment. Copy it into any Graphviz renderer to see the picture.</p>
  <button id="copy">Copy DOT</button>
  <pre id="dot"></pre>
  <script type="application/json" id="dot-source">${dotJson}</script>
  <script nonce="${nonce}">
    const vscode = acquireVsCodeApi();
    const dot = JSON.parse(document.getElementById('dot-source').textContent);
    document.getElementById('dot').textContent = dot;
    document.getElementById('copy').addEventListener('click', () => {
      vscode.postMessage({ type: 'copy', text: dot });
      const b = document.getElementById('copy');
      b.textContent = 'Copied';
      setTimeout(() => { b.textContent = 'Copy DOT'; }, 1500);
    });
  </script>
</body>
</html>`
}
