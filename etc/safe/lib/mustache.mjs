// A mustache subset, dependency-free.
//
// SPEC.md §5.3 rules that the templates are derived from the publisher's verbatim
// Markdown and proven to reproduce it, which means the renderer must not transform
// anything it is not told to. So:
//
//   * NO HTML escaping. `{{x}}` and `{{{x}}}` are the same thing here — the output is
//     Markdown, and escaping `&` or `<` would silently modify the form. (Real mustache
//     escapes `{{x}}`; that difference is deliberate and is why this file exists.)
//   * The tag set is exactly what the templates need: interpolation, sections over
//     arrays or truthy values, inverted sections, comments. No partials, no lambdas,
//     no `{{=<% %>=}}` delimiter changes, no `{{&x}}`-only unescaping.
//
// SPEC.md §5.3 also says: if this grows past a screen, delete it and take the
// lockfile hit on a real mustache. It has not.

/** Split a dotted path, honouring `.` as "the current item". */
function lookup(stack, path) {
  if (path === ".") return stack[stack.length - 1];
  const parts = path.split(".");
  // Mustache resolves the FIRST segment against the context stack, innermost out,
  // then walks the rest of the path within whatever that produced.
  for (let i = stack.length - 1; i >= 0; i--) {
    const frame = stack[i];
    if (frame === null || typeof frame !== "object") continue;
    if (!(parts[0] in frame)) continue;
    let v = frame[parts[0]];
    for (let j = 1; j < parts.length && v != null; j++) v = v[parts[j]];
    return v;
  }
  return undefined;
}

/** Tokenize into {type, value} — text | name | open | inverted | close | comment. */
function tokenize(src) {
  const out = [];
  let i = 0;
  while (i < src.length) {
    const open = src.indexOf("{{", i);
    if (open < 0) {
      out.push({ type: "text", value: src.slice(i) });
      break;
    }
    if (open > i) out.push({ type: "text", value: src.slice(i, open) });
    const triple = src[open + 2] === "{";
    const close = src.indexOf(triple ? "}}}" : "}}", open + 2);
    if (close < 0) throw new Error(`mustache: unclosed tag at offset ${open}`);
    const body = src.slice(open + (triple ? 3 : 2), close).trim();
    i = close + (triple ? 3 : 2);
    if (triple) out.push({ type: "name", value: body });
    else if (body.startsWith("!")) out.push({ type: "comment", value: "" });
    else if (body.startsWith("#"))
      out.push({ type: "open", value: body.slice(1).trim() });
    else if (body.startsWith("^"))
      out.push({ type: "inverted", value: body.slice(1).trim() });
    else if (body.startsWith("/"))
      out.push({ type: "close", value: body.slice(1).trim() });
    else if (body.startsWith("&"))
      out.push({ type: "name", value: body.slice(1).trim() });
    else out.push({ type: "name", value: body });
  }
  return out;
}

/**
 * Drop the line a standalone section/inverted/close/comment tag sits on, the way
 * mustache does. Without this a `{{#safes}}` on its own line leaves a blank line in
 * the Markdown, which changes the rendered document. Interpolation tags are never
 * standalone — they stand for text that belongs in the line.
 */
function stripStandalone(toks) {
  const standalone = new Set(["open", "inverted", "close", "comment"]);
  for (let i = 0; i < toks.length; i++) {
    if (!standalone.has(toks[i].type)) continue;
    const before = toks[i - 1];
    const after = toks[i + 1];
    const beforeOk =
      i === 0 || (before.type === "text" && /(^|\n)[ \t]*$/.test(before.value));
    const afterOk =
      i === toks.length - 1 ||
      (after.type === "text" && /^[ \t]*(\r?\n|$)/.test(after.value));
    if (!beforeOk || !afterOk) continue;
    if (before && before.type === "text")
      before.value = before.value.replace(/[ \t]*$/, "");
    if (after && after.type === "text")
      after.value = after.value.replace(/^[ \t]*\r?\n/, "");
  }
  return toks;
}

/** Build a tree of {type, value, children}. */
function build(toks) {
  const root = { type: "root", children: [] };
  const stack = [root];
  for (const t of toks) {
    const top = stack[stack.length - 1];
    if (t.type === "open" || t.type === "inverted") {
      const node = { type: t.type, value: t.value, children: [] };
      top.children.push(node);
      stack.push(node);
    } else if (t.type === "close") {
      if (stack.length === 1)
        throw new Error(`mustache: {{/${t.value}}} closes nothing`);
      const node = stack.pop();
      if (node.value !== t.value)
        throw new Error(
          `mustache: {{/${t.value}}} closes {{#${node.value}}} — tags are not nested`,
        );
    } else if (t.type !== "comment") {
      top.children.push(t);
    }
  }
  if (stack.length !== 1)
    throw new Error(
      `mustache: {{#${stack[stack.length - 1].value}}} is unclosed`,
    );
  return root;
}

export function parse(template) {
  return build(stripStandalone(tokenize(template)));
}

function emit(node, stack, out) {
  for (const c of node.children) {
    if (c.type === "text") {
      out.push(c.value);
    } else if (c.type === "name") {
      const v = lookup(stack, c.value);
      // A missing or null hole renders as the empty string, as in mustache. The
      // generator's business is to make sure no hole is missing (SPEC.md §5.2 step 1);
      // this renderer does not second-guess it.
      out.push(v === undefined || v === null || v === false ? "" : String(v));
    } else if (c.type === "open") {
      const v = lookup(stack, c.value);
      if (Array.isArray(v)) {
        for (const item of v) emit(c, [...stack, item], out);
      } else if (v !== undefined && v !== null && v !== false && v !== "") {
        emit(c, typeof v === "object" ? [...stack, v] : stack, out);
      }
    } else if (c.type === "inverted") {
      const v = lookup(stack, c.value);
      const empty =
        v === undefined ||
        v === null ||
        v === false ||
        v === "" ||
        (Array.isArray(v) && v.length === 0);
      if (empty) emit(c, stack, out);
    }
  }
}

export function render(template, view) {
  const out = [];
  emit(parse(template), [view ?? {}], out);
  return out.join("");
}

export default { parse, render };
