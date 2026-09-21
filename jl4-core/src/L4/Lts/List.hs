{-# LANGUAGE PatternSynonyms #-}
-- | The list baseline: the position of a @#TRACE@, as a plain-text list a
-- reader who does not program can follow.
--
-- This is P2a′ of @specs/todo/lexipedia-superset/LTS-VISUALISER.md@ (§1.1a,
-- §7.2): the rival the picture has to beat. It says nothing the back end
-- has not already said — the marking is "L4.Lts.Marking"'s, every
-- prediction is "L4.Lts.WhatIf"'s replay — it only puts words to them.
-- The words are chosen for the reader §1.1a has in mind, so nothing here
-- prints a Haskell constructor: an outcome is "done; on to what follows",
-- not @Matched ToHence@.
--
-- The four things the list answers, in the spec's numbering
-- (@STATEFUL-CONTRACT-DEPLOYMENT@ §6.4):
--
-- * what is owed, by whom, due when — endpoints 14\/15\/16 and, for a
--   barrier, the "held back: /n/ of /m/" line (§4.9);
-- * what would discharge it — endpoint 19;
-- * what would put you in breach — endpoint 20;
-- * the next deadline — endpoint 17.
--
-- And the two it does not (§1.1a): where in the contract you are, and what
-- happens after what you are about to do. The @--steps@ log is the
-- history, not the future.
--
-- == Loud and silent
--
-- * A candidate the what-if cannot run is LISTED under "could not be
--   tried", with the reason. It is never dropped, because a list that
--   omitted it would say "nothing else can happen".
-- * An act whose pattern BINDS a variable is a SET of acts, and the list
--   answers for the set: the line names the set, the verdict beside it is
--   the machine's for ONE act drawn from it, and the two lines under the
--   bullet ('boundLines') say which is which. That the binder matches
--   whatever the event carries is the rule's own text; that the act
--   discharges is the replay's word. The set goes under the heading its
--   witness's verdict puts it under, and only a witness the contract
--   passed over, or none at all, leaves it under "could not be tried".
-- * The enabled set is an over-approximation of what the contract allows
--   (spec §1.1b, G9): a tick or an act that the replay reports as
--   advancing may be one the contract's own guards would refuse in a
--   fuller run. The replay is the machine's word for THIS position only.
-- * A fresh position ('freshTrace') is the contract at its @AT 0@ with no
--   events, exactly as @#TRACE c AT 0 WITH@ would give. It is not "the
--   contract in general".
-- * "Next deadline" is the soonest deadline the machine CONFIRMED. A tick
--   the replay refused ('confirmTick') is a number the machine did not
--   bear out, and it is never printed as a date; the obligation is named
--   on the line as one whose deadline is not known here, so the soonest
--   confirmed date is never read as the soonest date.
module L4.Lts.List
  ( -- * The report
    TraceReport (..)
  , Standing (..)
  , reportOf
  , reportFrom
    -- * A trace that is not in the file
  , freshTrace
    -- * Rendering
  , renderReport
  , renderStep
  , reportJson
  ) where

import Base
import qualified Base.Text as Text
import Base.Text (textShow)
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import Data.Aeson.Types (Pair)

import L4.Annotation (HasSrcRange (..), emptyAnno)
import L4.Evaluate.ValueLazy (NF (..), RBinOp (..), Value (..))
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , prettyEvalException
  , prettyRefusal
  )
import L4.EvaluateLazy.DeonticStep
import L4.EvaluateLazy.Machine (pattern ValFulfilled)
import L4.Lts.Marking
import L4.Lts.WhatIf
-- the fields are what @rangeOf …@'s @.start.line@ resolves through
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Print (prettyLayout)
import L4.Syntax
import L4.Utils.Ratio (prettyRatio)

-- | Everything the list says about one @#TRACE@.
data TraceReport = MkTraceReport
  { rpContract :: !Text
    -- ^ the contract as the directive names it
  , rpLine     :: !(Maybe Int)
    -- ^ the directive's line in its file; 'Nothing' for a 'freshTrace'
  , rpEvents   :: ![Text]
    -- ^ the events as written, in order
  , rpClock    :: !Rational
    -- ^ where the contract clock stands after them
  , rpStanding :: !Standing
  , rpOwed     :: ![NormPlacement]
    -- ^ the marking: empty when the contract has ended
  , rpEnabled  :: ![Outcome]
    -- ^ every candidate, tried, in the what-if's order
  , rpNext     :: !(Maybe (Rational, [LiveNorm]))
    -- ^ endpoint 17: the soonest live deadline the machine CONFIRMED (a
    -- 'TickPast' whose verdict is not 'Untried'), and whose it is. A
    -- deadline 'deadlineOf' computed and the machine refused is not a
    -- deadline this reports (§2.4); it is in 'rpUnknown' instead
  , rpUnknown  :: ![LiveNorm]
    -- ^ the live obligations that have a deadline the list could not
    -- confirm: a 'NoTick' with a @WITHIN@, or a 'TickPast' the replay
    -- refused. Named on the "Next deadline" line, so that the soonest
    -- confirmed date is never read as the soonest date
  , rpDeadlines :: ![(LiveNorm, Rational)]
    -- ^ every live obligation whose absolute deadline the what-if computed
    -- AND the machine confirmed (the tick past it revealed an expiry, see
    -- 'confirmTick'); an obligation whose @WITHIN@ the residual still
    -- holds unevaluated is dated through this, not guessed
  , rpActions  :: ![(LiveNorm, Text)]
    -- ^ every live obligation whose act the what-if could instantiate, with
    -- that act as it would be written (@payment OF 2@, the @EXACTLY n@
    -- read through the heap); the "Owed now" line names this rather than
    -- the pattern (@payment (EXACTLY n)@) when it is known
  , rpSteps    :: ![DeonticStep]
    -- ^ the step log of the trace as written
  }

-- | Where the contract stands after the events.
data Standing
  = InProgress
  | Fulfilled
  | InBreach !Blame
  | NotEvaluated !Text   -- ^ the directive errored or refused; the text says why
  deriving stock (Eq, Show)

-- | Replay the trace, try every candidate, and gather the answers.
reportOf :: Rig -> Trace -> IO (Maybe TraceReport)
reportOf rig tr = fmap (reportFrom tr) <$> enabledSet rig tr

