-- | The pure read side of the norm log (NORM-LOG-SPEC P2: N2's pattern, N13's
-- states, N7 rule 4's refusals, N8's "cured").
--
-- This module takes the entries a writer made ('L4.Evaluate.NormLog') and
-- answers what a contract may ask of them: which norms match a pattern, and
-- what state each was in as at an instant. It has no parser, no machine and no
-- clock of its own; the instant is an argument, and the entries are a list.
-- So everything it decides is testable on hand-made entries, and the
-- evaluator form (a later part of P2) only has to supply the two.
--
-- == What a norm's state is
--
-- A norm has one armed entry and at most one fate entry ('viewNorm'). As at
-- instant @d@, compared with the entry's 'neObserved' as every as-of read is
-- (N13, N3):
--
--   * not yet armed (its armed entry is observed after @d@): the read does not
--     see the norm at all;
--   * armed, and no fate observed at or before @d@: 'Outstanding' (N13), unless
--     a compound it was armed inside has decided at or before @d@, in which case
--     it is 'DecidedWithout' (N13's join condition, which its own correction
--     added: an operand a compound has decided is left armed with no fate, and
--     would otherwise read as outstanding for ever);
--   * a fate observed at or before @d@: that fate.
--
-- "Failed and not cured" is 'isCured' (N8): a failure is cured when its whole
-- @LEST@ continuation, read over the parent links, has been performed, and
-- every performance in it was by the party that failed.
--
-- == Loud and silent
--
-- A read that cannot place an entry refuses, by name ('Refusal'); it never
-- answers with a smaller list (N7 rule 4):
--
--   * a bearer filter meets a norm whose party the machine never forced
--     ('BearerNotKnown');
--   * a read at an instant meets an entry with no instant ('NoInstant'), for
--     example a norm armed on a trace that never forced its clock;
--   * an operand's enclosing compound decided with a fulfilment, which carries
--     no time ('CompoundNoInstant'): until a fulfilment has an instant
--     (SEESAW's dual, not built), a read cannot say whether the compound had
--     decided yet, except that a @RAND@ cannot have decided before its last
--     operand's fate;
--   * a miss under a compound that an @ROR@ fulfilled (also
--     'CompoundNoInstant'): the machine runs an @ROR@'s left operand over the
--     whole trace, so the log holds a miss the contract never had, and a
--     fulfilment cannot say whether the miss came first (N17 and N18, not
--     built). The miss may be a real one, inside the alternative that won,
--     and the reader cannot tell it from the loser's: a read whose pattern
--     matches it refuses from the instant the norm is armed, and one whose
--     pattern leaves it out answers.
--
-- A refusal is raised only for a norm that the rest of the pattern (modal,
-- action constructor, how it was armed) matches, and naming a different
-- bearer does not avoid it: a bearer filter refuses on every norm whose party
-- the machine never forced, whoever the filter names, and the party of an
-- ordinary @PARTY name MUST ...@ is known only as written while the norm is
-- outstanding (N7 rule 3, which forces it when a read filters by bearer, is
-- not built). Until it is, a bearer pattern is usable on norms that have
-- performed or failed and on the members of an @EVERY@, not on the norms
-- that are still owed.
-- The silent failure that remains is a pattern that matches nothing: the
-- answer is an empty list, which a caller turns into "not outstanding", and
-- only the type checker's lint (a later part of P2) can warn of it.
module L4.Evaluate.NormLog.Read
  ( NormPattern (..)
  , BearerPattern (..)
  , BranchPattern (..)
  , anyNorm
  , NormState (..)
  , NormView (..)
  , Refusal (..)
  , prettyRefusal
  , readNorms
  , readHorizon
  , answerRead
  , readPattern
  , isCured
  ) where

import Base
import qualified Data.Map.Strict as Map
import Data.Ratio (denominator, numerator)
import qualified Data.Set as Set
import qualified Data.Text as Text
import L4.Evaluate.NormLog
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax (DeonticModal (..), ReadBranch (..), ReadWord (..))

-- | Whose norm (N2).
data BearerPattern
  = AnyBearer
  | BearerIs !Text
    -- ^ the party keyed exactly as the ledger keys it
    -- ('L4.EvaluateLazy.Machine.partyKeyWHNF'), which is what
    -- 'KnownBearer' holds
  deriving stock (Eq, Show)

-- | How the norm was armed (N2, N8): primary or reached through a @LEST@.
data BranchPattern
  = AnyBranch
  | TopLevel
    -- ^ armed from the top level: no parent link
  | ArmedByHence
  | ArmedByLest
  deriving stock (Eq, Show)

-- | A pattern over norm instances (N2). The action is a constructor only:
-- an entry holds the action as written (a pattern with variables), not as
-- evaluated, so an argument cannot be compared from it.
data NormPattern = MkNormPattern
  { npBearer :: !BearerPattern
  , npAction :: !(Maybe Text)
    -- ^ the constructor the action pattern names; 'Nothing' for any
  , npModal  :: !(Maybe DeonticModal)
  , npBranch :: !BranchPattern
  }
  deriving stock (Eq, Show)

-- | Every norm.
anyNorm :: NormPattern
anyNorm = MkNormPattern {npBearer = AnyBearer, npAction = Nothing, npModal = Nothing, npBranch = AnyBranch}

-- | What became of a norm as at an instant (N13, N1).
data NormState
  = Outstanding
    -- ^ armed, and neither performed nor failed nor closed
  | DecidedWithout
    -- ^ armed with no fate, but a compound it sat inside has decided
  | Performed
  | Exercised
  | Violated
  | Kept
  | Lapsed
  | Failed !FailedTo
  deriving stock (Eq, Show)

-- | One norm instance as the read sees it.
data NormView = MkNormView
  { nvNorm  :: !NormRef
  , nvArmed :: !NormEntry
  , nvFate  :: !(Maybe NormEntry)
    -- ^ its fate entry, when one was observed at or before the instant
  , nvState :: !NormState
  }
  deriving stock (Eq, Show)

-- | Why a read stopped (N7 rule 4).
data Refusal
  = BearerNotKnown !NormRef !NormBearer
  | NoInstant !NormRef !Fate
  | CompoundNoInstant !NormRef
  | FutureInstant !Rational !(Maybe Rational)
    -- ^ asked as at an instant the contract has not reached: the instant, and
    -- the latest instant the run has been at ('Nothing': it has not started)
  deriving stock (Eq, Show)

prettyRefusal :: Refusal -> Text
prettyRefusal = \case
  BearerNotKnown r b ->
    "the party of the norm at " <> siteText r <> " is "
      <> (case b of
            WrittenBearer t -> "only known as written (" <> t <> ")"
            UnknownBearer   -> "not yet known"
            _               -> "not a known party")
      <> ", so a read that filters by party cannot place it"
  NoInstant r f ->
    "the " <> fateText f <> " entry of the norm at " <> siteText r
      <> " has no instant, so a read at an instant cannot place it"
  CompoundNoInstant c ->
    "the compound at " <> siteText c
      <> " was fulfilled, and a fulfilment carries no time, so a read at an instant cannot say whether it had decided yet"
  FutureInstant d horizon ->
    "the read asks as at " <> ratText d <> ", "
      <> (case horizon of
            Just h  -> "but the contract has only reached " <> ratText h
            Nothing -> "but no contract has run yet")
      <> ": an instant after the clock cannot be answered, because what happens between is not in the log yet"
  where
    ratText r
      | denominator r == 1 = Text.pack (show (numerator r))
      | otherwise          = Text.pack (show (numerator r) <> "/" <> show (denominator r))

siteText :: NormRef -> Text
siteText r =
  maybe "(no source site)" (\ s -> "line " <> Text.pack (show s.start.line)) r.nrSite
    <> ", activation " <> Text.pack (show r.nrActivation)

-- | The fates of a norm instance itself: its arming, and how it ended.
isNormFate :: Fate -> Bool
isNormFate = \case
  FateArmed     -> True
  FatePerformed -> True
  FateFailed _  -> True
  FateViolated  -> True
  FateKept      -> True
  FateExercised -> True
  FateLapsed    -> True
  _             -> False

-- | The outcomes that decide a compound or a barrier: the reduction of an
-- @AND@\/@OR@, and an @EVERY ... ONCE@ barrier's own outcome. What each leaves
-- behind is read by 'decidedWithout'.
isJoinOutcome :: Fate -> Bool
isJoinOutcome = \case
  FateJoinedFulfilled _ -> True
  FateJoinedBreached _  -> True
  FateJoinReleased      -> True
  FateJoinExpired       -> True
  FateJoinFailed        -> True
  FateJoinStalled       -> True
  _                     -> False

-- | A fate that leaves a norm in no way owed: it was done, or it closed.
fulfilling :: NormState -> Bool
fulfilling = \case
  Performed -> True
  Exercised -> True
  Kept      -> True
  Lapsed    -> True
  _         -> False

-- | A fate that is a miss or a breach of what the norm asked.
negative :: Fate -> Bool
negative = \case
  FateFailed _ -> True
  FateViolated -> True
  _            -> False

-- | The state a fate puts a norm in.
stateOfFate :: Fate -> NormState
stateOfFate = \case
  FatePerformed -> Performed
  FateFailed ft -> Failed ft
  FateViolated  -> Violated
  FateKept      -> Kept
  FateExercised -> Exercised
  FateLapsed    -> Lapsed
  _             -> Outstanding

-- | The log, indexed once for a read at one instant.
data Ctx = MkCtx
  { cxAsOf   :: !Rational
  , cxNorms  :: !(Map NormRef [NormEntry])
    -- ^ every entry of each norm instance, in log order
  , cxOrder  :: [NormRef]
    -- ^ the norm instances, in the order they first appear
  , cxJoins  :: !(Map NormRef NormEntry)
    -- ^ each compound or barrier that has decided, by its own entry
  , cxBound  :: !(Map NormRef Rational)
    -- ^ for each compound, the latest instant a fate of one of its direct
    -- operands was observed: a @RAND@ cannot have decided before it
  , cxKids   :: !(Map NormRef [NormEntry])
    -- ^ every entry, by the norm whose @HENCE@ or @LEST@ armed it
  }

mkCtx :: Rational -> [NormEntry] -> Ctx
mkCtx d es = MkCtx
  { cxAsOf = d
  , cxNorms = Map.fromListWith (flip (<>)) [ (r, [e]) | e <- es, isNormFate e.neFate, Just r <- [e.neNorm] ]
  , cxOrder = nubOrd [ r | e <- es, isNormFate e.neFate, Just r <- [e.neNorm] ]
  , cxJoins = Map.fromList [ (c, e) | e <- es, isJoinOutcome e.neFate, Just c <- [e.neNorm] ]
  , cxBound = Map.fromListWith max
      [ (c, t)
      | e <- es, isNormFate e.neFate, e.neFate /= FateArmed
      , c : _ <- [e.neEnclosing], Just t <- [e.neObserved] ]
  , cxKids = Map.fromListWith (flip (<>)) [ (o.noParent, [e]) | e <- es, Just o <- [e.neOrigin] ]
  }

instantOf :: NormRef -> NormEntry -> Either Refusal Rational
instantOf r e = maybe (Left (NoInstant r e.neFate)) Right e.neObserved

-- | The norm instances that match the pattern, as at the instant, in log
-- order. See the module header for what each state means and when a read
-- refuses.
readNorms :: Rational -> NormPattern -> [NormEntry] -> Either Refusal [NormView]
readNorms d p es = catMaybes <$> traverse matching ctx.cxOrder
  where
    ctx = mkCtx d es
    matching r = case Map.lookup r ctx.cxNorms of
      Just grp@(g : _) | shapeMatches p (armedOf g grp) -> do
        ok <- bearerMatches r grp p.npBearer
        if ok then viewNorm ctx r else Right Nothing
      _ -> Right Nothing

armedOf :: NormEntry -> [NormEntry] -> NormEntry
armedOf g grp = fromMaybe g (find (\ e -> e.neFate == FateArmed) grp)

shapeMatches :: NormPattern -> NormEntry -> Bool
shapeMatches p e =
  maybe True (\ m -> modalMatches m e.neModal) p.npModal
    && maybe True (\ a -> e.neActionHead == Just a) p.npAction
    && case p.npBranch of
         AnyBranch    -> True
         TopLevel     -> isNothing e.neOrigin
         ArmedByHence -> ((.noBranch) <$> e.neOrigin) == Just ViaHence
         ArmedByLest  -> ((.noBranch) <$> e.neOrigin) == Just ViaLest

-- | A pattern's modal against an entry's. A @DO@ norm is an obligation like a
-- @MUST@ one (it fails on the same terms, 'L4.EvaluateLazy.Fates'), and the
-- checker already takes a @MUST@ pattern to match its site
-- ('L4.TypeCheck', @readsMatchingNoSite@); the reader must agree, or a read
-- the checker passes is false on every trace.
modalMatches :: DeonticModal -> Maybe DeonticModal -> Bool
modalMatches m entry = entry == Just m || (m == DMust && entry == Just DDo)

-- | The party of a norm instance, as well as any of its entries knew it: the
-- machine forces a party when the norm meets an event, so a later entry can
-- know what the arming did not.
instanceBearer :: [NormEntry] -> NormBearer
instanceBearer grp =
  case [ b | e <- grp, b@(KnownBearer _) <- [e.neBearer] ] of
    b : _ -> b
    [] -> case [ b | e <- grp, b@(WrittenBearer _) <- [e.neBearer] ] of
      b : _ -> b
      []    -> case grp of
        e : _ -> e.neBearer
        []    -> UnknownBearer

bearerMatches :: NormRef -> [NormEntry] -> BearerPattern -> Either Refusal Bool
bearerMatches r grp = \case
  AnyBearer  -> Right True
  BearerIs t -> case instanceBearer grp of
    KnownBearer k -> Right (k == t)
    NobodyBearer  -> Right False
    b             -> Left (BearerNotKnown r b)

-- | One norm instance by its own entries alone, as at the context's
-- instant: its armed entry, and its fate entry if one was observed by then.
-- 'Nothing' when it was not armed yet. No compound is consulted.
ownNorm :: Ctx -> NormRef -> Either Refusal (Maybe (NormEntry, Maybe NormEntry))
ownNorm ctx r = case Map.lookup r ctx.cxNorms of
  Just grp@(g : _) -> do
    let armed = armedOf g grp
        fateE = find (\ e -> e.neFate /= FateArmed) grp
    armedAt <- instantOf r armed
    if armedAt > ctx.cxAsOf then Right Nothing else do
      seen <- case fateE of
        Nothing -> Right Nothing
        Just e  -> do
          t <- instantOf r e
          pure (if t <= ctx.cxAsOf then Just e else Nothing)
      Right (Just (armed, seen))
  _ -> Right Nothing

-- | The state of a norm by its own entries alone: outstanding until a fate
-- has been observed.
ownState :: Ctx -> NormRef -> Either Refusal (Maybe NormState)
ownState ctx r = fmap (\ (_, seen) -> maybe Outstanding (stateOfFate . (.neFate)) seen) <$> ownNorm ctx r

-- | One norm instance as at the context's instant; 'Nothing' when it was not
-- armed yet.
viewNorm :: Ctx -> NormRef -> Either Refusal (Maybe NormView)
viewNorm ctx r = ownNorm ctx r >>= \case
  Nothing -> Right Nothing
  Just (armed, seen) -> do
    st <- case seen of
      Just e  -> do
        -- a miss under a compound that an ROR fulfilled: the machine runs an
        -- ROR's left operand over the whole trace, so the log holds a miss
        -- the contract never had, and a fulfilment carries no time to say
        -- whether this one came first (N17 and N18, not built)
        when (negative e.neFate) (settledByRor ctx armed)
        Right (stateOfFate e.neFate)
      Nothing -> do
        moot <- decidedWithout ctx armed
        pure (if moot then DecidedWithout else Outstanding)
    Right (Just MkNormView {nvNorm = r, nvArmed = armed, nvFate = seen, nvState = st})

-- | Refuse when a compound this norm was armed inside was fulfilled by an
-- @ROR@: the norm's miss may have come after the choice was settled.
settledByRor :: Ctx -> NormEntry -> Either Refusal ()
settledByRor ctx armed =
  case [ c | c <- armed.neEnclosing, Just j <- [Map.lookup c ctx.cxJoins], j.neFate == FateJoinedFulfilled JoinOr ] of
    c : _ -> Left (CompoundNoInstant c)
    []    -> Right ()

-- | N13's join condition: has a compound or barrier this norm was armed
-- inside decided at or before the instant? A compound decided with a breach,
-- and a barrier's failure, have their instants. A compound decided with a
-- fulfilment has none, and is a refusal unless another compound outside it
-- settles the question, or the read is earlier than the last of its direct
-- operands' fates, which a @RAND@ cannot have decided before.
decidedWithout :: Ctx -> NormEntry -> Either Refusal Bool
decidedWithout ctx armed
  | any isDecided statuses = Right True
  | (c : _) <- [ c | Unplaced c <- statuses ] = Left (CompoundNoInstant c)
  | otherwise = Right False
  where
    statuses = map status armed.neEnclosing
    status c = case Map.lookup c ctx.cxJoins of
      Nothing -> NotYet
      Just j -> case j.neObserved of
        Just t  -> if t <= ctx.cxAsOf then Decided else NotYet
        Nothing
          | j.neFate == FateJoinedFulfilled JoinAnd
          , Just bound <- Map.lookup c ctx.cxBound
          , ctx.cxAsOf < bound -> NotYet
          | otherwise -> Unplaced c
    isDecided = \case { Decided -> True; _ -> False }

data JoinStatus = Decided | NotYet | Unplaced !NormRef

-- | N8: is a failed norm's failure cured, as at the instant?
--
-- A failure that armed a reparation is cured when the @LEST@ continuation it
-- armed has reduced to a fulfilment, read over the parent links, and every
-- performance in it was by the party that failed. Each norm in the
-- continuation is fulfilled when it was performed (by that party) or closed
-- without a failure (a kept prohibition, a lapsed permission) and everything
-- its own continuation armed is fulfilled too; or when it failed or was
-- violated and its own @LEST@ continuation is fulfilled, because a reparation
-- that is itself repaired is a cure (N8's chained case: @MUST a LEST MUST b
-- LEST MUST c@ is cured for @a@ when @c@ was done). It is not fulfilled when it
-- is still outstanding, failed with nothing to repair it (a breach, or a
-- report to a barrier), was violated with nothing armed after the violation,
-- is not yet armed, or has a declared @BREACH@ or a breached compound among
-- what it armed, at or before the instant. A norm the continuation left
-- behind because a compound decided without it is not part of the answer
-- (N13's join condition applies here too).
--
-- An @ROR@ in the continuation is settled by an alternative that was itself
-- fulfilled (N8): its norm performed, or kept, exercised or lapsed, and
-- everything its own continuation armed fulfilled in turn. An alternative
-- whose norm was performed and whose @HENCE@ then reached a breach did not
-- settle it, and neither did one whose continuation is still owed or failed
-- (decided by Claude 2026-11-24, pending Meng's review, after the delta
-- review of P2's first half found the reader choosing the alternative whose
-- first norm came first). The other alternative's miss does not count, so
-- the cure is read from the one that settled it. With two alternatives
-- fulfilled the earliest by its own norm's instant settled it; if two share
-- the instant and their answers differ, or one was fulfilled by a reparation
-- and so cannot be placed by its own norm, the read refuses by name, because
-- a fulfilment carries no time to say which came first. The machine as built
-- never arms an @ROR@'s right alternative once its left was fulfilled, so a
-- log it wrote has one fulfilled alternative at most.
-- If no alternative was fulfilled yet, the failure is not cured as at the
-- instant when the log holds a fulfilling fate at all; if it holds none, the
-- choice was settled by something the log does not say, and the read refuses
-- (it also refuses when an alternative is itself a compound).
--
-- A failure that went straight to a breach, or was reported to a barrier,
-- has nothing to cure with and is not cured; anything that is not a failure
-- is not cured either. Reading the log is linear in its length for each
-- call.
isCured :: Rational -> [NormEntry] -> NormView -> Either Refusal Bool
isCured d es v = case v.nvState of
  Failed FailedToLest -> childrenFulfilled fullState performedBy (Set.singleton v.nvNorm) v.nvNorm
  _                   -> Right False
  where
    ctx = mkCtx d es
    entriesOf r = fromMaybe [] (Map.lookup r ctx.cxNorms)
    kidsOf r = fromMaybe [] (Map.lookup r ctx.cxKids)
    who = instanceBearer (entriesOf v.nvNorm)

    -- how a norm is read: with the compounds it sits in, or by its own
    -- entries alone (inside an ROR's alternatives, where the ROR itself is
    -- what is being decided)
    fullState r = fmap (.nvState) <$> viewNorm ctx r
    ownOnly r = ownState ctx r

    -- who performed it: the party that failed (a cure), or anyone (was the
    -- alternative fulfilled at all)
    anyone _ = Right True

    -- nothing a norm armed is a breach that has been reached, and every norm
    -- it armed is fulfilled
    childrenFulfilled stateOf by seen r = do
      reached <- anyM (breachReached r) [ e | e <- kidsOf r, isBreach e.neFate ]
      let kids = nubOrd [ c | e <- kidsOf r, isNormFate e.neFate, Just c <- [e.neNorm] ]
      if reached then Right False else allM (groupFulfilled stateOf by kids seen) (groupByCompound r kids)

    -- the norms a norm armed, in groups by the compound each was armed
    -- inside that the armer was not already in: a norm armed by an
    -- alternative's own @HENCE@ shares the alternative's compounds, and is
    -- not another alternative of them
    groupByCompound r ks =
      [ (key, [ k | k <- ks, newInnermost r k == key ]) | key <- nubOrd (map (newInnermost r) ks) ]
    chainOf k = case entriesOf k of
      g : _ -> (armedOf g (entriesOf k)).neEnclosing
      []    -> []
    newInnermost r k =
      let kc = chainOf k
          rc = chainOf r
      in listToMaybe (if rc `isSuffixOf` kc then take (length kc - length rc) kc else kc)

    groupFulfilled stateOf by kids seen (key, ks) = case key >>= \ c -> (,) c <$> Map.lookup c ctx.cxJoins of
      Just (c, j) | j.neFate == FateJoinedFulfilled JoinOr -> settledGroup by kids seen c ks
      _ -> allM (fulfilled stateOf by seen) ks

    -- An ROR that was fulfilled was settled by an alternative that was
    -- itself fulfilled, as at the instant: its norm performed (or kept, or
    -- exercised, or lapsed) and everything its own continuation armed
    -- fulfilled in turn, so an alternative whose @HENCE@ reached a breach is
    -- not the one, and neither is one whose continuation is still owed or
    -- failed. The alternatives are read by their own entries, because the ROR
    -- is what is being decided.
    -- One alternative fulfilled: it settled the choice. Several: the
    -- earliest by its own norm's instant, and if two share the instant and
    -- the answers differ, or one cannot be placed by its own norm (it was
    -- fulfilled by a reparation), the read refuses, because a fulfilment
    -- carries no time to say which came first. None yet: not cured as at the
    -- instant, if the log holds a fulfilling fate at all; otherwise the
    -- choice was settled by something the log does not say, and the read
    -- refuses.
    settledGroup by kids seen c ks
      | any (nestedUnder c) kids = Left (CompoundNoInstant c)
      | otherwise = do
          states <- traverse (\ k -> (,) k <$> ownNorm ctx k) ks
          settlers <- filterM (fulfilled ownOnly anyone seen) ks
          let placed k = listToMaybe
                [ t | (k', Just (_, Just e)) <- states, k' == k, fulfilling (stateOfFate e.neFate), Just t <- [e.neObserved] ]
              everFulfilled = or [ fulfilling (stateOfFate e.neFate) | k <- ks, e <- entriesOf k, e.neFate /= FateArmed ]
          case settlers of
            [] | everFulfilled -> Right False
               | otherwise     -> Left (CompoundNoInstant c)
            [k] -> fulfilled ownOnly by seen k
            _ -> case traverse (\ k -> (,) k <$> placed k) settlers of
              Nothing    -> Left (CompoundNoInstant c)
              Just timed -> do
                let t0 = minimum (map snd timed)
                answers <- traverse (fulfilled ownOnly by seen) [ k | (k, t) <- timed, t == t0 ]
                case nubOrd answers of
                  [a] -> Right a
                  _   -> Left (CompoundNoInstant c)
    nestedUnder c k = case entriesOf k of
      g : _ -> case (armedOf g (entriesOf k)).neEnclosing of
        enc@(h : _) -> c `elem` enc && h /= c
        []          -> False
      []    -> False

    fulfilled stateOf by seen r
      | r `Set.member` seen = Right False
      | otherwise = stateOf r >>= \case
          Nothing -> Right False
          Just st -> case st of
            DecidedWithout -> Right True
            Outstanding    -> Right False
            -- a violation is repaired by what it armed, as a failure is; with
            -- nothing armed after it, it is a breach
            Violated       -> if null (kidsOf r) then Right False else childrenFulfilled stateOf by seen' r
            Failed FailedToLest -> childrenFulfilled stateOf by seen' r
            Failed _       -> Right False
            Performed      -> by r `andThenM` childrenFulfilled stateOf by seen' r
            Exercised      -> by r `andThenM` childrenFulfilled stateOf by seen' r
            Kept           -> childrenFulfilled stateOf by seen' r
            Lapsed         -> childrenFulfilled stateOf by seen' r
      where seen' = Set.insert r seen

    performedBy r = case (who, instanceBearer (entriesOf r)) of
      (KnownBearer a, KnownBearer b) -> Right (a == b)
      (KnownBearer _, other)         -> Left (BearerNotKnown r other)
      (other, _)                     -> Left (BearerNotKnown v.nvNorm other)

    breachReached r e = case e.neObserved of
      Nothing -> Left (NoInstant r e.neFate)
      Just t  -> Right (t <= d)

    isBreach = \case
      FateBreached         -> True
      FateJoinedBreached _ -> True
      _                    -> False

-- | The pattern a written read means (NORM-LOG-SPEC N4b): the bearer, the
-- modal and the action's constructor, and the branch. A bare pattern matches
-- every branch; @UNDER LEST@ and @UNDER HENCE@ narrow it.
readPattern :: BearerPattern -> DeonticModal -> Text -> ReadBranch -> NormPattern
readPattern who modal con branch = MkNormPattern
  { npBearer = who
  , npAction = Just con
  , npModal  = Just modal
  , npBranch = case branch of
      ReadAnyBranch  -> AnyBranch
      ReadUnderLest  -> ArmedByLest
      ReadUnderHence -> ArmedByHence
  }

-- | The latest instant the entries show the run to have reached: the greatest
-- observed instant of any entry. A read asks at an instant no later than this
-- and the clock the machine adds (the stamp of the event a guard is matched
-- against, which no entry carries yet); one later is the read of a future the
-- log has not written, and 'FutureInstant' refuses it.
readHorizon :: [NormEntry] -> Maybe Rational
readHorizon es = case mapMaybe (.neObserved) es of
  [] -> Nothing
  ts -> Just (maximum ts)

-- | The answer to one of the four phrases (N4b), as at an instant: true when
-- ANY norm the pattern matches is in the state the phrase names (card
-- condition 2). @EVER FAILED@ is the spec's FAILED: a @MUST@'s @LEST@ fired
-- at or before the instant, cured or not; a lapsed @MAY@ and a violated
-- @SHANT@ are not failures (N13, N1). A refusal of 'readNorms' or 'isCured'
-- is the answer's refusal: it never turns into @False@.
answerRead :: ReadWord -> Rational -> NormPattern -> [NormEntry] -> Either Refusal Bool
answerRead word d pat es = do
  vs <- readNorms d pat es
  case word of
    ReadOutstanding       -> Right (any (\ v -> v.nvState == Outstanding) vs)
    ReadEverFailed        -> Right (any failed vs)
    ReadFailedNotCured    -> anyM (\ v -> if failed v then not <$> isCured d es v else Right False) vs
    ReadCuredByReparation -> anyM (\ v -> if failed v then isCured d es v else Right False) vs
  where
    failed v = case v.nvState of { Failed _ -> True; _ -> False }

-- | Short-circuiting over 'Either', so a refusal in a branch that another
-- branch has already settled does not stop the read.
allM :: (a -> Either r Bool) -> [a] -> Either r Bool
allM _ [] = Right True
allM f (x : xs) = f x >>= \b -> if b then allM f xs else Right False

anyM :: (a -> Either r Bool) -> [a] -> Either r Bool
anyM _ [] = Right False
anyM f (x : xs) = f x >>= \b -> if b then Right True else anyM f xs

andThenM :: Either r Bool -> Either r Bool -> Either r Bool
andThenM a b = a >>= \x -> if x then b else Right False
