# Source licence — quoted material

This encoding quotes two kinds of source, and they carry different terms.

## 1. Government announcements and administrative pages

| document | retrieved from |
| --- | --- |
| National Day Rally 2026 speech (English) | https://www.pmo.gov.sg/newsroom/ndr2026/ |
| SG Child Support Package | https://www.life.gov.sg/family-parenting/benefits-support/sg-child-support-package |
| Marriage & Parenthood measures at NDR 2026 | https://www.population.gov.sg/marriage-parenthood-measures-at-national-day-rally-2026/ |
| Baby Bonus Scheme | https://www.madeforfamilies.gov.sg/support-measures/child-raising/financial-support/baby-bonus-scheme |
| Large Families Scheme | https://www.madeforfamilies.gov.sg/support-measures/child-raising/financial-support/large-families-scheme |

All five were retrieved on **25 August 2026** and each is pinned by a `sha256` over the retrieved
bytes in [`registers/source-bundle.json`](registers/source-bundle.json). They are Singapore
Government material and remain subject to the terms of the sites that publish them.

## 2. Singapore legislation

The **Child Development Co-Savings Act 2001** is quoted for ss 12B, 12C and 12CA. Singapore
Statutes Online (`sso.agc.gov.sg`) answers HTTP 403 to non-browser clients, so the text was
retrieved through the `lawplain` statutes corpus (`act_id` `CDCSA2001`, kind `act_current`) on
25 August 2026, and the digest in the source bundle is over the JSON document that fetch returned —
the artifact the encoding was actually read from. Singapore legislation is Crown/Government
copyright; the official version is the one SSO publishes, not the copy here.

**Quotation is for the purpose of building and evidencing a faithful computational encoding**, and
every quotation is extracted mechanically from retrieved text rather than retyped.

## 3. What is licensed to you

The **encoding** — the `.l4` modules, registers, case suite, app, OpenFisca projection and report —
is the contribution of the maintainer named in `encoding.json` and is licensed under
**Apache-2.0** per the repository `NOTICE`. That licence covers the encoding only and makes no
claim over the announcements or the legislative text.

## 4. Read this before relying on any of it

**The SG Child Support Package is an announcement, not law.** No Bill has been introduced and the
Act is unamended. Every figure this encoding produces at a rule date on or after 1 April 2027
states a policy intention, and any of it may change before — or instead of — being legislated.

**This is not legal advice.**
