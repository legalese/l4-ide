// The status lattice, and the rules that stop a status from being nicer than
// the evidence behind it.
//
// This module is pure: it reads no files, spawns nothing, and never writes.
// It exists so that exactly one place in the tree decides what "PASS" means,
// and so that etc/go/selftest.mjs can attack that decision directly.
//
// The governing invariant of the whole orchestrator: a status is a function of
// bytes on disk, not of an agent's assertion. Everything below is the
// enforcement of that sentence.

/** Every terminal status a stage may carry. Only the first is green. */
export const STATUSES = [
  // an oracle ran, returned 0, and named an artifact whose sha256 is recorded
  "PASS",
  // the artifact was produced, but a part of it that the spec mandates is
  // missing or wrong; the run continues and the report says what is missing
  "DEGRADED",
  // the artifact was produced and cannot be executed by its own engine
  "NOT-EXECUTABLE",
  // the artifact exists in the tree but THIS run did not produce it, because
  // no reachable command produces it
  "NOT-REGENERATED",
  // the artifact exists and no oracle for it exists, or the oracle that exists
  // is too weak to license PASS (see ORACLE_CLASSES)
  "UNVERIFIED",
  // the capability is named by a spec and has no implementation at all
  "NOT-BUILT",
  // the machine lacks a named prerequisite; forgiven unless L4_GO_REQUIRED=1
  "SKIPPED",
  // the harness itself is defective. A repo defect. Fatal everywhere.
  "BROKEN",
];

/**
 * How much a passing oracle actually proves.
 *
 * The point of this enum is a failure mode the seven-status lattice does not
 * catch on its own: nothing stops a leg from declaring a *weak* oracle and
 * collecting a PASS. XML well-formedness proves an AKN file parses; it proves
 * nothing about whether it says what the statute says. `dmn-moddle` parsing a
 * DMN proves the same little. So the class rides on the receipt and the two
 * weak classes are structurally barred from PASS.
 */
export const ORACLE_CLASSES = {
  // the artifact was run by the engine it targets, on cases, and agreed
  execution: { sufficient: true },
  // the artifact was compared byte-for-byte (after declared canonicalisation)
  // against a committed golden that some other gate already defends
  differential: { sufficient: true },
  // a checker that models the artifact's semantics — soundness, exhaustiveness,
  // a counted invariant cross-checked against an independent source
  structural: { sufficient: true },
  // the artifact parses. Caps at UNVERIFIED.
  wellformedness: { sufficient: false },
  // the artifact exists and is non-empty. Caps at UNVERIFIED.
  presence: { sufficient: false },
};

/** Statuses that must name what is blocking them, not merely give a reason. */
const NEEDS_BLOCKER = new Set([
  "NOT-EXECUTABLE",
  "NOT-REGENERATED",
  "NOT-BUILT",
]);

/**
 * Validate one stage receipt. Returns an array of violation strings; empty
 * means the receipt may be written.
 *
 * Callers treat a non-empty return as exit 4 (BROKEN): a receipt that does not
 * satisfy these rules is a defect in the phase script, not a finding about the
 * corpus.
 */
