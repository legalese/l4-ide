# De novo diff — charities-jersey-2014

Produced by `etc/go/lib/denovo-diff.mjs` from `/private/tmp/claude-502/-Users-mengwong-src-legalese-l4-ide/7c74365c-e8cf-487b-a5ba-00ebbcbd6c57/scratchpad/charities.surface-map.json`. Every disposition below is **UNTRIAGED**: this script measures, it does not triage. SPEC.md §8's three dispositions — `ENCODING-ERROR`, `GENUINE-AMBIGUITY`, `IMPROVEMENT-OVER-CORPUS` — are judgements and belong to the reviewer or the skill.

## Surfaces

| | corpus (left) | cleanroom (right) |
| --- | --- | --- |
| module | `paper/case-studies/charities-jersey-2014/part-3-charity-test.l4` | `jl4/examples/legal/charities-cleanroom/charity-test.l4` |
| rules declared | 33 | 90 |
| rules paired | 16 | 17 |
| paired and `@export` | 0 | 1 |

## Battery

45 seed row(s), 2070 single-field perturbation(s), 2115 row(s) in all. Every seed is evaluated against all 17 pair(s); a perturbation is evaluated only against the pairs that take the mutated slot as an argument, because a decision is a function of its arguments and the rest are provably unchanged. That leaves **23535** evaluation(s) per side.

## Agreement

| pair | citation | evaluated | agreed | diverged | leaves perturbed | of those, inert |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `head-d` | Charities (Jersey) Law 2014, art 6(1)(d), 6(2)(a) | 2115 | 2115 | 0 | 27 | 25 |
| `head-f` | art 6(1)(f), 6(2)(b) | 2115 | 2115 | 0 | 27 | 24 |
| `head-h` | art 6(1)(h), 6(2)(c) | 2115 | 2115 | 0 | 27 | 25 |
| `head-i` | art 6(1)(i), 6(2)(d) | 2115 | 2115 | 0 | 27 | 24 |
| `head-n` | art 6(1)(n), 6(2)(e) | 2115 | 2027 | 88 | 27 | 25 |
| `head-p` | art 6(1)(p), 6(2)(f) | 2115 | 2115 | 0 | 27 | 25 |
| `within-6-1` | art 6(1) | 2115 | 2081 | 34 | 27 | 3 |
| `charitable-purpose` | art 6(1), 6(5) | 2115 | 2084 | 31 | 27 | 2 |
| `political` | art 6(5) | 2115 | 148 | 1967 | 27 | 2 |
| `ancillary` | art 5(1)(a)(ii), 6(5) | 2115 | 2108 | 7 | 27 | 25 |
| `charitable-or-ancillary` | art 5(1)(a) | 2115 | 2086 | 29 | 27 | 1 |
| `5-1-a` | art 5(1)(a) | 45 | 42 | 3 | 0 | 0 |
| `5-1-b` | art 5(1)(b), 7(3)(b) | 45 | 44 | 1 | 0 | 0 |
| `7-3-b` | art 7(3)(b) | 45 | 45 | 0 | 0 | 0 |
| `5-2` | art 5(2) | 45 | 45 | 0 | 0 | 0 |
| `5-2-bites` | art 5(2), 5(3) | 45 | 44 | 1 | 0 | 0 |
| `charity-test` | art 5 | 45 | 40 | 5 | 0 | 0 |
| **total** | | **23535** | **21369** | **2166** | **297** | **181** |

### Sensitivity — where an agreement is not evidence

An **inert** (pair, fact) leaf is one the battery perturbed without ever moving either side's answer away from its seed's. Agreement there is not agreement about anything: the decision never responded to that input over these values, so a real difference between the two encodings on that leaf would be invisible. This is measured, it does not affect the exit code, and it is not a defect in either encoding — it is a limit of the battery. The remedy is a seed case or a `slots.<n>.thresholds` entry that reaches the boundary.

