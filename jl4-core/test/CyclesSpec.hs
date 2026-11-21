{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The cycle report (#1075, layer 2): what it finds and what it shows ends.
--
-- Each obligation fixture has a run-time measurement behind its expected
-- verdict (2026-11-20, one self-loop per kind of continuation; the numbers are
-- in Note [What makes a lap wait] in "L4.Cycles"). The ones that must NOT come
-- out proved are the shapes that stalled, ran out of memory, or ran on with
-- nothing to stop them.
module CyclesSpec (spec) where

import Data.Foldable (for_)
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import System.Directory (listDirectory)
import System.Environment (lookupEnv)
import System.FilePath (takeBaseName, takeDirectory, takeExtension, takeFileName, (</>))
import Test.Hspec

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), VFS, checkWithImports, emptyVFS, vfsFromList)
import L4.Cycles
import L4.Syntax (DeonticModal (..), Module (..), Resolved)
import L4.TypeCheck (applyFinalSubstitution)
import L4.TypeCheck.Types (CheckErrorWithContext, EntityInfo, Severity (..), Substitution, severity)

spec :: Spec
spec = describe "cycle report (#1075 layer 2)" do
  -- A probe for checking the report by hand: @JL4_CYCLES_PROBE=<file>@ prints
  -- one line per cycle the report finds in that file. Not a test. The other
  -- @.l4@ files beside it can be imported by their base names.
  probe <- runIO (lookupEnv "JL4_CYCLES_PROBE")
  for_ probe \ file -> describe "probe" $ it file do
    let dir = takeDirectory file
    siblings <- filter (\ f -> takeExtension f == ".l4" && f /= takeFileName file) <$> listDirectory dir
    vfs <- vfsFromList <$> traverse (\ f -> (,) (Text.pack (takeBaseName f)) <$> Text.readFile (dir </> f)) siblings
    fs <- findingsIn vfs =<< Text.readFile file
    for_ fs \ f ->
      putStrLn (Text.unpack (Text.unwords
        ["CYCLE", findingClass f, Text.intercalate "," [n | (n, _) <- f.members], Text.pack (show f.verdict)]))
    putStrLn ("CYCLES " <> show (length fs))

  describe "functions" do
    it "proves a fold on the tail of a list" $
      classes (people <> "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\ntotal xs MEANS\n  CONSIDER xs\n    WHEN EMPTY THEN 0\n    WHEN y FOLLOWED BY ys THEN y PLUS total ys")
        `shouldReturn` ["function:proved-structural"]

    it "proves a countdown tested from below" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\ndown n MEANS IF n GREATER THAN 0 THEN down (n MINUS 1) ELSE 0")
        `shouldReturn` ["function:proved-countdown"]

    it "does not prove a countdown tested only for equality" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\ndown n MEANS IF n EQUALS 0 THEN 0 ELSE down (n MINUS 1)")
        `shouldReturn` ["function:unproved-self"]

    it "does not prove a search that counts up with no bound" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nsearch n MEANS IF n TIMES n GREATER THAN 50 THEN n ELSE search (n PLUS 1)")
        `shouldReturn` ["function:unproved-self"]

    it "does not try two functions that call each other" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A BOOLEAN\nev n MEANS IF n EQUALS 0 THEN TRUE ELSE od (n MINUS 1)\n\nGIVEN n IS A NUMBER GIVETH A BOOLEAN\nod n MEANS IF n EQUALS 0 THEN FALSE ELSE ev (n MINUS 1)")
        `shouldReturn` ["function:unproved-mutual"]

    it "finds a recursive WHERE definition as its own node" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS g n\n  WHERE\n    GIVEN k IS A NUMBER GIVETH A NUMBER\n    g k MEANS IF k GREATER THAN 0 THEN g (k MINUS 1) ELSE 0")
        `shouldReturn` ["function:proved-countdown"]

    it "reports nothing for a module with no cycle" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS n PLUS 1\n\nGIVEN n IS A NUMBER GIVETH A NUMBER\ng n MEANS f (f n)")
        `shouldReturn` []

  describe "obligations that wait each lap" do
    it "proves a HENCE that names its own rule (an event each lap)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 30 HENCE x")
        `shouldReturn` ["obligation:proved-waits"]

    it "proves a LEST that names its own rule under a positive WITHIN" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 30 LEST x")
        `shouldReturn` ["obligation:proved-waits"]

    it "proves a LEST with no deadline, which never runs" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick LEST x")
        `shouldReturn` ["obligation:proved-waits"]

    it "proves a MUST NOT whose LEST names its own rule (the breaking event is consumed)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST NOT tick LEST x")
        `shouldReturn` ["obligation:proved-waits"]

    it "proves a lap through an inner obligation's positive WITHIN OF THE DEADLINE" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x)")
        `shouldReturn` ["obligation:proved-waits"]

  describe "obligations that wait but multiply" do
    it "flags a LEST that starts two copies of its own rule" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (x RAND x)")
        `shouldReturn` ["obligation:proved-waits+multiplies"]

    it "flags the #1075 shape" $
      classes (people <> "GIVETH A DEONTIC Person Action\nw1 MEANS PARTY Alice MUST tick WITHIN 2 LEST (w3 RAND w1)\n\nGIVETH A DEONTIC Person Action\nw3 MEANS PARTY Bob MUST tick WITHIN 3 LEST w1")
        `shouldReturn` ["obligation:proved-waits+multiplies"]

    it "flags an UPON EACH HENCE that names its own rule, one copy per member" $
      classes (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN trio MUST Sign t WITHIN 5 UPON EACH HENCE x")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "flags a LEST that hands its own rule to a helper that uses it twice" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action GIVETH A DEONTIC Person Action\ntwice k MEANS k RAND k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (twice x)")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "but not a LEST that hands its own rule to a helper that uses it once" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action GIVETH A DEONTIC Person Action\nonce k MEANS k RAND (PARTY Bob MUST tick)\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (once x)")
        `shouldReturn` ["obligation:proved-waits"]

    it "proves a fold over a list whose element type is a parameter" $
      classes "GIVEN a IS A TYPE\n      x IS AN a\n      list IS A LIST OF a\nGIVETH A NUMBER\ncount x list MEANS\n  CONSIDER list\n    WHEN EMPTY THEN 0\n    WHEN y FOLLOWED BY ys THEN 1 PLUS count x ys"
        `shouldReturn` ["function:proved-structural"]

    it "proves recursion on a constructor's field" $
      classes "DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\n\nGIVEN m IS A Nat\n      n IS A Nat\nGIVETH A Nat\nadd m n MEANS\n  CONSIDER m\n  WHEN Zero THEN n\n  WHEN Suc p THEN Suc OF add p n"
        `shouldReturn` ["function:proved-structural"]

    it "but not recursion on a name for the whole value" $
      classes "DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\n\nGIVEN m IS A Nat\nGIVETH A Nat\nspin m MEANS\n  CONSIDER m\n  WHEN Zero THEN Zero\n  WHEN other THEN spin other"
        `shouldReturn` ["function:unproved-self"]

    it "proves a count up to a bound passed on unchanged" $
      classes "GIVEN low IS A NUMBER\n      high IS A NUMBER\nGIVETH A LIST OF NUMBER\nrange low high MEANS\n  IF low > high\n    THEN EMPTY\n    ELSE low FOLLOWED BY range (low + 1) high"
        `shouldReturn` ["function:proved-countdown"]

    it "but not up to a bound that moves with it" $
      classes "GIVEN low IS A NUMBER\n      high IS A NUMBER\nGIVETH A LIST OF NUMBER\nrange low high MEANS\n  IF low > high\n    THEN EMPTY\n    ELSE low FOLLOWED BY range (low + 1) (high + 1)"
        `shouldReturn` ["function:unproved-self"]

    it "flags a countdown that doubles" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nb n MEANS IF n GREATER THAN 0 THEN b (n MINUS 1) RAND b (n MINUS 1) ELSE PARTY Alice MUST tick")
        `shouldReturn` ["function:proved-countdown+fans"]

  describe "obligations that must NOT come out proved" do
    it "WITHIN 0 LEST its own rule (stalled at run time)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST x")
        `shouldReturn` ["obligation:no-time"]

    it "MUST NOT WITHIN 0 HENCE its own rule (stalled at run time)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST NOT tick WITHIN 0 HENCE x")
        `shouldReturn` ["obligation:no-time"]

    it "WITHIN 1 OF a fixed instant (stalled at run time)" $
      verdicts (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST x")
        `shouldReturn` [Unproved (Stalled [AnchoredAtInstant])]

    it "a WITHIN that halves each lap (ran out of memory at run time)" $
      verdicts (people <> "GIVEN d IS A NUMBER GIVETH A DEONTIC Person Action\nz d MEANS PARTY Alice MUST tick WITHIN d LEST z (d DIVIDED BY 2)")
        `shouldReturn` [Unproved (Stalled [WithinNotLiteral])]

    it "a RECORD whose HENCE recurs (ran out of memory at run time)" $
      verdicts (people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nr n MEANS RECORD `a` IS n HENCE r (n PLUS 1)")
        `shouldReturn` [Unproved (Stalled [RecordHence])]

    it "T7: a barrier HENCE over an empty roll (stopped by frame depth at run time)" $
      verdicts (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN nobody MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE x")
        `shouldReturn` [Unproved (Stalled [BarrierMayBeEmpty])]

    it "T6: the same, doubling (nothing stops it at run time)" $
      classes (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN nobody MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE (x RAND x)")
        `shouldReturn` ["obligation:unproved-stall+multiplies"]

    it "a barrier over a roll written out, but filtered (the filter may leave it empty)" $
      verdicts (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN trio WHO t EQUALS Tenant OF \"Nobody\" MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE x")
        `shouldReturn` [Unproved (Stalled [BarrierMayBeEmpty])]

    it "a barrier whose cast built none of the roll's members" $
      verdicts (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Landlord t IN trio MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE x")
        `shouldReturn` [Unproved (Stalled [BarrierMayBeEmpty])]

    it "but a barrier HENCE over a roll written out with members waits for their events" $
      classes (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN trio MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE x")
        `shouldReturn` ["obligation:proved-waits"]

  -- The adversarial pass of 2026-11-20 (#1075 layer 2). Each fixture whose
  -- name does not start "but" or "and" came out proved, or proved without
  -- "+multiplies" (the fan count, now "+fans"), before its fix, and stalled, overflowed or grew at run time
  -- on the layer-1 binary; the "but" and "and" fixtures are controls that
  -- ran to a value.
  describe "deadlines that do not move with the arming (adversarial pass)" do
    it "a bare WITHIN beside AFTER a fixed instant (stalled at run time)" $
      verdicts (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick AFTER 2 OF 0 WITHIN 1 LEST x")
        `shouldReturn` [Unproved (Stalled [AnchoredAtInstant])]

    it "a bare WITHIN beside an AFTER that is not a number written out (stalled at run time at AFTER -5)" $
      verdicts (people <> "back MEANS 0 MINUS 5\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick AFTER back WITHIN 1 LEST x")
        `shouldReturn` [Unproved (Stalled [OpensNotLiteral])]

    it "a MUST NOT's HENCE beside AFTER a fixed instant (stalled at run time)" $
      verdicts (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST NOT tick AFTER 2 OF 0 WITHIN 1 HENCE x")
        `shouldReturn` [Unproved (Stalled [AnchoredAtInstant])]

    it "WITHIN 1 OF THE DEADLINE of a deadline at a fixed instant (stalled at run time)" $
      verdicts (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x)")
        `shouldReturn` [Unproved (Stalled [AnchoredAtInstant])]

    it "a cure period WITHIN 5 OF THE DEADLINE of a BEFORE date (stalled at run time)" $
      verdicts ("IMPORT daydate\n" <> people <> "DECLARE Money IS ONE OF pay\nGIVETH A DEONTIC Person Money\nrent MEANS\n  PARTY Alice MUST pay BEFORE (YMD 2026 6 10)\n  LEST (PARTY Alice MUST pay WITHIN 5 OF THE DEADLINE LEST rent)")
        `shouldReturn` [Unproved (Stalled [BeforeDate])]

    it "an EVERY … MUST NOT whose ONCE line says WITHIN 0 (stack overflow at run time)" $
      classes (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN trio MUST NOT Sign t WITHIN 5 ONCE ALL HAVE WITHIN 0 LEST x")
        `shouldReturn` ["obligation:no-time"]

    it "but a bare WITHIN beside AFTER a positive number still waits" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick AFTER 1 WITHIN 1 LEST x")
        `shouldReturn` ["obligation:proved-waits"]

    it "and an EVERY … MUST NOT whose ONCE line has no deadline waits for its breaking event" $
      classes (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN trio MUST NOT Sign t WITHIN 5 ONCE ALL HAVE LEST x")
        `shouldReturn` ["obligation:proved-waits"]

  describe "operators are recognised by what they resolve to (adversarial pass)" $
    it "does not read the user's own __MINUS__ and __GT__ as MINUS and GREATER THAN (stack overflow at run time)" $
      classes "DECLARE Box HAS v IS A NUMBER\n\nGIVEN b IS A Box\n      k IS A NUMBER\nGIVETH A Box\n`__MINUS__` b k MEANS b\n\nGIVEN b IS A Box\n      k IS A NUMBER\nGIVETH A BOOLEAN\n`__GT__` b k MEANS TRUE\n\nGIVEN n IS A Box\nGIVETH A NUMBER\nf n MEANS IF `__GT__` n 0 THEN f (`__MINUS__` n 1) ELSE 0"
        `shouldReturn` ["function:unproved-self"]

  describe "work that multiplies (adversarial pass)" do
    it "a helper that uses a WHERE name for its parameter twice" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\ntwice k MEANS y RAND y\n  WHERE\n    y MEANS k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (twice x)")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a helper that uses a LET name for its parameter twice" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\ntwice k MEANS LET y IS k IN y RAND y\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (twice x)")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a CONSIDER pattern that names its own rule and uses the name twice" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST\n            CONSIDER (LIST x)\n              WHEN y FOLLOWED BY ys THEN y RAND y\n              WHEN EMPTY THEN FULFILLED")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "an obligation handed round in a parameter that each lap doubles" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nx k MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (k RAND k)))")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a countdown that returns an obligation and hands it to a helper that uses it twice" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\ntwice k MEANS k RAND k\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nb n MEANS\n  IF n GREATER THAN 0\n  THEN twice (b (n MINUS 1))\n  ELSE PARTY Alice MUST tick")
        `shouldReturn` ["function:proved-countdown+fans"]

    it "a countdown that calls itself inside a function mapped over a list" $
      classes "IMPORT prelude\n\nGIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS IF n GREATER THAN 0 THEN sum (map (GIVEN i YIELD f (n MINUS 1)) (LIST 1, 2, 3)) ELSE 1"
        `shouldReturn` ["function:proved-countdown+fans"]

    it "the same countdown with no GIVETH written" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\ntwice k MEANS k RAND k\n\nGIVEN n IS A NUMBER\nb n MEANS\n  IF n GREATER THAN 0\n  THEN twice (b (n MINUS 1))\n  ELSE PARTY Alice MUST tick")
        `shouldReturn` ["function:proved-countdown+fans"]

    it "the doubling parameter with no type written" $
      classes (people <> "x k MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (k RAND k)))")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "but not a list of obligations built with FOLLOWED BY" $
      classes (people <> "GIVEN n IS A NUMBER\nGIVETH A LIST OF DEONTIC Person Action\nmk n MEANS IF n GREATER THAN 0 THEN (PARTY Alice MUST tick) FOLLOWED BY mk (n MINUS 1) ELSE EMPTY")
        `shouldReturn` ["function:proved-countdown"]

    it "a cycle whose laps start another cycle" $
      classes (people <> "GIVETH A DEONTIC Person Action\nmonthly MEANS PARTY Alice MUST tick WITHIN 1 LEST (monthly RAND weekly)\n\nGIVETH A DEONTIC Person Action\nweekly MEANS PARTY Bob MUST tick WITHIN 1 LEST weekly")
        `shouldReturn` ["obligation:proved-waits", "obligation:proved-waits+nests"]

    it "but not two cycles that never start each other" $
      classes (people <> "GIVETH A DEONTIC Person Action\nmonthly MEANS PARTY Alice MUST tick WITHIN 1 LEST monthly\n\nGIVETH A DEONTIC Person Action\nweekly MEANS PARTY Bob MUST tick WITHIN 1 LEST weekly")
        `shouldReturn` ["obligation:proved-waits", "obligation:proved-waits"]

    it "and not a WHERE name used once" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nonce k MEANS y RAND (PARTY Bob MUST tick)\n  WHERE\n    y MEANS k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (once x)")
        `shouldReturn` ["obligation:proved-waits"]

  describe "cycles through a computed field (adversarial pass)" $
    it "finds a function that projects the computed field that calls it (heap exhausted at run time)" $
      classes "DECLARE Box HAS\n    n    IS A NUMBER\n    deep IS A NUMBER\n        MEANS bad n\n\nGIVEN k IS A NUMBER\nGIVETH A NUMBER\nbad k MEANS (Box WITH n IS k PLUS 1)'s deep"
        `shouldReturn` ["function:unproved-mutual"]

  -- THE DEADLINE names the obligation that hands the value on, not the one
  -- written around it (Note [What makes a lap wait]). Each "stalled" fixture
  -- was stopped by the stall guard at run time, and each control ran to a
  -- value (2026-11-20, second adversarial pass).
  describe "who hands an obligation on (second adversarial pass)" do
    it "OF THE DEADLINE in an obligation handed to a helper whose deadline is fixed (stalled at run time)" $
      classes (people <> wrapFixed <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (wrap (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))")
        `shouldReturn` ["obligation:unproved-stall"]

    it "the same, handed over by name (stalled at run time)" $
      classes (people <> wrapFixed <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (wrap WITH k IS (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))")
        `shouldReturn` ["obligation:unproved-stall"]

    it "the same through AFTER … OF THE DEADLINE (stalled at run time)" $
      classes (people <> wrapFixed <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (wrap (PARTY Alice MUST tick AFTER 1 OF THE DEADLINE WITHIN 1 LEST x))")
        `shouldReturn` ["obligation:unproved-stall"]

    it "the same under a helper whose deadline falls before its own arming (stalled at run time)" $
      classes (people <> "back MEANS 0 MINUS 5\n\nGIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nwrap k MEANS PARTY Bob MUST tick WITHIN back LEST k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (wrap (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))")
        `shouldReturn` ["obligation:unproved-stall"]

    -- the "+fans" counts the scrutinee and the name it binds both: high,
    -- not low (its run armed once per lap)
    it "the same in a CONSIDER scrutinee that an obligation with a fixed deadline hands on (stalled at run time)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST\n            CONSIDER (LIST (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))\n              WHEN k FOLLOWED BY ks THEN PARTY Bob MUST tick WITHIN 1 OF 0 LEST k\n              WHEN EMPTY THEN FULFILLED")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "and a hand-off through a helper is not shown either way, even where it ran to a value" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nwrap k MEANS PARTY Bob MUST tick WITHIN 1 LEST k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (wrap (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))")
        `shouldReturn` ["obligation:unproved-stall"]

    it "but the continuation's own result keeps it: IF and CONSIDER branches, RAND and ROR operands, WHERE and LET bodies (each ran to a value)" $
      for_
        [ "GIVEN b IS A BOOLEAN\nGIVETH A DEONTIC Person Action\ny b MEANS PARTY Alice MUST tick WITHIN 0 LEST (IF b THEN PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST y b ELSE FULFILLED)"
        , "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\ny n MEANS\n  PARTY Alice MUST tick WITHIN 0\n  LEST\n    CONSIDER n\n      WHEN 0 THEN FULFILLED\n      OTHERWISE PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST y n"
        , "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST ((PARTY Bob MAY tick) RAND (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))"
        , "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST ((PARTY Bob MUST never WITHIN 1000) ROR (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))"
        , "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x WHERE z MEANS 1)"
        , "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST (LET z IS 1 IN PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x)"
        ] \ body -> classes (people <> body) `shouldReturn` ["obligation:proved-waits"]

  describe "EVALTRACE runs on a trace of its own (second adversarial pass)" do
    it "a LEST that runs its own rule under EVALTRACE (stopped by frame depth at run time)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (EVALTRACE x 0 (LIST (`WAIT UNTIL` 5)))")
        `shouldReturn` ["obligation:unproved-stall"]

    it "a rule that is the EVALTRACE of a contract whose LEST is the rule (loop check at run time)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS EVALTRACE (PARTY Alice MUST tick WITHIN 1 LEST x) 0 (LIST (`WAIT UNTIL` 5))")
        `shouldReturn` ["obligation:unproved-stall"]

    -- third adversarial pass: the wait need not be on the edge into the
    -- EVALTRACE, nor the EVALTRACE written where the lap passes
    it "the wait in another member of the cycle (stopped by frame depth at run time)" $
      classes (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS EVALTRACE (w n) 0 (LIST (`WAIT UNTIL` 5))\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nw n MEANS PARTY Bob MUST tick WITHIN 1 LEST x n")
        `shouldReturn` ["obligation:unproved-stall"]

    it "an event continuation whose event each run supplies again (stopped by frame depth at run time)" $
      classes (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS EVALTRACE (k n) 0 (LIST (EVENT Bob tick 0))\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nk n MEANS PARTY Bob MUST tick WITHIN 5 HENCE x n")
        `shouldReturn` ["obligation:unproved-stall"]

    it "EVALTRACE inside a helper (stopped by frame depth at run time)" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nfresh k MEANS EVALTRACE k 0 (LIST (`WAIT UNTIL` 5))\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (fresh (x n))")
        `shouldReturn` ["obligation:unproved-stall"]

    -- "+fans": the helper hands the obligation to a function it does
    -- not know, which counts as unbounded (Note [Fan-out])
    it "EVALTRACE handed to a helper as a function (stopped by frame depth at run time)" $
      classes (people <> runHelper <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (run EVALTRACE (x n))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "and a helper that applies a function it is given is not shown either way, even where it ran to a value" $
      classes (people <> runHelper <> "GIVEN k IS A DEONTIC Person Action\n      t IS A NUMBER\n      es IS A LIST OF EVENT Person Action\nGIVETH A DEONTIC Person Action\nkeep k t es MEANS k\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (run keep (x n))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a function parameter that only gives an obligation, supplied with a definition that EVALTRACEs the cycle (stopped by frame depth at run time)" $
      classes (people <> "GIVEN f IS A FUNCTION FROM NUMBER TO DEONTIC Person Action\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx f n MEANS PARTY Alice MUST tick WITHIN 1 LEST ((f n) RAND (x f (n PLUS 1)))\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\ng n MEANS EVALTRACE (x g n) 0 (LIST (`WAIT UNTIL` 5))")
        `shouldReturn` ["function:unproved-self+fans+nests", "obligation:unproved-stall"]

    -- the entity table holds the imported module's names, so a helper from
    -- another module is judged by its declared type; "+fans" because
    -- an obligation handed to a helper not the module's own counts as
    -- unbounded (Note [Fan-out])
    it "EVALTRACE inside a helper from another module" $
      classesIn importedHelpers "IMPORT helpers\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (fresh (x n))"
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "and a helper from another module that takes an obligation is not shown either way" $
      classesIn importedHelpers "IMPORT helpers\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (plain (x n))"
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "but one that takes anything cannot run it as a contract, so the wait still proves it" $
      classesIn importedHelpers "IMPORT helpers\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (same (x n))"
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "and a synonym for DEONTIC from another module is seen through" $
      classesIn importedHelpers "IMPORT helpers\n\nGIVEN k IS A Duty\nGIVETH A Duty\nx k MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (k RAND k)))"
        `shouldReturn` ["obligation:proved-waits+fans"]

    -- fourth adversarial pass: a function value whose type hides the
    -- function (each stopped by frame depth at run time)
    it "a function parameter typed by a synonym, supplied with EVALTRACE" $
      classes (people <> "DECLARE Runner IS FUNCTION FROM DEONTIC Person Action AND NUMBER AND LIST OF EVENT Person Action TO DEONTIC Person Action\n\nGIVEN f IS A Runner\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx f n MEANS PARTY Alice MUST tick WITHIN 1 LEST (f (x f (n PLUS 1)) 0 (LIST (`WAIT UNTIL` 5)))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a function carried in a pair" $
      classes ("IMPORT prelude\n" <> people <> "GIVEN p IS A PAIR OF (FUNCTION FROM DEONTIC Person Action TO DEONTIC Person Action), NUMBER\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx p n MEANS PARTY Alice MUST tick WITHIN 1 LEST (maybe (p's fst) FULFILLED (JUST (x p (n PLUS 1))))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a function carried in a record whose field is a type variable" $
      classes ("IMPORT prelude\n" <> people <> "DECLARE Box a HAS v IS AN a\n\nGIVEN b IS A Box (FUNCTION FROM DEONTIC Person Action TO DEONTIC Person Action)\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx b n MEANS PARTY Alice MUST tick WITHIN 1 LEST (maybe (b's v) FULFILLED (JUST (x b (n PLUS 1))))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a function from another module whose type is a synonym" $
      classesIn importedHelpers "IMPORT helpers\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (runner (x n))"
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a function from another module that returns a function taking an obligation" $
      classesIn importedHelpers "IMPORT helpers\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (go (x n))\n  WHERE\n    go MEANS runAt 0"
        `shouldReturn` ["obligation:unproved-stall+fans"]

    -- coarse on purpose: the module names EVALTRACE, so no cycle in it is
    -- proved by waiting, though this one would end
    it "and a module that names EVALTRACE anywhere proves no cycle by waiting" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nonce k MEANS EVALTRACE k 0 (LIST)\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST x n")
        `shouldReturn` ["obligation:unproved-stall"]

    it "but a countdown through EVALTRACE is still proved: the function checks do not use time" $
      classes (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nc n MEANS IF n GREATER THAN 0 THEN EVALTRACE (c (n MINUS 1)) 0 (LIST) ELSE FULFILLED")
        `shouldReturn` ["function:proved-countdown"]

    -- each stopped by frame depth at run time (2026-11-21 attack round,
    -- countdown p13, p14, p15, p18): the countdown proves the self-call, but
    -- the lap through the HENCE starts a new run at instant 0
    it "and a countdown beside a lap that EVALTRACE starts again is not proved" $
      classes (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nc n MEANS\n  IF n > 0\n  THEN c (n MINUS 1)\n  ELSE EVALTRACE (PARTY Alice MUST tick WITHIN 5 HENCE c 1) 0 (LIST EVENT Alice tick 1)")
        `shouldReturn` ["obligation:unproved-stall"]

    it "nor a walk down a list beside such a lap" $
      classes (people <> "GIVEN xs IS A LIST OF NUMBER\nGIVETH A DEONTIC Person Action\nc xs MEANS\n  CONSIDER xs\n  WHEN y FOLLOWED BY ys THEN c ys\n  WHEN EMPTY THEN EVALTRACE (PARTY Alice MUST tick WITHIN 5 HENCE c (LIST 1)) 0 (LIST EVENT Alice tick 1)")
        `shouldReturn` ["obligation:unproved-stall"]

    it "nor when the EVALTRACE is supplied for a function parameter" $
      classes (people <> "GIVEN n IS A NUMBER\n      run IS A FUNCTION FROM DEONTIC Person Action TO DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nc n run MEANS\n  IF n > 0\n  THEN c (n MINUS 1) run\n  ELSE run (PARTY Alice MUST tick WITHIN 5 HENCE c 1 run)")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "but the same countdown with no lap is still proved" $
      classes (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nc n MEANS\n  IF n > 0\n  THEN c (n MINUS 1)\n  ELSE EVALTRACE (PARTY Alice MUST tick WITHIN 5 HENCE FULFILLED) 0 (LIST EVENT Alice tick 1)")
        `shouldReturn` ["function:proved-countdown"]

  -- each ran past the size ratio at run time, or into layer 1's limit on open
  -- obligations (2026-11-20, second adversarial pass)
  describe "work that multiplies behind a type or a name (second adversarial pass)" do
    it "an obligation held in a record, doubled each lap" $
      classes (people <> "DECLARE Box HAS ob IS A DEONTIC Person Action\n\nGIVEN b IS A Box\nGIVETH A DEONTIC Person Action\nx b MEANS (b's ob) RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (Box OF ((b's ob) RAND (b's ob)))))")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a countdown that returns a record holding an obligation a helper doubles" $
      classes (people <> "DECLARE Box HAS ob IS A DEONTIC Person Action\n\nGIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\ntwice k MEANS k RAND k\n\nGIVEN n IS A NUMBER\nGIVETH A Box\nb n MEANS\n  IF n GREATER THAN 0\n  THEN Box OF (twice ((b (n MINUS 1))'s ob))\n  ELSE Box OF (PARTY Alice MUST tick WITHIN 1000000)")
        `shouldReturn` ["function:proved-countdown+fans"]

    it "a parameter typed by a synonym for DEONTIC, doubled each lap" $
      classes (people <> "DECLARE Ob IS DEONTIC Person Action\n\nGIVEN k IS AN Ob\nGIVETH AN Ob\nx k MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (k RAND k)))")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a countdown that returns a synonym for DEONTIC and hands it to a helper that doubles it" $
      classes (people <> "DECLARE Duty IS A DEONTIC Person Action\n\nGIVEN k IS A Duty\nGIVETH A Duty\ntwice k MEANS k RAND k\n\nGIVEN n IS A NUMBER\nGIVETH A Duty\nb n MEANS IF n GREATER THAN 0 THEN twice (b (n MINUS 1)) ELSE PARTY Alice MAY tick")
        `shouldReturn` ["function:proved-countdown+fans"]

    it "a rule that doubles its own parameter through a WHERE name" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nx k MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (y RAND y)))\n  WHERE\n    y MEANS k")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "the same through a LET name" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nx k MEANS LET y IS k IN k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (y RAND y)))")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "the same through a name a CONSIDER pattern binds" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nx k MEANS PARTY Alice MUST tick WITHIN 1 LEST\n            CONSIDER (LIST k)\n              WHEN y FOLLOWED BY ys THEN y RAND x (y RAND y)\n              WHEN EMPTY THEN FULFILLED")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a helper whose WHERE names come in the other order" $
      classes (people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\ntwice k MEANS b RAND b\n  WHERE\n    b MEANS a\n    a MEANS k\n\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (twice x)")
        `shouldReturn` ["obligation:proved-waits+fans"]

    -- unproved as well: comb and mk are functions it is given, which may be
    -- EVALTRACE (Note [What makes a lap wait])
    it "a parameter typed by a type variable, combined with itself each lap" $
      classes (people <> "GIVEN a IS A TYPE\n      k IS AN a\n      comb IS A FUNCTION FROM a AND a TO a\n      mk IS A FUNCTION FROM a TO DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nx k comb mk MEANS (mk k) RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (comb k k) comb mk))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a lap that starts a countdown returning a synonym for DEONTIC" $
      classes (people <> "DECLARE Duty IS A DEONTIC Person Action\n\nGIVEN n IS A NUMBER\nGIVETH A Duty\ncopies n MEANS IF n GREATER THAN 0 THEN (PARTY Bob MUST tick WITHIN 1) RAND copies (n MINUS 1) ELSE FULFILLED\n\nGIVEN n IS A NUMBER\nGIVETH A Duty\nx n MEANS PARTY Alice MUST tick WITHIN 1 LEST (copies n RAND x (n PLUS 1))")
        `shouldReturn` ["function:proved-countdown", "obligation:proved-waits+nests"]

    it "a section GIVEN that a helper names twice, supplied by WITH" $
      classes (people <> "§ `S`\n    GIVEN k IS A DEONTIC Person Action\n\nGIVETH A DEONTIC Person Action\ntwice MEANS k RAND k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (twice WITH k IS x)")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "a section GIVEN that each lap supplies doubled" $
      classes (people <> "§ `S`\n    GIVEN k IS A DEONTIC Person Action\n\nGIVETH A DEONTIC Person Action\nx MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x WITH k IS (k RAND k)))")
        `shouldReturn` ["obligation:proved-waits+fans"]

  -- "+fans" on these is the fan count, which takes a function written in
  -- place as unbounded (Note [Fan-out]); it feeds no warning.
  describe "descent: a part of what each call was given (step 3)" do
    it "proves a walk over a tree through map and a stored field" $
      classes (tree <> "GIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (map (GIVEN c YIELD size c) (t's kids))")
        `shouldReturn` ["function:proved-structural+fans"]

    it "and through any, passing a field of the element" $
      classes ("IMPORT prelude\nDECLARE Person HAS\n  alive IS A BOOLEAN\n  ties IS A LIST OF Tie\nDECLARE Tie HAS\n  child IS A Person\n\nGIVEN p IS A Person GIVETH A BOOLEAN\nlive p MEANS p's alive OR any (GIVEN r YIELD live (r's child)) (p's ties)")
        `shouldReturn` ["function:proved-structural+fans"]

    it "and through a function of the author's own with map's type" $
      classes (tree <> "GIVEN a IS A TYPE\n      b IS A TYPE\n      f IS A FUNCTION FROM a TO b\n      xs IS A LIST OF a\nGIVETH A LIST OF b\neach f xs MEANS\n  CONSIDER xs\n    WHEN EMPTY THEN EMPTY\n    WHEN y FOLLOWED BY ys THEN f y FOLLOWED BY each f ys\n\nGIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (each (GIVEN c YIELD size c) (t's kids))")
        `shouldReturn` ["function:proved-structural", "function:proved-structural+fans"]

    it "but not through a function whose type lets it hand back what the function made" $
      classes (tree <> "GIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO a\n      xs IS A LIST OF a\nGIVETH A LIST OF a\nagain f xs MEANS map f xs\n\nGIVEN t IS A Tree GIVETH A Tree\nwalk t MEANS Tree OF 1, again (GIVEN c YIELD walk c) (t's kids)")
        `shouldReturn` ["function:unproved-self+fans"]

    it "and not through a computed field, whose MEANS can give anything" $
      classes ("IMPORT prelude\nDECLARE Tree HAS\n  label IS A NUMBER\n  around IS A LIST OF Tree MEANS LIST (Tree OF label)\n\nGIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (map (GIVEN c YIELD size c) (t's around))")
        `shouldReturn` ["function:unproved-self+fans"]

    it "and not through the list the function was not given from the parameter" $
      classes (tree <> "spare MEANS LIST (Tree OF 1, EMPTY)\n\nGIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (map (GIVEN c YIELD size c) spare)")
        `shouldReturn` ["function:unproved-self+fans"]

    it "proves definitions that call each other down a tree (hierarchy's render outline)" $
      classes (tree <> "GIVEN t IS A Tree GIVETH A LIST OF NUMBER\nnode t MEANS (t's label) FOLLOWED BY forest (t's kids)\n\nGIVEN ts IS A LIST OF Tree GIVETH A LIST OF NUMBER\nforest ts MEANS go ts\n\nGIVEN ts IS A LIST OF Tree GIVETH A LIST OF NUMBER\ngo ts MEANS\n  CONSIDER ts\n    WHEN EMPTY THEN EMPTY\n    WHEN k FOLLOWED BY ks THEN append (node k) (go ks)")
        `shouldReturn` ["function:proved-structural+fans"]

    it "but not definitions that hand each other the very value" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nping n MEANS pong n\n\nGIVEN n IS A NUMBER GIVETH A NUMBER\npong n MEANS ping n")
        `shouldReturn` ["function:unproved-mutual"]

    it "and not when one of them passes something that is not a part" $
      classes (tree <> "GIVEN t IS A Tree GIVETH A NUMBER\nup t MEANS down (Tree OF 1, LIST t)\n\nGIVEN t IS A Tree GIVETH A NUMBER\ndown t MEANS sum (map (GIVEN c YIELD up c) (t's kids))")
        `shouldReturn` ["function:unproved-mutual+fans"]

    it "proves definitions that call each other through a rule passed to map by name" $
      classes (tree <> "GIVEN t IS A Tree GIVETH A LIST OF NUMBER\nbelow t MEANS concat (map here (t's kids))\n\nGIVEN t IS A Tree GIVETH A LIST OF NUMBER\nhere t MEANS (t's label) FOLLOWED BY below t")
        `shouldReturn` ["function:proved-structural+fans"]

    it "and through a WHERE name that filters a field, the elements going to a rule by name" $
      classes (tree <> "GIVEN t IS A Tree GIVETH A LIST OF NUMBER\nbelow t MEANS concat (map here kept)\n  WHERE\n    kept MEANS filter (GIVEN c YIELD c's label GREATER THAN 0) (t's kids)\n\nGIVEN t IS A Tree GIVETH A LIST OF NUMBER\nhere t MEANS (t's label) FOLLOWED BY below t")
        `shouldReturn` ["function:proved-structural+fans"]

    it "but not through a function that can give back what its other list held" $
      classes (tree <> "spare MEANS LIST (Tree OF 1, EMPTY)\n\nGIVEN t IS A Tree GIVETH A LIST OF NUMBER\nbelow t MEANS concat (map here (append (t's kids) spare))\n\nGIVEN t IS A Tree GIVETH A LIST OF NUMBER\nhere t MEANS (t's label) FOLLOWED BY below t")
        `shouldReturn` ["function:unproved-mutual+fans"]

    it "reads a definition written as clauses as one rule, not a cycle with its own clauses" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\nlen EMPTY MEANS 0\nlen (y FOLLOWED BY ys) MEANS 1 PLUS len ys"
        `shouldReturn` ["function:proved-structural"]

    it "and a clause test for 0 still proves nothing" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nfact 0 MEANS 1\nfact n MEANS n TIMES fact (n MINUS 1)"
        `shouldReturn` ["function:unproved-self"]

    it "proves a count up to a definition that is a number written out" $
      classes "twelve MEANS 12\n\nGIVEN i IS A NUMBER GIVETH A NUMBER\nup i MEANS IF i LESS THAN twelve AND i GREATER THAN 0 THEN up (i PLUS 1) ELSE i"
        `shouldReturn` ["function:proved-countdown"]

  describe "what multiplies is proved, not counted (step 3)" do
    it "ruling L3's open test: alternatives that each call the rule from their own HENCE" $
      classes (people <> "GIVEN b IS A NUMBER\nGIVETH A DEONTIC Person Action\nowed b MEANS\n  IF b AT MOST 0 THEN FULFILLED\n  ELSE (PARTY Alice MUST tick WITHIN 7 HENCE owed (b MINUS 1))\n       ROR (PARTY Bob MUST tick WITHIN 7 HENCE owed (b MINUS 1))")
        `shouldReturn` ["obligation:proved-waits+fans"]

    it "an ROR in one LEST starts both sides" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (x ROR x)")
        `shouldReturn` ["obligation:proved-waits+multiplies"]

    it "says which continuation, which operator, how many copies, and what counts down" $ do
      fs <- findings (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nb n MEANS\n  IF n EQUALS 0 THEN FULFILLED\n  ELSE PARTY Alice MUST tick WITHIN 1 LEST (b (n MINUS 1) RAND b (n MINUS 1) RAND b (n MINUS 1))")
      [(m.rule, m.operator, m.copies, m.via, m.stepsDown) | f <- fs, Just m <- [f.multiplies]]
        `shouldBe` [("b", "RAND", 3, LestOf DMust, Just ("n", 1))]

    it "a MAY's LEST, and both operators" $ do
      fs <- findings (people <> "GIVETH A DEONTIC Person Action\nw1 MEANS PARTY Alice MUST tick WITHIN 2 LEST (w3 ROR w1)\n\nGIVETH A DEONTIC Person Action\nw3 MEANS PARTY Bob MAY tick WITHIN 2 LEST ((w1 RAND w3) ROR w1)")
      [(m.rule, m.operator, m.copies, m.via) | f <- fs, Just m <- [f.multiplies]]
        `shouldBe` [("w1", "ROR", 2, LestOf DMust)]

    it "and a HENCE" $ do
      fs <- findings (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MAY tick WITHIN 2 HENCE (x RAND x)")
      [m.via | f <- fs, Just m <- [f.multiplies]] `shouldBe` [HenceOf DMay]

    it "but not a call under an IF inside the operand (the run-time count stops it)" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST ((IF TRUE THEN x ELSE FULFILLED) RAND x)")
        `shouldReturn` ["obligation:proved-waits+fans"]

  describe "a name for an expression is read where it is named (step 3)" do
    it "proves a countdown through a LET name (doc/reference/functions/let-example.l4)" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nfact n MEANS\n  IF n <= 1\n  THEN 1\n  ELSE LET prev IS fact (n MINUS 1)\n       IN n TIMES prev"
        `shouldReturn` ["function:proved-countdown"]

    it "and a walk down a list through a WHERE name (doc/reference/functions/where-example.l4)" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\ntotal xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN 0\n  WHEN y FOLLOWED BY ys THEN y PLUS rest\n    WHERE\n      rest MEANS total ys"
        `shouldReturn` ["function:proved-structural"]

    it "but credits the call to the function that names it, not to where it is bound" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS h n\n  WHERE\n    GIVEN m IS A NUMBER GIVETH A NUMBER\n    h m MEANS again\n    again MEANS h n"
        `shouldReturn` ["function:unproved-self"]

    it "and keeps a name that names itself, so its loop is still reported" $
      classes "GIVEN n IS A NUMBER GIVETH A LIST OF NUMBER\nf n MEANS ones\n  WHERE\n    ones MEANS n FOLLOWED BY ones"
        `shouldReturn` ["function:unproved-self"]

    it "and two names that name each other" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS a\n  WHERE\n    a MEANS b PLUS n\n    b MEANS a PLUS 1"
        `shouldReturn` ["function:unproved-mutual"]

    it "and still counts the copies a LEST starts through two such names" $
      classes (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (a RAND b)\n  WHERE\n    a MEANS x\n    b MEANS x")
        `shouldReturn` ["obligation:proved-waits+multiplies"]

    it "but does not open a name whose body is the RAND, which was not counted before either" $ do
      fs <- findings (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST both\n  WHERE\n    both MEANS x RAND x")
      [m | f <- fs, Just m <- [f.multiplies]] `shouldSatisfy` null

  describe "descent: a pattern rebuilt from what it bound (step 3)" do
    it "proves a walk that passes on the tail it took apart (ok/list-nested-cons-exhaustive.l4)" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A BOOLEAN\nsorted xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN TRUE\n  WHEN x FOLLOWED BY EMPTY THEN TRUE\n  WHEN x FOLLOWED BY (y FOLLOWED BY rest) THEN x <= y AND sorted (y FOLLOWED BY rest)"
        `shouldReturn` ["function:proved-structural"]

    it "and a constructor's field rebuilt the same way" $
      classes "DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\n\nGIVEN n IS A Nat GIVETH A NUMBER\nhalf n MEANS\n  CONSIDER n\n  WHEN Zero THEN 0\n  WHEN Suc Zero THEN 0\n  WHEN Suc (Suc m) THEN 1 PLUS half (Suc m)"
        `shouldReturn` ["function:proved-structural"]

    it "but not the outermost pattern, which is the whole value again" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A BOOLEAN\nloop xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN TRUE\n  WHEN y FOLLOWED BY rest THEN loop (y FOLLOWED BY rest)"
        `shouldReturn` ["function:unproved-self"]

    it "and not names from different patterns put together" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A BOOLEAN\nsorted xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN TRUE\n  WHEN x FOLLOWED BY EMPTY THEN TRUE\n  WHEN x FOLLOWED BY (y FOLLOWED BY rest) THEN x <= y AND sorted (x FOLLOWED BY rest)"
        `shouldReturn` ["function:unproved-self"]

  -- each timed out at run time on a one-node tree (2026-11-21 attack round,
  -- parametricity p01, p02, p07, p20; mutual p08leaf, p09tail)
  describe "descent: a function that can hand back the function it was given (attack round)" do
    it "gives no proof through a callee whose result is a function taking an a" $
      classes (tree <> handBack <> "GIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS apply (holds (GIVEN c YIELD walk c) (t's kids)) t")
        `shouldReturn` ["function:unproved-self+fans"]

    it "nor when the rule is passed by name, round two definitions" $
      classes (tree <> handBack <> "GIVEN t IS A Tree GIVETH A BOOLEAN\nbelow t MEANS k t\n  WHERE\n    k MEANS holds here (t's kids)\n\nGIVEN t IS A Tree GIVETH A BOOLEAN\nhere t MEANS t's label EQUALS 0 OR below t")
        `shouldReturn` ["function:unproved-mutual+fans"]

    it "nor through a record that holds a function taking an a" $
      classes (tree <> "DECLARE Holder a HAS run IS A FUNCTION FROM a TO BOOLEAN\n\nGIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\nGIVETH A Holder a\nkeep f xs MEANS Holder OF f\n\nGIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS r t\n  WHERE\n    r MEANS (keep (GIVEN c YIELD walk c) (t's kids))'s run")
        `shouldReturn` ["function:unproved-self+fans"]

    it "but a callee that gives a list of a, as filter does, still proves" $
      classes (tree <> "GIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\nGIVETH A LIST OF a\nkept f xs MEANS filter f xs\n\nGIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (map size (kept (GIVEN c YIELD size c GREATER THAN 0) (t's kids)))")
        `shouldReturn` ["function:proved-structural+fans"]


  describe "nodes" do
    it "keeps overloads that share a name apart" $
      classes (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS IF n GREATER THAN 0 THEN f (n MINUS 1) ELSE 0\n\nGIVEN s IS A STRING GIVETH A NUMBER\nf s MEANS 1")
        `shouldReturn` ["function:proved-countdown"]

  describe "the labelled walk drops no reference" $
    it "finds exactly the references a plain fold finds, on every fixture above" $
      mapM_ walkCheck
        [ people <> "GIVETH A DEONTIC Person Action\nw1 MEANS PARTY Alice MUST tick WITHIN 2 LEST (w3 RAND w1)\n\nGIVETH A DEONTIC Person Action\nw3 MEANS PARTY Bob MUST tick WITHIN 3 LEST w1"
        , tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN trio MUST Sign t WITHIN deadline t ONCE ALL HAVE HENCE x LEST (x RAND x)\n\nGIVEN t IS AN Actor GIVETH A NUMBER\ndeadline t MEANS IF t EQUALS alice THEN 5 ELSE 6"
        , people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS g n PLUS g n\n  WHERE\n    GIVEN k IS A NUMBER GIVETH A NUMBER\n    g k MEANS IF k GREATER THAN 0 THEN g (k MINUS 1) ELSE f 0"
        , people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nr n MEANS RECORD `a` IS n HENCE r (n PLUS 1)"
        , "DECLARE Box HAS\n    n    IS A NUMBER\n    deep IS A NUMBER\n        MEANS bad n\n\nGIVEN k IS A NUMBER\nGIVETH A NUMBER\nbad k MEANS (Box WITH n IS k PLUS 1)'s deep"
        , people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST\n            CONSIDER (LIST (PARTY Alice MUST tick WITHIN 1 OF THE DEADLINE LEST x))\n              WHEN k FOLLOWED BY ks THEN PARTY Bob MUST tick WITHIN 1 OF 0 LEST k\n              WHEN EMPTY THEN FULFILLED"
        , people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (EVALTRACE x 0 (LIST (`WAIT UNTIL` 5)))"
        , people <> "§ `S`\n    GIVEN k IS A DEONTIC Person Action\n\nGIVETH A DEONTIC Person Action\ntwice MEANS k RAND k\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (twice WITH k IS x)"
        , people <> "GIVEN k IS A DEONTIC Person Action\nGIVETH A DEONTIC Person Action\nx k MEANS k RAND (PARTY Alice MUST tick WITHIN 1 LEST (x (y RAND y)))\n  WHERE\n    y MEANS k"
        ]

------------------------------------------------------------------------

tree :: Text
tree = "IMPORT prelude\nDECLARE Tree HAS\n  label IS A NUMBER\n  kids IS A LIST OF Tree\n\n"
-- | A function of @all@'s argument types that gives back the function it was
-- given, and one that applies a function: together they apply the function
-- to a value that is not an element of the list.
handBack :: Text
handBack = Text.unlines
  [ "GIVEN a IS A TYPE"
  , "      f IS A FUNCTION FROM a TO BOOLEAN"
  , "      xs IS A LIST OF a"
  , "GIVETH A FUNCTION FROM a TO BOOLEAN"
  , "holds f xs MEANS f"
  , ""
  , "GIVEN g IS A FUNCTION FROM Tree TO BOOLEAN"
  , "      t IS A Tree"
  , "GIVETH A BOOLEAN"
  , "apply g t MEANS g t"
  , ""
  ]

people :: Text
people = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
  , "DECLARE Action IS ONE OF never, tick"
  , ""
  ]

-- | A helper that applies the function it is given to an obligation.
runHelper :: Text
runHelper = Text.unlines
  [ "GIVEN f IS A FUNCTION FROM DEONTIC Person Action AND NUMBER AND LIST OF EVENT Person Action TO DEONTIC Person Action"
  , "      k IS A DEONTIC Person Action"
  , "GIVETH A DEONTIC Person Action"
  , "run f k MEANS f k 0 (LIST (`WAIT UNTIL` 5))"
  , ""
  ]

-- | A helper that hands its argument on from an obligation whose deadline is
-- the fixed instant 1.
wrapFixed :: Text
wrapFixed = Text.unlines
  [ "GIVEN k IS A DEONTIC Person Action"
  , "GIVETH A DEONTIC Person Action"
  , "wrap k MEANS PARTY Bob MUST tick WITHIN 1 OF 0 LEST k"
  , ""
  ]

tenants :: Text
tenants = Text.unlines
  [ "DECLARE Actor IS ONE OF"
  , "  Tenant HAS name IS A STRING"
  , "  Landlord HAS name IS A STRING"
  , "DECLARE Action IS ONE OF Sign HAS signer IS AN Actor"
  , "alice MEANS Tenant OF \"Alice\""
  , "bob MEANS Tenant OF \"Bob\""
  , "carol MEANS Tenant OF \"Carol\""
  , "GIVETH A LIST OF Actor"
  , "nobody MEANS LIST"
  , "trio MEANS LIST alice, bob, carol"
  , ""
  ]

-- | A module for the cross-module fixtures to import: a synonym for DEONTIC,
-- a helper that runs what it is given under EVALTRACE, one that takes an
-- obligation and only hands it back, and one that takes anything.
importedHelpers :: VFS
importedHelpers = vfsFromList
  [ ( "helpers"
    , Text.unlines
        [ "DECLARE Person IS ONE OF Alice, Bob, Carol"
        , "DECLARE Action IS ONE OF never, tick"
        , "DECLARE Duty IS A DEONTIC Person Action"
        , ""
        , "GIVEN k IS A DEONTIC Person Action"
        , "GIVETH A DEONTIC Person Action"
        , "fresh k MEANS EVALTRACE k 0 (LIST (`WAIT UNTIL` 5))"
        , ""
        , "GIVEN k IS A DEONTIC Person Action"
        , "GIVETH A DEONTIC Person Action"
        , "plain k MEANS k"
        , ""
        , "GIVEN a IS A TYPE"
        , "      v IS AN a"
        , "GIVETH AN a"
        , "same v MEANS v"
        , ""
        , "DECLARE Runner IS FUNCTION FROM DEONTIC Person Action TO DEONTIC Person Action"
        , "GIVETH A Runner"
        , "runner MEANS GIVEN k YIELD EVALTRACE k 0 (LIST (`WAIT UNTIL` 5))"
        , ""
        , "GIVEN t IS A NUMBER"
        , "GIVETH A FUNCTION FROM DEONTIC Person Action TO DEONTIC Person Action"
        , "runAt t MEANS GIVEN k YIELD EVALTRACE k t (LIST (`WAIT UNTIL` 5))"
        ] ) ]

checked :: Text -> IO (Substitution, EntityInfo, Module Resolved)
checked = checkedIn emptyVFS

checkedIn :: VFS -> Text -> IO (Substitution, EntityInfo, Module Resolved)
checkedIn vfs source = case checkWithImports vfs source of
  Left errs -> fail ("pipeline failure: " <> show errs)
  Right r
    | r.tcdSuccess -> pure (r.tcdSubstitution, r.tcdEntityInfo, r.tcdModule)
    | otherwise -> fail ("did not type-check:\n" <> Text.unpack source <> "\n" <> show (errorsOf r.tcdErrors))
 where
  errorsOf :: [CheckErrorWithContext] -> [CheckErrorWithContext]
  errorsOf = filter ((== SError) . severity)

findings :: Text -> IO [Finding]
findings = findingsIn emptyVFS

findingsIn :: VFS -> Text -> IO [Finding]
findingsIn vfs source =
  (\ (s, i, m@(MkModule _ uri _)) -> cycleFindings (applyFinalSubstitution s uri) i m) <$> checkedIn vfs source

classes :: Text -> IO [Text]
classes source = sort . map findingClass <$> findings source

classesIn :: VFS -> Text -> IO [Text]
classesIn vfs source = sort . map findingClass <$> findingsIn vfs source

verdicts :: Text -> IO [Verdict]
verdicts source = map (.verdict) <$> findings source

walkCheck :: Text -> Expectation
walkCheck source = do
  (_, i, m) <- checked source
  sort (map (.to) (moduleEdges i m)) `shouldBe` plainReferences m
