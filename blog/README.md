# The L4 blog — prefiguring the papers

**STATUS 2026-09-14 (evening): DRAFTING.** Posts 1, 2, 3 and 5 have been machine-drafted, critiqued
by six reader personas and a live fact-check, revised, and gated; posts 4 and 6 have machine drafts
with critiques gathered and revision pending; 7, 8, 9 and S1 are not yet drafted. No post has been
read by Meng. Every draft says so in its first
line. This directory holds the style guide and the posts. It is the companion to [`paper/`](../paper/): each post puts one of the
papers' positions in front of a general technical reader before the academic version lands. See
[`STYLE.md`](STYLE.md) for who that reader is and how a post is written.

## The arc

Nine posts and one standalone. The facet column names the `paper/` directory each post
prefigures. The arc has already changed once (7 posts → 8) as material arrived; treat it as live.

| #  | Working title                       | Facet                                                       |
| -- | ----------------------------------- | ----------------------------------------------------------- |
| 1  | We found a race condition in a law  | `icail/` (motivation)                                       |
| 2  | Three bets on legal AI              | `icail/` + Kant et al. replication                          |
| 3  | Specs are code                      | `cnl-affordances/`                                          |
| 4  | What the compiler checks            | `cnl-affordances/` + `icail/` §5; absorbs `bounded-deontics/` |
| 5  | The white-hat Bad Man               | `formal-methods-in-law/`                                    |
| 6  | The missing test suite              | `formal-methods-in-law/` §6 + backend portfolio             |
| 7  | When the code is the law            | tax-as-code; bitemporal substrate (added 2026-09-13)        |
| 8  | What formalization can't do         | `cls-determinacy-frontier/`                                 |
| 9  | One statute at a time _(working title)_ | the call to action — no facet of its own (added 2026-09-14) |
| S1 | Seeing like a citizen               | `political-economy/` — standalone, runs any time            |

## Framing constraints

Things a post must say, or must not claim, recorded when they were decided so a later drafter
does not have to rediscover them.

