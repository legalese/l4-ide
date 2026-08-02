import adapter from '@sveltejs/adapter-static'
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte'

/**
 * Serving under a sub-path (C2c). The dev host's nginx already owns "/" for the
 * IDE (`nix/jl4-web/configuration.nix`), so this SPA is mounted at a location of
 * its own — `/regcf/` by default. SvelteKit needs that prefix baked in at BUILD
 * time, hence the env var; the nix package passes it.
 */
const base = process.env.BASE_PATH ?? ''

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),

  kit: {
    paths: { base },

    // Pure SPA served from build/; deep links fall through to the SPA shell.
    adapter: adapter({
      pages: 'build',
      assets: 'build',
      fallback: '404.html',
      precompress: false,
      strict: false,
    }),

    // Content-Security-Policy. SvelteKit emits it as a <meta> tag on the static
    // pages, so a cross-origin fetch is BLOCKED with only a console error unless
    // the EXACT scheme+host+port of the jl4-service is in connect-src — 'self'
    // does NOT cover it, and the spinner would hang forever.
    //
    // Every origin this app is ever pointed at must appear here AND in
    // VITE_JL4_BASE_URL (src/lib/config.ts). The two MUST match. The loopback
    // entries are what `npm run dev`/`vite preview` talk to; 18099 is the port
    // this app was verified against (see README).
    //
    // style-src stays strict 'self' (no 'unsafe-inline'):
    //   - the app ships ZERO inline style="" attributes; and
    //   - the embedded ladder is safe under it because `sceneToSvg` emits only
    //     presentational SVG attributes (font-style, fill, font-weight) and
    //     `LadderController` writes every style through the CSSOM
    //     (`el.style.x = …`), which `style-src` does not govern.
    csp: {
      mode: 'hash',
      directives: {
        'default-src': ['self'],
        'script-src': ['self'],
        'style-src': ['self'],
        'font-src': ['self', 'data:'],
        'img-src': ['self', 'data:'],
        'connect-src': [
          'self',
          'http://localhost:8080',
          'http://127.0.0.1:8080',
          'http://localhost:18099',
          'http://127.0.0.1:18099',
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
