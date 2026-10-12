{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | What evaluation answers with an input nobody supplied, case by case
-- (UNKNOWN-EVALUATION-SPEC §8 step 3). The corpus file
-- @jl4/examples/ok/unknown-inputs-lifted.l4@ pins the rows through its
-- goldens; this module pins, one directive at a time, the cases where the
-- answer must stay what it was before the step because some supplied value
-- would make it an error, and the cases that must still be decided.
module UnknownInputsSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API (l4Eval, l4EvalDirective)
import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Evaluate.Ledger (LedgerStore (..))
import L4.Evaluate.ValueLazy (Term (..))
import L4.EvaluateLazy
  ( AssertionOutcome (..)
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithEnv
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Exceptions (prettyEvalException)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)

-- | A directive's outcome, as much of it as these tests compare.
data Outcome
  = Value Text.Text
  | Satisfied
  | Failed
  | Waits [Text.Text]
    -- ^ undetermined, waiting on these inputs, as its message names them
  | Errors Text.Text
  | Refuses
  deriving stock (Eq, Show)

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0)

-- | The outcome of each directive in a source, in order.
outcomes :: Text.Text -> IO [Outcome]
outcomes src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r | not r.tcdSuccess -> fail ("typecheck failed: " <> show r.tcdErrors)
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure (map (classify . (.result)) results)

-- | Each directive's result, as the core's JSON encodes it.
resultsJson :: Text.Text -> IO [Aeson.Value]
resultsJson src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r | not r.tcdSuccess -> fail ("typecheck failed: " <> show r.tcdErrors)
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure (map (Aeson.toJSON . (.result)) results)

-- | A key of a JSON object.
field :: Aeson.Key -> Aeson.Value -> Maybe Aeson.Value
field k = \ case
  Aeson.Object o -> KeyMap.lookup k o
  _              -> Nothing

-- | A JSON text, decoded.
decodeText :: Text.Text -> Maybe Aeson.Value
decodeText = Aeson.decode . LBS.fromStrict . Text.encodeUtf8

-- | The outcome of each directive, with how many ledger writes it made.
outcomesAndWrites :: Text.Text -> IO [(Outcome, Int)]
outcomesAndWrites src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r | not r.tcdSuccess -> fail ("typecheck failed: " <> show r.tcdErrors)
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure [ (classify d.result, writes d.ledger) | d <- results ]
  where
    writes store = sum (fmap length store.ownLedgers) + length store.officialLedger

classify :: EvalDirectiveValue -> Outcome
classify = \ case
  Assertion Holds              -> Satisfied
  Assertion Fails              -> Failed
  Assertion (FailsBecause _)   -> Failed
  Assertion (Refused _)        -> Refuses
  Assertion (Errored e)        -> Errors (Text.unlines (prettyEvalException e))
  Assertion (Undetermined ns)  -> Waits (map name (toList ns))
  Reduction (Reduced v)        -> Value (prettyLayout v)
  Reduction (ReducedRefused _) -> Refuses
  Reduction (ReducedErrored e) -> Errors (Text.unlines (prettyEvalException e))
  Reduction (ReducedUndetermined ns) -> Waits (map name (toList ns))
  where
    name = \ case
      TInput r _ -> prettyLayout r
      t          -> prettyLayout t

