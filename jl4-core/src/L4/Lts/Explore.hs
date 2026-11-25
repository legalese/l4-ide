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
-- * the answer each rule with no inputs that reads a ledger, of the module
--   or of one it imports, was forced to in this run, if it was (an imported
--   one in the replay's own copy, 'freshHeap'): the evaluator keeps a rule's first
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
-- By default an act fires at a choice of WHOLE instants (§4.5, T2: contract
-- time is discrete): the instant of the last event, the earliest live deadline
-- exactly, the instants where a window opens, the instants at which a
-- deadline some chain of acts would start falls on one fixed in absolute
-- time (a /tie/), and one instant between each of those. The clock where the
-- position already stands is tried too, and it is a fraction after a start
-- such as @AT 0.5@ or after time passes a deadline that is one; @--grid N@
-- tries the multiples of N instead. See 'instantsFor'. An act is never fired
-- past a live deadline: the machine
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
  , positionAlong
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
import Data.Char (isDigit)
import Data.Ratio (denominator)
import qualified Data.Sequence as Seq
import Data.Sequence (Seq (..))
import qualified Optics
import Control.Exception (handle, throwIO)

import L4.Annotation (emptyAnno, getAnno)
import L4.Parser.SrcSpan (prettySrcRange)
import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..), Provenance (..))
import L4.Evaluate.ValueLazy hiding (Blame)
import L4.EvaluateLazy.Machine (anchorInstant)
import L4.EvaluateLazy
  ( EntityInfo
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithDeonticLog
  , prettyEvalException
  , prettyReductionOutcome
  )
import L4.EvaluateLazy.DeonticStep (NormKey (..))
import L4.EvaluateLazy.Exceptions (LimitStopped (..), isLimitStop)
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
    -- ^ the @AT@ as written, for the reader
  , stClock    :: !(Maybe Rational)
    -- ^ the clock it is, once read ('explore' reads it): the replay is handed
    -- this as a literal, so a start below 0, or one that is an expression
    -- (@AT (10 + 5)@, @AT (DATE_SERIAL ...)@), is where the clock begins
  }

-- | What the replay is told the start is: the clock when it is read, else the
-- @AT@ as written.
startExpr :: Start -> Expr Resolved
startExpr s = maybe s.stAt (Lit emptyAnno . NumericLit emptyAnno) s.stClock

-- | One start per distinct contract and @AT@ among the module's @#TRACE@s,
-- in source order. The traces' events are not replayed: from the outset
-- they are one path among those the exploration walks.
startsOf :: Module Resolved -> [Start]
startsOf m = nubOrdOn (\ s -> (s.stName, prettyLayout s.stAt))
  [ MkStart {stName = prettyLayout tr.trContract, stContract = tr.trContract, stAt = tr.trStart, stClock = Nothing}
  | tr <- tracesOf m ]

-- | A rule with no inputs, at this @AT@: at the top level or under a @§@
-- heading, found as 'L4.Lts.List.freshTrace' finds it for @l4 lts@
-- ('ruleNamed'), since a contract that is explored is usually written in
-- sections.
startNamed :: Module Resolved -> Text -> Rational -> Either Text Start
startNamed m wanted at = do
  contract <- ruleNamed m wanted
  Right MkStart
    { stName = wanted
    , stContract = contract
    , stAt = Lit emptyAnno (NumericLit emptyAnno at)
    , stClock = Just at
    }

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
    -- ^ whole instants where something can change, and the clock where the
    -- position stands, chosen by 'instantsFor'; the clock is not in the state
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
    -- ^ the rules with no inputs whose answer depends on a ledger read,
    -- directly or through another rule: the main module's, and those of the
    -- modules it imports that it reaches by name ('reachableRules')
  , rsRunHeap    :: !(Set Unique)
    -- ^ the imported rules, of any inputs, that read a ledger directly or
    -- through another rule: every replay has its own copy of them
    -- ('freshHeap'), as it has its own of the main module's rules
  , rsReads      :: !ModuleReads
    -- ^ what a deadline is not worked out through ('Closed'), read off the
    -- module and the modules it imports ('moduleReads')
  }

