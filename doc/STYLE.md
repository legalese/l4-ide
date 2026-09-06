# Style: the words we lead with

This page is about **how to write** L4's documentation. It is not a list of banned words. With one
exception, every technical term on this page may appear in the manual — the question this page
answers is _which word comes first_, and _what has to happen before the technical one is allowed_.

The one exception, the single word that is genuinely retired, lives in `CLAUDE.md` §7 with the
ruling that retired it and the check that enforces it. **It is not repeated here**, because a
vocabulary rule kept in two places drifts in one of them.

---

## 1. Who is reading

Meng, 2026-09-04: pitch this to a relatively nontechnical audience, and be example-heavy.

> It has not escaped the notice of the computational law community that many people encountering
> this body of thinking are actually engaging in critical thinking for the very first time.

So the reader is a paralegal, a policy officer, a founder reading their own contract, a first-year
law student. Assume they have read
[Your First L4 File](tutorials/getting-started/first-l4-file.md) and nothing else. Assume no
programming. Assume they have never had to say precisely what "no answer" means.

That reader is not stupid and is not in a hurry. They are unfamiliar. Those are different problems,
and only the second one is ours to fix.

---

## 2. Which page you are writing decides which word you may use

Meng ruled on 2026-09-05 that the vocabulary binds the **learning-oriented** pages, and that a
reference page may use the technical term if it does the work of introducing it:

> We want the "retired vocabulary" list to be excluded from the tutorial and cookbook guides, but if
> they find their way into a Diataxis theory reference we could allow that iff we appropriately
> introduce PLT alongside.

| where you are writing                                         | what you may use                                                                                         |
| ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `doc/tutorials/`, `doc/courses/`, the cookbook when it exists | the **lead-with** wording in §4. The reader is here to learn the law, not the discipline.                |
| `doc/reference/`, `doc/concepts/`                             | the technical term **once the page has introduced it**, by the pattern in §3. Lead with the lay wording. |

"PLT" is programming language theory — the field these words come from. Naming the field is part of
introducing the term: a reader who is told _"this is what programming language theorists call a
**Boolean**"_ has learned where the word lives, and can go and read about it. A reader who simply
meets the word has learned nothing.

**The reference-side test is not enforced mechanically.** `etc/check-retired-terms.mjs` sweeps
`doc/tutorials` and `doc/courses` only. Nothing checks that a `reference/` page introduced a term
before using it, so on those pages this is a rule you keep by reading, not one CI keeps for you.

---

## 3. Introduce, then bold, then use bare

The pattern, from the 2026-09-04 brief, is the one a contract already uses for a defined term:

> lay words first, then the technical label as a bold-quoted defined term, once per page, then the
> bare term.

A yes-or-no fact — what programming language theory calls a **"Boolean"** — is either true or
false. Later on the page, "Boolean" alone is fine.

Three things follow.

**Define it on every page.** Readers arrive cold at whichever page a search engine gave them. A
definition on the tutorial does not carry to the reference page.

**Define it once per page**, and never use a term before its definition on that page.

**The same pattern introduces an acronym**, and Meng called this out as a particular pet peeve
(2026-09-04): _never use one before introducing the term in full._ "an application programming
interface (API)", "JavaScript Object Notation (JSON)", "the command-line interface (CLI)",
"Decision Model and Notation (DMN)". Later uses may be short. L4's own uppercase keywords — `GIVEN`,
`MEANS`, `REFUSE` — are not acronyms; they are taught as words.

---

## 4. The words to lead with

Twenty-five terms. **These are not prohibitions**: the middle column is what you may use on a
`reference/` or `concepts/` page once you have introduced it, and what you should not reach for
first anywhere.

