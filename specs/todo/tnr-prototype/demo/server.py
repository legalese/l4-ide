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
import re
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
# Hierarchical segmentation: align edited TNR to the original by anchor
# (spec §3.2 — anchors, not positions, are identity)
# ---------------------------------------------------------------------------

ANCHOR_RE = re.compile(r"^<!-- l4: (.+?) -->$")


def segment_tnr(md: str):
    """Split a TNR document into (key, text) segments. A segment starts at
    an anchor comment or a #-heading and runs to the next one. Text before
    the first key gets key None."""
    segs, cur_key, cur_lines = [], None, []

    def flush():
        nonlocal cur_key, cur_lines
        if cur_lines or cur_key is not None:
            segs.append((cur_key, "\n".join(cur_lines).strip()))
        cur_key, cur_lines = None, []

    for line in md.splitlines():
        m = ANCHOR_RE.match(line.strip())
        if m:
            flush()
            cur_key = m.group(1)
            cur_lines = [line]
        elif line.startswith("#"):
            flush()
            cur_key = "heading:" + line.lstrip("# ").strip()
            cur_lines = [line]
        else:
            cur_lines.append(line)
    flush()
    return segs


def changed_segments(old_md: str, new_md: str):
    """Per-segment diff. Returns a list of {anchor, before, after} when the
    two documents share the same anchor skeleton; None when the skeleton
    itself changed (segment added/removed/reordered) — callers fall back to
    full-document ingestion (the Class C-ish path)."""
    old, new = segment_tnr(old_md), segment_tnr(new_md)
    if [k for k, _ in old] != [k for k, _ in new]:
        return None
    return [
        {"anchor": k or "(preamble)", "before": a, "after": b}
        for (k, a), (_, b) in zip(old, new)
        if a != b
    ]


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

SCOPED_PROMPT = """\
You are the round-trip ingestion engine for L4, a typed functional language \
for law. The L4 module below is the MODEL — the single source of truth. A \
legislative text (TNR) was deterministically rendered from it; a human \
edited that rendering. The edits have been isolated to the specific \
sections listed below; every other section is byte-identical and its \
rendering must remain unchanged.

Update the L4 source so its rendering reflects exactly these edits.

Rules:
- MINIMAL DIFF. Touch only what the listed edits require. L4 is \
layout-sensitive: keep the indentation of unchanged regions byte-identical.
- Wording-only edits: rename the relevant backtick-quoted atom consistently \
at EVERY occurrence in the file (ASSUME and all uses) — a rename is global \
even though the edit is local. Note the renderer elides the shared subject \
of conditions and rewrites "the X must not VP" as "No X may VP who—", so \
condition text usually maps to an atom with the subject restored.
- Semantic edits (conditions added/removed/restructured, AND/OR changes, \
numbers, thresholds, deadlines): change the logic minimally to match.
- Comments are frozen: never edit text inside {{- -}} or after --, even \
when it quotes wording the human changed elsewhere.
- Never delete #EVAL/#CHECK directives.

<l4-source>
{l4}
</l4-source>

<edited-sections>
{sections}
</edited-sections>
{feedback}
Output ONLY the complete updated L4 source file. No code fences, no \
commentary, no explanation."""

SECTION_TMPL = """<section anchor="{anchor}">
<before>
{before}
</before>
<after>
{after}
</after>
</section>"""

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


def build_prompt(l4: str, tnr: str, edited: str, changes, feedback: str) -> str:
    """Scoped prompt when the anchor skeleton is intact; full-document
    prompt otherwise."""
    if changes:
        sections = "\n\n".join(
            SECTION_TMPL.format(**c) for c in changes)
        return SCOPED_PROMPT.format(l4=l4, sections=sections,
                                    feedback=feedback)
    return INGEST_PROMPT.format(l4=l4, tnr=tnr, edited=edited,
                                feedback=feedback)


