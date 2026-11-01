{-# LANGUAGE ExplicitNamespaces #-}
-- | Every diagnostic carries a stable code, so that tools never match on message
-- text. These examples run the real rules, as @l4 run@ does.
module DiagnosticCodesSpec (spec) where

import Control.Monad (forM_)
import Data.Char (isAsciiLower, isAsciiUpper)
import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.FilePath ((<.>), (</>))

import Language.LSP.Protocol.Types (CodeDescription (..), Diagnostic (..), Uri (..), normalizedFilePathToUri, type (|?) (..))

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Lexer (TokenType (..), keywords, tokenKindSlug)
import L4.TracePolicy (lspDefaultPolicy)
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics)
import LSP.L4.Rules (ExportCheck (..))

import ImportOnceSpec (Mode (..), fun, runTree, withTree)

import Test.Hspec

diagnosticsOf :: [(String, T.Text)] -> String -> IO [Diagnostic]
diagnosticsOf files entry = map (.fdLspDiagnostic) . fst <$> runTree "diagnostic-codes" Run files entry

codeOf :: Diagnostic -> Maybe T.Text
codeOf d = case d._code of
  Just (InR code) -> Just code
  _ -> Nothing

codesOf :: T.Text -> IO [T.Text]
codesOf source = mapMaybe codeOf <$> diagnosticsOf [("entry", source)] "entry"

-- | The diagnostics of the export check alone, over one file.
exportDiagnosticsOf :: T.Text -> IO [Diagnostic]
exportDiagnosticsOf source = withTree "export-codes" [("entry", source)] \dir -> do
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_logs, diags, _) <- oneshotL4ActionAndDiagnostics evalConfig (dir </> "entry" <.> "l4") \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use ExportCheck uri
  pure (map (.fdLspDiagnostic) diags)

-- | One @\@export@ for each kind of finding the export check has.
exportSource :: T.Text
exportSource = T.unlines
  [ "DECLARE Party IS ONE OF alice, bob"
  , "DECLARE Act IS ONE OF ping, pong"
  , "DECLARE Rule HAS"
  , "  name IS A STRING"
  , "  test IS A FUNCTION FROM NUMBER TO BOOLEAN"
  , ""
  , "@export Who acted"
  , "GIVEN e IS AN EVENT Party Act"
  , "GIVETH A Party"
  , "`who acted` MEANS"
  , "  CONSIDER e"
  , "  WHEN EVENT p a n THEN p"
  , ""
  , "@export How many events"
  , "GIVEN es IS A LIST OF EVENT Party Act"
  , "GIVETH A NUMBER"
  , "`how many events` MEANS 0"
  , ""
  , "@export Make an event"
  , "GIVEN p IS A Party"
  , "GIVETH AN EVENT Party Act"
  , "`make event` MEANS EVENT p ping 0"
  , ""
  , "@export The duty"
  , "GIVETH A DEONTIC Party Act"
  , "`the duty` MEANS PARTY alice MUST ping WITHIN 3"
  , ""
  , "@export Apply the test"
  , "GIVEN test IS A FUNCTION FROM NUMBER TO BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`apply the test` MEANS test 1"
  , ""
  , "@export Name of the rule"
  , "GIVEN r IS A Rule"
  , "GIVETH A STRING"
  , "`name of the rule` MEANS r's name"
  , ""
  , "@export Is it positive"
  , "GIVEN n"
  , "GIVETH A BOOLEAN"
  , "`is it positive` MEANS n > 0"
  , ""
  , "ASSUME rate IS A NUMBER"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`scaled` n MEANS n TIMES rate"
  , ""
  , "@export Scaled again"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`scaled again` n MEANS `scaled` n"
  ]

-- | A code that is a slug, with the link one formula gives.
hasCodeAndLink :: Diagnostic -> Expectation
hasCodeAndLink d = case codeOf d of
  Nothing -> expectationFailure ("no code on: " <> show d)
  Just code -> do
    code `shouldSatisfy` isSlug
    d._codeDescription `shouldBe`
      Just CodeDescription
        { _href = Uri ("https://legalese.com/l4/reference/errors#" <> T.replace "/" "-" code) }