| lead with                                                 | then, once introduced        | notes                                                                                                                                                                                |
| --------------------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| rule                                                      | function                     |                                                                                                                                                                                      |
| input; a fact the rule is `GIVEN`; the rule's inputs      | parameter, argument          | this is the compiler's own wording since 2026-09-05 too — the messages say "input"                                                                                                   |
| a name                                                    | variable                     |                                                                                                                                                                                      |
| a yes-or-no fact                                          | **Boolean**                  | worth introducing: "the reader will have learned something useful beyond L4" (Meng, 2026-09-05)                                                                                      |
| text                                                      | string                       |                                                                                                                                                                                      |
| L4 accepts it                                             | type-checks, compiles        |                                                                                                                                                                                      |
| run; work out; ask                                        | evaluate, evaluation         |                                                                                                                                                                                      |
| gives (its output); answers                               | returns, yields              |                                                                                                                                                                                      |
| a piece of a rule                                         | expression                   |                                                                                                                                                                                      |
| use; refer to; the rule it relies on                      | call, invoke, callee         |                                                                                                                                                                                      |
| the chain of rules                                        | call stack                   |                                                                                                                                                                                      |
| say it once; tidy                                         | factor out, refactor         |                                                                                                                                                                                      |
| where a name can be used; which rules can see it          | scope, in scope              |                                                                                                                                                                                      |
| takes precedence inside its own section                   | shadow                       |                                                                                                                                                                                      |
| stops and says why                                        | raise, throw, exception      |                                                                                                                                                                                      |
| deal with; turn into an answer                            | catch, handle                |                                                                                                                                                                                      |
| no value at all                                           | **null**, bottom, undefined  | introduce and link out — the point is to "send inquisitive readers down a Wikipedia rabbit hole" (Meng, 2026-09-05), e.g. [null pointer](https://en.wikipedia.org/wiki/Null_pointer) |
| the list of facts the form asks for                       | **schema**                   | same reasoning as Boolean (Meng, 2026-09-05)                                                                                                                                         |
| publish the rule as a service people and programs can ask | export, endpoint, API        | spell out "application programming interface" first                                                                                                                                  |
| an instruction to L4 such as `#EVAL`                      | directive                    |                                                                                                                                                                                      |
| a fixed value written out, like `18` or `"yes"`           | literal                      |                                                                                                                                                                                      |
| when the rule is run                                      | runtime, at runtime          |                                                                                                                                                                                      |
| works for any kind of thing                               | polymorphic                  | a real L4 concept, not only a word: it describes `FOR ALL` type variables. Lead with the lay wording in tutorials; the term is fine in reference once introduced                     |
| L4 stops reading as soon as it knows the answer           | lazy, left-to-right          |                                                                                                                                                                                      |
| following the chain of rules all the way down             | fixpoint, transitive closure |                                                                                                                                                                                      |

**`type` is allowed outright** and is not in the table. Meng, 2026-09-05: it is "no less meaningful
than kind". Write "kind of thing" where it reads better — `IS A NUMBER` means it is a number — but
"type" needs no apology and no introduction.

---

## 5. The one retired word

One word is not on the table above, because it is not a matter of leading with something else: it
is retired outright, in every quadrant. Today that word is **`binder`** — Meng, 2026-09-04, _"to
lawyers a binder is a ream of paper with ink and holes"_ — and the word to use instead is "section
`GIVEN`" for the construct and "input" for what it supplies.

**`CLAUDE.md` §7 is the list; this sentence is not.** Go there for the ruling that retired it, the
reason, the check that enforces it, and anything retired after this page was written. This page
names the word so you know what is meant, and deliberately does not carry a second copy of the
list — a vocabulary list kept in two places drifts in one of them, and §7 is the canonical one.

For the record of what §7 is for: a word moves from this page to §7 **only by a ruling**, never
because someone dislikes it. That gate is the difference between a style preference and a defect.

---

## 6. Other standing rulings

**Name the person in every example** (Meng, 2026-09-04). Never `GIVEN person IS A Person` — a
tautology to this reader. Name the hypothetical person the way a law-school problem does,
`GIVEN alex IS A Person`, and carry Alex through the page. The letter form statutes use,
`GIVEN p IS A Person` — "a person ('P')", Bribery Act 2010 — is introduced where re-declaration per
section is taught. Every example person on every page has a name.

**`REFUSE` is sequestered** (Meng, 2026-09-04):

> REFUSE is pretty obscure … you could encode a dozen laws or contracts and never use it, so let's
> not let it compete with more primary concepts.

So `REFUSE`, `TBD`, `#ASSERT REFUSED` and the non-answer taxonomy live in their own page or chapter,
placed after the primary material — never interleaved with definitions, inputs, conditions, dates or
duties. In an index it gets its own late heading, not a slot in "Getting Started". A primary page may
say "not `REFUSE`" in a single anti-pattern line where a writer would over-reach for it, and no more.

**Verbose is fine; padding is not** (Meng, 2026-09-04):

> Ok to be verbose for the sake of clarity. AI writing can sometimes be too concise.

When a reader could need the extra sentence, write it. Say the thing, then say what it means for the
reader, then show it. Restate a point in different words when the first way might not land. Never
trade a clear long sentence for a compressed short one. But every sentence must still carry
something the reader needs: the test is "would a careful teacher say this out loud?", not "is this
short?".

---

## See also

- [`CLAUDE.md` §7](../CLAUDE.md) — the retired word, its ruling, and the CI check
- [Errors and Troubleshooting](reference/errors/README.md) — where this vocabulary meets real output
- [Reviewing encoded law](concepts/reviewing/reviewing-encoded-law.md) — written for the same reader
