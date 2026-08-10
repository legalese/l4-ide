/**
 * R1 spike (E1-IDE-INTEGRATION.md §5) — *does BBE survive a real corpus?*
 *
 * ladder-core has only ever laid out the s415 hand fixture, `may-purchase-alcohol`,
 * and whatever the playground was pointed at. Dagre, by contrast, has been driven by
 * every module anyone has ever opened in the IDE. BBE is align-then-stack with no edge
 * routing, so the open question before E1 Step 4 is whether a wide OR of long statutory
 * prose simply blows the pane.
 *
 * So: drive every decision in the corpus through jl4-lsp -> RenderAsLadderInfo ->
 * fromVizFunDecl -> layout, and record the Scene size. The LSP plumbing is lifted from
 * standalone/serve.mjs, which already does the codeLens/executeCommand capture.
 *
 * Run (from ts-shared/ladder-svg):  npx tsx spike/corpus-sizes.ts [glob-root ...]
 * Env: JL4_LSP_PORT (default 5017). Writes spike/out/corpus-sizes.json.
 */
import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import { resolve, dirname, relative, join } from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";
import {
  layout,
  estimateMetrics,
  defaultViewSpec,
  fromVizFunDecl,
} from "@repo/ladder-core";
import type { IRExpr } from "@repo/ladder-core";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, "../../..");
const LSP_PORT = Number(process.env.JL4_LSP_PORT || 5017);
const GHCUP = "/Users/mengwong/.ghcup/bin";
const ROOTS = process.argv.slice(2).length
  ? process.argv.slice(2)
  : ["jl4/examples/ok"];

/* ------------------------------------------------------------- collect the corpus */

