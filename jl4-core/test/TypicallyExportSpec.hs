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

import L4.API.VirtualFS
  ( ResolvedImport (..), TypeCheckWithDepsResult (..), checkWithImports, vfsFromList )
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
import L4.Interchange.Fidelity (FidelityNote (..), FidelityReport (..), FidelitySeverity (..))
import L4.Interchange.Typically
  ( DefaultKind (..), DefaultSite (..), classifyDefault
  , describeDefault, describeSite, isLiteralDefault, moduleDefaultSites )
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
checked = checkedIn []

-- | The same, for a module that imports others, given as (module name, source).
checkedIn :: [(Text, Text)] -> Text -> TypeCheckWithDepsResult
checkedIn files src = case checkWithImports (vfsFromList files) src of
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

-- | The modules a checked module imports, as @l4 export@ hands them to a backend.
importsOf :: TypeCheckWithDepsResult -> [Module Resolved]
importsOf tc = [ ri.riTypeChecked.program | ri <- tc.tcdResolvedImports ]

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
    Declare a (MkDeclare da ts af (EnumDecl ea cons)) ->
      Declare a (MkDeclare da ts af
        (EnumDecl ea [ MkConDecl ca c [ MkTypedName fa n ty (fmap bump d) m | MkTypedName fa n ty d m <- fields ]
                     | MkConDecl ca c fields <- cons ]))
    Section a s -> Section a (goSection s)
    other -> other

-- | Replace every @TYPICALLY@ by a reference to the module's @GIVEN@ of that
-- name: a nullary application whose head is a variable, which is the shape R8
-- rule 3 (W7) admits as a default and which has exactly the shape of a nullary
-- constructor. The AST alone does not tell the two apart.
withDefaultsReferring :: Text -> Module Resolved -> Module Resolved
withDefaultsReferring target m = withDefaultsAs (const ref) m
 where
  ref = case [ r | r <- binderNames m, rawNameToText (rawName (getActual r)) == target ] of
    (r : _) -> let n = getOriginal r in App emptyAnno (Ref n (getUnique r) n) []
    _       -> error ("no GIVEN named " <> Text.unpack target)
  binderNames (MkModule _ _ section) = goSection section
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
  goDecl = \case
    Decide _ (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) _ _) ->
      [ n | MkOptionallyTypedName _ n _ _ <- otns ]
    Section _ s -> goSection s
    _ -> []

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

-- | A sum type whose constructor's field carries a TYPICALLY, read by an exported
-- decision. The fifth place a default can sit: it is not a record field, no selector
-- names it, and a survey that walked records only never saw it.
conFieldSrc, conFieldDecl, conFieldBpmnSrc :: Text
conFieldDecl = Text.unlines
  [ "DECLARE Shape IS ONE OF"
  , "  Circle HAS radius IS A NUMBER TYPICALLY 1"
  , "  Square HAS side IS A NUMBER"
  , ""
  ]
conFieldSrc = conFieldDecl <> Text.unlines
  [ "@export default the area"
  , "GIVEN s IS A Shape"
  , "GIVETH A NUMBER"
  , "DECIDE `the area` IS"
  , "  CONSIDER s"
  , "  WHEN Circle r THEN r TIMES r TIMES 3"
  , "  WHEN Square x THEN x TIMES x"
  ]
