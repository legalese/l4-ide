# Plan B: can a ladder survive inside Mermaid's grammar?

**Verdict up front: yes, far further than §24 assumes — but via a diagram type §24 never
considered (`railroad-beta`, not `block-beta` or `flowchart`), and the last 30% of fidelity
costs a code generator, which dissolves the only reason to want Mermaid at all.**

§24's _conclusion_ ("Mermaid never") survives. Its _reasoning_ does not, and should be
rewritten: two of its three load-bearing premises are factually wrong, and the honest
argument is a different (stronger) one.

---

## 1. Two premises in §24 are false

### 1.1 "GitHub pins its own [old] Mermaid" — **false**

GitHub renders Mermaid in a sandboxed iframe served from
`https://viewscreen.githubusercontent.com/markdown/mermaid`, which loads exactly one script:
`/static/assets/mermaidMarkdown-a1eea15eae7bd19ad131.js` (1.69 MB, no lazy chunks — every
diagram type is inlined).

I extracted the diagram-detector regexes from that production bundle and diffed them against
a local `mermaid@11.16.0`. **The registries are identical** (38 detectors, same set):

```
architecture  block  classDiagram  cynefin-beta  erDiagram  eventmodeling  flowchart
flowchart-elk  gantt  gitGraph  graph  info  ishikawa  journey  kanban  mindmap  packet
pie  quadrantChart  radar-beta  railroad-abnf-beta  railroad-beta  railroad-ebnf-beta
railroad-peg-beta  requirement  sankey  sequenceDiagram  stateDiagram  stateDiagram-v2
swimlane-beta  timeline  treeView-beta  treemap  venn-beta  wardley-beta  xychart  C4  …
```

The string `"11.16.0"` is also present in the bundle (passed to `renderer.draw`). **GitHub
ships current Mermaid.** The widely-cited community-discussion answers ("GitHub is on v10")
are stale. So `block-beta`, `flowchart-elk`, `venn-beta` _and_ `railroad-beta` are all live on
github.com today. There is also **no diagram-type allowlist** in GitHub's wrapper — it calls
`mermaid.render` on whatever you give it.

### 1.2 "GitHub may sanitize `%%{init}%%` directives" — **false**

Scraped verbatim from the bundle, GitHub's init call is:

```js
mermaid.initialize({
  startOnLoad: false,
  secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize"],
  securityLevel: "antiscript",
  flowchart: { diagramPadding: 48 },
  gantt: { useWidth: 1200 },
  pie: { useWidth: 1200 },
  sequence: { diagramMarginY: 40 },
  theme: "dark" === colorMode ? "dark" : "default",
});
```

`themeVariables`, `themeCSS` and per-diagram config blocks are **not** in `secure` — so
frontmatter `config:` / `%%{init}%%` directives _do_ take effect on github.com.

The output SVG is then DOMPurified against a 102-tag allowlist. I extracted it: `svg`, `g`,
`rect`, `path`, `text`, `tspan`, `circle`, `ellipse`, `defs`, `marker` **and `style`** are all
allowed (`script` is not). Mermaid's injected `<style>` element — which is where _all_
railroad styling lives — **survives GitHub's sanitizer intact.**

### 1.3 A lovely detail worth knowing

GitHub calls `mermaid.render("diagram", src, templateEl)` with a `<template>` element as the
measuring container. A `<template>` is inert (`display:none`), so SVG `getBBox()` inside it
returns **zero** and every text-measured diagram collapses (I reproduced this: railroad rects
shrink 104px → 20px; flowchart viewBox collapses to `-8 -8 16 16`). GitHub defeats this
deliberately, in `mermaid-a1eea15eae7bd19ad131.css`:

```css
#mermaid-view-template {
  display: block;
  border: 1px solid var(--borderColor-muted);
  min-width: 1600px;
}
```

A `<template>` forced to `display:block` at 1600px, purely as a text-measuring surface. Any
faithful local reproduction of GitHub's pipeline **must** include this rule or it will
mislead you into thinking Mermaid is broken on GitHub.

