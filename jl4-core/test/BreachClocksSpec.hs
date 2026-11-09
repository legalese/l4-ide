{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
-- | SEESAW (EVERY-EACH-QUANTIFIER-SPEC §6.1.2): the laws a compound breach's
-- report keeps, checked over a few hundred generated contracts.
--
-- Each case is a tree of @RAND@ / @ROR@ over single obligations, every leaf a
-- different party and action, and a trace of idle @WAIT UNTIL@ events and
-- acts. The generator is a fixed linear congruential sequence, so a failure
-- reproduces exactly; the case number is in the test's name.
--
--   * L0 — the instant is the tree's: with nobody acting and the trace past
--     every deadline, a @RAND@ is lost at the earliest deadline below it and
--     an @ROR@ at the latest, worked out inside out, and the decisive
--     failures are the leaves that set it.
--   * L1 — the order of the operands decides nothing: the tree and its
--     mirror image (every node's operands swapped) give the same verdict,
--     the same two instants and the same decisive failures. (A compound
--     still waiting prints its operands in the order they are written, so
--     two of those are compared only as still waiting.)
--   * L3 — an idle event decides nothing: adding a @WAIT UNTIL@ between two
--     events leaves the verdict, the effective instant and the decisive
--     failures as they were. (The generator writes only @MUST@s; a kept
--     @SHANT@'s @HENCE@, where an idle event used to move the clock, is
--     witnessed in @jl4/examples/ok/breach-clocks.l4@ §5.)
--   * L4 — a breach stays: a trace that is breached at an instant is still
--     breached at that instant when more events follow.
--   * L5 — nothing is observed before it took effect.
--
-- What the laws do NOT cover, by design: operands that read one another's
-- records, and an @ROR@'s right operand after the left is fulfilled (§6.1.2,
-- "What it does not promise").
module BreachClocksSpec (spec) where

import Data.Foldable (for_)
import Data.List (sort, sortOn)
import Data.Maybe (mapMaybe)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Evaluate.ValueLazy
import L4.EvaluateLazy
import L4.EvaluateLazy.Machine (emptyEnvironment, pattern ValFulfilled)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)

-- | An obligation tree: a leaf is party/action @i@ due at @d@.
data Tree = Leaf Int Integer | Node RBinOp Tree Tree
  deriving stock (Eq, Show)

-- | One trace event: an idle tick, or leaf @i@'s party doing its action.
data Ev = Tick Integer | Act Int Integer
  deriving stock (Eq, Show)

evTime :: Ev -> Integer
evTime = \ case
  Tick t  -> t
  Act _ t -> t

mirror :: Tree -> Tree
mirror = \ case
  Leaf i d     -> Leaf i d
  Node op l r  -> Node op (mirror r) (mirror l)

leaves :: Tree -> [(Int, Integer)]
leaves = \ case
  Leaf i d    -> [(i, d)]
  Node _ l r  -> leaves l ++ leaves r

-- | L0's oracle: the instant a tree with every leaf missed is lost at, and
-- the leaves that set it.
oracle :: Tree -> (Integer, [(Int, Integer)])
oracle = \ case
  Leaf i d -> (d, [(i, d)])
  Node op l r ->
    let (el, dl) = oracle l
        (er, dr) = oracle r
        pick = if op == ValRAnd then min else max
        e = pick el er
    in (e, (if el == e then dl else []) ++ (if er == e then dr else []))

-- | The tree as an L4 expression, every node bracketed.
render :: Tree -> Text.Text
render = \ case
  Leaf i d -> "(PARTY P" <> tshow i <> " MUST a" <> tshow i <> " WITHIN " <> tshow d <> ")"
  Node op l r -> "(" <> render l <> (if op == ValRAnd then " RAND " else " ROR ") <> render r <> ")"
  where
    tshow :: Show x => x -> Text.Text
    tshow = Text.pack . show

traceLines :: [Ev] -> [Text.Text]
traceLines = map \ case
  Tick t  -> "  (`WAIT UNTIL` " <> Text.pack (show t) <> ")"
  Act i t -> "  PARTY P" <> Text.pack (show i) <> " DOES a" <> Text.pack (show i) <> " AT " <> Text.pack (show t)

