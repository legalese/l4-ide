# Getting Started with Large Language Models

Set up and use a large language model (**"LLM"**) with L4.

**Prerequisites:** Basic L4 knowledge, and access to a large language model
through an application programming interface (an **"API"**) — the way one
program asks another program a question.

---

## The words this page uses

A rule is told some facts about the case in front of it — the names listed
after `GIVEN` (its **"inputs"**) — and works out one answer from them (its
**"output"**, whose kind of thing is named after `GIVETH`). Given these inputs,
a rule gives an output.

An input can be written in either of two places. A **"rule GIVEN"** sits
immediately above one rule and lists that rule's own inputs. A **"section
GIVEN"** sits once under a section heading, indented past the `§`, and names a
fact that every rule in that section may read. This page uses both.

---

## Why Combine an LLM and L4?

The two have complementary strengths:

| LLM Strengths                  | L4 Strengths         |
| ------------------------------ | -------------------- |
| Natural language understanding | Formal precision     |
| Handling ambiguity             | Logical consistency  |
| Text generation                | Verifiable reasoning |
| Flexibility                    | Reproducibility      |

**Combined approach:**

- the LLM handles fuzzy interpretation
- L4 handles formal reasoning
- together: explainable, auditable decisions

---

## The Hybrid Pattern

```
┌─────────────────────────────────────────────────┐
│                  Input Text                      │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│     LLM: read the facts out of the text         │
│     "Is this a 'reasonable time'?" → TRUE/FALSE │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│     L4: Apply formal rules                      │
│     IF `was reasonable time` THEN ...           │
└─────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────┐
│     Output: Decision + Explanation              │
└─────────────────────────────────────────────────┘
```

---

## Step 1: Name the Facts the LLM Will Supply

Declare the facts that come from the LLM's reading with a `GIVEN` under the
heading of the section that uses them, indented past the `§` — a section
`GIVEN`. One declaration serves every rule in the section:

```l4
§ `LLM Integration Example`
    GIVEN `was reasonable time` IS A BOOLEAN
          `tone is professional` IS A BOOLEAN
          `contains required elements` IS A BOOLEAN

-- Pure L4 logic
DECIDE `is valid notice` IF
    `was reasonable time`
    AND `tone is professional`
    AND `contains required elements`
```

The indentation carries the meaning. A `GIVEN` at column 1 is a rule `GIVEN`:
it lists the inputs of the one declaration below it, and nothing else can read
them. A `GIVEN` indented past the `§` is a section `GIVEN`, and belongs to the
whole section. See [the section `GIVEN`](../../reference/syntax/section-given.md).

An older spelling declared each fact with `ASSUME` at the left margin. `ASSUME`
is deprecated for this job (ruled 2026-09-04) and still works, so existing files
keep running; the two spellings behave identically.

### Key Insight

The LLM supplies the inputs — the values of those three names. L4 does the
reasoning — the `DECIDE` logic that combines them. Keeping the two apart is
what makes the decision auditable: the judgement calls are all in one place, and
the logic that acts on them is all in another.

Nothing in the file supplies those values. They arrive from the boundary: a
request that carries the LLM's answers, a run of
`l4 batch rules.l4 --inputs cases.json`, or the generated web form. Until they
arrive, a rule that reads one of them stops and says which name it needed and
that nobody has supplied it.

---

## Step 2: Design LLM Prompts

Create prompts that return structured answers:

```l4
{-
Prompt Template for "reasonable time" judgment:

"You are a legal assistant analyzing timing in a legal context.

Question: Was the action taken within a reasonable time?

Context:
- Required deadline: [DEADLINE]
- Actual date: [ACTUAL_DATE]
- Circumstances: [CIRCUMSTANCES]

Consider:
1. Industry standard timelines
2. Any extenuating circumstances
3. Whether delay caused harm

Answer with exactly one of:
- TRUE (reasonable time)
- FALSE (unreasonable delay)

Then explain your reasoning in 2-3 sentences."
-}
```

---

## Step 3: Create a Wrapper Type

Define a type that captures both the judgment and its provenance:

```l4
-- LLM judgment with audit trail
DECLARE LLMJudgment
    HAS question IS A STRING
        answer IS A BOOLEAN
        confidence IS A NUMBER   -- 0.0 to 1.0
        reasoning IS A STRING
        model IS A STRING        -- e.g., "gpt-4"
        timestamp IS A STRING

-- Example judgment
timingJudgment MEANS LLMJudgment
    "Was delivery within reasonable time?"
    TRUE
    0.85
    "The 5-day delivery is within industry standard of 7 days, and no harm resulted from the timing."
    "gpt-4"
    "2024-01-15T10:30:00Z"
```

---

## Step 4: Integrate with L4 Rules

Use the LLM judgment in your L4 rules:

