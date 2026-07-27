/**
 * Ladder playground bridge — a tiny, IDE-free dev server for prototyping ladder
 * diagrams against REAL L4. It:
 *   1. bundles playground.ts (esbuild) and serves standalone/dist/ over HTTP;
 *   2. connects to a running `jl4-lsp` websocket server (or spawns one), and
 *      exposes `POST /render {l4}` that runs the visualize capture
 *      (initialize → didOpen → codeLens → executeCommand "Show decision graph")
 *      and returns every decision's RenderAsLadderInfo.funDecl.
 *
 * No SvelteKit, no Monaco, no webview. Run from ts-shared/ladder-svg:
 *   node standalone/serve.mjs          # → http://localhost:8731
 * Env: JL4_LSP_PORT (default 5007), PORT (default 8731), REPO (auto).
 */
import { createServer } from "node:http";
import { spawn, spawnSync } from "node:child_process";
import { readFileSync, existsSync, statSync } from "node:fs";
import { resolve, dirname, extname } from "node:path";
import { fileURLToPath } from "node:url";
import net from "node:net";

const HERE = dirname(fileURLToPath(import.meta.url));
const PKG = resolve(HERE, "..");
const REPO = process.env.REPO || resolve(PKG, "../..");
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
  { cwd: PKG, stdio: "inherit" },
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
/** uri -> the last `textDocument/publishDiagnostics` payload for it. The server
 *  reports parse/typecheck failures ONLY here; a broken document still answers
 *  `codeLens` with an opaque `BadDependency`, so without this the page could say
 *  nothing more useful than "500". */
const diagnostics = new Map();

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
        } else if (m.method === "textDocument/publishDiagnostics") {
          // a notification: no id, so the branches above never see it
          diagnostics.set(m.params?.uri, m.params?.diagnostics ?? []);
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
  diagnostics.delete(uri);
  notify("textDocument/didOpen", {
    textDocument: { uri, languageId: "l4", version: 1, text: l4 },
  });
  // Wait for the server's own verdict rather than a flat 600ms: diagnostics
  // arrive when the typecheck settles, and an EMPTY array is a real answer
  // (a clean file), so poll for the key's presence, not its truthiness.
  for (let i = 0; i < 40 && !diagnostics.has(uri); i++)
    await new Promise((r) => setTimeout(r, 50));
  const diags = (diagnostics.get(uri) ?? []).map((d) => ({
    severity: d.severity ?? 1, // 1 Error, 2 Warning, 3 Information, 4 Hint
    line: (d.range?.start?.line ?? 0) + 1, // LSP is 0-based; editors are 1-based
    column: (d.range?.start?.character ?? 0) + 1,
    message: d.message ?? "",
  }));
  const errors = diags.filter((d) => d.severity === 1);

  // A file that does not typecheck cannot produce a decision graph; asking anyway
  // yields the opaque `BadDependency`. Return the diagnostics instead — they are
  // the actual answer to "why is there no ladder?".
  if (errors.length) return { funcs: [], diagnostics: diags };

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
  diagnostics.delete(uri);
  return { funcs, diagnostics: diags };
}

/* ---- curated inert-style examples (the point: inert L4 → interactive ladder) */
const EXAMPLES = [
  {
    id: "cheating",
    label: "s415 cheating (Poh Yuan Nie)",
    path: "jl4/examples/ok/inert/cheating-415-poh-yuan-nie.l4",
  },
  {
    id: "basic",
    label: "inert: basic",
    path: "jl4/examples/ok/inert/basic.l4",
  },
  {
    id: "asyndetic",
    label: "inert: asyndetic disjunction",
    path: "jl4/examples/ok/inert/asyndetic-disjunction.l4",
  },
  {
    id: "nested",
    label: "inert: nested context",
    path: "jl4/examples/ok/inert/nested-context.l4",
  },
  {
    id: "context",
    label: "inert: context-aware",
    path: "jl4/examples/ok/inert/context-aware.l4",
  },
  {
    id: "typically",
    label: "TYPICALLY defaults (may purchase alcohol)",
    path: "jl4/examples/ok/typically-basic.l4",
  },
  {
    id: "grounding",
    label:
      "grounding variants (permission vs obligation, defaults, permutations)",
    path: "jl4/examples/ok/inert/grounding-variants.l4",
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
        const { funcs, diagnostics } = await renderL4(String(l4 ?? ""));
        // 200 even when the file does not typecheck: "your L4 has an error on
        // line 4" is a successful answer to the request, not a server fault.
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ funcs, diagnostics }));
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
  // isFile(), not existsSync() — `resolve` strips trailing slashes, so the old
  // `!f.endsWith("/")` guard tested the STRING and happily matched a directory, and
  // `readFileSync` on a directory throws EISDIR from inside the request handler, which
  // took the whole dev server down. One stray URL should not end the session.
  const file = candidates.find((f) => {
    try {
      return statSync(f).isFile();
    } catch {
      return false;
    }
  });
  if (file) {
    res.writeHead(200, { "content-type": MIME[extname(file)] || "text/plain" });
    res.end(readFileSync(file));
  } else {
    res.writeHead(404).end("not found");
  }
});

// Belt and braces: a dev server that dies on one bad request costs more than the bug it
// dies on. Log and carry on.
server.on("clientError", (_e, socket) => socket.destroy());
process.on("uncaughtException", (e) =>
  console.error("[playground] uncaught (continuing):", e),
);

process.on("SIGINT", () => (lspChild?.kill(), process.exit(0)));
process.on("exit", () => lspChild?.kill());

await ensureLsp();
await connectLsp();
await initLsp();
server.listen(HTTP_PORT, () =>
  console.log(`[playground] ready → http://localhost:${HTTP_PORT}`),
);
