{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ExportValidationSpec (spec) where

import Control.Exception (evaluate)
import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import System.Timeout (timeout)

import L4.API.VirtualFS (VFS, checkWithImports, emptyVFS, vfsFromList)
import L4.Export (ExportedFunction(..), getExportedFunctions, enrichReturnTypes)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Print (prettyTypeForDisplay)
import L4.Syntax (getActual, nameToText)
import L4.TypeCheck (prettyCheckErrorWithContext)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))

-- | Run typecheck on a source snippet and return the list of
-- 'ExportFunctionTypeInput' errors that fired (or 'Left' on fatal failure).
exportFnErrors :: Text -> Either [Text] [CheckErrorWithContext]
exportFnErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e
      | e@MkCheckErrorWithContext{kind = ExportFunctionTypeInput _ _} <- r.tcdErrors
      ]

-- | Run typecheck on a source snippet and return the 'ExportEventTypeInput'
-- errors that fired, as (function name, input name) pairs, together with the
-- error text a user sees for the first of them. The snippet can import the
-- modules of the given VFS.
exportEventErrors :: VFS -> Text -> Either [Text] ([(Text, Text)], [Text])
exportEventErrors vfs source =
  case checkWithImports vfs source of
    Left errs -> Left errs
    Right r ->
      let hits =
            [ e
            | e@MkCheckErrorWithContext{kind = ExportEventTypeInput _ _} <- r.tcdErrors
            ]
      in Right
        ( [ (nameToText (getActual fn), nameToText (getActual p))
          | MkCheckErrorWithContext{kind = ExportEventTypeInput fn p} <- hits
          ]
        , concatMap prettyCheckErrorWithContext (take 1 hits)
        )

