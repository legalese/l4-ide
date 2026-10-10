/**
 * Call panels, client half, stage 1: the wire's optional `expansion` (viz-expr), the adapter's
 * `calls: "expand"` mode, and `spreadValue`.
 *
 * FIXTURE: `fixtures/call-expansions.json` is a REAL capture: this branch's jl4-lsp, asked for
 * call expansions (`l4.visualize` with `{"expandCalls": true}`), over every "Show decision
 * graph" lens of six small modules, verbatim (its `_captured` / `_how` fields say how). Nothing
 * in it is edited by hand. The tests look things up by label, not by node id.
 *
 * `fixtures/call-expansions.leaf-baseline.json` is what `fromVizFunDecl` made of those same
 * captures BEFORE the change (the ladder-core sources of 3e012727c). The leaf-mode test pins
 * today's decoder to it.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { makeVizInfoDecoder } from "@repo/viz-expr";
import type {
  FunDecl as VizFunDecl,
  IRExpr as VizIRExpr,
} from "@repo/viz-expr";
import {
  fromVizFunDecl,
  callLabel,
  spreadValue,
  type DecodedViz,
} from "../src/viz-adapter.js";
import type { IRExpr, NodeId, UBoolValue } from "../src/types.js";

const fixture = (name: string) =>
  JSON.parse(
    readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8"),
  );
const CAP = fixture("call-expansions.json") as {
  _captured: string;
  modules: Record<string, { source: string; funDecls: VizFunDecl[] }>;
};
const BASE = fixture("call-expansions.leaf-baseline.json") as {
  modules: Record<string, unknown[]>;
};
const MODULES = ["joint", "passthru", "r991", "r991pc", "visa", "loan"];

const funDecl = (mod: string, name: string): VizFunDecl => {
  const f = CAP.modules[mod]!.funDecls.find(
    (d) => d.name.label.replace(/`/g, "") === name,
  );
  assert.ok(f, `${mod}: no FunDecl ${name}`);
  return f;
};

/** Maps -> entry arrays, the form the baseline was written in. */
const ser = (d: DecodedViz) =>
  JSON.parse(
    JSON.stringify(
      Object.fromEntries(
        Object.entries(d).map(([k, v]) => [
          k,
          v instanceof Map ? [...v.entries()] : v,
        ]),
      ),
    ),
  );

/** Every node of a decoded tree, each with the labels of the call panels it sits inside. */
interface Placed {
  node: IRExpr;
  panels: string[];
}
function nodes(e: IRExpr, panels: string[] = []): Placed[] {
  const here: Placed = { node: e, panels };
  switch (e.$type) {
    case "And":
    case "Or": {
      const inner =
        e.$type === "And" && e.call ? [...panels, e.label ?? "?"] : panels;
      return [here, ...e.args.flatMap((a) => nodes(a, inner))];
    }
    case "Not":
      return [here, ...nodes(e.negand, panels)];
    case "Implies":
      return [here, ...nodes(e.scope, panels), ...nodes(e.requirement, panels)];
    default:
      return [here];
  }
}
const leafNamed = (ps: Placed[], label: string, panel: string | null) => {
  const hits = ps.filter(
    (p) =>
      (p.node.$type === "UBoolVar" || p.node.$type === "App") &&
      p.node.label === label &&
      (panel === null ? p.panels.length === 0 : p.panels.at(-1) === panel),
  );
  return hits.map((h) => h.node.id);
};

/** Wire call leaves that carry an expansion, at any depth. */
function wireCalls(e: VizIRExpr): { id: number; label: string }[] {
  const out: { id: number; label: string }[] = [];
  const go = (n: VizIRExpr) => {
    switch (n.$type) {
      case "And":
      case "Or":
        n.args.forEach(go);
        return;
      case "Not":
        go(n.negand);
        return;
      case "Implies":
        go(n.scope);
        go(n.requirement);
        return;
      case "UBoolVar":
        if (n.expansion) {
          out.push({ id: n.id.id, label: n.name.label });
          go(n.expansion);
        }
        return;
      case "App":
        if (n.expansion) {
          out.push({ id: n.id.id, label: n.fnName.label });
          go(n.expansion);
        }
        return;
      default:
        return;
    }
  };
  go(e);
  return out;
}

