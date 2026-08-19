// The Blawx re-save fixpoint (BLAWX-EXPORT-SPEC §8.12 R12), minus the browser
// chrome: for every workspace and every test in a `.blawx` golden, deserialise
// our `xml_content` through the REAL Blawx block restorers and regenerate
// s(CASP) with the REAL generator, then byte-diff against our
// `scasp_encoding`.
//
// This is the exact pair of lines the app runs when a user hits Save --
// `buttons.js:18-24` (updateWorkspace) and `buttons.js:480-487`
// (updateBlawxTest):
//
//     payload.xml_content   = Blockly.Xml.domToText(Blockly.Xml.workspaceToDom(ws));
//     payload.scasp_encoding = sCASP.workspaceToCode(ws);
//
// with the load side at `buttons.js:444-447` / `:469-473`:
//
//     xml = Blockly.utils.xml.textToDom(output_object.xml_content);
//     Blockly.Xml.domToWorkspace(xml, ws);
//
// The gate is on `scasp_encoding` ONLY. Re-saved `xml_content` legitimately
// differs from ours (Blockly re-serialisation adds menu caches and reorders
// attributes); that is out of scope. What must hold is that our XML (a)
// deserialises cleanly through the restorers and (b) makes the generator
// regenerate exactly the bytes we stored.
//
// Why the byte-diff and not "the XML parses": a MISSING `<mutation>` element
// fails SILENTLY. Measured on the reference evidence -- dropping the first
// mutation from life_act's sec_1_section threw nothing and produced 17,649
// bytes instead of 17,651, a quiet two-byte change in the generated logic.
// (An unknown block `type`, by contrast, throws loudly.) The byte-diff is the
// only detector for mutation-shaped mistakes. Do not weaken this to a
// well-formedness check.
//
// ---------------------------------------------------------------------------
// PROVENANCE -- this harness is only as true as the checkout it reads.
//
//   Blawx:   /Volumes/transcend/src/blawx @ 02eded1 (branch mengwong/main;
//            checkout HEAD e36ac8f is 02eded1 plus a docs-only CLAUDE.md edit
//            -- no JS differs).  Override with $BLAWX_CHECKOUT.
//   Blockly: 10.1.3.  NOT vendored in the checkout -- the Blawx Dockerfile
//            does a bare, unpinned `npm install blockly`, so the deployed
//            version is whatever npm served on image-build day.  10.1.3 is
//            what the running `lexpedite/blawx:latest` container ships
//            (`docker exec blawx cat .../blockly/package.json`), and npm's
//            `blockly@10.1.3` is byte-identical to the container's copy (md5
//            over blockly_compressed.js, blocks_compressed.js,
//            javascript_compressed.js, msg/en.js).  Override with
//            $BLAWX_BLOCKLY_DIR.
//
//   DRIFT RISK: upstream Blawx changing `scasp_generator.js` or
//            `blawx-blocks.js`, or a rebuilt container image picking up a
//            newer Blockly, silently invalidates every claim this harness
//            makes.  The Blockly version is checked and a mismatch WARNS
//            loudly; nothing can detect the Blawx-side drift except re-reading
//            the generator.  If a tier-2 browser pass ever disagrees with a
//            green harness, check `Blockly.VERSION` in the browser console
//            FIRST -- Blawx's own CHANGELOG gives that advice for the same
//            reason.
//
//   HEADLESS != RENDERED.  `Generator.workspaceToCode` provably reads only
//            `workspace.getTopBlocks(true)` plus block/field/mutation state,
//            and headless matched the container's stored bytes on 5/5
//            reference workspaces.  But the reference evidence exercises the
//            127 Blawx block types only partially; a block whose
//            `domToMutation` reached for rendering could behave differently.
//            The tier-2 browser pass remains the authority.  This is the
//            fast, cheap 99%.
//
// ---------------------------------------------------------------------------
// THE RESTORERS ARE NOT THE WHOLE LOAD PATH.  An earlier version of this
// harness loaded only the block definitions, the mutators and the generator,
// on the premise that the remaining editor scripts are "UI-only and
// contribute nothing to the generator".  That premise is FALSE and it hid a
// real defect for a whole build:
//
//   * `attributes.js:1-21` registers `setAttributeType` on `demoWorkspace`,
//     and BOTH editor templates load it (`blawx.html:168`, `test.html:164`).
//     On every BLOCK_CREATE it reinstalls the connection checks of every
//     `attribute_selector` -- with NO `if (attributeType)` guard, unlike
//     `mutators.js:165`.  `blawxTypeToBlocklyType("")` is `'OBJECT'`, and
//     `Connection.setCheck` UNPLUGS an already-connected incompatible child,
//     so an empty `attributetype` tore the `head_tail`/`empty_list`/
//     `number_value` operands off six golden rows.  Regenerating then emitted
//     `[X | Rest].` as a naked top-level statement and `running_total(,)` for
//     the clause that lost its arguments.
//   * `onCategoryChange` + `updateLocalCategories` (`mutators.js:230`,
//     `blawx-blocks.js:5556`) are registered by the templates themselves
//     (`blawx.html:100-101`, `test.html:149-150`) and can `setValue` a
//     dropdown whose current option is not in the rebuilt menu.
//
// None of this is visible synchronously: Blockly queues events and drains
// them on a macrotask, so `domToWorkspace(); workspaceToCode()` in one tick
// sees zero listeners run.  In the browser all of them land long before the
// user clicks Save.  So this harness boots the page's globals, loads
// `attributes.js`, registers the two template listeners, and AWAITS the event
// queue before generating.  `getAllWorkspaces` (`drawers.js:416-434`, a
// synchronous XHR for the ruledoc's workspaces) is modelled by the .blawx
// file's own workspace rows, which is exactly what the server would return.
//
// Still omitted, deliberately: buttons.js/drawers.js/import.js/blawx2scasp.js/
// context_menus.js, which need XHR, cookies and DOM chrome.  Of these only
// import.js registers a listener, and only to mirror deletions into
// `importDictionary` -- it never touches the demo workspace's blocks.
//
// ---------------------------------------------------------------------------
// TIMEZONE -- date and datetime blocks encode via the LOCAL-time `Date`
// constructor (`scasp_generator.js:528-535`, `:790-800`:
// `new Date(y, m-1, d).valueOf()/1000`), so the epoch integer a workspace
// generates is TIMEZONE-DEPENDENT.  This harness pins `TZ=UTC` unless the
// caller sets `TZ`, and prints the zone it used.
//
// The coordinator's tier-2 browser pass MUST run in the SAME zone.  A UI
// session on a laptop set to +08 will not match a harness pinned to UTC on any
// date-bearing corpus -- that is the one way a green harness can still fail
// tier 2.  Currently latent, not active: the four P1/P3 goldens contain zero
// numeric date literals.
//
// ---------------------------------------------------------------------------
// POSTURE (R13): optional-when-present, NEVER a build dependency.  Skips
// silently (exit 0, one line, no stack) when the Blawx checkout or the node
// dependencies are absent.  Nothing is added to the repo's `package.json` or
// lockfile -- the lockfile is already drifted and a new entry would block CI
// (same reasoning as `etc/validate-dmn.mjs:69-80`).  Its dependencies live in
// their own project, committed beside this file and outside the root
// workspaces globs so npm cannot hoist it:
//
//     npm install --prefix etc/blawx-fixpoint-harness.deps   # once
//     node etc/blawx-fixpoint-harness.mjs                    # all four goldens
//
// or, with no install at all (this route needs no file in the tree, and is
// what to use on a machine where the deps directory was never populated):
//
//     npx --yes --package=jsdom --package=blockly@10.1.3 --package=js-yaml \
//       node etc/blawx-fixpoint-harness.mjs jl4/examples/blawx/expected/foo.blawx
//
// Environment:
//   BLAWX_CHECKOUT          Blawx source checkout (default /Volumes/transcend/src/blawx)
//   BLAWX_BLOCKLY_DIR       directory holding blockly_compressed.js et al
//   BLAWX_HARNESS_DEPS      directory whose node_modules holds jsdom/js-yaml/blockly
//   BLAWX_FIXPOINT_ISOLATE  =1 to boot a fresh jsdom realm per row (contamination check)
//   TZ                      pinned to UTC when unset; see TIMEZONE above

