# Blog style guide

**STATUS 2026-09-14: IN USE.** Written on 2026-09-13 before any post existed; applied since to the
first drafts and their persona reviews, which changed it (length ceiling raised to 3,500; footnotes
welcomed; the NRF stanza; the field-research rule; the persona pass in §7). Expect it to keep
changing as posts meet it. Rulings marked _proposed_ are Meng's to make; everything else is copied from a source
named inline and re-checked on the date above.

## 1. Who reads this, and what for

**First reader: the senior programmer who still reads.** Not the lawyer, not the newcomer, not
the ICAIL regular. This is the same reader `paper/README.md` §Positioning settles on for the
Book, for the same three reasons (it is the strategy on record; programmers build the
ecosystem; programmers already buy argument-books). The blog exists to _prefigure_ the papers
for that reader — to put the positions in the open, in plain register, before the academic
version lands — and to be crawled in full by the second reader, the model.

So the reader is fluent in types, tests, invariants and race conditions, and new to deontics,
defeasibility and interpretation. Explain the law; do not explain the software.

**What a post is not.** Not a tutorial (those live in `doc/` and are pitched at a nontechnical
first-time critical thinker — the vocabulary rules there, "never say parameter", do _not_ apply
here). Not reference (the skill and `doc/reference/` are the reference). Not marketing. And,
per the Book's test: nothing in a post should be a thing the reader would rather ask a model.
Three paragraphs on what TLA+ is fail that test; a link passes it. What the model cannot supply
is our evidence — the pilots, the bugs we found, the counts we ran — and that is what a post is
made of.

**Third reader, over the shoulder: the lawyer and the law review.** The blog is not written for
them, but it will be read by them, and it must not say anything the paper would have to walk
back. If a post overclaims, the paper inherits the correction. The footnotes are for this reader
(§6): law is a citation discipline, and a post with a proper apparatus is one the law review can
cite.

## 2. Voice

**The target is "SF author does nonfiction."** Meng's brief (2026-09-13): Gibson's _Disneyland with
the Death Penalty_, Asimov's science essays, Doctorow's polemics, and the technology writing
that runs in _The Atlantic_ and _The New Yorker_ — "technically sound, stylistically first-rate,
entertaining, educational, and strikingly relevant to the lay reader." Not the default register a
language model writes in when nobody has told it otherwise. That default has recognizable tics,
and they were already in the first draft of this file and are already in this repo's prose (§2.3).

### 2.1 What the exemplars actually do

Five pieces were read and measured on 2026-09-13 (texts in the session scratchpad; counts are
from a script over the extracted text, so treat them as ±10%):

| Piece | Words | Median sentence | Questions | First-person sentences | Opens on |
| --- | --- | --- | --- | --- | --- |
| Gibson, "Disneyland with the Death Penalty", _Wired_ 1.04, 1993 | 4,970 | 21 (p90 39, max 127) | 14, mostly dialogue | 46 of 228 | a Hollywood producer's one-liner, in an office off Rodeo Drive |
| Asimov, "The Relativity of Wrong", _F&SF_ 1988 | ~2,500 | 19 (p90 38) | 19, Socratic ("How much is 2 + 2?") | 19 of 205 | a reader's letter "in crabbed penmanship" |
| Doctorow, "Tiktok's enshittification", _Pluralistic_, 21 Jan 2023 | — | short-to-long, "Then, they die." | many | "I", "we", "you" | the thesis as a four-beat sequence |
| Somers, "The Coming Software Apocalypse", _The Atlantic_, 2017 | 9,447 | 17 (p90 37) | 5 | 36 of 467 | a 911 outage, 37 calls, a kitchen knife, "The man fled." |
| Somers, "A Coder Considers the Waning Days of the Craft", _New Yorker_, 2023 | 4,780 | 15 (p90 27) | 12 | 157 of 296 | his wife three weeks from giving birth |

