import adapter from '@sveltejs/adapter-node'
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

/**
 * adapter-node, not adapter-static: the interview runs in a server route
 * (`src/routes/api/interview/+server.ts`) that holds the Anthropic key and
 * talks to jl4-service on the operator's behalf. The browser never sees the key.
 *
 * The rest of the page is still a browser app: the ladder, the charge text and
 * the evidence graph all come from the browser calling jl4-service directly, so
 * the CSP connect-src below must name the SAME origin as SERVICE_BASE_URL in
 * `src/lib/config.ts` (a <meta>-tag CSP blocks a cross-origin fetch with only a
 * console error — the spinner hangs). See regcf-wizard for the measurements
 * behind the strict style-src: the ladder embed writes styles through the CSSOM,
 * which style-src does not govern.
 */
const base = process.env.BASE_PATH ?? ''

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    paths: { base },
    adapter: adapter({ out: 'build', precompress: false }),
    csp: {
      mode: 'hash',
      directives: {
        'default-src': ['self'],
        'script-src': ['self'],
        'style-src': ['self'],
        'font-src': ['self', 'data:'],
        'img-src': ['self', 'data:', 'blob:'],
        'connect-src': [
          'self',
          'http://localhost:8080',
          'http://127.0.0.1:8080',
          'http://localhost:18099',
          'http://127.0.0.1:18099',
          // the demo host, reached from other machines on the LAN by name
          'http://nye:18099',
          'http://nye.local:18099',
          'http://192.168.252.125:18099',
          'http://192.168.252.23:18099',
          'https://dev.jl4.legalese.com',
          'https://jl4.legalese.com',
          'https://legalese.cloud',
          'https://*.legalese.cloud',
        ],
        'frame-src': ['none'],
        'object-src': ['none'],
        'base-uri': ['self'],
      },
    },
  },
}

export default config