---

## 2. The find: `railroad-beta` _is_ a ladder renderer

§24 evaluated `flowchart` (category error) and `block-beta` (no centering) and stopped.
It missed the one Mermaid diagram type that is **structurally the same object as a ladder**.

Railroad/syntax diagrams are series-parallel graphs drawn on a single axis: **concatenation =
series on one wire; alternation = stacked rungs fanning off a common node; no arrowheads; no
implied sequence; power terminals at both ends.** That is the ladder, under a different name.
The grammar has exactly the eight constructors we need — and the mapping is an isomorphism:

| L4 `IRExpr`                    | railroad-beta                                    |
| ------------------------------ | ------------------------------------------------ |
| `And [a,b,c]` (series)         | `sequence(a, b, c)`                              |
| `Or [a,b,c]` (parallel)        | `choice(a, b, c)`                                |
| `Leaf` (operative atom, boxed) | `nonterminal("…")` — a rect                      |
| `InertE` (grammatical glue)    | `terminal("…")` — restylable to _unboxed_        |
| eliminable / tentative         | `special("…")` — a **dashed** box (but see §4.3) |
| `Not`                          | **— nothing —**                                  |

### 2.1 Align-then-stack centering: present, exact, compositional

This is the headline. I parsed the emitted SVG transforms rather than eyeballing.
For `sequence(a, choice(sequence(b, choice(c1,c2,c3)), sequence(d,e), f), g)`:

```
main axis (start/end markers)  y = 113.5
inner choice branches          c1 y=19.5   c2 y=66.5   c3 y=113.5   → span centre = 66.5
  b (its series partner)       y = 66.5   ✓ exactly on the inner axis
outer choice bbox              y = 0 … 227                          → bbox centre = 113.5
  a, g (its series partners)   y = 113.5  ✓ exactly on the outer axis
```

Mermaid's railroad centres a `choice` on **the vertical centre of its own bounding box**, and
the parent `sequence` aligns its members to that axis — which is precisely DESIGN §5.3
("align, then stack") and §5.4 (the compound-nesting invariant), and it composes at arbitrary
depth. **The exact property Dagre could not do, and that this whole kernel was rebuilt to fix,
Mermaid's railroad renderer already has.** (`deep.png`)

---

## 3. Best attempt A — hand-written, no build step (the honest middle path)

The GPDO window rule from `logic-not-flowcharts.md`, hand-written, ~4 lines of Mermaid,
renders on github.com with zero tooling. **Rendered: `mermaid-planb/GH-honest-gpdo.png`**

````markdown
```mermaid
---
config:
  railroad:
    nonTerminalFill: "#ffffff"
    nonTerminalStroke: "#2f7a3f"
    nonTerminalTextColor: "#111111"
    terminalFill: "transparent"      # <- makes inert prose UNBOXED
    terminalStroke: "transparent"
    terminalTextColor: "#888888"
    lineColor: "#8a8a8a"
    markerFill: "#222222"
    strokeWidth: 1.5
    fontSize: 15
---
railroad-beta
A3_covers = sequence(nonterminal("on an upper floor"), choice(nonterminal("in a wall"), nonterminal("in a roof slope forming a side elevation")));
A3_requirement_met = sequence(nonterminal("obscure-glazed"), choice(nonterminal("non-opening"), nonterminal("openable parts at least 1.7m above the floor")));
```
````

Gets you: correct AND/OR topology, exact centering, no arrowheads, no invented sequence,
boxed operative atoms, power terminals, DAG-free reading. Loses everything in §5's table.
**Critically, it cannot draw `P → Q`** — see §4.1.

## 4. Best attempt B — generated, maximum fidelity

**Rendered: `mermaid-planb/GH-s415-full.png`** · source `mermaid-planb/s415-full.mmd` ·
generator `mermaid-planb/gen2.mjs`

