#!/usr/bin/env python3
"""Survey bare-name pattern binders across the L4 corpus, in two independent
modes that share one scope model and one AST walker.

WHAT THIS MEASURES
-------------------
`specs/todo/PATTERN-REFERENCE-RULE-SPEC.md` (R1) rules that a bare name in a
deontic action-argument pattern (`PARTY p MUST Pay landlord amount`) should
resolve as a REFERENCE to an in-scope term when one exists, and be a fresh
wildcard binder only when it names nothing (or only a field selector). R6
asks the same question, but not yet the same ruling, for `CONSIDER ... WHEN`
patterns (and multi-clause pattern-matching `DECIDE`, which the PARSER
desugars to nested `CONSIDER` trees at parse time -- see
`decidePatternMatch` / `desugarPatternClauses` / `matchClauses` in
`jl4-core/src/L4/Parser.hs:884-1168`; despite this script's own name and an
earlier draft of its own task description pointing at `L4/Desugar.hs`, that
module does NOT do this desugaring -- it only rewrites `Consider` nodes for
computed-field cycles (see `Desugar.hs:368-436`) and for the unrelated
AND/OR-inertness rewrite (`carameliseExpr`). The desugaring that matters here
is 100% parser-level and complete before `l4 ast` ever sees the tree).

  --mode deontic   walks every `MUST`/`MAY`/`SHANT`/`DO` action pattern and
                    classifies each argument-position bare-name binder by
                    whether it collides with something already in scope
                    (Appendix A.1/A.2 of the spec).

  --mode consider  walks every `CONSIDER ... WHEN` branch pattern (literal
                    source-level CONSIDER, and the synthetic CONSIDER trees a
                    multi-clause pattern-matching DECIDE desugars to) and
                    classifies each bare-name pattern binder the same way
                    (Appendix A.5, "NOT YET MEASURED" until this run).

Both modes read the PRE-RESOLUTION parse tree (`l4 ast`, i.e.
`LSP.L4.Rules.GetParsedAst` -- parsed, not type-checked), because the whole
point is to see what the CHECKER has not yet disambiguated. `l4 ast` runs
once per file and its raw dump is cached (in memory always; on disk too, as
plain text files, if `--cache-dir` is given -- pass a scratch directory, never
a path under this worktree, so a survey run never litters the repo).

SCOPE MODEL (shared by both modes)
-----------------------------------
A `Scope` is a chain of frames; `scope.lookup(name)` returns every frame's
kind that binds `name`, innermost first. Frames, in the order they nest:

  * module top level: `DECIDE`/`MEANS` and `ASSUME` names (kind
    `toplevel-decide` / `toplevel-assume`), collected ONCE from the whole
    module (including nested `SECTION`s, which are visible module-wide) so a
    forward reference to a later top-level definition still counts as
    in-scope, matching the type checker's own two-pass (`extendKnownGlobalMany`
    then resolve) behaviour;
  * a one-level-only IMPORT of another module's top level, prefixed `import-`;
  * `DECLARE` enum/record field selectors (kind `selector`) -- the ONE carve
    -out the spec keeps as a wildcard even when it collides (R1's table);
  * SECTION `GIVEN`s (`section-given`);
  * a `DECIDE`'s own `GIVEN`/app-form parameters (`given`);
  * `WHERE`/`LET` locals (`where-local` / `where-assume`);
  * lambda parameters (`lambda-param`);
  * an outer `CONSIDER`/pattern-match branch's own bound names, visible to
    everything nested inside that branch (`consider-binder` -- this IS the
    "outer pattern binder" category in the CONSIDER-mode classification);
  * an `EVERY` roll variable (`every-var`);
  * a deontic action's own argument binders, visible to its own
    `PROVIDED`/`HENCE` (`outer-action-binder`).

A bare `PatApp n []` is a BINDER unless `n` names a data constructor already
in scope (mirrors `TypeCheck.hs`'s `inferPattern (PatApp ann n [])`:
constructor-or-else-fresh-`PatVar`). `PatExpr` (an `EXACTLY e` or a bare
literal/expression pattern) is never a binder -- it is already a reference or
a literal match today, which is exactly why it is excluded here.

One thing the desugaring already gets right, so this script correctly finds
NO binder for it: `matchOne`/`matchLast` (`Parser.hs:1132-1168`) elides the
`WHEN` entirely for any pattern column whose bare name equals its own
scrutinee's name -- e.g. `DECIDE factorial n IS n * factorial (n - 1)`, the
catch-all clause of a multi-clause DECIDE, produces no `Consider`/`PatApp`
node at all for that column (`patAlwaysMatchesAs`). So the idiomatic "reuse
the GIVEN's own name as the wildcard" pattern this codebase already
recommends (see the comment in `jl4/examples/ok/pattern-matching.l4`) never
shows up as a "collision" here -- correctly, since it was never ambiguous.

PORTED FROM: the 2026-09-16 design memo's `exactly_survey.py`
(`/private/tmp/claude-502/.../scratchpad/exactly_survey.py`, whose own output
is `survey.json`/`survey.txt` alongside it -- the numbers this script's
`--mode deontic` run is compared against). That memo covered deontic actions
only; `--mode consider` and position-tracked pattern binders are new here,
added for Phase A of the spec build (run stamp 2026-09-16T04:10Z, base
`11b7534b`). The tokenizer/pretty-simple-dump parser below is carried over
unchanged; only the `Survey` walker and the CLI/reporting are new.

USAGE
-----
    JL4_LIBRARY_PATH=<repo>/jl4-core/libraries python3 survey-pattern-binders.py \\
        --repo <repo> --l4 <l4-binary> --mode {deontic,consider} \\
        --out <out.json> [--cache-dir <scratch-dir>] [--files-from <path>]

`--files-from` takes a file of repo-relative paths, one per line (default:
`git ls-files '*.l4'` in `--repo`, i.e. every tracked `.l4` file including the
vendored `jl4/examples/canon/` mirror -- included here as a READ-ONLY survey
subject; nothing in this script ever writes into `canon/`). Neither mode
pre-filters by keyword: `--mode deontic` looks for zero deontic actions in a
file with none and just says so, rather than assuming a `MUST`/`MAY` grep is
a safe substitute for parsing (the memo's own grep-prefilter is the reason
its candidate count undercounts the current tree by exactly the 15
`canon/` files landed after it ran -- see `deltaFromMemo` in the survey's own
report).
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

# ---------------------------------------------------------------- tokenizer
# pretty-simple prints Text UNESCAPED, so a string may contain quotes and (for
# lexer whitespace tokens) newlines. Every multi-line string lives inside a
# MkPosToken record (the CSN token lists), which the walker never reads, so:
#   pass 1: strip each MkPosToken { ... } block, line-wise, by indentation;
#   pass 2: tokenize, closing a string at the LAST quote on its line that is
#           followed only by structural punctuation.
POSTOK_OPEN = re.compile(r'^(\s*)(\[|,) MkPosToken\s*$')

def strip_postokens(text):
    lines = text.split('\n')
    out = []
    i = 0
    n = len(lines)
    while i < n:
        m = POSTOK_OPEN.match(lines[i])
        if m:
            # next line: <indent>{ range = ...; find matching <indent>}
            j = i + 1
            m2 = re.match(r'^(\s*)\{', lines[j])
            indent = m2.group(1)
            close = indent + '}'
            k = j + 1
            while k < n and lines[k] != close:
                k += 1
            out.append(m.group(1) + m.group(2) + ' TokStripped')
            i = k + 1
            continue
        out.append(lines[i])
        i += 1
    return '\n'.join(out)

TOK = re.compile(r"""
    (?P<ws>\s+)
  | (?P<chr>'(?:\\.|[^'\\])')
  | (?P<num>-?\d+(?:\.\d+)?)
  | (?P<cons>:\||%)
  | (?P<id>[A-Za-z_][A-Za-z0-9_']*)
  | (?P<punct>[()\[\]{},=])
""", re.X)
CLOSE_OK = re.compile(r'^\s*(?:[)\],}]|:\||$)')

def tokenize(s):
    s = strip_postokens(s)
    pos = 0
    n = len(s)
    out = []
    while pos < n:
        if s[pos] == '"':
            eol = s.find('\n', pos)
            if eol < 0:
                eol = n
            line = s[pos + 1:eol]
            # last quote in the line whose remainder is structural
            cands = [k for k, ch in enumerate(line) if ch == '"']
            close = None
            for k in reversed(cands):
                if CLOSE_OK.match(line[k + 1:]):
                    close = k
                    break
            if close is None:
                raise SyntaxError(f"unterminated string at {pos}: {line[:60]!r}")
            out.append(('str', line[:close]))
            pos = pos + 1 + close + 1
            continue
        m = TOK.match(s, pos)
        if not m:
            raise SyntaxError(f"bad token at {pos}: {s[pos:pos+40]!r}")
        pos = m.end()
        k = m.lastgroup
        if k == 'ws':
            continue
        out.append((k, m.group(k)))
    return out

class Node:
    __slots__ = ('con', 'args', 'fields')
    def __init__(self, con, args=None, fields=None):
        self.con = con
        self.args = args or []
        self.fields = fields or {}
    def __repr__(self):
        if self.fields:
            return f"{self.con}{{{','.join(self.fields)}}}"
        return f"{self.con}({len(self.args)})"

class P:
    def __init__(self, toks):
        self.t = toks
        self.i = 0
    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)
    def next(self):
        tok = self.t[self.i]
        self.i += 1
        return tok
    def expect(self, v):
        k, s = self.next()
        if s != v:
            raise SyntaxError(f"expected {v!r} got {s!r} at tok {self.i}")

    def value(self):
        v = self.app()
        k, s = self.peek()
        if k == 'cons':
            self.next()
            rest = self.value()
            return Node(s, [v, rest])
        return v

    def app(self):
        k, s = self.peek()
        if k == 'id':
            self.next()
            k2, s2 = self.peek()
            if s2 == '{':
                return self.record(s)
            args = []
            while self.atom_start():
                args.append(self.atom())
            return Node(s, args)
        return self.atom()

    def atom_start(self):
        k, s = self.peek()
        return k in ('str', 'chr', 'num', 'id') or s in ('(', '[')

    def atom(self):
        k, s = self.next()
        if k == 'str':
            return ('str', s)
        if k == 'chr':
            return ('chr', s[1:-1])
        if k == 'num':
            return ('num', float(s) if '.' in s else int(s))
        if k == 'id':
            return Node(s, [])
        if s == '(':
            k2, s2 = self.peek()
            if s2 == ')':
                self.next()
                return ('unit', None)
            v = self.value()
            # tuples
            items = [v]
            while self.peek()[1] == ',':
                self.next()
                items.append(self.value())
            self.expect(')')
            if len(items) > 1:
                return ('tuple', items)
            return v
        if s == '[':
            items = []
            if self.peek()[1] == ']':
                self.next()
                return ('list', items)
            items.append(self.value())
            while self.peek()[1] == ',':
                self.next()
                items.append(self.value())
            self.expect(']')
            return ('list', items)
        raise SyntaxError(f"unexpected {s!r} at tok {self.i}")

    def record(self, con):
        self.expect('{')
        fields = {}
        while True:
            k, name = self.next()
            self.expect('=')
            fields[name] = self.value()
            k, s = self.next()
            if s == '}':
                break
            if s != ',':
                raise SyntaxError(f"bad record sep {s!r}")
        return Node(con, [], fields)

def parse_dump(text):
    return P(tokenize(text)).value()

# ------------------------------------------------------------------ helpers
def is_node(x, con=None):
    return isinstance(x, Node) and (con is None or x.con == con)

def lst(x):
    if isinstance(x, tuple) and x[0] == 'list':
        return x[1]
    return []

def maybe(x):
    if is_node(x, 'Nothing'):
        return None
    if is_node(x, 'Just'):
        return x.args[0]
    return x

def rawname(nm):
    """MkName anno rawname -> text"""
    if is_node(nm, 'MkName'):
        rn = nm.args[1]
        if is_node(rn, 'NormalName') or is_node(rn, 'PreDef'):
            return rn.args[0][1]
        if is_node(rn, 'QualifiedName'):
            return rn.args[1][1]
    return None

def anno_range(anno):
    """Anno{range=Just(MkSrcRange{start=MkSrcPos{line,column}..})} -> (line,col)
    Returns None when range=Nothing -- which, on a `Consider`/`When`/`Branch`
    node's OWN annotation, means that node is synthetic: emitted by
    `desugarPatternClauses`/`matchOne`/`matchLast` for a multi-clause
    pattern-matching DECIDE, never typed by a drafter as literal `CONSIDER`
    source. (A pattern's bare NAME still carries its own real anno/range in
    that case -- only the wrapping Consider/Branch/When nodes are rangeless --
    so binder positions below are accurate either way.)"""
    if is_node(anno) and 'range' in anno.fields:
        r = maybe(anno.fields['range'])
        if is_node(r, 'MkSrcRange'):
            st = r.fields['start']
            return (st.fields['line'][1], st.fields['column'][1])
    return None

def name_pos(nm):
    if is_node(nm, 'MkName'):
        return anno_range(nm.args[0])
    return None

def term_given_names(tysig):
    """The GIVEN names of a TypeSig that are terms, not type parameters --
    mirrors TypeCheck.hs's `isTerm` (false only for `x IS A TYPE`)."""
    out = set()
    gsig = tysig.args[1]  # MkGivenSig
    for otn in lst(gsig.args[1]):  # MkOptionallyTypedName ann name maybeType maybeDefault
        mtype = maybe(otn.args[2])
        if not is_node(mtype, 'Type'):
            out.add(rawname(otn.args[1]))
    return out

def resolved_decide_head(d):
    """The NAME actually bound at top level by a `Decide`, which for a
    mixfix definition written head-as-parameter (`GIVEN x, y; x APPEND y
    MEANS ...`) is NOT the parsed AppForm's head slot.

    `TypeCheck.hs:1247-1266` (`checkTermAppFormTypeSigConsistency`,
    `isMixfixPatternHeadIsParam`) detects exactly this shape -- the AppForm's
    head token is itself one of the DECIDE's own GIVEN term-parameters -- and
    restructures the binding so the first token that is NOT a GIVEN
    parameter (the keyword, e.g. `APPEND`) becomes the real function name,
    with the GIVEN names as its arguments. Naively using the raw parsed head
    (`d.args[2].args[1]`), as this script's first draft and the 2026-09-16
    memo's `exactly_survey.py` both did, registers the WRONG name at module
    scope: e.g. `jl4-core/libraries/prelude.l4:76`'s `x APPEND y MEANS CONCAT
    x, y` would register a top-level term literally named `x` (colliding
    with any pattern binder anywhere named `x`), when the real binding the
    checker creates is named `APPEND` and `x` is never a standalone term at
    all. Confirmed empirically: prelude.l4 has exactly two Decides whose
    parsed head is the bare name `x` (lines 76 and 1209), both mixfix
    head-as-parameter definitions, zero of which are real `x` bindings."""
    tysig = d.args[1]
    appform = d.args[2]
    head = appform.args[1]
    head_name = rawname(head)
    params = lst(appform.args[2])
    if params:
        givens = term_given_names(tysig)
        if head_name in givens:
            for tok in [head] + params:
                n = rawname(tok)
                if n not in givens:
                    return n
            return head_name  # fallback: no keyword token found (shouldn't happen)
    return head_name

# ------------------------------------------------------------- scope model
class Scope:
    """A stack of (kind, name) frames. Lookup returns the kinds a raw name
    hits, innermost first."""
    def __init__(self, parent=None):
        self.parent = parent
        self.names = defaultdict(list)  # rawname -> [kind]
    def add(self, kind, name):
        if name:
            self.names[name].append(kind)
    def lookup(self, name):
        hits = []
        s = self
        while s:
            if name in s.names:
                hits.extend(s.names[name])
            s = s.parent
        return hits
    def child(self):
        return Scope(self)

BUILTIN_CONSTRUCTORS = {'TRUE', 'FALSE', 'EMPTY', 'NOTHING', 'JUST', 'FULFILLED', 'BREACH', 'LEFT', 'RIGHT'}

# Maps a raw scope-frame kind to the classification bucket used in reports.
# (Both modes share these; --mode consider additionally distinguishes
# lambda-param, which never collides in deontic argument position in the
# corpus today but is tracked uniformly rather than silently folded in.)
def bucket_of(kind):
    if kind in ('given', 'section-given'):
        return 'GIVEN'
    if kind in ('where-local', 'where-assume'):
        return 'WHERE'
    if kind in ('toplevel-decide', 'toplevel-assume'):
        return 'toplevel'
    if kind == 'outer-action-binder':
        return 'outerBinder'
    if kind == 'consider-binder':
        return 'CONSIDER'
    if kind == 'every-var':
        return 'EVERY'
    if kind == 'lambda-param':
        return 'LAMBDA'
    if kind.startswith('import-'):
        return 'import'
    if kind == 'selector':
        return 'selector'
    return kind

class Survey:
    def __init__(self, path):
        self.path = path
        self.constructors = set(BUILTIN_CONSTRUCTORS)
        self.records = []          # deontic action-pattern records
        self.consider_records = [] # CONSIDER/pattern-match branch-binder records
        self.n_consider = 0        # CONSIDER nodes walked (literal + desugared)
        self.n_consider_branches = 0  # WHEN/OTHERWISE branches walked

    # --- collect top-level names of a section (declares, decides, assumes)
    def collect_toplevel(self, section, scope, kindprefix='toplevel'):
        for td in lst(section.args[4]):
            if is_node(td, 'Declare'):
                d = td.args[1]
                tdcl = d.args[3]
                if is_node(tdcl, 'EnumDecl'):
                    for cd in lst(tdcl.args[1]):
                        self.constructors.add(rawname(cd.args[1]))
                        # a constructor with fields also has selectors
                        for tn in lst(cd.args[2]):
                            scope.add('selector', rawname(tn.args[1]))
                elif is_node(tdcl, 'RecordDecl'):
                    # record type name doubles as constructor
                    self.constructors.add(rawname(d.args[2].args[1]))
                    for tn in lst(tdcl.args[2]):
                        scope.add('selector', rawname(tn.args[1]))
            elif is_node(td, 'Decide'):
                d = td.args[1]
                scope.add(kindprefix + '-decide', resolved_decide_head(d))
                aka = maybe(d.args[2].args[3])
                if aka:
                    for a in lst(aka.args[1]):
                        scope.add(kindprefix + '-decide', rawname(a))
            elif is_node(td, 'Assume'):
                a = td.args[1]
                scope.add(kindprefix + '-assume', rawname(a.args[2].args[1]))
            elif is_node(td, 'Section'):
                # nested section names are visible module-wide
                self.collect_toplevel(td.args[1], scope, kindprefix)

    def walk_section(self, section, scope):
        sc = scope.child()
        gs = maybe(section.args[3])
        if gs:
            for otn in lst(gs.args[1]):
                sc.add('section-given', rawname(otn.args[1]))
        for td in lst(section.args[4]):
            if is_node(td, 'Decide'):
                self.walk_decide(td.args[1], sc)
            elif is_node(td, 'Assume'):
                a = td.args[1]
                e = maybe(a.args[4])
                if e is not None:
                    self.walk_expr(e, sc)
            elif is_node(td, 'Section'):
                self.walk_section(td.args[1], sc)
            elif is_node(td, 'Directive'):
                dr = td.args[1]
                for a in dr.args[1:]:
                    self.walk_any(a, sc)

    def walk_decide(self, decide, scope):
        sc = scope.child()
        ts = decide.args[1]
        gsig = ts.args[1]
        for otn in lst(gsig.args[1]):
            sc.add('given', rawname(otn.args[1]))
            dflt = maybe(otn.args[3])
            if dflt is not None:
                self.walk_expr(dflt, sc)
        appform = decide.args[2]
        for p in lst(appform.args[2]):
            sc.add('given', rawname(p))
        self.walk_expr(decide.args[3], sc)

    def walk_any(self, x, scope):
        if is_node(x):
            if x.con == 'Regulative':
                self.walk_expr(x, scope)
            elif x.con in ('Where', 'LetIn', 'Lam', 'Consider'):
                self.walk_expr(x, scope)
            else:
                for a in x.args:
                    self.walk_any(a, scope)
                for v in x.fields.values():
                    self.walk_any(v, scope)
        elif isinstance(x, tuple) and x[0] in ('list', 'tuple'):
            for a in x[1]:
                self.walk_any(a, scope)

    def walk_locals(self, locals_, scope):
        for ld in lst(locals_):
            d = ld.args[1]
            if is_node(ld, 'LocalDecide'):
                scope.add('where-local', resolved_decide_head(d))
            else:
                scope.add('where-assume', rawname(d.args[2].args[1]))
        for ld in lst(locals_):
            d = ld.args[1]
            if is_node(ld, 'LocalDecide'):
                self.walk_decide(d, scope)
            else:
                e = maybe(d.args[4])
                if e is not None:
                    self.walk_expr(e, scope)

    def walk_expr(self, e, scope):
        if not is_node(e):
            self.walk_any(e, scope)
            return
        c = e.con
        if c == 'Where':
            sc = scope.child()
            self.walk_locals(e.args[2], sc)
            self.walk_expr(e.args[1], sc)
        elif c == 'LetIn':
            sc = scope.child()
            self.walk_locals(e.args[1], sc)
            self.walk_expr(e.args[2], sc)
        elif c == 'Lam':
            sc = scope.child()
            for otn in lst(e.args[1].args[1]):
                sc.add('lambda-param', rawname(otn.args[1]))
            self.walk_expr(e.args[2], sc)
        elif c == 'Regulative':
            self.walk_deonton(e.args[1], scope)
        elif c == 'Consider':
            self.walk_consider(e, scope)
        else:
            for a in e.args:
                self.walk_any(a, scope)
            for v in e.fields.values():
                self.walk_any(v, scope)

    def walk_consider(self, e, scope):
        """A CONSIDER (literal source, or a synthetic node emitted by
        multi-clause DECIDE desugaring -- see the module docstring). Walks
        the scrutinee, then each branch: records every bare-name pattern
        binder (with its collision against the OUTER scope, i.e. before this
        branch's own siblings are added) into self.consider_records, then
        extends scope with those binders (kind 'consider-binder' == an
        "outer pattern binder" to anything nested inside this branch)."""
        is_synthetic = anno_range(e.args[0]) is None
        self.n_consider += 1
        self.walk_any(e.args[1], scope)
        scrut_name = None
        if is_node(e.args[1], 'App'):
            scrut_name = rawname(e.args[1].args[1])
        elif is_node(e.args[1], 'Var'):
            scrut_name = rawname(e.args[1].args[1])
        for br in lst(e.args[2]):
            self.n_consider_branches += 1
            sc = scope.child()
            lhs = br.args[1]
            if is_node(lhs, 'When'):
                pat = lhs.args[1]
                binders = self.pattern_binders_pos(pat)
                for name, pos in binders:
                    hits = scope.lookup(name)
                    self.consider_records.append({
                        'file': self.path, 'name': name, 'pos': pos,
                        'collides': hits, 'is_synthetic_pm': is_synthetic,
                        'scrutinee': scrut_name,
                    })
                    sc.add('consider-binder', name)
            self.walk_expr(br.args[2], sc)

    def pattern_binders_pos(self, pat):
        """Bare PatApp n [] / PatVar n that are not constructors -> binders,
        as (rawname, (line, col)) pairs. Nested inside a constructor
        application (e.g. `(JUST v)`) is walked recursively; PatCons walks
        both sides; PatLit/PatExpr never bind."""
        out = []
        if is_node(pat, 'PatApp'):
            n = rawname(pat.args[1])
            args = lst(pat.args[2])
            if not args:
                if n not in self.constructors:
                    out.append((n, name_pos(pat.args[1])))
            else:
                for a in args:
                    out.extend(self.pattern_binders_pos(a))
        elif is_node(pat, 'PatCons'):
            out.extend(self.pattern_binders_pos(pat.args[1]))
            out.extend(self.pattern_binders_pos(pat.args[2]))
        elif is_node(pat, 'PatVar'):
            out.append((rawname(pat.args[1]), name_pos(pat.args[1])))
        return out

    def walk_deonton(self, d, scope):
        f = d.fields
        subj = f['subject']
        sc = scope.child()
        every_var = None
        if is_node(subj, 'Party'):
            self.walk_any(subj.args[1], scope)
        elif is_node(subj, 'Every'):
            every_var = rawname(subj.args[2])
            roll = maybe(subj.args[3])
            if roll is not None:
                self.walk_any(roll, scope)
            sc.add('every-var', every_var)
            filt = maybe(subj.args[4])
            if filt is not None:
                self.walk_any(filt, sc)
        act = f['action']
        pat = act.fields['action']
        # record the action pattern
        rec = self.analyse_action(pat, sc, every_var)
        self.records.append(rec)
        # binders extend scope for PROVIDED, HENCE (typechecker: extendKnownMany boundByPattern for hence)
        sc2 = sc.child()
        for b in rec['binders']:
            sc2.add('outer-action-binder', b['name'])
        prov = maybe(act.fields['provided'])
        if prov is not None:
            self.walk_any(prov, sc2)
        due = maybe(f['due'])
        if due is not None:
            self.walk_any(due, sc)
        hence = maybe(f['hence'])
        if hence is not None:
            self.walk_expr(hence, sc2)
        lest = maybe(f['lest'])
        if lest is not None:
            self.walk_expr(lest, sc)

    def analyse_action(self, pat, scope, every_var):
        rec = {'file': self.path, 'pos': None, 'head': None, 'head_kind': None,
               'binders': [], 'exactly': [], 'nargs': 0, 'every_var': every_var}
        if is_node(pat, 'PatApp'):
            head = rawname(pat.args[1])
            rec['pos'] = name_pos(pat.args[1])
            rec['head'] = head
            args = lst(pat.args[2])
            rec['nargs'] = len(args)
            if not args:
                if head in self.constructors:
                    rec['head_kind'] = 'constructor'
                else:
                    hits = scope.lookup(head)
                    rec['head_kind'] = 'reference:' + hits[0] if hits else 'wildcard-binder'
            else:
                rec['head_kind'] = 'constructor' if head in self.constructors else 'unknown-head'
                for i, a in enumerate(args):
                    self.analyse_arg(a, i, scope, rec)
        elif is_node(pat, 'PatExpr'):
            rec['head_kind'] = 'exactly-whole'
            rec['pos'] = anno_range(pat.args[0])
        else:
            rec['head_kind'] = 'other:' + pat.con
        return rec

    def analyse_arg(self, a, idx, scope, rec):
        if is_node(a, 'PatApp'):
            n = rawname(a.args[1])
            args = lst(a.args[2])
            if not args:
                if n in self.constructors:
                    return
                hits = scope.lookup(n)
                rec['binders'].append({'name': n, 'pos': name_pos(a.args[1]), 'arg': idx,
                                       'collides': hits})
            else:
                for b in args:
                    self.analyse_arg(b, idx, scope, rec)
        elif is_node(a, 'PatExpr'):
            e = a.args[1]
            ref = None
            if is_node(e, 'App') and not lst(e.args[2]):
                ref = rawname(e.args[1])
            elif is_node(e, 'Var'):
                ref = rawname(e.args[1])
            rec['exactly'].append({'pos': anno_range(a.args[0]), 'arg': idx, 'ref': ref,
                                   'in_scope': bool(scope.lookup(ref)) if ref else None})
        elif is_node(a, 'PatCons'):
            self.analyse_arg(a.args[1], idx, scope, rec)
            self.analyse_arg(a.args[2], idx, scope, rec)

# --------------------------------------------------------------- imports
def module_imports(mod):
    out = []
    def go(section):
        for td in lst(section.args[4]):
            if is_node(td, 'Import'):
                out.append(rawname(td.args[1].args[1]))
            elif is_node(td, 'Section'):
                go(td.args[1])
    go(mod.args[2])
    return out

AST_CACHE = {}

def ast_of(repo, l4bin, path, cache_dir):
    if path in AST_CACHE:
        return AST_CACHE[path]
    cache_file = None
    if cache_dir:
        h = hashlib.sha1(path.encode()).hexdigest()[:16]
        cache_file = os.path.join(cache_dir, path.replace('/', '__')[-150:] + '.' + h + '.ast')
    if cache_file and os.path.exists(cache_file):
        txt = open(cache_file, encoding='utf-8').read()
    else:
        r = subprocess.run([l4bin, 'ast', path], capture_output=True, text=True, cwd=repo)
        txt = r.stdout if (r.returncode == 0 and r.stdout.strip()) else ''
        if cache_file:
            os.makedirs(cache_dir, exist_ok=True)
            open(cache_file, 'w', encoding='utf-8').write(txt)
    if 'MkModule' not in txt:
        AST_CACHE[path] = None
        return None
    try:
        txt = txt[txt.index('MkModule'):]
        node = parse_dump(txt)
    except Exception as ex:
        sys.stderr.write(f"PARSE FAIL {path}: {ex}\n")
        node = None
    AST_CACHE[path] = node
    return node

def resolve_import(repo, path, modname):
    d = os.path.dirname(path)
    cands = [os.path.join(d, modname + '.l4'),
             os.path.join(repo, 'jl4-core', 'libraries', modname + '.l4')]
    for c in cands:
        if os.path.exists(c):
            return c
    return None

def survey_file(repo, l4bin, path, cache_dir):
    mod = ast_of(repo, l4bin, path, cache_dir)
    if mod is None:
        return None
    sv = Survey(path)
    scope = Scope()
    # imports: one level, best effort
    unresolved = []
    for imp in module_imports(mod):
        ip = resolve_import(repo, path, imp)
        if ip is None:
            unresolved.append(imp)
            continue
        imod = ast_of(repo, l4bin, ip, cache_dir)
        if imod is None:
            unresolved.append(imp)
            continue
        isv = Survey(ip)
        isv.collect_toplevel(imod.args[2], scope, kindprefix='import')
        sv.constructors |= isv.constructors
    sv.collect_toplevel(mod.args[2], scope)
    sv.walk_section(mod.args[2], scope)
    return sv, unresolved

# ------------------------------------------------------------------- main
def deontic_report(results, files_scanned, failed, unresolved_all):
    n_actions = len(results)
    n_binders = sum(len(r['binders']) for r in results)
    n_exactly = sum(len(r['exactly']) for r in results)
    collide = [(r, b) for r in results for b in r['binders'] if b['collides']]
    selector_only = [(r, b) for r, b in collide
                     if all(k == 'selector' for k in b['collides'])]
    local_or_module = [(r, b) for r, b in collide
                       if any(k != 'selector' for k in b['collides'])]
    by_scope = Counter()
    for r, b in local_or_module:
        by_scope[bucket_of(b['collides'][0])] += 1
    lines = []
    lines.append(f"files scanned: {files_scanned}; ast failed: {len(failed)}")
    lines.append(f"deontic action patterns: {n_actions}")
    lines.append(f"  head kinds: {Counter(r['head_kind'] for r in results).most_common()}")
    lines.append(f"argument-position bare-name binders: {n_binders}")
    lines.append(f"argument-position EXACTLY references: {n_exactly}")
    lines.append(f"  of which EXACTLY <bare name in scope>: {sum(1 for r in results for x in r['exactly'] if x['in_scope'])}")
    lines.append(f"binders colliding with an in-scope term name: {len(collide)}")
    lines.append(f"  selector-only (deliberate wildcard, unchanged): {len(selector_only)}")
    lines.append(f"  local-or-module (the hazard): {len(local_or_module)}")
    lines.append(f"  by innermost non-selector collision bucket: {sorted(by_scope.items())}")
    lines.append(f"unresolved imports in {len(unresolved_all)} files: {sorted(set(x for v in unresolved_all.values() for x in v))[:20]}")
    lines.append("")
    lines.append("== hazard sites (local-or-module collision; file:line:col name arg# head buckets) ==")
    for r, b in sorted(local_or_module, key=lambda rb: (rb[0]['file'], rb[1]['pos'] or (0, 0))):
        pos = b['pos'] or (0, 0)
        buckets = ','.join(bucket_of(k) for k in b['collides'])
        lines.append(f"{r['file']}:{pos[0]}:{pos[1]}  {b['name']!r}  arg{b['arg']}  head={r['head']}  {buckets}")
    lines.append("")
    lines.append("== selector-only sites (deliberate wildcard; unchanged under R1) ==")
    for r, b in sorted(selector_only, key=lambda rb: (rb[0]['file'], rb[1]['pos'] or (0, 0))):
        pos = b['pos'] or (0, 0)
        lines.append(f"{r['file']}:{pos[0]}:{pos[1]}  {b['name']!r}  arg{b['arg']}  head={r['head']}")
    summary = {
        'files_scanned': files_scanned, 'files_failed': failed,
        'unresolved_imports': unresolved_all,
        'n_actions': n_actions, 'n_arg_binders': n_binders, 'n_exactly': n_exactly,
        'n_collide': len(collide), 'n_selector_only': len(selector_only),
        'n_local_or_module': len(local_or_module), 'by_scope': dict(by_scope),
        'hazard_sites': [
            {'file': r['file'], 'pos': b['pos'], 'name': b['name'], 'arg': b['arg'],
             'head': r['head'], 'collides': b['collides']}
            for r, b in local_or_module
        ],
        'selector_sites': [
            {'file': r['file'], 'pos': b['pos'], 'name': b['name'], 'arg': b['arg'], 'head': r['head']}
            for r, b in selector_only
        ],
        'actions': results,
    }
    return summary, '\n'.join(lines)

def consider_report(records, files_scanned, failed, unresolved_all, n_consider_nodes, n_consider_branches):
    n_binders = len(records)
    collide = [r for r in records if r['collides']]
    selector_only = [r for r in collide if all(k == 'selector' for k in r['collides'])]
    local_or_module = [r for r in collide if any(k != 'selector' for k in r['collides'])]
    by_scope = Counter()
    for r in local_or_module:
        by_scope[bucket_of(r['collides'][0])] += 1
    synthetic = [r for r in local_or_module if r['is_synthetic_pm']]
    lines = []
    lines.append(f"files scanned: {files_scanned}; ast failed: {len(failed)}")
    lines.append(f"CONSIDER nodes walked (literal + desugared multi-clause DECIDE): {n_consider_nodes}")
    lines.append(f"CONSIDER/pattern-match branches (WHEN + OTHERWISE): {n_consider_branches}")
    lines.append(f"CONSIDER/pattern-match branch bare-name binders: {n_binders}")
    lines.append(f"binders colliding with an in-scope term name: {len(collide)}")
    lines.append(f"  selector-only: {len(selector_only)}")
    lines.append(f"  local-or-module: {len(local_or_module)}  (of which from a desugared multi-clause DECIDE: {len(synthetic)})")
    lines.append(f"  by innermost non-selector collision bucket: {sorted(by_scope.items())}")
    lines.append(f"unresolved imports in {len(unresolved_all)} files: {sorted(set(x for v in unresolved_all.values() for x in v))[:20]}")
    lines.append("")
    lines.append("== CONSIDER collision sites (file:line:col name collides-with scrutinee synthetic?) ==")
    for r in sorted(local_or_module, key=lambda r: (r['file'], r['pos'] or (0, 0))):
        pos = r['pos'] or (0, 0)
        buckets = ','.join(bucket_of(k) for k in r['collides'])
        lines.append(f"{r['file']}:{pos[0]}:{pos[1]}  {r['name']!r}  {buckets}  scrutinee={r['scrutinee']}  synthetic={r['is_synthetic_pm']}")
    summary = {
        'files_scanned': files_scanned, 'files_failed': failed,
        'unresolved_imports': unresolved_all,
        'n_consider_nodes': n_consider_nodes, 'n_consider_branches': n_consider_branches,
        'n_binders': n_binders, 'n_collide': len(collide),
        'n_selector_only': len(selector_only), 'n_local_or_module': len(local_or_module),
        'n_synthetic_pm_collide': len(synthetic),
        'by_scope': dict(by_scope),
        'collision_sites': local_or_module,
        'selector_sites': selector_only,
        'all_binders': records,
    }
    return summary, '\n'.join(lines)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--repo', required=True)
    ap.add_argument('--l4', required=True, help='path to the l4 binary (snapshot it first -- never dist-newstyle/... directly)')
    ap.add_argument('--mode', choices=['deontic', 'consider'], required=True)
    ap.add_argument('--out', required=True, help='output JSON path')
    ap.add_argument('--cache-dir', default=None, help='ast-dump cache dir (scratch only; never under the worktree)')
    ap.add_argument('--files-from', default=None, help='file of repo-relative .l4 paths (default: git ls-files in --repo)')
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)

    if args.files_from:
        with open(args.files_from) as fh:
            all_files = [l.strip() for l in fh if l.strip()]
    else:
        all_files = subprocess.run(['git', 'ls-files', '*.l4'], capture_output=True, text=True, cwd=repo).stdout.split()

    # Neither mode pre-filters by a source-text keyword grep: a multi-clause
    # DECIDE that desugars to CONSIDER carries no literal "CONSIDER" token to
    # grep for, and a file's deontic-ness is exactly what we are asking the
    # parser, not assuming from a regex. Every tracked .l4 file is a
    # candidate for both modes.
    candidates = all_files

    results = []
    consider_records = []
    unresolved_all = {}
    failed = []
    n_consider_nodes = 0
    n_consider_branches = 0
    for f in candidates:
        p = os.path.join(repo, f)
        r = survey_file(repo, args.l4, p, args.cache_dir)
        if r is None:
            failed.append(f)
            continue
        sv, unresolved = r
        if unresolved:
            unresolved_all[f] = unresolved
        for rec in sv.records:
            rec['file'] = f
            results.append(rec)
        for rec in sv.consider_records:
            rec['file'] = f
            consider_records.append(rec)
        n_consider_nodes += sv.n_consider
        n_consider_branches += sv.n_consider_branches

    if args.mode == 'deontic':
        summary, text = deontic_report(results, len(candidates), failed, unresolved_all)
    else:
        summary, text = consider_report(consider_records, len(candidates), failed, unresolved_all,
                                         n_consider_nodes, n_consider_branches)

    with open(args.out, 'w') as fh:
        json.dump(summary, fh, indent=1)
    print(text)

if __name__ == '__main__':
    main()
