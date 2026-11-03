/**
 * Factory for the L4 LSP connection.
 *
 * The language server runs in the browser: jl4-core compiled to WebAssembly,
 * wrapped in MessageTransports so MonacoLanguageClient talks to it like any
 * other server.
 */

import type { MessageTransports } from 'vscode-languageclient'

/** Configuration for the LSP connection */
export interface LspConnectionConfig {
  /** URL to fetch the WASM binary */
  wasmUrl: string
  /** URL to fetch the WASM JS FFI glue code */
  wasmJsUrl: string
  /** The release the WASM came from, shown in load errors */
  wasmVersion: string
}

/** An open LSP connection */
export interface LspConnectionResult {
  /** Message transports for the language client */
  transports: MessageTransports
  /** Cleanup function */
  dispose: () => Promise<void>
}

/**
 * Check if WASM is available and can be used
 */
export function isWasmAvailable(): boolean {
  return (
    typeof WebAssembly !== 'undefined' &&
    typeof WebAssembly.instantiateStreaming === 'function'
  )
}

/**
 * Create the WASM-based LSP connection
 */
export async function createLspConnection(
  config: LspConnectionConfig
): Promise<LspConnectionResult> {
  if (!isWasmAvailable()) {
    throw new Error('WebAssembly is not supported in this browser')
  }

  // Import WASM bridge modules
  const { L4WasmBridge, createWasmMessageTransports } = await import(
    './wasm/index'
  )

  // Create and initialize the WASM bridge
  const bridge = new L4WasmBridge(
    config.wasmUrl,
    config.wasmJsUrl,
    config.wasmVersion
  )
  await bridge.initialize()

  // Create MessageTransports that route to the WASM bridge
  const transports = createWasmMessageTransports(bridge)

  console.log('[L4 LSP] WASM connection established')

  return {
    transports,
    dispose: async () => {
      transports.reader.dispose()
      transports.writer.dispose()
      bridge.dispose()
    },
  }
}

/**
 * Get the configuration from the environment
 */
export function getDefaultConfig(): LspConnectionConfig {
  return {
    wasmUrl: import.meta.env.VITE_WASM_URL || '/wasm/jl4-core.wasm',
    wasmJsUrl: import.meta.env.VITE_WASM_JS_URL || '/wasm/jl4-core.mjs',
    wasmVersion: import.meta.env.VITE_WASM_VERSION || 'dev',
  }
}