-- | A module with one rule per tree and one #TRACE per (tree, trace) pair.
moduleFor :: [(Tree, [Ev])] -> Text.Text
moduleFor cs = Text.unlines $
  [ "DECLARE Actor IS ONE OF P0, P1, P2, P3, P4, P5, P6, P7"
  , "DECLARE Action IS ONE OF a0, a1, a2, a3, a4, a5, a6, a7"
  , "" ]
  <> concat
    [ [ "GIVETH A DEONTIC Actor Action"
      , "`c" <> Text.pack (show n) <> "` MEANS " <> render t
      , ""
      , "#TRACE `c" <> Text.pack (show n) <> "` AT 0 WITH" ]
      <> (if null evs then ["  (`WAIT UNTIL` 0)"] else traceLines evs)
      <> [""]
    | (n, (t, evs)) <- zip [0 :: Int ..] cs ]

-- | What a run reports, reduced to what the laws compare.
data Verdict
  = Breached
      { vKind      :: Text.Text            -- ^ the constructor
      , vEffective :: Maybe Rational
      , vObserved  :: Maybe Rational
      , vDecisive  :: [(Text.Text, Rational)] -- ^ the decisive failures, as (party, deadline), sorted
      }
  | Fulfilled
  | Other Text.Text                        -- ^ a residual, or anything else, printed
  deriving stock (Eq, Show)

verdictOf :: EvalDirectiveResult -> Verdict
verdictOf res = case res.result of
  Reduction (Reduced (MkNF (ValBreached r))) ->
    let b = breachBlame r
        entries = foldr (:) [] (blameList b)
        dec = [ e | (i, e) <- zip [0 :: Int ..] entries, i `elem` decisiveIndices b ]
    in Breached
      { vKind = case r of
          DeadlineMissed {} -> "deadline missed"
          ExplicitBreach {} -> "explicit"
      , vEffective = breachEffective b
      , vObserved  = breachObserved b
      , vDecisive  = sort (mapMaybe entryKey dec)
      }
  Reduction (Reduced (MkNF ValFulfilled)) -> Fulfilled
  Reduction (Reduced nf) -> Other (prettyLayout nf)
  other -> Other (Text.pack (show other))
  where
    entryKey = \ case
      MissedDeadline p _ d _ -> Just (prettyLayout p, d)
      DeclaredBreach {}      -> Nothing

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

runCases :: [(Tree, [Ev])] -> IO [Verdict]
runCases cs = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) (moduleFor cs) of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure (map verdictOf results)

-- ---------------------------------------------------------------------------
-- The generator: a fixed linear congruential sequence.

newtype Gen = Gen Integer

next :: Gen -> (Integer, Gen)
next (Gen s) = let s' = (s * 6364136223846793005 + 1442695040888963407) `mod` (2 ^ (64 :: Int)) in (s' `div` 65536, Gen s')

below :: Integer -> Gen -> (Integer, Gen)
below n g = let (x, g') = next g in (x `mod` n, g')

-- | A tree of 2 to 5 leaves with deadlines in [1, 12]; equal deadlines are
-- common on purpose, since ties are what the old rule got wrong.
genTree :: Gen -> (Tree, Gen)
genTree g0 =
  let (k, g1) = below 4 g0
  in go (fromIntegral k + 2) 0 g1
  where
    go :: Int -> Int -> Gen -> (Tree, Gen)
    go 1 i g = let (d, g') = below 12 g in (Leaf i (d + 1), g')
    go n i g =
      let (split, g1) = below (fromIntegral n - 1) g
          nl = fromIntegral split + 1
          (opBit, g2) = below 2 g1
          op = if opBit == 0 then ValRAnd else ValROr
          (l, g3) = go nl i g2
          (r, g4) = go (n - nl) (i + nl) g3
      in (Node op l r, g4)

