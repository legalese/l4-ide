#!/usr/bin/env node
// Read the shape of `l4 render --format plan` output.
//
// Emits "<units> <populated-asks>" for `read -r`. Both are counted out of the
// artifact; neither is typed anywhere.
//
// Usage: node etc/go/lib/plan-shape.mjs PLAN.json

import { readFileSync } from "node:fs";

const [, , file] = process.argv;
if (!file) {
  process.stderr.write("usage: plan-shape.mjs PLAN.json\n");
  process.exit(2);
}
const plan = JSON.parse(readFileSync(file, "utf8"));
const units = (plan.modules || []).reduce(
  (n, m) => n + (m.units || []).length,
  0,
);
// A populated `asks` array — an empty one would be an interview with no
// questions, which is the same absence in a different shape.
const asks = (JSON.stringify(plan).match(/"asks":\s*\[\s*[^\s\]]/g) || [])
  .length;
process.stdout.write(`${units} ${asks}\n`);
