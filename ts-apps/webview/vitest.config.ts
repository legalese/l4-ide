import { fileURLToPath } from 'node:url'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vitest/config'

// Two kinds of test live here: PURE .ts helpers under src/lib (the deploy
// review's compatibility check, the input-default formatter), and the Svelte
// components that only turn props into markup (`tool-card`), which are
// rendered to a string on the server side of Svelte. No DOM and no jsdom are
// involved, and nothing here starts the extension or the language server.
//
// `jl4-client-rpc` is resolved here as it is for every other test in this
// package: to its built `dist/`, so `npm run build` comes before `npm run
// test` (CI does it in that order). It is not aliased to one source file: the
// chat-store tests import values from all over the package, and an alias to a
// single module leaves them undefined (`cloudSessionIdOf is not a function`).
export default defineConfig({
  plugins: [svelte({ hot: false })],
  resolve: {
    alias: {
      $lib: fileURLToPath(new URL('./src/lib', import.meta.url)),
    },
  },
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})
