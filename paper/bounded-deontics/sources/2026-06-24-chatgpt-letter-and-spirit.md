# ChatGPT conversation — "Types and Programming Languages"

> **Provenance.** Shared ChatGPT conversation, captured 2026-06-24 via browser.
> Source: <https://chatgpt.com/share/6a3b216e-7fac-83ec-b04a-97b048e46a21>
> Interlocutors: **Meng** (Wong Meng Weng) and **ChatGPT**.
> The opening turns are voice-transcribed (Meng's spoken prompts shown in quotation
> marks); the later turns are typed.
>
> **Known gap.** The transcript jumps from Meng's remark about Landin/Haskell
> straight to ChatGPT's "much deeper distinction than specification versus
> implementation." The intervening material — a discussion of **Peter Van Roy's
> "language tribes" / decomposition of paradigms into concepts**, and Meng's
> "letter and spirit" / "specification versus implementation" lead-in — did not
> render in the capture and is **missing here**. Marked inline as `[GAP]`.
>
> Saved as raw research source for a prospective **"Bounded Deontics"** paper.
> Related: `specs/todo/BOUNDED-DEONTICS-SPEC.md`.

---

## Why this is worth keeping (one-paragraph index)

Three interlocking ideas surface, in order:

1. **Letter/spirit ≅ implementation/property.** A program *executes*; a
   specification *judges*. Letter → transition relation / FSM; spirit →
   invariant / LTL-CTL formula. "The spirit is what survives refactoring."
2. **"Squeezing out the deontics"** (with **Oliver Goodenough**). Compiling
   `O(p)` into a costed transition loses something: Gneezy & Rustichini's
   *A Fine is a Price* (the daycare fine that turns a norm into a price) vs.
   Saki's Lady Carlotta running the compiler *backwards* (epistemic→deontic type
   error). A finite-state machine "does not naturally have guilt. Or excuse. Or
   justification. Or good faith. Or abuse of rights."
3. **Bounded deontics.** Every "must" is indexed to a (possibly implicit)
   **goal term**, exposed by the vernacular probe *"or else what, huh?"* Make the
   goal explicit (`Must(p, g)` / `Goal(g) ⇒ Must(p)`) and the obligation compiles
   into LTL maintenance/reachability properties — a deflationary, *teleological*
   account that sidesteps the classic deontic paradoxes. Honest edge case:
   intrinsic/constitutional norms ("you must not torture").

---

## Transcript

**Meng (voice):** "I understand that one of the classic texts, one of the classic
recent texts in programming language theory, is the text *Types and Programming
Languages*. Can you tell me about this book?"

**ChatGPT:** *Types and Programming Languages* (often abbreviated as TAPL) is a
well-known book by Benjamin C. Pierce. It's considered a cornerstone in
programming language theory. The book systematically introduces the theory of
type systems and how they apply to programming languages. It covers everything
from basic concepts like simply typed lambda calculus to more advanced topics
like polymorphism, type inference, and subtyping. The book is known for its
rigorous yet accessible approach, offering both theory and practical examples.
It's often used in graduate-level courses or by anyone interested in
understanding the deeper foundations of programming languages. If you're curious
about how types make programs safer and more predictable, this book is a classic
starting point.

**Meng (voice):** "When was it published?"

**ChatGPT:** It was first published in 2002. Despite its age, it's still
considered a foundational text in the field!

**Meng (voice):** "Prior to 2002, was there a standard treatment of types in
programming?"

**ChatGPT:** Before 2002, there were definitely important works on type theory,
but they were scattered across papers or more specialized texts. Some of the
foundations were laid by logicians like Alonzo Church and Haskell Curry, and key
ideas about types were explored in the 1970s and 1980s. Books like *The Lambda
Calculus: Its Syntax and Semantics* by Barendregt and Milner's work on type
polymorphism were hugely influential. But there wasn't a single, comprehensive
text that pulled all these strands together. *Types and Programming Languages*
really filled that gap by creating a unified and modern presentation of the field.

**Meng (voice):** "In contrast, I assume, to books like The Dragon Book, which
focused much more on the nuts and bolts of writing a compiler, but that Dragon
Book did talk about types, didn't it?"