-- | Up to four events at distinct times in [1, 20]: idle ticks, and acts by
-- leaves of the tree (on time or late).
genTrace :: Tree -> Gen -> ([Ev], Gen)
genTrace t g0 =
  let (n, g1) = below 5 g0
      (times, g2) = distinctTimes (fromIntegral n) [] g1
      (evs, g3) = foldl step ([], g2) (sort times)
  in (reverse evs, g3)
  where
    ls = leaves t
    step (acc, g) time =
      let (actBit, g1) = below 3 g
      in if actBit == 0 && not (null ls)
           then let (li, g2) = below (fromIntegral (length ls)) g1
                    (i, _) = ls !! fromIntegral li
                in (Act i time : acc, g2)
           else (Tick time : acc, g1)
    distinctTimes :: Int -> [Integer] -> Gen -> ([Integer], Gen)
    distinctTimes 0 acc g = (acc, g)
    distinctTimes k acc g =
      let (x, g') = below 20 g
          v = x + 1
      in if v `elem` acc then distinctTimes k acc g' else distinctTimes (k - 1) (v : acc) g'

generated :: Int -> [(Tree, [Ev])]
generated n = take n (go (Gen 20261009))
  where
    go g = let (t, g1) = genTree g
               (evs, g2) = genTrace t g1
           in (t, evs) : go g2

-- | An idle tick halfway between two events of the trace (or before the
-- first), at a time no event has: L3's stutter.
stutter :: [Ev] -> Maybe [Ev]
stutter evs = case sortOn evTime evs of
  [] -> Nothing
  (e : rest) ->
    let ts = 0 : map evTime (e : rest)
        gaps = [ (a, b) | (a, b) <- zip ts (drop 1 ts), b - a >= 2 ]
    in case gaps of
         ((a, _) : _) -> Just (sortOn evTime (Tick (a + 1) : evs))
         []           -> Nothing

spec :: Spec
spec = describe "a compound breach's report (SEESAW, spec §6.1.2)" do
  let cs = generated 240

  it "L0: with nobody acting, the tree decides the instant and the decisive leaves" do
    let quiet = [ (t, [Tick 100]) | (t, _) <- take 120 cs ]
    vs <- runCases quiet
    for_ (zip3 [0 :: Int ..] quiet vs) \ (n, (t, _), v) -> do
      let (e, dec) = oracle t
      case v of
        Breached {vEffective, vDecisive} -> do
          (n, vEffective) `shouldBe` (n, Just (fromInteger e))
          (n, vDecisive) `shouldBe` (n, sort [ ("P" <> Text.pack (show i), fromInteger d) | (i, d) <- dec ])
        other -> expectationFailure ("case " <> show n <> ": expected a breach, got " <> show other)

  it "L1: the tree and its mirror image report the same thing" do
    let paired = concat [ [(t, evs), (mirror t, evs)] | (t, evs) <- cs ]
    vs <- runCases paired
    for_ (zip [0 :: Int ..] (pairs vs)) \ (n, (a, b)) ->
      (n, settled a) `shouldBe` (n, settled b)

  it "L3: an idle event between two others changes neither the verdict nor the effective instant" do
    let stuttered = [ (n, t, evs, evs') | (n, (t, evs)) <- zip [0 :: Int ..] cs, Just evs' <- [stutter evs] ]
    vs <- runCases (concat [ [(t, evs), (t, evs')] | (_, t, evs, evs') <- stuttered ])
    for_ (zip stuttered (pairs vs)) \ ((n, _, _, _), (a, b)) ->
      (n, withoutObservation a) `shouldBe` (n, withoutObservation b)

  it "L4: a trace breached at an instant is still breached at that instant when more events follow" do
    let extended = [ (n, t, evs) | (n, (t, evs)) <- zip [0 :: Int ..] cs, not (null evs) ]
        withMore evs = evs <> [Tick 100]
    vs <- runCases (concat [ [(t, evs), (t, withMore evs)] | (_, t, evs) <- extended ])
    for_ (zip extended (pairs vs)) \ ((n, _, _), (a, b)) -> case a of
      Breached {} -> (n, withoutObservation b) `shouldBe` (n, withoutObservation a)
      _           -> pure ()

  it "L5: nothing is observed before it took effect" do
    vs <- runCases cs
    for_ (zip [0 :: Int ..] vs) \ (n, v) -> case v of
      Breached {vEffective = Just e, vObserved = Just o} -> (n, e <= o) `shouldBe` (n, True)
      _ -> pure ()
  where
    pairs (a : b : rest) = (a, b) : pairs rest
    pairs _              = []
    -- a compound still waiting keeps its operands in the drafter's order,
    -- so two residuals are compared only as residuals
    settled = \ case
      Other _ -> Other "still waiting"
      v       -> v
    withoutObservation = \ case
      v@Breached {} -> v {vObserved = Nothing}
      v             -> v
