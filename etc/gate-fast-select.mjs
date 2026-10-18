#!/usr/bin/env node
// gate-fast-select — may `verify-branch.sh --fast` run its REDUCED gate on this diff?
//
// PARTIAL GATE. It exists to answer one question, conservatively: is every changed path
// one that no gate step reads except through a check the reduced gate still runs? If any
// path is not provably such a path, the verdict is `full` and the caller runs the whole gate.
// Every reason it says `full` is printed. It never says `docs` or `corpus` for an empty
// diff, for a path it cannot classify, or when its selection would run nothing.
//
// VERDICTS
//   docs    every changed path is a markdown file that no test source or script names.
//   corpus  every changed path is a markdown file (as above), or a corpus `.l4` / golden under
//           jl4/examples/{ok,legal,canon,not-ok,lsp}/ that no test source or script names.
//           The output then lists hspec `--match` patterns, one per affected corpus file:
//           the changed files and every file that (transitively) IMPORTs one of them.
//   full    anything else. The reasons say what.
//
// WHAT IT DOES NOT DO: it does not look at the build. Whether a Haskell input changed is
// the caller's question and a Haskell path is simply not in either safe set.
//
// OUTPUT (default): tab-separated lines for the shell.
//   VERDICT<TAB>docs|corpus|full     REASON<TAB>text     FILE<TAB>path     MATCH<TAB>pattern
//   NOTE<TAB>text (things the reduced gate does not cover for this diff)
// Usage:
//   node etc/gate-fast-select.mjs [--base REF] [--max-closure N] [--json] [<worktree>]
//        changed = REF...HEAD, plus uncommitted and untracked files (the gate tests the working tree)
//   node etc/gate-fast-select.mjs --rev REV [<worktree>]
//        classify one commit against its first parent, reading the tree AT REV (history replay)
//   node etc/gate-fast-select.mjs --selftest
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve, dirname, join } from "node:path";

// ---------------------------------------------------------------------------------------
// What the safe sets are. Each line is a claim about the tree, and each has a source:
//   - the corpus directories and their per-file groups mirror jl4/tests/Main.hs's globDir1 calls
//     (the same list etc/check-corpus-goldens.mjs mirrors);
//   - the readers are the places that name a repository file at run time. Library and app source
//     only mention corpus files in comments (checked with `git grep` 2026-10-18), so the scan is
//     limited to test trees, scripts, workflows and nix.
// ---------------------------------------------------------------------------------------
const EXAMPLES = "jl4/examples/";
const CORPUS_DIRS = ["ok", "legal", "canon", "not-ok", "lsp"];

// jl4/tests/Main.hs:84-115. Paths are relative to jl4/examples/. A `.l4` in a corpus
// directory that matches none of these has no example of its own (a library that an
// importer imports, for instance).
const GROUPS = [
  ["ok files", /^ok\/.*\.l4$/],
  ["ok files", /^legal\/.*\.l4$/],
  ["ok files", /^canon\/.*\.l4$/],
  ["tc fails", /^not-ok\/tc\/.*\.l4$/],
  ["nlg fails", /^not-ok\/nlg\/.*\.l4$/],
  ["lsp semantic tokens", /^lsp\/semantic-tokens\/.*\.l4$/],
  ["lsp hover", /^lsp\/hover\/.*\.l4$/],
  ["export placement", /^not-ok\/export-[^/]*\.l4$/],
  ["import refusal", /^not-ok\/import\/[^/]*-refused\.l4$/],
  ["unresolvable import", /^not-ok\/import\/unresolved-[^/]*\.l4$/],
];

// jl4-test also has two examples that read the corpus as a whole (jl4/tests/Main.hs:121-141).
// Both are cheap and neither is per-file, so the reduced gate always includes them.
const ALWAYS_MATCH = ["corpus sanity", "connective traces name no parameters"];

const GENERIC_MD = new Set([
  "README.md",
  "SUMMARY.md",
  "index.md",
  "NOTES.md",
  "TODO.md",
  "CHANGELOG.md",
  "LICENSE.md",
]);

