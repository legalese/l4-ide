{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | smucclaw/l4-ide#1097: @l4 check@ warns on a @LEST@ that nothing can
-- reach, which is a @LEST@ on a @MUST@, @DO@ or @MAY@ with no deadline.
--
-- Two halves. The first counts the warning per rule shape: one where the
-- rule has no deadline, none where it has one (on the act, as @WITHIN@,
-- @WITHIN … OF@ or @BEFORE@, or on an @EVERY@'s join line), none on a
-- @MUST NOT@ or @SHANT@, none where there is no @LEST@. The second runs
-- each rule against the trace most likely to reach its @LEST@ (a long wait,
-- or the forbidden act for a prohibition) and asserts that the warning
-- fires exactly where the evaluator never took the @LEST@, so the checker's
-- reading cannot drift from the machine's.
--
-- The warning is matched by its code, so this file compiles against a tree
-- without it.
module LestWithoutDeadlineSpec (spec) where

import Control.Monad (forM)
import Data.Foldable (for_)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.EvaluateLazy (execEvalModuleWithEnv, prettyEvalDirectiveResult, resolveEvalConfig)
import L4.Import.Resolution (ResolvedImport (..), TypeCheckWithDepsResult (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.TracePolicy (apiDefaultPolicy)
import L4.TypeCheck.Types (CheckErrorWithContext (..), checkErrorCode)
import L4.Annotation (HasSrcRange (..))
import qualified L4.TypeCheck as TC

code :: Text
code = "lint/lest-without-deadline"

prologue :: [Text]
prologue =
  [ "IMPORT prelude"
  , "IMPORT daydate"
  , "DECLARE Actor IS ONE OF"
  , "    Landlord"
  , "    Tenant HAS name IS A STRING"
  , "DECLARE Act IS ONE OF payRent, refund, smoke"
  , "alice MEANS Tenant OF \"Alice\""
  , "tenants MEANS LIST alice"
  ]

-- | The rule under test is always called @r@, and its LEST (when it has one)
-- is always the same obligation, so the evaluator half can tell from the
-- result whether the LEST was taken: a taken LEST leaves the landlord's
-- refund, which has no LEST of its own.
module_ :: [Text] -> [Text] -> Text
module_ rule trace = Text.unlines $
  prologue <>
  [ "GIVETH A DEONTIC Actor Act"
  , "r MEANS" ] <>
  map ("  " <>) rule <>
  [ "" ] <>
  trace

lestBody :: Text
lestBody = "LEST (PARTY Landlord MUST refund)"

-- | Each shape: its name, the rule's lines, how many warnings it draws, and
-- the trace most likely to reach its LEST (Nothing when it has none).
data Shape = Shape
  { name :: String
  , rule :: [Text]
  , warnings :: Int
  , trace :: Maybe [Text]
  }

-- | A long wait: if time can take this rule to its LEST, this does.
waitLong :: [Text]
waitLong = [ "#TRACE r AT 0 WITH", "  (WAITUNTIL 1000000)" ]

-- | The forbidden act, for a prohibition: what takes it to its LEST.
violate :: [Text]
violate = [ "#TRACE r AT 0 WITH", "  PARTY alice DOES smoke AT 5" ]

shapes :: [Shape]
shapes =
  -- no deadline: the LEST can never be reached
  [ Shape "MUST, no deadline (the issue's repro)"
      [ "PARTY alice", "MUST payRent", lestBody ] 1 (Just waitLong)
  , Shape "DO, no deadline"
      [ "PARTY alice", "DO payRent", lestBody ] 1 (Just waitLong)
  , Shape "MAY, no deadline"
      [ "PARTY alice", "MAY payRent", lestBody ] 1 (Just waitLong)
  , Shape "MUST with an AFTER and no closing edge"
      [ "PARTY alice", "MUST payRent", "AFTER 10", lestBody ] 1 (Just waitLong)
  , Shape "EVERY barrier with no WITHIN anywhere"
      [ "EVERY Tenant t IN tenants", "  MUST payRent", "  ONCE ALL HAVE", "  " <> lestBody ] 1 (Just waitLong)
  , Shape "EVERY fork with no WITHIN anywhere"
      [ "EVERY Tenant t IN tenants", "  MUST payRent", "  UPON EACH", "  " <> lestBody ] 1 (Just waitLong)
  -- a deadline: the LEST is reached when it passes
  , Shape "MUST WITHIN"
      [ "PARTY alice", "MUST payRent", "WITHIN 30", lestBody ] 0 (Just waitLong)
  , Shape "MUST WITHIN with an OF anchor"
      [ "PARTY alice", "MUST payRent", "WITHIN 30 OF THE ARMING", lestBody ] 0 (Just waitLong)
  , Shape "MUST AFTER and WITHIN"
      [ "PARTY alice", "MUST payRent", "AFTER 10", "WITHIN 30", lestBody ] 0 (Just waitLong)
  , Shape "DO WITHIN"
      [ "PARTY alice", "DO payRent", "WITHIN 30", lestBody ] 0 (Just waitLong)
  , Shape "MAY WITHIN"
      [ "PARTY alice", "MAY payRent", "WITHIN 30", lestBody ] 0 (Just waitLong)
  , Shape "MUST BEFORE a date"
      [ "PARTY alice", "MUST payRent", "BEFORE (YMD 2026 6 30)", lestBody ] 0
      (Just [ "#TRACE r AT (DATE_SERIAL (YMD 2026 6 1)) WITH", "  (WAITUNTIL (DATE_SERIAL (YMD 2027 1 1)))" ])
  , Shape "EVERY barrier with its only WITHIN on the ONCE line"
      [ "EVERY Tenant t IN tenants", "  MUST payRent", "  ONCE ALL HAVE WITHIN 30", "  " <> lestBody ] 0 (Just waitLong)
  , Shape "EVERY fork with its only WITHIN on the UPON EACH line"
      [ "EVERY Tenant t IN tenants", "  MUST payRent", "  UPON EACH WITHIN 30", "  " <> lestBody ] 0 (Just waitLong)
  , Shape "EVERY barrier with a WITHIN on the act"
      [ "EVERY Tenant t IN tenants", "  MUST payRent", "  WITHIN 30", "  ONCE ALL HAVE", "  " <> lestBody ] 0 (Just waitLong)
  -- a prohibition: the forbidden act reaches the LEST, deadline or not
  , Shape "MUST NOT, no deadline"
      [ "PARTY alice", "MUST NOT smoke", lestBody ] 0 (Just violate)
  , Shape "SHANT, no deadline"
      [ "PARTY alice", "SHANT smoke", lestBody ] 0 (Just violate)
  , Shape "MUST NOT WITHIN"
      [ "PARTY alice", "MUST NOT smoke", "WITHIN 30", lestBody ] 0 (Just violate)
  -- no LEST: nothing to warn about
  , Shape "MUST, no deadline, HENCE only"
      [ "PARTY alice", "MUST payRent", "HENCE FULFILLED" ] 0 Nothing
  , Shape "MUST, no deadline, no HENCE and no LEST"
      [ "PARTY alice", "MUST payRent" ] 0 Nothing
  ]

checked :: Text -> IO TypeCheckWithDepsResult
checked src = case checkWithImports (vfsFromList []) src of
  Left errs -> fail (Text.unpack (Text.unlines errs))
  Right r -> pure r

lestWarnings :: TypeCheckWithDepsResult -> [CheckErrorWithContext]
lestWarnings r = [ e | e <- r.tcdErrors, checkErrorCode e.kind == code ]

-- | The text of the first directive's result. Each import is evaluated
-- first, as @l4 run@ does, so the prelude's and daydate's definitions are
-- there when the trace reads them.
firstResult :: Text -> IO Text
firstResult src = do
  cfg <- resolveEvalConfig (Just (UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0))) apiDefaultPolicy
  r <- checked src
  importEnv <- mconcat <$> forM r.tcdResolvedImports \ ri ->
    fst <$> execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo mempty ri.riTypeChecked.program
  (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo importEnv r.tcdModule
  case results of
    (x : _) -> pure (Text.strip (prettyEvalDirectiveResult x))
    []      -> fail "the trace produced no result"

-- | Did the trace take the LEST? A taken LEST leaves the landlord's refund;
-- an untaken one leaves the rule itself, which starts with its own party.
lestTaken :: Text -> Bool
lestTaken = Text.isPrefixOf "PARTY Landlord MUST refund"

spec :: Spec
spec = describe "a LEST on a rule with no deadline (smucclaw/l4-ide#1097)" do
  describe "how many warnings each shape draws" do
    for_ shapes \ s ->
      it s.name do
        r <- checked (module_ s.rule [])
        r.tcdSuccess `shouldBe` True
        length (lestWarnings r) `shouldBe` s.warnings

  describe "the warning fires exactly where the evaluator never takes the LEST" do
    for_ shapes \ s -> for_ s.trace \ tr ->
      it s.name do
        r <- checked (module_ s.rule tr)
        out <- firstResult (module_ s.rule tr)
        -- the run happened, and left an obligation to read: a failed run
        -- prints an error here, which neither reading would match
        out `shouldSatisfy` Text.isPrefixOf "PARTY "
        (not (null (lestWarnings r)), lestTaken out) `shouldSatisfy` \ (warned, taken) -> warned /= taken

  it "stays silent on an EVERY with no join line, which is already an error asking for the line" do
    -- the join line is where a deadline could go, so the warning would name
    -- a line the author has not written, on a rule that cannot run yet
    r <- checked (module_ [ "EVERY Tenant t IN tenants", "  MUST payRent", "  " <> lestBody ] [])
    [ e | e <- r.tcdErrors, checkErrorCode e.kind == "check/continuation-without-join" ]
      `shouldSatisfy` (not . null)
    length (lestWarnings r) `shouldBe` 0

  it "sits on the LEST keyword of the rule that has no deadline, not on an enclosing one" do
    -- the outer rule has a deadline; the rule under its LEST does not
    let src = module_
          [ "PARTY alice"
          , "MUST payRent"
          , "WITHIN 30"
          , "LEST"
          , "  PARTY alice"
          , "  MUST refund"
          , "  LEST (PARTY Landlord MUST refund)"
          ] []
    r <- checked src
    case lestWarnings r of
      [w] -> case rangeOf w of
        Just rng -> do
          -- the inner LEST is on the 7th line of the rule, after the
          -- prologue, GIVETH and the rule's head; the rule is indented by 2,
          -- and the inner LEST by 2 more
          -- (the end column is the one after the keyword's last letter)
          (rng.start.line, rng.start.column, rng.end.column) `shouldBe` (length prologue + 9, 5, 9)
        Nothing -> expectationFailure "the warning has no range"
      ws -> expectationFailure ("expected one warning, got " <> show (length ws))

  it "says the LEST can never be reached, and offers a WITHIN or removing the LEST" do
    r <- checked (module_ [ "PARTY alice", "MUST payRent", lestBody ] [])
    case lestWarnings r of
      [w] -> do
        let msg = Text.unlines (TC.prettyCheckErrorWithContext w)
        msg `shouldSatisfy` Text.isInfixOf "can never be reached"
        msg `shouldSatisfy` Text.isInfixOf "add a WITHIN"
        msg `shouldSatisfy` Text.isInfixOf "remove the LEST"
      ws -> expectationFailure ("expected one warning, got " <> show (length ws))
