/**
 * B2 — real-module provenance test, against a GOLDEN captured from the live LSP.
 *
 * `fixtures/may-purchase-alcohol.viz.json` is the actual `RenderAsLadderInfo.funDecl`
 * emitted by a running `jl4-lsp` (ws mode, built from the #110 tree) for the
 * exported decision `may purchase alcohol` in `jl4/examples/ok/typically-basic.l4`:
 *
 *     GIVEN b                       IS A Buyer
 *           `has spousal approval`  IS A BOOLEAN TYPICALLY FALSE
 *           `beer only`             IS A BOOLEAN
 *           `has parental approval` IS A BOOLEAN TYPICALLY FALSE
 *     ASSUME `person has capacity`  IS A BOOLEAN TYPICALLY TRUE
 *     DECLARE Buyer HAS `of age`    IS A BOOLEAN TYPICALLY TRUE   -- a FIELD default
 *     DECIDE `may purchase alcohol` IF
 *           `person has capacity`
 *       AND ( b's `of age` OR `has parental approval` OR `has spousal approval` )
 *
 * It was captured by driving the real ws LSP with an LSP JSON-RPC client
 * (initialize → didOpen → textDocument/codeLens → workspace/executeCommand
 * "Show decision graph"). This is the genuine A2 transport output, not a
 * hand-authored fixture — so it pins the real #110 producer ⇄ ladder-core adapter
 * contract end to end. Node ids below are the LSP's own: capacity=3, of-age=5,
 * parental=7, spousal=8.
 *
 * The `typically` field the LSP actually emitted (verified in the golden):
 *   - `person has capacity`  → true   (ASSUME, boolean TYPICALLY TRUE)
 *   - `has parental approval`→ false  (GIVEN,  boolean TYPICALLY FALSE)
 *   - `has spousal approval` → false  (GIVEN,  boolean TYPICALLY FALSE)
 *   - `b's of age`           → null   (a Buyer FIELD default reached via projection —
 *                                      NOT a direct GIVEN/ASSUME binder, so #110's
 *                                      collectTypicallyDefaults skips it: spec §4).
 * (The sibling decision `can vote` likewise emits `typically: null` on its numeric
 *  `age AT LEAST 18` atom — a numeric TYPICALLY is not a boolean prior.)
 *
 * This test validates the ladder-core CONSUMER end: provenance must mark exactly
 * the three boolean GIVEN/ASSUME TYPICALLYs `default`, and leave the field-
 * projection atom `given`.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import type { FunDecl as VizFunDecl } from "@repo/viz-expr";
import { fromVizFunDecl } from "../src/viz-adapter.js";
import { layout, estimateMetrics, defaultViewSpec } from "../src/index.js";

const mayPurchaseAlcohol = JSON.parse(
  readFileSync(
    new URL("./fixtures/may-purchase-alcohol.viz.json", import.meta.url),
    "utf8",
  ),
) as VizFunDecl;

test("real LSP golden: provenance marks exactly the GIVEN/ASSUME boolean TYPICALLYs", () => {
  const { fn, provenance } = fromVizFunDecl(mayPurchaseAlcohol);
  assert.equal(fn.name, "`may purchase alcohol`");
  // the three direct boolean binders carrying a TYPICALLY are `default`...
  assert.equal(provenance.get(3), "default", "capacity: ASSUME TYPICALLY TRUE");
  assert.equal(
    provenance.get(7),
    "default",
    "parental: GIVEN TYPICALLY FALSE (a false default is still a default)",
  );
  assert.equal(provenance.get(8), "default", "spousal: GIVEN TYPICALLY FALSE");
  // ...and the field-projection atom is NOT (typically:null => given): the
  // spec §4 boolean-GIVEN/ASSUME-only wrinkle, straight from the real LSP.
  assert.equal(
    provenance.has(5),
    false,
    "b's of age: Buyer field default, not a direct binder => null => given",
  );
  assert.equal(
    provenance.size,
    3,
    "exactly the three GIVEN/ASSUME boolean TYPICALLYs, no more",
  );
});

test("real LSP golden: no valuation yet, and the tree flows through layout()", () => {
  const { fn, valuation, provenance } = fromVizFunDecl(mayPurchaseAlcohol);
  assert.equal(valuation.size, 0, "all UnknownV => no valuation entries");
  const scene = layout(
    fn,
    defaultViewSpec({ valuation, provenance }),
    estimateMetrics,
  );
  assert.ok(scene.prims.length > 0, "renders");
  assert.ok(scene.size.w > 0 && scene.size.h > 0, "has extent");
});