-- | The read sites of the module explored and of the modules it imports.
-- A ledger-reading constant is keyed by its kept answer wherever it is
-- defined: in the module, or in a module it imports and reaches by name,
-- however many imports away. Since review of smucclaw/l4-ide#1107 the
-- imported rules count when 'readers' follows a call. Until a later round of
-- that review, on unstable too, an imported constant was not keyed at all,
-- and an imported module's heap was one for every replay, so a constant that
-- one replay had forced kept that answer in the next ('freshHeap').
readSitesOf :: Module Resolved -> [Module Resolved] -> ReadSites
readSitesOf main imported = MkReadSites
  { rsCells = Map.fromListWith (||)
      [ (s, mode == RecallAll) | ReadCell _ _ _ mode (Lit _ (StringLit _ s)) <- everyExpr ]
  , rsTimeScoped = any scoped (concatMap (Optics.toListOf (Optics.gplate @Resolved)) (main : imported))
  , rsLedgerCafs = Map.fromList
      [ (u, nameToText n)
      | (Def u n, [], _) <- rules
      , Set.member u readers ]
  , rsRunHeap = Set.fromList
      [ u | (name, _, _) <- rules, let u = getUnique name, Set.member u readers, not (Set.member u mainRules) ]
  , rsReads = moduleReads main imported
  }
  where
    everyExpr = concatMap exprsOf (main : imported)
    -- every name in the modules, however it is spelt, as 'readers' below
    scoped r = getUnique r `elem` [TypeCheck.evalAsOfSystemTimeUnique, TypeCheck.evalUnderValidTimeUnique]
    MkModule _ _ mainSection = main
    mainRules = Set.fromList [ getUnique name | MkDecide _ _ (MkAppForm _ name _ _) _ <- decidesOf mainSection ]
    -- the rules 'readers' follows a call into: the module's, and those of
    -- its imports that it reaches by name, each with the names it mentions
    rules = reachableRules main imported
    allDecides = [ (name, body, refsOf body) | (name, _, body) <- rules ]
    -- the least set of the module's rules that read a ledger, directly or
    -- by naming one that does, however it is spelt ('namesIn', every name
    -- at every node). Until review of smucclaw/l4-ide#1107 only variables
    -- and positional calls counted, on unstable too, so a constant that
    -- reached a ledger reader through WITH, as a genitive, or through a
    -- wrapper of either was not keyed, and two positions that differed only
    -- in its kept answer were one state.
    readers = fixpoint (Set.fromList [ getUnique name | (name, body, _) <- allDecides, readsDirectly body ])
    readsDirectly body = not (null [ () | ReadCell {} <- subExprsOf body ])
    refsOf body = Set.fromList (map getUnique (namesIn body))
    fixpoint s =
      let s' = s <> Set.fromList [ getUnique name | (name, _, refs) <- allDecides, not (Set.disjoint refs s) ]
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
  , gRunHeap     :: !(Set Unique)
    -- ^ the imported rules each replay has its own copy of ('rsRunHeap'),
    -- which 'replayPath' copies too
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
  , exClosed     :: !Closed
    -- ^ how a deadline written as a name or an expression is worked out
    -- ('exploreClosed'): WhatIf's reader, cached for the exploration
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
  let directive = Contract emptyAnno ex.exStart.stContract (startExpr ex.exStart) events
      MkModule a uri (MkSection sa sn saka sg decls) = ex.exRig.rigModule
      m' = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno directive]))
  in ( ex.exRig {rigModule = m'}
     , MkTrace {trDirective = directive, trContract = ex.exStart.stContract, trStart = startExpr ex.exStart, trEvents = events} )

-- | The rig one replay runs on: 'rigFor''s, with the replay's own copy of
-- the imported rules that read a ledger ('freshHeap'). Every replay site
-- takes one, so a replay starts as a run of the path alone starts.
replayRig :: Explorer -> Rig -> IO Rig
replayRig ex rig = (\ env -> rig {rigEnv = env}) <$> freshHeap ex.exSites.rsRunHeap rig.rigEnv

-- | The imports' heap with its own copy of these rules ('rsRunHeap'), each
-- unforced, and each closing over the copies of the others.
--
-- The evaluator gives each directive a fresh heap of the module's own rules
-- ('L4.EvaluateLazy.forEachDirectiveFreshHeap'), so a ledger-reading
-- constant of the module is forced afresh by every replay. The imports' heap
-- is built once and shared: forced in one replay, an imported constant kept
-- that answer in the next whenever the clock was fixed (the evaluator
-- re-serves a ledger read while the temporal context is unchanged), and its
-- answer was never part of the state's key either. A file that imported a
-- ledger-reading constant then explored to a graph that no run of its paths
-- gives (found in review of smucclaw/l4-ide#1107, the same on unstable): two
-- positions that differed only in the constant's kept answer were one state.
--
-- Only rules that read a ledger, directly or by naming one that does, are
-- copied: a rule that names none of them cannot reach a copy by name, so it
-- may stay shared. A copy starts unforced, as the rule was before any
-- replay; a function already forced keeps its closure, over the copies. A
-- value forced before the exploration began, which is not a function, is
-- left shared, since no replay forced it (decided by Claude 2026-11-25,
-- pending Meng's review).
freshHeap :: Set Unique -> Environment -> IO Environment
freshHeap run env
  | Set.null run = pure env
  | otherwise = do
      copies <- for (Map.toList (Map.restrictKeys env run)) \ (u, rf) -> readIORef rf.pointer >>= \ case
        WHNF v | not (isClosure v) -> pure Nothing
        t -> Just . (u,) . MkReference rf.address <$> newIORef t
      let fresh = Map.fromList (catMaybes copies)
          closeOver = \ case
            Unevaluated _ e env'          -> Unevaluated Set.empty e (fresh <> env')
            WHNFWhen _ _ e env'           -> Unevaluated Set.empty e (fresh <> env')
            WHNF (ValClosure g e env')    -> WHNF (ValClosure g e (fresh <> env'))
            other                         -> other
      for_ (Map.elems fresh) \ rf -> modifyIORef' rf.pointer closeOver
      pure (fresh <> env)
  where
    isClosure = \ case
      ValClosure{} -> True
      _            -> False