export function checkReceipt(r) {
  const bad = [];
  const push = (m) => bad.push(m);

  if (!r || typeof r !== "object") return ["receipt is not an object"];
  if (!r.stage) push("receipt has no stage id");
  if (!STATUSES.includes(r.status))
    push(
      `unknown status ${JSON.stringify(r.status)}; expected one of ${STATUSES.join(", ")}`,
    );

  const artifacts = Array.isArray(r.artifacts) ? r.artifacts : [];
  for (const a of artifacts) {
    if (!a.path) push("an artifact entry has no path");
    if (!a.sha256)
      push(
        `artifact ${a.path} has no sha256; a status may not point at an unhashed file`,
      );
  }

  // A REPLAYED receipt carries no oracle of its own, and that is correct: the
  // oracle ran, on inputs whose digest is identical, and its receipt is named
  // by `replayed_from` in the same hash-chained journal. The evidence for a
  // replayed PASS is that earlier row, which `go.sh verify` re-checks.
  //
  // The alternative — demoting a replayed PASS to UNVERIFIED — was tried and is
  // wrong: it makes the milestone verdict change when you run the same
  // milestone twice, which destroys the idempotence property that makes
  // resumability meaningful.
  const replayed = !!(r.replayed_from && String(r.replayed_from).trim());

  if (r.status === "PASS" && replayed) {
    if (artifacts.length === 0 && !r.replayed_from)
      push(
        "replayed PASS naming neither an artifact nor the receipt it replays",
      );
  } else if (r.status === "PASS") {
    // Rule 1 — PASS requires an oracle that ran and returned 0.
    if (!r.oracle)
      push("PASS with no oracle: a status may not be asserted, only measured");
    else {
      if (r.oracle.exit !== 0) push(`PASS with oracle exit ${r.oracle.exit}`);
      if (!r.oracle.cmd) push("PASS with an oracle that records no command");
      const cls = ORACLE_CLASSES[r.oracle.class];
      if (!cls)
        push(
          `PASS with unknown oracle class ${JSON.stringify(r.oracle.class)}`,
        );
      // Rule 6 — a weak oracle caps at UNVERIFIED.
      else if (!cls.sufficient)
        push(
          `PASS with a ${r.oracle.class} oracle: that class proves the artifact is well formed, not that it is right; the strongest available status is UNVERIFIED`,
        );
    }
    // Rule 2 — PASS requires something on disk to point at.
    if (artifacts.length === 0)
      push("PASS with no artifact on disk to point at");
  } else {
    // Rule 3 — every non-PASS status explains itself, in the report's words.
    if (!r.reason || !String(r.reason).trim())
      push(
        `${r.status} with no reason string; the report has nothing to print`,
      );
  }

  if (NEEDS_BLOCKER.has(r.status) && !(r.blocker && String(r.blocker).trim()))
    push(`${r.status} with no blocker field naming the missing thing`);

  if (r.oracle && r.oracle.class && !ORACLE_CLASSES[r.oracle.class])
    push(`unknown oracle class ${JSON.stringify(r.oracle.class)}`);

  return bad;
}

/**
 * The milestone rule.
 *
 * G1 is *completeness of accounting, not greenness* — which is what SPEC.md §6
 * actually asks for ("DMN may still be non-executable at G1 only if the report
 * says so in Blocking terms"). A milestone is COMPLETE when every declared leg
 * has a receipt, nothing is BROKEN, every non-PASS receipt carries a reason,
 * and every gate is either signed or explicitly waived on the record.
 */
export function milestoneVerdict({ declared, receipts, gates }) {
  const byStage = new Map();
  for (const r of receipts) byStage.set(r.stage, r);

  // A milestone that declares nothing is not a completed milestone, it is an
  // unstarted one. Without this, an EMPTY journal satisfies every clause of the
  // rule below vacuously and reports COMPLETE — the exact vacuous-pass failure
  // this lattice exists to refuse everywhere else.
  if (!declared.length)
    return {
      verdict: "INCOMPLETE",
      exit: 1,
      missing: [],
      broken: [],
      unexplained: [],
      ungated: [],
      note: "no stages declared: the run has a journal but no run_begin naming what it was supposed to do",
    };

  const missing = declared.filter((s) => !byStage.has(s));
  const broken = receipts.filter((r) => r.status === "BROKEN");
  const unexplained = receipts.filter(
    (r) => r.status !== "PASS" && !(r.reason && String(r.reason).trim()),
  );
  const ungated = (gates || []).filter(
    (g) => g.state !== "satisfied" && g.state !== "waived",
  );

  if (broken.length)
    return {
      verdict: "BROKEN",
      exit: 4,
      missing,
      broken,
      unexplained,
      ungated,
    };
  if (ungated.length)
    return { verdict: "GATE", exit: 3, missing, broken, unexplained, ungated };
  if (missing.length || unexplained.length)
    return {
      verdict: "INCOMPLETE",
      exit: 1,
      missing,
      broken,
      unexplained,
      ungated,
    };
  return {
    verdict: "COMPLETE",
    exit: 0,
    missing,
    broken,
    unexplained,
    ungated,
  };
}

/** Exit codes, extending etc/check-bpmn-kie.sh's 0/1/2/3/4. */
export const EXIT = {
  CLEAN: 0,
  FINDING: 1,
  USAGE: 2,
  GATE: 3,
  BROKEN: 4,
  SKIPPED_WHILE_REQUIRED: 5,
};
