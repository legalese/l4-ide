#!/usr/bin/env node
// Inline outcomes.json into the app template to produce a self-contained page.
//
// Kept separate from build-scenarios.mjs so the two concerns stay apart: that
// script asks the ENCODING what the law gives, this one only presents it. If
// you are changing what the page says about the law, you are in the wrong file.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const data = JSON.parse(readFileSync(join(HERE, "outcomes.json"), "utf8"));

// the assertion count the footer cites, read from the corpus rather than typed
const CORPUS = join(HERE, "..");
const modules = ["sg-wills.l4", "sg-paa.l4", "sg-succession-cases.l4"];
data.assertions = modules.reduce(
  (n, m) => n + (readFileSync(join(CORPUS, m), "utf8").match(/^#ASSERT/gm) || []).length, 0);

const tpl = readFileSync(join(HERE, "app.template.html"), "utf8");
if (!tpl.includes("/*__DATA__*/")) {
  console.error("build-app: template has no /*__DATA__*/ marker");
  process.exit(1);
}
// </script> inside JSON would close the host script element
const json = JSON.stringify(data).replace(/<\//g, "<\\/");
writeFileSync(join(HERE, "index.html"), tpl.replace("/*__DATA__*/", json));
console.log(`build-app: index.html written (${data.scenarios.length} scenarios, ${data.assertions} assertions cited)`);
