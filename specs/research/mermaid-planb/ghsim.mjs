// Faithful replay of GitHub's mermaid pipeline:
//   mermaid 11.16.0 (verified same version+registry as GitHub's viewscreen bundle)
//   + GitHub's exact initialize() options (scraped from mermaidMarkdown-a1eea15e....js)
//   + GitHub's exact DOMPurify ALLOWED_TAGS / ADD_ATTR
import { readFileSync, writeFileSync } from "node:fs";
import puppeteer from "puppeteer";

const ALLOWED_TAGS = JSON.parse(readFileSync("gh-allowed-tags.json", "utf8"));
const src = readFileSync(process.argv[2], "utf8");
const out = process.argv[3];

const mermaidJs = readFileSync(
  "node_modules/mermaid/dist/mermaid.min.js",
  "utf8",
);
const purifyJs = readFileSync(
  "node_modules/dompurify/dist/purify.min.js",
  "utf8",
);

const browser = await puppeteer.launch({ headless: "new" });
const page = await browser.newPage();
await page.setViewport({ width: 1600, height: 700, deviceScaleFactor: 2 });
await page.setContent(`<!doctype html><html><head><style>/* GitHub viewscreen CSS, verbatim */\n#mermaid-view-template{display:block;border:1px solid #d1d9e0;min-width:1600px}</style></head><body style="margin:0;background:#fff">
<div id="host"></div><template id="mermaid-view-template"></template>
<script>${purifyJs}</script><script>${mermaidJs}</script></body></html>`);

const res = await page.evaluate(
  async (src, ALLOWED_TAGS) => {
    // ---- GitHub's exact initialize() call ----
    mermaid.initialize({
      startOnLoad: false,
      secure: ["secure", "securityLevel", "startOnLoad", "maxTextSize"],
      securityLevel: "antiscript",
      flowchart: { diagramPadding: 48 },
      gantt: { useWidth: 1200 },
      pie: { useWidth: 1200 },
      sequence: { diagramMarginY: 40 },
      theme: "default",
    });
    let svg;
    try {
      ({ svg } = await mermaid.render(
        "diagram",
        src,
        document.getElementById("mermaid-view-template"),
      ));
    } catch (e) {
      return { error: String((e && e.message) || e) };
    }
    const rawLen = svg.length;
    // ---- GitHub's exact DOMPurify call ----
    const frag = DOMPurify.sanitize(svg, {
      RETURN_DOM_FRAGMENT: true,
      HTML_INTEGRATION_POINTS: { foreignobject: true },
      ALLOWED_TAGS,
      ADD_ATTR: ["transform-origin", "dominant-baseline"],
    });
    const el = frag.querySelector("svg");
    if (!el) return { error: "sanitizer removed the whole svg" };
    document.getElementById("host").appendChild(el);
    el.removeAttribute("width");
    el.style.width = "1500px";
    el.style.height = "auto";
    const styleKept = !!el.querySelector("style");
    const cssLen = styleKept ? el.querySelector("style").textContent.length : 0;
    return {
      rawLen,
      sanitizedLen: el.outerHTML.length,
      styleKept,
      cssLen,
      removed: DOMPurify.removed.map(
        (r) => r.element?.nodeName || r.attribute?.name,
      ),
    };
  },
  src,
  ALLOWED_TAGS,
);

if (res.error) {
  console.log("RENDER ERROR:", res.error);
  await browser.close();
  process.exit(1);
}
console.log(JSON.stringify(res, null, 1));
const host = await page.$("#host");
await host.screenshot({ path: out });
console.log("screenshot ->", out);
await browser.close();
