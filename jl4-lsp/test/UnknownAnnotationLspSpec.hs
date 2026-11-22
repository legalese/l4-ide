{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE PatternSynonyms #-}

-- | What the editor sees for an annotation this version of L4 does not know
-- (an @\@something@ line): a WARNING on that line, the rest of the file
-- checked and highlighted as usual.
--
-- Before this, the lexer refused the file. A lexer failure leaves zero
-- semantic tokens, so a module using an annotation from a newer L4 lost all of
-- its highlighting in an editor running an older one, as well as being
-- reported as an error. These tests run the real Shake rules, as the language
-- server does.
module UnknownAnnotationLspSpec (spec) where

import Control.Monad (forM_)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath ((</>))

import Language.LSP.Protocol.Types
  ( Diagnostic (..)
  , DiagnosticSeverity (..)
  , Position (..)
  , Range (..)
  , SemanticTokenTypes (..)
  , normalizedFilePathToUri
  )

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics)
import LSP.L4.Rules (LexerSemanticTokens (..), pattern TypeCheck)
import LSP.SemanticTokens (SemanticToken (..))

import Test.Hspec

rule :: [T.Text]
rule =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE `add one` n IS n + 1"
  ]

-- | Check a module written to a scratch file through the real rules, and hand
-- back every diagnostic published for it and the lexer's semantic tokens.
checkedWith :: String -> T.Text -> IO ([Diagnostic], [SemanticToken])
checkedWith stem source = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-unknown-annotation-lsp-spec"
      path = dir </> (stem <> ".l4")
  createDirectoryIfMissing True dir
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, diags, toks) <- oneshotL4ActionAndDiagnostics evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    _ <- Shake.use TypeCheck uri
    Shake.use LexerSemanticTokens uri
  pure ([ d | FileDiagnostic{fdLspDiagnostic = d} <- diags ], concat toks)

spec :: Spec
spec = do
  describe "an unknown annotation on the first line" $ do
    let firstLine = "@future-annotation this version has never heard of it"
        source = T.unlines $ firstLine : rule

    it "is one warning, and nothing else is reported" $ do
      (diags, _) <- checkedWith "first-line" source
      case diags of
        [d] -> do
          d._severity `shouldBe` Just DiagnosticSeverity_Warning
          d._message `shouldSatisfy` T.isInfixOf "@future-annotation"
        other -> expectationFailure ("expected exactly one diagnostic, got " <> show (length other) <> ": " <> show (map (._message) other))

    it "is reported over the annotation's whole line, from its first column" $ do
      (diags, _) <- checkedWith "first-line-range" source
      map (._range) diags
        `shouldBe` [Range (Position 0 0) (Position 0 (fromIntegral (T.length firstLine)))]

    it "leaves the rest of the file highlighted" $ do
      (_, toks) <- checkedWith "first-line-tokens" source
      toks `shouldSatisfy` (not . null)
      -- the rule's own keywords are still found
      [ t | t <- toks, t.start._line == 3 ] `shouldSatisfy` (not . null)

    it "highlights the annotation itself, as something ignored (a comment)" $ do
      (_, toks) <- checkedWith "first-line-comment" source
      [ t.category | t <- toks, t.start == Position 0 0 ]
        `shouldBe` [SemanticTokenTypes_Comment]

  describe "unknown annotations elsewhere" $ do
    it "mid-file: one warning for each" $ do
      (diags, _) <- checkedWith "mid-file" $ T.unlines $
        rule <> ["", "@one-future-annotation x", ""] <> rule <> ["@another-future-annotation y"]
      map (._severity) diags `shouldBe` replicate 2 (Just DiagnosticSeverity_Warning)

    it "before a DECIDE: one warning" $ do
      (diags, _) <- checkedWith "before-decide" $ T.unlines
        [ "GIVEN n IS A NUMBER", "GIVETH A NUMBER", "@future-annotation x", "DECIDE `add one` n IS n + 1" ]
      map (._severity) diags `shouldBe` [Just DiagnosticSeverity_Warning]

  -- A known annotation that does not have the form it needs is ignored too,
  -- not a lexer error: the same warning severity, the file still checks, and
  -- the editor keeps its highlighting.
  describe "a malformed @lang" $
    -- The last column is where the range ends, in the editor's 0-based
    -- characters. A tab counts to the next tab stop, as it does for every token
    -- in the checker's ranges (megaparsec's tab width of 8), so "@lang\ten" ends
    -- at 10 and not at 8.
    forM_ [ ("a bare @lang", "@lang", 5)
          , ("@lang then a tab", "@lang\ten", 10)
          , ("@lang then a non-ASCII code", "@lang \233", 7)
          ] $ \(what, line, endChar) ->
      describe what $ do
        let source = T.unlines $ line : rule
            message = "Malformed annotation `@lang`: it needs a language code after a space, such as `@lang en` (letters, digits and hyphens), so this line is ignored."
        it "is one warning, and nothing else is reported" $ do
          (diags, _) <- checkedWith "malformed-lang" source
          map (\d -> (d._severity, d._message)) diags
            `shouldBe` [(Just DiagnosticSeverity_Warning, message)]
        it "is reported over the line, from its first column" $ do
          (diags, _) <- checkedWith "malformed-lang-range" source
          map (._range) diags
            `shouldBe` [Range (Position 0 0) (Position 0 endChar)]
        it "leaves the rest of the file highlighted" $ do
          (_, toks) <- checkedWith "malformed-lang-tokens" source
          [ t | t <- toks, t.start._line == 3 ] `shouldSatisfy` (not . null)
        it "highlights the line itself as ignored (a comment)" $ do
          (_, toks) <- checkedWith "malformed-lang-comment" source
          [ t.category | t <- toks, t.start == Position 0 0 ]
            `shouldBe` [SemanticTokenTypes_Comment]

  describe "a file with only known annotations" $
    it "reports nothing" $ do
      (diags, _) <- checkedWith "known-only" $ T.unlines $ ["@desc adds one"] <> rule
      map (._message) diags `shouldBe` []
