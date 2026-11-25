-- | Black-box tests for @l4 explore@ (REGULATIVE-LOWERING-SPEC.md §4, WP1;
-- §5, WP2): the exit status a CI job reads, and the coverage line it ends
-- with. The graphs and the checks' verdicts are pinned in
-- @jl4/tests/LtsExplore.hs@; what only the binary can show is that an
-- incomplete exploration, a violated property and an unanswered one do not
-- exit 0 (§4.2: "a CI job cannot read a refused run as green"), and that a
-- printed counterexample, pasted into the file, is reproduced by @l4 run@
-- (§5.4); and that @--emit@ (§6.1, WP3) writes its files without changing
-- the status, gives fairness only to the actor @--fair@ names, makes the
-- relation total where a bound left a state with no edge, and refuses a
-- @--fair@ that names nothing.
module CliTest.Explore (spec, fixtures) where

import Control.Monad (forM_)
import Data.Char (isDigit)
import Data.List (isInfixOf, isPrefixOf, isSuffixOf, sort, tails)
import System.Directory (copyFile, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common

brief :: FilePath
brief = "examples" </> "explore" </> "brief"

-- | The fixtures of smucclaw/l4-ide#1081, the instants an act is tried at.
instants :: FilePath
instants = "tests-cli" </> "fixtures" </> "explore-instants"

-- | The fixtures of smucclaw/l4-ide#1087, a breached position that still has a
-- part waiting.
breached :: FilePath
breached = "tests-cli" </> "fixtures" </> "explore-breached"

startFixtures :: FilePath
startFixtures = "tests-cli" </> "fixtures" </> "explore-start"

-- | The fixtures of smucclaw/l4-ide#1106, a rule under a § heading.
sections :: FilePath
sections = "tests-cli" </> "fixtures" </> "lts-sections"

-- | The fixtures of smucclaw/l4-ide#1107, a deadline written as a name or an
-- expression.
deadlines :: FilePath
deadlines = "tests-cli" </> "fixtures" </> "explore-deadlines"

-- | Review of smucclaw/l4-ide#1107: the kept answer of a constant that reads
-- a ledger, called four ways.
keptAnswers :: FilePath
keptAnswers = "tests-cli" </> "fixtures" </> "explore-kept-answers"

-- | Review of smucclaw/l4-ide#1107: rules that read the run, in an imported
-- file.
imported :: FilePath
imported = "tests-cli" </> "fixtures" </> "explore-imported"

-- | Review of smucclaw/l4-ide#1107: properties that read a ledger through a
-- rule, called three ways.
propertyReaders :: FilePath
propertyReaders = "tests-cli" </> "fixtures" </> "explore-property-readers"

-- | Review of smucclaw/l4-ide#1107: acts the what-if cannot replay.
actions :: FilePath
actions = "tests-cli" </> "fixtures" </> "explore-actions"

fixtures :: [FilePath]
fixtures =
  [ brief </> f | f <- ["d1-naive.l4", "d2-reread.l4", "d3-atomic.l4", "refused-number.l4", "properties.l4"] ]
  <> [ instants </> f | f <- ["clocks.l4", "window.l4", "half.l4", "adjacent.l4", "open.l4", "flip3.l4", "room.l4", "lapse.l4", "merged.l4", "lapse-fixed.l4", "cap-re.l4", "own-lapse.l4", "frac-re.l4", "fx-fork.l4", "fx-barrier.l4", "succ2.l4", "hidden.l4", "succ4.l4", "cap-shift.l4", "frac-start.l4", "frac-wait.l4", "frac-stamp.l4"] ]
  <> [ breached </> f | f <- ["sale.l4", "resell.l4", "continuation.l4"] ]
  <> [ sections </> f | f <- ["sectioned.l4", "two-sections.l4"] ]
  <> [ deadlines </> f | f <- ["shapes.l4", "given.l4", "carried.l4", "armed.l4", "ledger.l4", "called.l4", "section-given.l4", "section-reader.l4", "clock.l4", "locals.l4", "slow.l4", "dated.l4"] ]
  <> [ keptAnswers </> f | f <- ["positional.l4", "named.l4", "genitive.l4", "wrapper.l4"] ]
  <> [ imported </> f | f <- ["readers.l4", "deadlines.l4", "kept.l4", "property.l4"] ]
  <> [ propertyReaders </> f | f <- ["positional.l4", "with.l4", "genitive.l4"] ]
  <> [ actions </> f | f <- ["section-given.l4", "section-party.l4", "local-function.l4"] ]

-- | The acceptance run of the fixtures' README: the clock bounded at
-- closing, the cells the properties read kept.
acceptance :: [String]
acceptance =
  [ "--until", "75600"
  , "--keep", "open at acceptance", "--keep", "dinners bought", "--keep", "dinners cancelled"
  , "--keep", "dinner status record", "--keep-latest", "belief", "--keep-latest", "plan"
  ]

-- | The brief's safety and reachability properties, P1 to P4. P2 and P4 read
-- `dinners cancelled`, which none of the brief's designs writes (one set of
-- properties serves several designs), so a run that names them says so.
safety :: [String]
safety =
  [ "--until", "75600"
  , "--unwritten", "dinners cancelled"
  , "--always", "every dinner was accepted while open"
  , "--always", "at most one dinner is bought"
  , "--reachable", "Alice's belief is stale"
  , "--stays", "one dinner is bought"
  ]

-- | A one-party contract with no #TRACE whose only COMMIT is on the tick of
-- its deadline, so that cell is written on a path that merges into a state
-- already seen.
lateContract :: [String]
lateContract =
  [ "DECLARE Who IS ONE OF W"
  , "DECLARE Move IS ONE OF go"
  , ""
  , "GIVETH A DEONTIC Who Move"
  , "`late` MEANS"
  , "    PARTY W"
  , "    MUST  go"
  , "    WITHIN 10"
  , "    HENCE FULFILLED"
  , "    LEST  COMMIT `missed` IS TRUE HENCE FULFILLED"
  ]

-- | The printed #TRACE that follows the comment line naming the property:
-- the comment, the #TRACE line and its indented events.
traceAfter :: String -> String -> [String]
traceAfter property out =
  case dropWhile (not . (("-- `" <> property <> "`") `isPrefixOf`)) (lines out) of
    comment : rest -> comment : takeWhile (\ l -> "#TRACE" `isPrefixOf` l || "    " `isPrefixOf` l) rest
    [] -> []

-- | The residual `l4 run` reaches by these events from the outset of this
-- fixture's contract, as one line.
reachedBy :: FilePath -> FilePath -> String -> [String] -> IO String
reachedBy bin fixture name events = withSystemTempDirectory "l4-explore-reach" \ dir -> do
  original <- readFile fixture
  let own = takeWhile (not . ("#TRACE" `isPrefixOf`)) (lines original)
  writeFile (dir </> "t.l4") (unlines (own <> ["#TRACE " <> name <> " AT 0 WITH"] <> map ("  " <>) events))
  Output rcode rout _ <- runL4 bin ["run", dir </> "t.l4"]
  rcode `shouldBe` ExitSuccess
  pure (unwords (words (filter (/= '\r') (unlines (takeWhile (not . null) (drop 1 (dropWhile (/= "Result:") (lines rout))))))))

-- | The states of @explore@'s text, each as its id, its residual's id, whether
-- it is marked terminal, and the events by which it is first reached. A state
-- reads @sN  depth D, residual rK[, terminal]@, then @first reached by:@ and the
-- events, then @ledgers:@.
statesOf :: String -> [(String, String, Bool, [String])]
statesOf out = go (lines out)
  where
    go (l : rest)
      | "s" `isPrefixOf` l, "  depth " `isInfixOf` l =
          let ws = words (map (\ c -> if c == ',' then ' ' else c) l)
              sid = case ws of { (w : _) -> w; [] -> "" }
              rid = case dropWhile (/= "residual") ws of { (_ : r : _) -> r; _ -> "" }
              events = map (drop 6) (takeWhile (not . ("    ledgers:" `isPrefixOf`)) (drop 1 rest))
          in (sid, rid, "terminal" `elem` ws, events) : go rest
      | otherwise = go rest
    go [] = []

