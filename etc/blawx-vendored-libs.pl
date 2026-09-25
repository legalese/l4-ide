% ============================================================================
% VENDORED BLAWX PROLOG LIBRARIES — do not edit by hand.
%
% This file is the verbatim string content of the Prolog libraries Blawx's
% reasoner.py injects before every run, concatenated in reasoner.py's exact
% write order:
%
%   blawx_passthrough  from blawx/passthrough.py
%   ldap_code          from blawx/ldap.py
%   scasp_dates        from blawx/dates.py
%   (scasp_now         is GENERATED AT RUNTIME by dates.py — the tier-1
%                       harness appends fresh blawx_now/blawx_today facts,
%                       mirroring it)
%   scasp_aggregates   from blawx/aggregates.py
%   ec_code            from blawx/events.py
%
% Source: Blawx checkout /Volumes/transcend/src/blawx at commit 02eded1.
% DRIFT RISK: upstream Blawx can change these libraries at any time; there is
% deliberately NO checksum pin (BLAWX-EXPORT-SPEC R13 as ruled) — if tier-1
% answers diverge from a live Blawx container, re-vendor from the container's
% blawx/ package first and re-run before suspecting the emitter.
%
% Consumed by etc/blawx-tier1-harness.py, which filters the #pred NLG
% directive lines when assembling a consultable program (they are s(CASP)
% source syntax, not Prolog; answers are unaffected — NLG only).
% ============================================================================

%% ---- blawx_passthrough (passthrough.py) ----

#pred blawx_diseq(X,Y) :: '@(X) is not the same object as @(Y)'.

blawx_diseq(X,Y) :- X \= Y.

#pred blawx_comparison(X,eq,Y) :: '@(X) is equal to @(Y)'.
#pred blawx_comparison(X,neq,Y) :: '@(X) is not equal to @(Y)'.
#pred blawx_comparison(X,gt,Y) :: '@(X) is greater than @(Y)'.
#pred blawx_comparison(X,gte,Y) :: '@(X) is greater than or equal to @(Y)'.
#pred blawx_comparison(X,lt,Y) :: '@(X) is less than @(Y)'.
#pred blawx_comparison(X,lte,Y) :: '@(X) is less than or equal to @(Y)'.

blawx_comparison(X,eq,Y) :- X #= Y.
blawx_comparison(X,neq,Y) :- X \= Y.
blawx_comparison(X,gt,Y) :- X #> Y.
blawx_comparison(X,gte,Y) :- X #>= Y.
blawx_comparison(X,lt,Y) :- X #< Y.
blawx_comparison(X,lte,Y) :- X #=< Y.

%% ---- ldap_code (ldap.py) ----

% We need language for the applies predicate that is not related to any other predicate.
#pred blawx_applies(Y,X) :: '@(Y) applies to @(X)'.
#pred holds(user,blawx_applies,Y,Z) :: 'it is provided as a fact that @(Y) applies to @(Z)'.
#pred holds(user,-blawx_applies,Y,Z) :: 'it is provided as a fact that it is not the case that @(Y) applies to @(Z)'.
#pred holds(X,blawx_applies,Y,Z) :: 'the conclusion in @(X) that @(Y) applies to @(Z) holds'.
#pred holds(X,-blawx_applies,Y,Z) :: 'the conclusion in @(X) that it is not the case that @(Y) applies to @(Z) holds'.
#pred according_to(X,blawx_applies,Y,Z) :: 'according to @(X) @(Y) applies to @(Z)'.
#pred according_to(X,-blawx_applies,Y,Z) :: 'according to @(X) it is not the case that @(Y) applies to @(Z)'.
#pred defeated(X,blawx_applies,Y,Z) :: 'the conclusion in @(X) that @(Y) applies to @(Z) is defeated'.
#pred defeated(X,-blawx_applies,Y,Z) :: 'the conclusion in @(X) that it is not the case that @(Y) applies to @(Z) is defeated'.

%% ---- scasp_dates (dates.py) ----

%:- use_module(library(scasp)).
%:- use_module(library(scasp/human)).
%:- style_check(-discontiguous).
%:- style_check(-singleton).
%:- set_prolog_flag(scasp_unknown, fail).

