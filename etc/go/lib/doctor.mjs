#!/usr/bin/env node
// The front-door forecast. Answers, BEFORE any stage spends time: which of
// this run's declared stages will run whole, which will SKIP or run partial,
// and what the one deliverable a reader cares about (the explainer) will be
// missing as a result.
//
// Why this exists, measured 2026-08-09: a full g1 needs five independently
// supplied prerequisites (l4, jl4-lsp, npm deps, a service URL, the library
// path), each discovered by a DIFFERENT stage at run time. Every stage's
// refusal was honest and carried its remedy — and the caller still learned
// them one ten-minute run at a time. This module is the five-line aggregation
// of checks that all already existed, printed first.
//
// It FORECASTS; it does not decide. The per-stage receipts remain the record
// of what actually happened — a forecast row here licenses nothing and is
// attested nowhere. That is also why the checks here must stay derived from
// the same sources the stages read (probe.mjs, the GO_S_* sidecar env): a
// forecast computed from a private copy of the rules would drift into lying
// about what the stages will do.
//
// Usage (driven by go.sh; env is the interface):
//   node etc/go/lib/doctor.mjs --milestone g1 --stages "p0-preflight p3-check …" [--brief]
//
// Reads: L4, GO_L4_PROVENANCE, JL4_LSP_CMD, GO_LSP_PROVENANCE,
//        JL4_GO_SERVICE_URL, JL4_LIBRARY_PATH, GO_S_* (subject sidecar).
// Exit:  0 every declared stage will run whole
//        1 at least one declared stage will SKIP / run partial / likely break
//        2 the run cannot start at all (no usable l4)

import { accessSync, constants } from "node:fs";
import { createRequire } from "node:module";
import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { probeAll } from "./probe.mjs";

const args = process.argv.slice(2);
const arg = (name, dflt = "") => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : dflt;
};
const BRIEF = args.includes("--brief");
const MILESTONE = arg("--milestone", "g1");
const STAGES = arg("--stages", "").split(/\s+/).filter(Boolean);
const env = process.env;

const declared = (s) => STAGES.includes(s);

const executable = (p) => {
  if (!p) return false;
  try {
    accessSync(p, constants.X_OK);
    return true;
  } catch {
    // Not a path — maybe a command name on PATH, which go.sh also accepts.
    const r = spawnSync("command", ["-v", p], { shell: true });
    return r.status === 0;
  }
};

// resolvable(pkg, dirs) — can `npm run` / `npx` in one of these directories
// see the package? Workspaces hoist, so the repo root is always a fallback.
const resolvable = (pkg, dirs) => {
  for (const d of dirs.filter(Boolean)) {
    try {
      createRequire(resolve(d, "package.json")).resolve(pkg);
      return true;
    } catch {
      /* try the next root */
    }
  }
  return false;
};

const probes = probeAll();
const findings = []; // {stage, what, remedy} — these drive exit 1
const notes = []; // informational; never change the exit code

// --- the one fatal prerequisite: a usable l4 --------------------------------
if (!executable(env.L4)) {
  const why =
    env.GO_L4_PROVENANCE === "none"
      ? "L4 is unset and no built l4 was discovered under dist-newstyle in this worktree or its siblings"
      : `L4=${env.L4 ?? ""} is not executable and not on PATH`;
  process.stdout.write(`doctor: CANNOT RUN — ${why}.\n`);
  process.stdout.write(
    "doctor:   remedy: build one in a DIFFERENT worktree (one cabal per worktree — the build\n" +
      "doctor:   lock, CLAUDE.md §2.1), or export L4=/path/to/dist-newstyle/build/<arch>/ghc-<v>/jl4-<v>/x/l4/build/l4/l4\n",
  );
  process.exit(2);
}