// Where a repository file can be named at run time. GATE readers are the four suites that
// verify-branch.sh runs (a path they name may be read by a test the reduced gate does not run);
// WIDER readers are suites and scripts that neither gate runs (jl4-lsp-test, jl4-mlir-test, the CI
// workflows, the web apps, nix). The wider ones never change the verdict, they are printed as notes,
// because the full gate would not run them either.
const READER_PATHSPECS = {
  gate: [
    ":(glob)jl4/tests/**",
    ":(glob)jl4/tests-cli/**",
    ":(glob)jl4-core/test/**",
    ":(glob)jl4-service/test/**",
  ],
  wider: [
    ":(glob)jl4-lsp/test/**",
    ":(glob)jl4-mlir/test/**",
    ":(glob)jl4-websessions/test/**",
    ":(glob)jl4-proleg/test/**",
    ":(glob)etc/**/*.mjs",
    ":(glob)etc/**/*.sh",
    ":(glob)etc/**/*.py",
    ":(glob)etc/**/*.java",
    ":(glob)ts-apps/**/*.ts",
    ":(glob)ts-apps/**/*.svelte",
    ":(glob).github/workflows/*.yml",
    ":(glob)nix/**",
  ],
};
// Files in those trees that are not readers (this tool, the gate itself, and goldens).
const READER_IGNORE = [
  /^etc\/gate-fast-select\.mjs$/,
  /^etc\/verify-branch\.sh$/,
  /\.golden$/,
];

// Markdown that is not documentation: fixtures beside the corpus and libraries, trees that other build
// systems read (the web apps, the workflows), and the trees whose probes the full gate keys on the DIRECTORY
// (verify-branch.sh runs probe (a) for jl4-core/src/L4/Parser*, (b) for jl4-service/, (c) for jl4/tests-cli/):
// a change anywhere in them, a README included, gets the full gate, so the probe is never silently dropped.
const NOT_DOC = [
  EXAMPLES,
  "jl4-core/libraries/",
  "jl4-core/src/L4/Parser",
  "jl4-service/",
  "jl4/tests-cli/",
  "ts-apps/",
  "ts-shared/",
  ".github/",
  "node_modules/",
];