import { createRequire } from "node:module";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join, dirname, resolve, basename } from "node:path";
import { fileURLToPath } from "node:url";

// Pin the zone BEFORE anything constructs a Date. Node honours a runtime
// assignment to process.env.TZ, and jsdom's realm shares this process's zone.
const TZ_PINNED = process.env.TZ === undefined;
if (TZ_PINNED) process.env.TZ = "UTC";
const TZ = process.env.TZ;

const SKIP = (why) => {
  console.log(`blawx-fixpoint-harness: skipped -- ${why}`);
  process.exit(0);
};

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

// ---- optional-dependency resolution ---------------------------------------
// Four sources, in order, none of which touches the repo's package.json:
//   1. an explicit $BLAWX_HARNESS_DEPS, or etc/blawx-fixpoint-harness.deps
//      (the project committed beside this file);
//   2. p3-design/harness-deps, the scratch location this was developed in;
//   3. the repo root's own node_modules, if someone happens to have the
//      packages there;
//   4. the npx cache -- `npx --package=X node script.mjs` installs X into
//      ~/.npm/_npx/<hash>/node_modules and puts only its .bin on PATH, so
//      require() must be anchored inside that cache directory
//      (etc/validate-dmn.mjs:69-98 does the same walk).
function anchors() {
  const c = [];
  const depDirs = [
    process.env.BLAWX_HARNESS_DEPS,
    join(repoRoot, "etc", "blawx-fixpoint-harness.deps"),
    join(repoRoot, "p3-design", "harness-deps"),
    repoRoot,
  ];
  for (const d of depDirs) {
    if (d && existsSync(join(d, "node_modules")))
      c.push(join(d, "package.json"));
  }
  for (const entry of (process.env.PATH ?? "").split(":")) {
    if (entry.includes("_npx") && entry.endsWith("node_modules/.bin")) {
      c.push(join(dirname(entry), "anchor.js"));
    }
  }
  c.push(import.meta.url);
  return c;
}

