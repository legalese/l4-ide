{-# LANGUAGE PatternSynonyms #-}
-- | The explicit labelled transition system of a contract, by iterating the
-- what-if: @l4 explore@ (REGULATIVE-LOWERING-SPEC.md §4, work package WP1).
--
-- "L4.Lts.WhatIf" answers one question about one position: what each
-- candidate event would do, by replaying it on the evaluator. This module
-- asks that question again of every position the answers lead to, breadth
-- first, until no new position turns up or a bound stops it. Every edge is
-- a replay; nothing about the deontic machine is re-derived here (§2.4 of
-- LTS-VISUALISER, which the spec's §2 adopts as the reference semantics).
--
-- == What a state is (§4.1)
--
-- Two positions are one state when their canonical forms are equal. The
-- canonical form ('StateKey') is:
--
-- * the residual, printed after every LOCAL it closed over has been read
--   back through the heap ('reifyExpr', but sparing the module's top-level
--   names, which mean the same thing in every position and print by name
--   whether or not a run happened to force them). Printing erases source
--   ranges and spells every name as the rule wrote it, which is the
--   renaming-in-order-of-occurrence of §4.1 for residuals that come from one
--   source. A local the residual still holds UNFORCED prints by its name
--   only, so two positions that differ in its value would merge: that is the
--   one silent faithfulness risk of §4.1, and every state in which it
--   happened is named in the coverage ('cvMergedByName') rather than left
--   silent;
-- * a projection of the ledgers: a cell some @RECALL ALL@ reads keeps its
--   whole history in recorded order; a cell read only by @RECALL@ keeps its
--   latest entry, which is all a last-write-wins read can see; a cell
--   nothing reads is dropped, and named in the coverage as write-only. When
--   the modules use @EVAL AS OF SYSTEM TIME@ or @EVAL UNDER VALID TIME@, a
--   read can see past the latest entry, so every read cell keeps its whole
--   history with its valid-from stamps. The second rule is narrower than
--   §4.1's text ("in recorded order" for every read cell) and was measured
--   on the dinner fixtures before it was adopted (their README, "What the
--   explorer must know", point 1);
-- * the answer each top-level rule with no inputs that reads a ledger was
--   forced to in this run, if it was: the evaluator keeps a rule's first
--   answer, so such a rule's answer is part of where the run stands even
--   though the ledger has moved on (the fixtures' README, "Traps"). It is
--   read through the environment of an obligation in force, because the
--   evaluator gives each directive a fresh top-level heap and returns only
--   the first pass's, which no directive forces
--   (@forEachDirectiveFreshHeap@, measured 2026-10-26: read from the
--   returned heap, the answer was never there). A position with no
--   obligation in force has no future for a stale answer to change, so
--   there the answer is left out;
-- * the clock, DROPPED under the region scheme of §4.5: what is kept is,
--   for each live deadline whose instant is known, whether the clock has
--   already passed it. Positions that agree on all of that and differ only
--   in the clock are time-abstract bisimilar while no guard reads the
--   clock, which is the region scheme's own condition. Under @--grid@ the
--   clock is kept whole.
--
-- == What an edge is (§4.2, §4.5, §4.6)
--
-- An edge is a candidate the replay TOOK: it led to @FULFILLED@, to a
-- breach, or to another position. An act the contract passed over is no
-- edge; an act that leaves the state as it was is a self-loop, labelled with
-- the act. A state that ends up with no edge at all, with nothing at it
-- untried, refused or cut by a bound, gets one self-loop labelled
-- @terminal@, so that no checker reads it as a deadlock (§4.6).
--
-- A candidate whose action pattern binds a variable names a SET of acts.
-- The what-if replays one act from it; exploration cannot, so the set is
-- ENUMERATED when the variable's type is finite ('enumerateType'), and every
-- constructor whose fields are not refused LOUDLY, by name ('Refusal'), with
-- the finite constructors beside it still explored. No sample is ever
-- tried in a refused constructor's place (§4.2, ruled R-L4).
--
-- An act fires at a choice of instants (§4.5): the instant of the last
-- event, one instant strictly between it and the earliest live deadline,
-- and that deadline exactly. An act is never fired past a live deadline:
-- the machine would expire the deadline first and the edge would carry the
-- act's name for the deadline's effect, so a later instant is reached by the
-- tick past the deadline and then the act, which is the same position with
-- honest labels.
module L4.Lts.Explore
  ( -- * Where an exploration starts
    Start (..)
  , startsOf
  , startNamed
    -- * Options
  , ExploreOptions (..)
  , TimeScheme (..)
  , defaultExploreOptions
    -- * What the modules read
  , ReadSites (..)
  , readSitesOf
  , keepCells
    -- * The graph
  , Graph (..)
  , StateNode (..)
  , Transition (..)
  , EdgeKind (..)
  , LedgerCell (..)
  , Keep (..)
  , Coverage (..)
  , Stop (..)
  , Refusal (..)
  , UntriedNote (..)
  , explore
  , coverageComplete
  , replayPath
  , withoutDirectives
  , decidesOf
    -- * Rendering
  , renderGraph
  , coverageLine
  , refusalText
  , graphJson
  , graphDot
    -- * Finite types
  , Domain (..)
  , Refused (..)
  , enumerateType
  , contractActionType
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import Base.Text (textShow)
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import qualified Data.Sequence as Seq
import Data.Sequence (Seq (..))
import qualified Optics

import L4.Annotation (emptyAnno, getAnno)
import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..), Provenance (..))
import L4.Evaluate.ValueLazy hiding (Blame)
import L4.EvaluateLazy
  ( EntityInfo
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithDeonticLog
  , prettyReductionOutcome
  )
import L4.Lts.Marking (LiveNorm (..), RawObligation (..), liveObligations, renderLive)
import L4.Lts.WhatIf
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.Utils.Ratio (prettyRatio)

----------------------------------------------------------------------------
-- Where an exploration starts
----------------------------------------------------------------------------

-- | A contract at its outset: what a @#TRACE contract AT at WITH@ with no
-- events would replay.
data Start = MkStart
  { stName     :: !Text
    -- ^ the contract as written, for the reader
  , stContract :: !(Expr Resolved)
  , stAt       :: !(Expr Resolved)
  }

-- | One start per distinct contract and @AT@ among the module's @#TRACE@s,
-- in source order. The traces' events are not replayed: from the outset
-- they are one path among those the exploration walks.
startsOf :: Module Resolved -> [Start]
startsOf m = nubOrdOn (\ s -> (s.stName, prettyLayout s.stAt))
  [ MkStart {stName = prettyLayout tr.trContract, stContract = tr.trContract, stAt = tr.trStart}
  | tr <- tracesOf m ]

-- | A top-level rule with no inputs, at this @AT@. Unlike
-- 'L4.Lts.List.freshTrace' this finds a rule under a @§@ heading too, since
-- a contract that is explored is usually written in sections.
startNamed :: Module Resolved -> Text -> Rational -> Either Text Start
startNamed (MkModule _ _ section) wanted at =
  case [ (u, n) | MkDecide _ _ (MkAppForm _ (Def u n) [] _) _ <- decidesOf section, nameToText n == wanted ] of
    [] -> Left ("no rule named `" <> wanted <> "` that takes no inputs")
    ((u, n) : _) -> Right MkStart
      { stName = wanted
      , stContract = Var emptyAnno (Ref n u n)
      , stAt = Lit emptyAnno (NumericLit emptyAnno at)
      }

-- | Every @DECIDE@ in a section and the sections under it.
decidesOf :: Section Resolved -> [Decide Resolved]
decidesOf (MkSection _ _ _ _ decls) = concatMap go decls
  where
    go = \ case
      Decide _ d  -> [d]
      Section _ s -> decidesOf s
      _           -> []

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data ExploreOptions = MkExploreOptions
  { eoMaxDepth  :: !Int
    -- ^ events on a path; a state this deep is counted and not expanded
  , eoMaxStates :: !Int
    -- ^ states; a new state past this many is not added
  , eoUntil     :: !(Maybe Rational)
    -- ^ the clock bound: no event later than this instant. A tick past it
    -- is not taken, and is counted in the coverage
  , eoTime      :: !TimeScheme
  , eoMaxActs   :: !Int
    -- ^ the most acts one variable's type may enumerate to before the
    -- variable is refused as too large
  }

-- | How the instant an act fires at is chosen (§4.5).
data TimeScheme
  = Regions
    -- ^ the instant of the last event, one instant strictly before the
    -- earliest live deadline, and that deadline; the clock is not in the
    -- state
  | Grid !Rational
    -- ^ the instant of the last event and the next multiple of this step
    -- after it, never past the earliest live deadline; the clock is in the
    -- state. For a guard that reads the clock arithmetically, on the
    -- condition that every event time and deadline is a multiple of the step
  deriving stock (Eq, Show)

defaultExploreOptions :: ExploreOptions
defaultExploreOptions = MkExploreOptions
  { eoMaxDepth = 100
  , eoMaxStates = 10000
  , eoUntil = Nothing
  , eoTime = Regions
  , eoMaxActs = 4096
  }

----------------------------------------------------------------------------
-- What the modules read
----------------------------------------------------------------------------

-- | What the state has to keep of the ledgers, decided statically from the
-- @RECALL@ sites of the modules (§4.1): so it is not a ruling.
data ReadSites = MkReadSites
  { rsCells      :: !(Map Text Bool)
    -- ^ every cell some @RECALL@ reads, and whether some @RECALL ALL@ does
  , rsTimeScoped :: !Bool
    -- ^ the modules use @EVAL AS OF SYSTEM TIME@ or @EVAL UNDER VALID
    -- TIME@, through which a read can see past a cell's latest entry
  , rsLedgerCafs :: !(Map Unique Text)
    -- ^ the main module's top-level rules with no inputs whose answer
    -- depends on a ledger read, directly or through another rule
  }

-- | The read sites of the module explored and of the modules it imports.
-- Only the explored module's own rules can be ledger-reading constants of
-- a run: an imported module's heap is built once, before any replay.
readSitesOf :: Module Resolved -> [Module Resolved] -> ReadSites
readSitesOf main imported = MkReadSites
  { rsCells = Map.fromListWith (||)
      [ (s, mode == RecallAll) | ReadCell _ _ _ mode (Lit _ (StringLit _ s)) <- everyExpr ]
  , rsTimeScoped = any timeScoped everyExpr
  , rsLedgerCafs = Map.fromList
      [ (u, nameToText n)
      | (Def u n, [], _) <- topDecides
      , Set.member u readers ]
  }
  where
    everyExpr = concatMap exprsOf (main : imported)
    timeScoped = \ case
      Var _ r   -> scoped r
      App _ r _ -> scoped r
      _         -> False
    scoped r = getUnique r `elem` [TypeCheck.evalAsOfSystemTimeUnique, TypeCheck.evalUnderValidTimeUnique]
    MkModule _ _ mainSection = main
    topDecides =
      [ (name, args, body) | MkDecide _ _ (MkAppForm _ name args _) body <- decidesOf mainSection ]
    -- the least set of the module's rules that read a ledger, directly or
    -- by naming one that does
    readers = fixpoint (Set.fromList [ getUnique name | (name, _, body) <- topDecides, readsDirectly body ])
    readsDirectly body = not (null [ () | ReadCell {} <- subExprsOf body ])
    refsOf body = Set.fromList (concat [ heads e | e <- subExprsOf body ])
    heads = \ case
      Var _ r   -> [getUnique r]
      App _ r _ -> [getUnique r]
      _         -> []
    fixpoint s =
      let s' = s <> Set.fromList [ getUnique name | (name, _, body) <- topDecides, not (Set.disjoint (refsOf body) s) ]
      in if s' == s then s else fixpoint s'

-- | Keep these cells although no @RECALL@ in the modules reads them: the
-- cells a property reads (§4.1: "every ledger that some rule or property
-- @RECALL@s"). A property here is a boolean decision whose inputs the
-- caller fills from the ledger, so it has no @RECALL@ of its own for
-- 'readSitesOf' to find, and whoever evaluates the properties says which
-- cells they read and how: 'True' for the whole history (an input filled by
-- @RECALL ALL@), 'False' for the latest entry (one filled by @RECALL@). A
-- cell some @RECALL ALL@ in the modules reads stays whole either way.
-- Keeping a cell never merges two positions, it can only split them, so a
-- cell kept that no property needed costs states, not soundness.
keepCells :: [(Text, Bool)] -> ReadSites -> ReadSites
keepCells cells sites = sites {rsCells = Map.unionWith (||) (Map.fromListWith (||) cells) sites.rsCells}

exprsOf :: Module Resolved -> [Expr Resolved]
exprsOf = Optics.toListOf (Optics.gplate @(Expr Resolved) Optics.% Optics.cosmosOf (Optics.gplate @(Expr Resolved)))

subExprsOf :: Expr Resolved -> [Expr Resolved]
subExprsOf = Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Resolved)))

----------------------------------------------------------------------------
-- The graph
----------------------------------------------------------------------------

data Graph = MkGraph
  { gStart       :: !Start
  , gStates      :: ![StateNode]
  , gTransitions :: ![Transition]
  , gEdgeEvents  :: !(Map (Int, Text, Int) (Expr Resolved))
    -- ^ the event each act or tick edge was first taken by, with its
    -- instant, keyed as the edge is: a step's counterexample is the path to
    -- its source and then this event ("L4.Lts.Explore.Check")
  , gCoverage    :: !Coverage
  }

data StateNode = MkStateNode
  { snId       :: !Int
  , snDepth    :: !Int
  , snEvents   :: ![Text]
    -- ^ the path that first reached it, as the events of a @#TRACE@
  , snPath     :: ![Expr Resolved]
    -- ^ the same path, as the events the replay appended
  , snStore    :: !LedgerStore
    -- ^ the ledgers of the position that first reached it, whole: what a
    -- property is evaluated on ("L4.Lts.Explore.Check"). Only the cells the
    -- state keeps ('snLedger') are the same in every position merged into
    -- it, so a property may read only those
  , snResidual :: !Text
    -- ^ the canonical residual ('StateKey')
  , snLedger   :: ![LedgerCell]
    -- ^ the ledger as the state keeps it
  , snClock    :: !Rational
    -- ^ the clock of the position that first reached it; under the region
    -- scheme not part of the state
  , snTerminal :: !Bool
  }

data Transition = MkTransition
  { tnFrom  :: !Int
  , tnLabel :: !Text
  , tnTo    :: !Int
  , tnKind  :: !EdgeKind
  }
  deriving stock (Eq, Ord, Show)

data EdgeKind = EdgeAct | EdgeTick | EdgeTerminal
  deriving stock (Eq, Ord, Show)

-- | One cell of one ledger, as the state keeps it.
data LedgerCell = MkLedgerCell
  { lcLedger :: !Text
    -- ^ @OFFICIAL@, or the party whose own ledger it is
  , lcCell   :: !Text
  , lcKeep   :: !Keep
  , lcValues :: ![Text]
  }
  deriving stock (Eq, Ord, Show)

data Keep = KeptAll | KeptLatest
  deriving stock (Eq, Ord, Show)

-- | §4.4's coverage line, as data.
data Coverage = MkCoverage
  { cvStates       :: !Int
  , cvTransitions  :: !Int
  , cvStops        :: ![Stop]
    -- ^ empty: the frontier was exhausted
  , cvRefused      :: ![Refusal]
  , cvUntried      :: ![UntriedNote]
  , cvPassedOver   :: !Int
    -- ^ (state, act) pairs the contract passed over at every instant tried
  , cvDropped      :: ![(Text, Text)]
    -- ^ write-only cells, dropped from the state: (ledger, cell)
  , cvTime         :: !Text
  , cvBeyondClock  :: !Int
    -- ^ ticks not taken because they fall past the clock bound
  , cvMergedByName :: ![Text]
    -- ^ unforced locals a residual held, compared by name
  , cvUnspellable  :: !Int
    -- ^ ledger values with no literal form, compared by their printed form
  , cvAnswersByForm :: ![Text]
    -- ^ ledger-reading rules with no inputs whose answer has no literal
    -- form, compared by its printed form
  }

data Stop
  = StopDepth !Int !Int
    -- ^ the depth bound, and how many states at it were not expanded
  | StopStates !Int !Int
    -- ^ the state bound, and how many new states were not added
  deriving stock (Eq, Show)

-- | A variable whose set of acts was not explored, or not all of it.
data Refusal = MkRefusal
  { rfVariable    :: !Text
  , rfType        :: !Text
  , rfWhole       :: !Bool
    -- ^ the variable is the whole action, not an operand of it
  , rfObligation  :: !Text
  , rfConstructor :: !(Maybe Text)
    -- ^ the constructor refused, when the refusal is of one constructor
  , rfReason      :: !Text
  , rfStates      :: !Int
    -- ^ in how many states
  }
  deriving stock (Eq, Show)

data UntriedNote = MkUntriedNote
  { unWhat   :: !Text
  , unWhy    :: !Text
  , unStates :: !Int
  }
  deriving stock (Eq, Show)

-- | Nothing refused, nothing untried, the frontier exhausted. What a CI job
-- may read as a complete exploration; anything else exits non-zero.
coverageComplete :: Coverage -> Bool
coverageComplete cv = null cv.cvRefused && null cv.cvUntried && null cv.cvStops

----------------------------------------------------------------------------
-- Finite types
----------------------------------------------------------------------------

-- | The acts a finite type names, and the constructors it could not list.
data Domain = MkDomain
  { dmValues  :: ![Expr Resolved]
  , dmRefused :: ![Refused]
  }

instance Semigroup Domain where
  MkDomain a b <> MkDomain c d = MkDomain (a <> c) (b <> d)

instance Monoid Domain where
  mempty = MkDomain [] []

-- | A constructor whose acts were not listed, and why: the field that
-- offends, its type, and, when the constructor sits inside a field of
-- another one, where.
data Refused = MkRefused
  { rdConstructor :: !Text
    -- ^ the constructor refused: the innermost one with the offending field
  , rdField       :: !Text
  , rdFieldType   :: !Text
  , rdWhy         :: !Text
  , rdWithin      :: ![(Text, Text)]
    -- ^ the constructors and fields it sits in, outermost first: a
    -- refused @custom@ inside the @size@ of an @Order@ is @[(Order, size)]@,
    -- and the @Order@s whose size is not @custom@ are still listed
  }
  deriving stock (Eq, Show)

-- | Every value of a type, when the type is finite by §4.2's rule:
-- @BOOLEAN@, or a declared type each of whose constructors has only fields
-- that are finite by the same rule. A constructor with a @NUMBER@,
-- @STRING@ or @LIST@ field (or one of a type this cannot read) is refused,
-- by name, and its siblings are still listed. 'Left' when the type itself
-- has no finite set of values to list at all.
--
-- The values are built as the what-if builds a witness: a constructor
-- applied to its fields' values, in the order the type checker allocated
-- the constructors, which within a @DECLARE@ is the order they are written.
-- A type with parameters (@MAYBE OF Status@) is not enumerated; it is
-- refused, which over-refuses a finite set and never under-refuses one.
enumerateType :: EntityInfo -> Type' Resolved -> Either Text Domain
enumerateType info = go Set.empty
  where
    go seen = \ case
      TyApp _ r []
        | u == getUnique TypeCheck.booleanRef ->
            Right (MkDomain [App emptyAnno TypeCheck.trueRef [], App emptyAnno TypeCheck.falseRef []] [])
        | u == TypeCheck.numberUnique -> Left "a NUMBER has no finite set of values"
        | u == TypeCheck.stringUnique -> Left "a STRING has no finite set of values"
        | Set.member u seen -> Left (quoted r <> " is recursive, so its values are not a finite set")
        | otherwise -> case constructorsOf info u of
            [] -> Left (quoted r <> " declares no constructors this explorer can list")
            cs -> Right (foldMap (constructorDomain (Set.insert u seen)) cs)
        where u = getUnique r
      TyApp _ r (_ : _)
        | getUnique r == TypeCheck.listUnique -> Left "a LIST has no finite set of values"
        | otherwise -> Left (quoted r <> " takes type arguments, which this explorer does not enumerate")
      _ -> Left "it is not a type whose values can be listed"

    constructorDomain seen (con, fields) = case fields of
      [] -> MkDomain [App emptyAnno con []] []
      _  ->
        let perField = [ (fname, fty, go seen fty) | (fname, fty) <- fields ]
        in case [ (fname, fty, why) | (fname, fty, Left why) <- perField ] of
          ((fname, fty, why) : _) ->
            MkDomain [] [MkRefused {rdConstructor = nameText con, rdField = fname, rdFieldType = prettyLayout fty, rdWhy = why, rdWithin = []}]
          [] ->
            let doms = [ (fname, d) | (fname, _, Right d) <- perField ]
                nested =
                  [ r {rdWithin = (nameText con, fname) : r.rdWithin}
                  | (fname, d) <- doms, r <- d.dmRefused ]
            in MkDomain [ App emptyAnno con args | args <- traverse ((.dmValues) . snd) doms ] nested

    quoted r = "`" <> nameText r <> "`"

-- | The constructors of a declared type, with their fields, from the type
-- checker's own record of them.
constructorsOf :: EntityInfo -> Unique -> [(Resolved, [(Text, Type' Resolved)])]
constructorsOf info ty =
  [ (Def u n, fieldsOf cty)
  | (u, (n, TypeCheck.KnownTerm cty Constructor)) <- Map.toList info
  , resultHead cty == Just ty
  ]
  where
    resultHead = \ case
      Fun _ _ res  -> resultHead res
      TyApp _ r [] -> Just (getUnique r)
      _            -> Nothing
    fieldsOf = \ case
      Fun _ args _ ->
        [ (maybe ("field " <> Text.pack (show i)) nameText mn, t)
        | (i, MkOptionallyNamedType _ mn t) <- zip [1 :: Int ..] args ]
      _ -> []

-- | The type of the actions of the contract a start names: the second
-- argument of its @DEONTIC@. Every obligation in a contract has that action
-- type, which is how a variable that is the WHOLE action, and so has no
-- type recorded of its own (WhatIf's 'binderTypes'), gets one.
contractActionType :: EntityInfo -> Expr Resolved -> Either Text (Type' Resolved)
contractActionType info e = case headName e of
  Just r | Just (_, TypeCheck.KnownTerm ty _) <- Map.lookup (getUnique r) info -> deonticAction (resultOf ty)
  _ -> case view annInfo (getAnno e) of
    Just (TypeInfo ty _) -> deonticAction ty
    _ -> Left "the contract's type is not recorded, so its action type cannot be read"
  where
    headName = \ case
      Var _ r   -> Just r
      App _ r _ -> Just r
      _         -> Nothing
    resultOf = \ case
      Forall _ _ t -> resultOf t
      Fun _ _ t    -> t
      t            -> t
    deonticAction = \ case
      TyApp _ c [_, a] | getUnique c == TypeCheck.contractUnique -> Right a
      t -> Left ("the contract's type is " <> prettyLayout t <> ", not a DEONTIC")

nameText :: Resolved -> Text
nameText = unqualifiedNameToText . getOriginal

----------------------------------------------------------------------------
-- The state
----------------------------------------------------------------------------

data StateKey = MkStateKey
  { skResidual :: !Text
  , skLedger   :: ![LedgerCell]
  , skCafs     :: ![(Text, Text)]
  , skClock    :: !ClockKey
  }
  deriving stock (Eq, Ord, Show)

data ClockKey
  = ClockDropped ![Bool]
    -- ^ for each live deadline whose instant is known: has the clock passed it
  | ClockKept !Rational
  deriving stock (Eq, Ord, Show)

-- | What the state key leaves out, for the coverage.
data KeyNotes = MkKeyNotes
  { knMergedByName  :: ![Text]
  , knDropped       :: ![(Text, Text)]
  , knUnspellable   :: !Int
  , knAnswersByForm :: ![Text]
    -- ^ ledger-reading rules with no inputs whose answer has no literal
    -- form (a function, say), compared by its printed form
  }

-- | Everything one exploration shares.
data Explorer = MkExplorer
  { exOptions    :: !ExploreOptions
  , exSites      :: !ReadSites
  , exRig        :: !Rig
    -- ^ the module with every directive taken out; each position puts its
    -- own @#TRACE@ back ('rigFor')
  , exStart      :: !Start
  , exActionType :: !(Either Text (Type' Resolved))
  , exAnchors    :: !(IORef (Map Text (Maybe Rational)))
    -- ^ closed anchors already evaluated ('resolveAnchor')
  }

-- | The rig and trace that replay this path.
rigFor :: Explorer -> [Expr Resolved] -> (Rig, Trace)
rigFor ex events =
  let directive = Contract emptyAnno ex.exStart.stContract ex.exStart.stAt events
      MkModule a uri (MkSection sa sn saka sg decls) = ex.exRig.rigModule
      m' = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno directive]))
  in ( ex.exRig {rigModule = m'}
     , MkTrace {trDirective = directive, trContract = ex.exStart.stContract, trStart = ex.exStart.stAt, trEvents = events} )

-- | A module with no directives: the explorer adds the one it replays.
withoutDirectives :: Module Resolved -> Module Resolved
withoutDirectives (MkModule a uri section) = MkModule a uri (go section)
  where
    go (MkSection sa sn saka sg decls) = MkSection sa sn saka sg (mapMaybe keep decls)
    keep = \ case
      Directive _ _ -> Nothing
      Section sa s  -> Just (Section sa (go s))
      other         -> Just other

stateKey :: Explorer -> Position -> IO (StateKey, KeyNotes)
stateKey ex pos = do
  (residual, merged) <- case pos.posResidual of
    Just v  -> canonResidual pos.posReplayScope v
    Nothing -> pure (standingText pos.posResult, [])
  (cells, dropped, unspellable) <- projectLedger ex.exSites pos.posResult.ledger
  -- the heap this directive forced, as the obligations in force closed over it
  let heaps = [ raw.roEnv | raw <- maybe [] liveObligations pos.posResidual ]
  cafs <- for (Map.toList ex.exSites.rsLedgerCafs) \ (u, name) -> (name,) <$> case listToMaybe (mapMaybe (Map.lookup u) heaps) of
    Nothing -> pure ("no obligation in force reads it", True)
    Just rf -> readIORef rf.pointer >>= \ case
      Unevaluated{} -> pure ("not yet asked", True)
      WHNF v -> answerText v
      WHNFWhen _ v _ _ -> answerText v
  deadlines <- liveDeadlines ex pos
  let clock = case ex.exOptions.eoTime of
        Regions -> ClockDropped [ pos.posClock > d | (_, Just (Right d)) <- deadlines ]
        Grid _  -> ClockKept pos.posClock
  pure ( MkStateKey {skResidual = residual, skLedger = cells, skCafs = map (second fst) cafs, skClock = clock}
       , MkKeyNotes
           { knMergedByName = merged
           , knDropped = dropped
           , knUnspellable = unspellable
           , knAnswersByForm = [ name | (name, (_, False)) <- cafs ] } )
  where
    -- A rule whose answer is a contract is keyed by the contract's printed
    -- source form: its own RECALLs run under events, not when it is forced,
    -- and a rule that chose one contract or another by a RECALL prints
    -- whichever it chose. Any other answer is read back as a value.
    answerText v = case v of
      ValObligation{} -> pure (prettyLayout v, True)
      ValROp{}        -> pure (prettyLayout v, True)
      ValQuantified{} -> pure (prettyLayout v, True)
      _               -> valueText v

-- | What a result that is not a residual says, for a state key.
standingText :: EvalDirectiveResult -> Text
standingText res = case res.result of
  Reduction o -> prettyReductionOutcome o
  Assertion _ -> "not a #TRACE"

-- | The residual, printed with its locals read back (see the module
-- header), and the unforced locals that are left in it by name.
canonResidual :: Set Unique -> Value NF -> IO (Text, [Text])
canonResidual scope v = do
  (v', merged) <- reifyResidual scope v
  pure (prettyLayout v', nubOrd merged)

reifyResidual :: Set Unique -> Value NF -> IO (Value NF, [Text])
reifyResidual scope = \ case
  ValObligation env p a o t f l -> do
    (p', m1) <- case p of
      Left e  -> first Left <$> expr env e
      Right x -> pure (Right x, [])
    (a', m2) <- inside env a
    (o', m3) <- case o of
      Left mo -> first Left <$> inside env mo
      Right x -> pure (Right x, [])
    (t', m4) <- case t of
      Left mt -> first Left <$> inside env mt
      Right x -> pure (Right x, [])
    (f', m5) <- expr env f
    (l', m6) <- case l of
      Nothing -> pure (Nothing, [])
      Just e  -> first Just <$> expr env e
    pure (ValObligation env p' a' o' t' f' l', concat [m1, m2, m3, m4, m5, m6])
  ValROp env op l r -> do
    (l', m1) <- side env l
    (r', m2) <- side env r
    pure (ValROp env op l' r', m1 <> m2)
  ValQuantified env d -> first (ValQuantified env) <$> inside env d
  other -> pure (other, [])
  where
    expr env e = do
      e' <- reifyLocals scope env e
      pure (e', map unqualifiedNameToText (openLocals scope env e'))
    inside :: Optics.GPlate (Expr Resolved) x => Environment -> x -> IO (x, [Text])
    inside env x = do
      x' <- Optics.traverseOf (Optics.gplate @(Expr Resolved)) (reifyLocals scope env) x
      pure (x', concatMap (map unqualifiedNameToText . openLocals scope env) (Optics.toListOf (Optics.gplate @(Expr Resolved)) x'))
    side env = \ case
      Left e  -> first Left <$> expr env e
      Right x -> first Right <$> reifyResidual scope x

-- | 'reifyExpr', but only for the locals an expression closed over: a name
-- the replay resolves at the top level means the same in every position,
-- and is left as written whether or not this run forced it.
reifyLocals :: Set Unique -> Environment -> Expr Resolved -> IO (Expr Resolved)
reifyLocals scope env = Optics.transformMOf (Optics.gplate @(Expr Resolved)) \ case
  Var a r
    | not (Set.member (getUnique r) scope)
    , Just rf <- Map.lookup (getUnique r) env -> fromMaybe (Var a r) <$> reifyRef rf
  other -> pure other

-- | A ledger value as text, and whether it had a literal form.
valueText :: WHNF -> IO (Text, Bool)
valueText v = reifyValue reifyRef v >>= pure . \ case
  Just e  -> (prettyLayout e, True)
  Nothing -> (prettyLayout v, False)

-- | The ledgers as the state keeps them (see the module header), the
-- write-only cells dropped, and how many kept values had no literal form.
projectLedger :: ReadSites -> LedgerStore -> IO ([LedgerCell], [(Text, Text)], Int)
projectLedger sites store = do
  let ledgers = ("OFFICIAL", store.officialLedger) : Map.toList store.ownLedgers
      byCell =
        Map.fromListWith (flip (<>))
          [ ((name, Text.intercalate "'s " path), [(v, prov)])
          | (name, led) <- ledgers
          , Assign path v prov <- toList led ]
  kept <- for (Map.toList byCell) \ ((name, cell), entries) -> case Map.lookup cell sites.rsCells of
    Nothing -> pure (Left (name, cell))
    Just readsAll -> do
      let keepAll = readsAll || sites.rsTimeScoped
          chosen = if keepAll then entries else lastOf entries
      texts <- for chosen \ (v, prov) -> do
        (t, ok) <- valueText v
        let stamped = if sites.rsTimeScoped then t <> maybe "" (\ d -> " (valid from " <> Text.pack (show d) <> ")") prov.vtFrom else t
        pure (stamped, ok)
      pure (Right ( MkLedgerCell {lcLedger = name, lcCell = cell, lcKeep = if keepAll then KeptAll else KeptLatest, lcValues = map fst texts}
                  , length (filter (not . snd) texts) ))
  pure ( [ c | Right (c, _) <- kept ]
       , [ d | Left d <- kept ]
       , sum [ n | Right (_, n) <- kept ] )
  where
    lastOf xs = case reverse xs of
      (x : _) -> [x]
      []      -> []

----------------------------------------------------------------------------
-- Deadlines
----------------------------------------------------------------------------

-- | Each obligation in force, with its absolute deadline: 'Nothing' when it
-- has none, 'Left' with the reason when it has one that is not known here.
-- WhatIf's 'deadlineOf' first; an anchor the residual holds unforced is then
-- evaluated, when it is closed in the module ('resolveAnchor').
liveDeadlines :: Explorer -> Position -> IO [(RawObligation NF, Maybe (Either Text Rational))]
liveDeadlines ex pos = for (maybe [] liveObligations pos.posResidual) \ raw -> case raw.roDue of
  Left Nothing -> pure (raw, Nothing)
  _ -> do
    d <- deadlineOf pos.posClock raw
    case d of
      Right x  -> pure (raw, Just (Right x))
      Left why -> do
        resolved <- resolveAnchor ex pos raw
        pure (raw, Just (maybe (Left why) Right resolved))

-- | An anchored deadline whose anchor the residual holds UNFORCED — the
-- @WITHIN 0 OF closing@ of an obligation that has met no event yet — is
-- not known to the what-if ('deadlineOf'), which reads only what the
-- machine forced. When the anchor and the duration are closed in the
-- module (they name only top-level rules and builtins), they mean the same
-- in every run, and the evaluator is asked for them: one @#EVAL@ of each,
-- in the module, cached. The tick this offers is then held to
-- 'confirmTick' like any other, so a deadline the machine does not bear
-- out is still reported untried. Only the plain form is read: a window
-- with an opening edge, or a lifecycle anchor, stays unknown.
resolveAnchor :: Explorer -> Position -> RawObligation NF -> IO (Maybe Rational)
resolveAnchor ex pos raw = case (raw.roDue, raw.roOpens) of
  (Left (Just (MkDeadline _ duration (Just (AnchorAt _ anchor)))), opens)
    | noOpening opens -> do
        a <- closedNumber anchor
        d <- closedNumber duration
        pure ((+) <$> a <*> d)
  _ -> pure Nothing
  where
    noOpening = \ case
      Left Nothing  -> True
      Right Nothing -> True
      _             -> False
    closedNumber e = do
      e' <- reifyExpr raw.roEnv e
      case e' of
        Lit _ (NumericLit _ r) -> pure (Just r)
        _ | null (openLocals pos.posReplayScope raw.roEnv e') -> evaluated e'
          | otherwise -> pure Nothing
    evaluated e = do
      let key = prettyLayout e
      cache <- readIORef ex.exAnchors
      case Map.lookup key cache of
        Just r  -> pure r
        Nothing -> do
          r <- evalNumber ex e
          modifyIORef' ex.exAnchors (Map.insert key r)
          pure r

-- | One @#EVAL@ of a closed expression in the module.
evalNumber :: Explorer -> Expr Resolved -> IO (Maybe Rational)
evalNumber ex e = do
  let MkModule a uri (MkSection sa sn saka sg decls) = ex.exRig.rigModule
      m' = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno (LazyEval emptyAnno e)]))
  (_, results) <- execEvalModuleWithDeonticLog ex.exRig.rigConfig ex.exRig.rigEntityInfo ex.exRig.rigEnv m'
  pure case results of
    ((res, _) : _) | Reduction (Reduced (MkNF (ValNumber r))) <- res.result -> Just r
    _ -> Nothing

-- | The instants an act is fired at (§4.5), from the clock and the known
-- live deadlines.
actInstants :: ExploreOptions -> Rational -> [Rational] -> [Rational]
actInstants opts clock deadlines =
  let ahead = [ d | d <- deadlines, d >= clock ]
      limit = case (ahead, opts.eoUntil) of
        ([], Nothing) -> Nothing
        ([], Just u)  -> Just u
        (ds, Nothing) -> Just (minimum ds)
        (ds, Just u)  -> Just (min u (minimum ds))
      within t = maybe True (t <=) limit
  in nubOrd $ filter within $ case opts.eoTime of
       Regions -> case limit of
         Nothing -> [clock, clock + 1]
         Just e
           | e > clock -> [clock, (clock + e) / 2, e]
           | otherwise -> [clock]
       Grid n -> [clock, (fromIntegral (floor (clock / n) :: Integer) + 1) * n]

----------------------------------------------------------------------------
-- Exploring
----------------------------------------------------------------------------

data Node = MkNode
  { ndId     :: !Int
  , ndDepth  :: !Int
  , ndEvents :: ![Expr Resolved]
  , ndPos    :: !Position
  }

-- | What one try of one candidate came to.
data Tried
  = TriedEdge !Text !EdgeKind !(Expr Resolved) !Position
    -- ^ taken: the label, the event appended, the position it led to
  | TriedPassed !Text
  | TriedUntried !Text !Text
  | TriedBeyond
    -- ^ a tick past the clock bound, not taken
  | TriedRefused !Refusal

data Accum = MkAccum
  { acSeen       :: !(Map StateKey Int)
  , acNodes      :: ![StateNode]
    -- ^ newest first
  , acNext       :: !Int
  , acEdges      :: !(Set (Int, Text, Int))
  , acEdgeList   :: ![Transition]
    -- ^ newest first
  , acEdgeEvents :: !(Map (Int, Text, Int) (Expr Resolved))
  , acQueue      :: !(Seq Node)
  , acPassed     :: !Int
  , acBeyond     :: !Int
  , acDepthCut   :: !Int
  , acStatesCut  :: !Int
  , acUntried    :: !(Map (Text, Text) Int)
  , acRefused    :: ![Refusal]
  , acDropped    :: !(Set (Text, Text))
  , acMerged     :: !(Set Text)
  , acUnspell    :: !Int
  , acByForm     :: !(Set Text)
  }

-- | Explore a contract from its outset. 'Left' when the outset itself
-- cannot be run.
explore :: ExploreOptions -> ReadSites -> Rig -> Start -> IO (Either Text Graph)
explore opts sites rig0 start = do
  anchors <- newIORef Map.empty
  let ex = MkExplorer
        { exOptions = opts
        , exSites = sites
        , exRig = rig0 {rigModule = withoutDirectives rig0.rigModule}
        , exStart = start
        , exActionType = contractActionType rig0.rigEntityInfo start.stContract
        , exAnchors = anchors
        }
      (rig, tr) = rigFor ex []
  mpos <- position rig tr
  case mpos of
    Nothing -> pure (Left "the contract produced no result at its outset")
    Just pos0 -> case pos0.posResidual of
      Nothing -> pure (Left ("the contract could not be run at its outset: " <> standingText pos0.posResult))
      Just _ -> do
        (key0, notes0) <- stateKey ex pos0
        let node0 = MkNode {ndId = 0, ndDepth = 0, ndEvents = [], ndPos = pos0}
            acc0 = noteKey notes0 MkAccum
              { acSeen = Map.singleton key0 0
              , acNodes = [stateNode 0 0 [] key0 pos0]
              , acNext = 1
              , acEdges = Set.empty
              , acEdgeList = []
              , acEdgeEvents = Map.empty
              , acQueue = Seq.singleton node0
              , acPassed = 0
              , acBeyond = 0
              , acDepthCut = 0
              , acStatesCut = 0
              , acUntried = Map.empty
              , acRefused = []
              , acDropped = Set.empty
              , acMerged = Set.empty
              , acUnspell = 0
              , acByForm = Set.empty
              }
        acc <- loop ex acc0
        pure (Right (finish ex acc))

-- | Replay a path of events from a start, afresh, with nothing the
-- exploration computed: what a counterexample is held to before it is
-- printed ("L4.Lts.Explore.Check"; spec §6.3, "replay every counterexample
-- on the evaluator before printing it"). The events are those of a
-- 'StateNode''s 'snPath', or that path and one edge's event after it.
replayPath :: Rig -> Start -> [Expr Resolved] -> IO (Maybe Position)
replayPath rig start events = do
  let directive = Contract emptyAnno start.stContract start.stAt events
      MkModule a uri (MkSection sa sn saka sg decls) = withoutDirectives rig.rigModule
      rig' = rig {rigModule = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno directive]))}
  position rig' MkTrace {trDirective = directive, trContract = start.stContract, trStart = start.stAt, trEvents = events}

loop :: Explorer -> Accum -> IO Accum
loop ex acc = case acc.acQueue of
  Empty -> pure acc
  node :<| rest
    | node.ndDepth >= ex.exOptions.eoMaxDepth -> do
        -- a state at the bound with no candidate at all (FULFILLED, say)
        -- has nothing the bound kept from it: it is terminal, not cut.
        -- Listing the candidates replays nothing, so asking costs nothing.
        let (rig, tr) = rigFor ex node.ndEvents
        cands <- candidatesOf rig tr node.ndPos
        loop ex if null cands
          then terminal node acc {acQueue = rest}
          else acc {acQueue = rest, acDepthCut = acc.acDepthCut + 1}
    | otherwise -> do
        tried <- expand ex node
        acc' <- foldM (record ex node) acc {acQueue = rest} tried
        let fired = not (null [ () | TriedEdge {} <- tried ])
            blocked = not (null [ () | t <- tried, isBlocked t ])
            acc'' = if fired || blocked then acc' else terminal node acc'
            -- a pass-over counts once per state and act, and only if no
            -- instant took the act
            firedLabels = Set.fromList [ l | TriedEdge l _ _ _ <- tried ]
            passed = Set.fromList [ l | TriedPassed l <- tried, not (Set.member l firedLabels) ]
            -- an untried candidate counts once per state and reason
            untriedHere = Set.fromList [ (l, why) | TriedUntried l why <- tried ]
        loop ex acc''
          { acPassed = acc''.acPassed + Set.size passed
          , acUntried = foldl' (\ m k -> Map.insertWith (+) k 1 m) acc''.acUntried (Set.toList untriedHere)
          , acRefused = foldl' mergeRefusal acc''.acRefused (nubOrdOn refusalKey [ r | TriedRefused r <- tried ])
          }
  where
    isBlocked = \ case
      TriedUntried {} -> True
      TriedBeyond     -> True
      TriedRefused {} -> True
      _               -> False
    -- the one self-loop of §4.6, and the mark on the state
    terminal node a = (addEdge a Nothing (MkTransition node.ndId "terminal" node.ndId EdgeTerminal))
      { acNodes = map (\ s -> if s.snId == node.ndId then s {snTerminal = True} else s) a.acNodes }

refusalKey :: Refusal -> (Text, Text, Maybe Text, Text)
refusalKey r = (r.rfVariable, r.rfObligation, r.rfConstructor, r.rfReason)

mergeRefusal :: [Refusal] -> Refusal -> [Refusal]
mergeRefusal rs r = case break ((== refusalKey r) . refusalKey) rs of
  (before, hit : after) -> before <> [hit {rfStates = hit.rfStates + 1}] <> after
  (_, [])               -> rs <> [r {rfStates = 1}]

-- | Fold one try into the graph.
record :: Explorer -> Node -> Accum -> Tried -> IO Accum
record ex node acc = \ case
  TriedEdge label kind event pos' -> do
    (key, notes) <- stateKey ex pos'
    case Map.lookup key acc.acSeen of
      Just j -> pure (addEdge acc (Just event) (MkTransition node.ndId label j kind))
      Nothing
        | Map.size acc.acSeen >= ex.exOptions.eoMaxStates ->
            pure acc {acStatesCut = acc.acStatesCut + 1}
        | otherwise -> do
            let j = acc.acNext
                events = node.ndEvents <> [event]
                new = MkNode {ndId = j, ndDepth = node.ndDepth + 1, ndEvents = events, ndPos = pos'}
            pure $ addEdge (noteKey notes acc
              { acSeen = Map.insert key j acc.acSeen
              , acNodes = stateNode j (node.ndDepth + 1) events key pos' : acc.acNodes
              , acNext = j + 1
              , acQueue = acc.acQueue :|> new
              }) (Just event) (MkTransition node.ndId label j kind)
  TriedBeyond -> pure acc {acBeyond = acc.acBeyond + 1}
  _ -> pure acc

-- | An edge, once; the event it was first taken by is kept beside it.
addEdge :: Accum -> Maybe (Expr Resolved) -> Transition -> Accum
addEdge acc mevent t
  | Set.member k acc.acEdges = acc
  | otherwise = acc
      { acEdges = Set.insert k acc.acEdges
      , acEdgeList = t : acc.acEdgeList
      , acEdgeEvents = maybe acc.acEdgeEvents (\ e -> Map.insert k e acc.acEdgeEvents) mevent
      }
  where k = (t.tnFrom, t.tnLabel, t.tnTo)

noteKey :: KeyNotes -> Accum -> Accum
noteKey n acc = acc
  { acDropped = acc.acDropped <> Set.fromList n.knDropped
  , acMerged = acc.acMerged <> Set.fromList n.knMergedByName
  , acUnspell = acc.acUnspell + n.knUnspellable
  , acByForm = acc.acByForm <> Set.fromList n.knAnswersByForm
  }

stateNode :: Int -> Int -> [Expr Resolved] -> StateKey -> Position -> StateNode
stateNode i depth events key pos = MkStateNode
  { snId = i
  , snDepth = depth
  , snEvents = map (oneLine . prettyLayout) events
  , snPath = events
  , snStore = pos.posResult.ledger
  , snResidual = key.skResidual
  , snLedger = key.skLedger
  , snClock = pos.posClock
  , snTerminal = False
  }

finish :: Explorer -> Accum -> Graph
finish ex acc = MkGraph
  { gStart = ex.exStart
  , gStates = reverse acc.acNodes
  , gTransitions = reverse acc.acEdgeList
  , gEdgeEvents = acc.acEdgeEvents
  , gCoverage = MkCoverage
      { cvStates = Map.size acc.acSeen
      , cvTransitions = Set.size acc.acEdges
      , cvStops = [ StopDepth ex.exOptions.eoMaxDepth acc.acDepthCut | acc.acDepthCut > 0 ]
               <> [ StopStates ex.exOptions.eoMaxStates acc.acStatesCut | acc.acStatesCut > 0 ]
      , cvRefused = acc.acRefused
      , cvUntried = [ MkUntriedNote what why n | ((what, why), n) <- Map.toList acc.acUntried ]
      , cvPassedOver = acc.acPassed
      , cvDropped = Set.toList acc.acDropped
      , cvTime = timeText ex.exOptions
      , cvBeyondClock = acc.acBeyond
      , cvMergedByName = Set.toList acc.acMerged
      , cvUnspellable = acc.acUnspell
      , cvAnswersByForm = Set.toList acc.acByForm
      }
  }

timeText :: ExploreOptions -> Text
timeText opts = Text.concat
  [ case opts.eoTime of
      Regions -> "time by regions (the instant of the last event, one between it and the next deadline, the deadline; the clock is not in the state)"
      Grid n  -> "time on a grid of " <> prettyRatio n <> " (the clock is in the state)"
  , maybe "" (\ u -> ", clock bounded at " <> prettyRatio u) opts.eoUntil
  ]

-- | Every try at one position: each candidate the what-if lists, with the
-- set of a variable's acts enumerated and each act fired at each instant.
expand :: Explorer -> Node -> IO [Tried]
expand ex node = do
  let (rig, tr) = rigFor ex node.ndEvents
      pos = node.ndPos
  cands <- candidatesOf rig tr pos
  deadlines <- liveDeadlines ex pos
  -- each candidate's obligation, found again by the 'LiveNorm' the what-if
  -- rendered it to from the very same residual ('candidatesOf')
  let lives :: [(LiveNorm, (RawObligation NF, Maybe (Either Text Rational)))]
      lives = [ (renderLive pos.posContext raw, (raw, due)) | (raw, due) <- deadlines ]
      known = nubOrd [ d | (_, Just (Right d)) <- deadlines ]
      instants = actInstants ex.exOptions pos.posClock known
      offeredTicks = [ d | MkCandidate {cdKind = TickPast d _} <- cands ]
      run label kind cand = do
        (outcome, mpos) <- tryCandidateFrom rig tr pos cand
        pure case outcome.ocVerdict of
          Untried why  -> TriedUntried label why
          PassedOver _ -> TriedPassed label
          _ -> case (cand.cdHypothetical, mpos) of
            (Right hyp, Just pos') | isJust pos'.posResidual -> TriedEdge label kind (hypotheticalExpr hyp) pos'
            _ -> TriedUntried label "the replay produced no position"
      tick label cand = case cand.cdHypothetical of
        Right (Tick t) | Just u <- ex.exOptions.eoUntil, t > u -> pure [TriedBeyond]
        _ -> pure <$> run label EdgeTick cand
  fmap concat $ for cands \ cand -> case cand.cdKind of
    TickPast d _ -> tick (tickLabel cand d) cand
    NoTick live -> case snd <$> lookup live lives of
      Just (Just (Right d))
        | d `notElem` offeredTicks ->
            let cand' = cand {cdKind = TickPast d [live], cdHypothetical = Right (Tick (tickPast known d))}
            in tick (tickLabel cand' d) cand'
        | otherwise -> pure []
      _ -> pure [TriedUntried ("time runs out on " <> live.lnAction) (either id (const "") cand.cdHypothetical)]
    ActBy live -> case fst <$> lookup live lives of
      Nothing -> pure [TriedUntried live.lnAction "the obligation could not be found in the residual again"]
      Just raw -> do
        mparty <- partyOf raw
        acts <- actsOf ex pos raw cand
        case (mparty, acts) of
          (Nothing, _) -> pure [TriedUntried live.lnAction "the party was never forced and could not be read back"]
          (Just party, Left why) -> pure [TriedUntried (obligationText party raw) why]
          (Just party, Right (actions, refusals)) -> do
            ran <- for [ (a, t) | a <- actions, t <- instants ] \ (a, t) ->
              run (actLabel party a) EdgeAct cand
                { cdHypothetical = Right Act {hyParty = party, hyAction = a, hyAt = t}
                , cdBound = Nothing }
            pure (ran <> map (TriedRefused . refusalFor party raw) refusals)
  where
    tickLabel cand d = case cand.cdHypothetical of
      Right (Tick t) -> "time passes the deadline " <> prettyRatio d <> " (WAIT UNTIL " <> prettyRatio t <> ")"
      _              -> "time passes the deadline " <> prettyRatio d
    refusalFor party raw (variable, ty, whole, constructor, why) = MkRefusal
      { rfVariable = variable
      , rfType = ty
      , rfWhole = whole
      , rfObligation = obligationText party raw
      , rfConstructor = constructor
      , rfReason = why
      , rfStates = 1
      }

-- | @PARTY World MAY act@, for naming an obligation in the coverage.
obligationText :: Expr Resolved -> RawObligation NF -> Text
obligationText party raw = "PARTY " <> prettyLayout party <> " " <> prettyLayout unguarded
  where
    MkAction a modal pat _ = raw.roAction
    unguarded = MkAction a modal pat Nothing

-- | @PARTY World DOES `Alice buys dinner` OF TRUE@: the act, as the label of
-- its edge. The instant is not in the label: it is not in the state.
actLabel :: Expr Resolved -> Expr Resolved -> Text
actLabel party action = "PARTY " <> prettyLayout party <> " DOES " <> prettyLayout action

-- | The obligation's bearer, read back as the what-if reads it.
partyOf :: RawObligation NF -> IO (Maybe (Expr Resolved))
partyOf raw = either (fmap Just . reifyExpr raw.roEnv) (reifyNF . MkNF) raw.roParty

-- | The acts of one obligation: its own act, or every act of the set its
-- pattern names, with the constructors that were refused. 'Left' when the
-- obligation's act could not be built at all.
actsOf
  :: Explorer -> Position -> RawObligation NF -> Candidate
  -> IO (Either Text ([Expr Resolved], [(Text, Text, Bool, Maybe Text, Text)]))
actsOf ex pos raw cand = case cand.cdBound of
  Nothing -> pure case cand.cdHypothetical of
    Right (Act _ a _) -> Right ([a], [])
    Right (Tick _)    -> Left "a tick where an act was expected"
    Left why          -> Left why
  Just _ -> pure case patternBinders raw.roAction.action of
    [(BoundWholeAction, v)] -> case ex.exActionType of
      Left why -> Right ([], [(nameText v, "(not known)", True, Nothing, why)])
      Right ty -> case enumerateType info ty of
        Left why -> Right ([], [(nameText v, prettyLayout ty, True, Nothing, why)])
        Right dom -> capped v ty True (dom.dmValues, [ (nameText v, prettyLayout ty, True, Just r.rdConstructor, refusedText r) | r <- dom.dmRefused ])
    binders -> do
      let types = binderTypes info raw.roAction.action
          perBinder =
            [ (v, case Map.lookup (getUnique v) types of
                    Nothing -> Left ("(not known)", "no declared type was recorded for it")
                    Just ty -> first (prettyLayout ty,) (enumerateType info ty)
                  )
            | (_, v) <- binders ]
          refusedWhole = [ (nameText v, t, False, actionConstructor, why) | (v, Left (t, why)) <- perBinder ]
          refusedNested =
            [ (nameText v, ty, False, Just r.rdConstructor, refusedText r)
            | (v, Right dom) <- perBinder
            , let ty = maybe "(not known)" prettyLayout (Map.lookup (getUnique v) types)
            , r <- dom.dmRefused ]
      shape <- maybe (Left "the action has no expression form") Right cand.cdShape
      if not (null refusedWhole)
        then Right ([], refusedWhole <> refusedNested)
        else do
          let domains = [ (v, either (const []) (.dmValues) d) | (v, d) <- perBinder ]
              size = product (map (length . snd) domains)
          if size > ex.exOptions.eoMaxActs
            then Right ([], refusedNested <>
              [ (Text.intercalate " and " (map (nameText . fst) domains), Text.intercalate ", " [ t | (v, _) <- domains, Just ty <- [Map.lookup (getUnique v) types], let t = prettyLayout ty ], False, actionConstructor
                , "they name " <> Text.pack (show size) <> " acts, more than the bound of " <> Text.pack (show ex.exOptions.eoMaxActs)) ])
            else do
              let choices = traverse (\ (v, vals) -> map (v,) vals) domains
              actions <- traverse (closedAction pos.posReplayScope raw.roEnv . (`fillBinders` shape)) choices
              Right (actions, refusedNested)
  where
    info = ex.exRig.rigEntityInfo
    actionConstructor = case raw.roAction.action of
      PatApp _ con _ -> Just (nameText con)
      _              -> Nothing
    capped v ty whole (values, refusals)
      | length values > ex.exOptions.eoMaxActs =
          Right ([], refusals <> [(nameText v, prettyLayout ty, whole, Nothing,
            "it names " <> Text.pack (show (length values)) <> " acts, more than the bound of " <> Text.pack (show ex.exOptions.eoMaxActs))])
      | otherwise = Right (values, refusals)

-- | @its field `recorded at` is a NUMBER, and a NUMBER has no finite set of
-- values@, with where the constructor sits when it is inside another.
refusedText :: Refused -> Text
refusedText r = Text.concat
  [ case r.rdWithin of
      [] -> ""
      w  -> "it sits in " <> Text.intercalate " in " [ "`" <> f <> "` of `" <> c <> "`" | (c, f) <- reverse w ] <> ", and "
  , "its field `", r.rdField, "` is ", article r.rdFieldType, " ", r.rdFieldType, ", and ", r.rdWhy
  ]
  where
    article t = if maybe False (`elem` ("AEIOU" :: String)) (fst <$> Text.uncons t) then "an" else "a"

----------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------

-- | The graph as text: the states, the transitions, the residuals they
-- share, what was refused or untried, and the coverage line last (§4.4).
renderGraph :: Graph -> Text
renderGraph g = Text.unlines $
  [ heading, "" ]
  <> concatMap stateLines g.gStates
  <> [ "", "Transitions (" <> textShow (length g.gTransitions) <> "):" ]
  <> map transitionLine g.gTransitions
  <> [ "", "Residuals (" <> textShow (length residuals) <> "):" ]
  <> concat [ residualLines i r | (i, r) <- zip [0 :: Int ..] residuals ]
  <> detailLines g.gCoverage
  <> [ "", coverageLine g.gCoverage ]
  where
    heading = g.gStart.stName <> ", explored from its outset at " <> prettyLayout g.gStart.stAt
      <> ": " <> count g.gCoverage.cvStates "state" <> ", " <> count g.gCoverage.cvTransitions "transition"
    residuals = nubOrd' (map (.snResidual) g.gStates)
    residualIndex r = maybe "?" (\ i -> "r" <> textShow i) (elemIndex r residuals)
    stateLines s =
      [ "s" <> textShow s.snId <> "  depth " <> textShow s.snDepth <> ", residual " <> residualIndex s.snResidual
          <> (if s.snTerminal then ", terminal" else "") ]
      <> (case s.snEvents of
            [] -> ["    at the outset"]
            es -> "    first reached by:" : map ("      " <>) es)
      <> (case s.snLedger of
            [] -> ["    ledgers: nothing kept"]
            cs -> map (("    " <>) . cellText) cs)
    transitionLine t = "  s" <> textShow t.tnFrom <> " -> s" <> textShow t.tnTo <> "  " <> t.tnLabel
    residualLines i r = case Text.lines r of
      [] -> ["  r" <> textShow i]
      (l : ls) -> ("  r" <> textShow i <> "  " <> l) : map ("      " <>) ls

-- | One kept cell: @OFFICIAL's `dinner status record`: opened, taken@.
cellText :: LedgerCell -> Text
cellText c = c.lcLedger <> "'s `" <> c.lcCell <> "`"
  <> (case c.lcKeep of KeptAll -> ""; KeptLatest -> " (latest)")
  <> ": " <> Text.intercalate ", " c.lcValues

-- | The refusals and untried candidates, each with its reason, before the
-- coverage line that counts them.
detailLines :: Coverage -> [Text]
detailLines cv =
  (if null cv.cvRefused then [] else "" : "Refused (not explored, no sample tried in their place):" : map refusalLine cv.cvRefused)
  <> (if null cv.cvUntried then [] else "" : "Untried:" : map untriedLine cv.cvUntried)
  <> (if null cv.cvMergedByName then [] else
        [ "", "Compared by name only (a residual held these locals unforced; positions differing in their values would be merged):"
        , "  " <> Text.intercalate ", " (map (\ n -> "`" <> n <> "`") cv.cvMergedByName) ])
  where
    untriedLine u = "  - " <> u.unWhat <> ", in " <> count u.unStates "state" <> ": " <> u.unWhy

refusalLine :: Refusal -> Text
refusalLine r = "  - " <> refusalText r <> ", in " <> count r.rfStates "state"

-- | @the rule binds `act` (the whole action of PARTY World MAY act), of
-- type Act: constructor `x` is refused: its field `y` is a NUMBER, …@
refusalText :: Refusal -> Text
refusalText r = Text.concat
  [ "the rule binds `", r.rfVariable, "` ("
  , if r.rfWhole then "the whole action" else "an operand of the action"
  , " of ", r.rfObligation, "), of type ", r.rfType
  , case r.rfConstructor of
      Just c  -> ": constructor `" <> c <> "` is refused: " <> r.rfReason
      Nothing -> ": refused: " <> r.rfReason
  ]

-- | §4.4's coverage line: what was explored, whether the frontier was
-- exhausted or which bound stopped it, what was refused and untried, and
-- which time scheme was used.
coverageLine :: Coverage -> Text
coverageLine cv = "Coverage: " <> Text.intercalate "; " (filter (not . Text.null)
  [ count cv.cvStates "state" <> ", " <> count cv.cvTransitions "transition"
  , case cv.cvStops of
      [] -> "frontier exhausted"
      ss -> "frontier NOT exhausted: " <> Text.intercalate ", " (map stopText ss)
  , case cv.cvRefused of
      [] -> "nothing refused"
      rs -> "REFUSED " <> textShow (length rs) <> ": " <> Text.intercalate "; " (map refusalShort rs)
  , case cv.cvUntried of
      [] -> "nothing untried"
      us -> "UNTRIED " <> textShow (length us) <> ": " <> Text.intercalate "; " [ u.unWhat <> " (" <> u.unWhy <> ")" | u <- us ]
  , count cv.cvPassedOver "act" <> " passed over"
  , if cv.cvBeyondClock > 0 then count cv.cvBeyondClock "tick" <> " past the clock bound not taken" else ""
  , case cv.cvDropped of
      [] -> "no write-only cell dropped"
      ds -> "write-only cells dropped: " <> Text.intercalate ", " [ l <> "'s `" <> c <> "`" | (l, c) <- ds ]
  , if null cv.cvMergedByName then "" else "compared by name only: " <> Text.intercalate ", " (map (\ n -> "`" <> n <> "`") cv.cvMergedByName)
  , if cv.cvUnspellable > 0 then count cv.cvUnspellable "ledger value" <> " compared by printed form" else ""
  , if null cv.cvAnswersByForm then "" else "answers compared by printed form: " <> Text.intercalate ", " (map (\ n -> "`" <> n <> "`") cv.cvAnswersByForm)
  , cv.cvTime
  ])
  where
    stopText = \ case
      StopDepth b n  -> count n "state" <> " at the depth bound " <> textShow b <> " not expanded"
      StopStates b n -> count n "new state" <> " past the state bound " <> textShow b <> " not added"
    refusalShort r = "`" <> r.rfVariable <> "` of type " <> r.rfType
      <> maybe "" (\ c -> ", constructor `" <> c <> "`") r.rfConstructor
      <> " (" <> r.rfReason <> ")"

-- | The graph as JSON: every state with its path and kept ledger, every
-- transition, and the coverage.
graphJson :: Graph -> Aeson.Value
graphJson g = Aeson.object
  [ "contract" .= g.gStart.stName
  , "at" .= prettyLayout g.gStart.stAt
  , "states" .= map stateJson g.gStates
  , "transitions" .= map transitionJson g.gTransitions
  , "coverage" .= coverageJson g.gCoverage
  ]
  where
    stateJson s = Aeson.object
      [ "id" .= s.snId
      , "depth" .= s.snDepth
      , "path" .= s.snEvents
      , "residual" .= s.snResidual
      , "ledger" .= map cellJson s.snLedger
      , "terminal" .= s.snTerminal
      ]
    cellJson c = Aeson.object
      [ "ledger" .= c.lcLedger
      , "cell" .= c.lcCell
      , "kept" .= (case c.lcKeep of KeptAll -> "all" :: Text; KeptLatest -> "latest")
      , "values" .= c.lcValues
      ]
    transitionJson t = Aeson.object
      [ "from" .= t.tnFrom
      , "to" .= t.tnTo
      , "label" .= t.tnLabel
      , "kind" .= (case t.tnKind of EdgeAct -> "act" :: Text; EdgeTick -> "tick"; EdgeTerminal -> "terminal")
      ]

coverageJson :: Coverage -> Aeson.Value
coverageJson cv = Aeson.object
  [ "states" .= cv.cvStates
  , "transitions" .= cv.cvTransitions
  , "complete" .= coverageComplete cv
  , "frontierExhausted" .= null cv.cvStops
  , "stops" .= map stopJson cv.cvStops
  , "refused" .= map refusalJson cv.cvRefused
  , "untried" .= [ Aeson.object ["what" .= u.unWhat, "why" .= u.unWhy, "states" .= u.unStates] | u <- cv.cvUntried ]
  , "passedOver" .= cv.cvPassedOver
  , "ticksPastClockBound" .= cv.cvBeyondClock
  , "writeOnlyCellsDropped" .= [ Aeson.object ["ledger" .= l, "cell" .= c] | (l, c) <- cv.cvDropped ]
  , "comparedByNameOnly" .= cv.cvMergedByName
  , "ledgerValuesComparedByPrintedForm" .= cv.cvUnspellable
  , "answersComparedByPrintedForm" .= cv.cvAnswersByForm
  , "time" .= cv.cvTime
  , "line" .= coverageLine cv
  ]
  where
    stopJson = \ case
      StopDepth b n  -> Aeson.object ["bound" .= ("depth" :: Text), "limit" .= b, "cut" .= n]
      StopStates b n -> Aeson.object ["bound" .= ("states" :: Text), "limit" .= b, "cut" .= n]
    refusalJson r = Aeson.object
      [ "variable" .= r.rfVariable
      , "type" .= r.rfType
      , "wholeAction" .= r.rfWhole
      , "obligation" .= r.rfObligation
      , "constructor" .= r.rfConstructor
      , "reason" .= r.rfReason
      , "states" .= r.rfStates
      , "text" .= refusalText r
      ]

-- | The graph in GraphViz's DOT language: one node per state, a double
-- circle for a terminal one, one edge per transition, labelled.
graphDot :: Graph -> Text
graphDot g = Text.unlines $
  [ "digraph explore {"
  , "  label=" <> quote (g.gStart.stName <> " at " <> prettyLayout g.gStart.stAt) <> ";"
  , "  node [shape=circle];"
  ]
  <> [ "  s" <> textShow s.snId <> " [label=" <> quote ("s" <> textShow s.snId) <> (if s.snTerminal then ", shape=doublecircle" else "") <> "];"
     | s <- g.gStates ]
  <> [ "  s" <> textShow t.tnFrom <> " -> s" <> textShow t.tnTo <> " [label=" <> quote t.tnLabel <> "];"
     | t <- g.gTransitions ]
  <> [ "  // " <> coverageLine g.gCoverage, "}" ]
  where
    quote t = "\"" <> Text.concatMap escape t <> "\""
    escape = \ case
      '"'  -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      c    -> Text.singleton c

-- | Printed source on one line, as an event in a @#TRACE@ is written.
oneLine :: Text -> Text
oneLine = Text.unwords . Text.words

count :: Int -> Text -> Text
count n w = textShow n <> " " <> w <> (if n == 1 then "" else "s")

-- | 'nubOrd', keeping first occurrences in order.
nubOrd' :: Ord a => [a] -> [a]
nubOrd' = nubOrd
