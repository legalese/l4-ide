# SOURCE-LICENSE — Penal Code 1871 (Singapore)

**Status: OPEN — not determined.** This file records the question, not an answer. Do not
read the absence of a restriction here as a grant.

## The question

The source text is Singapore primary legislation, published by the Attorney-General's
Chambers on the Singapore Statutes Online service (<https://sso.agc.gov.sg>). Singapore
government material is subject to Government copyright and to the publishing body's own
terms of use. **Which terms permit what, for a corpus of this kind, has not been checked.**
It must be settled before this row moves off `mengwong/drafts`.

This is the same open question already recorded for
[`sg/pdpa-2012`](../../../pdpa-2012/encodings/legalese/SOURCE-LICENSE.md), and it is open
for the same reason: unlike United States federal material (public domain, 17 U.S.C. § 105
and the edicts-of-government doctrine) and United Kingdom legislation (Open Government
Licence v3), Singapore has no equivalent finding recorded anywhere in this repository yet.

## What this encoding actually reproduces — and why it is a sharper case than pdpa-2012

The `sg/pdpa-2012` row could note that it **cites and paraphrases rather than reproducing**,
and that its one verbatim fragment ran to five words. **That mitigation is not available
here.** `culpable-homicide-301.l4` reproduces section 301 in full, and does so twice:

1. as a block comment in the file header, both subsections set out verbatim; and
2. distributed across the encoding itself — inert style works by carrying the statutory
   prose inline as string literals, so the operative rules quote the section's own words
   between the lifted atoms.

The quantity is small in absolute terms — one section, roughly 150 words, out of an Act of
several hundred sections — and the purpose is to make the encoding auditable against its
source, which is the entire point of the isomorphism claim. Neither observation is a
licence. Both belong in whatever assessment settles the question above.

No `source/` bundle of the Act is vendored under this subject.

## Attribution

The entry added to the repository [NOTICE](../../../../../NOTICE) records that the
applicable terms are undetermined. It is not an attribution discharging a requirement — the
requirement is exactly what has not been established.
