// fill -> round -> verify, on the encoding row's own example deal.
//
// The PDF legs need pandoc, exiftool and qpdf. Each is probed rather than assumed, and a
// missing one skips only the tests that need it, naming the tool — the Markdown, the
// instance module and the conversion schedule are produced without any of them.

import { ok, strictEqual } from "node:assert";
import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import {
  GEN,
  MAKE_TEMPLATES,
  NO_SUBJECT,
  buildScratchSubject,
  locateSubject,
} from "./fixture.mjs";
import { loadSubject } from "../lib/subject.mjs";
import { have } from "../lib/tools.mjs";

const src = locateSubject();
const tools = {
  pandoc: have("pandoc"),
  exiftool: have("exiftool"),
  qpdf: have("qpdf"),
};
const missing = Object.entries(tools)
  .filter(([, ok]) => !ok)
  .map(([t]) => t);
const NO_PDF = `PDF legs need ${missing.join(", ")} on PATH`;

let dir = null;
let out = null;
let deal = null;
before(() => {
  if (!src) return;
  dir = buildScratchSubject(src, mkdtempSync(join(tmpdir(), "safe-e2e-")));
  out = join(dir, "out");
  strictEqual(
    spawnSync(process.execPath, [MAKE_TEMPLATES, "--subject", dir], {
      encoding: "utf8",
    }).status,
    0,
  );
  deal = join(loadSubject(dir).row, "cases", "deal.example.json");
});
after(() => {
  if (dir) rmSync(dir, { recursive: true, force: true });
});

const gen = (...args) =>
  spawnSync(process.execPath, [GEN, ...args], { encoding: "utf8" });

test(
  "fill writes a document and an instance module per Safe",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const r = gen("fill", "--subject", dir, "--deal", deal, "--out", out);
    strictEqual(r.status, 0, r.stdout + r.stderr);
    for (const f of [
      "investor-a-llc.md",
      "investor-a-llc.l4",
      "investor-b-ventures-lp.md",
      "investor-b-ventures-lp.l4",
      "investor-b-ventures-lp-pro-rata.md",
      "manifest.json",
    ])
      ok(existsSync(join(out, f)), `expected ${f}`);
    // The side letter is generated only for the Safe that asked for one.
    ok(!existsSync(join(out, "investor-a-llc-pro-rata.md")));
    // fill runs `l4 check` on every instance it writes and refuses to continue otherwise.
    ok(/l4 check\s+investor-a-llc\.l4: ok/.test(r.stdout), r.stdout);
  },
);

test(
  "the filled document is the form with its blanks filled",
  { skip: src ? false : NO_SUBJECT },
  () => {
    strictEqual(
      gen("fill", "--subject", dir, "--deal", deal, "--out", out).status,
      0,
    );
    const md = readFileSync(join(out, "investor-a-llc.md"), "utf8");
    ok(
      md.includes("of $200,000 (the “**Purchase Amount**”)"),
      "purchase amount",
    );
    ok(md.includes("on or about September 4, 2026"), "date");
    ok(md.includes("“**Post-Money Valuation Cap**” is $4,000,000"), "cap");
    ok(md.includes("laws of the State of Delaware"), "governing law");
    ok(
      !/\\\[[^\]]*\\\]/.test(md.split("---")[0]),
      "no bracketed placeholder survives",
    );
    // The licence line is a condition of the CC BY-ND grant and must be reproduced.
    ok(md.includes("Y Combinator Management, LLC"), "licence line");
    ok(
      md.includes("Creative Commons Attribution-NoDerivatives 4.0"),
      "licence name",
    );
    // The blanks the parties fill by hand are still there.
    ok(md.includes("By:<u>     </u>"), "the signature rule survives");
  },
);

