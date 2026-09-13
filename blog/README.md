# The L4 blog — prefiguring the papers

**STATUS 2026-09-13: PLANNED. No post drafted.** This directory holds the style guide and, once
they exist, the posts. It is the companion to [`paper/`](../paper/): each post puts one of the
papers' positions in front of a general technical reader before the academic version lands. See
[`STYLE.md`](STYLE.md) for who that reader is and how a post is written.

## The arc

Eight posts and one standalone. The facet column names the `paper/` directory each post
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
| S1 | Seeing like a citizen               | `political-economy/` — standalone, runs any time            |

## Framing constraints

Things a post must say, or must not claim, recorded when they were decided so a later drafter
does not have to rediscover them.

- **Post 1.** We are not claiming incompetence on the part of the legislative drafters. The race
  condition in the regulations turned out to be documented in the accompanying guidance, which
  ameliorated it in practice. The claim is that our methods found it from the text of the rules
  alone — which is both the more defensible claim and the more interesting one, since it is the
  reader without the guidance who is caught. Both halves go in the post. (Meng, 2026-09-13.)

Citation notes gathered per post live in the planning notes (a Claude memory file, not in this
tree) until each post is drafted, at which point they move into the post's Sources list and are
re-verified there.
