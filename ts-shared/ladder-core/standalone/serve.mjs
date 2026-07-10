/**
 * Ladder playground bridge — a tiny, IDE-free dev server for prototyping ladder
 * diagrams against REAL L4. It:
 *   1. bundles playground.ts (esbuild) and serves standalone/dist/ over HTTP;
 *   2. connects to a running `jl4-lsp` websocket server (or spawns one), and
 *      exposes `POST /render {l4}` that runs the visualize capture
 *      (initialize → didOpen → codeLens → executeCommand "Show decision graph")
 *      and returns every decision's RenderAsLadderInfo.funDecl.
 *
 * No SvelteKit, no Monaco, no webview. Run from ts-shared/ladder-core:
 *   node standalone/serve.mjs          # → http://localhost:8731
 * Env: JL4_LSP_PORT (default 5007), PORT (default 8731), REPO (auto).
 */
import { createServer } from "node:http";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";

const HERE = dirname(fileURLToPath(import.meta.url));
const CORE = resolve(HERE, "..");
const REPO = process.env.REPO || resolve(CORE, "../..");
const LIBS = resolve(REPO, "jl4-core/libraries");
const ROOT_URI = "file://" + LIBS;
const HTTP_PORT = Number(process.env.PORT || 8731);
const LSP_PORT = Number(process.env.JL4_LSP_PORT || 5007);
const DIST = resolve(HERE, "dist");
const GHCUP = "/Users/mengwong/.ghcup/bin";

/* --------------------------------------------------------- 1. bundle the page */
console.log("[playground] bundling playground.ts …");
const build = spawnSync(
  "npx",
  [
    "esbuild",
    resolve(HERE, "playground.ts"),
    "--bundle",
    "--format=iife",
    `--outfile=${resolve(DIST, "playground.js")}`,
  ],
  { cwd: CORE, stdio: "inherit" },
);
if (build.status !== 0) {
  console.error("[playground] esbuild failed");
  process.exit(1);
}

/* ---------------------------------------------- 2. ensure a jl4-lsp ws server */
const portOpen = (port) =>
  new Promise((res) => {
    const s = net
      .connect(port, "127.0.0.1")
      .on("connect", () => (s.end(), res(true)))
      .on("error", () => res(false));
  });

let lspChild = null;
async function ensureLsp() {
  if (await portOpen(LSP_PORT)) {
    console.log(`[playground] using existing jl4-lsp on :${LSP_PORT}`);
    return;
  }
  console.log(`[playground] spawning jl4-lsp ws on :${LSP_PORT} …`);
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
      "--cwd",
      "jl4-core/libraries",
    ],
    {
      cwd: REPO,
      env: { ...process.env, PATH: `${GHCUP}:${process.env.PATH}` },
    },
  );
  lspChild.stderr.on("data", (d) => process.stderr.write(`[lsp] ${d}`));
  for (let i = 0; i < 120; i++) {
    if (await portOpen(LSP_PORT)) {
      console.log("[playground] jl4-lsp is up");
      return;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("jl4-lsp did not come up on time");
}

/* ------------------------------------- a persistent LSP JSON-RPC ws client */
let ws = null;
let nextId = 1;
const pending = new Map();
let docSeq = 0;

function connectLsp() {
  return new Promise((res, rej) => {
    ws = new WebSocket(`ws://127.0.0.1:${LSP_PORT}`);
    ws.addEventListener("message", (ev) => {
      let msg;
      try {
        msg = JSON.parse(ev.data);
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
          const res =
            m.method === "workspace/configuration"
              ? (m.params?.items ?? []).map(() => ({}))
              : null;
          ws.send(JSON.stringify({ jsonrpc: "2.0", id: m.id, result: res }));
        }
      }
    });
    ws.addEventListener("open", () => res());
    ws.addEventListener("error", () => rej(new Error("ws error")));
  });
}
const rpc = (method, params) => {
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
    }, 20000);
  });
};
const notify = (method, params) =>
  ws.send(JSON.stringify({ jsonrpc: "2.0", method, params }));

