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

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.TypeCheck (prettyCheckErrorWithContext)
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..))

-- | Typecheck a snippet and hand back its diagnostics.
diagnostics :: Text -> IO [CheckErrorWithContext]
diagnostics source =
  case checkWithImports emptyVFS source of
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

-- | Two genuinely different types that happen to share a base name, used
-- unambiguously (section proximity picks @Alpha@'s for the signature and
-- @Beta@'s for the body). The mismatch is real; only its rendering was broken.
sameNameDistinctTypes :: Text
sameNameDistinctTypes =
  Text.unlines
    [ "§ Alpha"
    , "DECLARE Verdict IS ONE OF yes"
    , ""
    , "§ Beta"
    , "DECLARE Verdict IS ONE OF no"
    , ""
    , "§ Alpha"
    , "GIVETH A Verdict"
    , "t MEANS no"
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

    it "never empties the diagnostic list" $ do
      -- Filtering is guarded on a resolution failure being present, and
      -- resolution failures are themselves never dropped, so a file that fails
      -- to check still fails to check.
      ks <- kinds <$> diagnostics dupDeclare
      ks `shouldNotBe` []

  describe "same-named types are distinguishable in a mismatch (#920 part 2)" $ do
    it "still reports the mismatch" $ do
      ks <- kinds <$> diagnostics sameNameDistinctTypes
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "qualifies both sides with their definition sites" $ do
      -- Before the fix this message read "namely / Verdict / but is here of
      -- type / Verdict" — two identical lines and no way to tell them apart.
      txt <- rendered sameNameDistinctTypes
      let qualified =
            [ Text.strip l
            | l <- Text.lines txt
            , "Verdict (Verdict defined at " `Text.isInfixOf` l
            ]
      case qualified of
        [expected, given] -> expected `shouldNotBe` given
        _ ->
          expectationFailure $
            "expected exactly two definition-qualified renderings, got: "
              ++ show qualified

    it "leaves an ordinary mismatch's rendering alone" $ do
      -- Disambiguation only kicks in when the two renderings collide; NUMBER
      -- vs BOOLEAN must not grow noise.
      txt <- rendered (Text.unlines ["GIVETH A NUMBER", "f MEANS TRUE"])
      txt `shouldSatisfy` Text.isInfixOf "NUMBER"
      txt `shouldSatisfy` Text.isInfixOf "BOOLEAN"
      txt `shouldNotSatisfy` Text.isInfixOf "defined at"
