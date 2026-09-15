// Assembles etc/lts-reader-proxy/manifest.json from the per-contract files.
// Run by prepare.sh; can be run on its own: `node etc/lts-reader-proxy/build-manifest.mjs`.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const contracts = [
  "contracts",
  "every-run-example",
  "tenancy",
  "promissory-note",
];
const artifacts = { A: "A.txt", B: "B.dot", C: "C.bpmn" };
const read = (c, f) => readFileSync(join(here, c, f), "utf8");

const entries = [];
for (const contract of contracts) {
  const truth = JSON.parse(read(contract, "truth.json"));
  const history = read(contract, "history.txt");
  for (const [artifact, file] of Object.entries(artifacts)) {
    entries.push({
      contract,
      artifact,
      text: read(contract, file),
      // The list (A) already states its own position, so A readers get no
      // separate history; B and C readers get the position in plain words.
      history: artifact === "A" ? null : history,
      questions: truth.questions,
      truth: truth.truth,
    });
  }
}
writeFileSync(
  join(here, "manifest.json"),
  JSON.stringify(entries, null, 2) + "\n",
);
console.log(`manifest.json: ${entries.length} entries`);
