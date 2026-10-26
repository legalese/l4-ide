{-# LANGUAGE PatternSynonyms #-}
-- | The in-process checker of @l4 explore@ (REGULATIVE-LOWERING-SPEC.md §5,
-- work package WP2): label every state of an explored graph with boolean
-- decisions of the module, decide safety, reachability and safety over
-- steps on the graph, and print what was found wrong as a @#TRACE@ that
-- reproduces it.
--
-- == A property is a boolean decision (§5.1)
--
-- No property language: a property is an ordinary @DECIDE@ that gives a
-- @BOOLEAN@, and its inputs are filled from the state's ledgers. Each input
-- is named for the ledger cell it reads; an input that is a @LIST@ is given
-- the cell's whole history, oldest first (what @RECALL ALL@ reads), and one
-- that is a @MAYBE@ its latest entry (what @RECALL@ reads). Which ledger
-- holds the cell is found, not written: a cell found in two ledgers is not
-- guessed between, and every label of the property is then unknown.
--
-- The class of a property — always, reachable, stays, eventually — is not
-- in the source, because L4 has no syntax for it (§3, the assertion surface
-- deferred as D-L2); the caller says which ('Request').
--
-- A property is refused, by name, when it could not mean the same thing at
-- every state: an input that is neither a @LIST@ nor a @MAYBE@; no inputs
-- at all; a rule that reads a ledger itself, directly or through a rule it
-- names (an @#EVAL@ has no ledger, so its @RECALL@ would read nothing, the
-- silent kind of wrong). An input named for a cell nothing in the modules
-- writes is not refused, since one set of properties serves several designs
-- and a cell one of them never writes is legitimately empty there; but it is
-- empty in every state, which is also what a typo in its name would give,
-- so the property's line says so.
--
-- == The labels
--
-- Every cell a property reads is kept in the state ('propertyCells', which
-- the caller passes to 'keepCells' before exploring), so a label is a
-- function of the state, not of whichever position happened to reach it
-- first. When a cell the property reads was not kept ('gKept'), or was
-- kept as its latest entry where the input reads its whole history, no
-- state is labelled: two positions that differ there may have been merged
-- into one, and labelling it from the first would be the silent
-- faithfulness failure of §4.1. The decision is evaluated by the evaluator: one @#EVAL@ per
-- distinct input, all in one run of the module, on the values the state's
-- ledgers hold, spelled back as literals.
--
-- == The verdicts (§5.2)
--
-- R-V8's three: @holds@, @violated@ with a counterexample, @unknown@ with
-- what stopped it.
--
-- * __always__ (@AG p@): violated by the first state, in breadth-first
--   order, where it is FALSE, so the counterexample is a shortest one. It
--   holds only when the exploration was complete and every state was
--   labelled.
-- * __reachable__ (@EF p@): holds with a witness, the first state where it
--   is TRUE; violated only when the exploration was complete.
-- * __stays__ (@□(p ⇒ □p)@): violated by a step from a state where it is
--   TRUE to one where it is FALSE; the counterexample is the path to the
--   first and that step's event.
-- * __eventually__ (@◇p@, and @□q ⇒ ◇p@ with a premise): liveness needs
--   cycles under a fairness assumption and a lasso for a counterexample
--   (§5.3), so it is answered @unknown (liveness: run the emitted model)@
--   and never guessed. Its states are labelled all the same, for the
--   emitters.
--
-- == Replayed before printing (§5.4, §6.3)
--
-- A counterexample or a witness is a path of events, which is a @#TRACE@.
-- Before it is printed it is replayed afresh on the evaluator
-- ('replayPath'), the property evaluated on the ledgers that replay left,
-- and only a path whose replay gives the answer the graph gave is reported
-- as one; a path that does not is reported as an unknown verdict, loudly,
-- since it means the explorer merged two positions the property tells
-- apart (§4.1's one silent risk).
module L4.Lts.Explore.Check
  ( -- * What is asked
    PropertyKind (..)
  , Request (..)
  , Decision (..)
  , Input (..)
  , Property (..)
  , resolveProperty
  , propertyCells
  , kindWord
  , requestText
    -- * Labels
  , Labels
  , labelGraph
  , decisionArgs
  , evalBooleans
    -- * Verdicts
  , Verdict (..)
  , Path (..)
  , CheckResult (..)
  , SourceReplay
  , checkGraph
  , verdictWord
  , livenessUnknown
    -- * Rendering
  , renderChecks
  , checksSummary
  , traceText
  , checksJson
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import Base.Text (textShow)
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Optics

import L4.Annotation (emptyAnno)
import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..))
import L4.Evaluate.ValueLazy hiding (Blame)
import L4.EvaluateLazy
  ( EntityInfo
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithDeonticLog
  , prettyReductionOutcome
  )
import L4.EvaluateLazy.Machine (pattern ValBool)
import L4.Lts.Explore
import L4.Lts.WhatIf (Position (..), Rig (..), reifyRef, reifyValue)
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.Utils.Ratio (prettyRatio)

----------------------------------------------------------------------------
-- What is asked
----------------------------------------------------------------------------

-- | The class of a property: the caller says which (see the module header).
data PropertyKind
  = Always
    -- ^ safety: no reachable state where it is FALSE
  | Reachable
    -- ^ reachability: some reachable state where it is TRUE
  | Stays
    -- ^ safety over steps: no step from a state where it is TRUE to one
    -- where it is FALSE
  | Eventually
    -- ^ liveness: answered unknown, never decided here
  deriving stock (Eq, Show)

kindWord :: PropertyKind -> Text
kindWord = \ case
  Always     -> "always"
  Reachable  -> "reachable"
  Stays      -> "stays"
  Eventually -> "eventually"

-- | One property asked for: its class, the rule's name, and for a liveness
-- property @□q ⇒ ◇p@ the premise @q@.
data Request = MkRequest
  { rqKind    :: !PropertyKind
  , rqName    :: !Text
  , rqPremise :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | @always `every dinner was accepted while open`@, as the request is
-- named in what is printed.
requestText :: Property -> Text
requestText p = kindWord p.prKind <> " `" <> p.prDecision.dcName <> "`"
  <> maybe "" (\ q -> " if always `" <> q.dcName <> "`") p.prPremise

-- | A boolean decision of the module, resolved.
data Decision = MkDecision
  { dcName   :: !Text
  , dcRef    :: !Resolved
  , dcInputs :: ![Input]
  }

-- | One input of a decision: the cell it is named for, and whether it is
-- given the cell's whole history (a @LIST@) or its latest entry (a
-- @MAYBE@).
data Input = MkInput
  { inCell    :: !Text
  , inWhole   :: !Bool
  , inWritten :: !Bool
    -- ^ some RECORD, COMMIT or ATTEST of the modules names the cell. One
    -- that none names is empty in every state, which a typo in the input's
    -- name would also give; it is not refused, since one set of properties
    -- serves several designs and a cell one of them never writes is
    -- legitimately empty there, but it is said on the property's line
  }
  deriving stock (Eq, Show)

data Property = MkProperty
  { prKind     :: !PropertyKind
  , prDecision :: !Decision
  , prPremise  :: !(Maybe Decision)
  }

-- | A request, resolved against the modules: the module explored and every
-- module it imports. 'Left' says why the property cannot be checked; the
-- caller treats that as an option that names nothing.
resolveProperty :: EntityInfo -> [Module Resolved] -> Request -> Either Text Property
resolveProperty info modules rq = do
  d <- resolveDecision info modules rq.rqName
  q <- case (rq.rqKind, rq.rqPremise) of
    (_, Nothing) -> Right Nothing
    (Eventually, Just n) -> Just <$> resolveDecision info modules n
    (k, Just _) -> Left ("a premise (if always …) is for an eventually property, not " <> kindWord k)
  Right MkProperty {prKind = rq.rqKind, prDecision = d, prPremise = q}

-- | The cells the properties read, and how, for 'keepCells': 'True' for a
-- cell some input reads whole.
propertyCells :: [Property] -> [(Text, Bool)]
propertyCells props =
  [ (i.inCell, i.inWhole) | p <- props, d <- decisionsOf p, i <- d.dcInputs ]

decisionsOf :: Property -> [Decision]
decisionsOf p = p.prDecision : maybeToList p.prPremise

resolveDecision :: EntityInfo -> [Module Resolved] -> Text -> Either Text Decision
resolveDecision info modules wanted0 = do
  let wanted = unquote wanted0
      decides = [ d | MkModule _ _ section <- modules, d <- decidesOf section ]
      named = nubOrdOn fst
        [ (u, n) | MkDecide _ _ (MkAppForm _ (Def u n) _ _) _ <- decides, nameToText n == wanted ]
  (u, n) <- case named of
    [] -> Left ("no rule named `" <> wanted <> "` in the file or the files it imports")
    [x] -> Right x
    _ -> Left ("more than one rule is named `" <> wanted <> "`")
  ty <- case Map.lookup u info of
    Just (_, TypeCheck.KnownTerm t _) -> Right (unforall t)
    _ -> Left ("the type of `" <> wanted <> "` is not recorded")
  (args, res) <- case ty of
    Fun _ args res -> Right (args, res)
    _ -> Left ("`" <> wanted <> "` takes no inputs, so it can read nothing of a state: give it one input for each ledger cell it reads, named for the cell")
  unless (isBoolean res) $
    Left ("`" <> wanted <> "` gives " <> article (prettyLayout res) <> ", not a BOOLEAN")
  when (Set.member u readers) $
    Left ("`" <> wanted <> "` reads a ledger itself (a RECALL in it, or in a rule it names); a property is evaluated outside any run, where a RECALL reads nothing, so it must take what it reads as inputs, each named for its cell")
  inputs <- for args \ (MkOptionallyNamedType _ mname t) -> do
    name <- maybe (Left ("an input of `" <> wanted <> "` has no name, and an input is filled from the cell it is named for")) (Right . nameText) mname
    whole <- case t of
      TyApp _ r [_]
        | getUnique r == TypeCheck.listUnique  -> Right True
        | getUnique r == TypeCheck.maybeUnique -> Right False
      _ -> Left ("the input `" <> name <> "` of `" <> wanted <> "` is " <> article (prettyLayout t)
                 <> "; an input is filled from the ledger cell it is named for, a LIST with the cell's whole history or a MAYBE with its latest entry, so it must be one of those")
    Right MkInput {inCell = name, inWhole = whole, inWritten = not writesKnown || Set.member name written}
  Right MkDecision {dcName = nameToText n, dcRef = Ref n u n, dcInputs = inputs}
  where
    unquote t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
    unforall = \ case
      Forall _ _ t -> unforall t
      t -> t
    isBoolean = \ case
      TyApp _ r [] -> getUnique r == getUnique TypeCheck.booleanRef
      _ -> False
    article t = if maybe False (`elem` ("AEIOU" :: String)) (fst <$> Text.uncons t) then "an " <> t else "a " <> t
    everyExpr = concatMap exprsIn modules
    -- every cell some write names; when one names a cell by an expression
    -- that is not a literal, any cell may be written, and nothing is refused
    writes = [ cell | Record _ _ cell _ _ _ <- everyExpr ]
    written = Set.fromList [ s | Lit _ (StringLit _ s) <- writes ]
    writesKnown = all (\ case Lit _ (StringLit _ _) -> True; _ -> False) writes
    -- the rules of every module that read a ledger, directly or by naming
    -- one that does (as 'readSitesOf' finds them for one module)
    topDecides =
      [ (getUnique name, body)
      | MkModule _ _ section <- modules
      , MkDecide _ _ (MkAppForm _ name _ _) body <- decidesOf section ]
    readers = fixpoint (Set.fromList [ u' | (u', body) <- topDecides, not (null [ () | ReadCell {} <- subExprsIn body ]) ])
    refsOf body = Set.fromList (concat [ heads e | e <- subExprsIn body ])
    heads = \ case
      Var _ r   -> [getUnique r]
      App _ r _ -> [getUnique r]
      _         -> []
    fixpoint s =
      let s' = s <> Set.fromList [ u' | (u', body) <- topDecides, not (Set.disjoint (refsOf body) s) ]
      in if s' == s then s else fixpoint s'

exprsIn :: Module Resolved -> [Expr Resolved]
exprsIn = Optics.toListOf (Optics.gplate @(Expr Resolved) Optics.% Optics.cosmosOf (Optics.gplate @(Expr Resolved)))

subExprsIn :: Expr Resolved -> [Expr Resolved]
subExprsIn = Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Resolved)))