async function initLsp() {
  await rpc("initialize", {
    processId: null,
    rootUri: ROOT_URI,
    capabilities: {},
    workspaceFolders: [{ uri: ROOT_URI, name: "libs" }],
  });
  notify("initialized", {});
}

/** didOpen a fresh doc (unique uri per render → no version bookkeeping), then
 *  list "Show decision graph" lenses and execute each; return the funDecls. */
async function renderL4(l4) {
  const uri = "file://" + resolve(LIBS, `_playground_${++docSeq}.l4`);
  notify("textDocument/didOpen", {
    textDocument: { uri, languageId: "l4", version: 1, text: l4 },
  });
  await new Promise((r) => setTimeout(r, 600)); // settle typecheck
  const lenses =
    (await rpc("textDocument/codeLens", { textDocument: { uri } })) || [];
  const viz = lenses.filter((l) => l.command?.title === "Show decision graph");
  const funcs = [];
  for (const l of viz) {
    try {
      const info = await rpc("workspace/executeCommand", {
        command: l.command.command,
        arguments: l.command.arguments,
      });
      if (info?.funDecl)
        funcs.push({
          name: info.funDecl.name?.label ?? "?",
          funDecl: info.funDecl,
        });
    } catch (e) {
      funcs.push({ name: "(error)", error: String(e) });
    }
  }
  notify("textDocument/didClose", { textDocument: { uri } });
  return funcs;
}

/* ---- curated inert-style examples (the point: inert L4 → interactive ladder) */
const EXAMPLES = [
  {
    id: "cheating",
    label: "s415 cheating (Poh Yuan Nie)",
    path: "jl4/ok/inert/cheating-415-poh-yuan-nie.l4",
  },
  { id: "basic", label: "inert: basic", path: "jl4/ok/inert/basic.l4" },
  { id: "simple", label: "inert: simple", path: "jl4/ok/inert/simple.l4" },
  {
    id: "asyndetic",
    label: "inert: asyndetic disjunction",
    path: "jl4/ok/inert/asyndetic-disjunction.l4",
  },
  {
    id: "nested",
    label: "inert: nested context",
    path: "jl4/ok/inert/nested-context.l4",
  },
  {
    id: "typically",
    label: "TYPICALLY defaults (may purchase alcohol)",
    path: "jl4/examples/ok/typically-basic.l4",
  },
];

/* --------------------------------------------------------------- 3. http */
const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
};
const server = createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/examples") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(EXAMPLES.map(({ id, label }) => ({ id, label }))));
    return;
  }
  if (req.method === "GET" && req.url?.startsWith("/example?")) {
    const id = new URL(req.url, "http://x").searchParams.get("id");
    const ex = EXAMPLES.find((e) => e.id === id);
    const file = ex && resolve(REPO, ex.path);
    if (file && existsSync(file)) {
      res.writeHead(200, { "content-type": "text/plain" });
      res.end(readFileSync(file));
    } else res.writeHead(404).end("no such example");
    return;
  }
  if (req.method === "POST" && req.url === "/render") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", async () => {
      try {
        const { l4 } = JSON.parse(body || "{}");
        const funcs = await renderL4(String(l4 ?? ""));
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ funcs }));
      } catch (e) {
        res.writeHead(500, { "content-type": "application/json" });
        res.end(JSON.stringify({ error: String(e) }));
      }
    });
    return;
  }
  // static
  const rel = req.url === "/" ? "/playground.html" : req.url.split("?")[0];
  const candidates = [resolve(DIST, "." + rel), resolve(HERE, "." + rel)];
  const file = candidates.find((f) => existsSync(f) && !f.endsWith("/"));
  if (file) {
    res.writeHead(200, { "content-type": MIME[extname(file)] || "text/plain" });
    res.end(readFileSync(file));
  } else {
    res.writeHead(404).end("not found");
  }
});

process.on("SIGINT", () => (lspChild?.kill(), process.exit(0)));
process.on("exit", () => lspChild?.kill());

await ensureLsp();
await connectLsp();
await initLsp();
server.listen(HTTP_PORT, () =>
  console.log(`[playground] ready → http://localhost:${HTTP_PORT}`),
);
