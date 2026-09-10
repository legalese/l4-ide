#!/usr/bin/env node
// Build the distributable L4 plugin bundle: the writing-l4-rules skill plus
// every file the skill cites, and nothing else.
//
// WHY THIS IS COMPUTED RATHER THAN A LIST. The skill teaches by example: it
// names ~46 files it does not carry (`jl4/examples/legal/regcf/regcf.l4` alone
// is cited 20 times) and almost all of those citations are prose, not markdown
// links -- so shipping the skill alone does not produce broken links, it
// produces an agent told "see how regcf.l4 handles this" with no regcf.l4 on
// disk. A hand-maintained include list would go stale the first time someone
// cites a new example, and would go stale silently, for exactly that reason.
// Extracting the citations from the skill text is a rule; a list is a promise.
//
// Cited files are copied to their ORIGINAL repo-relative paths under the
// bundle root, so every citation string in the skill stays literally correct
// -- relative to the bundle root the way it is relative to the repo root. That
// is why no skill text is rewritten here.
//
// Usage: node etc/build-plugin-bundle.mjs <outdir> [--quiet]

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SKILL_REL = ".claude/skills/writing-l4-rules";
const SKILL = path.join(REPO, SKILL_REL);

const outArg = process.argv[2];
const quiet = process.argv.includes("--quiet");
if (!outArg) {
  console.error("usage: node etc/build-plugin-bundle.mjs <outdir> [--quiet]");
  process.exit(2);
}
const OUT = path.resolve(outArg);

if (!fs.existsSync(SKILL)) {
  throw new Error(`skill not found at ${SKILL} -- did it move again?`);
}

// The prefixes a citation can start with are the repo's own top-level entries,
// read from disk rather than hardcoded, so a new top-level directory does not
// silently stop being recognised.
const TOP = fs
  .readdirSync(REPO, { withFileTypes: true })
  .filter(
    (e) =>
      e.isDirectory() && !e.name.startsWith(".") && e.name !== "node_modules",
  )
  .map((e) => e.name)
  .sort();

const CITATION = new RegExp(
  String.raw`(?:^|[\s(\[\`'"~])((?:${TOP.join("|")})/[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.[a-z0-9]{1,6})`,
  "g",
);

function walk(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else out.push(p);
  }
  return out;
}

// --- gather citations -------------------------------------------------------
const skillFiles = walk(SKILL);
const cited = new Map(); // relpath -> Set of skill files citing it
for (const f of skillFiles) {
  if (!/\.(md|l4|sh)$/.test(f)) continue;
  const text = fs.readFileSync(f, "utf8");
  for (const m of text.matchAll(CITATION)) {
    const rel = m[1];
    if (rel.startsWith(SKILL_REL)) continue; // self-reference
    if (!cited.has(rel)) cited.set(rel, new Set());
    cited.get(rel).add(path.relative(SKILL, f));
  }
  // Markdown links that climb out of the skill with `../` are citations too,
  // and the bare-prefix regex above cannot see them -- the character before
  // the top-level directory name is a `/`, not a delimiter. Missing these is
  // how a link to doc/tutorials/ shipped dangling in the first build.
  for (const m of text.matchAll(/\]\((\.\.\/[^)\s]+)\)/g)) {
    const abs = path.resolve(path.dirname(f), m[1]);
    const rel = path.relative(REPO, abs);
    if (rel.startsWith("..") || rel.startsWith(SKILL_REL)) continue;
    if (!cited.has(rel)) cited.set(rel, new Set());
    cited.get(rel).add(path.relative(SKILL, f));
  }
}

// --- copy -------------------------------------------------------------------
// Clear the bundle's CONTENTS but keep `.git`. The bundle is meant to be a
// published repository whose history is the record of what shipped when, and
// an earlier version of this line removed the directory whole -- silently
// deleting that history on the next build, which is how the first bundle repo
// lost its initial commit. Preserving it is what makes "regenerate, then
// commit the diff" a workable publish model.
fs.mkdirSync(OUT, { recursive: true });
for (const e of fs.readdirSync(OUT)) {
  if (e === ".git") continue;
  fs.rmSync(path.join(OUT, e), { recursive: true, force: true });
}