def llm_propose(prompt: str) -> str:
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

    # hierarchical alignment: which anchored sections actually changed?
    changes = changed_segments(original_tnr, edited_tnr)
    if changes is not None and not changes:
        return {"ok": True, "l4": original_l4, "tnr": original_tnr,
                "attempts": 0, "diagnostics": "",
                "log": ["no sections changed; nothing to ingest "
                        "(0 LLM calls)"]}
    if changes is None:
        log.append("anchor skeleton changed (section added/removed); "
                   "falling back to full-document ingestion")
    else:
        log.append(f"{len(changes)} section(s) changed: "
                   + ", ".join(c["anchor"] for c in changes))

    feedback = ""
    proposal = ""
    diagnostics = ""
    tmp = wp.with_suffix(".proposed.l4")
    for attempt in range(1, MAX_ATTEMPTS + 1):
        log.append(f"attempt {attempt}: interpreting edit (GPU: {MODEL})…")
        proposal = llm_propose(
            build_prompt(original_l4, original_tnr, edited_tnr,
                         changes, feedback))
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
# Akoma Ntoso (LegalDocML) export — prototype
#
# Transforms the canonical TNR markdown (which is the Block IR, serialized)
# into AKN 3.0 XML. Hack-grade: the production exporter belongs in Haskell
# as a sibling backend of the Markdown renderer (same Block IR). Round-trip
# anchors ride in @GUID; eIds follow AKN naming (sec_1, sec_1__para_a).
# ---------------------------------------------------------------------------

AKN_NS = "http://docs.oasis-open.org/legaldocml/ns/akn/3.0"


def xesc(t: str) -> str:
    return (t.replace("&", "&amp;").replace("<", "&lt;")
             .replace(">", "&gt;").replace('"', "&quot;"))


