{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ExportValidationSpec (spec) where

import Test.Hspec
import Control.Exception (evaluate)
import Data.Aeson (Value (..), decodeStrict)
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Foldable (toList)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import System.Timeout (timeout)

import L4.API (l4Check)

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (ExportError (..), ExportSite (..), ExportedFunction(..), ExportedParam(..), checkExports, getExportedFunctions, enrichReturnTypes, prettyExportError)
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

-- | The problems of a snippet, which have this long to be worked out in full. A
-- check that walks every path through nested types does not finish at all at
-- these sizes, so a failure here is a timeout and not a slow suite.
problemsWithin :: Int -> Text -> IO (Either [Text] [Problem])
problemsWithin seconds source = do
  let found = problems source
  timeout (seconds * 1000000) (evaluate (length (show found))) >>= \case
    Just _ -> pure found
    Nothing -> fail ("did not finish within " <> show seconds <> " seconds")

-- | Records nested to a depth, each with two fields of the record below it, so
-- that there are 2^depth paths to the bottom and depth+1 types. The fields are
-- given after those two.
diamond :: Int -> [Text] -> [Text]
diamond depth extraFields =
  "DECLARE L0 HAS v IS A NUMBER"
    : concat
        [ ["DECLARE " <> level i <> " HAS", "  a IS A " <> level (i - 1), "  b IS A " <> level (i - 1)]
        | i <- [1 .. depth]
        ]
    <> extraFields
 where
  level :: Int -> Text
  level i = "L" <> Text.pack (show i)

-- | What @l4_check@ says about a snippet, as (source, severity, message).
l4CheckDiagnostics :: Text -> [(Text, Int, Text)]
l4CheckDiagnostics source =
  case decodeStrict (Text.encodeUtf8 (l4Check source)) of
    Just (Array ds) -> [(s, truncate sev, m) | Object o <- toList ds, Just (String s) <- [KeyMap.lookup "source" o], Just (Number sev) <- [KeyMap.lookup "severity" o], Just (String m) <- [KeyMap.lookup "message" o]]
    _ -> []

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

      it "accepts an EITHER whose two sides have shapes, as published until now" $ do
        let src = Text.unlines
              [ "@export Pick"
              , "GIVEN e IS AN EITHER STRING NUMBER"
              , "GIVETH AN EITHER STRING NUMBER"
              , "pick MEANS e"
              ]
        problems src `shouldBe` Right []

      it "refuses an EITHER with a function on one side" $ do
        let src = Text.unlines
              [ "@export Pick"
              , "GIVEN e IS AN EITHER STRING (FUNCTION FROM NUMBER TO NUMBER)"
              , "GIVETH A BOOLEAN"
              , "pick MEANS TRUE"
              ]
        problems src `shouldBe` Right [(Just 1, "pick", Just "e", "a function")]

      it "warns about a GIVEN with no written type, and does not refuse it" $ do
        let src = Text.unlines
              [ "@export Is positive"
              , "GIVEN n"
              , "GIVETH A BOOLEAN"
              , "`is positive` MEANS n > 0"
              ]
        problems src `shouldBe` Right [(Just 1, "is positive", Just "n", "no written type")]

  describe "a type reached by many paths" $ do
    let exported ty =
          [ ""
          , "@export Deep"
          , "GIVEN x IS A " <> ty
          , "GIVETH A NUMBER"
          , "`deep rule` MEANS 1"
          ]

    it "checks records whose two fields share a record type, nested 64 levels" $ do
      let src = Text.unlines (diamond 64 (exported "L64"))
      r <- problemsWithin 30 src
      r `shouldBe` Right []
      case inputShapes src of
        Right [("x", Right (JRecord "L64" (JsonField "a" (JRecord "L63" _) True : _)))] -> pure ()
        other -> expectationFailure (show (fmap (map fst) other))

    it "finds a function in the field after the shared types, 64 levels down" $ do
      let src = Text.unlines $ diamond 64
            [ "DECLARE Top HAS"
            , "  below IS A L64"
            , "  test IS A FUNCTION FROM NUMBER TO BOOLEAN"
            , ""
            , "@export Deep"
            , "GIVEN x IS A Top"
            , "GIVETH A NUMBER"
            , "`deep rule` MEANS 1"
            ]
      r <- problemsWithin 30 src
      r `shouldBe` Right [(Just 198, "deep rule", Just "x", "of a record type Top whose field test is a function")]

    it "checks 14 records that each have a field of every one of them" $ do
      let names = [Text.pack ("T" <> show i) | i <- [1 .. 14 :: Int]]
          declare n = ("DECLARE " <> n <> " HAS") : ["  f" <> m <> " IS A MAYBE " <> m | m <- names]
          src = Text.unlines (concatMap declare names <> exported "T1")
      r <- problemsWithin 30 src
      r `shouldBe` Right []

    it "says the same of 14 such records with a function in the last, by the path it first meets it" $ do
      let names = [Text.pack ("T" <> show i) | i <- [1 .. 14 :: Int]]
          declare n =
            ("DECLARE " <> n <> " HAS")
              : ["  f" <> m <> " IS A " <> m | m <- names]
              <> ["  test IS A FUNCTION FROM NUMBER TO BOOLEAN" | n == "T14"]
          expected = foldr
            (\(n, m) why -> "of a record type " <> n <> " whose field f" <> m <> " is " <> why)
            "of a record type T14 whose field test is a function"
            (zip names (drop 1 names))
          src = Text.unlines (concatMap declare names <> exported "T1")
      r <- problemsWithin 30 src
      r `shouldBe` Right [(Just (length (concatMap declare names) + 2), "deep rule", Just "x", expected)]

    it "checks a type that takes a type and passes on twice what it was given, 40 levels" $ do
      let level :: Int -> Text
          level i = "P" <> Text.pack (show i)
          src = Text.unlines $
            "DECLARE P0 a HAS v IS AN a"
              : [ "DECLARE " <> level i <> " a HAS f IS A " <> level (i - 1) <> " OF (EITHER OF a, a)" | i <- [1 .. 40] ]
              <> exported "P40 OF NUMBER"
      r <- problemsWithin 30 src
      r `shouldBe` Right []

    -- The shape of a type in a cycle depends on where it is reached from: what
    -- is cut is what is being expanded on the way to it. A type must not keep
    -- the shape it had on the first path.
    it "gives a record in a cycle the shape it has from where it is reached" $ do
      let src = Text.unlines
            [ "DECLARE Top HAS"
            , "  q IS A Q"
            , "  r IS A R"
            , "DECLARE Q HAS r IS A R"
            , "DECLARE R HAS q IS A Q"
            , ""
            , "@export From the top"
            , "GIVEN x IS A Top"
            , "      y IS A Q"
            , "      z IS A R"
            , "GIVETH A NUMBER"
            , "`from the top` MEANS 1"
            ]
          field n s = JsonField n s True
      problems src `shouldBe` Right []
      inputShapes src `shouldBe` Right
        [ ( "x"
          , Right $ JRecord "Top"
              [ field "q" (JRecord "Q" [field "r" (JRecord "R" [field "q" (JRecursive "Q")])])
              , field "r" (JRecord "R" [field "q" (JRecord "Q" [field "r" (JRecursive "R")])])
              ]
          )
        , ("y", Right $ JRecord "Q" [field "r" (JRecord "R" [field "q" (JRecursive "Q")])])
        , ("z", Right $ JRecord "R" [field "q" (JRecord "Q" [field "r" (JRecursive "R")])])
        ]

    it "looks at a function in a record of a cycle, wherever the cycle is entered" $ do
      let src = Text.unlines
            [ "DECLARE P HAS q IS A Q"
            , "DECLARE Q HAS"
            , "  p IS A P"
            , "  test IS A FUNCTION FROM NUMBER TO BOOLEAN"
            , ""
            , "@export From P"
            , "GIVEN x IS A P"
            , "      y IS A Q"
            , "GIVETH A NUMBER"
            , "`from p` MEANS 1"
            ]
      problems src `shouldBe` Right
        [ (Just 6, "from p", Just "x", "of a record type P whose field q is of a record type Q whose field test is a function")
        , (Just 6, "from p", Just "y", "of a record type Q whose field test is a function")
        ]

    it "tells apart two uses of a type that takes a type" $ do
      let src = Text.unlines
            [ "DECLARE Box a HAS v IS AN a"
            , "DECLARE Holder HAS"
            , "  fine IS A Box OF NUMBER"
            , "  bad IS A Box OF (FUNCTION FROM NUMBER TO BOOLEAN)"
            , ""
            , "@export Holds"
            , "GIVEN h IS A Holder"
            , "GIVETH A NUMBER"
            , "`holds` MEANS 1"
            ]
      problems src `shouldBe` Right
        [(Just 6, "holds", Just "h", "of a record type Holder whose field bad is of a record type Box whose field v is a function")]

    it "looks inside a type given to itself" $ do
      let src = Text.unlines
            [ "DECLARE Box a HAS v IS AN a"
            , ""
            , "@export Holds"
            , "GIVEN h IS A Box OF (Box OF (FUNCTION FROM NUMBER TO BOOLEAN))"
            , "GIVETH A NUMBER"
            , "`holds` MEANS 1"
            ]
      problems src `shouldBe` Right
        [(Just 3, "holds", Just "h", "of a record type Box whose field v is a function")]

    it "stops at a type that gives itself a larger type" $ do
      let src = Text.unlines
            [ "DECLARE Grows a HAS"
            , "  v IS AN a"
            , "  next IS A MAYBE (Grows OF (LIST OF a))"
            , ""
            , "@export Grows"
            , "GIVEN g IS A Grows OF NUMBER"
            , "GIVETH A NUMBER"
            , "`grows` MEANS 1"
            ]
      r <- problemsWithin 30 src
      r `shouldBe` Right []

  describe "a generic rule" $ do
    it "says of its input that is a type, and of what uses it, that the rule is generic" $ do
      let src = Text.unlines
            [ "@export Pick"
            , "GIVEN a IS A TYPE"
            , "      `the default` IS AN a"
            , "GIVETH AN a"
            , "`pick the default` MEANS `the default`"
            ]
      problems src `shouldBe` Right
        [ (Just 1, "pick the default", Just "a", "a type, so the rule is generic")
        , (Just 1, "pick the default", Just "the default", "of the type variable `a`, so the rule is generic")
        , (Just 1, "pick the default", Nothing, "of the type variable `a`, so the rule is generic")
        ]

    it "says so of a result it inferred, which is not a function" $ do
      let src = Text.unlines
            [ "@export Same"
            , "GIVEN a IS A TYPE"
            , "      x IS AN a"
            , "`same back` MEANS x"
            ]
      problems src `shouldBe` Right
        [ (Just 1, "same back", Just "a", "a type, so the rule is generic")
        , (Just 1, "same back", Just "x", "of the type variable `a`, so the rule is generic")
        , (Just 1, "same back", Nothing, "of the type variable `a`, so the rule is generic")
        ]

    it "says so through a LIST OF and a record" $ do
      let src = Text.unlines
            [ "DECLARE Box b HAS v IS A b"
            , ""
            , "@export Count"
            , "GIVEN a IS A TYPE"
            , "      xs IS A LIST OF a"
            , "      y IS A Box OF a"
            , "GIVETH A NUMBER"
            , "`count` MEANS 0"
            ]
      problems src `shouldBe` Right
        [ (Just 3, "count", Just "a", "a type, so the rule is generic")
        , (Just 3, "count", Just "xs", "of the type variable `a`, so the rule is generic")
        , (Just 3, "count", Just "y", "of a record type Box whose field v is of the type variable `a`, so the rule is generic")
        ]

    it "says so of an ASSUME that holds for all types" $ do
      let src = Text.unlines
            [ "ASSUME anything IS FOR ALL a AN a"
            , ""
            , "@export Read"
            , "GIVETH A NUMBER"
            , "`read it` MEANS 1 + anything"
            ]
      problems src `shouldBe` Right
        [(Just 3, "read it", Just "anything", "of the type variable `a`, so the rule is generic")]

    it "says so of an input with no written type that the result comes from" $ do
      let src = Text.unlines
            [ "@export Same"
            , "GIVEN y"
            , "`same again` MEANS y"
            ]
      problems src `shouldBe` Right
        [ (Just 1, "same again", Just "y", "no written type")
        , (Just 1, "same again", Nothing, "of the type variable `y`, so the rule is generic")
        ]

    it "gives each of these messages one line on what to do, and does not list the types to use" $ do
      let src = Text.unlines
            [ "@export Pick"
            , "GIVEN a IS A TYPE"
            , "      `the default` IS AN a"
            , "GIVETH AN a"
            , "`pick the default` MEANS `the default`"
            ]
      case exportProblems src of
        Right errs -> do
          length errs `shouldBe` 3
          map (drop 1 . prettyExportError) errs `shouldSatisfy` all (== ["Write the type it is used at in its GIVEN and GIVETH, or publish a rule that calls it at that type."])
        Left e -> expectationFailure (show e)

  describe "l4_check, which the web editor reads" $ do
    let refused what result = Text.unlines $
          [ "DECLARE Party IS ONE OF alice, bob"
          , "DECLARE Act IS ONE OF ping, pong"
          , ""
          , "@export Refused"
          ] <> what <> [result]
    it "reports an EVENT input as l4 check does" $
      l4CheckDiagnostics (refused ["GIVEN e IS AN EVENT Party Act", "GIVETH A NUMBER"] "`refused` MEANS 1")
        `shouldBe` [("export", 1, "`refused` is published with @export, but its input `e` is an EVENT, and @export does not support that yet.\nTake the party, the action and the time as separate inputs, and build the event inside the rule.")]
    it "reports a function input as l4 check does" $
      l4CheckDiagnostics (refused ["GIVEN test IS A FUNCTION FROM NUMBER TO BOOLEAN", "GIVETH A NUMBER"] "`refused` MEANS 1")
        `shouldBe` [("export", 1, "`refused` is published with @export, but its input `test` is a function, and @export does not support that yet.\nPass the values the function would work on, and apply the function inside the rule.")]
    it "reports a DEONTIC result as l4 check does" $
      l4CheckDiagnostics (refused ["GIVETH A DEONTIC Party Act"] "`refused` MEANS PARTY alice MUST ping WITHIN 3")
        `shouldBe` [("export", 1, "`refused` is published with @export, but its result is a DEONTIC, a contract rule, and @export does not support that yet.\nA contract can't be an @export input or result yet. Remove the @export; the rule still evaluates in the editor, with its #EVAL and #EVALTRACE.")]
    it "reports a GIVEN with no written type as a warning" $
      l4CheckDiagnostics (refused ["GIVEN n", "GIVETH A BOOLEAN"] "`refused` MEANS n > 0")
        `shouldBe` [("export", 2, "`refused` is published with @export, but its input `n` has no written type.\nWrite one in the GIVEN, so that the schema says what to send.")]
    it "has nothing to say of an @export that can be sent" $
      l4CheckDiagnostics (refused ["GIVEN p IS A Party", "GIVETH A Party"] "`refused` MEANS p") `shouldBe` []
    it "knows the types of what the file imports" $
      l4CheckDiagnostics (Text.unlines
        [ "IMPORT time"
        , ""
        , "@export Imported"
        , "GIVEN m IS A `Meridiem Indicator`"
        , "GIVETH A NUMBER"
        , "`imported` MEANS 1"
        ]) `shouldBe` []
    it "does not ask what the exports of a file that does not type-check take" $ do
      let ds = l4CheckDiagnostics (refused ["GIVEN e IS AN EVENT Party Act", "GIVETH A NUMBER"] "`refused` MEANS TRUE")
      ds `shouldNotBe` []
      [s | (s, _, _) <- ds] `shouldSatisfy` all (/= "export")

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