-- | 'exportEventErrors' on a snippet with no imports, under a watchdog: the
-- walk over a type's fields once took a time that doubled with every level
-- of nesting, so a regression is reported as a failure and not as a hung
-- suite. The pairs only: (function, input).
refusedWithinWatchdog :: Text -> IO [(Text, Text)]
refusedWithinWatchdog src = do
  mb <- timeout (30 * 1000000) $ case exportEventErrors emptyVFS src of
    Left errs -> fail ("Fatal: " ++ show errs)
    Right (hits, _) -> evaluate (length hits) >> pure hits
  maybe (fail "the export check did not finish within 30s") pure mb

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

  describe "validateExportInputs" $ do
    it "rejects @export with a function-typed GIVEN parameter" $ do
      let src = Text.unlines
            [ "@export Apply the predicate"
            , "GIVEN `p` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_given_test` IF `p` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    it "rejects @export that references a function-typed ASSUME" $ do
      let src = Text.unlines
            [ "ASSUME `pred` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , ""
            , "@export Apply assumed predicate"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_assume_test` IF `pred` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    it "accepts @export with only value-typed inputs" $ do
      let src = Text.unlines
            [ "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF `age` >= 18"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> fns `shouldBe` []

    it "ignores function-typed ASSUMEs that aren't referenced by any export" $ do
      let src = Text.unlines
            [ "ASSUME `unused_fn` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `check_age` IF `age` >= 18"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> fns `shouldBe` []

    it "ignores function-typed GIVENs on non-@export DECIDEs" $ do
      let src = Text.unlines
            [ "GIVEN `p` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `internal_helper` IF `p` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> fns `shouldBe` []

    it "rejects MAYBE-wrapped function-typed GIVEN" $ do
      let src = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "@export With maybe callback"
            , "GIVEN `cb` IS A MAYBE OF FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_maybe_test` IF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    it "rejects function-typed input via type synonym" $ do
      let src = Text.unlines
            [ "DECLARE `Pred` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , ""
            , "@export Via synonym"
            , "GIVEN `p` IS A `Pred`"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_syn_test` IF `p` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

  -- An EVENT has no JSON form: the service's input decoder reads an object
  -- only into a declared record, the builtin EVENT type has none, and so an
  -- exported rule that takes one publishes a bare @object@ schema that no
  -- request can satisfy. The check refuses it where it refuses a function-typed
  -- input, so that `l4 check`, `l4 batch`, `jl4-schema` and the service's
  -- deploy all stop at the same error.
  describe "EVENT-typed inputs of an @export" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        -- the pairs only: (function, input)
        refused vfs src = case exportEventErrors vfs src of
          Left errs -> fail $ "Fatal: " ++ show errs
          Right (hits, _) -> pure hits

    it "rejects a GIVEN of type EVENT, naming the function and the input" $ do
      let src = parties <> Text.unlines
            [ "@export When it happened"
            , "GIVEN `the reported event` IS AN EVENT Person Action"
            , "GIVETH A NUMBER"
            , "`when it happened` `the reported event` MEANS"
            , "  CONSIDER `the reported event`"
            , "  WHEN EVENT party action time THEN time"
            ]
      refused emptyVFS src `shouldReturn` [("when it happened", "the reported event")]

    it "says what is wrong and what to do instead" $ do
      let src = parties <> Text.unlines
            [ "@export When it happened"
            , "GIVEN e IS AN EVENT Person Action"
            , "GIVETH A NUMBER"
            , "`when it happened` e MEANS 1"
            ]
      case exportEventErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `when it happened`:"
            , "  EVENT inputs are not supported for @export."
            , "  The input `e` has a type that contains an EVENT, and a request has no JSON form for an event."
            , "  Give the rule the party, the action and the time as separate inputs, and build the event inside it."
            ]

    it "rejects a LIST OF EVENT" $ do
      let src = parties <> Text.unlines
            [ "@export Any events"
            , "GIVEN es IS A LIST OF EVENT Person Action"
            , "GIVETH A BOOLEAN"
            , "`any events` es MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("any events", "es")]

    it "rejects a MAYBE EVENT" $ do
      let src = parties <> Text.unlines
            [ "@export Maybe an event"
            , "GIVEN me IS A MAYBE (EVENT Person Action)"
            , "GIVETH A BOOLEAN"
            , "`maybe an event` me MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("maybe an event", "me")]

    it "rejects an EVENT reached through a type synonym" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Occurrence IS AN EVENT Person Action"
            , ""
            , "@export Via synonym"
            , "GIVEN o IS AN Occurrence"
            , "GIVETH A BOOLEAN"
            , "`via synonym` o MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("via synonym", "o")]

    it "rejects an EVENT in a field of a record" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Report HAS reported IS AN EVENT Person Action"
            , "                   note IS A STRING"
            , ""
            , "@export Report note"
            , "GIVEN r IS A Report"
            , "GIVETH A STRING"
            , "`report note` r MEANS r's note"
            ]
      refused emptyVFS src `shouldReturn` [("report note", "r")]

    it "rejects an EVENT in a field of a constructor of a sum type" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Entry IS ONE OF"
            , "  unrecorded"
            , "  recorded HAS what IS AN EVENT Person Action"
            , ""
            , "@export Entry kind"
            , "GIVEN x IS AN Entry"
            , "GIVETH A BOOLEAN"
            , "`entry kind` x MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("entry kind", "x")]

    it "rejects an EVENT that sits behind a record of an imported module" $ do
      let lib = parties <> Text.unlines
            [ "DECLARE Report HAS reported IS AN EVENT Person Action"
            , ""
            , "DECLARE Occurrence IS AN EVENT Person Action"
            ]
          src = Text.unlines
            [ "IMPORT lib"
            , ""
            , "@export Report"
            , "GIVEN r IS A Report"
            , "GIVETH A BOOLEAN"
            , "`report` r MEANS TRUE"
            , ""
            , "@export Occurrence"
            , "GIVEN o IS AN Occurrence"
            , "GIVETH A BOOLEAN"
            , "`occurrence` o MEANS TRUE"
            ]
      refused (vfsFromList [("lib", lib)]) src
        `shouldReturn` [("report", "r"), ("occurrence", "o")]

    it "rejects an @export that uses an ASSUME of type EVENT" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `assumed event` IS AN EVENT Person Action"
            , ""
            , "@export Assumed"
            , "GIVETH A BOOLEAN"
            , "`assumed` MEANS"
            , "  CONSIDER `assumed event`"
            , "  WHEN EVENT party action time THEN TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("assumed", "assumed event")]

    it "ignores an ASSUME of type EVENT that no export uses" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `assumed event` IS AN EVENT Person Action"
            , ""
            , "@export Plain"
            , "GIVETH A BOOLEAN"
            , "`plain` MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` []

    it "reports each offending input, once" $ do
      let src = parties <> Text.unlines
            [ "@export Two events"
            , "GIVEN a IS AN EVENT Person Action"
            , "      b IS AN EVENT Person Action"
            , "      n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`two events` a b n MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("two events", "a"), ("two events", "b")]

    it "accepts a rule that takes an EVENT when it is not an @export" $ do
      let src = parties <> Text.unlines
            [ "GIVEN e IS AN EVENT Person Action"
            , "GIVETH A NUMBER"
            , "`when it happened` e MEANS"
            , "  CONSIDER e"
            , "  WHEN EVENT party action time THEN time"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts an @export that builds the event from its parts" $ do
      let src = parties <> Text.unlines
            [ "@export When it happened"
            , "GIVEN who IS A Person"
            , "      what IS AN Action"
            , "      `at time` IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`when it happened` who what `at time` MEANS"
            , "  CONSIDER EVENT who what `at time`"
            , "  WHEN EVENT party action time THEN time"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts an @export whose inputs are records, lists and maybes without an EVENT" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Report HAS who IS A Person"
            , "                   note IS A STRING"
            , "                   others IS A LIST OF Report"
            , ""
            , "@export Report note"
            , "GIVEN r IS A Report"
            , "      m IS A MAYBE NUMBER"
            , "GIVETH A STRING"
            , "`report note` r m MEANS r's note"
            ]
      refused emptyVFS src `shouldReturn` []

    it "terminates on a record that contains itself" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Tree HAS label IS A STRING"
            , "                 children IS A LIST OF Tree"
            , ""
            , "@export Label"
            , "GIVEN t IS A Tree"
            , "GIVETH A STRING"
            , "`label` t MEANS t's label"
            ]
      refused emptyVFS src `shouldReturn` []

    it "terminates on records that contain each other" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Ping HAS pong IS A MAYBE Pong"
            , "                 note IS A STRING"
            , "DECLARE Pong HAS ping IS A MAYBE Ping"
            , ""
            , "@export Note"
            , "GIVEN p IS A Ping"
            , "GIVETH A STRING"
            , "`note` p MEANS p's note"
            ]
      refused emptyVFS src `shouldReturn` []

    it "finds an EVENT in a record that is part of a cycle" $ do
      -- Both are asked for, from either end of the cycle: the EVENT is in a
      -- field of the type that the walk was already inside when it came back
      -- to it.
      let types = parties <> Text.unlines
            [ "DECLARE Ping HAS pong IS A MAYBE Pong"
            , "                 seen IS AN EVENT Person Action"
            , "DECLARE Pong HAS ping IS A MAYBE Ping"
            , ""
            ]
          export name input = Text.unlines
            [ "@export " <> name
            , "GIVEN x IS A " <> input
            , "GIVETH A BOOLEAN"
            , "`" <> name <> "` x MEANS TRUE"
            ]
      refused emptyVFS (types <> export "from ping" "Ping")
        `shouldReturn` [("from ping", "x")]
      refused emptyVFS (types <> export "from pong" "Pong")
        `shouldReturn` [("from pong", "x")]

    it "terminates on synonyms that name each other" $ do
      let src = parties <> Text.unlines
            [ "DECLARE SA IS A SB"
            , "DECLARE SB IS A SA"
            , ""
            , "@export Get"
            , "GIVEN t IS AN SA"
            , "GIVETH A NUMBER"
            , "`get` t MEANS 1"
            ]
      refused emptyVFS src `shouldReturn` []

    it "rejects an EVENT in any constructor of a sum type, the first included" $ do
      -- The constructors of a type are gathered into one list of field types.
      -- An EVENT in the first of them must count as much as one in the last.
      let sumType eventFirst = parties <> Text.unlines
            ( [ "DECLARE Entry IS ONE OF" ]
              <> (if eventFirst
                    then [ "  recorded HAS what IS AN EVENT Person Action"
                         , "  plain HAS n IS A NUMBER"
                         ]
                    else [ "  plain HAS n IS A NUMBER"
                         , "  recorded HAS what IS AN EVENT Person Action"
                         ]
                 )
              <> [ "  unrecorded"
                 , ""
                 , "@export Entry kind"
                 , "GIVEN x IS AN Entry"
                 , "GIVETH A BOOLEAN"
                 , "`entry kind` x MEANS TRUE"
                 ]
            )
      refused emptyVFS (sumType True) `shouldReturn` [("entry kind", "x")]
      refused emptyVFS (sumType False) `shouldReturn` [("entry kind", "x")]

    -- A chain of records in which each has TWO fields of the next one has
    -- 2^n paths from the first record to the last, though only n + 1 types.
    -- The check has to look at each type once, whichever way it got there.
    describe "a chain of records that doubles at every level" $ do
      let depth = 40 :: Int
          typeName i = "T" <> Text.pack (show i)
          chain leafField = Text.unlines $
            [ Text.unlines
                [ "DECLARE " <> typeName i <> " HAS"
                , "  f0 IS A " <> typeName (i + 1)
                , "  f1 IS A " <> typeName (i + 1)
                ]
            | i <- [0 .. depth - 1]
            ]
            <> [ "DECLARE " <> typeName depth <> " HAS " <> leafField ]
          exportFirst = Text.unlines
            [ "@export Chain"
            , "GIVEN t IS A T0"
            , "GIVETH A BOOLEAN"
            , "`chain` t MEANS TRUE"
            ]

      it "is checked in a moment when it holds no EVENT" $ do
        let src = parties <> chain "leaf IS A NUMBER" <> exportFirst
        refusedWithinWatchdog src `shouldReturn` []

      it "is refused when only the last record holds an EVENT" $ do
        let src = parties <> chain "leaf IS AN EVENT Person Action" <> exportFirst
        refusedWithinWatchdog src `shouldReturn` [("chain", "t")]

      it "still finds an EVENT in a later field once the chain has been walked" $ do
        -- The chain holds none. The EVENT is in a field that comes after the
        -- field that leads into it, so the walk has been all through the
        -- chain before it gets there.
        let src = parties <> chain "leaf IS A NUMBER" <> Text.unlines
              [ "DECLARE Root HAS"
              , "  first IS A T0"
              , "  second IS A Side"
              , ""
              , "DECLARE Side HAS later IS AN EVENT Person Action"
              , ""
              , "@export Root"
              , "GIVEN r IS A Root"
              , "GIVETH A BOOLEAN"
              , "`root` r MEANS TRUE"
              ]
        refusedWithinWatchdog src `shouldReturn` [("root", "r")]

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
