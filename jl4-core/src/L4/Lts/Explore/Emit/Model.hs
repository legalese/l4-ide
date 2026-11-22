-- | What every emitter of @l4 explore --emit@ reads (REGULATIVE-LOWERING-SPEC.md
-- §6.1, work package WP3): the explored graph, read once into the shape a
-- finite-state tool wants. No emitter interprets L4; each prints this.
--
-- == Actions, one per label
--
-- The graph's edges are grouped by their label, and each group is one
-- action: @`Alice buys dinner` OF TRUE@ is one action however many states
-- it leaves from. That is the granularity the probes' hand models fair'd at
-- (tla/REPORT.md:66-70: @WF_vars(Check)@, @WF_vars(BuyChecked)@), and the
-- one §4.6 states fairness in.
--
-- == Fairness per labelled action (§4.6, R-L6 and R-L7)
--
-- An action is given weak fairness when its actor is named by @--fair@ and
-- it moves: on its edges that leave their state, never on a self-loop. None
-- is given to a pause (an action every edge of which is a self-loop), to
-- time passing, to the explorer's @terminal@ self-loop, or to any act whose
-- actor was not named, which is the environment's: free never to act.
--
-- The actor cannot be read off the graph. Under §4.3's option C, ruled
-- R-L2, every act is the one party @World@'s and the actor is named inside
-- the act (@`Alice checks whether dinner is bought`@,
-- @`ledger records Bob's purchase`@), so §4.6's "derived from the graph"
-- has to be told whose acts are the agent's. A name given to @--fair@
-- matches an act whose party is that name, whose action's constructor is
-- that name, or whose constructor's name begins with that name and a space
-- (@--fair Alice@ matches @`Alice buys dinner`@; under option A it would
-- match @PARTY Alice@). Fairness is OPT-IN on purpose: forgetting it leaves
-- every action unfair, and a liveness property that needs it then fails
-- loudly, with a run that pauses forever; the other default, every act
-- fair, would assume the environment acts and pass "if Bob never buys,
-- Alice eventually buys" on no runs at all, silently (the trap of §4.6 and
-- of the probes' Spin run). Assumed, not ruled.
--
-- == The relation is made total (TLA+ and NuSMV only)
--
-- A state with no edge at all is one the exploration did not go past: a
-- bound cut it, or every candidate there was refused, untried, or past the
-- clock bound (the explorer gives its own @terminal@ self-loop only to a
-- state with no candidate). Measured on NuSMV 2.7.0, 2026-10-26: with one
-- state that has no successor and violates @p@, @SPEC AG p@ is reported
-- TRUE, @SPEC EF@ of that state FALSE, and only @INVARSPEC p@ FALSE, with no
-- warning, because CTL ranges over infinite paths. So the model emitted to
-- a checker gives each such state a self-loop labelled @unexplored@, with no
-- fairness, and says which states in its header; the @.aut@ and the
-- pictures show the graph as explored, without it.
--
-- == Labels
--
-- A boolean decision is emitted as the set of states the evaluator
-- labelled it TRUE in ("L4.Lts.Explore.Check"'s 'Labels'). A decision with
-- a state it could not label is not emitted, by name, and neither is any
-- property that reads it: half a set would be a different predicate.
module L4.Lts.Explore.Emit.Model
  ( -- * Input
    EmitInput (..)
  , fairMatches
    -- * The model
  , Model (..)
  , EmAction (..)
  , Fairness (..)
  , Predicate (..)
  , Prop (..)
  , buildModel
  , unexploredLabel
    -- * Helpers the emitters share
  , oneLine
  , identifier
  , fairnessLines
  , actionTable
  , count
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import Base.Text (textShow)
import Data.Char (isAlphaNum, isAscii, isDigit)

import L4.Lts.Explore
import L4.Lts.Explore.Check (Decision (..), Labels, Property (..), PropertyKind (..), requestText)
import L4.Print (prettyLayout)
import L4.Syntax

----------------------------------------------------------------------------
-- Input
----------------------------------------------------------------------------

data EmitInput = MkEmitInput
  { eiBase       :: !Text
    -- ^ the base name of every file written, which is also the TLA+ module
    -- name, so letters, digits and underscores only
  , eiSource     :: !Text
    -- ^ the file explored, as its name only, so that no emitted file holds
    -- an absolute path
  , eiGraph      :: !Graph
  , eiProperties :: ![Property]
  , eiLabels     :: !Labels
  , eiFair       :: ![Text]
    -- ^ the names given to @--fair@
  }

-- | Whether a name given to @--fair@ names the actor of some act of the
-- graph (see the module header). The CLI refuses a name that matches no
-- act of any graph explored.
fairMatches :: Graph -> Text -> Bool
fairMatches g name = any (actorIs (unquote name)) (map snd (labelEvents g))

-- | Each act label of the graph, with the event an edge of it was first
-- taken by (all edges of one label carry the same party and action).
labelEvents :: Graph -> [(Text, Event Resolved)]
labelEvents g = nubOrdOn fst
  [ (label, ev) | ((_, label, _), Event _ ev) <- Map.toList g.gEdgeEvents ]

actorIs :: Text -> Event Resolved -> Bool
actorIs name ev =
  headName ev.party == Just name
    || headName ev.action == Just name
    || maybe False ((name <> " ") `Text.isPrefixOf`) (headName ev.action)

headName :: Expr Resolved -> Maybe Text
headName = \ case
  Var _ r   -> Just (nameOf r)
  App _ r _ -> Just (nameOf r)
  _         -> Nothing
  where
    nameOf = unqualifiedNameToText . getOriginal

unquote :: Text -> Text
unquote t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")

----------------------------------------------------------------------------
-- The model
----------------------------------------------------------------------------

data Model = MkModel
  { mdBase       :: !Text
  , mdHeader     :: ![Text]
    -- ^ what the graph is and how it was explored, without comment markers
  , mdStates     :: !Int
  , mdActions    :: ![EmAction]
  , mdUnexplored :: ![Int]
    -- ^ states with no edge in the graph, each given an @unexplored@
    -- self-loop in the model a checker reads
  , mdPredicates :: ![Predicate]
  , mdProps      :: ![Prop]
  , mdNotEmitted :: ![(Text, Text)]
    -- ^ a property not emitted, and why
  }

data EmAction = MkEmAction
  { eaLabel    :: !Text
    -- ^ the graph's label, on one line
  , eaIdent    :: !Text
  , eaStill    :: !(Maybe Text)
    -- ^ for a fair action that is a self-loop in some states: the NuSMV
    -- value its self-loops record instead of 'eaIdent', so that pausing on
    -- it can never count as taking it (its JUSTICE reads the value)
  , eaKind     :: !(Maybe EdgeKind)
    -- ^ 'Nothing' for the @unexplored@ self-loops, which are not the graph's
  , eaEdges    :: ![(Int, Int)]
  , eaFairness :: !Fairness
  }

data Fairness
  = Fair
    -- ^ weak fairness on the action's edges that leave their state
  | Unfair !Text
    -- ^ none, and why
  deriving stock (Eq, Show)

data Predicate = MkPredicate
  { pdIdent    :: !Text
  , pdDecision :: !Text
  , pdTrue     :: ![Int]
    -- ^ the states the evaluator labelled TRUE
  }

data Prop = MkProp
  { ppKind    :: !PropertyKind
  , ppText    :: !Text
    -- ^ as the checker names it: @always `x`@
  , ppIdent   :: !Text
  , ppPred    :: !Text
    -- ^ the predicate's identifier
  , ppPremise :: !(Maybe Text)
  }

-- | The label of the self-loops that make the relation total.
unexploredLabel :: Text
unexploredLabel = "unexplored"

buildModel :: EmitInput -> Model
buildModel ei = MkModel
  { mdBase = ei.eiBase
  , mdHeader = header
  , mdStates = length g.gStates
  , mdActions = actions
  , mdUnexplored = unexplored
  , mdPredicates = predicates
  , mdProps = props
  , mdNotEmitted = notEmitted
  }
  where
    g = ei.eiGraph
    -- the graph's labels in the order their first edge was found, then the
    -- self-loops that make it total
    grouped = [ (label, kind, [ (t.tnFrom, t.tnTo) | t <- g.gTransitions, t.tnLabel == label ])
              | (label, kind) <- nubOrdOn fst [ (t.tnLabel, t.tnKind) | t <- g.gTransitions ] ]
    unexplored = [ s.snId | s <- g.gStates, s.snId `Set.notMember` sources ]
    sources = Set.fromList [ t.tnFrom | t <- g.gTransitions ]
    events = Map.fromList (labelEvents g)
    rawActions =
      [ (oneLine label, Just kind, edges, fairnessOf label kind edges) | (label, kind, edges) <- grouped ]
      <> [ (unexploredLabel, Nothing, [ (i, i) | i <- unexplored ], Unfair "not an act: the exploration did not go past this state")
         | not (null unexplored) ]
    fairnessOf label kind edges = case kind of
      EdgeTerminal -> Unfair "the explorer's terminal self-loop"
      EdgeTick -> Unfair "time passing, which no one is assumed to make happen"
      EdgeAct
        | all (uncurry (==)) edges -> Unfair "a pause: every edge of it is a self-loop"
        | maybe False (\ ev -> any (`actorIs` ev) (map unquote ei.eiFair)) (Map.lookup label events) -> Fair
        | otherwise -> Unfair "its actor is not named by --fair, so it is the environment's, free never to act"
    -- decisions the properties read, in the order first asked
    decisions = nubOrd (concat [ p.prDecision.dcName : maybeToList ((.dcName) <$> p.prPremise) | p <- ei.eiProperties ])
    labelled = [ (d, statesOf d) | d <- decisions ]
    statesOf d = case Map.lookup d ei.eiLabels of
      Nothing -> Left "no state was labelled with it"
      Just m -> do
        answers <- for g.gStates \ s -> case Map.lookup s.snId m of
          Nothing -> Left ("state s" <> textShow s.snId <> " was not labelled")
          Just (Left why) -> Left ("state s" <> textShow s.snId <> " could not be labelled: " <> why)
          Just (Right b) -> Right (s.snId, b)
        Right [ i | (i, True) <- answers ]
    -- one pass hands out every identifier, so no two collide in either tool
    mixed (_, _, es, f) = f == Fair && any (uncurry (==)) es
    idents = uniqueIdents
      ( [ actionIdent l | (l, _, _, _) <- rawActions ]
        <> [ actionIdent l <> "_still" | a@(l, _, _, _) <- rawActions, mixed a ]
        <> [ identifier d | (d, Right _) <- labelled ]
        <> [ propIdent p | p <- emitted ] )
    (actionIds, rest0) = splitAt (length rawActions) idents
    (stillIds, rest1) = splitAt (length (filter mixed rawActions)) rest0
    (predIds, propIds) = splitAt (length [ () | (_, Right _) <- labelled ]) rest1
    stills = zip [ l | a@(l, _, _, _) <- rawActions, mixed a ] stillIds
    actions =
      [ MkEmAction {eaLabel = l, eaIdent = i, eaStill = lookup l stills, eaKind = k, eaEdges = es, eaFairness = f}
      | ((l, k, es, f), i) <- zip rawActions actionIds ]
    predicates =
      [ MkPredicate {pdIdent = i, pdDecision = d, pdTrue = ss}
      | ((d, ss), i) <- zip [ (d, ss) | (d, Right ss) <- labelled ] predIds ]
    predIdent d = fromMaybe (identifier d) (lookup d [ (p.pdDecision, p.pdIdent) | p <- predicates ])
    ok d = isJust (lookup d [ (d', ()) | (d', Right _) <- labelled ])
    whyNot d = fromMaybe "" (lookup d [ (d', w) | (d', Left w) <- labelled ])
    emitted = [ p | p <- ei.eiProperties, all ok (decisionNames p) ]
    notEmitted =
      [ (requestText p, "`" <> d <> "`: " <> whyNot d)
      | p <- ei.eiProperties, d : _ <- [filter (not . ok) (decisionNames p)] ]
    decisionNames p = p.prDecision.dcName : maybeToList ((.dcName) <$> p.prPremise)
    props =
      [ MkProp
          { ppKind = p.prKind
          , ppText = requestText p
          , ppIdent = i
          , ppPred = predIdent p.prDecision.dcName
          , ppPremise = predIdent . (.dcName) <$> p.prPremise
          }
      | (p, i) <- zip emitted propIds ]
    propIdent p = kindPrefix p.prKind <> "_" <> identifier p.prDecision.dcName
      <> maybe "" (\ q -> "_if_always_" <> identifier q.dcName) p.prPremise
    kindPrefix = \ case
      Always     -> "Always"
      Reachable  -> "Never"
      Stays      -> "Stays"
      Eventually -> "Eventually"
    header =
      [ g.gStart.stName <> ", explored by l4 explore from " <> ei.eiSource <> " at " <> oneLine (prettyLayout g.gStart.stAt)
          <> ": " <> count g.gCoverage.cvStates "state" <> ", " <> count g.gCoverage.cvTransitions "transition" <> "."
      , "Generated by l4 explore --emit (REGULATIVE-LOWERING-SPEC.md section 6.1); edit the L4, not this file."
      , "State 0 is the outset. " <> oneLine (coverageLine g.gCoverage)
      ]
      <> (if coverageComplete g.gCoverage then [] else
           [ "INCOMPLETE: the exploration did not reach everything (the coverage line says what stopped it), so a verdict on this model is about the states explored, not the contract." ])

-- | An action's identifier: its label without the @PARTY … DOES@ frame.
actionIdent :: Text -> Text
actionIdent label = identifier case Text.stripPrefix "PARTY " label of
  Just rest -> Text.replace " DOES " " " rest
  Nothing -> label

-- | A name both tools read: ASCII letters, digits and underscores, starting
-- with a letter; every other run of characters becomes one underscore.
identifier :: Text -> Text
identifier t =
  let cleaned = Text.intercalate "_" (filter (not . Text.null) (Text.split (\ c -> not (isAscii c && isAlphaNum c)) t))
  in case Text.uncons cleaned of
       Nothing -> "x"
       Just (c, _) | isDigit c -> "x_" <> cleaned
       _ -> cleaned

-- | Each identifier, made distinct from the ones before it and from every
-- word either tool or the emitted model reserves, by a numeric suffix.
uniqueIdents :: [Text] -> [Text]
uniqueIdents = go reserved
  where
    go _ [] = []
    go seen (x : xs) =
      let pick = fromMaybe x (find (`Set.notMember` seen) (x : [ x <> "_" <> textShow n | n <- [2 :: Int ..] ]))
      in pick : go (Set.insert pick seen) xs

-- | Words the emitted models use for themselves, and the keywords of TLA+
-- and NuSMV 2.7 (NuSMV rejects @init@ as a value, measured 2026-10-26).
reserved :: Set Text
reserved = Set.fromList $
  [ "s", "lastAct", "beat", "vars", "Init", "Next", "Spec", "FairSpec", "act", "outset", "Moves" ]
  -- TLA+
  <> [ "ASSUME", "ASSUMPTION", "AXIOM", "BOOLEAN", "CASE", "CHOOSE", "CONSTANT", "CONSTANTS", "DOMAIN"
     , "ELSE", "ENABLED", "EXCEPT", "EXTENDS", "FALSE", "IF", "IN", "INSTANCE", "LET", "LOCAL", "MODULE"
     , "OTHER", "STRING", "SUBSET", "THEN", "THEOREM", "TRUE", "UNCHANGED", "UNION", "VARIABLE", "VARIABLES"
     , "WITH", "Nat", "LAMBDA", "RECURSIVE", "INSTANCE", "LEMMA", "PROPOSITION", "COROLLARY" ]
  -- NuSMV
  <> [ "MODULE", "DEFINE", "MDEFINE", "CONSTANTS", "VAR", "IVAR", "FROZENVAR", "INIT", "TRANS", "INVAR"
     , "SPEC", "CTLSPEC", "LTLSPEC", "PSLSPEC", "COMPUTE", "NAME", "INVARSPEC", "FAIRNESS", "JUSTICE"
     , "COMPASSION", "ISA", "ASSIGN", "CONSTRAINT", "SIMPWFF", "CTLWFF", "LTLWFF", "PSLWFF", "COMPWFF"
     , "IN", "MIN", "MAX", "MIRROR", "PRED", "PREDICATES", "process", "array", "of", "boolean", "integer"
     , "real", "word", "word1", "bool", "signed", "unsigned", "extend", "resize", "sizeof", "uwconst"
     , "swconst", "EX", "AX", "EF", "AF", "EG", "AG", "E", "F", "O", "G", "H", "X", "Y", "Z", "A", "U"
     , "S", "V", "T", "BU", "EBF", "ABF", "EBG", "ABG", "case", "esac", "mod", "next", "init", "union"
     , "in", "xor", "xnor", "self", "TRUE", "FALSE", "count", "abs", "max", "min", "toint", "floor"
     , "typeof", "set", "clock", "time", "until", "since" ]

----------------------------------------------------------------------------
-- Helpers the emitters share
----------------------------------------------------------------------------

-- | Text on one line: every run of whitespace, line breaks included, one
-- space.
oneLine :: Text -> Text
oneLine = Text.unwords . Text.words

-- | The fairness of every action, one line each, for a header comment: so
-- a reader of the emitted model sees the list (R-L6).
fairnessLines :: Model -> [Text]
fairnessLines m =
  "Fairness: weak, per labelled action (REGULATIVE-LOWERING-SPEC.md section 4.6), on the acts of the actors named by --fair"
    <> (if any ((== Fair) . (.eaFairness)) m.mdActions then ":" else "; none was named, so no action is fair:")
  : [ "  " <> word a <> " " <> a.eaIdent <> moves a | a <- m.mdActions ]
  where
    word a = case a.eaFairness of
      Fair -> "fair:"
      Unfair _ -> "none:"
    moves a = case a.eaFairness of
      Fair | any (uncurry (==)) a.eaEdges -> " (on its edges that leave their state; its self-loops are pauses)"
           | otherwise -> ""
      Unfair why -> ", " <> why

-- | Each action's identifier and the label it stands for.
actionTable :: Model -> [Text]
actionTable m =
  "Actions (identifier: the explorer's label; edges):"
  : [ "  " <> a.eaIdent <> ": " <> a.eaLabel <> "; " <> textShow (length a.eaEdges) | a <- m.mdActions ]
  <> (case m.mdUnexplored of
        [] -> []
        ss -> [ "States with no edge in the graph, each given an `unexplored` self-loop here so that no checker drops it as a deadlock: "
                <> Text.intercalate ", " (map textShow ss) ])

count :: Int -> Text -> Text
count n w = textShow n <> " " <> w <> (if n == 1 then "" else "s")
