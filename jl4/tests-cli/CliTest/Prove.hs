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

import Data.List (isInfixOf, isPrefixOf, sort)
import System.Directory (listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common

numbersFixture, recordsFixture, outOfFragmentFixture, defectFixture, integersFixture, sameLineFixture, assumedFixture,
  collideFixture, localsFixture, decidedFailFixture, exactFixture :: FilePath
numbersFixture       = fixtureDir </> "prove" </> "numbers.l4"
recordsFixture       = fixtureDir </> "prove" </> "records.l4"
outOfFragmentFixture = fixtureDir </> "prove" </> "out-of-fragment.l4"
defectFixture        = fixtureDir </> "prove" </> "defect.l4"
integersFixture      = fixtureDir </> "prove" </> "integers.l4"
collideFixture       = fixtureDir </> "prove" </> "collide.l4"
localsFixture        = fixtureDir </> "prove" </> "locals.l4"
decidedFailFixture   = fixtureDir </> "prove" </> "decided-fail.l4"
exactFixture         = fixtureDir </> "prove" </> "exact.l4"
sameLineFixture      = fixtureDir </> "prove" </> "same-line.l4"
assumedFixture       = fixtureDir </> "assert-assumed.l4"

fixtures :: [FilePath]
fixtures = [numbersFixture, recordsFixture, outOfFragmentFixture, defectFixture, integersFixture, sameLineFixture, assumedFixture
           , collideFixture, localsFixture, decidedFailFixture, exactFixture]

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
  -- wrong at p = 0 (constructor fields are lowered as strict), and the replay
  -- must say so instead of reporting a counterexample.
  it "reports a model the evaluator rejects as an ENCODING DEFECT, never as refuted, and exits 4" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", defectFixture]
    code `shouldBe` ExitFailure 4
    verdictOf 13 sout `shouldBe` "ENCODING"
    unwords (rowFor 13 sout) `shouldSatisfy` ("fails at p = 0, but the evaluator says it holds there" `isInfixOf`)

  -- Soundness: a guard such as IS INTEGER is a hypothesis of its own
  -- obligation and never changes a NUMBER's sort, or the unguarded assertion
  -- below would be "proved" over the integers.
  it "keeps a NUMBER Real whatever guard an assertion carries" $ withZ3 $ do
    Output code sout _ <- runL4 bin ["prove", integersFixture]
    code `shouldBe` ExitFailure 2
    verdictOf 7 sout `shouldBe` "refuted"
    unwords (rowFor 7 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)
    verdictOf 10 sout `shouldBe` "proved"

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