nameText :: Resolved -> Text
nameText = unqualifiedNameToText . getOriginal

----------------------------------------------------------------------------
-- Labels
----------------------------------------------------------------------------

-- | Each decision's answer at each state: by the decision's name, then the
-- state's id. 'Left' says why the state could not be labelled.
type Labels = Map Text (Map Int (Either Text Bool))

-- | The inputs of a decision, as the ledgers of one position fill them:
-- each a literal (a @LIST@ of the cell's entries, or @JUST@ the latest, or
-- @NOTHING@). 'Left' when a cell is in more than one ledger, or holds a
-- value with no literal form.
decisionArgs :: Decision -> LedgerStore -> IO (Either Text [Expr Resolved])
decisionArgs d store = fmap sequence $ for d.dcInputs \ i -> case cellIn store i.inCell of
  _ : _ : _ ->
    pure (Left ("the cell `" <> i.inCell <> "` is in more than one ledger here ("
      <> Text.intercalate ", " [ l <> "'s" | (l, _) <- cellIn store i.inCell ]
      <> "), and an input names a cell, not a ledger"))
  found -> do
    let entries = concatMap snd found
        chosen = if i.inWhole then entries else lastOf entries
    spelled <- traverse (reifyValue reifyRef) chosen
    pure case sequence spelled of
      Nothing -> Left ("a value in the cell `" <> i.inCell <> "` has no literal form")
      Just es
        | i.inWhole -> Right (List emptyAnno es)
        | otherwise -> Right case es of
            [e] -> App emptyAnno TypeCheck.justRef [e]
            _   -> App emptyAnno TypeCheck.nothingRef []
  where
    lastOf xs = case reverse xs of
      (x : _) -> [x]
      []      -> []

