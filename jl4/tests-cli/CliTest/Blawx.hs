-- | Black-box tests for @l4 blawx@, @l4 blawx --import@ and the lift, with the
-- helpers only they use. Split out of @Main.hs@ so a release can be sliced
-- per backend.
module CliTest.Blawx (spec, fixtures) where

import Control.Monad (unless)
import Data.List (isInfixOf, isPrefixOf)
import System.Exit (ExitCode(..))
import Test.Hspec

import CliTest.Common

-- | R12's sharpest failure mode: a @.blawx@ row whose @xml_content@ is empty
-- while its @scasp_encoding@ is not.
--
-- Blawx draws a workspace only @if (output_object.xml_content)@
-- (@buttons.js:444@; a falsy value leaves the canvas cleared by @:441@) and
-- its Save writes @sCASP.workspaceToCode(demoWorkspace)@ straight back
-- (@:22-24@) — so opening such a row and saving DELETES the rule. The
-- headless fixpoint harness (@etc\/blawx-fixpoint-harness.mjs@) fails on the
-- same condition, but it is optional-when-present; this is the copy that runs
-- in CI on every event.
--
-- Both halves are asserted: the pairing in the emitted stream, and the
-- absence of the emitter's own stderr diagnostic for it.
noBlankedBlawxRow :: FilePath -> String -> IO ()
noBlankedBlawxRow bin stem = do
  Output code sout serr <- runL4 bin ["blawx", "examples/blawx/" ++ stem ++ ".l4"]
  code `shouldBe` ExitSuccess
  (stem, "no Blockly image" `isInfixOf` serr) `shouldBe` (stem, False)
  let fields = [f | l <- lines sout, Just f <- [blawxStoredField l]]
      traps =
        [ stem
        | (("xml_content", "''"), ("scasp_encoding", v)) <- zip fields (drop 1 fields)
        , v /= "''"
        ]
  traps `shouldBe` []

-- | An @ASSUME@-shaped seed and its record-spelled semantic twin must emit the
-- SAME s(CASP): same ontology, same rule stack, byte for byte, apart from the
-- first line — the generator's provenance comment, which names the source file
-- and is expected to differ.
--
-- This is the load-bearing property behind the tier-1 oracle for an
-- @ASSUME@-shaped module. Such a module has no evaluable directive at all
-- (@ASSUME@ is uninterpreted, and @lowerQuery@ builds a scenario only out of a
-- record-literal query argument), so the harness takes its expectations from the
-- twin, whose @#EVAL@s DO run under @l4 run@, and replays the twin's fact rows
-- against the @ASSUME@ seed's own workspaces. That replay only means anything
-- while the two spellings share their atoms — otherwise every replayed query
-- finds no model and every FALSE expectation "passes". Asserting it here makes
-- a drifting field name a red test rather than a quietly weaker harness.
twinsAgree :: FilePath -> (String, String) -> IO ()
twinsAgree bin (seed, twin) = do
  Output codeA soutA _ <- runL4 bin ["blawx", "examples/blawx/" ++ seed ++ ".l4", "--scasp"]
  Output codeB soutB _ <- runL4 bin ["blawx", "examples/blawx/" ++ twin ++ ".l4", "--scasp"]
  codeA `shouldBe` ExitSuccess
  codeB `shouldBe` ExitSuccess
  let body = drop 1 . lines
  (seed, body soutA) `shouldBe` (seed, body soutB)