**Meng's pick as the primary exemplar (2026-09-13): Somers, _The Coming Software Apocalypse_** —
"good writing on formal verification; thumbs up from me for style." It is also the piece post 5
already cites as its on-ramp, so the blog's model and its subject overlap: when in doubt about a
paragraph, ask whether Somers would have written it that way.

What the five have in common is worth more than the numbers:

- **They open on a particular, never on the thesis.** A letter, a quote, an outage, a pregnancy.
  Doctorow is the exception and proves it: his thesis _is_ a particular sequence of events with a
  body count ("first, they are good to their users … Then, they die."). None of them opens by
  announcing what the piece will show.
- **The narrator has a body in a place.** Gibson is in a taxi whose speed-limit bell is chiming
  ("Singapore very clean city."); Somers is on a long-haul flight with a Borland C++ CD-ROM;
  Asimov is reading a letter and sighing. First person is _witness_, not opinion.
- **Terms are explained in a subordinate clause, and the sentence keeps moving.** Somers: "A
  compiler translates code you write into code that the machine can run; I had been struggling
  for days to get this one to work." One clause of definition, then back to the story. Nobody
  stops the piece to teach.
- **Numbers name their source in the same sentence.** Doctorow: "Forbes's Emily Baker-White
  broke a fantastic story … citing multiple internal sources"; Gibson pastes the _South China
  Morning Post_ clipping, dated 4/29/93, into the text; Somers: "The 911 outage, at the time the
  largest ever reported, was traced to software running on a server in Englewood, Colorado."
- **Questions are asked to be answered, on the next line.** Asimov's "How do you spell sugar?"
  is followed by the spellings. Not one of the five asks a question to make the reader wait.
- **Short sentences at paragraph ends are facts or speech, not epigrams.** Gibson's 23 short
  closers out of 82 paragraphs are things like "He asked where I was from." and "You come for
  golf?" Somers: "The man fled." "I did not cross." They end on something that happened.
- **The concession is in the writer's own voice.** Asimov, before he argues: "I am very aware
  of the vast state of my ignorance and I am prepared to learn as much as I can from anyone."
  Gibson, late at night: "what might the future prove to be, if this view should turn out to be
  right?" It is not a paragraph headed "Limitations".
- **The metaphor is done once, and it is concrete.** "Disneyland with the death penalty" lands
  mid-piece, after "feels like, well, Disneyland." — the hedge sets it up. Doctorow's
  "paperclip-maximizing artificial colony organism that treats human beings as inconvenient gut
  flora" is a polemic, and it is also a specific claim about incentive structure. Gibson ends on
  the Walled City of Kowloon "sucking in energy like a black hole" — an image of a place he has
  just described, not a swap of the subject for a figure of speech.
- **Sentence length varies a lot.** Median 15–21, but every one of them runs to 100+ words when
  a list or a scene wants it, and drops to three when a fact does. Uniform 20-word sentences are
  the machine tell.

### 2.2 The specimen, and what it does instead

The counter-example Meng supplied (scienceblog.com, Fukushima boar–pig hybrids, read
2026-09-13) does the opposite on every line above, and it is worth naming the moves so they can
be recognized in a draft:

- **The title is the abstract.** Fifty-odd words that state the finding, the mechanism and the
  twist. Nothing is left for the piece to do.
- **The writer narrates the reveal instead of performing it.** "The results keep saying
  something odd." "A follow-up study … found the accelerator hiding in the machinery." "The
  explanation is the one in this story's title, and it is elegant." The reader is told a thing is
  surprising, or elegant, rather than being surprised.
- **Anticipation superlatives.** "Faster than anyone predicted."
- **The epigram as the whole personality.** Paragraph after paragraph ends by swapping the
  subject for a figure: "The maternal surname survives in the mitochondria; the estate is spent."
  "They survive mostly as a rhythm." Epigrams are fine — Gibson's title is one — but here they are
  the only closer the piece has, so every paragraph ends on the writer rather than on the pigs.
  Meng's ruling (2026-09-13): epigrams are ok; they just must not carry the piece.
