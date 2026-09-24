#!/usr/bin/env python3
"""Generate #EVAL blocks for the rodents scenarios (scratch only)."""
import sys

FIELDS = [
    "Loss or Damage.caused by rodents",
    "Loss or Damage.caused by insects",
    "Loss or Damage.caused by vermin",
    "Loss or Damage.caused by birds",
    "Loss or Damage.to Contents",
    "any other exclusion applies",
    "a household appliance",
    "a swimming pool",
    "a plumbing, heating, or air conditioning system",
    "Loss or Damage.ensuing covered loss",
]


def block(vec, indent="        "):
    assert len(vec) == 10, vec
    out = [indent + "Inputs", indent + "WITH"]
    for f, v in zip(FIELDS, vec):
        out.append(f"{indent}    `{f}` IS {'TRUE' if v else 'FALSE'}")
    return "\n".join(out)


def eval_dir(fn, vec, comment=None):
    s = ""
    if comment:
        s += f"-- {comment}\n"
    s += f"#EVAL `{fn}` OF\n" + block(vec) + "\n"
    return s


# vector helper: string of T/F
def V(s):
    s = s.replace(" ", "")
    assert len(s) == 10, s
    return [c == "T" for c in s]


if __name__ == "__main__":
    pass
