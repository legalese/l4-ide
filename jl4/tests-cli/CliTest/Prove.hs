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
--
-- The second solver (smucclaw/l4-ide#1098) is tested twice over. Stub solvers,
-- shell scripts this suite writes, decide what each solver answers, so the
-- order of asking, the timeout, the reading of a cvc5 model and the report
-- are pinned on every POSIX machine whatever is installed ('withStubSolvers').
-- The tests that need the real cvc5 go through 'withCvc5', which reports them
-- PENDING when it is absent, as 'withZ3' does for z3.
module CliTest.Prove (spec, fixtures) where

import Control.Monad (forM_)
import Data.List (isInfixOf, isPrefixOf, sort)
import System.Directory
  ( createDirectory, doesFileExist, findExecutable, getPermissions, listDirectory
  , setOwnerExecutable, setPermissions )
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import qualified System.Info as Info
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common

numbersFixture, recordsFixture, outOfFragmentFixture, defectFixture, integersFixture, sameLineFixture, assumedFixture,
  collideFixture, localsFixture, decidedFailFixture, exactFixture, hashNameFixture, lazyFieldFixture,
  secondHoldsFixture, secondFailsFixture, floorMonotoneFixture, secondMixedFixture, twinModelFixture :: FilePath
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
secondHoldsFixture   = fixtureDir </> "prove" </> "second-holds.l4"
secondFailsFixture   = fixtureDir </> "prove" </> "second-fails.l4"
floorMonotoneFixture = fixtureDir </> "prove" </> "floor-monotone.l4"
secondMixedFixture   = fixtureDir </> "prove" </> "second-mixed.l4"
twinModelFixture     = fixtureDir </> "prove" </> "twin-model.l4"

fixtures :: [FilePath]
fixtures = [numbersFixture, recordsFixture, outOfFragmentFixture, defectFixture, integersFixture, sameLineFixture, assumedFixture
           , collideFixture, localsFixture, decidedFailFixture, exactFixture, hashNameFixture, lazyFieldFixture
           , secondHoldsFixture, secondFailsFixture, floorMonotoneFixture, secondMixedFixture, twinModelFixture]

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

----------------------------------------------------------------------------
-- Stub solvers, and the real cvc5
----------------------------------------------------------------------------

-- | What a stub solver does with a script.
data StubReply
  = Says String Int  -- ^ print this, then exit with this status
  | Hangs            -- ^ never answer, so that the driver's --timeout fires
  | ByPosition [(String, StubReply)] StubReply
    -- ^ the reply paired with the first text the script contains, else the
    -- last; a script's first line names its #ASSERT's position, so
    -- @"f.l4:7:"@ picks the obligation on line 7

-- | Run the body with stub solvers on a @PATH@ of their own.
--
-- Each stub is a POSIX shell script named for the solver it stands in for. It
-- answers @--version@ with @stub-NAME version 0@, adding a line to
-- @DIR/NAME.version@ each time; asked anything else, it keeps the script it
-- was given in @DIR/NAME.in@ (its standard input, or the file its last
-- argument names), adds it to @DIR/NAME.all@, and keeps its arguments in
-- @DIR/NAME.args@, then replies. So @DIR/NAME.in@ exists exactly when that
-- solver was asked about an obligation, and @DIR/NAME.version@ exactly when
-- it was started at all.
--
-- The body gets DIR and the child's environment, in which @PATH@ is the stubs'
-- directory ALONE and @Z3_EXE@ and @CVC5_EXE@ are unset: no solver installed
-- on this machine can answer in a stub's place. A stub runs only @/bin/cat@
-- and @/bin/sleep@, by absolute path, for the same reason.
withStubSolvers :: [(String, StubReply)] -> (FilePath -> [(String, String)] -> IO ()) -> IO ()
withStubSolvers stubs body
  | Info.os == "mingw32" = pendingWith "the stub solvers are POSIX shell scripts"
  | otherwise = withSystemTempDirectory "l4-prove-stubs" \dir -> do
      let stubBin = dir </> "bin"
      createDirectory stubBin
      forM_ stubs \(name, reply) -> writeStub dir (stubBin </> name) name reply
      parent <- getEnvironment
      body dir (("PATH", stubBin) : [ kv | kv@(k, _) <- parent, k `notElem` ["PATH", "Z3_EXE", "CVC5_EXE"] ])

writeStub :: FilePath -> FilePath -> String -> StubReply -> IO ()
writeStub dir path name reply = do
  let record ext = "'" <> (dir </> name) <> ext <> "'"
  writeFile path $ unlines $
    [ "#!/bin/sh"
    , "if [ \"$1\" = \"--version\" ]; then echo started >> " <> record ".version"
        <> "; echo 'stub-" <> name <> " version 0'; exit 0; fi"
    , "printf '%s\\n' \"$*\" > " <> record ".args"
    , "last=; for a in \"$@\"; do last=$a; done"
    , "if [ -n \"$last\" ] && [ -f \"$last\" ]; then /bin/cat \"$last\" > " <> record ".in"
        <> "; else /bin/cat > " <> record ".in" <> "; fi"
    , "/bin/cat " <> record ".in" <> " >> " <> record ".all"
    , "script=$(/bin/cat " <> record ".in" <> ")"
    ]
    <> replyLines reply
  p <- getPermissions path
  setPermissions path (setOwnerExecutable True p)
 where
  replyLines = \case
    Says out code -> ["/bin/cat <<'L4_STUB_END'", out, "L4_STUB_END", "exit " <> show code]
    Hangs -> ["exec /bin/sleep 60"]
    ByPosition cases fallback ->
      ["case \"$script\" in"]
      <> concat [ ("  *'" <> pat <> "'*)") : replyLines r <> ["  ;;"] | (pat, r) <- cases ]
      <> ["  *)"] <> replyLines fallback <> ["  ;;", "esac"]

-- | Was this stub asked about an obligation?
wasAsked :: FilePath -> String -> IO Bool
wasAsked dir name = doesFileExist (dir </> name <> ".in")

-- | How many times this stub was started to give its version.
timesStarted :: FilePath -> String -> IO Int
timesStarted dir name = countLines (dir </> name <> ".version") (const True)

-- | How many obligations this stub was asked about.
timesAsked :: FilePath -> String -> IO Int
timesAsked dir name = countLines (dir </> name <> ".all") ("(check-sat)" `isPrefixOf`)

countLines :: FilePath -> (String -> Bool) -> IO Int
countLines path p = do
  there <- doesFileExist path
  if there then length . filter p . lines <$> readUtf8 path else pure 0

-- | Run the body only when a real cvc5 can be found, as @l4 prove@ finds one
-- (@CVC5_EXE@, then @cvc5@ on @PATH@). Without one it is reported PENDING,
-- never passed; with @CVC5_CHECK_REQUIRED=1@ a missing cvc5 fails the test.
withCvc5 :: IO () -> IO ()
withCvc5 act = do
  configured <- lookupEnv "CVC5_EXE"
  found <- case configured of
    Just p | not (null p) -> doesFileExist p
    _ -> maybe False (const True) <$> findExecutable "cvc5"
  required <- lookupEnv "CVC5_CHECK_REQUIRED"
  if found
    then act
    else if required == Just "1"
      then expectationFailure "CVC5_CHECK_REQUIRED=1, but no cvc5 was found (set CVC5_EXE or put cvc5 on PATH)"
      else pendingWith "skipped: cvc5 not found (set CVC5_EXE or put cvc5 on PATH); no cvc5 verdict was measured"

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

  -- Soundness: a guard such as ISINTEGER is a hypothesis of its own
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

  secondSolverSpec bin

-- | smucclaw/l4-ide#1098: where z3 gives no answer, cvc5 is asked the same
-- question. second-holds.l4 and second-fails.l4 have their one #ASSERT on
-- line 6; second-mixed.l4 has three, on lines 6, 7 and 8.
secondSolverSpec :: FilePath -> Spec
secondSolverSpec bin = describe "a second solver (smucclaw/l4-ide#1098)" $ do
  -- The replies are what cvc5 1.4.2 printed for the emitted scripts of this
  -- suite's fixtures (measured 2026-11-25), with the values changed to suit
  -- each test: symbols that need no bars printed without them, a negative
  -- fraction as `(/ (- 3) 4)`, and after `unsat` an error for the script's
  -- closing get-value, on standard output, with exit status 0.
  let run env args = runL4WithEnv (Just env) bin ("prove" : args)
      unknownReply = Says "unknown\n((l4_x 0.0) (l4.defined true) (l4.goal true))" 0
      unsatReply = Says "unsat\n(error \"cannot get value unless after a SAT or UNKNOWN response.\")" 0
      -- a counterexample to second-fails.l4
      cvc5Refutes = Says "sat\n((l4_x (/ (- 1) 3)) (l4.defined true) (l4.goal false))" 0
      -- a "counterexample" at which second-fails.l4 holds: a wrong model
      cvc5Wrong = Says "sat\n((l4_x 1.0) (l4.defined true) (l4.goal true))" 0

  it "asks cvc5 the same script when z3 says unknown, and reports cvc5's proof as proved, naming it" $
    withStubSolvers [("z3", unknownReply), ("cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      unwords (rowFor 6 sout) `shouldSatisfy` ("proved by cvc5 after z3 gave no answer: the solver said unknown" `isInfixOf`)
      sout `shouldSatisfy` ("second solver: stub-cvc5 version 0, asked where z3 gave no answer: 1 obligation" `isInfixOf`)
      -- the same bytes, and the same as --emit-smt writes (R-V6)
      z3In <- readUtf8 (dir </> "z3.in")
      cvc5In <- readUtf8 (dir </> "cvc5.in")
      cvc5In `shouldBe` z3In
      withSystemTempDirectory "l4-prove-smt" \out -> do
        Output emitCode _ _ <- run env [secondHoldsFixture, "--emit-smt", out]
        emitCode `shouldBe` ExitSuccess
        emitted <- readUtf8 (out </> "second-holds-6-1.smt2")
        cvc5In `shouldBe` emitted
      -- cvc5 reads the script on standard input, told its language (z3's
      -- `-smt2 -in` would be refused), and told to print each model value
      -- in full: otherwise it abbreviates a repeated part with `let`, which
      -- the model reader does not read (see "with the real cvc5" below)
      readUtf8 (dir </> "cvc5.args") `shouldReturn` "--lang=smt2 --dag-thresh=0\n"

  it "reads cvc5's unsat even when what follows it cannot be read" $
    withStubSolvers [("z3", unknownReply), ("cvc5", Says "unsat\n(error \"this line is cut off" 1)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"

  it "asks cvc5 when z3 runs out of time, giving cvc5 the full --timeout" $
    withStubSolvers [("z3", Hangs), ("cvc5", unsatReply)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--timeout", "1"]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      unwords (rowFor 6 sout) `shouldSatisfy` ("proved by cvc5 after z3 gave no answer: timeout after 1s" `isInfixOf`)

  -- R-V5 holds whichever solver answered: a counterexample is reported only
  -- once the evaluator, run at cvc5's values, agrees.
  it "reads a counterexample in cvc5's model format and replays it through the evaluator" $
    withStubSolvers [("z3", unknownReply), ("cvc5", cvc5Refutes)] \_ env -> do
      Output code sout _ <- run env [secondFailsFixture]
      code `shouldBe` ExitFailure 2
      verdictOf 6 sout `shouldBe` "refuted"
      unwords (rowFor 6 sout) `shouldSatisfy` ("counterexample: x = -1 DIVIDED BY 3" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldSatisfy` ("refuted by cvc5 after z3 gave no answer" `isInfixOf`)

  it "reports a cvc5 model the evaluator rejects as an ENCODING DEFECT, naming cvc5, and exits 4" $
    withStubSolvers [("z3", unknownReply), ("cvc5", cvc5Wrong)] \_ env -> do
      Output code sout _ <- run env [secondFailsFixture]
      code `shouldBe` ExitFailure 4
      verdictOf 6 sout `shouldBe` "ENCODING"
      unwords (rowFor 6 sout) `shouldSatisfy` ("but the evaluator says it holds there" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldSatisfy` ("answered by cvc5 after z3 gave no answer" `isInfixOf`)

  -- ... and a proof only once the evaluator says TRUE at every sample point.
  -- second-fails.l4 is FALSE below zero, so a cvc5 that says unsat is wrong.
  it "checks cvc5's proof at the sample points, as z3's, and reports a wrong one as an ENCODING DEFECT" $
    withStubSolvers [("z3", unknownReply), ("cvc5", unsatReply)] \_ env -> do
      Output code sout _ <- run env [secondFailsFixture]
      code `shouldBe` ExitFailure 4
      verdictOf 6 sout `shouldBe` "ENCODING"
      unwords (rowFor 6 sout) `shouldSatisfy` ("the solver proved it, but at" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldSatisfy` ("answered by cvc5 after z3 gave no answer" `isInfixOf`)

  -- An answer that still leaves the verdict unknown is not "answered": the
  -- row says what cvc5 said, and the line above it why that is not a verdict.
  it "says what cvc5 answered when its answer still leaves the assertion unknown" $
    withStubSolvers
      [ ("z3", unknownReply)
      , ("cvc5", Says "sat\n((l4_x (root-obj (+ (^ x 2) (- 2)) 1)) (l4.defined true) (l4.goal false))" 0) ] \_ env -> do
      Output code sout _ <- run env [secondFailsFixture]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      unwords (rowFor 6 sout) `shouldSatisfy` ("model value not a rational" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldSatisfy` ("cvc5 said sat after z3 gave no answer: the solver said unknown" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldNotSatisfy` ("answered by" `isInfixOf`)

  it "names both solvers' reasons when neither answers, and exits 3" $
    withStubSolvers [("z3", unknownReply), ("cvc5", Hangs)] \dir env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--timeout", "1"]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      -- z3's reason first, worded as it was before there was a second solver
      take 1 (drop 1 (rowFor 6 sout)) `shouldBe` ["      the solver said unknown"]
      unwords (rowFor 6 sout) `shouldSatisfy` ("cvc5, asked next, gave no answer either: timeout after 1s" `isInfixOf`)
      wasAsked dir "cvc5" `shouldReturn` True

  -- Installing cvc5 must not turn an unknown into a failure of cvc5's own:
  -- only a disagreement with the evaluator (above) is a defect.
  it "counts output from cvc5 that it cannot read as no answer, not as an ENCODING DEFECT" $
    -- the shape of cvc5's reply to a script it cannot parse (measured)
    withStubSolvers [("z3", unknownReply), ("cvc5", Says "(error \"Parse Error: <stdin>:2.12: Symbol 'q' not declared as a variable\")" 1)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      unwords (rowFor 6 sout) `shouldSatisfy` ("cvc5, asked next, gave no answer either: could not read its output" `isInfixOf`)

  it "without cvc5, reports z3's unknown exactly as before, and says once that it was not retried" $
    withStubSolvers [("z3", unknownReply)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      drop 1 (rowFor 6 sout) `shouldBe` ["      the solver said unknown"]
      sout `shouldSatisfy` ("second solver: none found (set CVC5_EXE or put cvc5 on PATH), so 1 obligation z3 gave no answer to was not retried" `isInfixOf`)

  -- A file with several obligations: z3 answers the one on line 7, and
  -- gives no answer to those on lines 6 and 8.
  it "asks cvc5 only about the obligations z3 gave no answer to, and starts it once" $
    withStubSolvers
      [ ("z3", ByPosition [("second-mixed.l4:7:", unsatReply)] unknownReply)
      , ("cvc5", unsatReply) ] \dir env -> do
      Output code sout _ <- run env [secondMixedFixture]
      code `shouldBe` ExitSuccess
      map (`verdictOf` sout) [6, 7, 8] `shouldBe` ["proved", "proved", "proved"]
      unwords (rowFor 6 sout) `shouldSatisfy` ("proved by cvc5 after z3 gave no answer: the solver said unknown" `isInfixOf`)
      rowFor 7 sout `shouldSatisfy` ((== 1) . length)
      unwords (rowFor 8 sout) `shouldSatisfy` ("proved by cvc5 after z3 gave no answer: the solver said unknown" `isInfixOf`)
      sout `shouldSatisfy` ("second solver: stub-cvc5 version 0, asked where z3 gave no answer: 2 obligations" `isInfixOf`)
      timesAsked dir "z3" `shouldReturn` 3
      timesAsked dir "cvc5" `shouldReturn` 2
      timesStarted dir "cvc5" `shouldReturn` 1

  it "without cvc5, counts in one line every obligation z3 gave no answer to" $
    withStubSolvers [("z3", ByPosition [("second-mixed.l4:7:", unsatReply)] unknownReply)] \_ env -> do
      Output code sout _ <- run env [secondMixedFixture]
      code `shouldBe` ExitFailure 3
      map (`verdictOf` sout) [6, 7, 8] `shouldBe` ["unknown", "proved", "unknown"]
      drop 1 (rowFor 6 sout) `shouldBe` ["      the solver said unknown"]
      sout `shouldSatisfy` ("second solver: none found (set CVC5_EXE or put cvc5 on PATH), so 2 obligations z3 gave no answer to were not retried" `isInfixOf`)
      length (filter ("second solver" `isPrefixOf`) (lines sout)) `shouldBe` 1

  it "never starts cvc5 when z3 answers every obligation" $
    withStubSolvers [("z3", unsatReply), ("cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run env [secondMixedFixture]
      code `shouldBe` ExitSuccess
      sout `shouldNotSatisfy` ("second solver" `isInfixOf`)
      timesStarted dir "cvc5" `shouldReturn` 0
      -- the record works: z3 was started, and asked about all three
      timesStarted dir "z3" `shouldReturn` 1
      timesAsked dir "z3" `shouldReturn` 3

  -- z3 is read as strictly as before there was a second solver: output it
  -- cannot read is an ENCODING DEFECT, and cvc5 is not asked. Only a z3 that
  -- cannot be started, runs out of time or says unknown has given no answer.
  it "reports a z3 that exits with no output as an ENCODING DEFECT, as before, and does not ask cvc5" $
    withStubSolvers [("z3", Says "" 134), ("cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitFailure 4
      verdictOf 6 sout `shouldBe` "ENCODING"
      unwords (rowFor 6 sout) `shouldSatisfy` ("the solver printed nothing" `isInfixOf`)
      wasAsked dir "cvc5" `shouldReturn` False

  it "reads z3 strictly as the first solver: unsat followed by output it cannot read is an ENCODING DEFECT" $
    withStubSolvers [("z3", Says "unsat\n(error \"this line is cut off" 0), ("cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitFailure 4
      verdictOf 6 sout `shouldBe` "ENCODING"
      unwords (rowFor 6 sout) `shouldSatisfy` ("could not read the solver's output" `isInfixOf`)
      wasAsked dir "cvc5" `shouldReturn` False

  -- Controls: where z3 answers, nothing about the run changes.
  it "without cvc5, says nothing about a second solver when z3 answers every obligation" $
    withStubSolvers [("z3", unsatReply)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      sout `shouldNotSatisfy` ("second solver" `isInfixOf`)
      sout `shouldNotSatisfy` ("cvc5" `isInfixOf`)

  it "does not ask cvc5 when z3 proves the assertion" $
    withStubSolvers [("z3", unsatReply), ("cvc5", cvc5Refutes)] \dir env -> do
      Output code sout _ <- run env [secondHoldsFixture]
      code `shouldBe` ExitSuccess
      rowFor 6 sout `shouldSatisfy` ((== 1) . length)
      sout `shouldNotSatisfy` ("second solver" `isInfixOf`)
      wasAsked dir "cvc5" `shouldReturn` False

  it "does not ask cvc5 when z3 refutes the assertion" $
    withStubSolvers
      [ ("z3", Says "sat\n((|l4_x| (- 1.0))\n (|l4.defined| true)\n (|l4.goal| false))" 0)
      , ("cvc5", unsatReply) ] \dir env -> do
      Output code sout _ <- run env [secondFailsFixture]
      code `shouldBe` ExitFailure 2
      verdictOf 6 sout `shouldBe` "refuted"
      unwords (rowFor 6 sout) `shouldSatisfy` ("counterexample: x = -1" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldNotSatisfy` ("cvc5" `isInfixOf`)
      wasAsked dir "cvc5" `shouldReturn` False

  -- Discovery mirrors z3's (R-V6): CVC5_EXE first, and a configured path that
  -- does not exist is a hard failure; then cvc5 on PATH.
  it "fails with a named reason when CVC5_EXE names a file that does not exist" $
    withStubSolvers [("z3", unsatReply)] \_ env -> do
      Output code _ serr <- run (("CVC5_EXE", "/nonexistent/cvc5") : env) [secondHoldsFixture]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("CVC5_EXE is set to /nonexistent/cvc5, which does not exist" `isInfixOf`)

  it "finds cvc5 through CVC5_EXE" $
    -- named so that a PATH lookup for `cvc5` cannot find it
    withStubSolvers [("z3", unknownReply), ("my-cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run (("CVC5_EXE", dir </> "bin" </> "my-cvc5") : env) [secondHoldsFixture]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      sout `shouldSatisfy` ("second solver: stub-my-cvc5 version 0" `isInfixOf`)

  it "prefers CVC5_EXE to a cvc5 on PATH" $
    withStubSolvers [("z3", unknownReply), ("cvc5", unknownReply), ("my-cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run (("CVC5_EXE", dir </> "bin" </> "my-cvc5") : env) [secondHoldsFixture]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      sout `shouldSatisfy` ("second solver: stub-my-cvc5 version 0" `isInfixOf`)
      timesStarted dir "cvc5" `shouldReturn` 0
      wasAsked dir "cvc5" `shouldReturn` False

  -- A cvc5 that is there but cannot be run is no second solver, not a
  -- failure of the run: cvc5 is optional unless --solver names it.
  it "treats a cvc5 that cannot be run as absent, naming why, when no --solver names it" $
    withStubSolvers [("z3", unknownReply)] \dir env -> do
      let notRunnable = dir </> "not-runnable-cvc5"
      writeFile notRunnable "this file is not a program\n"
      Output code sout _ <- run (("CVC5_EXE", notRunnable) : env) [secondHoldsFixture]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      drop 1 (rowFor 6 sout) `shouldBe` ["      the solver said unknown"]
      sout `shouldSatisfy` ("second solver: none (could not run " `isInfixOf`)
      sout `shouldSatisfy` ("so 1 obligation z3 gave no answer to was not retried" `isInfixOf`)

  -- --solver chooses the solvers and their order.
  it "--solver z3 asks z3 alone, as before there was a second solver" $
    withStubSolvers [("z3", unknownReply), ("cvc5", unsatReply)] \dir env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--solver", "z3"]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      drop 1 (rowFor 6 sout) `shouldBe` ["      the solver said unknown"]
      sout `shouldNotSatisfy` ("second solver" `isInfixOf`)
      wasAsked dir "cvc5" `shouldReturn` False

  it "--solver cvc5 asks cvc5 alone, and needs no z3" $
    withStubSolvers [("cvc5", unsatReply)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--solver", "cvc5"]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      rowFor 6 sout `shouldSatisfy` ((== 1) . length)
      sout `shouldSatisfy` ("solver: stub-cvc5 version 0" `isInfixOf`)

  it "--solver cvc5 --solver z3 asks cvc5 first, and z3 where cvc5 gives no answer" $
    withStubSolvers [("z3", unsatReply), ("cvc5", unknownReply)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--solver", "cvc5", "--solver", "z3"]
      code `shouldBe` ExitSuccess
      verdictOf 6 sout `shouldBe` "proved"
      unwords (rowFor 6 sout) `shouldSatisfy` ("proved by z3 after cvc5 gave no answer: the solver said unknown" `isInfixOf`)
      sout `shouldSatisfy` ("second solver: stub-z3 version 0, asked where cvc5 gave no answer: 1 obligation" `isInfixOf`)

  -- How strictly a reply is read goes by the order the solvers are asked
  -- in, not by which solver it is: the first one's output that cannot be
  -- read is an encoding defect, as z3's always was; a later one's is no
  -- answer.
  it "reads the first solver asked strictly, whichever it is: --solver cvc5 output it cannot read is an ENCODING DEFECT" $
    withStubSolvers [("cvc5", Says "(error \"Parse Error: <stdin>:2.12: Symbol 'q' not declared as a variable\")" 1)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--solver", "cvc5"]
      code `shouldBe` ExitFailure 4
      verdictOf 6 sout `shouldBe` "ENCODING"
      unwords (rowFor 6 sout) `shouldSatisfy` ("unexpected solver output: (error" `isInfixOf`)

  it "--solver cvc5 --solver z3 counts z3 output it cannot read as no answer, z3 being asked second" $
    withStubSolvers [("cvc5", unknownReply), ("z3", Says "(oops" 0)] \_ env -> do
      Output code sout _ <- run env [secondHoldsFixture, "--solver", "cvc5", "--solver", "z3"]
      code `shouldBe` ExitFailure 3
      verdictOf 6 sout `shouldBe` "unknown"
      unwords (rowFor 6 sout) `shouldSatisfy` ("z3, asked next, gave no answer either: could not read its output" `isInfixOf`)

  it "--solver cvc5 with no cvc5 to be found is a named failure, exit 1" $
    withStubSolvers [("z3", unsatReply)] \_ env -> do
      Output code _ serr <- run env [secondHoldsFixture, "--solver", "cvc5"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--solver cvc5 was asked for, but no cvc5 was found: set CVC5_EXE or put cvc5 on PATH" `isInfixOf`)

  it "--solver refuses a solver it does not know, naming the two it does" $
    withStubSolvers [("z3", unsatReply)] \_ env -> do
      Output code _ serr <- run env [secondHoldsFixture, "--solver", "yices"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("the solvers are z3 and cvc5" `isInfixOf`)

  it "--solver refuses a solver named twice" $
    withStubSolvers [("z3", unsatReply)] \_ env -> do
      Output code _ serr <- run env [secondHoldsFixture, "--solver", "z3", "--solver", "z3"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--solver z3 is given twice" `isInfixOf`)

  -- With the real solvers. Each is PENDING where cvc5 is not installed, which
  -- includes CI today (pr-checks.yml installs z3 only).
  describe "with the real cvc5" $ do
    it "proves the issue's FLOOR-of-a-product monotonicity claim with cvc5 alone" $ withCvc5 $ do
      Output code sout _ <- runL4 bin ["prove", floorMonotoneFixture, "--solver", "cvc5", "--timeout", "30"]
      code `shouldBe` ExitSuccess
      verdictOf 16 sout `shouldBe` "proved"
      sout `shouldSatisfy` ("solver: " `isInfixOf`)

    it "proves it by default, cvc5 answering where z3 gives no answer" $ withZ3 $ withCvc5 $ do
      Output code sout _ <- runL4 bin ["prove", floorMonotoneFixture, "--timeout", "5"]
      code `shouldBe` ExitSuccess
      verdictOf 16 sout `shouldBe` "proved"
      if "proved by cvc5 after z3 gave no answer" `isInfixOf` unwords (rowFor 16 sout)
        then pure ()
        else pendingWith "z3 proved it on its own within 5 s, so the second solver was not exercised"

    it "reads cvc5's own model for a counterexample that is not a whole number" $ withCvc5 $ do
      Output code sout _ <- runL4 bin ["prove", exactFixture, "--solver", "cvc5"]
      code `shouldBe` ExitFailure 2
      unwords (rowFor 6 sout) `shouldSatisfy` ("counterexample: x = 4 DIVIDED BY 3" `isInfixOf`)
      unwords (rowFor 6 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

    -- cvc5 abbreviates a part repeated in a model value with `let` unless it
    -- is told not to, and the model reader reads only constructors, numbers
    -- and truth values: this counterexample's two fields hold equal records.
    it "reads cvc5's own model for a record whose two fields hold equal values" $ withCvc5 $ do
      Output code sout _ <- runL4 bin ["prove", twinModelFixture, "--solver", "cvc5"]
      code `shouldBe` ExitFailure 2
      verdictOf 16 sout `shouldBe` "refuted"
      unwords (rowFor 16 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

    it "reads cvc5's own model for a negative counterexample" $ withCvc5 $ do
      Output code sout _ <- runL4 bin ["prove", secondFailsFixture, "--solver", "cvc5"]
      code `shouldBe` ExitFailure 2
      verdictOf 6 sout `shouldBe` "refuted"
      unwords (rowFor 6 sout) `shouldSatisfy` ("the evaluator agrees" `isInfixOf`)

    -- The emitted scripts are portable (R-V6): cvc5 reaches z3's verdicts.
    it "reaches z3's verdicts on the NUMBER and record fixtures" $ withCvc5 $ do
      Output _ numbers _ <- runL4 bin ["prove", numbersFixture, "--solver", "cvc5"]
      map (`verdictOf` numbers) [12, 15, 18, 22, 25, 28]
        `shouldBe` ["proved", "proved", "proved", "refuted", "refuted", "decided"]
      Output _ records _ <- runL4 bin ["prove", recordsFixture, "--solver", "cvc5"]
      map (`verdictOf` records) [19, 22] `shouldBe` ["proved", "refuted"]