function need(spec) {
  for (const from of anchors()) {
    try {
      return createRequire(from)(spec);
    } catch {}
  }
  return null;
}

function needDir(spec) {
  for (const from of anchors()) {
    try {
      return dirname(createRequire(from).resolve(spec));
    } catch {}
  }
  return null;
}

// ---- the Blawx checkout: block definitions + the generator ----------------
const CHECKOUT = process.env.BLAWX_CHECKOUT ?? "/Volumes/transcend/src/blawx";
const STATIC = join(CHECKOUT, "blawx", "static", "blawx");
if (!existsSync(join(STATIC, "scasp_generator.js"))) {
  SKIP(`no Blawx checkout at ${CHECKOUT} (set $BLAWX_CHECKOUT)`);
}

// ---- Blockly ---------------------------------------------------------------
const BLOCKLY =
  (process.env.BLAWX_BLOCKLY_DIR && existsSync(process.env.BLAWX_BLOCKLY_DIR)
    ? process.env.BLAWX_BLOCKLY_DIR
    : null) ??
  (existsSync(join(STATIC, "blockly", "blockly_compressed.js"))
    ? join(STATIC, "blockly")
    : null) ??
  needDir("blockly/package.json");
if (!BLOCKLY) {
  SKIP(
    "blockly not resolvable (npm install --prefix etc/blawx-fixpoint-harness.deps)",
  );
}

const jsdom = need("jsdom");
if (!jsdom)
  SKIP(
    "jsdom not resolvable (npm install --prefix etc/blawx-fixpoint-harness.deps)",
  );
