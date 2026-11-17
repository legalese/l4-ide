import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

// Only PURE .ts helpers under src/lib are unit-tested here (the deploy
// review's compatibility check, the input-default formatter). No Svelte
// runes and no DOM are exercised, so no Svelte plugin and no jsdom are
// needed: the same line the other apps in this repo draw.
//
// The one value these helpers take from `jl4-client-rpc` is
// `takesDeonticEnvelope` (everything else they import from it is a type, which
// is erased). It is aliased to its TypeScript source rather than to the
// package's `dist/`, so that a test run does not depend on that package, and
// the packages it re-exports, having been built. A test that needs another
// value from the package adds it here.
export default defineConfig({
  resolve: {
    alias: {
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
