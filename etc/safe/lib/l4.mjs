// Talking to the L4 toolchain: find the binary, run an @export function over a deal,
// decode what comes back.
//
// NOTHING HERE BUILDS ANYTHING. CLAUDE.md §2.1: `cabal` in a shared worktree corrupts a
// concurrent build, so the answer to "no binary" is discovery and then a named refusal.
// The discovery policy is a port of etc/go/lib/toolchain.sh, kept deliberately identical
// so that a run of `etc/safe` and a run of `etc/go` on the same machine pick the same
// binary: explicit $L4 always wins; then this worktree's own dist-newstyle (the binary
// built from this tree is the one whose CLI surface was measured); then the newest among
// sibling worktrees under the l4wt convention.

import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";

/** Walk up from `from` to the directory that holds a .git entry. */
export function repoRoot(from = process.cwd()) {
  let d = resolve(from);
  for (;;) {
    if (existsSync(join(d, ".git"))) return d;
    const up = dirname(d);
    if (up === d) return null;
    d = up;
  }
}

function candidatesUnder(root) {
  // dist-newstyle/build/<arch>/ghc-*/jl4-*/x/l4/build/l4/l4
  const out = [];
  const base = join(root, "dist-newstyle", "build");
  if (!existsSync(base)) return out;
  const dirs = (p) => {
    try {
      return readdirSync(p, { withFileTypes: true })
        .filter((e) => e.isDirectory())
        .map((e) => join(p, e.name));
    } catch {
      return [];
    }
  };
  for (const arch of dirs(base))
    for (const ghc of dirs(arch))
      for (const pkg of dirs(ghc)) {
        const exe = join(pkg, "x", "l4", "build", "l4", "l4");
        if (existsSync(exe)) {
          let m = 0;
          try {
            m = statSync(exe).mtimeMs;
          } catch {
            m = 0;
          }
          out.push({ path: exe, mtime: m });
        }
      }
  return out;
}

