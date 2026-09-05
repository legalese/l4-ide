#!/usr/bin/env node
// Rewrite term-role `ASSUME` declarations to section `GIVEN`s — the ruled
// spelling of IMPLICIT-PROPS-DESIGN.md §11.1 (R0) and PROPS-REDTEAM-2026-09-03.md
// §6 item 7 — and report, by name and line, every `ASSUME` it will not touch.
//
// This is the file-level half of R0's sequencing item 5. It is NOT the LSP code
// action that item also asks for: jl4-lsp today has exactly one code action,
// `outOfScopeAssumeQuickFix` (`jl4-lsp/app/LSP/L4/Handlers.hs:1009`), and that
// one INSERTS a new `ASSUME` for an out-of-scope name rather than rewriting an
// existing one — so it currently offers the spelling R0 deprecates. Repointing
// it, and adding a rewrite action, is separate work.
//
// The script is idempotent (a second run changes nothing) and it never edits a
// file unless `--write` is given.
//
// Usage
//   node etc/migrate-assume.mjs [--write] [--add-heading] [--json] <file-or-dir>...
//
//   --write        apply the rewrite (default: dry run, report only)
//   --add-heading  a file with NO `§` heading gets one, because only a heading
//                  can carry a section GIVEN — a bare top-of-file `GIVEN` binds
//                  the DECIDE that follows it, not the file (probed 2026-09-05:
//                  the decision comes back as `<function>`). The heading goes
//                  after the file's prologue (blanks, IMPORTs, and the opening
//                  comment run that titles it) and is named from that opening
//                  comment when it reads as a title, else from the file stem.
//                  Without this flag such files are reported and left alone.
//   --json         machine-readable report on stdout
//
// What it rewrites — the term role, in either of its spellings:
//
//   ASSUME `annual income` IS A NUMBER              -- a fact, any type
//   ASSUME `is authorised` IS A FUNCTION FROM Person TO BOOLEAN
//   ASSUME map IS FOR ALL a AND b A FUNCTION FROM … -- polymorphic, multi-line
//   ASSUME jurisdiction IS A STRING TYPICALLY "SG"  -- TYPICALLY carries over
//   @desc the age of the person                     -- @desc carries over
//   ASSUME age IS A NUMBER
//
// becomes one parameter of the GIVEN indented under the nearest enclosing
// heading (R4's taught form), in source order:
//
//   § `Heading`
//       GIVEN `annual income` IS A NUMBER
//             `is authorised` IS A FUNCTION FROM Person TO BOOLEAN
//             age IS A NUMBER @desc the age of the person
//
// Placement is the ASSUME's OWN section, not the title `§`. The parser
// elaborates a section GIVEN to a 0-ary ASSUME at the head of that same section
// (L4.Desugar.desugarSectionGivens), so own-section placement is the identical
// AST modulo declaration order — which is what "answer-preserving" means here.
// Hoisting to the title heading is a visibility no-op only when no other
// section declares the same name; it is a stylistic choice a human can make
// afterwards, checked by the same oracle (`--verify`).
//
// What it refuses, each with a reason in the report:
//
//   type role       ASSUME T IS A TYPE           — an opaque sort; its ruled
//                                                   spelling is a bodiless
//                                                   DECLARE T (§11.1), migrated
//                                                   separately
//   app-form        GIVEN p IS A Person           — a signature-style ASSUME.
//                   ASSUME f p IS A BOOLEAN        Measured 2026-09-05: read by
//                                                   an @export, its function-typed
//                                                   section-GIVEN image is rejected
//                                                   by the export path ("Function
//                                                   type inputs are not supported
//                                                   for @export"), so the Blawx and
//                                                   relational exhibits keep it
//   refusal role    ASSUME `no X exists before …`  — a deliberate typed bottom.
//                                                   Its ruled spelling is REFUSE
//                                                   (R7); the DMN exhibits wait for
//                                                   REFUSE's DMN image, and
//                                                   daydate.l4's YMD is invalid
//                                                   input, not a refusal
//   local ASSUME    … WHERE ASSUME x IS A T        — the dead LocalAssume grammar;
//                                                   left for keyword removal
//   ditto           ASSUME x IS A BOOLEAN          — a `^` copies the declaration
//                   ^      y ^  ^ ^                  above it, so moving the
//                                                   declaration changes what is
//                                                   copied
//   overload        ASSUME foo IS A NUMBER         — type-directed name resolution.
//                   ASSUME foo IS A BOOLEAN          A section GIVEN cannot yet
//                                                   carry one name at two types:
//                                                   resolveSectionGiven pairs each
//                                                   parameter with its elaboration
//                                                   by raw name, so all of them
//                                                   collapse onto the first type
//   keep            a file whose SUBJECT is the keyword — one named for it, or
//                   one whose own comment says the ASSUME spelling is the thing
//                   under test. Migrating it would delete the exhibit
//   root section    an ASSUME before the first heading of a file that HAS
//                   headings — no heading to attach to; hoist by hand
//   no heading      a file with no `§` at all, unless --add-heading
//
// It also prints a READ ME line for every surviving comment that still names
// `ASSUME`. Those are not decidable mechanically: the comment may describe a
// declaration that is now a section GIVEN, or it may mark the file as one whose
// subject is the keyword. Three files were caught that way on 2026-09-05.
//
// Verification (`--verify <l4-binary>`): for every `.l4` under the inputs whose
// working copy differs from HEAD, compare `l4 run --json` on the committed
// version (`git show HEAD:<file>`) against the working copy, ignoring source
// ranges and file names. Values, kinds and error messages must be identical.
// Diagnostics that merely changed ORDER are reported as `reordered`, not as a
// difference. The script exits 1 on any real difference.
//
//   JL4_LIBRARY_PATH=$PWD/jl4-core/libraries \
//     node etc/migrate-assume.mjs --verify $(cabal list-bin l4) jl4/examples/ok