**ChatGPT:** Yes, absolutely. The "Dragon Book" — officially *Compilers:
Principles, Techniques, and Tools* — does discuss type checking, but it's in the
context of a broader compiler design pipeline. It covers lexical analysis,
parsing, optimization, and code generation, with types appearing as one piece of
ensuring correctness. In contrast, TAPL is laser-focused on type theory itself —
formalizing types, proving properties about them, and exploring how they form the
theoretical backbone of languages. So yes, the Dragon Book gave you a practical
look at types in the compiler's journey, but TAPL gives you the deep theory
behind them.

**Meng (voice):** "Is there a more recent book that also talks about types in a
way that is just as accessible?"

**ChatGPT:** One more recent book that people often find accessible is
*Programming Languages: Application and Interpretation* by Shriram Krishnamurthi.
It explores types and language design, but in a more hands-on, interpreter-building
way. Another approachable one is *Types and Programming Languages, The Next 700
Pages*, which is a modern, evolving follow-up project online. While TAPL remains a
classic, these newer resources emphasize interactive learning, often blending
theory and practice in a more project-based, incremental style.

**Meng (voice):** "The next 700 pages is a playful reference to the next 700
programming languages."

**ChatGPT:** Exactly! That's a playful nod to Peter Landin's famous paper *The
Next 700 Programming Languages*. It's a bit of an inside joke in the programming
languages community. Landin's paper talked about the future of language design,
and "The Next 700 Pages" plays with that idea — suggesting there's always more to
explore when it comes to types and languages!

**Meng (voice):** "The next 700 languages in Landin's magnum opus was a sort of
precursor and a sort of nod in the direction of what would later become Haskell."

> `[GAP]` — Missing here: ChatGPT's reply to the Haskell remark, the **Van Roy
> "language tribes" / paradigms-into-concepts** discussion, and Meng's "letter and
> spirit" / "specification versus implementation" lead-in that prompts the next turn.

**ChatGPT:** That strikes me as a much deeper distinction than specification
versus implementation.

The phrase "the letter and the spirit" naturally evokes law, but in computing it
points toward something like:

| Legal notion | Computing notion |
| --- | --- |
| Letter of the law | Executable program |
| Spirit of the law | Temporal/property specification |
| Legal text | Source code |
| Jurisprudence | Program verification |
| Compliance | Satisfaction relation |

A program executes. A specification judges. That's a fundamentally asymmetric
relationship.

In model checking, the program is a transition system and the LTL/CTL formula is
not another program. It is a statement *about* programs. For example: "Every
request is eventually followed by a response." In LTL: `G(request -> F(response))`.
This is not a competing implementation. It lives at a different semantic level.

The implementation says: *Here is what happens.* The temporal formula says: *Here
is what ought to happen.* And suddenly we're very close to law.

A statute might say: "A tenant who gives notice shall receive the deposit within
thirty days." That is not a procedure for returning deposits. It is a property
that any compliant procedure must satisfy.

The distinction reminds me a bit of the old separation between object language and
metalanguage. The implementation inhabits the object language; the specification
inhabits the metalanguage. But "letter and spirit" captures something that
"object and meta" misses — because legal systems often contain both explicit
rules ("the letter") and underlying purposes ("the spirit"), and the spirit is
often expressed as constraints on the interpretation of the letter.

That's surprisingly close to what happens in formal methods. Consider a protocol
implementation. The code may literally say `if timeout then resend`, but the
property we care about is "Messages are eventually delivered." The property
explains *why* the code exists. The code is one witness. The property is the
intent.

In fact, if I were looking for a computational analogue of "the spirit of the
law", I wouldn't choose a specification language like TLA+ as a whole. I'd choose
the temporal properties themselves. The implementation is the operational
semantics; the spirit is the invariant. Or perhaps:

- Letter → transition relation; Spirit → invariant
- Letter → finite-state machine; Spirit → LTL/CTL formula

The spirit is what survives refactoring. You can replace the entire
implementation, alter data structures, rewrite algorithms, even change languages,
and still preserve the same temporal properties. That's very similar to law: you
can amend procedures, agencies, forms, deadlines, and administrative mechanisms
while attempting to preserve the underlying normative objective.

