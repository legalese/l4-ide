// The §5.3 round-trip proof, as a test: every template reproduces its source form.

import { ok, strictEqual } from "node:assert";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";
import {
  CHECK_ENCODING,
  CHECK_TEMPLATES,
  MAKE_TEMPLATES,
  NO_SUBJECT,
  buildScratchSubject,
  locateSubject,
} from "./fixture.mjs";
import { holeTokens, loadSubject, templateRelPath } from "../lib/subject.mjs";
import { render } from "../lib/mustache.mjs";

const src = locateSubject();
let dir = null;
if (src)
  dir = buildScratchSubject(src, mkdtempSync(join(tmpdir(), "safe-tpl-")));
after(() => {
  if (dir) rmSync(dir, { recursive: true, force: true });
});

const node = (script, args) =>
  spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });

test(
  "make-templates derives one template per published cell",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const r = node(MAKE_TEMPLATES, ["--subject", dir]);
    strictEqual(r.status, 0, r.stdout + r.stderr);
    const juris = readdirSync(join(dir, "templates"), { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
    ok(
      juris.includes("side-letter"),
      `expected a side-letter directory, got ${juris}`,
    );
    strictEqual(juris.join(","), "ca,ky,sg,side-letter,us");
  },
);

test(
  "every template reproduces its source form byte for byte",
  { skip: src ? false : NO_SUBJECT },
  () => {
    strictEqual(node(MAKE_TEMPLATES, ["--subject", dir]).status, 0);
    const r = node(CHECK_TEMPLATES, ["--subject", dir]);
    strictEqual(r.status, 0, r.stdout + r.stderr);
    ok(/10\/10 templates reproduce/.test(r.stdout), r.stdout);
  },
);

test(
  "the proof is a real one: a corrupted template is caught",
  { skip: src ? false : NO_SUBJECT },
  () => {
    strictEqual(node(MAKE_TEMPLATES, ["--subject", dir]).status, 0);
    const subject = loadSubject(dir);
    const file = "Postmoney Safe - Valuation Cap Only - FINAL.md";
    const form = subject.forms[file];
    const rel = templateRelPath(form.document, form.jurisdiction, form.variant);
    const text = readFileSync(join(dir, "templates", rel), "utf8");
    // Drop one word from the body — the kind of edit "modified version of the form" means.
    const broken = text.replace(
      "without regard to the conflicts of law",
      "without regard to the law",
    );
    ok(broken !== text, "the fixture sentence moved; update this test");
    const view = {};
    for (const e of holeTokens(form, file).entries) view[e.token] = e.literal;
    const source = readFileSync(join(dir, "source", "md", file), "utf8");
    ok(
      render(broken, view) !== source,
      "a corrupted template must not reproduce the form",
    );
  },
);

test(
  "encoding.json's record_fields match the DECLAREs",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const r = node(CHECK_ENCODING, ["--subject", dir]);
    strictEqual(r.status, 0, r.stdout + r.stderr);
    ok(/matches the DECLAREs/.test(r.stdout), r.stdout);
  },
);

test(
  "make-templates --check reports a stale template instead of writing one",
  { skip: src ? false : NO_SUBJECT },
  () => {
    strictEqual(node(MAKE_TEMPLATES, ["--subject", dir]).status, 0);
    strictEqual(node(MAKE_TEMPLATES, ["--subject", dir, "--check"]).status, 0);
    const rel = join(dir, "templates", "us", "cap.md.mustache");
    const keep = readFileSync(rel, "utf8");
    try {
      spawnSync("sh", ["-c", `printf 'x' >> ${JSON.stringify(rel)}`]);
      strictEqual(
        node(MAKE_TEMPLATES, ["--subject", dir, "--check"]).status,
        1,
      );
    } finally {
      spawnSync("sh", ["-c", `cat > ${JSON.stringify(rel)}`], { input: keep });
    }
  },
);