-- | The answers, read off an enabled set already tried. Pure, so that a
-- test can hand it an outcome the replay would not produce on its own.
reportFrom :: Trace -> EnabledSet -> TraceReport
reportFrom tr es =
  MkTraceReport
    { rpContract = prettyLayout tr.trContract
    , rpLine     = (.start.line) <$> rangeOf tr.trDirective
    , rpEvents   = map (Text.unwords . Text.words . prettyLayout) tr.trEvents
    , rpClock    = pos.posClock
    , rpStanding = standing
    , rpOwed     = case standing of
        InProgress -> pos.posMarking
        _          -> []   -- a breach is the standing, not a place owed
    , rpEnabled  = es.esOutcomes
    , rpNext     = listToMaybe (sortOn fst confirmedTicks)
    , rpUnknown  = unknown
    , rpDeadlines = [ (n, d) | (d, ns) <- confirmedTicks, n <- ns ]
    , rpActions  = [ (n, prettyLayout a) | o <- es.esOutcomes, ActBy n <- [o.ocCandidate.cdKind], Just a <- [o.ocCandidate.cdShape] ]
    , rpSteps    = pos.posSteps
    }
  where
    pos = es.esPosition
    standing = standingOf pos.posResult
    -- only a tick the machine confirmed dates anything (§2.4): 'confirmTick'
    -- turns a tick whose arithmetic the machine did not bear out into an
    -- 'Untried', and that number is exactly the one not to print
    confirmedTicks = [ (d, ns) | o <- es.esOutcomes, TickPast d ns <- [o.ocCandidate.cdKind], notUntried o.ocVerdict ]
    unknown =
      [ n | o <- es.esOutcomes, TickPast _ ns <- [o.ocCandidate.cdKind], not (notUntried o.ocVerdict), n <- ns ]
      <> [ n | o <- es.esOutcomes, NoTick n <- [o.ocCandidate.cdKind], hasDeadline n ]
    notUntried = \ case
      Untried _ -> False
      _         -> True
    hasDeadline n = case n.lnDue of
      NoDeadline -> False
      _          -> True

standingOf :: EvalDirectiveResult -> Standing
standingOf res = case res.result of
  Reduction (Reduced (MkNF v)) -> case v of
    ValFulfilled  -> Fulfilled
    ValBreached r -> InBreach (blameOf r)
    _             -> InProgress
  Reduction (Reduced Omitted)    -> NotEvaluated "the result was omitted"
  Reduction (ReducedRefused ref) -> NotEvaluated (Text.unlines (prettyRefusal ref))
  Reduction (ReducedErrored exc) -> NotEvaluated (Text.unlines (prettyEvalException exc))
  Assertion _                    -> NotEvaluated "not a #TRACE"

-- | A @#TRACE name AT 0 WITH@ — no events — for a top-level rule the file
-- does not trace, so that a contract can be listed at its outset without
-- editing the file. The rule must be defined at the top level under
-- exactly that name and take no inputs; the directive is appended to the
-- module so the replay can find it ('replay' matches directives by
-- equality with the ones the module carries).
--
-- The name is matched as written, without backticks: @the tenancy@ finds
-- @`the tenancy` MEANS …@.
freshTrace :: Module Resolved -> Text -> Either Text (Module Resolved, Trace)
freshTrace (MkModule a uri (MkSection sa sn saka sg decls)) wanted =
  case [ (u, n) | Decide _ (MkDecide _ _ (MkAppForm _ (Def u n) [] _) _) <- decls, nameToText n == wanted ] of
    [] -> Left ("no top-level rule named `" <> wanted <> "` that takes no inputs")
    ((u, n) : _) ->
      let contract  = Var emptyAnno (Ref n u n)
          start     = Lit emptyAnno (NumericLit emptyAnno 0)
          directive = Contract emptyAnno contract start []
          m' = MkModule a uri (MkSection sa sn saka sg (decls <> [Directive emptyAnno directive]))
      in Right (m', MkTrace {trDirective = directive, trContract = contract, trStart = start, trEvents = []})

----------------------------------------------------------------------------
-- Text
----------------------------------------------------------------------------

-- | The list, as text. The step log is appended when asked for.
renderReport :: Bool -> TraceReport -> Text
renderReport withSteps rp = Text.unlines $
  [ heading ]
  <> map ("    " <>) rp.rpEvents
  <> [ "  " <> standingLine ]
  <> owedBlock
  <> block "What would discharge it (the contract ends fulfilled):" discharges
  <> block "What would put someone in breach:" breaches
  <> block "What would move things along (neither ends nor breaches it):" advances
  <> block "What the contract would pass over (nothing changes):" ignored
  <> block "What could not be tried:" untriable
  <> nextLine
  <> stepsBlock
  where
    heading =
      rp.rpContract <> " — "
      <> (case rp.rpEvents of
            [] -> "before anything has happened"
            es -> "after " <> count (length es) "event")
      <> ", the clock stands at " <> prettyRatio rp.rpClock
      <> maybe "" (\ l -> " (the #TRACE on line " <> textShow l <> ")") rp.rpLine

    standingLine = case rp.rpStanding of
      InProgress     -> "Standing: in progress."
      Fulfilled      -> "Standing: FULFILLED — nothing more is owed."
      InBreach b     -> "Standing: BREACHED — " <> blameLine b <> "."
      NotEvaluated t -> "Standing: could not be worked out — " <> Text.strip t

    owedBlock = case rp.rpStanding of
      InProgress | null rp.rpOwed -> ["", "  Owed now: nothing."]
      InProgress -> "" : "  Owed now:" : map (("    - " <>) . placementLine rp.rpDeadlines rp.rpActions rp.rpClock) rp.rpOwed
      _ -> []

    -- an item is one or more lines; only its first gets the bullet
    discharges = [ [candidateLine o <> " → fulfilled"] <> boundLines o | o <- rp.rpEnabled, Discharging <- [o.ocVerdict] ]
    breaches   = [ [candidateLine o <> " → " <> blameLine b] <> boundLines o | o <- rp.rpEnabled, Breaching b <- [o.ocVerdict] ]
    advances   =
      [ (candidateLine o <> " → then:") : map (("    · " <>) . placementLine [] [] (stampOf o)) m <> boundLines o
      | o <- rp.rpEnabled, Advancing m <- [o.ocVerdict] ]
    ignored    = [ [candidateLine o <> " — " <> passOverWords why] | o <- rp.rpEnabled, PassedOver why <- [o.ocVerdict] ]
    untriable  = [ [candidateLine o <> " — " <> Text.strip why] | o <- rp.rpEnabled, Untried why <- [o.ocVerdict] ]

    block _ [] = []
    block title items = "" : ("  " <> title) : concatMap bullet items
    bullet = \ case
      []       -> []
      (l : ls) -> ("    - " <> l) : map ("      " <>) ls

    -- endpoint 17, from confirmed ticks only; an obligation whose deadline
    -- the list could not confirm is named, never silently left out
    nextLine = case (rp.rpNext, rp.rpUnknown) of
      (Nothing, []) -> []
      (Just (d, ns), []) -> [ "", "  Next deadline: " <> soonest d ns ]
      (Just (d, ns), us) -> [ "", "  Next deadline: " <> soonest d ns <> " — not counting " <> whose us <> ", whose deadline is not known here" ]
      (Nothing, us) -> [ "", "  Next deadline: not known here — " <> whose us <> " " <> hasHave us <> " a deadline this list could not work out" ]
    soonest d ns = prettyRatio d <> " (" <> whose ns <> ")"
    whose = Text.intercalate "; " . map (whoseNorm rp.rpActions)
    hasHave = \ case
      [_] -> "has"
      _   -> "have"

    stepsBlock
      | not withSteps = []
      | null rp.rpSteps = ["", "  Steps: none were logged."]
      | otherwise = "" : "  Steps, in order:" : map (("    " <>) . renderStep) rp.rpSteps

    -- the clock a candidate's outcome is relative to: the hypothetical's stamp
    stampOf o = either (const rp.rpClock) (.hyAt) o.ocCandidate.cdHypothetical

-- | Why the contract passed an act over, in words. The classification is
-- the what-if's ('confirmAct', read from the machine's steps); this only
-- puts words to it.
passOverWords :: PassOver -> Text
passOverWords = \ case
  GuardFalse    -> "its condition (PROVIDED) does not hold"
  TooEarly open -> "the window has not opened yet (it opens at " <> prettyRatio open <> "; an act before then counts for nothing)"
  WrongAct      -> "it is not the act awaited"
  WrongParty    -> "it is not this party's to do"
  NoTaker       -> "no obligation in force took it"

