# Source licence — quoted legal text

The legal text quoted in this encoding is Singapore legislation, retrieved from **Singapore
Statutes Online** (`sso.agc.gov.sg`), published by the Legislation Division of the
Attorney-General's Chambers of Singapore.

| Act                                                        | Retrieved from                      |
| ---------------------------------------------------------- | ----------------------------------- |
| Wills Act 1838                                             | https://sso.agc.gov.sg/Act/WA1838   |
| Intestate Succession Act 1967                              | https://sso.agc.gov.sg/Act/ISA1967  |
| Probate and Administration Act 1934                        | https://sso.agc.gov.sg/Act/PAA1934  |
| Guardianship of Infants Act 1934                           | https://sso.agc.gov.sg/Act/GIA1934  |
| Administration of Muslim Law Act 1966 (cited, not encoded) | https://sso.agc.gov.sg/Act/AMLA1966 |
| Interpretation Act 1965 (cited, not encoded)               | https://sso.agc.gov.sg/Act/IA1965   |
| Civil Law Act 1909 (cited, not encoded)                    | https://sso.agc.gov.sg/Act/CLA1909  |

All seven were retrieved on **26 August 2026** in their official PDF form, and each is pinned by
a `sha256` over the retrieved bytes in
[`registers/source-bundle.json`](registers/source-bundle.json). The publisher's own currency
banner at that date — _"Current version as at 26 Aug 2026"_ — is recorded there too, and
[`source/fetch-sso.py`](source/fetch-sso.py) reproduces the fetch.

The last three are **corroborations**: they are cited in the encoding's reasoning and are not
themselves encoded. ISA s 2 excludes Muslim estates into the Administration of Muslim Law Act;
the Interpretation Act and the Civil Law Act are cited on the question of the age of majority,
where between them they establish that Singapore has **no single statutory answer** (see
NOTES.md).

Singapore legislation is Crown/Government copyright, made available through SSO under the terms
that site states. **Quotation here is for the purpose of building and evidencing a
computational encoding**, and every quotation is extracted mechanically from the retrieved text
rather than retyped. Nothing in this directory is an official version of the law; the official
version is the one SSO publishes.

The **encoding** — the `.l4` modules, the registers and the case suite — is the contribution of
the maintainer named in `encoding.json` and is licensed under **Apache-2.0**, per the repository
`NOTICE`. That licence covers the encoding only; it makes no claim over the underlying
legislative text.

**This is not legal advice**, it has not been reviewed against the Acts by a human (see
`encoding.json`'s `not_reviewed`), and it is not a substitute for reading them.