- **The em-dash aside that names the point.** "The pig's signature gift to its descendants —
  hurry — is the engine erasing everything else." Somers uses an em-dash every sixth sentence, so
  the dash itself is not the tell; the dash that _labels_ the point is.

### 2.3 Blocklist, and the lint

The following are banned from posts. `blog/lint-tics.sh` greps for them and fails loudly on the
hard list; it warns on the soft one. It was calibrated against the five exemplars on
2026-09-13 — a rule that fired on Gibson or Asimov was removed.

**Hard (fail):** _honest_ / _honestly_ as an intensifier ("the honest answer"), _load-bearing_
(outside structural engineering), _crucially_, _the real X is_, _here's the thing_, _but that's
not the …_, _keep reading_, _the twist_, _the kicker_, _let that sink in_, _it's worth noting_,
_delve_, _tapestry_, _testament to_, _underscore_ (verb), _robust_, _nuanced_, _at its core_, _in
a world where_, _elegant_ said of one's own explanation, and any sentence shaped "It's not X — it's
Y" / "This isn't about X".

**Exempt: quotations and cited titles.** A source's own words are never altered or omitted to
satisfy the lint — a paper whose title contains "robust" is cited by its title. (Ruled 2026-09-14
after a reviser left a title out of a footnote for this reason.) The lint skips quoted and
italicized spans.

**Soft (warn, then a human looks):** _genuinely_ and _leverage_ (both demoted from hard on
2026-09-13: Gibson uses _genuinely_ twice, Somers _leverage_ once), _quietly_, _remarkably_, _of
course_, _in other words_; a title over twelve words; and an **epigram ratio** over 25% —
the share of paragraphs whose final sentence is six words or fewer with no digit, quotation mark or
proper noun. The exemplars run 6–19% (Somers 2017: 6/95; Gibson: 7/82; Somers 2023: 9/48;
Asimov: 0), so a post above a quarter is leaning on the figure. Individual epigrams are not
flagged; they are allowed.

The lint is the loud failure. The silent ones — a paragraph that narrates its own reveal, a
closer that ends on the writer instead of the subject, a definition that stops the story — need a
reader, and §4's review table is where they are looked for.

### 2.4 Inherited from the earlier draft, still true

- **Evidence first, then the frame.** "We found a race condition in a law" before any word about
  deontic logic. The pilots — the government double-bind, the insurance payout formula, the New
  Zealand benefits calculator with a handful of tests — are the opening, not the appendix.
- **Numbers carry their denominator.** "246 startups in contract management … out of a total
  population of 3,076." Not "hundreds".
- **One analogy per idea, from an adjacent field, used once.** PostScript; the Adobe suite versus
  Word; Grab and the taxi drivers; _zenzizenzizenzic_.
- **Theory names are tools, not credentials.** Christensen, Moore, Arthur, Hohfeld, Hart appear
  with the idea stated in the same clause, so a reader who does not know the name loses nothing.
- **First person is fine.** "We" is the project; "I" is Meng when the sentence is about his
  experience (the Berkman year, the CodeX year). No hedging in the passive.
- **Acronyms are spelled out on first use, every post** — "Contract Lifecycle Management
  (CLM)", then CLM. A standing pet peeve, ruled for `doc/` on 2026-09-04.
- **US spelling** (ruled by Meng, 2026-09-13). `paper/*.md` leans British 34:9 on _formalise_;
  the blog does not follow it. Quotations keep their source's spelling.

## 3. The shape of a post

