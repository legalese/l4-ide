// The conversion schedule, rendered from the L4 result.
//
// SPEC.md §5.5, ruling R10: the instrument has a publisher's text and the form is its own
// renderer, but the schedule has NO publisher's text — it is a document the arithmetic
// produces — so this is the one place the generator writes prose of its own. When
// Export.Document's house style can carry arithmetic tables it should take this job.
//
// Rounding is display-only. `convert` keeps exact rationals and rounds share counts down
// once, at the end (fork F3); the numbers below are those values shown to the precision
// the User Guide prints — whole shares, four decimals for a price, two for a percent —
// and conversion.json beside this file carries them unrounded.

import { groupDigits } from "./fill.mjs";

// Down, not to nearest: the User Guide rounds share counts DOWN (fork F3), and the
// encoding already floors the counts it computes. Company Capitalization is the one
// figure here that is still fractional, and the guide prints 11,764,705 for 11,764,705.88.
const shares = (n) => groupDigits(Math.floor(n));
const pct = (n) => `${n.toFixed(2)}%`;

function money(n, symbol, dp = 2) {
  const x = Number(n);
  const whole = Math.trunc(x);
  const g = String(Math.abs(whole)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const frac = Math.abs(x - whole)
    .toFixed(dp)
    .slice(1);
  return `${x < 0 ? "-" : ""}${symbol}${g}${dp ? frac : ""}`;
}

export function currencySymbol(jurisdiction) {
  // The US forms print `$` before the amount blanks and SG/CA/KY print `US$`
  // (SPEC.md §3.1); the schedule follows the instruments it summarises.
  return jurisdiction === "us" ? "$" : "US$";
}

function table(headers, rows, align = []) {
  const sep = headers.map((_, i) =>
    align[i] === "r" ? "---:" : align[i] === "c" ? ":---:" : "---",
  );
  return [
    `| ${headers.join(" | ")} |`,
    `| ${sep.join(" | ")} |`,
    ...rows.map((r) => `| ${r.join(" | ")} |`),
  ].join("\n");
}

function terms(row, $) {
  if (row.cap > 0) return `${$}${groupDigits(row.cap)} post-money cap`;
  if (row.discountRate > 0)
    return `${row.discountRate.toFixed(0)}% Discount Rate`;
  return "MFN, no cap or discount";
}

export function conversionSchedule(deal, conversion, meta = {}) {
  const $ = currencySymbol(deal.form.jurisdiction);
  const roundName = deal.round?.name ?? "the Equity Financing";
  const L = [];
  L.push(`# Conversion schedule — ${roundName}`);
  L.push("");
  L.push(
    `**${deal.company.name}** · ${deal.safes.length} Post-Money Safe${deal.safes.length === 1 ? "" : "s"}` +
      ` · prepared ${meta.at ?? new Date().toISOString().slice(0, 10)} by \`etc/safe/gen.mjs\`` +
      `${meta.row ? ` over encoding row \`${meta.row}\`` : ""}`,
  );
  L.push("");
  L.push(
    "This schedule is not part of any Safe. It states what the Safes' own arithmetic",
    "produces at the round described below, and the round convention it assumes is the",
    "term sheet's, not the instrument's: a Safe takes the lowest price per share of the",
    "Standard Preferred Stock as an **input**.",
  );
  L.push("");

  L.push("## The round");
  L.push("");
  if (deal.round) {
    const r = deal.round;
    L.push(
      table(
        ["parameter", "value"],
        [
          ["Round", r.name],
          ["Pre-money valuation", money(r.preMoneyValuation, $, 0)],
          ["New money", money(r.newMoney, $, 0)],
          [
            "Target available option pool after closing",
            pct(r.targetPoolPercent),
          ],
          ...(r.lead
            ? [
                [
                  "Lead investor",
                  `${r.lead.name}, ${money(r.lead.amount, $, 0)}`,
                ],
              ]
            : []),
          [
            "Standard Preferred price per share",
            money(conversion.standardPrice, $, 4),
          ],
          [
            "Option pool increase",
            `${shares(conversion.optionPoolIncrease)} shares`,
          ],
          ["New-money shares", `${shares(conversion.newMoneyShares)} shares`],
        ],
      ),
    );
  } else {
    L.push(
      "No round is described in this deal, so no Standard Preferred price exists. Only",
      "Safes with a Post-Money Valuation Cap convert, and they convert at their cap.",
    );
  }
  L.push("");

  L.push("## Company Capitalization");
  L.push("");
  const ct = deal.company.capTable;
  L.push(
    table(
      ["component", "shares"],
      [
        ["Capital Stock issued and outstanding", shares(ct.commonOutstanding)],
        ["Options issued and outstanding", shares(ct.optionsOutstanding)],
        ["Promised Options", shares(ct.promisedOptions)],
        [
          "Unissued Option Pool, before the round's increase",
          shares(ct.unissuedOptionPool),
        ],
        [
          "**Converting Securities (this and every other Safe)**",
          "*the fixpoint*",
        ],
        [
          "**Company Capitalization**",
          `**${shares(conversion.companyCapitalization)}**`,
        ],
      ],
      ["", "r"],
    ),
  );
  L.push("");
  L.push(
    "*“Company Capitalization … Includes all Converting Securities”, and Converting",
    "Securities include this Safe — so the denominator of the Safe Price contains the",
    "shares the Safe Price determines. The figure above is the solution of that equation,",
    "asserted against the User Guide's own worked example in the encoding row's cases.*",
  );
  L.push("");

  L.push("## The Safes");
  L.push("");
  L.push(
    table(
      [
        "Investor",
        "Purchase Amount",
        "Terms",
        "Method",
        "Safe Price",
        "Conversion price",
        "Shares",
        "Series",
      ],
      conversion.rows.map((r) => [
        r.investor,
        money(r.purchaseAmount, $, 0),
        terms(r, $),
        r.method,
        r.safePrice > 0 ? money(r.safePrice, $, 4) : "—",
        r.conversionPrice > 0 ? money(r.conversionPrice, $, 4) : "—",
        shares(r.shares),
        r.series,
      ]),
      ["", "r", "", "", "r", "r", "r", ""],
    ),
  );
  L.push("");
  L.push(
    "*Method* is which limb of §1(a) governs: **cap** means the Purchase Amount divided",
    "by the Safe Price (Safe Preferred Stock); **price** means the Purchase Amount divided",
    "by the lowest Standard Preferred price; **discount** means the Discount Price. §1(a)",
    "gives the investor the greater of the two, so the choice is the arithmetic's, not the",
    "parties'.",
  );
  L.push("");

  L.push("## Pro rata rights");
  L.push("");
  if (conversion.proRata.length === 0) {
    L.push(
      "No Safe in this deal carries a Pro Rata Side Letter, or no round price exists to",
      "exercise it against.",
    );
  } else {
    L.push(
      table(
        ["Investor", "Pro rata share", "Shares", "Amount"],
        conversion.proRata.map((p) => [
          p.investor,
          pct(p.percent),
          shares(p.shares),
          money(p.amount, $, 2),
        ]),
        ["", "r", "r", "r"],
      ),
    );
    L.push("");
    L.push(
      "*The pro rata share is the ratio of the Capital Stock issued from the Investor's",
      "Safes with a Post-Money Valuation Cap to the Company Capitalization, applied to the",
      "Standard Preferred sold in the round.*",
    );
  }
  L.push("");

  L.push("## Cap table after the round");
  L.push("");
  L.push(
    table(
      ["Holder", "Common", "Preferred", "Plan", "Total", "Fully diluted"],
      conversion.capTableAfter.map((r) => [
        r.holder,
        r.common ? shares(r.common) : "—",
        r.preferred ? shares(r.preferred) : "—",
        r.plan ? shares(r.plan) : "—",
        shares(r.total),
        pct(r.fullyDilutedPercent),
      ]),
      ["", "r", "r", "r", "r", "r"],
    ),
  );
  L.push("");

  L.push("## Notes");
  L.push("");
  for (const n of conversion.notes) L.push(`- ${n}`);
  if (conversion.notes.length === 0) L.push("- (none)");
  L.push("");
  L.push(
    "Shares are shown whole and rounded down, prices to four decimals and percentages to",
    "two, which is the User Guide's own practice; `conversion.json` beside this file",
    "carries the unrounded values the encoding computed.",
  );
  L.push("");
  return L.join("\n");
}

/**
 * The Liquidity Event settlement (§1(b) and the §1(d) priority).
 *
 * Like the conversion schedule this has no publisher's text; unlike it, the two figures
 * it needs beyond the cap table — what ranks ahead of the Safes, and how many Promised
 * Options are "to the extent receiving Proceeds" — are deal-specific and the form leaves
 * them open, so the header states the ones the run was given.
 */
export function liquiditySchedule(deal, event, result, meta = {}) {
  const $ = currencySymbol(deal.form.jurisdiction);
  const L = [];
  L.push("# Liquidity Event settlement");
  L.push("");
  L.push(
    `**${deal.company.name}** · ${deal.safes.length} Post-Money Safe${deal.safes.length === 1 ? "" : "s"}` +
      ` · prepared ${meta.at ?? new Date().toISOString().slice(0, 10)} by \`etc/safe/gen.mjs\`` +
      `${meta.row ? ` over encoding row \`${meta.row}\`` : ""}`,
  );
  L.push("");
  L.push(
    "A Change of Control, Direct Listing or initial public offering. §1(b) gives each",
    "Investor the greater of its Cash-Out Amount and the amount payable on its Conversion",
    "Amount, and §1(d) decides who is paid first when the Proceeds do not cover everyone.",
  );
  L.push("");
  L.push("## The event");
  L.push("");
  L.push(
    table(
      ["parameter", "value"],
      [
        ["Proceeds legally available for distribution", money(event.proceeds, $, 0)],
        ["Indebtedness and creditor claims ranking ahead", money(event.indebtedness, $, 0)],
        ["Promised Options receiving Proceeds", shares(event.promisedOptionsReceivingProceeds)],
        ["**Liquidity Capitalization**", `**${shares(result.liquidityCapitalization)}**`],
        ["Consideration per as-converted share", money(result.perShareConsideration, $, 4)],
      ],
    ),
  );
  L.push("");
  L.push("## What each Safe takes");
  L.push("");
  L.push(
    table(
      [
        "Investor",
        "Purchase Amount",
        "Method",
        "Liquidity Price",
        "Conversion shares",
        "Entitlement",
        "Paid",
      ],
      result.rows.map((r) => [
        r.investor,
        money(r.purchaseAmount, $, 0),
        r.method,
        r.liquidityPrice > 0 ? money(r.liquidityPrice, $, 4) : "—",
        r.conversionShares ? shares(r.conversionShares) : "—",
        money(r.entitlement, $, 2),
        money(r.paid, $, 2),
      ]),
      ["", "r", "", "r", "r", "r", "r"],
    ),
  );
  L.push("");
  L.push(
    "*Method* is which limb of §1(b) the Investor takes: **cash-out** is the Purchase",
    "Amount back; **convert** is the amount payable on the Purchase Amount divided by the",
    "Liquidity Price. The choice is the greater of the two, so it is the arithmetic's.",
    "*Paid* differs from *Entitlement* only when the Proceeds run out under §1(d).",
  );
  L.push("");
  L.push("## Notes");
  L.push("");
  for (const n of result.notes) L.push(`- ${n}`);
  if (result.notes.length === 0) L.push("- (none)");
  L.push("");
  L.push(
    "Shares are shown whole and rounded down and money to two decimals;",
    "`liquidity.json` beside this file carries the unrounded values.",
  );
  L.push("");
  return L.join("\n");
}
