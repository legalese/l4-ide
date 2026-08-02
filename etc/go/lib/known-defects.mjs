#!/usr/bin/env node
// Run a group of measured defects as negative controls against an artifact.
//
// The catalogue is per subject: etc/go/subjects/<id>/known-defects.json,
// reached through $GO_S_KNOWN_DEFECTS (exported by go.sh from the subject
// resolver). Defects are facts about ONE corpus, so they live in its sidecar.
//
// Usage: GO_S_KNOWN_DEFECTS=… node etc/go/lib/known-defects.mjs GROUP ARTIFACT.json
// Exit:  0 every defect in the group still reproduces (or the group is empty)
//        1 the artifact could not be read
//        2 usage / unknown group / no catalogue named
//        4 a defect STOPPED reproducing — delete the entry (see the ::error::)

import { existsSync, readFileSync } from "node:fs";

const CATALOGUE = process.env.GO_S_KNOWN_DEFECTS;

const CHECKS = {
  json_literal_count(artifactText, spec) {
    const re = new RegExp(
      spec.literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "g",
    );
    const n = (artifactText.match(re) || []).length;
    return {
      reproduces: n === spec.expect,
      observed: n,
      expected: spec.expect,
    };
  },
};

const [, , group, artifact] = process.argv;
if (!group || !artifact) {
  process.stderr.write("usage: known-defects.mjs GROUP ARTIFACT.json\n");
  process.exit(2);
}
if (!CATALOGUE || !existsSync(CATALOGUE)) {
  process.stderr.write(
    "known-defects.mjs: GO_S_KNOWN_DEFECTS must name the subject's known-defects.json (etc/go/subjects/<id>/); it is exported by go.sh from the subject resolver\n",
  );
  process.exit(2);
}
if (!existsSync(artifact)) {
  process.stderr.write(`known-defects.mjs: ${artifact} does not exist\n`);
  process.exit(1);
}

const catalogue = JSON.parse(readFileSync(CATALOGUE, "utf8"));
const g = catalogue[group];
if (!g) {
  process.stderr.write(
    `known-defects.mjs: no group '${group}' in ${CATALOGUE}\n`,
  );
  process.exit(2);
}

const text = readFileSync(artifact, "utf8");
if (!g.defects.length) {
  process.stdout.write(
    `known-defects[${group}]: group is empty — ${g.note ?? "no reason recorded"}\n`,
  );
  process.exit(0);
}

let stopped = 0;
for (const d of g.defects) {
  const check = CHECKS[d.check.kind];
  if (!check) {
    process.stderr.write(
      `known-defects.mjs: unknown check kind '${d.check.kind}' for ${d.id}\n`,
    );
    process.exit(2);
  }
  const r = check(text, d.check);
  if (r.reproduces) {
    process.stdout.write(
      `known-defects[${group}]: ${d.id} still reproduces (observed ${r.observed}, expected ${r.expected}) — ${d.description}\n`,
    );
  } else {
    stopped++;
    process.stdout.write(
      `::error::known-defects[${group}]: ${d.id} NO LONGER REPRODUCES (observed ${r.observed}, expected ${r.expected}).\n` +
        `  Measured ${g.measured_on} by: ${g.measured_by ?? "(unrecorded)"}\n` +
        `  ${d.description}\n` +
        `  DELETE this entry from ${CATALOGUE}. A negative control that no longer\n` +
        `  holds is a lie about what this leg measures, and leaving it in place turns a genuine\n` +
        `  improvement into a permanent red.\n`,
    );
  }
}

process.exit(stopped ? 4 : 0);