This may actually connect back to Van Roy in an unexpected way. His decomposition
of languages into concepts is one move up from language tribes. Your "letter and
spirit" distinction is arguably another move up. Van Roy asks: *What concepts
constitute a language?* You are asking: *What properties constitute a conceptually
correct realization of those concepts?* At that point we're not classifying
programs anymore. We're classifying the relationship between programs and their
intended meanings. And that's where temporal logic, deontic logic, contracts,
legal drafting, and formal verification all start to look like members of the
same family — not because they're all specification languages, but because
they're all attempts to express the spirit independently of the letter.

**Meng:** In conversation with Oliver Goodenough we elaborated the idea of
"squeezing out the deontics" from a contract. Two illustrations, one more glib
than the other. Gneezy and Rustichini say in "A Fine is a Price": the daycare may
think a fine will strengthen the "you must pick up your child on time". Instead it
weakens it because parents realize the policy is now an amoral state machine. The
glib illustration: we recall the exchange from Saki's "The Schartz-Metterklume
Method":

> "You must be Miss Hope, the governess I've come to meet," said the apparition,
> in a tone that admitted of very little argument.
>
> "Very well, if I must I must," said Lady Carlotta to herself with dangerous
> meekness.

**ChatGPT:** That's a wonderful pair of examples, because they point in opposite
directions while illustrating the same phenomenon.

The phrase "squeezing out the deontics" is quite evocative. In computational
terms, it sounds like transforming "Alice ought to do X" into "If Alice does not
do X, transition to state Y." The obligation disappears and only the state machine
remains.

That's exactly the concern in the *A Fine is a Price* example. The daycare
operator believes they are strengthening the norm "Parents must collect children
on time" by adding a sanction "Late pickup costs $10." But the famous result is
that many parents appear to reinterpret the rule as "Late pickup is available for
purchase at $10." The deontic *ought not* has been compiled into *may, with fee*,
and something important is lost in translation. The normative statement has been
lowered into an operational semantics. The resulting machine behaves differently
because the parents are no longer evaluating their actions against a social norm
but against a price schedule. It's a kind of semantic degradation.

