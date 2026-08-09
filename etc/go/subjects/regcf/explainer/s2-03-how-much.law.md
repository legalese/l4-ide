Two ceilings apply at once, and they are ceilings on different people.

**The issuer's ceiling.** Rule 100(a)(1) caps the aggregate raised in reliance
on section 4(a)(6) over the preceding twelve months at
[$5,000,000](src:jl4/examples/legal/regcf/regcf.l4#L151). Only prior sales made
under this exemption count towards it. Money raised some other way — a
conventional venture round sold privately to professional investors, say — does
not eat into this ceiling, because it was not sold under section 4(a)(6).

**The investor's ceiling.** Rule 100(a)(2) caps what one person may put into
_all_ Regulation Crowdfunding offerings, from every issuer, over the same
rolling twelve months. It is the provision most likely to matter to a member of
the public, and it is a formula rather than a table.

There are two limbs, and which one applies turns on a single cut point,
at time of writing ({{as_of}}) [$124,000](src:jl4/examples/legal/regcf/regcf.l4#L163):

- **If either annual income or net worth is below the cut point**, the cap is the
  greater of [$2,500](src:jl4/examples/legal/regcf/regcf.l4#L172) and five per
  cent of the greater of income and net worth.
- **If both are at or above the cut point**, the cap is ten per cent of the
  greater of the two, itself capped at
  [$124,000](src:jl4/examples/legal/regcf/regcf.l4#L182).

**An accredited investor is subject to no Regulation Crowdfunding cap at all.**
That is true today and was not always true — the carve-out arrived with the
substantive amendment described under **Time**. "Accredited investor" is not
defined in this Part; the wizard that asks the question puts it as
[Are you an accredited investor, as Rule 501 of Regulation D defines that term?](src:jl4/examples/legal/regcf/regcf-wizard.l4#L123 "verbatim"),
which is where the definition lives. The carve-out itself is dated: the corpus
records that
[an accredited purchaser is subject to no Reg CF investment limit at all. Added 2021-03-15 by Release 33-10884](src:jl4/examples/legal/regcf/regcf.l4#L446-L448 "verbatim"),
and before that date the limit applied to every investor without exception. This
is the sentence in every plain-English summary of Reg CF that is right today and
silently wrong about any transaction before that date.

A worked example the corpus asserts and re-checks on every run: an investor with
income of [$60,000](src:jl4/examples/legal/regcf/regcf.l4#L1033) and net worth of
[$200,000](src:jl4/examples/legal/regcf/regcf.l4#L1033) falls in the first limb —
income is below the cut point — so the cap is five per cent of the _greater_
figure: [$10,000](src:jl4/examples/legal/regcf/regcf.l4#L1033).

The word "greater" in that last sentence is not a detail. Until the amendment
described under **Time**, below, both limbs read _lesser_ of income and net
worth, and the same investor's cap was
[$3,000](src:jl4/examples/legal/regcf/regcf.l4#L1390).
