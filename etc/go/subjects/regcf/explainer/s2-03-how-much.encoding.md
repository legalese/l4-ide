**The statute is ambiguous, the regulator glossed it twice, and the encoding
resolves neither.** Section 4(a)(6)(B) of the Securities Act says only that an
investor may put in "a given percentage of the annual income or net worth of
such investor, as applicable". The Commission's own note, quoted in the corpus
at the site, records that the statutory
[language does not expressly provide that the investor use the lesser of annual income or net worth](src:jl4/examples/legal/regcf/regcf.l4#L386-L387 "verbatim").
It chose "lesser" in the adopting release, held that reading for five years, and
then reversed it.

An encoding has to do something with that. What this one does is refuse to pick:
the measure is a **dated function** that selects `greater of` from the amendment
date and `lesser of` before it, and both readings stay live and testable
forever. The consequence is asserted at both ends — the same investor is capped
at [$10,000](src:jl4/examples/legal/regcf/regcf.l4#L912) today and was capped at
[$3,000](src:jl4/examples/legal/regcf/regcf.l4#L1182) under the earlier rule, a
factor of more than three.

**An exhaustiveness claim the prose does not make.** Limb (i) applies "if
either…"; limb (ii) applies "if both…". The encoding notes, and then relies on,
the observation that
[The two are exhaustive and mutually exclusive, so one boolean selects between them.](src:jl4/examples/legal/regcf/regcf.l4#L403-L404 "verbatim")
That is a reading. It happens to be an obviously correct one, but it is the kind
of step that vanishes into prose and cannot vanish into code: something has to
decide what happens when neither limb matches, and here the answer is that
nothing can. It is pinned by boundary assertions on either side of the cut
point.

**One number decides two different gates.** The aggregate a company has raised
feeds both the offering ceiling in Rule 100(a)(1) and the financial-statement
tier in Rule 201(t), because the two provisions compute the same quantity. The
encoding binds it once and both consumers read that one function. The saving is
not keystrokes; it is that the two can never drift apart, which in a hand-drafted
document they eventually do.

**What the type system refused.** Renaming the record fields to drop a redundant
leading verb once made a test fixture collide with a field of the same new name:
the record `InvestorFacts` declares
[`an accredited investor` IS A BOOLEAN](src:jl4/examples/legal/regcf/regcf-wizard.l4#L123 "verbatim"),
and the fixture that had been called the same thing now had to be something
else. It was resolved by taking Rule 100(a)(2)'s own noun, so the fixture is
[`an accredited purchaser` MEANS InvestorFacts WITH](src:jl4/examples/legal/regcf/regcf-wizard.l4#L680 "verbatim").
That is a real type error and not a style complaint, and it is the smallest
possible illustration of the difference this whole exercise is about: in prose,
two things with the same name are a reader's problem, and here they were the
checker's, at the moment of writing rather than the moment of dispute.
