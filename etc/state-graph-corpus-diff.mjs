// Is the picture the "Show state graph" pane draws the one `dot -Tsvg` draws?
//
// `@repo/state-graph-render` is Graphviz compiled to WebAssembly (viz.js), so
// the answer should be yes by construction — but "by construction" is a claim,
// and this is the check. Every `.dot` under jl4/ and doc/ (the state-graph
// goldens and the doc figures) is rendered twice, through the wrapper and
// through the system `dot`, and the two SVGs are compared *structurally*:
// counts of `class="node"`, `class="edge"`, `<ellipse>`, `<polygon>`, `<path>`
// and `<text>`, and the sorted set of `<title>` elements. Coordinates are NOT
// compared: they move between Graphviz releases (the wrapper pins 16.0.0; a
// Homebrew `dot` is whatever it is), and the pane makes no promise about them.
//
// The wrapper strips Graphviz's white background `<polygon>` so the picture
// sits on the editor's theme; the same polygon is stripped from the system
// output here, otherwise every file differs by exactly one polygon.
//
// This is local evidence, not CI: it needs a system `dot` on PATH and the
// wrapper built (`npm run build -w @repo/state-graph-render`). With no
// arguments it takes every .dot under jl4/ and doc/.
//
//   node etc/state-graph-corpus-diff.mjs
//   node etc/state-graph-corpus-diff.mjs doc/reference/regulative/figures/every-barrier.dot
//
// Measured 2026-09-16 (LTS-VISUALISER.md §4.8): 41 same, 0 differ, of 41,
// viz.js Graphviz 16.0.0 against system Graphviz 14.1.0.
import { execFileSync, execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const REPO = resolve(dirname(fileURLToPath(import.meta.url)), "..");

let dotVersion;
try {
  dotVersion = execSync("dot -V 2>&1", { encoding: "utf8" }).trim();
} catch {
  console.log("no system `dot` on PATH; nothing to compare against — skipping");
  process.exit(0);
}

const { renderStateGraphSvg, graphvizVersion } = await import(
  pathToFileURL(resolve(REPO, "ts-shared/state-graph-render/dist/index.js"))
    .href
);

const files =
  process.argv.length > 2
    ? process.argv.slice(2)
    : execSync(
        "find jl4 doc -name '*.dot' -not -path '*/node_modules/*' | sort",
        { cwd: REPO, encoding: "utf8" },
      )
        .trim()
        .split("\n")
        .filter(Boolean);

const count = (s, re) => (s.match(re) ?? []).length;
const stripCanvas = (svg) => svg.replace(/<polygon fill="white"[^>]*\/>/, "");
const shape = (svg) => ({
  nodes: count(svg, /class="node"/g),
  edges: count(svg, /class="edge"/g),
  ellipse: count(svg, /<ellipse/g),
  polygon: count(svg, /<polygon/g),
  path: count(svg, /<path/g),
  text: count(svg, /<text/g),
  titles: (svg.match(/<title>[^<]*<\/title>/g) ?? []).sort().join("|"),
});

let same = 0;
let differ = 0;
for (const f of files) {
  const dot = readFileSync(resolve(REPO, f), "utf8");
  const ours = shape(await renderStateGraphSvg(dot));
  const theirs = shape(
    stripCanvas(execFileSync("dot", ["-Tsvg"], { input: dot }).toString()),
  );
  if (JSON.stringify(ours) === JSON.stringify(theirs)) {
    same++;
  } else {
    differ++;
    console.log(
      `DIFF ${f}\n  viz.js: ${JSON.stringify(ours)}\n  dot:    ${JSON.stringify(theirs)}`,
    );
  }
}
console.log(
  `viz.js Graphviz ${graphvizVersion} vs system "${dotVersion}": ${same} same, ${differ} differ, of ${files.length}`,
);
process.exit(differ === 0 ? 0 : 1);
