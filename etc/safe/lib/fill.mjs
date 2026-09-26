// Turning deal.json into the two artefacts of one instrument: the hole values that go
// into the form, and the instance .l4 module that IS the executable contract.

import { holeTokens } from "./subject.mjs";

const MONTHS = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

/** "2026-09-04" -> "September 4, 2026". Parsed textually: `new Date` would shift it. */
export function longDate(iso) {
  const m = String(iso).match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!m)
    throw new Error(
      `etc/safe: date ${JSON.stringify(iso)} is not ISO 8601 (YYYY-MM-DD)`,
    );
  return `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}`;
}

/** 1000000 -> "1,000,000"; 1234.5 -> "1,234.50". No currency symbol: see `money` below. */
export function groupDigits(n) {
  const neg = n < 0;
  const x = Math.abs(n);
  const whole = Math.floor(x);
  const frac = x - whole;
  const g = String(whole).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return (neg ? "-" : "") + g + (frac ? "." + frac.toFixed(2).slice(2) : "");
}

/** Trim a rate to the fewest digits that say it: 80 -> "80", 82.5 -> "82.5". */
export function rate(n) {
  return String(Number(n.toFixed(4)));
}

export function slug(name) {
  return (
    String(name)
      .normalize("NFKD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60) || "investor"
  );
}

/**
 * Holes the generator deliberately leaves as the form printed them.
 *
 * `By:` is where a wet signature goes and the second address line is a continuation
 * neither deal.json nor the conversion has a value for. Filling either with the empty
 * string would DELETE the rule the signer needs, so these keep their placeholder — the
 * document comes out of the generator ready to sign, not pre-signed.
 */
export const LEAVE_BLANK = new Set([
  "companySignatureLine",
  "investorSignatureLine",
  "companyAddressLine2",
  "investorAddressLine2",
]);

/**
 * The value of every hole this generator knows, for one instrument.
 *
 * Jurisdiction-specific holes are present only where the form has them, and that is not
 * a convenience: `validate deal` refuses a Singapore deal that carries a governing law
 * and a US deal that does not (safe-form.l4, `reasons the company block cannot be
 * filled`), so a value supplied here for a hole the form does not have would be a value
 * the encoding has already ruled inadmissible.
 */
export function holeValues(deal, safe, { document = "safe" } = {}) {
  const c = deal.company;
  const v = {
    companyName: c.name,
    companyNameCaps: String(c.name).toUpperCase(),
    investorName: safe.investor.name,
    investorNameCaps: String(safe.investor.name).toUpperCase(),
    dateOfSafe: longDate(safe.date),
    companySignatoryName: c.signatory?.name,
    companySignatoryTitle: c.signatory?.title,
    investorSignatoryName: safe.investor.signatory?.name,
    investorSignatoryTitle: safe.investor.signatory?.title,
  };
  if (document === "safe") {
    v.purchaseAmount = groupDigits(safe.purchaseAmount);
    v.companyAddress = oneLine(c.address);
    v.companyEmail = c.email;
    v.investorAddress = oneLine(safe.investor.address);
    v.investorEmail = safe.investor.email;
    if (safe.terms?.cap != null) v.valuationCap = groupDigits(safe.terms.cap);
    // "The Discount Rate is [100 minus the discount]%" — the form's blank is the RATE.
    if (safe.terms?.discount != null)
      v.discountRate = rate(100 - safe.terms.discount);
    if (c.incorporation != null) {
      v.stateOfIncorporation = c.incorporation;
      v.incorporationJurisdiction = c.incorporation;
    }
    if (c.governingLaw != null) {
      v.governingLaw = c.governingLaw;
      v.governingProvince = c.governingLaw;
    }
    if (c.registrationNumber != null)
      v.companyRegistrationNumber = c.registrationNumber;
  }
  for (const k of Object.keys(v)) if (v[k] == null) delete v[k];
  return v;
}

function oneLine(s) {
  return String(s ?? "")
    .replace(/\s*\n\s*/g, ", ")
    .trim();
}

/**
 * Build the mustache view for one template: token -> presented value.
 *
 * The presentation the FORM asks for lives in holes.json (`case`, and the `wrap` the
 * normaliser adds for a bold run that straddles the bracket). The presentation the
 * SURROUNDING TEXT asks for is read off the template itself: the US forms print `$`
 * and the non-US forms `US$` immediately before the amount blanks, and the discount
 * form prints `%` immediately after the rate, so those characters must NOT come from
 * the value. Reading them from the template rather than from a table keyed by
 * jurisdiction means a template that changes its mind is followed, not contradicted.
 */
export function buildView(templateText, form, file, values) {
  const { entries } = holeTokens(form, file);
  const view = {};
  const unresolved = [];
  const blank = [];
  for (const e of entries) {
    if (view[e.token] !== undefined) continue;
    if (LEAVE_BLANK.has(e.hole)) {
      view[e.token] = e.literal;
      blank.push(e.hole);
      continue;
    }
    let value = values[e.hole];
    if (value === undefined) {
      unresolved.push(e.hole);
      view[e.token] = e.literal;
      continue;
    }
    if (e.case === "upper") value = String(value).toUpperCase();
    const tag = `{{${e.token}}}`;
    const at = templateText.indexOf(tag);
    const before = at > 0 ? templateText.slice(Math.max(0, at - 4), at) : "";
    const after =
      at >= 0 ? templateText.slice(at + tag.length, at + tag.length + 1) : "";
    if (e.hole === "purchaseAmount" || e.hole === "valuationCap")
      if (!/\$$/.test(before)) value = "$" + value;
    if (e.hole === "discountRate" && after !== "%") value = value + "%";
    if (Array.isArray(e.wrap)) value = e.wrap[0] + value + e.wrap[1];
    else if (e.wrap) value = e.wrap + value + e.wrap;
    view[e.token] = value;
  }
  return { view, unresolved, blank };
}

// ---------------------------------------------------------------------------
// The instance module
// ---------------------------------------------------------------------------

const esc = (s) =>
  `"${String(s)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\s*\n\s*/g, ", ")}"`;
const num = (n) => (Number.isInteger(n) ? String(n) : String(n));
const maybeStr = (s) => (s == null ? "NOTHING" : `JUST ${esc(s)}`);

/**
 * The instance module: the deal bound as L4 values, in the style of the encoding row's
 * own `cases/user-guide-appendix-ii.l4`.
 *
 * It carries EVERY Safe in the deal, not just the one the document is for, because the
 * conversion is a portfolio computation: Company Capitalization contains all Converting
 * Securities, so one Safe's shares cannot be computed from that Safe alone (SPEC.md
 * §6.3). A PDF that embedded only its own Safe would carry a program that cannot answer
 * the question the instrument poses.
 */
export function instanceModule(deal, { generatedAt, row, forSafe } = {}) {
  const L = [];
  const p = (s = "") => L.push(s);
  p(
    `-- Generated by etc/safe/gen.mjs${generatedAt ? ` on ${generatedAt}` : ""}.`,
  );
  p(`--`);
  p(
    `-- This is the executable form of one YC Post-Money Safe transaction: the deal as`,
  );
  p(
    `-- L4 values, over the encoding row ${row ?? "legalese-2026-09"}. It is the payload`,
  );
  p(`-- attached to the PDF and hashed into its XMP packet (SPEC.md §5.4).`);
  if (forSafe)
    p(
      `-- The document this module accompanies is the Safe issued to ${forSafe}.`,
    );
  p(`--`);
  p(
    `-- Every Safe in the round is bound here, not only that one: Company Capitalization`,
  );
  p(
    `-- includes all Converting Securities, so no Safe's share count is computable alone.`,
  );
  p(`--`);
  p(
    `-- The instrument text itself is © Y Combinator Management, LLC under CC BY-ND 4.0;`,
  );
  p(
    `-- this module is a formalisation of the parameters, not a copy of the form.`,
  );
  p();
  p("IMPORT prelude");
  p("IMPORT `safe-form`");
  p("IMPORT safe");
  p("IMPORT `safe-portfolio`");
  p();
  p("§ `The form`");
  p();
  p("`the form` MEANS FormIn WITH");
  p(`    family       IS ${esc(deal.form.family)}`);
  p(`    edition      IS ${esc(deal.form.edition)}`);
  p(`    jurisdiction IS ${esc(deal.form.jurisdiction)}`);
  p(`    variant      IS ${esc(deal.form.variant)}`);
  p();
  p("§ `The company`");
  p();
  const ct = deal.company.capTable;
  p("`the cap table` MEANS CapTableIn WITH");
  p(`    commonOutstanding  IS ${num(ct.commonOutstanding)}`);
  p(`    optionsOutstanding IS ${num(ct.optionsOutstanding)}`);
  p(`    promisedOptions    IS ${num(ct.promisedOptions)}`);
  p(`    unissuedOptionPool IS ${num(ct.unissuedOptionPool)}`);
  p();
  p("`the company signatory` MEANS Signatory WITH");
  p(`    name  IS ${esc(deal.company.signatory?.name ?? "")}`);
  p(`    title IS ${esc(deal.company.signatory?.title ?? "")}`);
  p();
  p("`the company` MEANS CompanyIn WITH");
  p(`    name               IS ${esc(deal.company.name)}`);
  p(`    incorporation      IS ${maybeStr(deal.company.incorporation)}`);
  p(`    governingLaw       IS ${maybeStr(deal.company.governingLaw)}`);
  p(`    registrationNumber IS ${maybeStr(deal.company.registrationNumber)}`);
  p(`    address            IS ${esc(deal.company.address ?? "")}`);
  p(`    email              IS ${esc(deal.company.email ?? "")}`);
  p(`    signatory          IS \`the company signatory\``);
  p(`    capTable           IS \`the cap table\``);
  p();
  p("§ `The safes`");
  const names = [];
  deal.safes.forEach((s, i) => {
    const n = i + 1;
    names.push(`\`safe ${n}\``);
    p();
    p(`\`safe ${n} signatory\` MEANS Signatory WITH`);
    p(`    name  IS ${esc(s.investor.signatory?.name ?? "")}`);
    p(`    title IS ${esc(s.investor.signatory?.title ?? "")}`);
    p();
    p(`\`safe ${n} investor\` MEANS Party WITH`);
    p(`    name      IS ${esc(s.investor.name)}`);
    p(`    address   IS ${esc(s.investor.address ?? "")}`);
    p(`    email     IS ${esc(s.investor.email ?? "")}`);
    p(`    signatory IS \`safe ${n} signatory\``);
    p();
    p(`\`safe ${n} terms\` MEANS TermsIn WITH`);
    p(
      `    cap      IS ${s.terms?.cap == null ? "NOTHING" : `JUST ${num(s.terms.cap)}`}`,
    );
    p(
      `    discount IS ${s.terms?.discount == null ? "NOTHING" : `JUST ${num(s.terms.discount)}`}`,
    );
    p(
      `    mfn      IS ${s.terms?.mfn == null ? "NOTHING" : `JUST ${s.terms.mfn ? "TRUE" : "FALSE"}`}`,
    );
    p();
    p(`\`safe ${n}\` MEANS SafeIn WITH`);
    p(`    investor          IS \`safe ${n} investor\``);
    p(`    purchaseAmount    IS ${num(s.purchaseAmount)}`);
    p(`    date              IS ${esc(s.date)}`);
    p(`    terms             IS \`safe ${n} terms\``);
    p(`    proRataSideLetter IS ${s.proRataSideLetter ? "TRUE" : "FALSE"}`);
  });
  p();
  if (deal.round) {
    p("§ `The round`");
    p();
    p(
      "-- The instrument takes the Standard Preferred price as an INPUT; how a round sets",
    );
    p(
      "-- it is the term sheet's business, and this block is that convention made explicit",
    );
    p("-- (SPEC.md §6.4, ruling R7).");
    p("`the round` MEANS RoundIn WITH");
    p(`    name              IS ${esc(deal.round.name)}`);
    p(`    preMoneyValuation IS ${num(deal.round.preMoneyValuation)}`);
    p(`    newMoney          IS ${num(deal.round.newMoney)}`);
    p(`    targetPoolPercent IS ${num(deal.round.targetPoolPercent)}`);
    p(
      `    lead              IS ${
        deal.round.lead
          ? `JUST (LeadIn WITH name IS ${esc(deal.round.lead.name)}, amount IS ${num(deal.round.lead.amount)})`
          : "NOTHING"
      }`,
    );
    p();
  }
  p("§ `The deal`");
  p();
  p("`the deal` MEANS Deal WITH");
  p("    form    IS `the form`");
  p("    company IS `the company`");
  p(`    safes   IS LIST ${names.join(", ")}`);
  p(`    round   IS ${deal.round ? "JUST `the round`" : "NOTHING"}`);
  p();
  p("§ `What the instrument decides`");
  p();
  p("-- Empty means the deal can be filled onto the published form it names.");
  p("#EVAL `validate deal` `the deal`");
  p();
  p("-- The Equity Financing conversion of the whole portfolio (§1(a)).");
  p("#EVAL convert `the deal`");
  p();
  return L.join("\n");
}
