# Notes on judgment calls (vanilla cell, t8)

These are the points where the contract text required interpretation rather than a
mechanical lookup. No answer key or external source was consulted; this is reasoning
from `inputs/chubb-policy.txt` and `inputs/queries-blind.md` alone.

## Q1 — firefighter burns

Straightforward: §3.1.3 excludes any injury "arising directly or indirectly out of ...
Service as a fire fighter." Burns sustained on duty as a firefighter fall squarely
within this. No judgment call needed.

## Q4 — fall while traveling abroad + late wellness confirmation

Two independent readings both point the same way, which is why I answered `No` with
confidence despite each reading individually requiring some interpretation:

1. **Geography.** §2.2 says the Daily Hospital Income Benefit "will only be payable for
   each (24 hour) day of continuous confinement in a hospital **in the United States**."
   §4.1.1 separately says the policy "insures You twenty-four (24) hours a day anywhere
   in the world" — but that clause is about where a covered _event_ can occur, not where
   the _confinement_ that triggers payment must be. I read "hospitalized ... while
   traveling abroad" as meaning the hospitalization itself took place abroad, which
   would fail §2.2's situs requirement.
2. **Timing.** §1.3 requires written confirmation of the wellness visit "no later than
   the 7th month anniversary." The query states confirmation was given at 8 months —
   past that deadline. §1.2 states cancelation "will be deemed to have occurred ... if
   the condition set out in Section 1.3 has not been satisfied in a timely fashion."
   I treated this as determinative on its own (i.e., even setting the geography question
   aside, the policy is canceled), since the query gives us this fact specifically and
   the instructions say not to assume away facts the query itself supplies.

## Q5 — punching own face to "show off," no fraud/misrepresentation

The hardest call in the set. The contract never defines "accidental Injury" and has no
express exclusion for self-inflicted or intentional acts (unlike the closed, enumerated
list in §3.1). Two legitimate readings compete:

- **Ordinary-meaning reading (the one I used, answer `No`):** "accidental" ordinarily
  means unintended/by chance. Deliberately punching yourself is a voluntary act, not a
  chance event, so the resulting injury is not "accidental Injury" within the plain
  sense of §2.1.
- **Competing reading (would give `Yes` or `I do not know`):** some insurance doctrine
  distinguishes "accidental means" from "accidental results" — under the latter, an
  injury can be "accidental" if the _outcome_ (hospitalization) was unintended even
  though the _act_ (the punch) was voluntary. The query's explicit statement that no
  fraud/misrepresentation occurred seems designed to take §1.2's fraud-cancelation
  clause off the table and isolate exactly this "was it an accident" question — which
  suggests the drafters intended it to be answerable, not a dead end.

I went with the ordinary-meaning reading and answered `No`, on the view that a
plain-English consumer policy with no definitions section should be read the way an
ordinary person would read it, and an ordinary person would not call deliberately
punching your own face "an accident." This is a genuine judgment call, not a certainty.

## Q9 — son biting ankle while serving as a police officer

§3.1.4 excludes injury "arising directly or indirectly out of ... Service in the
police." I read this as requiring a causal link between the injury and police duties,
not merely that the claimant happens to be a police officer. Being bitten by one's own
son reads as a domestic/accidental event unconnected to police service, so I did not
apply the exclusion. Answered `Yes` (also checked: wellness proof given at 6 months
satisfies both the "no later than 6th month anniversary" visit deadline and the "no
later than 7th month anniversary" confirmation deadline in §1.3).

## General approach to unmentioned facts

Per the standing preamble ("assuming all other conditions are met and no other
exclusions apply ... anything not referenced in the query"), for any condition not
mentioned in a given query (e.g., hospital location in Q3/Q7/Q9, fraud in Q1-7/Q9) I
assumed it was satisfied / not applicable, and did not treat silence as grounds for
"I do not know."
