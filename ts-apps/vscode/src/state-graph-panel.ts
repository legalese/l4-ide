import * as vscode from 'vscode'
import {
  renderStateGraphSvg,
  StateGraphRenderError,
} from '@repo/state-graph-render'
import {
  renderStateGraphHtml,
  type StateGraphPayload,
} from './state-graph-html.js'

/**
 * The pane the "Show state graph" code lens opens.
 *
 * The language server answers `l4.stateGraph` with the graph as GraphViz DOT
 * source. The DOT is rendered to SVG **here, in the extension host**, by
 * `@repo/state-graph-render` (Graphviz compiled to WebAssembly), and the
 * finished markup is handed to the webview — so the webview's CSP needs no
 * `wasm-unsafe-eval`, no script source and no resource root: inline SVG is
 * DOM, not a fetched resource. The DOT source and a **Copy DOT** button stay
 * under a fold beneath the picture. See `doc/reference/regulative/STATE-GRAPH.md`
 * for what the picture does and does not say, and LTS-VISUALISER.md §4.8.
 *
 * One panel is reused across clicks; a click replaces its contents and brings
 * it forward. `refresh` (called from `didChange`) replaces the contents
 * without stealing focus and is a no-op once the pane has been closed.
 *
 * The document itself is built by `state-graph-html.ts`, which imports no
 * `vscode` so the unit tests can load it.
 */
export class StateGraphPanel {
  static readonly viewType = 'l4StateGraph'

  #panel: vscode.WebviewPanel | undefined

  constructor(private readonly output: vscode.OutputChannel) {}

  /** The pane exists (it may be hidden behind another tab). */
  get isOpen(): boolean {
    return this.#panel !== undefined
  }

  /** Show the graph called `name`, creating the pane if needed. */
  async show(name: string, dot: string): Promise<void> {
    const payload = await this.#render(name, dot)
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
      this.#panel.title = `L4 State Graph: ${name}`
      this.#panel.webview.html = renderStateGraphHtml(payload)
    } else {
      this.#panel.reveal(undefined, /* preserveFocus */ true)
      this.#panel.title = `L4 State Graph: ${name}`
      await this.#panel.webview.postMessage({ type: 'update', ...payload })
    }
  }

  /** Redraw after an edit. Does not reveal; does nothing if the pane is gone. */
  async refresh(name: string, dot: string): Promise<void> {
    if (!this.#panel) return
    const payload = await this.#render(name, dot)
    this.#panel.title = `L4 State Graph: ${name}`
    await this.#panel.webview.postMessage({ type: 'update', ...payload })
  }

  /**
   * The rule the pane was showing is no longer at the position the lens named
   * (it moved under an edit the tracker could not follow, or was deleted).
   * Keep the last picture, say so, and stop refreshing until the next click.
   */
  async markStale(reason: string): Promise<void> {
    if (!this.#panel) return
    await this.#panel.webview.postMessage({ type: 'stale', reason })
  }

  async #render(name: string, dot: string): Promise<StateGraphPayload> {
    try {
      const svg = await renderStateGraphSvg(dot)
      return { name, dot, svg }
    } catch (e) {
      const error =
        e instanceof StateGraphRenderError
          ? e.message
          : `Could not render the state graph: ${String(e)}`
      this.output.appendLine(`[state graph] ${error}`)
      return { name, dot, error }
    }
  }
}
