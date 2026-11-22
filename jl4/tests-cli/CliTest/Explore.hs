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
import Data.List (isInfixOf, isPrefixOf, sort)
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

fixtures :: [FilePath]
fixtures =
  [ brief </> f | f <- ["d1-naive.l4", "d2-reread.l4", "d3-atomic.l4", "refused-number.l4", "properties.l4"] ]
  <> [ instants </> f | f <- ["clocks.l4", "window.l4", "half.l4", "adjacent.l4", "open.l4", "flip3.l4", "room.l4", "lapse.l4", "merged.l4"] ]

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
      lastLine sout `shouldSatisfy` ("UNTRIED 1: ties through chains of acts, for " `isInfixOf`)
      lastLine sout `shouldSatisfy` ("--chains tries them" `isInfixOf`)
      lastLine sout `shouldSatisfy` (not . ("nothing untried" `isInfixOf`))
      Output ccode csout _ <- runL4 bin ["explore", instants </> "room.l4", "--chains"]
      ccode `shouldBe` ExitSuccess
      lastLine csout `shouldSatisfy` ("frontier exhausted; nothing refused; nothing untried" `isInfixOf`)
      -- the chain made the graph larger, not smaller
      let states l = read (takeWhile (/= ' ') (drop (length ("Coverage: " :: String)) l)) :: Int
      states (lastLine csout) `shouldSatisfy` (> states (lastLine sout))

    it "clocks.l4: no chain, so nothing is said about chains" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "clocks.l4"]
      code `shouldBe` ExitSuccess
      lastLine sout `shouldSatisfy` (not . ("chains" `isInfixOf`))

    it "lapse.l4: a deadline started by a lapse is named by default (exit 2), and --chains holds the positions the evaluator reaches by it" $ do
      Output code sout _ <- runL4 bin ["explore", instants </> "lapse.l4"]
      code `shouldBe` ExitFailure 2
      lastLine sout `shouldSatisfy` ("UNTRIED 1: ties through chains of acts, for PARTY P DOES a" `isInfixOf`)
      Output ccode csout _ <- runL4 bin ["explore", instants </> "lapse.l4", "--chains"]
      ccode `shouldBe` ExitSuccess
      lastLine csout `shouldSatisfy` ("nothing untried" `isInfixOf`)
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
      let out = filter (/= '\r') sout
      out `shouldSatisfy` ("nothing happens by 3 (the clock reaches 4) \8594 P is in breach\n" `isInfixOf`)
      out `shouldSatisfy` (not . ("3.5" `isInfixOf`))
  where
    liveness =
      [ "--eventually", "Alice has bought or stopped"
      , "--eventually", "one dinner is bought", "--if-always", "the ledger is open"
      , "--eventually", "Bob has bought" ]
