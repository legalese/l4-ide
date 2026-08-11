You have now seen what this thing does. This section is about how it is made,
what each part of this page is for, and what the words mean — because the rest of
the page uses a vocabulary that belongs to this project and to nobody else.

**A warning about what follows.** Nothing here is subject-specific. It describes
the process that produced this page, and it would read identically in a report
about a tax statute or a lease. If you only came for the law, skip to **The
rules**; nothing below is needed to follow it.

### What formalising a law actually is

Writing a rule as code is not translation, and the difference is the whole
subject. Prose survives on unresolved questions — a reader supplies an answer
without noticing there was a question. Code cannot: every choice has to be made
before anything will run at all.

So formalising a law does three things, in this order of usefulness:

1. **It finds the questions the prose let you skip.** Most of them are boring and
   have one sensible answer. Some are not, and those are the interesting output —
   not the code.
2. **It makes the rule answer.** Facts in, consequence out, with the reasoning
   available rather than asserted.
3. **It makes the rule feed other systems.** A rule that computes can be exported
   into tools that already exist, so the rule and the system that implements it
   cannot drift apart quietly.

**What it does not do.** It does not decide anything the source leaves open. Where
the law is genuinely undetermined, the encoder picks a reading in order to compute
at all — and the honest response is to say which, not to pretend the question was
settled. That is what **Where the law is unsettled** is for.

### What the process is, and why each step is there

The pipeline that produced this page runs as a sequence of stages, each writing a
receipt as it goes. The reasons matter more than the names:

- **Preflight** records what the run is running against — which files, at which
  content hashes. It exists because every later claim is a claim _about a
  particular version of something_, and a report that cannot say which version is
  not checkable.
- **Ingest and sweep** obtain the source text and search for the material around
  it — the amendments, the guidance, the interpretive letters. The sweep's
  output is mostly the record of **what it did not find**, which is why this page
  has a section called _What was never searched_. An exclusion nobody sizes is an
  exclusion nobody believes.
- **Encode**, or on a replay run **check**, produces or validates the rules as
  code. This is where the questions in step 1 above surface.
- **Forks** collects those questions into a register: both readings, the one
  taken, the reason. It is a separate stage rather than a drafter's footnote
  because a disclosure that depends on somebody remembering to write it is not a
  disclosure.
