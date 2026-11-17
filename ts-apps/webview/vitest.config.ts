import { fileURLToPath } from 'node:url'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vitest/config'

// Two kinds of test live here: PURE .ts helpers under src/lib (the deploy
// review's compatibility check, the input-default formatter), and the Svelte
// components that only turn props into markup (`tool-card`), which are
// rendered to a string on the server side of Svelte. No DOM and no jsdom are
// involved, and nothing here starts the extension or the language server.
//
// The one value the pure helpers take from `jl4-client-rpc` is
// `takesDeonticEnvelope` (everything else they import from it is a type, which
// is erased). It is aliased to its TypeScript source rather than to the
// package's `dist/`, so that a test run does not depend on that package, and
// the packages it re-exports, having been built. A test that needs another
// value from the package adds it here.
export default defineConfig({
  plugins: [svelte({ hot: false })],
  resolve: {
    alias: {
      $lib: fileURLToPath(new URL('./src/lib', import.meta.url)),
      'jl4-client-rpc': fileURLToPath(
        new URL(
          '../../ts-shared/jl4-client-rpc/deontic-envelope.ts',
          import.meta.url
        )
      ),
    },
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})