/* ------------------------------------------------------------ the fixture */

test("the fixture says it is a capture with expansions asked for, and has calls to expand", () => {
  assert.match(CAP._captured, /^jl4-lsp built from .*"expandCalls": true/);
  const calls = MODULES.flatMap((m) =>
    CAP.modules[m]!.funDecls.flatMap((f) => wireCalls(f.body)),
  );
  assert.ok(calls.length >= 15, `only ${calls.length} expanded calls`);
});

/* ------------------------------------------------------------ C1: wire decoder */

test("viz-expr's runtime decoder keeps a nested expansion, and still decodes a reply without one", () => {
  const decode = makeVizInfoDecoder();
  const verDocId = { uri: "file:///loan.l4", version: 1 };
  const withExp = funDecl("loan", "may receive a loan");
  const r = decode({ verDocId, funDecl: withExp });
  assert.equal(r._tag, "Right");
  if (r._tag !== "Right") return;
  // The decoded value equals the input: Effect's Struct would have STRIPPED an undeclared
  // `expansion`, so equality here is the evidence the field is in the schema, nested too.
  assert.deepEqual(r.right.funDecl, withExp);
  assert.equal(wireCalls(r.right.funDecl.body).length, 5);

  const strip = (x: unknown): unknown =>
    Array.isArray(x)
      ? x.map(strip)
      : x && typeof x === "object"
        ? Object.fromEntries(
            Object.entries(x)
              .filter(([k]) => k !== "expansion")
              .map(([k, v]) => [k, strip(v)]),
          )
        : x;
  const old = strip(withExp) as VizFunDecl;
  const r2 = decode({ verDocId, funDecl: old });
  assert.equal(r2._tag, "Right");
  if (r2._tag === "Right") assert.deepEqual(r2.right.funDecl, old);

  // A malformed expansion is refused, not silently dropped.
  const bad = JSON.parse(JSON.stringify(withExp));
  bad.body.args[0].expansion = { $type: "Nope", id: { id: 1 } };
  assert.equal(decode({ verDocId, funDecl: bad })._tag, "Left");
});

/* ------------------------------------------------------------ C2: leaf mode unchanged */

test("default mode decodes every capture exactly as the adapter did before the change", () => {
  for (const m of MODULES) {
    const funs = CAP.modules[m]!.funDecls;
    const base = BASE.modules[m]!;
    assert.equal(funs.length, base.length, m);
    funs.forEach((f, i) => {
      assert.deepEqual(ser(fromVizFunDecl(f)), base[i], `${m}[${i}] default`);
      assert.deepEqual(
        ser(fromVizFunDecl(f, { calls: "leaf" })),
        base[i],
        `${m}[${i}] leaf`,
      );
    });
  }
});

/* ------------------------------------------------------------ C2: expand mode */

test("expand mode: one call panel per expanded call, under the call's own id, labelled as written", () => {
  for (const m of MODULES)
    for (const f of CAP.modules[m]!.funDecls) {
      const calls = wireCalls(f.body);
      const d = fromVizFunDecl(f, { calls: "expand" });
      const panels = nodes(d.fn.body)
        .map((p) => p.node)
        .filter((n) => n.$type === "And" && n.call === true);
      assert.deepEqual(
        panels.map((p) => p.id).sort(),
        calls.map((c) => c.id).sort(),
        `${m} ${f.name.label}`,
      );
      for (const p of panels) {
        assert.equal(p.$type, "And");
        if (p.$type !== "And") continue;
        assert.equal(p.args.length, 1, "a panel holds the one expansion");
        const c = calls.find((x) => x.id === p.id)!;
        assert.equal(p.label, callLabel(c.label));
        assert.ok(!p.label!.includes("`"), p.label);
        assert.ok(!/ OF /.test(p.label!), p.label);
      }
    }
  const labels = (mod: string, fn: string) =>
    nodes(fromVizFunDecl(funDecl(mod, fn), { calls: "expand" }).fn.body)
      .map((p) => p.node)
      .filter((n) => n.$type === "And" && n.call)
      .map((n) => ("label" in n ? n.label : ""));
  assert.deepEqual(labels("joint", "may lend jointly"), [
    "is creditworthy a",
    "is creditworthy b",
    "is creditworthy a",
  ]);
  assert.deepEqual(labels("passthru", "pass through"), ["limb a b"]);
  assert.deepEqual(labels("loan", "may receive a loan"), [
    "is of age a",
    "is creditworthy a",
    "has stable income a",
    "has clean credit history a",
    "is adequately secured a",
  ]);
});

