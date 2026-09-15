# Figures from "Compliance through model checking" (WAICOM 2022)

Avishkar Mahajan, Martin Strecker, Seng Joe Watt and Meng Weng Wong, "Compliance through model
checking," International Workshop on AI Compliance Mechanism (WAICOM 2022), December 2022. Accepted
version on SMU InK, <https://ink.library.smu.edu.sg/cclaw/3/>, copyright the authors, licensed
CC BY-NC-ND 4.0. The four PNGs are the paper's embedded images, extracted unaltered with
`pdfimages` on 2026-09-14 from the PDF Meng supplied; nothing is cropped or redrawn.

| file                               | in the paper | what it shows                                                                                                                                                                                                                                                                  |
| ---------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `fig1a-commission-automaton.png`   | Fig. 1(a)    | The Commission: `acceptingNotification` → on `notifyPDPC?` → `evaluatingNotification` → either `notifIndivProhibited` or `notifIndivRequested`, an autonomous choice.                                                                                                          |
| `fig1b-individual-automaton.png`   | Fig. 1(b)    | The Individual: `ignorant` → on `notifyIndiv?` → `informed`.                                                                                                                                                                                                                   |
| `fig1c-organisation-automaton.png` | Fig. 1(c)    | The Organisation, in the UPPAAL editor: `breachDetected` → (`isNotifiable and cl <= 30`, `cl := 0`) → `breachDeterminedNotifiable` → (`cl <= 3`, `notifyPDPC!`) → `pdpcNotified` → (`notifyIndiv!`) → `individualNotified`; or `not isNotifiable` → `notificationNotRequired`. |
| `fig2-failure-trace.png`           | Fig. 2       | The UPPAAL simulator with the trace for `E<> I.informed and C.notifIndivProhibited`, ending in `(notifIndivProhibited, informed, individualNotified)`: the individual informed although the Commission prohibited it.                                                          |

What the paper says the model found (§3, read 2026-09-14): the property `E<> I.informed and
C.notifIndivProhibited` — an individual informed in spite of the Commission's prohibition — "is
also satisfied, and Uppaal produces a trace (Figure 2) … It comes about because the organization
has no clue at which point the commission's interdiction to inform the individual could intervene,
and is therefore entitled to inform the individual as soon as a data breach is identified." And
`E<> O.breachDeterminedNotifiable and deadlock` holds: "in this state, no action is possible when
the notification deadline of 3 days has been exceeded." The paper also records that the model
sequentialises the notifications (Commission first, then the individual) as a modelling choice.
