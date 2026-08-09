// A CLOSED markdown subset, rendered to HTML with no dependency.
//
// Written for etc/go/report/render-explainer.mjs and used only by it.
// render-report.mjs does not import this and is not modified by its existence:
// the audit report's HTML is a <pre> wrapper and stays one.
//
// WHY A CLOSED SUBSET WITH A REFUSING LINT, rather than a tolerant renderer.
// Markdown degrades silently: an unrecognised construct becomes paragraph text
// and a sentence quietly changes meaning. In a document about a regulation a
// silently mangled sentence is the worst available failure, so the constructs
// this renderer cannot carry are REJECTED at file:line by lintMarkdown()
// rather than mangled by mdToHtml().
//
// WHY NOT A DEPENDENCY. There is no markdown engine in any of this repo's
// package.json files, and adding the project's first one in order to publish a
// document is a large change disguised as a small one.
//
// THE SUBSET
//   blocks   ATX headings (levels one to four) · paragraphs · unordered and
//            ordered lists · GFM pipe tables · fenced code · block quotes ·
//            horizontal rules · a raw-block sentinel (see `raw` below)
//   inline   **strong** · _emphasis_ · `code` · [text](scheme:target "title")
//
// REJECTED, each with its own lint code: reference-link definitions, setext
// headings, HTML comments, images, footnotes, nested block quotes, headings
// below level four, and any raw HTML tag outside the whitelist.
//
// ESCAPING. escapeText() is the three-replacement escaper render-report.mjs
// uses; escapeAttr() ADDS the quote characters. That distinction is the whole
// reason both exist: this renderer puts text into attributes (title=, href=,
// class=), and the three-replacement version in an attribute context is an
// injection bug.

/** HTML text-node escaping. Not safe for attributes — use escapeAttr there. */
export const escapeText = (s) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");