-- | One place on the norm plane, in words. The clock is what a residual
-- countdown counts from, so the due date can be given absolutely; an
-- obligation whose countdown has not started is dated from the confirmed
-- deadlines when it is among them. The act is named as it would be written
-- when the what-if could instantiate it ('TraceReport.rpActions'), else as
-- the pattern.
placementLine :: [(LiveNorm, Rational)] -> [(LiveNorm, Text)] -> Rational -> NormPlacement -> Text
placementLine confirmed actions clock = \ case
  InEffect n -> Text.unwords $ [ normLine actions n ] <> dueWords n (lookup n confirmed) <> familyWords n.lnMember
  Awaiting {awProgress} -> case awProgress of
    Nothing -> "the next step is held back until the group has acted (how many have is not known here)"
    Just p ->
      "the next step is held back until " <> thresholdWords p.prThreshold
      <> ": " <> textShow p.prDone <> " of " <> textShow p.prTotal <> " have"
  Created {crSource} -> "not yet started: " <> crSource
  Violated b -> "in breach: " <> blameLine b
  Lapsed b -> "no longer available (this alternative was lost; the contract stands): " <> blameLine b
  where
    dueWords n known = case (n.lnDue, known) of
      (NoDeadline, _)               -> ["— no deadline" <> opensClause]
      -- an unanchored WITHIN counts from now; an anchored one (@WITHIN d OF
      -- anchor@) counts from its anchor, so "from now" would be false of it
      -- — and so would it be of a bare WITHIN beside an AFTER, which counts
      -- from the instant the window opens (re-anchor, R-X5 as amended):
      -- that one is worded as the rule wrote it, AFTER n WITHIN d
      (UnforcedDeadline t Nothing, Just d)
        | Just o <- unforcedOpening         -> ["— due by " <> prettyRatio d <> " (" <> o <> " WITHIN " <> t <> ")"]
        | otherwise                         -> ["— due by " <> prettyRatio d <> " (" <> t <> " from now)"]
      (UnforcedDeadline t (Just a), Just d)  -> ["— due by " <> prettyRatio d <> " (WITHIN " <> t <> " OF " <> a <> ")" <> opensClause]
      (UnforcedDeadline t Nothing, Nothing)
        | Just o <- unforcedOpening         -> ["— due " <> o <> " WITHIN " <> t]
        | otherwise                         -> ["— due within " <> t <> " from now"]
      (UnforcedDeadline t (Just a), Nothing) -> ["— due WITHIN " <> t <> " OF " <> a <> opensClause]
      -- a BEFORE date is an instant: no "from now", no anchor
      (UnforcedBefore t, Just d)             -> ["— due by " <> prettyRatio d <> " (BEFORE " <> t <> ")" <> opensClause]
      (UnforcedBefore t, Nothing)            -> ["— due BEFORE " <> t <> opensClause]
      -- a residual due counts from the last event seen — or, while the
      -- window has still to open, from the OPENING (the machine's
      -- @relativeDue@): the deadline is then clock + opening + remaining,
      -- and the reader is told where the window opens
      (Remaining r, _) -> case n.lnOpens of
        OpensIn o -> ["— due by " <> prettyRatio (clock + o + r) <> " (" <> prettyRatio (o + r) <> " from now; the window opens at " <> prettyRatio (clock + o) <> ")"]
        _         -> ["— due by " <> prettyRatio (clock + r) <> " (" <> prettyRatio r <> " from now)"]
      where
        -- the AFTER clause as the rule wrote it, for a window not yet evaluated
        unforcedOpening = case n.lnOpens of
          UnforcedOpening o ma -> Just ("AFTER " <> o <> maybe "" (" OF " <>) ma)
          _                    -> Nothing
        -- a pending opening the due wording does not already carry
        opensClause = case n.lnOpens of
          NoOpening            -> ""
          OpensIn o            -> "; the window opens at " <> prettyRatio (clock + o)
          UnforcedOpening o ma -> "; the window opens AFTER " <> o <> maybe "" (" OF " <>) ma
    familyWords = \ case
      Nothing -> []
      Just f  -> ["(" <> familyLine f <> ")"]
    thresholdWords = \ case
      AllHave _ -> "all have acted"

-- | @who MUST what@, as the contract says it.
normLine :: [(LiveNorm, Text)] -> LiveNorm -> Text
normLine actions n = Text.unwords [ bearerText n.lnBearer, modalWord n.lnModal, actionText actions n ]