| pair | fact leaf | perturbations | moved an answer |
| --- | --- | ---: | ---: |
| `ancillary` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering` | 45 | 0 |
| `ancillary` | `purpose.(2)(b)(i) rural or urban regeneration` | 45 | 0 |
| `ancillary` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sec…` | 45 | 0 |
| `ancillary` | `purpose.(2)(c) the sport involves physical skill and exertion` | 45 | 0 |
| `ancillary` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who hav…` | 45 | 0 |
| `ancillary` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at…` | 45 | 0 |
| `ancillary` | `purpose.(2)(e) relief given by the provision of accommodation or care` | 45 | 0 |
| `ancillary` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief…` | 45 | 0 |
| `ancillary` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `ancillary` | `purpose.(b) the advancement of education` | 45 | 0 |
| `ancillary` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `ancillary` | `purpose.(d) the advancement of health` | 45 | 0 |
| `ancillary` | `purpose.(e) the saving of lives` | 45 | 0 |
| `ancillary` | `purpose.(f) the advancement of citizenship or community development` | 45 | 0 |
| `ancillary` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `ancillary` | `purpose.(h) the advancement of public participation in sport` | 45 | 0 |
| `ancillary` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational…` | 45 | 0 |
| `ancillary` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `ancillary` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `ancillary` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `ancillary` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `ancillary` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financi…` | 45 | 0 |
| `ancillary` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `ancillary` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the …` | 45 | 0 |
| `ancillary` | `purpose.description` | 900 | 0 |
| `charitable-or-ancillary` | `purpose.description` | 900 | 0 |
| `charitable-purpose` | `purpose.description` | 900 | 0 |
| `charitable-purpose` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `head-d` | `purpose.(2)(b)(i) rural or urban regeneration` | 45 | 0 |
| `head-d` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sec…` | 45 | 0 |
| `head-d` | `purpose.(2)(c) the sport involves physical skill and exertion` | 45 | 0 |
| `head-d` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who hav…` | 45 | 0 |
| `head-d` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at…` | 45 | 0 |
| `head-d` | `purpose.(2)(e) relief given by the provision of accommodation or care` | 45 | 0 |
| `head-d` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief…` | 45 | 0 |
| `head-d` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `head-d` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `head-d` | `purpose.(b) the advancement of education` | 45 | 0 |
| `head-d` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `head-d` | `purpose.(e) the saving of lives` | 45 | 0 |
| `head-d` | `purpose.(f) the advancement of citizenship or community development` | 45 | 0 |
| `head-d` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `head-d` | `purpose.(h) the advancement of public participation in sport` | 45 | 0 |
| `head-d` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational…` | 45 | 0 |
| `head-d` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `head-d` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `head-d` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `head-d` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `head-d` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financi…` | 45 | 0 |
| `head-d` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `head-d` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the …` | 45 | 0 |
| `head-d` | `purpose.description` | 900 | 0 |
| `head-d` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `head-f` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering` | 45 | 0 |
| `head-f` | `purpose.(2)(c) the sport involves physical skill and exertion` | 45 | 0 |
| `head-f` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who hav…` | 45 | 0 |
| `head-f` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at…` | 45 | 0 |
| `head-f` | `purpose.(2)(e) relief given by the provision of accommodation or care` | 45 | 0 |
| `head-f` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief…` | 45 | 0 |
| `head-f` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `head-f` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `head-f` | `purpose.(b) the advancement of education` | 45 | 0 |
| `head-f` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `head-f` | `purpose.(d) the advancement of health` | 45 | 0 |
| `head-f` | `purpose.(e) the saving of lives` | 45 | 0 |
| `head-f` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `head-f` | `purpose.(h) the advancement of public participation in sport` | 45 | 0 |
| `head-f` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational…` | 45 | 0 |
| `head-f` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `head-f` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `head-f` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `head-f` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `head-f` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financi…` | 45 | 0 |
| `head-f` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `head-f` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the …` | 45 | 0 |
| `head-f` | `purpose.description` | 900 | 0 |
| `head-f` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `head-h` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering` | 45 | 0 |
| `head-h` | `purpose.(2)(b)(i) rural or urban regeneration` | 45 | 0 |
| `head-h` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sec…` | 45 | 0 |
| `head-h` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who hav…` | 45 | 0 |
| `head-h` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at…` | 45 | 0 |
| `head-h` | `purpose.(2)(e) relief given by the provision of accommodation or care` | 45 | 0 |
| `head-h` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief…` | 45 | 0 |
| `head-h` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `head-h` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `head-h` | `purpose.(b) the advancement of education` | 45 | 0 |
| `head-h` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `head-h` | `purpose.(d) the advancement of health` | 45 | 0 |
| `head-h` | `purpose.(e) the saving of lives` | 45 | 0 |
| `head-h` | `purpose.(f) the advancement of citizenship or community development` | 45 | 0 |
| `head-h` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `head-h` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational…` | 45 | 0 |
| `head-h` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `head-h` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `head-h` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `head-h` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `head-h` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financi…` | 45 | 0 |
| `head-h` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `head-h` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the …` | 45 | 0 |
| `head-h` | `purpose.description` | 900 | 0 |
| `head-h` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `head-i` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering` | 45 | 0 |
| `head-i` | `purpose.(2)(b)(i) rural or urban regeneration` | 45 | 0 |
| `head-i` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sec…` | 45 | 0 |
| `head-i` | `purpose.(2)(c) the sport involves physical skill and exertion` | 45 | 0 |
| `head-i` | `purpose.(2)(e) relief given by the provision of accommodation or care` | 45 | 0 |
| `head-i` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief…` | 45 | 0 |
| `head-i` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `head-i` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `head-i` | `purpose.(b) the advancement of education` | 45 | 0 |
| `head-i` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `head-i` | `purpose.(d) the advancement of health` | 45 | 0 |
| `head-i` | `purpose.(e) the saving of lives` | 45 | 0 |
| `head-i` | `purpose.(f) the advancement of citizenship or community development` | 45 | 0 |
| `head-i` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `head-i` | `purpose.(h) the advancement of public participation in sport` | 45 | 0 |
| `head-i` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `head-i` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `head-i` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `head-i` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `head-i` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financi…` | 45 | 0 |
| `head-i` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `head-i` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the …` | 45 | 0 |
| `head-i` | `purpose.description` | 900 | 0 |
| `head-i` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `head-n` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering` | 45 | 0 |
| `head-n` | `purpose.(2)(b)(i) rural or urban regeneration` | 45 | 0 |
| `head-n` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sec…` | 45 | 0 |
| `head-n` | `purpose.(2)(c) the sport involves physical skill and exertion` | 45 | 0 |
| `head-n` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who hav…` | 45 | 0 |
| `head-n` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at…` | 45 | 0 |
| `head-n` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief…` | 45 | 0 |
| `head-n` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `head-n` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `head-n` | `purpose.(b) the advancement of education` | 45 | 0 |
| `head-n` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `head-n` | `purpose.(d) the advancement of health` | 45 | 0 |
| `head-n` | `purpose.(e) the saving of lives` | 45 | 0 |
| `head-n` | `purpose.(f) the advancement of citizenship or community development` | 45 | 0 |
| `head-n` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `head-n` | `purpose.(h) the advancement of public participation in sport` | 45 | 0 |
| `head-n` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational…` | 45 | 0 |
| `head-n` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `head-n` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `head-n` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `head-n` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `head-n` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `head-n` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the …` | 45 | 0 |
| `head-n` | `purpose.description` | 900 | 0 |
| `head-n` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `head-p` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering` | 45 | 0 |
| `head-p` | `purpose.(2)(b)(i) rural or urban regeneration` | 45 | 0 |
| `head-p` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sec…` | 45 | 0 |
| `head-p` | `purpose.(2)(c) the sport involves physical skill and exertion` | 45 | 0 |
| `head-p` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who hav…` | 45 | 0 |
| `head-p` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at…` | 45 | 0 |
| `head-p` | `purpose.(2)(e) relief given by the provision of accommodation or care` | 45 | 0 |
| `head-p` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `head-p` | `purpose.(a) the prevention or relief of poverty` | 45 | 0 |
| `head-p` | `purpose.(b) the advancement of education` | 45 | 0 |
| `head-p` | `purpose.(c) the advancement of religion` | 45 | 0 |
| `head-p` | `purpose.(d) the advancement of health` | 45 | 0 |
| `head-p` | `purpose.(e) the saving of lives` | 45 | 0 |
| `head-p` | `purpose.(f) the advancement of citizenship or community development` | 45 | 0 |
| `head-p` | `purpose.(g) the advancement of the arts, heritage, culture or science` | 45 | 0 |
| `head-p` | `purpose.(h) the advancement of public participation in sport` | 45 | 0 |
| `head-p` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational…` | 45 | 0 |
| `head-p` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation` | 45 | 0 |
| `head-p` | `purpose.(k) the promotion of religious or racial harmony` | 45 | 0 |
| `head-p` | `purpose.(l) the promotion of equality and diversity` | 45 | 0 |
| `head-p` | `purpose.(m) the advancement of environmental protection or improvement` | 45 | 0 |
| `head-p` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financi…` | 45 | 0 |
| `head-p` | `purpose.(o) the advancement of animal welfare` | 45 | 0 |
| `head-p` | `purpose.description` | 900 | 0 |
| `head-p` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `political` | `purpose.description` | 900 | 0 |
| `political` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |
| `within-6-1` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for el…` | 45 | 0 |
| `within-6-1` | `purpose.description` | 900 | 0 |
| `within-6-1` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes` | 45 | 0 |

## Triage table (SPEC.md §8)

| # | pair | witness | corpus says | cleanroom says | also seen on | fork | disposition |
| ---: | --- | --- | --- | --- | ---: | --- | --- |
| 1 | `5-1-a` | whole seed row _purpose:care-home_ | `TRUE` | `FALSE` | 2 | — | **UNTRIAGED** |
| 2 | `5-1-b` | whole seed row _entity:the applicant not yet operating_ | `FALSE` | `TRUE` | 0 | — | **UNTRIAGED** |
| 3 | `5-2-bites` | whole seed row _entity:the trust with a Minister in a private capacity_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 4 | `ancillary` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes`: false → true<br>on seed _entity:the gift shop with nothing behind it_ | `TRUE` | `FALSE` | 6 | — | **UNTRIAGED** |
| 5 | `charitable-or-ancillary` | `purpose.description`: "providing accommodation and care" → "relieving poverty in St Helier"<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 19 | — | **UNTRIAGED** |
| 6 | `charitable-or-ancillary` | `purpose.(2)(e) relief given by the provision of accommodation or care`: false → true<br>on seed _purpose:chess_ | `TRUE` | `FALSE` | 2 | — | **UNTRIAGED** |
| 7 | `charitable-or-ancillary` | whole seed row _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 8 | `charitable-or-ancillary` | `purpose.(h) the advancement of public participation in sport`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 9 | `charitable-or-ancillary` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 10 | `charitable-or-ancillary` | `purpose.(2)(c) the sport involves physical skill and exertion`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 11 | `charitable-or-ancillary` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 12 | `charitable-or-ancillary` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 13 | `charitable-purpose` | `purpose.description`: "providing accommodation and care" → "relieving poverty in St Helier"<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 19 | — | **UNTRIAGED** |
| 14 | `charitable-purpose` | `purpose.(2)(e) relief given by the provision of accommodation or care`: false → true<br>on seed _purpose:chess_ | `TRUE` | `FALSE` | 3 | — | **UNTRIAGED** |
| 15 | `charitable-purpose` | whole seed row _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 16 | `charitable-purpose` | `purpose.(h) the advancement of public participation in sport`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 17 | `charitable-purpose` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 18 | `charitable-purpose` | `purpose.(2)(c) the sport involves physical skill and exertion`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 19 | `charitable-purpose` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 20 | `charitable-purpose` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 21 | `charitable-purpose` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 22 | `charity-test` | whole seed row _purpose:care-home_ | `TRUE` | `FALSE` | 2 | — | **UNTRIAGED** |
| 23 | `charity-test` | whole seed row _entity:the trust with a Minister in a private capacity_ | `FALSE` | `TRUE` | 1 | — | **UNTRIAGED** |
| 24 | `head-n` | `purpose.(2)(e) relief given by the provision of accommodation or care`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 42 | — | **UNTRIAGED** |
| 25 | `head-n` | `purpose.description`: "providing accommodation and care" → "relieving poverty in St Helier"<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 19 | — | **UNTRIAGED** |
| 26 | `head-n` | whole seed row _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 27 | `head-n` | `purpose.(a) the prevention or relief of poverty`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 28 | `head-n` | `purpose.(b) the advancement of education`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 29 | `head-n` | `purpose.(c) the advancement of religion`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 30 | `head-n` | `purpose.(d) the advancement of health`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 31 | `head-n` | `purpose.(e) the saving of lives`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 32 | `head-n` | `purpose.(f) the advancement of citizenship or community development`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 33 | `head-n` | `purpose.(g) the advancement of the arts, heritage, culture or science`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 34 | `head-n` | `purpose.(h) the advancement of public participation in sport`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 35 | `head-n` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 36 | `head-n` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 37 | `head-n` | `purpose.(k) the promotion of religious or racial harmony`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 38 | `head-n` | `purpose.(l) the promotion of equality and diversity`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 39 | `head-n` | `purpose.(m) the advancement of environmental protection or improvement`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 40 | `head-n` | `purpose.(o) the advancement of animal welfare`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 41 | `head-n` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 42 | `head-n` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 43 | `head-n` | `purpose.(2)(b)(i) rural or urban regeneration`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 44 | `head-n` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sector or the effectiveness or efficiency of registered charities`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 45 | `head-n` | `purpose.(2)(c) the sport involves physical skill and exertion`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 46 | `head-n` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 47 | `head-n` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 48 | `head-n` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief in a god)`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 49 | `head-n` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 50 | `head-n` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for election to any office, whether in Jersey or elsewhere`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 51 | `political` | `purpose.description`: "relieving poverty in St Helier" → "running a school"<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 759 | — | **UNTRIAGED** |
| 52 | `political` | `purpose.description`: "campaigning for a political party" → "relieving poverty in St Helier"<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 59 | — | **UNTRIAGED** |
| 53 | `political` | `purpose.(e) the saving of lives`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 54 | `political` | `purpose.(g) the advancement of the arts, heritage, culture or science`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 55 | `political` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 56 | `political` | `purpose.(k) the promotion of religious or racial harmony`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 57 | `political` | `purpose.(l) the promotion of equality and diversity`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 58 | `political` | `purpose.(m) the advancement of environmental protection or improvement`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 59 | `political` | `purpose.(o) the advancement of animal welfare`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 60 | `political` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sector or the effectiveness or efficiency of registered charities`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 41 | — | **UNTRIAGED** |
| 61 | `political` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for election to any office, whether in Jersey or elsewhere`: false → true<br>on seed _purpose:poverty_ | `FALSE` | `TRUE` | 41 | — | **UNTRIAGED** |
| 62 | `political` | `purpose.(c) the advancement of religion`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 63 | `political` | `purpose.(d) the advancement of health`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 64 | `political` | `purpose.(f) the advancement of citizenship or community development`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 65 | `political` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 66 | `political` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 67 | `political` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 68 | `political` | `purpose.(2)(b)(i) rural or urban regeneration`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 69 | `political` | `purpose.(2)(e) relief given by the provision of accommodation or care`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 70 | `political` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief in a god)`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 71 | `political` | `purpose.(a) the prevention or relief of poverty`: false → true<br>on seed _purpose:education_ | `TRUE` | `FALSE` | 40 | — | **UNTRIAGED** |
| 72 | `political` | whole seed row _purpose:poverty_ | `TRUE` | `FALSE` | 37 | — | **UNTRIAGED** |
| 73 | `political` | `purpose.(2)(c) the sport involves physical skill and exertion`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 37 | — | **UNTRIAGED** |
| 74 | `political` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 37 | — | **UNTRIAGED** |
| 75 | `political` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 37 | — | **UNTRIAGED** |
| 76 | `political` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 37 | — | **UNTRIAGED** |
| 77 | `political` | `purpose.(h) the advancement of public participation in sport`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 36 | — | **UNTRIAGED** |
| 78 | `political` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 35 | — | **UNTRIAGED** |
| 79 | `political` | `purpose.(b) the advancement of education`: false → true<br>on seed _purpose:poverty_ | `TRUE` | `FALSE` | 16 | — | **UNTRIAGED** |
| 80 | `political` | whole seed row _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 81 | `political` | `purpose.(a) the prevention or relief of poverty`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 82 | `political` | `purpose.(b) the advancement of education`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 83 | `political` | `purpose.(c) the advancement of religion`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 84 | `political` | `purpose.(d) the advancement of health`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 85 | `political` | `purpose.(e) the saving of lives`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 86 | `political` | `purpose.(f) the advancement of citizenship or community development`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 87 | `political` | `purpose.(g) the advancement of the arts, heritage, culture or science`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 88 | `political` | `purpose.(h) the advancement of public participation in sport`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 89 | `political` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 90 | `political` | `purpose.(j) the advancement of human rights, conflict resolution or reconciliation`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 91 | `political` | `purpose.(k) the promotion of religious or racial harmony`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 92 | `political` | `purpose.(l) the promotion of equality and diversity`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 93 | `political` | `purpose.(m) the advancement of environmental protection or improvement`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 94 | `political` | `purpose.(n) the relief of those in need by reason of age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 95 | `political` | `purpose.(o) the advancement of animal welfare`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 96 | `political` | `purpose.(p) any other purpose that may reasonably be regarded as analogous to any of the purposes listed in sub-paragraphs (a) to (o)`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 97 | `political` | `purpose.(2)(a) the prevention or relief of sickness, disease or human suffering`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 98 | `political` | `purpose.(2)(b)(i) rural or urban regeneration`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 99 | `political` | `purpose.(2)(b)(ii) the promotion of civic responsibility, volunteering, the voluntary sector or the effectiveness or efficiency of registered charities`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 100 | `political` | `purpose.(2)(c) the sport involves physical skill and exertion`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 101 | `political` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 102 | `political` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 103 | `political` | `purpose.(2)(e) relief given by the provision of accommodation or care`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 104 | `political` | `purpose.(2)(f) the advancement of a philosophical belief (whether or not involving belief in a god)`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 105 | `political` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes`: false → true<br>on seed _purpose:political_ | `FALSE` | `TRUE` | 2 | — | **UNTRIAGED** |
| 106 | `political` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for election to any office, whether in Jersey or elsewhere`: true → false<br>on seed _purpose:political-edu_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 107 | `within-6-1` | `purpose.description`: "providing accommodation and care" → "relieving poverty in St Helier"<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 19 | — | **UNTRIAGED** |
| 108 | `within-6-1` | `purpose.(2)(e) relief given by the provision of accommodation or care`: false → true<br>on seed _purpose:chess_ | `TRUE` | `FALSE` | 5 | — | **UNTRIAGED** |
| 109 | `within-6-1` | whole seed row _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 110 | `within-6-1` | `purpose.(h) the advancement of public participation in sport`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 111 | `within-6-1` | `purpose.(i) the provision of recreational facilities, or the organisation of recreational activities, with the object of improving the conditions of life for the persons for whom the facilities or activities are primarily intended`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 112 | `within-6-1` | `purpose.(2)(c) the sport involves physical skill and exertion`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 113 | `within-6-1` | `purpose.(2)(d)(i) the facilities or activities are primarily intended for persons who have need of them by reason of their age, ill-health, disability, financial hardship or other disadvantage`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 114 | `within-6-1` | `purpose.(2)(d)(ii) the facilities or activities are available to members of the public at large or to male or female members of the public at large`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 115 | `within-6-1` | `purpose.is purely ancillary or incidental to any of the entity's charitable purposes`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |
| 116 | `within-6-1` | `purpose.(5) is the purpose of advancing a political party or promoting a candidate for election to any office, whether in Jersey or elsewhere`: false → true<br>on seed _purpose:care-home_ | `TRUE` | `FALSE` | 0 | — | **UNTRIAGED** |

