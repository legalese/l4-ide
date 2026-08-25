/**
 * A drift guard for the committed Reg CF ladder figures.
 *
 * `figures/README.md` used to claim "Nothing is retyped, so nothing can
 * drift." That is true of the GENERATOR (`demo/regcf.ts` reads the corpus
 * through the LSP) and was false of the twenty-four committed FILES, which
 * nothing re-derived: `demo:regcf` is not wired into `turbo.json` and CI never
 * ran it, so the figures could sit stale beside a renamed corpus indefinitely.
 * The DMN and BPMN goldens do not have that hole — `cabal test` re-derives
 * them from the same corpus on every run.
 *
 * Regenerating here is not an option: the demo spawns `jl4-lsp`, which needs a
 * Haskell build CI's node job does not have. So this checks the property that
 * actually breaks, WITHOUT the LSP — every leaf label drawn in a figure must
 * still be findable in the corpus. A decision renamed, a field reworded or a
 * limb deleted in `regcf.l4` then fails here, naming the stale figure, instead
 * of shipping a diagram that quotes law the corpus no longer contains.
 *
 * What it deliberately does NOT check: layout, geometry, or that the figure is
 * the CURRENT projection of the corpus. A leaf ADDED to the L4 and absent from
 * the figure passes — the guard is one-directional. Run `npm run demo:regcf`
 * for the real thing.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");
const FIGURES = resolve(REPO, "jl4/examples/legal/regcf/figures");
const CORPUS = resolve(REPO, "jl4/examples/legal/regcf/regcf.l4");

/** The four carriers `demo/regcf.ts` writes for every subject. */
const CARRIERS = [".svg", ".txt", ".mmd", ".sentences"] as const;

const slugs = () =>
  [
    ...new Set(
      readdirSync(FIGURES)
        .filter((f) => f.startsWith("regcf-"))
        .map((f) => f.replace(/\.(svg|txt|mmd|sentences)$/, "")),
    ),
  ].sort();

/**
 * The labels inside the ASCII figure's boxes. A leaf is drawn as
 * `┤ <label>  ├`, so the box glyphs delimit it exactly; the inert chapeaux ride
 * the wire as bare text and are not boxed, which is why they are not checked
 * here (they are quoted CFR prose, and `regcf.l4` holds them as string
 * literals that the ASCII renderer re-wraps).
 */
function boxedLabels(ascii: string): string[] {
  const out: string[] = [];
  for (const m of ascii.matchAll(/┤\s(.+?)\s+├/gu)) out.push(m[1].trim());
  return out;
}

test("every subject has all four carriers", () => {
  const names = readdirSync(FIGURES);
  for (const slug of slugs()) {
    for (const ext of CARRIERS) {
      assert.ok(
        names.includes(slug + ext),
        `${slug} is missing its ${ext} carrier — re-run \`npm run demo:regcf\``,
      );
    }
  }
});

test("there are figures at all (an empty directory must not pass)", () => {
  assert.ok(
    slugs().length >= 6,
    `expected >= 6 subjects, saw ${slugs().length}`,
  );
});

test("every boxed leaf label in a figure is still present in regcf.l4", () => {
  const corpus = readFileSync(CORPUS, "utf8");
  const stale: string[] = [];
  let checked = 0;

  for (const slug of slugs()) {
    for (const label of boxedLabels(
      readFileSync(`${FIGURES}/${slug}.txt`, "utf8"),
    )) {
      checked++;
      // The figure prints `transfer's `is to …``; the corpus writes the same
      // selector application, but may break the line between the two halves.
      // Compare on the backticked identifier, which is the part a rename
      // changes and which the corpus always keeps on one line.
      const ident = label.match(/`([^`]+)`/u)?.[1] ?? label;
      if (!corpus.includes(ident)) stale.push(`${slug}.txt: ${label}`);
    }
  }

  assert.ok(
    checked > 0,
    "no boxed labels were found — has the ASCII format changed?",
  );
  assert.deepEqual(
    stale,
    [],
    `figure labels no longer in regcf.l4 — the corpus moved and the figures did not.\n` +
      `Re-run \`npm run demo:regcf\` (needs jl4-lsp):\n  ${stale.join("\n  ")}`,
  );
});

test("every sentence file names the decision it expands, and that decision is in regcf.l4", () => {
  const corpus = readFileSync(CORPUS, "utf8");
  for (const slug of slugs()) {
    const [title] = readFileSync(`${FIGURES}/${slug}.sentences`, "utf8").split(
      "\n",
    );
    assert.ok(title.length > 0, `${slug}.sentences has no title line`);
    assert.ok(
      corpus.includes(title),
      `${slug}.sentences is headed "${title}", which regcf.l4 no longer defines`,
    );
  }
});
