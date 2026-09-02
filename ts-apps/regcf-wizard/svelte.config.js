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
    // style-src stays strict 'self' (no 'unsafe-inline'). What that costs and
    // what it does not, MEASURED in headless Chrome against the built app on a
    // loopback preview (2026-08-02) — not reasoned about:
    //
    //   - The embedded ladder is safe. `sceneToSvg` emits only presentational
    //     SVG attributes (font-style, fill, font-weight), and `LadderController`
    //     writes every style through the CSSOM (`el.style.x = …`), which
    //     `style-src` does not govern. Those CSSOM writes DO serialise into a
    //     `style=` attribute you can read back — the served SVG shows
    //     `style="transition: opacity 320ms;"` on `polyline.lad-wire` and
    //     `max-width:100%;height:auto;display:block` on the root — and they take
    //     effect: computed `transition-duration` is `0.32s`. So do not "fix" a
    //     style attribute you find in the live SVG; reading one back is not
    //     evidence that anything was blocked.
    //
    //   - It is NOT true that the app ships zero inline `style=` attributes. An
    //     earlier version of this comment said so and was wrong. SvelteKit emits
    //     its own `#svelte-announcer` live-region with an inline style, so every
    //     page load logs exactly ONE violation — `style-src-attr`, `blockedURI:
    //     "inline"`, empty sample, sourced to Svelte's hydration chunk. Nothing
    //     visibly degrades (the announcer still computes to a 1×1 clipped box,
    //     because the prerendered markup is parsed before hydration), so this is
    //     console noise, not breakage. It is recorded rather than silenced:
    //     relaxing style-src to quiet one benign warning would give up the
    //     directive that makes the ladder embed safe in the first place.
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
