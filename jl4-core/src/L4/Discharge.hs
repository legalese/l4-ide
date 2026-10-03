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
-- The pass mints a 'Unique' in two places: the parameters of the eta-expansion
-- that lets a reader with parameters of its own be passed as a value (see
-- 'dischargeModule'), and the function that stands for a binder's default at a
-- root when that default reads other binders ('defaultThunkUnique').
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
  , dischargeModuleWith
  , sectionBinders
  , Binder (..)
  , readSets
  , implicitSupplySites
  , unreadImplicitSupplies
  , implicitSuppliesToInputs
  , ambiguousImplicitSupplies
  , misdeliveredImplicitSupplies
  , ambiguousRootBinders
  , implicitReaders
  , defaultCycles
  , inputDefaultReads
  , inputDefaultCaptures
  , defaultThunkUnique
  ) where

import Base
import Control.Applicative ((<|>))
import qualified Base.Map as Map
import qualified Base.Text as Text
import qualified Data.Set as Set
import L4.Annotation (emptyAnno)
import L4.Export (collectExportedDecides, collectReferencedUniques, decideBodiesFromModule, transitiveReferencedUniquesWith)
import L4.Presumption (requestRecordName)
import L4.Syntax
import L4.TypeCheck.Types (typeKey)
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
-- names, plus those named by anything it reaches through the call graph —
-- less whatever a call site supplies (§2.2's subtraction rule).
--
-- > R(f) = reads(f) ∪ ⋃ { R(g) \ supplied(f → g) | g called from f }
--
-- A @WITH@ that pins a binder at a call takes that binder off the caller's
-- requirement along that path: @h MEANS alpha PLUS (g WITH beta IS 100)@ reads
-- @alpha@ and nothing else, and a root that evaluates @h@ is not asked for
-- @beta@. Without the subtraction every caller would carry a dead trailing
-- parameter for every binder it pins, and the export schema would list it as
-- required.
--
-- Computed as a fixpoint over the whole call graph, so a recursive group is
-- discharged as a block, every member carrying the union. The iteration is
-- capped at one round per definition plus one: the sets only ever grow, so the
-- cap is never reached in practice, and it guarantees termination should the
-- spelling half of 'suppliesBinder' ever flip a match.
--
-- A binder's @TYPICALLY@ default is an expression (R8 rule 3), and reading the
-- binder reads what its default reads, so it is a node of this graph: a
-- pseudo-definition under the binder's own 'Unique' ('decideBodiesFromModule'),
-- whose read-set is what the default needs and which every reader of the
-- binder reaches. That is the default's read-set joining the requirement of
-- every root that may use it. The binder itself is NOT in the result — only
-- definitions are: a reference to a binder is a reader's own parameter, and
-- must not be turned into an application. 'defaultReads' is where the
-- pseudo-definitions' read-sets are, for the cycle check and for the root's
-- supply.
readSets :: Module Resolved -> Map.Map Unique Binder -> Map.Map Unique [Binder]
readSets mod' binders =
  Map.withoutKeys (readSetsAll mod' binders) (Map.keysSet binders)

-- | The read-set of every default a binder carries: the section binders its
-- expression reads, directly or through the definitions it calls and the other
-- binders' defaults it needs. Keyed by the binder. A binder whose default
-- reads nothing has no entry.
defaultReads :: Module Resolved -> Map.Map Unique Binder -> Map.Map Unique [Binder]
defaultReads mod' binders =
  Map.restrictKeys (readSetsAll mod' binders) (Map.keysSet binders)

readSetsAll :: Module Resolved -> Map.Map Unique Binder -> Map.Map Unique [Binder]
readSetsAll mod' binders = (readSetStages mod' binders).closed

-- | The read-sets in the two stages they are computed in. @own@ is what each
-- definition reads itself: its own names and its callees' own reads, less what
-- each call supplies. @closed@ is @own@ closed under the defaults of the binders
-- in each set, which is what a root is asked for.
--
-- A @WITH@ written inside a definition reaches only @own@: a binder that only a
-- default reads is worked out at the root, from the root's values, and a
-- supply written below the root never gets there. A @WITH@ at a directive (a
-- root) reaches @closed@.
data ReadSetStages = ReadSetStages
  { own    :: Map.Map Unique [Binder]
  , closed :: Map.Map Unique [Binder]
  }

readSetStages :: Module Resolved -> Map.Map Unique Binder -> ReadSetStages
readSetStages mod' binders
  | Map.null binders = ReadSetStages Map.empty Map.empty
  | otherwise =
      ReadSetStages
        { own    = Map.mapMaybe nonEmptyRead ownSets
        , closed = Map.mapMaybe nonEmptyRead
            (iterateToFixpoint (Map.size bodies + 1) closeStep ownSets)
        }
 where
  ownSets = iterateToFixpoint (Map.size bodies + 1) ownStep direct
  bodies = decideBodiesFromModule mod'

  -- Per definition: the binders its body names, and the definitions it calls
  -- together with what each call supplies by name.
  direct = Map.map (directBinderReads binders) bodies
  -- A reference to a binder is an edge to its default's pseudo-definition too
  -- ('decideBodiesFromModule'), and is left out here: it is what the closure
  -- below does, and taking it through the call graph would put a default's
  -- reads into the part a @WITH@ subtracts from.
  edges  = Map.map (filter (\ (g, _) -> not (Map.member g binders)) . bodyCallEdges bodies) bodies

  -- What a definition reads, not counting what a binder's default adds: its own
  -- names and its callees' own reads, less what each call supplies. This is the
  -- part a call site's @WITH@ takes away from. It has to be kept apart from the
  -- closure below, which is not subtracted from by a @WITH@: with the two mixed,
  -- @a TYPICALLY (h WITH b IS 1)@ was charged with what @b@'s default reads
  -- through @h@, although the site never takes @b@'s default, and a pair of
  -- defaults that are no circle was refused as one.
  ownStep current =
    Map.mapWithKey
      (\ u cur -> canonicalise (cur <> reachedThrough current (Map.findWithDefault [] u edges)))
      current

  -- Then each set is closed under the defaults of the binders in it. A root that
  -- supplies nothing for a binder works its default out from the root's own
  -- values, so a definition that takes the binder as a parameter is charged with
  -- what its default reads even when it never names the reads itself:
  -- @h MEANS (g WITH r IS 1)@ takes @b@ from its root, and the root works out
  -- @b@'s default from the root's @r@. A binder with no default has no entry in
  -- @current@ and adds nothing.
  closeStep current =
    Map.map (\ bs -> canonicalise (bs <> defaultsOf current bs)) current

  defaultsOf current bs =
    concat [ Map.findWithDefault [] (key b) current | b <- bs ]

  iterateToFixpoint :: Int -> (Map.Map Unique [Binder] -> Map.Map Unique [Binder]) -> Map.Map Unique [Binder] -> Map.Map Unique [Binder]
  iterateToFixpoint fuel f x
    | fuel <= 0 = x
    | otherwise =
        let x' = f x
        in if sameSets x x' then x' else iterateToFixpoint (fuel - 1) f x'

  sameSets a b =
    Map.keys a == Map.keys b
      && and (zipWith (\ xs ys -> map key xs == map key ys) (Map.elems a) (Map.elems b))
  key b = getUnique b.resolved

  nonEmptyRead [] = Nothing
  nonEmptyRead bs = Just bs

  canonicalise = canonicaliseBinders

-- | Section binders whose @TYPICALLY@ default reads the binder itself, directly
-- or through another binder's default or a definition either calls: the check
-- of R8 rule 3, @b ∈ R*(default(b))@. One entry per circle, naming the binders
-- on it in declaration order; the checker reports each at its first.
--
-- A default that SUPPLIES the binder it would otherwise read, as in
-- @b TYPICALLY (g WITH b IS 1)@, does not read it, by the same subtraction as
-- everywhere else, so it is no circle.
defaultCycles :: Module Resolved -> [[Resolved]]
defaultCycles mod'
  | Map.null binders = []
  | otherwise        = go [] (sortOn (.position) onCircle)
 where
  binders = sectionBinders mod'
  reads'  = defaultReads mod' binders
  uniqOf b = getUnique b.resolved
  readsOf b = Set.fromList (map uniqOf (Map.findWithDefault [] (uniqOf b) reads'))
  onCircle = [ b | b <- Map.elems binders, uniqOf b `Set.member` readsOf b ]

  go _    []       = []
  go seen (b : bs)
    | uniqOf b `elem` seen = go seen bs
    | otherwise =
        let members =
              [ c | c <- onCircle
                  , uniqOf c `Set.member` readsOf b
                  , uniqOf b `Set.member` readsOf c ]
        in map (.resolved) members : go (map uniqOf members <> seen) bs

-- | The section binders that the @TYPICALLY@ default of a rule's input or a
-- record's field reads, directly or through the definitions it calls: one entry
-- for each such input or field that reads any, with the binders it reads in
-- declaration order. The checker refuses each ('L4.TypeCheck.Types.TypicallyReadsInput').
--
-- A section binder's default is worked out ONCE, at the root, from the root's
-- values (R8 rule 3). A default on a rule's input or a record's field is copied
-- to every call or construction that leaves it out, so what it reads there is
-- whatever that site reads, and the one expression gives one answer under an
-- inner @WITH@, another at a directive that supplies the same binder, and a
-- third through @l4 batch@ and the service, which work it out at the root. R8
-- says where a section's is worked out and does not say where these are, so a
-- default that would depend on it is refused (TYPICALLY-ONE-BEHAVIOUR-SPEC.md
-- §4.3, decision 1). A default that reads only definitions that read no binder
-- has one value wherever it is taken and is not in this list.
--
-- The section binders' own defaults are not in it: they are the 'sectionBinders'
-- themselves and 'defaultCycles' is where they are checked.
inputDefaultReads :: Module Resolved -> [(Resolved, [Binder])]
inputDefaultReads mod'
  | Map.null binders = []
  | otherwise =
      [ (owner, reads')
      | (owner, d) <- ruleInputDefaults <> fieldDefaults
      , let reads' = exprReads d
      , not (null reads')
      ]
 where
  binders = sectionBinders mod'
  bodies  = decideBodiesFromModule mod'
  stages  = readSetStages mod' binders

  -- The same two steps a definition's read-set is: what the expression names and
  -- what it reaches through its calls, less what each call supplies, and then
  -- that closed under the defaults of the binders in it. The subtraction acts on
  -- the first: a default that SUPPLIES an input gives the rule it calls that
  -- input, so the input's own default is never taken and what it reads is not
  -- read (@k TYPICALLY (h WITH b IS 1)@ with @b TYPICALLY (r PLUS 1)@ reads
  -- neither; it was refused as reading @r@, W7 second review, silent S7). A
  -- reference to a binder is itself closed under that binder's default, as in
  -- 'readSetStages'.
  exprReads e =
    let direct =
          canonicaliseBinders
            (directBinderReads binders e
               <> reachedThrough stages.own
                    (filter (\ (g, _) -> not (Map.member g binders)) (bodyCallEdges bodies e)))
    in canonicaliseBinders
         (direct <> concat [ Map.findWithDefault [] (getUnique b.resolved) stages.closed | b <- direct ])

  -- A section's own @GIVEN@ is an 'OptionallyTypedName' too, and is where a
  -- binder's default is written; it is not a rule's input.
  ruleInputDefaults =
    [ (r, d)
    | MkOptionallyTypedName _ r _ (Just d) <- nodesOfType @(OptionallyTypedName Resolved) mod'
    , not (Map.member (getUnique r) binders)
    ]
  -- The record the service and @l4 batch generate for a request is not the
  -- author's: each input of the exported rule is one of its fields, with the
  -- input's default as the field's, so a section input's default that reads
  -- another section input sits there as a field default that reads a section
  -- input. That is right there, and refusing it refused every request that
  -- supplied such an input, or sent @{}@ for it, and every request under hard
  -- (W7 second review, silent S3 and rulings S2).
  fieldDefaults =
    [ (r, d)
    | tns <- authoredFieldGroups mod'
    , MkTypedName _ r _ (Just d) _ <- tns
    ]

-- | The @TYPICALLY@ defaults of rule inputs and record fields that NAME, by
-- spelling, another input of the same rule or another field of the same record:
-- one entry for each such default, with the names it uses, in the order they
-- occur.
--
-- A default is worked out outside the rule or record it is written on, where
-- that rule's inputs and that record's fields are not in scope
-- ('L4.TypeCheck.checkPendingDefaults', 'L4.TypeCheck.checkFieldDefaults'). So a
-- name spelled like a sibling resolves to something else, when something else
-- is called that, and the answer quietly uses it:
-- @bonus TYPICALLY (salary DIVIDED BY 10)@ beside the input @salary@ and a
-- definition @salary MEANS 50000@ is a tenth of the 50000 and not of the
-- input, with no error and the schema printing the opposite. When nothing else
-- is called that, the name is reported as not in scope, which is the wording
-- the documentation gives ("It cannot name the rule's other inputs"); this is
-- the same refusal for the case where it is not (smucclaw/l4-ide W7, silent
-- review S1).
--
-- A name the author qualified with its section is exempt: it says which
-- definition it means. So is a name the default binds itself (a lambda's
-- parameter, a @LET@ or @WHERE@ binding): it never reaches the module's scope.
-- The record the service and @l4 batch decode a request into is not the
-- author's, and carries each input of the exported rule beside the default's
-- text, so it is not examined.
inputDefaultCaptures :: Module Resolved -> [(Resolved, [Resolved])]
inputDefaultCaptures mod' =
  [ (owner, names)
  | (owner, siblings, d) <- ruleInputs <> recordFields
  , let names = captured siblings d
  , not (null names)
  ]
 where
  binders = sectionBinders mod'

  -- A section's own GIVEN is a 'GivenSig' too; its inputs are binders, whose
  -- defaults may read each other by name and are resolved among them.
  ruleInputs =
    [ (r, siblings, d)
    | MkGivenSig _ otns <- nodesOfType @(GivenSig Resolved) mod'
    , let siblings = [ r' | MkOptionallyTypedName _ r' _ _ <- otns ]
    , MkOptionallyTypedName _ r _ (Just d) <- otns
    , not (Map.member (getUnique r) binders)
    ]

  recordFields =
    [ (r, siblings, d)
    | tns <- authoredFieldGroups mod'
    , let siblings = [ r' | MkTypedName _ r' _ _ _ <- tns ]
    , MkTypedName _ r _ (Just d) _ <- tns
    ]

  captured siblings d =
    [ ref
    | ref <- namesIn d
    , Ref actual u _ <- [ref]
    , NormalName t <- [rawName actual]
    , t `elem` map spellingOf siblings
    , not (Set.member u (definedIn d))
    ]

  -- The references that can reach the module's scope: a call, a bare name, or
  -- the field of a projection.
  namesIn d =
    concat
      [ case e of
          App _ r _        -> [r]
          AppNamed _ r _ _ -> [r]
          Proj _ _ f       -> [f]
          _                -> []
      | e <- subExprsOf d
      ]

  -- What the default binds itself. Type variables a node's annotation holds are
  -- in here too, which cannot be the 'Unique' of a value a default names.
  definedIn d = Set.fromList [ u | Def u _ <- Optics.toListOf (Optics.gplate @Resolved) d ]

-- | The fields of each record the author declared, and of each enum
-- constructor that carries data, one group per record or constructor. Not the
-- record 'requestRecordName' that @l4 batch@ and the service generate to decode
-- a request into.
authoredFieldGroups :: Module Resolved -> [[TypedName Resolved]]
authoredFieldGroups mod' =
  [ tns
  | MkDeclare _ _ (MkAppForm _ n _ _) decl <- nodesOfType @(Declare Resolved) mod'
  , spellingOf n /= requestRecordName
  , tns <- case decl of
      RecordDecl _ _ ts -> [ts]
      EnumDecl _ cds    -> [ ts | MkConDecl _ _ ts <- cds ]
      _                 -> []
  ]

-- | Every node of one type in a module, whatever it sits inside: the topmost
-- ones, and then those nested under each.
nodesOfType
  :: forall a. (Optics.GPlate a (Module Resolved), Optics.GPlate a a)
  => Module Resolved -> [a]
nodesOfType m =
  concatMap (Optics.toListOf (Optics.cosmosOf (Optics.gplate @a)))
    (Optics.toListOf (Optics.gplate @a) m)

-- | The 'Unique' of the function that stands for a binder's default at a root
-- ('dischargeModuleWith'): one per binder, numbered by where it is declared, so
-- that discharge and the evaluator's report of the default agree on it without
-- either consulting the other. Sort char @\'q\'@, which no other minter uses
-- (see the list on 'dischargeModule').
defaultThunkUnique :: NormalizedUri -> Binder -> Unique
defaultThunkUnique uri b = MkUnique 'q' b.position uri

-- | The binders a body names directly.
directBinderReads :: Map.Map Unique Binder -> Expr Resolved -> [Binder]
directBinderReads binders body =
  [ b | u <- Set.toList (collectReferencedUniques body), Just b <- [Map.lookup u binders] ]

-- | One edge per CALL SITE, because what a site supplies is the site's own:
-- a definition called once with @WITH beta IS …@ and once positionally in
-- the same body contributes its full read-set through the second call.
-- 'collectReferencedUniques' cannot be used for this half; it merges the
-- sites of one callee, and the merged edge would re-add what a @WITH@ took
-- off.
--
-- Edges to definitions outside @bodies@ are dropped: they have no read-set to
-- contribute here. Across an @IMPORT@ that is not the same as "contributes
-- nothing" — see 'L4.Export.validateExportImplicitImports', which is what
-- refuses that case rather than answering it.
bodyCallEdges
  :: Map.Map Unique (Expr Resolved) -> Expr Resolved -> [(Unique, [Resolved])]
bodyCallEdges bodies body =
  [ (getUnique g, [ r | (i, MkNamedExpr _ r _) <- zip order nes, i < 0 ])
  | AppNamed _ g nes (Just order) <- subExprsOf body
  , Map.member (getUnique g) bodies
  ]
  <> [ (getUnique h, [])
     | e <- subExprsOf body
     , h <- case e of
         App _ h _  -> [h]
         Var _ h    -> [h]
         Proj _ _ f -> [f]
         _          -> []
     , Map.member (getUnique h) bodies
     ]

-- | What a body picks up through its call edges: each callee's read-set, less
-- whatever that call site supplies (§2.2's subtraction rule).
reachedThrough :: Map.Map Unique [Binder] -> [(Unique, [Resolved])] -> [Binder]
reachedThrough current es =
  concat
    [ [ b | b <- reached, not (any (\ r -> suppliesBinder reached r b) supplied) ]
    | (g, supplied) <- es
    , let reached = Map.findWithDefault [] g current
    ]

-- | Declaration order, once each.
canonicaliseBinders :: [Binder] -> [Binder]
canonicaliseBinders bs =
  Map.elems (Map.fromList [ (b.position, b) | b <- bs ])

subExprsOf :: Expr Resolved -> [Expr Resolved]
subExprsOf = Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Resolved)))

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
dischargeModule = dischargeModuleWith True

-- | 'dischargeModule', with T4's presumption switch
-- (TYPICALLY-ONE-BEHAVIOUR-SPEC.md §5). With it off, no binder's @TYPICALLY@
-- is filled in at the root ('fillInDefault' does not fire), so a binder that
-- nothing supplies stays the assumed term it was before defaults existed:
-- \"absent with no default\". Every other part of the pass is the same.
dischargeModuleWith :: Bool -> Module Resolved -> Module Resolved
dischargeModuleWith presume mod'
  | Map.null binders = mod'
  | Map.null rs      = mod'
  | otherwise        = rewriteExprs (rewriteSignatures mod')
 where
  binders = sectionBinders mod'
  rsAll   = readSetsAll mod' binders
  rs      = Map.withoutKeys rsAll (Map.keysSet binders)

  -- The binders whose default discharge fills ('fillInDefault') and whose
  -- default reads other binders. At a ROOT such a default is worked out from
  -- the root's own values for what it reads, which is not what the
  -- module-level definition holds once a @WITH@ has replaced one of them, so a
  -- root passes the default's function ('defaultFunctionDecl') applied to
  -- those values instead of the module-level definition (R8: "filled in once
  -- at the root"). A default that reads nothing needs no function, and the
  -- module-level definition serves.
  filledWithReads :: Map.Map Unique (Resolved, [Binder])
  filledWithReads
    | not presume = Map.empty
    | otherwise = Map.fromList
        [ (u, (defaultThunkName b, bs))
        | (u, b) <- Map.toList binders
        , Map.member u elaborated
        , Just bs <- [Map.lookup u rsAll]
        ]
   where
    elaborated = Map.restrictKeys (decideBodiesFromModule mod') (Map.keysSet binders)

  defaultThunkName b =
    Def (defaultThunkUnique moduleUriOf b)
        (MkName emptyAnno (NormalName ("default of " <> unqualifiedRawNameToText (rawName (getOriginal b.resolved)))))

  -- Trailing parameters, on the definition's AppForm (which is what
  -- 'L4.EvaluateLazy.Machine.evalDecide' builds the closure's binders from) and
  -- on its GivenSig (which is what a reader and 'L4.Print.prettyLayout' see).
  rewriteSignatures (MkModule ann uri sect) = MkModule ann uri (goSection sect)
   where
    goSection (MkSection sann mn maka mgiven decls) =
      MkSection sann mn maka mgiven (concatMap goTopDecl decls)
    goTopDecl = \ case
      Section a s -> [Section a (goSection s)]
      Decide a d  -> [Decide a (goDecide d)]
      Assume a as -> case fillInDefault a as of
        Nothing  -> [Assume a as]
        Just dec -> dec : maybeToList (defaultFunctionDecl as)
      other       -> [other]
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
    | presume
    , Map.member (getUnique n) binders =
        Just (Decide a (MkDecide asann (withGiveth mty tysig) appform d))
  fillInDefault _ _ = Nothing

  -- The function a root applies to its own values for what a default reads:
  -- the default as a definition whose parameters are those binders, which a
  -- reference to the binder inside it then finds by 'Unique', exactly as any
  -- reader does ('binderParam'). The call-graph rewrite below passes through
  -- whatever it calls, so the default may name a definition that reads a binder.
  defaultFunctionDecl (MkAssume _ tysig (MkAppForm _ n [] _) mty (Just d))
    | Just (ref, bs) <- Map.lookup (getUnique n) filledWithReads =
        Just $ Decide emptyAnno $ MkDecide emptyAnno
          (case withGiveth mty tysig of
             MkTypeSig tann _ mgiveth ->
               MkTypeSig tann (MkGivenSig emptyAnno (map binderParam bs)) mgiveth)
          (MkAppForm emptyAnno ref (map (.resolved) bs) Nothing)
          d
  defaultFunctionDecl _ = Nothing

  -- The ASSUME carried its declared type in its own field; a DECIDE carries it
  -- on the signature's GIVETH. Keeping it there is what lets a reader (and
  -- 'L4.Print.prettyLayout') still see what the default was declared to be.
  withGiveth mty (MkTypeSig tann givens mgiveth) =
    MkTypeSig tann givens (mgiveth <|> fmap (MkGivethSig emptyAnno) mty)

  -- Pass them through at every reference. A definition's own body, a WHERE or
  -- LET local inside it, a lambda, a directive: all of them are Expr children
  -- of the module, so one traversal reaches them all.
  --
  -- A directive is a ROOT: nothing above it supplied anything, so what a
  -- binder's default reads is whatever the directive itself supplies
  -- ('flowedAt'). Everywhere else a binder reaches a call as the caller's own
  -- parameter. That is the one thing the traversal has to know about where it is.
  --
  -- Monadic only to mint the eta-expansion parameters below; the counter is the
  -- whole state.
  rewriteExprs (MkModule ann uri sect) =
    evalState (MkModule ann uri <$> goSection sect) 0
   where
    goSection (MkSection sann mn maka mgiven decls) =
      MkSection sann mn maka <$> traverse (inExprs False) mgiven <*> traverse goTopDecl decls
    goTopDecl = \ case
      Section a s   -> Section a <$> goSection s
      Directive a d -> Directive a <$> inExprs True d
      other         -> inExprs False other
    inExprs root =
      Optics.traverseOf (Optics.gplate @(Expr Resolved))
        (Optics.transformMOf (Optics.gplate @(Expr Resolved)) (rewriteCall root))

  arities = declaredArities mod'

  rewriteCall root = \ case
    -- A bare reference to a definition that takes parameters of its own: it is
    -- being passed as a VALUE, so the trailing binders cannot simply be appended
    -- — that would put them in the first argument positions. Eta-expand instead.
    App ann n []
      | Just bs <- Map.lookup (getUnique n) rs
      , Just k  <- Map.lookup (getUnique n) arities
      , k > 0 -> etaExpand root ann n k bs
    Var ann n
      | Just bs <- Map.lookup (getUnique n) rs
      , Just k  <- Map.lookup (getUnique n) arities
      , k > 0 -> etaExpand root ann n k bs
    App ann n args
      | Just bs <- Map.lookup (getUnique n) rs ->
          pure (App ann n (args <> map (flowedAt root bs []) bs))
    -- 'Var' and 'App _ n []' are the same thing to the evaluator ("still
    -- problematic: similarity / overlap", 'L4.EvaluateLazy.Machine'), so both
    -- have to grow the same arguments or a 'Var' would reach a closure with
    -- none.
    Var ann n
      | Just bs <- Map.lookup (getUnique n) rs ->
          pure (App ann n (map (flowedAt root bs []) bs))
    -- The evaluator desugars a projection to @App _ field [record]@, so a
    -- COMPUTED field whose body reads a binder needs the same treatment as any
    -- other definition: its selector is an ordinary module-level DECIDE.
    Proj ann e f
      | Just bs <- Map.lookup (getUnique f) rs ->
          pure (App ann f (e : map (flowedAt root bs []) bs))
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
          in pure (App ann n (declared <> map (supply root bs supplied) bs))
    other -> pure other

  -- @f@, named but not applied, where @f@ takes @k > 0@ parameters of its own
  -- and reads binders @bs@. A bare name cannot carry the trailing binders, so
  -- the reference becomes the function the writer meant:
  --
  -- > GIVEN _eta0 ... _eta(k-1) YIELD f _eta0 ... _eta(k-1) b1 ... bn
  --
  -- This is the one place the pass mints a 'Unique'. They carry the sort char
  -- @\'d\'@, which no other minter uses (@\'c\'@ is 'L4.TypeCheck', @\'e\'@ the
  -- evaluator, @\'b\'@ the builtins, @\'x\'@ 'L4.Relational.Lower', @\'l\'@
  -- the evaluator's lifecycle names, @\'p\'@ the service's per-request root
  -- fills in @jl4-service@ @Backend.Jl4@, @\'q\'@ a binder's default function,
  -- 'defaultThunkUnique'), so an eta parameter cannot collide
  -- with a name the module already had. A new minter adds itself here.
  --
  -- Measured 2026-09-05: without this, @legal\/british-citizen-act.l4@ on the
  -- @ASSUME@ sweep's tree loses both its @#EVAL@s — it passes the 1-ary reader
  -- @\`is a British citizen (variant)\`@ to a higher-order rule, which is
  -- ordinary L4 and must keep working.
  etaExpand root ann n k bs = do
    ps <- traverse etaParam [0 .. k - 1]
    pure
      (Lam ann
        (MkGivenSig emptyAnno
          [ MkOptionallyTypedName emptyAnno p Nothing Nothing | p <- ps ])
        (App emptyAnno n (map (Var emptyAnno) ps <> map (flowedAt root bs []) bs)))

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

  -- The same, at a root, for a binder whose default reads other binders: the
  -- default's function applied to the root's values for them. Each is what the
  -- site supplies by name, or else what it passes on for the binder, which for
  -- another such binder is again its default's function. A binder meets itself
  -- only in a circle ('defaultCycles'), which the checker has refused; the
  -- guard is for a module that never was checked.
  flowedAt root bs supplied = flowedFrom [] root bs supplied

  flowedFrom seen root bs supplied b
    | root
    , getUnique b.resolved `notElem` seen
    , Just (ref, reads') <- Map.lookup (getUnique b.resolved) filledWithReads =
        App emptyAnno ref
          [ supplyFrom (getUnique b.resolved : seen) root bs supplied c | c <- reads' ]
    | otherwise = flowed b

  supply = supplyFrom []

  supplyFrom seen root bs supplied b =
    case [ e | MkNamedExpr _ r e <- supplied, suppliesBinder bs r b ] of
      e : _ -> e
      []    -> flowedFrom seen root bs supplied b

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

-- | 'implicitSupplySites', each with whether it is written at a ROOT: inside a
-- directive, a lambda or a @WHERE@ written there included. That is what
-- 'dischargeModuleWith' means by a root, a syntactic fact, and the one thing a
-- supply's reach depends on: a @WITH@ at a root reaches a binder that only a
-- default reads, and one written in a definition does not.
implicitSupplySitesAt :: Module Resolved -> [(Bool, Resolved, Resolved)]
implicitSupplySitesAt (MkModule _ _ sect) = goSection sect
 where
  goSection (MkSection _ _ _ mgiven decls) =
    maybe [] (sitesIn False) mgiven <> concatMap goTopDecl decls
  goTopDecl = \ case
    Section _ s   -> goSection s
    Directive _ d -> sitesIn True d
    other         -> sitesIn False other
  sitesIn :: Optics.GPlate (Expr Resolved) a => Bool -> a -> [(Bool, Resolved, Resolved)]
  sitesIn root x =
    [ (root, n, r)
    | e <- concatMap (Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Resolved))))
             (Optics.toListOf (Optics.gplate @(Expr Resolved)) x)
    , AppNamed _ n nes (Just order) <- [e]
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
      | (root, n, r) <- implicitSupplySitesAt mod'
      , not (Map.member (getUnique n) binders)
      , let reach = readSetAt root n
      , not (any (suppliesBinder reach r) reach)
      , not (ambiguousFor reach r)
      ]
 where
  binders = sectionBinders mod'
  stages  = readSetStages mod' binders
  -- A supply at a root reaches what the callee needs from its root, defaults
  -- included. One written in a definition reaches only what the callee reads
  -- itself: a binder that only a default reads is worked out at the root, from the
  -- root's values, so a supply for it written below the root would have nowhere to
  -- go (W7 second review, silent S4). The base refused that WITH for the same
  -- reason, since no default could read an input then.
  readSetAt root n =
    fromMaybe [] (Map.lookup (getUnique n) ((if root then stages.closed else stages.own) `Map.withoutKeys` Map.keysSet binders))

-- | Call sites that give a @WITH@ to a section INPUT as though it were a rule:
-- @discount WITH \`list price\` IS 200@, where @discount@ is a binder. An input
-- has no read-set of its own for a @WITH@ to reach ('readSets' leaves binders
-- out), so 'unreadImplicitSupplies' would say it does not read the value, which
-- is false when its default does. The writer's mistake is a different one: the
-- value belongs on a rule that reads the input. One entry per site: the input
-- called, and the binder supplied.
implicitSuppliesToInputs :: Module Resolved -> [(Resolved, Resolved)]
implicitSuppliesToInputs mod'
  | Map.null binders = []
  | otherwise =
      [ (n, r)
      | (n, r) <- implicitSupplySites mod'
      , Map.member (getUnique n) binders
      ]
 where
  binders = sectionBinders mod'

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

-- | Call sites whose supplied value was type-checked against ONE section binder
-- and is then delivered to ANOTHER, declared at a different type.
--
-- smucclaw\/l4-ide#960, the residue of #956. 'L4.TypeCheck.sectionBinderFor'
-- validates the value against the binder's DECLARED type, but only where the
-- module has exactly one binder of that spelling; with two it returns 'Nothing'
-- — deliberately, see its Haddock — and 'L4.TypeCheck.implicitSupply' falls back
-- to @resolveTerm@, which answers in the CALLER's scope. Delivery meanwhile is
-- decided here, by 'suppliesBinder' against the CALLEE's read-set. With two
-- same-spelled binders at different types those two questions disagree, and
-- then nothing has checked the value against the type it actually arrives at:
-- #960's repro passes @l4 check@ and a @GIVETH A NUMBER@ rule returns a
-- @STRING@.
--
-- __Why this can live here when the type check cannot.__ The read-set is the
-- very fact 'L4.TypeCheck.sectionBinderFor' lacks while a body is being
-- checked, and it exists by the time these whole-module checks run. Both halves
-- of the comparison are already recorded and need no re-deriving: the binder
-- the body check chose is the 'Resolved' carried in the 'NamedExpr'
-- ('implicitSupplySites'), and the binder that receives is whichever
-- 'suppliesBinder' selects. So this needs no re-checking of the expression, and
-- none of R-X3's closure work.
--
-- __Only when the declared types actually differ__, by 'typeKey', as R3 already
-- compares them in 'ambiguousRootBinders'. Two same-typed binders of one
-- spelling are R3's business and are refused there; a disagreement that cannot
-- change the value's type is not a defect and must not draw a diagnostic. This
-- is also what keeps the check off the TDNR overload of @ok\/section-given-tdnr.l4@
-- and @ok\/misc.l4@ — widening to the spelling alone is the reverted fix
-- (legalese\/l4-ide#369) that this must not become.
--
-- Returns @(callee, binderCheckedAgainst, binderThatReceives)@.
misdeliveredImplicitSupplies :: Module Resolved -> [(Resolved, Resolved, Resolved)]
misdeliveredImplicitSupplies mod'
  | Map.null binders = []
  | otherwise =
      [ (n, r, b.resolved)
      | (n, r) <- implicitSupplySites mod'
      , b <- take 1 (filter (suppliesBinder (readSetOf n) r) (readSetOf n))
      , getUnique r /= getUnique b.resolved
      , Just checked <- [Map.lookup (getUnique r) binders]
      , fmap typeKey checked.typ /= fmap typeKey b.typ
      ]
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders
  readSetOf n = fromMaybe [] (Map.lookup (getUnique n) rs)

-- | R3's per-root check: the two shapes in which one name ends up standing for
-- two section binders at the point where binders are actually filled in.
--
-- R3 enforces one binder per name PER ROOT, not per module — two sibling
-- sections may each declare @foo@, and each is read by its own subtree. A ROOT
-- is where the values arrive: an @\@export@, whose read-set is published as a
-- request schema, and a @WITH@, where a writer names one. The two go wrong
-- differently, so they are tested differently:
--
-- * __An @\@export@__ whose read-set holds two same-spelled, same-typed binders
--   cannot publish a schema at all — the row would need one key twice.
--   Unconditional: nothing has to be supplied for this to be broken.
--
-- * __A @WITH@ supply__ whose callee reads two same-spelled, same-typed binders
--   reaches exactly one of them, and the other falls back to its own default.
--   This is §11.4's measured witness: @ok\/section-given-bridge.l4@ plus
--   @`both` MEANS foo PLUS g@ and @#EVAL `both` WITH foo IS 1@ answers __991__
--   (1 + 99×10 — the supply reached one @foo@, the other took its default),
--   and @l4 check@ used to accept it.
--
-- __Why a supply and not merely a directive.__ An earlier build tested every
-- directive's read-set, on the reading that a directive is a root. Two
-- independent adversarial passes broke that on 2026-09-08: with no @WITH@ there
-- is no supply channel at all, every binder takes its own @TYPICALLY@ default
-- and the answer is total and deterministic, so there is nothing to be
-- ambiguous between — and the rule refused the very sibling-section drafting R3
-- exists to permit, turning @ok\/section-given-fruit.l4@,
-- @doc\/reference\/syntax\/sections-example.l4@ and the section-@GIVEN@ tutorial
-- red with one added @#ASSERT@ apiece, with no way out, since a directive
-- cannot be rewritten to reach fewer binders. It also refused
-- @#EVAL g WITH foo IS foo@ — the bridge its own message tells the writer to
-- write.
--
-- __Why this does not overlap 'ambiguousImplicitSupplies'.__ That check fires
-- when the supplied name's 'Unique' matches NO binder the callee reads; this
-- one requires that it matches ONE and that a second is spelled alike. The two
-- conditions are disjoint, so a site is reported at most once.
--
-- Returns @(callee-or-export, binders)@ with the binders in declaration order,
-- one entry per same-spelled group. The first component is what the diagnostic
-- points at and names.
ambiguousRootBinders :: Module Resolved -> [(Resolved, [Resolved])]
ambiguousRootBinders mod'
  | Map.null binders = []
  | otherwise        = exportGroups <> supplyGroups
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders

  readSetOf n = Map.findWithDefault [] (getUnique n) rs

  exportGroups =
    [ (n, map (.resolved) alike)
    | MkDecide _ _ (MkAppForm _ n _ _) _ <- collectExportedDecides mod'
    , alike <- sameSpelledGroups (readSetOf n)
    ]

  supplyGroups =
    [ (n, map (.resolved) alike)
    | (n, r) <- implicitSupplySites mod'
    , let reached = readSetOf n
    , getUnique r `elem` map (getUnique . (.resolved)) reached
    , alike <- sameSpelledGroups reached
    , spellingOf r `elem` map (spellingOf . (.resolved)) alike
    ]

-- | The read-set entries that share an unqualified spelling AND a type, in
-- declaration order, for each such pair that two or more of them share.
--
-- __The type is half the key, and leaving it out was a real defect.__ L4 lets
-- one heading bind a name several times at several types and resolves each use
-- by its context — the idiom @ok\/section-given-tdnr.l4@ and @ok\/misc.l4@ exist
-- to pin, and which @doc\/reference\/syntax\/section-given.md@ documents under
-- "One name, several types". Grouping on spelling alone called that an
-- ambiguity: two adversarial passes on 2026-09-08 each turned both fixtures red
-- by adding a single directive, and the diagnostic offered the reader two
-- candidates printed under identical section-qualified spellings, with three
-- remedies none of which applies. Two binders of one name at DIFFERENT types
-- are not two answers to one question; they are two questions.
--
-- 'typeKey' is the annotation-insensitive skeleton the resolver already uses to
-- decide which candidates count as "the same type", so this check and
-- overload resolution cannot drift apart on what sameness means. An untyped
-- binder groups with other untyped ones.
sameSpelledGroups :: [Binder] -> [[Binder]]
sameSpelledGroups bs =
  [ alike
  | alike@(_ : _ : _) <-
      Map.elems (Map.fromListWith (flip (<>))
        [ ((spellingOf b.resolved, fmap typeKey b.typ), [b]) | b <- bs ])
  ]

-- | The definitions an IMPORTER must treat as carrying implicit inputs: the
-- ones it can neither supply nor see in a schema, because discharge stops at
-- the module boundary.
--
-- Three sources, and the second and third were each a measured hole before they
-- were added (adversarial pass, 2026-09-08):
--
-- * every definition with a non-empty read-set;
-- * every section binder itself — the elaboration is a 0-ary @ASSUME@, never a
--   'readSets' key, so an @\@export@ in the importer that names the imported
--   BINDER directly went unrefused and, with a @TYPICALLY@ on it, answered a
--   wrong number with @"status":"success"@;
-- * every definition that reaches an ALREADY-imported reader. Without this a
--   module in the middle of a chain — @A@ imports @B@ imports @C@, only @C@
--   declares a binder — contributes nothing, because its own 'sectionBinders'
--   is empty and its 'readSets' is therefore @Map.empty@; @A@'s export then
--   validated a row it could not evaluate, one hop further out than the defect
--   this refusal was built for.
--
-- The third is the only part that costs anything, so it is skipped entirely
-- when @imported@ is empty — which is every module whose imports are the
-- stdlib.
implicitReaders :: Set Unique -> Module Resolved -> Set Unique
implicitReaders imported mod' =
  imported
    <> Map.keysSet binders
    <> Map.keysSet rs
    <> reachers
 where
  binders = sectionBinders mod'
  rs      = readSets mod' binders
  bodies  = decideBodiesFromModule mod'

  reachers
    | Set.null imported = Set.empty
    | otherwise =
        Set.fromList
          [ u
          | (u, body) <- Map.toList bodies
          , not (Set.disjoint (transitiveReferencedUniquesWith bodies body) imported)
          ]

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
