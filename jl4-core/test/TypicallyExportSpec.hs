{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | What each interchange backend does with a @TYPICALLY@
-- (@specs\/todo\/TYPICALLY-ONE-BEHAVIOUR-SPEC.md@ ruling T5, work item W9).
--
-- The rule is "map it, or say you did not". These tests run each lowering over
-- small modules that differ in one thing, and assert on the lowering's own
-- output, so nothing here can drift from what @l4 export@ writes. The black-box
-- tests (@jl4\/tests-cli@) pin the wording a user reads; these pin the contract.
--
-- __The computed-default section is the one that has no other home.__ The
-- checker accepts only a literal @TYPICALLY@ today (R8 rule 3, work item W7, is
-- on another branch), so no source text can produce an expression default. A
-- backend that matches on the default's shape and has a fallback arm for
-- anything else must still be shown to reach that arm, or the first expression
-- default to arrive would find a backend that was never exercised on it. So
-- 'withComputedDefaults' rewrites every literal default of a CHECKED module into
-- an expression (@a PLUS b@) after the fact, and each backend is asked what it
-- does. Each answer is "maps it" or "refuses it, loudly"; none is "drops it".
module TypicallyExportSpec (spec) where

import Test.Hspec

import Data.Either (isLeft, isRight)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Annotation (emptyAnno)
import L4.Blawx.Emit (renderPlDumpWith)
import L4.Blawx.Lower (lowerBlawx)
import L4.Bpmn.Lower (bpmnDefaultNotes)
import qualified L4.Catala.Emit as CatalaEmit
import qualified L4.Catala.Lower as Catala
import L4.Dmn.IR (Drg (..), DmnFlavor (..), dmnReport)
import L4.Dmn.Lower
  ( DmnLowerOptions (..), lowerModule, resolveMaybePredicates )
import L4.Dmn.Markdown (markdownReport)
import qualified L4.Docassemble.Lower as Docassemble
import L4.Interchange.Fidelity (FidelityNote (..), FidelityReport (..))
import L4.Interchange.Typically
  ( DefaultKind (..), DefaultSite (..), classifyDefault
  , describeDefault, isLiteralDefault, moduleDefaultSites )
import qualified L4.OpenFisca.Emit as OpenFisca
import qualified L4.OpenFisca.Lower as OpenFisca
import L4.Relational.IR (RelProgram (..), renderLowerError)
import qualified L4.Relational.Lower as Relational
import L4.StateGraph (StateGraph (..), extractStateGraphs)
import L4.Syntax
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))
import qualified L4.Yscript.Lower as Yscript

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

-- | Typecheck a snippet. A module L4 rejects is a broken fixture, never the
-- thing under test, so it fails loudly here and not in an assertion further on.
-- The two export-publication refusals are stepped over for the reason
-- 'BlawxAssumeSpec' gives: they are about publishing a web API.
checked :: Text -> TypeCheckWithDepsResult
checked src = case checkWithImports emptyVFS src of
  Left errs -> error ("source failed to parse: " <> show errs)
  Right r
    | errs@(_ : _) <-
        [ e | e <- r.tcdErrors, TC.severity e == SError
            , not (TC.isExportPublicationRefusal e.kind) ] ->
        error ("source failed to typecheck: "
                 <> Text.unpack (Text.unlines (concatMap TC.prettyCheckErrorWithContext errs)))
    | otherwise -> r

moduleOf :: Text -> Module Resolved
moduleOf = (.tcdModule) . checked

-- | Rewrite every @TYPICALLY@ into an expression: a number @n@ becomes @n PLUS 1@
-- and anything else @IF d THEN d ELSE d@. Both are defaults the checker would
-- refuse today, and the shapes W7 will let through.
withComputedDefaults :: Module Resolved -> Module Resolved
withComputedDefaults = withDefaultsAs bump
 where
  bump e = case e of
    Lit _ (NumericLit _ _) -> Plus emptyAnno e (Lit emptyAnno (NumericLit emptyAnno 1))
    other                  -> IfThenElse emptyAnno other other other

