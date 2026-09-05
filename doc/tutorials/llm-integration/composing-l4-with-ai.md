# Composing L4 with Legalese AI (Artificial Intelligence)

Go from a policy or contract written in ordinary English to draft L4, with
Legalese AI — an artificial-intelligence (**"AI"**) assistant you drive from
inside your editor.

**Prerequisites:** [Your First L4 File](../getting-started/first-l4-file.md), Legalese AI installed

---

## The words this page uses

A rule is told some facts about the case in front of it — the names listed
after `GIVEN` (its **"inputs"**) — and works out one answer from them (its
**"output"**, whose kind of thing is named after `GIVETH`). A fact that every
rule in a section needs is written once under the section heading, indented past
the `§` (a **"section GIVEN"**).

---

## Setup

1. **Install L4 VS Code extension.** See [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode).
2. **Open your L4 project.** Create a VS Code workspace in a folder of your choice. Create a new repo using `git` if you like.
3. **Switch to the Legalese AI tab.** Say "Hello" and see what it responds.

Legalese AI already knows how L4 is written, how to check a file, and how to deploy one, so you do not need to paste a cheat sheet into every prompt.

---

## Phase 1: Frame the Source Text

Before prompting, decide three things:

1. **How much to take on** — one clause, one section, or the whole contract? Smaller helpings produce cleaner drafts.
2. **The output** — what question should the L4 rule answer? (`is eligible`, `amount owed`, `is in breach`.)
3. **The inputs** — what facts will a caller supply? A `Person`, an `Order`, a `Claim`?

Write these down as a short brief. You will paste it into your first prompt.

### Example brief

> **Source:** Section 4 of our refund policy (pasted below).
> **Decision:** `is eligible for refund`, answering a yes-or-no question (a `BOOLEAN`).
> **Inputs:** an `Order` with purchase date, amount, and product category; the current date.

---

## Phase 2: Ask Legalese AI to Draft

Open Legalese AI and paste your brief plus the source text. A good opening prompt:

```
Draft L4 for the refund policy below.

Brief:
- Decision: `is eligible for refund`, answering a BOOLEAN
- Input: an Order record
- Put the result in rules/refund.l4

Source (Section 4):
"""
A customer may request a refund within 30 days of purchase, provided
the product has not been opened. Digital goods are non-refundable
except where required by law. Orders over $500 require manager approval
before a refund is issued.
"""

Start by proposing the type declarations, then the decision rule.
Annotate each clause with a comment citing the source.
```

Legalese AI will typically:

- declare `Order`, any fixed lists of choices (`ProductCategory`, say), and supporting records;
- write the top-level `DECIDE` rule;
- break sub-conditions into named helper rules, so the whole reads like the prose;
- add `#EVAL` examples at the end of the file.

---

## Phase 3: Let It Check the File and Iterate

Ask Legalese AI to run the checker and fix what it finds:

```
Run `l4 check rules/refund.l4` and fix any errors. Keep going until it
comes back clean, then show me the final file.
```

Legalese AI will go round on the checker's output — a missing `GIVETH`, a field read the wrong way, a list where a single value was wanted — until L4 accepts the file. This is where an assistant working inside your editor beats a chat transcript: it reads the actual error, edits the actual file, and runs it again.

Then add sanity checks:

```
Add three #EVAL blocks:
1. Alex buys a digital download and opens it, yesterday — expect FALSE.
2. Alex buys a $200 physical good, unopened, 10 days ago — expect TRUE.
3. Alex buys a $900 physical good, unopened, 10 days ago — expect
   the "requires manager approval" route.
```

If the answers contradict what you intended, that is a finding. Either the prose was ambiguous, or the draft misread it, or your own picture of the policy was wrong. All three are worth knowing.

---

## Phase 4: Human Review

The draft is not done when L4 accepts it. Review for:

- **Fidelity** — does each clause of the source map to something in the L4?
- **Silent assumptions** — look for choices Legalese AI made without asking (what "opened" means, whether store credit counts).
- **Cross-references** — if the policy cites other sections, are they genuinely encoded, or left as a blank someone has to fill in for each case? A blank belongs under the heading of the section that reads it, as a [section `GIVEN`, indented past the `§`](../../reference/syntax/section-given.md); older drafts spell it `ASSUME`, which is deprecated (ruled 2026-09-04) and still works.
- **Edge cases** — a purchase on day 31, a zero-dollar order, a refund in a foreign currency.

Ask Legalese AI to annotate its own assumptions:

```
List every assumption you made that is not explicit in the source text,
with a one-line justification each.
```

This surfaces the interpretive choices so a lawyer or policy owner can sign off.

---

## A Complete Session

```
You: Draft L4 in rules/late-fee.l4 for:
     "A late fee of 5% of the outstanding balance applies to any
     payment received more than 14 days after the due date. The fee
     is waived for first-time late payments."
     Decision: `late fee owed`, answering a NUMBER. Input: a Payment.

AI: [writes rules/late-fee.l4 with Payment record, helper rules,
         and #EVAL examples]

You: Run the checker and fix anything that breaks.

AI: [runs `L4 Check`, fixes a missing GIVETH, re-runs, clean]

You: Add an #EVAL for a payment Alex made 20 days late, where Alex has
     two prior late payments — expect 5% of the balance.

AI: [adds the block, re-runs, confirms]

You: List your assumptions.

AI: 1. "First-time" means no prior late payments ever, not
           "first this year" — source is silent.
        2. Days late is calendar days, not business days.
        3. The 5% applies to outstanding balance at the due date,
           not at the payment date.
```

Three assumptions the policy owner now has to confirm. That's the point.

---

## Tips

- **One clause per prompt** when the source is dense. Aggregate later.
- **Keep the brief in a file** (e.g. `rules/_brief.md`) and reference it — saves retyping.
- **Ask for alternatives** when a clause is ambiguous: _"show two encodings and explain the difference"_.
- **Let Legalese AI prepare for deployment** — once the file is clean, ask it to mark the decision `@export`, which publishes the rule as a service people and other programs can ask, and to walk you through deploying it. See [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md).

---

## Limitations

- Legalese AI can misread an unfamiliar legal structure. Always compare the draft against the source, clause by clause.
- Generated `#EVAL` cases reflect the assistant's reading, not the truth. Write your own before you trust the rule.
- L4 will happily accept a rule that says the wrong thing. A file L4 accepts is a file that is well formed, not a file that is right.

---

## What You Learned

- A four-phase workflow: frame, draft, iterate, review
- How to brief Legalese AI so its drafts are usable
- How to bring interpretive assumptions into the open before they ship

---

## Next Steps

- [Exporting Rules for Deployment](../deploying-rules/exporting-rules-for-deployment.md) — publish the rule as a service people and other programs can ask, through an application programming interface (an **"API"**)
- [Common Patterns](../../reference/patterns/common-patterns.md) — idioms worth knowing when reviewing what the assistant wrote
- [Legislative Ingestion](legislative-ingestion.md) — deeper workflow for statute-scale text
