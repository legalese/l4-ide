import { sveltekit } from '@sveltejs/kit/vite'
import { defineConfig } from 'vitest/config'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [sveltekit(), tailwindcss()],
  build: {
    rollupOptions: {
      external: ['vscode-webview'],
    },
    minify: true,
    sourcemap: false,
  },
  test: {
    include: ['src/**/*.test.ts'],
  },
})
