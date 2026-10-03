{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The read-set of an @\@export@ is transitive: an ASSUME read by a helper
-- the export reaches (a module-level DECIDE, a WHERE-local, a mutually
-- recursive pair) is a parameter of the export, in the schema that
-- 'L4.Export.getExportedFunctions' and 'L4.FunctionSchema' publish. Before
-- this was so, the schema listed only the export body's own references, so
-- a request that validated against it could still get stuck on an assumed
-- term at evaluation time.
module ExportReadSetSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map

import L4.API.VirtualFS (checkWithImports, emptyVFS, vfsFromList)
import L4.Export (ExportedFunction(..), ExportedParam(..), getExportedFunctions)
import L4.FunctionSchema (Parameters(..), Parameter(..), parametersFromDecide)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Syntax (Resolved, getActual, rawName, unqualifiedRawNameToText)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))

-- | A resolved name as the author wrote it, without its section.
nameOf :: Resolved -> Text
nameOf = unqualifiedRawNameToText . rawName . getActual

-- | The parameter names of the single export in a source snippet.
exportParamNames :: Text -> Either [Text] [Text]
exportParamNames source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> case getExportedFunctions r.tcdModule of
      [ef] -> Right (map (.paramName) ef.exportParams)
      efs  -> Left ["expected exactly one export, got " <> Text.pack (show (length efs))]

-- | The JSON-schema 'Parameters' of the single export in a source snippet.
exportSchema :: Text -> Either [Text] Parameters
exportSchema source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> case getExportedFunctions r.tcdModule of
      [ef] -> Right (parametersFromDecide r.tcdModule ef.exportDecide)
      efs  -> Left ["expected exactly one export, got " <> Text.pack (show (length efs))]

-- | The GIVEN/ASSUME name-clash errors a snippet raises.
nameClashErrors :: Text -> Either [Text] [CheckErrorWithContext]
nameClashErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e | e@MkCheckErrorWithContext{kind = ExportAssumeNameClash _ _} <- r.tcdErrors ]

helperReadsAssume :: Text
helperReadsAssume = Text.unlines
  [ "ASSUME x IS A NUMBER"
  , "g MEANS x PLUS 1"
  , ""
  , "@export f adds"
  , "GIVEN y IS A NUMBER"
  , "GIVETH A NUMBER"
  , "f y MEANS g PLUS y"
  ]

