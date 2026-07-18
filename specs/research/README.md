# Research records

Working records of investigations that fed a design decision. **These are not
documentation.** They keep the false starts, the dead ends, the citation traps, and
the record of what we got wrong before we got it right — which is exactly what makes
them worth keeping, and exactly why they do not belong in `doc/`.

Where a finding is settled and useful to a reader, it has been promoted:

| Record                                   | What it investigated                                                                                                            | Promoted to                                                                                                      |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| [`DMN-STEELMAN.md`](DMN-STEELMAN.md)     | Are our criticisms of DMN / decision tables defensible? (Answer: three of four were **false**.) 82 confidence-marked citations. | `doc/concepts/language-design/{logic-not-flowcharts,related-work}.md`; `specs/todo/QUESTION-ORDERING-SPEC.md` §9 |
| [`MERMAID-PLAN-B.md`](MERMAID-PLAN-B.md) | Can a ladder diagram be forced into Mermaid, so it renders natively on github.com? (Answer: yes — and we still should not.)     | `specs/todo/ladder-diagrams-2026/DESIGN.md` §21a, §24                                                            |

## Conventions

**Citations carry a confidence marker.** `[V]` = the source was read at its primary
location and confirms the claim. `[P]` = the bibliographic record was verified
(publisher/dblp) but the full text was not read. `[U]` = could not verify — **do not
cite**. A fabricated citation is far worse than a missing one, and these records name
the ones that nearly got through.

**Renders are not committed, sources are.** `mermaid-planb/*.mmd` regenerate with
`npx @mermaid-js/mermaid-cli -i x.mmd -o x.png`; `ghsim.mjs` replays GitHub's actual
rendering pipeline (its exact Mermaid version, `initialize()` config, DOMPurify
allowlist and viewscreen CSS) so a candidate can be checked without loading
github.com. Committing the pictures instead of the sources would invert the very
thesis these investigations were serving.
