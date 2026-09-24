// Read decision tables out of an EMITTED DMN artifact.
//
// A narrow, regex-level reader: it takes <decisionTable> and its <input>,
// <output>, <rule> and hitPolicy, and nothing else. It does not model DMN, does
// not validate it, and is not a second exporter.
//
// ON THE OBJECTION that this duplicates jl4-core/src/L4/Dmn/Markdown.hs, whose
// own header warns against two hand-maintained exporters that quietly disagree:
// the two read DIFFERENT THINGS. Markdown.hs reads the L4 intermediate
// representation and emits a table for the decisions dmnmd's grammar can say.
// This reads the emitted ARTIFACT, which is what a fidelity report is a view
// of. Where both produce a table for the same decision the explainer compares
// their shapes and reports a disagreement as a finding.
//
// Usage as a module only; there is no CLI, because the only caller is the
// explainer renderer and a CLI would invite this to become a second exporter.

const decode = (s) =>
  String(s ?? "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");

const attr = (tag, name) => {
  const m = new RegExp(`${name}="([^"]*)"`).exec(tag);
  return m ? decode(m[1]) : null;
};

const textOf = (xml, tag) => {
  const m = new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`).exec(xml);
  return m ? decode(m[1].trim()) : null;
};

/**
 * Every decision that carries a decision table, in document order.
 *
 * Returns [{ id, name, hitPolicy, inputs[], outputs[], rules[], annotations[] }]
 * where a rule is { entries[], output[], annotation }. Cell text is the FEEL
 * source as emitted; nothing is re-formatted, because a reformatted cell is a
 * cell a reader cannot diff against the file.
 */
export function decisionTables(xml) {
  const out = [];
  const src = String(xml);
  const decisionRe = /<decision\b([^>]*)>([\s\S]*?)<\/decision>/g;
  for (const dm of src.matchAll(decisionRe)) {
    const head = dm[1];
    const body = dm[2];
    const tm = /<decisionTable\b([^>]*)>([\s\S]*?)<\/decisionTable>/.exec(body);
    if (!tm) continue;
    const table = tm[2];
    const inputs = [];
    for (const im of table.matchAll(
      /<input\b([^>]*)>([\s\S]*?)<\/input>|<input\b([^>]*)\/>/g,
    )) {
      const a = im[1] ?? im[3] ?? "";
      const inner = im[2] ?? "";
      inputs.push({
        label: attr(a, "label") ?? textOf(inner, "text") ?? attr(a, "id"),
        expression: textOf(inner, "text"),
        typeRef:
          /<inputExpression\b[^>]*typeRef="([^"]*)"/.exec(inner)?.[1] ?? null,
      });
    }
    const outputs = [];
    for (const om of table.matchAll(
      /<output\b([^>]*)>([\s\S]*?)<\/output>|<output\b([^>]*)\/>/g,
    )) {
      const a = om[1] ?? om[3] ?? "";
      outputs.push({
        label: attr(a, "label") ?? attr(a, "name") ?? attr(a, "id"),
        typeRef: attr(a, "typeRef"),
      });
    }
    const annotations = [];
    for (const am of table.matchAll(/<annotation\b([^>]*)\/?>/g))
      annotations.push(attr(am[1], "name") ?? "annotation");
    const rules = [];
    for (const rm of table.matchAll(/<rule\b[^>]*>([\s\S]*?)<\/rule>/g)) {
      const r = rm[1];
      const entries = [
        ...r.matchAll(/<inputEntry\b[^>]*>([\s\S]*?)<\/inputEntry>/g),
      ].map((e) => textOf(e[1], "text") ?? "");
      const output = [
        ...r.matchAll(/<outputEntry\b[^>]*>([\s\S]*?)<\/outputEntry>/g),
      ].map((e) => textOf(e[1], "text") ?? "");
      const ann = [
        ...r.matchAll(/<description>([\s\S]*?)<\/description>/g),
      ].map((e) => decode(e[1].trim()));
      rules.push({ entries, output, annotation: ann.join(" · ") });
    }
    out.push({
      id: attr(head, "id"),
      name: attr(head, "name"),
      hitPolicy: attr(tm[1], "hitPolicy") ?? "UNIQUE",
      inputs,
      outputs,
      annotations,
      rules,
    });
  }
  return out;
}

/** Counts a caller can print without opening the file itself. */
export function drgCounts(xml) {
  const src = String(xml);
  const n = (re) => (src.match(re) ?? []).length;
  return {
    decisions: n(/<decision\b/g),
    decisionTables: n(/<decisionTable\b/g),
    literalExpressions: n(/<literalExpression\b/g),
    inputData: n(/<inputData\b/g),
    businessKnowledgeModels: n(/<businessKnowledgeModel\b/g),
    itemDefinitions: n(/<itemDefinition\b/g),
    informationRequirements: n(/<informationRequirement\b/g),
  };
}

/**
 * The rule-date tables: those whose inputs mention the rule-date variable. This
 * is the temporal axis rendered as a table, which is the one thing in the
 * projection set that no other legal explainer has to show.
 */
export function ruleDateTables(tables) {
  return tables.filter((t) =>
    t.inputs.some((i) =>
      /rules?[_ ]?effective[_ ]?date/i.test(
        `${i.expression ?? ""} ${i.label ?? ""}`,
      ),
    ),
  );
}
