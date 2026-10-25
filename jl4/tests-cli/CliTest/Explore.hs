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

import Data.List (isInfixOf, isPrefixOf, sort)
import System.Directory (copyFile, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import CliTest.Common

brief :: FilePath
brief = "examples" </> "explore" </> "brief"

fixtures :: [FilePath]
fixtures = [ brief </> f | f <- ["d1-naive.l4", "d2-reread.l4", "d3-atomic.l4", "refused-number.l4", "properties.l4"] ]

-- | The acceptance run of the fixtures' README: the clock bounded at
-- closing, the cells the properties read kept.
acceptance :: [String]
acceptance =
  [ "--until", "75600"
  , "--keep", "open at acceptance", "--keep", "dinners bought", "--keep", "dinners cancelled"
  , "--keep", "dinner status record", "--keep-latest", "belief", "--keep-latest", "plan"
  ]

-- | The brief's safety and reachability properties, P1 to P4.
safety :: [String]
safety =
  [ "--until", "75600"
  , "--always", "every dinner was accepted while open"
  , "--always", "at most one dinner is bought"
  , "--reachable", "Alice's belief is stale"
  , "--stays", "one dinner is bought"
  ]

-- | The printed #TRACE that follows the comment line naming the property:
-- the comment, the #TRACE line and its indented events.
traceAfter :: String -> String -> [String]
traceAfter property out =
  case dropWhile (not . (("-- `" <> property <> "`") `isPrefixOf`)) (lines out) of
    comment : rest -> comment : takeWhile (\ l -> "#TRACE" `isPrefixOf` l || "    " `isPrefixOf` l) rest
    [] -> []

lastLine :: String -> String
lastLine = \ s -> case lines s of
  [] -> ""
  ls -> last ls

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
  where
    liveness =
      [ "--eventually", "Alice has bought or stopped"
      , "--eventually", "one dinner is bought", "--if-always", "the ledger is open"
      , "--eventually", "Bob has bought" ]