-- | Replace every @TYPICALLY@ by what the function makes of it.
withDefaultsAs :: (Expr Resolved -> Expr Resolved) -> Module Resolved -> Module Resolved
withDefaultsAs bump (MkModule ann uri section) = MkModule ann uri (goSection section)
 where
  goSection (MkSection a n aka mgiven decls) =
    MkSection a n aka (fmap goGiven mgiven) (map goDecl decls)
  goGiven (MkGivenSig a otns) = MkGivenSig a (map goOtn otns)
  goOtn (MkOptionallyTypedName a n ty d) = MkOptionallyTypedName a n ty (fmap bump d)
  goDecl = \case
    Decide a (MkDecide da (MkTypeSig ta g gv) af body) ->
      Decide a (MkDecide da (MkTypeSig ta (goGiven g) gv) af body)
    Assume a (MkAssume aa ts af ty d) -> Assume a (MkAssume aa ts af ty (fmap bump d))
    Declare a (MkDeclare da ts af (RecordDecl ra con fields)) ->
      Declare a (MkDeclare da ts af
        (RecordDecl ra con [ MkTypedName fa n ty (fmap bump d) m | MkTypedName fa n ty d m <- fields ]))
    Section a s -> Section a (goSection s)
    other -> other

sitesOf :: Module Resolved -> [DefaultSite]
sitesOf = moduleDefaultSites

-- | A lowering that must succeed: a failure is a broken fixture, reported with
-- its reasons, not an incomplete pattern.
succeeds :: Either [Text] a -> a
succeeds = either (\es -> error ("expected success, got: " <> Text.unpack (Text.intercalate "; " es))) id

-- | A lowering that must refuse, with its reasons.
refuses :: Show a => Either [Text] a -> [Text]
refuses = either id (\a -> error ("expected a refusal, got: " <> show a))

-- ---------------------------------------------------------------------------
-- Sources
-- ---------------------------------------------------------------------------

-- | One of each place a @TYPICALLY@ can sit.
fourPlaces :: Text
fourPlaces = Text.unlines
  [ "DECLARE Config HAS"
  , "    timeout IS A NUMBER TYPICALLY 30"
  , "    retries IS A NUMBER"
  , ""
  , "§ `Rates`"
  , "    GIVEN rate IS A NUMBER TYPICALLY 3"
  , ""
  , "ASSUME allowance IS A NUMBER TYPICALLY 100"
  , ""
  , "@export Budget"
  , "GIVEN c IS A Config"
  , "      factor IS A NUMBER TYPICALLY 2"
  , "GIVETH A NUMBER"
  , "`budget` c factor MEANS (c's timeout) TIMES (c's retries) TIMES rate TIMES factor PLUS allowance"
  ]

-- | What Blawx admits: a defaulted record field and a defaulted rule GIVEN. (A
-- scalar section GIVEN or ASSUME has no category subject there and is refused
-- before it could carry anything, so 'fourPlaces' cannot reach the emitter.)
blawxSrc :: Text
blawxSrc = Text.unlines
  [ "DECLARE Config HAS"
  , "    timeout IS A NUMBER TYPICALLY 30"
  , "    retries IS A NUMBER"
  , ""
  , "@export Budget for a configuration"
  , "GIVEN c IS A Config"
  , "      rate IS A NUMBER TYPICALLY 3"
  , "GIVETH A NUMBER"
  , "`budget` c rate MEANS (c's timeout) TIMES (c's retries) TIMES rate"
  ]

-- | A decision with a rule GIVEN and a record field, both defaulted, and an
-- enum default on the rule's GIVEN (a record field cannot carry one, p10).
openFiscaSrc :: Text
openFiscaSrc = Text.unlines
  [ "DECLARE Status IS ONE OF single, married"
  , ""
  , "DECLARE Claimant HAS"
  , "    income IS A NUMBER"
  , "    `hours a week` IS A NUMBER TYPICALLY 40"
  , "    `is resident` IS A BOOLEAN TYPICALLY TRUE"
  , ""
  , "@export Allowance for a claimant"
  , "GIVEN c IS A Claimant"
  , "      period IS A STRING"
  , "      status IS A Status TYPICALLY married"
  , "      rate IS A NUMBER TYPICALLY 3"
  , "      label IS A STRING TYPICALLY \"standard\""
  , "GIVETH A NUMBER"
  , "allowance c period status rate label MEANS"
  , "  IF c's `is resident` AND (c's `hours a week`) >= 20"
  , "  THEN CONSIDER status"
  , "         WHEN single THEN c's income"
  , "         OTHERWISE (c's income) * rate"
  , "  ELSE 0"
  ]