test("callLabel: drops backticks, the top-level OF and argument commas, and nothing inside an argument", () => {
  assert.equal(callLabel("`is creditworthy` OF a"), "is creditworthy a");
  assert.equal(callLabel("limb OF a, b"), "limb a b");
  assert.equal(callLabel("`limb`"), "limb");
  assert.equal(callLabel("f OF (g OF x, y), `p, q`"), "f (g OF x, y) p, q");
  assert.equal(callLabel("`proof OF x` OF a"), "proof OF x a");
  // a call with named arguments, laid out one argument to a line (smucclaw/l4-ide#1033)
  assert.equal(
    callLabel(
      "whichever WITH y IS r\n               cond IS p\n               x IS q",
    ),
    "whichever WITH y IS r, cond IS p, x IS q",
  );
  assert.equal(callLabel("big WITH k IS n"), "big WITH k IS n");
  assert.equal(
    callLabel("`may lend` WITH b IS (f OF x,\n  y)\n  a IS `p, q`"),
    "may lend WITH b IS (f OF x,\n  y), a IS p, q",
  );
  // a string literal is copied untouched, commas and all (review 2026-10-05)
  assert.equal(
    callLabel('`has role` OF a, "owner, director"'),
    'has role a "owner, director"',
  );
  assert.equal(callLabel('f OF "a `b`", c'), 'f "a `b`" c');
  assert.equal(callLabel('f OF "say \\"x, y\\"", c'), 'f "say \\"x, y\\"" c');
  // a list argument keeps its commas
  assert.equal(callLabel("limb OF [a, b], c"), "limb [a, b] c");
});

test("expand mode: node ids are unique across the decoded tree", () => {
  for (const m of MODULES)
    for (const f of CAP.modules[m]!.funDecls) {
      const ids = nodes(fromVizFunDecl(f, { calls: "expand" }).fn.body).map(
        (p) => p.node.id,
      );
      assert.equal(new Set(ids).size, ids.length, `${m} ${f.name.label}`);
    }
});

test("expand mode: a node id repeated by an expansion is rejected loudly; leaf mode ignores expansions", () => {
  // A server that broke the fresh-id contract used to decode silently, swapping atomId and
  // TYPICALLY provenance between an expansion leaf and an unrelated outer leaf (review
  // probe5, 2026-10-05).
  const leafV = (id: number, label: string, atomId: string, extra = {}) => ({
    $type: "UBoolVar",
    id: { id },
    name: { label, unique: id },
    value: "UnknownV",
    atomId,
    canInline: false,
    ...extra,
  });
  const bad = {
    id: { id: 1 },
    name: { label: "f", unique: 1 },
    params: [],
    body: {
      $type: "And",
      id: { id: 10 },
      args: [
        leafV(11, "b", "ATOM-B"),
        leafV(12, "g a", "ATOM-G", {
          canInline: true,
          expansion: leafV(11, "a", "ATOM-A2", { typically: false }),
        }),
      ],
    },
  } as unknown as VizFunDecl;
  assert.throws(
    () => fromVizFunDecl(bad, { calls: "expand" }),
    /node id 11 occurs twice/,
  );
  assert.doesNotThrow(() => fromVizFunDecl(bad));
});