#pred date_add(X,Y,Z) :: 'adding @(Y) to @(X) gives @(Z)'.
#pred date_compare(X,eq,Y) :: '@(X) is the same as @(Y)'.
#pred date_compare(X,lt,Y) :: '@(X) is before @(Y)'.
#pred date_compare(X,lte,Y) :: '@(X) is on or before @(Y)'.
#pred date_compare(X,gt,Y) :: '@(X) is after @(Y)'.
#pred date_compare(X,gte,Y) :: '@(X) is on or after @(Y)'.
#pred date_compare(X,ne,Y) :: '@(X) is not the same as @(Y)'.
#pred duration_compare(X,eq,Y) :: '@(X) is the same as @(Y)'.
#pred duration_compare(X,lt,Y) :: '@(X) is larger than @(Y)'.
#pred duration_compare(X,lte,Y) :: '@(X) is larger than or the same as @(Y)'.
#pred duration_compare(X,gt,Y) :: '@(X) is less than @(Y)'.
#pred duration_compare(X,gte,Y) :: '@(X) is less than or the same as @(Y)'.
#pred duration_compare(X,ne,Y) :: '@(X) is not the same as @(Y)'.

%date_add(date(X),duration(Y),datetime(Z)) :- X \= bot, Z \= eot, Z #= X + Y.
%date_add(datetime(X),duration(Y),datetime(Z)) :- X \= bot, Z \= eot, Z #= X + Y.
%date_add(date(X),time(Y),datetime(Z)) :- Z \= bot, Z \= eot, Z #= X + Y.
date_add(date(X),duration(Y),datetime(Z)) :- Z #= X + Y.
date_add(datetime(X),duration(Y),datetime(Z)) :- Z #= X + Y.
date_add(date(X),time(Y),datetime(Z)) :- Z #= X + Y.


%-date_add(_,_,datetime(eot)).
%-date_add(_,_,date(eot)).
%-date_add(date(bot),_,_).
%-date_add(datetime(bot),_,_).

date_compare(time(X),eq,time(X)).
date_compare(time(X),lt,time(Y)) :- X #< Y.
date_compare(time(X),gt,time(Y)) :- X #> Y.
date_compare(time(X),lte,time(Y)) :- X #=< Y.
date_compare(time(X),gte,time(Y)) :- X #>= Y.
date_compare(time(X),ne,time(Y)) :- X \= Y.

date_compare(datetime(X),eq,datetime(X)).
%date_compare(datetime(bot),gte,datetime(bot)).
%date_compare(datetime(bot),lte,datetime(bot)).
%date_compare(datetime(eot),gte,datetime(eot)).
%date_compare(datetime(eot),lte,datetime(eot)).
%date_compare(datetime(bot),lt,datetime(Y)) :- Y \= bot.
%date_compare(datetime(eot),gt,datetime(Y)) :- Y \= eot.
date_compare(datetime(X),lt,datetime(Y)) :- X #< Y.
date_compare(datetime(X),gt,datetime(Y)) :- X #> Y.
date_compare(datetime(X),lte,datetime(Y)) :- X #=< Y.
date_compare(datetime(X),gte,datetime(Y)) :- X #>= Y.
date_compare(datetime(X),ne,datetime(Y)) :- X \= Y.

date_compare(date(X),eq,datetime(X)).
%date_compare(date(bot),gte,datetime(bot)).
%date_compare(date(eot),lte,datetime(eot)).
%date_compare(date(eot),gte,datetime(eot)).
%date_compare(date(bot),lte,datetime(bot)).
%date_compare(date(bot),lt,datetime(Y)) :- Y \= bot.
%date_compare(date(eot),gt,datetime(Y)) :- Y \= eot.
date_compare(date(X),lt,datetime(Y)) :- X #< Y.
date_compare(date(X),gt,datetime(Y)) :- X #> Y.
date_compare(date(X),lte,datetime(Y)) :- X #=< Y.
date_compare(date(X),gte,datetime(Y)) :- X #>= Y.
date_compare(date(X),ne,datetime(Y)) :- X \= Y.

