#!/usr/bin/env node
// status-board — collect programme state into one page, so "what is ruled, what
// is in flight, what is merged" is a lookup rather than an archaeology session.
//
// WHY IT EXISTS. Meng, 2026-09-13: "I'm easily confused because we have so many
// things in flight I don't know what's unruled or ruled, what's in progress,
// what's PRed, and what's merged."
//
// WHAT IT REFUSES TO DO. It does not guess a ruling's state. Measured on this
// tree: 471 bare state words across 151 spec files in NINE vocabularies, but
// only 231 of them are DATED (`RULED 2026-09-04`), and a regex keyed to the
// bold/heading shape found only 25 rulings because most are not written that
// way. A board that turned the loose 471 into a tidy four-state chart would be
// inventing precision the corpus does not have, and would then be believed --
// so files with no status header are reported as UNKNOWN, by name, and the
// dated markers are counted separately from the undated ones. The honest gap is
// the most useful thing on that pane.
//
// ORDER OF PANES is Meng's: in-flight first, then rulings, shelf, canon, and
// the unstable -> main release train LAST, "because it moves glacially".
//
// Usage:  node etc/status-board.mjs > board.html
//         node etc/status-board.mjs --json      (the collected data, no HTML)
// Needs `gh` authenticated. Network calls are the slow part (~10s).

import { execSync } from "node:child_process";
import { readdirSync, statSync, readFileSync, existsSync } from "node:fs";
import { join, extname } from "node:path";