/** HTML attribute escaping: everything escapeText does, plus both quotes. */
export const escapeAttr = (s) =>
  escapeText(s).replace(/"/g, "&quot;").replace(/'/g, "&#39;");

/** Raw block sentinel. A line consisting of exactly this is replaced verbatim. */
export const rawToken = (key) => `⟦RAW:${key}⟧`;
const RAW_LINE = /^⟦RAW:([A-Za-z0-9_.:-]+)⟧$/;

// Raw HTML the subset admits, as whole lines. Everything else starting with a
// tag is a lint error: the explainer's figures arrive through the raw sentinel,
// which is a renderer decision, not something a narrative file can reach.
const HTML_WHITELIST =
  /^<\/?(?:figure|figcaption)>$|^<figure(?: class="[a-z-]+")?>$|^<div class="[a-z-]+">$|^<\/div>$/;

/** Link schemes the subset admits. `src:`/`art:` are checked by narrative.mjs. */
const LINK_SCHEME = /^(?:src:|art:|https:\/\/|#)/;

// --------------------------------------------------------------------- lint

/**
 * Lint one markdown document against the subset.
 * Returns [{ line, code, message }]; empty means it renders without loss.
 */
export function lintMarkdown(text) {
  const out = [];
  const lines = String(text).split("\n");
  let inFence = false;
  lines.forEach((line, i) => {
    const n = i + 1;
    const prev = i > 0 ? lines[i - 1] : "";
    if (/^```/.test(line)) {
      inFence = !inFence;
      return;
    }
    if (inFence) return;
    if (RAW_LINE.test(line)) return;
    if (/^\[[^\]]+\]:\s/.test(line))
      out.push({
        line: n,
        code: "MD-REFLINK",
        message:
          "reference-link definition; write the link inline so its target travels with the sentence",
      });
    if (/^=+\s*$/.test(line) || (/^-{3,}\s*$/.test(line) && prev.trim() !== ""))
      out.push({
        line: n,
        code: "MD-SETEXT",
        message:
          "setext heading (a rule directly under text); use an ATX heading, and leave a blank line before a horizontal rule",
      });
    if (line.includes("<!--"))
      out.push({
        line: n,
        code: "MD-COMMENT",
        message:
          "HTML comment; a claim that is not rendered is a claim nobody re-reads",
      });
    if (/!\[/.test(line))
      out.push({
        line: n,
        code: "MD-IMAGE",
        message:
          "image; figures are emitted by the renderer from an attested artifact, not referenced from prose",
      });
    if (/\[\^/.test(line))
      out.push({ line: n, code: "MD-FOOTNOTE", message: "footnote" });
    if (/^>\s*>/.test(line))
      out.push({
        line: n,
        code: "MD-NESTEDQUOTE",
        message: "nested block quote",
      });
    if (/^#{5,}\s/.test(line))
      out.push({
        line: n,
        code: "MD-HEADING-DEPTH",
        message: "heading below level four",
      });
    // Two adjacent backticks outside a fence. In the subset a code span is
    // delimited by ONE backtick, so `` is either a double-backtick span (which
    // this renderer does not carry) or a span that closed where the writer
    // meant it to keep going. Either way inline() mangles it silently rather
    // than failing: MEASURED on a rendered explainer, where a narrative line
    // reading `"(1)" ... transfer's `to the issuer of the securities`` drew as
    // an unstyled sentence with a bare pair of backticks trailing it.
    if (/``/.test(line))
      out.push({
        line: n,
        code: "MD-BACKTICK",
        message:
          "two adjacent backticks; a code span in this subset takes one backtick and cannot nest, so quote the excerpt in a fenced block instead",
      });
    if (/^\s*<[a-zA-Z/]/.test(line) && !HTML_WHITELIST.test(line.trim()))
      out.push({
        line: n,
        code: "MD-HTML",
        message: `raw HTML outside the whitelist: ${line.trim().slice(0, 60)}`,
      });
    for (const m of line.matchAll(/\[[^\]]*\]\(([^)\s]+)/g)) {
      if (!LINK_SCHEME.test(m[1]))
        out.push({
          line: n,
          code: "MD-LINKSCHEME",
          message: `link target '${m[1]}' uses no admitted scheme (src:, art:, https://, #)`,
        });
    }
  });
  if (inFence)
    out.push({
      line: lines.length,
      code: "MD-FENCE",
      message: "unclosed fenced code block",
    });
  return out;
}

// ------------------------------------------------------------------- inline

/**
 * Inline rendering. Code spans and links are lifted out FIRST so that escaping
 * cannot corrupt a URL and emphasis cannot fire inside a code span; the rest is
 * escaped as a text node and only then given emphasis.
 *
 * HOLDS NEST, SO THE RESTORE MUST ITERATE. A link whose text is a code span —
 * [`report.md`](report.md), which is exactly how this renderer writes the
 * pointer to the audit report — holds the code span first and then holds the
 * whole anchor, whose body still carries the inner sentinel. A single-pass
 * restore therefore emitted an anchor whose text was two NUL bytes around a
 * stray digit: a browser draws that as the bare character `0`, and it made the
 * whole file read as binary to grep. MEASURED in the explainer of run
 * 2026-08-03-3f45e62b-002, before this loop existed. Restoring to a FIXED POINT
 * is what makes the nesting safe, and it terminates because a held entry can
 * only refer to holds taken before it.
 */
function inline(src) {
  const held = [];
  const hold = (html) => {
    held.push(html);
    return `\u0000${held.length - 1}\u0000`;
  };
  let s = String(src ?? "");
  s = s.replace(/`([^`]+)`/g, (_, code) =>
    hold(`<code>${escapeText(code)}</code>`),
  );
  s = s.replace(
    /\[([^\]]+)\]\(([^)\s]+)(?:\s+"([^"]*)")?\)/g,
    (_, text, href, title) =>
      hold(
        `<a href="${escapeAttr(href)}"${title ? ` title="${escapeAttr(title)}"` : ""}>${escapeText(text)}</a>`,
      ),
  );
  s = escapeText(s);
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/(^|[\s(])_([^_]+)_(?=$|[\s).,;:!?])/g, "$1<em>$2</em>");
  for (let pass = 0; pass <= held.length && /\u0000\d+\u0000/.test(s); pass++)
    s = s.replace(/\u0000(\d+)\u0000/g, (_, i) => held[Number(i)] ?? "");
  return s;
}

const cells = (row) =>
  row
    .replace(/^\|/, "")
    .replace(/\|\s*$/, "")
    .split(/(?<!\\)\|/)
    .map((c) => c.replace(/\\\|/g, "|").trim());

// ------------------------------------------------------------------- render

/**
 * Render the subset to HTML.
 *
 * `raw` maps a sentinel key to a string emitted VERBATIM — the only route by
 * which unescaped HTML reaches the output, and it is the renderer's, never a
 * narrative file's. A sentinel with no entry renders as a visible marker rather
 * than silently vanishing.
 */
export function mdToHtml(text, { raw = {} } = {}) {
  const lines = String(text).split("\n");
  const out = [];
  let para = [];
  let quote = [];
  let list = null; // { tag, items: [ [lines] ] }
  const flushPara = () => {
    if (para.length) out.push(`<p>${inline(para.join(" "))}</p>`);
    para = [];
  };
  const flushQuote = () => {
    if (quote.length)
      out.push(`<blockquote><p>${inline(quote.join(" "))}</p></blockquote>`);
    quote = [];
  };
  const flushList = () => {
    if (list) {
      out.push(`<${list.tag}>`);
      for (const item of list.items)
        out.push(`<li>${inline(item.join(" "))}</li>`);
      out.push(`</${list.tag}>`);
    }
    list = null;
  };
  const flushAll = () => {
    flushPara();
    flushQuote();
    flushList();
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const t = line.trim();

    if (/^```/.test(t)) {
      flushAll();
      const body = [];
      i++;
      while (i < lines.length && !/^```/.test(lines[i].trim()))
        body.push(lines[i++]);
      out.push(`<pre><code>${escapeText(body.join("\n"))}</code></pre>`);
      continue;
    }
    const rawM = RAW_LINE.exec(t);
    if (rawM) {
      flushAll();
      out.push(
        rawM[1] in raw
          ? raw[rawM[1]]
          : `<p><strong>MISSING RAW BLOCK</strong> <code>${escapeText(rawM[1])}</code></p>`,
      );
      continue;
    }
    if (t === "") {
      flushAll();
      continue;
    }
    if (/^-{3,}$/.test(t)) {
      flushAll();
      out.push("<hr>");
      continue;
    }
    const h = /^(#{1,4})\s+(.*)$/.exec(t);
    if (h) {
      flushAll();
      out.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`);
      continue;
    }
    if (t.startsWith(">")) {
      flushPara();
      flushList();
      quote.push(t.replace(/^>\s?/, ""));
      continue;
    }
    // pipe table: a row whose successor is a delimiter row
    if (
      t.startsWith("|") &&
      /^\|[\s:|-]+\|$/.test((lines[i + 1] ?? "").trim())
    ) {
      flushAll();
      const head = cells(t);
      i += 2;
      const body = [];
      while (i < lines.length && lines[i].trim().startsWith("|"))
        body.push(cells(lines[i++].trim()));
      i--;
      out.push('<div class="scroll"><table>');
      // A header row whose every cell is empty is the markdown idiom for a
      // two-column key/value table with no headings — the explainer's own run
      // facts table is one. Emitting <thead><tr><th></th><th></th></tr> for it
      // draws a shaded empty band above the first real row. MEASURED on run
      // 2026-08-03-3f45e62b-004, where that band sat above the header table.
      if (head.some((c) => c.trim() !== "")) {
        out.push("<thead><tr>");
        for (const c of head) out.push(`<th>${inline(c)}</th>`);
        out.push("</tr></thead>");
      }
      out.push("<tbody>");
      for (const row of body) {
        out.push("<tr>");
        for (const c of row) out.push(`<td>${inline(c)}</td>`);
        out.push("</tr>");
      }
      out.push("</tbody></table></div>");
      continue;
    }
    const li = /^([-*]|\d+\.)\s+(.*)$/.exec(t);
    if (li) {
      flushPara();
      flushQuote();
      const tag = /^\d/.test(li[1]) ? "ol" : "ul";
      if (!list || list.tag !== tag) {
        flushList();
        list = { tag, items: [] };
      }
      list.items.push([li[2]]);
      continue;
    }
    if (list && /^\s+\S/.test(line)) {
      list.items[list.items.length - 1].push(t);
      continue;
    }
    if (HTML_WHITELIST.test(t)) {
      flushAll();
      out.push(t);
      continue;
    }
    flushQuote();
    flushList();
    para.push(t);
  }
  flushAll();
  return out.join("\n");
}