- **The gate** is where a human either signs off on the judgements a machine
  cannot make, or explicitly waives that requirement with a stated reason. There
  are two, and only one of them can be waived:
  [HG1 is the only waivable gate. HG2 guards anything outward-facing](src:etc/go/go.sh#L29 "verbatim").
  The header of this page tells you what happened to the first. A waiver is not
  an absence; it is a verdict with somebody's reason attached.
- **Tests** run the rules against cases with known answers —
  [tests, without trusting the exit code](src:etc/go/phases/p6-tests.sh#L2 "verbatim"),
  because a suite that runs no tests at all exits successfully.
- **Projections** export the same rules into other formats: diagrams, decision
  tables, process models, published legal XML. Each one is generated, never
  drawn. Each also reports what it **could not** carry across, which is the more
  interesting half.
- **Verification** attempts to prove properties over the rules rather than sample
  them. It is the newest and least complete part of this.
- **The report and this page** are the last two stages. They are siblings from
  one journal: an audit report for somebody checking the work, and this one for
  somebody reading the law. Where they disagree, the audit report governs and
  this page has a defect.

### What each part of this page is for

Every section of this document is a fixed slot, present in every report of this
kind. A slot that has nothing to say says so, in place, with a reason. It is
never dropped — because a section that quietly vanishes is indistinguishable
from a section nobody thought to write, and the reader cannot tell which happened.

| section                          | what it is for                                                                              |
| -------------------------------- | ------------------------------------------------------------------------------------------- |
| _What this is, and who it binds_ | the law in ordinary language, and the parties it applies to                                 |
| _Use it_                         | how to run the encoding yourself and get answers to your own questions                      |
| _Pictures_                       | the generated diagrams, each showing something the others hide                              |
| _How this works_                 | this section                                                                                |
| _The rules_                      | the law walked through, with the encoding of each part alongside it                         |
| _Time_                           | how the rules changed, and how to ask a question as of a past date                          |
| _Where the law is unsettled_     | the questions the source does not decide, and the reading taken for each                    |
| _Limits_                         | everything the encoding does not do, listed so nobody discovers it later and feels oversold |
| _What was never searched_        | the boundary of the research, stated as a boundary                                          |
| _How to check this document_     | the provenance of every claim above, and the commands to re-derive this page yourself       |

**Why the order is this and not the obvious one.** The instinct is to explain the
language, then the encoding, then what it is good for — mechanism before payoff.
That order serves the writer, who already knows why it matters, and fails the
reader, who does not yet. So the applications come early, and the machinery comes
after them, at the point where a reader has a reason to care.

### The words

Terms of art used throughout, in the sense this project uses them.

**Corpus** — the rules written as code, taken together with the tests and notes
that ship beside them. Not a synonym for the law itself.

**Encoding** — the act of writing a rule as code, and also its result. "The
encoding says" is a claim about the code, never about the law; the two are kept
apart deliberately, and this page marks the join.

**Isomorphic** — an encoding whose structure follows the source's structure, so
somebody can read them side by side, provision by provision, and check one
against the other. The alternative — a correct answer arrived at by a shape
nobody can trace back to the text — is not reviewable, and unreviewable is the
one thing a legal encoding may not be.

**Constitutive and regulative** — the two kinds of rule. A constitutive rule says
what something _is_ or _counts as_: an eligibility test, a definition, a
calculation. You evaluate it and you are done. A regulative rule says what
somebody _must, may, or must not do_, usually by some deadline. It has a life —
it comes into being, it is complied with or breached, it can renew. Only the
second kind can be drawn as a process or a state machine, which is why some rules
in this report get a workflow diagram and others cannot.

**Deontic** — pertaining to obligation, permission, and prohibition; the
vocabulary of regulative rules. A deontic rule is not true or false, it is
complied with or not.

**Projection** — a view of the same rules in another format, generated from the
encoding rather than drawn by hand. A diagram, a decision table, a process model,
a published-standard XML file. The point of generating them is that they cannot
drift from the rules they depict; the point of reading them is that each makes
something visible the others hide.

**Fidelity** — how much of the meaning survived a projection. Every export in
this pipeline writes a fidelity note saying what it could not carry across and
what a reader consequently loses. An export with nothing to declare is usually an
export that did not look.

**Fork** — a place where the source does not settle a question and the encoding
had to pick a reading in order to compute anything. Registered with both
readings, the one taken, and why. A fork is not a defect in the encoding; it is a
property of the source that the encoding made visible.

**Ladder** — a diagram of one decision's logical shape, drawn as a circuit: `AND`
in series, `OR` in parallel, each leaf carrying the source's own words. It shows
a missing limb at a glance.

**Golden** — a stored copy of some output, kept so that any change to it has to
be noticed and approved rather than slipping through. When output and golden
disagree, somebody decides which is right; nothing is updated silently.

**Gate** — a point where the process stops and requires a human. This pipeline
has two: one for judgements a machine cannot make, and one for anything that
reaches the outside world. The second is never waivable.

**Replay and de novo** — the two ways of arriving at an encoding. A replay checks
an encoding somebody already wrote. A de novo encodes the same source
independently, without looking at the first, so the two can be compared — and a
disagreement between them is a finding neither could have produced alone.

**Slot** — a fixed section of this report, listed in the table above. Named
because the structure is fixed in advance and a report cannot quietly omit one.

**Provenance** — the record of what each passage of this page was written from,
and when. Kept so that when a source file changes, every passage written against
the old version is flagged rather than left silently stale. If you see a banner
above a section saying its source moved, that machinery is working.

### The one thing to be suspicious of

Every number on this page is either read out of the run's own records or is a
quotation whose source line was re-opened and matched while the page was being
built. That bounds transcription error. It does **not** bound misreading: a
quotation can keep matching its source while the sentence around it stops being
true, if somebody edits the source in a way that leaves the quoted words in
place. When that happens, the only thing that catches it is a person re-reading
the passage against the changed source — so the sections here carry banners
saying whether anyone has, and whether the source has moved since.

The document tells you, section by section, how far its own checking goes. That
is the section called **How to check this document**, and it is the one to read
if you intend to rely on any of this.