function copyInto(relSrc, relDest) {
  const src = path.join(REPO, relSrc);
  const dest = path.join(OUT, relDest);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.cpSync(src, dest, { recursive: true });
}

// The skill itself goes to the Agent Plugins 1.0 fixed location, `skills/`,
// which is where a plugin client looks -- NOT to `.claude/skills/`, which is
// this repo's project-skill location and means nothing to an installed plugin.
copyInto(SKILL_REL, "skills/writing-l4-rules");

// The skill sits at a different depth in the bundle than in the repo
// (`skills/x` vs `.claude/skills/x`), so a `../`-relative link that is correct
// in one is off-by-one in the other. Recompute each from the actual depths
// rather than assuming either layout -- this is precisely the arithmetic a
// human gets wrong, and it fails silently because nothing link-checks a skill.
const BUNDLED_SKILL = path.join(OUT, "skills/writing-l4-rules");
for (const f of walk(BUNDLED_SKILL)) {
  if (!f.endsWith(".md")) continue;
  const origin = path.join(SKILL, path.relative(BUNDLED_SKILL, f));
  const before = fs.readFileSync(f, "utf8");
  const after = before.replace(/\]\((\.\.\/[^)\s]+)\)/g, (whole, link) => {
    const target = path.relative(
      REPO,
      path.resolve(path.dirname(origin), link),
    );
    if (target.startsWith("..")) return whole; // points outside the repo; leave it
    // A link that stays inside the skill needs no rewriting: the skill's own
    // tree is copied verbatim, so its internal relative links are already
    // correct. Rewriting them pointed them at `.claude/skills/...` inside the
    // bundle, where nothing lives -- 100 broken links, all self-inflicted.
    if (target.startsWith(SKILL_REL)) return whole;
    let out = path.relative(path.dirname(f), path.join(OUT, target));
    if (!out.startsWith(".")) out = "./" + out;
    return `](${out})`;
  });
  if (after !== before) fs.writeFileSync(f, after);
}

// The standard library is compiled INTO the `l4` binary, wholesale: the
// Template Haskell splice in jl4-core/src/L4/API/EmbeddedLibraries.hs embeds
// every .l4 under jl4-core/libraries/, and the resolver reaches them under the
// `jl4-embedded` scheme with no file on disk.
//
// So copying them here would not add a missing file, it would add a SECOND
// copy at a path the skill cites -- and a second copy is worse than none.
// CLAUDE.md 3.1: pointing an `l4` at a prelude NEWER than itself does not
// report a version mismatch, it fails as cascading "could not find a
// definition" errors for setFromList and every other prelude name, which reads
// as a broken spec. A bundle that ages past the user's binary would manufacture
// exactly that. The embedded copy is correct by construction, always.
const RUNTIME_PROVIDED = /^jl4-core\/libraries\//;

const carried = [];
const skippedDirs = [];
const fromRuntime = [];
const unresolved = [];
for (const [rel, whom] of [...cited].sort()) {
  const abs = path.join(REPO, rel);
  if (!fs.existsSync(abs)) {
    unresolved.push([rel, [...whom]]);
    continue;
  }
  if (fs.statSync(abs).isDirectory()) {
    // A bare directory mention ("everything under jl4/examples/legal/") is a
    // gesture, not a citation; copying the tree would drag in megabytes the
    // skill never names. Recorded, not carried.
    skippedDirs.push(rel);
    continue;
  }
  if (RUNTIME_PROVIDED.test(rel)) {
    fromRuntime.push(rel);
    continue;
  }
  copyInto(rel, rel);
  carried.push([rel, fs.statSync(abs).size]);
}

