#!/usr/bin/env node
// The corpus section of the HG1 payload, expressed as receipt metrics: one
// `corpus_sha_<path>=<sha256>` line per module of the encoding.
//
// Usage: node etc/go/lib/corpus-metrics.mjs FILE…
// Exit:  0 one `key=value` line per file, in the order given
//        2 usage, a file that is not on disk, or a path the metric transport
//          cannot carry
//
// --- why this is a module and not three lines of bash ------------------------
//
// What it emits is the ENTIRE content binding between a human signature and the
// L4 that runs afterwards. `gate-payload.mjs` builds the payload's `corpus`
// section from exactly these metrics and from nothing else, so a module that
// gets no line here is a module the reviewer is never shown and the signature
// does not commit to. Only `p0-preflight.sh` calls this in a run — but a seam a
// selftest can call directly is what lets the payload's coverage be measured
// rather than asserted, and the defect it exists to prevent (below) is silent.
//
// --- why the key is a repo-relative PATH and not a basename ------------------
//
// `receipt.mjs`'s `metricsFrom` is last-wins: two `--metric` arguments sharing a
// key collapse into one entry. p0-preflight keyed these metrics by
// `basename` while a subject's encoding was one module plus a wizard, where a
// collision was impossible. `corpus.modules` makes an N-module encoding
// ordinary, and an N-module encoding makes two modules sharing a basename in
// different directories ordinary with it — at which point the collapse drops a
// whole module out of the signed document, with no error anywhere, in exactly
// the case (a big encoding) where a reviewer is least able to notice it by eye.
//
// A path also tells the reviewer WHICH file each digest is of, which a bare
// basename does not once the modules live in more than one directory.
//
// --- and why the value is `sha256File`, not `digest.mjs` ---------------------
//
// The metric used to be `digest.mjs`, i.e. `digestSet` over a ONE-ELEMENT set,
// which hashes `path\tsize\tsha256` — so the recorded value embedded the
// absolute worktree path and was not the file's sha256 at all. Measured on
// `jl4/examples/legal/regcf/regcf.l4`: `sha256:78529ff9…` from a relative path,
// `sha256:a9534ae0…` from an absolute one, `sha256:1048701d…` from
// `shasum -a 256`. Only the third is a fact about the file, and only the third
// is one a reviewer can check against the payload with a command they already
// know. `digestSet` is the right tool for "did this SET of inputs move"; it is
// the wrong one for "here is the digest of this file".
//
// The cost is recorded, not hidden: SPEC.md R8 previously noted that a payload
// binding basenames alone survives a subject being MOVED between directories.
// It no longer does — moving a module changes its key, so the payload changes
// and the signature must be re-obtained. That is the same rule R8 already
// states for content ("binds to content, not to a moment"), now applied to the
// file set as well as to the file bytes; a signature that cannot say which
// files it covered is not worth preserving across a reorganisation.

import { existsSync, statSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { sha256File } from "./ledger.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");

function die(msg) {
  process.stderr.write(`corpus-metrics.mjs: ${msg}\n`);
  process.exit(2);
}

const paths = process.argv.slice(2);
if (paths.length === 0)
  die(
    "no module paths given. The caller must name every module of the encoding: an empty set would record a corpus digest of nothing, and the HG1 payload would commit to nothing",
  );

const seen = new Map(); // key -> the argument that produced it
const lines = [];
for (const p of paths) {
  const abs = resolve(REPO, p);
  if (!existsSync(abs) || !statSync(abs).isFile())
    die(
      `no file at ${abs} (from '${p}'). A corpus module is committed, so a missing one is a misconfiguration of the subject sidecar, not a status a stage may report`,
    );
  // Inside the repo, the key is the repo-relative path — stable across
  // checkouts and worktrees, which a run directory's contents have to be.
  // Outside it (the selftest points at a tmpdir), the absolute path is kept:
  // still unique, still a path, and never silently truncated to a basename.
  const rel = relative(REPO, abs);
  const key = rel && !rel.startsWith("..") && !isAbsolute(rel) ? rel : abs;
  // The transport is `key=value` lines parsed by splitting at the FIRST `=`
  // (receipt.mjs metricsFrom), re-emitted verbatim on a replay (go.sh), and
  // rendered one per line in the payload (gate-payload.mjs). A key carrying
  // `=` or whitespace would be silently truncated or split in one of those
  // three places rather than refused in any of them.
  if (/[\s=]/.test(key))
    die(
      `module path '${p}' resolves to key '${key}', which contains whitespace or '='. The metric transport is newline-separated 'key=value', so such a key would be truncated or split rather than carried`,
    );
  if (seen.has(key))
    die(
      `'${p}' and '${seen.get(key)}' both key to '${key}'. Metrics are last-wins, so one of the two would drop out of the HG1 payload silently`,
    );
  seen.set(key, p);
  lines.push(`corpus_sha_${key}=${sha256File(abs)}`);
}

process.stdout.write(lines.join("\n") + "\n");