-- | The ledgers that hold a cell, with its entries in recorded order: the
-- official record first, then each party's own, as 'projectLedger' reads
-- them.
cellIn :: LedgerStore -> Text -> [(Text, [WHNF])]
cellIn store cell =
  [ (name, vs)
  | (name, led) <- ("OFFICIAL", store.officialLedger) : Map.toList store.ownLedgers
  , let vs = [ v | Assign path v _ <- toList led, Text.intercalate "'s " path == cell ]
  , not (null vs) ]

-- | Evaluate boolean expressions in the module, by the evaluator: one
-- @#EVAL@ each, in one run of the module with its own directives taken out.
evalBooleans :: Rig -> [Expr Resolved] -> IO [Either Text Bool]
evalBooleans _ [] = pure []
evalBooleans rig es = do
  let MkModule a uri (MkSection sa sn saka sg decls) = withoutDirectives rig.rigModule
      m' = MkModule a uri (MkSection sa sn saka sg (decls <> [ Directive emptyAnno (LazyEval emptyAnno e) | e <- es ]))
  (_, results) <- execEvalModuleWithDeonticLog rig.rigConfig rig.rigEntityInfo rig.rigEnv m'
  pure if length results /= length es
    then map (const (Left "the evaluator returned a different number of answers than it was asked for")) es
    else [ answer res.result | (res, _) <- results ]
  where
    answer = \ case
      Reduction (Reduced (MkNF (ValBool b))) -> Right b
      Reduction o -> Left ("it did not evaluate to TRUE or FALSE: " <> oneLine (prettyReductionOutcome o))
      Assertion _ -> Left "the evaluator answered with an assertion"