// --- optional: an installer for the l4 binary --------------------------------
//
// The skill invokes `l4` in 60-odd places (32 x `l4 run`, 10 x `l4 check`), and
// scripts/validate.sh resolves PATH -> `cabal run l4` -> an error telling you to
// install from VS Code. So a bundle with no route to a binary hands a user a
// skill whose every validation step is a dead letter -- the same shape of defect
// as shipping it without the worked examples.
//
// The binaries are NOT committed. `legalese/prereleases` publishes three
// platform archives totalling 150 MB per release, and a plugin install is a git
// clone: committed binaries would sit in history forever, so the "small plugin
// repo" would pass the 289 MB monorepo it exists to escape after two releases,
// recoverable only by rewriting history. Fetching costs the user one archive
// for their own platform instead of all three, once.
//
// WHY THE CHECKSUMS ARE EMBEDDED HERE rather than fetched by the script. A
// download verified against a checksum pulled from the same host at the same
// moment proves the bytes did not corrode in transit and almost nothing else.
// Embedded at generation time, the digest travels inside the reviewed, committed
// bundle, so it is checkable against a release anyone can inspect. That is a
// weaker guarantee than signing and a much stronger one than self-certification.
async function shelfRelease(spec) {
  const API = "https://api.github.com/repos/legalese/prereleases/releases";
  const h = { accept: "application/vnd.github+json" };
  let tag = spec;
  if (spec === "latest") {
    // NOT /releases/latest: that endpoint excludes prereleases, and every
    // release on this shelf is one, so it answers 404 forever.
    const r = await fetch(`${API}?per_page=10`, { headers: h });
    if (!r.ok) throw new Error(`shelf listing: HTTP ${r.status}`);
    const list = await r.json();
    if (!list.length) throw new Error("the shelf has published no releases");
    tag = list[0].tag_name;
  }
  const sums = await fetch(
    `https://github.com/legalese/prereleases/releases/download/${tag}/SHA256SUMS`,
  );
  if (!sums.ok) throw new Error(`SHA256SUMS for ${tag}: HTTP ${sums.status}`);
  const checksums = {};
  for (const line of (await sums.text()).split("\n")) {
    const m = line
      .trim()
      .match(
        /^([0-9a-f]{64})\s+l4-.*-(darwin-arm64|linux-x64|win32-x64)\.tar\.gz$/,
      );
    if (m) checksums[m[2]] = m[1];
  }
  if (Object.keys(checksums).length === 0)
    throw new Error(`no recognisable archive lines in ${tag}'s SHA256SUMS`);
  return { tag, checksums };
}

