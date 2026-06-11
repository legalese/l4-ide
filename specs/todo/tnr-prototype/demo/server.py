#!/usr/bin/env python3
"""Round-trip demo server for the TNR prototype.

Serves the two-pane demo (static files) plus a small API implementing the
spec's round-trip ingestion loop (specs/todo/NLG-TNR-ROUNDTRIP-SPEC.md §3,
§6): the human edits the TNR; an LLM (via `claude -p`) proposes an updated
L4 source; the proposal is GATED by the deterministic toolchain (`l4 check`
typecheck, with retry-on-diagnostics); on success the canonical TNR is
re-rendered with `l4 tnr`. The GPU drafts; the CPU verifies.

Endpoints
  GET  /api/instruments          -> {"instruments": [name, ...]}
  GET  /api/load?name=N          -> {"name", "l4", "tnr"}
  POST /api/reset   {"name"}     -> discard working copy, reload original
  POST /api/ingest  {"name", "tnr"} -> run the loop; returns
       {"ok", "l4", "tnr", "attempts", "log": [...], "diagnostics"}

Working copies live in work/ (gitignored); originals in data/ are never
touched. Zero third-party dependencies. Run from anywhere:

    L4_BIN=$(cabal list-bin exe:l4) python3 server.py [port]
"""

import json
import os
import shutil
import subprocess
import sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path

DEMO = Path(__file__).resolve().parent
DATA = DEMO / "data"
WORK = DEMO / "work"

L4_BIN = os.environ.get("L4_BIN", "l4")
CLAUDE_BIN = os.environ.get("CLAUDE_BIN") or shutil.which("claude") \
    or str(Path.home() / ".local/bin/claude")
MODEL = os.environ.get("TNR_MODEL", "claude-sonnet-4-6")
MAX_ATTEMPTS = 3
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8642

# ---------------------------------------------------------------------------
# Toolchain plumbing
# ---------------------------------------------------------------------------

def run(cmd, input_=None, timeout=240):
    p = subprocess.run(cmd, input=input_, capture_output=True, text=True,
                       timeout=timeout)
    return p.returncode, p.stdout, p.stderr


def instruments():
    """A data/*.l4 file is an instrument if it has at least one § heading;
    heading-less files are libraries (kept around for IMPORT resolution
    but not listed)."""
    out = []
    for p in sorted(DATA.glob("*.l4")):
        if "§" in p.read_text(encoding="utf-8"):
            out.append(p.stem)
    return out


def work_path(name: str) -> Path:
    if name not in instruments():           # also blocks path traversal
        raise ValueError(f"unknown instrument: {name}")
    WORK.mkdir(exist_ok=True)
    # libraries must sit next to working copies for IMPORT resolution
    inst = set(instruments())
    for lib in DATA.glob("*.l4"):
        if lib.stem not in inst and not (WORK / lib.name).exists():
            shutil.copy(lib, WORK / lib.name)
    w = WORK / f"{name}.l4"
    if not w.exists():
        shutil.copy(DATA / f"{name}.l4", w)
    return w


def render_tnr(path: Path) -> str:
    code, out, err = run([L4_BIN, "tnr", str(path)])
    if code != 0:
        raise RuntimeError(f"l4 tnr failed: {err or out}")
    return out


def check_l4(path: Path):
    code, out, err = run([L4_BIN, "check", str(path)])
    return code == 0, (err + "\n" + out).strip()

# ---------------------------------------------------------------------------
# The GPU half: LLM interpretation of the human's TNR edit
# ---------------------------------------------------------------------------

INGEST_PROMPT = """\
You are the round-trip ingestion engine for L4, a typed functional language \
for law. Below are three artifacts:

1. an L4 module (the MODEL — the single source of truth);
2. the legislative text (TNR) deterministically generated from it (a VIEW);
3. a human-edited version of that TNR.

Update the L4 source so that its deterministic rendering reflects the \
human's edits.

Rules:
- MINIMAL DIFF. Preserve the L4's structure, comments, layout and names \
wherever the edit does not touch them. L4 is layout-sensitive: keep the \
indentation of unchanged regions byte-identical.
- Wording-only edits (rephrasings that do not change the logic): rename the \
relevant backtick-quoted atom consistently at every occurrence (ASSUME and \
all uses). Note the renderer elides the shared subject of conditions and \
rewrites "the X must not VP" conclusions as "No X may VP who—", so an edit \
inside a condition usually maps to the atom text with the subject restored.
- Semantic edits (conditions added, removed or restructured; AND/OR changes; \
thresholds or deadlines changed): change the logic minimally to match.
- Never delete #EVAL/#CHECK directives or comments.
- If an edit is impossible to honour, keep the source unchanged for that \
fragment.

<l4-source>
{l4}
</l4-source>

<generated-tnr>
{tnr}
</generated-tnr>

<human-edited-tnr>
{edited}
</human-edited-tnr>
{feedback}
Output ONLY the complete updated L4 source file. No code fences, no \
commentary, no explanation."""

