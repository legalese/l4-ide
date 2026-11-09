{-# LANGUAGE OverloadedRecordDot, PatternSynonyms #-}
-- | The out-of-scope quick fix ('LSP.L4.Actions.outOfScopeFix') declares
-- the missing name the way IMPLICIT-PROPS-DESIGN.md §11.1 rules, never as an
-- @ASSUME@, the spelling it deprecates (§11.14 Finding 2 is the ruling that
-- the repointing lands with the deprecation warning): a term as a @GIVEN@,
-- a type as a bodiless @DECLARE@ (§11.1.1).
--
-- Each case type-checks a small module through the real oneshot pipeline,
-- takes the @OutOfScopeError@ the checker produced for it, and asserts the
-- edit the fix computes: where the line goes, its indentation, and its text.
-- For a term, the four shapes are the four the fix distinguishes: a section
-- with a @GIVEN@ to extend, a section heading with none, and — under no
-- heading at all — a rule with a @GIVEN@ to extend and a rule with none (with
-- an annotation above it, which must stay above it). For a type, each case
-- also applies the edit and checks the result again, which must come back
-- with no error at all.
module OutOfScopeGivenFixSpec (spec) where

import Data.Maybe (listToMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath ((</>))

import Language.LSP.Protocol.Types (Position (..), Range (..), TextEdit (..), UInt, normalizedFilePathToUri)

import L4.Annotation (Anno_ (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Lexer (PosToken)
import L4.Names (HasName (..))
import L4.Syntax
  ( Decide (..), Declare (..), Extension (..), Module (..), Name, Resolved
  , Section (..), TopDecl (..), Type' (..), getDesc, rawName, rawNameToText
  )
import L4.TracePolicy (lspDefaultPolicy)
import L4.TypeCheck (CheckError (..), CheckErrorWithContext (..))
import qualified LSP.Core.Shake as Shake
import LSP.L4.Actions (OutOfScopeFix (..), outOfScopeFix)
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (GetLexTokens (..), TypeCheckResult (..), pattern TypeCheck)

import Test.Hspec

-- | Type-check a module written to a scratch file and hand the result, with
-- the module's tokens, to @k@.
checked :: String -> T.Text -> ([PosToken] -> TypeCheckResult -> Maybe a) -> IO (Maybe a)
checked stem source k = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-out-of-scope-given-fix-spec"
      path = dir </> (stem <> ".l4")
  createDirectoryIfMissing True dir
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mResult) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _    <- Shake.addVirtualFileFromFS nfp
    mTc  <- Shake.use TypeCheck uri
    mLex <- Shake.use GetLexTokens uri
    pure do
      tc          <- mTc
      (tokens, _) <- mLex
      k tokens tc
  pure mResult

-- | The fix the checker's first out-of-scope name earns.
fixFor :: String -> T.Text -> IO (Maybe OutOfScopeFix)
fixFor stem source =
  checked stem source \ tokens tc -> do
    (name, ty) <- firstOutOfScope tc
    outOfScopeFix tokens tc.module' name ty

-- | Apply the fix the checker's first out-of-scope name earns, check the
-- edited text again, and hand back the edited text with what the second
-- check found.
recheckAfterFix :: String -> T.Text -> IO (Maybe (T.Text, TypeCheckResult))
recheckAfterFix stem source = do
  mFix <- fixFor stem source
  case mFix of
    Nothing  -> pure Nothing
    Just fix -> do
      let edited = applyEdit fix.edit source
      fmap (edited,) <$> checked (stem <> "-fixed") edited (const Just)

-- | The first name the checker could not find a definition for. Its type is
-- whatever the use pinned it to; a use that leaves an inference variable
-- behind (the overloaded @>=@ does) earns no fix, so every case below reads
-- the name through a rule with a declared @NUMBER@ input.
firstOutOfScope :: TypeCheckResult -> Maybe (Name, Type' Resolved)
firstOutOfScope tc =
  listToMaybe
    [ (name, ty)
    | MkCheckErrorWithContext (OutOfScopeError name ty) _ <- tc.errors
    ]

-- | Every name the checker could not find a definition for.
outOfScopeNames :: TypeCheckResult -> [T.Text]
outOfScopeNames tc =
  [ rawNameToText (rawName name)
  | MkCheckErrorWithContext (OutOfScopeError name _) _ <- tc.errors
  ]

-- | A rule with a declared @NUMBER@ input, so that passing an undefined name
-- to it pins that name's type.
pins :: [T.Text]
pins =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `at least eighteen` n IF n >= 18"
  , ""
  ]

-- | An insertion at the start of the given 0-based line.
insertion :: UInt -> T.Text -> TextEdit
insertion line text = TextEdit (Range (Position line 0) (Position line 0)) text

-- | Apply an insertion (every edit this fix makes is one) to the text.
applyEdit :: TextEdit -> T.Text -> T.Text
applyEdit (TextEdit (Range (Position line col) _) new) source =
  let (above, rest) = splitAt (fromIntegral line) (T.splitOn "\n" source)
  in case rest of
       []       -> T.intercalate "\n" above <> new
       (l : ls) ->
         let (l1, l2) = T.splitAt (fromIntegral col) l
         in T.intercalate "\n" (above <> [l1 <> new <> l2] <> ls)

-- | The @\@desc@ on each top-level declaration, keyed by the declaration's
-- name: where an annotation ended up after an edit.
topLevelDescs :: Module Resolved -> [(T.Text, Maybe T.Text)]
topLevelDescs (MkModule _ _ (MkSection _ _ _ _ decls)) =
  [ (rawNameToText (rawName (getName appForm)), getDesc <$> ann.extra.desc)
  | d <- decls
  , (appForm, ann) <- case d of
      Declare _ (MkDeclare ann _ appForm _) -> [(appForm, ann)]
      Decide  _ (MkDecide  ann _ appForm _) -> [(appForm, ann)]
      _                                     -> []
  ]

-- | A module with one declaration ahead of the one that uses the unknown
-- type, so that "directly above the use's declaration" and "at the top of
-- the file" are different lines.
colour :: [T.Text]
colour =
  [ "DECLARE Colour IS ONE OF red, green"
  , ""
  ]

-- | What the type role's fix must leave behind: the edited text checks with
-- no error at all, so in particular the name is no longer out of scope.
shouldRecheckClean :: Maybe (T.Text, TypeCheckResult) -> T.Text -> Expectation
shouldRecheckClean mRe name =
  case mRe of
    Nothing          -> expectationFailure "no fix was offered"
    Just (edited, tc) -> do
      outOfScopeNames tc `shouldNotContain` [name]
      (edited, length tc.errors) `shouldBe` (edited, 0)

spec :: Spec
spec = do
  describe "out-of-scope quick fix declares a GIVEN, never an ASSUME" $ do
    it "appends to the section's existing GIVEN, aligned with its first parameter" $ do
      mFix <- fixFor "section-with-given" $ T.unlines $
        [ "§ `Adults`"
        , "    GIVEN income IS A NUMBER"
        , ""
        ] <> pins <>
        [ "DECIDE `is adult` IF `at least eighteen` age"
        ]
      fmap (.title) mFix `shouldBe` Just "Add `age` to the GIVEN of § `Adults`"
      fmap (.edit) mFix `shouldBe` Just (insertion 2 "          age IS A NUMBER\n")

    it "opens a GIVEN under a heading that has none, four columns past the §" $ do
      mFix <- fixFor "section-without-given" $ T.unlines $
        [ "§ `Adults`"
        , ""
        ] <> pins <>
        [ "DECIDE `is adult` IF `at least eighteen` age"
        ]
      fmap (.title) mFix `shouldBe` Just "Start a GIVEN for `age` under § `Adults`"
      fmap (.edit) mFix `shouldBe` Just (insertion 1 "    GIVEN age IS A NUMBER\n")

    it "appends to the rule's own GIVEN when no heading encloses the use" $ do
      mFix <- fixFor "rule-with-given" $ T.unlines $
        pins <>
        [ "GIVEN income IS A NUMBER"
        , "DECIDE `is well off` IF income > 0 AND `at least eighteen` age"
        ]
      fmap (.title) mFix `shouldBe` Just "Add `age` to the GIVEN of the rule `is well off`"
      fmap (.edit) mFix `shouldBe` Just (insertion 5 "      age IS A NUMBER\n")

    it "opens a rule GIVEN above the declaration, keeping its annotation above it" $ do
      mFix <- fixFor "rule-without-given" $ T.unlines $
        pins <>
        [ "@export"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is adult` IF `at least eighteen` age"
        ]
      fmap (.title) mFix `shouldBe` Just "Start a GIVEN for `age` on the rule `is adult`"
      fmap (.edit) mFix `shouldBe` Just (insertion 5 "GIVEN age IS A NUMBER\n")

    it "never spells the deprecated keyword" $ do
      mFix <- fixFor "no-assume" $ T.unlines $
        [ "§ `Adults`"
        , ""
        ] <> pins <>
        [ "DECIDE `is adult` IF `at least eighteen` age"
        ]
      fmap ((.edit) >>> (._newText) >>> T.isInfixOf "ASSUME") mFix `shouldBe` Just False

  describe "out-of-scope quick fix declares an unknown TYPE with a bodiless DECLARE" $ do
    it "declares a type a rule's GIVEN uses, directly above the rule" $ do
      let source = T.unlines $
            colour <>
            [ "GIVEN w IS A Widget"
            , "GIVETH A BOOLEAN"
            , "DECIDE `is shiny` w IS TRUE"
            ]
      mFix <- fixFor "type-in-rule-given" source
      fmap (.title) mFix `shouldBe` Just "Declare `Widget` as a type"
      fmap (.edit) mFix `shouldBe` Just (insertion 2 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-in-rule-given" source
      recheck `shouldRecheckClean` "Widget"

    it "declares a type a rule's GIVETH uses" $ do
      let source = T.unlines $
            colour <>
            [ "GIVEN c IS A Colour"
            , "GIVETH A Widget"
            , "DECIDE `the widget for` c IS `the widget for` c"
            ]
      mFix <- fixFor "type-in-giveth" source
      fmap (.title) mFix `shouldBe` Just "Declare `Widget` as a type"
      fmap (.edit) mFix `shouldBe` Just (insertion 2 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-in-giveth" source
      recheck `shouldRecheckClean` "Widget"

    it "declares a type a DECLARE's field uses, where no rule encloses the use" $ do
      let source = T.unlines $
            colour <>
            [ "DECLARE Order"
            , "  HAS item   IS A Widget"
            , "      colour IS A Colour"
            ]
      mFix <- fixFor "type-in-declare-field" source
      fmap (.title) mFix `shouldBe` Just "Declare `Widget` as a type"
      fmap (.edit) mFix `shouldBe` Just (insertion 2 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-in-declare-field" source
      recheck `shouldRecheckClean` "Widget"

    it "declares a type used under a § heading inside that section, never as a section GIVEN" $ do
      let source = T.unlines $
            [ "§ `Shop`"
            , ""
            ] <> colour <>
            [ "GIVEN w IS A Widget"
            , "GIVETH A BOOLEAN"
            , "DECIDE `is shiny` w IS TRUE"
            ]
      mFix <- fixFor "type-under-heading" source
      fmap (.title) mFix `shouldBe` Just "Declare `Widget` as a type"
      fmap (.edit) mFix `shouldBe` Just (insertion 4 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-under-heading" source
      recheck `shouldRecheckClean` "Widget"

    it "declares a type a section GIVEN uses above that section's heading" $ do
      let source = T.unlines $
            colour <>
            [ "§ `Shop`"
            , "    GIVEN `the widget` IS A Widget"
            , ""
            , "DECIDE `the shop's widget` IS `the widget`"
            ]
      mFix <- fixFor "type-in-section-given" source
      fmap (.title) mFix `shouldBe` Just "Declare `Widget` as a type"
      fmap (.edit) mFix `shouldBe` Just (insertion 2 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-in-section-given" source
      recheck `shouldRecheckClean` "Widget"

    it "goes above the annotations of the declaration, which stay attached to it" $ do
      let source = T.unlines $
            colour <>
            [ "@desc Is the widget shiny?"
            , "GIVEN w IS A Widget"
            , "GIVETH A BOOLEAN"
            , "DECIDE `is shiny` w IS TRUE"
            ]
      mFix <- fixFor "type-under-annotation" source
      fmap (.edit) mFix `shouldBe` Just (insertion 2 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-under-annotation" source
      recheck `shouldRecheckClean` "Widget"
      fmap (topLevelDescs . (.module') . snd) recheck `shouldBe`
        Just [("Colour", Nothing), ("Widget", Nothing), ("is shiny", Just "Is the widget shiny?")]

    it "takes the comment lines directly over the declaration along, and leaves a comment with a blank line under it" $ do
      let source = T.unlines $
            colour <>
            [ "-- Rules about widgets."
            , ""
            , "-- Whether a widget is shiny."
            , "@desc Is the widget shiny?"
            , ""
            , "-- One input, a widget."
            , "GIVEN w IS A Widget"
            , "GIVETH A BOOLEAN"
            , "DECIDE `is shiny` w IS TRUE"
            ]
      mFix <- fixFor "type-under-comment" source
      fmap (.edit) mFix `shouldBe` Just (insertion 4 "DECLARE Widget\n\n")
      recheck <- recheckAfterFix "type-under-comment" source
      recheck `shouldRecheckClean` "Widget"
      fmap (topLevelDescs . (.module') . snd) recheck `shouldBe`
        Just [("Colour", Nothing), ("Widget", Nothing), ("is shiny", Just "Is the widget shiny?")]

    it "gives a type applied to arguments one parameter per argument, named apart from the module's names" $ do
      let source = T.unlines
            [ "GIVEN a IS A Box OF NUMBER, STRING"
            , "GIVETH A BOOLEAN"
            , "DECIDE `is full` a IS TRUE"
            ]
      mFix <- fixFor "type-applied" source
      fmap (.title) mFix `shouldBe` Just "Declare `Box` as a type"
      fmap (.edit) mFix `shouldBe` Just (insertion 0 "DECLARE Box b c\n\n")
      recheck <- recheckAfterFix "type-applied" source
      recheck `shouldRecheckClean` "Box"

    it "never spells the deprecated keyword, nor makes the type a type variable" $ do
      mFix <- fixFor "type-no-assume" $ T.unlines $
        [ "§ `Shop`"
        , ""
        , "GIVEN w IS A Widget"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is shiny` w IS TRUE"
        ]
      let newText = (.edit) >>> (._newText)
      fmap (newText >>> T.isInfixOf "ASSUME") mFix `shouldBe` Just False
      fmap (newText >>> T.isInfixOf "IS A TYPE") mFix `shouldBe` Just False
  where
    f >>> g = g . f