Minimality: a witness marked `one-field-from-agreeing-seed` is minimal by construction — its seed agreed and exactly one field moved. A witness marked `whole-seed-row` is not minimised: the seed itself diverged, and there is no agreeing neighbour to shrink towards.

## Limits — what this comparison cannot see

- **Only the pairs the map declares.** Coverage is `rules paired / rules declared` above. A decision present in one encoding and absent from the other is invisible here unless somebody wrote the pair down — the map is a declaration, and the oracle can only disagree with what was declared.
- **Decisions only — the deontic layer is not exercised.** The battery evaluates `DECIDE`/`MEANS` functions. Regulative rules (obligations, deadlines, reparations) have no answer this comparator reads, so two encodings could differ on who owes what, by when, and with what consequence on breach, and every row here would still agree. The BPMN/LTS legs are where that divergence would show; wiring them into the diff is not built.
- **Answer equality is equality of the compiler's rendering.** Two answers that mean the same thing but render differently (a record with reordered fields, `4/2` against `2.0`) read as a divergence, and are triaged away by a human. The `field` projection in the map exists to narrow the comparison when that noise dominates.
- **Both sides erroring identically counts as agreement.** If a fact pattern makes both encodings refuse, that is recorded as an agreement on the refusal — which is the right answer for a curated refusal (Reg CF pre-commencement dates) and the wrong one if both encodings are broken in the same way.
- **Perturbation is single-field.** Interaction defects that need two fields to move together are out of reach. The generator is a search over a neighbourhood of the seed cases, not over the input space.
- **A leaf the battery never made a decision respond to is not compared, only visited.** The generator reaches the values it can derive from the seed cases (±1, ×0/×½/×2, ×−1, cross-pollination, declared thresholds); a statutory boundary outside every one of them is never crossed, and both encodings answer identically on the near side of it whatever they say on the far side. Measured case: moving `total assets threshold` from 10,000,000 to 20,000,000 in a scratch copy of `regcf.l4` changes a live path of `reporting-may-terminate` and produces **zero** divergence, because every value the battery reaches for `status.total assets` is below both. The Sensitivity table above is that blind spot enumerated rather than described; the remedy is a seed case or a `slots.<n>.thresholds` entry at the boundary.
- **List-valued and optional-shaped facts are not perturbed.** `leavesOf` descends objects and stops at arrays.
- **An enum-typed input field cannot be fed.** `JSONDECODE` delivers a constructor name as a string, so any `CONSIDER` over an enum-valued field of a decoded record raises `NonExhaustivePatterns` — on both sides identically, which reads as agreement on an error and measures nothing. Keep such slots out of the map (the Reg CF identity fixture drops `FormCFiling` for exactly this) until the decoder learns constructors. `l4 batch` decodes rows the same way and has the same limit.
- **A `#ASSERT` in either module is not consulted.** This is a differential oracle between two encodings; it says nothing about whether either agrees with the statute. That is HG1's question and P5's.
