#!/usr/bin/env node
// The `l4 run` exit-code workaround, isolated so it can be attacked directly.
//
// MEASURED, 2026-08-02, against the prebuilt binary:
//
//   $ l4 run /tmp/failing.l4 --json      # file contains  #ASSERT `double` 21 EQUALS 43
//   {"diagnostics":[…"assertion failed"…],"ok":true,
//    "results":[{"kind":"assertion","range":"failing.l4:5:1-30","value":false}]}
//   $ echo $?
//   0
//
// That binary exited 0 on a failed #ASSERT — a clean FALSE — with ok:true, and
// that is the case this module was written for. Since 2026-09-29 (ruled by
// Meng) `l4 run` exits 1 with ok:false on a failed #ASSERT too, as it already
// did on a directive that CRASHES: a raising #EVAL (kind "error"), or an
// #ASSERT that raises or is stuck on an assumed term (kind "assertion", value
// null, the reason under "error"). The envelope is written in every case.
//
// This module still reads results[] rather than the exit code. The exit code
// cannot say WHICH directive failed, and it cannot count assertions, which
// p6-tests' floor (min_assertions) and its vacuous-pass guard need: a module
// with no #ASSERT at all also exits 0. Reading results[] also keeps the stage
// correct on a binary built before 2026-09-29.
//
// etc/go/phases/p0-preflight.sh checks the contract this module relies on: a
// deliberately failing fixture comes back as one assertion with value false.
//
// Usage:  node etc/go/lib/assert-report.mjs RUN.json [RUN.json…] [--json]
// Exit:   0 every assertion true and no error result · 1 a finding · 2 usage

import { readFileSync } from "node:fs";

export function analyse(envelope) {
  const results = Array.isArray(envelope?.results) ? envelope.results : [];
  const failedAssertions = results.filter(
    (r) => r.kind === "assertion" && r.value !== true,
  );
  const errors = results.filter((r) => r.kind === "error");
  const assertions = results.filter((r) => r.kind === "assertion");
  const values = results.filter((r) => r.kind === "value");
  return {
    file: envelope?.file ?? null,
    // `ok` is recorded so the report can show it, and explicitly NOT consulted.
    typecheck_ok: envelope?.ok === true,
    assertions_total: assertions.length,
    assertions_failed: failedAssertions.length,
    values_total: values.length,
    errors_total: errors.length,
    failures: [...failedAssertions, ...errors].map((r) => ({
      kind: r.kind,
      range: r.range ?? null,
      value: r.value ?? null,
    })),
    ok: failedAssertions.length === 0 && errors.length === 0,
  };
}

export function analyseFile(path) {
  return analyse(JSON.parse(readFileSync(path, "utf8")));
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const files = args.filter((a) => !a.startsWith("--"));
  if (files.length === 0) {
    process.stderr.write(
      "usage: assert-report.mjs RUN.json [RUN.json…] [--json]\n",
    );
    process.exit(2);
  }
  const reports = files.map(analyseFile);
  if (asJson) {
    process.stdout.write(JSON.stringify(reports, null, 2) + "\n");
  } else {
    for (const r of reports) {
      const verdict = r.ok ? "OK" : "FINDING";
      process.stdout.write(
        `${verdict} ${r.file ?? "(unnamed)"} — ${r.assertions_total} assertions, ${r.assertions_failed} failed; ${r.values_total} values; ${r.errors_total} errors\n`,
      );
      for (const f of r.failures)
        process.stdout.write(
          `  ${f.kind} at ${f.range}: ${JSON.stringify(f.value)}\n`,
        );
    }
  }
  process.exit(reports.every((r) => r.ok) ? 0 : 1);
}
