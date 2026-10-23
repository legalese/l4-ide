{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Regression guard for issue #920: a name-resolution failure used to cascade
-- into two further diagnostics, both of them worse than useless.
--
-- 1. 'MissingEntityInfo' — rendered as "This is an error in this system and
--    should be reported as a bug" — fired for every 'OutOfScope' sentinel,
--    because those sentinels carry a deliberately unregistered 'Unique'. The
--    message accused the compiler of a bug when the user had merely written an
--    ambiguous or undefined name.
--
-- 2. A 'TypeMismatch' against the poisoned signature type, which (since the
--    printer never shows uniques) came out as the vacuous
--    "must match ... namely Verdict but is here of type Verdict".
--
-- The specs below pin down BOTH halves of the fix, and — just as importantly —
-- the control cases proving that genuine type errors are still reported.
module ResolutionCascadeSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS, vfsFromList)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.TypeCheck (prettyCheckErrorWithContext)
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..))

-- | Typecheck a snippet and hand back its diagnostics.
diagnostics :: Text -> IO [CheckErrorWithContext]
diagnostics source =
  case checkWithImports emptyVFS source of
    Left errs -> fail $ "Fatal: " ++ show errs
    Right r -> pure r.tcdErrors

-- | Typecheck a snippet that imports @lib@, and hand back the snippet's own
-- diagnostics: the imported module's are not among them.
diagnosticsWithLib :: Text -> Text -> IO [CheckErrorWithContext]
diagnosticsWithLib lib source =
  case checkWithImports (vfsFromList [("lib", lib)]) source of
    Left errs -> fail $ "Fatal: " ++ show errs
    Right r -> pure r.tcdErrors

-- | All diagnostics of a snippet, rendered exactly as the user would see them,
-- joined into one blob so we can assert on presence/absence of phrases.
rendered :: Text -> IO Text
rendered source =
  Text.unlines . concatMap prettyCheckErrorWithContext <$> diagnostics source

kinds :: [CheckErrorWithContext] -> [CheckError]
kinds = map (.kind)

isAmbiguousType :: CheckError -> Bool
isAmbiguousType AmbiguousTypeError {} = True
isAmbiguousType _ = False

isMissingEntityInfo :: CheckError -> Bool
isMissingEntityInfo MissingEntityInfo {} = True
isMissingEntityInfo _ = False

isTypeMismatch :: CheckError -> Bool
isTypeMismatch TypeMismatch {} = True
isTypeMismatch _ = False

isOutOfScopeError :: CheckError -> Bool
isOutOfScopeError OutOfScopeError {} = True
isOutOfScopeError _ = False

-- | The issue's repro: two @DECLARE Verdict@s, then a DECIDE whose GIVETH
-- names the (now ambiguous) type.
dupDeclare :: Text
dupDeclare =
  Text.unlines
    [ "DECLARE Verdict IS ONE OF yes, no"
    , ""
    , "DECLARE Verdict IS ONE OF maybe, perhaps"
    , ""
    , "GIVEN x IS A BOOLEAN"
    , "GIVETH A Verdict"
    , "`decide it` MEANS IF x THEN yes ELSE no"
    ]

-- | Two different types spelled `Verdict`, told apart only by their
-- constructors: a genuine mismatch whose two sides print identically.
sameNameTypes :: Text
sameNameTypes =
  Text.unlines
    [ "DECLARE Verdict IS ONE OF yes, no"
    , ""
    , "DECLARE Verdict IS ONE OF maybe, perhaps"
    , ""
    , "GIVEN x IS A BOOLEAN"
    , "`pick` MEANS IF x THEN yes ELSE maybe"
    ]