// --- per-leg forecasts, only for stages this run declares -------------------
if (declared("p7-ladder")) {
  if (!probes.npm?.present) {
    findings.push({
      stage: "p7-ladder",
      what: "will SKIP — npm is not on PATH and the ladder generator is an npm script",
      remedy: "install node/npm",
    });
  } else if (!env.JL4_LSP_CMD) {
    findings.push({
      stage: "p7-ladder",
      what: "will SKIP — JL4_LSP_CMD is unset and no built jl4-lsp was discovered; the explainer will inline NO ladder figures",
      remedy:
        "build jl4-lsp in another worktree, or export JL4_LSP_CMD=<dist-newstyle …/jl4-lsp>",
    });
  } else if (
    !resolvable("tsx", [env.GO_S_LADDER_NPM_DIR, env.GO_ROOT || process.cwd()])
  ) {
    findings.push({
      stage: "p7-ladder",
      what: "will SKIP — the generator runs under tsx and node_modules does not provide it",
      remedy: "npm ci at the repo root",
    });
  }
}

if (declared("p7-mcp") && !env.JL4_GO_SERVICE_URL) {
  findings.push({
    stage: "p7-mcp",
    what: "deploy half will SKIP — JL4_GO_SERVICE_URL is unset (the deployable zip is still built and hashed)",
    remedy:
      "bring up a LOOPBACK jl4-service (./dev-start.sh) and export JL4_GO_SERVICE_URL=http://127.0.0.1:8080 — never auto-set; a deployment target must be named by a human",
  });
}

// The moddle gates need only npx: the stages run
// `npx --yes --package=dmn-moddle …`, which fetches into npx's own cache, so
// repo-root node_modules is NOT a prerequisite (a first-ever run needs the
// network once; after that the cache serves it). A forecast that demanded
// `npm ci` here cried wolf on its very first live run — 2026-08-09, this
// file's own smoke test — against a leg that had just PASSed.
const moddleLegs = [
  ["p7-dmn", "dmn-moddle"],
  ["p7-bpmn", "bpmn-moddle"],
];
for (const [stage, pkg] of moddleLegs) {
  if (!declared(stage)) continue;
  if (!probes.npx?.present) {
    findings.push({
      stage,
      what: `well-formedness gate will fail — npx is not on PATH (the ${pkg} check runs under npx)`,
      remedy: "install node/npm",
    });
  }
}

if (declared("p7-lts") && !probes.dot?.present) {
  notes.push(
    "p7-lts: graphviz absent — DOT still emitted and checked, SVG rendering skipped (named on the receipt; not a stage skip)",
  );
}

// --- output ------------------------------------------------------------------
const provLine = (name, val, prov) =>
  `doctor:   ${name.padEnd(12)} ${val || "(unset)"}${prov ? `  [${prov}]` : ""}`;

if (!BRIEF) {
  process.stdout.write(
    `doctor: milestone ${MILESTONE} — ${STAGES.length} declared stage(s)\n`,
  );
  process.stdout.write(
    provLine("l4", env.L4, env.GO_L4_PROVENANCE || "explicit") + "\n",
  );
  process.stdout.write(
    provLine(
      "jl4-lsp",
      env.JL4_LSP_CMD,
      env.JL4_LSP_CMD ? env.GO_LSP_PROVENANCE || "explicit" : "",
    ) + "\n",
  );
  process.stdout.write(
    provLine("jl4-service", env.JL4_GO_SERVICE_URL, "") + "\n",
  );
  process.stdout.write(
    provLine("library path", env.JL4_LIBRARY_PATH, "") + "\n",
  );
}

for (const f of findings) {
  process.stdout.write(`doctor: ${f.stage} ${f.what}\n`);
  process.stdout.write(`doctor:   remedy: ${f.remedy}\n`);
}
if (!BRIEF) {
  for (const n of notes) process.stdout.write(`doctor: note — ${n}\n`);
  // The gates are not an environment problem and never count toward the exit
  // code, but a first-time caller hits them right after the environment, so
  // the forecast says where the run will stop.
  process.stdout.write(
    "doctor: gates — HG1 blocks p6-tests onward until signed (etc/go/gate-request.sh HG1) or waived\n" +
      "doctor:   (--waive HG1=REASON, on the record); HG2 has no waiver and no env override.\n",
  );
}

if (findings.length === 0) {
  process.stdout.write(
    "doctor: every declared stage is fully provisioned; the run should produce a whole deliverable\n",
  );
  process.exit(0);
}
process.stdout.write(
  `doctor: ${findings.length} of ${STAGES.length} declared stage(s) will not run whole; remedies above\n`,
);
process.exit(1);
