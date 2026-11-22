// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
  namespace App {
    // interface Error {}
    // interface Locals {}
    // interface PageData {}
    // interface PageState {}
    // interface Platform {}
  }
}

// Vite environment variable types
interface ImportMetaEnv {
  /** URL to fetch L4 WASM binary (e.g., '/wasm/jl4-core.wasm') */
  readonly VITE_WASM_URL?: string
  /** URL to fetch the WASM JS FFI glue (e.g., '/wasm/jl4-core.mjs') */
  readonly VITE_WASM_JS_URL?: string
  /** The release the WASM came from, shown in load errors */
  readonly VITE_WASM_VERSION?: string
  /** Session persistence service URL; Share is hidden without it */
  readonly VITE_SESSION_URL?: string
  /** Cloudflare Turnstile site key the session service checks shares against */
  readonly VITE_TURNSTILE_SITE_KEY?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

export {}
