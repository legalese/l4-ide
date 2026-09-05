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
-- with no renaming at all, and the pass never has to re-resolve a name. It is
-- also what makes the fixpoint sound: because
-- @R(caller) ⊇ R(callee)@, the caller is guaranteed to have the very key its
-- call site needs to pass on.
--
-- The pass mints a 'Unique' in exactly one place: the parameters of the
-- eta-expansion that lets a reader with parameters of its own be passed as a
-- value. See 'dischargeModule'.
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
  , ambiguousImplicitSupplies
  ) where

import Base
import Control.Applicative ((<|>))
import qualified Base.Map as Map
import qualified Base.Text as Text
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
  -- ONLY definition bodies. A binder's TYPICALLY default is deliberately NOT an
  -- edge of this graph, which makes R8 rule 3 ("Closure" -- a default's own
  -- read-set joins the requirement of every root that may use it) DEFERRED, not
  -- implemented.
  --
  -- Its guard is that a default is literal-only, so it can read nothing: probed
  -- 2026-09-05, the grammar rejects an operator after TYPICALLY and a dedicated
  -- check rejects a bare identifier ("the TYPICALLY value ... must be a literal:
  -- a number, a string, or a nullary constructor"). Adding the edge anyway is
  -- worse than leaving it out, because it keys an entry in the result by a
  -- BINDER's own Unique -- and 'dischargeModule' gives a default's elaborated
  -- definition no trailing parameters, while 'rewriteCall' would then rewrite
  -- every reference to that binder, including the value-bound parameter
  -- references inside readers, into an application. If the literal restriction
  -- is ever lifted, supply-through-defaults has to be built deliberately.
  bodies = decideBodiesFromModule mod'
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
  --
  -- Monadic only to mint the eta-expansion parameters below; the counter is the
  -- whole state.
  rewriteExprs m =
    evalState
      (Optics.traverseOf (Optics.gplate @(Expr Resolved))
         (Optics.transformMOf (Optics.gplate @(Expr Resolved)) rewriteCall) m)
      0

  arities = declaredArities mod'

  rewriteCall = \ case
    -- A bare reference to a definition that takes parameters of its own: it is
    -- being passed as a VALUE, so the trailing binders cannot simply be appended
    -- — that would put them in the first argument positions. Eta-expand instead.
    App ann n []
      | Just bs <- Map.lookup (getUnique n) rs
      , Just k  <- Map.lookup (getUnique n) arities
      , k > 0 -> etaExpand ann n k bs
    Var ann n
      | Just bs <- Map.lookup (getUnique n) rs
      , Just k  <- Map.lookup (getUnique n) arities
      , k > 0 -> etaExpand ann n k bs
    App ann n args
      | Just bs <- Map.lookup (getUnique n) rs ->
          pure (App ann n (args <> map flowed bs))
    -- 'Var' and 'App _ n []' are the same thing to the evaluator ("still
    -- problematic: similarity / overlap", 'L4.EvaluateLazy.Machine'), so both
    -- have to grow the same arguments or a 'Var' would reach a closure with
    -- none.
    Var ann n
      | Just bs <- Map.lookup (getUnique n) rs ->
          pure (App ann n (map flowed bs))
    -- The evaluator desugars a projection to @App _ field [record]@, so a
    -- COMPUTED field whose body reads a binder needs the same treatment as any
    -- other definition: its selector is an ordinary module-level DECIDE.
    Proj ann e f
      | Just bs <- Map.lookup (getUnique f) rs ->
          pure (App ann f (e : map flowed bs))
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
          in pure (App ann n (declared <> map (supply bs supplied) bs))
    other -> pure other

  -- @f@, named but not applied, where @f@ takes @k > 0@ parameters of its own
  -- and reads binders @bs@. A bare name cannot carry the trailing binders, so
  -- the reference becomes the function the writer meant:
  --
  -- > GIVEN _eta0 ... _eta(k-1) YIELD f _eta0 ... _eta(k-1) b1 ... bn
  --
  -- This is the one place the pass mints a 'Unique'. They carry the sort char
  -- @\'d\'@, which no other minter uses (@\'c\'@ is 'L4.TypeCheck', @\'e\'@ the
  -- evaluator, @\'b\'@ the builtins, @\'x\'@ 'L4.Relational.Lower'), so an
  -- eta parameter cannot collide with a name the module already had.
  --
  -- Measured 2026-09-05: without this, @legal\/british-citizen-act.l4@ on the
  -- @ASSUME@ sweep's tree loses both its @#EVAL@s — it passes the 1-ary reader
  -- @\`is a British citizen (variant)\`@ to a higher-order rule, which is
  -- ordinary L4 and must keep working.
  etaExpand ann n k bs = do
    ps <- traverse etaParam [0 .. k - 1]
    pure
      (Lam ann
        (MkGivenSig emptyAnno
          [ MkOptionallyTypedName emptyAnno p Nothing Nothing | p <- ps ])
        (App emptyAnno n (map (Var emptyAnno) ps <> map flowed bs)))

  etaParam i = do
    j <- get
    put (j + 1)
    pure
      (Def
        (MkUnique 'd' j moduleUriOf)
        (MkName emptyAnno (NormalName ("_eta" <> Text.pack (show (i :: Int))))))

  moduleUriOf = case mod' of MkModule _ uri _ -> uri

  -- The value a call passes on when the writer said nothing: the binder itself,
  -- which inside a discharged caller is that caller's own trailing parameter and
  -- at a root is still the module-level ASSUME.
  flowed b = App emptyAnno b.resolved []

  supply bs supplied b =
    case [ e | MkNamedExpr _ r e <- supplied, suppliesBinder bs r b ] of
      e : _ -> e
      []    -> flowed b

-- | Which binder in the callee's read-set a supplied name refers to.
--
-- By 'Unique' first. Failing that by SPELLING, provided the read-set holds
-- exactly one binder so spelled.
--
-- The spelling case is what makes R3's \"bridge at the call\" work. In
-- @g WITH foo IS foo@ the name to the LEFT of @IS@ is one of @g@'s implicit
-- inputs, but 'L4.TypeCheck.implicitSupply' resolved it in the CALLER's scope
-- to get its type — so when two sibling sections both declare @foo@, its
-- 'Unique' is the caller's and never matches the callee's. Declared parameters
-- are already matched this way ('L4.TypeCheck.lookupOptionallyNamedType'
-- compares raw names), so this makes implicits agree with them rather than
-- introducing a second rule.
--
-- Safe by construction: the spelling case can only fire where the 'Unique' case
-- failed, and a supply whose 'Unique' is in no read-set is an error today
-- ('unreadImplicitSupplies'). So it can turn an error into a working program
-- and can never change an answer a working program already gives.
suppliesBinder :: [Binder] -> Resolved -> Binder -> Bool
suppliesBinder bs r b
  | getUnique r == getUnique b.resolved = True
  | otherwise =
      spellingOf r == spellingOf b.resolved
        && length [ () | x <- bs, spellingOf x.resolved == spellingOf r ] == 1

-- The UNQUALIFIED text: a section binder's name can carry its declaring
-- section as a qualifier (the ambiguity diagnostic spells them
-- @toplevel.\`1\`.foo@ and @toplevel.\`2\`.foo@), while a writer supplying one
-- at a call spells it bare.
spellingOf :: Resolved -> Text
spellingOf = unqualifiedRawNameToText . rawName . getOriginal

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
-- This runs on every module the checker accepts, so it begins by asking
-- 'sectionBinders' — a walk of the section headings alone — and stops there when
-- the module declares none. Without that guard every file in the corpus would
-- pay a full 'allExprs' traversal to be told there is nothing to report; today
-- that is 305 of the 312 files under @ok\/**@ and @legal\/**@.
unreadImplicitSupplies :: Module Resolved -> [(Resolved, Resolved)]
unreadImplicitSupplies mod'
  | Map.null binders = []
  | otherwise =
      [ (n, r)
      | (n, r) <- implicitSupplySites mod'
      , not (any (suppliesBinder (readSetOf n) r) (readSetOf n))
      , not (ambiguousFor (readSetOf n) r)
      ]
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders
  readSetOf n = fromMaybe [] (Map.lookup (getUnique n) rs)

-- | Supplies whose 'Unique' matches no binder the callee reads and whose
-- SPELLING matches two or more of them.
--
-- 'suppliesBinder' deliberately refuses to guess between them, so without this
-- the value would be dropped in silence. Reported separately from
-- 'unreadImplicitSupplies' because the fix is different: the writer has to say
-- which binder is meant, by renaming one or hoisting them to a common ancestor.
ambiguousImplicitSupplies :: Module Resolved -> [(Resolved, Resolved)]
ambiguousImplicitSupplies mod'
  | Map.null binders = []
  | otherwise =
      [ (n, r)
      | (n, r) <- implicitSupplySites mod'
      , ambiguousFor (readSetOf n) r
      ]
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders
  readSetOf n = fromMaybe [] (Map.lookup (getUnique n) rs)

-- | No 'Unique' match, and two or more binders in the read-set spelled alike.
ambiguousFor :: [Binder] -> Resolved -> Bool
ambiguousFor bs r =
  getUnique r `notElem` map (getUnique . (.resolved)) bs
    && length [ () | x <- bs, spellingOf x.resolved == spellingOf r ] >= 2

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