spec :: Spec
spec = describe "unknown inputs (UNKNOWN-EVALUATION-SPEC §8 step 3)" $ do

  -- A field of an unknown is a field path only when every value of the type
  -- has the field. Every Square makes each of these three an error, so none
  -- may be decided; step 3 first answered all three "satisfied".
  describe "a field of an unknown of a type with several constructors" $ do
    let shapes = Text.unlines
          [ "DECLARE Shape IS ONE OF"
          , "  Circle HAS radius IS A NUMBER"
          , "  Square HAS side IS A NUMBER"
          , "DECLARE Person HAS age IS A NUMBER"
          , "§ `Unknown`"
          , "    GIVEN s IS A Shape"
          , "          d IS A Person"
          ]
    it "stays Stuck on the unknown, as it was before the step" $ do
      os <- outcomes $ shapes <> Text.unlines
        [ "#ASSERT s's radius EQUALS s's radius"
        , "#ASSERT NOT ((s's radius GREATER THAN 0) AND FALSE)"
        , "#ASSERT (s's radius GREATER THAN 0) OR TRUE"
        ]
      os `shouldBe` replicate 3 (Waits ["s"])
    it "is a field path for a type with one constructor, which those decide" $ do
      os <- outcomes $ shapes <> Text.unlines
        [ "#ASSERT d's age EQUALS d's age"
        , "#ASSERT NOT ((d's age GREATER THAN 0) AND FALSE)"
        , "#ASSERT (d's age GREATER THAN 0) OR TRUE"
        , "#EVAL d's age GREATER THAN 0"
        ]
      os `shouldBe` [Satisfied, Satisfied, Satisfied, Waits ["d's age"]]

  -- The identity rule applies only where equality is defined, and a synonym
  -- is the type it names. Every supplied `f` makes `f EQUALS f` the
  -- unsupported-equality error; step 3 first answered it "satisfied", and
  -- the same for a LIST of them, a record holding one and a synonym of that
  -- record.
  describe "equality on an unknown whose type is a synonym" $ do
    let synonyms = Text.unlines
          [ "DECLARE Fn IS FUNCTION FROM NUMBER TO NUMBER"
          , "DECLARE Holder HAS op IS A Fn"
          , "DECLARE Held IS Holder"
          , "DECLARE Amount IS NUMBER"
          , "ASSUME mk IS A FUNCTION FROM NUMBER TO Fn"
          , "§ `Unknown`"
          , "    GIVEN f IS A Fn"
          , "          fs IS A LIST OF Fn"
          , "          h IS A Holder"
          , "          h2 IS A Held"
          , "          k IS AN Amount"
          ]
        unsupported = \ case
          Errors t -> "Trying to check equality on types that do not support it" `Text.isPrefixOf` t
          _        -> False
    it "is the unsupported-equality error for a synonym of a function type" $ do
      os <- outcomes $ synonyms <> Text.unlines
        [ "#ASSERT f EQUALS f"
        , "#ASSERT mk 3 EQUALS mk 3"
        ]
      map unsupported os `shouldBe` [True, True]
    it "stays Stuck for a type with one inside, through a synonym" $ do
      os <- outcomes $ synonyms <> Text.unlines
        [ "#ASSERT fs EQUALS fs"
        , "#ASSERT h EQUALS h"
        , "#ASSERT h2 EQUALS h2"
        ]
      os `shouldBe` [Waits ["fs"], Waits ["h"], Waits ["h2"]]
    it "is the identity for a synonym of a type equality supports" $ do
      os <- outcomes $ synonyms <> "#ASSERT k EQUALS k\n"
      os `shouldBe` [Satisfied]

  -- The right operand of a connective whose left is unknown is evaluated
  -- only because the left might need it; the two-valued run would not have
  -- reached it unless the left came out so. An effect there does not
  -- happen: the answer is Stuck on the left's inputs, and nothing is
  -- written. These tests use only a ledger write and a read of the process
  -- environment; none makes a request.
  describe "an effect under an unknown" $ do
    let unknowns = Text.unlines
          [ "§ `Unknown`"
          , "    GIVEN x IS A BOOLEAN"
          , "          n IS A NUMBER"
          ]
    it "does not write the ledger, and is Stuck on the left's inputs" $ do
      os <- outcomesAndWrites $ unknowns <> Text.unlines
        [ "#EVAL x AND (RECORD `wrote` IS FALSE)"
        , "#EVAL x OR (RECORD `wrote` IS TRUE)"
        , "#EVAL (LIST n, RECORD `wrote` IS 2) EQUALS (LIST 1, 3)"
        ]
      os `shouldBe` [(Waits ["x"], 0), (Waits ["x"], 0), (Waits ["n"], 0)]
    it "writes it with the left supplied, as before" $ do
      os <- outcomesAndWrites $ unknowns <> "#EVAL TRUE AND (RECORD `wrote` IS FALSE)\n"
      os `shouldBe` [(Value "FALSE", 1)]
    it "does not read the environment" $ do
      os <- outcomes $ unknowns <> Text.unlines
        [ "#EVAL x AND ((ENV \"L4_UNKNOWN_INPUTS_SPEC_NEVER_SET\") EQUALS (JUST \"a\"))"
        , "#EVAL TRUE AND ((ENV \"L4_UNKNOWN_INPUTS_SPEC_NEVER_SET\") EQUALS (JUST \"a\"))"
        ]
      os `shouldBe` [Waits ["x"], Value "FALSE"]
    -- A built-in that cannot take its argument reports it as an internal
    -- error; under an unknown that is Stuck on the left, like any other
    -- error there. `FETCH` of a string that is no https URL fails before it
    -- makes any request.
    it "is Stuck where a built-in refuses its argument, not an internal error" $ do
      os <- outcomes $ unknowns <> Text.unlines
        [ "#EVAL x AND ((FETCH \"not a url\") EQUALS \"\")"
        , "#EVAL (FETCH \"not a url\") EQUALS \"\""
        ]
      case os of
        [speculative, supplied] -> do
          speculative `shouldBe` Waits ["x"]
          supplied `shouldSatisfy` \ case
            Errors t -> "Internal error:" `Text.isPrefixOf` t
            _        -> False
        _ -> expectationFailure ("expected two outcomes, got " <> show os)

  -- An undetermined result has one JSON shape, `l4 run --json`'s: what it
  -- waits on under "undetermined", as {"needs", "message"}, and not an
  -- "error", which it is not. The API reports it as no verdict, a null
  -- "success", never the false of a failed assertion.
  describe "an undetermined result in JSON" $ do
    let src = Text.unlines
          [ "§ `Unknown`"
          , "    GIVEN x IS A BOOLEAN"
          , "          y IS A BOOLEAN"
          , "#ASSERT x"
          , "#EVAL x AND y"
          ]
        needsOf v = field "undetermined" v >>= field "needs"
    it "is the core's, for an #ASSERT and an #EVAL" $ do
      vs <- resultsJson src
      case vs of
        [assertion, eval] -> do
          field "type" assertion `shouldBe` Just (Aeson.String "assertion")
          field "value" assertion `shouldBe` Just Aeson.Null
          field "error" assertion `shouldBe` Nothing
          needsOf assertion `shouldBe` Just (Aeson.toJSON ["x" :: Text.Text])
          (field "undetermined" assertion >>= field "message") `shouldSatisfy` \ case
            Just (Aeson.String m) -> "I needed to know the value of" `Text.isInfixOf` m
            _                     -> False
          field "error" eval `shouldBe` Nothing
          needsOf eval `shouldBe` Just (Aeson.toJSON ["x" :: Text.Text, "y"])
        _ -> expectationFailure ("expected two results, got " <> show vs)
    it "is the API's, with a null success" $ do
      out <- l4Eval src
      case decodeText out >>= field "results" of
        Just (Aeson.Array rs) -> case toList rs of
          [assertion, eval] -> do
            field "success" assertion `shouldBe` Just Aeson.Null
            needsOf assertion `shouldBe` Just (Aeson.toJSON ["x" :: Text.Text])
            field "success" eval `shouldBe` Just Aeson.Null
            needsOf eval `shouldBe` Just (Aeson.toJSON ["x" :: Text.Text, "y"])
          other -> expectationFailure ("expected two results, got " <> show other)
        other -> expectationFailure ("expected results, got " <> show other <> " from " <> show out)
      one <- l4EvalDirective src 4 1 "ASSERT"
      let v = decodeText one
      (v >>= field "success") `shouldBe` Just Aeson.Null
      (v >>= needsOf) `shouldBe` Just (Aeson.toJSON ["x" :: Text.Text])
    -- Each need is spelled as L4 source, as the message lists it, so a
    -- path whose names have spaces can be split back into them.
    it "spells each need as L4 source, quoting a name with spaces" $ do
      vs <- resultsJson $ Text.unlines
        [ "DECLARE Person HAS `age in years` IS A NUMBER"
        , "§ `Unknown`"
        , "    GIVEN `the applicant` IS A Person"
        , "          `has criminal record` IS A BOOLEAN"
        , "          d IS A Person"
        , "#EVAL `the applicant`'s `age in years` GREATER THAN 18 AND `has criminal record`"
        , "#EVAL d's `age in years` GREATER THAN 1"
        ]
      map needsOf vs `shouldBe`
        [ Just (Aeson.toJSON ["`the applicant`'s `age in years`" :: Text.Text, "`has criminal record`"])
        , Just (Aeson.toJSON ["d's `age in years`" :: Text.Text])
        ]

  -- Coverage for the step-3 review: each fails under the mutation named
  -- beside it in the commit that added it.
  describe "coverage" $ do
    let unknowns = Text.unlines
          [ "DECLARE Pair HAS num IS A NUMBER, tag IS A STRING"
          , "§ `Unknown`"
          , "    GIVEN x IS A BOOLEAN"
          , "          n IS A NUMBER"
          ]
    -- the biconditional is a connective, combined by §4.3's table, which
    -- decides nothing here: `x EQUALS FALSE` is `NOT x`, and `NOT x EQUALS x`
    -- is left for the truth table of build step 4
    it "leaves (x EQUALS FALSE) EQUALS x undetermined" $ do
      os <- outcomes $ unknowns <> "#EVAL (x EQUALS FALSE) EQUALS x\n"
      os `shouldBe` [Waits ["x"]]
    -- a structural equality whose components include a term is that term,
    -- conjoined, unless another component is FALSE
    it "keeps a term component of a structural equality, and lets a FALSE one decide" $ do
      os <- outcomes $ unknowns <> Text.unlines
        [ "#EVAL (LIST n) EQUALS (LIST 1)"
        , "#EVAL (Pair n \"a\") EQUALS (Pair 3 \"b\")"
        ]
      os `shouldBe` [Waits ["n"], Value "FALSE"]
    -- an error in a component after a term is Stuck on the term: had `n`
    -- not been 1, the two-valued run would have stopped at it
    it "is Stuck on the term where a later component of a structural equality raises" $ do
      os <- outcomes $ unknowns <> "#EVAL (LIST n, 1 DIVIDED BY 0) EQUALS (LIST 1, 5)\n"
      os `shouldBe` [Waits ["n"]]
    -- A stack overflow in a speculative right operand is Stuck on the left,
    -- like any error there. The counter limits the right operand to 250,000
    -- steps, about 9,000 levels of `sink`, so `grow` first fills the stack to
    -- within 1,000 frames of its cap (1,000,000; measured: `grow` alone
    -- overflows between 999,414 and 1,000,000 levels) outside any
    -- speculation, and `sink` overflows it inside one, before it runs out of
    -- steps. The control below shows the overflow is real.
    describe "a stack overflow under an unknown" $ do
      let deep bottom = unknowns <> Text.unlines
            [ "GIVEN i IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "sink i MEANS IF i EQUALS 0 THEN TRUE ELSE (sink (i MINUS 1)) AND TRUE"
            , "GIVEN i IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "grow i MEANS IF i EQUALS 0 THEN " <> bottom <> " ELSE (grow (i MINUS 1)) AND TRUE"
            , "#EVAL grow 999000"
            ]
      it "is Stuck on the left operand's inputs" $ do
        os <- outcomes (deep "x AND (sink 50000)")
        os `shouldBe` [Waits ["x"]]
      it "is a stack overflow with the left operand supplied" $ do
        os <- outcomes (deep "TRUE AND (sink 50000)")
        os `shouldSatisfy` \ case
          [Errors t] -> "Stack overflow" `Text.isInfixOf` t
          _          -> False