function installerScript({ tag, checksums }) {
  return `#!/usr/bin/env bash
# Install the l4 CLI and jl4-lsp for this plugin's skill.
#
# GENERATED. The release tag and the digests below were embedded when this
# bundle was built, so they travel with a bundle you can inspect rather than
# being fetched from the same host as the download at the same moment.
#
# Installs to ~/.local/lib/l4-<tag>/ and links ~/.local/bin/{l4,jl4-lsp}.
set -euo pipefail

TAG="${tag}"
REPO="legalese/prereleases"
${Object.entries(checksums)
  .map(([k, v]) => `SHA_${k.replace(/-/g, "_")}="${v}"`)
  .join("\n")}

os="$(uname -s)"; arch="$(uname -m)"
case "$os/$arch" in
  Darwin/arm64)        plat="darwin-arm64"; sha="$SHA_darwin_arm64" ;;
  Linux/x86_64|Linux/amd64) plat="linux-x64"; sha="$SHA_linux_x64" ;;
  *)
    echo "No prebuilt l4 for $os/$arch." >&2
    echo "Windows x64 builds are published at:" >&2
    echo "  https://github.com/$REPO/releases/tag/$TAG" >&2
    echo "Otherwise build from source: https://github.com/legalese/l4-ide" >&2
    exit 1 ;;
esac

ARCHIVE="l4-$TAG-$plat.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ARCHIVE"
PREFIX="\${L4_PREFIX:-$HOME/.local}"
LIBDIR="$PREFIX/lib/l4-$TAG"
BINDIR="$PREFIX/bin"

if [ -x "$LIBDIR/l4" ]; then
  echo "Already installed: $LIBDIR/l4"
else
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading $ARCHIVE ..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 -o "$tmp/$ARCHIVE" "$URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$tmp/$ARCHIVE" "$URL"
  else
    echo "Need curl or wget to download the archive." >&2; exit 1
  fi

  # Verify BEFORE unpacking. An archive is unpacked by code that trusts it.
  echo "Verifying ..."
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$tmp/$ARCHIVE" | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    got="$(shasum -a 256 "$tmp/$ARCHIVE" | cut -d' ' -f1)"
  else
    echo "Need sha256sum or shasum to verify the download; refusing to install unverified." >&2
    exit 1
  fi
  if [ "$got" != "$sha" ]; then
    echo "CHECKSUM MISMATCH -- refusing to install." >&2
    echo "  expected \$sha" >&2
    echo "  got      \$got" >&2
    echo "This means the archive is not the one this bundle was built against." >&2
    exit 1
  fi

  mkdir -p "$LIBDIR"
  tar -xzf "$tmp/$ARCHIVE" -C "$tmp"
  # The archive unpacks to a single directory named for the build; move its
  # contents up so the layout here does not depend on that name.
  src="$tmp/l4-$TAG-$plat"
  [ -d "$src" ] || { echo "Unexpected archive layout: $src is missing." >&2; exit 1; }
  cp -R "$src/." "$LIBDIR/"
  chmod +x "$LIBDIR/l4" "$LIBDIR/jl4-lsp" 2>/dev/null || true
fi

mkdir -p "$BINDIR"
ln -sf "$LIBDIR/l4" "$BINDIR/l4"
ln -sf "$LIBDIR/jl4-lsp" "$BINDIR/jl4-lsp"

echo
echo "Installed:"
echo "  $BINDIR/l4"
echo "  $BINDIR/jl4-lsp   (language server: diagnostics and hovers)"
echo
# The standard library ships INSIDE the archive, beside the binary, and is also
# compiled into it. Both are version-matched to this binary by construction,
# which is why this bundle deliberately carries no copy of its own: an l4 aimed
# at a prelude newer than itself does not report a version mismatch, it fails as
# cascading "could not find a definition" errors that read as a broken program.
echo "The standard library is version-matched inside the install; do not set"
echo "JL4_LIBRARY_PATH at anything else."
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo; echo "NOTE: $BINDIR is not on your PATH." ;;
esac
`;
}

const relSpec = process.argv.includes("--l4-release")
  ? process.argv[process.argv.indexOf("--l4-release") + 1] || "latest"
  : null;
if (relSpec) {
  try {
    const rel = await shelfRelease(relSpec);
    const dest = path.join(OUT, "scripts/install-l4.sh");
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, installerScript(rel));
    fs.chmodSync(dest, 0o755);
    if (!quiet)
      console.log(
        `l4 binary   : scripts/install-l4.sh pinned to ${rel.tag} (${Object.keys(rel.checksums).length} platform digests embedded)`,
      );
  } catch (e) {
    // Loud, and NOT fatal. A bundle without an installer is honest; a bundle
    // with an installer pinned to a release nobody verified is not.
    console.error(
      `build-plugin-bundle: NO INSTALLER EMITTED -- ${e.message}\n` +
        `  The bundle is complete otherwise. Re-run with network access to pin one.`,
    );
  }
}

// --- optional: make the bundle openable as a Claude Code project ------------
// `--project-layout` additionally writes the skill to `.claude/skills/`, so the
// bundle can be opened as a working directory and the skill auto-loads as a
// project skill, with every example it cites sitting at the path it names.
// OFF by default: an installed plugin reads `skills/`, ignores `.claude/`, and
// the published artifact should not carry the skill twice. This exists so the
// bundle can be exercised outside an l4-ide checkout before anything is
// published -- which is the only way to find out whether the skill still works
// when its examples travel with it.
if (process.argv.includes("--project-layout")) {
  copyInto(SKILL_REL, ".claude/skills/writing-l4-rules");
  if (!quiet)
    console.log(
      "project     : also written to .claude/skills/ (--project-layout)",
    );
}

