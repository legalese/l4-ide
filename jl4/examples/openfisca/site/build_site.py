#!/usr/bin/env python3
"""Build a self-contained index.html for the L4 -> OpenFisca bridge.

Captures everything LIVE so the site can't drift from the code:
  * reads each example's .l4 source,
  * runs `l4 openfisca` to emit the OpenFisca Python,
  * runs roundtrip_check.py to capture the validating output numbers,
  * renders L4-OPENFISCA.md to HTML.

Usage:  python build_site.py <path-to-l4-binary>
"""
import html
import pathlib
import subprocess
import sys

import markdown

HERE = pathlib.Path(__file__).resolve().parent     # .../openfisca/site
EXDIR = HERE.parent                                 # .../openfisca
L4BIN = sys.argv[1]
PYBIN = sys.executable                              # the venv python running this

EXAMPLES = [
    ("flat-tax",  "Flat tax on salary",
     "The OpenFisca textbook example: one scalar variable, one formula."),
    ("benefit",   "Means-tested benefit",
     "Comparisons, Booleans, IF/THEN/ELSE, and one decision calling another."),
    ("household", "Household — group entity + aggregation",
     "A LIST OF Person makes a group entity; sum (map ...) aggregates over members."),
    ("scale", "Marginal-rate scale + parameter store",
     "A @desc scale value + scale tax → an OpenFisca ParameterNode and scale.calc; "
     "verified on openfisca-core AND policyengine-core (Phase 1)."),
    ("roles", "Roles + count / any / all",
     "adults/children roles, with count -> nb_persons, role-restricted sum, "
     "and any/all over members."),
    ("housing", "Enums + CONSIDER",
     "DECLARE … IS ONE OF -> an OpenFisca Enum; CONSIDER -> nested np.where on "
     "enum equality; max -> np.maximum."),
    ("dated", "Dated formulas",
     "BRANCH IF period reaches Y, M -> OpenFisca formula_YYYY_MM methods; the "
     "engine selects by period."),
    ("agecheck", "Member decision-calls",
     "age OF c, period inside any -> household.members('age', period); the called "
     "decision compiles as a Person variable; period's year -> period.start.year."),
    ("incometax", "Scalar parameter store",
     "@desc parameter <path> with a time-varying rate -> an OpenFisca scalar "
     "parameter; rate OF period's year -> parameters(period).<path>."),
]


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def emit_py(name):
    return run([L4BIN, "openfisca", str(EXDIR / f"{name}.l4")]).stdout


def roundtrip(name, py_text):
    tmp = HERE / f"_gen_{name}.py"
    tmp.write_text(py_text)
    r = run([PYBIN, str(EXDIR / "roundtrip_check.py"), str(tmp), name])
    tmp.unlink(missing_ok=True)
    return (r.stdout + r.stderr).strip()


def code_block(text, lang):
    # language-l4 / language-python get Highlight.js coloring; output stays plain.
    cls = {"l4": "language-l4", "python": "language-python"}.get(lang, "nohighlight")
    return (f'<pre class="code {lang}"><code class="{cls}">'
            + html.escape(text.rstrip("\n")) + "</code></pre>")


def example_section(name, title, blurb):
    l4_src = (EXDIR / f"{name}.l4").read_text()
    py_src = emit_py(name)
    out = roundtrip(name, py_src)
    return f"""
<section id="{name}" class="example">
  <h2>{html.escape(title)}</h2>
  <p class="blurb">{html.escape(blurb)} <span class="file">{name}.l4</span></p>
  <div class="cols">
    <div class="col">
      <div class="col-head">L4 source <span class="tag readable">human-reviewable</span></div>
      {code_block(l4_src, "l4")}
    </div>
    <div class="col">
      <div class="col-head">Generated OpenFisca <span class="tag generated">compiled artifact</span></div>
      {code_block(py_src, "python")}
    </div>
  </div>
  <div class="testrun">
    <div class="testrun-head">Round-trip in real OpenFisca — numbers must match the L4 <code>#EVAL</code></div>
    {code_block(out, "output")}
  </div>
</section>
"""