-- | The residuals of @explore@'s text by id, each on one line: a residual that
-- is printed over several lines continues on lines indented past its id.
residualTexts :: String -> [(String, String)]
residualTexts out = collect (takeWhile (not . null) (drop 1 (dropWhile (not . ("Residuals (" `isPrefixOf`)) (lines out))))
  where
    collect [] = []
    collect (l : rest) =
      let (more, rest') = span (isPrefixOf "      ") rest
      in case words l of
           (rid : ws) -> (rid, unwords (ws <> concatMap words more)) : collect rest'
           [] -> collect rest'

-- | The transitions of @explore@'s text: from, to, label.
edgesOf :: String -> [(String, String, String)]
edgesOf out =
  [ (a, b, unwords label)
  | l <- takeWhile (not . null) (drop 1 (dropWhile (not . ("Transitions (" `isPrefixOf`)) (lines out)))
  , (a : "->" : b : label) <- [words l] ]

lastLine :: String -> String
lastLine = \ s -> case lines s of
  [] -> ""
  ls -> last ls

replaceAll :: String -> String -> String -> String
replaceAll from to = go
  where
    go [] = []
    go s@(c : cs)
      | from `isPrefixOf` s = to <> go (drop (length from) s)
      | otherwise = c : go cs

-- | A number with a fractional part, anywhere in the text.
hasFraction :: String -> Bool
hasFraction s = or [ isDig a && b == '.' && isDig c | (a, b, c) <- zip3 s (drop 1 s) (drop 2 s) ]
  where isDig ch = ch >= '0' && ch <= '9'

-- | The events by which the graph first reaches the state whose residual
-- holds all of these phrases, as the @#TRACE@ lines that replay them, and
-- the residual itself on one line. @explore@'s text shows each state as
-- @sN  depth D, residual rK@ then @first reached by:@ and the events, and
-- each residual as @rK  text@.
statePath :: [String] -> String -> Maybe ([String], String)
statePath phrases out = do
  (k, residual) <- case [ (takeWhile (/= ' ') (drop 3 l), unwords (words (drop 2 (dropWhile (/= ' ') (drop 2 l)))))
                        | l <- residualBlock, all (`isInfixOf` l) phrases ] of
    (hit : _) -> Just hit
    []        -> Nothing
  header <- case [ i | (i, l) <- zip [0 :: Int ..] ls, "  depth " `isInfixOf` l, residualId l == Just ("r" <> k) ] of
    (i : _) -> Just i
    []      -> Nothing
  let events = takeWhile (not . ("    ledgers:" `isPrefixOf`)) (drop (header + 2) ls)
  pure (map (drop 6) events, residual)
  where
    ls = lines out
    -- "s7  depth 2, residual r7, terminal" names residual r7
    residualId l = case dropWhile (/= "residual") (words (map (\ c -> if c == ',' then ' ' else c) l)) of
      (_ : r : _) -> Just r
      _           -> Nothing
    residualBlock = takeWhile (not . null) (drop 1 (dropWhile (not . ("Residuals (" `isPrefixOf`)) ls))

spec :: FilePath -> Spec
spec bin = describe "l4 explore" $ do
  -- a time stamp that is not a whole number is used as written; the note says
  -- what `l4 explore` will not do with it
  describe "a time stamp in a #TRACE that is not a whole number" $ do
    it "breach-clocks.l4: `l4 run` and `l4 check` print a note, once for each such stamp, and the exit status is the same" $
      forM_ ["run", "check"] \ verb -> do
        Output code _ serr <- runL4 bin [verb, "examples" </> "ok" </> "breach-clocks.l4"]
        code `shouldBe` ExitSuccess
        length (filter ("lint/fractional-trace-stamp" `isInfixOf`) (lines serr)) `shouldBe` 2
        serr `shouldSatisfy` ("`l4 explore` does not read it" `isInfixOf`)
        serr `shouldSatisfy` ("`--grid 0.2`, a step that divides this stamp, also tries the multiples of 0.2." `isInfixOf`)
        serr `shouldSatisfy` (not . ("tries whole instants only" `isInfixOf`))
        serr `shouldSatisfy` ("DiagnosticSeverity_Information" `isInfixOf`)

    it "frac-start.l4: a start that is not a whole number gets no note, because `l4 explore` reads it as its clock and names what that leaves untried" $ do
      forM_ ["run", "check"] \ verb -> do
        Output code _ serr <- runL4 bin [verb, instants </> "frac-start.l4"]
        code `shouldBe` ExitSuccess
        serr `shouldSatisfy` (not . ("fractional-trace-stamp" `isInfixOf`))
      Output code' sout _ <- runL4 bin ["explore", instants </> "frac-start.l4"]
      sout `shouldSatisfy` ("explored from its outset at 0.5" `isInfixOf`)
      sout `shouldSatisfy` ("PARTY P DOES a AT 0.5" `isInfixOf`)
      code' `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("an instant it needs (3.5) is not a whole number" `isInfixOf`)
      lastLine sout `shouldSatisfy` ("the clock where it stands, are tried; --grid N tries the multiples of N" `isInfixOf`)

    it "frac-wait.l4: after time passes a deadline that is a fraction, the act that follows is tried at the clock there, a fraction, and the deadline it then needs is named" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "frac-wait.l4"]
      map (filter (/= '\r')) (lines sout) `shouldSatisfy` elem "      PARTY Q DOES b AT 3.5"
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("not a whole number" `isInfixOf`)

    it "frac-stamp.l4: the --grid step the note names is one under which the explorer tries the stamp, and a step that does not divide it never does" $ do
      Output code _ serr <- runL4 bin ["check", instants </> "frac-stamp.l4"]
      code `shouldBe` ExitSuccess
      let marker = "`--grid "
          steps = [ takeWhile (/= '`') (drop (length marker) t) | t <- tails serr, marker `isPrefixOf` t ]
          triedAt38 sout = elem "      PARTY P DOES a AT 3.8" (map (filter (/= '\r')) (lines sout))
      steps `shouldBe` ["0.2"]
      forM_ steps \ step -> do
        Output _ sout _ <- runL4 bin ["explore", instants </> "frac-stamp.l4", "--grid", step]
        sout `shouldSatisfy` triedAt38
      -- a step of 0.5 is not one the stamp is a multiple of: green, and no act at 3.8
      Output code' sout' _ <- runL4 bin ["explore", instants </> "frac-stamp.l4", "--grid", "0.5"]
      code' `shouldBe` ExitSuccess
      sout' `shouldSatisfy` (not . triedAt38)

    it "half.l4 under --grid 0.5: acts are tried at the halves between whole instants (the explorer's side of what the note says)" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "half.l4", "--grid", "0.5"]
      code `shouldBe` ExitSuccess
      forM_ ["0", "0.5", "1", "1.5", "2", "2.5"] \ t ->
        map (filter (/= '\r')) (lines sout) `shouldSatisfy` elem ("      PARTY P DOES a AT " <> t)
      lastLine sout `shouldSatisfy` ("time on a grid of 0.5" `isInfixOf`)

    it "must-example.l4: whole stamps get no note" $ do
      Output code _ serr <- runL4 bin ["run", ".." </> "doc" </> "reference" </> "regulative" </> "must-example.l4"]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` (not . ("fractional-trace-stamp" `isInfixOf`))

  it "explores D1 to the probes' 12 states and 21 transitions, ends with the coverage line, and exits 0" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "d1-naive.l4"] <> acceptance)
    code `shouldBe` ExitSuccess
    lastLine sout `shouldSatisfy` ("Coverage: 12 states, 21 transitions; frontier exhausted; nothing refused; nothing untried" `isPrefixOf`)

  it "explores D3 to 10 states and 21 transitions and exits 0" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "d3-atomic.l4"] <> acceptance)
    code `shouldBe` ExitSuccess
    lastLine sout `shouldSatisfy` ("Coverage: 10 states, 21 transitions; frontier exhausted" `isPrefixOf`)

  it "refuses refused-number.l4's NUMBER payload by name and exits 2" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "refused-number.l4"] <> acceptance)
    code `shouldBe` ExitFailure 2
    let line = lastLine sout
    line `shouldSatisfy` ("Coverage: " `isPrefixOf`)
    line `shouldSatisfy` ("REFUSED 1: `act` of type Act, constructor `ledger records Bob's purchase` (its field `recorded at` is a NUMBER" `isInfixOf`)

  it "exits 3 when the depth bound stops it, and says so" $ do
    Output code sout _ <- runL4 bin (["explore", brief </> "d1-naive.l4", "--max-depth", "2"] <> acceptance)
    code `shouldBe` ExitFailure 3
    lastLine sout `shouldSatisfy` ("frontier NOT exhausted" `isInfixOf`)

  it "puts the coverage line on stderr too when the graph is JSON" $ do
    Output code sout serr <- runL4 bin (["explore", brief </> "refused-number.l4", "--json"] <> acceptance)
    code `shouldBe` ExitFailure 2
    sout `shouldSatisfy` ("\"coverage\"" `isInfixOf`)
    lastLine serr `shouldSatisfy` ("Coverage: " `isPrefixOf`)

  it "exits 1 on a --contract that names no rule" $ do
    Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--contract", "no such rule"]
    code `shouldBe` ExitFailure 1
    serr `shouldSatisfy` ("no rule named `no such rule`" `isInfixOf`)

  -- Three silent failures that the adversarial pass of 2026-10-26 reproduced
  -- (each exited 0 and printed a confident line), now loud or true.
  describe "what used to pass without a word" $ do
    it "exits 1 on an --until before the outset, instead of holding every property of the one state" $ do
      Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "0", "--always", "every dinner was accepted while open"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("is before the outset at 64800" `isInfixOf`)

    it "exits 1 when a property, --emit or --fair is asked of a file with no #TRACE, and 0 when nothing was asked" $
      withSystemTempDirectory "explore-notrace" $ \ dir -> do
        let file = dir </> "late.l4"
        writeFile file (unlines lateContract)
        Output plain sout _ <- runL4 bin ["explore", file]
        plain `shouldBe` ExitSuccess
        sout `shouldSatisfy` ("Nothing to explore" `isInfixOf`)
        Output asked _ serr <- runL4 bin ["explore", file, "--always", "no such rule at all"]
        asked `shouldBe` ExitFailure 1
        serr `shouldSatisfy` ("Nothing was checked" `isInfixOf`)
        Output fair _ _ <- runL4 bin ["explore", file, "--emit", dir </> "out", "--fair", "W"]
        fair `shouldBe` ExitFailure 1

    it "names, on the coverage line, a cell written only on a path that merges into a state already seen" $
      withSystemTempDirectory "explore-merge" $ \ dir -> do
        let file = dir </> "late.l4"
        writeFile file (unlines lateContract)
        Output _ sout _ <- runL4 bin ["explore", file, "--contract", "late"]
        lastLine sout `shouldSatisfy` ("write-only cells dropped: OFFICIAL's `missed`" `isInfixOf`)

  describe "--always, --reachable, --stays, --eventually (WP2)" $ do
    it "D1 violates P1 by check, Bob's purchase, buy, prints it as a #TRACE, and exits 4" $ do
      Output code sout _ <- runL4 bin (["explore", brief </> "d1-naive.l4"] <> safety)
      code `shouldBe` ExitFailure 4
      sout `shouldSatisfy` ("always `every dinner was accepted while open`: violated after 3 events" `isInfixOf`)
      drop 1 (traceAfter "every dinner was accepted while open" sout) `shouldBe`
        [ "#TRACE `the arrangement` AT 64800 WITH"
        , "    PARTY World DOES `Alice checks whether dinner is bought` AT 64800"
        , "    PARTY World DOES `ledger records Bob's purchase` AT 64800"
        , "    PARTY World DOES `Alice buys dinner` AT 64800"
        ]
      lastLine sout `shouldSatisfy` ("Coverage: 12 states, 21 transitions; frontier exhausted" `isPrefixOf`)

    it "the counterexample, pasted into D1, is reproduced by l4 run: the official record ends open at acceptance FALSE" $ do
      Output _ sout _ <- runL4 bin (["explore", brief </> "d1-naive.l4"] <> safety)
      let printed = traceAfter "every dinner was accepted while open" sout
      length printed `shouldBe` 5
      withSystemTempDirectory "l4-explore-replay" \ dir -> do
        original <- readFile (brief </> "d1-naive.l4")
        copyFile (brief </> "properties.l4") (dir </> "properties.l4")
        -- the file's own traces are taken out, so the run prints only the pasted one
        let own = takeWhile (not . ("§ `D1: the traces`" `isPrefixOf`)) (lines original)
        writeFile (dir </> "d1-naive.l4") (unlines (own <> [""] <> printed))
        Output code out _ <- runL4 bin ["run", dir </> "d1-naive.l4"]
        code `shouldBe` ExitSuccess
        let official = takeWhile (not . null) (drop 1 (dropWhile (/= "Official record:") (lines out)))
        map (takeWhile (/= '[')) official `shouldBe`
          [ "  COMMIT `dinner status record` IS opened   "
          , "  COMMIT `dinner status record` IS taken   "
          , "  COMMIT `dinners bought` IS `dinner for two`   "
          , "  COMMIT `open at acceptance` IS FALSE   "
          ]

    it "D2 violates P1 by check, re-read, Bob's purchase, buy" $ do
      Output code sout _ <- runL4 bin (["explore", brief </> "d2-reread.l4"] <> safety)
      code `shouldBe` ExitFailure 4
      drop 2 (traceAfter "every dinner was accepted while open" sout) `shouldBe`
        [ "    PARTY World DOES `Alice checks whether dinner is bought` AT 64800"
        , "    PARTY World DOES `Alice reads the ledger again` OF TRUE AT 64800"
        , "    PARTY World DOES `ledger records Bob's purchase` AT 64800"
        , "    PARTY World DOES `Alice buys dinner` AT 64800"
        ]

    it "D3 holds P1, P2 and P4, reaches P3, and exits 0" $ do
      Output code sout _ <- runL4 bin (["explore", brief </> "d3-atomic.l4"] <> safety)
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Checks (4): 4 hold" `isInfixOf`)

    it "a liveness property is unknown, never guessed, and exits 5" $ do
      Output code sout _ <- runL4 bin ["explore", brief </> "d3-atomic.l4", "--until", "75600", "--eventually", "Alice has bought or stopped"]
      code `shouldBe` ExitFailure 5
      sout `shouldSatisfy` ("eventually `Alice has bought or stopped`: unknown (liveness: run the emitted model)" `isInfixOf`)

    it "with --json the checks are in the graph's object and the summary goes to stderr too" $ do
      Output code sout serr <- runL4 bin (["explore", brief </> "d1-naive.l4", "--json"] <> safety)
      code `shouldBe` ExitFailure 4
      sout `shouldSatisfy` ("\"checks\"" `isInfixOf`)
      sout `shouldSatisfy` ("\"labels\"" `isInfixOf`)
      serr `shouldSatisfy` ("Checks (4): 1 violated, 3 hold" `isInfixOf`)

    it "exits 1 on a property that names no rule, or an --if-always with no --eventually before it" $ do
      Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--always", "no such rule"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("no rule named `no such rule`" `isInfixOf`)
      Output code' _ serr' <- runL4 bin ["explore", brief </> "d1-naive.l4", "--if-always", "the ledger is open"]
      code' `shouldBe` ExitFailure 1
      serr' `shouldSatisfy` ("must come straight after one" `isInfixOf`)

  -- §4.1, ruled 2026-10-26: what a run's observers can tell apart is what
  -- it keeps in a state. A property input named for a cell nothing writes is
  -- refused (it is empty in every state, as a misspelt one would be) unless
  -- --unwritten names the cell; and --emit with no property named keeps the
  -- cells the file's properties read, since the emitted model's consumer
  -- is unseen.
  describe "unwritten cells and the cells an emitted model keeps (§4.1)" $ do
    it "refuses a property input named for a cell nothing writes, naming the property and the cell, and exits 1 before exploring" $ do
      Output code sout serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "75600", "--always", "at most one dinner is bought"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--always `at most one dinner is bought`: its input `dinners cancelled` is named for a cell that no RECORD, COMMIT or ATTEST in the file or its imports writes" `isInfixOf`)
      serr `shouldSatisfy` ("--unwritten 'dinners cancelled'" `isInfixOf`)
      sout `shouldBe` ""

    it "lifts the refusal for the cell --unwritten names, and the graph is the one that property's cells make: 10 states, not 12" $ do
      Output code sout _ <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "75600", "--always", "at most one dinner is bought", "--unwritten", "dinners cancelled"]
      code `shouldBe` ExitSuccess
      lastLine sout `shouldSatisfy` ("Coverage: 10 states, 18 transitions; frontier exhausted" `isPrefixOf`)

    it "does not lift it for a cell --unwritten does not name, so a misspelt exemption leaves the refusal in place" $ do
      Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "75600", "--always", "at most one dinner is bought", "--unwritten", "dinners canceled"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("its input `dinners cancelled`" `isInfixOf`)

    it "refuses a misspelt input, which held on a cell nobody wrote before this rule" $
      withSystemTempDirectory "explore-typo" $ \ dir -> do
        copyFile (brief </> "d1-naive.l4") (dir </> "d1-naive.l4")
        props <- readFile (brief </> "properties.l4")
        writeFile (dir </> "properties.l4") (replaceAll "open at acceptance" "open at acceptence" props)
        Output code _ serr <- runL4 bin ["explore", dir </> "d1-naive.l4", "--until", "75600", "--always", "every dinner was accepted while open"]
        code `shouldBe` ExitFailure 1
        serr `shouldSatisfy` ("its input `open at acceptence` is named for a cell that no RECORD, COMMIT or ATTEST" `isInfixOf`)

    it "leaves a bare run as it was: D1 is 10 states, with no --emit and no property" $ do
      Output code sout _ <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "75600"]
      code `shouldBe` ExitSuccess
      lastLine sout `shouldSatisfy` ("Coverage: 10 states, 18 transitions; frontier exhausted" `isPrefixOf`)

    it "keeps, for an emitted model with no property named, every cell the file's properties read: D1's .aut has 12 states, and stderr lists the cells" $
      withSystemTempDirectory "l4-explore-emit-keep" \ dir -> do
        Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "75600", "--emit", dir]
        code `shouldBe` ExitSuccess
        serr `shouldSatisfy` ("--emit with no property named keeps, in the state, every cell a property of the file or its imports reads: `belief`, `dinner status record`, `dinners bought`, `open at acceptance`, `plan`" `isInfixOf`)
        aut <- readFile (dir </> "d1_naive.aut")
        take 1 (map (filter (/= '\r')) (lines aut)) `shouldBe` ["des (0,21,12)"]

    it "keeps only the named property's cells when --emit has one named: the same D1 is 10 states, and stderr does not claim otherwise" $
      withSystemTempDirectory "l4-explore-emit-named" \ dir -> do
        Output code _ serr <- runL4 bin ["explore", brief </> "d1-naive.l4", "--until", "75600", "--always", "at most one dinner is bought", "--unwritten", "dinners cancelled", "--emit", dir]
        code `shouldBe` ExitSuccess
        serr `shouldSatisfy` (not . ("keeps, in the state" `isInfixOf`))
        aut <- readFile (dir </> "d1_naive.aut")
        take 1 (map (filter (/= '\r')) (lines aut)) `shouldBe` ["des (0,18,10)"]

  describe "--emit and --fair (WP3)" $ do
    it "writes D3's thirteen files, gives Alice's two moving acts weak fairness, and exits as it would without --emit" $
      withSystemTempDirectory "l4-explore-emit" \ dir -> do
        Output code _ serr <- runL4 bin (["explore", brief </> "d3-atomic.l4"] <> safety <> liveness <> ["--emit", dir, "--fair", "Alice"])
        -- a liveness property is unknown in process, so 5, as without --emit
        code `shouldBe` ExitFailure 5
        serr `shouldSatisfy` ("Emitted to " `isInfixOf`)
        files <- listDirectory dir
        sort files `shouldBe` sort
          ( [ "d3_atomic.aut", "d3_atomic.tla", "d3_atomic.cfg", "d3_atomic.smv", "d3_atomic.dot", "d3_atomic.pnml" ]
            <> [ "d3_atomic." <> p <> ".cfg"
               | p <- [ "Always_every_dinner_was_accepted_while_open", "Always_at_most_one_dinner_is_bought"
                      , "Never_Alice_s_belief_is_stale", "Stays_one_dinner_is_bought"
                      , "Eventually_Alice_has_bought_or_stopped"
                      , "Eventually_one_dinner_is_bought_if_always_the_ledger_is_open", "Eventually_Bob_has_bought" ] ] )
        tla <- readFile (dir </> "d3_atomic.tla")
        tla `shouldSatisfy` ("FairSpec == Spec /\\ WF_vars(World_Alice_checks_whether_dinner_is_bought) /\\ WF_vars(World_Alice_buys_dinner_OF_TRUE)\n" `isInfixOf`)
        smv <- readFile (dir </> "d3_atomic.smv")
        length [ () | l <- lines smv, "JUSTICE " `isPrefixOf` l ] `shouldBe` 2
        aut <- readFile (dir </> "d3_atomic.aut")
        take 1 (lines aut) `shouldBe` ["des (0,21,10)"]

    it "with no --fair, makes no action fair, and says so in the model" $
      withSystemTempDirectory "l4-explore-emit" \ dir -> do
        Output code _ _ <- runL4 bin ["explore", brief </> "d3-atomic.l4", "--until", "75600", "--emit", dir]
        code `shouldBe` ExitSuccess
        tla <- readFile (dir </> "d3_atomic.tla")
        tla `shouldSatisfy` ("none was named, so no action is fair" `isInfixOf`)
        tla `shouldSatisfy` ("FairSpec == Spec\n" `isInfixOf`)
        smv <- readFile (dir </> "d3_atomic.smv")
        smv `shouldSatisfy` (not . ("JUSTICE " `isInfixOf`))

    it "gives a state the depth bound left with no edge an unexplored self-loop in the .tla and .smv, and none in the .aut" $
      withSystemTempDirectory "l4-explore-emit" \ dir -> do
        Output code _ _ <- runL4 bin ["explore", brief </> "d3-atomic.l4", "--until", "75600", "--max-depth", "1", "--emit", dir]
        code `shouldBe` ExitFailure 3
        tla <- readFile (dir </> "d3_atomic.tla")
        tla `shouldSatisfy` ("INCOMPLETE: " `isInfixOf`)
        tla `shouldSatisfy` ("lastAct' = \"unexplored\"" `isInfixOf`)
        smv <- readFile (dir </> "d3_atomic.smv")
        smv `shouldSatisfy` ("next(act) = unexplored" `isInfixOf`)
        aut <- readFile (dir </> "d3_atomic.aut")
        aut `shouldSatisfy` (not . ("unexplored" `isInfixOf`))

    it "exits 1 on a --fair that names no act, and on --fair without --emit" $
      withSystemTempDirectory "l4-explore-emit" \ dir -> do
        Output code _ serr <- runL4 bin ["explore", brief </> "d3-atomic.l4", "--until", "75600", "--emit", dir, "--fair", "Bobby"]
        code `shouldBe` ExitFailure 1
        serr `shouldSatisfy` ("--fair Bobby: names no party" `isInfixOf`)
        Output code' _ serr' <- runL4 bin ["explore", brief </> "d3-atomic.l4", "--fair", "Alice"]
        code' `shouldBe` ExitFailure 1
        serr' `shouldSatisfy` ("needs --emit" `isInfixOf`)

  -- smucclaw/l4-ide#1087: a breached position that still has a part waiting.
  describe "a breached position that still has a part waiting (#1087)" $ do
    it "sale.l4: after the buyer's breach the state waits on the seller, is not terminal, offers the seller's act and the seller's deadline, and the position `l4 run` reaches by the tick is in the graph" $ do
      Output code sout _ <- runL4 bin ["explore", breached </> "sale.l4"]
      code `shouldBe` ExitSuccess
      lastLine sout `shouldSatisfy` ("nothing untried" `isInfixOf`)
      case [ (sid, rid, term) | (sid, rid, term, ["WAITUNTIL OF 3"]) <- statesOf sout ] of
        [(sid, rid, term)] -> do
          term `shouldBe` False
          lookup rid (residualTexts sout) `shouldSatisfy` maybe False ("[still waiting on: Seller MUST deliver WITHIN 2]" `isInfixOf`)
          [ l | (a, _, l) <- edgesOf sout, a == sid ] `shouldBe`
            ["PARTY Seller DOES deliver", "time passes the deadline 5 (WAITUNTIL 6)"]
          let towards = [ b | (a, b, l) <- edgesOf sout, a == sid, "WAITUNTIL 6" `isInfixOf` l ]
              residualOf b = lookup b [ (sid', rid') | (sid', rid', _, _) <- statesOf sout ] >>= \ r -> lookup r (residualTexts sout)
          got <- reachedBy bin (breached </> "sale.l4") "sale" ["(WAITUNTIL 3)", "(WAITUNTIL 6)"]
          map residualOf towards `shouldBe` [Just got]
        other -> expectationFailure ("expected one state first reached by WAITUNTIL OF 3, got " <> show (length other))

    it "sale.l4: the breach with the seller still waiting and the breach with nothing waiting are two states, and the second is terminal" $ do
      Output _ sout _ <- runL4 bin ["explore", breached </> "sale.l4"]
      let blamedBuyer = [ (term, r) | (_, rid, term, _) <- statesOf sout, Just r <- [lookup rid (residualTexts sout)]
                        , "DEONTIC BREACHED" `isPrefixOf` r, "BY Buyer" `isInfixOf` r, not ("BY Seller" `isInfixOf` r) ]
      sort [ term | (term, r) <- blamedBuyer, "still waiting" `isInfixOf` r ] `shouldBe` [False]
      sort [ term | (term, r) <- blamedBuyer, not ("still waiting" `isInfixOf` r) ] `shouldBe` [True]

    it "resell.l4: the issue's contract: the buyer's breach does not lift the seller's prohibition, and resell after it adds the seller's blame" $ do
      Output code sout _ <- runL4 bin ["explore", breached </> "resell.l4"]
      -- exit 2 for what it always was: a SHANT with no WITHIN offers no tick, and says so
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("UNTRIED 1: time runs out on resell (no WITHIN" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("(unread)" `isInfixOf`))
      case [ (sid, rid, term) | (sid, rid, term, ["WAITUNTIL OF 3"]) <- statesOf sout ] of
        [(sid, rid, term)] -> do
          term `shouldBe` False
          lookup rid (residualTexts sout) `shouldSatisfy` maybe False ("[still waiting on: Seller SHANT resell]" `isInfixOf`)
          let towards = [ b | (a, b, l) <- edgesOf sout, a == sid, "resell" `isInfixOf` l ]
              residualOf b = lookup b [ (sid', rid') | (sid', rid', _, _) <- statesOf sout ] >>= \ r -> lookup r (residualTexts sout)
          -- the same position the evaluator reaches by the tick and the act, and by the act alone at 3
          later <- reachedBy bin (breached </> "resell.l4") "`the sale`" ["(WAITUNTIL 3)", "PARTY Seller DOES resell AT 3"]
          alone <- reachedBy bin (breached </> "resell.l4") "`the sale`" ["PARTY Seller DOES resell AT 3"]
          map residualOf towards `shouldBe` [Just later]
          alone `shouldBe` later
        other -> expectationFailure ("expected one state first reached by WAITUNTIL OF 3, got " <> show (length other))

    it "continuation.l4: an obligation armed after the breach is named as untried (exit 2), and its state is not called terminal" $ do
      Output code sout _ <- runL4 bin ["explore", breached </> "continuation.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("UNTRIED 1: (unread) Seller" `isInfixOf`)
      lastLine sout `shouldSatisfy` ("armed after the breach" `isInfixOf`)
      case [ term | (_, rid, term, _) <- statesOf sout, Just r <- [lookup rid (residualTexts sout)], "(unread)" `isInfixOf` r ] of
        [term] -> term `shouldBe` False
        other -> expectationFailure ("expected one state that waits on an unread norm, got " <> show (length other))

  -- smucclaw/l4-ide#1081: which instants an act is tried at.
  describe "the instants an act is tried at (#1081)" $ do
    it "clocks.l4: the position in which both deadlines fall together is in the graph, nothing is untried, and l4 run reaches the same position by the printed path" $
      withSystemTempDirectory "l4-explore-instants" \ dir -> do
        Output code sout _ <- runL4 bin ["explore", instants </> "clocks.l4"]
        code `shouldBe` ExitSuccess
        lastLine sout `shouldSatisfy` ("frontier exhausted; nothing refused; nothing untried" `isInfixOf`)
        case statePath ["MUST b WITHIN 5 HENCE", "MUST c WITHIN 5 HENCE"] sout of
          Nothing -> expectationFailure ("no state holds both deadlines at 5 days out:\n" <> sout)
          Just (events, residual) -> do
            original <- readFile (instants </> "clocks.l4")
            let own = takeWhile (not . ("#TRACE" `isPrefixOf`)) (lines original)
            writeFile (dir </> "clocks.l4") (unlines (own <> ["#TRACE clocks AT 0 WITH"] <> map ("  " <>) events))
            Output rcode rout _ <- runL4 bin ["run", dir </> "clocks.l4"]
            rcode `shouldBe` ExitSuccess
            let got = unwords (words (unlines (takeWhile (not . null) (drop 1 (dropWhile (/= "Result:") (lines rout))))))
            got `shouldBe` residual

    it "clocks.l4 has no fractional instant, on a grid of 1 either, and says how many instants it tried" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "clocks.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . hasFraction)
      lastLine sout `shouldSatisfy` ("instants: " `isInfixOf`)
      Output gcode gout _ <- runL4 bin ["explore", instants </> "clocks.l4", "--grid", "1"]
      gcode `shouldBe` ExitSuccess
      gout `shouldSatisfy` (not . hasFraction)
      statePath ["MUST b WITHIN 5 HENCE", "MUST c WITHIN 5 HENCE"] gout `shouldSatisfy` (/= Nothing)

    it "window.l4: --grid 1 tries ship inside the window that opens at 3 and reaches FULFILLED" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "window.l4", "--grid", "1"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("PARTY Ben DOES ship" `isInfixOf`)
      lastLine sout `shouldSatisfy` ("nothing untried" `isInfixOf`)

    it "open.l4: --grid 1 with no deadline and no --until says it stopped, and exits 2; with --until 10 it reaches FULFILLED, and the only thing untried is what was untried before" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "open.l4", "--grid", "1"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("no deadline and no --until" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("nothing untried" `isInfixOf`))
      Output code' sout' _ <- runL4 bin ["explore", instants </> "open.l4", "--grid", "1", "--until", "10"]
      sout' `shouldSatisfy` ("PARTY Ben DOES ship" `isInfixOf`)
      -- a MAY with no WITHIN has no deadline to tick past, which the explorer has always listed as untried
      code' `shouldBe` ExitFailure 2
      lastLine sout' `shouldSatisfy` ("UNTRIED 1: time runs out on ship (no WITHIN" `isInfixOf`)

    it "half.l4: a deadline that is not a whole number leaves instants untried, says so, and exits 2" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "half.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("not a whole number" `isInfixOf`)
      -- what is tried by default and under --grid, not "only whole instants"
      lastLine sout `shouldSatisfy` ("by default only whole instants, and the clock where it stands, are tried; --grid N tries the multiples of N" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("and only whole instants are tried" `isInfixOf`))
      lastLine sout `shouldSatisfy` (not . ("nothing untried" `isInfixOf`))

    it "--max-instants 2 cuts a grid of 1 on clocks.l4, says how, and exits 2" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "clocks.l4", "--grid", "1", "--max-instants", "2"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("instant cap of 2" `isInfixOf`)

    it "--grid 2 on deadlines at 3 and 7 says they are off the grid, and exits 2" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "clocks.l4", "--grid", "2"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("off the grid of 2" `isInfixOf`)

    it "flip3.l4: the state where Q's deadline passed alone (an anchored deadline) is reachable, and the explorer finds it" $ do
      Output _ sout _ <- runL4 bin ["explore", instants </> "flip3.l4", "--reachable", "Q missed first"]
      sout `shouldSatisfy` ("reachable `Q missed first`: holds" `isInfixOf`)

    it "room.l4: a tie that needs a chain of acts is named and not searched by default (exit 2), and --chains searches it" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "room.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("ties through chains of acts, for " `isInfixOf`)
      lastLine sout `shouldSatisfy` ("--chains tries them" `isInfixOf`)
      -- and what --chains does not reach, with the way that does
      lastLine sout `shouldSatisfy` ("--grid 1 tries every whole instant up to a deadline or --until" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("nothing untried" `isInfixOf`))
      Output ccode csout _ <- runL4 bin ["explore", instants </> "room.l4", "--chains"]
      -- exit 2 still: the norms armed after a breach (#1087) are named and cannot be read; the chain is not
      ccode `shouldBe` ExitFailure 2
      lastLine csout `shouldSatisfy` ("(unread)" `isInfixOf`)
      lastLine csout `shouldSatisfy` (not . ("ties through chains" `isInfixOf`))
      -- the chain made the graph larger, not smaller
      let states l = read (takeWhile (/= ' ') (drop (length ("Coverage: " :: String)) l)) :: Int
      states (lastLine csout) `shouldSatisfy` (> states (lastLine sout))

    it "lapse-fixed.l4: a lapse of a deadline that no act started is tied with the acts of its state, and the position it reaches is in the graph" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "lapse-fixed.l4"]
      -- exit 2 for the norms armed after a breach (#1087), which are named and cannot be read; not for a tie
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("(unread)" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("ties through chains" `isInfixOf`))
      got <- reachedBy bin (instants </> "lapse-fixed.l4") "lapsef" ["PARTY P DOES a AT 5", "(WAITUNTIL 7)"]
      unwords (words (filter (/= '\r') sout)) `shouldSatisfy` (got `isInfixOf`)

    it "cap-re.l4: a cut that only a second visit to a state makes is named (exit 2), and is not made with room for one more instant" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "cap-re.l4", "--max-instants", "3"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("past the instant cap" `isInfixOf`)
      -- with room for one more instant the cap names nothing (exit 2 stays, for the norms armed after a breach)
      Output _ wout _ <- runL4 bin ["explore", instants </> "cap-re.l4", "--max-instants", "4"]
      lastLine wout `shouldSatisfy` (not . ("past the instant cap" `isInfixOf`))

    it "own-lapse.l4: the act whose own lapse arms a cure is tied with it in the chain note, a loud false alarm that --chains clears (exit 2, then exit 0)" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "own-lapse.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("ties through chains of acts, for PARTY T DOES t" `isInfixOf`)
      Output ccode csout _ <- runL4 bin ["explore", instants </> "own-lapse.l4", "--chains"]
      ccode `shouldBe` ExitSuccess
      lastLine csout `shouldSatisfy` ("nothing untried" `isInfixOf`)

    it "succ4.l4: a chain tie with the cure of an act's own lapse, which the act's continuation re-arms, is named by default (exit 2) and --chains reaches it" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "succ4.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("ties through chains of acts, for PARTY T DOES t" `isInfixOf`)
      Output ccode csout _ <- runL4 bin ["explore", instants </> "succ4.l4", "--chains"]
      -- exit 2 for the cure armed behind a breach (#1087), named and not readable: not for a chain
      ccode `shouldBe` ExitFailure 2
      lastLine csout `shouldSatisfy` ("(unread)" `isInfixOf`)
      lastLine csout `shouldSatisfy` (not . ("ties through chains" `isInfixOf`))
      let tAtTwo = [ l | l <- lines (filter (/= '\r') csout), "PARTY T DOES t AT 2" `isInfixOf` l ]
      tAtTwo `shouldSatisfy` (not . null)

    it "cap-shift.l4: a state reached again at a LATER window says the shortfall of the larger visit, whichever came first" $ do
      let need k = do
            Output code sout _ <- runL4 bin ["explore", instants </> "cap-shift.l4", "--max-instants", show (k :: Int)]
            pure (code, lastLine sout)
      (c2, l2) <- need 2
      c2 `shouldBe` ExitFailure 2
      l2 `shouldSatisfy` ("PARTY B DOES b at the instants past the instant cap (it needs 3 more instants than the instant cap of 2 allows" `isInfixOf`)
      (c3, l3) <- need 3
      c3 `shouldBe` ExitFailure 2
      l3 `shouldSatisfy` ("it needs 2 more instants than the instant cap of 3 allows" `isInfixOf`)
      (c5, l5) <- need 5
      -- exit 2 for what is armed behind a breach (#1087), and no cap note any more
      c5 `shouldBe` ExitFailure 2
      l5 `shouldSatisfy` ("(unread)" `isInfixOf`)
      l5 `shouldSatisfy` (not . ("instant cap" `isInfixOf`))

    it "frac-re.l4: a state reached again names its fraction once, not once for each fraction its visits find" $ do
      Output _ sout _ <- runL4 bin ["explore", instants </> "frac-re.l4"]
      let occurrences needle hay = length [ () | i <- [0 .. length hay - length needle], needle `isPrefixOf` drop i hay ]
      occurrences "PARTY B DOES b at instants that are not whole numbers" (lastLine sout) `shouldBe` 1

    it "succ2.l4: an act that re-arms its own lapse is tried at the tie with the cure the lapse arms: t at 3 is in the graph" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "succ2.l4"]
      -- exit 2 for the cure armed behind a breach (#1087), named and not readable; not for a missing tie
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("(unread)" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("ties through chains" `isInfixOf`))
      let tAtThree = [ l | l <- lines (filter (/= '\r') sout), "PARTY T DOES t AT 3" `isInfixOf` l ]
      tAtThree `shouldSatisfy` (not . null)

    it "hidden.l4: two reasons under one label in one state are both named" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "hidden.l4"]
      code `shouldBe` ExitFailure 2
      let occurrences needle hay = length [ () | i <- [0 .. length hay - length needle], needle `isPrefixOf` drop i hay ]
      occurrences "no WITHIN: the obligation has no deadline to tick past" (lastLine sout) `shouldBe` 1
      occurrences "the BEFORE date was never evaluated" (lastLine sout) `shouldBe` 1

    it "cap-re.l4 --max-instants 2: a state reached again at an earlier clock says the shortfall it has there, the larger" $ do
      Output _ sout _ <- runL4 bin ["explore", instants </> "cap-re.l4", "--max-instants", "2"]
      lastLine sout `shouldSatisfy` ("PARTY B DOES b at the instants past the instant cap" `isInfixOf`)
      lastLine sout `shouldSatisfy` ("it needs 2 more instants than the instant cap of 2 allows" `isInfixOf`)

    it "fx-fork.l4, fx-barrier.l4: a lapse of a deadline fixed at the outset, inside an EVERY, ties the act of its state with the cure: pia's act at 5 is in the graph" $
      forM_ ["fx-fork.l4", "fx-barrier.l4"] \ f -> do
        Output code sout _ <- runL4 bin ["explore", instants </> f]
        -- exit 2 for the refund armed after a breach (#1087), named and not readable; not for a missing tie
        code `shouldBe` ExitFailure 2
        lastLine sout `shouldSatisfy` ("(unread)" `isInfixOf`)
        lastLine sout `shouldSatisfy` (not . ("ties through chains" `isInfixOf`))
        let piaAtFive = [ l | l <- lines (filter (/= '\r') sout), "pia" `isInfixOf` l || "Pia" `isInfixOf` l, " AT 5" `isSuffixOf` l ]
        piaAtFive `shouldSatisfy` (not . null)

    it "merged.l4 --chains --max-states 20: the states the bound keeps out are counted as states, no more than the graph has past the bound" $ do
      Output _ full _ <- runL4 bin ["explore", instants </> "merged.l4", "--chains"]
      Output code cut _ <- runL4 bin ["explore", instants </> "merged.l4", "--chains", "--max-states", "20"]
      -- the state bound is named whatever the exit status (2 outranks 3 when something is also untried)
      code `shouldSatisfy` (/= ExitSuccess)
      lastLine cut `shouldSatisfy` ("frontier NOT exhausted" `isInfixOf`)
      let states l = read (takeWhile (/= ' ') (drop (length ("Coverage: " :: String)) l)) :: Int
          notAdded l = case words (snd (breakOn "frontier NOT exhausted:" l)) of
            (_ : _ : _ : n : _) -> read n :: Int
            _                   -> -1
          breakOn needle hay = case [ i | i <- [0 .. length hay - length needle], needle `isPrefixOf` drop i hay ] of
            (i : _) -> splitAt i hay
            []      -> (hay, "")
      notAdded (lastLine cut) `shouldSatisfy` (<= states (lastLine full) - 20)
      notAdded (lastLine cut) `shouldSatisfy` (> 0)

    it "clocks.l4: no chain, so nothing is said about chains" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "clocks.l4"]
      code `shouldBe` ExitSuccess
      lastLine sout `shouldSatisfy` (not . ("chains" `isInfixOf`))

    it "lapse.l4: a deadline started by a lapse is named by default (exit 2), and --chains holds the positions the evaluator reaches by it" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "lapse.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("ties through chains of acts, for PARTY P DOES a" `isInfixOf`)
      Output ccode csout _ <- runL4 bin ["explore", instants </> "lapse.l4", "--chains"]
      -- exit 2 still, for the norms armed after a breach (#1087), which are named and cannot be read; the chain is not
      ccode `shouldBe` ExitFailure 2
      lastLine csout `shouldSatisfy` ("(unread)" `isInfixOf`)
      lastLine csout `shouldSatisfy` (not . ("ties through chains" `isInfixOf`))
      forM_ [ ["PARTY P DOES a AT 2", "(WAITUNTIL 6)"], ["PARTY P DOES a AT 3", "(WAITUNTIL 7)"] ] \ events -> do
        got <- reachedBy bin (instants </> "lapse.l4") "lapse" events
        unwords (words (filter (/= '\r') csout)) `shouldSatisfy` (got `isInfixOf`)

    it "merged.l4: a state reached again at an earlier clock is explored again, so the positions the evaluator reaches by 4 and 5 events are in the graph" $
      forM_ [[], ["--chains"]] \ flags -> do
        Output _ sout _ <- runL4 bin (["explore", instants </> "merged.l4"] <> flags)
        forM_ [ [ "PARTY T DOES t AT 0", "PARTY T DOES confirm AT 0", "PARTY Q DOES q AT 0", "PARTY B DOES b AT 0" ]
              , [ "PARTY T DOES t AT 0", "PARTY T DOES confirm AT 0", "PARTY Q DOES q AT 0", "PARTY B DOES b AT 0", "(WAITUNTIL 3)" ]
              , [ "PARTY T DOES t AT 0", "PARTY T DOES confirm AT 0", "PARTY Q DOES q AT 0", "PARTY B DOES b AT 3", "(WAITUNTIL 7)" ] ] \ events -> do
          got <- reachedBy bin (instants </> "merged.l4") "m" events
          unwords (words (filter (/= '\r') sout)) `shouldSatisfy` (got `isInfixOf`)

    it "l4 lts on adjacent.l4: the tick past the deadline at 3 is the clock reaching 4, not 3.5, and does not reach the deadline at 4" $ do
      Output code sout _ <- runL4 bin ["lts", instants </> "adjacent.l4", "--contract", "adjacent"]
      code `shouldBe` ExitSuccess
      let ls = map (filter (/= '\r')) (lines sout)
      ls `shouldSatisfy` any ("nothing happens by 3 (the clock reaches 4) \8594 P is in breach" `isInfixOf`)
      ls `shouldSatisfy` all (not . ("3.5" `isInfixOf`))

  -- the explorer's X2: the clock an exploration starts at
  describe "the clock an exploration starts at (X2)" $ do
    it "negstart.l4: a start of -5 is the clock, so an act at -5 is in time and the tick past the deadline is at -1" $ do
      Output code sout _ <- runL4 bin ["explore", startFixtures </> "negstart.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("explored from its outset at -5" `isInfixOf`)
      sout `shouldSatisfy` ("PARTY P DOES a AT -5" `isInfixOf`)
      sout `shouldSatisfy` (not . ("AT 0" `isInfixOf`))
      sout `shouldSatisfy` ("WAITUNTIL OF -1" `isInfixOf`)

    it "nonliteral.l4: a start that is not a literal is read: AT (10 + 5) is 15, and the tick is at 19" $ do
      Output code sout _ <- runL4 bin ["explore", startFixtures </> "nonliteral.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("PARTY P DOES a AT 15" `isInfixOf`)
      sout `shouldSatisfy` (not . ("AT 0" `isInfixOf`))
      sout `shouldSatisfy` ("WAITUNTIL OF 19" `isInfixOf`)

    it "unreadable.l4: a start that has no value is refused (exit 1), not taken for 0" $ do
      Output code sout serr <- runL4 bin ["explore", startFixtures </> "unreadable.l4"]
      code `shouldBe` ExitFailure 1
      (sout <> serr) `shouldSatisfy` ("is neither a number nor a date the explorer can read" `isInfixOf`)

    it "frac-neg.l4: below 0 a state reached again still names its fraction once, whatever its sign" $ do
      Output code sout _ <- runL4 bin ["explore", startFixtures </> "frac-neg.l4"]
      code `shouldBe` ExitFailure 2
      let occurrences needle hay = length [ () | i <- [0 .. length hay - length needle], needle `isPrefixOf` drop i hay ]
      occurrences "PARTY B DOES b at instants that are not whole numbers" (lastLine sout) `shouldBe` 1

  -- smucclaw/l4-ide#1106: `l4 lts --contract` looked only at the top level
  describe "a rule under a § heading (#1106)" $ do
    it "sectioned.l4: l4 lts --contract finds the rule, as l4 explore --contract does" $ do
      Output code sout serr <- runL4 bin ["lts", sections </> "sectioned.l4", "--contract", "pay on time"]
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` ("no top-level rule" `isInfixOf`)
      sout `shouldSatisfy` ("`pay on time` \8212 before anything has happened" `isInfixOf`)
      sout `shouldSatisfy` ("Next deadline: 10 (Alice: pay)" `isInfixOf`)
      Output ecode esout _ <- runL4 bin ["explore", sections </> "sectioned.l4", "--contract", "pay on time"]
      ecode `shouldBe` ExitSuccess
      esout `shouldSatisfy` ("3 states, 4 transitions" `isInfixOf`)

    it "two-sections.l4: of two rules called `the duty`, both take the first in the file, and l4 lts finds one two headings down" $ do
      Output code sout _ <- runL4 bin ["lts", sections </> "two-sections.l4", "--contract", "the duty"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Alice MUST pay \8212 due by 10 (10 from now)" `isInfixOf`)
      sout `shouldNotSatisfy` ("ship" `isInfixOf`)
      Output ecode esout _ <- runL4 bin ["explore", sections </> "two-sections.l4", "--contract", "the duty"]
      ecode `shouldBe` ExitSuccess
      esout `shouldSatisfy` ("time passes the deadline 10 (WAITUNTIL 11)" `isInfixOf`)
      esout `shouldNotSatisfy` ("ship" `isInfixOf`)
      Output ncode nsout _ <- runL4 bin ["lts", sections </> "two-sections.l4", "--contract", "the nested duty"]
      ncode `shouldBe` ExitSuccess
      nsout `shouldSatisfy` ("Alice MUST ship \8212 due by 30 (30 from now)" `isInfixOf`)

    it "a name no section defines: both refuse it in the same words, and exit 1" $ do
      Output code _ serr <- runL4 bin ["lts", sections </> "two-sections.l4", "--contract", "no such duty"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--contract: no rule named `no such duty` that takes no inputs" `isInfixOf`)
      Output ecode _ eserr <- runL4 bin ["explore", sections </> "two-sections.l4", "--contract", "no such duty"]
      ecode `shouldBe` ExitFailure 1
      eserr `shouldSatisfy` ("--contract: no rule named `no such duty` that takes no inputs" `isInfixOf`)

  -- smucclaw/l4-ide#1107: a WITHIN written as a name or an expression was
  -- never worked out, so its breach was never explored and the list could not
  -- name its deadline. Each spelling is held to its literal twin: the same
  -- text, but for the contract's name and the WITHIN as written.
  describe "a deadline written as a name or an expression (#1107)" $ do
    let explored c f = runL4 bin ["explore", deadlines </> f, "--contract", c]
        listed c f = runL4 bin ["lts", deadlines </> f, "--contract", c]
        twins f lit c = do
          Output lcode lout _ <- explored lit f
          Output code out _ <- explored c f
          lcode `shouldBe` ExitSuccess
          code `shouldBe` ExitSuccess
          exploreTwin out `shouldBe` exploreTwin lout
          Output llcode llout _ <- listed lit f
          Output lscode lsout _ <- listed c f
          llcode `shouldBe` ExitSuccess
          lscode `shouldBe` ExitSuccess
          ltsTwin lsout `shouldBe` ltsTwin llout
          pure (out, lsout)
    it "shapes.l4: a named constant, arithmetic on literals, and a name for arithmetic explore and list as the literal does" $
      forM_ ["named", "sum", "named sum"] \ c -> do
        (out, lsout) <- twins "shapes.l4" "literal" c
        out `shouldSatisfy` ("3 states, 4 transitions" `isInfixOf`)
        out `shouldSatisfy` ("time passes the deadline 10 (WAITUNTIL 11)" `isInfixOf`)
        lsout `shouldSatisfy` ("Alice MUST pay \8212 due by 10 (" `isInfixOf`)
        lsout `shouldSatisfy` ("Next deadline: 10 (Alice: pay)" `isInfixOf`)

    it "shapes.l4: a deadline whose working out divides by zero is not known, and neither tool crashes" $ do
      let why = "working out the WITHIN failed (Division by zero in the operation: DIVIDED BY), so its deadline is not known here"
      Output code out _ <- explored "raises" "shapes.l4"
      code `shouldBe` ExitFailure 2
      out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
      Output lcode lout _ <- listed "raises" "shapes.l4"
      lcode `shouldBe` ExitSuccess
      lout `shouldSatisfy` (("time runs out on Alice MUST pay \8212 " <> why) `isInfixOf`)
      lout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    it "given.l4: a WITHIN that reads the rule's own input is not worked out" $ do
      let why = "the WITHIN reads `period`, an input of the rule, which the contract has not worked out yet, so its deadline is not known here"
      Output code out _ <- runL4 bin ["explore", deadlines </> "given.l4"]
      code `shouldBe` ExitFailure 2
      out `shouldSatisfy` (why `isInfixOf`)
      Output lcode lout _ <- runL4 bin ["lts", deadlines </> "given.l4"]
      lcode `shouldBe` ExitSuccess
      lout `shouldSatisfy` (why `isInfixOf`)

    it "carried.l4: a named deadline carried past a breach explores as the literal does" $ do
      Output lcode lout _ <- explored "sale literal" "carried.l4"
      Output code out _ <- explored "sale named" "carried.l4"
      lcode `shouldBe` ExitSuccess
      code `shouldBe` ExitSuccess
      exploreTwin out `shouldBe` exploreTwin lout
      out `shouldSatisfy` ("12 states, 26 transitions" `isInfixOf`)
      out `shouldSatisfy` ("[still waiting on: Seller MUST deliver WITHIN 2]" `isInfixOf`)

    it "armed.l4: armed by HENCE, beside an AFTER, and counted OF a named instant, each as its literal twin" $ do
      _ <- twins "armed.l4" "then literal" "then named"
      (_, opened) <- twins "armed.l4" "after literal" "after named"
      opened `shouldSatisfy` ("Next deadline: 15 (Alice: ship)" `isInfixOf`)
      (_, anchored) <- twins "armed.l4" "of literal" "of named"
      anchored `shouldSatisfy` ("Next deadline: 8 (Alice: ship)" `isInfixOf`)
      Output code out _ <- runL4 bin ["lts", deadlines </> "armed.l4"]
      code `shouldBe` ExitSuccess
      out `shouldSatisfy` ("Bob MUST ship \8212 due by 12 (`ten days` from now)" `isInfixOf`)
      out `shouldSatisfy` ("Next deadline: 12 (Bob: ship)" `isInfixOf`)

    it "armed.l4 and ledger.l4: a named AFTER, and a name that reads a ledger, are not worked out" $ do
      Output code out _ <- explored "named after" "armed.l4"
      code `shouldBe` ExitFailure 2
      out `shouldSatisfy` ("time runs out on ship, in 1 state: the AFTER was never evaluated and is not a literal" `isInfixOf`)
      Output lcode lout _ <- explored "ledger read" "ledger.l4"
      lcode `shouldBe` ExitFailure 2
      lout `shouldSatisfy` ("the WITHIN reads `recorded period`, which reads a ledger, so it is worked out only in a run and its deadline is not known here" `isInfixOf`)

    it "ledger.l4: a RECALL written in the WITHIN, or in its OF anchor, is not worked out either" $ do
      forM_ [("direct read", "the WITHIN"), ("direct anchor", "the anchor of the WITHIN")] \ (c, what) -> do
        let why = what <> " reads a ledger with RECALL, so it is worked out only in a run and its deadline is not known here"
        Output code out _ <- explored c "ledger.l4"
        code `shouldBe` ExitFailure 2
        out `shouldSatisfy` (why `isInfixOf`)
        Output lcode lout _ <- listed c "ledger.l4"
        lcode `shouldBe` ExitSuccess
        lout `shouldSatisfy` (why `isInfixOf`)
        lout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    -- review of #1107: a name the check met only as a variable or the head
    -- of a positional application missed a ledger read reached any other way
    it "called.l4: a rule that reads a ledger, named with WITH, through a wrapper, or as a genitive, is not worked out" $
      forM_ [("named call", "recorded period"), ("wrapped", "wrapper"), ("genitive", "period for")] \ (c, rule) -> do
        let why = "the WITHIN reads `" <> rule <> "`, which reads a ledger, so it is worked out only in a run and its deadline is not known here"
        Output code out _ <- explored c "called.l4"
        code `shouldBe` ExitFailure 2
        out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
        out `shouldNotSatisfy` ("time passes the deadline 50" `isInfixOf`)
        Output lcode lout _ <- listed c "called.l4"
        lcode `shouldBe` ExitSuccess
        lout `shouldSatisfy` (why `isInfixOf`)
        lout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    -- review of #1107: a section GIVEN supplied by a WITH was read at its
    -- TYPICALLY default (30, and 35 through the OF anchor, where the run's
    -- deadline is 20 for both)
    it "section-given.l4: a WITHIN or an OF anchor that reads a section GIVEN is not worked out, supplied or not" $
      forM_ [ ("the deal", "the WITHIN", "the period", "30")
            , ("the plain deal", "the WITHIN", "the period", "30")
            , ("anchored deal", "the anchor of the WITHIN", "the start", "35") ] \ (c, what, given, wrong) -> do
        let why = what <> " reads `" <> given <> "`, a section GIVEN, which a WITH can supply, so it is worked out only in a run and its deadline is not known here"
        Output code out _ <- explored c "section-given.l4"
        code `shouldBe` ExitFailure 2
        out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
        out `shouldNotSatisfy` (("time passes the deadline " <> wrong) `isInfixOf`)
        Output lcode lout _ <- listed c "section-given.l4"
        lcode `shouldBe` ExitSuccess
        lout `shouldSatisfy` (why `isInfixOf`)
        lout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    -- review of #1107: worked out in the module, a rule that reads a section
    -- GIVEN stopped with the evaluator's internal error
    it "section-reader.l4: a WITHIN naming a rule that reads a section GIVEN is untried with a reason, not an internal error" $
      forM_ ["supplied", "plain"] \ c -> do
        let why = "the WITHIN reads `the window`, which reads `rate`, a section GIVEN, which a WITH can supply, so it is worked out only in a run and its deadline is not known here"
        Output code out err <- explored c "section-reader.l4"
        code `shouldBe` ExitFailure 2
        out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
        (out <> err) `shouldNotSatisfy` ("Internal error" `isInfixOf`)
        Output lcode lout lerr <- listed c "section-reader.l4"
        lcode `shouldBe` ExitSuccess
        lout `shouldSatisfy` (why `isInfixOf`)
        (lout <> lerr) `shouldNotSatisfy` ("Internal error" `isInfixOf`)

    -- review of #1107: worked out outside a run, a deadline that reads the
    -- clock comes out 8 under one --fixed-now and 5 under another
    it "clock.l4: a WITHIN that reads the clock or the environment, itself or through a rule, is not worked out, under any --fixed-now" $
      forM_ [ ("clock duty", "the WITHIN reads `clocky`, which reads the clock (TODAY)")
            , ("today duty", "the WITHIN reads the clock (TODAY)")
            , ("env duty", "the WITHIN reads `env period`, which reads the world outside the file (ENV)") ] \ (c, reads') ->
        forM_ ["2025-01-31T15:45:30Z", "2025-02-04T15:45:30Z"] \ now -> do
          let why = reads' <> ", so it is worked out only in a run and its deadline is not known here"
          Output code out _ <- runL4 bin ["explore", deadlines </> "clock.l4", "--contract", c, "--fixed-now", now]
          code `shouldBe` ExitFailure 2
          out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
          out `shouldNotSatisfy` ("time passes the deadline" `isInfixOf`)
          Output lcode lout _ <- runL4 bin ["lts", deadlines </> "clock.l4", "--contract", c, "--fixed-now", now]
          lcode `shouldBe` ExitSuccess
          lout `shouldSatisfy` (why `isInfixOf`)
          lout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    -- review of #1107: the reason called every such name "an input of the
    -- rule, or a name local to it"; it now says which it is
    it "locals.l4: a WITHIN that reads a WHERE name, or a value an event carried, is not worked out, and the reason names which" $ do
      let whereWhy = "the WITHIN reads `period`, a name the rule defines with WHERE or LET, which the contract has not worked out yet, so its deadline is not known here"
          eventWhy = "the WITHIN reads `n`, a value an event carried, which the contract has not worked out yet, so its deadline is not known here"
      Output code out _ <- explored "where local" "locals.l4"
      code `shouldBe` ExitFailure 2
      out `shouldSatisfy` (("time runs out on ship, in 1 state: " <> whereWhy) `isInfixOf`)
      Output lcode lout _ <- listed "where local" "locals.l4"
      lcode `shouldBe` ExitSuccess
      lout `shouldSatisfy` (whereWhy `isInfixOf`)
      Output tcode tout _ <- runL4 bin ["lts", deadlines </> "locals.l4"]
      tcode `shouldBe` ExitSuccess
      tout `shouldSatisfy` (("time runs out on Bob MUST ship \8212 " <> eventWhy) `isInfixOf`)
      tout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    it "ledger.l4: a rule that reads a ledger through another rule is not worked out" $ do
      let why = "the WITHIN reads `via another`, which reads a ledger, so it is worked out only in a run and its deadline is not known here"
      Output code out _ <- explored "through another" "ledger.l4"
      code `shouldBe` ExitFailure 2
      out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
      Output lcode lout _ <- listed "through another" "ledger.l4"
      lcode `shouldBe` ExitSuccess
      lout `shouldSatisfy` (why `isInfixOf`)

    it "slow.l4: working out a deadline stopped at a limit refuses the exploration (exit 1), and l4 lts lists it (exit 0)" $ do
      let stopped = "I stopped evaluating: it took more than 500 steps"
      Output code out err <- runL4 bin ["explore", deadlines </> "slow.l4", "--contract", "slow", "--max-steps", "500"]
      code `shouldBe` ExitFailure 1
      (out <> err) `shouldSatisfy` (("the evaluator stopped at a limit working out a deadline: " <> stopped) `isInfixOf`)
      Output lcode lout _ <- runL4 bin ["lts", deadlines </> "slow.l4", "--contract", "slow", "--max-steps", "500"]
      lcode `shouldBe` ExitSuccess
      lout `shouldSatisfy` (("time runs out on Alice MUST pay \8212 working out the WITHIN failed (" <> stopped) `isInfixOf`)
      lout `shouldSatisfy` ("Next deadline: not known here" `isInfixOf`)

    it "dated.l4: a WITHIN counted OF a named date is worked out as its literal twin is" $ do
      Output code out _ <- runL4 bin ["explore", deadlines </> "dated.l4"]
      code `shouldBe` ExitSuccess
      length (filter ("time passes the deadline 740176 (WAITUNTIL 740177)" `isInfixOf`) (lines out)) `shouldBe` 2
      Output lcode lout _ <- runL4 bin ["lts", deadlines </> "dated.l4"]
      lcode `shouldBe` ExitSuccess
      lout `shouldSatisfy` ("Alice MUST pay \8212 due by 740176 (WITHIN 14 OF `the kickoff`)" `isInfixOf`)
      lout `shouldSatisfy` ("Alice MUST pay \8212 due by 740176 (WITHIN 14 OF (YMD OF 2026, 7, 1))" `isInfixOf`)
      length (filter ("Next deadline: 740176 (Alice: pay)" `isInfixOf`) (lines lout)) `shouldBe` 2

  describe "a silent wrong graph that unstable has too (review of #1107)" $ do
    forM_ ["positional.l4", "named.l4", "genitive.l4", "wrapper.l4"] \ f ->
      it (f <> ": a constant that reads a ledger is keyed by its kept answer however it calls the reader") $ do
        Output code out _ <- runL4 bin ["explore", keptAnswers </> f, "--contract", "start"]
        code `shouldBe` ExitSuccess
        out `shouldSatisfy` ("start, explored from its outset at 0: 5 states, 8 transitions" `isInfixOf`)
        out `shouldSatisfy` ("  s0 -> s2  PARTY Bob DOES go OF skip" `isInfixOf`)
        out `shouldSatisfy` ("1 act passed over" `isInfixOf`)

    let readsItself = "--always never taken: `never taken` reads a ledger itself (a RECALL in it, or in a rule it names); a property is evaluated outside any run"
    forM_ ([ (propertyReaders </> f, "explore-property-readers/" <> f) | f <- ["positional.l4", "with.l4", "genitive.l4"] ]
           <> [ (imported </> "property.l4", "explore-imported/property.l4") ]) \ (path, f) ->
      it (f <> ": a property that reads a ledger through a rule is refused however it calls the rule") $ do
        Output code out err <- runL4 bin ["explore", path, "--contract", "start", "--always", "never taken"]
        code `shouldBe` ExitFailure 1
        (out <> err) `shouldSatisfy` (readsItself `isInfixOf`)
        (out <> err) `shouldNotSatisfy` ("holds in every one" `isInfixOf`)

    it "explore-imported/kept.l4: a constant that calls an imported ledger reader is keyed too" $ do
      Output code out _ <- runL4 bin ["explore", imported </> "kept.l4", "--contract", "start"]
      code `shouldBe` ExitSuccess
      out `shouldSatisfy` ("start, explored from its outset at 0: 5 states, 8 transitions" `isInfixOf`)
      out `shouldSatisfy` ("  s0 -> s2  PARTY Bob DOES go OF skip" `isInfixOf`)

    -- the expected graph is the one each path gives run alone: the file's one
    -- #TRACE is the skip path, whose buy l4 run passes over (WITHIN 9 left)
    forM_ [("hop1.l4", "one import away"), ("hop2.l4", "two imports away")] \ (f, away) ->
      it ("explore-imported/" <> f <> ": a constant that reads a ledger, " <> away <> ", is keyed, and each path forces its own") $
        forM_ [[], ["--fixed-now", "2025-01-31T15:45:30Z"]] \ now -> do
          Output code out _ <- runL4 bin (["explore", imported </> f, "--contract", "start"] <> now)
          code `shouldBe` ExitSuccess
          out `shouldSatisfy` ("start, explored from its outset at 0: 5 states, 8 transitions" `isInfixOf`)
          out `shouldSatisfy` ("  s0 -> s2  PARTY Bob DOES go OF skip" `isInfixOf`)
          out `shouldSatisfy` ("1 act passed over" `isInfixOf`)
          Output rcode rout _ <- runL4 bin (["run", imported </> f] <> now)
          rcode `shouldBe` ExitSuccess
          rout `shouldSatisfy` ("PARTY Bob MAY buy PROVIDED (NOT `taken now`) WITHIN 9 HENCE" `isInfixOf`)

    forM_
      [ ("ledger duty","the WITHIN reads `recorded period`, which reads a ledger, so it is worked out only in a run and its deadline is not known here")
      , ("clock duty", "the WITHIN reads `clocky`, which reads the clock (TODAY), so it is worked out only in a run and its deadline is not known here")
      , ("library clock duty", "the WITHIN reads `Today serial`, which reads the clock (TODAY), so it is worked out only in a run and its deadline is not known here")
      , ("env duty", "the WITHIN reads `env period`, which reads the world outside the file (ENV), so it is worked out only in a run and its deadline is not known here")
      , ("window duty", "the WITHIN reads `the window`, which reads `rate`, a section GIVEN of readers.l4, which a WITH can supply only inside that file, so it is worked out only in a run and its deadline is not known here")
      ] \ (contract, why) ->
        it ("explore-imported/deadlines.l4: " <> contract <> ", a WITHIN naming an imported rule that reads the run, is not worked out") $
          forM_ ["2025-01-31T15:45:30Z", "2025-02-04T15:45:30Z"] \ now -> do
            Output code out _ <- runL4 bin ["explore", imported </> "deadlines.l4", "--contract", contract, "--fixed-now", now]
            code `shouldBe` ExitFailure 2
            out `shouldSatisfy` (("time runs out on pay, in 1 state: " <> why) `isInfixOf`)
            Output lcode lout _ <- runL4 bin ["lts", imported </> "deadlines.l4", "--contract", contract, "--fixed-now", now]
            lcode `shouldBe` ExitSuccess
            lout `shouldSatisfy` (("time runs out on Alice MUST pay \8212 " <> why) `isInfixOf`)

    let sectionWhy = "the action reads `the price`, a section GIVEN, which a WITH can supply, so the act is known only in a run and the what-if cannot try it"
        ruleWhy = "the action reads `the total`, which reads `the price`, a section GIVEN, which a WITH can supply, so the act is known only in a run and the what-if cannot try it"
    forM_
      [ ("the deal", "PARTY Alice MUST pay `the price`", "pay OF `the price`", sectionWhy)
      , ("the deal through a rule", "PARTY Alice MUST pay (`the total` OF `the price`)", "pay OF (`the total` OF `the price`)", ruleWhy)
      , ("the plain deal", "PARTY Alice MUST pay `the price`", "pay OF `the price`", sectionWhy)
      ] \ (contract, residual, act, why) ->
        it ("explore-actions/section-given.l4: " <> contract <> ", an act reading a section GIVEN, is untried and not replayed at its default") $ do
          Output code out _ <- runL4 bin ["explore", actions </> "section-given.l4", "--contract", contract]
          code `shouldBe` ExitFailure 2
          out `shouldSatisfy` (("UNTRIED 1: " <> residual <> " (" <> why <> ")") `isInfixOf`)
          out `shouldSatisfy` ("0 acts passed over" `isInfixOf`)
          out `shouldNotSatisfy` ("Internal error" `isInfixOf`)
          Output lcode lout _ <- runL4 bin ["lts", actions </> "section-given.l4", "--contract", contract]
          lcode `shouldBe` ExitSuccess
          lout `shouldSatisfy` (("Alice does " <> act <> " \8212 " <> why) `isInfixOf`)
          lout `shouldNotSatisfy` ("it is not the act awaited" `isInfixOf`)
          lout `shouldNotSatisfy` ("Internal error" `isInfixOf`)

    -- the importing file cannot supply an imported section GIVEN, so the
    -- reason says whose it is
    forM_
      [ ("direct", "PARTY Alice MUST pay rate", "the action reads `rate`, a section GIVEN of readers.l4, which a WITH can supply only inside that file, so the act is known only in a run and the what-if cannot try it")
      , ("via rule", "PARTY Alice MUST pay `the window`", "the action reads `the window`, which reads `rate`, a section GIVEN of readers.l4, which a WITH can supply only inside that file, so the act is known only in a run and the what-if cannot try it")
      ] \ (contract, residual, why) ->
        it ("explore-imported/section-act.l4: " <> contract <> ", an act reading an imported section GIVEN, is untried, and the reason names its file") $ do
          Output code out _ <- runL4 bin ["explore", imported </> "section-act.l4", "--contract", contract]
          code `shouldBe` ExitFailure 2
          out `shouldSatisfy` (("UNTRIED 1: " <> residual <> " (" <> why <> ")") `isInfixOf`)
          out `shouldNotSatisfy` ("Internal error" `isInfixOf`)

    forM_
      [ ("applied", "PARTY Alice MUST pay (f OF 3)", "pay OF (f OF 3)", "the action applies `f`, a function local to the rule, which the what-if cannot supply")
      , ("where positional", "PARTY Alice MUST pay (twice OF 3)", "pay OF (twice OF 3)", "the action applies `twice`, a function local to the rule, which the what-if cannot supply")
      , ("where named", "PARTY Alice MUST pay (twice WITH y IS 3)", "pay OF (twice WITH y IS 3)", "the action applies `twice`, a function local to the rule, which the what-if cannot supply")
      , ("plain", "PARTY Alice MUST pay n", "pay OF n", "the action binds `n`, which the what-if cannot choose")
      , ("where plain", "PARTY Alice MUST pay six", "pay OF six", "the action binds `six`, which the what-if cannot choose")
      ] \ (contract, residual, act, why) ->
        it ("explore-actions/local-function.l4: " <> contract <> ", an act naming a local, is untried with the what-if's own reason") $ do
          Output code out _ <- runL4 bin ["explore", actions </> "local-function.l4", "--contract", contract]
          code `shouldBe` ExitFailure 2
          out `shouldSatisfy` (("UNTRIED 1: " <> residual <> " (" <> why <> ")") `isInfixOf`)
          out `shouldNotSatisfy` ("Internal error" `isInfixOf`)
          Output lcode lout _ <- runL4 bin ["lts", actions </> "local-function.l4", "--contract", contract]
          lcode `shouldBe` ExitSuccess
          lout `shouldSatisfy` (("Alice does " <> act <> " \8212 " <> why) `isInfixOf`)
          lout `shouldNotSatisfy` ("Internal error" `isInfixOf`)

    it "explore-actions/section-party.l4: a party a section GIVEN names, supplied by a WITH, still explores to the act the run takes" $ do
      Output code out _ <- runL4 bin ["explore", actions </> "section-party.l4", "--contract", "the deal"]
      code `shouldBe` ExitSuccess
      out `shouldSatisfy` ("the deal, explored from its outset at 0: 3 states, 4 transitions" `isInfixOf`)
      out `shouldSatisfy` ("  s0 -> s1  PARTY Bob DOES pay" `isInfixOf`)
  where
    liveness =
      [ "--eventually", "Alice has bought or stopped"
      , "--eventually", "one dinner is bought", "--if-always", "the ledger is open"
      , "--eventually", "Bob has bought" ]

-- | An exploration's text with what spells the deadline left out: the
-- contract's name on the first line, and the residuals, which print the
-- WITHIN as written.
exploreTwin :: String -> [String]
exploreTwin out = case lines out of
  (h : rest) -> dropWhile (/= ',') h : filter (not . residualLine) rest
  []         -> []
  where
    residualLine = \ case
      ' ' : ' ' : 'r' : d : _ -> isDigit d
      _                       -> False

-- | A list's text with what spells the deadline left out: the header, which
-- names the contract, and what follows the due date on an owed line.
ltsTwin :: String -> [String]
ltsTwin out = map dueLine (drop 1 (lines out))
  where
    dueLine l = case breakOn "\8212 due by " l of
      Just (pre, post) -> pre <> "\8212 due by " <> takeWhile (/= ' ') post
      Nothing -> case breakOn "\8212 due " l of
        Just (pre, _) -> pre <> "\8212 due"
        Nothing       -> l
    breakOn pat s = case [ (take i s, drop (i + length pat) s) | (i, t) <- zip [0 :: Int ..] (tails s), pat `isPrefixOf` t ] of
      (x : _) -> Just x
      []      -> Nothing
