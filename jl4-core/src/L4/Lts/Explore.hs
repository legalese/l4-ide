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
-- An act fires at a choice of WHOLE instants (§4.5, T2: contract time is
-- discrete): the instant of the last event, the earliest live deadline
-- exactly, the instants where a window opens, the instants at which a
-- deadline some chain of acts would start falls on one fixed in absolute
-- time (a /tie/), and one instant between each of those. See
-- 'instantsFor'. An act is never fired past a live deadline: the machine
-- would expire the deadline first and the edge would carry the act's name for
-- the deadline's effect, so a later instant is reached by the tick past the
-- deadline and then the act, which is the same position with honest labels.
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
  , InstantStats (..)
  , Stop (..)
  , Refusal (..)
  , UntriedNote (..)
  , explore
  , coverageComplete
  , replayPath
    -- * What tests hold the scheme to
  , Explorer
  , newExplorer
  , rigFor
  , liveDeadlines
  , timeSignature
  , keyText
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
import Data.Ratio (denominator)
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
import L4.Lts.Marking (Bearer (..), Countdown (..), LiveNorm (..), RawObligation (..), liveObligations, renderLive)
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
  , eoMaxInstants :: !Int
    -- ^ the most instants one act is tried at in one state; more are not
    -- tried, and the coverage says so
  , eoChains    :: !Bool
    -- ^ under 'Regions', search the ties that need a CHAIN of acts too (an
    -- act starts a deadline, the next act's tie is in reach only if this one
    -- was early enough). Off, they are not searched, and the coverage says
    -- how many (state, act) pairs they would have added instants to
  }

-- | How the instant an act fires at is chosen (§4.5).
data TimeScheme
  = Regions
    -- ^ whole instants where something can change, chosen by 'instantsFor';
    -- the clock is not in the state
  | Grid !Rational
    -- ^ the instant of the last event and every multiple of this step from
    -- the first instant the act's window is open to the earliest live
    -- deadline; the clock is in the state. For a guard that reads the clock
    -- arithmetically, on the condition that every event time, deadline and
    -- opening is a multiple of the step, which is checked ('offGrid')
  deriving stock (Eq, Show)