```l4
-- Extract the answer from judgment
GIVEN judgment IS A LLMJudgment
GIVETH A BOOLEAN
`judgment is yes` MEANS judgment's answer

-- Use in rule with confidence threshold
GIVEN judgment IS A LLMJudgment
      threshold IS A NUMBER
GIVETH A BOOLEAN
`confident yes` MEANS
    judgment's answer
    AND judgment's confidence >= threshold

-- Main rule using LLM input
GIVEN deliveryJudgment IS A LLMJudgment
      qualityJudgment IS A LLMJudgment
GIVETH A BOOLEAN
DECIDE `delivery acceptable` IF
    `confident yes` deliveryJudgment 0.7
    AND `confident yes` qualityJudgment 0.7
```

---

## Step 5: Preserve Audit Trail

Keep full records for compliance:

```l4
-- Decision record with full audit trail
DECLARE Decision
    HAS rule IS A STRING
        inputs IS A LIST OF LLMJudgment
        outcome IS A BOOLEAN
        timestamp IS A STRING

-- Create decision record
GIVEN outcome IS A BOOLEAN
      judgments IS A LIST OF LLMJudgment
GIVETH A Decision
`record decision` MEANS Decision
    "delivery acceptable"
    judgments
    outcome
    "2024-01-15T10:35:00Z"
```

---

## Example: Complete Integration

```l4
-- The three judgments come from the API in practice; they are declared once
-- for the whole section.
§ `Contract Compliance Check with LLM`
    GIVEN timingJudgment IS A LLMJudgment
          qualityJudgment IS A LLMJudgment
          professionalismJudgment IS A LLMJudgment

-- Confidence threshold for accepting LLM judgments
minConfidence MEANS 0.75

-- Individual checks
DECIDE `timing ok` IF
    timingJudgment's answer
    AND timingJudgment's confidence >= minConfidence

DECIDE `quality ok` IF
    qualityJudgment's answer
    AND qualityJudgment's confidence >= minConfidence

DECIDE `professionalism ok` IF
    professionalismJudgment's answer
    AND professionalismJudgment's confidence >= minConfidence

-- Combined compliance check
DECIDE `is compliant` IF
    `timing ok`
    AND `quality ok`
    AND `professionalism ok`

-- What one case looks like: the three judgments a caller would send
sampleTiming MEANS LLMJudgment WITH
    question IS "Was delivery timely?"
    answer IS TRUE
    confidence IS 0.90
    reasoning IS "Delivered 2 days early"
    model IS "gpt-4"
    timestamp IS "2024-01-15T10:30:00Z"

sampleQuality MEANS LLMJudgment WITH
    question IS "Does quality meet specifications?"
    answer IS TRUE
    confidence IS 0.85
    reasoning IS "All quality metrics passed"
    model IS "gpt-4"
    timestamp IS "2024-01-15T10:31:00Z"

sampleProfessionalism MEANS LLMJudgment WITH
    question IS "Was conduct professional?"
    answer IS TRUE
    confidence IS 0.80
    reasoning IS "Communication was clear and timely"
    model IS "gpt-4"
    timestamp IS "2024-01-15T10:32:00Z"

-- `#CHECK` reports what kind of thing the rule answers with. It does not
-- supply the judgments: those come from the request.
#CHECK `is compliant`
```

_Proposed, not landed (2026-09-04): supplying values in the file itself, with a
`WITH` clause on the instruction naming each judgment. This lands with the
discharge pull request; until then supply values from outside the file (web
form, `l4 batch`, API). `#CHECK ... WITH ...` does not supply them today: L4
rejects it, reporting that a rule, which is not something you can apply to named
inputs, is being applied to named inputs._

---

## Best Practices

### 1. Clear Prompt Design

- Ask for binary (TRUE/FALSE) answers
- Request confidence scores
- Require reasoning explanation

### 2. Confidence Thresholds

- Set minimum confidence levels
- Have fallback for low-confidence responses
- Consider human review for edge cases

### 3. Audit Everything

- Log all LLM calls
- Store prompts, responses, timestamps
- Preserve for compliance

### 4. Separation of Concerns

- the LLM: interpretation, classification
- L4: logic, consequences, obligations
- keep the formal rules in L4, not in prompts

---

## Limitations

- **An LLM's answers can vary** - the same prompt may give different answers on
  different days
- **No guaranteed consistency** - unlike L4, which gives the same answer to the
  same facts every time
- **Confidence scores are subjective** - calibrate them carefully
- **Audit requirements** - make sure you can explain every decision you ship

---

## What You Learned

- How to combine an LLM's strengths with L4's
- How to declare the facts an LLM supplies as a section `GIVEN`, once for a
  whole section
- How to design prompts that come back as structured answers
- How to keep an audit trail
- Good practice for systems that use both

---

## Next Steps

- [Legislative Ingestion](legislative-ingestion.md) - Use an LLM to help encode legislation
- [The design record for this bridge](https://github.com/legalese/l4-ide/tree/main/specs/done/LLM-INTEGRATION-SPEC.md) - Technical details
- [Foundation Course](../../courses/foundation/README.md) - Learn L4 fundamentals