-- | @area/what-happened@, with nothing in it that could have been typed in a
-- document: the rest is letters and hyphens, and the examples below check that
-- it is not what the user wrote.
isSlug :: T.Text -> Bool
isSlug code = case T.splitOn "/" code of
  [area, rest] ->
    area `elem` ["parse", "check", "lint", "eval", "import", "file", "internal"]
      && not (T.null rest)
      && not ("-" `T.isSuffixOf` rest)
      && T.all (\c -> isAsciiLower c || isAsciiUpper c || c == '-') rest
  _ -> False

-- | Sources that fail on something the user wrote, to see that it stays out of
-- the code: @zzq@ and @98765@ are in the source of all of them, and in none of
-- the codes.
userText :: [(T.Text, T.Text)]
userText =
  [ ("DECLARE Foo HAS zzqa zzqb\n", "parse/unexpected-identifier")
  , ("DECLARE Foo HAS `zzq a` `zzq b`\n", "parse/unexpected-identifier")
  , ("DECLARE \"zzq\"\n", "parse/unexpected-string")
  , ("DECLARE 98765\n", "parse/unexpected-number")
  , ("DECIDE x IS 1 \"zzq\"\n", "parse/unexpected-string")
  , ("DECIDE zzq IS \"zzq\n", "parse/unexpected-end-of-input")
  , ("DECIDE zzq IS 1 \\ 98765\n", "parse/syntax-error")
  ]

-- | Where the code of a diagnostic is decided, read to check the list of codes.
codeSources :: [FilePath]
codeSources =
  [ "../jl4-core/src/L4/EvaluateLazy.hs"
  , "../jl4-core/src/L4/EvaluateLazy/Exceptions.hs"
  , "../jl4-core/src/L4/Export.hs"
  , "../jl4-core/src/L4/Lexer.hs"
  , "../jl4-core/src/L4/Parser/AnnotationWarning.hs"
  , "../jl4-core/src/L4/TypeCheck/Types.hs"
  , "src/LSP/Core/FileStore.hs"
  , "src/LSP/Core/Shake.hs"
  , "src/LSP/L4/Rules.hs"
  ]

