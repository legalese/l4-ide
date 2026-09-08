{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ExportValidationSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (ExportedFunction(..), getExportedFunctions, enrichReturnTypes)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Print (prettyTypeForDisplay)
import qualified L4.TypeCheck as TC
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

-- | Run typecheck and return the arity carried by every
-- 'ExportAssumeArityInput' — so a test can assert both how many fired and what
-- each one counted. The names are asserted through 'renderedErrors' instead,
-- which is what a user actually reads.
--
-- Separate from 'exportFnErrors' on purpose: the two constructors are the two
-- spellings of one refusal (R-X4), and a test that counted them together could
-- not tell a widened gate from a reclassified one.
exportArityErrors :: Text -> Either [Text] [Int]
exportArityErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ arity
      | MkCheckErrorWithContext{kind = ExportAssumeArityInput _ _ arity} <- r.tcdErrors
      ]

-- | Every diagnostic the checker would print, as one blob — for asserting on
-- the wording a user actually sees.
renderedErrors :: Text -> Either [Text] Text
renderedErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right (Text.unlines (concatMap TC.prettyCheckErrorWithContext r.tcdErrors))

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

  -- R-X4, 2026-09-07 (specs/todo/IMPLICIT-PROPS-DESIGN.md §11.20): the gate is
  -- keyed on the assumed name's ARITY, not on how its type is spelled. The
  -- app-form spelling below used to pass `l4 check` and then die on every
  -- `l4 batch` row with a stuck assumed term — a false green, which is worse
  -- than the refusal it dodged.
  describe "validateExportInputs, app-form ASSUME (R-X4)" $ do
    let appFormSrc = Text.unlines
          [ "ASSUME Person IS A TYPE"
          , ""
          , "GIVEN `p` IS A Person"
          , "ASSUME `is authorised` `p` IS A BOOLEAN"
          , ""
          , "@export Whether the person may act"
          , "GIVEN `who` IS A Person"
          , "GIVETH A BOOLEAN"
          , "DECIDE `may act` IF `is authorised` `who`"
          ]

    it "rejects an @export that reads a one-input assumed rule" $
      exportArityErrors appFormSrc `shouldBe` Right [1]

    it "does not misreport it as a function-typed input" $
      -- The declared type IS `BOOLEAN`. Reusing ExportFunctionTypeInput here
      -- would print "has a function type", which is simply false, and is why
      -- R-X4 got its own constructor.
      fmap length (exportFnErrors appFormSrc) `shouldBe` Right 0

    it "names the rule, the export, and the way out" $
      case renderedErrors appFormSrc of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right out -> do
          out `shouldSatisfy` Text.isInfixOf "`is authorised`"
          out `shouldSatisfy` Text.isInfixOf "`may act`"
          out `shouldSatisfy` Text.isInfixOf "1 input"
          out `shouldSatisfy` Text.isInfixOf "remove the @export"

    it "counts a two-input assumed rule as two" $ do
      let src = Text.unlines
            [ "ASSUME Consequence IS A TYPE"
            , ""
            , "GIVEN `c` IS A Consequence"
            , "      `n` IS A NUMBER"
            , "ASSUME `severity exceeds` `c` `n` IS A BOOLEAN"
            , ""
            , "@export Whether it qualifies"
            , "GIVEN `c` IS A Consequence"
            , "GIVETH A BOOLEAN"
            , "DECIDE `qualifies` IF `severity exceeds` `c` 10"
            ]
      exportArityErrors src `shouldBe` Right [2]

    -- Found by an adversarial refuter on the first build of this gate: the
    -- result type has two spellings and the gate read only one.
    it "reads the result type off a GIVETH, not only off IS A" $ do
      -- No term GIVEN, so the app form has no arguments to backfill and the
      -- `IS A` slot is empty — the type lives in the GIVETH alone. This is the
      -- arrow form written the other way round, so it is refused as one; what
      -- must not happen is that it is refused by neither, which is what the
      -- first build of this gate did (it checked clean, then died on every
      -- request with "multiple definitions for the identifier f").
      let src = Text.unlines
            [ "GIVETH A FUNCTION FROM NUMBER TO NUMBER"
            , "ASSUME `f`"
            , ""
            , "@export Apply the assumed rule"
            , "GIVEN `n` IS A NUMBER"
            , "GIVETH A NUMBER"
            , "DECIDE `go` `n` IS `f` `n`"
            ]
      fmap length (exportFnErrors src) `shouldBe` Right 1
      exportArityErrors src `shouldBe` Right []

    it "adds a GIVETH arrow spine to the app-form arity" $ do
      -- One input on the head, one in the GIVETH: the count must be 2, or the
      -- message understates what a request would have to send.
      let src = Text.unlines
            [ "GIVEN `x` IS A NUMBER"
            , "GIVETH A FUNCTION FROM NUMBER TO NUMBER"
            , "ASSUME `f` `x`"
            , ""
            , "@export Apply the assumed rule"
            , "GIVEN `n` IS A NUMBER"
            , "GIVETH A NUMBER"
            , "DECIDE `go` `n` IS `f` `n` 1"
            ]
      exportArityErrors src `shouldBe` Right [2]

    it "still fires when only a helper reads the assumed rule" $ do
      -- The read-set is transitive: moving the ASSUME behind a helper does not
      -- make it supplyable, so it must not make it acceptable either.
      let src = Text.unlines
            [ "ASSUME Person IS A TYPE"
            , ""
            , "GIVEN `p` IS A Person"
            , "ASSUME `is authorised` `p` IS A BOOLEAN"
            , ""
            , "GIVEN `p` IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `helper` IF `is authorised` `p`"
            , ""
            , "@export Whether the person may act"
            , "GIVEN `who` IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `may act` IF `helper` `who`"
            ]
      exportArityErrors src `shouldBe` Right [1]

    it "ignores an app-form ASSUME that no export reads" $ do
      let src = Text.unlines
            [ "ASSUME Person IS A TYPE"
            , ""
            , "GIVEN `p` IS A Person"
            , "ASSUME `is authorised` `p` IS A BOOLEAN"
            , ""
            , "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF `age` >= 18"
            ]
      exportArityErrors src `shouldBe` Right []

    it "leaves an app-form ASSUME on a non-@export decision alone" $ do
      let src = Text.unlines
            [ "ASSUME Person IS A TYPE"
            , ""
            , "GIVEN `p` IS A Person"
            , "ASSUME `is authorised` `p` IS A BOOLEAN"
            , ""
            , "GIVEN `who` IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `internal only` IF `is authorised` `who`"
            ]
      exportArityErrors src `shouldBe` Right []

    it "keeps letting a nullary assumed value through" $ do
      -- The whole point of keying on arity: a nullary ASSUME is a VALUE, and a
      -- request can supply it. Nothing about R-X4 may change that.
      let src = Text.unlines
            [ "ASSUME `person has capacity` IS A BOOLEAN"
            , ""
            , "@export May purchase"
            , "GIVETH A BOOLEAN"
            , "DECIDE `may purchase` IF `person has capacity`"
            ]
      exportArityErrors src `shouldBe` Right []

    it "adds the arrow spine to the app-form arity in a mixed spelling" $ do
      -- `f x` with an arrow RESULT is a rule of two inputs, one written on the
      -- head and one in the type, and the count must add them — otherwise the
      -- message understates what a request would have to send.
      --
      -- The call site below is separately ill-typed, and deliberately left so:
      -- there is no surface syntax that applies an app-form ASSUME and then its
      -- arrow result in one step (`f x y` reports "expects 1 input, given 2";
      -- `f x OF y` and `(f OF x) OF y` do not parse). That is a fact about the
      -- grammar, not about this gate — which reads the DECLARATION, not the
      -- call — so the assertion is on the arity errors alone.
      let src = Text.unlines
            [ "ASSUME Person IS A TYPE"
            , ""
            , "GIVEN `p` IS A Person"
            , "ASSUME `rated` `p` IS A FUNCTION FROM NUMBER TO BOOLEAN"
            , ""
            , "@export Whether the person is rated"
            , "GIVEN `who` IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `is rated` IF `rated` `who` 3"
            ]
      exportArityErrors src `shouldBe` Right [2]

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
