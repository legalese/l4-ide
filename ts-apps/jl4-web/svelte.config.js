import adapter from '@sveltejs/adapter-static'
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

/** @type {import('@sveltejs/kit').Config} */
const config = {
  // Consult https://svelte.dev/docs/kit/integrations
  // for more information about preprocessors
  preprocess: vitePreprocess(),

  kit: {
    adapter: adapter({
      // default options are shown. On some platforms
      // these options are set automatically — see below
      pages: 'build',
      assets: 'build',
      // No SPA fallback: the one page is prerendered to index.html (see
      // src/routes/+layout.ts), and a fallback would overwrite it.
      precompress: true,
      strict: true,
    }),
    serviceWorker: {
      register: false,
    },
  },
}

export default config
