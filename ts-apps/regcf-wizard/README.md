# regcf-wizard

The citizen-facing wizard over the Regulation Crowdfunding corpus — Track C item
**C2b** of [`specs/todo/lexipedia-superset/`](../../specs/todo/lexipedia-superset/),
with the deployment half (**C2c**) prepared but not performed.

It re-implements no law. Every number, every sentence and every citation on the
page comes back from `jl4-service` evaluating
[`jl4/examples/legal/regcf/regcf-wizard.l4`](../../jl4/examples/legal/regcf/regcf-wizard.l4),
which is itself a façade over `regcf.l4`. The client's job is to ask, to render,
and to refuse to guess.

---

## What it is

An entry page that is a **hub**, not a questionnaire. The corpus exports five
decision surfaces for two audiences; a single linear form would ask a founder
about resale restrictions and an investor about audited financials.

| Surface                              | Export                                      | Shape                                     |
| ------------------------------------ | ------------------------------------------- | ----------------------------------------- |
| Can this company raise? step by step | `can this company raise` (BOOLEAN)          | progressive disclosure over `/query-plan` |
| Full raise check                     | `raise check` (`RaiseAssessment`)           | 9-question form → answer card             |
| How much may I invest?               | `investment limit check` + the law-time one | the R8 surface — two clocks, one form     |
| May I sell these securities yet?     | `resale check` (`ResaleAnswer`)             | form → answer card                        |
| May we stop filing annual reports?   | `reporting exit check`                      | form → answer card                        |

The **ladder is embedded in the entry page** (SPEC.md §7, G3): static on the hub,
interactive inside the step-by-step surface, both driven by the framework-free
`LadderController` from PR #177 via `@repo/ladder-svg`.

---

## Three things that are easy to get wrong, and how this app gets them right

### 1. Switch on `verdict`, never on `determined`

`Backend/DecisionQueryPlan.hs:224-226` says a UI that switches on `determined`
"will sooner or later tell someone they complied with a rule that never reached
them". `determined` is `null` for four of the six verdicts. `lib/elicit/plan.ts`
switches on `verdict`, and `plan.test.ts` pins that.

### 2. Join the ladder to the query plan on `unique`, not `atomId`

Measured against the loopback service, for the same atom of
`can this company raise`:

| payload                        | `unique` | `atomId`                               |
| ------------------------------ | -------- | -------------------------------------- |
| `GET …/ladder`                 | 4        | `64e895d0-1863-5f26-bb2b-63ef440b85d3` |
| `POST …/query-plan` (`ranked`) | 4        | `a87d9b26-bfef-5b0b-9c22-d77d103f93a9` |

Binding by the query plan's atomId works; binding by the **ladder's** atomId
returns `200` and silently changes nothing. A client that joined on `atomId`
would draw one diagram and answer a different question, with no error anywhere.
`ladder-embed.test.ts` asserts the disagreement so a future change to either
derivation is caught rather than absorbed.

### 3. The ladder payload carries no valuation

Every leaf is `"value":"UnknownV"` on the wire and **stays** `UnknownV` when the
query plan binds it. The valuation is the client's, exactly as EMBEDDABLE.md
**EK5** requires; the verdict beside it is still the service's, so the picture
and the answer cannot disagree.

---

## Ruling R8 — one input, two clocks, the derivation shown

`CORPUS-TRACK.md` §8 R8: _"ask a fact date, disclose the derived rule date, and
allow an override"_. `lib/lawtime.ts` owns all three, and knows nothing about
which figures changed when — a client-side regime table would be a second copy
of the law and the first one to go stale.

Live, same investor (income $150,000, net worth $80,000, nothing invested yet,
not accredited):

| rule date  | 12-month limit |
| ---------- | -------------- |
| 2016-06-01 | $4,000         |
| 2018-01-01 | $4,000         |
| 2022-09-20 | $7,500         |
| 2023-01-01 | $7,500         |

Same question, same figures, two rule dates, two answers — and the page says
_why_ it applied the date it applied.

---

## Running it locally

```bash
# 1. a loopback jl4-service with the regcf bundle
mkdir -p /tmp/jl4-store/regcf/sources
cp jl4/examples/legal/regcf/*.l4 /tmp/jl4-store/regcf/sources/
echo '{"smFunctions":[],"smVersion":"dev","smCreatedAt":"2025-01-01T00:00:00Z"}' \
  > /tmp/jl4-store/regcf/metadata.json
JL4_LIBRARY_PATH="$PWD/jl4-core/libraries" \
  cabal run jl4-service -- --port 18099 --store-path /tmp/jl4-store \
  --server-name http://127.0.0.1:18099

# 2. the wizard
npm run dev -w regcf-wizard         # or: npm run build -w regcf-wizard && npm run preview -w regcf-wizard
```

`VITE_JL4_BASE_URL` defaults to `http://127.0.0.1:18099`. Point it elsewhere and
**add that exact origin to the CSP `connect-src` list in `svelte.config.js`** —
the policy is emitted as a `<meta>` tag, `'self'` does not cover a cross-origin
fetch, and the failure mode is a spinner that hangs with only a console error.

---

## The manual browser gate

