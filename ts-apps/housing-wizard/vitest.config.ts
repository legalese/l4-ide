import { defineConfig } from 'vitest/config'

// Only PURE .ts helpers are unit-tested (label cleaning, widget classification,
// tree building, validate/toArguments). No Svelte runes are exercised here, so
// no Svelte plugin is needed. The helpers import the shared schema types with
// `import type`, which esbuild erases — so `jl4-client-rpc` need not resolve at
// test runtime.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})