whoseNorm :: [(LiveNorm, Text)] -> LiveNorm -> Text
whoseNorm actions n = bearerText n.lnBearer <> ": " <> actionText actions n

-- | The act as it would be written, when known; else the pattern.
actionText :: [(LiveNorm, Text)] -> LiveNorm -> Text
actionText actions n = fromMaybe n.lnAction (lookup n actions)

bearerText :: Bearer -> Text
bearerText = \ case
  KnownParty t    -> t
  UnforcedParty t -> t

modalWord :: DeonticModal -> Text
modalWord = \ case
  DMust    -> "MUST"
  DMay     -> "MAY"
  DMustNot -> "SHANT"
  DDo      -> "DO"

familyLine :: Family -> Text
familyLine f = case f.faJoin of
  Barrier _    -> "one of " <> textShow f.faTotal <> " who must all act before the next step"
  Fork         -> "one of " <> textShow f.faTotal <> ", each with a next step of their own"
  Distributive -> "one of " <> textShow f.faTotal

-- | The hypothetical, in words: who does what, or time passing. An act the
-- what-if refused is still named as far as the residual could instantiate
-- it ('Candidate.cdShape'), and as the pattern only when it could not at
-- all.
candidateLine :: Outcome -> Text
candidateLine o = case (o.ocCandidate.cdKind, o.ocCandidate.cdHypothetical) of
  -- a binding pattern names a SET of acts; the line is the set, and the
  -- witness that was actually replayed is printed under it ('boundLines')
  (ActBy n, hyp) | Just b <- o.ocCandidate.cdBound ->
    bearerText n.lnBearer <> " does " <> boundSetText b (shapeOr n)
      <> either (const "") (\ h -> " now (at " <> prettyRatio h.hyAt <> ")") hyp
  (ActBy n, Right h)       -> bearerText n.lnBearer <> " does " <> prettyLayout h.hyAction <> " now (at " <> prettyRatio h.hyAt <> ")"
  (ActBy n, Left _)        -> bearerText n.lnBearer <> " does " <> shapeOr n
  (TickPast d _, Right h)  -> "nothing happens by " <> prettyRatio d <> " (the clock reaches " <> prettyRatio h.hyAt <> ")"
  (TickPast d _, Left _)   -> "nothing happens by " <> prettyRatio d
  (NoTick n, _)            -> "time runs out on " <> normLine [] n
  where
    shapeOr n = maybe n.lnAction prettyLayout o.ocCandidate.cdShape

-- | The SET of acts a binding action pattern describes, in words. A binder
-- that IS the whole action leaves nothing else to name, so it is
-- "anything"; a binder in an operand keeps the act and frees that place.
-- The @PROVIDED@ guard is the set's only narrowing, and it is printed as
-- the rule wrote it with whatever the residual has already computed read
-- back into it ('L4.Lts.WhatIf.BoundAct').
boundSetText :: BoundAct -> Text -> Text
boundSetText b shape = case b.baScope of
  BoundWholeAction -> "anything" <> constraint
  BoundArgument    -> shape <> ", with any " <> binderNames b <> constraint
  where
    constraint = maybe "" (\ g -> " for which " <> g <> " holds") b.baGuard

-- | What the reader is owed beside a bound act's verdict: how far the set
-- reaches, and that the verdict above came from replaying ONE act drawn
-- from it. The two are different kinds of claim — the reach is the rule's
-- own text, the verdict is the machine's — and saying so is the only thing
-- that lets the verdict be read as the set's.
boundLines :: Outcome -> [Text]
boundLines o = case (o.ocCandidate.cdKind, o.ocCandidate.cdBound) of
  (ActBy n, Just b) | Right vs <- b.baWitness ->
    [ reach n b
    , "checked by replaying one act from that set, with " <> valuesText vs
    ]
  -- no witness: the set is named under "could not be tried", with the
  -- what-if's own reason, and nothing was replayed to add to it
  _ -> []
  where
    reach n b = case (b.baScope, b.baGuard) of
      (BoundWholeAction, Nothing) ->
        "any act by " <> bearerText n.lnBearer <> " counts: the rule binds "
        <> binderNames b <> " rather than naming an act"
      (BoundArgument, Nothing) ->
        "any " <> binderNames b <> " counts: the rule binds it and does not test it"
      (_, Just _) ->
        "any " <> binderNames b <> " the condition accepts counts: the rule binds it and tests it only through that condition"

binderNames :: BoundAct -> Text
binderNames b = Text.intercalate " and " (map binderName b.baBinders)

-- | A binder, spelled as the rule wrote it and without its section — the
-- spelling the action printed beside it uses.
binderName :: Resolved -> Text
binderName r = "`" <> unqualifiedNameToText (getOriginal r) <> "`"

-- | @`amount` = 0@, for as many binders as the pattern has.
valuesText :: [(Resolved, Expr Resolved)] -> Text
valuesText vs = Text.intercalate ", " [ binderName r <> " = " <> prettyLayout e | (r, e) <- vs ]

-- | A breach, in words. The machine's own no-party clock event is the
-- "revealing" act when a deadline is missed on a tick; it has no name a
-- reader should see, so it is rendered as the clock.
--
-- Since R-T3 a breach names every obligation that failed (EVERY-EACH-
-- QUANTIFIER-SPEC §6.1): the line's headline is the ANCHOR — the failure the
-- breach's time comes from, which for a single obligation's breach is the
-- whole story — and a compound's other failures follow it, in the
-- drafter's order, so none is dropped.
blameLine :: Blame -> Text
blameLine b = Text.concat $ catMaybes
  [ Just (maybe "the contract is in breach (no party is named)" (<> " is in breach") b.blParty)
  , (\ o -> ": " <> o <> maybe "" (\ d -> " was due by " <> prettyRatio d) b.blDeadline) <$> b.blObliged
  , revealed
  , case (b.blObliged, b.blReason) of
      (Nothing, Just r) -> Just (" — " <> reasonText r)
      _ -> Nothing
  , case b.blNamed of
      (_ : _ : _) -> Just ("; the breach names, in order: " <> Text.intercalate ", " (map entryText b.blNamed))
      _           -> Nothing
  ]
  where
    entryText e = Text.concat $ catMaybes
      [ Just (fromMaybe "(nobody named)" e.beParty)
      , (\ o -> " (" <> o <> maybe "" (\ d -> ", due by " <> prettyRatio d) e.beDeadline <> ")") <$> e.beObliged
      , (\ r -> " (" <> reasonText r <> ")") <$> e.beReason
      ]
    revealed = case (b.blAction, b.blStamp) of
      (Just a, Just t)
        | isClockSentinel a -> Just ("; the clock reached " <> prettyRatio t <> " without it")
        | otherwise -> Just ("; seen at " <> prettyRatio t <> ", when " <> a <> " happened instead")
      (Nothing, Just t) -> Just ("; at " <> prettyRatio t)
      _ -> Nothing

