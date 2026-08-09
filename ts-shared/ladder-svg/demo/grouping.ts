/**
 * Grouping-and-precedence tutorial figures.
 *
 * Derived from demo/regcf.ts — same transport, different corpus and subjects.
 * Reads doc/tutorials/getting-started/grouping-and-precedence.l4 through the LSP,
 * so no label here is retyped and none can drift from the code the tutorial quotes.
 *
 * Unlike `s415.ts` and `charities-a3.ts`, which hand-build their `IRExpr` in
 * TypeScript with local `leaf`/`and`/`or` helpers and whose labels are (their
 * own header says so) "the statutory phrases, TRIMMED FOR THE PAGE", this one
 * reads the real corpus. Nothing here is retyped, so nothing here can drift
 * from the L4: every label, every ordering, every inert chapeau comes out of
 * `jl4/examples/legal/regcf/regcf.l4` through the LSP. That is the whole point
 * — the competitive thesis is single-sourcing, and a figure a human transcribed
 * is a second source.
 *
 * The transport (spawn `jl4-lsp` in ws mode, codeLens -> `l4.visualize` ->
 * `RenderAsLadderInfo.funDecl` -> `fromVizFunDecl`) is lifted from
 * `spike/corpus-sizes.ts`, which is lifted from `standalone/serve.mjs`. Do not
 * write a fourth copy.
 *
 * Four emits per subject, all off the same decoded `FunDecl`:
 *   *.svg        sceneToSvg(scene, "ink")             — print/page figure
 *   *.txt        sceneToAscii(scene)                  — pasteable, and DIFFABLE
 *   *.mmd        toMermaidRailroad(fn, {theme:"ink"}) — for markdown that renders it
 *   *.sentences  expandSentences(fn)                  — READABLE PROSE
 *
 * The fourth carrier exists because the page this exhibit is measured against
 * is prose, and until 2026-07-27 every artifact here was a diagram, an XML
 * model or a loss report: the only scannable English in the deliverable was
 * hand-written README commentary, which is itself a second source. One
 * sentence per way the rule can be satisfied is the surplusage view a
 * compliance reader actually reads, and it is a projection, so it cannot
 * drift.
 *
 * The four carriers are NOT interchangeable, and the sentence file is where
 * that is easiest to see. `toMermaidRailroad` deliberately drops the medial
 * inert glue inside an OR — a railroad `choice` branch is a live path, and
 * prose-as-branch would make the disjunction trivially satisfiable — so
 * `regcf-resale-exceptions.mmd` carries the chapeau and none of limbs (2)-(4)'s
 * captions, while the SVG, the ASCII and the sentences carry all four.
 *
 * Run (from ts-shared/ladder-svg):  npx tsx demo/regcf.ts
 * Env: JL4_LSP_PORT (default 5019). Writes jl4/examples/legal/regcf/figures/.
 *      Set JL4_LSP_CMD to point at a prebuilt jl4-lsp instead of `cabal run`.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";
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
const CORPUS = resolve(
  REPO,
  "doc/tutorials/getting-started/grouping-and-precedence.l4",
);
const OUT = resolve(REPO, "doc/tutorials/getting-started/figures");
const LSP_PORT = Number(process.env.JL4_LSP_PORT || 5019);

/**
 * The subjects, and why each is here. `slug` names the files; `decision` must
 * match the decision's own name in the corpus EXACTLY, so a rename in the L4
 * breaks this loudly rather than silently dropping a figure.
 */
const SUBJECTS: { decision: string; slug: string; why: string }[] = [
  {
    decision: "left grouped",
    slug: "grouping-left",
    why: "(a OR b) AND c — the OR nested one level in, so it binds first",
  },
  {
    decision: "right grouped",
    slug: "grouping-right",
    why: "a OR (b AND c) — same three atoms, same operators, one indentation apart",
  },
  {
    decision: "contravenes s 229(4)",
    slug: "grouping-chew",
    why: "Chew: the comma the High Court divided over, as a mandatory indentation",
  },
  {
    decision: "exempt — packing is one activity",
    slug: "grouping-oakhurst-one",
    why: "Oakhurst reading 1: packing, qualified by either destination — one leaf",
  },
  {
    decision: "exempt — packing and distribution are two",
    slug: "grouping-oakhurst-two",
    why: "Oakhurst reading 2: packing-for-shipment, and distribution — two leaves",
  },
  {
    decision: "in force — notice binds renewals only",
    slug: "grouping-rogers-renewals",
    why: "Rogers reading 1: the termination right reaches the successive terms only",
  },
  {
    decision: "in force — notice binds both",
    slug: "grouping-rogers-both",
    why: "Rogers reading 2: it reaches the initial term too — the reading that cost the money",
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
    console.log(`[regcf] using existing jl4-lsp on :${LSP_PORT}`);
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
  console.log(`[regcf] spawning ${cmd} on :${LSP_PORT} …`);
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
      console.log("[regcf] jl4-lsp is up");
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
  console.log(`[regcf] ${viz.length} visualisable decisions in the corpus`);

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

  console.log(`\n===== Reg CF ladder figures =====\n${rows.join("\n")}`);
  if (missing.length) {
    console.error(
      `\nFAILED: ${missing.length} subject(s) not found in the corpus — has a decision been renamed?\n  ` +
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