const yaml = need("js-yaml");
if (!yaml)
  SKIP(
    "js-yaml not resolvable (npm install --prefix etc/blawx-fixpoint-harness.deps)",
  );

const blocklyVersion = JSON.parse(
  readFileSync(join(BLOCKLY, "package.json"), "utf8"),
).version;
if (blocklyVersion !== "10.1.3") {
  console.warn(
    `blawx-fixpoint-harness: WARNING blockly ${blocklyVersion} at ${BLOCKLY}; the deployed ` +
      `container ships 10.1.3. A green run under a different Blockly does not predict tier 2.`,
  );
}

// ---- the realm -------------------------------------------------------------
// Load order is `blawx.html:43-48,76-77,168` and its inline script at
// `:100-101` -- see "THE RESTORERS ARE NOT THE WHOLE LOAD PATH" above for what
// is in and what is out.
//
// The one non-obvious mechanic: append real <script> ELEMENTS, do not
// win.eval() the sources. `scasp_generator.js:10` is a top-level
// `const sCASP = new Blockly.Generator('sCASP')`; inside an eval() that
// binding lands in the eval's own declarative scope and is gone on return.
// Script elements put it in the realm's global lexical environment, shared
// across scripts, exactly as a browser does.
const LOAD_ORDER = [
  join(BLOCKLY, "blockly_compressed.js"), // defines the global `Blockly`
  join(BLOCKLY, "msg/en.js"), // Blockly.Msg -- block defs read it at definition time
  join(BLOCKLY, "javascript_compressed.js"), // blawx-blocks.js touches Blockly.JavaScript
  join(BLOCKLY, "blocks_compressed.js"), // stock logic/math/text blocks Blawx reuses
  join(STATIC, "blawx-blocks.js"), // block defs + mutationToDom/domToMutation (the restorers)
  join(STATIC, "mutators.js"), // mutator helper blocks + onCategoryChange
  join(STATIC, "scasp_generator.js"), // `const sCASP = new Blockly.Generator('sCASP')`
];
for (const f of LOAD_ORDER) {
  if (!existsSync(f)) SKIP(`missing ${f}`);
}
const ATTRIBUTES_JS = join(STATIC, "attributes.js");
if (!existsSync(ATTRIBUTES_JS)) SKIP(`missing ${ATTRIBUTES_JS}`);

const SOURCES = LOAD_ORDER.map((f) => readFileSync(f, "utf8"));
const ATTRIBUTES_SRC = readFileSync(ATTRIBUTES_JS, "utf8");

// The globals the two editor templates create before the listener scripts run
// (blawx.html:79-101, test.html:112-150), plus the two the omitted UI files
// would have created and that `getKnownCategories` reads.
const PAGE_GLOBALS = `
  var workspace_is_test = false;
  var importDictionary = {};
  var knownCategories = [];
  var localCategories = [];
  var __all_workspaces = [];
  var getAllWorkspaces = function () { return __all_workspaces; };
  var demoWorkspace = new Blockly.Workspace();
`;
// blawx.html:100-101 / test.html:149-150, verbatim.
const TEMPLATE_LISTENERS = `
  demoWorkspace.addChangeListener(onCategoryChange);
  demoWorkspace.addChangeListener(updateRelationshipDeclaration);
`;

const { JSDOM, VirtualConsole } = jsdom;
let jsdomErrors = 0;

function bootRealm() {
  const vc = new VirtualConsole();
  vc.on("jsdomError", (e) => {
    jsdomErrors++;
    console.warn(`blawx-fixpoint-harness: jsdomError ${e.message}`);
  });
  const win = new JSDOM(
    `<!doctype html><html><head></head><body></body></html>`,
    {
      runScripts: "dangerously",
      virtualConsole: vc,
    },
  ).window;
  const add = (src) => {
    const s = win.document.createElement("script");
    s.textContent = src;
    win.document.head.appendChild(s);
  };
  SOURCES.forEach(add);
  if (win.eval("typeof Blockly") !== "object")
    SKIP("Blockly failed to initialise under jsdom");
  if (win.eval("typeof sCASP") !== "object")
    SKIP("scasp_generator.js failed to define sCASP");
  add(PAGE_GLOBALS);
  add(ATTRIBUTES_SRC); // registers setAttributeType on demoWorkspace
  add(TEMPLATE_LISTENERS);
  return win;
}