spec :: Spec
spec = do
  describe "transitive export read-set" $ do
    it "lists an ASSUME read only by a module-level helper" $ do
      exportParamNames helperReadsAssume `shouldBe` Right ["y", "x"]

    it "lists an ASSUME read only by a WHERE-local helper" $ do
      let src = Text.unlines
            [ "ASSUME x IS A NUMBER"
            , ""
            , "@export helper in WHERE reads the ASSUME"
            , "GIVEN y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f y MEANS h PLUS y"
            , "  WHERE"
            , "    h MEANS x PLUS 1"
            ]
      exportParamNames src `shouldBe` Right ["y", "x"]

    it "reaches an ASSUME through mutual recursion (and terminates)" $ do
      let src = Text.unlines
            [ "ASSUME x IS A NUMBER"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "even n MEANS IF n EQUALS 0 THEN x ELSE odd (n MINUS 1)"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "odd n MEANS IF n EQUALS 0 THEN 0 ELSE even (n MINUS 1)"
            , ""
            , "@export mutual recursion reaches the ASSUME"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f n MEANS even n"
            ]
      exportParamNames src `shouldBe` Right ["n", "x"]

    it "does not list an ASSUME no reachable definition reads" $ do
      let src = Text.unlines
            [ "ASSUME x IS A NUMBER"
            , "ASSUME z IS A NUMBER"
            , "g MEANS x PLUS 1"
            , "unrelated MEANS z PLUS 1"
            , ""
            , "@export f adds"
            , "GIVEN y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f y MEANS g PLUS y"
            ]
      exportParamNames src `shouldBe` Right ["y", "x"]

  describe "function schema for read ASSUMEs" $ do
    it "requires a helper-read ASSUME exactly once" $ do
      case exportSchema helperReadsAssume of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps -> do
          ps.required `shouldBe` ["y", "x"]
          Map.keys ps.parameterMap `shouldBe` ["x", "y"]

    it "carries the ASSUME's own @desc into the schema" $ do
      let src = Text.unlines
            [ "@desc the offset added by the helper"
            , "ASSUME x IS A NUMBER"
            , "g MEANS x PLUS 1"
            , ""
            , "@export f adds"
            , "GIVEN y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f y MEANS g PLUS y"
            ]
      case exportSchema src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps ->
          fmap (.parameterDescription) (Map.lookup "x" ps.parameterMap)
            `shouldBe` Just "the offset added by the helper"

  describe "GIVEN / ASSUME name clash" $ do
    let clash = Text.unlines
          [ "ASSUME x IS A NUMBER"
          , "g MEANS x PLUS 1"
          , ""
          , "@export f adds"
          , "GIVEN x IS A NUMBER"
          , "GIVETH A NUMBER"
          , "f x MEANS g PLUS x"
          ]

    it "is reported as a check error" $ do
      case nameClashErrors clash of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right es -> length es `shouldBe` 1

    it "is not reported when the names differ" $ do
      case nameClashErrors helperReadsAssume of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right es -> es `shouldBe` []

    it "keeps one property and one required entry for the clashing name" $ do
      case exportSchema clash of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps -> do
          ps.required `shouldBe` ["x"]
          Map.keys ps.parameterMap `shouldBe` ["x"]

  -- R8 rule 3 (W7): a default is an expression, and whatever reads the input
  -- is charged with what the default reads, so a request can supply it.
  describe "export read-set through a TYPICALLY default" $ do
    let binderReadsBinder = Text.unlines
          [ "§ `Pricing`"
          , "    GIVEN `list price` IS A NUMBER"
          , "          discount IS A NUMBER TYPICALLY (`list price` DIVIDED BY 10)"
          , ""
          , "@export final"
          , "GIVETH A NUMBER"
          , "`final price` MEANS discount TIMES 2"
          ]
        inputDefaultReadsAssume = Text.unlines
          [ "ASSUME k IS A NUMBER"
          , ""
          , "@export scaled"
          , "GIVEN base IS A NUMBER"
          , "      rate IS A NUMBER TYPICALLY (k PLUS 1)"
          , "GIVETH A NUMBER"
          , "scaled MEANS base TIMES rate"
          ]
        defaultSuppliesInput = Text.unlines
          [ "§ `Supplied`"
          , "    GIVEN base IS A NUMBER TYPICALLY 4"
          , ""
          , "GIVETH A NUMBER"
          , "`double it` MEANS base TIMES 2"
          , ""
          , "@export scaled"
          , "GIVEN rate IS A NUMBER TYPICALLY (`double it` WITH base IS 1)"
          , "GIVETH A NUMBER"
          , "scaled MEANS rate TIMES 100"
          ]
        suppliedDefault = Text.unlines
          [ "§ `Supplied`"
          , "    GIVEN base IS A NUMBER TYPICALLY 4"
          , "          doubled IS A NUMBER TYPICALLY (`double it` WITH base IS 10)"
          , ""
          , "GIVETH A NUMBER"
          , "`double it` MEANS base TIMES 2"
          , ""
          , "@export read"
          , "GIVETH A NUMBER"
          , "`read it` MEANS doubled"
          ]

    it "lists a section input that only another input's default reads" $ do
      exportParamNames binderReadsBinder `shouldBe` Right ["list price", "discount"]

    -- The export's closure follows references and does not subtract what a WITH
    -- supplies, as it never has for a body: `base` is listed although the default
    -- supplies it for itself. That over-asks and is loud, and is not W7's to
    -- change; `ok/typically-expression.l4` pins that it is no cycle.
    it "lists an input a default supplies for itself, as it does for a body" $ do
      exportParamNames suppliedDefault `shouldBe` Right ["base", "doubled"]

    -- A request that leaves `rate` out takes its default, which reads the written
    -- ASSUME `k`, so `k` is an input of the export and a request can supply it. It
    -- was left out of the schema, and a request that sent it was refused as an
    -- unknown parameter (W7 second review, rulings S4).
    it "lists a written ASSUME that an export's own input's default reads" $ do
      exportParamNames inputDefaultReadsAssume `shouldBe` Right ["base", "rate", "k"]

    -- The export's closure follows what an export's own input's default calls for a
    -- written ASSUME, and not for a section input: the default gives `base` itself,
    -- so `base` is no input of the export. Binding it to the row in l4 batch would
    -- make the WITH in the default a WITH to a bound input, which is refused.
    it "does not list a section input that an export's own input's default supplies" $ do
      exportParamNames defaultSuppliesInput `shouldBe` Right ["rate"]

    it "publishes an expression default as its source text, and a literal as its value" $ do
      case exportSchema binderReadsBinder of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps -> do
          fmap (.parameterDefault) (Map.lookup "discount" ps.parameterMap)
            `shouldBe` Just (Just (Aeson.String "`list price` DIVIDED BY 10"))
          ps.required `shouldBe` ["list price"]
      case exportSchema (Text.unlines
             [ "@export f"
             , "GIVEN n IS A NUMBER TYPICALLY 3"
             , "GIVETH A NUMBER"
             , "f MEANS n"
             ]) of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps ->
          fmap (.parameterDefault) (Map.lookup "n" ps.parameterMap)
            `shouldBe` Just (Just (Aeson.Number 3))

    -- A call with several arguments is one line, comma-separated, so that it
    -- reads as source wherever it is written out; it used to put each argument on
    -- a line of its own, with the column padding that goes with it.
    it "publishes a default that is a call with several arguments on one line" $ do
      case exportSchema (Text.unlines
             [ "GIVEN a IS A NUMBER"
             , "      b IS A NUMBER"
             , "GIVETH A NUMBER"
             , "combine MEANS a PLUS b"
             , ""
             , "§ `Pricing`"
             , "    GIVEN `list price` IS A NUMBER"
             , "          discount IS A NUMBER TYPICALLY (combine WITH a IS `list price`, b IS 1)"
             , ""
             , "@export final"
             , "GIVETH A NUMBER"
             , "`final price` MEANS discount TIMES 2"
             ]) of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right ps ->
          fmap (.parameterDefault) (Map.lookup "discount" ps.parameterMap)
            `shouldBe` Just (Just (Aeson.String "combine WITH a IS `list price`, b IS 1"))

    it "reports a default that reads its own input as a check error" $ do
      let src = Text.unlines
            [ "§ `Loop`"
            , "    GIVEN a IS A NUMBER TYPICALLY (b PLUS 1)"
            , "          b IS A NUMBER TYPICALLY (a PLUS 1)"
            ]
      case checkWithImports emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right r ->
          [ length bs | MkCheckErrorWithContext{kind = TypicallyCycle bs} <- r.tcdErrors ]
            `shouldBe` [2]

    -- W7, decision 1 (§4.3 of the spec): a rule's own input takes an expression
    -- too, but not one that reads a section input, so a section input is never
    -- an input of an export merely because an export's own input's default
    -- reads it: the module is refused instead.
    describe "a rule input's or a field's default that reads a section input" $ do
      let readsOf src =
            case checkWithImports emptyVFS src of
              Left errs -> fail $ "Fatal: " ++ show errs
              Right r ->
                pure [ (nameOf owner, map nameOf bs)
                     | MkCheckErrorWithContext{kind = TypicallyReadsInput owner bs} <- r.tcdErrors ]
          ruleInput = Text.unlines
            [ "§ `Rates`"
            , "    GIVEN alpha IS A NUMBER"
            , ""
            , "@export scaled"
            , "GIVEN base IS A NUMBER"
            , "      rate IS A NUMBER TYPICALLY (alpha PLUS 1)"
            , "GIVETH A NUMBER"
            , "scaled MEANS base TIMES rate"
            ]
          throughDefinition = Text.unlines
            [ "§ `Rates`"
            , "    GIVEN alpha IS A NUMBER"
            , ""
            , "GIVETH A NUMBER"
            , "`alpha plus one` MEANS alpha PLUS 1"
            , ""
            , "DECLARE Config HAS"
            , "  timeout IS A NUMBER TYPICALLY `alpha plus one`"
            , "  retries IS A NUMBER"
            ]
          control = Text.unlines
            [ "GIVETH A NUMBER"
            , "phi MEANS 8"
            , ""
            , "§ `Rates`"
            , "    GIVEN alpha IS A NUMBER"
            , "          beta IS A NUMBER TYPICALLY (alpha PLUS 1)"
            , ""
            , "@export scaled"
            , "GIVEN base IS A NUMBER"
            , "      rate IS A NUMBER TYPICALLY (phi PLUS 1)"
            , "GIVETH A NUMBER"
            , "scaled MEANS base TIMES rate"
            ]
      it "is refused, naming the input and what it reads" $ do
        rs <- readsOf ruleInput
        rs `shouldBe` [("rate", ["alpha"])]
      it "is refused through a definition, for a record's field too" $ do
        rs <- readsOf throughDefinition
        rs `shouldBe` [("timeout", ["alpha"])]
      -- Positive control: a default that reads only a definition that reads no
      -- section input, and a section input's own default that reads another,
      -- raise nothing, so the two above are what the check can see.
      it "raises nothing for a default that reads no section input" $ do
        rs <- readsOf control
        rs `shouldBe` []

    -- W7 second review, rulings S5 and silent S8: the refusal of an export that
    -- reaches an imported reader ('validateExportImplicitImports') reads the body
    -- and the export's own inputs' defaults, and now the defaults of the fields of
    -- the records those inputs carry, because the decoder takes one when a request
    -- leaves the field out.
    describe "a record field's default that reaches an imported reader" $ do
      let lib = Text.unlines
            [ "§ `Rates`"
            , "    GIVEN `the rate` IS A NUMBER TYPICALLY 0.05"
            , ""
            , "GIVEN amount IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`scaled by the rate` amount MEANS amount TIMES `the rate`"
            , ""
            , "GIVEN amount IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`doubled` amount MEANS amount TIMES 2"
            ]
          vfs = vfsFromList [("rates", lib)]
          crossings src =
            case checkWithImports vfs src of
              Left errs -> fail $ "Fatal: " ++ show errs
              Right r ->
                pure [ (nameOf fn, unqualifiedRawNameToText (rawName imported))
                     | MkCheckErrorWithContext{kind = ImplicitCrossesImport fn imported} <- r.tcdErrors ]
          exportTaking reader = Text.unlines
            [ "IMPORT rates"
            , ""
            , "DECLARE Config HAS"
            , "  markup IS A NUMBER TYPICALLY (" <> reader <> " 100)"
            , "  retries IS A NUMBER"
            , ""
            , "@export cost"
            , "GIVEN amount IS A NUMBER"
            , "      cfg IS A Config"
            , "GIVETH A NUMBER"
            , "`cost with config` MEANS amount PLUS cfg's markup"
            ]
          -- the record sits in a field of another record the export takes
          nested = Text.unlines
            [ "IMPORT rates"
            , ""
            , "DECLARE Config HAS"
            , "  markup IS A NUMBER TYPICALLY (`scaled by the rate` 100)"
            , "  retries IS A NUMBER"
            , ""
            , "DECLARE Wrapper HAS"
            , "  inner IS A Config"
            , ""
            , "@export cost"
            , "GIVEN amount IS A NUMBER"
            , "      w IS A Wrapper"
            , "GIVETH A NUMBER"
            , "`cost with wrapper` MEANS amount PLUS w's inner's markup"
            ]
      it "is refused, naming the export and the reader" $ do
        cs <- crossings (exportTaking "`scaled by the rate`")
        cs `shouldBe` [("cost with config", "scaled by the rate")]
      it "is refused when the record is nested in another the export takes" $ do
        cs <- crossings nested
        cs `shouldBe` [("cost with wrapper", "scaled by the rate")]
      -- Positive control: the same shape with an imported rule that reads no section
      -- input is not a reader, and raises nothing.
      it "raises nothing for a default that names an imported rule that reads no input" $ do
        cs <- crossings (exportTaking "`doubled`")
        cs `shouldBe` []
      -- The same control for an export's own input's default, which F7 refuses when it
      -- reaches a reader: a rule that reads no input is not one.
      it "raises nothing for an export input's default that names an imported rule that reads no input" $ do
        cs <- crossings (Text.unlines
          [ "IMPORT rates"
          , ""
          , "@export cost"
          , "GIVEN amount IS A NUMBER"
          , "      markup IS A NUMBER TYPICALLY (`doubled` 100)"
          , "GIVETH A NUMBER"
          , "`cost with markup` MEANS amount PLUS markup"
          ])
        cs `shouldBe` []
      it "is refused for an export input's default that names an imported reader" $ do
        cs <- crossings (Text.unlines
          [ "IMPORT rates"
          , ""
          , "@export cost"
          , "GIVEN amount IS A NUMBER"
          , "      markup IS A NUMBER TYPICALLY (`scaled by the rate` 100)"
          , "GIVETH A NUMBER"
          , "`cost with markup` MEANS amount PLUS markup"
          ])
        cs `shouldBe` [("cost with markup", "scaled by the rate")]
