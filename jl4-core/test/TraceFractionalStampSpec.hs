{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A @#TRACE@ whose event carries a time stamp that is not a whole number is
-- a legitimate thing to write and the evaluator uses the stamp as written.
-- @l4 explore@ does not read an event's stamp at all (from a @#TRACE@ it takes
-- the contract and the start), and by default it tries whole instants, so a
-- reader who ran @l4 run@ on such a trace had no hint that the explorer would
-- not try that time. The type checker says so, as a notice (severity
-- Information): it blocks nothing and asks for nothing.
--
-- The trace's own start is not noticed: @l4 explore@ does read it, as its
-- clock, and says itself, with exit status 2, what that leaves untried.
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

  it "is not noticed in the trace's own start, which `l4 explore` reads as its clock" do
    stampsOf (notices ["#TRACE `one` AT 0.5 WITH", "  (WAITUNTIL 4)"]) `shouldBe` []

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

  it "does not say that `l4 explore` tries whole instants only: it reads no event stamp, tries whole instants by default, and --grid steps finer" do
    let text = Text.unlines (concatMap prettyCheckErrorWithContext
          (notices ["#TRACE `one` AT 0 WITH", "  (WAITUNTIL 3.8)"]))
    text `shouldSatisfy` (not . ("whole instants only" `Text.isInfixOf`))
    text `shouldSatisfy` (not . ("does not explore the positions" `Text.isInfixOf`))
    text `shouldSatisfy` ("`l4 explore` does not read it" `Text.isInfixOf`)
    text `shouldSatisfy` ("`--grid 0.5`" `Text.isInfixOf`)