-- | Is this the machine's own no-party clock event (a @WAIT UNTIL@)? Its
-- party and action are the builtins @neverMatchesParty@ \/
-- @neverMatchesAct@, whose surface names are @NEVERMATCHESPARTY@ \/
-- @NEVERMATCHESACT@ because the builtin environment upper-cases every
-- builtin that is not given a @rename@ (@TypeCheck/Environment/TH.hs@,
-- @mkBuiltin@; the two are listed without one in @Environment.hs@). The
-- ledger key ('partyKeyWHNF') does no casing of its own.
isClockSentinel :: Text -> Bool
isClockSentinel a = "nevermatches" `Text.isPrefixOf` Text.toLower a

-- | A breach reason with the clock sentinels put into words.
reasonText :: Text -> Text
reasonText r
  | any isClockSentinel (Text.words r) = "revealed when the clock ran on with nothing happening"
  | otherwise = r

-- | One step of the log, clock first, in words. The step's own vocabulary
-- ('StepOutcome') names machine frames; this names what happened.
--
-- A party is written as the rest of the list writes it — @Tenant OF
-- "Alice"@ — when the log had its name ('NormKey.nkBearerName',
-- 'EventKey.ekPartyName': recorded once the machine had forced the
-- party's fields, which the party comparison does). A party or an action
-- the machine had not fully looked at when the step was logged is keyed by
-- its partly-evaluated layout ('NormKey.nkBearer': "unforced fields and
-- all"), which prints a heap reference such as @Tenant OF &229\@file.l4@.
-- That is the log's limit, not the reader's business: the reference is
-- elided to @…@ here, and the member ordinal (@member 2 of 3@) is what
-- tells the members of a cast apart on such a step.
--
-- A party the machine has not looked at AT ALL — no key, no name — is
-- written as the rule wrote it, marked so ('NormKey.nkBearerSource':
-- @theLandlord (as written; not yet resolved) MUST@). That is the case of
-- the no-@LEST@ breach of a computed party (O1, 2026-09-19): the machine
-- allocates the party as a thunk it never has to force, and the log peeks
-- and never forces, so the written form is all it has. It is source, not
-- a resolved party: @theLandlord@ here and @Landlord OF "Ms Ng"@ on the
-- Standing line beside it are the same party under two spellings, and the
-- marker is what stops a reader from reading the name as a third person.
-- "(party not yet known)" remains for a key with no written form either,
-- which today is only a join's own key (worded "the group" below).
renderStep :: DeonticStep -> Text
renderStep s = Text.unwords $ catMaybes
  [ Just (maybe "at —:" (\ c -> "at " <> prettyRatio c <> ":") s.dsClock)
  , eventWords <$> s.dsEvent
  , if isJoinStep then Just "the group —" else normWords <$> s.dsNorm
  , Just (outcomeWords s.dsOutcome)
  , joinWords <$> s.dsJoin
  , scrutinyWords s.dsScrutiny
  ]
  where
    -- The barrier's own steps carry the join's key ('armJoinKey'): no
    -- bearer, and a modal that is the members', not the group's. "(party not
    -- yet known) MUST" is what that key says; "the group" is what it means.
    isJoinStep = case s.dsOutcome of
      JoinReleased   -> True
      JoinExpired {} -> True
      JoinFailed {}  -> True
      JoinStalled    -> True
      _              -> False
    eventWords e = (<> ";") case (e.ekParty, e.ekAction) of
      (Nothing, Nothing) -> "the event at " <> prettyRatio e.ekStamp
      (_, Just a) | isClockSentinel a -> "the clock runs to " <> prettyRatio e.ekStamp <> " with nothing happening"
      (p, a) -> fromMaybe "someone" (partyText e.ekPartyName p) <> " does " <> maybe "something" elide a <> " at " <> prettyRatio e.ekStamp
    normWords k = Text.unwords $ catMaybes
      [ Just (fromMaybe "(party not yet known)" (stepBearerText k))
      , Just (modalWord k.nkModal)
      , (\ m -> "(member " <> textShow m.moIndex <> " of " <> textShow m.moTotal <> ")") <$> k.nkMember
      , Just "—" ]
    outcomeWords = \ case
      Waiting          -> "no more events; still waiting"
      PartyMismatch    -> "not this party's event; passed over"
      ActionMismatch   -> "not the act awaited; passed over"
      GuardFailed      -> "the act matched but its condition did not hold; passed over"
      EarlyAct open    -> "the act came before the window opens at " <> prettyRatio open <> "; it counts for nothing and is passed over"
      Matched br       -> "done; " <> branchWords br
      Expired br d     -> "deadline " <> prettyRatio d <> " passed without the act; " <> branchWords br
      Breached b       -> "BREACH declared" <> maybe "" (" by " <>) (partyText b.bsBlameName b.bsBlame) <> namedWords b
      Joined op note   -> opWords op <> ": " <> joinResultWords note
      JoinReleased     -> "everyone has acted; the shared next step begins"
      JoinExpired br d -> "everyone has acted, but after the group's deadline " <> prettyRatio d <> "; " <> branchWords br
      JoinFailed br    -> "a member did not come through; " <> branchWords br
      JoinStalled      -> "a member's permission lapsed; the group's next step can never begin"
    branchWords = \ case
      ToHence  -> "on to what follows"
      ToLest   -> "on to the fallback"
      ToBreach -> "that is a breach"
    opWords = \ case
      ValRAnd -> "both parts together"
      ValROr  -> "either part"
    joinResultWords note = case note.jnResult of
      JoinFulfilled  -> "fulfilled" <> sideWords note
      JoinBreached b -> "breached" <> maybe "" (" by " <>) (partyText b.bsBlameName b.bsBlame) <> sideWords note <> namedWords b
      JoinPending    -> "still open"
    -- R-T3: a breach that names more than its anchor lists every failure,
    -- in order, so the log drops none of them. A failure's party has no
    -- written form to fall back on: a 'FailureSummary' is read off a
    -- 'L4.Evaluate.ValueLazy.Failure', which holds the party as a heap
    -- reference and nothing else (O1 left it: carrying the syntax there is
    -- a change to a wire type, not to the log).
    namedWords b = case b.bsFailures of
      (_ : _ : _) -> "; names, in order: " <> Text.intercalate ", " (map failureWords b.bsFailures)
      _           -> ""
    failureWords = \ case
      MissedSummary p a d -> maybe "(party not yet known)" elide p <> " (" <> elide a <> ", due " <> prettyRatio d <> ")"
      DeclaredSummary p r -> namedPartyWords p <> maybe "" (\ t -> " (" <> reasonText t <> ")") r
    -- "nobody named" is what the SOURCE says; "not yet known" is what the RUN
    -- has forced — a BY the machine has not forced is still a BY
    namedPartyWords = \ case
      NobodyNamed          -> "(nobody named)"
      PartyNamed Nothing   -> "(party not yet known)"
      PartyNamed (Just t)  -> elide t
    sideWords note = case note.jnWinner of
      Nothing -> ""
      Just LeftSide  -> " (decided by the first part" <> tie note <> ")"
      Just RightSide -> " (decided by the second part" <> tie note <> ")"
      Just BothSides -> ""
    tie note = if note.jnTieBreak then ", by the tie-break rule" else ""
    joinWords = \ case
      MemberSatisfied n m -> "(" <> textShow n <> " of " <> textShow m <> " have acted; the shared next step waits for the rest)"
      ForkContinued i m   -> "(member " <> textShow i <> " of " <> textShow m <> ": their own next step begins)"
    scrutinyWords = \ case
      Reoffered -> Just "[the same event, offered a second time]"
      _         -> Nothing

-- | A party as a step names it: its rendered name when the log had it,
-- else its ledger key with the heap references elided, else nothing.
partyText :: Maybe Text -> Maybe Text -> Maybe Text
partyText name key = name `mplus` fmap elide key

-- | A norm's bearer as a step names it: 'partyText' over the key's two
-- renderings of the value, else the party as written, marked as such so
-- it cannot be mistaken for a resolved party (O1). 'Nothing' only for a
-- key with no written form either.
stepBearerText :: NormKey -> Maybe Text
stepBearerText k =
  partyText k.nkBearerName k.nkBearer `mplus` fmap (<> " (as written; not yet resolved)") k.nkBearerSource

-- | The bearer as the JSON writes it: the resolved party under @party@
-- (null when the machine had not looked at it), and, only then, the party
-- as written under @partyAsWritten@ when the key has it. Adding the second
-- field changes no existing field's meaning, so @format@ stays at 1.
bearerJson :: NormKey -> [Pair]
bearerJson k = case partyText k.nkBearerName k.nkBearer of
  Just p  -> ["party" .= p]
  Nothing -> ["party" .= Aeson.Null] <> maybe [] (\ w -> ["partyAsWritten" .= w]) k.nkBearerSource

-- | Elide heap references (@&229\@file.l4@) in a machine-keyed text,
-- keeping the punctuation around them.
elide :: Text -> Text
elide = Text.unwords . map ref . Text.words
  where
    ref w =
      let (open, rest) = Text.span (== '(') w
          (body, close) = (Text.dropWhileEnd isClose rest, Text.takeWhileEnd isClose rest)
          isClose = (`elem` (",)" :: String))
      in if "&" `Text.isPrefixOf` body && "@" `Text.isInfixOf` body
           then open <> "…" <> close
           else w

count :: Int -> Text -> Text
count 1 noun = "1 " <> noun
count n noun = textShow n <> " " <> noun <> "s"

----------------------------------------------------------------------------
-- JSON
----------------------------------------------------------------------------

-- | The same list, as JSON, for a program to read. Every discriminator is
-- a stable camelCase token, never prose: prose is for 'renderReport', and
-- a consumer that switches on @"kind"@ must not break when the wording
-- does. Numbers on the contract clock are rendered as JSON numbers (a
-- 'Rational' that is not a terminating decimal, such as @1/3@, is rounded
-- to a 'Double'); source ranges are dropped. @format@ is the shape's
-- version, bumped whenever a key or token changes meaning.
jsonFormat :: Int
jsonFormat = 1

reportJson :: Bool -> TraceReport -> Aeson.Value
reportJson withSteps rp = Aeson.object $
  [ "format"     .= jsonFormat
  , "contract"   .= rp.rpContract
  , "line"       .= rp.rpLine
  , "events"     .= rp.rpEvents
  , "clock"      .= ratio rp.rpClock
  , "standing"   .= standingJson rp.rpStanding
  , "owed"       .= map (placementJson rp.rpDeadlines rp.rpActions rp.rpClock) rp.rpOwed
  , "discharging" .= [ candidateJson o | o <- rp.rpEnabled, Discharging <- [o.ocVerdict] ]
  , "breaching"  .= [ Aeson.object ["event" .= candidateJson o, "breach" .= blameJson b] | o <- rp.rpEnabled, Breaching b <- [o.ocVerdict] ]
  , "advancing"  .= [ Aeson.object ["event" .= candidateJson o, "then" .= map (placementJson [] [] (stampOf o)) m] | o <- rp.rpEnabled, Advancing m <- [o.ocVerdict] ]
  , "passedOver" .= [ Aeson.object (["event" .= candidateJson o, "reason" .= passOverToken why, "why" .= passOverWords why] <> passOverFields why) | o <- rp.rpEnabled, PassedOver why <- [o.ocVerdict] ]
  , "untried"    .= [ Aeson.object ["event" .= candidateJson o, "why" .= Text.strip why] | o <- rp.rpEnabled, Untried why <- [o.ocVerdict] ]
  , "nextDeadline" .= fmap (\ (d, ns) -> Aeson.object ["at" .= ratio d, "whose" .= map (normJson rp.rpActions) ns]) rp.rpNext
  , "deadlineNotKnown" .= map (normJson rp.rpActions) rp.rpUnknown
  ]
  <> [ "steps" .= map stepJson rp.rpSteps | withSteps ]
  where
    stampOf o = either (const rp.rpClock) (.hyAt) o.ocCandidate.cdHypothetical

ratio :: Rational -> Aeson.Value
ratio r = Aeson.toJSON (fromRational r :: Double)

-- | The token a pass-over is filed under; 'passOverWords' is the sentence.
passOverToken :: PassOver -> Text
passOverToken = \ case
  GuardFalse -> "guardFalse"
  TooEarly _ -> "tooEarly"
  WrongAct   -> "wrongAct"
  WrongParty -> "wrongParty"
  NoTaker    -> "noTaker"

-- | What a pass-over carries besides its token: the opening a too-early act
-- missed, on the contract clock.
passOverFields :: PassOver -> [(Aeson.Key, Aeson.Value)]
passOverFields = \ case
  TooEarly open -> ["opensAt" .= ratio open]
  _             -> []

standingJson :: Standing -> Aeson.Value
standingJson = \ case
  InProgress     -> Aeson.object ["status" .= ("inProgress" :: Text)]
  Fulfilled      -> Aeson.object ["status" .= ("fulfilled" :: Text)]
  InBreach b     -> Aeson.object ["status" .= ("breached" :: Text), "breach" .= blameJson b]
  NotEvaluated t -> Aeson.object ["status" .= ("notEvaluated" :: Text), "why" .= Text.strip t]

placementJson :: [(LiveNorm, Rational)] -> [(LiveNorm, Text)] -> Rational -> NormPlacement -> Aeson.Value
placementJson confirmed actions clock = \ case
  InEffect n -> Aeson.object $ ["kind" .= ("owed" :: Text)] <> normFields n
  Awaiting {awProgress} -> Aeson.object $
    ["kind" .= ("heldBack" :: Text)]
    <> maybe [] (\ p -> ["done" .= p.prDone, "total" .= p.prTotal, "until" .= thresholdToken p.prThreshold]) awProgress
  Created {crSource} -> Aeson.object ["kind" .= ("notStarted" :: Text), "source" .= crSource]
  Violated b -> Aeson.object ["kind" .= ("inBreach" :: Text), "breach" .= blameJson b]
  Lapsed b -> Aeson.object ["kind" .= ("lapsed" :: Text), "breach" .= blameJson b]
  where
    normFields n =
      [ "party"  .= bearerText n.lnBearer
      , "modal"  .= modalWord n.lnModal
      , "action" .= actionText actions n
      ] <> dueFields n <> maybe [] (\ f -> ["group" .= familyJson f]) n.lnMember
    dueFields n = opensFields n <> case (n.lnDue, lookup n confirmed) of
      (NoDeadline, _)               -> []
      (UnforcedDeadline t ma, Just d)  -> ["dueBy" .= ratio d, "dueWithin" .= t] <> dueAnchor ma
      (UnforcedDeadline t ma, Nothing) -> ["dueWithin" .= t] <> dueAnchor ma
      (UnforcedBefore t, Just d)       -> ["dueBy" .= ratio d, "dueBefore" .= t]
      (UnforcedBefore t, Nothing)      -> ["dueBefore" .= t]
      -- @remaining@ is from now to the deadline, so a pending opening is
      -- added to the residual's own number (which counts from the opening)
      (Remaining r, _)              -> ["dueBy" .= ratio (clock + pending n + r), "remaining" .= ratio (pending n + r)]
    -- @dueWithin@ is the duration alone; the @OF@ anchor, when written, is its own field
    dueAnchor = maybe [] (\ a -> ["dueAnchor" .= a])
    -- the window's opening edge, while it is still to open: @opensAt@ on
    -- the contract clock once the residual has measured it, else the
    -- @AFTER@ as written (@opensAfter@, and @opensAnchor@ when anchored)
    opensFields n = case n.lnOpens of
      NoOpening            -> []
      OpensIn o            -> ["opensAt" .= ratio (clock + o)]
      UnforcedOpening o ma -> ["opensAfter" .= o] <> maybe [] (\ a -> ["opensAnchor" .= a]) ma
    pending n = case n.lnOpens of
      OpensIn o -> o
      _         -> 0
    thresholdToken = \ case
      AllHave _ -> "allHave" :: Text

normJson :: [(LiveNorm, Text)] -> LiveNorm -> Aeson.Value
normJson actions n = Aeson.object ["party" .= bearerText n.lnBearer, "modal" .= modalWord n.lnModal, "action" .= actionText actions n]

familyJson :: Family -> Aeson.Value
familyJson f = Aeson.object
  [ "join" .= (case f.faJoin of
                 Barrier _    -> "barrier"
                 Fork         -> "fork"
                 Distributive -> "none" :: Text)
  , "total" .= f.faTotal ]

blameJson :: Blame -> Aeson.Value
blameJson b = Aeson.object $ catMaybes
  [ ("party" .=) <$> b.blParty
  , ("missed" .=) <$> b.blObliged
  , ("due" .=) . ratio <$> b.blDeadline
  , ("seenAt" .=) . ratio <$> b.blStamp
  , ("reason" .=) . reasonText <$> b.blReason
  -- R-T3: every failure named, the anchor's index among them; the scalars
  -- above are the anchor's (the same shape as the evaluator's own wire)
  , Just ("names" .= map entryJson b.blNamed)
  , Just ("anchor" .= b.blAnchor)
  ]
  where
    entryJson e = Aeson.object $ catMaybes
      [ ("party" .=) <$> e.beParty
      , ("missed" .=) <$> e.beObliged
      , ("due" .=) . ratio <$> e.beDeadline
      , ("reason" .=) . reasonText <$> e.beReason
      ]