FEEDBACK_TMPL = """
Your previous attempt failed to typecheck. Previous attempt:

<previous-attempt>
{attempt}
</previous-attempt>

Compiler diagnostics:

<diagnostics>
{diagnostics}
</diagnostics>

Fix the problems and try again.
"""


def llm_propose(l4: str, tnr: str, edited: str, feedback: str) -> str:
    prompt = INGEST_PROMPT.format(l4=l4, tnr=tnr, edited=edited,
                                  feedback=feedback)
    code, out, err = run(
        [CLAUDE_BIN, "-p", "--output-format", "text", "--model", MODEL],
        input_=prompt)
    if code != 0:
        raise RuntimeError(f"claude -p failed: {err or out}")
    text = out.strip()
    # defensive: strip code fences if the model added them anyway
    if text.startswith("```"):
        lines = text.splitlines()
        if lines and lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)
    return text + "\n" if not text.endswith("\n") else text

# ---------------------------------------------------------------------------
# The loop: GPU drafts, CPU verifies
# ---------------------------------------------------------------------------

def ingest(name: str, edited_tnr: str) -> dict:
    wp = work_path(name)
    original_l4 = wp.read_text()
    original_tnr = render_tnr(wp)
    log = []

    feedback = ""
    proposal = ""
    diagnostics = ""
    tmp = wp.with_suffix(".proposed.l4")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        log.append(f"attempt {attempt}: interpreting edit (GPU: {MODEL})…")
        proposal = llm_propose(original_l4, original_tnr, edited_tnr, feedback)
        tmp.write_text(proposal)
        log.append(f"attempt {attempt}: validating (CPU: l4 check)…")
        ok, diagnostics = check_l4(tmp)
        if ok:
            wp.write_text(proposal)
            tmp.unlink(missing_ok=True)
            new_tnr = render_tnr(wp)
            log.append(f"attempt {attempt}: typecheck passed; re-rendered TNR.")
            return {"ok": True, "l4": proposal, "tnr": new_tnr,
                    "attempts": attempt, "log": log, "diagnostics": ""}
        log.append(f"attempt {attempt}: typecheck FAILED; feeding "
                   f"diagnostics back.")
        feedback = FEEDBACK_TMPL.format(attempt=proposal,
                                        diagnostics=diagnostics)

    tmp.unlink(missing_ok=True)
    return {"ok": False, "l4": original_l4, "tnr": original_tnr,
            "attempts": MAX_ATTEMPTS, "log": log,
            "diagnostics": diagnostics,
            "rejected": proposal}

# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(DEMO), **kw)

    def _json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self):
        # demo: never cache, so regenerated artifacts show immediately
        if self.command == "GET" and not self.path.startswith("/api/"):
            self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_GET(self):
        try:
            if self.path == "/api/instruments":
                return self._json({"instruments": instruments()})
            if self.path.startswith("/api/load"):
                from urllib.parse import urlparse, parse_qs
                name = parse_qs(urlparse(self.path).query)["name"][0]
                wp = work_path(name)
                return self._json({"name": name, "l4": wp.read_text(),
                                   "tnr": render_tnr(wp)})
            return super().do_GET()
        except Exception as e:  # noqa: BLE001 — demo server
            return self._json({"error": str(e)}, 500)

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > 2_000_000:
                return self._json({"error": "body too large"}, 413)
            body = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/api/reset":
                name = body["name"]
                if name not in instruments():
                    raise ValueError("unknown instrument")
                (WORK / f"{name}.l4").unlink(missing_ok=True)
                wp = work_path(name)
                return self._json({"name": name, "l4": wp.read_text(),
                                   "tnr": render_tnr(wp)})
            if self.path == "/api/ingest":
                return self._json(ingest(body["name"], body["tnr"]))
            return self._json({"error": "unknown endpoint"}, 404)
        except Exception as e:  # noqa: BLE001
            return self._json({"error": str(e)}, 500)

    def log_message(self, fmt, *args):
        sys.stderr.write("[tnr-demo] " + fmt % args + "\n")


if __name__ == "__main__":
    print(f"[tnr-demo] l4 = {L4_BIN}")
    print(f"[tnr-demo] claude = {CLAUDE_BIN} (model {MODEL})")
    print(f"[tnr-demo] instruments: {', '.join(instruments())}")
    print(f"[tnr-demo] http://localhost:{PORT}/")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