stateKey :: Explorer -> Position -> IO (StateKey, KeyNotes)
stateKey ex pos = do
  (residual, merged) <- case pos.posResidual of
    Just v  -> canonResidual pos.posReplayScope v
    Nothing -> pure (standingText pos.posResult, [])
  (cells, dropped, unspellable) <- projectLedger ex.exSites pos.posResult.ledger
  -- the heap this directive forced, as the obligations in force closed over it
  let heaps = [ raw.roEnv | raw <- maybe [] liveObligations pos.posResidual ]
  -- an obligation of an imported rule that reads no ledger closes over the
  -- shared heap, whose ledger readers no replay forces ('freshHeap'): the
  -- answer is the replay's own copy, so a forced one is read first
  cafs <- for (Map.toList ex.exSites.rsLedgerCafs) \ (u, name) -> (name,) <$> do
    thunks <- traverse (readIORef . (.pointer)) (mapMaybe (Map.lookup u) heaps)
    let forced = \ case
          WHNF v           -> Just v
          WHNFWhen _ v _ _ -> Just v
          Unevaluated{}    -> Nothing
    case (mapMaybe forced thunks, thunks) of
      (v : _, _)  -> answerText v
      ([], _ : _) -> pure ("not yet asked", True)
      ([], [])    -> pure ("no obligation in force reads it", True)
  deadlines <- liveDeadlines ex pos
  openings <- for (obligationsOf pos) (openingOf pos.posClock)
  let (dueRanks, openRanks) = ranksOf [ d | (_, d) <- deadlines ] openings
      clock = case ex.exOptions.eoTime of
        Regions -> ClockDropped [ pos.posClock > d | (_, Just (Right d)) <- deadlines ] dueRanks openRanks
        Grid _  -> ClockKept pos.posClock
      -- a breached position holds on to what it still waits on: two that blame
      -- the same party are not one state when one has a sibling pending
      waiting = waitingLines True pos [ d | (_, d) <- deadlines ] openings
  pure ( MkStateKey {skResidual = residual <> waitingText waiting, skLedger = cells, skCafs = map (second fst) cafs, skClock = clock}
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
  openings <- for (obligationsOf pos) (openingOf pos.posClock)
  let (dueRanks, openRanks) = ranksOf [ d | (_, d) <- deadlines ] openings
  pure (Text.unlines
    [ residual <> waitingText (waitingLines False pos [ d | (_, d) <- deadlines ] openings)
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

-- | What a BREACHED position still waits on, one line each, in a fixed order:
-- who, what, and (when the key is to keep it) how long is left. The line has to
-- say which obligations are still standing and nothing about the ones that are
-- gone; the explorer does not know what the right side's continuation, armed
-- after the breach, holds, and says that too ('posUnread'), so that a state
-- with one waiting is not taken for a state with none.
waitingLines :: Bool -> Position -> [Maybe (Either Text Rational)] -> [Maybe (Either Text Rational)] -> [Text]
waitingLines withTimes pos dues opens = sort (carried <> unread)
  where
    own = length (maybe [] liveObligations pos.posResidual)
    carried =
      [ Text.unwords (catMaybes
          [ Just (bearerWord live.lnBearer), Just (modalWord' live.lnModal), Just live.lnAction
          , if withTimes then within due else Nothing
          , if withTimes then opening open else Nothing ])
      | (p, due, open) <- zip3 pos.posPending (drop own dues <> repeat Nothing) (drop own opens <> repeat Nothing)
      , let live = renderLive pos.posContext p.pdRaw ]
    unread = [ unreadLine k | k <- pos.posUnread ]
    within = \ case
      Just (Right d) -> Just ("WITHIN " <> prettyRatio (d - pos.posClock))
      Just (Left _)  -> Just "WITHIN (not known here)"
      Nothing        -> Nothing
    opening = \ case
      Just (Right o) | o > pos.posClock -> Just ("AFTER " <> prettyRatio (o - pos.posClock))
      _                                 -> Nothing

waitingText :: [Text] -> Text
waitingText [] = ""
waitingText ls = "\n  [still waiting on: " <> Text.intercalate "; " ls <> "]"

bearerWord :: Bearer -> Text
bearerWord = \ case
  KnownParty t    -> t
  UnforcedParty t -> t

modalWord' :: DeonticModal -> Text
modalWord' = \ case
  DMust    -> "MUST"
  DMay     -> "MAY"
  DMustNot -> "SHANT"
  DDo      -> "DO"

firstJust :: [Maybe a] -> Maybe a
firstJust = listToMaybe . catMaybes

-- | A norm the log shows waiting behind a breach that the explorer holds no
-- obligation for: who, what kind, and where in the source it is written
-- (the file's name and the range, not its path).
unreadLine :: NormKey -> Text
unreadLine k = Text.unwords
  [ "(unread)"
  , fromMaybe "(party not yet known)" (firstJust [k.nkBearerName, k.nkBearer, fmap (<> " (as written)") k.nkBearerSource])
  , modalWord' k.nkModal
  , case k.nkSite of
      Just r  -> "(at " <> prettySrcRange r <> ")"
      Nothing -> "(no location)"
  ]

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
-- Read by WhatIf's 'deadlineOf', through the exploration's 'Closed' reader,
-- which is the one 'candidatesWith' is given too, so a deadline known here is
-- one a tick is offered for, and the other way round.
liveDeadlines :: Explorer -> Position -> IO [(RawObligation NF, Maybe (Either Text Rational))]
liveDeadlines ex pos = for (obligationsOf pos) \ raw -> case raw.roDue of
  Left Nothing -> pure (raw, Nothing)
  _ -> (raw,) . Just <$> deadlineOf ex.exClosed pos raw

-- | WhatIf's 'Closed' reader for one exploration: a deadline written as a name
-- or an expression, and closed (@WITHIN `ten days`@, @WITHIN 5 PLUS 5@, an
-- @OF@ anchor the residual has not forced), is worked out by one @#EVAL@ in
-- the module ('evalInModule'), and the answer is kept for the rest of the
-- exploration under the expression's printed form and the names it refers
-- to. An evaluation stopped at a limit raises 'LimitStopped' rather than
-- answer: a deadline read as unknown would leave its tick out, and the graph
-- would be missing positions with nothing to say so. The 2026-11-21 budget
-- ruling had that for an anchor; that a stop working out a @WITHIN@ refuses
-- the exploration too is decided by Claude 2026-11-25, pending Meng's review
-- (@l4 lts@ lists the same stop as the reason, and exits 0). Any other
-- failure (a division by zero) is the reason the deadline is not known, and
-- the tick is listed as untried with it.
exploreClosed :: Rig -> ReadSites -> IORef (Map (Text, [Unique]) (Either Text (Value NF))) -> Closed
exploreClosed rig sites cache = (closedIn rig) {clEval = Just evalCached, clReads = sites.rsReads}
  where
    evalCached e = do
      let key = (prettyLayout e, map getUnique (namesIn e))
      known <- Map.lookup key <$> readIORef cache
      case known of
        Just v -> pure v
        Nothing -> do
          r <- evalInModule rig e
          case r of
            Just (ReducedErrored exc) | isLimitStop exc ->
              throwIO (LimitStopped ("working out a deadline: " <> Text.unwords (prettyEvalException exc)))
            _ -> do
              let v = outcomeValue r
              modifyIORef' cache (Map.insert key v)
              pure v

-- | One @#EVAL@ of a closed expression in the module, read as an instant: a
-- NUMBER as it is, a DATE by its serial (as the machine lowers an anchor).
evalInstantIn :: Rig -> Expr Resolved -> IO (Maybe Rational)
evalInstantIn rig e = do
  let MkModule a uri (MkSection sa sn saka sg decls) = withoutDirectives rig.rigModule
      m' = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno (LazyEval emptyAnno e)]))
  (_, results) <- execEvalModuleWithDeonticLog rig.rigConfig rig.rigEntityInfo rig.rigEnv m'
  pure case results of
    ((res, _) : _) | Reduction (Reduced (MkNF v)) <- res.result -> case v of
      ValNumber r -> Just r
      ValDate d   -> either (const Nothing) Just (anchorInstant (ValDate d))
      _           -> Nothing
    _ -> Nothing

-- | The start with its clock read. A literal @AT@ is its own clock; any
-- other is evaluated once, here, so that the replay is handed a number. A start
-- that is neither a number nor a date is refused: the explorer would otherwise
-- take it for 0 and explore a contract that had not begun where it says it did.
resolveStart :: Rig -> Start -> IO (Either Text Start)
resolveStart rig start = case start.stClock of
  Just _ -> pure (Right start)
  Nothing -> case start.stAt of
    Lit _ (NumericLit _ r) -> pure (Right start {stClock = Just r})
    e -> evalInstantIn rig e >>= \ case
      Just r  -> pure (Right start {stClock = Just r})
      Nothing -> pure (Left ("the start of the trace, `AT " <> prettyLayout e <> "`, is neither a number nor a date the explorer can read, so it cannot say where the clock begins"))

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
-- are tried, and the clock where the position stands (contract time is
-- discrete, T2; the clock is a fraction after a fractional start or after
-- time passes a fractional deadline).
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
              , "an instant it needs (" <> prettyRatio (minimum notWhole) <> ") is not a whole number, and by default only whole instants, and the clock where it stands, are tried; --grid N tries the multiples of N")
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
  openings <- for (obligationsOf pos) (openingOf pos.posClock)
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
  | TriedBeyond !Text
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
  , acPassedAt   :: !(Map Int (Set Text))
    -- ^ per state, the acts some visit passed over; a state is visited again
    -- when it is reached at an earlier clock ('ndRe'), and each tally below is
    -- kept per STATE so that a second visit adds only what the first did not
    -- find
  , acFiredAt    :: !(Map Int (Set Text))
    -- ^ per state, the acts some instant took: an act that was passed over at
    -- one clock and taken at another is not passed over
  , acBeyondAt   :: !(Map Int Int)
    -- ^ per state, how many of its ticks fall past the clock bound: the most
    -- any visit found (the same ticks are there at every clock, and the bound
    -- takes some of them according to where the clock is)
  , acDepthCutIds :: !(Set Int)
    -- ^ the states at the depth bound with something left to try
  , acCutKeys    :: !(Set StateKey)
    -- ^ the states the state bound kept out, each once: what the line says is a
    -- number of states, and a state reached by ten moves is one state
  , acUntriedAt  :: !(Map (Int, Text) [Text])
    -- ^ per state and label, the reasons its visits left ('mergeReasons'). Two
    -- reasons for one label in one visit (the label may name the action and
    -- not the party) are both kept; reasons that differ only in their numbers
    -- (a cap's shortfall, the fraction a window holds) are one, the larger
  , acRefused    :: ![Refusal]
  , acRefusedSeen :: !(Set (Int, (Text, Text, Maybe Text, Text)))
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
  cache <- newIORef Map.empty
  records <- newIORef []
  let rig = rig0 {rigModule = withoutDirectives rig0.rigModule}
  pure MkExplorer
    { exOptions = opts
    , exSites = sites
    , exRig = rig
    , exStart = start
    , exActionType = contractActionType rig0.rigEntityInfo start.stContract
    , exClosed = exploreClosed rig sites cache
    , exHint = hint
    , exRecords = records
    }

-- | Explore a contract from its outset. 'Left' when the outset itself
-- cannot be run, or when an evaluation the graph's instants depend on was
-- stopped at a limit ('LimitStopped'): a graph built without it could be
-- missing positions and still read as complete.
explore :: ExploreOptions -> ReadSites -> Rig -> Start -> IO (Either Text Graph)
explore opts sites rig0 start0 =
  handle (\ (LimitStopped why) -> pure (Left ("the evaluator stopped at a limit " <> why))) $
    resolveStart rig0 start0 >>= \ case
      Left e      -> pure (Left e)
      Right start -> exploreFrom opts sites rig0 start

-- | 'explore' from a start whose clock is read.
exploreFrom :: ExploreOptions -> ReadSites -> Rig -> Start -> IO (Either Text Graph)
exploreFrom opts sites rig0 start = case opts.eoTime of
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
         <> " could put a tie in reach and were not tried; --chains tries them, at the cost of a larger graph."
         <> " It does not reach a tie with an instant fixed in absolute time that the state does not count down"
         <> " (an OF anchor, running or not, or the cure a lapse will arm),"
         <> " nor one with the cure of a second lapse in a row, for an act done before the first lapse: --grid 1 tries every whole instant up to a deadline or --until")
      (Set.size (Set.fromList [ st | (st, _, _) <- short ]))
  | not (null short) ]
  where
    perRecord =
      [ (r.arState, r.arLabel, [ t | t <- ties, isWhole t, Set.notMember t r.arTried ])
      | (r, (sums, fixed)) <- after
      , let inRange t' = t' >= r.arClock && maybe True (t' <=) r.arLimit
            fixeds = nubOrd (r.arFixed <> r.arLearnedFixed <> Set.toList fixed <> maybeToList r.arLimit)
            ties = tiesOf inRange fixeds (chainOffsets (0 : r.arOffsets) (Set.toList sums)) ]
    short = [ r | r@(_, _, ts) <- perRecord, not (null ts) ]
    acts = nubOrd [ l | (_, l, _) <- short ]
    instants = nubOrd (sort (concatMap (\ (_, _, ts) -> ts) short))

-- | One exploration, with the hint its 'Explorer' carries.
exploreWith :: Explorer -> IO (Either Text Graph)
exploreWith ex = do
  let opts = ex.exOptions
      (rig, tr) = rigFor ex []
  mpos <- replayRig ex rig >>= \ rig' -> position rig' tr
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
              , acPassedAt = Map.empty
              , acFiredAt = Map.empty
              , acBeyondAt = Map.empty
              , acDepthCutIds = Set.empty
              , acCutKeys = Set.empty
              , acUntriedAt = Map.empty
              , acRefused = []
              , acRefusedSeen = Set.empty
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
-- 'StateNode''s 'snPath', or that path and one edge's event after it. Afresh
-- includes the imports: the replay has its own copy of the imported rules
-- that read a ledger, as the exploration's replays have ('gRunHeap').
replayPath :: Set Unique -> Rig -> Start -> [Expr Resolved] -> IO (Maybe Position)
replayPath run rig start events = do
  env <- freshHeap run rig.rigEnv
  let directive = Contract emptyAnno start.stContract (startExpr start) events
      MkModule a uri (MkSection sa sn saka sg decls) = withoutDirectives rig.rigModule
      rig' = rig {rigModule = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno directive])), rigEnv = env}
  position rig' MkTrace {trDirective = directive, trContract = start.stContract, trStart = startExpr start, trEvents = events}

-- | The position a path of events leads to, as the exploration holds it: each
-- event replayed from the start, and what a breach on the way left standing
-- carried from one position to the next ('carryBreach'). Unlike 'replayPath',
-- which is the evaluator's own answer for the whole path and nothing more, this
-- is what a state's key is made of, so it is what a test that recomputes a
-- state's key from its path must use.
positionAlong :: Explorer -> [Expr Resolved] -> IO (Maybe Position)
positionAlong ex events = do
  let (rig0, tr0) = rigFor ex []
  start <- replayRig ex rig0 >>= \ rig0' -> position rig0' tr0
  go [] events start
  where
    go _ _ Nothing = pure Nothing
    go _ [] mpos = pure mpos
    go done (e : es) (Just parent) = do
      let done' = done <> [e]
          (rig, tr) = rigFor ex done'
      replayRig ex rig >>= \ rig' -> position rig' tr >>= \ case
        Nothing    -> pure Nothing
        Just child -> carryBreach ex.exClosed parent child >>= go done' es . Just

loop :: Explorer -> Accum -> IO Accum
loop ex acc = case acc.acQueue of
  Empty -> pure acc
  node :<| rest
    | node.ndDepth >= ex.exOptions.eoMaxDepth -> do
        -- a state at the bound with no candidate at all (FULFILLED, say)
        -- has nothing the bound kept from it: it is terminal, not cut.
        -- Listing the candidates replays nothing, so asking costs nothing.
        let (rig, tr) = rigFor ex node.ndEvents
        cands <- candidatesWith ex.exClosed rig tr node.ndPos
        loop ex if null cands && null node.ndPos.posUnread
          then terminal node acc {acQueue = rest}
          else acc {acQueue = rest, acDepthCutIds = Set.insert node.ndId acc.acDepthCutIds}
    | otherwise -> do
        tried <- expand ex node
        acc' <- foldM (record ex node) acc {acQueue = rest} tried
        let fired = not (null [ () | TriedEdge {} <- tried ])
            blocked = not (null [ () | t <- tried, isBlocked t ])
            -- what this visit found, merged into what the state's earlier
            -- visits found: a pass-over counts once per state and act, and
            -- only if no instant of any visit took the act; an untried
            -- candidate and a refusal once per state and reason
            firedHere = Set.fromList [ l | TriedEdge l _ _ _ <- tried ]
            passedHere = Set.fromList [ l | TriedPassed l _ <- tried ]
            -- once per state and label, whatever the clock of the visit
            untriedHere = Map.map nubOrd (Map.fromListWith (flip (<>)) [ ((node.ndId, l), [why]) | TriedUntried l why <- tried ])
            newRefused = [ r | r <- nubOrdOn refusalKey [ r | TriedRefused r <- tried ], not (Set.member (node.ndId, refusalKey r) acc'.acRefusedSeen) ]
            beyondHere = length (nubOrd [ l | TriedBeyond l <- tried ])
            acc'' = acc'
              { acBeyondAt = Map.insertWith max node.ndId beyondHere acc'.acBeyondAt
              , acFiredAt = Map.insertWith Set.union node.ndId firedHere acc'.acFiredAt
              , acPassedAt = Map.insertWith Set.union node.ndId passedHere acc'.acPassedAt
              , acUntriedAt = Map.unionWith mergeReasons untriedHere acc'.acUntriedAt
              , acRefused = foldl' mergeRefusal acc'.acRefused newRefused
              , acRefusedSeen = acc'.acRefusedSeen <> Set.fromList [ (node.ndId, refusalKey r) | r <- newRefused ]
              }
        -- a state is terminal by its first visit; a second one, at an earlier
        -- clock, adds edges and states and leaves that standing
        loop ex if node.ndRe || fired || blocked then acc'' else terminal node acc''
  where
    isBlocked = \ case
      TriedUntried {} -> True
      TriedBeyond {}  -> True
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
        pure if not earlier then acc1
          else if node.ndDepth + 1 < ex.exOptions.eoMaxDepth
            then acc1
              { acBest = Map.insert j pos'.posClock acc.acBest
              , acQueue = acc.acQueue :|> MkNode {ndId = j, ndDepth = node.ndDepth + 1, ndEvents = node.ndEvents <> [event], ndPos = pos', ndRe = True} }
            -- the earlier clock allows more than the later one did, and the bound
            -- keeps it from being explored: a state at the bound with something
            -- left to try ('finish' leaves out the ones that were terminal)
            else acc1 {acDepthCutIds = Set.insert j acc1.acDepthCutIds}
      Nothing
        | Map.size acc.acSeen >= ex.exOptions.eoMaxStates ->
            pure acc {acCutKeys = Set.insert key acc.acCutKeys}
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
      , cvStops = [ StopDepth ex.exOptions.eoMaxDepth depthCut | depthCut > 0 ]
               <> [ StopStates ex.exOptions.eoMaxStates (Set.size acc.acCutKeys) | not (Set.null acc.acCutKeys) ]
      , cvRefused = acc.acRefused
      , cvUntried = [ MkUntriedNote what why n
                    | ((what, why), n) <- Map.toList (Map.fromListWith (+) [ ((l, why'), 1 :: Int) | ((_, l), whys) <- Map.toList acc.acUntriedAt, why' <- whys ]) ]
      , cvPassedOver = sum [ Set.size (ps `Set.difference` Map.findWithDefault Set.empty i acc.acFiredAt) | (i, ps) <- Map.toList acc.acPassedAt ]
      , cvDropped = Set.toList acc.acDropped
      , cvTime = timeText ex.exOptions
      , cvBeyondClock = sum (Map.elems acc.acBeyondAt)
      , cvMergedByName = Set.toList acc.acMerged
      , cvUnspellable = acc.acUnspell
      , cvAnswersByForm = Set.toList acc.acByForm
      , cvInstants = acc.acInstants
      }
  , gRunHeap = ex.exSites.rsRunHeap
  }
  where
    -- a state that was cut and then found to be terminal had nothing left to try
    depthCut = Set.size (acc.acDepthCutIds `Set.difference` Set.fromList [ st.snId | st <- acc.acNodes, st.snTerminal ])

-- | The reasons two visits of one state left under one label. A reason that
-- differs only in its numbers from another (the shortfall of the instant cap,
-- the fraction a window holds) is the same reason, and the one with the larger
-- numbers is kept: whichever visit was first, the advice is then the one that
-- clears the state wherever it was reached. The earlier clock's window is not
-- always the wider (a relative deadline shifts it), so "the latest visit" is not
-- the one that says the most.
mergeReasons :: [Text] -> [Text] -> [Text]
mergeReasons new old = Map.elems (Map.fromListWith larger [ (shape r, r) | r <- new <> old ])
  where
    -- a number is its digits and a minus sign directly before them: below 0 an
    -- instant is negative, and (-3.5) is the same reason as (1.5)
    shape r = Text.pack (squash (Text.unpack r))
    squash ('-' : c : rest) | isDigit c = '#' : squash (dropWhile isDigit rest)
    squash (c : rest)
      | isDigit c = '#' : squash (dropWhile isDigit rest)
      | otherwise = c : squash rest
    squash [] = []
    numbers r = [ read n :: Integer | n <- words (map (\ c -> if isDigit c then c else ' ') (Text.unpack r)) ]
    larger a b = if numbers a >= numbers b then a else b

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
  cands <- candidatesWith ex.exClosed rig tr pos
  deadlines <- liveDeadlines ex pos
  -- each candidate's obligation, found again by the 'LiveNorm' the what-if
  -- rendered it to from the very same residual ('candidatesWith')
  let lives :: [(LiveNorm, (RawObligation NF, Maybe (Either Text Rational)))]
      lives = [ (renderLive pos.posContext raw, (raw, due)) | (raw, due) <- deadlines ]
      known = nubOrd [ d | (_, Just (Right d)) <- deadlines ]
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
        (outcome, mpos) <- replayRig ex rig >>= \ rig' -> tryCandidateFrom rig' tr pos cand
        case outcome.ocVerdict of
          Untried why  -> pure (TriedUntried label why)
          PassedOver r -> pure (TriedPassed label (case r of TooEarly open -> Just open; _ -> Nothing))
          _ -> case (cand.cdHypothetical, mpos) of
            -- what a breach leaves standing is carried to the position it leads to
            (Right hyp, Just pos') | isJust pos'.posResidual -> do
              carried <- carryBreach ex.exClosed pos pos'
              pure (TriedEdge label kind (hypotheticalExpr hyp) carried)
            _ -> pure (TriedUntried label "the replay produced no position")
      -- a tick, and the instants a lapse it reveals arms (see 'tickRecord')
      tick label d cand = case cand.cdHypothetical of
        Right (Tick t) | Just u <- ex.exOptions.eoUntil, t > u -> pure ([TriedBeyond label], [])
        Right (Tick t) -> do
          r <- run label EdgeTick cand
          armed <- case r of
            TriedEdge _ _ _ pos' | Regions <- ex.exOptions.eoTime -> tickRecord label d t pos'
            _ -> pure []
          pure ([r], armed)
        _ -> (\ r -> ([r], [])) <$> run label EdgeTick cand
      -- A deadline started by a LAPSE (a LEST that arms a cure) is not started
      -- by an act, so the act that led here never saw it move; it is read here,
      -- at the tick that revealed the lapse, as an act's successor is read, and
      -- kept as the offsets (relative to the deadline that lapsed, which the
      -- act's own offset already reaches) and fixed instants that the paths
      -- through this state carry ('pathPools'). The instants a lapse arms are
      -- also returned, because they are a fact about THIS state that the acts
      -- tried in it have to be tied with, whichever way the lapsed deadline
      -- came to be: to them it is a deadline already running, and so fixed. An
      -- act that starts a deadline of 3 at 5 puts it on a cure armed at 8 by a
      -- deadline fixed at 6, and only the tick (6 and the cure's 2) says 8 is
      -- there. The acts before this state learn it from their own state's tick,
      -- where the same deadline is running, or, if the lapsed deadline is one
      -- they started, as an offset from it.
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
        pure [ h.heldAt | h <- new ]
      tickMove cand = case cand.cdKind of
        TickPast d _ -> let cand' = retimed d cand in tick (tickLabel cand' d) d cand'
        -- the what-if read the deadline with the exploration's own reader
        -- ('candidatesWith', 'liveDeadlines'), so one it could not read is not
        -- known here either; before smucclaw/l4-ide#1107 the two read differently, and a
        -- NoTick whose anchor this module could work out was turned into a
        -- tick here
        NoTick live -> pure ([TriedUntried ("time runs out on " <> live.lnAction) (either id (const "") cand.cdHypothetical)], [])
        ActBy _ -> pure ([], [])
  -- the ticks first, and each in its own place in the result: what a lapse
  -- arms is a fact about this state that the acts tried in it are tied with
  ticked <- for (zip [0 :: Int ..] cands) \ (i, cand) -> (i,) <$> tickMove cand
  let lapseFixed = nubOrd (concatMap (snd . snd) ticked)
  moves <- fmap concat $ for (zip [0 :: Int ..] cands) \ (i, cand) -> case cand.cdKind of
    TickPast {} -> pure (maybe [] fst (lookup i ticked))
    NoTick {} -> pure (maybe [] fst (lookup i ticked))
    ActBy live -> case lookup live lives of
      Nothing -> pure [TriedUntried live.lnAction "the obligation could not be found in the residual again"]
      Just (raw, _) -> do
        mparty <- partyOf raw
        acts <- actsOf ex pos raw cand
        case (mparty, acts) of
          (Nothing, _) -> pure [TriedUntried live.lnAction "the party was never forced and could not be read back"]
          (Just party, Left why) -> pure [TriedUntried (obligationText party raw) why]
          (Just party, Right (actions, refusals)) -> do
            win0 <- windowOf ex node pos "" live lives raw
            -- the instants a lapse arms are tied with by every act of the state,
            -- the act whose own deadline lapses included. An instant tried on
            -- account of the cure of its own lapse is a real run whatever the
            -- cure's fate (the act's successor may arm the same deadline and the
            -- same cure, and then the cure stands: a position that exists), and
            -- the chain note keeps the cure too, for the same reason: a tie
            -- through a chain of acts with it is real when the act's
            -- continuation re-arms the lapse (a position `--chains` reaches),
            -- and a note that is not needed when it is not (`--chains` clears
            -- it) is a loud false alarm, which is chosen over a silent miss
            let win = win0 {wnFixed = nubOrd (win0.wnFixed <> lapseFixed)}
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
  pure (moves <> grid <> unreadTried)
  where
    -- a norm waiting behind a breach that no obligation held before it
    -- accounts for (usually one armed by the continuation of a sibling that was
    -- taken; an EVERY member whose obligation the parent did not hold is
    -- another) is in no residual the explorer can read; naming it is the least
    -- it owes, because the breached position looks finished and is not
    unreadTried = [ TriedUntried (unreadLine k)
                      "it is waiting behind a breach and is not one the explorer held before it: usually armed after the breach, by the continuation of a part that was then taken (a breached value keeps only its blame), so what it asks and when cannot be read back"
                  | k <- node.ndPos.posUnread ]
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
              actions <- traverse (closedAction ex.exClosed.clReads pos.posReplayScope raw.roEnv . (`fillBinders` shape)) choices
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
      StopDepth b n  -> count n "state" <> " with a visit at the depth bound " <> textShow b <> " not expanded"
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
