/**
 * Robbery ladder figures — the page assets for the canon encoding row
 * `subjects/sg/penal-code-1871/encodings/legalese/`.
 *
 * Modelled on `regcf.ts`, and for its reason: the corpus is read through the
 * LSP, so every label, every ordering and every inert chapeau comes out of
 * `robbery-390-392.l4` itself. Nothing is retyped, so nothing can drift. A
 * figure a human transcribed is a second source.
 *
 * ONE DIFFERENCE FROM regcf.ts WORTH KNOWING. That corpus lives in this
 * repository; this one lives in `legalese/canon`, which this repository must
 * never depend on (CLAUDE.md 1.2). So the row is located by CANON_DIR, the
 * same env var `ts-apps/charge-generator/scripts/seed.mjs` uses, and the
 * script SKIPS CLEANLY (exit 0) when canon is not checked out. It is not in
 * turbo.json and CI never runs it.
 *
 * Four emits per subject, all off the same decoded FunDecl:
 *   *.svg        sceneToSvg(scene, "ink")             — print/page figure
 *   *.txt        sceneToAscii(scene)                  — pasteable, and DIFFABLE
 *   *.mmd        toMermaidRailroad(fn, {theme:"ink"}) — for markdown that renders it
 *   *.sentences  expandSentences(fn)                  — READABLE PROSE
 *
 * The fourth carrier is the one to read first here. s 390 is the section a
 * criminal-law textbook states as a list of elements, and `.sentences` is the
 * projection that says the same thing one line at a time — so it is what a
 * textbook page can be held against, without anyone transcribing the ladder
 * into English by hand.
 *
 * Run (from ts-shared/ladder-svg):  npx tsx demo/robbery.ts
 * Env: JL4_LSP_PORT (default 5019), JL4_LSP_CMD (a prebuilt jl4-lsp; otherwise
 *      `cabal run`), CANON_DIR (default ~/src/legalese/canon).
 */
import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";
import { homedir } from "node:os";
import {
  layout,
  estimateMetrics,
  monoMetrics,
  ASCII_GEOMETRY,
  defaultViewSpec,
  fromVizFunDecl,
  sceneToAscii,
  toMermaidRailroad,
  expandSentences,
} from "@repo/ladder-core";
import type { IRExpr } from "@repo/ladder-core";
import { sceneToSvg } from "../src/index.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");
const CANON = process.env.CANON_DIR ?? resolve(homedir(), "src/legalese/canon");
const ROW = resolve(CANON, "subjects/sg/penal-code-1871/encodings/legalese");
const CORPUS = resolve(ROW, "robbery-390-392.l4");
const OUT = resolve(ROW, "projections");
const LSP_PORT = Number(process.env.JL4_LSP_PORT || 5019);

if (!existsSync(CORPUS)) {
  console.log(
    `[robbery] no canon corpus at ${CORPUS} — skipping.\n` +
      `          Set CANON_DIR to a legalese/canon checkout to generate the figures.`,
  );
  process.exit(0);
}

/**
 * The subjects, and why each is here. `slug` names the files; `decision` must
 * match the decision's own name in the corpus EXACTLY, so a rename in the L4
 * breaks this loudly rather than silently dropping a figure.
 */
const SUBJECTS: { decision: string; slug: string; why: string }[] = [
  {
    decision: "commits robbery",
    slug: "robbery-390",
    why: "the root picture: s 390(1), a two-way OR over the two subsections. This is the figure a reader should meet first",
  },
  {
    decision: "theft is robbery",
    slug: "robbery-390-2",
    why: "s 390(2): the theft, then the WHEN group, then the purposive link, then causes-or-attempts, then the six harms. The widest of the six, and the one to compare against a textbook's element list",
  },
  {
    decision: "extortion is robbery",
    slug: "robbery-390-3",
    why: "s 390(3): the other limb — presence, the three instant harms, to whom, and then-and-there. Illustration (d) is the boundary these leaves draw",
  },
  {
    decision: "offence under s 392",
    slug: "robbery-392",
    why: "the punishing section: one rung over `commits robbery`, which is what makes the definition/punishment split visible",
  },
  {
    decision: "offence under s 393",
    slug: "robbery-393",
    why: "the attempt: ONE leaf. The smallest figure in the row, and deliberately so — s 393 adds nothing to s 390 but the word 'attempts'",
  },
  {
    decision: "offence under s 394",
    slug: "robbery-394",
    why: "hurt in committing robbery: not s 392 plus a leaf. Its first limb is its own OR (robbery or an attempt at one) and it asks a second question about where the accused stood",
  },
];