-- | A bare scalar decision, for the lowerings that take a rule's GIVEN.
ruleGivenSrc :: Text
ruleGivenSrc = Text.unlines
  [ "@export the scaled amount"
  , "GIVEN rate IS A NUMBER TYPICALLY 3"
  , "      base IS A NUMBER"
  , "GIVETH A NUMBER"
  , "scaled MEANS base TIMES rate"
  ]

-- | Two exported decisions that read one input and disagree about its default.
conflictSrc :: Text
conflictSrc = Text.unlines
  [ "@export Scaled amount"
  , "GIVEN base IS A NUMBER"
  , "      rate IS A NUMBER TYPICALLY 3"
  , "GIVETH A NUMBER"
  , "scaled base rate MEANS base * rate"
  , ""
  , "@export Capped amount"
  , "GIVEN base IS A NUMBER"
  , "      rate IS A NUMBER TYPICALLY 5"
  , "GIVETH A NUMBER"
  , "capped base rate MEANS (base * rate) - 1"
  ]

nothingDefaultSrc :: Text
nothingDefaultSrc = Text.unlines
  [ "@export the scaled amount"
  , "GIVEN rate IS A MAYBE NUMBER TYPICALLY NOTHING"
  , "      base IS A NUMBER"
  , "GIVETH A NUMBER"
  , "scaled MEANS base"
  ]

-- | A regulative rule with its default on its own GIVEN.
bpmnGivenSrc, bpmnSectionSrc, bpmnAssumeSrc, bpmnHenceSrc, bpmnPlainSrc :: Text
bpmnGivenSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "GIVEN `is in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `is in good standing`"
  , "    WITHIN 14"
  ]
bpmnSectionSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "§ `Standing`"
  , "    GIVEN `is in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `is in good standing`"
  , "    WITHIN 14"
  ]
bpmnAssumeSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "ASSUME `is in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `is in good standing`"
  , "    WITHIN 14"
  ]
bpmnHenceSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Filer"
  , "DECLARE Action IS ONE OF file, acknowledge"
  , ""
  , "GIVEN `is complete` IS A BOOLEAN TYPICALLY TRUE"
  , "GIVETH A DEONTIC Actor Action"
  , "`the acknowledgement` MEANS"
  , "    PARTY Filer"
  , "    MUST acknowledge"
  , "    PROVIDED `is complete`"
  , "    WITHIN 7"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the filing` MEANS"
  , "    PARTY Filer"
  , "    MUST file"
  , "    WITHIN 30"
  , "    HENCE `the acknowledgement` TRUE"
  ]
bpmnPlainSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "GIVEN `is in good standing` IS A BOOLEAN"
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `is in good standing`"
  , "    WITHIN 14"
  ]

yscriptAssumeSrc, yscriptSectionSrc, yscriptControlSrc, yscriptUnreadSrc :: Text
yscriptAssumeSrc = Text.unlines
  [ "ASSUME `has capacity` IS A BOOLEAN TYPICALLY TRUE"
  , "ASSUME `is adult` IS A BOOLEAN"
  , ""
  , "@export May contract"
  , "`may contract` MEANS `has capacity` AND `is adult`"
  ]
yscriptSectionSrc = Text.unlines
  [ "§ `Capacity`"
  , "    GIVEN `has capacity` IS A BOOLEAN TYPICALLY TRUE"
  , "          `is adult` IS A BOOLEAN"
  , ""
  , "@export May contract"
  , "`may contract` MEANS `has capacity` AND `is adult`"
  ]
yscriptControlSrc = Text.unlines
  [ "ASSUME `has capacity` IS A BOOLEAN"
  , "ASSUME `is adult` IS A BOOLEAN"
  , ""
  , "@export May contract"
  , "`may contract` MEANS `has capacity` AND `is adult`"
  ]
yscriptUnreadSrc = Text.unlines
  [ "ASSUME `has capacity` IS A BOOLEAN"
  , "ASSUME `is adult` IS A BOOLEAN"
  , "ASSUME `an unrelated fact` IS A BOOLEAN TYPICALLY TRUE"
  , ""
  , "@export May contract"
  , "`may contract` MEANS `has capacity` AND `is adult`"
  ]

-- ---------------------------------------------------------------------------
-- Per-backend helpers
-- ---------------------------------------------------------------------------

dmnDrg :: Module Resolved -> TypeCheckWithDepsResult -> Drg
dmnDrg m tc =
  lowerModule
    MkDmnLowerOptions
      { dloModelName        = "probe"
      , dloSubstitution     = tc.tcdSubstitution
      , dloFlavor           = FlavorCamunda
      , dloMaybePredicates  = resolveMaybePredicates m tc.tcdEnvironment tc.tcdEntityInfo
      , dloIncludeTests     = False
      , dloMissingMatchRanges = []
      , dloClauseMatrixRanges = []
      , dloExternalRefNames = Just Set.empty
      }
    m

dmnTypicallyNotes :: Drg -> [FidelityNote]
dmnTypicallyNotes drg = [ n | n <- (dmnReport drg).notes, n.code == "D-TYPICALLY" ]

relational :: Text -> Either [Text] RelProgram
relational src =
  let tc = checked src
  in either (Left . map renderLowerError) Right
       (Relational.lowerModule Relational.defaultLowerOptions tc.tcdEntityInfo tc.tcdModule)

-- | The same, over a module whose defaults have been rewritten into expressions.
relationalComputed :: Text -> Either [Text] RelProgram
relationalComputed src =
  let tc = checked src
  in either (Left . map renderLowerError) Right
       (Relational.lowerModule Relational.defaultLowerOptions tc.tcdEntityInfo
          (withComputedDefaults tc.tcdModule))

relationalTypically :: RelProgram -> [FidelityNote]
relationalTypically p = [ n | n <- p.rpgFidelity.notes, n.code == "R-TYPICALLY" ]

openFiscaOut :: Module Resolved -> Either [Text] Text
openFiscaOut m = case OpenFisca.lowerModule m of
  Left es   -> Left (map OpenFisca.renderLowerError es)
  Right pkg -> Right (OpenFisca.renderPackage pkg)

catalaOut :: Module Resolved -> Either [Text] Text
catalaOut m = case Catala.lowerModule m of
  Left es   -> Left (map Catala.renderLowerError es)
  Right cm  -> Right (CatalaEmit.renderModule cm)

-- | A rule's own @GIVEN@ read as a plain scalar decision, with and without the default.
withoutDefault :: Text -> Text
withoutDefault = Text.replace " TYPICALLY 3" ""

yscriptErrors :: Module Resolved -> [Text]
yscriptErrors m = case Yscript.lowerModule m of
  Left es -> map Yscript.renderLowerError es
  Right _ -> []

bpmnNotes :: Module Resolved -> Text -> [FidelityNote]
bpmnNotes m rule =
  concat [ bpmnDefaultNotes m g | g <- extractStateGraphs m, g.sgName == rule ]

-- | Does some message in the list contain this text?
mentions :: Text -> [Text] -> Bool
mentions needle = any (Text.isInfixOf needle)

spec :: Spec
spec = do
  ------------------------------------------------------------------------
  describe "where a TYPICALLY is written (L4.Interchange.Typically)" $ do
    let sites = sitesOf (moduleOf fourPlaces)
        kindOf n = [ s.kind | s <- sites, s.name == n ]

    it "finds all four places, in source order" $
      map (\s -> (s.name, s.kind)) sites `shouldBe`
        [ ("timeout", DefaultOnRecordField)
        , ("rate", DefaultOnSectionGiven)
        , ("allowance", DefaultOnAssume)
        , ("factor", DefaultOnRuleGiven)
        ]

    it "tells a section GIVEN from the written ASSUME, though the checker makes both ASSUMEs" $ do
      kindOf "rate" `shouldBe` [DefaultOnSectionGiven]
      kindOf "allowance" `shouldBe` [DefaultOnAssume]

    it "names the owner of a field and of a rule's GIVEN, and no owner for the others" $
      map (\s -> (s.name, s.owner)) sites `shouldBe`
        [ ("timeout", Just "Config"), ("rate", Nothing)
        , ("allowance", Nothing), ("factor", Just "budget") ]

    it "classifies and spells each literal the way source would" $ do
      map (describeDefault . classifyDefault . (.value)) sites `shouldBe` ["30", "3", "100", "2"]
      all (isLiteralDefault . classifyDefault . (.value)) sites `shouldBe` True

    it "finds nothing in a module that writes no TYPICALLY" $
      sitesOf (moduleOf yscriptControlSrc) `shouldBe` []

    it "classifies an expression as computed, and prints it" $ do
      let sitesC = sitesOf (withComputedDefaults (moduleOf fourPlaces))
      map (isLiteralDefault . classifyDefault . (.value)) sitesC `shouldBe` [False, False, False, False]
      map (describeDefault . classifyDefault . (.value)) sitesC `shouldBe`
        ["30 PLUS 1", "3 PLUS 1", "100 PLUS 1", "2 PLUS 1"]

  ------------------------------------------------------------------------
  describe "OpenFisca: maps every default, and refuses what it cannot map" $ do
    let out = succeeds (openFiscaOut (moduleOf openFiscaSrc))

    it "writes a number, a boolean and a string as default_value, on fields and on GIVENs" $ do
      out `shouldSatisfy` Text.isInfixOf "    default_value = 40.0\n"
      out `shouldSatisfy` Text.isInfixOf "    default_value = True\n"
      out `shouldSatisfy` Text.isInfixOf "    default_value = 3.0\n"
      out `shouldSatisfy` Text.isInfixOf "    default_value = 'standard'\n"

    it "writes an enum default as the member the source wrote, not the first declared" $ do
      out `shouldSatisfy` Text.isInfixOf "default_value = Status.married"
      out `shouldSatisfy` (not . Text.isInfixOf "default_value = Status.single")

    it "defines an input variable for a defaulted field (it used to vanish)" $ do
      out `shouldSatisfy` Text.isInfixOf "class hours_a_week(Variable):"
      out `shouldSatisfy` Text.isInfixOf "class is_resident(Variable):"

    it "writes no default_value for an input that has none" $
      succeeds (openFiscaOut (moduleOf (withoutDefault ruleGivenSrc)))
        `shouldSatisfy` (not . Text.isInfixOf "default_value")

    it "refuses a default that has no OpenFisca value (NOTHING)" $
      refuses (openFiscaOut (moduleOf nothingDefaultSrc))
        `shouldSatisfy` mentions "has no OpenFisca value"

    it "refuses two exported decisions that disagree about an input's default, and names both" $
      refuses (openFiscaOut (moduleOf conflictSrc))
        `shouldSatisfy` mentions "different TYPICALLY defaults (3 and 5)"

    it "maps an expression default to a formula the supplied input overrides" $ do
      let computed = succeeds (openFiscaOut (withComputedDefaults (moduleOf ruleGivenSrc)))
      computed `shouldSatisfy` Text.isInfixOf "class rate(Variable):"
      computed `shouldSatisfy` Text.isInfixOf "def formula(person, period):\n        return (3 + 1)"
      -- an input with a formula has no default_value of its own
      computed `shouldSatisfy` (not . Text.isInfixOf "default_value")

    it "refuses an expression default it cannot lower, rather than dropping it" $
      -- a string concatenation has no OpenFisca form
      refuses (openFiscaOut (withDefaultsAs (const (Concat emptyAnno [])) (moduleOf ruleGivenSrc)))
        `shouldSatisfy` mentions "unsupported construct for OpenFisca"

  ------------------------------------------------------------------------
  describe "Blawx (relational middle end): says what it dropped" $ do
    let prg   = succeeds (relational fourPlaces)
        notes = relationalTypically prg

    it "reports every place the lowering reached: a field, a section input, an ASSUME and a rule GIVEN" $
      map (.element) notes `shouldMatchList` ["timeout", "rate", "allowance", "factor"]

    it "words each kind for what it is" $ do
      let msgOf e = [ n.message | n <- notes, n.element == e ]
      msgOf "timeout"   `shouldSatisfy` mentions "the field `timeout` of `Config` carries TYPICALLY 30"
      msgOf "rate"      `shouldSatisfy` mentions "the section GIVEN `rate` carries TYPICALLY 3"
      msgOf "allowance" `shouldSatisfy` mentions "the ASSUME `allowance` carries TYPICALLY 100"
      msgOf "factor"    `shouldSatisfy` mentions "the GIVEN `factor` of `budget` carries TYPICALLY 2"

    it "is lossy under one code" $ do
      map (.code) notes `shouldBe` replicate 4 "R-TYPICALLY"

    it "does not report a TYPICALLY on a decision nothing lowered" $ do
      let unreached = Text.unlines
            [ "@export the scaled amount"
            , "GIVEN base IS A NUMBER"
            , "GIVETH A NUMBER"
            , "scaled MEANS base"
            , ""
            , "GIVEN rate IS A NUMBER TYPICALLY 3"
            , "GIVETH A NUMBER"
            , "unused rate MEANS rate"
            ]
      relationalTypically (succeeds (relational unreached)) `shouldBe` []

    it "reports an expression default too, by printing it" $
      map (.message) (relationalTypically (succeeds (relationalComputed ruleGivenSrc)))
        `shouldSatisfy` mentions "carries TYPICALLY 3 PLUS 1"

    it "carries the notes into the header of the .pl dump, one % line each, and only then" $
      let blawxPrg   = succeeds (relational blawxSrc)
          blawxNotes = relationalTypically blawxPrg
      in case lowerBlawx blawxPrg of
        Left es -> expectationFailure (show (map renderLowerError es))
        Right doc -> do
          let withNotes    = renderPlDumpWith blawxNotes "probe.l4" doc
              withoutNotes = renderPlDumpWith [] "probe.l4" doc
              header t = takeWhile (/= "") (Text.lines t)
          length blawxNotes `shouldBe` 2
          length (header withNotes) `shouldBe` length (header withoutNotes) + 2
          all (Text.isPrefixOf "% ") (header withNotes) `shouldBe` True
          length (filter (Text.isInfixOf "R-TYPICALLY") (header withNotes)) `shouldBe` 2
          -- with no notes the header is the two lines it always was
          length (header withoutNotes) `shouldBe` 2

  ------------------------------------------------------------------------
  describe "DMN and dmn-md: no default exists in the target, so each is reported" $ do
    let m   = moduleOf fourPlaces
        tc  = checked fourPlaces
        drg = dmnDrg m tc

    it "reports a D-TYPICALLY for a field, a section GIVEN, an ASSUME and a rule GIVEN" $
      map (.element) (dmnTypicallyNotes drg) `shouldMatchList`
        ["Config.timeout", "input_rate", "input_allowance", "input_factor"]

    it "is Lossy and names what each engine does with an omitted input" $ do
      let ns = dmnTypicallyNotes drg
      map (.code) ns `shouldBe` replicate 4 "D-TYPICALLY"
      all (Text.isInfixOf "`null` on Camunda 8, a model error on KIE" . (.message)) ns `shouldBe` True

    it "carries the same four notes into the dmnmd report" $
      length [ () | n <- (markdownReport drg).notes, n.code == "D-TYPICALLY" ] `shouldBe` 4

    it "reports an expression default as well, printing it rather than missing it" $ do
      let drgC = dmnDrg (withComputedDefaults m) tc
      length (dmnTypicallyNotes drgC) `shouldBe` 4
      map (.message) (dmnTypicallyNotes drgC) `shouldSatisfy` mentions "carries TYPICALLY 30 PLUS 1"

    it "says nothing about TYPICALLY when the module writes none" $ do
      let src = withoutDefault ruleGivenSrc
      dmnTypicallyNotes (dmnDrg (moduleOf src) (checked src)) `shouldBe` []

  ------------------------------------------------------------------------
  describe "BPMN: a process cannot carry a default, so each is reported" $ do
    it "reports a default on the drawn rule's own GIVEN" $
      map (.code) (bpmnNotes (moduleOf bpmnGivenSrc) "the duty") `shouldBe` ["P-TYPICALLY"]

    it "reports a default on a section GIVEN the rule reads" $
      map (.code) (bpmnNotes (moduleOf bpmnSectionSrc) "the duty") `shouldBe` ["P-TYPICALLY"]

    it "reports a default on an ASSUME the rule reads" $
      map (.code) (bpmnNotes (moduleOf bpmnAssumeSrc) "the duty") `shouldBe` ["P-TYPICALLY"]

    it "reports a default on a rule the drawn rule reaches through HENCE" $ do
      let ns = bpmnNotes (moduleOf bpmnHenceSrc) "the filing"
      map (.code) ns `shouldBe` ["P-TYPICALLY"]
      map (.message) ns `shouldSatisfy`
        mentions "the GIVEN `is complete` of `the acknowledgement` carries TYPICALLY TRUE"

    it "reports nothing when the module writes no TYPICALLY" $
      bpmnNotes (moduleOf bpmnPlainSrc) "the duty" `shouldBe` []

    it "prints an expression default too, instead of missing it" $
      map (.message) (bpmnNotes (withComputedDefaults (moduleOf bpmnGivenSrc)) "the duty")
        `shouldSatisfy` mentions "carries TYPICALLY IF TRUE THEN TRUE ELSE TRUE"

  ------------------------------------------------------------------------
  describe "yscript: refuses an input with a default, as R5 requires" $ do
    it "refuses an ASSUME the exported rule reads, naming it and its default" $
      yscriptErrors (moduleOf yscriptAssumeSrc) `shouldSatisfy`
        mentions "`has capacity`: carries TYPICALLY TRUE"

    it "refuses a section GIVEN the same way" $
      yscriptErrors (moduleOf yscriptSectionSrc) `shouldSatisfy`
        mentions "`has capacity`: carries TYPICALLY TRUE"

    it "refuses an expression default as well" $
      yscriptErrors (withComputedDefaults (moduleOf yscriptAssumeSrc)) `shouldSatisfy`
        mentions "carries TYPICALLY IF TRUE THEN TRUE ELSE TRUE"

    it "compiles the same module once the TYPICALLY is gone (the control)" $
      Yscript.lowerModule (moduleOf yscriptControlSrc) `shouldSatisfy` isRight

    it "does not refuse a default on a fact the exported rule never reads" $
      Yscript.lowerModule (moduleOf yscriptUnreadSrc) `shouldSatisfy` isRight

    it "refuses the whole module, not just the offender (all-or-nothing)" $
      Yscript.lowerModule (moduleOf yscriptAssumeSrc) `shouldSatisfy` isLeft

  ------------------------------------------------------------------------
  describe "Catala: maps a GIVEN's default to a context, and says what it cannot" $ do
    let out = succeeds (catalaOut (moduleOf fourPlaces))

    it "lowers a section GIVEN's and an ASSUME's TYPICALLY to a context with an in-scope default" $ do
      out `shouldSatisfy` Text.isInfixOf "  context rate content decimal"
      out `shouldSatisfy` Text.isInfixOf "  context allowance content decimal"
      out `shouldSatisfy` Text.isInfixOf "definition rate\n    equals\n      3.0"
      out `shouldSatisfy` Text.isInfixOf "definition allowance\n    equals\n      100.0"

    it "still lowers a rule GIVEN's TYPICALLY (R10), unchanged" $ do
      out `shouldSatisfy` Text.isInfixOf "  context factor content decimal"
      out `shouldSatisfy` Text.isInfixOf "definition factor\n    equals\n      2.0"

    it "says in the notes that a record field's default was dropped, and still emits the field" $ do
      out `shouldSatisfy` Text.isInfixOf "field `timeout` of `Config` carries TYPICALLY 30, which is dropped"
      out `shouldSatisfy` Text.isInfixOf "  data timeout content decimal"

    it "lowers an expression default as the in-scope definition, so a new kind of default is not lost" $
      succeeds (catalaOut (withComputedDefaults (moduleOf fourPlaces)))
        `shouldSatisfy` Text.isInfixOf "definition rate\n    equals\n      (3.0 + 1.0)"

    it "writes no context for an input with no TYPICALLY" $
      succeeds (catalaOut (moduleOf (withoutDefault ruleGivenSrc)))
        `shouldSatisfy` (not . Text.isInfixOf "context ")

  ------------------------------------------------------------------------
  describe "docassemble: prefills a literal and refuses what it cannot, loudly" $ do
    it "reports a literal default as a prefill (DA-TYPICALLY), as before" $
      case Docassemble.lowerModule Docassemble.noSideInputs (moduleOf ruleGivenSrc) of
        Left es -> expectationFailure (show (map Docassemble.renderLowerError es))
        Right (_, report) -> map (.code) report.notes `shouldSatisfy` elem "DA-TYPICALLY"

    it "refuses an expression default rather than dropping it" $
      Docassemble.lowerModule Docassemble.noSideInputs (withComputedDefaults (moduleOf ruleGivenSrc))
        `shouldSatisfy` either (any (Text.isInfixOf "unsupported TYPICALLY default" . Docassemble.renderLowerError)) (const False)