function walk(dir: string, acc: string[] = []): string[] {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, acc);
    else if (e.name.endsWith(".l4")) acc.push(p);
  }
  return acc;
}
const files = ROOTS.flatMap((r) => walk(resolve(REPO, r))).sort();
console.log(`[r1] ${files.length} .l4 files under ${ROOTS.join(", ")}`);

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
    console.log(`[r1] using existing jl4-lsp on :${LSP_PORT}`);
    return;
  }
  console.log(`[r1] spawning jl4-lsp ws on :${LSP_PORT} …`);
  lspChild = spawn(
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
    {
      cwd: REPO,
      env: {
        ...process.env,
        PATH: `${GHCUP}:${process.env.PATH}`,
        JL4_LIBRARY_PATH: resolve(REPO, "jl4-core/libraries"),
      },
    },
  );
  lspChild.stderr?.on("data", (d: Buffer) => {
    const s = String(d);
    if (/error|Error/.test(s)) process.stderr.write(`[lsp] ${s}`);
  });
  for (let i = 0; i < 240; i++) {
    if (await portOpen(LSP_PORT)) {
      console.log("[r1] jl4-lsp is up");
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
  timeoutMs = 30000,
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

/* -------------------------------------------------------------------- the measure */

interface Row {
  file: string;
  decision: string;
  w: number;
  h: number;
  leaves: number;
  depth: number;
  fan: number;
  label: string;
}
const rows: Row[] = [];
const errors: { file: string; err: string }[] = [];

/** Leaves + nesting depth + max OR fan-out of the DRAWN tree — the three things that
 *  drive BBE size. Fan-out is the one R1 is really about: BBE stacks an OR's rungs
 *  vertically and aligns them to the widest, so a wide OR of long prose is the shape
 *  that would blow the pane. Typed against IRExpr, not `any`, so a wrong field name is
 *  a compile error rather than a silently-dropped row (which is exactly what the first
 *  run of this spike did: it read `.children` instead of `.args`, threw on every
 *  compound node, and reported stats over the trivial diagrams only). */
interface Shape {
  leaves: number;
  depth: number;
  fan: number;
  /** the longest single leaf label — BBE does not wrap, so this alone sets a lower
   *  bound on the scene width, independent of any structure */
  label: string;
}
const longest = (xs: string[]) =>
  xs.reduce((a, b) => (b.length > a.length ? b : a), "");

function shape(e: IRExpr): Shape {
  switch (e.$type) {
    case "And":
    case "Or": {
      const kids = e.args.map(shape);
      return {
        leaves: kids.reduce((a, k) => a + k.leaves, 0),
        depth: 1 + Math.max(...kids.map((k) => k.depth), 0),
        fan: Math.max(
          e.$type === "Or" ? e.args.length : 0,
          ...kids.map((k) => k.fan),
          0,
        ),
        label: longest(kids.map((k) => k.label)),
      };
    }
    case "Not": {
      const k = shape(e.negand);
      return {
        leaves: k.leaves,
        depth: 1 + k.depth,
        fan: k.fan,
        label: k.label,
      };
    }
    case "Implies": {
      const p = shape(e.scope);
      const q = shape(e.requirement);
      return {
        leaves: p.leaves + q.leaves,
        depth: 1 + Math.max(p.depth, q.depth),
        fan: Math.max(p.fan, q.fan),
        label: longest([p.label, q.label]),
      };
    }
    case "InertE":
      return { leaves: 0, depth: 1, fan: 0, label: "" };
    default:
      return { leaves: 1, depth: 1, fan: 0, label: e.label ?? "" };
  }
}

async function measure(file: string) {
  const uri = "file://" + file;
  const text = readFileSync(file, "utf8");
  notify("textDocument/didOpen", {
    textDocument: { uri, languageId: "l4", version: 1, text },
  });
  await new Promise((r) => setTimeout(r, 250));
  let lenses: any[] = [];
  try {
    lenses =
      (await rpc("textDocument/codeLens", { textDocument: { uri } })) || [];
  } catch (e) {
    errors.push({ file, err: "codeLens: " + String(e) });
    notify("textDocument/didClose", { textDocument: { uri } });
    return;
  }
  const viz = lenses.filter((l) => l.command?.title === "Show decision graph");
  for (const l of viz) {
    try {
      const info = await rpc("workspace/executeCommand", {
        command: l.command.command,
        arguments: l.command.arguments,
      });
      if (!info?.funDecl) continue;
      const decoded = fromVizFunDecl(info.funDecl);
      const scene = layout(
        decoded.fn,
        defaultViewSpec({
          valuation: decoded.valuation,
          provenance: decoded.provenance,
        }),
        estimateMetrics,
      );
      const sh = shape(decoded.fn.body);
      rows.push({
        file: relative(REPO, file),
        decision: info.funDecl.name?.label ?? "?",
        w: Math.round(scene.size.w),
        h: Math.round(scene.size.h),
        leaves: sh.leaves,
        depth: sh.depth,
        fan: sh.fan,
        label: sh.label,
      });
    } catch (e) {
      errors.push({ file: relative(REPO, file), err: String(e).slice(0, 120) });
    }
  }
  notify("textDocument/didClose", { textDocument: { uri } });
}

/* ------------------------------------------------------------------------- report */

const pct = (xs: number[], p: number) =>
  xs.length
    ? xs.slice().sort((a, b) => a - b)[Math.floor((xs.length - 1) * p)]
    : 0;

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

  let n = 0;
  for (const f of files) {
    await measure(f);
    if (++n % 25 === 0)
      console.log(`[r1] ${n}/${files.length} … ${rows.length} decisions`);
  }

  const ws_ = rows.map((r) => r.w);
  const hs = rows.map((r) => r.h);
  // The IDE pane is roughly 900x700 CSS px before the user pans. Call anything wider
  // than 1600 "needs scale modes / auto-fold", which is what R1 is really asking.
  const WIDE = 1600;
  const wide = rows.filter((r) => r.w > WIDE).sort((a, b) => b.w - a.w);

  console.log(`\n===== R1: BBE on the real corpus =====`);
  console.log(
    `files: ${files.length}   decisions laid out: ${rows.length}   errors: ${errors.length}`,
  );
  console.log(
    `width  px  p50=${pct(ws_, 0.5)}  p90=${pct(ws_, 0.9)}  p99=${pct(ws_, 0.99)}  max=${Math.max(...ws_, 0)}`,
  );
  console.log(
    `height px  p50=${pct(hs, 0.5)}  p90=${pct(hs, 0.9)}  p99=${pct(hs, 0.99)}  max=${Math.max(...hs, 0)}`,
  );
  console.log(
    `leaves     p50=${pct(
      rows.map((r) => r.leaves),
      0.5,
    )}  p90=${pct(
      rows.map((r) => r.leaves),
      0.9,
    )}  max=${Math.max(...rows.map((r) => r.leaves), 0)}`,
  );
  console.log(
    `depth      p50=${pct(
      rows.map((r) => r.depth),
      0.5,
    )}  p90=${pct(
      rows.map((r) => r.depth),
      0.9,
    )}  max=${Math.max(...rows.map((r) => r.depth), 0)}`,
  );
  console.log(
    `OR fan-out p50=${pct(
      rows.map((r) => r.fan),
      0.5,
    )}  p90=${pct(
      rows.map((r) => r.fan),
      0.9,
    )}  max=${Math.max(...rows.map((r) => r.fan), 0)}`,
  );
  console.log(
    `\nwider than ${WIDE}px: ${wide.length} / ${rows.length} (${((100 * wide.length) / (rows.length || 1)).toFixed(1)}%)`,
  );
  for (const r of wide.slice(0, 15))
    console.log(
      `  ${String(r.w).padStart(6)}x${String(r.h).padEnd(5)} leaves=${String(r.leaves).padStart(3)} depth=${String(r.depth).padStart(2)} fan=${String(r.fan).padStart(2)}  ${r.decision}\n         longest leaf label (${r.label.length} chars): "${r.label.slice(0, 90)}${r.label.length > 90 ? "…" : ""}"`,
    );
  if (errors.length) {
    console.log(`\nerrors (first 10):`);
    for (const e of errors.slice(0, 10)) console.log(`  ${e.file}: ${e.err}`);
  }

  mkdirSync(resolve(HERE, "out"), { recursive: true });
  writeFileSync(
    resolve(HERE, "out/corpus-sizes.json"),
    JSON.stringify({ rows, errors }, null, 2),
  );
  console.log(`\nwrote spike/out/corpus-sizes.json`);
  lspChild?.kill();
  process.exit(0);
}

process.on("SIGINT", () => (lspChild?.kill(), process.exit(0)));
main().catch((e) => {
  console.error(e);
  lspChild?.kill();
  process.exit(1);
});