The Saki example is much funnier because it runs the compiler in the opposite
direction. When Lady Carlotta says "Very well, if I must I must," she is
performing a deliberate type error. The speaker intends "must" in the epistemic
sense ("You are Miss Hope. Therefore you must be the governess" — really, "I infer
that you are the governess"). Lady Carlotta chooses to hear it as a deontic ("You
are required to be the governess") and replies as though she has reluctantly
accepted the obligation. The comedy comes from switching semantic domains. In
modal logic terms, she takes `□ₑ p` (epistemic necessity) and responds as though
it were `□ₒ p` (deontic necessity). The joke works because English uses the same
modal verb for both.

What's interesting is that both examples involve a transformation between
modalities. The daycare transforms *obligation* into *costed transition*; Lady
Carlotta transforms *inference* into *obligation*. In each case, the surface
language remains intact but the underlying modality changes.

That observation makes me wonder whether "squeezing out the deontics" is really a
special case of a more general phenomenon. Perhaps contracts, laws, and
specifications all contain several kinds of modality:

- deontic ("must", "may", "shall")
- temporal ("before", "after", "eventually")
- epistemic ("knows", "believes")
- operational ("if X then Y")

A compiler from law to code tends to preserve the operational and temporal
components because machines are good at state transitions. What is difficult is
preserving the deontic component. After all, a finite-state machine has states and
transitions. It does not naturally have guilt. Or excuse. Or justification. Or
good faith. Or abuse of rights. Those are not state transitions; they are
evaluations *of* state transitions.

Which brings us back to your "letter and spirit" distinction. The spirit may be
precisely what remains after you've squeezed out all the operational content. Or,
put differently: the letter tells you what transitions are allowed; the deontics
tell you which transitions are admirable, blameworthy, excused, required, or
forbidden; the spirit tells you *why* those evaluations exist. A purely
operational rendering of a contract risks collapsing all three levels into one.

The daycare's mistake was to assume that a sanction and an obligation are
interchangeable representations of the same thing. Gneezy and Rustichini's result
suggests they are not. In type-theoretic language, they treated `Obligation(A, X)`
and `Price(A, X, $10)` as isomorphic. The experiment suggests they are not even
close. The inhabitants of the two types behave very differently. And lawyers,
judges, and parents all seem to know this instinctively, even when economists and
software engineers are tempted to compile one into the other.

**Meng:** I introduced the notion of "bounded deontics" as a way of formalizing
the vernacular "oh yeah? Or else what, huh?" Basically every deontic expression is
indexed to some goal term; sometimes the goal is explicit; sometimes it is
implicit. "I must return the library book on time … if I want to avoid paying a
fine." The avoidance-of-fine is the goal. And the background theory generally
asserts an implicit goal term of "… if you want to stay out of jail / remain in
good standing with the tax man / not attract any fines." But sometimes these
implicit goals are unstated, as with Saki, and may include "… if you want to have
good health / good to heaven / seek the approbation of the public". For the
purposes of L4 it is sufficient to interpret implicit goals to explicit goals and
then once we do that we can shoehorn the whole shebang into LTL where the "musts"
really belong.

**ChatGPT:** That's a very elegant move, and it strikes me as more radical than it
first appears.

Most deontic logics take "ought" or "must" as primitive. They spend decades
wrestling with paradoxes: the Good Samaritan paradox, Chisholm's paradox,
contrary-to-duty obligations, Ross's paradox, and so on.

Your bounded-deontics move is almost a deflationary account of obligation. Instead
of `O(p)` you have something closer to `Goal(g) ⇒ Must(p)` or perhaps even
`Must(p, g)`, where the obligation is indexed by the goal it serves.

The vernacular test "Or else what?" is actually a remarkably powerful semantic
probe. Children understand it immediately. Parent: "You must eat your vegetables."
Child: "Or else what?" The child is asking for the hidden goal term. The parent's
answer may be "So that you grow up healthy" or "So that I stop nagging you" or "So
that your grandmother approves." Each answer reveals a different semantics for the
same surface "must." Viewed this way, the modal verb isn't carrying much meaning
on its own. The real semantic content lies in the goal structure.

And that explains why Saki's joke works so well. When the speaker says "You must
be Miss Hope," there is no obvious goal term — the modal is epistemic. Lady
Carlotta mischievously pretends there is a hidden goal ("…if I wish to satisfy
your expectations") and suddenly the statement becomes deontic. The joke is a kind
of illicit goal insertion.

What I find particularly interesting is that your move resembles a transformation
that happens in AI planning. Classical planning doesn't talk much about
obligations. It talks about states, actions, goals. The planner chooses actions
because they lead to desired goal states. From that perspective, "You must file
your tax return" becomes "If your goal is to remain compliant with the tax
authority, then filing is required." The "must" is derived rather than primitive.

And once you've done that, I can see why LTL starts to look attractive. Instead of
representing `Obligated(file_return)` you can represent something like
`Maintain(GoodStanding)` together with temporal constraints such as
`G(IncomeReported -> F(ReturnFiled))`, or whatever the appropriate formulation is.
The obligation has been compiled into reachability and maintenance properties.

In a sense, you're replacing deontic operators with teleological operators. Not
"What must be done?" but "What goals are being pursued?" Then the "must" emerges
from the combination of goals and temporal structure. That feels very close to how
humans actually reason. If I say "I must catch my flight," nobody imagines a
cosmic obligation operator hovering over me. What they infer is: my goal is to be
in Tokyo tomorrow; missing the flight frustrates that goal; therefore I "must"
catch it. The necessity is contingent on the goal. Which is precisely what your
bounded-deontics terminology captures.

The place where I'd be curious is the edge cases. Some legal obligations seem
intentionally designed to resist the "or else what?" analysis. For example,
constitutional rights discourse often treats some norms as intrinsic rather than
instrumental: "You must not torture." The legal system may attach sanctions, but
lawyers frequently insist that the wrongness is not reducible to the sanction. In
your framework, I suspect one would still model this by introducing a goal term —
"preserve human dignity," or "maintain constitutional order," or "satisfy the
fundamental commitments of the polity." But then the interesting question becomes
whether those goals are merely engineering conveniences for the formalism or
whether they correspond to genuine jurisprudential commitments. For L4, though,
that may not matter. As you put it, if the purpose is to obtain an executable
semantics, then finding an explicit goal term that supports the obligation may be
enough.

In that sense, bounded deontics reminds me of Van Roy's move: take something that
appears primitive and indivisible, crack it open, and reveal the smaller structure
inside. Van Roy asks: *What concepts are hidden inside a paradigm?* Bounded
deontics asks: *What goals are hidden inside an obligation?* And the answer to both
questions is often: more than people realize.
