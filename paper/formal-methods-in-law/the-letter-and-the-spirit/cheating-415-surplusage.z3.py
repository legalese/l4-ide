#!/usr/bin/env python3
"""
Poh Yuan Nie v Public Prosecutor [2022] SGCA 74 — the surplusage argument as a proof.

The deterministic symbolic backend behind the L4 model cheating-415-poh-yuan-nie.l4.
The L4 file is the human-auditable *model*; this is the *decision procedure*. Z3 does
not enumerate the 2^11 cases — it reasons symbolically and returns either a PROOF
(unsat of the negation) or a COUNTEREXAMPLE (a model). That is what "formal methods"
buys over brute force: completeness, and it scales past toy sizes.

    pip install z3-solver ;  python3 cheating-415-surplusage.z3.py
"""

from z3 import *

# --- the 11 operative atoms of s 415 (2008 version, GD [5]) -----------------
by_deceiving    = Bool('by deceiving any person')
conceal         = Bool('dishonest concealment of facts')             # Explanation 1 route
prop_intent     = Bool('intent to cause wrongful property gain/loss')  # THE s 24 requirement
fraudulently    = Bool('fraudulently')
prop_delivery   = Bool('induces delivery or retention of property')   # first-limb actus reus
intentionally   = Bool('intentionally induces act or omission')       # second-limb mens rea
causes_harm     = Bool('act or omission causes or is likely to cause harm')
harm_body       = Bool('harm to body')
harm_mind       = Bool('harm to mind')
harm_reputation = Bool('harm to reputation')
harm_property   = Bool('harm to property')

ATOMS = [by_deceiving, conceal, prop_intent, fraudulently, prop_delivery,
         intentionally, causes_harm, harm_body, harm_mind, harm_reputation, harm_property]

s24_met = prop_intent  # s 24 = doing a thing intending wrongful property gain/loss

# --- s 415, parameterised by interpretation and by the concealment bit -------
# GD [18]: on every reading EXCEPT the applicants', a dishonest concealment is a
# deception in the ordinary sense; the applicants (Second) bolt on the s 24 gate.
def concealment_counts(reading, c):
    return And(c, s24_met) if reading == 'Second' else c

def deception(reading, c):
    return Or(by_deceiving, concealment_counts(reading, c))

def first_limb(reading, c):
    return And(deception(reading, c), Or(fraudulently, s24_met), prop_delivery)

def second_limb(reading, c):
    return And(deception(reading, c), intentionally, causes_harm,
               Or(harm_body, harm_mind, harm_reputation, harm_property))

def cheats(reading, c=conceal):
    return Or(first_limb(reading, c), second_limb(reading, c))

# --- proof helpers -----------------------------------------------------------
def readable(m):
    on = [str(a) for a in ATOMS if is_true(m.eval(a, model_completion=True))]
    return "{ " + ", ".join(on) + " }" if on else "{ }"

def prove(name, claim):
    s = Solver(); s.add(Not(claim))
    if s.check() == unsat:
        print(f"  [PROVED ]  {name}")
    else:
        print(f"  [FAILED ]  {name}")
        print(f"             counterexample: {readable(s.model())}")

def find(name, formula):
    s = Solver(); s.add(formula)
    if s.check() == sat:
        print(f"  [WITNESS]  {name}")
        print(f"             {readable(s.model())}")
    else:
        print(f"  [NONE   ]  {name}: no such case exists")

# ============================================================================
print("THEOREM A — the applicants' reading is strictly NARROWER than the court's")
prove("cheat[Second] => cheat[Fourth]  (the applicants' reading can only ever acquit"
      " where the court's convicts; never the reverse)",
      Implies(cheats('Second'), cheats('Fourth')))
find("a case the court CONVICTS but the applicants would ACQUIT",
     And(cheats('Fourth'), Not(cheats('Second'))))

print()
print("THEOREM B — surplusage as a Boolean-difference proof (GD [30], [32])")
print("            under the applicants' reading, with no property, the value of")
print("            'dishonest concealment' can NEVER change the verdict: it is a")
print("            don't-care across the whole no-property region => Explanation 1")
print("            is otiose.  (This is the kernel operation of boolean minimization.)")
no_property      = Not(prop_intent)                       # the s 24 gate is off
no_property_atall = And(Not(prop_intent), Not(prop_delivery))  # forged-degree: no property of any kind
diff_second = cheats('Second', BoolVal(True)) != cheats('Second', BoolVal(False))
diff_fourth = cheats('Fourth', BoolVal(True)) != cheats('Fourth', BoolVal(False))
prove("under [Second]:  no-property  =>  concealment is irrelevant  (otiose / surplusage)",
      Implies(no_property, Not(diff_second)))
find("under [Fourth]:  a no-property case where concealment IS decisive  (Expl 1 is live)",
     And(no_property_atall, diff_fourth))

print()
print("THEOREM C — the engine FINDS the counterexample class (GD [28] was handed to us)")
find("a forged-degree case the two readings classify differently",
     And(cheats('Second') != cheats('Fourth'), no_property_atall))