The escape hatch: Mermaid's `themeCSS` config injects **arbitrary CSS** into the diagram's
`<style>`, it is not in GitHub's `secure` list, and it survives DOMPurify. Railroad's emitted
`<g>` tree **mirrors the AST exactly**, so a generator can address every node by structural
path (`.railroad-choice:nth-of-type(6) .railroad-nonterminal:nth-of-type(2)` = `mind`) and
style it individually. That restores, on github.com:

- per-leaf **state colour** (live green / unknown grey)
- **ELIMINABLE** ghost rung (§15) — dashed box _and_ dashed ghost fan-curves
- **TYPICALLY / tentative** (§22) — amber fine-dash on `mind`
- **unboxed inert prose** (§17), italic, grey
- **current flow** (§20) — leader thick+black down the spine and through `body`'s fan,
  streamer weight on the presumed rung, open rungs thin+light

That is a genuinely high-fidelity s415 ladder, in a ```mermaid fence, on github.com.

### 4.1 The hard walls (evidenced)

**`NOT` does not exist, and the nearest hack is _actively wrong_.** (`GH-not.png`)
The best available encoding, `special("NOT")`, renders `? NOT ?` as **a box in series** —
i.e. it reads as a _conjunct_, with no scope whatsoever. A reader cannot tell whether the NOT
governs the following choice or not. §21's scope frame and inverter bubble are unreachable
(no enclosure primitive, no per-edge inversion).

**Consequence: the document's own headline example is undrawable.** A.3 is a material
conditional `P → Q ≡ ¬P ∨ Q`. With no `NOT`, railroad can draw `P` and `Q` as two disconnected
rules and nothing else. The `→` — "the thing a lawyer must actually verify" — is exactly what
is lost. That is a _very_ citable fact for §24.

**No text wrapping.** (`wrap-test.png`) `\n` in a label is ignored; there is no `wrap`/
`maxWidth` in the config key set. Long statutory prose therefore runs on one line and blows the
diagram out horizontally — §17's straddle-wire, which exists precisely to halve that footprint,
has no analogue. Real statutes will need horizontal scrolling on github.com.

**`themeCSS` is destroyed by a single `>`.** Bisected: mermaid's `antiscript` directive
sanitizer discards the **entire** `themeCSS` string if it contains one `<` or `>` — so **child
combinators are unusable** and every selector must be built from descendant combinators,
`:nth-of-type`, and `:not(.railroad-choice *)` depth guards. (Baseline style 3559 B; with a
`>`-free rule 3643 B; with any `>` anywhere → back to 3559 B, i.e. silently dropped.) There is
also no CSS-injection escape via `themeVariables`: those are gated by an anchored
`COLOR_VALUE_PATTERN` / `FONT_FAMILY_PATTERN`.

**No interactivity, ever.** Railroad has no `click`; GitHub's allowlist excludes `<script>`.
Folding (§16), T/F/U cycling (§19), hover, minimap: all impossible. The best available is a
`<details>` block holding a folded and an expanded fence — two static pictures, not a fold.

**Rule names must be identifiers.** `A.3 covers` / `window complies with A.3` are rejected
(`Expecting token of type '='`); you get `A3_covers`, and it is rendered as `A3_covers =`,
which reads as an assignment, not a legal name.

**No dark-mode adaptation** once `themeCSS` hardcodes colours (GitHub flips
`theme: dark|default` by `data-color-mode`; our overrides win in both).

---

## 5. Fidelity table

Verified against GitHub's exact pipeline (§7). ✅ works · ⚠️ degraded · ❌ impossible.

| Ladder property                                 | Hand-written (A) | Generated `themeCSS` (B) | Note                                                                                                                                                                   |
| ----------------------------------------------- | :--------------: | :----------------------: | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **align-then-stack centering** (§5.3/5.4)       |        ✅        |            ✅            | exact, compositional, at depth                                                                                                                                         |
| series (AND) = one wire, L→R                    |        ✅        |            ✅            | `sequence`                                                                                                                                                             |
| parallel (OR) = stacked rungs, common node      |        ✅        |            ✅            | `choice`                                                                                                                                                               |
| no arrowheads / no implied sequence             |        ✅        |            ✅            |                                                                                                                                                                        |
| power terminals                                 |        ✅        |            ✅            | `markerFill`, `showMarkers`                                                                                                                                            |
| curved fan connectors (§18)                     |        ⚠️        |            ⚠️            | arcs+lines, not cubic Béziers; close enough                                                                                                                            |
| boxed operative atoms                           |        ✅        |            ✅            | `nonterminal`                                                                                                                                                          |
| **unboxed inert text** (§17)                    |        ⚠️        |            ⚠️            | achievable, but the wire **breaks** around it — i.e. forced into the `on-wire` style §17 explicitly discourages ("its gap reads like a contact, which inert never is") |
| OR heading / `Pre` (§5.6, §17)                  |        ❌        |            ❌            | no primitive; `.railroad-comment` exists in the CSS but is **dead code** — no parser path emits it                                                                     |
| medial connective ("or" between rungs)          |        ❌        |            ❌            | same                                                                                                                                                                   |
| long-prose wrapping / straddle-wire (§17)       |        ❌        |            ❌            | no wrap; diagrams run wide                                                                                                                                             |
| state colour live/inert/dead (§15)              |        ❌        |            ✅            | needs generated CSS                                                                                                                                                    |
| ELIMINABLE ghost rung (§15)                     |        ❌        |            ✅            | dashed box + dashed fan                                                                                                                                                |
| TYPICALLY / tentative (§22)                     |        ❌        |            ✅            | fine-dash + amber                                                                                                                                                      |
| current-flow weights (§20)                      |        ❌        |            ✅            | `stroke-width` is global in config, but per-path via `themeCSS`                                                                                                        |
| **NOT** — scope frame + bubble (§21)            |        ❌        |            ❌            | **no primitive; the hack is semantically wrong**                                                                                                                       |
| **material conditional `P → Q`**                |        ❌        |            ❌            | follows from NOT                                                                                                                                                       |
| folding / progressive disclosure (§16)          |        ❌        |            ❌            | `<details>` = two static pictures                                                                                                                                      |
| T/F/U click, hover, eval, minimap (§19)         |        ❌        |            ❌            | no `click`; `<script>` stripped                                                                                                                                        |
| Full/Small/Tiny scales (§7)                     |        ❌        |            ❌            | `fontSize` only                                                                                                                                                        |
| print / A3 / PDF (target D)                     |        ❌        |            ❌            | browser-bound; no headless path                                                                                                                                        |
| dark/light adaptive                             |        ✅        |            ❌            | `themeCSS` pins colours                                                                                                                                                |
| **source lives in the Markdown, no build step** |        ✅        |            ❌            | (B) is 3.4 KB of generated CSS                                                                                                                                         |

Also tried and rejected: **`block-beta`** (`GH-block.png`) — no rails, no fan, no centering;
children stretch/left-align inside the group; it draws two adjacent containers, exactly the
§24 prediction. **`flowchart`/`flowchart-elk`** (`GH-flowchart.png`) — the category error made
visible: invented sequence, arrowheads, and `permitted` duplicated three times because the
AND/OR tree has been linearised. Keep that image; it is a _better_ illustration of the thesis
than anything we could draw by hand.

---

## 6. Verdict & recommendation

**It can be done — and that is precisely why we still shouldn't.**

The decisive argument is not "Mermaid can't". It's **the build-step dilemma**:

- **The hand-written ladder (A)** is the only version that delivers Mermaid's _one_ real
  prize — _source in the Markdown, renders on github.com, zero build step_. But it cannot draw
  `NOT`, and therefore cannot draw the **material conditional**, which is the entire subject of
  `logic-not-flowcharts.md`. Illustrating "the law here is a material conditional `P → Q`" with
  a picture that structurally cannot express `→` is a worse self-refutation than the flowchart
  one §24 warned about.

- **The generated ladder (B)** reaches ~70% fidelity — but it needs a **code generator** emitting
  3.4 KB of positional, `>`-free CSS whose `nth-of-type` indices silently mis-style every node
  if anyone edits the tree. And the moment you accept a build step, **§24's option I-a (generate
  and commit an SVG) strictly dominates**: same build step, _zero_ fidelity loss, plus print,
  plus `<picture>` dark-mode, plus it works in npm/VS Code/PDF. Mermaid's _only_ advantage is
  "no build step", and (B) spends exactly that to buy a strictly worse picture.

So: **do not ship a Mermaid ladder.** Not because it's impossible — it is surprisingly
possible — but because the version that's worth having isn't hand-writable, and the version
that's hand-writable can't say `→`.

### What to change in §24

1. **Delete the factual claims** that GitHub pins an old Mermaid and may sanitize `%%{init}%%`.
   Both are false and will embarrass us. GitHub ships **11.16.0**, current, with the full
   registry, and honours `themeCSS`.
2. **Replace §24.2(b)'s reasoning.** "block-beta won't centre" is true but is _not_ the
   interesting objection, and it's the wrong diagram type to have tested. The real chapter and
   verse is:
   > Mermaid's `railroad-beta` _is_ a ladder renderer — it even does align-then-stack centring
   > exactly, at depth. It has no **NOT**, therefore no scope frame (§21) and no material
   > conditional; no text wrapping (§17); and no per-node styling except through generated,
   > `>`-free `themeCSS`. So a _hand-written_ Mermaid ladder cannot draw the very rule this
   > document is about, and a _generated_ one concedes the build step that makes committed SVG
   > (I-a) strictly better in every dimension. **Mermaid never — and now we know exactly why.**
3. **Keep `GH-flowchart.png`** and consider actually putting it in `logic-not-flowcharts.md` as
   the "wrong picture" exhibit, beside the ladder. The document currently _asserts_ the
   linearisation damage; that image _shows_ it (`permitted` × 3).
4. Optional: if we ever want a Mermaid fallback, the honest one is (A) restricted to
   NOT-free subtrees — e.g. render `A.3 covers` and `A.3 requirement met` as two railroads and
   state the `→` in prose. Better than nothing on a PR comment; **not** good enough for the
   document that makes the argument.

### One genuinely reusable idea

Mermaid's railroad renderer independently arrived at BBE's centring rule. If we ever want an
external sanity-check on `ladder-core`'s layout, `railroad-beta` is a free oracle for the
AND/OR-only subset.

---

## 7. Method / reproducibility

Everything above was rendered through a **faithful replay of GitHub's pipeline**, not through
plain `mmdc`, because they differ:

- `mermaid@11.16.0` — the version I verified GitHub ships (identical detector registry).
- GitHub's **exact `initialize()` options**, incl. its `secure` list, scraped from
  `mermaidMarkdown-a1eea15eae7bd19ad131.js`.
- GitHub's **exact DOMPurify call** — the 102-tag `ALLOWED_TAGS` allowlist scraped from the
  same bundle, plus `ADD_ATTR: ["transform-origin","dominant-baseline"]`.
- GitHub's **`#mermaid-view-template{display:block;min-width:1600px}`** measuring-surface CSS
  (`mermaid-planb/gh-viewscreen.css`), without which everything collapses.

Harness: `mermaid-planb/ghsim.mjs` (`node ghsim.mjs <file>.mmd <out>.png`). Every image in
`mermaid-planb/` prefixed `GH-` came out of it, and reports `styleKept: true` with nothing
stripped but the `<body>` wrapper.

**Honest caveat (unverified):** I was denied browser permission, so I did not load
github.com and look at a rendered fence with my own eyes. The simulation above is as faithful
as I could make it — same version, same config, same sanitizer, same measuring CSS, and I found
no diagram-type allowlist in GitHub's wrapper — but the final "seen on github.com" step is
outstanding. To close it: paste `mermaid-planb/honest.mmd`'s fence into any issue comment box
and hit **Preview** (renders without submitting), or run ` ```mermaid ` + `info` to print the
deployed version.