spec :: Spec
spec = do
  describe "name-resolution failures do not cascade (#920)" $ do
    it "an ambiguous type name is reported exactly once, as an ambiguity" $ do
      ks <- kinds <$> diagnostics dupDeclare
      filter isAmbiguousType ks `shouldSatisfy` ((== 1) . length)

    it "does not blame the compiler for the user's ambiguous name" $ do
      ks <- kinds <$> diagnostics dupDeclare
      filter isMissingEntityInfo ks `shouldBe` []

    it "does not emit the 'report this as a bug' text" $ do
      txt <- rendered dupDeclare
      txt `shouldNotSatisfy` Text.isInfixOf "should be reported as a bug"

    it "does not emit a vacuous mismatch against the poisoned signature" $ do
      ks <- kinds <$> diagnostics dupDeclare
      filter isTypeMismatch ks `shouldBe` []

    it "still tells the user what actually went wrong" $ do
      txt <- rendered dupDeclare
      txt `shouldSatisfy` Text.isInfixOf "multiple definitions for the identifier"

    it "an undefined type name likewise cascades no further" $ do
      let src =
            Text.unlines
              [ "GIVETH A Nonexistent"
              , "f MEANS 42"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 1) . length)
      filter isMissingEntityInfo ks `shouldBe` []
      filter isTypeMismatch ks `shouldBe` []

  describe "suppression is limited to the cascade" $ do
    it "control: a plain type error is still reported" $ do
      let src = Text.unlines ["GIVETH A NUMBER", "f MEANS TRUE"]
      ks <- kinds <$> diagnostics src
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "a genuine type error survives alongside an unrelated resolution failure" $ do
      -- This is the decisive case: the presence of an OutOfScopeError turns the
      -- cascade filter ON, and the NUMBER/BOOLEAN mismatch — whose types
      -- mention no sentinel — must still come through untouched.
      let src =
            Text.unlines
              [ "GIVETH A NUMBER"
              , "bad MEANS TRUE"
              , ""
              , "GIVETH A BOOLEAN"
              , "missing MEANS `no such thing`"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 1) . length)
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "a genuine type error survives alongside an ambiguity" $ do
      let src = dupDeclare <> Text.unlines ["", "GIVETH A NUMBER", "g MEANS TRUE"]
      ks <- kinds <$> diagnostics src
      filter isAmbiguousType ks `shouldSatisfy` ((== 1) . length)
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "keeps a mismatch that a poisoned sub-term does not account for" $ do
      -- The signature says NUMBER, the body is a LIST. `Typo` is undeclared, so
      -- the LIST's ELEMENT type is a sentinel — but the NUMBER-vs-LIST
      -- discrepancy is between two heads we did resolve, and it survives
      -- verbatim once `Typo` is declared. Suppressing on "mentions a sentinel
      -- anywhere" would have deleted it.
      let src =
            Text.unlines
              [ "GIVEN xs IS A LIST OF Typo"
              , "GIVETH A NUMBER"
              , "h MEANS xs"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 1) . length)
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "keeps a mismatch under a poisoned function argument" $ do
      -- Both sides are FUNCTION FROM <sentinel> TO ..., so they agree exactly
      -- where the resolution failure is. They differ in the RETURN type, which
      -- is resolved on both sides: a real error, and reported.
      let src =
            Text.unlines
              [ "GIVEN p IS A FUNCTION FROM Typo TO BOOLEAN"
              , "GIVETH A NUMBER"
              , "useIt MEANS 1"
              , ""
              , "GIVEN q IS A FUNCTION FROM Typo TO NUMBER"
              , "GIVETH A NUMBER"
              , "callIt MEANS useIt OF q"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((>= 1) . length)
      filter isTypeMismatch ks `shouldSatisfy` ((>= 1) . length)

    it "keeps a mismatch in a declaration the typo is not even in" $ do
      -- The typo is in `f`'s GIVEN; the mismatch is `g` returning a function
      -- where it declared a BOOLEAN. Different declaration, different defect.
      let src =
            Text.unlines
              [ "GIVEN x IS A Typo"
              , "GIVETH A NUMBER"
              , "f MEANS 1"
              , ""
              , "GIVETH A BOOLEAN"
              , "g MEANS f"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((>= 1) . length)
      filter isTypeMismatch ks `shouldSatisfy` ((>= 1) . length)

    it "still drops the mismatch a sentinel does account for" $ do
      -- The control for the three above: here the two sides agree modulo the
      -- sentinel (LIST OF <sentinel> against LIST OF <sentinel>), so there is
      -- nothing to say that the OutOfScopeError has not said already.
      let src =
            Text.unlines
              [ "GIVEN xs IS A LIST OF Typo"
              , "GIVETH A LIST OF Typo"
              , "h MEANS xs"
              ]
      ks <- kinds <$> diagnostics src
      filter isTypeMismatch ks `shouldBe` []

    it "keeps an importer's mismatches against a name that failed to resolve in its import" $ do
      -- The failure is in @lib@, so the importer's own list holds no failure
      -- for @Money@: the sentinels in the importer's types were made by the
      -- other module, and the importer has not reported them. It keeps what it
      -- says about the poisoned type (`Money`), alongside its own genuine
      -- BOOLEAN-versus-NUMBER error. A filter that dropped every mismatch that
      -- mentions @Money@ would leave only the genuine one.
      let lib =
            Text.unlines
              [ "GIVEN amount IS A Money"
              , "GIVETH A NUMBER"
              , "`total due` MEANS amount"
              , ""
              , "DECLARE Wrapper HAS inner IS A Money"
              ]
          src =
            Text.unlines
              [ "IMPORT lib"
              , ""
              , "GIVETH A BOOLEAN"
              , "x MEANS `total due` 5"
              , ""
              , "GIVEN w IS A Wrapper"
              , "GIVETH A NUMBER"
              , "y MEANS w's inner"
              ]
      errs <- diagnosticsWithLib lib src
      let ks = kinds errs
          mismatches = [ Text.unlines (prettyCheckErrorWithContext e) | e <- errs, isTypeMismatch e.kind ]
      filter isOutOfScopeError ks `shouldBe` []
      length mismatches `shouldBe` 3
      length (filter (Text.isInfixOf "  Money") mismatches) `shouldBe` 2

    it "never empties the diagnostic list" $ do
      -- Filtering is guarded on a resolution failure being present, and
      -- resolution failures are themselves never dropped, so a file that fails
      -- to check still fails to check.
      ks <- kinds <$> diagnostics dupDeclare
      ks `shouldNotBe` []

  describe "the filter does not depend on errors that have nothing to do with the mismatch" $ do
    -- @lib@ uses a type nobody declared, so the type of `total due` is poisoned
    -- in every module that imports it. Whether an importer reports a mismatch
    -- against that type must not depend on whether the importer happens to
    -- have an unknown name of its own somewhere else.
    let lib =
          Text.unlines
            [ "GIVEN amount IS A Money"
            , "GIVETH A NUMBER"
            , "`total due` MEANS amount"
            ]
        callIt =
          Text.unlines
            [ "IMPORT lib"
            , ""
            , "GIVETH A NUMBER"
            , "x MEANS `total due` 5"
            ]
        unrelatedName =
          Text.unlines
            [ ""
            , "GIVETH A NUMBER"
            , "y MEANS `no such name`"
            ]
        mismatchTexts errs =
          [ Text.unlines (prettyCheckErrorWithContext e) | e <- errs, isTypeMismatch e.kind ]

    it "an importer reports its mismatch against the imported poisoned type" $ do
      errs <- diagnosticsWithLib lib callIt
      length (mismatchTexts errs) `shouldBe` 1
      mismatchTexts errs `shouldSatisfy` all (Text.isInfixOf "  Money")

    it "reports exactly the same mismatch when the importer also has an unknown name of its own" $ do
      alone <- diagnosticsWithLib lib callIt
      withOther <- diagnosticsWithLib lib (callIt <> unrelatedName)
      filter isOutOfScopeError (kinds withOther) `shouldSatisfy` ((== 1) . length)
      mismatchTexts withOther `shouldBe` mismatchTexts alone

    it "drops the cascade of the importer's own unknown type and keeps the imported one's" $ do
      -- Two poisoned types in one module, told apart by which module reported
      -- them: `Typo` is the importer's own failure and what it leads to is
      -- dropped, `Money` was reported by @lib@ and the importer's mismatch
      -- about it stays.
      let src =
            callIt
              <> Text.unlines
                [ ""
                , "GIVEN t IS A Typo"
                , "GIVETH A Typo"
                , "h MEANS t"
                ]
      errs <- diagnosticsWithLib lib src
      filter isOutOfScopeError (kinds errs) `shouldSatisfy` ((== 2) . length)
      length (mismatchTexts errs) `shouldBe` 1
      mismatchTexts errs `shouldSatisfy` all (Text.isInfixOf "  Money")

    it "within one module, drops the cascade of its own unknown type with or without an unrelated unknown name" $ do
      -- The control: the unknown type is this module's own failure, so the
      -- mismatch against it is dropped, and an unrelated unknown name next to
      -- it changes nothing.
      let own = lib <> Text.unlines ["", "GIVETH A NUMBER", "x MEANS `total due` 5"]
      a <- diagnostics own
      b <- diagnostics (own <> unrelatedName)
      filter isTypeMismatch (kinds a) `shouldBe` []
      filter isTypeMismatch (kinds b) `shouldBe` []

  describe "same-named types are distinguishable in a mismatch (#920 part 2)" $ do
    it "leaves an ordinary mismatch's rendering alone" $ do
      -- Disambiguation only kicks in when the two renderings collide; NUMBER
      -- vs BOOLEAN must not grow noise.
      txt <- rendered (Text.unlines ["GIVETH A NUMBER", "f MEANS TRUE"])
      txt `shouldSatisfy` Text.isInfixOf "NUMBER"
      txt `shouldSatisfy` Text.isInfixOf "BOOLEAN"
      txt `shouldNotSatisfy` Text.isInfixOf "defined at"

    it "still reports a mismatch between two types that print the same" $ do
      -- Nothing here names `Verdict`, so nothing is ambiguous: the constructors
      -- `yes` and `maybe` each belong to a different one of the two types.
      ks <- kinds <$> diagnostics sameNameTypes
      filter isAmbiguousType ks `shouldBe` []
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "qualifies both sides with the place their type was declared" $ do
      txt <- rendered sameNameTypes
      Text.count "Verdict defined at" txt `shouldBe` 2
      txt `shouldSatisfy` Text.isInfixOf ":1:9-16"
      txt `shouldSatisfy` Text.isInfixOf ":3:9-16"