/** @returns {{path: string, provenance: "explicit"|"own"|"sibling"}} */
export function discoverL4(root = repoRoot()) {
  if (process.env.L4) return { path: process.env.L4, provenance: "explicit" };
  const newest = (xs) => xs.sort((a, b) => b.mtime - a.mtime)[0];
  if (root) {
    const own = newest(candidatesUnder(root));
    if (own) return { path: own.path, provenance: "own" };
    const parent = dirname(root);
    const siblings = [];
    for (const e of readdirSync(parent, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      const d = join(parent, e.name);
      if (d === root) continue;
      siblings.push(...candidatesUnder(d));
    }
    const best = newest(siblings);
    if (best) return { path: best.path, provenance: "sibling" };
  }
  throw new Error(
    "etc/safe: no `l4` binary. Set $L4, or build one in a sibling worktree:\n" +
      "  export L4=/path/to/dist-newstyle/build/<arch>/ghc-9.10.3/jl4-0.1/x/l4/build/l4/l4\n" +
      "This tool never runs cabal (CLAUDE.md §2.1).",
  );
}

/**
 * `l4` has no --version (measured 2026-09-04: `l4 --version` exits 1 with
 * "Invalid option `--version'"). SPEC.md §5.4 wants a version string in the XMP
 * payload, so record "unknown" rather than inventing one — and say so in the README
 * so a reader does not read "unknown" as a failed probe.
 */
export function l4Version(l4 = discoverL4().path) {
  const r = spawnSync(l4, ["--version"], { encoding: "utf8" });
  const text = ((r.stdout || "") + (r.stderr || "")).trim();
  if (r.status === 0 && text && !/Invalid option/.test(text))
    return text.split("\n")[0];
  return "unknown";
}

/** `l4 check FILE` — typecheck only. @returns {{ok: boolean, output: string}} */
export function check(file, { l4 = discoverL4().path, libraryPath } = {}) {
  const env = { ...process.env };
  if (libraryPath) env.JL4_LIBRARY_PATH = libraryPath;
  const r = spawnSync(l4, ["check", file], { encoding: "utf8", env });
  return { ok: r.status === 0, output: (r.stdout || "") + (r.stderr || "") };
}

const MAYBE = new Set(["JUST", "NOTHING"]);

/**
 * Decode `l4 batch` output values into plain JS.
 *
 * Measured shape (2026-09-04): records come back as `{"Conversion": [v1, v2, …]}` —
 * the constructor name and the field values POSITIONALLY, in DECLARE order. The names
 * are not in the wire format at all, so `encoding.json`'s `batch.record_fields` is the
 * decoding key, and `etc/safe/check-encoding.mjs` is what keeps it honest.
 * Lists are JSON arrays; strings and numbers are native.
 */
export function decode(value, recordFields) {
  if (Array.isArray(value)) return value.map((v) => decode(v, recordFields));
  if (value === null || typeof value !== "object") return value;
  const keys = Object.keys(value);
  if (keys.length === 1 && Array.isArray(value[keys[0]])) {
    const ctor = keys[0];
    if (MAYBE.has(ctor))
      return ctor === "NOTHING" ? null : decode(value[ctor][0], recordFields);
    const fields = recordFields[ctor];
    if (!fields)
      throw new Error(
        `etc/safe: l4 batch returned a record \`${ctor}\` that encoding.json's ` +
          `batch.record_fields does not name. Either the encoding grew a type or the ` +
          `field map has drifted — run etc/safe/check-encoding.mjs.`,
      );
    const args = value[ctor];
    if (args.length !== fields.length)
      throw new Error(
        `etc/safe: \`${ctor}\` came back with ${args.length} values but ` +
          `encoding.json names ${fields.length} fields (${fields.join(", ")}). ` +
          `The DECLARE and the field map disagree — run etc/safe/check-encoding.mjs.`,
      );
    const out = {};
    fields.forEach((f, i) => {
      out[f] = decode(args[i], recordFields);
    });
    return out;
  }
  const out = {};
  for (const k of keys) out[k] = decode(value[k], recordFields);
  return out;
}

/**
 * Run one @export function over one row of named parameters.
 *
 * MEASURED call shape (2026-09-04):
 *   JL4_LIBRARY_PATH=<row> l4 batch <row>/safe-form.l4 -e "validate deal" -i rows.json
 * with rows.json = `[{"deal": <deal object>}]`. A function of several parameters takes
 * one key per parameter, named as `encoding.json`'s `entrypoints.<name>.params` says:
 *   [{"deal": <deal object>, "event": {"proceeds": 1e7, …}}]
 * Output is NDJSON, one envelope per row:
 *   {"diagnostics":[…],"input":{…},"output":[{"result": <value>,"trace":null}],"status":"success"}
 * On failure `status` is "error" and `output[0].result.error` carries the message.
 *
 * JL4_LIBRARY_PATH must name the encoding row or the module's IMPORTs do not resolve.
 */
export function runBatchRow(modulePath, entrypoint, row, opts = {}) {
  const {
    l4 = discoverL4().path,
    libraryPath = dirname(resolve(modulePath)),
    recordFields = {},
    tmpDir,
  } = opts;
  const dir = mkdtempSync(join(tmpDir ?? tmpdir(), "l4-safe-"));
  const rows = join(dir, "rows.json");
  try {
    writeFileSync(rows, JSON.stringify([row]));
    const r = spawnSync(
      l4,
      ["batch", resolve(modulePath), "-e", entrypoint, "-i", rows],
      {
        encoding: "utf8",
        env: { ...process.env, JL4_LIBRARY_PATH: libraryPath },
      },
    );
    const stdout = r.stdout || "";
    const stderr = r.stderr || "";
    const lines = stdout.split("\n").filter((l) => l.trim().length > 0);
    if (lines.length === 0)
      throw new Error(
        `etc/safe: \`l4 batch ${modulePath} -e ${entrypoint}\` produced no rows ` +
          `(exit ${r.status}).\n${stderr || stdout}`,
      );
    const env = JSON.parse(lines[lines.length - 1]);
    if (env.status !== "success") {
      const msg = env.output?.[0]?.result?.error ?? JSON.stringify(env.output);
      throw new Error(
        `etc/safe: L4 refused \`${entrypoint}\` in ${modulePath}:\n${msg}`,
      );
    }
    return decode(env.output[0].result, recordFields);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** The one-parameter case, which is `validate deal` and `convert`. */
export function runBatch(modulePath, entrypoint, deal, opts = {}) {
  const { param = "deal", extra = {} } = opts;
  return runBatchRow(modulePath, entrypoint, { [param]: deal, ...extra }, opts);
}
