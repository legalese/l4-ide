{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE PatternSynonyms #-}

-- | The smart-punctuation quick fixes in "LSP.L4.Actions"
-- (L4.SmartPunctuation / DUMBWAITER): the confusable-did-you-mean helper,
-- the whole-document straighten action, the per-diagnostic lexer fixes, and
-- the NBSP lint's fix. All four are pure edit computations — testable
-- without an IDE — except the did-you-mean helper's END-TO-END wiring,
-- which (in the style of "OutOfScopeGivenFixSpec") runs the real pipeline
-- so at least one case proves 'inScopeRawNamesAt' and 'rangeOf' agree with
-- what the checker actually produces.
module SmartPunctuationActionsSpec (spec) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Maybe (listToMaybe)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath ((</>))

import Language.LSP.Protocol.Types
  ( NormalizedUri
  , Position (..)
  , Range (..)
  , TextEdit (..)
  , Uri (..)
  , normalizedFilePathToUri
  , toNormalizedUri
  )

import L4.Annotation (rangeOf)
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Lexer (execLexer, straightenDocument)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax (Name, Resolved, Type' (..), rawName, rawNameToText)
import L4.TracePolicy (lspDefaultPolicy)
import L4.TypeCheck (CheckError (..), CheckErrorWithContext (..))
import qualified LSP.Core.Shake as Shake
import LSP.L4.Actions
  ( QuickFix (..)
  , confusableDidYouMean
  , confusableDidYouMeanFix
  , inScopeRawNamesAt
  , lexErrorQuickFixes
  , nbspQuickFix
  , straightenDocumentQuickFix
  )
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck, srcRangeToLspRange)

import Test.Hspec

specUri :: NormalizedUri
specUri = toNormalizedUri (Uri "file:///smart-punctuation-actions-spec")

spec :: Spec
spec = do
  describe "confusableDidYouMean (pure)" $ do
    it "matches an in-scope name that differs only by a curly apostrophe" $
      confusableDidYouMean ["don't panic", "something else"] "don\x2019t panic"
        `shouldBe` Just "don't panic"

    it "is direction-symmetric: the IN-SCOPE side may carry the curly character instead" $
      confusableDidYouMean ["don\x2019t panic", "something else"] "don't panic"
        `shouldBe` Just "don\x2019t panic"

    it "finds nothing when no in-scope name straightens to the same text" $
      confusableDidYouMean ["totally unrelated"] "don\x2019t panic"
        `shouldBe` Nothing

    it "finds nothing when the reference is already spelled exactly like an in-scope name" $
      -- (would not have been out of scope to begin with; not this helper's job)
      confusableDidYouMean ["don't panic"] "don't panic"
        `shouldBe` Nothing

  describe "confusableDidYouMeanFix (pure)" $ do
    let range = MkSrcRange (MkSrcPos 6 8) (MkSrcPos 6 21) 13 specUri

    it "offers the in-scope spelling, quoted, replacing the reference's own range" $
      confusableDidYouMeanFix range "don\x2019t panic" ["don't panic"] `shouldBe` Just MkQuickFix
        { title = "Replace with `don't panic`"
        , edits = [TextEdit (srcRangeToLspRange (Just range)) "`don't panic`"]
        }

    it "offers nothing when confusableDidYouMean itself finds nothing" $
      confusableDidYouMeanFix range "don\x2019t panic" ["unrelated"] `shouldBe` Nothing

  describe "straightenDocumentQuickFix (pure)" $ do
    it "offers nothing for an already-ASCII document" $
      straightenDocumentQuickFix specUri "GIVEN p IS A Person\n" `shouldBe` Nothing

    it "offers nothing when only ONE replacement would be made (that confusable has its own per-character fix already)" $
      straightenDocumentQuickFix specUri "DECIDE `x` IF p\x2019s age >= 18\n" `shouldBe` Nothing

    it "offers the whole-document edit once two or more replacements would be made, titled with the count" $ do
      let src = "DECIDE `is adult` IF p\x2019s age >= 18   \x2013 plain comment\n"
          (n, final) = straightenDocument specUri src
      n `shouldBe` 2
      straightenDocumentQuickFix specUri src `shouldBe` Just MkQuickFix
        { title = "Straighten all smart punctuation in this file (2 replacements)"
        , edits = [ TextEdit (Range (Position 0 0) (Position 1 0)) final ]
        }

  describe "lexErrorQuickFixes (pure, from a real confusable-character lexer error)" $ do
    it "offers a single replacement fix for an unpaired confusable (a genitive apostrophe)" $ do
      case execLexer specUri "DECIDE `x` IF p\x2019s age >= 18\n" of
        Right _ -> expectationFailure "expected this to fail lexing"
        Left (pErr :| _) -> do
          let fixes = lexErrorQuickFixes pErr
          map (.title) fixes `shouldBe` ["Replace with `'`"]

    it "offers the dash's alternative spelling alongside its default" $ do
      case execLexer specUri "18   \x2013 plain comment\n" of
        Right _ -> expectationFailure "expected this to fail lexing"
        Left (pErr :| _) -> do
          let fixes = lexErrorQuickFixes pErr
          map (.title) fixes `shouldBe`
            [ "Replace with `-`"
            , "Replace with `--` (start a comment)"
            ]

    it "offers ONE paired fix for an opening curly quote with a matching closer on the same line" $ do
      case execLexer specUri "#EVAL x (Person WITH name IS \x201C\&Alice\x201D)\n" of
        Right _ -> expectationFailure "expected this to fail lexing"
        Left (pErr :| _) -> case lexErrorQuickFixes pErr of
          [pairFix, singleFix] -> do
            pairFix.title `shouldBe` "Straighten this pair of quotes"
            singleFix.title `shouldBe` "Replace with `\"`"
            -- the pair fix touches BOTH quotes in one edit
            length pairFix.edits `shouldBe` 2
          other -> expectationFailure ("expected exactly two fixes, got " <> show (length other))

  describe "nbspQuickFix (pure)" $
    it "replaces exactly the offending character with an ordinary space" $ do
      let range = MkSrcRange (MkSrcPos 3 5) (MkSrcPos 3 6) 1 specUri
          fix = nbspQuickFix range
      fix.title `shouldBe` "Replace with an ordinary space"
      fix.edits `shouldBe` [TextEdit (srcRangeToLspRange (Just range)) " "]

  describe "end to end: the did-you-mean fix through the real checker" $ do
    it "reference curly, declaration straight" $ do
      mFix <- confusableFixFor "curly-ref" $ T.unlines
        [ "GIVETH A BOOLEAN"
        , "DECIDE `don't panic` IF TRUE"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE `check` IF `don\x2019t panic`"
        ]
      fmap (.title) mFix `shouldBe` Just "Replace with `don't panic`"

    it "reference straight, declaration curly" $ do
      mFix <- confusableFixFor "curly-decl" $ T.unlines
        [ "GIVETH A BOOLEAN"
        , "DECIDE `don\x2019t panic` IF TRUE"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE `check` IF `don't panic`"
        ]
      fmap (.title) mFix `shouldBe` Just "Replace with `don\x2019t panic`"

-- | Type-check a module written to a scratch file and hand back the
-- did-you-mean fix the checker's first out-of-scope name earns — the same
-- shape as "OutOfScopeGivenFixSpec"'s @fixFor@, but for the confusable-
-- character quick fix instead of the GIVEN quick fix.
confusableFixFor :: String -> T.Text -> IO (Maybe QuickFix)
confusableFixFor stem source = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-smart-punctuation-actions-spec"
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
      (name, _ty) <- firstOutOfScope tc
      range <- rangeOf name
      let refRaw = rawNameToText (rawName name)
          inScopeRaw = inScopeRawNamesAt range.start tc
      confusableDidYouMeanFix range refRaw inScopeRaw
  pure mFix

-- | The first name the checker could not find a definition for.
firstOutOfScope :: TypeCheckResult -> Maybe (Name, Type' Resolved)
firstOutOfScope tc =
  listToMaybe
    [ (name, ty)
    | MkCheckErrorWithContext (OutOfScopeError name ty) _ <- tc.errors
    ]