// --- totals (needed by both the bundle README and the report) ---------------
const bytes = carried.reduce((a, [, n]) => a + n, 0);
const skillBytes = walk(SKILL).reduce((a, f) => a + fs.statSync(f).size, 0);
const mb = (n) => (n / 1024 / 1024).toFixed(2);

// --- manifests --------------------------------------------------------------
// Carried from the repo rather than written here, so the plugin's identity has
// exactly one author. The marketplace entry is the one thing rewritten: its
// `source` must name wherever this bundle is published, which is not the repo
// it was generated from -- that mismatch is the whole point of the split.
const PUBLISH_REPO = process.env.L4_PLUGIN_REPO || "legalese/l4-plugin";

for (const f of [
  "plugin.json",
  ".claude-plugin/plugin.json",
  "PLUGIN.md",
  // The manifests declare Apache-2.0. A public repository that declares a
  // licence and does not ship its text has not actually granted one.
  "LICENSE",
]) {
  if (fs.existsSync(path.join(REPO, f))) copyInto(f, f);
}

// PLUGIN.md describes the PLUGIN, in which the skill sits at `skills/`. In
// this repo it sits at `.claude/skills/`, so its links are written that way
// and have to be mapped back on the way in -- otherwise the bundle's own front
// page links into a `.claude/` directory the bundle does not have.
const pluginMd = path.join(OUT, "PLUGIN.md");
if (fs.existsSync(pluginMd)) {
  fs.writeFileSync(
    pluginMd,
    fs
      .readFileSync(pluginMd, "utf8")
      .split(SKILL_REL)
      .join("skills/writing-l4-rules"),
  );
}

const mkt = JSON.parse(
  fs.readFileSync(path.join(REPO, ".claude-plugin/marketplace.json"), "utf8"),
);
for (const entry of mkt.plugins ?? []) {
  if (entry.source && entry.source.repo) entry.source.repo = PUBLISH_REPO;
}
const mktText = JSON.stringify(mkt, null, 2) + "\n";
for (const dest of [
  ".claude-plugin/marketplace.json",
  ".github/plugin/marketplace.json",
]) {
  fs.mkdirSync(path.join(OUT, path.dirname(dest)), { recursive: true });
  fs.writeFileSync(path.join(OUT, dest), mktText);
}

let headSha = "unknown";
try {
  headSha = execFileSync("git", ["-C", REPO, "rev-parse", "HEAD"], {
    encoding: "utf8",
  }).trim();
} catch {}

fs.writeFileSync(
  path.join(OUT, "README.md"),
  `# L4 Computational Law — plugin bundle

> ## ⚠️ Experimental prototype — may be taken down at any time
>
> This repository is an experiment in packaging the L4 authoring skill so it can
> be used **outside** the [l4-ide](https://github.com/legalese/l4-ide) monorepo,
> whose plugin install otherwise resolves to a 289 MB clone to deliver half a
> megabyte of skill.
>
> It has **not been through architectural review**. It is not a supported
> product, it carries no compatibility promise, and it may be **moved, renamed,
> restructured or deleted without notice or deprecation period**. The upstream
> decision about whether the plugin should live in its own repository at all has
> not been taken.
>
> If you depend on anything here, vendor it: take a copy, pin a commit, and do
> not assume this URL resolves next month. The skill itself is stable and lives
> in l4-ide; it is only this *packaging* that is provisional.

**This directory is generated. Do not edit it by hand.** Every file here was
copied out of [legalese/l4-ide](https://github.com/legalese/l4-ide) by
\`etc/build-plugin-bundle.mjs\`; edits made here are lost on the next build.
Change the skill in l4-ide at \`.claude/skills/writing-l4-rules/\` and rebuild.

Generated from l4-ide \`${headSha.slice(0, 12)}\`.

## What is here, and why

\`skills/writing-l4-rules/\` is the skill. Everything else is the material the
skill **cites**: it teaches by worked example, naming files like
\`jl4/examples/legal/regcf/regcf.l4\` in its prose rather than restating them.
Those citations are carried at their original repo-relative paths, so each one
resolves against this bundle root exactly as it resolves against the l4-ide
root. Nothing in the skill text was rewritten.

The set is computed from the skill's own text, not from a maintained list, so
citing a new example carries that example on the next build.

One class is deliberately **not** carried: \`jl4-core/libraries/*.l4\`, the
standard library. The \`l4\` binary embeds it at compile time and resolves it
under the \`jl4-embedded\` scheme, so a copy here would be a second copy of
something the runtime already has -- and a second copy that ages past the
user's binary is worse than none, because an \`l4\` pointed at a prelude newer
than itself does not report a version mismatch; it fails as cascading
\`could not find a definition\` errors that read as a broken program.

| | |
|---|---|
| skill | ${skillFiles.length} files |
| cited material | ${carried.length} files |
| cited but NOT carried | ${fromRuntime.length} standard-library files |
| bundle | ${mb(skillBytes + bytes)} MB |
| the repo it came from | 289 MB packed |

That last row is the reason this bundle exists: installing the plugin used to
mean cloning the whole monorepo to deliver half a megabyte of skill.
`,
);

