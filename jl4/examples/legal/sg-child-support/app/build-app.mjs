#!/usr/bin/env node
// Inline outcomes.json into app.template.html to produce index.html.
// The app ships as ONE file so it can be opened from disk with no server;
// the JSON it carries is what the encoding answered, never a copy of the law.
import { readFileSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
const HERE = dirname(fileURLToPath(import.meta.url));
const tpl = readFileSync(join(HERE, "app.template.html"), "utf8");
const out = readFileSync(join(HERE, "outcomes.json"), "utf8");
// </script> inside JSON would close the host element early.
const safe = out.replace(/<\/script/gi, "<\\/script");
writeFileSync(join(HERE, "index.html"), tpl.replace("/*__OUTCOMES__*/", safe));
console.log(`build-app: index.html written (${(tpl.length + safe.length) / 1024 | 0} KB)`);
