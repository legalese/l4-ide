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
import Control.Exception (evaluate)
import Control.Monad (void)
import Test.Hspec

import LinearTime (cpuRatio, quadraticControl)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Base (Uri (..), toNormalizedUri)
import L4.API.EmbeddedLibraries (embeddedLibraries)
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), VFS, checkWithImports, checkWithImportsAndUri, emptyVFS, vfsFromList)
import L4.Cycles
import L4.Cycles.Warning (CycleTrouble (..), CycleWarning (..))
import L4.Syntax (DeonticModal (..), Module (..), Resolved)
import L4.TypeCheck (applyFinalSubstitution, prettyCheckError)
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..), CheckWarning (..), EntityInfo, Severity (..), Substitution, severity)

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

    -- each stopped by frame depth at run time when supplied with EVALTRACE
    -- (2026-11-21 attack round, obligations t6, t4)
    it "a function parameter typed by a synonym with a parameter" $
      classes (people <> "DECLARE Endo a IS FUNCTION FROM a TO a\n\nGIVEN f IS AN Endo (DEONTIC Person Action)\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx f n MEANS PARTY Alice MUST tick WITHIN 1 LEST (f (x f (n PLUS 1)))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "a function in a field of a record with a parameter" $
      classes ("IMPORT prelude\n" <> people <> "DECLARE Wrap a HAS run IS A FUNCTION FROM a TO a\n\nGIVEN w IS A Wrap (DEONTIC Person Action)\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx w n MEANS PARTY Alice MUST tick WITHIN 1 LEST (maybe (w's run) FULFILLED (JUST (x w (n PLUS 1))))")
        `shouldReturn` ["obligation:unproved-stall+fans"]

    it "but a synonym with a parameter that gives no obligation still lets the wait prove it" $
      classes (people <> "DECLARE Endo a IS FUNCTION FROM a TO a\n\nGIVEN f IS AN Endo NUMBER\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx f n MEANS PARTY Alice MUST tick WITHIN 1 LEST (x f (f n))")
        `shouldReturn` ["obligation:proved-waits"]

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

    -- each ended at run time and was "could not check" (2026-11-21 attack
    -- round, names q07, q02, q08; patterns m3)
    it "proves a countdown whose argument is a name for the smaller number" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS IF n > 0 THEN f next PLUS 1 ELSE 0\n  WHERE next MEANS n MINUS 1"
        `shouldReturn` ["function:proved-countdown"]

    it "and one whose test is a name for the comparison" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS IF big THEN f (n MINUS 1) ELSE 0\n  WHERE big MEANS n > 0"
        `shouldReturn` ["function:proved-countdown"]

    it "and a walk whose argument is a name for the tail" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\ntotal xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN 0\n  WHEN y FOLLOWED BY ys THEN y PLUS total rest\n    WHERE rest MEANS ys"
        `shouldReturn` ["function:proved-structural"]

    it "but not a name for the very value" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\ntotal xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN 0\n  WHEN y FOLLOWED BY ys THEN y PLUS total same\n    WHERE same MEANS xs"
        `shouldReturn` ["function:unproved-self"]

    it "nor a name for a number that does not move" $
      classes "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS IF n > 0 THEN f next PLUS 1 ELSE 0\n  WHERE next MEANS n PLUS 0"
        `shouldReturn` ["function:unproved-self"]

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

    -- each ended at run time and was "could not check" (2026-11-21 attack
    -- round, patterns m1, m2)
    it "proves a walk that names the tail with a bare pattern of an inner CONSIDER" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\nm xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN 0\n  WHEN y FOLLOWED BY ys THEN\n    CONSIDER ys\n    WHEN EMPTY THEN 1\n    WHEN other THEN 1 PLUS m other"
        `shouldReturn` ["function:proved-structural"]

    it "and one that rebuilds the whole pattern of an inner CONSIDER over the tail" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\nm xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN 0\n  WHEN y FOLLOWED BY ys THEN\n    CONSIDER ys\n    WHEN EMPTY THEN 1\n    WHEN z FOLLOWED BY zs THEN 1 PLUS m (z FOLLOWED BY zs)"
        `shouldReturn` ["function:proved-structural"]

    it "but not a bare pattern over the very value" $
      classes "GIVEN xs IS A LIST OF NUMBER GIVETH A NUMBER\nm xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN 0\n  WHEN other THEN 1 PLUS m other"
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

    -- "untraced" as well: the member reads a field that holds a function
    it "nor through a record that holds a function taking an a" $
      classes (tree <> "DECLARE Holder a HAS run IS A FUNCTION FROM a TO BOOLEAN\n\nGIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\nGIVETH A Holder a\nkeep f xs MEANS Holder OF f\n\nGIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS r t\n  WHERE\n    r MEANS (keep (GIVEN c YIELD walk c) (t's kids))'s run")
        `shouldReturn` ["function:unproved-untraced+fans"]

    it "but a callee that gives a list of a, as filter does, still proves" $
      classes (tree <> "GIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\nGIVETH A LIST OF a\nkept f xs MEANS filter f xs\n\nGIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (map size (kept (GIVEN c YIELD size c GREATER THAN 0) (t's kids)))")
        `shouldReturn` ["function:proved-structural+fans"]

  -- each timed out at run time on a one-node tree, the callee handing the
  -- function a value of every type (2026-11-21 attack round, parametricity
  -- p12, p11, p17, p13): Note [Trusting a callee]
  describe "descent: a callee keeps its type's credit only where its body earns it (attack round)" do
    it "gives no proof through a callee that applies the function to a refusal" $
      classes (tree <> smuggling "f (REFUSE \"no such element\")" <> "GIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS smuggle (GIVEN c YIELD walk c) (t's kids)")
        `shouldReturn` ["function:unproved-self+fans"]

    it "nor to an ASSUME of a type variable" $
      classes (tree <> "GIVEN v IS A TYPE\nASSUME anything IS A v\n\n" <> smuggling "f anything" <> "GIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS smuggle (GIVEN c YIELD walk c) (t's kids)")
        `shouldReturn` ["function:unproved-self+fans"]

    it "nor to the prelude's TBD, the rule passed by name" $
      classes (tree <> smuggling "f TBD" <> "GIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS smuggle walk (t's kids) OR t's label EQUALS 0")
        `shouldReturn` ["function:unproved-self+fans"]

    it "nor through a callee of filter's type that gives a list of a refusal" $
      classes (tree <> "GIVEN a IS A TYPE\n      keep IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\nGIVETH A LIST OF a\nchoose keep xs MEANS LIST (REFUSE \"no such element\")\n\nGIVEN t IS A Tree GIVETH A BOOLEAN\nwalk t MEANS all walk (choose (GIVEN c YIELD TRUE) (t's kids))")
        `shouldReturn` ["function:unproved-self+fans"]

    -- the first finding, here and below, is the helper's own walk
    it "nor through a helper whose own walk applies the function to a refusal" $
      classes (tree <> counting "THEN f (REFUSE \"none\")" <> "GIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS count (GIVEN c YIELD size c) (t's kids)")
        `shouldReturn` ["function:proved-structural", "function:unproved-self+fans"]

    it "but a helper that hands the function on to map, with the list, still proves" $
      classes (tree <> "GIVEN a IS A TYPE\n      b IS A TYPE\n      f IS A FUNCTION FROM a TO b\n      xs IS A LIST OF a\nGIVETH A LIST OF b\neach f xs MEANS map f xs\n\nGIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS sum (each size (t's kids))")
        `shouldReturn` ["function:proved-structural+fans"]

    it "and so does a helper that walks the list itself in a WHERE" $
      classes (tree <> counting "THEN 0" <> "GIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS 1 PLUS count (GIVEN c YIELD size c) (t's kids)")
        `shouldReturn` ["function:proved-structural", "function:proved-structural+fans"]

    it "and the prelude's foldl, whose body walks the list in a WHERE" $
      classes (tree <> "GIVEN t IS A Tree GIVETH A NUMBER\nsize t MEANS foldl (GIVEN n, c YIELD n PLUS size c) 1 (t's kids)")
        `shouldReturn` ["function:proved-structural+fans"]

  describe "the library functions taken on trust (Note [Trusting a callee])" do
    it "are exactly the ones whose bodies earn every credit their types give" $
      for_ (Map.toList embeddedLibraries) \ (name, source) -> do
        (_, i, m) <- checkedAs name source
        sort (earnedByBody i m)
          `shouldBe` maybe [] (sort . Set.toList) (Map.lookup (name <> ".l4") trustedLibrary)

    it "and leave out a name one of whose definitions does not earn its credit" $ do
      -- both helpers walk the list themselves, as a library's must: the
      -- check reads a library with no other library trusted
      let walk name = name <> " f xs MEANS\n  CONSIDER xs\n  WHEN EMPTY THEN TRUE\n  WHEN y FOLLOWED BY ys THEN f y AND " <> name <> " f ys\n\n"
          sig = "GIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\n"
      (_, i, m) <- checked ("IMPORT prelude\n\n" <> sig <> "GIVETH A BOOLEAN\n" <> walk "holds" <> sig <> "      n IS A NUMBER\nGIVETH A BOOLEAN\nholds f xs n MEANS f TBD\n\n" <> sig <> "GIVETH A BOOLEAN\n" <> walk "kept")
      earnedByBody i m `shouldBe` ["kept"]

    it "include map, and leave out a function whose body reads as no more than its type (sortBy)" $ do
      let listed = Map.findWithDefault Set.empty "prelude.l4" trustedLibrary
      (Set.member "map" listed, Set.member "sortBy" listed) `shouldBe` (True, False)

    it "are recognised by a library URI no other file can take" $
      map (libraryFile . toNormalizedUri . Uri)
        [ "jl4-embedded:/prelude.l4"
        , "file:///home/ci/l4-ide/jl4-core/libraries/prelude.l4"
        , "project:/prelude.l4"
        , "file:///home/someone/prelude.l4" ]
        `shouldBe` [Just "prelude.l4", Just "prelude.l4", Nothing, Nothing]

    it "and in the API's pipeline, where a project:/ name is looked up among the libraries first" $
      apiLibraryFile (toNormalizedUri (Uri "project:/prelude.l4")) `shouldBe` Just "prelude.l4"

  -- each overflowed the frame-depth guard at run time while the cycle the
  -- graph sees was proved (2026-11-21 attack round, mutual p10, obligations
  -- t2): the loop ran through a function in a field
  describe "a function no edge follows (attack round)" do
    it "gives no proof to a descent whose member applies a function held in a field" $
      classes ("DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\nDECLARE Wrap HAS run IS A FUNCTION FROM Wrap TO NUMBER\n\nGIVEN g IS A FUNCTION FROM Wrap TO NUMBER\n      x IS A Wrap\nGIVETH A NUMBER\napply g x MEANS g x\n\nGIVEN n IS A Nat\n      w IS A Wrap\nGIVETH A NUMBER\nf n w MEANS\n  CONSIDER n\n  WHEN Zero THEN 0\n  WHEN Suc k THEN (apply (w's run) w) PLUS f k w")
        `shouldReturn` ["function:unproved-untraced"]

    it "nor to a wait whose member calls a function held in a record of a type that holds itself" $
      classes (people <> "DECLARE Box HAS check IS A FUNCTION FROM Box AND NUMBER TO BOOLEAN\n\nGIVEN b IS A Box\n      n IS A NUMBER\nGIVETH A DEONTIC Person Action\nx b n MEANS PARTY Alice MUST tick WITHIN 1 LEST (IF c b n THEN x b (n PLUS 1) ELSE FULFILLED)\n  WHERE\n    c MEANS b's check")
        `shouldReturn` ["obligation:unproved-untraced"]

    it "nor when the field is taken apart by a pattern" $
      classes ("DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\nDECLARE Wrap HAS run IS A FUNCTION FROM Wrap TO NUMBER\n\nGIVEN n IS A Nat\n      w IS A Wrap\nGIVETH A NUMBER\nf n w MEANS\n  CONSIDER w\n  WHEN Wrap r THEN\n    CONSIDER n\n    WHEN Zero THEN 0\n    WHEN Suc k THEN r w PLUS f k w")
        `shouldReturn` ["function:unproved-untraced"]

    it "nor when such a field's value is handed in as a function, beside a type that holds itself" $
      classes ("DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\nDECLARE Wrap HAS run IS A FUNCTION FROM Wrap TO NUMBER\n\nGIVEN n IS A Nat\n      g IS A FUNCTION FROM NUMBER TO NUMBER\nGIVETH A NUMBER\nf n g MEANS\n  CONSIDER n\n  WHEN Zero THEN 0\n  WHEN Suc k THEN g 0 PLUS f k g")
        `shouldReturn` ["function:unproved-untraced"]

    it "but a function parameter is followed where no type holds a function of itself" $
      classes ("DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\n\nGIVEN n IS A Nat\n      g IS A FUNCTION FROM NUMBER TO NUMBER\nGIVETH A NUMBER\nf n g MEANS\n  CONSIDER n\n  WHEN Zero THEN 0\n  WHEN Suc k THEN g 0 PLUS f k g")
        `shouldReturn` ["function:proved-structural"]

    it "and a field that holds no function does not count" $
      classes ("DECLARE Nat IS ONE OF\n  Zero\n  Suc HAS pred IS A Nat\nDECLARE Wrap HAS size IS A NUMBER\n\nGIVEN n IS A Nat\n      w IS A Wrap\nGIVETH A NUMBER\nf n w MEANS\n  CONSIDER n\n  WHEN Zero THEN 0\n  WHEN Suc k THEN w's size PLUS f k w")
        `shouldReturn` ["function:proved-structural"]

  -- Reading names through multiplies the edges: a name used k times for a
  -- body with 10 calls is 10k edges. Testing each edge by a search of its
  -- own was quadratic in them: 150 uses took 18.4 s of report where the
  -- check took 0.08 s, and 300 did not finish in 60 s (2026-11-21 attack
  -- round, names d13, d14). The edges are counted, not the source's size.
  describe "the report takes time near-linear in the edges of a cycle" $ do
    it "judges a cycle of 1,000 and of 4,000 edges in near the ratio of the edges" $ do
      let prepare k = do
            r@(_, _, m) <- checked (namedTenTimes k)
            void (evaluate m)
            pure r
          run (s, i, m@(MkModule _ uri _)) = do
            let fs = cycleFindings (applyFinalSubstitution s uri) i m
            -- the run happened, and judged the one cycle it was built for
            map findingClass fs `shouldBe` ["function:unproved-mutual+fans"]
      r <- cpuRatio prepare run 100 400
      r `shouldSatisfy` (< 8)

    it "fails work quadratic in the edges on the same sizes (the control)" $
      quadraticControl 100 400 8

  -- What the checker says (recursion-limit rulings L3 and L4, and the
  -- scope ruling (ii); 'cycleNotices'). Each warning that fires has a fixture where
  -- it fires and one where it does not (ruling L3's condition).
  describe "a function cycle draws no warning (the scope ruling (ii))" do
    it "a self-call not shown to end stays in the report and draws no alarm" do
      fs <- findings (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\ndown n MEANS IF n EQUALS 0 THEN 0 ELSE down (n MINUS 1)")
      map findingClass fs `shouldBe` ["function:unproved-self"]
      map alarms fs `shouldBe` [[]]

    it "nor does it draw a warning from the checker" $
      notices (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\ndown n MEANS IF n EQUALS 0 THEN 0 ELSE down (n MINUS 1)")
        `shouldReturn` []

    it "nor do two functions that call each other" $
      notices (people <> "GIVEN n IS A NUMBER GIVETH A BOOLEAN\nev n MEANS IF n EQUALS 0 THEN TRUE ELSE od (n MINUS 1)\n\nGIVEN n IS A NUMBER GIVETH A BOOLEAN\nod n MEANS IF n EQUALS 0 THEN FALSE ELSE ev (n MINUS 1)")
        `shouldReturn` []

  describe "an obligation cycle draws its alarms (the scope ruling (ii), L3)" do
    it "could not check: a LEST whose deadline is counted from a fixed instant" do
      fs <- findings (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST x")
      map alarms fs `shouldBe` [[CouldNotCheck]]
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST x")
        `shouldReturn` [("could not check", "x")]

    it "but not a LEST under a positive WITHIN, which waits" $
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 30 LEST x")
        `shouldReturn` []

    it "could not check: a rule that uses itself directly and through a HENCE (obligation:unproved-self)" do
      let src = people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nmix n MEANS IF n EQUALS 0 THEN FULFILLED ELSE (PARTY Alice MUST tick WITHIN 1 HENCE mix (n MINUS 1)) RAND mix (n MINUS 1)"
      classes src `shouldReturn` ["obligation:unproved-self+fans"]
      notices src `shouldReturn` [("could not check", "mix")]
      marked <- notices (people <> "@ends-because n drops by one\n" <> Text.drop (Text.length people) src)
      map fst marked `shouldSatisfy` notElem "could not check"
      t <- noticeText src
      t `shouldSatisfy` Text.isInfixOf "because `mix` also uses itself directly, with no duty in between, and there I could not find an input that gets smaller each time, towards a stop."

    it "could not check: two rules that use each other directly, and one a HENCE back to itself (obligation:unproved-mutual)" do
      let src = people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\na n MEANS IF n EQUALS 0 THEN FULFILLED ELSE (PARTY Alice MUST tick WITHIN 1 HENCE a (n MINUS 1)) RAND b (n MINUS 1)\n\nGIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nb n MEANS IF n EQUALS 0 THEN FULFILLED ELSE a (n MINUS 1)"
      classes src `shouldReturn` ["obligation:unproved-mutual+fans"]
      notices src `shouldReturn` [("could not check", "a")]
      t <- noticeText src
      t `shouldSatisfy` Text.isInfixOf "because two or more of them also use each other directly, with no duty in between, and I do not check that kind of loop."

    it "could not check, shown on a rule that only hands on by a HENCE: names the rule that uses itself directly" do
      let rules = "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\na n MEANS PARTY Alice MUST tick WITHIN 1 HENCE b n\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nb n MEANS IF n EQUALS 0 THEN FULFILLED ELSE (PARTY Alice MUST tick WITHIN 1 HENCE a (n MINUS 1)) RAND b (n MINUS 1)"
      notices (people <> rules) `shouldReturn` [("could not check", "a")]
      t <- noticeText (people <> rules)
      t `shouldSatisfy` Text.isInfixOf "I could not check that this comes to an end, because `b` also uses itself directly, with no duty in between"
      t `shouldSatisfy` (not . Text.isInfixOf "`a` also uses itself")
      t `shouldSatisfy` (not . Text.isInfixOf "its HENCE")
      marked <- notices (people <> "@ends-because n drops by one\n" <> rules)
      map fst marked `shouldSatisfy` notElem "could not check"

    it "could not check, on two rules that each use themselves directly: names both" do
      t <- noticeText (people <> "GIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\na n MEANS IF n EQUALS 0 THEN FULFILLED ELSE (PARTY Alice MUST tick WITHIN 1 HENCE b (n MINUS 1)) RAND a (n MINUS 1)\n\nGIVEN n IS A NUMBER\nGIVETH A DEONTIC Person Action\nb n MEANS IF n EQUALS 0 THEN FULFILLED ELSE (PARTY Alice MUST tick WITHIN 1 HENCE a (n MINUS 1)) RAND b (n MINUS 1)")
      t `shouldSatisfy` Text.isInfixOf "I could not check that this comes to an end, because `a` and `b` also use themselves directly, with no duty in between"

    it "no time: WITHIN 0 LEST its own rule, and the text names no annotation when there is none" do
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST x")
        `shouldReturn` [("no time", "x")]
      t <- noticeText (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST x")
      t `shouldSatisfy` Text.isInfixOf "its deadline falls at the very moment each copy starts"
      t `shouldSatisfy` (not . Text.isInfixOf "@ends-because")

    it "multiplies: a LEST that starts two copies of its own rule, per missed deadline" do
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (x RAND x)")
        `shouldReturn` [("multiplies", "x")]
      t <- noticeText (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (x RAND x)")
      for_ ["starts 2 copies of itself at once", "joins them with RAND", "every time a deadline is missed", "doubles", "Nothing written limits"] \ needle ->
        t `shouldSatisfy` Text.isInfixOf needle

    it "but not a LEST that hands its rule to a helper that uses it once" $
      notices (people <> "GIVEN k IS A DEONTIC Person Action GIVETH A DEONTIC Person Action\nonce k MEANS k RAND (PARTY Bob MUST tick)\n\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (once x)")
        `shouldReturn` []

    it "multiplies: the #1075 shape, reported on the rule that holds the RAND" $
      notices (people <> "GIVETH A DEONTIC Person Action\nw1 MEANS PARTY Alice MUST tick WITHIN 2 LEST (w3 RAND w1)\n\nGIVETH A DEONTIC Person Action\nw3 MEANS PARTY Bob MUST tick WITHIN 3 LEST w1")
        `shouldReturn` [("multiplies", "w1")]

    it "but not two rules that hand on to each other one copy at a time" $
      notices (people <> "GIVETH A DEONTIC Person Action\nw1 MEANS PARTY Alice MUST tick WITHIN 2 LEST w3\n\nGIVETH A DEONTIC Person Action\nw3 MEANS PARTY Bob MUST tick WITHIN 3 LEST w1")
        `shouldReturn` []

    it "multiplies: a HENCE that starts two copies, each time the duty is done" do
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 HENCE (x RAND x)")
        `shouldReturn` [("multiplies", "x")]
      t <- noticeText (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 HENCE (x RAND x)")
      t `shouldSatisfy` Text.isInfixOf "every time the duty is done"

    it "but not a HENCE that starts its rule once" $
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 HENCE x")
        `shouldReturn` []

    it "multiplies, bounded by a countdown as written: the text says so" do
      let src = people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nb n MEANS IF n EQUALS 0 THEN FULFILLED ELSE PARTY Alice MUST tick WITHIN 1 LEST (b (n MINUS 1) RAND b (n MINUS 1))"
      notices src `shouldReturn` [("multiplies", "b")]
      t <- noticeText src
      for_ ["is given `n` less 1", "as many as 2 to the power of `n`"] \ needle ->
        t `shouldSatisfy` Text.isInfixOf needle
      t `shouldSatisfy` (not . Text.isInfixOf "Nothing written limits")

    it "but not a countdown that starts one copy at a time" $
      notices (people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nb n MEANS IF n EQUALS 0 THEN FULFILLED ELSE PARTY Alice MUST tick WITHIN 1 LEST b (n MINUS 1)")
        `shouldReturn` []

    it "multiplies and could not check: T6, a barrier HENCE over an empty roll, doubling" $
      notices (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN nobody MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE (x RAND x)")
        `shouldReturn` [("multiplies", "x"), ("could not check", "x")]

    it "but a barrier HENCE over an empty roll that starts one copy only could not be checked" $
      notices (tenants <> "GIVETH A DEONTIC Actor Action\nx MEANS EVERY Tenant t IN nobody MUST Sign t WITHIN 5 ONCE ALL HAVE HENCE x")
        `shouldReturn` [("could not check", "x")]

    it "multiplies: a RECORD whose HENCE starts two copies" $
      notices (people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nr n MEANS RECORD `a` IS n HENCE (r (n PLUS 1) RAND r (n PLUS 1))")
        `shouldReturn` [("multiplies", "r"), ("could not check", "r")]

    it "but a RECORD whose HENCE starts one copy only could not be checked" $
      notices (people <> "GIVEN n IS A NUMBER GIVETH A DEONTIC Person Action\nr n MEANS RECORD `a` IS n HENCE r (n PLUS 1)")
        `shouldReturn` [("could not check", "r")]

    it "nothing, on a module that does not check" $
      notices (people <> "GIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST x\n\ny MEANS 1 PLUS TRUE")
        `shouldReturn` []

  describe "@ends-because (L4)" do
    it "on the rule, silences could not check, and leaves a note at information level carrying its reason" do
      let src = people <> "@ends-because Alice is paid by then\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST x"
      notices src `shouldReturn` [("accepted", "x")]
      sevs <- noticeSeverities src
      sevs `shouldBe` [SInfo]
      t <- noticeText src
      t `shouldSatisfy` Text.isInfixOf "Alice is paid by then"

    it "does not silence no time, and the warning says so" do
      let src = people <> "@ends-because it stops\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 0 LEST x"
      notices src `shouldReturn` [("no time", "x")]
      t <- noticeText src
      t `shouldSatisfy` Text.isInfixOf "@ends-because does not silence this warning"

    it "does not silence multiplies, and the warning says so" do
      let src = people <> "@ends-because it stops\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 1 LEST (x RAND x)"
      notices src `shouldReturn` [("multiplies", "x")]
      t <- noticeText src
      t `shouldSatisfy` Text.isInfixOf "@ends-because does not silence this warning"

    it "counts only on the rule the warning is reported on, the first of the cycle" do
      let cyc mark1 mark3 = people
            <> mark1 <> "GIVETH A DEONTIC Person Action\nw1 MEANS PARTY Alice MUST tick WITHIN 1 OF 2 LEST w3\n\n"
            <> mark3 <> "GIVETH A DEONTIC Person Action\nw3 MEANS PARTY Bob MUST tick WITHIN 1 OF 3 LEST w1"
      notices (cyc "" "") `shouldReturn` [("could not check", "w1")]
      notices (cyc "@ends-because Bob pays\n" "") `shouldReturn` [("accepted", "w1")]
      notices (cyc "" "@ends-because Bob pays\n") `shouldReturn` [("could not check", "w1")]
      t <- noticeText (cyc "" "@ends-because Bob pays\n")
      t `shouldSatisfy` Text.isInfixOf "The @ends-because above `w3` does not count here: it goes above `w1`"

    it "is taken silently on a function cycle" $
      notices (people <> "@ends-because n drops by one\nGIVEN n IS A NUMBER GIVETH A NUMBER\ndown n MEANS IF n EQUALS 0 THEN 0 ELSE down (n MINUS 1)")
        `shouldReturn` []

    it "is taken silently on an obligation cycle shown to end" $
      notices (people <> "@ends-because Alice ticks\nGIVETH A DEONTIC Person Action\nx MEANS PARTY Alice MUST tick WITHIN 30 LEST x")
        `shouldReturn` []

    it "is taken silently on a rule that never leads back to itself" $
      notices (people <> "@ends-because it ends\nGIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS n PLUS 1")
        `shouldReturn` []

    it "on a WHERE name read through, on the lap, is on the cycle, and not the rule reported on" do
      let src = people <> "GIVEN d IS A NUMBER GIVETH A DEONTIC Person Action\nz d MEANS PARTY Alice MUST tick WITHIN d LEST next\n  WHERE\n    @ends-because d halves\n    next MEANS z (d DIVIDED BY 2)"
      notices src `shouldReturn` [("could not check", "z")]
      t <- noticeText src
      t `shouldSatisfy` Text.isInfixOf "The @ends-because above `next` does not count here"

    it "on a WHERE name read through, off any lap, is taken silently" $
      notices (people <> "GIVEN n IS A NUMBER GIVETH A NUMBER\nf n MEANS m PLUS 1\n  WHERE\n    @ends-because it ends\n    m MEANS n TIMES 2")
        `shouldReturn` []

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

-- | A function of any's type whose body is @use@.
smuggling :: Text -> Text
smuggling use = "GIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO BOOLEAN\n      xs IS A LIST OF a\nGIVETH A BOOLEAN\nsmuggle f xs MEANS " <> use <> "\n\n"

-- | A function that adds what @f@ gives for each element, walking the list
-- in a WHERE, with @onEmpty@ for the empty list's branch.
counting :: Text -> Text
counting onEmpty = "GIVEN a IS A TYPE\n      f IS A FUNCTION FROM a TO NUMBER\n      xs IS A LIST OF a\nGIVETH A NUMBER\ncount f xs MEANS go xs\n  WHERE\n    go l MEANS\n      CONSIDER l\n      WHEN EMPTY " <> onEmpty <> "\n      WHEN y FOLLOWED BY ys THEN f y PLUS go ys\n\n"

tree :: Text
tree = "IMPORT prelude\nDECLARE Tree HAS\n  label IS A NUMBER\n  kids IS A LIST OF Tree\n\n"

-- | Two definitions that call each other, one naming @k@ times a WHERE name
-- whose body calls the other ten times: @10 k@ edges in one cycle.
namedTenTimes :: Int -> Text
namedTenTimes k = Text.unlines
  [ "GIVEN n IS A NUMBER GIVETH A NUMBER"
  , "f n MEANS IF n > 100 THEN 0 ELSE " <> Text.intercalate " PLUS " (replicate k "t")
  , "  WHERE t MEANS " <> Text.intercalate " PLUS " ["g " <> Text.pack (show i) | i <- [1 .. 10 :: Int]]
  , ""
  , "GIVEN n IS A NUMBER GIVETH A NUMBER"
  , "g n MEANS f (n PLUS 1)"
  ]

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
checkedIn vfs = checkedResult . checkWithImports vfs

-- | A module checked under its own name, as a library is.
checkedAs :: Text -> Text -> IO (Substitution, EntityInfo, Module Resolved)
checkedAs name = checkedResult . checkWithImportsAndUri emptyVFS name

checkedResult :: Either [Text] TypeCheckWithDepsResult -> IO (Substitution, EntityInfo, Module Resolved)
checkedResult = \ case
  Left errs -> fail ("pipeline failure: " <> show errs)
  Right r
    | r.tcdSuccess -> pure (r.tcdSubstitution, r.tcdEntityInfo, r.tcdModule)
    | otherwise -> fail ("did not type-check:\n" <> show (errorsOf r.tcdErrors))
 where
  errorsOf :: [CheckErrorWithContext] -> [CheckErrorWithContext]
  errorsOf = filter ((== SError) . severity)

findings :: Text -> IO [Finding]
findings = findingsIn emptyVFS

findingsIn :: VFS -> Text -> IO [Finding]
findingsIn vfs source =
  (\ (s, i, m@(MkModule _ uri _)) -> cycleFindingsWith apiLibraryFile (applyFinalSubstitution s uri) i m) <$> checkedIn vfs source

classes :: Text -> IO [Text]
classes source = sort . map findingClass <$> findings source

classesIn :: VFS -> Text -> IO [Text]
classesIn vfs source = sort . map findingClass <$> findingsIn vfs source

verdicts :: Text -> IO [Verdict]
verdicts source = map (.verdict) <$> findings source

-- | The cycle warnings and notes the checker gives a module, each as what it
-- is and the rule it is reported on.
notices :: Text -> IO [(Text, Text)]
notices source = map summary <$> cycleDiagnostics source
 where
  summary = \ case
    MkCheckErrorWithContext {kind = CheckWarning (CycleAlarm w)} -> (trouble w.trouble, w.rule)
    MkCheckErrorWithContext {kind = EndsBecauseAccepted w} -> ("accepted", w.rule)
    _ -> ("other", "")
  trouble = \ case
    CouldNotCheckThat _ -> "could not check"
    GivesNoTime _ -> "no time"
    StartsCopies _ -> "multiplies"

noticeText :: Text -> IO Text
noticeText source = Text.unlines . concatMap (\ e -> prettyCheckError e.kind) <$> cycleDiagnostics source

noticeSeverities :: Text -> IO [Severity]
noticeSeverities source = map severity <$> cycleDiagnostics source

cycleDiagnostics :: Text -> IO [CheckErrorWithContext]
cycleDiagnostics source = case checkWithImports emptyVFS source of
  Left errs -> fail ("pipeline failure: " <> show errs)
  Right r -> pure (filter isCycle r.tcdErrors)
 where
  isCycle e = case e.kind of
    CheckWarning (CycleAlarm _) -> True
    EndsBecauseAccepted _ -> True
    _ -> False

walkCheck :: Text -> Expectation
walkCheck source = do
  (_, i, m) <- checked source
  sort (map (.to) (moduleEdges i m)) `shouldBe` plainReferences m
