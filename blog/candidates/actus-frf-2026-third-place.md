---
title: The other half of a financial contract
status: outline
date: 2026-09-21
facet: formal-methods-in-law/ (or case-studies/; Meng's call)
words: 0
license: CC-BY-NC-4.0
sources_checked: 2026-09-21 (repo, report and transcripts only; nothing external)
---

**STATUS 2026-09-21 (evening): OUTLINE, NOT A DRAFT.**
No prose has been written.
This file records the ACTUS competition work of November 2025 to March 2026 and the shape a post could take.
It sits in `blog/candidates/` because it carries no arc number and `check-post.sh` would fail it on `status:` and length.
Whoever adopts it assigns the number, flips `status:` to `draft`, and moves the file.
Every fact below names where it was read.
The evening revision replaced the first draft's guesses with what the submission itself says: the technical report, the tagged repository and the meeting transcripts were all found and read on 2026-09-21.
The `[NEEDS MENG]` markers that remain are the ones only a team member can settle.

---

## What was actually submitted, and where it is

This section exists because the first draft of this outline did not know, and guessed.

- **The technical report.** "Comprehensive, Standardized, Machine-Readable Contract Representation", M. Flood, E. Kendall, P. Rivett, M. Wilson and M. Wong, "Report for the ACTUS Algorithmic Financial Contracts Use Case Competition", dated 2026-03-16, nine sections, about 3,100 words.
  The copy at `GoogleDrive-mengwong@legalese.com/My Drive/2026 ACTUS Use Case/FloodETAL_ACTUSContractRepresentation_TechReport.docx` (modified 17 March) carries Pete Rivett's corrected affiliation, which he committed to the repository at 00:36 UTC on 17 March, so it is the post-final-edit version.
  The file of the same name in the local clone's `doc/` is a mislabelled copy of the 4 February tech sketch (913 words, "Version 1.2"); do not cite it.
- **The code.** <https://github.com/ACTUS-FIBO/actus2026>, public, tagged `actus_challenge_submission` at commit `cd99a037`, Pete Rivett's merge of 2026-03-17T00:39Z.
  Local clone at `~/src/actus-fibo/actus2026`.
  The 12 March working meeting agreed the deliverables were a technical report uploaded as PDF or Word through APIX's web form, a public repository URL with a tagged release so that reviewers evaluate a fixed version, and an optional video which Mark said there was no way to make in time.
  Source: `meeting notes and transcripts/ACTUS Challenge Working Meeting_20260312/Transcript…txt`, summary paragraph and lines 37 to 42, 264, 292 to 295, 376.
- **Who pressed the button, and when.** Mark Flood, through APIX's web form, confirmed by an automated "Solution Submitted" email from no-reply@apixplatform.com at 01:58 UTC on 17 March 2026 for the entry titled "Benefits of ACTUS-enabled financial literacy"; Mark forwarded it to the team at 19:00 Eastern on 16 March with the words "We're in!"
  Elisa: "Congratulations!! Thanks everyone for all of the hard work and last minute push."
  Matt: "Yall did a lot in a short time. Great to watch it unfold."
  Mark then asked Matt to have Tram Chase at SimVentions make the repository public and freeze a branch named `actus_challenge_submission` "so that we can continue tinkering without interfering with what the ACTUS reviewers will see"; Matt confirmed on 17 March that the repos were public.
  Source: thread "Solution Submitted for Benefits of ACTUS-enabled financial literacy", forwarded from mengwong@legalese.com to gmail.com on 2026-09-21.
- **The proposal round.** Mark submitted the five-page proposal through the same form on 15 December 2025 (APIX confirmation 19:20 UTC), team name "ACTUS Expanders", problem statement "#4 Standards and Education", roles as entered: Mark lead and online training, Elisa and Pete ontology development, Matt production deployment, Meng "computable contract representation".
  Mark's email of 16 December records exactly how the five-pager was cut into the form's 2,000-character boxes, and is the source for the proposal's wording if the report's differs.
  Meng to Michael Fairweather and Thomas Gorissen, 23 December: "This might get us some good exposure and/or serve as cred if we come out with a good showing."
  Source: threads "Proposal Submitted for ACTUS Algorithmic Financial Contracts Use Case Competition" and "APIX / ACTUS submission", forwarded 2026-09-21.
- **The result.** APIX's Instagram announcement of 20 May 2026: 113 registrations from 19 countries, six winners, the team one of two third-place entries under "ACTUS Enhancements & Education".
  Saved to `blog/assets/actus-frf-2026/` with a README.

## How it started

Mark Flood's email of 26 November 2025 to Meng and Elisa Kendall: the team "will be submitting a proposal for the ACTUS Competition", integrating "(a) ACTUS for cash flow structures (the term sheet, basically); (b) L4 for the other legal terms and conditions; and (c) FIBO for accounting and compliance standards", with the FX master agreement as the proof of concept and a five-page limit on proposals.
Meng's reply the next morning: "Yes, I'd be interested. Can't promise anything but I gather the nature of this competition isn't life-or-death."
Mark: "Your first assignment is to insert a good, succinct description of L4."
Source: gmail.com thread "ACTUS competition", read 2026-09-21.
The prehistory is a monthly "Computable Contracts" call among Meng, Mark, Elisa and Chris Clack running since at least January 2025, where Mark flagged the APIX hackathons on 9 October 2025 and the ACTUS challenge kickoff of 15 October.
Source: gmail.com thread "This week's meeting".

The team: Mark Flood (ProBanker Simulations; formerly a founder of the Committee to Establish a National Institute of Finance), Elisa Kendall (Thematix Partners, lead ontologist for FIBO at the EDMA), Pete Rivett (Intuitive, knowledge graph practice), Matt Wilson (SimVentions) and Meng Weng Wong (Legalese / SMU).
Source: report §2, which has a paragraph on each and is the wording to lift from.

## The claim, in one sentence

ACTUS can tell you every cash flow a contract promises, and it says nothing about what happens when a party stops paying; that other half of the contract is the law, and we showed it can be made just as machine-readable, served as an API, and called from the same simulation as the cash flows.

The reader who should repeat this to a colleague is a programmer in a bank, or anyone who has heard "smart contract" and assumed the cash-flow schedule was the whole contract.

## Cold open (beat 0): the cherry-pick, with the submitted numbers

A bank fails.
It has four open foreign-exchange contracts with a counterparty, two in the money and two out.
Its administrator performs on the two favourable ones and lets the other two lapse.
Under cherry-picking the defaulting bank collects $160,000 in gains and avoids $350,000 in losses, a net benefit of $510,000 at the counterparty's expense.
The 1997 International Foreign Exchange Master Agreement anticipated it.
Section 5.1(a) lets the non-defaulting party close out "all, but not less than all" outstanding currency obligations, and §5.1(b)(iii) nets them "into a single liquidated amount payable by one Party to the other".
All four contracts go into one liquidation and the defaulting party owes $190,000.
The report's sentence: "The cherry-picking is defeated by $700,000."
Source: report §3 "Cherry-picking demonstration"; the scenario is `src/py/cherry_picking_demo.py`, which calls the live L4 netting endpoint and falls back to local arithmetic with `--local-only`.
These are designed figures on four made-up contracts, and the post says so in the same sentence it uses them.

Then back out to the claim: ACTUS knows the four cash flows; it does not know section 5.1.

## Beat 1: what was built

**Three standards, three professions.**
Mark's framing from the proposal, worth keeping in his words: a financial contract serves the portfolio manager who needs the cash flows (ACTUS), the accountant who needs the classification (FIBO), and the lawyer who needs to know how a court will read it on default (L4).
Source: proposal §2; report §1 restates it.
The proposal says this three-way integration "has never been attempted"; quote it as their claim, not ours.

**Three queries, one per standard.**
This is the submitted structure and the post should use it as its spine.
Given a NetworkX network of banks and IFEMA-governed FX contracts (Mark's `fxnet.py`, one currency pair USD/GBP, maturities T+2, T+30, T+60, T+90, forwards paired with an offsetting spot to make swaps):

1. L4: which transactions in the network are implicated by cross-default when one named bank defaults? (`findCrossDefaults`, IFEMA §5(x) with the Schedule's Threshold Amount.)
2. ACTUS: what are the aggregate settlement volumes at each maturity, with and without that default? (FXOUT contracts through the ACTUS contract server, Docker, port 8083.)
3. FIBO: which regulators in the US and Great Britain are implicated? (SPARQL over a 3,500-triple subset, LEI → legal entity → functional entity → regulator; Barclays resolves to FCA, PRA, EBA and ECB.)

Source: report §1 and §3 to §5.
Mark's notebook, `src/jup/actus.ipynb`, runs the pipeline over 13 institutions, 3 in New York and 10 in London; the 15 March session report records the L4 call returning Société Générale NY's cascade across 3 master agreements and 12 transactions.

**The IFEMA encoding.**
About 1,750 lines of L4 across 11 modules by the report's count (5,717 lines across 13 files in the submitted tree, which includes the two API modules), one per section of the agreement.
First commit 23 January 2026, from a Claude Code session whose transcript is in the repository (`transcripts/2026-01-23/`).
The rule to show: `FX Transaction`, the first obligor MUST deliver, HENCE the counterparty delivers, LEST delivery default with a two-day cure, LEST event of default, whereupon the non-defaulting party MAY issue a close-out notice.
Source: `ifema/ifema-main.l4` lines 210 to 269.
The report's own phrasing: each decision point "branches into HENCE (comply) and LEST (violate) consequences, forming a game tree of strategic choices", which "captures the distinction between what a party should do under the contract and what they actually do".
That is the sentence a programmer will remember.

**The two endpoints, and the fact that they are still up.**
`findCrossDefaults` and `computeCloseOutNetting` were deployed to `dev.jl4.legalese.com` on 15 March by zipping the `.l4` files and POSTing them to jl4-service, which discovers `@export` functions and generates the JSON schema from the L4 types.
Checked 2026-09-21: both deployments are listed on the service (redeployed 2026-07-27), and the SPARQL endpoint answers.
Source: session report of 2026-03-15; `curl https://dev.jl4.legalese.com/service/deployments/`.
One engineering detail worth a sentence: the first netting deployment had an O(2^n) blow-up and was fixed by moving the currency list into the input (commit `527c4fc`, 15 March).

**The pragma distinction.**
Sections 4, 6, 7, 8 and 9 (representations, force majeure, expertise, miscellaneous, jurisdiction) are encoded not as executable logic but as what the encoding's README calls pragmas: instructions to the court rather than to the parties.
Governing law selects an interpreter; jury waiver disables a feature; severability is partial-invalidity handling.
Source: `ifema/README.md`.
This did not make the report and is the one genuinely new idea in the encoding; it deserves a paragraph, with the concession that it is an analogy.

**FIBO's side, in their words.**
Elisa wrote report §5 and §6: three new FIBO ontologies for ACTUS (taxonomy, data dictionary, applicability mapping) scheduled for the 2026Q1 FIBO release the week of 30 March 2026, plus example bank individuals with LEIs and regulatory relationships under FBC/FunctionalEntities.
Pete's `ACTUS-examples.ttl` carries a real HSBC/Infosonics FX master agreement from SEC EDGAR.
Meng built the SPARQL endpoint (rdflib and Flask, commit `6cff543`, 16 March) that serves Elisa's data; Pete removed a dependency on FIBO's SEC-215 module the night before the deadline.
`[NEEDS MENG]` Elisa and Pete should be asked what they want said; the post should quote §5 rather than paraphrase their ontology work.

**The ACTUS library that outlived the competition.**
Seven files, about a thousand lines, in `jl4-core/libraries/actus*.l4`, committed 28 January 2026 and shipped in the L4 standard library with a golden test and a reference page.
Source: `git log -- jl4-core/libraries/actus.l4`; `doc/reference/libraries/actus.md`.

## Beat 2: what it cost, and who could do it

The L4 side of the entry was one person with Claude Code and the L4 skill, and the timeline is in the commit log: the IFEMA encoding in one session on 23 January; nothing on the L4 side from 6 March to 14 March; then the two endpoints, the Python bridge, the diagrams, the README walkthrough and the SPARQL server between 04:25 UTC on 15 March and 15:26 UTC on 16 March, twenty-one commits, with Mark's notebook landing in between.
Source: `git log` of `ACTUS-FIBO/actus2026`.
The 15 March session report is addressed to the team and the reviewers and is the honest account; the post can quote it.

The four open questions Pete raised in his FIBO example make a good device here, because L4 answered each of them without trying to.
"Not really an event until it happens": MAY is a potential event and DOES is an actual one.
"Which leg is the quantity on": both legs are parameters.
"Is a grace period valid without a start date": WITHIN 2 is anchored to the obligation it qualifies.
"We may need a class for potential events": a MUST that times out is the LEST branch.
Source: README, "Pete's Open Questions".

## Beat 3: what the evidence does not show

**Novation netting could not be expressed.**
IFEMA §3.3 says that when two obligations in the same currency for the same value date arise between the same offices, each is "automatically and without further action" cancelled and replaced by one netted obligation.
L4's obligations are syntax, not values: nothing in the language can pattern-match on "all obligations sharing a currency and value date", cancel them and create a new one.
The team wrote a spec proposing obligations as first-class values (`doc/specs/HOMOICONICITY-SPEC.md`, in the submitted tree) and did not build it.
`[NEEDS MENG]` Has anything since closed this, or is it still open?

**The close-out netting that ran is the simplified one.**
The session report says so in terms: the deployed `computeCloseOutNetting` nets receivables and payables per currency, and omits the interest accrual on past-due obligations, present-value discounting and conversion to base currency that the full §5.1(b) requires; that logic sits in `ifema-section5-closeout.l4` and was not the endpoint.
The report's "Findings" section lists "deeper analysis and experimentation of the close-out netting functionality" as future work.

**Cross-default was a modelling choice, not a reading of the text.**
The README's own walkthrough concedes that FX delivery obligations are arguably not "Specified Indebtedness" ("borrowed money") under §5(x), so a pure reading might not cascade at all; the encoding gates the cascade on the Schedule's Threshold Amount as a modelling choice and says so.
Source: README §"Step 2" and "Modeling Choice: Threshold-Gated Cross-Defaults".
This is the paragraph a lawyer will look for, and it should be in the post rather than left for them to find.

**The numbers are synthetic.**
The banks are simulated, the network is generated with a seed, the cherry-pick contracts are designed, and US regulatory relationships in FIBO were "in progress" at submission (10 of 10 GB/EU banks mapped, US partial).
Source: report §1, §5 "Data coverage".

**The jury saw a proof of concept.**
Third place, in a category named "Enhancements & Education".
Say what that means: the entry showed the integration was possible and taught something about it; it did not run a bank's book.

## Hand off

The facet is not settled.
`formal-methods-in-law/` fits if the post leans on the game tree and the comply-or-breach argument.
`case-studies/` fits if it is written as a case, like the Jersey charities work.
Post 6 (the missing test suite) argues that a runnable reference test is what statutes lack; the ACTUS reference tests are a second example of the same thing and this post can point at post 6 rather than re-argue it.
Checked 2026-09-21: post 6 does not mention ACTUS, so there is no overlap to manage.

## Sources read on 2026-09-21

- The Instagram post and caption, <https://www.instagram.com/p/DYi-0DxE5tu/>.
- The technical report, Drive copy named above; converted with pandoc, 3,134 words.
- `ACTUS-FIBO/actus2026` at tag `actus_challenge_submission`: `README.md`, `doc/session-report-2026-03-15.md`, `doc/l4-section-for-report.md`, `src/py/cherry_picking_demo.py`, `ifema/*.l4`, `doc/specs/HOMOICONICITY-SPEC.md`.
- Meeting transcripts in the Drive folder: 5 March (chat and transcript), 10 March check-in, 12 March working meeting.
  Meng does not appear in the 10 or 12 March transcripts; the 12 March one names Mark, Elisa, Pete and Matt.
- gmail.com threads "ACTUS competition" (26 and 27 November 2025) and "This week's meeting" (August to October 2025); everything else native to that mailbox is calendar traffic.
- Three threads Meng forwarded from mengwong@legalese.com on 2026-09-21: the proposal-submitted confirmation of 15 December 2025, Mark's "APIX / ACTUS submission" form transcript of 16 December, and the solution-submitted confirmation of 17 March 2026 with the team's replies.
- The proposal, `proposal/FloodETAL_ComprehensiveStandardizedMachineReadableContractRepresentation.pdf`.
- `l4-ide/specs/done/ACTUS-L4-BRIDGE-SPEC.md` and `doc/reference/libraries/actus.md`.

Not yet checked: IFEMA §3.3 and §5.1 against the New York Fed's PDF (the quotations above are as the report and README quote them); the ACTUS reference test `fxout03` figure of 738.80 USD that the README cites.