conFieldBpmnSrc = conFieldDecl <> Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "GIVEN s IS A Shape"
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` s MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    WITHIN 14"
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

-- | A household whose members are a role, with a default written on the field.
listFieldSrc :: Text
listFieldSrc = Text.unlines
  [ "DECLARE Person HAS salary IS A NUMBER"
  , "DECLARE Household HAS members IS A LIST OF Person TYPICALLY EMPTY"
  , ""
  , "@export Total"
  , "GIVEN h IS A Household"
  , "      period IS A STRING"
  , "GIVETH A NUMBER"
  , "`total` h period MEANS 1"
  ]

-- | A @LIST OF@ number as a rule's own GIVEN, with a default written on it.
listGivenSrc :: Text
listGivenSrc = Text.unlines
  [ "@export Total"
  , "GIVEN xs IS A LIST OF NUMBER TYPICALLY EMPTY"
  , "      period IS A STRING"
  , "GIVETH A NUMBER"
  , "`total` xs period MEANS 5"
  ]

-- | A synonym of STRING as a rule's GIVEN, with a string default. OpenFisca holds
-- a type it does not recognise as a number. (The checker refuses the same default
-- on a record field of a synonym type, so a field cannot reach the export.)
synonymGivenSrc :: Text
synonymGivenSrc = Text.unlines
  [ "DECLARE Label IS A STRING"
  , ""
  , "@export Allowance"
  , "GIVEN l IS A Label TYPICALLY \"x\""
  , "      period IS A STRING"
  , "GIVETH A NUMBER"
  , "allowance l period MEANS IF l EQUALS \"x\" THEN 1 ELSE 0"
  ]

-- | Two exported decisions that share an input called @x@: the first writes the
-- given default, the second writes none. (Neither body reads it; an unread GIVEN
-- is still an input variable.)
defaultVsNoneSrc :: Text -> Text -> Text
defaultVsNoneSrc ty dflt = Text.unlines
  [ "DECLARE Status IS ONE OF single, married"
  , ""
  , "@export A"
  , "GIVEN x IS A " <> ty <> " " <> dflt
  , "GIVETH A NUMBER"
  , "`the a` x MEANS 1"
  , ""
  , "@export B"
  , "GIVEN x IS A " <> ty
  , "GIVETH A NUMBER"
  , "`the b` x MEANS 2"
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
bpmnGivenSrc, bpmnSectionSrc, bpmnAssumeSrc, bpmnHenceSrc, bpmnPlainSrc, bpmnFieldSrc :: Text
bpmnFieldSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "DECLARE Standing HAS"
  , "    `in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , "    `years a member`   IS A NUMBER  TYPICALLY 0"
  , ""
  , "GIVEN s IS A Standing"
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` s MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED s's `in good standing`"
  , "    WITHIN 14"
  ]
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
-- | The drawn rule reaches another through HENCE, and that rule reads an ASSUME
-- that carries a default. (bpmnHenceSrc has the default on the reached rule's GIVEN.)
bpmnHenceAssumeSrc :: Text
bpmnHenceAssumeSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Filer"
  , "DECLARE Action IS ONE OF file, acknowledge"
  , ""
  , "ASSUME `is complete` IS A BOOLEAN TYPICALLY TRUE"
  , ""
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
  , "    HENCE `the acknowledgement`"
  ]

-- | The default is on a record's field that a helper reads by taking the record
-- apart, so no selector is named anywhere.
bpmnFieldPatternSrc :: Text
bpmnFieldPatternSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "DECLARE Standing HAS"
  , "    `in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , "    `years a member`   IS A NUMBER"
  , ""
  , "GIVEN s IS A Standing"
  , "GIVETH A BOOLEAN"
  , "`ok` s MEANS"
  , "  CONSIDER s"
  , "  WHEN Standing g y THEN g"
  , ""
  , "GIVEN s IS A Standing"
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` s MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `ok` s"
  , "    WITHIN 14"
  ]

-- | The same ASSUME read through a helper: defined in the file the rule imports
-- (importedHelperMain, which uses importedLib's `may act`), or in the same file.
importedHelperMain, localHelperSrc :: Text
importedHelperMain = Text.unlines
  [ "IMPORT ratelib"
  , ""
  , "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `may act`"
  , "    WITHIN 14"
  ]
localHelperSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "ASSUME `is in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , ""
  , "GIVETH A BOOLEAN"
  , "`may act` MEANS `is in good standing`"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `may act`"
  , "    WITHIN 14"
  ]