test(
  "round reproduces the User Guide's Example 1 figures",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const r = gen("round", "--subject", dir, "--deal", deal, "--out", out);
    strictEqual(r.status, 0, r.stdout + r.stderr);
    const c = JSON.parse(readFileSync(join(out, "conversion.json"), "utf8"));
    // "Company Capitalization = 10,000,000 / (100% - 15%) = 11,764,705" — User Guide p. 20
    strictEqual(Math.floor(c.companyCapitalization), 11764705);
    strictEqual(
      c.rows.find((x) => /Investor A/.test(x.investor)).shares,
      588235,
    );
    strictEqual(
      c.rows.find((x) => /Investor B/.test(x.investor)).shares,
      1176470,
    );
    // "$1.1144" per share, 1,695,000 pool increase (the guide rounds to the thousand).
    ok(Math.abs(c.standardPrice - 1.1144) < 0.0005, `price ${c.standardPrice}`);
    ok(
      Math.abs(c.optionPoolIncrease - 1695000) / 1695000 < 0.0005,
      `pool ${c.optionPoolIncrease}`,
    );
    const md = readFileSync(join(out, "conversion-schedule.md"), "utf8");
    ok(md.includes("**11,764,705**"), "Company Capitalization in the schedule");
    ok(md.includes("| Founders |"), "cap table");
  },
);

test(
  "fill --pdf embeds, and verify reads it back",
  { skip: src ? (missing.length ? NO_PDF : false) : NO_SUBJECT },
  () => {
    const f = gen(
      "fill",
      "--subject",
      dir,
      "--deal",
      deal,
      "--out",
      out,
      "--pdf",
    );
    strictEqual(f.status, 0, f.stdout + f.stderr);
    const pdf = join(out, "investor-a-llc.pdf");
    ok(existsSync(pdf));
    const v = gen("verify", pdf, "--subject", dir);
    strictEqual(v.status, 0, v.stdout + v.stderr);
    ok(/every hash agrees/.test(v.stdout), v.stdout);
    ok(/l4 check investor-a-llc\.l4/.test(v.stdout), v.stdout);
  },
);

test(
  "verify refuses a PDF that carries no L4",
  { skip: src ? (missing.length ? NO_PDF : false) : NO_SUBJECT },
  () => {
    const md = join(dir, "plain.md");
    writeFileSync(md, "# not a safe\n");
    strictEqual(
      spawnSync("pandoc", ["-f", "gfm", "-o", join(dir, "plain.pdf"), md])
        .status,
      0,
    );
    const v = gen("verify", join(dir, "plain.pdf"));
    strictEqual(v.status, 1);
    ok(/carries no XMP-pdfx:L4/.test(v.stderr), v.stderr);
  },
);

test(
  "a deal the form cannot take produces no document at all",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const bad = JSON.parse(readFileSync(deal, "utf8"));
    bad.safes[0].terms = { cap: 1000 }; // below the purchase amount
    const path = join(dir, "bad.json");
    writeFileSync(path, JSON.stringify(bad));
    const badOut = join(dir, "out-bad");
    const r = gen("fill", "--subject", dir, "--deal", path, "--out", badOut);
    strictEqual(r.status, 2, r.stdout + r.stderr);
    ok(/the cap must exceed the purchase amount/.test(r.stderr), r.stderr);
    ok(
      !existsSync(join(badOut, "investor-a-llc.md")),
      "no document is written",
    );
  },
);

test(
  "an unpublished cell is refused, not synthesised",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const bad = JSON.parse(readFileSync(deal, "utf8"));
    bad.form.jurisdiction = "sg";
    bad.form.variant = "discount";
    const path = join(dir, "unpublished.json");
    writeFileSync(path, JSON.stringify(bad));
    const r = gen(
      "fill",
      "--subject",
      dir,
      "--deal",
      path,
      "--out",
      join(dir, "out-unpub"),
    );
    strictEqual(r.status, 2, r.stdout + r.stderr);
    ok(
      /no published YC form for jurisdiction 'sg' with variant 'discount'/.test(
        r.stderr,
      ),
      r.stderr,
    );
  },
);