test("expand mode: the identity indexes include the expansion leaves", () => {
  for (const m of MODULES)
    for (const f of CAP.modules[m]!.funDecls) {
      const d = fromVizFunDecl(f, { calls: "expand" });
      for (const { node } of nodes(d.fn.body)) {
        if (node.$type === "UBoolVar" || node.$type === "App") {
          assert.equal(d.atomIdByNode.get(node.id), node.atomId);
          assert.ok(d.nodesByAtomId.get(node.atomId!)!.includes(node.id));
        }
        if (node.$type === "UBoolVar") {
          assert.equal(d.uniqueByNode.get(node.id), node.unique);
          assert.ok(d.nodesByUnique.get(node.unique!)!.includes(node.id));
        }
        // A panel is in the atomId index (it is the call's proposition when folded) and
        // in no other channel.
        if (node.$type === "And" && node.call) {
          assert.ok(d.atomIdByNode.has(node.id));
          assert.ok(!d.uniqueByNode.has(node.id));
          assert.ok(!d.valuation.has(node.id));
        }
      }
    }
  // Concretely: record pass through's inlined `a's has stable income` and its direct one.
  const d = fromVizFunDecl(funDecl("passthru", "record pass through"), {
    calls: "expand",
  });
  const ps = nodes(d.fn.body);
  const [inl] = leafNamed(ps, "a's `has stable income`", "is creditworthy a");
  const [dir] = leafNamed(ps, "a's `has stable income`", null);
  assert.ok(inl !== undefined && dir !== undefined);
  const atom = d.atomIdByNode.get(dir)!;
  assert.deepEqual(d.nodesByAtomId.get(atom)!.sort(), [inl, dir].sort());
});

test("expand mode: valuation, provenance and defaults are lifted from expansion leaves; the call's own are not", () => {
  const wire: VizFunDecl = {
    $type: "FunDecl",
    id: { id: 1 },
    name: { label: "top", unique: 1 },
    params: [],
    body: {
      $type: "And",
      id: { id: 2 },
      args: [
        {
          $type: "UBoolVar",
          id: { id: 3 },
          name: { label: "`callee` OF x", unique: 4 },
          canInline: true,
          atomId: "call",
          value: "TrueV",
          typically: true,
          expansion: {
            $type: "Or",
            id: { id: 5 },
            args: [
              {
                $type: "UBoolVar",
                id: { id: 6 },
                name: { label: "x", unique: 7 },
                canInline: false,
                atomId: "x",
                value: "FalseV",
                typically: false,
              },
              {
                $type: "UBoolVar",
                id: { id: 8 },
                name: { label: "y", unique: 9 },
                canInline: false,
                atomId: "y",
                value: "UnknownV",
                typically: null,
              },
            ],
          },
        },
      ],
    },
  };
  const e = fromVizFunDecl(wire, { calls: "expand" });
  assert.deepEqual([...e.valuation], [[6, "FalseV"]]);
  assert.deepEqual([...e.provenance], [[6, "default"]]);
  assert.deepEqual([...e.defaults], [[6, "FalseV"]]);
  assert.deepEqual([...e.atomIdByNode].sort(), [
    [3, "call"],
    [6, "x"],
    [8, "y"],
  ]);
  // …and in leaf mode the same wire is the one box it always was.
  const l = fromVizFunDecl(wire);
  assert.deepEqual([...l.valuation], [[3, "TrueV"]]);
  assert.deepEqual([...l.defaults], [[3, "TrueV"]]);
  assert.deepEqual(
    nodes(l.fn.body).map((p) => p.node.id),
    [2, 3],
  );
});

test("expand mode: a call leaf with no expansion stays a leaf", () => {
  // Every capture, stripped of expansions, decodes in expand mode exactly as in leaf mode.
  for (const m of MODULES)
    BASE.modules[m]!.forEach((base, i) => {
      const f = JSON.parse(
        JSON.stringify(CAP.modules[m]!.funDecls[i], (k, v) =>
          k === "expansion" ? undefined : v,
        ),
      );
      assert.deepEqual(ser(fromVizFunDecl(f, { calls: "expand" })), base);
    });
});

/* ------------------------------------------------------------ C3: spreadValue */

