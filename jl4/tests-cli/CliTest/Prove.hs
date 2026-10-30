-- | Black-box tests for @l4 prove@ (VERIFICATION-BACKEND-LOWERING-SPEC,
-- Phase 1): the verdict per @#ASSERT@, the replayed counterexample, the
-- coverage line, and the exit status a CI job reads.
--
-- The assertions are on VERDICTS and on the values in a counterexample, never
-- on the solver's own text, which differs between z3 versions.
--
-- Every test that needs a solver goes through 'withZ3'. Without one it is
-- reported PENDING (@skipped: z3 not found@), never passed; with
-- @Z3_CHECK_REQUIRED=1@, which the CI Haskell job sets, a missing solver fails
-- the test instead. The @--emit-smt@ tests need no solver at all (R-V6:
-- "goldens over the emitted SMT-LIB2 run with no solver installed").
module CliTest.Prove (spec, fixtures) where

import Data.Foldable (for_)
import Data.List (isInfixOf, isPrefixOf, sort)
import System.Directory (listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common

numbersFixture, recordsFixture, outOfFragmentFixture, defectFixture, integersFixture, sameLineFixture, assumedFixture,
  collideFixture, localsFixture, decidedFailFixture, exactFixture, hashNameFixture, lazyFieldFixture,
  rebateBuggyFixture, rebateFixedFixture, rebateNoFloorFixture :: FilePath
numbersFixture       = fixtureDir </> "prove" </> "numbers.l4"
recordsFixture       = fixtureDir </> "prove" </> "records.l4"
outOfFragmentFixture = fixtureDir </> "prove" </> "out-of-fragment.l4"
defectFixture        = fixtureDir </> "prove" </> "defect.l4"
integersFixture      = fixtureDir </> "prove" </> "integers.l4"
collideFixture       = fixtureDir </> "prove" </> "collide.l4"
localsFixture        = fixtureDir </> "prove" </> "locals.l4"
decidedFailFixture   = fixtureDir </> "prove" </> "decided-fail.l4"
exactFixture         = fixtureDir </> "prove" </> "exact.l4"
hashNameFixture      = fixtureDir </> "prove" </> "hash-name.l4"
lazyFieldFixture     = fixtureDir </> "prove" </> "lf2.l4"
sameLineFixture      = fixtureDir </> "prove" </> "same-line.l4"
assumedFixture       = fixtureDir </> "assert-assumed.l4"
rebateBuggyFixture   = fixtureDir </> "prove" </> "rates-rebate-buggy.l4"
rebateFixedFixture   = fixtureDir </> "prove" </> "rates-rebate-fixed.l4"
rebateNoFloorFixture = fixtureDir </> "prove" </> "rates-rebate-no-floor.l4"

fixtures :: [FilePath]
fixtures = [numbersFixture, recordsFixture, outOfFragmentFixture, defectFixture, integersFixture, sameLineFixture, assumedFixture
           , collideFixture, localsFixture, decidedFailFixture, exactFixture, hashNameFixture, lazyFieldFixture
           , rebateBuggyFixture, rebateFixedFixture, rebateNoFloorFixture]

-- | The lines of a run's report that belong to the @#ASSERT@ on this line of
-- the fixture: its verdict line, and the indented lines under it.
rowFor :: Int -> String -> [String]
rowFor n sout =
  case break isRow (lines sout) of
    (_, r : rest) -> r : takeWhile ("      " `isPrefixOf`) rest
    _ -> []
 where
  isRow l = (":" <> show n <> ":") `isInfixOf` l && "#ASSERT" `isInfixOf` l

verdictOf :: Int -> String -> String
verdictOf n sout = case rowFor n sout of
  (r : _) -> takeWhile (/= ' ') (dropWhile (== ' ') r)
  [] -> "<no row for line " <> show n <> ">"

-- | The value a counterexample gives to a name: @x = 0.5@ gives @0.5@.
valueOf :: String -> [String] -> Maybe String
valueOf name = go . words . unwords
 where
  go (n : "=" : v : _) | n == name = Just (filter (/= ',') v)
  go (_ : rest) = go rest
  go [] = Nothing

-- | A value printed as a decimal or a ratio is not a whole number.
isFraction :: String -> Bool
isFraction v = '.' `elem` v || '/' `elem` v

spec :: FilePath -> Spec
spec bin = describe "l4 prove" $ do
  it "refutes both polarities of the smallest undecidable assertion, with the witness the spec predicts (R-V3)" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", assumedFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 7 sout `shouldBe` "refuted"
    verdictOf 8 sout `shouldBe` "refuted"
    unwords (rowFor 7 sout) `shouldSatisfy` ("counterexample: b = FALSE" `isInfixOf`)
    unwords (rowFor 8 sout) `shouldSatisfy` ("counterexample: b = TRUE" `isInfixOf`)
    -- R-V5: a counterexample is reported only once the evaluator agrees
    unwords (rowFor 7 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

  it "proves, refutes and leaves to the evaluator the right #ASSERTs over NUMBER" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", numbersFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 12 sout `shouldBe` "proved"
    verdictOf 15 sout `shouldBe` "proved"
    verdictOf 18 sout `shouldBe` "proved"
    verdictOf 22 sout `shouldBe` "refuted"
    verdictOf 25 sout `shouldBe` "refuted"
    -- the only point at which x / x raises is 0, and the replay must raise too
    unwords (rowFor 25 sout) `shouldSatisfy` ("counterexample: x = 0" `isInfixOf`)
    unwords (rowFor 25 sout) `shouldSatisfy` ("raises" `isInfixOf`)
    -- a ground #ASSERT is the evaluator's, and is not counted as proved
    verdictOf 28 sout `shouldBe` "decided"
    sout `shouldSatisfy` ("coverage: 6 #ASSERT: 1 decided by evaluation, not re-proved; 5 obligations: 3 proved, 2 refuted, 0 unknown" `isInfixOf`)
    sout `shouldSatisfy` ("solver: " `isInfixOf`)

  it "unfolds a CONSIDER over an enumeration and reads a record's fields" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", recordsFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 19 sout `shouldBe` "proved"
    verdictOf 22 sout `shouldBe` "refuted"
    unwords (rowFor 22 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

  it "reports what it cannot lower as unknown, naming the reason, and exits 3" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", outOfFragmentFixture]
    code `shouldBe` ExitFailure 3
    verdictOf 6 sout `shouldBe` "unknown"
    unwords (rowFor 6 sout) `shouldSatisfy` ("out of fragment: STRING" `isInfixOf`)

  -- The positive control for R-V5's sat half: the encoding is known to be
  -- wrong at p = 0 (a record passed to another rule is lowered as if every
  -- field were read), and the replay must say so instead of reporting a
  -- counterexample.
  it "reports a model the evaluator rejects as an ENCODING DEFECT, never as refuted, and exits 4" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", defectFixture]
    code `shouldBe` ExitFailure 4
    verdictOf 17 sout `shouldBe` "ENCODING"
    unwords (rowFor 17 sout) `shouldSatisfy` ("fails at p = 0, but the evaluator says it holds there" `isInfixOf`)

  -- Soundness: a guard such as IS INTEGER is a hypothesis of its own
  -- obligation and never changes a NUMBER's sort, or the unguarded assertion
  -- below would be "proved" over the integers.
  it "keeps a NUMBER Real whatever guard an assertion carries" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", integersFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 7 sout `shouldBe` "refuted"
    unwords (rowFor 7 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)
    verdictOf 10 sout `shouldBe` "proved"

  -- The guards a drafter has for "whole" or "bounded" are hypotheses of the
  -- one obligation they sit in. A refutation at a fraction must survive
  -- outside the guard (lines 7 and 19) and inside a bound that does not imply
  -- wholeness (line 25); the guarded twins are proved (lines 10, 16, 22).
  it "admits an IS INTEGER, FLOOR or bound guard only as a hypothesis, so a fraction still refutes" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", integersFixture]
    code `shouldBe` ExitFailure 2
    for_ [10, 16, 22] \n -> verdictOf n sout `shouldBe` "proved"
    for_ [7, 19, 25] \n -> do
      verdictOf n sout `shouldBe` "refuted"
      unwords (rowFor n sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)
      fmap isFraction (valueOf "x" (rowFor n sout)) `shouldBe` Just True
    sout `shouldSatisfy` ("coverage: 6 #ASSERT: 0 decided by evaluation, not re-proved; 6 obligations: 3 proved, 3 refuted, 0 unknown" `isInfixOf`)

  -- The same property, stated where no solver is needed: no declaration is an
  -- Int, and the IS INTEGER guard is the antecedent of the goal.
  it "declares every NUMBER Real in the emitted SMT-LIB2, with a guard as the antecedent of the goal" $
    withSystemTempDirectory "l4-prove-smt" \dir -> do
      Output code _ _ <- runL4 bin ["prove", integersFixture, "--emit-smt", dir]
      code `shouldBe` ExitSuccess
      files <- sort <$> listDirectory dir
      length files `shouldBe` 6
      for_ files \f -> do
        script <- readFile (dir </> f)
        script `shouldSatisfy` ("(declare-const |l4_x| Real)" `isInfixOf`)
        filter ("(declare" `isPrefixOf`) (lines script) `shouldSatisfy` all (not . ("Int" `isInfixOf`))
      guarded <- readFile (dir </> "integers-10-1.smt2")
      guarded `shouldSatisfy` ("(=> (is_int |l4_x|)" `isInfixOf`)

  -- The New Zealand rates rebate (the deck "20190514 Multilateral Isomorphism
  -- in L4"): the buggy form takes a bare MINUS for the income excess.
  it "finds the rates-rebate bug: the rebate over its ceiling is refuted, with a counterexample the evaluator replays" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", rebateBuggyFixture]
    -- 2, not 4: the replay agrees, so no ENCODING DEFECT
    code `shouldBe` ExitFailure 2
    -- the deck's worked number, decided by the evaluator and not the solver
    verdictOf 62 sout `shouldBe` "decided"
    unwords (rowFor 62 sout) `shouldSatisfy` ("assertion satisfied" `isInfixOf`)
    verdictOf 66 sout `shouldBe` "decided"
    for_ [76, 80] \n -> do
      verdictOf n sout `shouldBe` "refuted"
      unwords (rowFor n sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)
    sout `shouldSatisfy` ("coverage: 4 #ASSERT: 2 decided by evaluation, not re-proved; 2 obligations: 0 proved, 2 refuted, 0 unknown" `isInfixOf`)

  it "proves the same assertions on the clamped rates-rebate rule, monotonicity in income among them" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", rebateFixedFixture]
    code `shouldBe` ExitSuccess
    -- the deck's worked number again: 560 where the buggy form pays 630
    verdictOf 60 sout `shouldBe` "decided"
    unwords (rowFor 60 sout) `shouldSatisfy` ("assertion satisfied" `isInfixOf`)
    for_ [75, 79, 85] \n -> verdictOf n sout `shouldBe` "proved"
    sout `shouldSatisfy` ("coverage: 5 #ASSERT: 2 decided by evaluation, not re-proved; 3 obligations: 3 proved, 0 refuted, 0 unknown" `isInfixOf`)

  -- Monotonicity cannot tell the two forms apart, because the bug is in the
  -- size of the rebate and not in its direction: with the FLOOR out of the
  -- income excess it is proved of both, and only the ceiling is refuted.
  it "proves monotonicity of both rates-rebate forms, so only the ceiling finds the bug" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", rebateNoFloorFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 73 sout `shouldBe` "proved"
    verdictOf 76 sout `shouldBe` "proved"
    verdictOf 79 sout `shouldBe` "refuted"
    unwords (rowFor 79 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)
    verdictOf 82 sout `shouldBe` "proved"
    sout `shouldSatisfy` ("coverage: 4 #ASSERT: 0 decided by evaluation, not re-proved; 4 obligations: 3 proved, 1 refuted, 0 unknown" `isInfixOf`)

  it "fails with a named reason when Z3_EXE names a file that does not exist" $ do
    Output code _ serr <- runL4WithEnvExtra [("Z3_EXE", "/nonexistent/z3")] bin ["prove", assumedFixture]
    code `shouldBe` ExitFailure 1
    serr `shouldSatisfy` ("Z3_EXE is set to /nonexistent/z3, which does not exist" `isInfixOf`)

  it "writes portable SMT-LIB2 with every user name prefixed, and needs no solver to do it (R-V6)" $
    withSystemTempDirectory "l4-prove-smt" \dir -> do
      Output code sout _ <- runL4 bin ["prove", numbersFixture, "--emit-smt", dir]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("no solver was run" `isInfixOf`)
      files <- listDirectory dir
      length files `shouldBe` 5
      pi' <- readFile (dir </> "numbers-22-1.smt2")
      -- `pi` is a theory symbol in some solvers; the user's must not be it
      pi' `shouldSatisfy` ("(declare-const |l4_pi| Real)" `isInfixOf`)
      pi' `shouldNotSatisfy` ("(declare-const pi " `isInfixOf`)
      pi' `shouldNotSatisfy` ("|pi|" `isInfixOf`)
      pi' `shouldSatisfy` ("(set-logic ALL)" `isInfixOf`)
      -- no solver-specific options or tactics
      pi' `shouldNotSatisfy` (":timeout" `isInfixOf`)
      pi' `shouldNotSatisfy` ("check-sat-using" `isInfixOf`)
      -- the header names the #ASSERT the script came from, so a second
      -- solver's answer maps back to file:line
      pi' `shouldSatisfy` ("; l4 prove: the negation of the #ASSERT at numbers.l4:22:" `isPrefixOf`)
      twice <- readFile (dir </> "numbers-12-1.smt2")
      twice `shouldSatisfy` ("(define-fun |l4_twice|" `isInfixOf`)

  it "gives two #ASSERTs on one source line two scripts, named by line and column" $
    withSystemTempDirectory "l4-prove-smt" \dir -> do
      Output code _ _ <- runL4 bin ["prove", sameLineFixture, "--emit-smt", dir]
      code `shouldBe` ExitSuccess
      files <- listDirectory dir
      sort files `shouldBe` ["same-line-6-1.smt2", "same-line-6-13.smt2"]
      first <- readFile (dir </> "same-line-6-1.smt2")
      second <- readFile (dir </> "same-line-6-13.smt2")
      first `shouldSatisfy` ("(assert (not (and |l4.defined| |l4.goal|)))" `isInfixOf`)
      first `shouldSatisfy` ("(define-fun |l4.goal| () Bool |l4_b|)" `isInfixOf`)
      second `shouldSatisfy` ("(define-fun |l4.goal| () Bool (not |l4_b|))" `isInfixOf`)

  -- Audit of #784, finding 1: two parameter names a lossy sanitiser mapped to
  -- one symbol gave duplicate binders, and z3's shadowing turned a FALSE
  -- assertion into "proved".
  it "keeps two parameters whose names differ only in `|` and `_` apart" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", collideFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 12 sout `shouldBe` "refuted"
    unwords (rowFor 12 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

  -- Finding 2: every zero-parameter WHERE or LET looped (<<loop>>).
  it "lowers zero-parameter WHERE and LET locals, including one that reads another" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", localsFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 14 sout `shouldBe` "proved"
    verdictOf 17 sout `shouldBe` "proved"
    verdictOf 20 sout `shouldBe` "refuted"

  -- Finding 3: a decided FALSE, or a decided raise, is a failing file.
  it "exits 2 when the evaluator decides an #ASSERT FALSE or it raises" $ do
    Output code sout _ <- runL4 bin ["prove", decidedFailFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 3 sout `shouldBe` "decided"
    verdictOf 4 sout `shouldBe` "decided"

  -- Finding 4: a counterexample prints exactly, so it reproduces under l4 run.
  it "prints a counterexample that is not a whole number exactly" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", exactFixture]
    code `shouldBe` ExitFailure 2
    unwords (rowFor 6 sout) `shouldSatisfy` ("counterexample: x = 4 DIVIDED BY 3" `isInfixOf`)

  -- Finding 6 (the audit's numbering): an unwritable --emit-smt directory is
  -- a one-line refusal, not a raw exception.
  it "refuses an --emit-smt directory it cannot create in one line, exit 1" $ do
    Output code _ serr <- runL4 bin ["prove", numbersFixture, "--emit-smt", "/dev/null/x"]
    code `shouldBe` ExitFailure 1
    serr `shouldSatisfy` ("l4 prove: cannot write the scripts to /dev/null/x" `isInfixOf`)
    serr `shouldNotSatisfy` ("CallStack" `isInfixOf`)
    length (lines serr) `shouldBe` 1

  -- The numbering suffix for a second binder of one spelling (`x#2`) must not
  -- meet a binder whose own name is `x#2`: '#' is escaped inside names.
  it "keeps a shadowed name's numbered symbol apart from a name spelled `x#2`" $
    withSystemTempDirectory "l4-prove-smt" \dir -> do
      Output code _ _ <- runL4 bin ["prove", hashNameFixture, "--emit-smt", dir]
      code `shouldBe` ExitSuccess
      script <- readFile (dir </> "hash-name-15-1.smt2")
      script `shouldSatisfy` ("(declare-const |l4_x| Real)" `isInfixOf`)
      script `shouldSatisfy` ("(declare-const |l4_x#2| Real)" `isInfixOf`)
      script `shouldSatisfy` ("(declare-const |l4_x_h2| Real)" `isInfixOf`)

  it "refutes an assertion over the three, the evaluator agreeing" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", hashNameFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 15 sout `shouldBe` "refuted"
    unwords (rowFor 15 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

  -- STARGAZY audit of #784: a projection out of a constructor needs only its
  -- own field defined, as L4 evaluates only the fields it reads.
  it "proves an assertion that reads one field of a record whose other field would raise" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", lazyFieldFixture]
    code `shouldBe` ExitSuccess
    verdictOf 16 sout `shouldBe` "proved"
