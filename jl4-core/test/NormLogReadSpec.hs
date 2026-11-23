{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | NORM-LOG-SPEC (P2): the pure read of the norm log.
--
-- Hand-made entries, no machine: what the reader decides is a function of the
-- entries and an instant, and each rule it carries is pinned on its own.
--
--   * N13: a norm's state as at an instant, compared with @observed@;
--   * N13's join condition: an operand a compound has decided is not
--     outstanding;
--   * N2: a pattern over bearer, action constructor, modal and branch;
--   * N7 rule 4: a read that cannot place an entry refuses by name, and only
--     for a norm the rest of the pattern matches;
--   * N8: a failure is cured when its @LEST@ continuation is fulfilled by the
--     party that failed.
module NormLogReadSpec (spec) where

import qualified Data.Text as Text
import Data.Foldable (for_)
import Data.List (find)

import L4.Evaluate.NormLog
import L4.Evaluate.NormLog.Read
import L4.Syntax (DeonticModal (..))
import Test.Hspec

ref :: Int -> NormRef
ref n = MkNormRef {nrSite = Nothing, nrActivation = n}

-- | A norm's entry: a @MUST pay@ by Alice, with no instant yet.
entry :: Fate -> Int -> NormEntry
entry f n = MkNormEntry
  { neFate = f, neNorm = Just (ref n), neModal = Just DMust, neBearer = KnownBearer "Alice"
  , neAction = Just "pay 5", neActionHead = Just "pay", neEnclosing = []
  , neOrigin = Nothing, neMember = Nothing, neEffective = Nothing, neObserved = Nothing }

at :: Rational -> NormEntry -> NormEntry
at t e = e {neObserved = Just t, neEffective = Just t}

armedAt :: Rational -> Int -> NormEntry
armedAt t n = at t (entry FateArmed n)

fateAt :: Fate -> Rational -> Int -> NormEntry
fateAt f t n = at t (entry f n)

bearer :: Text.Text -> NormEntry -> NormEntry
bearer b e = e {neBearer = KnownBearer b}

headed :: Text.Text -> NormEntry -> NormEntry
headed h e = e {neActionHead = Just h}

modalled :: DeonticModal -> NormEntry -> NormEntry
modalled m e = e {neModal = Just m}

-- | Armed by the @HENCE@ or @LEST@ of norm @parent@.
child :: OriginBranch -> Int -> NormEntry -> NormEntry
child br parent e = e
  {neOrigin = Just MkNormOrigin {noParent = ref parent, noParentModal = DMust, noParentBearer = KnownBearer "Alice", noBranch = br}}

-- | Change every entry of one norm instance.
ofNorm :: Int -> (NormEntry -> NormEntry) -> [NormEntry] -> [NormEntry]
ofNorm n f = map (\ e -> if e.neNorm == Just (ref n) then f e else e)

-- | Armed inside these compounds, innermost first.
within :: [Int] -> NormEntry -> NormEntry
within cs e = e {neEnclosing = map ref cs}

-- | A compound's reduction: breached with its instants, or fulfilled with none.
joinBreached :: Int -> Rational -> NormEntry
joinBreached c t = (compound (FateJoinedBreached JoinAnd) c) {neObserved = Just t, neEffective = Just t}

joinFulfilled :: Int -> NormEntry
joinFulfilled = compound (FateJoinedFulfilled JoinOr)

compound :: Fate -> Int -> NormEntry
compound f c = MkNormEntry
  { neFate = f, neNorm = Just (ref c), neModal = Nothing, neBearer = NobodyBearer
  , neAction = Nothing, neActionHead = Nothing, neEnclosing = []
  , neOrigin = Nothing, neMember = Nothing, neEffective = Nothing, neObserved = Nothing }

-- | A declared @BREACH@ that a continuation reached, hanging from norm @parent@.
breachFrom :: Int -> Rational -> NormEntry
breachFrom parent t = child ViaLest parent
  ((compound FateBreached 0) {neNorm = Nothing, neObserved = Just t, neEffective = Just t})

states :: Rational -> NormPattern -> [NormEntry] -> Either Refusal [NormState]
states d p es = map (.nvState) <$> readNorms d p es

norms :: Rational -> NormPattern -> [NormEntry] -> Either Refusal [NormRef]
norms d p es = map (.nvNorm) <$> readNorms d p es

-- | Is the failure of norm @n@ cured as at @d@?
cured :: Rational -> [NormEntry] -> Int -> Either Refusal Bool
cured d es n = do
  vs <- readNorms d anyNorm es
  case find (\ v -> v.nvNorm == ref n) vs of
    Just v  -> isCured d es v
    Nothing -> Right False

-- | Norm 1 failed to its @LEST@ at 10; its reparation is norm 2 (armed by the
-- @LEST@, parent 1).
failedAt10 :: [NormEntry]
failedAt10 =
  [ armedAt 1 1, fateAt (FateFailed FailedToLest) 10 1
  , child ViaLest 1 (armedAt 10 2) ]

spec :: Spec
spec = describe "NormLogRead, the pure read of the norm log (NORM-LOG-SPEC P2)" do
  describe "N13: a norm's state as at an instant, compared with observed" do
    it "a norm is not seen before it is armed, is outstanding once armed, and has its fate from the fate's instant" do
      let es = [armedAt 2 1, fateAt FatePerformed 4 1]
      states 1 anyNorm es `shouldBe` Right []
      states 2 anyNorm es `shouldBe` Right [Outstanding]
      states 3 anyNorm es `shouldBe` Right [Outstanding]
      states 4 anyNorm es `shouldBe` Right [Performed]
      states 100 anyNorm es `shouldBe` Right [Performed]

    for_
      [ (FatePerformed, Performed)
      , (FateFailed FailedToLest, Failed FailedToLest)
      , (FateFailed FailedToBreach, Failed FailedToBreach)
      , (FateFailed FailedToJoin, Failed FailedToJoin)
      , (FateViolated, Violated)
      , (FateKept, Kept)
      , (FateExercised, Exercised)
      , (FateLapsed, Lapsed)
      ] \ (f, st) ->
      it ("the fate " <> Text.unpack (fateText f) <> " is the state " <> show st) do
        states 9 anyNorm [armedAt 1 1, fateAt f 5 1] `shouldBe` Right [st]
        states 4 anyNorm [armedAt 1 1, fateAt f 5 1] `shouldBe` Right [Outstanding]

    it "the norms come back in the order they first appear in the log" do
      norms 9 anyNorm [armedAt 1 2, armedAt 1 1, fateAt FatePerformed 3 2] `shouldBe` Right [ref 2, ref 1]

  describe "N13's join condition: an operand a compound has decided is not outstanding" do
    -- a RAND (9) whose left operand (norm 1) failed at 5: the right operand
    -- (norm 2) is left armed with no fate
    let randBreached =
          [ within [9] (armedAt 1 1), within [9] (fateAt (FateFailed FailedToBreach) 5 1)
          , within [9] (armedAt 1 2)
          , joinBreached 9 5 ]

    it "is outstanding until the compound decided, and decided without it from then on" do
      states 4 anyNorm randBreached `shouldBe` Right [Outstanding, Outstanding]
      states 5 anyNorm randBreached `shouldBe` Right [Failed FailedToBreach, DecidedWithout]
      states 9 anyNorm randBreached `shouldBe` Right [Failed FailedToBreach, DecidedWithout]

    it "climbs the whole chain: a compound that has not reduced writes no entry, and the one outside it still decides" do
      let es = [ within [8, 9] (armedAt 1 1), joinBreached 9 5 ]
      states 4 anyNorm es `shouldBe` Right [Outstanding]
      states 6 anyNorm es `shouldBe` Right [DecidedWithout]

    it "refuses when the compound was fulfilled, because a fulfilment carries no time" do
      let es = [ within [9] (armedAt 1 1), joinFulfilled 9 ]
      states 6 anyNorm es `shouldBe` Left (CompoundNoInstant (ref 9))

    it "does not refuse for a norm that has its fate, or when a compound outside settles it" do
      states 6 anyNorm [ within [9] (armedAt 1 1), within [9] (fateAt FatePerformed 2 1), joinFulfilled 9 ]
        `shouldBe` Right [Performed]
      let es = [ within [8, 9] (armedAt 1 1), joinFulfilled 8, joinBreached 9 5 ]
      states 6 anyNorm es `shouldBe` Right [DecidedWithout]
      states 4 anyNorm es `shouldBe` Left (CompoundNoInstant (ref 8))

  describe "N2: a pattern over bearer, action constructor, modal and branch" do
    let es = [ armedAt 1 1, bearer "Bob" (headed "deliver" (armedAt 1 2))
             , modalled DMay (armedAt 1 3)
             , child ViaLest 1 (armedAt 5 4), child ViaHence 1 (armedAt 5 5) ]
    it "matches on the bearer" do
      norms 9 anyNorm {npBearer = BearerIs "Bob"} es `shouldBe` Right [ref 2]
    it "matches on the constructor of the action" do
      norms 9 anyNorm {npAction = Just "deliver"} es `shouldBe` Right [ref 2]
      norms 9 anyNorm {npAction = Just "nothing"} es `shouldBe` Right []
    it "matches on the modal" do
      norms 9 anyNorm {npModal = Just DMay} es `shouldBe` Right [ref 3]
    it "matches on how the norm was armed" do
      norms 9 anyNorm {npBranch = TopLevel} es `shouldBe` Right [ref 1, ref 2, ref 3]
      norms 9 anyNorm {npBranch = ArmedByLest} es `shouldBe` Right [ref 4]
      norms 9 anyNorm {npBranch = ArmedByHence} es `shouldBe` Right [ref 5]

  describe "N7 rule 4: a read that cannot place an entry refuses by name, and only for a norm the rest of the pattern matches" do
    let alice = anyNorm {npBearer = BearerIs "Alice"}
    it "a bearer filter meets a party the machine never forced" do
      let unknown = [ (armedAt 1 1) {neBearer = UnknownBearer} ]
      states 9 alice unknown `shouldBe` Left (BearerNotKnown (ref 1) UnknownBearer)
      states 9 alice {npModal = Just DMay} unknown `shouldBe` Right []
      states 9 anyNorm unknown `shouldBe` Right [Outstanding]
    it "a party known only as written is no better" do
      states 9 alice [ (armedAt 1 1) {neBearer = WrittenBearer "theLandlord"} ]
        `shouldBe` Left (BearerNotKnown (ref 1) (WrittenBearer "theLandlord"))
    it "a later entry that knew the party settles it" do
      states 9 alice [ (armedAt 1 1) {neBearer = WrittenBearer "theLandlord"}, fateAt FatePerformed 3 1 ]
        `shouldBe` Right [Performed]
    it "nobody named is a plain non-match, not a refusal" do
      states 9 alice [ (armedAt 1 1) {neBearer = NobodyBearer} ] `shouldBe` Right []
    it "an entry with no instant cannot be placed at one" do
      states 9 anyNorm [ entry FateArmed 1 ] `shouldBe` Left (NoInstant (ref 1) FateArmed)
      states 9 anyNorm [ armedAt 1 1, entry FatePerformed 1 ] `shouldBe` Left (NoInstant (ref 1) FatePerformed)
      states 9 anyNorm {npModal = Just DMay} [ entry FateArmed 1 ] `shouldBe` Right []

  describe "N8: a failure is cured when its LEST continuation is fulfilled by the party that failed" do
    it "is not cured while the reparation is outstanding, and is once it is performed by the same party" do
      let es = failedAt10 <> [ fateAt FatePerformed 12 2 ]
      cured 11 es 1 `shouldBe` Right False
      cured 12 es 1 `shouldBe` Right True
    it "is not cured when someone else performed the reparation" do
      -- every entry of the norm names its party, as the machine writes them
      let es = ofNorm 2 (bearer "Bob") (failedAt10 <> [ fateAt FatePerformed 12 2 ])
      cured 12 es 1 `shouldBe` Right False
    it "is not cured when the reparation failed with nothing to repair it" do
      cured 12 (failedAt10 <> [ fateAt (FateFailed FailedToBreach) 12 2 ]) 1 `shouldBe` Right False
    it "a reparation that is itself repaired is a cure (the chained LEST)" do
      let es = failedAt10 <>
            [ fateAt (FateFailed FailedToLest) 12 2, child ViaLest 2 (armedAt 12 3), fateAt FatePerformed 15 3 ]
      cured 14 es 1 `shouldBe` Right False
      cured 15 es 1 `shouldBe` Right True
    it "is not cured once a declared BREACH in the continuation has been reached" do
      let es = failedAt10 <> [ fateAt FatePerformed 12 2, breachFrom 2 14 ]
      cured 13 es 1 `shouldBe` Right True
      cured 14 es 1 `shouldBe` Right False
    it "a failure that went straight to a breach, and a norm that did not fail, are not cured" do
      let es = [ armedAt 1 1, fateAt (FateFailed FailedToBreach) 10 1, armedAt 1 2, fateAt FatePerformed 3 2 ]
      cured 20 es 1 `shouldBe` Right False
      cured 20 es 2 `shouldBe` Right False
    it "a RAND of two reparations is cured only when both were performed by the party that failed" do
      let rand = failedAt10 <>
            [ within [9] (child ViaLest 1 (armedAt 10 3)), within [9] (fateAt FatePerformed 12 2)
            , within [9] (fateAt FatePerformed 13 3) ]
          -- norm 2 and 3 are both operands of compound 9, so give norm 2 the same chain
          es = map (\ e -> if e.neNorm == Just (ref 2) then within [9] e else e) rand
      cured 13 es 1 `shouldBe` Right True
      cured 12 es 1 `shouldBe` Right False
      let other = ofNorm 3 (bearer "Bob") es
      cured 13 other 1 `shouldBe` Right False
    it "a party the machine never forced stops the read instead of being guessed" do
      let es = ofNorm 2 (\ e -> e {neBearer = UnknownBearer}) (failedAt10 <> [ fateAt FatePerformed 12 2 ])
      cured 12 es 1 `shouldBe` Left (BearerNotKnown (ref 2) UnknownBearer)
    it "an ROR settled by one alternative cannot be read yet: the compound's fulfilment has no instant" do
      -- the loud limit, until a fulfilment carries a time: the alternative
      -- that lost is left armed, and whether the compound had decided at the
      -- instant is not something an entry says
      let es = failedAt10 <>
            [ within [9] (fateAt FatePerformed 12 2)
            , within [9] (child ViaLest 1 (armedAt 10 3)), joinFulfilled 9 ]
          es' = map (\ e -> if e.neNorm == Just (ref 2) && e.neFate == FateArmed then within [9] e else e) es
      cured 13 es' 1 `shouldBe` Left (CompoundNoInstant (ref 9))
