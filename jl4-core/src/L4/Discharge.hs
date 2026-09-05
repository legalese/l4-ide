-- | Discharge: a section-level @GIVEN@ becomes an ordinary parameter of every
-- definition that reads it.
--
-- The section binder (R4, shipped in legalese\/l4-ide#333) is parsed as a
-- 'GivenSig' hanging off a section heading and desugared by
-- 'L4.Desugar.desugarSectionGivens' into a 0-ary @ASSUME@ at the head of that
-- section's declarations. That much makes the binder /resolve/ like a
-- same-section @ASSUME@ — nearest-ancestor visibility, the export schema entry,
-- the six backends — but it also makes it /evaluate/ like one: a definition
-- that reads it is stuck on an assumed term, and there is no way to supply a
-- value except at the module's own address, once, for the whole evaluation.
--
-- This pass replaces that placeholder with the elaboration
-- @PROPS-REDTEAM-2026-09-03.md@ §2.2 specifies:
--
-- > R(f) = reads(f) ∪ ⋃ { R(g) | g referenced in f }
--
-- Every module-level definition with a non-empty read-set takes those binders
-- as parameters /trailing/ its own (R10), every reference passes them through
-- unchanged, and a @WITH@ that names one at a call site becomes an ordinary
-- argument. After the pass the module is plain L4: no environment, no dynamic
-- extent, no cache axis. \"Assumed term\" survives only as \"unsupplied at the
-- root\", because the root's own reference to the binder is still the
-- module-level @ASSUME@ the desugaring left there.
--
-- == Why the parameter reuses the binder's own 'Unique'
--
-- The discharged parameter is not a fresh name: it is the binder's own
-- 'Resolved', taken off the section's 'GivenSig'. The evaluator's environment
-- is keyed by 'Unique' ('L4.Evaluate.ValueLazy.Environment') and
-- 'L4.EvaluateLazy.Machine.matchGivens' binds a closure's parameters at exactly
-- those keys, so a body that already refers to the binder finds the argument
-- with no renaming at all, and the pass never has to mint a 'Unique' or
-- re-resolve a name. It is also what makes the fixpoint sound: because
-- @R(caller) ⊇ R(callee)@, the caller is guaranteed to have the very key its
-- call site needs to pass on.
--
-- == What this pass deliberately does not do
--
-- * __It does not cross @IMPORT@__ (§2.2: \"nothing implicit crosses
--   @IMPORT@\"). The read-set is computed over one module's definitions, so a
--   definition in an imported module keeps the arity it was checked with.
--   See 'dischargeModule' for the consequence and how it is reported.
-- * __It does not run before the backends.__ The DMN, Catala, Docassemble,
--   OpenFisca, Blawx and MLIR lowerings consume the /undischarged/ module and
--   see a section binder as the 0-ary @ASSUME@ they saw before this pass
--   existed. Moving them onto the discharged AST is R10 and is separate work;
--   until it happens 'implicitSupplySites' names the one construct they cannot
--   see (an inner @WITH@ on a binder) so they can refuse rather than answer
--   wrongly.
module L4.Discharge
  ( dischargeModule
  , sectionBinders
  , Binder (..)
  , readSets
  , implicitSupplySites
  , unreadImplicitSupplies
  , valueReferenceHazards
  ) where

import Base
import Control.Applicative ((<|>))
import qualified Base.Map as Map
import qualified Data.Set as Set
import L4.Annotation (emptyAnno)
import L4.Export (decideBodiesFromModule, transitiveReferencedUniquesWith)
import L4.Syntax
import qualified Optics

-- | A section binder, as the checker left it on the section's own 'GivenSig'.
--
-- 'resolved' is a /referring/ occurrence (see 'L4.TypeCheck.resolveSectionGiven':
-- the binder is defined by its elaboration, and the @GIVEN@ line refers to it),
-- which is all the evaluator needs — 'getUnique' is the same either way.
data Binder = MkBinder
  { resolved  :: Resolved
  , typ       :: Maybe (Type' Resolved)
  , typically :: Maybe (Expr Resolved)
  , position  :: Int
    -- ^ Declaration order across the whole module. This is the canonical order
    -- in which discharged parameters trail a definition's own, so that a
    -- caller and a callee agree without either consulting the other.
  }

-- | Every section binder in the module, keyed by 'Unique'.
sectionBinders :: Module Resolved -> Map.Map Unique Binder
sectionBinders (MkModule _ _ sect) =
  Map.fromList (zipWith withPosition [0 ..] (goSection sect))
 where
  withPosition i (u, b) = (u, b { position = i })

  goSection (MkSection _ _ _ mgiven decls) =
    binderParams mgiven <> concat [ goSection s | Section _ s <- decls ]

  binderParams Nothing = []
  binderParams (Just (MkGivenSig _ otns)) =
    [ ( getUnique r
      , MkBinder { resolved = r, typ = mty, typically = mtyp, position = 0 }
      )
    | MkOptionallyTypedName _ r mty mtyp <- otns
    ]

-- | The read-set of every module-level definition: the section binders it
-- names, plus those named by anything it reaches through the call graph.
--
-- Cycle-safe, because 'transitiveReferencedUniquesWith' is: a recursive group
-- is discharged as a block, every member carrying the union.
readSets :: Module Resolved -> Map.Map Unique Binder -> Map.Map Unique [Binder]
readSets mod' binders
  | Map.null binders = Map.empty
  | otherwise =
      Map.mapMaybe (nonEmptyRead . readSetOf) bodies
 where
  -- A binder's TYPICALLY default is a module-scope expression whose own
  -- read-set joins the requirement of every root that may use it (R8 rule 3,
  -- "Closure"), so it is an edge of the call graph like any definition's body.
  --
  -- A default can never itself read a binder, so this edge never keys an entry
  -- in the result by a BINDER's own 'Unique' — which matters, because
  -- 'dischargeModule' gives a default's elaborated definition no trailing
  -- parameters and a caller passing some would be an arity mismatch. Two
  -- independent guards make it unreachable (probed 2026-09-05): the grammar
  -- rejects an operator after @TYPICALLY@, and a dedicated check rejects a bare
  -- identifier ("the TYPICALLY value ... must be a literal: a number, a string,
  -- or a nullary constructor"). The edge is kept because R8 rule 3 is about the
  -- default's read-set in general, and the guards are the parser's to relax.
  bodies =
    decideBodiesFromModule mod'
      <> Map.fromList [ (u, e) | (u, b) <- Map.toList binders, Just e <- [b.typically] ]
  nonEmptyRead [] = Nothing
  nonEmptyRead bs = Just bs
  readSetOf body =
    canonicalise (transitiveReferencedUniquesWith bodies body)

  canonicalise us =
    sortOn (.position)
      [ b | u <- Set.toList us, Just b <- [Map.lookup u binders] ]

-- | Discharge a checked module.
--
-- Idempotent in the sense that matters: a module with no section binder is
-- returned unchanged and untraversed.
--
-- __Imports.__ The read-set is computed over this module's own definitions, so
-- a definition an importer calls keeps whatever arity it was given when its own
-- module was discharged. Today that is not reachable — no file in @jl4\/examples@,
-- @jl4-core\/libraries@ or @doc@ that declares a section binder is @IMPORT@ed by
-- another (measured 2026-09-05) — and the corpus migration keeps it that way,
-- because the files being rewritten are the ones nothing imports. If it ever is
-- reached, the failure is loud: 'L4.EvaluateLazy.Machine.matchGivens'' raises a
-- length mismatch naming the callee, rather than answering with a wrong value.
-- Discharging across an import needs the importer's pass to see the imported
-- module's read-sets, which is §2.2's \"discharge happens at the module
-- boundary\" and is not in this release.
dischargeModule :: Module Resolved -> Module Resolved
dischargeModule mod'
  | Map.null binders = mod'
  | Map.null rs      = mod'
  | otherwise        = rewriteExprs (rewriteSignatures mod')
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders

  -- Trailing parameters, on the definition's AppForm (which is what
  -- 'L4.EvaluateLazy.Machine.evalDecide' builds the closure's binders from) and
  -- on its GivenSig (which is what a reader and 'L4.Print.prettyLayout' see).
  rewriteSignatures (MkModule ann uri sect) = MkModule ann uri (goSection sect)
   where
    goSection (MkSection sann mn maka mgiven decls) =
      MkSection sann mn maka mgiven (map goTopDecl decls)
    goTopDecl = \ case
      Section a s -> Section a (goSection s)
      Decide a d  -> Decide a (goDecide d)
      Assume a as -> fromMaybe (Assume a as) (fillInDefault a as)
      other       -> other
    goDecide d@(MkDecide dann tysig (MkAppForm afann n args maka) body) =
      case Map.lookup (getUnique n) rs of
        Nothing -> d
        Just bs ->
          MkDecide dann
            (extendTypeSig bs tysig)
            (MkAppForm afann n (args <> map (.resolved) bs) maka)
            body

  extendTypeSig bs (MkTypeSig tann (MkGivenSig gann otns) mgiveth) =
    MkTypeSig tann (MkGivenSig gann (otns <> map binderParam bs)) mgiveth

  -- The default lives at the ONE declaration that owns it (R8 rule 2), which
  -- after this pass is the module-level definition below; the discharged
  -- parameter therefore carries no default of its own, and could not use one —
  -- discharge always passes it something.
  binderParam b = MkOptionallyTypedName emptyAnno b.resolved b.typ Nothing

  -- R8, "filled in once at the root". A binder declared @TYPICALLY d@ stops
  -- being an assumed term and becomes an ordinary 0-ary definition whose body
  -- is @d@. Every reader takes the binder as a parameter and every call passes
  -- it on, so the only site that can reach this definition is a root that
  -- supplied nothing — and because a 0-ary definition is a shared thunk, @d@ is
  -- forced at most once per evaluation and every reader sees the same value.
  -- An inner @WITH@ still wins: it is an argument, and arguments shadow.
  --
  -- Nothing when the binder has no default, or when this declaration is not a
  -- section-binder elaboration at all (an ordinary ASSUME keeps its meaning).
  fillInDefault a (MkAssume asann tysig appform@(MkAppForm _ n [] _) mty (Just d))
    | Map.member (getUnique n) binders =
        Just (Decide a (MkDecide asann (withGiveth mty tysig) appform d))
  fillInDefault _ _ = Nothing

  -- The ASSUME carried its declared type in its own field; a DECIDE carries it
  -- on the signature's GIVETH. Keeping it there is what lets a reader (and
  -- 'L4.Print.prettyLayout') still see what the default was declared to be.
  withGiveth mty (MkTypeSig tann givens mgiveth) =
    MkTypeSig tann givens (mgiveth <|> fmap (MkGivethSig emptyAnno) mty)

  -- Pass them through at every reference. A definition's own body, a WHERE or
  -- LET local inside it, a lambda, a directive: all of them are Expr children
  -- of the module, so one traversal reaches them all.
  rewriteExprs =
    Optics.over (Optics.gplate @(Expr Resolved))
      (Optics.transformOf (Optics.gplate @(Expr Resolved)) rewriteCall)

  rewriteCall = \ case
    App ann n args
      | Just bs <- Map.lookup (getUnique n) rs ->
          App ann n (args <> map flowed bs)
    -- 'Var' and 'App _ n []' are the same thing to the evaluator ("still
    -- problematic: similarity / overlap", 'L4.EvaluateLazy.Machine'), so both
    -- have to grow the same arguments or a 'Var' would reach a closure with
    -- none.
    Var ann n
      | Just bs <- Map.lookup (getUnique n) rs ->
          App ann n (map flowed bs)
    -- The evaluator desugars a projection to @App _ field [record]@, so a
    -- COMPUTED field whose body reads a binder needs the same treatment as any
    -- other definition: its selector is an ordinary module-level DECIDE.
    Proj ann e f
      | Just bs <- Map.lookup (getUnique f) rs ->
          App ann f (e : map flowed bs)
    -- A named call site supplying an implicit. R1: a site is entirely
    -- positional or entirely named, so the declared parameters are all present
    -- and their permutation is the non-negative half of the order list; the
    -- implicits are whatever the writer chose to override, and every binder the
    -- writer did not name keeps flowing.
    AppNamed ann n nes (Just order)
      | Just bs <- Map.lookup (getUnique n) rs ->
          let paired      = zip order nes
              positional  = map snd (sortOn fst (filter ((>= 0) . fst) paired))
              supplied    = [ ne | (i, ne) <- paired, i < 0 ]
              declared    = [ e | MkNamedExpr _ _ e <- positional ]
          in App ann n (declared <> map (supply supplied) bs)
    other -> other

  -- The value a call passes on when the writer said nothing: the binder itself,
  -- which inside a discharged caller is that caller's own trailing parameter and
  -- at a root is still the module-level ASSUME.
  flowed b = App emptyAnno b.resolved []

  supply supplied b =
    case [ e | MkNamedExpr _ r e <- supplied, getUnique r == getUnique b.resolved ] of
      e : _ -> e
      []    -> flowed b

-- | Call sites that supply a section binder by name — the construct a backend
-- consuming the undischarged module cannot see, and must therefore refuse by
-- name rather than lower as though the override were not there.
--
-- Returns the callee and the binder supplied, one entry per supplied binder.
implicitSupplySites :: Module Resolved -> [(Resolved, Resolved)]
implicitSupplySites mod' =
  [ (n, r)
  | AppNamed _ n nes (Just order) <- allExprs mod'
  , (i, MkNamedExpr _ r _) <- zip order nes
  , i < 0
  ]

-- | Named call sites that supply a section binder the callee does not read.
--
-- Under R1 a @WITH@ may name a binder /in the callee's read-set/; naming one
-- outside it is the same mistake as naming a parameter the callee does not
-- take, and must be reported for the same reason — discharge has nowhere to put
-- the value, so an unreported one would be an override that silently did
-- nothing. The check cannot live in 'L4.TypeCheck.supplyAppNamed', which sees
-- one body at a time; the read-set is a whole-module fact.
--
-- Returns @(callee, binder)@ pairs.
--
-- Both this and 'valueReferenceHazards' run on every module the checker
-- accepts, so both begin by asking 'sectionBinders' — a walk of the section
-- headings alone — and stop there when the module declares none. Without that
-- guard every file in the corpus would pay two full 'allExprs' traversals to be
-- told there is nothing to report; today that is 305 of the 312 files under
-- @ok\/**@ and @legal\/**@.
unreadImplicitSupplies :: Module Resolved -> [(Resolved, Resolved)]
unreadImplicitSupplies mod'
  | Map.null binders = []
  | otherwise =
      [ (n, r)
      | (n, r) <- implicitSupplySites mod'
      , getUnique r `notElem` map (getUnique . (.resolved)) (readSetOf n)
      ]
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders
  readSetOf n = fromMaybe [] (Map.lookup (getUnique n) rs)

-- | References to a discharged definition that are /not/ calls: a definition
-- with declared parameters, named but not applied, and so used as a first-class
-- value.
--
-- Discharge appends the binders to such a definition's parameter list, but a
-- bare reference cannot carry them without an eta-expansion this pass does not
-- perform (it would have to mint 'Unique's). Reported so the caller can refuse
-- by name.
--
-- __A @#CHECK@ does not count.__ @#CHECK e@ reports the type @e@ was declared
-- with and never evaluates it (@evalDirective (Check _ _) = pure []@,
-- "L4.EvaluateLazy.Machine"), so a bare mention of a discharged reader there is
-- a question /about/ the rule, not a use of it as a value: nothing has to carry
-- the extra parameter. Measured 2026-09-05 by the oracle below: without this
-- exclusion @ok\/section-given-indented.l4:29@ — @#CHECK \`tax on\`@, green
-- before this pass — turns red, and it is the only site in @ok\/**@,
-- @legal\/**@ or @jl4-core\/libraries@ that this check reaches at all.
valueReferenceHazards :: Module Resolved -> [Resolved]
valueReferenceHazards mod'
  | Map.null binders = []
  | otherwise =
      [ n
      | App _ n [] <- allExprs (withoutCheckDirectives mod')
      , Map.member (getUnique n) rs
      , Just k <- [Map.lookup (getUnique n) arities]
      , k > 0
      ]
 where
  binders  = sectionBinders mod'
  rs       = readSets mod' binders
  arities  = declaredArities mod'

-- | The module with its @#CHECK@ directives dropped.
--
-- Only ever used to narrow a /query/ ('valueReferenceHazards'); the module the
-- evaluator runs is never built this way. 'unreadImplicitSupplies' deliberately
-- does /not/ use it: naming a binder the callee does not read is a mistake
-- wherever it is written, and reporting it there costs nothing.
withoutCheckDirectives :: Module Resolved -> Module Resolved
withoutCheckDirectives (MkModule ann uri sect) = MkModule ann uri (goSection sect)
 where
  goSection (MkSection sann mn maka mgiven decls) =
    MkSection sann mn maka mgiven (concatMap goTopDecl decls)
  goTopDecl = \ case
    Directive _ Check{} -> []
    Section a s         -> [Section a (goSection s)]
    other               -> [other]

-- | Every expression anywhere in the module, sub-expressions included.
allExprs :: Module Resolved -> [Expr Resolved]
allExprs mod' =
  concatMap
    (Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Resolved))))
    (Optics.toListOf (Optics.gplate @(Expr Resolved)) mod')

-- | How many parameters each module-level definition was written with.
declaredArities :: Module Resolved -> Map.Map Unique Int
declaredArities (MkModule _ _ sect) = Map.fromList (goSection sect)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \ case
    Decide _ (MkDecide _ _ (MkAppForm _ n args _) _) -> [(getUnique n, length args)]
    Section _ s -> goSection s
    _ -> []
