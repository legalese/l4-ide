# The L4 blog — prefiguring the papers

**STATUS 2026-09-13: PLANNED. No post drafted.** This directory holds the style guide and, once
they exist, the posts. It is the companion to [`paper/`](../paper/): each post puts one of the
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
  and describes the judgment as what it is. Open the judgment before quoting it. Meng's closing phrase, "It was
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

Citation notes gathered per post live in the planning notes (a Claude memory file, not in this
tree) until each post is drafted, at which point they move into the post's Sources list and are
re-verified there.