const expandAll = (mod: string, fn: string) => {
  const d = fromVizFunDecl(funDecl(mod, fn), { calls: "expand" });
  return { d, ps: nodes(d.fn.body) };
};
const changed = (
  before: ReadonlyMap<NodeId, UBoolValue>,
  after: ReadonlyMap<NodeId, UBoolValue>,
) =>
  [...new Set([...before.keys(), ...after.keys()])]
    .filter((k) => before.get(k) !== after.get(k))
    .sort((a, b) => a - b);

test("spreadValue: pass-through links the inlined a with the direct a, and not with b", () => {
  const { d, ps } = expandAll("passthru", "pass through");
  const [inlA] = leafNamed(ps, "a", "limb a b");
  const [inlB] = leafNamed(ps, "b", "limb a b");
  const [dirA] = leafNamed(ps, "a", null);
  assert.ok(inlA !== undefined && inlB !== undefined && dirA !== undefined);
  const before = new Map<NodeId, UBoolValue>();
  const after = spreadValue(d, inlA, "TrueV", before);
  assert.deepEqual(
    changed(before, after),
    [inlA, dirA].sort((a, b) => a - b),
  );
  assert.equal(after.get(dirA), "TrueV");
  assert.equal(before.size, 0, "the input map is not touched");
  // And from the other end: the direct a reaches the inlined one.
  const back = spreadValue(d, dirA, "FalseV", after);
  assert.equal(back.get(inlA), "FalseV");
  assert.equal(back.has(inlB), false);
  // Unknown clears every copy.
  const cleared = spreadValue(d, inlA, "UnknownV", back);
  assert.equal(cleared.size, 0);
});

test("spreadValue: limb a b and limb c d do not link", () => {
  for (const mod of ["r991", "r991pc"]) {
    const { d, ps } = expandAll(mod, "different actuals");
    const ab = ps
      .filter(
        (p) => p.panels.at(-1) === "limb a b" && p.node.$type === "UBoolVar",
      )
      .map((p) => p.node.id);
    const cd = ps
      .filter(
        (p) => p.panels.at(-1) === "limb c d" && p.node.$type === "UBoolVar",
      )
      .map((p) => p.node.id);
    assert.equal(ab.length, 2, mod);
    assert.equal(cd.length, 2, mod);
    const atomsAB = new Set(ab.map((n) => d.atomIdByNode.get(n)));
    for (const n of cd) assert.ok(!atomsAB.has(d.atomIdByNode.get(n)), mod);
    for (const n of ab) {
      const after = spreadValue(d, n, "TrueV", new Map());
      assert.deepEqual(changed(new Map(), after), [n], `${mod}: ${n} alone`);
    }
  }
});

test("spreadValue: in joint, the two copies of `is creditworthy a` link leaf for leaf, and not to b's", () => {
  const { d, ps } = expandAll("joint", "may lend jointly");
  const income = leafNamed(ps, "a's `has stable income`", "is creditworthy a");
  const [incomeB] = leafNamed(
    ps,
    "b's `has stable income`",
    "is creditworthy b",
  );
  assert.equal(income.length, 2, "two panels for `is creditworthy a`");
  const after = spreadValue(d, income[0]!, "TrueV", new Map());
  assert.deepEqual(
    changed(new Map(), after),
    [...income].sort((a, b) => a - b),
  );
  assert.equal(after.has(incomeB!), false);

  // A FOLDED panel is a box too: clicking one copy of the call sets the other.
  const panels = ps
    .map((p) => p.node)
    .filter(
      (n) => n.$type === "And" && n.call && n.label === "is creditworthy a",
    )
    .map((n) => n.id);
  assert.equal(panels.length, 2);
  const folded = spreadValue(d, panels[0]!, "FalseV", new Map());
  assert.deepEqual(
    changed(new Map(), folded),
    [...panels].sort((a, b) => a - b),
  );
});

test("spreadValue: a node with no atomId changes alone", () => {
  const { d, ps } = expandAll("joint", "may lend jointly");
  const or = ps.find((p) => p.node.$type === "Or")!.node.id;
  const after = spreadValue(d, or, "TrueV", new Map([[1, "FalseV"]]));
  assert.deepEqual(
    [...after].sort(),
    [
      [1, "FalseV"],
      [or, "TrueV"],
    ].sort(),
  );
});
