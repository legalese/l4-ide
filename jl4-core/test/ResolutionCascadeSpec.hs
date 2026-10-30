{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Regression guard for issue #920: a name that could not be resolved used to
-- cascade into further diagnostics, all of them worse than useless.
--
-- 1. 'MissingEntityInfo' -- rendered as "This is an error in this system and
--    should be reported as a bug" -- fired for every sentinel that stands in
--    for an unresolved name, because those carry a 'Unique' that is
--    deliberately not registered. The message accused the compiler of a bug
--    when the user had merely written an ambiguous or undefined name.
--
-- 2. A 'TypeMismatch' against the sentinel's type, which (since the printer
--    never shows uniques) came out as the vacuous
--    "must match ... namely Verdict but is here of type Verdict".
--
-- The unifier now lets a type headed by such a sentinel match anything
-- (L4.TypeCheck.Unify, @unify'@), so the second kind never arises. The specs
-- pin that, and the cases where it must NOT apply: a genuine mismatch between
-- types that did resolve is still reported.
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

isAmbiguousTerm :: CheckError -> Bool
isAmbiguousTerm AmbiguousTermError {} = True
isAmbiguousTerm _ = False

isMissingEntityInfo :: CheckError -> Bool
isMissingEntityInfo MissingEntityInfo {} = True
isMissingEntityInfo _ = False

isTypeMismatch :: CheckError -> Bool
isTypeMismatch TypeMismatch {} = True
isTypeMismatch _ = False

isOutOfScopeError :: CheckError -> Bool
isOutOfScopeError OutOfScopeError {} = True
isOutOfScopeError _ = False

isKindError :: CheckError -> Bool
isKindError KindError {} = True
isKindError _ = False

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

  describe "a sentinel matches only where it stands" $ do
    it "control: a plain type error is still reported" $ do
      let src = Text.unlines ["GIVETH A NUMBER", "f MEANS TRUE"]
      ks <- kinds <$> diagnostics src
      filter isTypeMismatch ks `shouldSatisfy` ((== 1) . length)

    it "a genuine type error survives alongside an unrelated resolution failure" $ do
      -- The NUMBER/BOOLEAN mismatch mentions no sentinel, so the one
      -- unresolved name next to it must not hide it.
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
      -- the LIST's ELEMENT type is a sentinel -- but the NUMBER-vs-LIST
      -- discrepancy is between two heads that did resolve, and it survives
      -- verbatim once `Typo` is declared. Only a sentinel at the head of a
      -- type matches anything; one deeper down does not hide the outer types.
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

    it "reports nothing for a mismatch a sentinel accounts for" $ do
      -- The control for the three above: here the two sides agree modulo the
      -- sentinel (LIST OF <sentinel> against LIST OF <sentinel>), so
      -- there is nothing to say that the OutOfScopeError has not said already.
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

  describe "a name that did not resolve, used as the type of a value" $ do
    it "an operator applied to it reports the unresolved name only" $ do
      let src =
            Text.unlines
              [ "GIVEN y IS A Typo"
              , "GIVETH A BOOLEAN"
              , "`is small` y MEANS y < 3"
              , ""
              , "GIVEN x IS A Typo"
              , "GIVETH A NUMBER"
              , "`add one` x MEANS x + 1"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 2) . length)
      length ks `shouldBe` 2

    it "a call and a result of that type report the unresolved name only" $ do
      let src =
            Text.unlines
              [ "DECLARE Person HAS age IS A NUMBER"
              , ""
              , "GIVEN q IS A Person"
              , "GIVETH A Typo"
              , "make q MEANS q"
              , ""
              , "GIVETH A NUMBER"
              , "useMake MEANS make (Person 3)"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 1) . length)
      length ks `shouldBe` 1

    it "known limit: an overloaded function applied to it is also reported as ambiguous" $ do
      -- Which of the two `speak`s is meant cannot be told from a value whose
      -- type is not known, so both fit and the use is ambiguous. The unresolved
      -- name is reported as well; the ambiguity follows from it.
      let src =
            Text.unlines
              [ "DECLARE Cat HAS name IS A STRING"
              , "DECLARE Dog HAS name IS A STRING"
              , ""
              , "GIVEN c IS A Cat"
              , "GIVETH A STRING"
              , "speak c MEANS \"meow\""
              , ""
              , "GIVEN d IS A Dog"
              , "GIVETH A STRING"
              , "speak d MEANS \"woof\""
              , ""
              , "GIVEN x IS A Typo"
              , "GIVETH A STRING"
              , "`use it` x MEANS speak x"
              ]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 1) . length)
      length (filter isAmbiguousTerm ks) `shouldBe` 1
      length ks `shouldBe` 2

  describe "a type that failed to resolve in an import" $ do
    -- @lib@ uses a type nobody declared, so the type of `total due` is a
    -- sentinel in every module that imports it. The importer already fails
    -- on the import, which names @lib@'s error; it is not given a second
    -- mismatch for each use of the type. Its own genuine errors still come.
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
        mismatchTexts errs =
          [ Text.unlines (prettyCheckErrorWithContext e) | e <- errs, isTypeMismatch e.kind ]

    it "is not reported again as a mismatch in the importer" $ do
      errs <- diagnosticsWithLib lib src
      filter (Text.isInfixOf "Money") (mismatchTexts errs) `shouldBe` []

    it "leaves the importer's own genuine mismatch" $ do
      errs <- diagnosticsWithLib lib src
      length (mismatchTexts errs) `shouldBe` 1
      mismatchTexts errs `shouldSatisfy` all (Text.isInfixOf "BOOLEAN")

  describe "a synonym whose alias collides with an imported type" $ do
    -- @lib@ declares `Money`; the importer declares `Cash AKA Money` as a
    -- synonym of `Money`, so the name `Money` is ambiguous at every use. The
    -- ambiguity is what the user needs to hear, once for each use.
    let lib = Text.unlines ["DECLARE Money HAS amount IS A NUMBER"]
        src =
          Text.unlines
            [ "IMPORT lib"
            , ""
            , "DECLARE Cash AKA Money IS A Money"
            , ""
            , "GIVEN c IS A Cash"
            , "GIVETH A Money"
            , "f c MEANS c"
            ]

    it "is reported as the ambiguity only" $ do
      ks <- kinds <$> diagnosticsWithLib lib src
      length (filter isAmbiguousType ks) `shouldBe` 3
      length ks `shouldBe` 3

  describe "a type name that did not resolve has no arity to disagree with" $ do
    -- A name that failed to resolve has no kind of its own, so the arguments
    -- written after it cannot be counted against anything: "I expected 0
    -- arguments, but I found 2" would compare them with a number made up for
    -- the failure. The failure itself is reported, once, and that is all.
    let source ls = Text.unlines ls
        ambiguousUse = \ declaration use ->
          source (declaration <> ["", use, "GIVETH A NUMBER", "f x MEANS 1"])

    it "a type of your own named EVENT with two parameters is reported as the ambiguity only" $ do
      let src = ambiguousUse
            [ "DECLARE EVENT party action"
            , "  HAS who IS A party"
            , "      what IS AN action"
            ]
            "GIVEN x IS AN EVENT STRING NUMBER"
      ks <- kinds <$> diagnostics src
      filter isAmbiguousType ks `shouldSatisfy` ((== 1) . length)
      filter isKindError ks `shouldBe` []

    it "keeps both candidates in the ambiguity" $ do
      let src = ambiguousUse
            [ "DECLARE EVENT party action"
            , "  HAS who IS A party"
            , "      what IS AN action"
            ]
            "GIVEN x IS AN EVENT STRING NUMBER"
      txt <- rendered src
      txt `shouldSatisfy` Text.isInfixOf "multiple definitions for the identifier"
      txt `shouldSatisfy` Text.isInfixOf "EVENT (predefined) of arity 2"
      Text.count "of arity 2" txt `shouldBe` 2

    it "a type of your own named MAYBE is reported as the ambiguity only" $ do
      let src = ambiguousUse
            [ "DECLARE MAYBE a HAS content IS AN a" ]
            "GIVEN x IS A MAYBE NUMBER"
      ks <- kinds <$> diagnostics src
      filter isAmbiguousType ks `shouldSatisfy` ((== 1) . length)
      filter isKindError ks `shouldBe` []

    it "a parameterised type declared twice is reported as the ambiguity only" $ do
      let src = ambiguousUse
            [ "DECLARE Box a HAS content IS AN a"
            , ""
            , "DECLARE Box a HAS other IS AN a"
            ]
            "GIVEN x IS A Box NUMBER"
      ks <- kinds <$> diagnostics src
      filter isAmbiguousType ks `shouldSatisfy` ((== 1) . length)
      filter isKindError ks `shouldBe` []

    it "an undeclared type constructor given arguments is reported as undeclared only" $ do
      let src = source ["GIVEN p IS A Duo OF NUMBER, NUMBER", "GIVETH A NUMBER", "f p MEANS 1"]
      ks <- kinds <$> diagnostics src
      filter isOutOfScopeError ks `shouldSatisfy` ((== 1) . length)
      filter isKindError ks `shouldBe` []

    it "control: a built-in type given the wrong number of arguments is still reported" $ do
      let src = source ["GIVEN x IS A MAYBE OF NUMBER, STRING", "GIVETH A NUMBER", "f x MEANS 1"]
      ks <- kinds <$> diagnostics src
      filter isKindError ks `shouldSatisfy` ((== 1) . length)

    it "control: a type of your own named EVENT with no parameters is not ambiguous with the built-in one" $ do
      -- The number of parameters rules the built-in type out, so there is one
      -- candidate and nothing to report.
      let src = source
            [ "DECLARE EVENT HAS who IS A STRING"
            , ""
            , "GIVEN x IS AN EVENT STRING NUMBER"
            , "GIVETH A NUMBER"
            , "f x MEANS 1"
            ]
      ks <- kinds <$> diagnostics src
      filter isAmbiguousType ks `shouldBe` []
      filter isKindError ks `shouldBe` []

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