// --- report -----------------------------------------------------------------
if (!quiet) {
  console.log(`bundle root : ${OUT}`);
  console.log(`skill       : ${skillFiles.length} files, ${mb(skillBytes)} MB`);
  console.log(`cited files : ${carried.length} carried, ${mb(bytes)} MB`);
  if (fromRuntime.length)
    console.log(
      `runtime     : ${fromRuntime.length} cited file(s) NOT carried — the l4 binary embeds them`,
    );
  console.log(`total       : ${mb(skillBytes + bytes)} MB`);
  if (skippedDirs.length) {
    console.log(`\ndirectory mentions, recorded but not carried:`);
    for (const d of skippedDirs) console.log(`  ${d}/`);
  }
  if (unresolved.length) {
    console.log(
      `\nUNRESOLVED citations (the skill names these; they do not exist):`,
    );
    for (const [rel, whom] of unresolved) {
      console.log(`  ${rel}`);
      for (const w of whom.slice(0, 3)) console.log(`      cited by ${w}`);
    }
  }
}

// --- self-check -------------------------------------------------------------
// Verify the bundle from the outside, the way a plugin user meets it: every
// path the bundled skill names must exist in the bundle, and every markdown
// link must resolve. The first build of this bundle passed every internal
// check and still shipped one dangling link, because the generator only ever
// checked its own bookkeeping. This checks the artifact instead.
const dangling = [];
for (const f of walk(BUNDLED_SKILL)) {
  if (!/\.(md|l4|sh)$/.test(f)) continue;
  const text = fs.readFileSync(f, "utf8");
  const who = path.relative(OUT, f);
  for (const m of text.matchAll(CITATION)) {
    // A citation the `l4` binary answers is satisfied, not dangling. It has no
    // file in the bundle by design -- see RUNTIME_PROVIDED above.
    if (RUNTIME_PROVIDED.test(m[1])) continue;
    if (!fs.existsSync(path.join(OUT, m[1])))
      dangling.push([m[1], who, "citation"]);
  }
  for (const m of text.matchAll(/\]\(([^)\s#][^)\s]*)\)/g)) {
    const link = m[1];
    if (/^[a-z]+:/.test(link)) continue; // external URL
    if (!fs.existsSync(path.resolve(path.dirname(f), link.split("#")[0])))
      dangling.push([link, who, "link"]);
  }
}
if (dangling.length && !quiet) {
  console.log(`\nBUNDLE SELF-CHECK FAILED — ${dangling.length} unresolved:`);
  for (const [what, who, kind] of dangling.slice(0, 20))
    console.log(`  ${kind.padEnd(9)} ${what}\n      named by ${who}`);
} else if (!quiet) {
  console.log(
    `\nself-check  : every citation and link in the bundled skill resolves`,
  );
}

// Unresolved citations are a defect in the skill, not in this script: the skill
// is telling a reader to open something that is not there. Surface it as a
// non-zero exit so CI can refuse to publish a bundle with dangling advice.
process.exit(unresolved.length || dangling.length ? 1 : 0);
