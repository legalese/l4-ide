import { defineConfig } from 'vitest/config'

// Only PURE .ts helpers are unit-tested: label cleaning, widget classification,
// tree building, validate/toArguments, and the elicitation-loop policy in
// `lib/elicit/plan.ts`. No Svelte runes and no DOM are exercised here, so no
// Svelte plugin and no jsdom are needed — the same deliberate line
// EMBEDDABLE.md §3.5 draws for the ladder controller.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})