- **Post 1.** We are not claiming incompetence on the part of the legislative drafters. The race
  condition in the regulations turned out to be documented in the accompanying guidance, which
  ameliorated it in practice. The claim is that our methods found it from the text of the rules
  alone — which is both the more defensible claim and the more interesting one, since it is the
  reader without the guidance who is caught. Both halves go in the post. And the gap is bridged
  in more than one direction: found at drafting time, the same race condition could have been
  fixed in the regulations themselves, earlier, rather than afterwards in guidance that is
  effectively a practice direction — a patch beside a binding text that still carries the
  contradiction. The offer is to the drafters as much as to the reader. (Meng, 2026-09-13.)

  **The double bind's shape and what ran the search — Meng, 2026-09-14, answering the post's
  `[NEEDS MENG]` markers 1 and 2. Use these; the instrument stays unnamed.** His words: "in the
  event of a data breach which has been assessed as being a notifiable data breach, the
  organization must notify, as soon as possible, both the affected parties (users whose data was
  exposed) and the government regulator. The government regulator may some time later advise the
  organization to not advise the affected parties, presumably because major breaches call for
  disaster management in some way, or maybe the breach was tied to a state sponsored actor and
  geopolitical concerns may require a temporary pretense that the breach did not occur. I say
  'presumably because' as I'm speculating from my own world knowledge, not from any direct
  knowledge. That places the organization in a double bind: you must notify, and you must not
  notify. Even if we read this with 'lex posterior' framing so that the organization stops
  notifying users the moment they hear from the regulator, as a whole the system has already
  leaked the fact that the breach was detected so somewhere some high level goal is going unmet."
  On the tooling: "This analysis was done with an early version of our language and the UPPAAL
  encoding was performed manually once the fragment of the regulation was understood." So the
  post must say the UPPAAL model was hand-built from the understood fragment, not emitted by a
  compiler — and that the reproduction is cheap today (write the L4; lower it to a timed
  backend per `specs/proposals/VERIFICATION-BACKEND-LOWERING-SPEC.md`, which is a proposal with
  Phase 1 ruled and nothing built). The regulator's reasons are Meng's speculation and are
  reported as such or left out. Replace the spec's remediate/assessment fragment in the opening
  with this real shape, names filed off.
  **The year, and the paper — Meng, 2026-09-14: "the data-breach pilot was conducted 2022";
  verified the same day.** The instrument is Singapore's Personal Data Protection Act, the data
  breach notification obligation (the repos call it PDPA DBNO). Evidence: `smucclaw/dsl`
  (`caseStudies/PDPA/README.org` created 2021-07-19; the `pdpadbno-*` encodings and parser tests
  carry 16 commits in 2022 and 29 in 2023); `smucclaw/vue-pure-pdpa`, the web wizard behind
  <https://smucclaw.github.io/mengwong/pdpa/> (first commit 2021-09-12; 185 commits in 2022); and
  the paper: Avishkar Mahajan, Martin Strecker, Seng Joe Watt and Meng Weng Wong, "Compliance
  through model checking," International Workshop on AI Compliance Mechanism (WAICOM 2022),
  December 2022, SMU InK <https://ink.library.smu.edu.sg/cclaw/3/> (accepted version, CC
  BY-NC-ND 4.0; record read 2026-09-14). Its abstract: "we describe part of a case study about
  Singapore's Personal Data Protection Act, which we first presented informally, then formally as
  interacting Timed Automata. From these, we derive desiderata on a language and verification
  framework for reasoning about compliance." So the post can now name the instrument (the PDPA
  and its breach-notification obligation — the agency stays unnamed only if Meng still wants it
  so; the paper is public), give the year (2022), and cite the paper for the timed-automata
  model. "Interacting Timed Automata" is the paper's phrase for the UPPAAL model; whether the
  paper prints the trace or a figure is for the drafter to check in the PDF (InK sits behind a
  bot wall for curl; open it in a browser). Note the site is a Vue app whose bundle contains the
  strings "notifiable data breach?" and "notify?".
  **OPEN — a discrepancy the drafter must not resolve alone (found 2026-09-14 by the gate).**
  `paper/formal-methods-in-law/FORMAL-PAPER.md` §4.4 lists TWO exhibits: "PDPA data-breach
  notification race condition (our UPPAAL study). Interacting clocks (assessment window vs
  notify-the-regulator window) reach a state where timely compliance is impossible — a
  double-bind" AND "the government-agency race condition from our regulatory pilot — the same
  shape, in live secondary legislation affecting citizens." `paper/icail/l4-icail.tex` §Experience
  likewise calls the pilot's instrument "secondary legislation"; the PDPA is an Act. Meng's account
  of 2026-09-14 describes ONE bind — must notify the individuals and the regulator; the regulator
  may later direct not to notify the individuals — and points the "data-breach pilot" at the PDPA
  wizard repo. So either (a) the WAICOM study and the government-agency pilot are one engagement
  described twice, or (b) they are two, with two different binds (a deontic must/must-not, and a
  clock collision). **ANSWERED — Meng, 2026-09-14 (afternoon):** "there was one engagement but
  we worked it several ways: Uppaal and then Maude. The double bind was both deontic and temporal:
  if the org notified the government then waited a while to notify the users they would
  potentially be able to comply with a non-notification notice that arrived in the interim. The
  only way to comply with a non-notification notice from the regulator is to violate the
  immediate notification requirement to the affected users. And vice versa." So: ONE engagement
  (the WAICOM study and the government-agency pilot are the same PDPA work), modeled twice
  (UPPAAL, then Maude — the Maude work is the JURIX 2023 executable-semantics line, Watt,
  Goodenough & Wong, so the post may say the same case was later re-run in Maude, citing that
  paper only for the Maude semantics, not for the PDPA result unless the drafter opens it and
  finds it there). The bind is deontic AND temporal at once, and the post should carry Meng's
  exact structure: the immediacy duty to the users and the regulator's later non-notification
  direction cannot both be satisfied; the only way to comply with either is to violate the other;
  and the one path that "complies" with both — notify the regulator, then stall on the users until
  a direction arrives — does so only by breaching the immediacy requirement in the interim, which
  is why a static read misses it and a timed model finds it. FORMAL-PAPER.md §3/§4.4's "two
  exhibits" and "secondary legislation" are the paper's looseness, not two engagements; the
  post's marker on this point is CLOSED.
  **THE TRACE CAN BE SHOWN — Meng supplied the PDF 2026-09-14 17:32 (saved as
  `~/Dropbox/Documents/printed/Mahajan-Strecker-Watt-Wong-2022-Compliance-through-model-checking-WAICOM.pdf`;
  8 pages; a symlink of the same name sits untracked in the worktree root for the harness).** The paper prints the model: **Fig. 1**, three
  interacting timed automata — (a) Commission, (b) Individual, (c) Organisation — and **Fig. 2**, the
  UPPAAL simulator's failure trace. All four images are extracted unaltered into
  `blog/assets/waicom-2022/` with a provenance README; embed Fig. 1(c) and Fig. 2 in post 1 by
  relative path (`../assets/waicom-2022/…`) with captions naming the paper and the licence
  (CC BY-NC-ND 4.0, copyright the authors). What the paper itself records (§3.1–3.2, read
  2026-09-14) — use its words, not a paraphrase of Meng's: one clock `cl`; the breach must be
  determined notifiable within 30 days (`isNotifiable and cl <= 30`, then `cl := 0`); the
  Commission must then be notified within 3 days (`cl <= 3`, `notifyPDPC!`); the model
  sequentialises the notifications, Commission first then the individual, "a modelling choice";
  the Commission's decision to prohibit or request notification of the individual is autonomous.
  The queries: `E<> I.informed and C.notifIndivRequested` holds (the good case);
  `E<> I.informed and C.notifIndivProhibited` **also holds, and UPPAAL produces the trace of
  Fig. 2** — "It comes about because the organization has no clue at which point the commission's
  interdiction to inform the individual could intervene, and is therefore entitled to inform the
  individual as soon as a data breach is identified"; and `E<> O.breachDeterminedNotifiable and
  deadlock` holds — "no action is possible when the notification deadline of 3 days has been
  exceeded." The trace's last state is `(notifIndivProhibited, informed, individualNotified)`.
  Note the paper's own framing is "the individual is informed in spite of the commission having
  prohibited it" plus a deadlock past the 3-day deadline; Meng's "must notify and must not notify"
  is the same finding stated as a bind. Say both. Bench Q1 is thereby answered.

  **The insurer — Meng, 2026-09-14, answering marker 3. Use this.** His words: "The insurer
  reviewed what it had been doing — it had been making the larger payout, not the smaller — and
  we had to finesse the explanation of the case to management because we were acutely aware that
  the team of insurance adjusters who had been kindly assisting us with the pilot project could
  potentially be penalized for overpaying. When we presented the findings at CxO level though the
  top management simply observed that the newly discovered ambiguity of the contract may have
  exposed them to a 'Ocidental – Companhia Portuguesa de Seguros de Vida v LP, C-263/22, CJEU,
  20 April 2023' liability risk, and that clarifying the ambiguity would save them that
  liability; no mention was made of whether they would lean stricter or stay generous in future
  payouts. So the fix was at the right layer: at the abstract logic and not necessarily the
  particular algorithm." What the post may say: the insurer had been paying the generous reading;
  the finding was presented so that the adjusters who had helped were not exposed; management's
  response was about the liability an ambiguous consumer term carries, not about which reading
  to pay in future; the fix was to the wording, at the level of the logic, not to the payout
  algorithm. The CJEU citation checks out (searched 2026-09-14; EUR-Lex CELEX 62022CJ0263,
  summary at CELEX 62022CJ0263_SUM): Judgment of the Court (Ninth Chamber), 20 April 2023, on a
  reference from Portugal's Supremo Tribunal de Justiça — Directive 93/13/EEC on unfair terms in
  consumer contracts, Articles 3–6; the transparency requirement; a group payment-protection
  insurance contract; a term limiting or excluding cover that the consumer had not been informed
  of. It is a transparency-and-disclosure case about a limiting term, not a case about an
  ambiguous formula, so the post reports management's remark as their reading of their exposure
  and describes the judgment as what it is. Open the judgment before quoting it.
  **A second case, from Meng (2026-09-14): _Tay Eng Chuan v Ace Insurance Ltd_ [2008] SGCA 26**
  (Singapore Court of Appeal, CA 95/2007, decided 27 June 2008; read on eLitigation 2026-09-14).
  This one is on point for the sentence the post already carries — "an ambiguity in a policy the
  insurer wrote is, by the usual rule of construction, read against the insurer" — and can be its
  citation: the Court held that the contra proferentem rule "is particularly pertinent in
  insurance policies because these policies are invariably drafted and/or vetted by experts for
  the benefit of insurers so as to protect the latter's interest," and that an ambiguity in the
  extent of cover "should be construed against the respondent" insurer. A Singapore authority
  suits a Singapore research group.
  **SUPERSEDING CORRECTION on who raised the cases — Meng, 2026-09-14, later the same morning.** His
  words: "Let's put in both Ocidental and Tay Eng Chuan; IIRC it was our presentation to management
  at the insurer that highlighted these cases as risks, but the presentation is lost to time and I
  have only a vague memory that it was this class of suit that we mentioned as representative of
  'yes, insurers have some discretion — that's what adjusters do — but policies need to avoid
  certain classes of unpredictability, and courts have agreed.'" So: the earlier note's "management
  observed … a liability risk" is withdrawn as to attribution. The post says that *our*
  presentation put the two cases in front of management as the class of risk an ambiguous term
  carries, that the presentation is lost and this is Meng's recollection, hedged as he hedges it;
  that management's response was about liability rather than about which reading to pay; and it
  keeps the point Meng draws — adjusters exercise discretion by design; what a policy must avoid is
  a class of unpredictability courts have refused to tolerate, which is what both cases stand for.
  Both cases go in, each described as what it holds (Tay Eng Chuan: contra proferentem, ambiguity
  in cover construed against the insurer; Ocidental: transparency and a limiting term the consumer
  was not told of, under Directive 93/13). **One date check the drafter must do:** Ocidental was
  decided 20 April 2023. If the insurer pilot and its presentation predate that, the presentation
  cannot have cited it — say so, or cite Ocidental as the later authority for the same class. The
  pilot's year is a [NEEDS MENG] until he gives it. (Meng pointed at
  <https://ink.library.smu.edu.sg/cclaw/3/> for the insurance pilot on 2026-09-14, but that
  record is the PDPA model-checking paper; the CCLAW series on InK, read the same day, has no
  insurance paper — "Deontics and time in contracts: An executable semantics for the L4 DSL"
  (Watt, Goodenough, Wong, JURIX 2023) is about the Flood & Goodenough loan agreement. The
  insurance pilot's public reference, if any, is still to be supplied.) **The year, found in the
  tree 2026-09-14: 2023.** `smucclaw/usecases` (private working repo; cite only as "the
  project's working repository") carries the insurance work: 752 commits in 2023, from an
  insurance lexicon (2023-03-31) through Maude and s(CASP) experiments (April–July), a DMN
  representation (2023-07-23), the `insurance_wiki` (Aug–Oct), `joe/insurance` (506 commits from
  2023-04-10) and `ym/insurance` (195, Sep–Nov), to "L4 insurance policy encoding documentation"
  dated 24 November 2023 (`smu/L4_insurance_policy_encoding_documentation.pdf`, added by Joe
  Watt). There is also `Presentations/Presentation_2023_07_25_Eval_and_UI` (commits 25–26 July
  2023) — whether that is the management presentation Meng remembers as lost is for him to say.
  So the Ocidental date check passes: the judgment (20 April 2023) predates the pilot's
  presentations, and both cases could have been cited. The post says the insurance pilot was in
  2023; it does not name the insurer.

  **The New Zealand exercise — Meng, 2026-09-14, answering marker 4, with his May 2019 deck
  "Multi-Way Isomorphism in L4: a humble universal converter for rules as code" (Google Slides
  1U4pQFXuVAocbwzF1nPtyhxH2SBza_7nEErLPE2lnAAw; text export read 2026-09-14). Use these.** His
  words: "We did the work in a very early prototype of the L4 system; an early implementation just
  using S-expressions in raw Haskell but that was enough to buy us QuickCheck." What the deck
  shows: the scheme was the **rates rebate** (OpenFisca-Aotearoa's `rates_rebates` formula); the
  Python parser was written by Varun Patro (NUS); the prototype's S-expressions had operators
  named `SoMuchOf`, `Inxs` ("in excess of") and `IntDiv`; the bug was **the semantics of
  "excess"** — "the amount by which a exceeds b" had been coded as `a − b` where the Act means
  `max(0, a − b)`, so once combined income passed the threshold the "excess income" went negative
  and the rebate went *up*, into negative rebates; it was found by **charting the rebate over a
  grid** — combined income $12,000–$30,000 in $1,000 steps against rates of $100 upward in $100
  steps, dependants 0 — and reading the sign ("this looks wrong"; after the fix, "this now
  reflects legislative intent"); the deck credits the upstream fix to two OpenFisca-Aotearoa
  contributors by GitHub handle (@Br3nda, @Verbman); the prototype's evaluator printed an
  explanation trace in the Act's words ("560.00 — which is the lesser of …"), which the deck calls
  putting the legislation into the debugger; the repository was
  `legalese/complaw-deeptech`, path `ontologies/rules/aotearoa-haskell`; a shell prompt in the
  deck is dated 2019-05-14. So the post says: rates rebate; a grid sweep with a human reading the
  sign as the oracle (QuickCheck is Meng's recollection of what the prototype made possible — the
  deck's evidence is the grid, so attribute QuickCheck to him and show the grid); the parser is
  not in the current tree. One thing the deck's slide order leaves open: whether the chart found
  the bug or reproduced one already found upstream — say "surfaced in our chart; fixed upstream by
  …" only if Meng confirms; otherwise "the chart shows the bug; the fix landed upstream." The
  earlier "entire domain of possible scenarios" wording is retired: the domain was a grid.
  **Checked on GitHub, 2026-09-14:** the upstream fix exists — OpenFisca-Aotearoa (then
  `ServiceInnovationLab/openfisca-aotearoa`, now `BetterRules/openfisca-aotearoa`) commit
  `68d839ebbd73`, Br3nda, **2019-05-09, "Clip excess to minimum zero (excess can't be negative)"**,
  with "Tests for 2019, rates rebate: rebate, min and max" the same day — five days before the
  shell prompt in Meng's deck (2019-05-14). Cite the commit. **ANSWERED — Meng, 2026-09-14:**
  "the chart was not what prompted Br3nda's fix; they found it and we found it simultaneously;
  they found it by inspection and reasoning; we found it by lightweight formal methods." So the
  post says exactly that: two independent findings of the same defect in the same week, one by a
  maintainer reading the code, one by a grid sweep over an isomorphic encoding — and neither
  prompted the other. That is a better story than priority: the same bug, found two ways, and the
  formal way is the one that scales to the cases nobody happens to read. Do not claim the chart
  caused the fix. The prototype itself
  is public: `smucclaw/complaw` (last pushed 2024-07-10), path
  `doc/ex-nz-rates-20200909/aotearoa-haskell/` (`app/Main.hs`, `l4/from-openfisca-rr.l4`); the
  `legalese/complaw-deeptech` path in the deck is gone (404). So "the parser is not in the
  repository" becomes "not in this repository; it is in `smucclaw/complaw`, path …". Meng's closing phrase, "It was
  about computability in the NP-hard sense," is his gloss — do not put "NP-hard" in the post
  unless the claim is made precise (NP-hardness is a complexity class, and the formal-methods
  critic will ask which problem was shown hard); the substance is that the defect was in the
  logic of the term, not in any computation of it.

- **Post 9 (the call to action).** Meng (2026-09-14): "Feel like the series is lacking a call to
  action as the last post. What are we doing with these new capabilities?" Two calls, in his
  words. First: "an encoding of all the world's laws, one statute at a time: like Wikipedia but a
  Rule-ipedia; and we need volunteers to participate by running the encoding pipeline and doing
  the HG1 review. Lawyers with specialties in this area or that are obviously well placed to do
  the tweaking and ruling between forks and HG1 imprimatur. We calculate it would cost someone
  with a Claude Code subscription about \$20 to do an entire statute plus surrounding research."
  Second: "this is infrastructure. It's designed for people building the next generation of
  LegalTech products and services to add rigour — the symbolic half of a neurosymbolic hybrid
  solution. As the first flywheel of statute encodings begins to turn, and more and more encodings
  appear in legalese/canon, it begins to be progressively easier for governments and startups to
  deploy citizen and business facing solutions on top of our decision service APIs, our MCP and
  WebMCP servers, and our exported runtimes: including Catala and OpenFisca." The \$20 is Meng's
  calculation and is attributed as such; HG1 is explained from `doc/concepts/reviewing/`; the
  canon repository's own status header (a scaffold with its first subject) is respected, not
  inflated; the Wikipedia analogy is made with Wikipedia's actual quality mechanisms in view.

- **Bench marks, 2026-09-14 ~17:35–17:55** (artifact "Author queries, posts 1–5", collection
  `blog-rulings`; Meng's words verbatim where quoted). **Q1** show — the WAICOM PDF supplied; see
  above. **Q2** accept — the agency stays unnamed. **Q3 (post 2, blinding) — edit:** "tbh best
  source is the history of what we did: look in ~/src/legalese/l4wt/kant-chubb, branch
  mengwong/kant-chubb, under paper/kant-replication/" — reading order README.md (§4 "The harness"
  is the methodological core; §1 what was measured; §2 what the original's method can't support;
  §3 why our 0.889 is not yet a result), FOUNDATION.md (gold standard; §1.2 mechanical vs
  interpretive; §1.3–1.4 the Q4/Q5 disagreements; §3 what L4 can express; §3.4 scorecard),
  PROVENANCE.md (wrapper prompts verbatim; §6 disclosed gaps), source-defects.md (16 defects in the
  published fixture; D1: the policy as printed never grants coverage because Kant et al.'s
  reproduction deletes §2 BENEFITS), bench/ (bench.mjs, per-arm scripts, keys.json vs
  keys-restored.json, PREREGISTRATION-restored.md run, PREREGISTRATION-go.md specified not run).
  Encodings at jl4/examples/legal/chubb/; a copy deposited in legalese/canon at
  subjects/us/chubb-hospital-cash/. **Two warnings:** bench/PREREGISTRATION-go.md is
  result-adjacent and forbidden to encoder sandboxes — a blog reviser does not open it either; and
  the memory system is a contamination channel (FOUNDATION.md T9) — the MEMORY.md index lines for
  kant-chubb-replication and kant-guided-encoding stay finding-free; do not edit them. One finding
  is recorded only in conversation, not in a repo file (the deadline survey: all 40 Prolog + 20 L4
  trial encodings model time as integer months with no temporal machinery; the 20 guided trials
  split 5–5 on whether month 7 is inside the pending window) — the post may not cite it until it
  is in a file. **Q4 — other:** "i have asked for a push and pr. you can cite the PR." — the post
  cites the PR: **legalese/l4-ide#387**, "paper(kant-replication): replicate Kant et al. 2025 with
  L4, and audit the benchmark", open, head `60ee8d84`, branch `mengwong/kant-chubb` on origin —
  checked with `git ls-remote` and `gh pr list` at 18:05 on 2026-09-14. A "[PR NUMBER PENDING]"
  placeholder left by a reviser is to be replaced with #387.
  **Q5 (post 3) — anon:** attribute to "senior legislative drafter with deep roots in the Rules as
  Code movement"; the conversation occurred **circa 2026-07-15 at the CALC (Commonwealth
  Association of Legislative Counsel) conference in Singapore** and was recorded in session on
  2026-09-14 — so the post's "12 September" date is wrong and the invented "ruling" in note 8 comes
  out. **Q6 (post 3) — not on record:** "This is a qualitative impression; a quantitative study
  would have to be focus of future research similar to
  https://popl22.sigplan.org/details/prolala-2022-papers/7/Cod-e-ifying-The-Law. The qualitative
  impression is traceable to the work on the PDPA case and the insurance case; in both cases the
  'client' assigned a business executive to review the encoding and even though they were not a
  programmer they were able to review and sign off." — so the sentence stays, attributed as an
  impression from two engagements, one executive each, with the PROLALA pointer for the study not
  done. **Q7 (post 5) — not on record:** "perhaps we could look at the go-pipeline producing
  output into the legalese/canon corpora and look for counts of forks, as a proxy for what's being
  asked for here? We are still in the middle of research to answer these kinds of questions." —
  keep the concession; name the fork register in canon as the instrument that will one day supply
  the denominator. **Q8 (post 1, the Berkman/CodeX sentence) — note completed 18:09, no mark needed; use it.**
  Meng, verbatim: "Engineers who came up in the IETF tradition, reading and implementing RFCs, are
  intimately familiar with the immortal words of RFC 2119 (BCP 14): [the boilerplate] The guru
  who wrote that RFC, Scott Bradner, just happened to be hanging out at Harvard's Berkman Klein
  Center, as is his wont, on a Thursday afternoon when I was presenting my plans for L4 as a
  residential fellow; we connected over the formalization of normative specifications involving
  deontic keywords. Technologists borrowed those terms from law decades ago, and built the
  Internet with them; now it's time to return the debt with interest. At Berkman I studied the
  social implications of moving rule-of-law onto a rules-as-code platform, and the questions
  around unlicensed-practice-of-law (UPL) in an AI world. At Stanford at CodeX I studied the
  programming language theory of specification languages, and how a controlled natural language
  could sit at the intersection of law and code." **Verified 2026-09-14 against the RFC Editor:**
  RFC 2119, "Key words for use in RFCs to Indicate Requirement Levels", S. Bradner, Harvard
  University, March 1997, BCP 14; the boilerplate sentence is exactly as Meng quotes it (RFC
  2119 p. 1: 'The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
  "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
  described in RFC 2119.'); updated by RFC 8174 (B. Leiba, May 2017, also BCP 14), which the post
  may note in a footnote. Bradner is listed as a Berkman Klein Center affiliate
  (<https://cyber.harvard.edu/people/sob>). The Thursday, the presentation and the conversation
  are Meng's recollection and are attributed as such. **Years, checked 2026-09-14:** Meng is in
  the Berkman Klein Center's announced 2016–2017 community
  (<https://hls.harvard.edu/today/berkman-klein-center-announces-2016-2017-community/>: "Meng
  Weng Wong is a serial entrepreneur, angel investor, and computer scientist currently working on
  Legalese.com…"), so the Bradner conversation is 2016–17; the CodeX year is not stated on any
  page opened today (the FutureLaw 2019 speaker page names the Berkman and Ca' Foscari
  fellowships only) — the post says "the following year" or leaves CodeX undated until Meng
  confirms. **One more verified detail worth the sentence:** Meng is himself an RFC author —
  RFC 4408, "Sender Policy Framework (SPF)", M. Wong and W. Schlitt, April 2006 (RFC Editor,
  read 2026-09-14; the FutureLaw page says he "led the development and global adoption of the
  email standard SPF") — so the Berkman moment is the author of BCP 14 meeting the author of
  RFC 4408 over what MUST and MAY mean; the post may say so in one clause, since it is what makes
  the "return the debt with interest" line his to say. This replaces the credential sentence: the moment is Bradner and the RFC, and the
  claim it carries — law lent the Internet MUST/SHOULD/MAY; L4 returns the loan — is the post's
  own, in Meng's words.

Citation notes gathered per post live in the planning notes (a Claude memory file, not in this
tree) until each post is drafted, at which point they move into the post's Sources list and are
re-verified there.