**One post, one claim,** stated in a sentence the reader could repeat to a colleague. The
working titles in `README.md` are already that shape ("Specs are code", "The missing test
suite"). If the claim will not fit in a title, it is two posts.

**2,000–2,500 words as the target; 3,500 as the ceiling.** Below 1,500 it is a note. The ceiling
was 2,500 until post 1 came in at 3,200 with its critics asking for more, not less; Meng
(2026-09-14): "If we have to go wordier I'm okay to increase the length limit." Length is earned
by evidence and concession, never by survey — when a post is over target, the literature moves
to footnotes first. Post 5's material, for example, is a paper's worth; the post gets the three
beats and points at the paper for the rest.

**Cold open on evidence.** A bug, a number, a comic, a sentence from a statute. Then back out
to the claim. Never open with "In this post I will…".

**Three beats, and the third concedes something.** The pattern that came out of post 5's
planning generalises: (1) what was found, (2) what it cost and who could do it, (3) what the
evidence does _not_ show. Beat three is what makes a technical reader trust beats one and two.
A post with no beat three reads as a pitch. The "what would overturn this" paragraph that
closes `paper/README.md` §Positioning is the same move and is welcome at the end of a post.

**Hand off.** Every post names the paper facet it prefigures (see the arc table in
`README.md`) and, once that paper exists, links it. A post may not claim more than the paper
will be able to back.

**One case may carry two arguments — in two posts.** Robodebt is the failure case in post 7 and
a political-economy case in the standalone. That is fine. Within one post, one case makes one
argument.

## 4. Claims and citations

The user-level `CLAUDE.md` rules on written claims apply in full. The ones that bite a blog
post:

- **Take the sounding when the claim becomes durable.** A citation is verified _at the moment
  it enters the post_, not when it entered the plan. Post 5's list was checked live on
  2026-09-13; that check expires when the draft starts. Items marked `UNVERIFIED` or `NOT
  READ` in the plan have not been checked even once — a post cannot go out carrying one.
- **Never sharpen a borrowed claim.** If the source says "at least 16 critical issues", the
  post does not say "dozens". If the settlement figure is reported inconsistently ($548.5m vs
  ~$1.8bn for Robodebt), the post says so or omits the number; it does not pick the larger one.
- **On-ramp, not authority.** A popular piece (Somers in _The Atlantic_, a Fowler bliki entry)
  may be cited as the way in for a reader, never as the evidence for a claim. Say which it is.
- **Say the critique ourselves.** Where a source cuts against us — Woodcock & Larsen on
  survivorship bias in formal-methods case studies — the post states the point in its own words
  and then cites; it does not hide the point in a footnote or let the citation carry it.
- **Read what you cite.** A 403 from a publisher is bot-blocking as often as it is a paywall
  (Woodcock & Larsen turned out to be CC-BY). Do not quote from an abstract.
- **Know the field, past and present, before drafting.** Meng (2026-09-13): the author should "web
  search the past and present of the part of the field it's writing about, not just parrot the
  paper content but show familiarity with the broader context." Concretely: before a word is
  drafted, find who did this first, what the canonical prior work is, what was tried and
  abandoned, and what is happening now — in industry, in government rules-as-code programs, in
  research — and weave it in the way Somers weaves in Lamport's biography: a name, a date, a
  source, in passing. A reader who knows the field must never catch a post presenting as new
  what is old. The review pass has a persona for exactly this (§7).
- **Every number carries a date and a source, inline.** The tables in `paper/README.md`
  §Positioning are the house form: figure, period, "checked against", and a note when the
  source is hearsay or contradicted.

**Where the review time goes: the silent failures** (§2.3's lint catches the loud ones). A broken link fails loudly — a checker
catches it, a reader notices. The failures worth a reviewer's attention return exit code 0:

| Silent failure                                         | What catches it                                     |
| ------------------------------------------------------ | --------------------------------------------------- |
| A wrong number that reads confidently                  | Re-derive it from the cited source before publishing |
| A quote attributed to the wrong author or paper        | Open the source; find the sentence                  |
| A planned thing described in the present tense         | Grep the post for "we have", "L4 supports"; verify each against the tree |
| An analogy that was true of the source but not of law  | Beat three                                          |
| A claim the paper will not be able to back             | Read the facet's `DESIGN.md` / outline first        |

## 5. L4 in a post

Any L4 shown must exist in a tree and pass the `l4` binary — cite the path
(`jl4/examples/legal/regcf/regcf.l4`, or the `legalese/canon` repo for encodings of a body of
law, which is where new encodings go). Do not write L4 in prose for convenience; the reader
will paste it. If the snippet was pretty-printed rather than copied, run the evaluation
differential in the l4-ide `CLAUDE.md` §3.2.1 — re-parsing is not re-meaning.

Prefer the worked cases the papers already use — _Poh Yuan Nie_, Reg CF, the British Nationality
Act, the Jersey instruments — over new examples. One corpus, not two.

## 6. Mechanics

- **Files:** `blog/posts/NN-slug.md`, `NN` from the arc table; the standalone is `S1-…`.
  Plain Markdown with YAML front matter, so it ports to whatever platform is chosen.
- **Front matter:** `title`, `status` (`draft` | `review` | `published`), `date`, `facet` (the
  `paper/` directory it prefigures), `words`, `license` (`CC-BY-NC-4.0`), `sources_checked` (date of the last full
  citation pass). Then, as the first line of the body, the status header in the house form —
  `**STATUS <date>: DRAFT — …**` — because a reader of the raw file sees that before any
  front matter renderer does. Present tense, dated, per l4-ide `CLAUDE.md` §4.1.
- **Headings** in sentence case. Few of them: a 2,000-word post wants three or four.
- **Links inline for the web reader; footnotes and academic citations for the scholarly one —
  use both, liberally.** L4 has been an academic research project at SMU for six years (Meng,
  2026-09-13), and the posts prefigure papers; a post that cites the way a paper cites is in
  character, not out of it. Markdown footnotes (`[^n]`) carry the apparatus — the DOI, the page,
  the caveat about what the source does and does not show. A "Sources" list at the end still
  repeats every citation with its check date, because that list is what the fact-check reads.
- **Funding acknowledgement, verbatim, as the last thing in every post** (after Sources):

  > This research is supported by the National Research Foundation (NRF), Singapore, under its
  > Industry Alignment Fund – Pre-Positioning Programme, as the Research Programme in
  > Computational Law. Any opinions, findings and conclusions or recommendations expressed in
  > this material are those of the author(s) and do not reflect the views of National Research
  > Foundation, Singapore.

  `blog/check-post.sh` fails a post that lacks it or alters it.
- **No images that carry the argument.** A ladder diagram or a table may illustrate; the text
  must stand without it (second reader: the model).
- **Titles are sentences,** as in the arc table. Title case is not used.

## 7. Process

1. Draft in a worktree (`~/src/legalese/l4wt/<name>`), never the reference checkout.
2. Run `blog/check-post.sh` (structure, stanza, spelling, word count, and the tic lint) until it
   is clean. Then the persona pass: six readers critique the draft — the target programmer and
   the SME founder for confusions; a law-review editor, a formal-methods reviewer and a
   computational-law veteran (unearned novelty: "this was Sergot in 1986") for unearned claims;
   a magazine editor for voice — plus a fact-checker who opens every source live. Revise until
   no critic has a blocking item. (First run 2026-09-13 as a Workflow; the script lives with the
   session, not in the tree.) PR to `unstable`. The PR checklist is §4's table.
3. When a post goes live, flip `status` to `published`, add the URL to the status header, and
   record the date the citations were last re-checked.
4. If a later post or paper contradicts an earlier post, correct the earlier post in place with
   a dated note — do not leave the retracted claim live because it is "old". Find every copy
   first (a post quoted in a deck, a memory file).

## 8. Rulings and open questions

- **Spelling: US** (Meng, 2026-09-13).
- **License: CC BY-NC 4.0** (Meng, 2026-09-13). Each post carries `license: CC-BY-NC-4.0` in its
  front matter and a one-line notice at the foot. Note what this does and does not satisfy: the
  Book's positioning (`paper/README.md`) wants the prose "open-licensed and crawlable in full" for
  the second reader, the model — BY-NC is crawlable and quotable, and it withholds commercial
  reuse, which is the intent. The repo itself stays Apache-2.0; the posts' license is stated per
  post, not repo-wide.
- **Open: where it is published.** No platform chosen as of the date above (candidates: a page
  under legalese.com, a static build of this directory, a hosted newsletter). Markdown + front
  matter keeps all three open.
