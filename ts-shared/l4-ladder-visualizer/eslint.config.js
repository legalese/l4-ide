import { config } from '@repo/eslint-config/svelte'

export default [
  ...config,
  {
    files: ['**/*.svelte'],
    rules: {
      /**
       * `no-undef` is a false positive on every TS-only identifier in a `.svelte` file, and
       * ladder Step 4 is the first change in this repo to trip it.
       *
       * Why it fires: `@repo/eslint-config`'s `base.js` pulls in `js.configs.recommended`,
       * which turns `no-undef` on. typescript-eslint ships a compatibility layer that turns
       * it back off — TypeScript already reports undefined names as ts(2304)/ts(2552) — but
       * that layer scopes itself to TS extensions only — `ts`, `tsx`, `mts`, `cts` (see the
       * `files` key in `@typescript-eslint/eslint-plugin`'s `eslint-recommended-raw.js`). A
       * `.svelte` file is TS-parsed here and falls outside that glob, so it keeps the rule.
       *
       * What tripped it: `partial-eval-sidebar.svelte`'s `<script lang="ts" generics="C =
       * unknown">`. That attribute declares a TYPE parameter — it exists for TypeScript and
       * for nobody else — and `no-undef` reported `'C' is not defined`, failing CI at
       * `--max-warnings=0`. It is the repo's first use of `generics=`, which is why a config
       * gap that has always been there had never been hit.
       *
       * Nothing is lost: `npm run check` runs `svelte-check` over exactly these files, and
       * that is the checker that can see the type layer at all.
       *
       * Scoped to THIS package rather than fixed in `@repo/eslint-config/svelte` on purpose.
       * The shared config is the right home for it, but turning the rule off there makes two
       * pre-existing `// eslint-disable-next-line no-undef` directives redundant
       * (`ts-apps/webview/src/routes/+page.svelte:168` and `sidebar/+page.svelte:1603`), and
       * eslint then fails those packages for the now-unused directives. Deleting them is a
       * two-line cleanup in `ts-apps/webview`, which ladder Step 4 deliberately does not
       * touch (that is Step 5). Follow-up: move this rule to the shared config and drop
       * those two directives in the same change.
       */
      'no-undef': 'off',
    },
  },
]