-- | An act whose pattern binds keeps @action@ meaning what it has always
-- meant — the shape, with the binder standing by its own name — and says
-- what was actually replayed under the new @bound@ key. Adding a key
-- changes no existing key's meaning, so @format@ stays at 1.
candidateJson :: Outcome -> Aeson.Value
candidateJson o = case (o.ocCandidate.cdKind, o.ocCandidate.cdHypothetical) of
  (ActBy n, hyp) | Just b <- o.ocCandidate.cdBound -> Aeson.object $
    [ "kind" .= ("act" :: Text), "party" .= bearerText n.lnBearer
    , "action" .= maybe n.lnAction prettyLayout o.ocCandidate.cdShape
    , "bound" .= boundJson b ]
    <> either (const []) (\ h -> ["at" .= ratio h.hyAt]) hyp
  (ActBy n, Right h) -> Aeson.object ["kind" .= ("act" :: Text), "party" .= bearerText n.lnBearer, "action" .= prettyLayout h.hyAction, "at" .= ratio h.hyAt]
  (ActBy n, Left _) -> Aeson.object ["kind" .= ("act" :: Text), "party" .= bearerText n.lnBearer, "action" .= maybe n.lnAction prettyLayout o.ocCandidate.cdShape]
  (TickPast d ns, Right h) -> Aeson.object ["kind" .= ("tick" :: Text), "deadline" .= ratio d, "at" .= ratio h.hyAt, "whose" .= map (normJson []) ns]
  (TickPast d ns, Left _) -> Aeson.object ["kind" .= ("tick" :: Text), "deadline" .= ratio d, "whose" .= map (normJson []) ns]
  (NoTick n, _) -> Aeson.object ["kind" .= ("noTick" :: Text), "whose" .= [normJson [] n]]

