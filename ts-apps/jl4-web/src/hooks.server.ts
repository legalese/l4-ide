import type { Handle } from '@sveltejs/kit'

// Runs when the page shell is prerendered (and in `vite dev`): fills in the
// WASM URL app.html preloads, the same one lsp-connection-factory.ts fetches.
const wasmUrl = import.meta.env.VITE_WASM_URL || '/wasm/jl4-core.wasm'

export const handle: Handle = ({ event, resolve }) =>
  resolve(event, {
    transformPageChunk: ({ html }) => html.replace('%l4.wasmUrl%', wasmUrl),
  })