-- | Label every state with every decision the properties name.
labelGraph :: Rig -> [Property] -> Graph -> IO Labels
labelGraph rig props g = do
  let decisions = nubOrdOn (.dcName) (concatMap decisionsOf props)
  perState <- for decisions \ d -> do
    args <- for g.gStates \ s -> (s.snId,) <$> decisionArgs d s.snStore
    pure (d, args)
  -- one #EVAL per distinct input, across every decision
  let calls = nubOrdOn fst
        [ (callKey d as, App emptyAnno d.dcRef as) | (d, args) <- perState, (_, Right as) <- args ]
  answers <- Map.fromList . zip (map fst calls) <$> evalBooleans rig (map snd calls)
  let label d a = case (ambiguousCells d <> unkeptCells d, a) of
        (why : _, _)  -> Left why
        (_, Left why) -> Left why
        (_, Right as) -> fromMaybe (Left "no answer was returned") (Map.lookup (callKey d as) answers)
  pure $ Map.fromList
    [ (d.dcName, Map.fromList [ (i, label d a) | (i, a) <- args ]) | (d, args) <- perState ]
  where
    callKey d as = d.dcName <> " " <> Text.unwords (map prettyLayout as)
    -- a label is read off the position that first reached the state, so it
    -- is the state's only when every cell it reads is in the state's key,
    -- kept as the input reads it; a cell left out may differ between the
    -- positions merged into a state, and the label would be a guess. The
    -- CLI keeps the cells ('propertyCells'); a caller that did not is told,
    -- in every state, since which states merged positions is not recorded
    unkeptCells d =
      [ "the cell `" <> i.inCell <> "` was not kept in the state"
          <> (if isJust (Map.lookup i.inCell g.gKept) then " whole, only its latest entry" else "")
          <> ", so positions merged into one state may differ in it: explore with the properties' cells kept ('propertyCells' to 'keepCells', as the CLI does)"
      | i <- d.dcInputs
      , case Map.lookup i.inCell g.gKept of
          Nothing    -> True
          Just whole -> i.inWhole && not whole ]
    -- a cell found in one ledger in one state and another in another is
    -- named by its input ambiguously across the graph, even where each
    -- state alone holds it in one
    ambiguousCells d =
      [ "the cell `" <> i.inCell <> "` is in more than one ledger across the states explored ("
          <> Text.intercalate ", " [ l <> "'s" | l <- ls ] <> "), and an input names a cell, not a ledger"
      | i <- d.dcInputs
      , let ls = nubOrd [ l | s <- g.gStates, (l, _) <- cellIn s.snStore i.inCell ]
      , length ls > 1 ]