defaultExploreOptions :: ExploreOptions
defaultExploreOptions = MkExploreOptions
  { eoMaxDepth = 100
  , eoMaxStates = 10000
  , eoUntil = Nothing
  , eoTime = Regions
  , eoMaxActs = 4096
  , eoMaxInstants = 256
  , eoChains = False
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
  , gKept        :: !(Map Text Bool)
    -- ^ every cell the state keeps, in every ledger: 'True' for its whole
    -- history, 'False' for its latest entry. A cell not here was dropped
    -- wherever it was written, so positions that differ in it may be one
    -- state ("L4.Lts.Explore.Check" labels nothing by such a cell)
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
  , cvInstants     :: !InstantStats
    -- ^ how many acts were tried at how many instants, and why those
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
  = ClockDropped ![Bool] ![Maybe Int] ![Maybe Int]
    -- ^ for each live deadline whose instant is known: has the clock passed it;
    -- and the rank of each live deadline and each window opening among one
    -- another ('ranksOf'), ties equal. The clock itself is not kept, and a
    -- clock AT a deadline is the same state as one before it (the contract
    -- does not say them apart, and a deadline that is not in the residual's
    -- text, being anchored (@WITHIN 3 OF THE DEADLINE@), prints the same at
    -- every clock). But which of two deadlines comes first is part of where
    -- the position stands, and the printed residual does not say it for an
    -- anchored one: two positions that differ only in that were one state
    -- (smucclaw/l4-ide, the explorer's X1)
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
  , exHint       :: !(Map Text (Set Rational, Set Rational))
    -- ^ per act (as its edge is labelled), what the acts that can FOLLOW it
    -- were found to do in an earlier pass over the same contract: the sums of
    -- the offsets by which they start deadlines along the paths of acts that
    -- follow it ('pathPools'), and the instants fixed in absolute time that
    -- their positions held. With 'eoChains', ties are searched over all of
    -- them ('regionInstants'); without, they are only counted
    -- ('chainsLeftOut')
  , exRecords    :: !(IORef [ActRecord])
    -- ^ every act whose instants were chosen, newest first
  }

-- | One act in one state, as its instants were chosen, and what its probes
-- showed about time.
data ActRecord = MkActRecord
  { arState   :: !Int
  , arLabel   :: !Text
  , arClock   :: !Rational
  , arLimit   :: !(Maybe Rational)
  , arTried   :: !(Set Rational)
  , arFixed   :: ![Rational]
    -- ^ the instants the position held when the act was tried
  , arOffsets :: ![Rational]
    -- ^ the offsets by which the act started deadlines
  , arLearnedFixed :: ![Rational]
    -- ^ the instants fixed in absolute time that its successors held
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
  openings <- for (maybe [] liveObligations pos.posResidual) (openingOf pos.posClock)
  let (dueRanks, openRanks) = ranksOf [ d | (_, d) <- deadlines ] openings
      clock = case ex.exOptions.eoTime of
        Regions -> ClockDropped [ pos.posClock > d | (_, Just (Right d)) <- deadlines ] dueRanks openRanks
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

-- | The state key as text: two positions with the same text are one state.
keyText :: Explorer -> Position -> IO Text
keyText ex pos = textShow . fst <$> stateKey ex pos

-- | A position up to time: what it IS, with the countdowns taken out and
-- the ORDER of its instants kept. It is what a graph built on a sample of
-- instants is held to, against every instant (the key itself holds the
-- remaining @WITHIN@ numbers, which a sample cannot reproduce for an
-- instant it did not try). It is NOT a bisimulation: two positions with the
-- same signature but different gaps between their deadlines have different
-- futures (an act that starts a deadline of 2 puts it on one and not the
-- other), which is why 'instantsFor' chooses instants by the chains of acts
-- that can follow and not only by the order of what is live now. A test that
-- finds every signature at depth @d@ tells nothing about depth @d + 1@.
--
-- Its parts: the standing, or the residual with each live obligation's
-- remaining due and opening taken out; the ledgers as the state keeps them;
-- whether the clock has passed each deadline, and the rank of every known
-- deadline and of every known opening among one another, ties equal.
timeSignature :: Explorer -> Position -> IO Text
timeSignature ex pos = do
  (residual, _) <- case pos.posResidual of
    Just v  -> canonResidual pos.posReplayScope (withoutTimes v)
    Nothing -> pure (standingText pos.posResult, [])
  (cells, _, _) <- projectLedger ex.exSites pos.posResult.ledger
  deadlines <- liveDeadlines ex pos
  openings <- for (maybe [] liveObligations pos.posResidual) (openingOf pos.posClock)
  let (dueRanks, openRanks) = ranksOf [ d | (_, d) <- deadlines ] openings
  pure (Text.unlines
    [ residual
    , textShow cells
    , "passed " <> textShow [ pos.posClock > d | (_, Just (Right d)) <- deadlines ]
    , "opening ranks " <> textShow openRanks
    , "deadline ranks " <> textShow dueRanks
    ])
  where
    withoutTimes = \ case
      ValObligation env p a _ _ f l -> ValObligation env p a (Left Nothing) (Left Nothing) f l
      ValROp env op l r -> ValROp env op (side l) (side r)
      other -> other
    side = \ case
      Left e  -> Left e
      Right x -> Right (withoutTimes x)

-- | The rank of every known deadline and of every known opening among one
-- another (dense, ties equal); 'Nothing' for one whose instant is not known.
-- The clock is not among them.
ranksOf :: [Maybe (Either Text Rational)] -> [Maybe (Either Text Rational)] -> ([Maybe Int], [Maybe Int])
ranksOf dues opens = (map (>>= rank) dueOf, map (>>= rank) openOf)
  where
    known x = either (const Nothing) Just =<< x
    dueOf = map known dues
    openOf = map known opens
    instants = sort (nubOrd (catMaybes dueOf <> catMaybes openOf))
    rank x = fmap fst (find ((== x) . snd) (zip [0 :: Int ..] instants))

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

----------------------------------------------------------------------------
-- The instants an act is tried at
----------------------------------------------------------------------------

-- | What an act's instants are chosen from, at one position.
data Window = MkWindow
  { wnState      :: !Int
    -- ^ the state the act is tried in
  , wnLabel      :: !Text
    -- ^ the act, as its edge is labelled
  , wnClock      :: !Rational
    -- ^ the instant of the last event: an act is never tried before it
  , wnLimit      :: !(Maybe Rational)
    -- ^ the earliest live deadline, or the clock bound if that is sooner: an
    -- act is never tried past it, because the machine would expire the
    -- deadline first and the edge would carry the act's name for the
    -- deadline's effect. 'Nothing': no live deadline and no bound
  , wnOpen       :: !(Maybe Rational)
    -- ^ the instant the act's own window opens, when the obligation has an
    -- opening edge and its instant is known: before it the act is a nullity
  , wnFixed      :: ![Rational]
    -- ^ the instants OTHER live obligations hold in absolute time: their
    -- deadlines and openings. An act that starts a deadline of its own ties
    -- with one of these at one instant
  , wnOtherOpens :: ![Rational]
    -- ^ the others' openings: an act that two obligations would take is
    -- taken by one of them or both according to which side of its opening it
    -- falls on
  , wnHeld       :: ![Held]
    -- ^ what the position holds now, by obligation: an obligation the act
    -- leaves with the instant it had is fixed, which is not to be told from
    -- one that moved by matching values across probes
  }

-- | What choosing the instants of one act came to.
data Instants = MkInstants
  { inRuns   :: ![(Rational, Tried)]
    -- ^ every instant tried, in order, with what came of it
  , inCuts   :: ![(Text, Text)]
    -- ^ what could not be tried, as an untried candidate's (what, why)
  , inStats  :: !InstantStats
  }

-- | How many acts were tried, at how many instants, and why those: the
-- coverage's account of the scheme (an information clause: what was left out
-- is in the untried ones).
data InstantStats = MkInstantStats
  { isActs     :: !Int
  , isInstants :: !Int
  , isTies     :: !Int
    -- ^ instants chosen because a deadline the act starts meets another
  , isGaps     :: !Int
    -- ^ instants chosen to stand for the whole numbers between two others
  }
  deriving stock (Eq, Show)

instance Semigroup InstantStats where
  MkInstantStats a b c d <> MkInstantStats a' b' c' d' = MkInstantStats (a + a') (b + b') (c + c') (d + d')

instance Monoid InstantStats where
  mempty = MkInstantStats 0 0 0 0

-- | The instants of one act, by the scheme the run was asked for. @probe@
-- tries the act at one instant.
--
-- 'Regions' (§4.5): an act is tried at the instants where something can
-- change, and at one whole instant in each gap between them. After an act at
-- @t@ the live deadlines are of two kinds: instants fixed in absolute time
-- (those already live, and those anchored to one) and those the act starts,
-- which move with @t@. How @t@ orders against the fixed instants decides
-- what happens next, and the tie @t + w = d@ is a case of its own: it is where
-- two deadlines fall together, and a breach names both parties. So the
-- instants are the clock; the limit; the act's own opening; every other
-- opening between the clock and the limit; every tie; and one whole instant
-- inside each gap between two of those that has one. Only whole instants
-- are tried (contract time is discrete, T2).
--
-- The offsets @w@ and the fixed instants are READ from the replays, not from
-- the text of the @HENCE@: the act is tried at the clock and at the limit,
-- and the known deadlines and openings of the positions that come back are
-- compared: a value that is found again, shifted by the difference of the
-- two instants, moved with @t@ (an offset), and one that is found again as it
-- was did not (a fixed instant). A value that matches both ways, or neither
-- (the contract answered differently at the two instants), counts as both,
-- which costs an instant and never a tie. The set is closed under what later
-- replays show, within 'eoMaxInstants'.
--
-- 'Grid' n: the clock, and every multiple of n from the first instant the
-- act's window is open to the limit. With no limit, only up to one step past
-- that instant, which is said.
instantsFor :: Explorer -> Window -> (Rational -> IO Tried) -> IO Instants
instantsFor ex w probe = case ex.exOptions.eoTime of
  Regions -> regionInstants ex w probe
  Grid n  -> gridInstants ex n w probe

isWhole :: Rational -> Bool
isWhole x = denominator x == 1

-- | The first instant the window is open: the opening, if it is after the clock.
openFrom :: Window -> Rational
openFrom w = maybe w.wnClock (max w.wnClock) w.wnOpen

gridInstants :: Explorer -> Rational -> Window -> (Rational -> IO Tried) -> IO Instants
gridInstants ex n w probe = do
  let cap = ex.exOptions.eoMaxInstants
      c = w.wnClock
      firstMultiple = fromInteger (ceiling (openFrom w / n)) * n
      multiples = case w.wnLimit of
        Just l  -> takeWhile (<= l) (iterate (+ n) firstMultiple)
        Nothing -> [firstMultiple, firstMultiple + n]
      wanted = nubOrd (c : multiples)
      (kept, cutOff) = splitAt cap wanted
      noLimit = isNothing w.wnLimit
  runs <- for kept \ t -> (t,) <$> probe t
  pure MkInstants
    { inRuns = runs
    , inCuts =
        [ ("at the grid points past the instant cap", "it needs more instants than the instant cap of " <> textShow cap <> "; the rest were not tried (--max-instants raises the bound)")
        | not (null cutOff) ]
        <> [ ("at the grid points past one step after its window opens", "there is no deadline and no --until, so the clock has no end to try up to (--until bounds it)")
           | noLimit ]
    , inStats = MkInstantStats {isActs = 1, isInstants = length runs, isTies = 0, isGaps = 0}
    }

regionInstants :: Explorer -> Window -> (Rational -> IO Tried) -> IO Instants
regionInstants ex w probe = go Map.empty
  where
    c = w.wnClock
    cap = ex.exOptions.eoMaxInstants
    inRange t = t >= c && maybe True (t <=) w.wnLimit
    lo = openFrom w
    (hintSums, hintFixed) = Map.findWithDefault (Set.empty, Set.empty) w.wnLabel ex.exHint
    -- the instants the position itself names
    base = nubOrd (filter inRange ([c, lo] <> maybeToList w.wnLimit <> w.wnOtherOpens)
                   <> [ lo + 1 | isNothing w.wnLimit ])

    -- @tried@: each instant tried, what came of it, and what the position it
    -- led to holds in absolute time
    go :: Map Rational (Tried, [Held]) -> IO Instants
    go tried = do
      let seen = [ (t, th) | (t, (TriedEdge {}, th)) <- Map.toList tried ]
          (learnedOffsets, learnedFixed) = shiftOrStay w.wnHeld seen
      let -- the clock itself is an offset of 0: a deadline fixed in absolute
          -- time that only the successor holds is a boundary at its own instant
          own = nubOrd (0 : learnedOffsets)
          offsets = chainOffsets own (if ex.exOptions.eoChains then Set.toList hintSums else [0])
          fixedAll = nubOrd (learnedFixed <> w.wnFixed <> (if ex.exOptions.eoChains then Set.toList hintFixed else []) <> maybeToList w.wnLimit)
          early = [ o | (TriedPassed _ (Just o), _) <- Map.elems tried ]
          ties = tiesOf inRange fixedAll offsets
          sumsTruncated = False
          named = nubOrd (base <> filter inRange early <> ties)
          (wholeNamed, notWhole) = partition (\ t -> t == c || isWhole t) named
          critical = sort wholeNamed
          gapReps =
            [ rep
            | (x, y) <- zip critical (drop 1 critical)
            , y - x >= 2
            , let rep = fromInteger (floor x + 1)
            , rep < y
            , not (any (\ t -> t > x && t < y) (Map.keys tried)) ]
          wanted = filter (`Map.notMember` tried) (critical <> gapReps)
          room = max 0 (cap - Map.size tried)
          (now, cutOff) = splitAt room wanted
      if null now
        then settle tried learnedOffsets learnedFixed (Set.fromList critical) (Set.fromList ties) notWhole (length (take 100001 cutOff)) sumsTruncated
        else do
          ran <- for now \ t -> do
            r <- probe t
            th <- case r of
              TriedEdge _ _ _ p -> thresholdsOf ex p
              _                 -> pure []
            pure (t, (r, th))
          go (foldl' (\ m (t, r) -> Map.insert t r m) tried ran)

    settle tried learnedOffsets learnedFixed critical ties notWhole cutN sumsTruncated = do
      modifyIORef' ex.exRecords (MkActRecord
        { arState = w.wnState, arLabel = w.wnLabel, arClock = c, arLimit = w.wnLimit
        , arTried = Set.fromList (Map.keys tried), arFixed = nubOrd (w.wnFixed <> maybeToList w.wnLimit)
        , arOffsets = learnedOffsets, arLearnedFixed = learnedFixed } :)
      let runs = [ (t, r) | (t, (r, _)) <- Map.toList tried ]
          ts = map fst runs
          tieHits = length [ () | t <- ts, Set.member t ties, t `notElem` base ]
          gapHits = length [ () | t <- ts, Set.notMember t critical ]
      pure MkInstants
        { inRuns = runs
        , inCuts =
            [ ("at instants that are not whole numbers"
              , "an instant it needs (" <> prettyRatio (minimum notWhole) <> ") is not a whole number, and only whole instants are tried")
            | not (null notWhole) ]
            <> [ ("at the instants past the instant cap"
                 , "it needs " <> (if cutN > 100000 then "more than 100000" else textShow cutN) <> " more instants than the instant cap of "
                     <> textShow cap <> " allows; they were not tried (--max-instants raises the bound)")
               | cutN > 0 ]
            <> [ ("at the ties that chains of acts make"
                 , "the chains of offsets it would add up are too many to list, so ties through them were not searched")
               | sumsTruncated ]
        , inStats = MkInstantStats {isActs = 1, isInstants = length runs, isTies = tieHits, isGaps = gapHits}
        }

-- | The sums by which a deadline can fall from the instant an act is done:
-- the act's own offsets (and none) plus what follows it, one sum from each
-- path of later acts ('pathPools'). A chain matters because an act is never
-- tried past the earliest live deadline, and the deadline the first act
-- starts is that one: a later act's tie is in reach only if the first act was
-- done early enough, so the sum of both offsets is a boundary of the first
-- act's instants. An act that starts no deadline adds no such boundary: what
-- it leaves behind is a lower bound on the clock, so trying it early reaches
-- everything trying it later does (the offset 0 stays bare, for a deadline
-- fixed in absolute time that only its successor holds).
chainOffsets :: [Rational] -> [Rational] -> [Rational]
chainOffsets own following = nubOrd (own <> [ o + x | o <- own, o > 0, x <- following ])

-- | The instants at which a deadline falls on a fixed one: @f - y@ for a
-- fixed instant @f@ and a sum @y@, inside the window.
tiesOf :: (Rational -> Bool) -> [Rational] -> [Rational] -> [Rational]
tiesOf inRange fixeds sums = nubOrd [ x | f <- fixeds, y <- sums, let x = f - y, inRange x ]

-- | An obligation in force at some position, by what identifies it across
-- positions (its place in the contract, its bearer, its modal, its action,
-- and which of several such it is), with an instant it holds.
data Held = MkHeld
  { heldNorm :: !LiveNorm
  , heldNth  :: !Int
  , heldKind :: !HeldKind
  , heldAt   :: !Rational
  }

data HeldKind = HeldDeadline | HeldOpening
  deriving stock (Eq)

sameHeld :: Held -> Held -> Bool
sameHeld a b = a.heldKind == b.heldKind && a.heldNth == b.heldNth && sameNorm a.heldNorm b.heldNorm

-- | The same obligation, wherever it is met: its place in the contract, its
-- modal and its action, and its bearer. The bearer is printed as the party's
-- value once it has been forced and as the expression before, so a party
-- forced between two positions is the same bearer; two printed alike in one
-- form are the same, and one in each form is not told apart.
sameNorm :: LiveNorm -> LiveNorm -> Bool
sameNorm x y = (x.lnSite, x.lnModal, x.lnAction) == (y.lnSite, y.lnModal, y.lnAction) && sameBearer x.lnBearer y.lnBearer
  where
    sameBearer (KnownParty p) (KnownParty q) = p == q
    sameBearer (UnforcedParty p) (UnforcedParty q) = p == q
    sameBearer _ _ = True

-- | The instants a position holds in absolute time, as far as they are
-- known: its live deadlines and the openings of its windows, each with the
-- obligation it belongs to.
thresholdsOf :: Explorer -> Position -> IO [Held]
thresholdsOf ex pos = do
  deadlines <- liveDeadlines ex pos
  openings <- for (maybe [] liveObligations pos.posResidual) (openingOf pos.posClock)
  let norms = [ renderLive pos.posContext raw | (raw, _) <- deadlines ]
      nth i n = length [ () | n' <- take i norms, sameNorm n' n ]
  pure
    [ MkHeld {heldNorm = n, heldNth = nth i n, heldKind = kind, heldAt = at}
    | (i, n, (_, due), open) <- zip4' [0 :: Int ..] norms deadlines (openings <> repeat Nothing)
    , (kind, Just (Right at)) <- [(HeldDeadline, due), (HeldOpening, open)] ]
  where
    zip4' (a : as) (b : bs) (c' : cs) (d : ds) = (a, b, c', d) : zip4' as bs cs ds
    zip4' _ _ _ _ = []

-- | From the instants an act was tried at and what each position it led to
-- holds: the offsets by which it starts deadlines (they moved with the
-- instant) and the instants that were fixed (they did not), told apart FOR
-- EACH OBLIGATION across the probes. An obligation seen at one probe only, or
-- one whose instant did neither, may be either, and counts as both: that
-- costs an instant and never a tie. Matching by obligation and not by value
-- matters: two fixed deadlines a distance apart, seen at two probes that far
-- apart, look like one deadline that moved.
shiftOrStay :: [Held] -> [(Rational, [Held])] -> ([Rational], [Rational])
shiftOrStay existing seen = (nubOrd (concat offs), nubOrd (concat fixs))
  where
    firsts = dedupe [ th | (_, ths) <- seen, th <- ths ]
    dedupe = foldr (\ x acc -> x : filter (not . sameHeld x) acc) []
    (offs, fixs) = unzip (map one firsts)
    one th0 =
      let obs = [ (t, th.heldAt) | (t, ths) <- seen, th <- ths, sameHeld th th0 ]
          values = nubOrd (map snd obs)
          shifts = nubOrd [ v - t | (t, v) <- obs ]
          unchanged = [ e.heldAt | e <- existing, sameHeld e th0, [e.heldAt] == values ]
          -- what the residual itself says of a deadline seen at one probe only:
          -- one counting from now moves with the act, one anchored does not
          written = case th0.heldNorm.lnDue of
            UnforcedDeadline _ Nothing  -> Just True
            UnforcedDeadline _ (Just _) -> Just False
            _                           -> Nothing
      in case (unchanged, length obs >= 2, values, shifts) of
           -- the act left it where it was. The position already held it (it is in
           -- 'wnFixed' for this act's own ties), and it is not new with the act, so
           -- it is not carried upstream: a deadline an EARLIER act started is held
           -- by every later position and moves with that earlier act, which is not
           -- to be told from a fixed one by looking at the later act's probes alone
           (_ : _, _, _, _)    -> ([], [])
           (_, True, [_], _)   -> ([], values)
           (_, True, _, [_])   -> (shifts, [])
           _ | th0.heldKind == HeldDeadline, written == Just True  -> (shifts, [])
             | th0.heldKind == HeldDeadline, written == Just False -> ([], values)
           _                   -> (shifts, values)

----------------------------------------------------------------------------
-- Exploring
----------------------------------------------------------------------------

data Node = MkNode
  { ndId     :: !Int
  , ndDepth  :: !Int
  , ndEvents :: ![Expr Resolved]
  , ndPos    :: !Position
  , ndRe     :: !Bool
    -- ^ this position reached a state that was already known, at an EARLIER
    -- clock than the one explored from: it is explored again, for the acts
    -- and instants the later clock no longer allows. A key says nothing of
    -- how far the clock is from a deadline that is anchored in absolute time,
    -- so two positions with one key can differ in what is still possible; the
    -- earlier clock allows all the later one does
  }

-- | What one try of one candidate came to.
data Tried
  = TriedEdge !Text !EdgeKind !(Expr Resolved) !Position
    -- ^ taken: the label, the event appended, the position it led to
  | TriedPassed !Text !(Maybe Rational)
    -- ^ passed over; when the act came before its window opened, the
    -- instant it opens
  | TriedStats !InstantStats
    -- ^ how many instants one act was tried at, and why those
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
  , acInstants   :: !InstantStats
  , acBest       :: !(Map Int Rational)
    -- ^ per state, the earliest clock any position of it was queued at
  }

-- | What one exploration shares, ready to explore or, for a test, to look at
-- single positions through ('timeSignature', 'keyText', 'rigFor').
newExplorer :: ExploreOptions -> ReadSites -> Rig -> Start -> IO Explorer
newExplorer opts sites rig0 start = newExplorerWith Map.empty opts sites rig0 start

newExplorerWith :: Map Text (Set Rational, Set Rational) -> ExploreOptions -> ReadSites -> Rig -> Start -> IO Explorer
newExplorerWith hint opts sites rig0 start = do
  anchors <- newIORef Map.empty
  records <- newIORef []
  pure MkExplorer
    { exOptions = opts
    , exSites = sites
    , exRig = rig0 {rigModule = withoutDirectives rig0.rigModule}
    , exStart = start
    , exActionType = contractActionType rig0.rigEntityInfo start.stContract
    , exAnchors = anchors
    , exHint = hint
    , exRecords = records
    }

-- | Explore a contract from its outset. 'Left' when the outset itself
-- cannot be run.
explore :: ExploreOptions -> ReadSites -> Rig -> Start -> IO (Either Text Graph)
explore opts sites rig0 start = case opts.eoTime of
  Grid n | n <= 0 -> pure (Left "a grid needs a positive step")
  Grid _ -> fmap fst <$> once Map.empty
  Regions
    | opts.eoChains -> passes Map.empty (3 :: Int)
    | otherwise -> fmap fst <$> once Map.empty
  where
    once hint = do
      ex <- newExplorerWith hint opts sites rig0 start
      r <- exploreWith ex
      case r of
        Left e -> pure (Left e)
        Right g -> do
          records <- readIORef ex.exRecords
          let (pools, cut) = pathPools g records
              after = actPools g records pools
              missing = (if opts.eoChains then [] else chainsLeftOut after)
                <> [ MkUntriedNote "ties through chains of acts"
                       "the sums of offsets along the paths of acts were too many to list (20000 for one state), so the ties through the ones left out were not searched" 1
                   | cut ]
          pure (Right (g {gCoverage = g.gCoverage {cvUntried = g.gCoverage.cvUntried <> missing}}, hintsOf after))
    -- The ties an act is tried at depend on the offsets of the acts that can
    -- follow it, which a state only learns by exploring them. So with
    -- 'eoChains' the contract is explored again with what the last pass
    -- learned, until a pass learns nothing new; a contract whose offsets keep
    -- growing says so.
    passes hint left = do
      r <- once hint
      case r of
        Left e -> pure (Left e)
        Right (g, learned)
          | all (\ (l, (o, f)) -> maybe False (\ (o', f') -> o `Set.isSubsetOf` o' && f `Set.isSubsetOf` f') (Map.lookup l hint)) (Map.toList learned)
              -> pure (Right g)
          | left <= 1 -> pure (Right g
              { gCoverage = g.gCoverage
                  { cvUntried = g.gCoverage.cvUntried <>
                      [ MkUntriedNote "ties through chains of acts"
                          "the offsets by which acts start deadlines were still growing after three passes, so the last pass searched ties with what the one before had learned" 1 ] } })
          | otherwise -> passes (Map.unionWith (\ (a, b) (c, d) -> (a <> c, b <> d)) hint learned) (left - 1)

-- | For each state, what the acts that start there and after it were found to
-- do: the sums of the offsets by which they start deadlines along each path of
-- acts (every act on the path contributing its offset or nothing, and the
-- empty path 0), and the instants fixed in absolute time their positions
-- held. These are paths in the graph that was explored, not every sum of
-- every offset: an offset repeats only where the graph loops. The sums are
-- kept up to the furthest fixed instant and to 20000 values a state; the
-- second component says that more were left out.
pathPools :: Graph -> [ActRecord] -> (Map Int (Set Rational, Set Rational), Bool)
pathPools g records = go start (0 :: Int) False
  where
    bound = maximum (0 : [ f - r.arClock | r <- records, f <- r.arFixed <> r.arLearnedFixed ])
    leads = Map.fromListWith (<>) [ ((t.tnFrom, t.tnLabel), [t.tnTo]) | t <- g.gTransitions, t.tnFrom /= t.tnTo ]
    recordsAt = Map.fromListWith (<>) [ (r.arState, [r]) | r <- records ]
    start = Map.fromList [ (st.snId, (Set.singleton 0, Set.empty)) | st <- g.gStates ]
    after pools r = followPool pools (Map.findWithDefault [] (r.arState, r.arLabel) leads)
    step pools = Map.mapWithKey (\ st _ -> contribution pools st) pools
    contribution pools st =
      let rs = Map.findWithDefault [] st recordsAt
          parts = [ (Set.fromList [ y | o <- 0 : r.arOffsets, x <- Set.toList xs, let y = o + x, y <= bound ]
                    , Set.fromList r.arLearnedFixed <> fs)
                  | r <- rs, let (xs, fs) = after pools r ]
      in (Set.insert 0 (foldMap fst parts), foldMap snd parts)
    go pools n cut
      | pools' == pools = (pools, cut)
      | n > 200 = (pools, True)
      | otherwise = go capped (n + 1) (cut || trimmed)
      where
        pools' = step pools
        trimmed = any ((> 20000) . Set.size . fst) (Map.elems pools')
        capped = Map.map (\ (xs, fs) -> (Set.fromList (take 20000 (Set.toAscList xs)), fs)) pools'

-- | For each act in each state, what the acts that can FOLLOW it were found to
-- do: the paths and fixed instants of every state its edges lead to. Not the
-- other acts of the same state, which are not after it.
actPools :: Graph -> [ActRecord] -> Map Int (Set Rational, Set Rational) -> [(ActRecord, (Set Rational, Set Rational))]
actPools g records pools = [ (r, pool r) | r <- records ]
  where
    leads = Map.fromListWith (<>) [ ((t.tnFrom, t.tnLabel), [t.tnTo]) | t <- g.gTransitions, t.tnFrom /= t.tnTo ]
    pool r = followPool pools (Map.findWithDefault [] (r.arState, r.arLabel) leads)

-- | What the states an act leads to hold, taken together.
followPool :: Map Int (Set Rational, Set Rational) -> [Int] -> (Set Rational, Set Rational)
followPool pools succs = foldMap (\ st -> Map.findWithDefault (Set.empty, Set.empty) st pools) (nubOrd succs)

-- | What the acts that can follow each act were found to do, per act label.
hintsOf :: [(ActRecord, (Set Rational, Set Rational))] -> Map Text (Set Rational, Set Rational)
hintsOf after = Map.fromListWith (\ (a, b) (c, d) -> (a <> c, b <> d)) [ (r.arLabel, p) | (r, p) <- after ]

-- | The acts whose instants a tie through a chain of acts would have added to,
-- as an untried entry (none when 'eoChains' searched them), judged with what
-- the acts that can follow each one do.
chainsLeftOut :: [(ActRecord, (Set Rational, Set Rational))] -> [UntriedNote]
chainsLeftOut after =
  [ MkUntriedNote
      ("ties through chains of acts, for " <> Text.intercalate ", " (take 3 acts) <> (if length acts > 3 then ", …" else ""))
      ("an act that starts a deadline sets the limit the next act's tie must be inside, so the instants "
         <> Text.intercalate ", " (map prettyRatio (take 4 instants))
         <> (if length instants > 4 then ", …" else "")
         <> " could put a tie in reach and were not tried; --chains tries them, at the cost of a larger graph")
      (length short)
  | not (null short) ]
  where
    perRecord =
      [ (r.arLabel, [ t | t <- ties, isWhole t, Set.notMember t r.arTried ])
      | (r, (sums, fixed)) <- after
      , let inRange t' = t' >= r.arClock && maybe True (t' <=) r.arLimit
            fixeds = nubOrd (r.arFixed <> r.arLearnedFixed <> Set.toList fixed <> maybeToList r.arLimit)
            ties = tiesOf inRange fixeds (chainOffsets (0 : r.arOffsets) (Set.toList sums)) ]
    short = [ (l, ts) | (l, ts) <- perRecord, not (null ts) ]
    acts = nubOrd (map fst short)
    instants = nubOrd (sort (concatMap snd short))

-- | One exploration, with the hint its 'Explorer' carries.
exploreWith :: Explorer -> IO (Either Text Graph)
exploreWith ex = do
  let opts = ex.exOptions
      (rig, tr) = rigFor ex []
  mpos <- position rig tr
  case mpos of
    Nothing -> pure (Left "the contract produced no result at its outset")
    Just pos0 -> case pos0.posResidual of
      Nothing -> pure (Left ("the contract could not be run at its outset: " <> standingText pos0.posResult))
      Just _
        | Just u <- opts.eoUntil, pos0.posClock > u ->
            pure (Left ("--until " <> prettyRatio u <> " is before the outset at " <> prettyRatio pos0.posClock
              <> ", so no act could fire and every property would hold of the one state"))
      Just _ -> do
        (key0, notes0) <- stateKey ex pos0
        let node0 = MkNode {ndId = 0, ndDepth = 0, ndEvents = [], ndPos = pos0, ndRe = False}
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
              , acInstants = mempty
              , acBest = Map.singleton 0 pos0.posClock
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
        if node.ndRe then loop ex acc' else do
          let fired = not (null [ () | TriedEdge {} <- tried ])
              blocked = not (null [ () | t <- tried, isBlocked t ])
              acc'' = if fired || blocked then acc' else terminal node acc'
              -- a pass-over counts once per state and act, and only if no
              -- instant took the act
              firedLabels = Set.fromList [ l | TriedEdge l _ _ _ <- tried ]
              passed = Set.fromList [ l | TriedPassed l _ <- tried, not (Set.member l firedLabels) ]
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
      Just j -> do
        let acc1 = addEdge (noteKey notes acc) (Just event) (MkTransition node.ndId label j kind)
            earlier = maybe False (pos'.posClock <) (Map.lookup j acc.acBest)
        pure if earlier && node.ndDepth + 1 < ex.exOptions.eoMaxDepth
          then acc1
            { acBest = Map.insert j pos'.posClock acc.acBest
            , acQueue = acc.acQueue :|> MkNode {ndId = j, ndDepth = node.ndDepth + 1, ndEvents = node.ndEvents <> [event], ndPos = pos', ndRe = True} }
          else acc1
      Nothing
        | Map.size acc.acSeen >= ex.exOptions.eoMaxStates ->
            pure acc {acStatesCut = acc.acStatesCut + 1}
        | otherwise -> do
            let j = acc.acNext
                events = node.ndEvents <> [event]
                new = MkNode {ndId = j, ndDepth = node.ndDepth + 1, ndEvents = events, ndPos = pos', ndRe = False}
            pure $ addEdge (noteKey notes acc
              { acSeen = Map.insert key j acc.acSeen
              , acBest = Map.insert j pos'.posClock acc.acBest
              , acNodes = stateNode j (node.ndDepth + 1) events key pos' : acc.acNodes
              , acNext = j + 1
              , acQueue = acc.acQueue :|> new
              }) (Just event) (MkTransition node.ndId label j kind)
  TriedBeyond -> pure acc {acBeyond = acc.acBeyond + 1}
  TriedStats st -> pure acc {acInstants = acc.acInstants <> st}
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
  , gKept = Map.map (|| ex.exSites.rsTimeScoped) ex.exSites.rsCells
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
      , cvInstants = acc.acInstants
      }
  }

timeText :: ExploreOptions -> Text
timeText opts = Text.concat
  [ case opts.eoTime of
      Regions -> "time by regions (whole instants: the last event, the deadline, window openings, the ties between a deadline an act starts and one already live, and one between each; the clock is not in the state)"
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
      offeredTicks = [ d | MkCandidate {cdKind = TickPast d _} <- cands ]
      -- the stamp that reveals deadline d: one unit past it, or, on a grid,
      -- the next point of the grid past it
      -- (never earlier than the clock: a deadline the clock has already passed
      -- is revealed by an event at the clock, and a tick that ran time
      -- backwards reached positions no run of the contract reaches)
      tickTime d = max pos.posClock case ex.exOptions.eoTime of
        Regions -> tickPast known d
        Grid n  -> (fromInteger (floor (d / n)) + 1) * n
      retimed d cand = cand {cdHypothetical = Right (Tick (tickTime d))}
      run label kind cand = do
        (outcome, mpos) <- tryCandidateFrom rig tr pos cand
        pure case outcome.ocVerdict of
          Untried why  -> TriedUntried label why
          PassedOver r -> TriedPassed label (case r of TooEarly open -> Just open; _ -> Nothing)
          _ -> case (cand.cdHypothetical, mpos) of
            (Right hyp, Just pos') | isJust pos'.posResidual -> TriedEdge label kind (hypotheticalExpr hyp) pos'
            _ -> TriedUntried label "the replay produced no position"
      tick label d cand = case cand.cdHypothetical of
        Right (Tick t) | Just u <- ex.exOptions.eoUntil, t > u -> pure [TriedBeyond]
        Right (Tick t) -> do
          r <- run label EdgeTick cand
          case r of
            TriedEdge _ _ _ pos' | Regions <- ex.exOptions.eoTime -> tickRecord label d t pos'
            _ -> pure ()
          pure [r]
        _ -> pure <$> run label EdgeTick cand
      -- A deadline started by a LAPSE (a LEST that arms a cure) is not started
      -- by an act, so the act that led here never saw it move; it is read here,
      -- at the tick that revealed the lapse, as an act's successor is read, and
      -- kept as the offsets (relative to the deadline that lapsed, which the
      -- act's own offset already reaches) and fixed instants that the paths
      -- through this state carry ('pathPools')
      tickRecord label d t pos' = do
        before <- thresholdsOf ex pos
        after <- thresholdsOf ex pos'
        let new = [ h | h <- after, h.heldKind == HeldDeadline, not (any (sameHeld h) before) ]
            anchoredH h = case h.heldNorm.lnDue of
              UnforcedDeadline _ (Just _) -> True
              _                           -> False
            movesH h = case h.heldNorm.lnDue of
              UnforcedDeadline _ (Just _) -> False
              _                           -> True
        modifyIORef' ex.exRecords (MkActRecord
          { arState = node.ndId, arLabel = label, arClock = t, arLimit = Just t
          , arTried = Set.singleton t, arFixed = []
          , arOffsets = [ h.heldAt - d | h <- new, movesH h ]
          , arLearnedFixed = [ h.heldAt | h <- new, anchoredH h || not (movesH h) ] } :)
  moves <- fmap concat $ for cands \ cand -> case cand.cdKind of
    TickPast d _ -> let cand' = retimed d cand in tick (tickLabel cand' d) d cand'
    NoTick live -> case snd <$> lookup live lives of
      Just (Just (Right d))
        | d `notElem` offeredTicks ->
            let cand' = cand {cdKind = TickPast d [live], cdHypothetical = Right (Tick (tickTime d))}
            in tick (tickLabel cand' d) d cand'
        | otherwise -> pure []
      _ -> pure [TriedUntried ("time runs out on " <> live.lnAction) (either id (const "") cand.cdHypothetical)]
    ActBy live -> case lookup live lives of
      Nothing -> pure [TriedUntried live.lnAction "the obligation could not be found in the residual again"]
      Just (raw, _) -> do
        mparty <- partyOf raw
        acts <- actsOf ex pos raw cand
        case (mparty, acts) of
          (Nothing, _) -> pure [TriedUntried live.lnAction "the party was never forced and could not be read back"]
          (Just party, Left why) -> pure [TriedUntried (obligationText party raw) why]
          (Just party, Right (actions, refusals)) -> do
            win <- windowOf ex node pos "" live lives raw
            ran <- for actions \ a -> do
              let label = actLabel party a
                  probe t = run label EdgeAct cand
                    { cdHypothetical = Right Act {hyParty = party, hyAction = a, hyAt = t}
                    , cdBound = Nothing }
              ins <- instantsFor ex win {wnLabel = label} probe
              pure (map snd ins.inRuns <> [TriedStats ins.inStats]
                      <> [ TriedUntried (label <> " " <> what) why | (what, why) <- ins.inCuts ])
            pure (concat ran <> map (TriedRefused . refusalFor party raw) refusals)
  grid <- offGrid ex pos
  pure (moves <> grid)
  where
    tickLabel cand d = case cand.cdHypothetical of
      Right (Tick t) -> "time passes the deadline " <> prettyRatio d <> " (WAITUNTIL " <> prettyRatio t <> ")"
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

-- | What the instants of one act are chosen from, at one position.
windowOf
  :: Explorer -> Node -> Position -> Text -> LiveNorm
  -> [(LiveNorm, (RawObligation NF, Maybe (Either Text Rational)))]
  -> RawObligation NF -> IO Window
windowOf ex node pos label live lives own = do
  let c = pos.posClock
      ahead = [ d | (_, (_, Just (Right d))) <- lives, d >= c ]
      limit = case (ahead, ex.exOptions.eoUntil) of
        ([], Nothing) -> Nothing
        ([], Just u)  -> Just u
        (ds, Nothing) -> Just (minimum ds)
        (ds, Just u)  -> Just (min u (minimum ds))
      others = [ (raw, due) | (l, (raw, due)) <- lives, l /= live ]
  held <- thresholdsOf ex pos
  ownOpen <- openingOf c own
  otherOpens <- for others \ (raw, _) -> openingOf c raw
  let opens = [ o | Just (Right o) <- otherOpens ]
  pure MkWindow
    { wnState = node.ndId
    , wnLabel = label
    , wnClock = c
    , wnLimit = limit
    , wnOpen = case ownOpen of
        Just (Right o) -> Just o
        _              -> Nothing
    , wnFixed = [ d | (_, Just (Right d)) <- others ] <> opens
    , wnOtherOpens = filter (> c) opens
    , wnHeld = held
    }

-- | On a grid, a position whose clock, deadline or window opening is not a
-- multiple of the step cannot be explored by acts at the grid's points alone:
-- the soundness condition of @--grid@ is checked here, not assumed.
offGrid :: Explorer -> Position -> IO [Tried]
offGrid ex pos = case ex.exOptions.eoTime of
  Regions -> pure []
  Grid n -> do
    held <- map (.heldAt) <$> thresholdsOf ex pos
    let off = [ x | x <- pos.posClock : held, denominator (x / n) /= 1 ]
    pure [ TriedUntried ("acts between the points of the grid of " <> prettyRatio n)
             ("the clock, a deadline or a window opening (" <> prettyRatio (minimum off) <> ") is off the grid of " <> prettyRatio n)
         | not (null off) ]

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
  , instantsClause cv.cvInstants
  ])
  where
    -- what the scheme tried, after everything else: an account, not a
    -- verdict (what it could not try is among the untried above)
    instantsClause st
      | st.isActs == 0 = ""
      | otherwise = "instants: " <> count st.isActs "act" <> " tried at " <> count st.isInstants "instant"
          <> (if st.isTies + st.isGaps > 0 then " (" <> count st.isTies "tie" <> ", " <> count st.isGaps "gap" <> ")" else "")
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
  , "instants" .= Aeson.object
      [ "acts" .= cv.cvInstants.isActs
      , "instants" .= cv.cvInstants.isInstants
      , "ties" .= cv.cvInstants.isTies
      , "gaps" .= cv.cvInstants.isGaps
      ]
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