spec :: Spec
spec = describe "diagnostic codes" do
  describe "parse errors" do
    it "name a keyword that is out of place" do
      codesOf "DECLARE Foo HAS\n  x WITH\n" `shouldReturn` ["parse/unexpected-WITH"]

    it "name an operator that is out of place" do
      codesOf (fun "f" "x == 5") `shouldReturn` ["parse/unexpected-double-equals"]

    it "say so when the input ends" do
      codesOf "DECIDE x IS (1\n" `shouldReturn` ["parse/unexpected-end-of-input"]

    it "report indentation" do
      codesOf "DECIDE x IS\n  IF TRUE THEN 1 ELSE\nDECIDE y IS 1\n" `shouldReturn` ["parse/indentation"]

  describe "type errors" do
    it "name an identifier nothing defines" do
      codesOf (fun "f" "`nothing by that name`") `shouldReturn` ["check/unknown-identifier"]

    it "name a wrong number of arguments" do
      codes <- codesOf (fun "f" "x" <> "#EVAL f 1 2\n")
      codes `shouldContain` ["check/wrong-argument-count"]

    it "name a type mismatch" do
      codes <- codesOf (fun "f" "x PLUS TRUE")
      codes `shouldContain` ["check/type-mismatch"]

  describe "evaluation" do
    it "names a failed #ASSERT" do
      codesOf "#ASSERT FALSE\n" `shouldReturn` ["eval/assertion-failed"]

    it "tells a passed #ASSERT from a failed one" do
      codesOf "#ASSERT TRUE\n" `shouldReturn` ["eval/assertion-passed"]

    it "has one code for the result of an #EVAL" do
      codesOf "#EVAL 1\n#EVAL 2\n" `shouldReturn` ["eval/result", "eval/result"]

    it "names what stopped an #EVAL" do
      codesOf "#EVAL 1 / 0\n" `shouldReturn` ["eval/division-by-zero"]

    it "names what stopped an #ASSERT, which is not a failed verdict" do
      codesOf "#ASSERT 1 / 0 = 1\n" `shouldReturn` ["eval/division-by-zero"]

    it "answers a #CHECK with a code of its own" do
      codesOf "#CHECK 1\n" `shouldReturn` ["check/result"]

  describe "lint warnings" do
    it "name AND and OR at one indentation" do
      codes <- codesOf "DECIDE w IS FALSE\nDECIDE v IS\n  w\n    AND w\n    OR w\n"
      codes `shouldContain` ["lint/and-or-same-indentation"]

    it "name a redundant branch" do
      codes <- codesOf $ T.unlines
        [ "GIVEN x IS A BOOLEAN"
        , "f x MEANS"
        , "  CONSIDER x"
        , "    WHEN TRUE THEN 1"
        , "    OTHERWISE 2"
        , "    WHEN FALSE THEN 3"
        ]
      codes `shouldContain` ["lint/redundant-branch"]

    it "name a redundant @lang en" do
      codes <- codesOf "@lang en\n\nDECIDE x IS 1\n"
      codes `shouldContain` ["lint/redundant-lang-en"]

  describe "imports" do
    it "name a module that is not there" do
      codes <- codesOf "IMPORT `no such module`\n\nDECIDE x IS 1\n"
      codes `shouldContain` ["import/module-not-found"]

    it "name an imported module with errors" do
      diags <- diagnosticsOf
        [ ("broken", fun "broken" "x PLUS TRUE")
        , ("entry", "IMPORT broken\n\nDECIDE x IS 1\n")
        ]
        "entry"
      mapMaybe codeOf diags `shouldContain` ["import/module-has-errors"]

    it "name a ring of imports" do
      diags <- diagnosticsOf
        [ ("left", "IMPORT right\n\nDECIDE x IS 1\n")
        , ("right", "IMPORT left\n\nDECIDE y IS 1\n")
        ]
        "left"
      mapMaybe codeOf diags `shouldContain` ["import/cycle"]

    it "name a file that imports itself" do
      codes <- codesOf "IMPORT entry\n\nDECIDE x IS 1\n"
      codes `shouldContain` ["import/self-import"]

  describe "exports" do
    it "name what an @export cannot send, and the one input that has no written type" do
      diags <- exportDiagnosticsOf exportSource
      forM_ diags \d -> d._source `shouldBe` Just "export"
      forM_ diags hasCodeAndLink
      sort (mapMaybe codeOf diags) `shouldBe` sort
        [ "check/export-event-type"
        , "check/export-event-type"
        , "check/export-event-type"
        , "check/export-deontic-type"
        , "check/export-function-input"
        , "check/export-function-input"
        , "lint/export-untyped-given"
        , "check/export-assume-reached"
        ]

  describe "every code" do
    let examples =
          [ "DECLARE Foo HAS\n  x WITH\n"
          , fun "f" "`nothing by that name`"
          , "#ASSERT FALSE\n#ASSERT TRUE\n#EVAL 1\n#EVAL 1 / 0\n#CHECK 1\n"
          , "@lang en\n\nDECIDE x IS 1\n"
          , "IMPORT `no such module`\n\nDECIDE x IS 1\n"
          ]

    it "is set on every diagnostic, with the link one formula gives" do
      forM_ examples \source -> do
        diags <- diagnosticsOf [("entry", source)] "entry"
        diags `shouldNotBe` []
        forM_ diags hasCodeAndLink

    it "never contains what the user wrote" do
      forM_ userText \(source, expected) -> do
        codes <- codesOf source
        codes `shouldBe` [expected]
        forM_ codes \code -> do
          code `shouldSatisfy` isSlug
          code `shouldSatisfy` (not . T.isInfixOf "zzq")
          code `shouldSatisfy` (not . T.isInfixOf "98765")

    it "of a keyword is the keyword" do
      forM_ (Map.toList keywords) \(spelling, keyword) ->
        tokenKindSlug (TKeywords keyword) `shouldBe` spelling

    -- A rule for the list, not for the compiler: nothing else notices when the
    -- document that tools read falls behind the code.
    it "in the source is in DIAGNOSTIC-CODES.md, and the other way round" do
      sources <- traverse T.readFile codeSources
      document <- T.readFile "DIAGNOSTIC-CODES.md"
      let inSource = Set.fromList (filter isSlug (concatMap (T.splitOn "\"") sources))
          inDocument = Set.fromList (filter documented (backticked document))
          -- Built from a token's kind, so the document names them by a pattern.
          documented code = isSlug code && not ("parse/unexpected-" `T.isPrefixOf` code)
      sort (Set.toList (inSource `Set.difference` inDocument)) `shouldBe` []
      sort (Set.toList (inDocument `Set.difference` inSource)) `shouldBe` []
 where
  backticked = map snd . filter (odd . fst) . zip [0 :: Int ..] . T.splitOn "`"