`vitest` covers everything below the DOM: schema→widget classification, the
multi-root argument payload, the elicitation policy, R8's date arithmetic, the
ladder decode/join/layout/emit path against verbatim live fixtures. What it does
**not** cover is listener plumbing, `innerHTML`, sizing, `requestAnimationFrame`
and `ResizeObserver` — deliberately, for the reason `LadderController`'s own
header gives: a `jsdom` dependency is the merge-queue hazard EMBEDDABLE.md §3.5
flags, and it would buy machine coverage of event-to-argument translation only.

So, against a loopback service, in a real browser:

1. **Entry page.** The hub lists five surfaces and the ladder appears above them
   with both limbs named. It is static: clicking a box does nothing, the cursor
   does not change.
2. **Step by step.** The ladder is now interactive. Answer "Yes" to limb 1 —
   that box turns green, the wire lights as far as it goes, and the next
   question is limb 2. Answer "No" to limb 1 instead and the verdict settles at
   `Fails` **without limb 2 ever being asked**. That early stop is the
   observable difference from a form.
3. Still there: click a green box on the diagram. It cycles Yes → No → unknown
   and the verdict follows. Watch the `viewBox` attribute change under
   ⌘/ctrl-wheel — that is the check that distinguishes "zoom works" from "zoom
   silently no-ops" when a host's height chain is broken.
4. **How much may I invest?** Set the fact date to 2016-06-01, income 150000,
   net worth 80000, invested 0, not accredited. The card must say **$4,000**,
   must say _"because that is when the investment was made"_, and must contrast
   it with $7,500 today.
5. Same surface, open "Advanced: pin the rule date separately", tick it and pin
   2023-01-01 with the fact date left at 2016-06-01. The headline becomes
   $7,500 and the sentence changes to _"because you pinned that date — not
   because of when the investment was made"_.
6. **Full raise check** with a clean US company raising $3,000,000: "You
   qualify", headroom $5,000,000, audited financial statements, and the
   as-at-date line at the foot.
7. Devtools console shows **exactly one** CSP violation per load and no others.
   This is the one that must be checked against the BUILT app (`npm run build &&
npm run preview`), not the dev server: the two emit different policies.

### What step 1 and step 7 look like when measured

Steps 1 and 7 were run in headless Chrome (Playwright, system Chrome channel)
against the built app on a loopback preview, 2026-08-02. Recording the numbers
here so the next reader is comparing against something, not re-deriving it:

| check                      | measured                                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| service calls from the hub | one — `GET …/can this company raise/ladder`; no failed requests                                         |
| ladder mounts              | 1 `<svg>`, `viewBox="0 0 1062 180"`, rendered 685×116 (so `max-width:100%` is live)                     |
| it is the corpus's         | 2 `rect.lad-box`, 3 `polyline.lad-wire`, and the two `<text>` nodes are the leaf labels verbatim        |
| CSP violations             | exactly 1 — `style-src-attr`, `blockedURI:"inline"`, empty sample, from SvelteKit's `#svelte-announcer` |
| that violation's effect    | none visible: the announcer still computes to `position:absolute`, 1×1, `clip-path:inset(50%)`          |

The two `<text>` contents are `` `issuer is eligible` OF (`issuer profile from`
OF plan) `` and `` `offering is within the offering limit` OF (`offering from`
OF plan) `` — byte-identical to the `name.label` fields the loopback
`/ladder` endpoint returned, which is what makes them the corpus's picture and
not a placeholder.

Steps 2, 3, 5 (interaction, pan/zoom, the R8 override toggle) remain hand-run:
they need input events, and the automation above only loads and reads.

---

## Deploying (C2c) — and the line this repository stops at

Everything needed is committed:

- `nix/regcf-wizard/configuration.nix` contributes the **`regcf` bundle** to
  `services.jl4-service.bundles`, from inside the same `mkIf` as the page.
  Verified by replicating `jl4-service`'s `ExecStartPre` exactly — copying the
  whole corpus directory and starting the service — which reported
  `exportCount: 6` and `ready:1, total:1`, ignoring `figures/`, `tests/` and the
  two `.md` files.

  It is contributed there and **not** in `jl4-service`'s bundle defaults, which
  is where it first landed. Every host imports `nix/configuration.nix`,
  production included, so a bundle sitting in that default would have been
  pre-seeded and served publicly by the next unrelated `nixos-rebuild switch`,
  with nobody having enabled the wizard. Note the module-system detail that
  makes the gated version work: `bundles` now carries an empty `default` and the
  base two are a `config` definition, because an `attrsOf` option merges its
  definitions but discards its default as soon as anything defines it — the
  naive gated version would have dropped `classic` and `thailand-cosmetics`.

- `nix/regcf-wizard/{package.nix,configuration.nix}` build the SPA and serve it
  at `/regcf/`, with `VITE_JL4_BASE_URL` derived from the same domain as the
  service — so `connect-src 'self'` covers it and **no CSP edit is needed** to
  deploy same-origin.
- `nix/configuration.nix` imports the module. It is **off by default**, so
  importing it serves nothing.

**These nix expressions have not been evaluated.** There is no `nix` in the
environment they were written in; they are reviewed-by-eye against the existing
`jl4-web` module they are modelled on, and that is all.

Turning it on is one line:

```nix
services.regcf-wizard.enable = true;
```

and then the command that actually publishes it — which this work did **not**
run, and which is gate HG2's to authorise:

```bash
nixos-rebuild switch --flake .#jl4-dev --target-host root@dev.jl4.legalese.com
```