-- | @    xml_content: |-@ → @Just ("xml_content","|-")@. Four-space indent
-- exactly, so the six-space block-scalar content lines (which are full of
-- colons — @xmlns=\"http:\/\/…\"@) cannot masquerade as fields.
blawxStoredField :: String -> Maybe (String, String)
blawxStoredField l
  | not ("    " `isPrefixOf` l) || "     " `isPrefixOf` l = Nothing
  | otherwise = case break (== ':') (drop 4 l) of
      (k, ':' : v) | k `elem` ["xml_content", "scasp_encoding"] ->
        Just (k, dropWhile (== ' ') v)
      _ -> Nothing

-- | Files this module's tests need to exist. 'Main.main' checks every
-- module's list before hspec runs anything; nothing here is checked up front
-- today, because the files these tests read are named inline in the tests.
fixtures :: [FilePath]
fixtures = []

spec :: FilePath -> Spec
spec bin = do
  describe "l4 blawx" $ do
    it "compiles the Appendix-A benefit example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/benefit.l4"]
                       "examples/blawx/expected/benefit.blawx"

    it "dumps benefit's concatenated s(CASP) (--scasp) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/benefit.l4", "--scasp"]
                       "examples/blawx/expected/benefit.pl"

    it "compiles the minimal mortality example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/mortality.l4"]
                       "examples/blawx/expected/mortality.blawx"

    it "dumps mortality's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/mortality.l4", "--scasp"]
                       "examples/blawx/expected/mortality.pl"

    it "compiles the aggregates example (findall + *_blawx_list) to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/scores.l4"]
                       "examples/blawx/expected/scores.blawx"

    it "dumps scores' s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/scores.l4", "--scasp"]
                       "examples/blawx/expected/scores.pl"

    it "compiles the structural-recursion example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/sumlist.l4"]
                       "examples/blawx/expected/sumlist.blawx"

    it "dumps sumlist's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/sumlist.l4", "--scasp"]
                       "examples/blawx/expected/sumlist.pl"

    it "compiles the rodents-and-vermin exclusion to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/rodents.l4"]
                       "examples/blawx/expected/rodents.blawx"

    it "dumps rodents' s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/rodents.l4", "--scasp"]
                       "examples/blawx/expected/rodents.pl"

    it "compiles the ASSUME-shaped anti-social example to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/antisocial.l4"]
                       "examples/blawx/expected/antisocial.blawx"

    it "dumps antisocial's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/antisocial.l4", "--scasp"]
                       "examples/blawx/expected/antisocial.pl"

    it "compiles antisocial's record-spelled semantic twin to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/antisocial-twin.l4"]
                       "examples/blawx/expected/antisocial-twin.blawx"

    it "dumps the antisocial twin's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/antisocial-twin.l4", "--scasp"]
                       "examples/blawx/expected/antisocial-twin.pl"

    it "compiles the ASSUME-shaped alcohol act to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/alcohol.l4"]
                       "examples/blawx/expected/alcohol.blawx"

    it "dumps alcohol's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/alcohol.l4", "--scasp"]
                       "examples/blawx/expected/alcohol.pl"

    it "compiles alcohol's record-spelled semantic twin to its golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/alcohol-twin.l4"]
                       "examples/blawx/expected/alcohol-twin.blawx"

    it "dumps the alcohol twin's s(CASP) to its golden .pl" $
      expectGolden bin ["blawx", "examples/blawx/alcohol-twin.l4", "--scasp"]
                       "examples/blawx/expected/alcohol-twin.pl"

    -- P4c, the statute showcase: Housing Act 1988 Sch 2 grounds 8, 13, 15 and
    -- 17 inlined into ONE module (`buildCtx` is module-scoped, so an aggregator
    -- that IMPORTed them would emit queries against an ontology that does not
    -- exist). Four records in one Blawx namespace, 49 oracle-anchored
    -- directives, and the corpus's only arity-2 computed predicate.
    it "compiles the four Housing Act grounds to their golden .blawx stream" $
      expectGolden bin ["blawx", "examples/blawx/housing-grounds.l4"]
                       "examples/blawx/expected/housing-grounds.blawx"

    it "compiles the four Housing Act grounds to their golden s(CASP) dump" $
      expectGolden bin ["blawx", "examples/blawx/housing-grounds.l4", "--scasp"]
                       "examples/blawx/expected/housing-grounds.pl"

    -- The arity-2 gap, pinned rather than assumed. `per-period threshold met`
    -- is (Ground8Claim, NUMBER) -> BOOLEAN: total arity 2 with the boolean
    -- output dropped, and its second parameter is neither record- nor
    -- enum-sorted, so it is not attribute-shaped and does not reach the arity-3
    -- relationship form either. It therefore gets NO `blawx_attribute`
    -- declaration (`L4.Blawx.Lower`, the recorded relationships-start-at-arity-3
    -- gap) while its rules and its four query rows DO emit. This asserts both
    -- halves: the declaration is absent, and nothing downstream blanks — the
    -- `noBlankedBlawxRow` row below covers the images, and the headless fixpoint
    -- harness re-saves every one of them. If a later change starts declaring
    -- arity-2 predicates, this test is the one to delete.
    it "emits an undeclared but imaged arity-2 predicate (the recorded gap)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/housing-grounds.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("per_period_threshold_met(Claim,Arrears)" `isInfixOf`)
      sout `shouldSatisfy` ("?- per_period_threshold_met(g1,1300)." `isInfixOf`)
      sout `shouldSatisfy`
        (not . ("blawx_attribute(ground8_claim,per_period_threshold_met" `isInfixOf`))
      -- and the four records really did land in one namespace, un-collided
      mapM_ (\c -> sout `shouldSatisfy` (("blawx_category(" ++ c ++ ")") `isInfixOf`))
        ["ground8_claim", "ground13_claim", "ground15_claim", "ground17_claim"]
      -- the rename that made that possible: the enum keeps `rent_period`, the
      -- field became `the basis on which rent is payable`
      sout `shouldSatisfy` ("blawx_category(rent_period)" `isInfixOf`)
      sout `shouldSatisfy`
        ("blawx_attribute(ground8_claim,the_basis_on_which_rent_is_payable" `isInfixOf`)
      -- the interview follows the FIRST @export: the mandatory ground
      sout `shouldSatisfy` ("?- ground_8_made_out(X)." `isInfixOf`)

    -- The twin discipline, as a property rather than a comment. An
    -- `ASSUME`-shaped seed has no evaluable directive, so `etc/blawx-tier1-harness.py`
    -- takes its expectations from a record-spelled twin and replays the twin's
    -- fact rows against the ASSUME seed's own workspaces. That is only sound if
    -- the two spellings share their atoms, and this is the assertion that they
    -- do: the emitted s(CASP) is identical apart from the first line, which is
    -- the provenance comment naming the source file. If someone renames a field
    -- in a twin "for readability", this fails here rather than degrading the
    -- tier-1 run into a comparison of two unrelated programs.
    it "emits byte-identical s(CASP) for an ASSUME seed and its record twin" $
      mapM_ (twinsAgree bin)
        [("antisocial", "antisocial-twin"), ("alcohol", "alcohol-twin")]

    it "never blanks a row's xml_content while its scasp_encoding is non-empty (R12)" $
      mapM_ (noBlankedBlawxRow bin)
        [ "benefit", "mortality", "scores", "sumlist", "rodents"
        , "antisocial", "antisocial-twin", "alcohol", "alcohol-twin"
        , "housing-grounds" ]

    it "carries the @export prose into rule_text, and falls back to @ref (structural)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/antisocial.l4"]
      code `shouldBe` ExitSuccess
      -- arm A: a decision carrying BOTH @export prose and @ref shows the prose
      sout `shouldSatisfy`
        ("1. Anti-social Behaviour, Crime and Policing Act 2014 s.43(1): an authorised person"
           `isInfixOf`)
      -- arm B: a bare @export with only a @ref shows the citation, not the stub
      sout `shouldSatisfy`
        ("5. Anti-social Behaviour, Crime and Policing Act 2014, s.43(1)(b)" `isInfixOf`)
      sout `shouldSatisfy`
        (not . ("Definition of the conduct is unreasonable." `isInfixOf`))
      -- the P1 earmark discharged: an interview on a module with no DECLARE
      sout `shouldSatisfy` ("#abducible person(X)." `isInfixOf`)
      sout `shouldSatisfy` ("#abducible conduct(X,Y)." `isInfixOf`)
      sout `shouldSatisfy` ("?- may_issue_a_community_protection_notice(X,Y)." `isInfixOf`)
      -- the reachability gate: an ASSUME no clause reaches contributes nothing
      sout `shouldSatisfy` (not . ("effect_target" `isInfixOf`))

    it "gives NOT over an ASSUMEd input classical negation, not NAF (R5)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/alcohol.l4", "--scasp"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("-the_proprietor_corrects_the_price_list(Pr)." `isInfixOf`)
      sout `shouldSatisfy` (not . ("not the_proprietor_corrects_the_price_list" `isInfixOf`))

    it "rejects a subjectless ASSUMEd input rather than blanking its row" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/zero-arity.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("no category subject" `isInfixOf`)
      -- the refused band is an ARITY band; the message must say so, because
      -- `arity-two.l4` below satisfies "first parameter is a category" and is
      -- refused anyway
      serr `shouldSatisfy` ("total arity 0" `isInfixOf`)
      serr `shouldSatisfy` ("start at total arity 3" `isInfixOf`)

    it "rejects a two-place ASSUMEd input EVEN WITH a category first parameter" $ do
      -- The other half of the refused band. `classifyPred` places an input as
      -- an attribute only at (category) or (category) -> value; relationship
      -- blocks start at total arity 3; a two-place input falls between them.
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/arity-two.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("no category subject" `isInfixOf`)
      serr `shouldSatisfy` ("`severity exceeds` is an input of total arity 2" `isInfixOf`)
      -- and it must NOT tell an author who already has a category subject to
      -- add one: that was the old wording, and it named no reachable fix
      serr `shouldSatisfy` (not . ("first parameter is not a category" `isInfixOf`))

    it "emits the ruledoc first, then workspaces with the dedup-marked triple (structural smoke)" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/benefit.l4"]
      code `shouldBe` ExitSuccess
      -- R1: exactly one ruledoc row, FIRST — before any workspace row
      firstLineWith "- model: blawx.ruledoc" sout
        `shouldSatisfy` (< firstLineWith "- model: blawx.workspace" sout)
      sout `shouldSatisfy` ("workspace_name: root_section" `isInfixOf`)
      sout `shouldSatisfy` ("workspace_name: sec_1_section" `isInfixOf`)
      sout `shouldSatisfy` (":- dynamic applicant/1." `isInfixOf`)
      sout `shouldSatisfy` ("% BLAWX CHECK DUPLICATES" `isInfixOf`)
      sout `shouldSatisfy` ("?- benefit_amount(a1,Benefitamount)." `isInfixOf`)
      -- R11: the #ASSERT-as-constraint emission and the #abducible interview test
      sout `shouldSatisfy` ("false :- not eligible_for_benefit(a1)." `isInfixOf`)
      sout `shouldSatisfy` ("false :- not benefit_amount(a1,1250)." `isInfixOf`)
      sout `shouldSatisfy` ("test_name: interview" `isInfixOf`)
      sout `shouldSatisfy` ("#abducible applicant(X)." `isInfixOf`)
      sout `shouldSatisfy` ("#abducible age(X,Y)." `isInfixOf`)
      sout `shouldSatisfy` ("#abducible is_veteran(X)." `isInfixOf`)
      sout `shouldSatisfy` ("?- eligible_for_benefit(X)." `isInfixOf`)

    it "refuses -o FILE.pl without --scasp (the dump would clobber its own YAML)" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/benefit.l4",
                                       "-o", "examples/blawx/refused.pl"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--scasp" `isInfixOf`)

    it "rejects a DATE-sorted field by name (Blawx v1)" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/dates.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("dates (Blawx v1)" `isInfixOf`)

    it "rejects an unstratified module (the middle-end records, this leg refuses)" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/unstratified.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("unstratified negation (Blawx v1)" `isInfixOf`)

    it "rejects EQUALS on record-typed operands (§11 W1, the silent one)" $ do
      -- This fixture is Jason Morris's own reading of RPS s.4 and it USED to
      -- lower clean: L4 answered TRUE, the tier-1 harness found no model,
      -- because R11's flattening emits one object per occurrence of a record
      -- value. A wrong answer with a green exit code is the worst outcome a
      -- transpiler has, so the refusal is loud and both operand positions of
      -- the IF/ELSE (the REq and its complement RNeq) are covered.
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/record-identity.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("record identity (Blawx)" `isInfixOf`)
      serr `shouldSatisfy` ("EQUALS on operands of record type `Player`" `isInfixOf`)
      serr `shouldSatisfy` ("a disequality on operands of record type `Player`" `isInfixOf`)
      serr `shouldSatisfy` ("once per slot" `isInfixOf`)

    it "rejects it inside a container too (LIST OF, and LIST OF MAYBE)" $ do
      -- The first cut of the §11 W1 refusal tested the operand sort for a
      -- record at the top only, so `a's members EQUALS b's members` over a
      -- `LIST OF Player` lowered clean and emitted `Members = Members2`. Both
      -- rules in this fixture are refused now, and each diagnostic names the
      -- operand's OWN sort, because "of record type `Player`" would be a false
      -- description of a list.
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/record-identity-list.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("type `LIST OF Player`, which contains the record type `Player`" `isInfixOf`)
      serr `shouldSatisfy` ("type `LIST OF MAYBE Player`, which contains the record type `Player`" `isInfixOf`)

    -- Integration, 2026-09-02 (§11 W1). W1's note said the `RSOpaque` escape
    -- was "not known to be reachable in the M1 fragment, and none was
    -- constructed". It is reachable through `IMPORT`, and this is the
    -- construction: a record DECLAREd in an imported module arrives as
    -- `RSOpaque "Shared Ontology.Player"` — a printed name with no `RName`
    -- behind it — so `recordInSort` had nothing to look up and the comparison
    -- lowered at exit 0, emitting the `A = B` identity W1 exists to refuse.
    it "rejects EQUALS on an IMPORTed record, whose sort reaches us opaque" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "tests-cli/fixtures/blawx-opaque/imported-record-identity.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("record identity (Blawx)" `isInfixOf`)
      serr `shouldSatisfy` ("opaque type `Shared Ontology.Player`" `isInfixOf`)
      serr `shouldSatisfy` ("no name to look up" `isInfixOf`)

    it "rejects a relationship above the arity-10 block ceiling" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/arity.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("above the block ceiling of 10" `isInfixOf`)

    -- Spec §11 W3(b): a pinned section whose text opens with a SECOND index is
    -- a sub-provision, and emitting it hands clean-law the insert index `4. 5`
    -- -- eId sec_4_5 against the workspace sec_4_section we wrote, i.e. an
    -- orphaned canvas in a document that imports and stores without complaint.
    it "rejects a pinned section whose text opens with another index" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/sub-provision-index.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("sub-provision index (Blawx v1)" `isInfixOf`)
      serr `shouldSatisfy` ("orphaning" `isInfixOf`)

    -- Integration, 2026-09-02 (§8.4, §11 W3). The number/eId invariant W3 built
    -- has a third road into it: clean-law's `legal_text` is pyparsing
    -- `printables`, which is ASCII-only, so ANY character above U+007F ends the
    -- parse there and orphans every later canvas. `asciiFold` folds what
    -- legislation actually contains; the residue is refused.
    it "rejects a section text carrying a character clean-law cannot lex" $ do
      Output code _ serr <- runL4 bin ["blawx", "examples/blawx/not-ok/section-text-non-ascii.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("non-ASCII section text (Blawx v1)" `isInfixOf`)
      serr `shouldSatisfy` ("U+00A3" `isInfixOf`)
      serr `shouldSatisfy` ("orphaned" `isInfixOf`)

    -- ... and the characters legislation.gov.uk actually serves are FOLDED, not
    -- refused: a curly apostrophe would otherwise make every UK statute paste
    -- unemittable. The fixture above pins the refusal; this pins the fold, on
    -- the seed corpus, which carries ten U+2014 em dashes across five files.
    it "folds the punctuation legislation carries rather than refusing it" $ do
      Output code sout _ <- runL4 bin ["blawx", "examples/blawx/antisocial.l4"]
      code `shouldBe` ExitSuccess
      -- the ten U+2014 em dashes across the seed corpus become hyphens, and
      -- none of them reaches the emitted rule_text
      sout `shouldSatisfy` (not . ("\x2014" `isInfixOf`))

    it "fails on a file that does not typecheck" $
      expectFail bin ["blawx", errorFixture]

  -- The import direction (R14, spec §10 P5). `lift . emit = id` has two
  -- halves; this is the parse half, and it is checked in the only way that
  -- needs no foreign toolchain and no external corpus: emit a real document,
  -- read it back through every layer, and compare both the IR and the bytes.
  describe "l4 blawx --import" $ do
    it "round-trips each P1/P3 seed: emit -> parse -> the same block IR and the same bytes" $
      mapM_
        (\stem -> do
            Output code sout serr <- runL4 bin ["blawx", "examples/blawx/" ++ stem ++ ".l4", "--roundtrip"]
            unless (code == ExitSuccess) $
              expectationFailure (stem ++ ": --roundtrip failed\n--- stderr ---\n" ++ serr)
            sout `shouldSatisfy` ("IR and bytes unchanged" `isInfixOf`))
        ["benefit", "mortality", "scores", "sumlist"]

    it "parses an emitted .blawx back and reports a clean census" $ do
      Output code sout serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "examples/blawx/expected/mortality.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("--import --parse-only failed\n--- stderr ---\n" ++ serr)
      -- One machine-readable line, so the census harness need not scrape prose.
      sout `shouldSatisfy` ("CENSUS mortality clean" `isInfixOf`)
      sout `shouldSatisfy` ("workspaces=2 tests=3" `isInfixOf`)
      -- Our own emission is by construction not stale, so nothing warns.
      serr `shouldSatisfy` (not . ("stale-encoding" `isInfixOf`))

    it "names the row and the block when a document is outside the liftable fragment" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/unsupported.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-parse/unsupported-block" `isInfixOf`)
      serr `shouldSatisfy` ("sec_1_section" `isInfixOf`)
      serr `shouldSatisfy` ("date_value" `isInfixOf`)

    it "warns per skipped disabled block rather than silently dropping it (P5-3)" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/disabled.blawx"]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` ("blawx-parse/disabled-block-skipped" `isInfixOf`)
      serr `shouldSatisfy` ("skipped disabled <query>" `isInfixOf`)

    it "refuses a stream whose first row is not the ruledoc" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/no-ruledoc.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-parse/row-order" `isInfixOf`)

    it "refuses XML outside the Blockly subset by name and offset" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "--parse-only", "tests-cli/fixtures/blawx-import/bad-xml.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-parse/xml-malformed" `isInfixOf`)
      serr `shouldSatisfy` ("mismatched close tag" `isInfixOf`)

    -- `l4 blawx` has no --help of its own (the subcommand parsers carry no
    -- helper), so the usage banner optparse prints on a bad option is where
    -- the surface is documented. Asserting on it keeps the new flags from
    -- being added to the parser and forgotten in the spec.
    it "documents the new flags in the usage banner" $ do
      Output code _ serr <- runL4 bin ["blawx", "--help"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("--import" `isInfixOf`)
      serr `shouldSatisfy` ("--parse-only" `isInfixOf`)
      serr `shouldSatisfy` ("--reemit" `isInfixOf`)

  -- The lift (R14's other half). Its evidence is `jl4/examples/blawx/imported/`,
  -- both halves of which the pipeline produced: `bird.l4` is what the lift
  -- emitted from upstream's own bird.yaml, and `bird.blawx` is what the
  -- renderers re-emitted from the same parsed blocks. The reference checkout
  -- is NOT a test dependency -- these tests read only what is committed.
  describe "l4 blawx --import (the lift)" $ do
    it "the committed bird artifact evaluates to the oracles recorded in it" $ do
      Output code sout serr <- runL4 bin ["run", "--trace", "none", "examples/blawx/imported/bird.l4"]
      unless (code == ExitSuccess) $
        expectationFailure ("l4 run on the lifted bird failed\n--- stderr ---\n" ++ serr)
      -- The four blawxtests, in document order: an unbound query filtered over
      -- the declared universe, then the three defeat-layer booleans. The last
      -- is the one the whole example exists for -- the [pingu] span makes NBA 5
      -- inapplicable, so NBA 3 survives and pingu cannot fly.
      let ls = lines sout
          results = [dropWhile (== ' ') l | (prev, l) <- zip ls (drop 1 ls), prev == "Result:"]
      results `shouldBe` ["LIST \"pingu\"", "TRUE", "TRUE", "TRUE"]

    it "re-lifting the re-emitted .blawx reproduces the same rules and the same oracles" $ do
      Output code sout serr <- runL4 bin ["blawx", "--import", "examples/blawx/imported/bird.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("--import on the re-emitted bird failed\n--- stderr ---\n" ++ serr)
      -- The applies-idiom, the unfolded defeat layer, and the recorded answers.
      sout `shouldSatisfy` ("DECIDE `NBA 5 applies to x` x" `isInfixOf`)
      sout `shouldSatisfy` ("IF naf (`it is not the case that NBA 5 applies to x` x)" `isInfixOf`)
      sout `shouldSatisfy` ("AND NOT `the conclusion in NBA 2 that x can fly is defeated` x" `isInfixOf`)
      sout `shouldSatisfy` ("-- L4 oracle ==> LIST \"pingu\"" `isInfixOf`)
      length (filter ("-- L4 oracle ==> " `isPrefixOf`) (lines sout)) `shouldBe` 4

    it "refuses a document outside the liftable fragment, naming every construct" $ do
      Output code _ serr <- runL4 bin ["blawx", "--import", "examples/blawx/expected/sumlist.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("cannot lift this document to L4" `isInfixOf`)
      -- an n-ary relation is not a unary predicate over the object universe
      serr `shouldSatisfy` ("blawx-lift/relationship" `isInfixOf`)
      serr `shouldSatisfy` ("total_from/3" `isInfixOf`)
      -- and the refusal is BATCHED: one run names them all, so a caller does
      -- not have to fix them one at a time.
      serr `shouldSatisfy` ("go/4" `isInfixOf`)

    -- BLAWX-EXPORT-SPEC §11 W5 made `number` attributes liftable — as an
    -- input field plus an accessor — so the claim this test used to pin
    -- ("a non-boolean attribute is refused") is no longer true. What still
    -- has no image is a rule that DERIVES a value-typed attribute
    -- (benefit.blawx concludes `benefit_amount(A, Tmp)` from `Tmp is
    -- 1000 + Bonus`), and it is refused by its own name.
    it "refuses a value-typed attribute a rule CONCLUDES, by name" $ do
      Output code _ serr <- runL4 bin ["blawx", "--import", "examples/blawx/expected/benefit.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-lift/value-attribute-concluded" `isInfixOf`)
      serr `shouldSatisfy` ("blawx-lift/conclusion-shape" `isInfixOf`)

    -- Jason Morris's own Beard Tax Act, the second of the two shipped
    -- examples §11 W5 sized the lift against. Everything this asserts was
    -- refused by name before that increment: the `number` attribute, the
    -- binary attribute goal, `blawx_comparison(L,gte,5)`, the paragraph
    -- workspaces, and the free-variable test query.
    it "lifts Blawx's own beard_tax, comparisons and paragraphs included" $ do
      Output code sout serr <- runL4 bin
        ["blawx", "--import", "examples/blawx/imported/beard_tax.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("beard_tax did not lift\n--- stderr ---\n" ++ serr)
      -- the number attribute: one MAYBE NUMBER field, one definedness
      -- decision, one accessor
      sout `shouldSatisfy` ("facial_hair_length_mm           IS A MAYBE NUMBER" `isInfixOf`)
      sout `shouldSatisfy` ("IF isJust (x's facial_hair_length_mm)" `isInfixOf`)
      sout `shouldSatisfy` ("MEANS fromMaybe 0 (x's facial_hair_length_mm)" `isInfixOf`)
      -- blawx_comparison(Length, gte, 5)
      sout `shouldSatisfy` ("AND `the facial_hair_length_mm of` x AT LEAST 5" `isInfixOf`)
      -- two attributed_rules concluding `bearded` in s.1: one decision each,
      -- OR-ed by `according_to`
      sout `shouldSatisfy` ("`according to BTA 1, x is bearded (clause 1)` x" `isInfixOf`)
      sout `shouldSatisfy` ("OR `according to BTA 1, x is bearded (clause 2)` x" `isInfixOf`)
      -- the paragraph rules are filed under the parent section, and say so
      serr `shouldSatisfy` ("blawx-lift/rule-section-flattened" `isInfixOf`)
      sout `shouldSatisfy` ("sec_1__para_a_section attributed_rule" `isInfixOf`)
      -- `?- bearded(Person)` over an empty universe: provenance, no #EVAL
      serr `shouldSatisfy` ("blawx-lift/unbound-query-empty-universe" `isInfixOf`)
      sout `shouldSatisfy` ("-- blawxtest are_they_bearded" `isInfixOf`)
      length (filter ("#EVAL" `isPrefixOf`) (lines sout)) `shouldBe` 0

    -- __The defect the paragraph fold shipped with__ (§11 W5), and the reason
    -- these two fixtures exist. Both are Jason Morris's `beard_tax.yaml` with
    -- the two `sec_1__para_a_section` rules made `defeasible TRUE` and one
    -- `overrules` block appended to `sec_1_section`'s XML, defeating
    -- `qualifies_s1a`; they differ only in which section the DEFEATING
    -- `doc_selector` names.
    --
    -- `paragraph-defeat-ok.blawx` names `sec_1__para_b_section`, the
    -- paragraph that actually concludes `qualifies_s1b`. The fold is
    -- extension-preserving, so the defeat survives it. Before the fix the
    -- rules were filed under the FOLDED section while the `overrules` was
    -- keyed on the RAW paragraph: the `AND NOT <defeated>` conjunct was never
    -- emitted, the `… is defeated` decision was defined and never used, and
    -- the lift exited 0 with warnings only.
    it "keeps a defeat whose sections are paragraphs (§11 W5)" $ do
      Output code sout serr <- runL4 bin
        ["blawx", "--import", "tests-cli/fixtures/blawx-import/paragraph-defeat-ok.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("paragraph-defeat-ok did not lift\n--- stderr ---\n" ++ serr)
      sout `shouldSatisfy`
        ("AND NOT `the conclusion in BTA 1 that x qualifies under section 1 a is defeated` x" `isInfixOf`)
      -- the sentence the old artifact printed in its place, which was false
      sout `shouldSatisfy` (not . ("no overrules names BTA 1 as defeated" `isInfixOf`))
      -- and the fold is disclosed on the defeat too, not only on the rules
      serr `shouldSatisfy` ("blawx-lift/defeat-section-flattened" `isInfixOf`)
      serr `shouldSatisfy` ("sec_1__para_a_section" `isInfixOf`)

    -- `paragraph-defeat.blawx` is the review counterexample verbatim: its
    -- DEFEATING `doc_selector` names `sec_1_section`, the flat parent, which
    -- no rule is attributed to. s(CASP) keys `holds/3` on the exact section,
    -- so `holds(sec_1_section,qualifies_s1b,X)` has no clause and the defeat
    -- never fires in Blawx — measured with swipl over the re-emitted program:
    -- `?- qualifies_s1a(p).` answers MODEL in all four scenarios. Folding it
    -- would give the defeat a body the source does not have, so it is refused
    -- by name instead.
    it "refuses an `overrules` the fold would activate, by name (§11 W5)" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "tests-cli/fixtures/blawx-import/paragraph-defeat.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-lift/defeat-target" `isInfixOf`)
      serr `shouldSatisfy` ("holds(sec_1_section,qualifies_s1b,X)" `isInfixOf`)

    -- __The APPLICABILITY layer's half of the same fold hazard__, found in
    -- review of W5a and closed at integration (2026-09-02). The fixture is
    -- Jason Morris's own bird.yaml with ONE empty workspace
    -- (`sec_5__para_a_section`) added and two `doc_selector` section_references
    -- repointed at it, so the `inapplicable TRUE` attributed_rule is attributed
    -- to a PARAGRAPH. `scasp_generator.js:1188-1194` injects
    -- `blawx_applies(<the rule's own section>, X)`, so Blawx asks
    -- `blawx_applies(sec_5__para_a_section, X)`, which has no clause at all;
    -- the lift injected the PARENT's gate, which is derivable. Measured before
    -- the fix: exit 0, warnings only, `l4 check` clean, and the two engines
    -- disagreed — L4 TRUE, s(CASP) NOMODEL, with a hand-added
    -- `blawx_applies(sec_5__para_a_section,A) :- not -blawx_applies(...)`
    -- flipping it back. Refused by name now, exactly as `defeat-target` is.
    it "refuses an `inapplicable` rule the fold would re-gate, by name" $ do
      Output code _ serr <- runL4 bin
        ["blawx", "--import", "tests-cli/fixtures/blawx-import/paragraph-applies.blawx"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("blawx-lift/applies-target" `isInfixOf`)
      serr `shouldSatisfy` ("blawx_applies(sec_5__para_a_section,X)" `isInfixOf`)

    it "--reemit writes the .blawx regenerated from the parsed blocks" $ do
      Output code sout serr <- runL4 bin
        ["blawx", "--import", "--reemit", "examples/blawx/expected/mortality.blawx"]
      unless (code == ExitSuccess) $
        expectationFailure ("--reemit failed\n--- stderr ---\n" ++ serr)
      -- Our own emission parsed and re-emitted is byte-identical to itself;
      -- that is the byte half of `lift . emit = id`, reached through the CLI
      -- rather than through --roundtrip's in-process comparison.
      original <- readFile "examples/blawx/expected/mortality.blawx"
      sout `shouldBe` original