const ISOLATE = process.env.BLAWX_FIXPOINT_ISOLATE === "1";
let sharedWin = ISOLATE ? null : bootRealm();

// Blockly's `eventUtils.fire` pushes onto a queue and schedules the drain with
// setTimeout(0); jsdom's timers run on this process's event loop, so awaiting a
// realm-side macrotask is what lets the change listeners actually run. Three
// ticks, not one: a listener that calls setValue re-enters fire().
const drain = async (win) => {
  for (let i = 0; i < 3; i++)
    await win.eval("new Promise(r => setTimeout(r, 0))");
};

// The fixpoint predicate: textToDom -> domToWorkspace -> (listeners) ->
// sCASP.workspaceToCode.  `Blockly.Xml.textToDom` does NOT exist in Blockly
// 10.x; the live entry point is `Blockly.utils.xml.textToDom`, which is also
// what Blawx itself calls (buttons.js:444, drawers.js:12,75,
// blawx-blocks.js:5528).
//
// `siblings` models the server response `getAllWorkspaces` would get, so that
// `getKnownCategories` sees the ruledoc's category declarations even when the
// row under test is a section workspace that declares none. window.onload sets
// knownCategories, and the workspace XHR resolves independently, so the real
// ordering is racy; the benign order is modelled here, and the malign one
// (empty knownCategories, every category dropdown reset to `none`) would
// corrupt any workspace, not just ours.
async function regenerate(xmlContent, siblings) {
  const win = ISOLATE ? bootRealm() : sharedWin;
  win.__xml = xmlContent;
  win.__siblings = siblings;
  try {
    win.eval(`
      __all_workspaces = window.__siblings;
      demoWorkspace.clear();
    `);
    await drain(win);
    win.eval(`
      knownCategories = getKnownCategories();
      updateLocalCategories();
      Blockly.Xml.domToWorkspace(Blockly.utils.xml.textToDom(window.__xml), demoWorkspace);
    `);
    await drain(win);
    return win.eval("sCASP.workspaceToCode(demoWorkspace)");
  } finally {
    if (ISOLATE) win.close();
  }
}

// ---- inputs ----------------------------------------------------------------
const defaultDir = join(repoRoot, "jl4", "examples", "blawx", "expected");
let files = process.argv.slice(2);
if (files.length === 0) {
  if (!existsSync(defaultDir)) SKIP(`no input files and no ${defaultDir}`);
  files = readdirSync(defaultDir)
    .filter((f) => f.endsWith(".blawx") && !f.endsWith(".actual.blawx"))
    .sort()
    .map((f) => join(defaultDir, f));
}
if (files.length === 0) SKIP("no input files");

// ---- comparison ------------------------------------------------------------
// `.trim()` on BOTH sides, deliberately. Every regeneration comes out exactly
// one trailing "\n" longer than what the server stores, uniformly, because
// `blawx/serializers.py:3-7` runs the payload through a DRF ModelSerializer
// and DRF maps `models.TextField` -> `serializers.CharField`, whose
// `trim_whitespace` defaults to True (confirmed in the container: DRF 3.14.0 /
// Django 4.2.5). So the stored value is always `generated.strip()`. Anyone who
// "tightens" this to `===` gets a failure on every input, for a reason that
// has nothing to do with the emitter.
function firstDivergence(stored, got) {
  const a = stored.split("\n");
  const b = got.split("\n");
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  if (i === a.length && i === b.length) return null;
  return {
    line: i + 1,
    stored: a[i] ?? "<eof>",
    got: b[i] ?? "<eof>",
    nStored: a.length,
    nGot: b.length,
  };
}

