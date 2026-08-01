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
// So: `l4 run` exits 0 on a failed #ASSERT, on a runtime exception, and on a
// Stuck evaluation. `ok` tracks TYPECHECKING only. The only machine-readable
// verdict is results[], and it must be parsed here rather than inferred from
// the process exit code.
//
// UPGRADE TRIPWIRE. `l4 run --fail-on-assert` does not exist today
// (specs/todo/lexipedia-superset/CORPUS-TRACK.md proposes it). When it ships,
// this whole module is dead weight — and etc/go/phases/p6-tests.sh runs a
// deliberately-failing fixture whose CONTINUED exit-0 is asserted, so the day
// the CLI starts exiting 1 the tripwire goes red and tells you to delete this.
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
