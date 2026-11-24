-- | Black-box tests for @l4 coverage@ (CATALA-EXPORT-SPEC §8.4, "A standalone
-- report"). The verb, the flags, the layout and the exit statuses were ruled
-- on 2026-11-12 (TALLYSTICK); the rows for answers that differ inside a bucket
-- and for inputs no condition reads came after, and were ruled later the same
-- day (CROSSWORD).
module CliTest.Coverage (spec, fixtures) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.List (isInfixOf, isPrefixOf)
import Data.Foldable (toList)
import qualified Data.Text as T
import System.Exit (ExitCode (..))
import Test.Hspec

import CliTest.Common

-- | The files these tests read, checked before hspec runs anything.
fixtures :: [FilePath]
fixtures =
  [ "examples/catala/bands.l4"
  , "examples/catala/many-bands.l4"
  , "examples/catala/or-leaves.l4"
  , "examples/catala/guarded-leaf.l4"
  , "examples/coverage-report/expected/bands.txt"
  , "examples/coverage-report/expected/or-leaves.txt"
  , "examples/coverage-report/no-condition.l4"
  , "examples/coverage-report/varies.l4"
  , "examples/coverage-report/unread.l4"
  , "examples/coverage-report/consider.l4"
  , "examples/coverage-report/consider-shapes.l4"
  , "examples/coverage-report/consider-limits.l4"
  , "examples/coverage-report/consider-partial.l4"
  , "examples/coverage-report/consider-text.l4"
  , "examples/coverage-report/expected/consider.txt"
  , "examples/coverage-report/expected/consider-shapes.txt"
  , "examples/coverage-report/expected/consider-limits.txt"
  ]

spec :: FilePath -> Spec
spec bin = describe "l4 coverage" $ do
  -- One of the four combinations (the higher band without the lower) is
  -- impossible, and only a solver can say so, so these need z3.
  it "prints the cover points, the buckets, a witness for each and the proof for the impossible one" $ withZ3 $ do
    expectOutput bin ExitSuccess ["coverage", "examples/catala/bands.l4"]
                 "examples/coverage-report/expected/bands.txt"

  -- Three leaves in one rung: seven realisable combinations of them, each its
  -- own bucket, none needing a solver.
  it "counts the leaves of a rung, not the rung" $ do
    expectOutput bin ExitSuccess ["coverage", "examples/catala/or-leaves.l4"]
                 "examples/coverage-report/expected/or-leaves.txt"

  it "lists a few of the buckets a solver proved impossible and says how to see the rest" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/catala/many-bands.l4"]
    code `shouldBe` ExitSuccess
    sout `shouldSatisfy` ("512 combinations: 10 witnessed, 502 proved impossible, none undecided" `isInfixOf`)
    sout `shouldSatisfy` ("... and 486 more proved impossible (--all lists them, --json carries them)" `isInfixOf`)
    Output code' sout' _ <- runL4 bin ["coverage", "--all", "examples/catala/many-bands.l4"]
    code' `shouldBe` ExitSuccess
    sout' `shouldNotSatisfy` ("more proved impossible" `isInfixOf`)

  -- A leaf that raises where its rung is decided without reaching it: the
  -- decision is covered by its rungs, says so, and the status says it is not
  -- the finer report.
  it "covers a decision at rung level, and exits 3, where a leaf raises behind its guard" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/catala/guarded-leaf.l4"]
    code `shouldBe` ExitFailure 3
    sout `shouldSatisfy` ("AT RUNG LEVEL" `isInfixOf`)
    sout `shouldSatisfy` ("instalments = 0" `isInfixOf`)

  -- Without a solver the one impossible combination is neither reached nor
  -- proved, and a script must not read that as covered.
  it "leaves a bucket undecided, and exits 2, when there is no solver to decide it" $ do
    Output code sout _ <- runL4WithEnvExtra [("Z3_EXE", "/nonexistent/z3")] bin
                            ["coverage", "examples/catala/bands.l4"]
    code `shouldBe` ExitFailure 2
    sout `shouldSatisfy` ("UNDECIDED" `isInfixOf`)
    sout `shouldSatisfy` ("no SMT solver was found" `isInfixOf`)

  it "carries the same report as JSON" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["coverage", "--json", "examples/catala/bands.l4"]
    code `shouldBe` ExitSuccess
    let doc = Aeson.decode (BSL8.pack sout) :: Maybe Aeson.Value
        decisions = case doc of
          Just (Aeson.Object o) | Just (Aeson.Array ds) <- KM.lookup "decisions" o -> toList ds
          _ -> []
    case decisions of
      [Aeson.Object d] -> do
        KM.lookup "level" d `shouldBe` Just (Aeson.String "leaf")
        fmap (\ v -> case v of Aeson.Array bs -> length bs; _ -> -1) (KM.lookup "buckets" d) `shouldBe` Just 4
      _ -> expectationFailure ("expected one decision in the JSON report, got: " ++ sout)

  -- Every income that is not above 1000 lands in one bucket and has its own
  -- allowance, so the bucket has three answers, and the row must not read as
  -- if it had one.
  it "says when the answers inside one bucket differ" $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/varies.l4"]
    code `shouldBe` ExitSuccess
    sout `shouldSatisfy` ("L4's answer DIFFERS across them: 3 different values" `isInfixOf`)
    sout `shouldSatisfy` ("different values (0, 50, 49.95)" `isInfixOf`)
    sout `shouldSatisfy` ("income = 999 gives 49.95" `isInfixOf`)
    -- the other bucket has one input and one answer, and says so plainly
    sout `shouldSatisfy` ("witnessed by 1 input; L4 answers 100.1" `isInfixOf`)

  -- An input no condition reads is tried at one value, and the report says
  -- which, because the answers it prints are only as varied as its inputs.
  it "names the inputs that no condition reads" $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/unread.l4"]
    code `shouldBe` ExitSuccess
    sout `shouldSatisfy` ("Inputs no condition reads (tried at one value only, so the answers below may vary with them): income" `isInfixOf`)

  it "refuses a --decision that names nothing, exit 1" $ do
    Output code _ serr <- runL4 bin ["coverage", "--decision", "no such rule", "examples/catala/bands.l4"]
    code `shouldBe` ExitFailure 1
    serr `shouldSatisfy` ("no decision named no such rule" `isInfixOf`)

  it "does not call a file with nothing to cover covered: exit 3" $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/no-condition.l4"]
    code `shouldBe` ExitFailure 3
    sout `shouldSatisfy` ("NOTHING COVERED" `isInfixOf`)

  -- smucclaw/l4-ide#1094. Each WHEN of a CONSIDER over the options of a
  -- choice is a condition the rule branches on, as each IF of the BRANCH it
  -- stands for is: before, the CONSIDER was counted among the rules with no
  -- condition to branch on, and the run still exited 0. Both decisions of the
  -- file must be listed, with the same cover points and the same buckets.
  -- (The one impossible combination, two options at once, needs a solver.)
  it "covers each WHEN of a CONSIDER over options, as it covers each IF of the BRANCH twin" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["coverage", "--json", "examples/coverage-report/consider.l4"]
    code `shouldBe` ExitSuccess
    let twin = decisionNamed sout "monthly fee by BRANCH"
        consider = decisionNamed sout "monthly fee"
    fmap pointTexts consider `shouldBe` Just ["p EQUALS basic", "p EQUALS pro"]
    fmap pointTexts consider `shouldBe` fmap pointTexts twin
    (consider >>= KM.lookup "buckets") `shouldBe` (twin >>= KM.lookup "buckets")
    (consider >>= KM.lookup "level") `shouldBe` Just (Aeson.String "leaf")
    expectOutput bin ExitSuccess ["coverage", "examples/coverage-report/consider.l4"]
                 "examples/coverage-report/expected/consider.txt"

  -- The other CONSIDERs whose every WHEN is one condition: one that lists
  -- every option and has no OTHERWISE (no plan is none of them, which the
  -- solver proves), one over numbers, which before was covered only at rung
  -- level with every cover point spanning the whole CONSIDER, and one in a
  -- BOOLEAN rule, whose report is the same as before.
  it "covers a CONSIDER with no OTHERWISE, and a CONSIDER over numbers, at leaf level" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/consider-shapes.l4"]
    sout `shouldNotSatisfy` ("AT RUNG LEVEL" `isInfixOf`)
    sout `shouldNotSatisfy` ("no condition to branch on" `isInfixOf`)
    code `shouldBe` ExitSuccess
    expectOutput bin ExitSuccess ["coverage", "examples/coverage-report/consider-shapes.l4"]
                 "examples/coverage-report/expected/consider-shapes.txt"

  -- A WHEN that takes an option apart, a pattern inside a pattern, a new name,
  -- and an OTHERWISE before the last WHEN are not one yes-or-no condition
  -- each. Such a rule is named as not covered, with a reason that names
  -- CONSIDER, and the run exits 3; it is never counted among the rules with
  -- no condition to branch on.
  it "names a CONSIDER it cannot cover as not covered, with the reason, and exits 3" $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/consider-limits.l4"]
    sout `shouldNotSatisfy` ("no condition to branch on" `isInfixOf`)
    length (filter ("NOT COVERED: its body is a CONSIDER" `isInfixOf`) (lines sout)) `shouldBe` 4
    code `shouldBe` ExitFailure 3
    expectOutput bin (ExitFailure 3) ["coverage", "examples/coverage-report/consider-limits.l4"]
                 "examples/coverage-report/expected/consider-limits.txt"

  -- A CONSIDER with no OTHERWISE whose WHENs miss an option: the bucket in
  -- which no WHEN holds is reached only by the option none of them names, at
  -- which L4 raises, so it is undecided and the run exits 2, whether or not
  -- the rule is marked @nonexhaustive.
  it "leaves undecided the bucket of a CONSIDER that no WHEN matches, with or without @nonexhaustive, and exits 2" $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/consider-partial.l4"]
    length (filter ("    F  F    UNDECIDED: " `isPrefixOf`) (lines sout)) `shouldBe` 2
    code `shouldBe` ExitFailure 2

  -- A CONSIDER over text: the report writes the conditions for a solver that
  -- has no text, so the rule is not covered, and the run exits 3. The help and
  -- coverage.md once listed text among the shapes covered.
  it "names a CONSIDER over text as not covered, since the solver cannot read text, and exits 3" $ do
    Output code sout _ <- runL4 bin ["coverage", "examples/coverage-report/consider-text.l4"]
    sout `shouldSatisfy` ("NOT COVERED: out of fragment: STRING" `isInfixOf`)
    code `shouldBe` ExitFailure 3

-- | One decision of a @--json@ report, by name.
decisionNamed :: String -> String -> Maybe Aeson.Object
decisionNamed sout name =
  case Aeson.decode (BSL8.pack sout) :: Maybe Aeson.Value of
    Just (Aeson.Object o) | Just (Aeson.Array ds) <- KM.lookup "decisions" o ->
      case [ d | Aeson.Object d <- toList ds, KM.lookup "name" d == Just (Aeson.String (T.pack name)) ] of
        [d] -> Just d
        _ -> Nothing
    _ -> Nothing

-- | The texts of a decision's cover points, in order.
pointTexts :: Aeson.Object -> [String]
pointTexts d = case KM.lookup "coverPoints" d of
  Just (Aeson.Array ps) -> [ T.unpack t | Aeson.Object p <- toList ps, Just (Aeson.String t) <- [KM.lookup "text" p] ]
  _ -> []

-- | The exit status is part of the claim, so it is asserted, not assumed.
expectOutput :: FilePath -> ExitCode -> [String] -> FilePath -> IO ()
expectOutput bin want args goldenPath = do
  Output code sout serr <- runL4 bin args
  golden <- readUtf8 goldenPath
  code `shouldBe` want
  unless' (scrubSolverVersion sout == scrubSolverVersion golden) $
    expectationFailure $
      "Output does not match golden " ++ goldenPath
      ++ "\n(to update: l4 " ++ unwords args ++ " > " ++ goldenPath
      ++ ", then put $Z3_VERSION where the solver's version is)"
      ++ "\n--- got ---\n" ++ sout ++ "\n--- golden ---\n" ++ golden ++ "\n--- stderr ---\n" ++ serr
 where
  unless' c a = if c then pure () else a

-- | The solver's version is the one thing in a report that depends on the
-- machine, and the z3 that CI installs is not the one a golden was blessed
-- with, so both sides are compared with it replaced (a report, like
-- @l4 prove@'s, names it so that a reader can tell what proved a bucket
-- impossible; what the tests pin is the rest).
scrubSolverVersion :: String -> String
scrubSolverVersion [] = []
scrubSolverVersion s@(c : cs)
  | prefix `isPrefixOf` s =
      prefix ++ "$Z3_VERSION" ++ scrubSolverVersion (dropWhile (`notElem` (",;\n" :: String)) (drop (length prefix) s))
  | otherwise = c : scrubSolverVersion cs
 where
  prefix = "Z3 version " :: String