import { readdirSync, readFileSync, writeFileSync, statSync } from "node:fs";
import { join, basename, relative, resolve } from "node:path";
import { execFileSync } from "node:child_process";

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const argv = process.argv.slice(2);
const opts = { write: false, addHeading: false, json: false, verify: null };
const inputs = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--write") opts.write = true;
  else if (a === "--add-heading") opts.addHeading = true;
  else if (a === "--json") opts.json = true;
  else if (a === "--verify") opts.verify = argv[++i];
  else if (a === "-h" || a === "--help") {
    console.log(
      readFileSync(new URL(import.meta.url))
        .toString()
        .split("\n")
        .filter((l) => l.startsWith("//"))
        .map((l) => l.slice(3))
        .join("\n"),
    );
    process.exit(0);
  } else inputs.push(a);
}
if (inputs.length === 0) {
  console.error(
    "usage: node etc/migrate-assume.mjs [--write] [--add-heading] [--json] [--verify <l4>] <file-or-dir>...",
  );
  process.exit(2);
}

// ---------------------------------------------------------------------------
// File discovery
// ---------------------------------------------------------------------------

function l4FilesUnder(p) {
  const st = statSync(p);
  if (st.isFile()) return p.endsWith(".l4") ? [p] : [];
  const out = [];
  for (const e of readdirSync(p, { withFileTypes: true })) {
    if (
      e.name === "node_modules" ||
      e.name === "dist-newstyle" ||
      e.name.startsWith(".")
    )
      continue;
    const q = join(p, e.name);
    if (e.isDirectory()) out.push(...l4FilesUnder(q));
    else if (e.isFile() && e.name.endsWith(".l4")) out.push(q);
  }
  return out.sort();
}

// ---------------------------------------------------------------------------
// Lexical helpers (line level; L4 is layout-sensitive, and the forms we touch
// are regular enough that a line scanner is exact for them)
// ---------------------------------------------------------------------------

const RE_HEADING = /^(\s*)(§+)(.*)$/u;
const RE_ASSUME = /^(\s*)ASSUME\b(.*)$/;
const RE_GIVEN = /^(\s*)GIVEN\b(.*)$/;
const RE_GIVETH = /^(\s*)(GIVETH|GIVES)\b(.*)$/;
const RE_ANNOT = /^(\s*)@(\w+)\b(.*)$/;
const RE_BLANK = /^\s*$/;
const RE_LINE_COMMENT = /^\s*--/;
const RE_IMPORT = /^\s*IMPORT\b/;

function indentOf(line) {
  return line.match(/^\s*/)[0].length;
}

/** Split a line into code and trailing `--` comment (naive: no `--` inside strings/backticks). */
function splitTrailingComment(s) {
  let inStr = false,
    inTick = false;
  for (let i = 0; i < s.length - 1; i++) {
    const c = s[i];
    if (c === '"' && !inTick) inStr = !inStr;
    else if (c === "`" && !inStr) inTick = !inTick;
    else if (!inStr && !inTick && c === "-" && s[i + 1] === "-") {
      return [s.slice(0, i).replace(/\s+$/, ""), s.slice(i)];
    }
  }
  return [s.replace(/\s+$/, ""), ""];
}

/** Mark which lines are inside `{- … -}` block comments (no nesting). */
function blockCommentMask(lines) {
  const mask = new Array(lines.length).fill(false);
  let inBlock = false;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (inBlock) {
      mask[i] = true;
      if (l.includes("-}")) inBlock = false;
      continue;
    }
    const open = l.indexOf("{-");
    if (open >= 0) {
      // a line that opens a block: treat the whole line as commented unless the
      // block also closes on it and code precedes it — good enough for the corpus
      if (open === 0 || RE_BLANK.test(l.slice(0, open))) mask[i] = true;
      if (!l.slice(open).includes("-}")) inBlock = true;
    }
  }
  return mask;
}

