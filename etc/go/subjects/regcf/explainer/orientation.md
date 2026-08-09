Selling shares in your company to the public normally means registering the
offering with the Securities and Exchange Commission. Regulation Crowdfunding is
the rulebook for one exemption from that requirement: an issuer may
[offer or sell securities in reliance on section 4(a)(6) of the Securities Act of 1933](src:jl4/examples/legal/regcf/regcf.l4#L881 "verbatim"),
raising money from ordinary people over the internet, if it satisfies the
conditions this Part sets out.

**The rulebook says who may rely on it, how much they may raise, from whom,
through whom, and what they owe afterwards.** It is short as securities
regulation goes. It is also unusual in who reads it: a founder raising a first
round, and a member of the public deciding how much of their savings to put in.

**It binds four kinds of party, not one.** The encoding names them as the
regulation does —
[Issuer Intermediary Investor Purchaser](src:jl4/examples/legal/regcf/regcf.l4#L89-L93 "verbatim")
— the company that raises the money, the funding portal or broker whose platform
the offering sits on, the person who buys, and the holder who later wants to
sell. A reader who thinks of this as "the rules for companies" will miss half of
it: the investor has a personal spending cap, and the buyer has a lock-up.

**The bargain is: accept conditions up front, and accept duties afterwards.**
**The rules** takes those in turn. Before it come the things the encoding lets
you do, because they are the reason to read the rest.

---

**About this document.** It has two jobs. The first is to explain the
regulation. The second is to say what happened when somebody wrote it out as
executable code — where the prose was vague and the code could not be, what the
type system refused to accept, and what the encoding honestly failed to capture.
The two threads interleave, marked _In the encoding_, because the second is only
worth reading where it lands on the first.

**What it covers, and what it leaves out.** The encoding deliberately mirrors
one external summary of this regulation, which
[presents Reg CF as eight numbered requirement groups](src:jl4/examples/legal/regcf/regcf.l4#L14-L17 "verbatim"),
and the rule-by-rule sections under **The rules** take seven of the eight. The
one with no section of its
own is
[Intermediary obligations](src:jl4/examples/legal/regcf/regcf.l4#L23 "verbatim"),
the conduct regime for the funding portal. The encoding reaches it only as far
as the exemption depends on it, so a section devoted to it would have had almost
nothing to say; what it does have is said under **The bargain** and under
**Limits**. That is a choice about this document, not a claim that the group
does not matter.

Nothing here is legal advice, and nothing here substitutes for the regulation.
Statements about the law are written to carry a link to the line of the encoding
or of the source text they came from, and this renderer re-opened each of those
lines and matched it before printing the sentence around it. **That coverage is
not total**: the section _How to check this document_ prints, section by
section, how many citations each one carries, and names the ones that carry
none. Where the encoding takes a position the regulation does not compel, the
section says so at the site, in the encoding's own words.
