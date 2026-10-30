{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ExportValidationSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (ExportError (..), ExportSite (..), ExportedFunction(..), ExportedParam(..), checkExports, getExportedFunctions, enrichReturnTypes)
import L4.Export.Shape (JsonField (..), JsonShape (..), Unsendable (..), jsonShape, moduleDeclares, shapeEnvFromDeclares, unsendableWhat)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Parser.SrcSpan (SrcPos(..), SrcRange(..))
import L4.Print (prettyTypeForDisplay)
import L4.Syntax (getActual, nameToText)
import L4.TypeCheck (prettyCheckErrorWithContext, severity)
import L4.TypeCheck.Types (Severity(..))

-- | The problems 'checkExports' finds in a snippet (or 'Left' on fatal failure).
exportProblems :: Text -> Either [Text] [ExportError]
exportProblems source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right (checkExports (shapeEnvFromDeclares (moduleDeclares r.tcdModule) r.tcdEntityInfo) r.tcdModule)

-- | One problem as the line of the @\@export@ it is reported at, the exported
-- rule, the input (Nothing: the result), and what is wrong. A missing type is
-- "no written type".
type Problem = (Maybe Int, Text, Maybe Text, Text)

problems :: Text -> Either [Text] [Problem]
problems = fmap (map summarise) . exportProblems
 where
  summarise = \case
    ExportUnsendable range fn site why ->
      (line range, nameToText (getActual fn), siteName site, unsendableWhat why)
    ExportUntypedGiven range fn input ->
      (line range, nameToText (getActual fn), Just (nameToText (getActual input)), "no written type")
  line = fmap (\rg -> rg.start.line)
  siteName = \case
    ExportInput n -> Just (nameToText (getActual n))
    ExportResult -> Nothing

-- | The messages of every error (not warning) the type check gives a snippet.
-- A refused @\@export@ is not one of them: the file still type-checks.
errorMessages :: Text -> Either [Text] [Text]
errorMessages source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ Text.intercalate " " (prettyCheckErrorWithContext e)
      | e <- r.tcdErrors
      , severity e == SError
      ]

-- | The shape of each exported input of a snippet (or 'Left' on fatal failure).
inputShapes :: Text -> Either [Text] [(Text, Either Unsendable JsonShape)]
inputShapes source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r ->
      let env = shapeEnvFromDeclares (moduleDeclares r.tcdModule) r.tcdEntityInfo
      in Right
        [ (p.paramName, maybe (Left (UUnknownType "no type")) (jsonShape env) p.paramType)
        | ef <- getExportedFunctions r.tcdModule
        , p <- ef.exportParams
        ]

-- | Run typecheck on a source snippet and return the exported function
-- names (or 'Left' on fatal failure).
exportedNames :: Text -> Either [Text] [Text]
exportedNames source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right $ map (.exportName) (getExportedFunctions r.tcdModule)

-- | Run typecheck and return the displayed return type of each export,
-- exactly as the deployed schema / LSP would render it.
exportedReturnTypes :: Text -> Either [Text] [(Text, Text)]
exportedReturnTypes source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r ->
      let exps = enrichReturnTypes r.tcdEntityInfo (getExportedFunctions r.tcdModule)
      in Right
        [ (ef.exportName, maybe "unknown" prettyTypeForDisplay ef.exportReturnType)
        | ef <- exps
        ]