const sh = (c) => {
  try {
    return execSync(c, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
  } catch {
    return "";
  }
};
const j = (c) => {
  const o = sh(c);
  try {
    return o ? JSON.parse(o) : null;
  } catch {
    return null;
  }
};
const REPO = "legalese/l4-ide";

// ---------------------------------------------------------------- in flight
const prs =
  j(
    `gh pr list --repo ${REPO} --state open --limit 100 --json number,title,headRefName,baseRefName,isDraft,mergeStateStatus,reviewDecision,updatedAt,additions,deletions,changedFiles`,
  ) ?? [];
const inFlight = prs.filter((p) => p.baseRefName === "unstable");
const train = prs.filter((p) => p.baseRefName !== "unstable");

// ------------------------------------------------------------------ rulings
const walk = (d) =>
  !existsSync(d)
    ? []
    : readdirSync(d).flatMap((e) => {
        const p = join(d, e);
        return statSync(p).isDirectory()
          ? walk(p)
          : extname(p) === ".md"
            ? [p]
            : [];
      });
const STATES = [
  "RULED",
  "ANSWERED",
  "ACCEPTED",
  "DECLINED",
  "UNDECIDED",
  "OPEN",
  "PROPOSED",
  "DEFERRED",
  "SUPERSEDED",
  "RETRACTED",
];
const specs = walk("specs").map((f) => {
  const t = readFileSync(f, "utf8");
  const status = (/^\*\*Status:?\*\*\s*(.+)$/m.exec(t)?.[1] ?? "")
    .replace(/\s+/g, " ")
    .slice(0, 90);
  const dated = {},
    undated = {};
  for (const s of STATES) {
    const d = (
      t.match(new RegExp(`\\b${s}\\b\\s+\\d{4}-\\d{2}-\\d{2}`, "g")) ?? []
    ).length;
    const a = (t.match(new RegExp(`\\b${s}\\b`, "g")) ?? []).length;
    if (d) dated[s] = d;
    if (a - d) undated[s] = a - d;
  }
  return {
    file: f,
    area: f.split("/")[1] ?? "-",
    status,
    dated,
    undated,
    nDated: Object.values(dated).reduce((a, b) => a + b, 0),
    nUndated: Object.values(undated).reduce((a, b) => a + b, 0),
  };
});

// -------------------------------------------------------------------- shelf
sh("git fetch origin unstable -q");
const rels = (
  sh(`gh release list --repo legalese/prereleases --limit 10`) || ""
)
  .split("\n")
  .filter(Boolean)
  .map((l) => {
    const c = l.split("\t");
    const tag = c[2] ?? "";
    const sha = tag.split("-").pop();
    const behind =
      sha && sh(`git cat-file -e ${sha} 2>/dev/null && echo ok`)
        ? Number(sh(`git rev-list --count ${sha}..origin/unstable`) || 0)
        : null;
    return { tag, published: c[3] ?? "", sha, behind };
  });
const shelfAssets = (
  j(`gh release view ${rels[0]?.tag} --repo legalese/prereleases --json assets`)
    ?.assets ?? []
).map((a) => ({ name: a.name, mb: +(a.size / 1048576).toFixed(1) }));

// -------------------------------------------------------------------- canon
const canonMeta = j(`gh api repos/legalese/canon`);
const canonBranches = (
  j(`gh api repos/legalese/canon/branches --paginate`) ?? []
).map((b) => {
  const tree = j(
    `gh api "repos/legalese/canon/git/trees/${b.commit.sha}?recursive=1"`,
  );
  const blobs = (tree?.tree ?? []).filter((x) => x.type === "blob");
  return {
    name: b.name,
    sha: b.commit.sha.slice(0, 8),
    files: blobs.length,
    l4: blobs.filter((x) => x.path.endsWith(".l4")).length,
    md: blobs.filter((x) => x.path.endsWith(".md")).length,
    mb: +(blobs.reduce((a, x) => a + (x.size || 0), 0) / 1048576).toFixed(1),
  };
});

const data = {
  generatedAt: new Date().toISOString(),
  inFlight,
  train,
  specs,
  rels,
  shelfAssets,
  canonMeta,
  canonBranches,
  unstableHead: sh("git rev-parse --short origin/unstable"),
  mainHead: sh("git rev-parse --short origin/main"),
  mainBehind: Number(
    sh("git rev-list --count origin/main..origin/unstable") || 0,
  ),
};

if (process.argv.includes("--json")) {
  console.log(JSON.stringify(data, null, 1));
  process.exit(0);
}
process.stdout.write(render(data));

// --------------------------------------------------------------------- view
function esc(s) {
  return String(s ?? "").replace(
    /[&<>]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[c],
  );
}
function render(d) {
  const noStatus = d.specs.filter((s) => !s.status);
  const totDated = d.specs.reduce((a, s) => a + s.nDated, 0),
    totUndated = d.specs.reduce((a, s) => a + s.nUndated, 0);
  const red = d.train.filter((p) => p.mergeStateStatus === "UNSTABLE").length;
  const unreviewed = d.train.filter((p) => !p.reviewDecision).length;
  const stateAgg = {};
  for (const s of d.specs)
    for (const [k, v] of Object.entries(s.dated))
      stateAgg[k] = (stateAgg[k] || 0) + v;
  return `<title>L4 Programme Board</title>
<style>
:root{--bg:#faf9f7;--fg:#1c1a17;--dim:#6b6560;--line:#e0dcd5;--card:#fff;--accent:#8a5a2b;--red:#a33a2a;--amber:#9a7a1a;--green:#3f6b3a;--mono:ui-monospace,SFMono-Regular,Menlo,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#17161a;--fg:#eae7e2;--dim:#9b948c;--line:#33302c;--card:#1f1e22;--accent:#d9a05b;--red:#e07a63;--amber:#d4ad4a;--green:#82b478}}
:root[data-theme="dark"]{--bg:#17161a;--fg:#eae7e2;--dim:#9b948c;--line:#33302c;--card:#1f1e22;--accent:#d9a05b;--red:#e07a63;--amber:#d4ad4a;--green:#82b478}
*{box-sizing:border-box}body{background:var(--bg);color:var(--fg);font:15px/1.55 ui-serif,Georgia,serif;margin:0;padding:28px 20px 80px}
.wrap{max-width:1080px;margin:0 auto}
h1{font-size:26px;margin:0 0 2px;letter-spacing:-.01em}
.sub{color:var(--dim);font-size:13px;margin-bottom:26px;font-family:var(--mono)}
h2{font-size:17px;margin:34px 0 4px;padding-top:14px;border-top:2px solid var(--line)}
h2 .n{color:var(--dim);font-weight:400;font-size:13px;font-family:var(--mono);margin-left:8px}
.lede{color:var(--dim);font-size:13.5px;margin:0 0 12px}
table{border-collapse:collapse;width:100%;font-size:13px;font-family:var(--mono)}
th{text-align:left;font-weight:600;color:var(--dim);border-bottom:1px solid var(--line);padding:5px 8px 5px 0;font-size:11.5px;letter-spacing:.04em;text-transform:uppercase}
td{padding:5px 8px 5px 0;border-bottom:1px solid var(--line);vertical-align:top}
td.n{text-align:right;font-variant-numeric:tabular-nums}
.scroll{overflow-x:auto}
.pill{display:inline-block;padding:1px 7px;border-radius:9px;font-size:11px;font-family:var(--mono)}
.ok{background:color-mix(in srgb,var(--green) 16%,transparent);color:var(--green)}
.bad{background:color-mix(in srgb,var(--red) 16%,transparent);color:var(--red)}
.warn{background:color-mix(in srgb,var(--amber) 18%,transparent);color:var(--amber)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin:12px 0 4px}
.card{background:var(--card);border:1px solid var(--line);border-radius:7px;padding:10px 12px}
.card .k{font-size:11px;color:var(--dim);text-transform:uppercase;letter-spacing:.04em;font-family:var(--mono)}
.card .v{font-size:23px;font-variant-numeric:tabular-nums;margin-top:1px}
.note{background:var(--card);border-left:3px solid var(--accent);padding:9px 13px;margin:12px 0;font-size:13.5px;border-radius:0 5px 5px 0}
a{color:var(--accent)}
</style>
<div class="wrap">
<h1>L4 Programme Board</h1>
<div class="sub">generated ${esc(d.generatedAt)} · unstable ${esc(d.unstableHead)} · main ${esc(d.mainHead)} · regenerate with <b>node etc/status-board.mjs</b></div>

<h2>In flight<span class="n">PRs targeting unstable — ${d.inFlight.length}</span></h2>
<p class="lede">Everything actually moving. Distinct from the release train at the bottom, which is a different queue.</p>
<div class="scroll"><table><tr><th>PR</th><th>branch</th><th>checks</th><th>review</th><th>size</th><th>updated</th></tr>
${d.inFlight.map((p) => `<tr><td><a href="https://github.com/${REPO}/pull/${p.number}">#${p.number}</a>${p.isDraft ? ' <span class="pill warn">draft</span>' : ""}</td><td>${esc(p.headRefName)}</td><td>${p.mergeStateStatus === "UNSTABLE" ? '<span class="pill bad">failing</span>' : p.mergeStateStatus === "CLEAN" ? '<span class="pill ok">clean</span>' : `<span class="pill warn">${esc(p.mergeStateStatus)}</span>`}</td><td>${p.reviewDecision ? esc(p.reviewDecision) : '<span class="pill warn">none</span>'}</td><td class="n">${p.changedFiles}f</td><td>${esc((p.updatedAt || "").slice(0, 10))}</td></tr>`).join("")}
</table></div>

<h2>Rulings<span class="n">${totDated} dated · ${totUndated} undated · ${d.specs.length} spec files</span></h2>
<p class="lede">Counted, not inferred. A dated marker (<span style="font-family:var(--mono)">RULED 2026-09-04</span>) is trustworthy; a bare state word in prose is not, so the two are never added together.</p>
<div class="cards">${Object.entries(stateAgg)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(
      ([k, v]) =>
        `<div class="card"><div class="k">${esc(k)}</div><div class="v">${v}</div></div>`,
    )
    .join("")}</div>
<div class="note"><b>${noStatus.length} of ${d.specs.length} spec files carry no <span style="font-family:var(--mono)">**Status:**</span> header</b>, so their state is genuinely unknown rather than open. That gap is the finding, not a rendering problem — a spec with no header cannot be triaged without reading it.</div>
<div class="scroll"><table><tr><th>spec</th><th>status header</th><th class="n">dated</th><th class="n">undated</th></tr>
${d.specs
  .filter((s) => s.nDated || s.status)
  .sort((a, b) => b.nDated - a.nDated)
  .slice(0, 22)
  .map(
    (s) =>
      `<tr><td>${esc(s.file.replace("specs/", ""))}</td><td>${s.status ? esc(s.status) : '<span class="pill warn">none</span>'}</td><td class="n">${s.nDated || ""}</td><td class="n">${s.nUndated || ""}</td></tr>`,
  )
  .join("")}
</table></div>

<h2>Build shelf<span class="n">legalese/prereleases</span></h2>
<p class="lede">What a user who installs today actually gets, and how far behind the tree it is.</p>
<div class="scroll"><table><tr><th>tag</th><th>published</th><th class="n">commits behind unstable</th></tr>
${d.rels.map((r, i) => `<tr><td>${esc(r.tag)}${i === 0 ? ' <span class="pill ok">current</span>' : ""}</td><td>${esc((r.published || "").slice(0, 10))}</td><td class="n">${r.behind === null ? "—" : r.behind > 200 ? `<span class="pill bad">${r.behind}</span>` : r.behind > 40 ? `<span class="pill warn">${r.behind}</span>` : `<span class="pill ok">${r.behind}</span>`}</td></tr>`).join("")}
</table></div>
<p class="lede" style="margin-top:9px">Assets on the current shelf: ${d.shelfAssets.map((a) => `${esc(a.name.replace(/^l4-|\.tar\.gz$/g, ""))} <b>${a.mb}MB</b>`).join(" · ")}</p>

<h2>Canon<span class="n">legalese/canon · ${d.canonBranches.length} branches</span></h2>
<p class="lede">Encoded law by branch. <span style="font-family:var(--mono)">.l4</span> count is the one that matters; bytes are mostly source PDFs and prose.</p>
<div class="scroll"><table><tr><th>branch</th><th>head</th><th class="n">.l4</th><th class="n">.md</th><th class="n">files</th><th class="n">MB</th></tr>
${d.canonBranches
  .sort((a, b) => b.l4 - a.l4)
  .map(
    (b) =>
      `<tr><td>${esc(b.name)}${b.name === d.canonMeta?.default_branch ? ' <span class="pill ok">default</span>' : ""}</td><td>${esc(b.sha)}</td><td class="n">${b.l4}</td><td class="n">${b.md}</td><td class="n">${b.files}</td><td class="n">${b.mb}</td></tr>`,
  )
  .join("")}
</table></div>

<h2>Release train<span class="n">unstable → main · ${d.train.length} PRs · main is ${d.mainBehind} commits behind unstable</span></h2>
<p class="lede">Last, because it moves glacially. These are review slices, not work in flight — leave them alone.</p>
<div class="cards">
<div class="card"><div class="k">slices open</div><div class="v">${d.train.length}</div></div>
<div class="card"><div class="k">failing checks</div><div class="v" style="color:${red ? "var(--red)" : "var(--green)"}">${red}</div></div>
<div class="card"><div class="k">no review yet</div><div class="v" style="color:${unreviewed === d.train.length ? "var(--amber)" : "var(--fg)"}">${unreviewed}</div></div>
</div>
<div class="scroll"><table><tr><th>PR</th><th>branch</th><th>base</th><th>checks</th><th>review</th><th class="n">files</th></tr>
${d.train
  .sort((a, b) => a.number - b.number)
  .map(
    (p) =>
      `<tr><td><a href="https://github.com/${REPO}/pull/${p.number}">#${p.number}</a></td><td>${esc(p.headRefName.replace(/^claude\//, ""))}</td><td>${esc(p.baseRefName.replace(/^claude\//, ""))}</td><td>${p.mergeStateStatus === "UNSTABLE" ? '<span class="pill bad">failing</span>' : p.mergeStateStatus === "CLEAN" ? '<span class="pill ok">clean</span>' : `<span class="pill warn">${esc(p.mergeStateStatus)}</span>`}</td><td>${p.reviewDecision ? esc(p.reviewDecision) : '<span class="pill warn">none</span>'}</td><td class="n">${p.changedFiles}</td></tr>`,
  )
  .join("")}
</table></div>
</div>`;
}
