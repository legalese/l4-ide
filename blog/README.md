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