----------------------------------------------------------------------------
-- Verdicts
----------------------------------------------------------------------------

-- | A path of events from the start, as a @#TRACE@ would carry them.
data Path = MkPath
  { ptState  :: !Int
    -- ^ the state it ends at (for a step, the state the step leaves)
  , ptEvents :: ![Expr Resolved]
  , ptStep   :: !Bool
    -- ^ its last event is the step that changed the answer
  }

data Verdict
  = Holds !Text
    -- ^ with the extent of what was explored
  | Reached !Path
    -- ^ a reachability property holds: a witness, replayed
  | Violated !Text !(Maybe Path)
    -- ^ with a counterexample, replayed; reachability has none to give
  | Unknown !Text !(Maybe Path)
    -- ^ with what stopped it, and a path that did not replay as it should
    -- when that is what stopped it

verdictWord :: Verdict -> Text
verdictWord = \ case
  Holds _      -> "holds"
  Reached _    -> "holds"
  Violated _ _ -> "violated"
  Unknown _ _  -> "unknown"

-- | What the in-process checker says of every liveness property (§5.3).
livenessUnknown :: Text
livenessUnknown = "liveness: run the emitted model"

data CheckResult = MkCheckResult
  { crProperty :: !Property
  , crVerdict  :: !Verdict
  , crReads    :: ![(Input, [Text])]
    -- ^ each input of the property, and the ledgers its cell was found in
    -- across the states explored (none: never written)
  }

-- | Run a @#TRACE@ given as source text, appended to the file explored,
-- and give back the ledgers it left: how a printed counterexample is run as
-- what it is printed as, before it is printed. Parsing a file with its
-- imports is the caller's business (the CLI does it with a virtual file
-- beside the one explored), so the caller supplies it, or does not.
type SourceReplay = Text -> IO (Either Text LedgerStore)

-- | Label the graph and answer every property on it.
checkGraph :: ExploreOptions -> Rig -> Maybe SourceReplay -> Graph -> [Property] -> IO ([CheckResult], Labels)
checkGraph opts rig msource g props = do
  labels <- labelGraph rig props g
  results <- for props \ p -> do
    v <- verdictOf opts rig msource g labels p
    pure MkCheckResult
      { crProperty = p
      , crVerdict = v
      , crReads =
          [ (i, nubOrd [ l | s <- g.gStates, (l, _) <- cellIn s.snStore i.inCell ])
          | d <- decisionsOf p, i <- d.dcInputs ]
      }
  pure (results, labels)