def md_to_akn(md: str, name: str) -> str:
    blocks = [b for b in re.split(r"\n\n+", md) if b.strip()]
    title = name
    out = []
    sec_open = False          # a <section> provision is open
    pending_anchor = None
    pending_heading = None
    sec_no = 0
    # stack of (tab_depth, element_name) currently open inside the section
    tab_stack = []
    # heading-group nesting: stack of heading levels with open hcontainers
    grp_stack = []
    grp_no = 0

    def close_tabs(to_depth=-1):
        while tab_stack and tab_stack[-1][0] >= to_depth + 1:
            _, el = tab_stack.pop()
            out.append(f"{'  ' * (len(tab_stack) + 3)}</{el}>")

    def close_section():
        nonlocal sec_open
        close_tabs(-1)
        if sec_open:
            out.append("      </section>")
            sec_open = False

    def close_groups(to_level):
        while grp_stack and grp_stack[-1] >= to_level:
            grp_stack.pop()
            out.append("      " + "</hcontainer>")

    marker_el = ["paragraph", "subparagraph", "point", "point"]

    for block in blocks:
        b = block.strip()
        m_anchor = re.match(r"^<!-- l4: (.+?) -->$", b)
        m_cover = re.match(r"^<!-- tnr-coverage: (.*) -->$", b)
        m_head = re.match(r"^(#+) (.*)$", b, re.S)
        if m_anchor:
            pending_anchor = m_anchor.group(1)
            continue
        if m_cover:
            close_section()
            close_groups(0)
            out.append(f"      <!-- tnr-coverage: {xesc(m_cover.group(1))} -->")
            continue
        if m_head:
            close_section()
            lvl, text = len(m_head.group(1)), m_head.group(2).strip()
            if lvl == 1:
                title = text
                continue
            close_groups(lvl)
            grp_no += 1
            grp_stack.append(lvl)
            out.append(f'      <hcontainer name="group" eId="grp_{grp_no}">')
            out.append(f"        <heading>{xesc(text)}</heading>")
            continue

        indent = len(block) - len(block.lstrip(" "))
        depth = min(indent // 4 - 1, 3) if indent >= 4 else -1

        if depth < 0:
            # provision lead (or marginal-note heading line)
            close_section()
            m_note = re.match(r"^\*\*(\d+)\. (.*)\*\*$", b)
            m_lead = re.match(r"^\*\*(\d+)\.\*\* (.*)$", b, re.S)
            if m_note:
                sec_no = int(m_note.group(1))
                pending_heading = m_note.group(2)
                continue
            if m_lead:
                sec_no = int(m_lead.group(1))
                lead = m_lead.group(2)
            else:
                lead = b      # trailing paragraph (e.g. WHERE definitions)
                if sec_open:
                    out.append(f"        <wrapUp><p>{xesc(lead)}</p></wrapUp>")
                    continue
            guid = f' GUID="{xesc(pending_anchor)}"' if pending_anchor else ""
            pending_anchor = None
            out.append(f'      <section eId="sec_{sec_no}"{guid}>')
            out.append(f"        <num>{sec_no}.</num>")
            if pending_heading:
                out.append(f"        <heading>{xesc(pending_heading)}</heading>")
                pending_heading = None
            tag = "intro" if lead.rstrip().endswith("—") else "content"
            out.append(f"        <{tag}><p>{xesc(lead)}</p></{tag}>")
            sec_open = True
            tab_stack.clear()
        else:
            # tabulated item at `depth`
            m_item = re.match(r"^\(([a-z0-9ivxA-Z]+)\) (.*)$", b, re.S)
            num, text = (m_item.group(1), m_item.group(2)) if m_item else ("", b)
            close_tabs(depth)
            el = marker_el[min(depth, 3)]
            pad = "  " * (len(tab_stack) + 4)
            eid = f"sec_{sec_no}__{el[:4]}_{num or 'x'}"
            out.append(f'{pad}<{el} eId="{eid}">')
            out.append(f"{pad}  <num>({num})</num>" if num else "")
            if text.rstrip().endswith("—"):
                out.append(f"{pad}  <intro><p>{xesc(text)}</p></intro>")
                tab_stack.append((depth, el))   # children follow inside
            else:
                out.append(f"{pad}  <content><p>{xesc(text)}</p></content>")
                out.append(f"{pad}</{el}>")

    close_section()
    close_groups(0)
    body = "\n".join(l for l in out if l)

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<akomaNtoso xmlns="{AKN_NS}">
  <act name="{xesc(name)}">
    <meta>
      <identification source="#jl4-tnr">
        <FRBRWork>
          <FRBRthis value="/akn/xx/act/{xesc(name)}/main"/>
          <FRBRuri value="/akn/xx/act/{xesc(name)}"/>
          <FRBRauthor href="#jl4-tnr"/>
          <FRBRcountry value="xx"/>
        </FRBRWork>
        <FRBRExpression>
          <FRBRthis value="/akn/xx/act/{xesc(name)}/eng@/main"/>
          <FRBRuri value="/akn/xx/act/{xesc(name)}/eng@"/>
          <FRBRlanguage language="eng"/>
        </FRBRExpression>
        <FRBRManifestation>
          <FRBRthis value="/akn/xx/act/{xesc(name)}/eng@/main.xml"/>
          <FRBRuri value="/akn/xx/act/{xesc(name)}/eng@.xml"/>
        </FRBRManifestation>
      </identification>
    </meta>
    <preface>
      <longTitle><p>{xesc(title)}</p></longTitle>
    </preface>
    <body>
{body}
    </body>
  </act>
</akomaNtoso>
"""


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
            if self.path.startswith("/api/akn"):
                from urllib.parse import urlparse, parse_qs
                name = parse_qs(urlparse(self.path).query)["name"][0]
                wp = work_path(name)
                xml = md_to_akn(render_tnr(wp), name).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/xml; charset=utf-8")
                self.send_header("Content-Length", str(len(xml)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(xml)
                return None
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
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