/* ---------------------------------------------------------------- the LSP client */

const portOpen = (port: number) =>
  new Promise<boolean>((res) => {
    const s = net
      .connect(port, "127.0.0.1")
      .on("connect", () => (s.end(), res(true)))
      .on("error", () => res(false));
  });

let lspChild: ChildProcess | null = null;
async function ensureLsp() {
  if (await portOpen(LSP_PORT)) {
    console.log(`[robbery] using existing jl4-lsp on :${LSP_PORT}`);
    return;
  }
  const custom = process.env.JL4_LSP_CMD;
  const [cmd, args] = custom
    ? [custom, ["ws", "--host", "127.0.0.1", "--port", String(LSP_PORT)]]
    : [
        "cabal",
        [
          "run",
          "-v0",
          "exe:jl4-lsp",
          "--",
          "ws",
          "--host",
          "127.0.0.1",
          "--port",
          String(LSP_PORT),
        ],
      ];
  console.log(`[robbery] spawning ${cmd} on :${LSP_PORT} …`);
  lspChild = spawn(cmd, args, {
    cwd: REPO,
    env: {
      ...process.env,
      JL4_LIBRARY_PATH: resolve(REPO, "jl4-core/libraries"),
    },
  });
  lspChild.stderr?.on("data", (d: Buffer) => {
    const s = String(d);
    if (/error|Error/.test(s)) process.stderr.write(`[lsp] ${s}`);
  });
  for (let i = 0; i < 300; i++) {
    if (await portOpen(LSP_PORT)) {
      console.log("[robbery] jl4-lsp is up");
      return;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("jl4-lsp did not come up in time");
}

let ws: WebSocket;
let nextId = 1;
const pending = new Map<number, (m: any) => void>();

function connectLsp() {
  return new Promise<void>((res, rej) => {
    ws = new WebSocket(`ws://127.0.0.1:${LSP_PORT}`);
    ws.addEventListener("message", (ev: MessageEvent) => {
      let msg: any;
      try {
        msg = JSON.parse(String(ev.data));
      } catch {
        return;
      }
      for (const m of Array.isArray(msg) ? msg : [msg]) {
        if (
          m.id !== undefined &&
          (m.result !== undefined || m.error !== undefined)
        ) {
          const p = pending.get(m.id);
          if (p) pending.delete(m.id), p(m);
        } else if (m.id !== undefined && m.method) {
          const result =
            m.method === "workspace/configuration"
              ? (m.params?.items ?? []).map(() => ({}))
              : null;
          ws.send(JSON.stringify({ jsonrpc: "2.0", id: m.id, result }));
        }
      }
    });
    ws.addEventListener("open", () => res());
    ws.addEventListener("error", () => rej(new Error("ws error")));
  });
}
const rpc = (
  method: string,
  params: unknown,
  timeoutMs = 60000,
): Promise<any> => {
  const id = nextId++;
  return new Promise((res, rej) => {
    pending.set(id, (m) =>
      m.error
        ? rej(new Error(method + ": " + JSON.stringify(m.error)))
        : res(m.result),
    );
    ws.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
    setTimeout(() => {
      if (pending.has(id))
        pending.delete(id), rej(new Error(method + " timeout"));
    }, timeoutMs);
  });
};
const notify = (method: string, params: unknown) =>
  ws.send(JSON.stringify({ jsonrpc: "2.0", method, params }));

/* ------------------------------------------------------------------- the measure */

/** The longest single leaf label in a tree. BBE does not wrap leaf labels
 *  (layout.ts: `w = caretW + tm.width(label, FONT) + 2*PAD_X`), so this alone
 *  sets a lower bound on the scene width, independent of any structure. Printed
 *  per subject so an overflowing figure is visible from the console rather than
 *  only from opening the SVG. */
function longestLeaf(e: IRExpr): string {
  const longer = (a: string, b: string) => (b.length > a.length ? b : a);
  switch (e.$type) {
    case "And":
    case "Or":
      return e.args.map(longestLeaf).reduce(longer, "");
    case "Not":
      return longestLeaf(e.negand);
    case "Implies":
      return longer(longestLeaf(e.scope), longestLeaf(e.requirement));
    case "InertE":
      return "";
    default:
      return e.label ?? "";
  }
}

async function main() {
  await ensureLsp();
  await connectLsp();
  await rpc("initialize", {
    processId: null,
    rootUri: "file://" + REPO,
    capabilities: {},
    workspaceFolders: [{ uri: "file://" + REPO, name: "repo" }],
  });
  notify("initialized", {});

  const uri = "file://" + CORPUS;
  notify("textDocument/didOpen", {
    textDocument: {
      uri,
      languageId: "l4",
      version: 1,
      text: readFileSync(CORPUS, "utf8"),
    },
  });
  await new Promise((r) => setTimeout(r, 1500));

  const lenses: any[] =
    (await rpc("textDocument/codeLens", { textDocument: { uri } })) || [];
  const viz = lenses.filter((l) => l.command?.title === "Show decision graph");
  console.log(`[robbery] ${viz.length} visualisable decisions in the corpus`);

  // The wire label keeps the L4 backticks a spaced name is written with
  // (`\`issuer is eligible\``), so match on the unquoted form.
  const unquote = (s: string) => s.replace(/`/g, "").trim();

  const byName = new Map<string, any>();
  for (const l of viz) {
    const info = await rpc("workspace/executeCommand", {
      command: l.command.command,
      arguments: l.command.arguments,
    });
    const nm = info?.funDecl?.name?.label;
    if (nm) byName.set(unquote(nm), info.funDecl);
  }

  mkdirSync(OUT, { recursive: true });
  const missing: string[] = [];
  const rows: string[] = [];

  for (const s of SUBJECTS) {
    const funDecl = byName.get(s.decision);
    if (!funDecl) {
      missing.push(s.decision);
      continue;
    }
    const decoded = fromVizFunDecl(funDecl);
    const vs = defaultViewSpec({
      valuation: decoded.valuation,
      provenance: decoded.provenance,
    });

    const scene = layout(decoded.fn, vs, estimateMetrics);
    writeFileSync(`${OUT}/${s.slug}.svg`, sceneToSvg(scene, "ink"));

    const asciiScene = layout(decoded.fn, vs, monoMetrics(), ASCII_GEOMETRY);
    writeFileSync(`${OUT}/${s.slug}.txt`, sceneToAscii(asciiScene) + "\n");

    writeFileSync(
      `${OUT}/${s.slug}.mmd`,
      toMermaidRailroad(decoded.fn, { theme: "ink" }) + "\n",
    );

    const lines = expandSentences(decoded.fn, vs.foldSet);
    writeFileSync(
      `${OUT}/${s.slug}.sentences`,
      `${s.decision}\n${"=".repeat(s.decision.length)}\n\n` +
        `${lines.length} way${lines.length === 1 ? "" : "s"} this can be satisfied.\n\n` +
        lines.map((l, i) => `${String(i + 1).padStart(3)}. ${l}`).join("\n") +
        "\n",
    );

    const leaf = longestLeaf(decoded.fn.body);
    const w = Math.round(scene.size.w);
    const h = Math.round(scene.size.h);
    rows.push(
      `${s.slug.padEnd(28)} ${String(w).padStart(6)}x${String(h).padEnd(5)}` +
        `  ${String(lines.length).padStart(3)} sentence(s)` +
        `  longest leaf ${String(leaf.length).padStart(4)} chars`,
    );
    console.log(
      `wrote ${s.slug}.{svg,txt,mmd,sentences}  ${w}x${h}  ${lines.length} sentence(s)  longest leaf ${leaf.length} chars` +
        (leaf.length > 90 ? `\n        "${leaf.slice(0, 90)}…"` : ""),
    );
  }

  console.log(
    `\n===== Penal Code robbery ladder figures =====\n${rows.join("\n")}`,
  );
  if (missing.length) {
    console.error(
      `\nFAILED: ${missing.length} decision(s) not found in robbery-390-392.l4 — has one been renamed?\n  ` +
        missing.join("\n  "),
    );
    lspChild?.kill();
    process.exit(1);
  }
  console.log(`\nwrote ${SUBJECTS.length * 4} files to ${OUT}`);
  lspChild?.kill();
  process.exit(0);
}

process.on("SIGINT", () => (lspChild?.kill(), process.exit(0)));
main().catch((e) => {
  console.error(e);
  lspChild?.kill();
  process.exit(1);
});
