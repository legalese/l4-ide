{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A @#TRACE@ whose start or event carries a time stamp that is not a whole
-- number is a legitimate thing to write and the evaluator uses the stamp as
-- written. @l4 explore@ tries whole instants only, and a reader who ran
-- @l4 run@ on such a trace had no hint of that. The type checker now says so,
-- as a notice (severity Information): it blocks nothing and asks for nothing.
module TraceFractionalStampSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.TypeCheck (prettyCheckErrorWithContext)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.TypeCheck.Types
  (CheckError (..), CheckErrorWithContext (..), Severity (..), checkErrorCode, severity)
import L4.Annotation (HasSrcRange (..))

-- | A contract and the traces over it; the lines of the stamps are given in
-- the expectations below.
contract :: [Text]
contract =
  [ "DECLARE Person IS ONE OF P"
  , "DECLARE Action IS ONE OF a"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "`one` MEANS PARTY P MUST a WITHIN 3 HENCE FULFILLED LEST BREACH BY P"
  , ""
  ]

notices :: [Text] -> [CheckErrorWithContext]
notices traces = case checkWithImports emptyVFS (Text.unlines (contract <> traces)) of
  Left errs -> error ("the fixture failed to check: " <> show errs)
  Right r -> [ e | e@(MkCheckErrorWithContext FractionalTraceStamp {} _) <- r.tcdErrors ]

stampsOf :: [CheckErrorWithContext] -> [Rational]
stampsOf es = [ s | MkCheckErrorWithContext (FractionalTraceStamp s _) _ <- es ]

linesOf :: [CheckErrorWithContext] -> [Int]
linesOf es = [ l | e <- es, Just (MkSrcRange (MkSrcPos l _) _ _ _) <- [rangeOf e] ]

spec :: Spec
spec = describe "a fractional time stamp in a #TRACE" do
  it "is noticed in a WAITUNTIL and in an act's AT, once each, where it is written" do
    let ns = notices
          [ "#TRACE `one` AT 0 WITH"        -- line 7
          , "  (WAITUNTIL 3.8)"              -- line 8
          , "  PARTY P DOES a AT 4.25"       -- line 9
          ]
    stampsOf ns `shouldBe` [19 / 5, 17 / 4]
    linesOf ns `shouldBe` [8, 9]

  it "is noticed in the trace's own start" do
    stampsOf (notices ["#TRACE `one` AT 0.5 WITH", "  (WAITUNTIL 4)"]) `shouldBe` [1 / 2]

  it "is a notice, not an error and not a warning, under a stable code" do
    let ns = notices ["#TRACE `one` AT 0 WITH", "  (WAITUNTIL 3.5)"]
    map severity ns `shouldBe` [SInfo]
    map (\(MkCheckErrorWithContext e _) -> checkErrorCode e) ns `shouldBe` ["lint/fractional-trace-stamp"]

  it "says nothing about whole numbers, whether the trace writes them with a decimal point or not" do
    stampsOf (notices ["#TRACE `one` AT 0 WITH", "  (WAITUNTIL 4)", "  PARTY P DOES a AT 4.0"]) `shouldBe` []

  it "says nothing about a stamp that is not a literal, which has no value until it is evaluated" do
    stampsOf (notices ["#TRACE `one` AT 0 WITH", "  (WAITUNTIL (7 / 2))"]) `shouldBe` []

  it "is printed exactly, not through a Double" do
    let ns = notices ["#TRACE `one` AT 0 WITH", "  PARTY P DOES a AT 2.0000000000000000001"]
        text = Text.unlines (concatMap prettyCheckErrorWithContext ns)
    stampsOf ns `shouldBe` [20000000000000000001 / 10000000000000000000]
    text `shouldSatisfy` ("a time stamp of 2.0000000000000000001, which" `Text.isInfixOf`)