-- | The set a binding pattern describes, and the one act drawn from it.
-- @binds@ and @scope@ are the rule's own text; @witness@ is what the replay
-- carried, and is null when none could be built (the reason is then on the
-- @untried@ entry's @why@).
boundJson :: BoundAct -> Aeson.Value
boundJson b = Aeson.object $
  [ "binds" .= map (unqualifiedNameToText . getOriginal) b.baBinders
  , "scope" .= (case b.baScope of
                  BoundWholeAction -> "wholeAction" :: Text
                  BoundArgument    -> "argument")
  , "witness" .= case b.baWitness of
      Left _   -> Aeson.Null
      Right vs -> Aeson.toJSON
        [ Aeson.object ["name" .= unqualifiedNameToText (getOriginal r), "value" .= prettyLayout e] | (r, e) <- vs ]
  ]
  <> maybe [] (\ g -> ["constraint" .= g]) b.baGuard

stepJson :: DeonticStep -> Aeson.Value
stepJson s = Aeson.object $ catMaybes
  [ Just ("clock" .= fmap ratio s.dsClock)
  , ("event" .=) . eventJson <$> s.dsEvent
  , ("norm" .=) . normKeyJson <$> s.dsNorm
  , Just ("outcome" .= outcomeJson s.dsOutcome)
  , ("join" .=) . joinJson <$> s.dsJoin
  , Just ("scrutiny" .= scrutinyText s.dsScrutiny)
  ]
  where
    eventJson e
      | Just a <- e.ekAction, isClockSentinel a = Aeson.object ["at" .= ratio e.ekStamp, "kind" .= ("clock" :: Text)]
      | otherwise = Aeson.object ["at" .= ratio e.ekStamp, "kind" .= ("act" :: Text), "party" .= partyText e.ekPartyName e.ekParty, "action" .= fmap elide e.ekAction]
    normKeyJson k = Aeson.object $
      bearerJson k <> [ "modal" .= modalWord k.nkModal, "activation" .= k.nkActivation ]
      <> maybe [] (\ m -> ["member" .= m.moIndex, "of" .= m.moTotal]) k.nkMember
    -- one token per 'StepOutcome' constructor; the sentence is 'outcomeWords'
    outcomeJson = \ case
      Waiting          -> Aeson.object ["what" .= ("waiting" :: Text)]
      PartyMismatch    -> Aeson.object ["what" .= ("partyMismatch" :: Text)]
      ActionMismatch   -> Aeson.object ["what" .= ("actionMismatch" :: Text)]
      GuardFailed      -> Aeson.object ["what" .= ("guardFailed" :: Text)]
      EarlyAct open    -> Aeson.object ["what" .= ("earlyAct" :: Text), "opensAt" .= ratio open]
      Matched br       -> Aeson.object ["what" .= ("matched" :: Text), "then" .= branchToken br]
      Expired br d     -> Aeson.object ["what" .= ("expired" :: Text), "deadline" .= ratio d, "then" .= branchToken br]
      Breached b       -> Aeson.object ["what" .= ("breached" :: Text), "by" .= partyText b.bsBlameName b.bsBlame, "names" .= map failureJson b.bsFailures, "anchor" .= b.bsAnchor]
      Joined op note   -> Aeson.object $
        [ "what" .= ("joined" :: Text), "operator" .= (case op of ValRAnd -> "and"; ValROr -> "or" :: Text), "result" .= joinResultToken note
        , "winner" .= fmap sideToken note.jnWinner, "tieBreak" .= note.jnTieBreak ]
        -- a breached join carries the same blame the text prints (R-T3)
        <> case note.jnResult of
             JoinBreached b -> ["by" .= partyText b.bsBlameName b.bsBlame, "names" .= map failureJson b.bsFailures, "anchor" .= b.bsAnchor]
             _              -> []
      JoinReleased     -> Aeson.object ["what" .= ("joinReleased" :: Text)]
      JoinExpired br d -> Aeson.object ["what" .= ("joinExpired" :: Text), "deadline" .= ratio d, "then" .= branchToken br]
      JoinFailed br    -> Aeson.object ["what" .= ("joinFailed" :: Text), "then" .= branchToken br]
      JoinStalled      -> Aeson.object ["what" .= ("joinStalled" :: Text)]
    branchToken = \ case
      ToHence  -> "hence" :: Text
      ToLest   -> "lest"
      ToBreach -> "breach"
    sideToken = \ case
      LeftSide  -> "left" :: Text
      RightSide -> "right"
      BothSides -> "both"
    joinResultToken note = case note.jnResult of
      JoinFulfilled  -> "fulfilled" :: Text
      JoinBreached _ -> "breached"
      JoinPending    -> "pending"
    -- one object per failure a breach names (R-T3)
    failureJson = \ case
      MissedSummary p a d -> Aeson.object ["party" .= fmap elide p, "missed" .= elide a, "due" .= ratio d]
      DeclaredSummary p r -> Aeson.object ["named" .= namedAnyone p, "party" .= namedPartyJson p, "reason" .= fmap reasonText r]
    -- @named@ is whether BY named anyone (a fact of the source); @party@ is
    -- who, if forced (a fact of the run) — null with @named: true@ means
    -- named but not yet known, as it does for a missed deadline's @party@
    namedAnyone = \ case
      NobodyNamed  -> False
      PartyNamed _ -> True
    namedPartyJson = \ case
      NobodyNamed  -> Nothing
      PartyNamed p -> fmap elide p
    -- the join's kind is the discriminator; the counts are the progress
    joinJson = \ case
      MemberSatisfied n m -> Aeson.object ["kind" .= ("barrier" :: Text), "done" .= n, "total" .= m]
      ForkContinued i m   -> Aeson.object ["kind" .= ("fork" :: Text), "member" .= i, "total" .= m]
    scrutinyText = \ case
      Consumed      -> "consumed" :: Text
      WitnessedOnly -> "witnessedOnly"
      Reoffered     -> "reoffered"
      NoEvent       -> "noEvent"
