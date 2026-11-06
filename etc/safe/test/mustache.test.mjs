import { deepStrictEqual, strictEqual, throws } from "node:assert";
import { test } from "node:test";
import { render } from "../lib/mustache.mjs";

test("interpolates, and does not escape", () => {
  strictEqual(render("Hello {{who}}", { who: "<b>&</b>" }), "Hello <b>&</b>");
  strictEqual(render("Hello {{{who}}}", { who: "<b>&</b>" }), "Hello <b>&</b>");
  strictEqual(render("Hello {{&who}}", { who: "a&b" }), "Hello a&b");
});

test("a missing hole renders empty, not the tag", () => {
  strictEqual(render("[{{gone}}]", {}), "[]");
  strictEqual(render("[{{gone}}]", { gone: null }), "[]");
});

test("dotted paths, and the dot", () => {
  strictEqual(render("{{a.b.c}}", { a: { b: { c: "deep" } } }), "deep");
  strictEqual(render("{{#xs}}[{{.}}]{{/xs}}", { xs: ["a", "b"] }), "[a][b]");
});

test("sections iterate arrays and push object context", () => {
  strictEqual(
    render("{{#xs}}{{n}};{{/xs}}", { xs: [{ n: 1 }, { n: 2 }] }),
    "1;2;",
  );
  strictEqual(render("{{#o}}{{n}}{{/o}}", { o: { n: "in" } }), "in");
  strictEqual(render("{{#no}}x{{/no}}", { no: [] }), "");
  strictEqual(render("{{#no}}x{{/no}}", { no: false }), "");
  strictEqual(render("{{#yes}}x{{/yes}}", { yes: true }), "x");
});

test("inverted sections", () => {
  strictEqual(render("{{^xs}}none{{/xs}}", { xs: [] }), "none");
  strictEqual(render("{{^xs}}none{{/xs}}", { xs: [1] }), "");
  strictEqual(render("{{^gone}}none{{/gone}}", {}), "none");
});

test("comments vanish", () => {
  strictEqual(render("a{{! not shown }}b", {}), "ab");
});

test("a standalone section tag takes its whole line with it", () => {
  strictEqual(render("a\n{{#xs}}\nx\n{{/xs}}\nb\n", { xs: [1] }), "a\nx\nb\n");
  strictEqual(render("a\n{{! c }}\nb\n", {}), "a\nb\n");
  // An interpolation is never standalone: its line is the text it belongs to.
  strictEqual(render("a\n{{x}}\nb\n", { x: "X" }), "a\nX\nb\n");
});

test("outer context is still visible inside a section", () => {
  strictEqual(
    render("{{#xs}}{{top}}{{n}}{{/xs}}", { top: "T", xs: [{ n: 1 }] }),
    "T1",
  );
});

test("malformed templates fail loudly", () => {
  throws(() => render("{{#a}}x", {}), /unclosed/);
  throws(() => render("x{{/a}}", {}), /closes nothing/);
  throws(() => render("{{#a}}{{/b}}", {}), /not nested/);
  throws(() => render("{{a", {}), /unclosed tag/);
});

test("a literal that looks like a placeholder survives round-trip", () => {
  // This is the shape check-templates.mjs relies on: the view value may itself contain
  // brackets, backslashes and emphasis, and none of it is reinterpreted.
  const lit = "\\[**COMPANY\\]**";
  strictEqual(
    render("> {{companyNameCaps}}\n", { companyNameCaps: lit }),
    `> ${lit}\n`,
  );
});

test("parse is stable across renders", () => {
  const t = "{{#xs}}{{a}}{{/xs}}";
  const v = { xs: [{ a: 1 }, { a: 2 }] };
  deepStrictEqual(render(t, v), render(t, v));
});