const clip = (s, n = 300) =>
  s.length > n ? `${s.slice(0, n)}...(+${s.length - n} chars)` : s;

let checked = 0;
let failed = 0;
let empty = 0;
const failures = [];

for (const file of files) {
  let rows;
  try {
    rows = yaml.load(readFileSync(file, "utf8"));
  } catch (e) {
    console.log(`FAIL ${basename(file)}: YAML parse: ${e.message}`);
    failures.push(`${basename(file)}: YAML parse: ${e.message}`);
    failed++;
    continue;
  }
  if (!Array.isArray(rows)) {
    console.log(`FAIL ${basename(file)}: not a dumpdata list`);
    failures.push(`${basename(file)}: not a dumpdata list`);
    failed++;
    continue;
  }
  // What `getAllWorkspaces()` would fetch for this ruledoc.
  const siblings = rows
    .filter((r) => (r?.fields ?? {}).workspace_name !== undefined)
    .map((r) => ({ xml_content: r.fields.xml_content ?? "" }));

  for (const row of rows) {
    const f = row?.fields ?? {};
    const name = f.workspace_name ?? f.test_name;
    if (name === undefined) continue; // blawx.ruledoc row: no editor, no XML
    const kind = String(row.model ?? "?")
      .split(".")
      .pop();
    const label = `${basename(file)} ${kind}/${name}`;
    const xml = f.xml_content ?? "";
    const stored = String(f.scasp_encoding ?? "");

    if (xml.trim() === "") {
      // Only defensible when there is nothing to regenerate. An empty
      // xml_content beside a non-empty scasp_encoding is the data loss R12
      // exists to prevent: opening that workspace and saving would blank it.
      if (stored.trim() !== "") {
        console.log(
          `FAIL ${label}: empty xml_content but ${stored.trim().length} bytes of scasp_encoding`,
        );
        failures.push(
          `${kind}/${name}: empty xml_content but non-empty scasp_encoding`,
        );
        failed++;
      } else {
        empty++;
        console.log(`skip ${label} (empty workspace)`);
      }
      continue;
    }

    checked++;
    let got;
    try {
      got = await regenerate(xml, siblings);
    } catch (e) {
      const msg = `${e.constructor?.name ?? "Error"}: ${e.message}`;
      console.log(`FAIL ${label}: deserialisation/generation threw -- ${msg}`);
      failures.push(`${kind}/${name}: ${msg}`);
      failed++;
      continue;
    }

    const d = firstDivergence(stored.trim(), String(got).trim());
    if (d === null) {
      console.log(
        `ok   ${label} (${stored.trim().length} bytes, ${stored.trim().split("\n").length} lines)`,
      );
    } else {
      failed++;
      console.log(
        `FAIL ${label}: first divergence at line ${d.line} ` +
          `(stored ${d.nStored} lines / ${stored.trim().length} bytes, ` +
          `regen ${d.nGot} lines / ${String(got).trim().length} bytes)`,
      );
      console.log(`       stored: ${clip(JSON.stringify(d.stored))}`);
      console.log(`       regen : ${clip(JSON.stringify(d.got))}`);
      failures.push(
        `${kind}/${name}: line ${d.line}: stored ${clip(JSON.stringify(d.stored), 120)} != regen ${clip(JSON.stringify(d.got), 120)}`,
      );
    }
  }
}

console.log(
  `blawx-fixpoint-harness: ${checked} checked, ${failed} failed, ${empty} empty-skipped; ` +
    `blockly ${blocklyVersion}, checkout ${CHECKOUT}, TZ=${TZ}${TZ_PINNED ? " (pinned)" : " (from env)"}, ` +
    `jsdomErrors ${jsdomErrors}${ISOLATE ? ", isolated realms" : ""}`,
);
process.exit(failed === 0 ? 0 : 1);
