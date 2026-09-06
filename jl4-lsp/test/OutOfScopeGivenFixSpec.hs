{-# LANGUAGE OverloadedRecordDot, PatternSynonyms #-}
-- | The out-of-scope quick fix ('LSP.L4.Actions.outOfScopeGivenFix') declares
-- the missing name as a @GIVEN@ rather than as an @ASSUME@, the spelling
-- IMPLICIT-PROPS-DESIGN.md §11.1 deprecates (§11.14 Finding 2 is the ruling
-- that the repointing lands with the deprecation warning).
--
-- Each case type-checks a small module through the real oneshot pipeline,
-- takes the @OutOfScopeError@ the checker produced for it, and asserts the
-- edit the fix computes: where the line goes, its indentation, and its text.
-- The four shapes are the four the fix distinguishes: a section with a
-- @GIVEN@ to extend, a section heading with none, and — under no heading at
-- all — a rule with a @GIVEN@ to extend and a rule with none (with an
-- annotation above it, which must stay above it).
module OutOfScopeGivenFixSpec (spec) where

import Data.Maybe (listToMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath ((</>))

import Language.LSP.Protocol.Types (Position (..), Range (..), TextEdit (..), UInt, normalizedFilePathToUri)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Syntax (Type' (..), Name, Resolved)
import L4.TracePolicy (lspDefaultPolicy)
import L4.TypeCheck (CheckError (..), CheckErrorWithContext (..))
import qualified LSP.Core.Shake as Shake
import LSP.L4.Actions (GivenFix (..), outOfScopeGivenFix)
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)

import Test.Hspec

-- | Type-check a module written to a scratch file and hand back the fix the
-- checker's first out-of-scope name earns, with the module it was computed on.
fixFor :: String -> T.Text -> IO (Maybe GivenFix)
fixFor stem source = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-out-of-scope-given-fix-spec"
      path = dir </> (stem <> ".l4")
  createDirectoryIfMissing True dir
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mFix) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure do
      tc <- mTc
      (name, ty) <- firstOutOfScope tc
      outOfScopeGivenFix tc.module' name ty
  pure mFix

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

spec :: Spec
spec =
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
      fmap (.title) mFix `shouldBe` Just "Declare `age` as a GIVEN of § `Adults`"
      fmap (.edit) mFix `shouldBe` Just (insertion 1 "    GIVEN age IS A NUMBER\n")

    it "appends to the rule's own GIVEN when no heading encloses the use" $ do
      mFix <- fixFor "rule-with-given" $ T.unlines $
        pins <>
        [ "GIVEN income IS A NUMBER"
        , "DECIDE `is well off` IF income > 0 AND `at least eighteen` age"
        ]
      fmap (.title) mFix `shouldBe` Just "Add `age` to the GIVEN of `is well off`"
      fmap (.edit) mFix `shouldBe` Just (insertion 5 "      age IS A NUMBER\n")

    it "opens a rule GIVEN above the declaration, keeping its annotation above it" $ do
      mFix <- fixFor "rule-without-given" $ T.unlines $
        pins <>
        [ "@export"
        , "GIVETH A BOOLEAN"
        , "DECIDE `is adult` IF `at least eighteen` age"
        ]
      fmap (.title) mFix `shouldBe` Just "Declare `age` as a GIVEN of `is adult`"
      fmap (.edit) mFix `shouldBe` Just (insertion 5 "GIVEN age IS A NUMBER\n")

    it "never spells the deprecated keyword" $ do
      mFix <- fixFor "no-assume" $ T.unlines $
        [ "§ `Adults`"
        , ""
        ] <> pins <>
        [ "DECIDE `is adult` IF `at least eighteen` age"
        ]
      fmap ((.edit) >>> (._newText) >>> T.isInfixOf "ASSUME") mFix `shouldBe` Just False
  where
    f >>> g = g . f