def main():
    # The page hero already shows the title + tagline, so drop the markdown's
    # own leading H1 and bold tagline to avoid showing them twice.
    md_text = (EXDIR / "L4-OPENFISCA.md").read_text()
    blocks = md_text.split("\n\n")
    if blocks and blocks[0].lstrip().startswith("# "):
        drop = 2 if len(blocks) > 1 and blocks[1].lstrip().startswith("**") else 1
        md_text = "\n\n".join(blocks[drop:])
    md_html = markdown.markdown(
        md_text, extensions=["tables", "fenced_code", "toc"],
    )

    nav = "".join(
        f'<a href="#{name}">{html.escape(title)}</a>'
        for name, title, _ in EXAMPLES
    )
    sections = "".join(example_section(*e) for e in EXAMPLES)

    out_html = TEMPLATE.format(nav=nav, overview=md_html, sections=sections)
    (HERE / "index.html").write_text(out_html)
    print("wrote", HERE / "index.html")


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>L4 → OpenFisca</title>
<link rel="stylesheet" href="vendor/hljs-github-dark.css">
<style>
  :root {{
    --ink:#14181f; --muted:#5b6675; --line:#e4e8ee; --bg:#fbfcfe;
    --l4:#0b5; --of:#2563eb; --accent:#7c3aed; --code-bg:#0f1722; --code-fg:#dbe4f0;
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
    font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif; }}
  a {{ color:var(--of); text-decoration:none; }}
  a:hover {{ text-decoration:underline; }}
  .wrap {{ display:grid; grid-template-columns:240px minmax(0,1fr); gap:0; }}
  aside {{ position:sticky; top:0; align-self:start; height:100vh; overflow:auto;
    border-right:1px solid var(--line); padding:24px 18px; background:#fff; }}
  aside .brand {{ font-weight:700; font-size:18px; letter-spacing:-.01em; }}
  aside .brand small {{ display:block; color:var(--muted); font-weight:500; font-size:12px; margin-top:2px; }}
  aside nav {{ margin-top:22px; display:flex; flex-direction:column; gap:2px; }}
  aside nav a {{ color:var(--ink); padding:7px 10px; border-radius:7px; font-size:14px; }}
  aside nav a:hover {{ background:#f1f4f9; text-decoration:none; }}
  aside .seclabel {{ text-transform:uppercase; letter-spacing:.08em; font-size:11px;
    color:var(--muted); margin:18px 10px 6px; }}
  main {{ padding:40px 48px 120px; max-width:1100px; }}
  h1 {{ font-size:30px; letter-spacing:-.02em; margin:0 0 6px; }}
  .lede {{ color:var(--muted); font-size:17px; margin:0 0 30px; max-width:70ch; }}
  h2 {{ font-size:22px; letter-spacing:-.01em; margin:38px 0 8px; }}
  h3 {{ font-size:17px; margin:26px 0 6px; }}
  .overview {{ border-bottom:1px solid var(--line); padding-bottom:24px; margin-bottom:10px; }}
  .overview table {{ border-collapse:collapse; width:100%; margin:14px 0; font-size:14px; }}
  .overview th, .overview td {{ border:1px solid var(--line); padding:7px 10px; text-align:left; vertical-align:top; }}
  .overview th {{ background:#f4f7fb; }}
  .overview code {{ background:#eef2f7; padding:1px 5px; border-radius:4px; font-size:13px; }}
  .overview pre {{ background:var(--code-bg); color:var(--code-fg); padding:14px 16px;
    border-radius:10px; overflow:auto; }}
  .overview pre code {{ background:none; padding:0; color:inherit; }}
  .example {{ padding:14px 0 6px; border-bottom:1px solid var(--line); }}
  .blurb {{ color:var(--muted); margin:0 0 14px; }}
  .file {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:12px;
    background:#eef2f7; padding:2px 7px; border-radius:5px; color:#334; margin-left:6px; }}
  .cols {{ display:grid; grid-template-columns:1fr 1fr; gap:16px; }}
  @media (max-width:900px) {{ .cols {{ grid-template-columns:1fr; }} .wrap {{ grid-template-columns:1fr; }} aside {{ position:static; height:auto; }} }}
  .col-head {{ font-size:13px; font-weight:600; margin-bottom:6px; display:flex; align-items:center; gap:8px; }}
  .tag {{ font-size:10.5px; font-weight:600; text-transform:uppercase; letter-spacing:.04em;
    padding:2px 7px; border-radius:20px; }}
  .tag.readable {{ background:#e7f8ef; color:#067a45; }}
  .tag.generated {{ background:#e8effe; color:#1d4ed8; }}
  pre.code {{ background:var(--code-bg); color:var(--code-fg); margin:0; padding:14px 16px;
    border-radius:10px; overflow:auto; font:13px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace; }}
  pre.code.l4 {{ border-left:3px solid var(--l4); }}
  pre.code.python {{ border-left:3px solid var(--of); }}
  .testrun {{ margin:16px 0 8px; }}
  .testrun-head {{ font-size:13px; font-weight:600; margin-bottom:6px; }}
  .testrun-head code {{ background:#eef2f7; padding:1px 5px; border-radius:4px; }}
  pre.code.output {{ background:#0c1f17; color:#b8f5d2; border-left:3px solid var(--l4); }}
  footer {{ color:var(--muted); font-size:13px; padding:30px 0 0; }}
  /* Highlight.js colors the tokens; keep our panel background + accent borders. */
  pre.code code.hljs {{ background:transparent; padding:0; }}
  .overview pre code.hljs {{ background:transparent; padding:0; }}
</style>
</head>
<body>
<div class="wrap">
  <aside>
    <div class="brand">L4 → OpenFisca<small>computational-law bridge</small></div>
    <nav>
      <a href="#overview">Overview</a>
      <div class="seclabel">Worked examples</div>
      {nav}
    </nav>
  </aside>
  <main>
    <h1>From legislation to OpenFisca, via L4</h1>
    <p class="lede">A readable, type-checked source layer that compiles to OpenFisca —
      so the policy owner can validate the rules by eye, and the engine still runs in OpenFisca.</p>
    <div id="overview" class="overview">{overview}</div>
    {sections}
    <footer>Generated by <code>build_site.py</code> — L4 source, OpenFisca output, and
      test numbers are all captured live from the bridge.</footer>
  </main>
</div>
<script src="vendor/highlight.min.js"></script>
<script src="vendor/l4.min.js"></script>
<script>
  hljs.configure({{cssSelector:'pre code.language-l4, pre code.language-python'}});
  hljs.highlightAll();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