verdictOf :: ExploreOptions -> Rig -> Maybe SourceReplay -> Graph -> Labels -> Property -> IO Verdict
verdictOf opts rig msource g labels p = case p.prKind of
  Eventually -> pure (Unknown livenessUnknown Nothing)
  Always -> case [ s | s <- g.gStates, lab s.snId == Right False ] of
    s : _ -> confirm (pathTo s) False [] \ path ->
      Violated ("after " <> count (length s.snPath) "event") (Just path)
    [] -> pure (unlessIncomplete ("in every one of the " <> count (length g.gStates) "state" <> " explored"))
  Reachable -> case [ s | s <- g.gStates, lab s.snId == Right True ] of
    s : _ -> confirm (pathTo s) True [] Reached
    [] -> pure case incomplete of
      Just why -> Unknown why Nothing
      Nothing -> Violated ("no state of the " <> count (length g.gStates) "state" <> " explored satisfies it" <> clockNote) Nothing
  Stays -> do
    let steps = [ (t, ev) | t <- g.gTransitions, t.tnFrom /= t.tnTo, Just ev <- [Map.lookup (t.tnFrom, t.tnLabel, t.tnTo) g.gEdgeEvents] ]
        bad = [ (src, ev) | (t, ev) <- steps, lab t.tnFrom == Right True, lab t.tnTo == Right False, Just src <- [stateById t.tnFrom] ]
        unlabelledStep = [ () | (t, _) <- steps, isLeft' (lab t.tnFrom) || (lab t.tnFrom == Right True && isLeft' (lab t.tnTo)) ]
    case sortOn (\ (src, _) -> src.snDepth) bad of
      (src, ev) : _ ->
        let path = (pathTo src) {ptEvents = src.snPath <> [ev], ptStep = True}
        in confirm path False [(src.snPath, True)] \ path' ->
             Violated ("after " <> count (length path.ptEvents) "event" <> ": "
                       <> (case length src.snPath of
                             0 -> "it holds at the outset, and the first event takes it away"
                             n -> "it holds after the first " <> textShow n <> ", and the last takes it away")) (Just path')
      [] | not (null unlabelledStep) -> pure (Unknown unlabelledWhy Nothing)
         | otherwise -> pure case incomplete of
             Just why -> Unknown why Nothing
             Nothing -> Holds ("on every one of the " <> count (length steps) "step" <> " between states explored" <> clockNote)
  where
    lab i = fromMaybe (Left "not labelled") (Map.lookup p.prDecision.dcName labels >>= Map.lookup i)
    isLeft' = \ case Left _ -> True; Right _ -> False
    stateById i = find ((== i) . (.snId)) g.gStates
    pathTo s = MkPath {ptState = s.snId, ptEvents = s.snPath, ptStep = False}
    unlabelled = [ (s, why) | s <- g.gStates, Left why <- [lab s.snId] ]
    unlabelledWhy = case unlabelled of
      (s, why) : _ -> count (length unlabelled) "state" <> " could not be labelled; the first, s" <> textShow s.snId <> ": " <> why
      [] -> "a state could not be labelled"
    incomplete
      | not (null unlabelled) = Just unlabelledWhy
      | coverageComplete g.gCoverage = Nothing
      | otherwise = Just ("the exploration was not complete, so a state it did not reach may be the one: " <> incompleteText g.gCoverage)
    unlessIncomplete what = maybe (Holds (what <> clockNote)) (`Unknown` Nothing) incomplete
    clockNote = case opts.eoUntil of
      Just u | g.gCoverage.cvBeyondClock > 0 ->
        "; within the clock bound " <> prettyRatio u <> " (" <> count g.gCoverage.cvBeyondClock "tick" <> " past it not taken)"
      _ -> ""
    -- replay the path afresh and evaluate the property where it ends (and,
    -- for a step, where each prefix given ends): only a path that gives the
    -- answer the graph gave is reported as a counterexample or a witness.
    -- Then, when the caller can, run the #TRACE as printed, as source, and
    -- require it to leave the property's inputs as the replay left them
    confirm path expected prefixes ok = do
      full <- replayed path.ptEvents
      rest <- for prefixes \ (events, want) -> (events, want,) <$> replayed events
      let mismatch (events, want, got) = case got of
            Left why -> Just ("replaying it gave no answer: " <> why)
            Right (_, b)
              | b /= want -> Just ("replayed afresh, it is " <> boolText b <> " where the graph says " <> boolText want
                                   <> " (after " <> count (length events) "event" <> "): the explorer merged two positions the property tells apart")
              | otherwise -> Nothing
      source <- case (msource, full) of
        (Just run, Right (args, _)) -> asSource run path.ptEvents args
        _ -> pure Nothing
      pure case catMaybes (map mismatch ((path.ptEvents, expected, full) : rest)) <> maybeToList source of
        [] -> ok path
        why : _ -> Unknown ("the path the graph gives did not replay: " <> why) (Just path)
    replayed events = do
      mpos <- replayPath rig g.gStart events
      case mpos of
        Nothing -> pure (Left "the replay produced no result")
        Just pos -> decisionArgs p.prDecision pos.posResult.ledger >>= \ case
          Left why -> pure (Left why)
          Right as -> do
            rs <- evalBooleans rig [App emptyAnno p.prDecision.dcRef as]
            pure case rs of
              [Right b] -> Right (as, b)
              [Left why] -> Left why
              _ -> Left "the evaluator returned no answer"
    asSource run events args = do
      r <- run (traceText g.gStart "replayed by l4 explore before printing" events)
      case r of
        Left why -> pure (Just ("the printed #TRACE, run as source, " <> why))
        Right store -> decisionArgs p.prDecision store >>= \ case
          Left why -> pure (Just ("the printed #TRACE, run as source: " <> why))
          Right args'
            | map prettyLayout args' == map prettyLayout args -> pure Nothing
            | otherwise -> pure (Just ("the printed #TRACE, run as source, gives the property "
                <> Text.unwords (map prettyLayout args') <> " where the replay gives it " <> Text.unwords (map prettyLayout args)))

boolText :: Bool -> Text
boolText b = if b then "TRUE" else "FALSE"

-- | What the coverage line would say stopped the exploration short.
incompleteText :: Coverage -> Text
incompleteText cv = Text.intercalate "; " $ filter (not . Text.null)
  [ case cv.cvStops of
      [] -> ""
      ss -> "frontier not exhausted (" <> Text.intercalate ", " (map stopText ss) <> ")"
  , if null cv.cvRefused then "" else count (length cv.cvRefused) "refusal"
  , if null cv.cvUntried then "" else count (length cv.cvUntried) "kind" <> " of candidate untried"
  ]
  where
    stopText = \ case
      StopDepth b n  -> count n "state" <> " at the depth bound " <> textShow b
      StopStates b n -> count n "new state" <> " past the state bound " <> textShow b

----------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------

-- | The path as runnable source: a @#TRACE@ of the start with the path's
-- events, preceded by a comment saying what it shows. Pasted into the file
-- explored, @l4 run@ replays it (§5.4).
traceText :: Start -> Text -> [Expr Resolved] -> Text
traceText start comment events = Text.unlines $
  [ "-- " <> comment
  , "#TRACE " <> operand start.stContract <> " AT " <> operand start.stAt <> " WITH" ]
  <> [ "    " <> eventText e | e <- events ]
  where
    -- an event of a party is written as it prints; any other event (the
    -- tick, a `WAIT UNTIL`) in brackets, as an authored trace writes it
    eventText e = case e of
      Event {} -> oneLine (prettyLayout e)
      _        -> "(" <> oneLine (prettyLayout e) <> ")"
    operand e = case e of
      Var {}      -> oneLine (prettyLayout e)
      Lit {}      -> oneLine (prettyLayout e)
      App _ _ []  -> oneLine (prettyLayout e)
      _           -> "(" <> oneLine (prettyLayout e) <> ")"

-- | Printed source on one line: line breaks only are joined, so nothing
-- inside a string literal changes.
oneLine :: Text -> Text
oneLine = Text.intercalate " " . filter (not . Text.null) . map Text.strip . Text.lines

-- | @Checks (5): 1 violated, 3 hold, 1 unknown@.
checksSummary :: [CheckResult] -> Text
checksSummary rs = "Checks (" <> textShow (length rs) <> "): " <> Text.intercalate ", " (filter (not . Text.null)
  [ tally "violated" "violated" "violated"
  , tally "holds" "holds" "hold"
  , tally "unknown" "unknown" "unknown" ])
  where
    tally word one many =
      case length [ () | r <- rs, verdictWord r.crVerdict == word ] of
        0 -> ""
        1 -> "1 " <> one
        k -> textShow k <> " " <> many

-- | The checks as text: one verdict line per property with the cells it
-- read, and after a violated or reached one the replayed @#TRACE@, flush
-- left so that it can be pasted.
renderChecks :: Graph -> [CheckResult] -> [Text]
renderChecks g rs = checksSummary rs : concatMap one rs
  where
    one r =
      [ ""
      , requestText r.crProperty <> ": " <> verdictLine r.crVerdict
      , "  reads " <> Text.intercalate "; " (map readText r.crReads) ]
      <> case r.crVerdict of
           Violated _ (Just path) -> "" : traceLines path (comment r path "FALSE")
           Reached path -> "" : traceLines path (comment r path "TRUE")
           Unknown _ (Just path) -> "" : traceLines path ("NOT reproduced on replay; this path is a fault of the explorer, not a counterexample: " <> requestText r.crProperty)
           _ -> []
    verdictLine = \ case
      Holds what -> "holds " <> what
      Reached path -> "holds: reached after " <> count (length path.ptEvents) "event" <> " (state s" <> textShow path.ptState <> ")"
      Violated what (Just path) -> "violated " <> what <> " (" <> stateText path <> ")"
      Violated what Nothing -> "violated: " <> what
      Unknown why _ -> "unknown (" <> why <> ")"
    stateText path
      | path.ptStep = "the step from state s" <> textShow path.ptState
      | otherwise = "state s" <> textShow path.ptState
    comment r path word =
      "`" <> r.crProperty.prDecision.dcName <> "` is " <> word <> " after the " <> count (length path.ptEvents) "event" <> " below"
        <> (if path.ptStep then ", and TRUE before the last" else "")
        <> " (l4 explore; replayed on the evaluator)"
    traceLines path c = Text.lines (traceText g.gStart c path.ptEvents)
    readText (i, ledgers) =
      "`" <> i.inCell <> "` (" <> (if i.inWhole then "every entry" else "the latest entry") <> ", "
        <> (case ledgers of
              [] -> "never written in any state explored"
              ls -> "in " <> Text.intercalate " and " [ l <> "'s ledger" | l <- ls ])
        <> (if i.inWritten then "" else "; no RECORD, COMMIT or ATTEST in the file or its imports writes a cell of this name")
        <> ")"

-- | The checks and labels as JSON, merged into the graph's own object.
checksJson :: Graph -> [CheckResult] -> Labels -> Aeson.Value -> Aeson.Value
checksJson g rs labels = \ case
  Aeson.Object o -> Aeson.Object (KeyMap.insert (Key.fromText "checks") (Aeson.toJSON (map one rs))
                                   (KeyMap.insert (Key.fromText "labels") labelsJson o))
  other -> other
  where
    one r = Aeson.object
      [ "kind" .= kindWord r.crProperty.prKind
      , "property" .= r.crProperty.prDecision.dcName
      , "premise" .= fmap (.dcName) r.crProperty.prPremise
      , "verdict" .= verdictWord r.crVerdict
      , "reason" .= reasonOf r.crVerdict
      , "path" .= fmap pathJson (pathOf r.crVerdict)
      , "replayed" .= case r.crVerdict of
          Violated _ (Just _) -> Just True
          Reached _ -> Just True
          Unknown _ (Just _) -> Just False
          _ -> Nothing
      , "reads" .= [ Aeson.object ["cell" .= i.inCell, "whole" .= i.inWhole, "written" .= i.inWritten, "ledgers" .= ls] | (i, ls) <- r.crReads ]
      ]
    reasonOf = \ case
      Holds what -> what
      Reached _ -> "reached"
      Violated what _ -> what
      Unknown why _ -> why
    pathOf = \ case
      Reached p -> Just p
      Violated _ mp -> mp
      Unknown _ mp -> mp
      Holds _ -> Nothing
    pathJson p = Aeson.object
      [ "state" .= p.ptState
      , "step" .= p.ptStep
      , "events" .= map (oneLine . prettyLayout) p.ptEvents
      , "trace" .= traceText g.gStart (if p.ptStep then "a step" else "a path") p.ptEvents
      ]
    labelsJson = Aeson.object
      [ Key.fromText name .= Aeson.object
          [ Key.fromText ("s" <> textShow i) .= either (const Aeson.Null) Aeson.toJSON l | (i, l) <- Map.toList m ]
      | (name, m) <- Map.toList labels ]

count :: Int -> Text -> Text
count n w = textShow n <> " " <> w <> (if n == 1 then "" else "s")