test(
  "the edition comes from the form's stamp, and a deal that disagrees is refused",
  { skip: src ? false : NO_SUBJECT },
  () => {
    // The US MFN form is stamped "Version 1.3" while the cap and discount forms are 1.2,
    // so a deal that says 1.2 for every US form is wrong about exactly one of them.
    const d = JSON.parse(readFileSync(deal, "utf8"));
    d.form.variant = "mfn";
    d.safes.forEach((s) => {
      s.terms = { mfn: true };
    });
    const path = join(dir, "mfn-12.json");
    writeFileSync(path, JSON.stringify(d));
    const bad = gen(
      "fill",
      "--subject",
      dir,
      "--deal",
      path,
      "--out",
      join(dir, "out-mfn12"),
    );
    strictEqual(bad.status, 2, bad.stdout + bad.stderr);
    ok(
      /deal\.form\.edition is "1\.2".*edition 1\.3/s.test(bad.stderr),
      bad.stderr,
    );

    d.form.edition = "1.3";
    const good = join(dir, "mfn-13.json");
    writeFileSync(good, JSON.stringify(d));
    const out13 = join(dir, "out-mfn13");
    const r = gen("fill", "--subject", dir, "--deal", good, "--out", out13);
    strictEqual(r.status, 0, r.stdout + r.stderr);
    ok(/edition\s+1\.3 from the form's own stamp/.test(r.stdout), r.stdout);
    const m = JSON.parse(readFileSync(join(out13, "manifest.json"), "utf8"));
    strictEqual(
      m.editions["Postmoney Safe - MFN Only - FINAL.md"].edition,
      "1.3",
    );
    // The side letter carries its own stamp, not the SAFE's.
    strictEqual(m.editions["Pro Rata Side Letter.md"].edition, "1.0");
  },
);

test(
  "liquidity reproduces the User Guide's Q3 and Q4",
  { skip: src ? false : NO_SUBJECT },
  () => {
    // Q3, p. 21: Proceeds $10m, both Safes convert, $0.8901 per as-converted share,
    // Conversion Amounts 561,764 and 1,123,529.
    const q3 = join(dir, "out-q3");
    const r3 = gen(
      "liquidity",
      "--subject",
      dir,
      "--deal",
      deal,
      "--out",
      q3,
      "--proceeds",
      "10000000",
    );
    strictEqual(r3.status, 0, r3.stdout + r3.stderr);
    const a = JSON.parse(
      readFileSync(join(q3, "liquidity.json"), "utf8"),
    ).result;
    ok(
      Math.abs(a.perShareConsideration - 0.8901) < 0.0005,
      `per share ${a.perShareConsideration}`,
    );
    strictEqual(
      a.rows.find((x) => /Investor A/.test(x.investor)).conversionShares,
      561764,
    );
    strictEqual(
      a.rows.find((x) => /Investor B/.test(x.investor)).conversionShares,
      1123529,
    );
    ok(
      a.rows.every((x) => x.method === "convert"),
      JSON.stringify(a.rows.map((x) => x.method)),
    );

    // Q4, p. 21: Proceeds $3m, neither converts, each takes its Cash-Out Amount.
    const q4 = join(dir, "out-q4");
    strictEqual(
      gen(
        "liquidity",
        "--subject",
        dir,
        "--deal",
        deal,
        "--out",
        q4,
        "--proceeds",
        "3000000",
      ).status,
      0,
    );
    const b = JSON.parse(
      readFileSync(join(q4, "liquidity.json"), "utf8"),
    ).result;
    ok(
      b.rows.every((x) => x.method === "cash-out"),
      JSON.stringify(b.rows.map((x) => x.method)),
    );
    strictEqual(b.rows.find((x) => /Investor A/.test(x.investor)).paid, 200000);
    strictEqual(b.rows.find((x) => /Investor B/.test(x.investor)).paid, 800000);
    ok(existsSync(join(q4, "liquidity-schedule.md")));
  },
);

test(
  "liquidity without --proceeds says so",
  { skip: src ? false : NO_SUBJECT },
  () => {
    const r = gen(
      "liquidity",
      "--subject",
      dir,
      "--deal",
      deal,
      "--out",
      join(dir, "out-noproceeds"),
    );
    strictEqual(r.status, 1);
    ok(/needs --proceeds N/.test(r.stderr), r.stderr);
  },
);
