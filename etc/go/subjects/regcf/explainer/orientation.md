Selling shares in your company to the public normally means registering the
offering with the Securities and Exchange Commission: months of work and a legal
bill most small companies cannot carry. Title III of the JOBS Act created an
exemption from that requirement — section 4(a)(6) of the Securities Act — so a
small company can raise money from ordinary people over the internet without
registering.

**Regulation Crowdfunding is the rulebook that makes the exemption usable.** It
says who may rely on it, how much they may raise, from whom, through whom, and
what they owe afterwards. It is short as securities regulation goes, and it is
unusually consequential per word, because the people it governs are mostly not
represented by counsel: a founder raising a first round, and a member of the
public deciding how much of their savings to put in.

**It binds four kinds of party, not one.** The encoding names them as the
regulation does —
[Issuer Intermediary Investor Purchaser](src:jl4/examples/legal/regcf/regcf.l4#L89-L93 "verbatim")
— the
company that raises the money, the funding portal or broker whose platform the
offering sits on, the person who buys, and the holder who later wants to sell. A
reader who thinks of this as "the rules for companies" will miss half of it: the
investor has a personal spending cap, and the buyer has a lock-up.

**The bargain is: accept conditions up front, and accept duties afterwards.**
The next section takes those in turn.

---

**About this document.** It has two jobs. The first is to explain the
regulation. The second is to say what happened when somebody wrote it out as
executable code — where the prose was vague and the code could not be, what the
type system refused to accept, and what the encoding honestly failed to capture.
The two threads interleave, marked _In the encoding_, because the second is only
worth reading where it lands on the first.

Nothing here is legal advice, and nothing here substitutes for the regulation.
Every statement about the law carries a link to the line of the encoding or of
the source text it came from, and this renderer re-opened each of those lines
and matched it before printing the sentence you are reading. Where the encoding
takes a position the regulation does not compel, the section says so at the
site, in the encoding's own words.