spec :: Spec
spec = do
  describe "@export detection" $ do
    it "detects @export when it sits immediately above the function" $ do
      let src = Text.unlines
            [ "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right ["adult"]

    it "detects @export when followed by @desc rows before the function" $ do
      let src = Text.unlines
            [ "@export Check age"
            , "@desc Some description for the function"
            , "@desc Another description line"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right ["adult"]

    it "detects @export with @desc lines both before and after the export line" $ do
      let src = Text.unlines
            [ "@desc Pre-export description"
            , "@export Check age"
            , "@desc Post-export description"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right ["adult"]

    it "does not treat a plain @desc as an export" $ do
      let src = Text.unlines
            [ "@desc Just a description"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right []

  describe "checkExports" $ do
    let types =
          [ "DECLARE Party IS ONE OF alice, bob"
          , "DECLARE Act IS ONE OF ping, pong"
          , ""
          ]
        noTypeError src = errorMessages src `shouldBe` Right []

    it "refuses a function-typed GIVEN, at the @export" $ do
      let src = Text.unlines
            [ "@export Apply the predicate"
            , "GIVEN `p` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_given_test` IF `p` OF TRUE"
            ]
      problems src `shouldBe` Right [(Just 1, "fn_given_test", Just "p", "a function")]
      noTypeError src

    it "refuses an ASSUME of function type that the body reads" $ do
      let src = Text.unlines
            [ "ASSUME `pred` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , ""
            , "@export Apply assumed predicate"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_assume_test` IF `pred` OF TRUE"
            ]
      problems src `shouldBe` Right [(Just 3, "fn_assume_test", Just "pred", "a function")]
      noTypeError src

    it "accepts value-typed inputs" $ do
      let src = Text.unlines
            [ "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF `age` >= 18"
            ]
      problems src `shouldBe` Right []

    it "ignores a function-typed ASSUME that no export reads" $ do
      let src = Text.unlines
            [ "ASSUME `unused_fn` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `check_age` IF `age` >= 18"
            ]
      problems src `shouldBe` Right []

    it "ignores function-typed GIVENs on a rule that is not @export" $ do
      let src = Text.unlines
            [ "GIVEN `p` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `internal_helper` IF `p` OF TRUE"
            ]
      problems src `shouldBe` Right []

    it "refuses a function inside MAYBE OF" $ do
      let src = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "@export With maybe callback"
            , "GIVEN `cb` IS A MAYBE OF FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_maybe_test` IF TRUE"
            ]
      problems src `shouldBe` Right [(Just 3, "fn_maybe_test", Just "cb", "a function")]

    it "refuses a function named through a type synonym" $ do
      let src = Text.unlines
            [ "DECLARE `Pred` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , ""
            , "@export Via synonym"
            , "GIVEN `p` IS A `Pred`"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_syn_test` IF `p` OF TRUE"
            ]
      problems src `shouldBe` Right [(Just 3, "fn_syn_test", Just "p", "a function")]

    describe "EVENT" $ do
      it "refuses an EVENT input, at the @export" $ do
        let src = Text.unlines $ types ++
              [ "@export Who acted"
              , "GIVEN e IS AN EVENT Party Act"
              , "GIVETH A Party"
              , "`who acted` MEANS"
              , "  CONSIDER e"
              , "  WHEN EVENT p a n THEN p"
              ]
        problems src `shouldBe` Right [(Just 4, "who acted", Just "e", "an EVENT")]
        noTypeError src

      it "refuses an EVENT result that is written" $ do
        let src = Text.unlines $ types ++
              [ "@export Make an event"
              , "GIVEN p IS A Party"
              , "GIVETH AN EVENT Party Act"
              , "`make event` MEANS EVENT p ping 0"
              ]
        problems src `shouldBe` Right [(Just 4, "make event", Nothing, "an EVENT")]
        noTypeError src

      it "refuses an EVENT result that is inferred" $ do
        let src = Text.unlines $ types ++
              [ "@export Make an event"
              , "GIVEN p IS A Party"
              , "`make event` MEANS EVENT p ping 0"
              ]
        problems src `shouldBe` Right [(Just 4, "make event", Nothing, "an EVENT")]

      it "refuses an EVENT in a LIST OF, a MAYBE OF, or behind a synonym, or an ASSUME that the body reads" $ do
        let listed = Text.unlines $ types ++
              [ "@export How many"
              , "GIVEN es IS A LIST OF EVENT Party Act"
              , "GIVETH A NUMBER"
              , "`how many` MEANS 0"
              ]
            maybed = Text.unlines $ types ++
              [ "IMPORT prelude"
              , ""
              , "@export Maybe time"
              , "GIVEN m IS A MAYBE OF EVENT Party Act"
              , "GIVETH A NUMBER"
              , "`maybe time` MEANS 0"
              ]
            synonym = Text.unlines $ types ++
              [ "DECLARE Occurrence IS AN EVENT Party Act"
              , ""
              , "@export Who acted"
              , "GIVEN e IS AN Occurrence"
              , "GIVETH A NUMBER"
              , "`who acted` MEANS 0"
              ]
            assumed = Text.unlines $ types ++
              [ "ASSUME e IS AN EVENT Party Act"
              , ""
              , "@export Who acted"
              , "GIVETH A Party"
              , "`who acted` MEANS"
              , "  CONSIDER e"
              , "  WHEN EVENT p a n THEN p"
              ]
        problems listed `shouldBe` Right [(Just 4, "how many", Just "es", "an EVENT")]
        problems maybed `shouldBe` Right [(Just 6, "maybe time", Just "m", "an EVENT")]
        problems synonym `shouldBe` Right [(Just 6, "who acted", Just "e", "an EVENT")]
        problems assumed `shouldBe` Right [(Just 6, "who acted", Just "e", "an EVENT")]

      it "accepts an EVENT that the body builds or reads but the signature does not name" $ do
        let src = Text.unlines $ types ++
              [ "@export Who acted first"
              , "GIVEN p IS A Party"
              , "GIVETH A Party"
              , "`who acted first` MEANS"
              , "  CONSIDER EVENT p ping 0"
              , "  WHEN EVENT q a n THEN q"
              ]
        noTypeError src
        problems src `shouldBe` Right []

      it "accepts an EVENT in a definition that is not @export" $ do
        let src = Text.unlines $ types ++
              [ "GIVEN e IS AN EVENT Party Act"
              , "GIVETH A Party"
              , "`who acted` MEANS"
              , "  CONSIDER e"
              , "  WHEN EVENT p a n THEN p"
              ]
        noTypeError src
        problems src `shouldBe` Right []

      it "accepts a type of the user's own called EVENT" $ do
        let src = Text.unlines
              [ "DECLARE EVENT HAS who IS A STRING"
              , ""
              , "@export Who"
              , "GIVEN e IS AN EVENT"
              , "GIVETH A STRING"
              , "speaker MEANS e's who"
              ]
        noTypeError src
        problems src `shouldBe` Right []

    describe "DEONTIC" $ do
      -- Meng, 2026-10-30: contract rules are not exported for now, and the
      -- editor still evaluates them. The refusal is meant to be revisited.
      it "refuses a result that is a DEONTIC, and the file still type-checks" $ do
        let src = Text.unlines $ types ++
              [ "@export Duty"
              , "GIVETH A DEONTIC Party Act"
              , "`duty` MEANS PARTY alice MUST ping WITHIN 3"
              , ""
              , "#EVAL `duty`"
              ]
        problems src `shouldBe` Right [(Just 4, "duty", Nothing, "a DEONTIC, a contract rule")]
        noTypeError src

      it "refuses a DEONTIC input" $ do
        let src = Text.unlines $ types ++
              [ "@export Is it breached"
              , "GIVEN d IS A DEONTIC Party Act"
              , "GIVETH A BOOLEAN"
              , "`is breached` MEANS TRUE"
              ]
        problems src `shouldBe` Right [(Just 4, "is breached", Just "d", "a DEONTIC, a contract rule")]

    describe "which types have a shape" $ do
      it "accepts a record, an enumeration, a LIST OF, a MAYBE OF and a DATE" $ do
        let src = Text.unlines $ types ++
              [ "DECLARE Bill HAS"
              , "  amount IS A NUMBER"
              , "  due IS A DATE"
              , "  payer IS A Party"
              , "  notes IS A LIST OF STRING"
              , "  ref IS A MAYBE STRING"
              , ""
              , "@export Owed"
              , "GIVEN b IS A Bill"
              , "GIVETH A BOOLEAN"
              , "owed MEANS b's amount > 0"
              ]
        problems src `shouldBe` Right []
        inputShapes src `shouldBe` Right
          [ ( "b"
            , Right $ JRecord "Bill"
                [ JsonField "amount" JNumber True
                , JsonField "due" JDate True
                , JsonField "payer" (JEnum "Party" ["alice", "bob"]) True
                , JsonField "notes" (JArray JString) True
                , JsonField "ref" (JOptional JString) False
                ]
            )
          ]

      it "accepts a record that contains itself, and stops there" $ do
        let src = Text.unlines
              [ "DECLARE Tree HAS"
              , "  label IS A STRING"
              , "  kids IS A LIST OF Tree"
              , ""
              , "@export Label"
              , "GIVEN t IS A Tree"
              , "GIVETH A STRING"
              , "label MEANS t's label"
              ]
        problems src `shouldBe` Right []
        inputShapes src `shouldBe` Right
          [ ("t", Right (JRecord "Tree" [JsonField "label" JString True, JsonField "kids" (JArray (JRecursive "Tree")) True])) ]

      it "refuses a record with a function among its fields, and says which" $ do
        let src = Text.unlines
              [ "DECLARE Rule HAS"
              , "  name IS A STRING"
              , "  test IS A FUNCTION FROM NUMBER TO BOOLEAN"
              , ""
              , "@export Name"
              , "GIVEN r IS A Rule"
              , "GIVETH A STRING"
              , "name MEANS r's name"
              ]
        problems src `shouldBe` Right [(Just 5, "name", Just "r", "of a record type Rule whose field test is a function")]

      it "accepts an enumeration whose constructors have fields, as published until now" $ do
        let src = Text.unlines
              [ "DECLARE Action IS ONE OF"
              , "  delivery"
              , "  payment HAS amount IS A NUMBER"
              , ""
              , "@export Is it a payment"
              , "GIVEN a IS AN Action"
              , "GIVETH A BOOLEAN"
              , "`is it a payment` MEANS TRUE"
              ]
        problems src `shouldBe` Right []

      it "refuses EITHER, which has no shape yet" $ do
        let src = Text.unlines
              [ "@export Pick"
              , "GIVEN e IS AN EITHER STRING NUMBER"
              , "GIVETH A BOOLEAN"
              , "pick MEANS TRUE"
              ]
        problems src `shouldBe` Right [(Just 1, "pick", Just "e", "of the type EITHER")]

      it "warns about a GIVEN with no written type, and does not refuse it" $ do
        let src = Text.unlines
              [ "@export Is positive"
              , "GIVEN n"
              , "GIVETH A BOOLEAN"
              , "`is positive` MEANS n > 0"
              ]
        problems src `shouldBe` Right [(Just 1, "is positive", Just "n", "no written type")]

  describe "exported return type display" $ do
    -- A concrete inferred return type renders normally.
    it "renders a concrete inferred return type" $ do
      let src = Text.unlines
            [ "@export Adds one"
            , "GIVEN `x` IS A NUMBER"
            , "`plus one` MEANS `x` + 1"
            ]
      exportedReturnTypes src `shouldBe` Right [("plus one", "NUMBER")]

    -- A genuinely polymorphic inferred return type must normalise residual
    -- inference variables to stable names (a, b, …), never an edit-order
    -- dependent id like "res184" or "A3" that would make the deployed schema
    -- non-deterministic and trip the breaking-change check.
    it "normalises a residual inference variable to a stable type-variable name" $ do
      let src = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "@export Empty list"
            , "`xs` MEANS EMPTY"
            ]
      case exportedReturnTypes src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right rts -> do
          rts `shouldBe` [("xs", "LIST OF a")]
          -- And crucially: no raw inference-variable id leaks.
          all (not . Text.isInfixOf "res" . snd) rts `shouldBe` True
