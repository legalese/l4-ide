:- discontiguous covered/1.
excluded(skydiving). excluded(military). excluded(firefighting). excluded(police_arising).
covered(C) :- \+ (member(X, C.causes), excluded(X)), C.age < 80, C.confirm_month =< 7.