-- | A second regulative rule that mentions no Standing.
unrelatedRuleSrc :: Text
unrelatedRuleSrc = Text.unlines
  [ ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the unrelated duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    WITHIN 30"
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

-- | A library whose defaults a rule in another file reads (W9 review F1: a
-- default read through an @IMPORT@ was dropped without a note). A record field
-- and an @ASSUME@ the main module reads, one it does not, and a rule whose own
-- @GIVEN@ carries a default.
importedLib :: Text
importedLib = Text.unlines
  [ "DECLARE Config HAS"
  , "    timeout IS A NUMBER TYPICALLY 30"
  , "    retries IS A NUMBER"
  , "    grace   IS A NUMBER TYPICALLY 5"
  , ""
  , "ASSUME allowance IS A NUMBER TYPICALLY 100"
  , ""
  , "ASSUME `an unrelated fact` IS A NUMBER TYPICALLY 7"
  , ""
  , "ASSUME `is in good standing` IS A BOOLEAN TYPICALLY TRUE"
  , ""
  , "GIVEN k IS A NUMBER TYPICALLY 9"
  , "GIVETH A NUMBER"
  , "`library rule` k MEANS k"
  , ""
  , "GIVETH A BOOLEAN"
  , "`may act` MEANS `is in good standing`"
  ]

importedDmnMain, importedBpmnMain, importedBpmnFieldMain :: Text
importedBpmnFieldMain = Text.unlines
  [ "IMPORT ratelib"
  , ""
  , "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "GIVEN c IS A Config"
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` c MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED c's timeout AT LEAST 10"
  , "    WITHIN 14"
  ]
importedDmnMain = Text.unlines
  [ "IMPORT ratelib"
  , ""
  , "@export The budget"
  , "GIVEN c IS A Config"
  , "GIVETH A NUMBER"
  , "`the budget` c MEANS (c's timeout) TIMES (c's retries) PLUS allowance"
  ]
importedBpmnMain = Text.unlines
  [ "IMPORT ratelib"
  , ""
  , "DECLARE Actor IS ONE OF Member"
  , "DECLARE Action IS ONE OF pay"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`the duty` MEANS"
  , "    PARTY Member"
  , "    MUST pay"
  , "    PROVIDED `is in good standing`"
  , "    WITHIN 14"
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
      , dloImports          = importsOf tc
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
bpmnNotes = bpmnNotesWith []

-- | The same, for a module that imports others: the imports' modules go in as
-- the CLI passes them.
bpmnNotesWith :: [Module Resolved] -> Module Resolved -> Text -> [FidelityNote]
bpmnNotesWith imports m rule =
  concat [ bpmnDefaultNotes imports m g | g <- extractStateGraphs m, g.sgName == rule ]

-- | Does some message in the list contain this text?
mentions :: Text -> [Text] -> Bool
mentions needle = any (Text.isInfixOf needle)

spec :: Spec
spec = do
  ------------------------------------------------------------------------
  describe "where a TYPICALLY is written (L4.Interchange.Typically)" $ do
    let sites = sitesOf (moduleOf fourPlaces)
        kindOf n = [ s.kind | s <- sites, s.name == n ]

    it "finds a record field, a section GIVEN, an ASSUME and a rule GIVEN, in source order" $
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

    it "maps a default that names another input to a formula, not to 'no way to say a variable has no value'" $ do
      -- `TYPICALLY base` has the same shape as a nullary constructor. The
      -- checker tells them apart, the AST does not, so the lowering must.
      let referring = withDefaultsReferring "base" (moduleOf ruleGivenSrc)
          o = succeeds (openFiscaOut referring)
      o `shouldSatisfy` Text.isInfixOf "class rate(Variable):"
      o `shouldSatisfy` Text.isInfixOf "def formula(person, period):"
      o `shouldSatisfy` (not . Text.isInfixOf "default_value")

    it "still refuses NOTHING as a default on a scalar GIVEN (the constructor arm, after that change)" $
      refuses (openFiscaOut (moduleOf nothingDefaultSrc))
        `shouldSatisfy` mentions "no way to say a variable has no value"

    it "accepts TYPICALLY EMPTY on a LIST OF field: a role nobody fills is already empty" $
      succeeds (openFiscaOut (moduleOf listFieldSrc))
        `shouldBe` succeeds (openFiscaOut (moduleOf (Text.replace " TYPICALLY EMPTY" "" listFieldSrc)))

    it "refuses any other default on a LIST OF field, rather than dropping it" $
      refuses (openFiscaOut (withDefaultsAs (const (Lit emptyAnno (NumericLit emptyAnno 1))) (moduleOf listFieldSrc)))
        `shouldSatisfy` mentions "`members` is a LIST OF records and carries TYPICALLY 1"

    it "accepts TYPICALLY EMPTY on a LIST OF GIVEN, as on a LIST OF field, instead of calling EMPTY an unbound reference" $
      succeeds (openFiscaOut (moduleOf listGivenSrc))
        `shouldBe` succeeds (openFiscaOut (moduleOf (Text.replace " TYPICALLY EMPTY" "" listGivenSrc)))

    it "refuses any other default on a LIST OF GIVEN, naming the GIVEN" $
      refuses (openFiscaOut (withDefaultsAs (const (Lit emptyAnno (NumericLit emptyAnno 1))) (moduleOf listGivenSrc)))
        `shouldSatisfy` mentions "the GIVEN `xs` is a LIST and carries TYPICALLY 1"

    it "says why it refuses a string default on a synonym of STRING: the type is not one the export recognises" $ do
      let msgs = refuses (openFiscaOut (moduleOf synonymGivenSrc))
      msgs `shouldSatisfy` mentions "does not recognise the type `Label`"
      -- and does not say what it used to say, which blamed the default for the type
      msgs `shouldSatisfy` (not . mentions "it is not a number, which is what this variable holds")

    it "still gives a plain mismatch the plain reason (the control)" $
      -- a string where the variable is a number, with no synonym in sight
      refuses (openFiscaOut (withDefaultsAs (const (Lit emptyAnno (StringLit emptyAnno "x"))) (moduleOf ruleGivenSrc)))
        `shouldSatisfy` mentions "it is not a number, which is what this variable holds"

    it "treats a default equal to OpenFisca's own as no disagreement: 0, FALSE and the first member against none" $ do
      succeeds (openFiscaOut (moduleOf (defaultVsNoneSrc "NUMBER" "TYPICALLY 0"))) `shouldSatisfy` Text.isInfixOf "class x(Variable):"
      succeeds (openFiscaOut (moduleOf (defaultVsNoneSrc "BOOLEAN" "TYPICALLY FALSE"))) `shouldSatisfy` Text.isInfixOf "class x(Variable):"
      succeeds (openFiscaOut (moduleOf (defaultVsNoneSrc "Status" "TYPICALLY single"))) `shouldSatisfy` Text.isInfixOf "class x(Variable):"

    it "refuses a default that differs from OpenFisca's own against none, and says what none means" $ do
      let msgs src = refuses (openFiscaOut (moduleOf src))
      msgs (defaultVsNoneSrc "NUMBER" "TYPICALLY 3") `shouldSatisfy` mentions "different TYPICALLY defaults (3 and none"
      msgs (defaultVsNoneSrc "BOOLEAN" "TYPICALLY TRUE") `shouldSatisfy` mentions "(TRUE and none"
      -- an enum's undefaulted side is its first member, whether or not it was written
      msgs (defaultVsNoneSrc "Status" "TYPICALLY married")
        `shouldSatisfy` mentions "(Status.married and Status.single (the first member, which is also what no TYPICALLY gives)"
      msgs (defaultVsNoneSrc "NUMBER" "TYPICALLY 3")
        `shouldSatisfy` mentions "OpenFisca then gives the input its own default for its type"

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
      map (.severity) ns `shouldBe` replicate 4 Lossy
      -- a top-level input: Camunda reads null, KIE refuses the decision
      let inputs = [ n | n <- ns, n.element /= "Config.timeout" ]
      length inputs `shouldBe` 3
      all (Text.isInfixOf "`null` on Camunda 8, a model error on KIE" . (.message)) inputs `shouldBe` True

    it "says of a record field what was measured of one: both engines read null, and neither complains" $ do
      -- A missing itemComponent is NOT a missing input on KIE. It is answered
      -- (as null) and reported SUCCEEDED, so the note must not send a reader
      -- to KIE for a loud failure it will not give.
      -- (jl4/examples/dmn/defaults-omit-component.cases.json)
      let field = [ n | n <- dmnTypicallyNotes drg, n.element == "Config.timeout" ]
      map (.message) field `shouldSatisfy` all (Text.isInfixOf "`null` for it on Camunda 8 and on KIE alike, and neither reports an error")
      map (.message) field `shouldSatisfy` all (not . Text.isInfixOf "a model error on KIE")
      -- worded for a consumer that builds the record, which is true whether or not a decision reads it
      map (.message) field `shouldSatisfy` all (Text.isInfixOf "an evaluation that builds a `Config` without `timeout`")

    it "carries the same four notes into the dmnmd report" $
      length [ () | n <- (markdownReport drg).notes, n.code == "D-TYPICALLY" ] `shouldBe` 4

    it "reports an expression default as well, printing it rather than missing it" $ do
      let drgC = dmnDrg (withComputedDefaults m) tc
      length (dmnTypicallyNotes drgC) `shouldBe` 4
      map (.message) (dmnTypicallyNotes drgC) `shouldSatisfy` mentions "carries TYPICALLY 30 PLUS 1"

    it "says nothing about TYPICALLY when the module writes none" $ do
      let src = withoutDefault ruleGivenSrc
      dmnTypicallyNotes (dmnDrg (moduleOf src) (checked src)) `shouldBe` []

    it "reports a default it reads through an IMPORT, names the module, and leaves an unread one alone" $ do
      let tcI = checkedIn [("ratelib", importedLib)] importedDmnMain
          ns  = dmnTypicallyNotes (dmnDrg tcI.tcdModule tcI)
      map (.element) ns `shouldMatchList` ["Config.timeout", "allowance"]
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "(in the imported module `ratelib`)")
      map (.message) ns `shouldSatisfy` (not . mentions "an unrelated fact")
      -- a rule's own GIVEN default in the library is not this model's loss
      map (.message) ns `shouldSatisfy` (not . mentions "library rule")
      -- nor a defaulted field of the imported record that no decision reads
      map (.message) ns `shouldSatisfy` (not . mentions "`grace`")
      -- The imported ASSUME has no inputData in the model (free terms come from
      -- the module being lowered), so its note must not describe one. The field
      -- of the imported record does have an itemComponent, and keeps that wording.
      let assumeNote = [ n.message | n <- ns, n.element == "allowance" ]
          fieldNote  = [ n.message | n <- ns, n.element == "Config.timeout" ]
      assumeNote `shouldSatisfy` all (Text.isInfixOf "the model has no input for it at all")
      assumeNote `shouldSatisfy` all (not . Text.isInfixOf "DMN has no default for an inputData")
      assumeNote `shouldSatisfy` all (Text.isInfixOf "KIE cannot load the model")
      fieldNote `shouldSatisfy` all (Text.isInfixOf "DMN has no default for an itemComponent")
      -- the dmnmd report carries them too
      length [ () | n <- (markdownReport (dmnDrg tcI.tcdModule tcI)).notes, n.code == "D-TYPICALLY" ] `shouldBe` 2

    it "would have said nothing of an imported default before it was handed the imports (the control)" $ do
      let tcI  = checkedIn [("ratelib", importedLib)] importedDmnMain
          bare = dmnDrg tcI.tcdModule (tcI { tcdResolvedImports = [] })
      dmnTypicallyNotes bare `shouldBe` []

  ------------------------------------------------------------------------
  describe "BPMN: a process cannot carry a default, so each is reported" $ do
    it "reports a default on the drawn rule's own GIVEN" $
      map (.code) (bpmnNotes (moduleOf bpmnGivenSrc) "the duty") `shouldBe` ["P-TYPICALLY"]

    it "reports a default on a section GIVEN the rule reads" $
      map (.code) (bpmnNotes (moduleOf bpmnSectionSrc) "the duty") `shouldBe` ["P-TYPICALLY"]

    it "reports a default on an ASSUME the rule reads" $
      map (.code) (bpmnNotes (moduleOf bpmnAssumeSrc) "the duty") `shouldBe` ["P-TYPICALLY"]

    -- The call a HENCE makes supplies every argument, so the source never relies
    -- on the callee's default in this process, and the old note ("the source says
    -- an unsupplied `is complete` is TRUE") described a presumption that was not
    -- in play. What the process loses is the argument, which BPMN has never drawn.
    it "says nothing of a default on the GIVEN of a rule the drawn rule reaches through HENCE" $
      bpmnNotes (moduleOf bpmnHenceSrc) "the filing" `shouldBe` []

    it "says nothing of it when the HENCE passes the opposite of the default, either" $
      bpmnNotes (moduleOf (Text.replace "HENCE `the acknowledgement` TRUE" "HENCE `the acknowledgement` FALSE" bpmnHenceSrc))
        "the filing" `shouldBe` []

    it "still reports a default on the drawn rule's own GIVEN when it is the rule reached (the control)" $
      -- drawing `the acknowledgement` itself: its GIVEN is a process input, nothing supplies it
      map (.code) (bpmnNotes (moduleOf bpmnHenceSrc) "the acknowledgement") `shouldBe` ["P-TYPICALLY"]

    it "reports a default on an ASSUME that a rule reached through HENCE reads" $ do
      let ns = bpmnNotes (moduleOf bpmnHenceAssumeSrc) "the filing"
      map (.code) ns `shouldBe` ["P-TYPICALLY"]
      map (.message) ns `shouldSatisfy` mentions "the ASSUME `is complete` carries TYPICALLY TRUE"

    -- A condition is opaque text in the BPMN, and a helper may read a field by
    -- naming it (`s's field`) or by taking the record apart (`CONSIDER s WHEN
    -- Standing g y THEN g`), which names no selector. The process has lost the
    -- default of every field of a record it handles either way.
    it "reports every defaulted field of a record the rule handles, the one a condition names and the one it does not" $ do
      let ns = bpmnNotes (moduleOf bpmnFieldSrc) "the duty"
      map (.code) ns `shouldBe` ["P-TYPICALLY", "P-TYPICALLY"]
      map (.element) ns `shouldBe` ["in good standing", "years a member"]
      map (.message) ns `shouldSatisfy`
        mentions "the field `in good standing` of `Standing` carries TYPICALLY TRUE"
      map (.message) ns `shouldSatisfy` mentions "an instance that holds a `Standing` without it does not get TRUE"
      map (.message) ns `shouldSatisfy` mentions "the field `years a member` of `Standing` carries TYPICALLY 0"

    it "reports a field a helper reads by taking the record apart, though no selector is named" $ do
      let ns = bpmnNotes (moduleOf bpmnFieldPatternSrc) "the duty"
      map (.element) ns `shouldBe` ["in good standing"]

    it "says nothing of a record's fields when the rule handles no such record (the control)" $
      -- the same module drawn from a rule that never mentions Standing
      bpmnNotes (moduleOf (bpmnFieldPatternSrc <> unrelatedRuleSrc)) "the unrelated duty" `shouldBe` []

    it "reports nothing when the module writes no TYPICALLY" $
      bpmnNotes (moduleOf bpmnPlainSrc) "the duty" `shouldBe` []

    it "reports a default on an ASSUME the rule reads through an IMPORT, and names the module" $ do
      let tcI = checkedIn [("ratelib", importedLib)] importedBpmnMain
          ns  = bpmnNotesWith (importsOf tcI) tcI.tcdModule "the duty"
      map (.code) ns `shouldBe` ["P-TYPICALLY"]
      map (.message) ns `shouldSatisfy`
        mentions "the ASSUME `is in good standing` (in the imported module `ratelib`) carries TYPICALLY TRUE"

    it "reports the defaulted fields of an IMPORTED record the rule handles, and nothing else the library writes" $ do
      let tcI = checkedIn [("ratelib", importedLib)] importedBpmnFieldMain
          ns  = bpmnNotesWith (importsOf tcI) tcI.tcdModule "the duty"
      map (.element) ns `shouldBe` ["timeout", "grace"]
      map (.message) ns `shouldSatisfy`
        mentions "the field `timeout` of `Config` (in the imported module `ratelib`) carries TYPICALLY 30"
      -- not the ASSUMEs nobody reads, nor the library rule's own GIVEN
      map (.message) ns `shouldSatisfy` (not . mentions "an unrelated fact")
      map (.message) ns `shouldSatisfy` (not . mentions "library rule")

    -- The same helper, `may act`, reads the same ASSUME. Defined in the rule's own
    -- file the note appeared; defined in an imported file the call graph stopped at
    -- the import and nothing did. Both emit the identical conditionExpression.
    it "reports an ASSUME read through a helper defined in an IMPORTED file, as it does for a local helper" $ do
      let tcI = checkedIn [("ratelib", importedLib)] importedHelperMain
          viaImport = bpmnNotesWith (importsOf tcI) tcI.tcdModule "the duty"
          viaLocal  = bpmnNotes (moduleOf localHelperSrc) "the duty"
      map (.code) viaLocal `shouldBe` ["P-TYPICALLY"]
      map (.code) viaImport `shouldBe` ["P-TYPICALLY"]
      map (.message) viaImport `shouldSatisfy`
        mentions "the ASSUME `is in good standing` (in the imported module `ratelib`) carries TYPICALLY TRUE"

    it "says nothing of it when the helper's file is not handed over (the control)" $ do
      let tcI = checkedIn [("ratelib", importedLib)] importedHelperMain
      bpmnNotes tcI.tcdModule "the duty" `shouldBe` []

    it "says nothing of that default when it is not handed the imports (the control)" $ do
      let tcI = checkedIn [("ratelib", importedLib)] importedBpmnMain
      bpmnNotes tcI.tcdModule "the duty" `shouldBe` []

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

  ------------------------------------------------------------------------
  -- The checker accepts a TYPICALLY on the field of a sum type's constructor
  -- (`Circle HAS radius IS A NUMBER TYPICALLY 1`). It is a fifth place a default
  -- can sit, and the survey that found four walked records only: Catala,
  -- docassemble and DMN dropped it with exit 0 and no note, which the exports
  -- README's "none of them drops it quietly" denied. A new kind of site has to
  -- reach each backend's fallback, whatever it is.
  describe "a constructor's field is the fifth place a TYPICALLY can sit" $ do
    let sum' = moduleOf conFieldSrc

    it "is found, owned by the constructor, with the sum type as the thing a backend asks about" $ do
      let found = sitesOf sum'
      map (.kind) found `shouldBe` [DefaultOnConstructorField]
      map (.name) found `shouldBe` ["radius"]
      map (.owner) found `shouldBe` [Just "Circle"]
      map describeSite found `shouldBe` ["the field `radius` of the constructor `Circle`"]

    it "Catala: says in the notes that it is dropped" $
      succeeds (catalaOut sum') `shouldSatisfy`
        Text.isInfixOf "field `radius` of the constructor `Circle` carries TYPICALLY 1, which is dropped"

    it "docassemble: prefills the follow-up question, and reports the prefill" $
      case Docassemble.lowerModule Docassemble.noSideInputs sum' of
        Left es -> expectationFailure (show (map Docassemble.renderLowerError es))
        Right (_, report) ->
          [ n.message | n <- report.notes, n.code == "DA-TYPICALLY" ] `shouldSatisfy` mentions "s_radius"

    it "docassemble: refuses an expression default there, as it does for any other" $
      Docassemble.lowerModule Docassemble.noSideInputs (withComputedDefaults sum')
        `shouldSatisfy` either (any (Text.isInfixOf "unsupported TYPICALLY default" . Docassemble.renderLowerError)) (const False)

    it "DMN and dmn-md: report it, and say that the payload of a sum type is not in the model" $ do
      let tc  = checked conFieldSrc
          drg = dmnDrg tc.tcdModule tc
          ns  = dmnTypicallyNotes drg
      map (.element) ns `shouldBe` ["Circle.radius"]
      map (.message) ns `shouldSatisfy` mentions "the field `radius` of the constructor `Circle` carries TYPICALLY 1"
      map (.message) ns `shouldSatisfy` mentions "the model keeps no payload for a sum type at all (see D-SUMTYPE)"
      length [ () | n <- (markdownReport drg).notes, n.code == "D-TYPICALLY" ] `shouldBe` 1

    it "OpenFisca: refuses the module, naming the field, rather than writing the enum without it" $
      refuses (openFiscaOut sum') `shouldSatisfy`
        mentions "the field `radius` of the constructor `Circle` carries TYPICALLY 1, and OpenFisca writes an enum as its members alone"

    it "OpenFisca: says nothing of a sum type that carries no default (the control)" $
      refuses (openFiscaOut (moduleOf (Text.replace " TYPICALLY 1" "" conFieldSrc)))
        `shouldSatisfy` (not . mentions "carries TYPICALLY")

    it "Blawx: reports it, as it does a record field" $ do
      let prg = succeeds (relational (conFieldDecl <> blawxSrc))
          ns  = relationalTypically prg
      map (.element) ns `shouldContain` ["radius"]
      map (.message) ns `shouldSatisfy` mentions "the field `radius` of the constructor `Circle` carries TYPICALLY 1, which is dropped"

    it "BPMN: reports it for a rule that handles the sum type, and for no other" $ do
      let ns = bpmnNotes (moduleOf conFieldBpmnSrc) "the duty"
      map (.element) ns `shouldBe` ["radius"]
      map (.message) ns `shouldSatisfy` mentions "the field `radius` of the constructor `Circle` carries TYPICALLY 1"
      -- a rule that never mentions Shape owes nothing for it
      bpmnNotes (moduleOf (conFieldBpmnSrc <> unrelatedRuleSrc)) "the unrelated duty" `shouldBe` []