date_compare(datetime(X),eq,date(X)).
%date_compare(datetime(bot),gte,date(bot)).
%date_compare(datetime(bot),lte,date(bot)).
%date_compare(datetime(eot),gte,date(eot)).
%date_compare(datetime(eot),lte,date(eot)).
%date_compare(datetime(bot),lt,date(Y)) :- Y \= bot.
%date_compare(datetime(eot),gt,date(Y)) :- Y \= eot.
date_compare(datetime(X),lt,date(Y)) :- X #< Y.
date_compare(datetime(X),gt,date(Y)) :- X #> Y.
date_compare(datetime(X),lte,date(Y)) :- X #=< Y.
date_compare(datetime(X),gte,date(Y)) :- X #>= Y.
date_compare(datetime(X),ne,date(Y)) :- X \= Y.

date_compare(date(X),eq,date(X)).
%date_compare(date(bot),gte,date(bot)).
%date_compare(date(bot),lte,date(bot)).
%date_compare(date(eot),gte,date(eot)).
%date_compare(date(eot),lte,date(eot)).
%date_compare(date(bot),lt,date(Y)) :- Y \= bot.
%date_compare(date(eot),gt,date(Y)) :- Y \= eot.
date_compare(date(X),lt,date(Y)) :- X #< Y.
date_compare(date(X),gt,date(Y)) :- X #> Y.
date_compare(date(X),lte,date(Y)) :- X #=< Y.
date_compare(date(X),gte,date(Y)) :- X #>= Y.
date_compare(date(X),ne,date(Y)) :- X \= Y.


duration_compare(duration(X),eq,duration(X)).
duration_compare(duration(X),lt,duration(Y)) :- X #< Y.
duration_compare(duration(X),gt,duration(Y)) :- X #> Y.
duration_compare(duration(X),lte,duration(Y)) :- X #=< Y.
duration_compare(duration(X),gte,duration(Y)) :- X #>= Y.
duration_compare(duration(X),ne,duration(Y)) :- X \= Y.

%% ---- scasp_aggregates (aggregates.py) ----

count_blawx_list([],0).
count_blawx_list([_|[]],1).
count_blawx_list([_|Rest],Count) :-
    Rest \= [],
    count_blawx_list(Rest,RestCount),
    Count is RestCount + 1.
    
sum_blawx_list([],0).
sum_blawx_list([Any|[]],Any).
sum_blawx_list([First|Rest],Sum) :-
    Rest \= [],
    sum_blawx_list(Rest,RestSum),
    Sum is First + RestSum.

average_blawx_list([Any|[]],Any).
average_blawx_list(List,Average) :-
    count_blawx_list(List,Count),
    sum_blawx_list(List,Sum),
    Average is Sum / Count.

% If there is only one element, the maximum of that list is the element.
max_blawx_list([Any|[]],Any).

% If there are three elements, the maximum is either the first element, or the maximum of the remainder
max_blawx_list([First|Rest],First) :-
    max_blawx_list(Rest,RestMax),
    First #>= RestMax.
max_blawx_list([First|Rest],RestMax) :-
    max_blawx_list(Rest,RestMax),
    First #< RestMax.

min_blawx_list([Any|[]],Any).
min_blawx_list([First|Rest],First) :-
    min_blawx_list(Rest,RestMin),
    First #=< RestMin.
min_blawx_list([First|Rest],RestMin) :-
    min_blawx_list(Rest,RestMin),
    First #> RestMin.

blawx_list_not_between([Head|Tail],Start,End) :-
    blawx_not_between(Head,Start,End),
    blawx_list_not_between(Tail,Start,End).
blawx_list_not_between([],_,_).
blawx_not_between(X,Y,Z) :- X =< Y.
blawx_not_between(X,Y,Z) :- X >= Z.

blawx_list_not_before([Head|Tail],End) :-
    Head >= End,
    blawx_list_not_before(Tail,End).
blawx_list_not_before([],_).

blawx_list_not_after([Head|Tail],Start) :-
    Head =< Start,
    blawx_list_not_after(Tail,Start).
blawx_list_not_after([],_).


%% ---- ec_code (events.py) ----

blawx_as_of(X,datetime(Y)) :- blawx_as_of(X,date(Y)).
blawx_during(datetime(X),Y,datetime(Z)) :- blawx_during(date(X),Y,date(Z)).
blawx_during(datetime(X),Y,datetime(Z)) :- blawx_during(date(X),Y,datetime(Z)).
blawx_during(datetime(X),Y,datetime(Z)) :- blawx_during(datetime(X),Y,date(Z)).
blawx_becomes(X,datetime(Y)) :- blawx_becomes(X,date(Y)).
