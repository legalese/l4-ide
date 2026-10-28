# Draft rules with Legalese AI

Go from a policy or contract in plain language to a checked L4 draft, with Legalese AI in VS Code.

**Before you start:** [Install L4 and write your first rule](../getting-started/first-l4-file.md).

---

## Setup

1. Install the [L4 VS Code extension](https://marketplace.visualstudio.com/items?itemName=Legalese.l4-vscode).
2. Open a folder for your rules in VS Code. Putting it under git from the start is a good idea; see [Manage rules in git and CI](../getting-started/version-control-for-rules.md).
3. Open the **L4** sidebar, sign in with Legalese Cloud, and switch to the **Legalese AI** tab. Say "Hello" to check that it answers.

Legalese AI already knows L4 syntax and how to deploy, so you don't need to paste a cheat sheet into your prompts.

---

## Step 1: Frame the source text

Before prompting, decide three things:

1. **Scope**: one clause, one section, or the whole document? Smaller pieces give cleaner drafts.
2. **The decision**: what question should the rule answer? For example `` `is eligible for refund` ``, `` `amount owed` `` or `` `is in breach` ``.
3. **The inputs**: what facts will a caller provide? A person, an order, a claim?

Write these down as a short brief:

> **Source:** Section 4 of our refund policy (pasted below).
> **Decision:** `is eligible for refund`, giving a BOOLEAN.
> **Inputs:** an `Order` with purchase date, amount and product category; the current date.

---

## Step 2: Ask for a draft

Paste the brief and the source text into Legalese AI:

```
Draft L4 for the refund policy below.

Brief:
- Decision: `is eligible for refund`, giving a BOOLEAN
- Input: an Order record
- Put the result in rules/refund.l4

Source (Section 4):
"""
A customer may request a refund within 30 days of purchase, provided
the product has not been opened. Digital goods are non-refundable
except where required by law. Orders over $500 require manager approval
before a refund is issued.
"""

Start with the type declarations, then the decision rule.
Mark each condition with a comment citing the source.
```

A typical draft declares `Order` and any lists of choices (such as a product category), writes the main `DECIDE` rule, splits sub-conditions into named helpers so the rule reads like the policy, and adds examples at the end.

---

## Step 3: Let it fix errors, then add tests

You don't need to ask Legalese AI to check its work. Every time it creates, edits or reads an `.l4` file, it gets the type checker's diagnostics for that file. If there are errors (a misspelt name, a wrong field access, a list where a single value was expected), it fixes them before it answers. You can watch the same diagnostics in VS Code's Problems panel.

When the draft is clean, ask for tests:

```
Add three #EVAL blocks:
1. An opened digital good bought yesterday: expect FALSE.
2. An unopened $200 physical good bought 10 days ago: expect TRUE.
3. An unopened $900 physical good bought 10 days ago: expect it to
   need manager approval.
```

After that edit, Legalese AI sees the `#EVAL` results and can compare them with what you asked for. If a result contradicts what you expected, you have found something: the policy is ambiguous, the draft misread it, or your own reading was wrong. Each of these is worth knowing.

A file that type-checks is not necessarily right. The checker catches rules that don't fit together, not rules that say the wrong thing; that is what the tests and the review are for.

---

## Step 4: Review

A draft is not finished when it type-checks. Review it for:

- **Fidelity**: does each clause of the source appear in the L4, and nothing else?
- **Silent assumptions**: did the draft decide something the source leaves open, such as what "opened" means or whether store credit counts?
- **Cross-references**: are other sections the policy mentions encoded, or only stubbed?
- **Edge cases**: a purchase on day 30 and day 31, an order of exactly $500, a zero-value order.

Ask Legalese AI to list its assumptions, so the policy owner can confirm them:

```
List every assumption you made that is not explicit in the source text,
with a one-line justification for each.
```

---

## A complete session

```
You: Draft L4 in rules/late-fee.l4 for:
     "A late fee of 5% of the outstanding balance applies to any
     payment received more than 14 days after the due date. The fee
     is waived for first-time late payments."
     Decision: `late fee owed`, giving a NUMBER. Input: a Payment.

AI:  [writes rules/late-fee.l4 with a Payment record, helper rules
     and tests; sees a misspelt field name in the diagnostics and
     fixes it; the file checks clean]

You: Add a test for a payment 20 days late where the customer has
     two earlier late payments. Expect 5% of the balance.

AI:  [adds the test, sees its result after the edit, confirms]

You: List your assumptions.

AI:  1. "First-time" means no earlier late payment ever, not
        "first this year"; the source does not say.
     2. Days late are calendar days, not business days.
     3. The 5% applies to the balance on the due date, not on the
        payment date.
```

The policy owner now has three questions to answer. That is the point.

---

## Tips

- **One clause per prompt** when the source is dense. Combine the pieces later.
- **Keep the brief in a file** (for example `rules/brief.md`) and refer to it instead of retyping it.
- **Ask for alternatives** when a clause is ambiguous: "show two encodings and explain the difference".
- **Let it prepare deployment**: once the file is clean, ask Legalese AI to mark the decision with `@export` and walk you through [deploying your rules](../deploying-rules/exporting-rules-for-deployment.md).
- **For legislation**, see [Encode legislation](../getting-started/encoding-legislation.md#drafting-with-an-ai-assistant): a workflow and prompts for statutes.

---

## Limits

- Legalese AI can misread unusual legal structures. Compare the draft with the source, clause by clause.
- Tests it writes reflect its own reading of the source. Write your own tests before you trust the rule.
- A rule that type-checks can still say the wrong thing.

---

## Next steps

- [Test your rules](../getting-started/testing-your-rules.md): assertions and timelines.
- [Common patterns](../getting-started/common-patterns.md): shapes worth knowing when you review a draft.
- [Deploy your rules](../deploying-rules/exporting-rules-for-deployment.md): publish the rule as an API.