/** Parse the head of an ASSUME: name, args (app-form), type text, TYPICALLY text. */
function parseAssumeHead(tail) {
  // tail: everything after the ASSUME keyword on the first line, joined with
  // continuation lines (newlines preserved so multi-line types can be re-indented)
  let s = tail.replace(/^\s+/, "");
  let name;
  if (s.startsWith("`")) {
    const end = s.indexOf("`", 1);
    if (end < 0) return null;
    name = s.slice(0, end + 1);
    s = s.slice(end + 1);
  } else {
    const m = s.match(/^[^\s`]+/);
    if (!m) return null;
    name = m[0];
    s = s.slice(name.length);
  }
  s = s.replace(/^[ \t]+/, "");
  // args before IS / TYPICALLY / end → app-form
  let args = "";
  const isAt = s.search(/(^|\s)IS(\s|$)/);
  const typAt = s.search(/(^|\s)TYPICALLY(\s|$)/);
  const cut = [isAt, typAt].filter((x) => x >= 0).sort((a, b) => a - b)[0];
  if (cut === undefined) {
    args = s.trim();
    s = "";
  } else {
    args = s.slice(0, cut).trim();
    s = s.slice(cut).replace(/^\s+/, "");
  }
  let type = null,
    typically = null;
  if (/^IS(\s|$)/.test(s)) {
    s = s.slice(2);
    const t = s.search(/(^|\s)TYPICALLY(\s|$)/);
    if (t >= 0) {
      type = s.slice(0, t);
      typically = s
        .slice(t)
        .replace(/^\s*TYPICALLY\s*/, "")
        .trim();
    } else type = s;
    type = type.replace(/^[ \t]*\n?/, "").replace(/\s+$/, "");
  } else if (/^TYPICALLY(\s|$)/.test(s)) {
    typically = s.replace(/^TYPICALLY\s*/, "").trim();
  }
  return { name, args, type, typically };
}

function classifyType(type) {
  if (type === null) return "untyped";
  const flat = type.replace(/\s+/g, " ").trim();
  // The type role is `IS A TYPE`, and it may carry a BODY:
  // `ASSUME Person IS A TYPE / HAS ATTRIBUTE \`mother\` IS A Person / …`.
  // Anchoring this on `TYPE$` — as it was until 2026-09-05 — matched only the
  // bare form, so the bodied one fell through to `term` and was rewritten.
  // Measured on `jl4/experiments/britishcitizen.l4`, where that turned a sort
  // with five attributes into a section-GIVEN parameter, next to the
  // `DECLARE Person IS A TYPE` already beneath it. Nothing caught it: the
  // experiments tree is in no goldened glob and the file's error count happened
  // not to change. The type role is `gm-opaque-declare`'s to migrate, whole.
  if (/^(A |AN )?TYPE\b/.test(flat)) return "type";
  if (/^(A |AN )?FUNCTION\b/.test(flat) || /^FOR ALL\b/.test(flat))
    return "function";
  return "term";
}

// Files that must keep their `ASSUME`s because their subject IS the keyword.
// Rewriting these would delete the exhibit the page or the test exists to show.
const KEEP = [
  // A file NAMED for the keyword exists to exercise the keyword. That covers
  // `doc/reference/types/assume-example.l4` (the worked example on the page that
  // documents ASSUME), `ok/assumes.l4`, `ok/assume-as-given.l4` (the fixture for
  // jl4-service's ASSUME-to-API-parameter promotion), `lsp/semantic-tokens/assume.l4`,
  // `relational/assumed*.l4`, `relational/not-ok/local-assume.l4` (the dead
  // LocalAssume grammar), `docassemble/assume-via-fn.l4` and
  // `implicit-assume-test.l4`. They migrate when the keyword goes, not before.
  [
    /(^|\/)[^/]*assume[^/]*\.l4$/i,
    "the file is named for the keyword: it exists to exercise ASSUME's own behaviour, so rewriting it would delete the exhibit",
  ],
  [
    /(^|\/)jl4\/examples\/not-ok\/tc\/parse-error[23]\.l4$/,
    "a deliberate parse-error exhibit whose error is anchored on the ASSUME line itself; migrating it would change what the file exhibits",
  ],
  [
    /(^|\/)jl4\/examples\/blawx\/not-ok\/zero-arity\.l4$/,
    "the subjectless-input rejection fixture: its own comment names 'a nullary top-level ASSUME' as the shape under test",
  ],
  [
    /(^|\/)jl4\/examples\/ok\/inert\/grounding-variants\.l4$/,
    "the file says in its own comment that it is deliberately NOT under a section, because the visualizer reports a name declared in one fully qualified and the box labels become unreadably wide",
  ],
  [
    /(^|\/)jl4\/examples\/ok\/section-scoping-descendant-rebind\.l4$/,
    "the regression is about a fully annotated ASSUME's inference-variable type falling into its own type group; the ASSUME spelling is the thing under test",
  ],
  [
    /(^|\/)jl4\/examples\/ok\/typically-basic\.l4$/,
    "covers TYPICALLY on all three surfaces it can appear on, one of which is an ASSUME declaration; migrating drops that third of the coverage while the keyword still exists",
  ],
];

// DITTO (`^`) repeats the declaration above it, positionally, and it reaches
// across blank lines and comments. Hoisting a declaration out from under a `^`
// silently reassigns what that `^` copies. Measured 2026-09-05: `ok/ditto.l4`
// and `lsp/semantic-tokens/ditto.l4` both stopped parsing when their ASSUMEs
// moved. The test has to be per-declaration, not per-file:
// `legal/british-citizen-act.l4` uses DITTO heavily for a `DECLARE Place`
// twenty lines below its ASSUMEs, and those ASSUMEs migrate safely.
const RE_DITTO = /^\s*\^/;

// Annotations that a section GIVEN parameter accepts in TRAILING position, so a
// standalone annotation line above an ASSUME can travel with it. Probed
// 2026-09-05 against `l4 check`: `GIVEN age IS A NUMBER @nlg "…"` and the same
// with `@ref` and `@desc` all check clean, while the LEADING form
// (`GIVEN @nlg "…" age IS A NUMBER`) is a parse error. Anything outside this set
// is refused rather than guessed at.
const CARRIED_ANNOTATIONS = new Set(["desc", "nlg", "ref"]);

// A refusal-role ASSUME: a deliberate typed bottom, whose ruled spelling is
// REFUSE (R7) and not a section GIVEN. Two ways to recognise one — the naming
// convention the corpus uses ("no X exists …"), and three known sites whose
// reason for staying is specific enough to be worth printing verbatim.
// The corpus names a refusal for what is missing ("no GST rate exists before
// commencement on 1994-04-01") or says outright that it refused
// (`YMD refused an out-of-range month or day`). Those two shapes cover every
// refusal-role site measured 2026-09-05; nothing else in the corpus is named
// that way, so the test does not over-reach.
const REFUSAL_NAME = /^`?(no\b|.*\brefus)/i;
const DMN_REASON =
  "refusal role, and DMN holds it: `L4.Dmn.Lower` writes a refusal into a FEEL literal " +
  "(Dmn/Lower.hs:2285) and KIE 8.44.0.Final then fails to compile the whole file " +
  "(ERR_COMPILING_FEEL, engine verdict FAILED; measured on CI 2026-09-05). Migrates when the " +
  "designed DMN image lands — PROPS-REDTEAM §6 item 6";
const REFUSAL_PATHS = [
  [
    /(^|\/)jl4-core\/libraries\/daydate\.l4$/,
    "refusal role, and not even that: an out-of-range YMD is invalid INPUT, so the fix is that " +
      "constructor's return type, not a change of bottom (REFUSE.md limits)",
  ],
  [/(^|\/)jl4\/examples\/dmn\//, DMN_REASON],
];

function titleFromStem(file) {
  const stem = basename(file, ".l4");
  const words = stem.replace(/[-_]+/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/**
 * A title for a synthesised heading. Prefer the file's own opening comment —
 * a headingless file almost always starts with one, and it is the author's own
 * name for the file, so using it invents nothing. Fall back to the stem.
 */
function titleFor(file, lines, mask) {
  let i = 0;
  while (i < lines.length && RE_BLANK.test(lines[i])) i++;
  if (i < lines.length && !mask[i] && RE_LINE_COMMENT.test(lines[i])) {
    const t = lines[i]
      .replace(/^\s*--+\s*/, "")
      .replace(/^#+\s*/, "") // some files open with a markdown-ish `-- # Title`
      .replace(/[`]/g, "")
      .trim();
    // Take it only if it reads as a title rather than a sentence about the file.
    // `error-directive-ambiguity.l4` opens "This is a test case for issue #89.",
    // which makes a poor heading and drags a `#` into the diagnostics.
    const titleish =
      t.length > 0 && t.length <= 60 && !/[.!?]$/.test(t) && !t.includes("#");
    if (titleish) return t;
  }
  return titleFromStem(file);
}

/**
 * Where a synthesised heading goes: after the file's prologue — leading blanks,
 * IMPORTs, a block comment, and the ONE opening comment run that titles the file
 * — and before the first thing the file actually says. Skipping every leading
 * comment would drop the heading past an interior section marker, which reads
 * as though the marker introduced it.
 */
function prologueEnd(lines, mask) {
  let at = 0;
  const skipBlanks = () => {
    while (at < lines.length && RE_BLANK.test(lines[at])) at++;
  };
  skipBlanks();
  while (at < lines.length && (RE_IMPORT.test(lines[at]) || mask[at])) {
    at++;
    skipBlanks();
  }
  if (at < lines.length && RE_LINE_COMMENT.test(lines[at]) && !mask[at]) {
    while (at < lines.length && RE_LINE_COMMENT.test(lines[at]) && !mask[at])
      at++;
    skipBlanks();
  }
  return at;
}

// ---------------------------------------------------------------------------
// The rewrite, one file
// ---------------------------------------------------------------------------

function migrateFile(file, text) {
  const lines = text.split("\n");
  const mask = blockCommentMask(lines);
  const rel = relative(process.cwd(), file);
  const report = {
    file: rel,
    rewritten: [],
    refused: [],
    addedHeading: null,
    changed: false,
  };

  const kept = KEEP.find(([re]) => re.test(rel));
  if (kept) {
    for (let i = 0; i < lines.length; i++) {
      if (!mask[i] && RE_ASSUME.test(lines[i]))
        report.refused.push({
          name: "(whole file)",
          line: i + 1,
          role: "keep",
          reason: kept[1],
        });
    }
    return report;
  }

  /** Does a DITTO line copy the declaration that ends at line `end`? */
  const dittoFollows = (end) => {
    for (let k = end + 1; k < lines.length; k++) {
      if (mask[k] || RE_BLANK.test(lines[k]) || RE_LINE_COMMENT.test(lines[k]))
        continue;
      return RE_DITTO.test(lines[k]);
    }
    return false;
  };

  // 1. headings (index, § column, level)
  const headings = [];
  for (let i = 0; i < lines.length; i++) {
    if (mask[i]) continue;
    const m = lines[i].match(RE_HEADING);
    if (m)
      headings.push({
        line: i,
        col: m[1].length + 1,
        level: m[2].length,
        text: lines[i],
      });
  }

  // 2. ASSUME declarations
  const decls = [];
  for (let i = 0; i < lines.length; i++) {
    if (mask[i]) continue;
    const m = lines[i].match(RE_ASSUME);
    if (!m) continue;
    const col = m[1].length + 1;
    // continuation lines: deeper-indented, non-blank; stop at blank/comment/dedent
    let end = i;
    while (end + 1 < lines.length) {
      const nx = lines[end + 1];
      if (RE_BLANK.test(nx) || RE_LINE_COMMENT.test(nx) || mask[end + 1]) break;
      if (indentOf(nx) + 1 <= col) break;
      end++;
    }
    // Preceding lines that belong to this declaration. Absorb a GIVEN/GIVETH
    // signature above ONLY when one is actually there: the run of deeper-indented
    // lines above an ASSUME is just as often another declaration's body (a
    // `DECLARE Person` / `HAS` / `name IS A STRING` block), and swallowing that
    // deletes it. Measured 2026-09-05 on `ok/nlg_lin1.l4`, which lost its
    // `Person` record to exactly that mistake.
    let start = i;
    let sig = false;
    {
      let k = i - 1;
      let top = i;
      while (
        k >= 0 &&
        !mask[k] &&
        !RE_BLANK.test(lines[k]) &&
        !RE_LINE_COMMENT.test(lines[k])
      ) {
        const isSigHead =
          (RE_GIVEN.test(lines[k]) || RE_GIVETH.test(lines[k])) &&
          indentOf(lines[k]) + 1 === col;
        const isContinuation = indentOf(lines[k]) + 1 > col;
        if (!isSigHead && !isContinuation) break;
        if (isSigHead) sig = true;
        top = k;
        k--;
      }
      if (sig) start = top;
    }
    // annotations sitting directly above, which travel with the declaration
    const annots = [];
    while (start - 1 >= 0 && !mask[start - 1]) {
      const am = lines[start - 1].match(RE_ANNOT);
      if (!am) break;
      annots.unshift({ kind: am[2], text: am[3].trim() });
      start--;
    }
    // the ASSUME's own text: first line tail + continuation lines
    const [firstCode, trailingComment] = splitTrailingComment(m[2]);
    const cont = lines.slice(i + 1, end + 1);
    const contCodes = cont.map((l) => splitTrailingComment(l)[0]);
    const tail = [firstCode, ...contCodes].join("\n");
    const head = parseAssumeHead(tail);
    decls.push({
      start,
      i,
      end,
      col,
      annots,
      sig,
      head,
      trailingComment,
      contIndent: cont.length ? Math.min(...cont.map(indentOf)) : null,
    });
  }

  // 3. classify and target

  // Type-directed name resolution: the same name ASSUMEd more than once, at a
  // different type each time. A section GIVEN cannot yet carry that shape.
  // Measured 2026-09-05: `resolveSectionGiven` (jl4-core/src/L4/TypeCheck.hs:641)
  // pairs each GivenSig parameter with its desugared 0-ary ASSUME elaboration by
  // raw name alone — `List.lookup (rawName nm) elaborations` — so when a name
  // repeats, every occurrence finds the FIRST elaboration and inherits its type
  // and its resolved binder. The rewritten file still `l4 check`s clean and
  // evaluates identically, because the elaborations themselves stay distinct and
  // they are what runs; only the checked module's GivenSig node is wrong. But
  // `prettyLayout` prints exactly that node, so `l4 batch` and the REPL re-emit
  // `GIVEN foo IS NUMBER` three times over and the re-emitted module no longer
  // type-checks. `ok/tdnr.l4` (foo at NUMBER/BOOLEAN/STRING) and `ok/misc.l4`
  // (coerce at four function types) were the only two files in the authored
  // corpus to reach it, and both failed the `prettyLayout round-trip` block.
  // Compare names the way the CHECKER does, not the way they are spelled: a
  // backticked name and a bare one denote the same identifier. Measured on
  // `jl4/experiments/macma3.l4`, which ASSUMEs `` `forfeiture` `` at
  // `FROM Order TO BOOLEAN` (line 94) and `forfeiture` at
  // `FROM Action TO BOOLEAN` (line 188), and likewise `confiscation` — the
  // checker reports "multiple definitions for the identifier" for both, so they
  // are one name, and a guard keyed on the raw spelling let both through.
  //
  // THIS GUARD IS MEANT TO BE DELETED. It exists only because the compiler
  // cannot yet carry an overloaded section binder; when that is repaired the
  // whole block goes and `ok/tdnr.l4` and `ok/misc.l4` migrate. Those two files
  // are that repair's acceptance test and are left un-migrated as its marker —
  // see IMPLICIT-PROPS-DESIGN.md §11.14, Finding 1, which records what "done"
  // looks like. The repair had NOT landed on `unstable` as of 2026-09-05: check
  // the tree rather than deleting this on the strength of a comment.
  //
  // Note `macma3.l4` is cited above ONLY as evidence that a backticked and a
  // bare name are one identifier. Its two vanishing "multiple definitions"
  // diagnostics are a SEPARATE, still-unowned declaration-order sensitivity in
  // TDNR candidate resolution that predates section binders; an earlier version
  // of §11.14 blamed them on the collapse and that attribution was retracted.
  const overloadKey = (n) => n.replace(/^`|`$/g, "");
  const overloaded = new Set();
  {
    const seen = new Set();
    for (const d of decls) {
      if (!d.head) continue;
      const k = overloadKey(d.head.name);
      if (seen.has(k)) overloaded.add(k);
      seen.add(k);
    }
  }

  const fileHasHeading = headings.length > 0;
  const plan = [];
  for (const d of decls) {
    const name = d.head ? d.head.name : "?";
    const refuse = (role, reason) =>
      report.refused.push({ name, line: d.i + 1, role, reason });
    if (!d.head) {
      refuse("unparsed", "could not parse the ASSUME head");
      continue;
    }
    if (overloaded.has(overloadKey(d.head.name))) {
      refuse(
        "overload",
        "the name is ASSUMEd more than once in this file, at a different type each time (type-directed name resolution); a section GIVEN collapses every occurrence onto the first parameter's type — see resolveSectionGiven, jl4-core/src/L4/TypeCheck.hs:641",
      );
      continue;
    }
    if (dittoFollows(d.end)) {
      refuse(
        "ditto",
        "a DITTO (`^`) line copies this declaration; moving it would change or break what the `^` repeats",
      );
      continue;
    }
    if (d.col > 1) {
      // Measured 2026-09-05: exactly one indented ASSUME exists in the authored
      // trees — `jl4/examples/relational/not-ok/local-assume.l4:20` — and it is the
      // dead LocalAssume grammar itself. A top-level ASSUME always starts at
      // column 1, so indentation is a sound test for the local form.
      refuse(
        "local",
        "indented ASSUME (the WHERE-local form); the LocalAssume grammar goes with the keyword",
      );
      continue;
    }
    if (d.sig || d.head.args) {
      refuse(
        "app-form",
        "signature-style ASSUME (GIVEN … ASSUME f x …): its function-typed section-GIVEN image is rejected on the export path (measured 2026-09-05, l4 blawx)",
      );
      continue;
    }
    const kind = classifyType(d.head.type);
    if (kind === "type") {
      refuse(
        "type",
        "uninterpreted type; its ruled spelling is a bodiless DECLARE (§11.1), migrated separately",
      );
      continue;
    }
    // The name decides that a site is refusal-role; the path only supplies a
    // better reason for that site staying. A path must never classify, or every
    // ordinary ASSUME in `jl4/examples/dmn/` would be mistaken for a refusal.
    if (REFUSAL_NAME.test(d.head.name)) {
      const sited = REFUSAL_PATHS.find(([re]) => re.test(rel));
      refuse(
        "refusal",
        sited
          ? sited[1]
          : "refusal role: a deliberate typed bottom, whose ruled spelling is REFUSE (R7), which no backend yet has an image for (REFUSE.md limits)",
      );
      continue;
    }
    const stray = d.annots.find((a) => !CARRIED_ANNOTATIONS.has(a.kind));
    if (stray) {
      refuse(
        "annotated",
        `carries @${stray.kind}, which this script has not established a GIVEN parameter accepts; ` +
          `only ${[...CARRIED_ANNOTATIONS].map((k) => "@" + k).join(", ")} were probed (2026-09-05) and carried`,
      );
      continue;
    }
    // enclosing heading = nearest heading above
    let h = null;
    for (const hh of headings) if (hh.line < d.i) h = hh;
    if (!h) {
      if (fileHasHeading) {
        refuse(
          "root",
          "sits before the first heading of a file that has headings; the root section cannot carry a binder — hoist by hand",
        );
        continue;
      }
      if (!opts.addHeading) {
        refuse("no-heading", "file has no § heading (run with --add-heading)");
        continue;
      }
    }
    plan.push({ d, h, role: kind === "function" ? "function" : "term" });
  }

  if (plan.length === 0) return report;

  // 4. synthesise a heading if needed, after the file's prologue
  let syntheticHeading = null;
  if (!fileHasHeading) {
    const at = prologueEnd(lines, mask);
    syntheticHeading = {
      insertBefore: at,
      col: 1,
      text: "§ `" + titleFor(file, lines, mask) + "`",
    };
    report.addedHeading = syntheticHeading.text;
  }

  // 5. build params per heading, in source order
  const byHeading = new Map(); // key: heading line (or -1 for synthetic) → params[]
  for (const p of plan) {
    const key = p.h ? p.h.line : -1;
    if (!byHeading.has(key)) byHeading.set(key, []);
    const { name, type, typically } = p.d.head;
    // A one-line type sits on the parameter's own line. A multi-line one (the
    // `FOR ALL a … A FUNCTION FROM … TO …` shape) keeps `IS` at the end of that
    // line and drops its own lines below, re-indented as a block so the
    // FROM/AND/TO alignment the author wrote survives.
    let head = name;
    let body = [];
    if (type !== null) {
      const raw = type.split("\n").map((l) => l.replace(/\s+$/, ""));
      const nonEmpty = raw.filter((l) => l.trim());
      if (nonEmpty.length <= 1) {
        head += " IS " + (nonEmpty[0] ?? "").trim();
      } else {
        head += " IS";
        const common = Math.min(...nonEmpty.map(indentOf));
        body = raw
          .filter((l, k) => l.trim() || k > 0)
          .map((l) => l.slice(common));
      }
    }
    const tailBits = [];
    if (typically !== null) tailBits.push("TYPICALLY " + typically);
    // A standalone annotation line above the declaration becomes a trailing
    // annotation on the parameter, which is where a section GIVEN takes one.
    for (const a of p.d.annots) tailBits.push(`@${a.kind} ${a.text}`.trimEnd());
    if (tailBits.length) {
      if (body.length) body[body.length - 1] += " " + tailBits.join(" ");
      else head += " " + tailBits.join(" ");
    }
    if (p.d.trailingComment) {
      if (body.length) body[body.length - 1] += "  " + p.d.trailingComment;
      else head += "  " + p.d.trailingComment;
    }
    byHeading.get(key).push({ head, body, decl: p.d });
    report.rewritten.push({
      name,
      line: p.d.i + 1,
      role: p.role,
      heading: p.h ? p.h.text.trim() : syntheticHeading.text,
    });
  }

  // 6. apply: delete declaration lines (bottom-up), then insert GIVEN blocks (bottom-up)
  const del = new Set();
  for (const p of plan) for (let k = p.d.start; k <= p.d.end; k++) del.add(k);

  // A comment that introduced nothing but the declarations we just moved is
  // left pointing at empty space ("-- Assumed external values with defaults",
  // then a blank line). Take it with them — but only when EVERY declaration it
  // introduces is going, so a comment heading a mixed group survives.
  for (let i = 0; i < lines.length; i++) {
    if (mask[i] || !RE_LINE_COMMENT.test(lines[i]) || del.has(i)) continue;
    let runEnd = i;
    while (
      runEnd + 1 < lines.length &&
      !mask[runEnd + 1] &&
      RE_LINE_COMMENT.test(lines[runEnd + 1])
    )
      runEnd++;
    let introduced = 0,
      kept = 0;
    for (let k = runEnd + 1; k < lines.length; k++) {
      if (mask[k] || RE_BLANK.test(lines[k])) continue;
      if (RE_LINE_COMMENT.test(lines[k]) || RE_HEADING.test(lines[k])) break;
      introduced++;
      if (!del.has(k)) kept++;
    }
    if (introduced > 0 && kept === 0)
      for (let k = i; k <= runEnd; k++) del.add(k);
    i = runEnd;
  }

  const inserts = []; // {afterLine, textLines}
  for (const [key, params] of byHeading) {
    const h = key === -1 ? null : headings.find((x) => x.line === key);
    const hcol = h ? h.col : 1;
    const givenIndent = " ".repeat(hcol - 1 + 4);
    const paramIndent = " ".repeat(hcol - 1 + 4 + "GIVEN ".length);
    // an existing section GIVEN directly under this heading? append to it
    let existing = null;
    if (h) {
      let j = h.line + 1;
      while (
        j < lines.length &&
        (RE_BLANK.test(lines[j]) || RE_LINE_COMMENT.test(lines[j]))
      )
        j++;
      const gm = j < lines.length ? lines[j].match(RE_GIVEN) : null;
      if (gm && gm[1].length + 1 > hcol) {
        // find its param column and its last line
        const pcol = lines[j].indexOf("GIVEN") + "GIVEN ".length;
        let last = j;
        while (
          last + 1 < lines.length &&
          !RE_BLANK.test(lines[last + 1]) &&
          indentOf(lines[last + 1]) + 1 > gm[1].length + 1 &&
          !del.has(last + 1)
        )
          last++;
        existing = { last, pcol };
      }
    }
    const render = (firstPrefix, restPrefix) => {
      const bodyIndent = restPrefix + "    ";
      return params.flatMap((p, idx) => [
        (idx === 0 ? firstPrefix : restPrefix) + p.head,
        ...p.body.map((l) => (l.trim() ? bodyIndent + l : "")),
      ]);
    };
    if (existing) {
      const pre = " ".repeat(existing.pcol);
      inserts.push({ afterLine: existing.last, textLines: render(pre, pre) });
    } else if (h) {
      inserts.push({
        afterLine: h.line,
        textLines: render(givenIndent + "GIVEN ", paramIndent),
      });
    } else {
      inserts.push({
        afterLine: -1,
        textLines: [
          syntheticHeading.text,
          ...render(givenIndent + "GIVEN ", paramIndent),
          "",
        ],
      });
    }
  }

  const out = [];
  for (let k = 0; k < lines.length; k++) {
    if (syntheticHeading && k === syntheticHeading.insertBefore) {
      const ins = inserts.find((x) => x.afterLine === -1);
      out.push(...ins.textLines);
    }
    if (!del.has(k)) out.push(lines[k]);
    for (const ins of inserts)
      if (ins.afterLine === k) out.push(...ins.textLines);
  }
  if (syntheticHeading && syntheticHeading.insertBefore >= lines.length) {
    out.push(...inserts.find((x) => x.afterLine === -1).textLines);
  }
  // collapse blank runs left behind by deletions (never more than two blank lines in a row)
  const collapsed = [];
  let blanks = 0;
  for (const l of out) {
    if (RE_BLANK.test(l)) {
      blanks++;
      if (blanks > 2) continue;
    } else blanks = 0;
    collapsed.push(l);
  }
  // a deleted block that sat between two blank lines leaves two; keep one
  const final = [];
  for (let k = 0; k < collapsed.length; k++) {
    if (
      RE_BLANK.test(collapsed[k]) &&
      k + 1 < collapsed.length &&
      RE_BLANK.test(collapsed[k + 1]) &&
      k > 0 &&
      !RE_BLANK.test(collapsed[k - 1])
    ) {
      // two blanks after a non-blank: keep both only if the original had them; we cannot
      // know cheaply, so keep one — the corpus uses single blank separators
      continue;
    }
    final.push(collapsed[k]);
  }
  // A comment that still talks about `ASSUME` after the rewrite either
  // describes a declaration that is now a section GIVEN, or marks the file as
  // one whose subject is the keyword. Neither is decidable here — say so, and
  // let a human read it. Three files were caught this way on 2026-09-05.
  for (let k = 0; k < lines.length; k++) {
    if (
      mask[k] ||
      del.has(k) ||
      !RE_LINE_COMMENT.test(lines[k]) ||
      !/\bASSUME/.test(lines[k])
    )
      continue;
    (report.warnings ??= []).push({
      line: k + 1,
      text: lines[k].trim().slice(0, 100),
    });
  }

  report.changed = true;
  report.output = final.join("\n");
  return report;
}

// ---------------------------------------------------------------------------
// Verification oracle
// ---------------------------------------------------------------------------

function normalizeRun(json, file) {
  const stem = basename(file);
  const scrub = (s) =>
    String(s)
      .replaceAll(stem, "<file>")
      .replace(/<file>:\d+:\d+(-\d+(:\d+)?)?/g, "<file>:<range>")
      .replace(/Range:\s*\d+:\d+-\d+:\d+/g, "Range: <range>")
      .replace(/\(at <file>:<range>\)/g, "(at <range>)")
      .replace(/\b\d+:\d+-\d+:\d+\b/g, "<range>")
      .replace(/\b\d+:\d+-\d+\b/g, "<range>");
  let d;
  try {
    d = JSON.parse(json);
  } catch {
    return { ok: null, raw: scrub(json) };
  }
  return {
    ok: d.ok,
    results: (d.results || []).map((r) => ({
      kind: r.kind,
      value: scrub(r.value ?? ""),
    })),
    errors: (d.diagnostics || [])
      .filter((x) => /DiagnosticSeverity_Error/.test(x))
      .map(scrub),
  };
}

function runL4(bin, file) {
  try {
    return execFileSync(bin, ["run", "--json", file], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      maxBuffer: 64 << 20,
    });
  } catch (e) {
    return e.stdout || "";
  }
}

function verifyFile(bin, file) {
  const rel = relative(process.cwd(), file);
  let orig;
  try {
    orig = execFileSync("git", ["show", `HEAD:${rel}`], {
      encoding: "utf8",
      maxBuffer: 64 << 20,
    });
  } catch {
    return { file: rel, status: "no-HEAD-copy" };
  }
  const tmp = resolve(file + ".migrate-assume.orig.l4");
  writeFileSync(tmp, orig);
  try {
    const a = normalizeRun(runL4(bin, tmp), tmp);
    const b = normalizeRun(runL4(bin, file), file);
    if (JSON.stringify(a) === JSON.stringify(b))
      return { file: rel, status: "identical" };
    // A declaration that moves can move its diagnostic up or down the report.
    // Say so separately: the same diagnostics in a different order is not a
    // change of answer. `l4 run --json` hands back one blob per run, so split it
    // per `File:` record before comparing as a multiset.
    const bag = (x) =>
      JSON.stringify(
        (x.errors || [])
          .flatMap((e) => e.split(/^(?=File:)/m))
          .map((s) => s.trim())
          .filter(Boolean)
          .sort(),
      );
    const reordered =
      a.ok === b.ok &&
      JSON.stringify(a.results) === JSON.stringify(b.results) &&
      bag(a) === bag(b);
    return {
      file: rel,
      status: reordered ? "reordered" : "DIFFERENT",
      before: a,
      after: b,
    };
  } finally {
    try {
      execFileSync("rm", ["-f", tmp]);
    } catch {}
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

const files = inputs.flatMap((p) => l4FilesUnder(resolve(p)));
const reports = [];
for (const f of files) {
  const text = readFileSync(f, "utf8");
  const r = migrateFile(f, text);
  if (r.changed && opts.write) writeFileSync(f, r.output);
  if (r.rewritten.length || r.refused.length) reports.push(r);
}

if (opts.verify) {
  // Verify every `.l4` under the inputs whose working copy differs from HEAD —
  // not merely the files THIS run rewrote. The rewrite is idempotent, so a
  // verify pass after a `--write` pass would otherwise find nothing to check.
  const changed = execFileSync(
    "git",
    ["diff", "--name-only", "HEAD", "--", ...inputs],
    { encoding: "utf8" },
  )
    .split("\n")
    .filter((l) => l.endsWith(".l4"));
  if (changed.length === 0)
    console.error(
      "note: no .l4 file under the inputs differs from HEAD — nothing to verify",
    );
  const results = changed.map((f) => verifyFile(opts.verify, resolve(f)));
  const bad = results.filter((x) => x.status === "DIFFERENT");
  const reordered = results.filter((x) => x.status === "reordered");
  for (const x of results) console.log(`${x.status.padEnd(12)} ${x.file}`);
  for (const x of [...bad, ...reordered])
    console.log(JSON.stringify(x, null, 2));
  console.log(
    `\nverify: ${results.filter((x) => x.status === "identical").length} identical, ${reordered.length} reordered, ${bad.length} different`,
  );
  process.exit(bad.length ? 1 : 0);
}

const summary = {
  files: reports.length,
  rewritten: 0,
  refused: 0,
  byRole: {},
  refusedByRole: {},
  byTree: {},
};
const tree = (f) => f.split("/").slice(0, 3).join("/");
summary.warned = 0;
for (const r of reports) {
  for (const x of r.rewritten) {
    summary.rewritten++;
    summary.byRole[x.role] = (summary.byRole[x.role] || 0) + 1;
    const t = tree(r.file);
    summary.byTree[t] = summary.byTree[t] || { rewritten: 0, refused: 0 };
    summary.byTree[t].rewritten++;
  }
  for (const x of r.refused) {
    summary.refused++;
    summary.refusedByRole[x.role] = (summary.refusedByRole[x.role] || 0) + 1;
    const t = tree(r.file);
    summary.byTree[t] = summary.byTree[t] || { rewritten: 0, refused: 0 };
    summary.byTree[t].refused++;
  }
  summary.warned += (r.warnings || []).length;
}

if (opts.json) {
  console.log(
    JSON.stringify(
      {
        mode: opts.write ? "write" : "dry-run",
        summary,
        files: reports.map(({ output, ...rest }) => rest),
      },
      null,
      2,
    ),
  );
} else {
  for (const r of reports) {
    console.log(
      `${r.file}${r.addedHeading ? `   [+ heading: ${r.addedHeading}]` : ""}`,
    );
    for (const x of r.rewritten)
      console.log(
        `  rewrite  L${x.line}  ${x.role.padEnd(8)} ${x.name}  → ${x.heading}`,
      );
    for (const x of r.refused)
      console.log(
        `  LEAVE    L${x.line}  ${x.role.padEnd(8)} ${x.name}  — ${x.reason}`,
      );
    for (const x of r.warnings || [])
      console.log(
        `  READ ME  L${x.line}  a comment still names ASSUME: ${x.text}`,
      );
  }
  console.log(
    `\n${opts.write ? "wrote" : "dry run:"} ${summary.rewritten} rewritten (${
      Object.entries(summary.byRole)
        .map(([k, v]) => `${k} ${v}`)
        .join(", ") || "none"
    }), ${summary.refused} left (${
      Object.entries(summary.refusedByRole)
        .map(([k, v]) => `${k} ${v}`)
        .join(", ") || "none"
    }) across ${summary.files} files`,
  );
  for (const [t, c] of Object.entries(summary.byTree))
    console.log(`  ${t}: ${c.rewritten} rewritten, ${c.refused} left`);
  if (summary.warned)
    console.log(
      `\n${summary.warned} surviving comment(s) still name ASSUME — read each (marked READ ME above): the comment may describe a declaration that is now a section GIVEN.`,
    );
}
