import adapter from '@sveltejs/adapter-static'
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),

  kit: {
    // Pure SPA served from the build/ folder; deep links fall through to the
    // SPA shell at 404.html.
    adapter: adapter({
      pages: 'build',
      assets: 'build',
      fallback: '404.html',
      precompress: false,
      strict: false,
    }),

    // Content-Security-Policy. The wizard fetches its question schema and posts
    // the citizen's facts to a jl4-service. Because SvelteKit emits the policy
    // as a <meta> tag on the static pages, a cross-origin fetch is BLOCKED with
    // only a console error unless the EXACT scheme+host+port of that service is
    // listed in connect-src — 'self' does NOT cover it. The spinner would hang
    // forever otherwise.
    //
    // For a non-localhost demo: add the prod jl4-service origin to connect-src
    // here AND set VITE_JL4_BASE_URL to the same origin (see src/lib/config.ts).
    // The two MUST match.
    //
    // style-src stays strict 'self' (no 'unsafe-inline'): the app ships ZERO
    // inline style="" attributes — every answer-card outcome colour is applied
    // via STATIC classes (.outcome-must/.outcome-may/.outcome-clear) in app.css.
    // Verify this against the BUILT app (`vite build && vite preview`): the
    // dev-server CSP and the built <meta> CSP behave differently.
    csp: {
      mode: 'hash',
      directives: {
        'default-src': ['self'],
        'script-src': ['self'],
        'style-src': ['self'],
        'font-src': ['self', 'data:'],
        'img-src': ['self'],
        'connect-src': [
          'self',
          'http://localhost:8080',
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