const stem = (p) => p.replace(/^.*\//, "").replace(/\.l4$/, "");
const base = (p) => p.replace(/^.*\//, "");

// A golden is <dir>/tests/<stem>[.ep|.nlg|.schema|.hover].golden; its source is <dir>/<stem>.l4.
export function goldenSource(p) {
  const m =
    /^(.*)\/tests\/([^/]+?)(?:\.(?:ep|nlg|schema|hover))?\.golden$/.exec(p);
  return m ? `${m[1]}/${m[2]}.l4` : null;
}

export function groupOf(p) {
  if (!p.startsWith(EXAMPLES)) return null;
  const rel = p.slice(EXAMPLES.length);
  for (const [name, re] of GROUPS) if (re.test(rel)) return name;
  return null;
}
const inCorpus = (p) =>
  CORPUS_DIRS.some((d) => p.startsWith(`${EXAMPLES}${d}/`));

// One changed path -> what it is.
export function kindOf(p) {
  // Markdown inside the five corpus directories is the encoding's README and notes. jl4-test globs only .l4 and
  // .golden there, and no gate step reads the prose; a test that names one is caught by the name scan like any other.
  if (/\.md$/.test(p) && inCorpus(p)) return "doc";
  if (/\.md$/.test(p) && !NOT_DOC.some((d) => p.startsWith(d))) return "doc";
  if (inCorpus(p) && p.endsWith(".l4")) return "corpus-l4";
  if (inCorpus(p) && goldenSource(p)) return "corpus-golden";
  return "other";
}

// ---------------------------------------------------------------------------------------
// The decision. `repo` is the part of the world that needs git, so --selftest can fake it:
//   repo.readers(names, scope) -> [{ name, file, line, text }]  every line of a `gate` or `wider` reader naming one of `names`
//   repo.imports()       -> [{ file, module }]            every `IMPORT module` line in every .l4
//   repo.exists(path)    -> bool                          in the tree being gated
// ---------------------------------------------------------------------------------------
const commentLine = (file, text) => {
  const t = text.trim();
  if (/\.(hs|cabal|l4)$/.test(file)) return t.startsWith("--");
  if (/\.(mjs|js|ts|svelte|java)$/.test(file))
    return t.startsWith("//") || t.startsWith("*");
  if (/\.(sh|py|yml|yaml|nix)$/.test(file))
    return t.startsWith("#") && !t.startsWith("#!");
  return false;
};

export function select(changes, repo, opts = {}) {
  const maxClosure = opts.maxClosure ?? 120;
  const reasons = [];
  const notes = [];
  const full = (why) => ({
    verdict: "full",
    reasons: [...reasons, why],
    notes,
    files: [],
    matches: [],
  });

  if (changes.length === 0)
    return full(
      "no changed paths, so there is nothing for a reduced gate to be about",
    );

  const kinds = changes.map((c) => ({ ...c, kind: kindOf(c.path) }));
  const other = kinds.filter((k) => k.kind === "other");
  if (other.length > 0) {
    const shown = other
      .slice(0, 5)
      .map((k) => k.path)
      .join(", ");
    return full(
      `${other.length} changed path(s) are neither a markdown file nor a corpus .l4/golden: ${shown}${other.length > 5 ? ", ..." : ""}`,
    );
  }

  // 1. Is any changed file named by a test source? Basenames are searched, because tests build
  //    paths from segments (`"canon" </> "us" </> "regcf" </> "regcf.l4"`).
  const names = new Set();
  const namesOf = (k) =>
    k.kind === "corpus-golden"
      ? [base(k.path), base(goldenSource(k.path))]
      : [base(k.path)];
  for (const k of kinds) for (const n of namesOf(k)) names.add(n);
  const live = (hits) =>
    hits.filter(
      (h) =>
        !READER_IGNORE.some((re) => re.test(h.file)) &&
        !commentLine(h.file, h.text),
    );
  // A generic name (README.md) is named only by a line that also shows its directory beside it,
  // either whole ("syntax/README.md") or as joined segments ("syntax" </> "README.md").
  const names_ = (k, h) => {
    if (!namesOf(k).includes(h.name)) return false;
    if (!GENERIC_MD.has(h.name)) return true;
    const leaf = dirname(k.path).split("/").pop();
    return (
      h.text.includes(`${leaf}/${h.name}`) ||
      new RegExp(
        `["']${leaf}["']\\s*(</>|,|\\+)\\s*["']${h.name.replace(/\./g, "\\.")}["']`,
      ).test(h.text)
    );
  };
  const gateHits = live(repo.readers([...names], "gate"));
  const named = [];
  for (const k of kinds) {
    const h = gateHits.find((x) => names_(k, x));
    if (h) named.push(`${k.path} is named by ${h.file}:${h.line}`);
  }
  if (named.length > 0) {
    return full(
      `${named.length} changed path(s) are named by a test source, so a suite outside the reduced gate may read them: ${named.slice(0, 4).join("; ")}${named.length > 4 ? "; ..." : ""}`,
    );
  }
  for (const h of live(repo.readers([...names], "wider"))
    .filter((x) => kinds.some((k) => names_(k, x)))
    .slice(0, 3)) {
    notes.push(
      `${h.name} is also named by ${h.file}:${h.line}, which neither this gate nor the full gate runs`,
    );
  }

  // 2. Docs only: nothing more to select.
  const corpus = kinds.filter((k) => k.kind !== "doc");
  if (corpus.length === 0) {
    notes.push(
      "doc/test-docs.sh part 2 (the l4 CLI over every .l4 under doc/) does not run in this gate or in the reduced gate; no .l4 under doc/ changed",
    );
    return { verdict: "docs", reasons, notes, files: [], matches: [] };
  }

  // 3. Corpus: the changed .l4 files, the owners of changed goldens, and every importer.
  const seeds = new Set();
  for (const k of corpus) {
    if (k.kind === "corpus-l4") seeds.add(k.path);
    else {
      const src = goldenSource(k.path);
      if (!repo.exists(src) && k.status !== "D")
        return full(`${k.path} is a golden with no ${src} beside it`);
      seeds.add(src);
    }
  }
  const importersOf = new Map();
  for (const { file, module } of repo.imports()) {
    if (!importersOf.has(module)) importersOf.set(module, new Set());
    importersOf.get(module).add(file);
  }
  // Per seed, so that a changed file nothing runs cannot hide behind another changed file that something does.
  const closure = new Set();
  for (const seed of seeds) {
    const mine = new Set([seed]);
    const queue = [seed];
    while (queue.length > 0) {
      const f = queue.pop();
      for (const imp of importersOf.get(stem(f)) ?? []) {
        if (mine.has(imp)) continue;
        mine.add(imp);
        queue.push(imp);
        if (mine.size + closure.size > maxClosure)
          return full(
            `the files affected through IMPORT number more than ${maxClosure}, which is most of the cost of the full gate`,
          );
      }
    }
    const outside = [...mine].filter((f) => !inCorpus(f));
    if (outside.length > 0)
      return full(
        `${outside[0]} imports ${seed} (directly or through others) but is outside jl4-test's corpus`,
      );
    // A deleted source has no examples left, and the rest of its cone is judged on its own.
    if (
      repo.exists(seed) &&
      ![...mine].some((f) => repo.exists(f) && groupOf(f))
    ) {
      return full(
        `no jl4-test example reads ${seed}: it is in no glob and nothing in a glob imports it`,
      );
    }
    for (const f of mine) closure.add(f);
  }
  const selected = [...closure]
    .filter((f) => repo.exists(f) && groupOf(f))
    .sort();
  const grouped = [...new Set(selected.map(groupOf))];
  if (selected.length === 0) {
    return full(
      "every changed corpus file is deleted and nothing imports it, so a reduced run would run no example of its own",
    );
  }
  notes.push(`jl4-test groups touched: ${grouped.join(", ")}`);
  notes.push(
    `${seeds.size} changed corpus file(s), ${closure.size - seeds.size} more through IMPORT`,
  );
  const matches = [
    ...selected.map((f) => `/${f.slice(EXAMPLES.length)}`),
    ...ALWAYS_MATCH,
  ];
  return { verdict: "corpus", reasons, notes, files: selected, matches };
}

// ---------------------------------------------------------------------------------------
// The real repository, through git. `rev` null = the working tree.
// ---------------------------------------------------------------------------------------
const git = (wt, args, { ok = [0] } = {}) => {
  try {
    return execFileSync("git", ["-C", wt, ...args], {
      encoding: "utf8",
      maxBuffer: 1 << 28,
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (e) {
    if (e.status !== undefined && ok.includes(e.status)) return e.stdout ?? "";
    throw e;
  }
};

export function gitRepo(wt, rev) {
  const treeArgs = rev ? [rev] : ["--untracked"];
  const strip = (line) =>
    rev && line.startsWith(`${rev}:`) ? line.slice(rev.length + 1) : line;
  return {
    readers(names, scope) {
      if (names.length === 0) return [];
      const out = git(
        wt,
        [
          "grep",
          "-F",
          "-n",
          ...names.flatMap((n) => ["-e", n]),
          ...treeArgs,
          "--",
          ...READER_PATHSPECS[scope],
        ],
        { ok: [0, 1] },
      );
      const hits = [];
      for (const raw of out.split("\n")) {
        const m = /^([^:]+):(\d+):(.*)$/.exec(strip(raw));
        if (!m) continue;
        for (const name of names)
          if (m[3].includes(name))
            hits.push({ name, file: m[1], line: Number(m[2]), text: m[3] });
      }
      return hits;
    },
    imports() {
      const out = git(
        wt,
        [
          "grep",
          "-n",
          "-E",
          "-e",
          "^[[:space:]]*IMPORT[[:space:]]+",
          ...treeArgs,
          "--",
          "*.l4",
        ],
        { ok: [0, 1] },
      );
      const res = [];
      for (const raw of out.split("\n")) {
        const m = /^([^:]+):\d+:\s*IMPORT\s+(`[^`]+`|[^\s]+)/.exec(strip(raw));
        if (m) res.push({ file: m[1], module: m[2].replace(/^`|`$/g, "") });
      }
      return res;
    },
    exists(p) {
      if (rev) {
        try {
          execFileSync("git", ["-C", wt, "cat-file", "-e", `${rev}:${p}`], {
            stdio: "ignore",
          });
          return true;
        } catch {
          return false;
        }
      }
      try {
        execFileSync("test", ["-f", resolve(wt, p)]);
        return true;
      } catch {
        return false;
      }
    },
  };
}

export function gitChanges(wt, { baseRef, rev }) {
  const changes = [];
  const parse = (out) => {
    for (const line of out.split("\n")) {
      if (!line) continue;
      const [status, ...rest] = line.split("\t");
      changes.push({ status: status[0], path: rest.join("\t") });
    }
  };
  if (rev) {
    try {
      parse(
        git(wt, ["diff", "--name-status", "--no-renames", `${rev}^1`, rev]),
      );
    } catch {
      parse(
        git(wt, ["show", "--name-status", "--no-renames", "--format=", rev]),
      );
    }
    return changes;
  }
  parse(
    git(wt, ["diff", "--name-status", "--no-renames", `${baseRef}...HEAD`]),
  );
  parse(git(wt, ["diff", "--name-status", "--no-renames", "HEAD"]));
  for (const p of git(wt, ["ls-files", "-o", "--exclude-standard"]).split("\n"))
    if (p) changes.push({ status: "A", path: p });
  const seen = new Map();
  for (const c of changes) seen.set(c.path, c);
  return [...seen.values()];
}

// ---------------------------------------------------------------------------------------
// --selftest: a checker's green means nothing until something has shown it can go red.
// ---------------------------------------------------------------------------------------
function selftest() {
  let failed = 0;
  const check = (label, cond) => {
    if (!cond) failed++;
    console.log(`${cond ? "ok  " : "FAIL"} ${label}`);
  };
  const files = new Set([
    "jl4/examples/ok/a.l4",
    "jl4/examples/ok/b.l4",
    "jl4/examples/ok/lib.l4",
    "jl4/examples/not-ok/import/lib.l4",
    "jl4/examples/not-ok/import/x-refused.l4",
    "jl4/examples/dmn/d.l4",
    "jl4/examples/ok/tests/a.golden",
    "jl4/examples/ok/orphan.l4",
    "jl4/examples/ok/named.l4",
  ]);
  const fake = (over = {}) => ({
    readers: (names, scope) =>
      (over.readers ?? []).filter(
        (h) => names.includes(h.name) && (h.scope ?? "gate") === scope,
      ),
    imports: () => over.imports ?? [],
    exists: (p) => files.has(p),
  });
  const ch = (...paths) =>
    paths.map((p) => ({
      status: p.startsWith("-") ? "D" : "M",
      path: p.replace(/^-/, ""),
    }));
  const v = (changes, repo, o) => select(changes, repo, o);

  check("empty diff is full", v([], fake()).verdict === "full");
  check(
    "a markdown file is docs",
    v(ch("doc/x.md"), fake()).verdict === "docs",
  );
  check(
    "a haskell file is full",
    v(ch("jl4-core/src/L4/X.hs"), fake()).verdict === "full",
  );
  check(
    "a library .l4 is full",
    v(ch("jl4-core/libraries/prelude.l4"), fake()).verdict === "full",
  );
  check(
    "a markdown file inside the corpus is docs",
    v(ch("jl4/examples/ok/README.md"), fake()).verdict === "docs",
  );
  check(
    "a markdown file beside the other examples (dmn/, not the corpus) is full",
    v(ch("jl4/examples/dmn/expected/x.dmn.md"), fake()).verdict === "full",
  );
  check(
    "a json file inside the corpus is full",
    v(ch("jl4/examples/legal/bna/bna.cases.json"), fake()).verdict === "full",
  );
  check(
    "a README under jl4-service/ is full, because probe (b) keys on the directory",
    v(ch("jl4-service/README.md"), fake()).verdict === "full",
  );
  check(
    "a markdown file under jl4/tests-cli/ is full, because probe (c) keys on the directory",
    v(ch("jl4/tests-cli/NOTES.md"), fake()).verdict === "full",
  );
  check(
    "a markdown file beside the parser is full, because probe (a) keys on the directory",
    v(ch("jl4-core/src/L4/Parser/NOTES.md"), fake()).verdict === "full",
  );
  check(
    "docs + corpus mix is corpus",
    v(ch("doc/x.md", "jl4/examples/ok/a.l4"), fake()).verdict === "corpus",
  );
  const r = v(ch("jl4/examples/ok/a.l4"), fake());
  check(
    "a corpus file selects /ok/a.l4 plus the two whole-corpus groups",
    r.verdict === "corpus" &&
      r.matches.join("|") ===
        "/ok/a.l4|corpus sanity|connective traces name no parameters",
  );
  const g = v(ch("jl4/examples/ok/tests/a.ep.golden"), fake());
  check(
    "a golden selects its source",
    g.verdict === "corpus" && g.matches[0] === "/ok/a.l4",
  );
  const gh = v(ch("jl4/examples/ok/tests/a.hover.golden"), fake());
  check(
    "a hover golden selects its source",
    gh.verdict === "corpus" && gh.matches[0] === "/ok/a.l4",
  );
  check(
    "a golden with no source beside it is full",
    v(ch("jl4/examples/ok/tests/nosuch.golden"), fake()).verdict === "full",
  );
  check(
    "a non-.l4, non-golden corpus file is full",
    v(ch("jl4/examples/ok/data.json"), fake()).verdict === "full",
  );
  check(
    "a path outside every safe set among safe ones is full",
    v(ch("doc/x.md", "etc/foo.mjs"), fake()).verdict === "full",
  );
  const imp = v(
    ch("jl4/examples/ok/lib.l4"),
    fake({ imports: [{ file: "jl4/examples/ok/b.l4", module: "lib" }] }),
  );
  check(
    "an importer is selected too",
    imp.verdict === "corpus" &&
      imp.matches.includes("/ok/b.l4") &&
      imp.matches.includes("/ok/lib.l4"),
  );
  const chain = v(
    ch("jl4/examples/ok/lib.l4"),
    fake({
      imports: [
        { file: "jl4/examples/ok/b.l4", module: "lib" },
        { file: "jl4/examples/ok/a.l4", module: "b" },
      ],
    }),
  );
  check(
    "importers are transitive",
    chain.verdict === "corpus" && chain.matches.includes("/ok/a.l4"),
  );
  const outside = v(
    ch("jl4/examples/ok/lib.l4"),
    fake({ imports: [{ file: "jl4/examples/dmn/d.l4", module: "lib" }] }),
  );
  check("an importer outside the corpus is full", outside.verdict === "full");
  const big = v(
    ch("jl4/examples/ok/lib.l4"),
    fake({
      imports: [
        { file: "jl4/examples/ok/b.l4", module: "lib" },
        { file: "jl4/examples/ok/a.l4", module: "lib" },
      ],
    }),
    { maxClosure: 2 },
  );
  check("a closure above the cap is full", big.verdict === "full");
  const lib = v(
    ch("jl4/examples/not-ok/import/lib.l4"),
    fake({
      imports: [
        { file: "jl4/examples/not-ok/import/x-refused.l4", module: "lib" },
      ],
    }),
  );
  check(
    "a module in no glob selects the importer that has one",
    lib.verdict === "corpus" &&
      lib.matches[0] === "/not-ok/import/x-refused.l4",
  );
  check(
    "a file in no glob that nothing imports would run nothing, so full",
    v(ch("jl4/examples/not-ok/import/lib.l4"), fake()).verdict === "full",
  );
  const named = v(
    ch("jl4/examples/ok/named.l4"),
    fake({
      readers: [
        {
          name: "named.l4",
          file: "jl4/tests-cli/Main.hs",
          line: 9,
          text: 'x = "examples/ok/named.l4"',
        },
      ],
    }),
  );
  check(
    "a corpus file a test names is full",
    named.verdict === "full" &&
      /named by jl4\/tests-cli\/Main.hs:9/.test(named.reasons.join()),
  );
  const cmt = v(
    ch("jl4/examples/ok/named.l4"),
    fake({
      readers: [
        {
          name: "named.l4",
          file: "jl4/tests-cli/Main.hs",
          line: 9,
          text: "  -- see named.l4",
        },
      ],
    }),
  );
  check(
    "a mention in a Haskell comment line is not a reader",
    cmt.verdict === "corpus",
  );
  const shcmt = v(
    ch("doc/a.md"),
    fake({
      readers: [
        {
          name: "a.md",
          file: "etc/x.sh",
          line: 2,
          text: "echo a.md # not a comment line",
        },
      ],
    }),
  );
  check(
    "a mention at the end of a shell line is a reader",
    shcmt.verdict === "full",
  );
  const readme = {
    name: "README.md",
    file: "jl4/tests-cli/Main.hs",
    line: 481,
    text: 'p = "../doc/reference/syntax/README.md"',
  };
  check(
    "a generic name counts when the line shows its directory beside it",
    v(ch("doc/reference/syntax/README.md"), fake({ readers: [readme] }))
      .verdict === "full",
  );
  check(
    "a generic name counts when the line joins its segments",
    v(
      ch("doc/syntax/README.md"),
      fake({
        readers: [{ ...readme, text: 'p = root </> "syntax" </> "README.md"' }],
      }),
    ).verdict === "full",
  );
  check(
    "a generic name does not count for an unrelated directory",
    v(ch("doc/other/README.md"), fake({ readers: [readme] })).verdict ===
      "docs",
  );
  const wide = v(
    ch("doc/x.md"),
    fake({
      readers: [
        {
          name: "x.md",
          file: "jl4-lsp/test/Y.hs",
          line: 5,
          text: '"x.md"',
          scope: "wider",
        },
      ],
    }),
  );
  check(
    "a reader outside the gate is a note, not a reason",
    wide.verdict === "docs" &&
      wide.notes.some((n) => /also named by jl4-lsp\/test\/Y.hs:5/.test(n)),
  );
  check(
    "a mention in an L4 comment line is not a reader",
    v(
      ch("doc/x.md"),
      fake({
        readers: [
          {
            name: "x.md",
            file: "jl4/tests-cli/fixtures/f.l4",
            line: 2,
            text: "-- see x.md",
          },
        ],
      }),
    ).verdict === "docs",
  );
  const gold = v(
    ch("jl4/examples/ok/tests/a.nlg.golden"),
    fake({
      readers: [
        {
          name: "a.l4",
          file: "jl4-core/test/DminSpec.hs",
          line: 3,
          text: '"a.l4"',
        },
      ],
    }),
  );
  check(
    "a golden is named by its source's basename too",
    gold.verdict === "full",
  );
  check(
    "a deleted corpus .l4 with no importers runs nothing, so full",
    v(ch("-jl4/examples/ok/gone.l4"), fake()).verdict === "full",
  );

  // The real git adapter, over a throwaway repository: the fake above cannot catch a wrong git command line.
  const d = mkdtempSync(join(tmpdir(), "gfs-"));
  try {
    const sh = (...a) =>
      execFileSync(
        "git",
        ["-C", d, "-c", "user.name=t", "-c", "user.email=t@t", ...a],
        { encoding: "utf8" },
      );
    const put = (rel, text) => {
      mkdirSync(dirname(join(d, rel)), { recursive: true });
      writeFileSync(join(d, rel), text);
    };
    sh("init", "-q");
    put("jl4/examples/ok/lib.l4", "x MEANS 1\n");
    put("jl4/examples/ok/user.l4", "IMPORT lib\n\ny MEANS 2\n");
    put("jl4/examples/ok/other.l4", "z MEANS 3\n");
    put("jl4/examples/ok/tests/lib.golden", "g\n");
    put(
      "jl4/tests-cli/Main.hs",
      'f = "examples/ok/other.l4"\n-- a comment about lib.l4\n',
    );
    put("doc/a.md", "a\n");
    sh("add", "-A");
    sh("commit", "-q", "-m", "base");
    const baseSha = sh("rev-parse", "HEAD").trim();
    const real = (opts) => {
      const rev = opts.rev ?? null;
      return select(
        gitChanges(d, { baseRef: opts.base ?? "HEAD", rev }),
        gitRepo(d, rev),
      );
    };
    check(
      "real git: a clean tree changes nothing, so full",
      real({}).verdict === "full",
    );
    put("doc/a.md", "a2\n");
    check(
      "real git: an uncommitted markdown edit is docs",
      real({}).verdict === "docs",
    );
    put("jl4/examples/ok/lib.l4", "x MEANS 11\n");
    const w = real({});
    check(
      "real git: an edited module selects its importer, from the working tree",
      w.verdict === "corpus" &&
        w.matches.includes("/ok/lib.l4") &&
        w.matches.includes("/ok/user.l4"),
    );
    put("jl4/examples/ok/newuser.l4", "IMPORT lib\n\nq MEANS 4\n");
    check(
      "real git: an untracked importer is found too",
      real({}).matches.includes("/ok/newuser.l4"),
    );
    put("jl4/examples/ok/other.l4", "z MEANS 33\n");
    check(
      "real git: a file a test source names is full",
      real({}).verdict === "full" &&
        /other\.l4 is named by jl4\/tests-cli\/Main\.hs:1/.test(
          real({}).reasons.join(),
        ),
    );
    sh("checkout", "-q", "jl4/examples/ok/other.l4");
    rmSync(join(d, "jl4/examples/ok/newuser.l4"));
    sh("add", "-A");
    sh("commit", "-q", "-m", "edit");
    const c = real({ base: baseSha });
    check(
      "real git: a committed diff since a base reads the same",
      c.verdict === "corpus" && c.matches.includes("/ok/user.l4"),
    );
    const r = real({ rev: "HEAD" });
    check(
      "real git: --rev replays one commit against its parent",
      r.verdict === "corpus" && r.matches.includes("/ok/user.l4"),
    );
    const root = real({ rev: baseSha });
    check(
      "real git: --rev on a root commit does not crash",
      root.verdict === "full",
    );
  } finally {
    rmSync(d, { recursive: true, force: true });
  }
  console.log(failed === 0 ? "selftest: all ok" : `selftest: ${failed} FAILED`);
  return failed === 0 ? 0 : 3;
}

// ---------------------------------------------------------------------------------------
function main(argv) {
  if (argv.includes("--selftest")) process.exit(selftest());
  let baseRef = "origin/unstable";
  let rev = null;
  let json = false;
  let maxClosure = 120;
  let wt = ".";
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--base") baseRef = argv[++i];
    else if (a === "--rev") rev = argv[++i];
    else if (a === "--json") json = true;
    else if (a === "--max-closure") maxClosure = Number(argv[++i]);
    else if (a.startsWith("-")) {
      console.error(`gate-fast-select: unknown option ${a}`);
      process.exit(2);
    } else wt = a;
  }
  const repo = gitRepo(wt, rev);
  const changes = gitChanges(wt, { baseRef, rev });
  const res = select(changes, repo, { maxClosure });
  if (json) {
    console.log(JSON.stringify({ ...res, changed: changes.length }, null, 2));
    return;
  }
  console.log(`VERDICT\t${res.verdict}`);
  console.log(`CHANGED\t${changes.length}`);
  for (const r of res.reasons) console.log(`REASON\t${r}`);
  for (const n of res.notes) console.log(`NOTE\t${n}`);
  for (const f of res.files) console.log(`FILE\t${f}`);
  for (const m of res.matches) console.log(`MATCH\t${m}`);
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === resolve(new URL(import.meta.url).pathname)
)
  main(process.argv.slice(2));
