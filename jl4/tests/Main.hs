{-# LANGUAGE ViewPatterns #-}
module Main (main) where

import Base
import Control.Monad.Trans.Maybe
import qualified Data.Aeson.Encode.Pretty as AP
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text.Encoding as TE
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified L4.Annotation as JL4
import qualified L4.EvaluateLazy as JL4Lazy
import L4.TracePolicy (lspDefaultPolicy)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Export (ExportedFunction (..))
import qualified L4.Export as Export
import qualified L4.Export.Document as Doc
import qualified L4.Export.Render as Render
import L4.JsonSchema (SchemaContext (..))
import qualified L4.JsonSchema as JsonSchema
import qualified L4.Nlg as Nlg
import L4.Parser (PError (..), execProgramParserWithHintPass, execProgramParserWithHintPassUnmemoised)
import qualified L4.Parser.SrcSpan as JL4
import L4.Syntax
import qualified L4.TypeCheck as JL4

import qualified Paths_jl4
import qualified Paths_jl4_core

import qualified Base.Text as Text
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types
import System.Environment (lookupEnv, setEnv)
import System.FilePath
import System.FilePath.Glob
import System.IO.Silently
import Test.Hspec
import Test.Hspec.Golden
import qualified Regex.Text as RE
import qualified Data.CharSet as CharSet
import qualified System.OsPath as OsPath
import LSP.L4.Rules

import qualified Hover
import qualified SemanticTokens

main :: IO ()
main = do
  dataDir <- Paths_jl4.getDataDir
  dataDirCore <- Paths_jl4_core.getDataDir
  -- Make the golden suite self-sufficient under a bare `cabal test`: point
  -- library resolution at the bundled core libraries unless the caller has
  -- already chosen a store. Without this, examples that IMPORT a library (e.g.
  -- actus-library-test) fail locally because embedded transitive resolution is
  -- incomplete. CI already exports JL4_LIBRARY_PATH, so this only restores
  -- local/CI parity; an explicit setting is respected.
  mLibEnv <- lookupEnv "JL4_LIBRARY_PATH"
  case mLibEnv of
    Just _  -> pure ()
    Nothing -> setEnv "JL4_LIBRARY_PATH" (dataDirCore </> "libraries")
  envFixed <- JL4Lazy.readFixedNowEnv
  let fallbackNow =
        fromMaybe (error "Internal: invalid fallback timestamp for JL4 tests")
                  (JL4Lazy.parseFixedNow "2025-01-31T15:45:30Z")
  let chosenNow = maybe (Just fallbackNow) Just envFixed
  let tracePolicy = lspDefaultPolicy defaultGraphVizOptions
  evalConfig <- JL4Lazy.resolveEvalConfig chosenNow tracePolicy
  let examplesRoot = dataDir </> "examples"
  okFiles <- sort <$> globDir1 (compile "ok/**/*.l4") examplesRoot
  librariesFiles <- sort <$> globDir1 (compile "*.l4") (dataDirCore </> "libraries")
  legalFiles <- sort <$> globDir1 (compile "legal/**/*.l4") examplesRoot
  tcFailsFiles <- sort <$> globDir1 (compile "not-ok/tc/**/*.l4") examplesRoot
  nlgFailsFiles <- sort <$> globDir1 (compile "not-ok/nlg/**/*.l4") examplesRoot
  semanticTokenFiles <- sort <$> globDir1 (compile "lsp/semantic-tokens/**/*.l4") examplesRoot
  hoverFiles <- sort <$> globDir1 (compile "lsp/hover/**/*.l4") examplesRoot
  -- Top-level not-ok/ fixtures, missed by the not-ok/tc and not-ok/nlg globs.
  -- The export-*.l4 files typecheck fine but assert (via their schema golden)
  -- that an @export in an unsupported position yields no default export.
  -- (empty.l4 used to live here while warnings still failed typecheck; now
  -- that only SError blocks 'SuccessfulTypeCheck', it lives in ok/.)
  exportPlacementFiles <- sort <$> globDir1 (compile "not-ok/export-*.l4") examplesRoot
  hspec do
    describe "corpus sanity (every glob matched something)" $ do
      let corpusNonEmpty nm xs = it (nm <> " corpus is non-empty") $ xs `shouldSatisfy` (not . null)
      corpusNonEmpty "ok"              okFiles
      corpusNonEmpty "libraries"       librariesFiles
      corpusNonEmpty "legal"           legalFiles
      corpusNonEmpty "tc-fails"        tcFailsFiles
      corpusNonEmpty "nlg-fails"       nlgFailsFiles
      corpusNonEmpty "semantic-tokens" semanticTokenFiles
      corpusNonEmpty "hover"           hoverFiles
      corpusNonEmpty "export-placement" exportPlacementFiles
    describe "ok files" $ tests evalConfig (True, True) (okFiles <> legalFiles <> librariesFiles) examplesRoot
    -- The legal examples are what a reader of a rendered document sees. A change
    -- to the wording shows here as a diff, line by line, across all of them.
    describe "rendered documents" $
      forM_ legalFiles $ \inputFile ->
        it (makeRelative examplesRoot inputFile) $
          jl4RenderGolden evalConfig (takeDirectory inputFile </> "tests") inputFile
    -- Invariant: exactprint is the identity on the source for every parseable
    -- corpus file. This is the single guard against the whole class of
    -- format-mangling bugs (mixfix/event reordering, dropped TIMEZONE/DECIDE
    -- tokens, duplicated UNLESS, re-escaped unicode). Unlike the per-file
    -- ".ep.golden" test — which blesses whatever exactprint currently emits, so
    -- it silently records mangled output — this compares against the verbatim
    -- source and so cannot bless a regression.
    describe "exactprint identity (source round-trips l4 format)" $
      forM_ (okFiles <> legalFiles <> librariesFiles) $ \inputFile ->
        it (makeRelative examplesRoot inputFile) $
          jl4ExactPrintIdentity evalConfig inputFile
    -- Invariant: the parser's memo of bracketed groups changes nothing
    -- (MATRYOSHKA, smucclaw/l4-ide#1017). 'L4.Parser.memoGroup' replays a
    -- group's first parse wherever the group is reached again, which is exact
    -- only while the invariants documented there hold. If one breaks, the memo
    -- replays a wrong syntax tree or a wrong error SILENTLY: the file still
    -- parses, or still fails, and nothing else need move. So every file the
    -- blocks in this suite read, those that fail to parse included, is parsed
    -- with the memo on and off, and the two answers must be equal to the
    -- token. jl4-core-test's NestedParenParserSpec does the same on deeper
    -- and broken nests, which the corpus has few of.
    describe "parser memo changes nothing (memo on = memo off; #1017)" $
      forM_ (okFiles <> legalFiles <> librariesFiles <> tcFailsFiles <> nlgFailsFiles <> semanticTokenFiles <> hoverFiles <> exportPlacementFiles) $ \inputFile ->
        it (makeRelative examplesRoot inputFile) $
          jl4ParserMemoChangesNothing inputFile
    describe "tc fails" $ tests evalConfig (False, True) tcFailsFiles examplesRoot
    describe "nlg fails" $ tests evalConfig (True, False) nlgFailsFiles examplesRoot
    describe "export placement (typechecks; no default export)" $
      tests evalConfig (True, True) exportPlacementFiles examplesRoot
    describe "lsp" $ SemanticTokens.semanticTokenTests evalConfig semanticTokenFiles examplesRoot
    describe "lsp hover" $ Hover.hoverTests evalConfig hoverFiles examplesRoot
  where
    tests evalConfig (tcOk, nlgOk) files root =
      forM_ files $ \inputFile -> do
        let testCase = makeRelative root inputFile
        let goldenDir = takeDirectory inputFile </> "tests"
        describe testCase $ do
          it "parses and checks" $
            l4Golden evalConfig tcOk goldenDir inputFile
          it "exactprints" $
            jl4ExactPrintGolden evalConfig goldenDir inputFile
          it "natural language annotations" $
            jl4NlgAnnotationsGolden evalConfig nlgOk goldenDir inputFile
          it "json schema" $
            jl4JsonSchemaGolden evalConfig goldenDir inputFile

l4Golden :: JL4Lazy.EvalConfig -> Bool -> String -> String -> IO (Golden String)
l4Golden evalConfig isOk dir inputFile = do
  (output, _) <- capture (checkFile evalConfig isOk inputFile)
  pure
    Golden
      { output = normalizeWhitespaceString $ stripAnsiCodesString output
      , encodePretty = show
      , writeToFile = writeFile
      , readFromFile = fmap (normalizeWhitespaceString . stripAnsiCodesString) . readFile
      , goldenFile = dir </> (takeFileName inputFile -<.> "golden")
      , actualFile = Just (dir </> (takeFileName inputFile -<.> "actual"))
      , failFirstTime = True
      }

jl4ExactPrintGolden :: JL4Lazy.EvalConfig -> String -> String -> IO (Golden Text)
jl4ExactPrintGolden evalConfig dir inputFile = do
  (errs, moutput) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.ExactPrint uri

  -- NOTE: we sort the output, because the traces are concurrent and might not be in order
  -- Strip ANSI codes and normalize whitespace for cross-platform consistency
  let output = normalizeWhitespace $ stripAnsiCodes $ fromMaybe (sanitizeFilePaths $ mconcat errs) moutput

  pure
    Golden
      { output
      , encodePretty = Text.unpack
      , writeToFile = Text.writeFile
      , readFromFile = fmap (normalizeWhitespace . stripAnsiCodes) . Text.readFile
      , goldenFile = dir </> (takeFileName inputFile -<.> "ep.golden")
      , actualFile = Just (dir </> (takeFileName inputFile -<.> "ep.actual"))
      , failFirstTime = True
      }

-- | Assert @exactprint (parse f) == f@: the exact-printer reproduces the source
-- byte-for-byte. Runs the same 'Rules.ExactPrint' rule that @l4 format@ uses and
-- compares to the verbatim file contents (no whitespace normalisation — that is
-- the whole point). On mismatch we report the first differing line so failures
-- stay legible instead of dumping the whole file.
jl4ExactPrintIdentity :: JL4Lazy.EvalConfig -> FilePath -> IO ()
jl4ExactPrintIdentity evalConfig inputFile = do
  (errs, moutput) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.ExactPrint uri
  src <- Text.readFile inputFile
  case moutput of
    Nothing ->
      expectationFailure $
        "exactprint produced no output for " <> inputFile <> ":\n"
          <> Text.unpack (Text.unlines errs)
    Just out
      | out == src -> pure ()
      | otherwise ->
          expectationFailure $
            "exactprint is not the identity for " <> inputFile
              <> firstDiff (Text.lines src) (Text.lines out)
  where
    firstDiff ss os =
      let n      = max (length ss) (length os)
          pad xs = xs <> replicate (n - length xs) ""
          diffs  = [ (i, s, o)
                   | (i, s, o) <- zip3 [1 :: Int ..] (pad ss) (pad os)
                   , s /= o ]
      in case diffs of
        [] -> " (line contents match; differ only in trailing newline / length: "
                <> show (length ss) <> " vs " <> show (length os) <> " lines)"
        ((i, s, o) : _) ->
          "\n  first difference at line " <> show i
            <> "\n  source:    " <> show s
            <> "\n  exactprint:" <> show o

-- | Assert that the parser answers the same on a file with its memo of
-- bracketed groups on ('execProgramParserWithHintPass', what the tools run)
-- and off: the same syntax tree, hints and warnings when the file parses, and
-- the same errors, message and position, when it does not.
jl4ParserMemoChangesNothing :: FilePath -> IO ()
jl4ParserMemoChangesNothing inputFile = do
  src <- Text.readFile inputFile
  let uri = toNormalizedUri (filePathToUri inputFile)
      memoOn = execProgramParserWithHintPass uri src
      memoOff = execProgramParserWithHintPassUnmemoised uri src
  when (memoOn /= memoOff) $
    expectationFailure $
      "the parser's memo changed its answer on " <> inputFile <> case (memoOn, memoOff) of
        (Left on, Left off) ->
          "\n  memo on:\n" <> errors on <> "\n  memo off:\n" <> errors off
        _ ->
          -- A syntax tree is too big to print whole; show where the two
          -- first differ.
          let shownOn = show memoOn
              shownOff = show memoOff
              differAt = length (takeWhile id (List.zipWith (==) shownOn shownOff))
              excerpt shown = take 400 (drop (max 0 (differAt - 200)) shown)
          in  "\n  first difference at character " <> show differAt <> " of the shown answers"
                <> "\n  memo on:  " <> excerpt shownOn
                <> "\n  memo off: " <> excerpt shownOff
  where
    errors errs = unlines [show e.range <> "\n" <> Text.unpack e.message | e <- toList errs]

jl4NlgAnnotationsGolden :: JL4Lazy.EvalConfig -> Bool -> String -> FilePath -> IO (Golden Text)
jl4NlgAnnotationsGolden evalConfig isOk dir inputFile = do
  (errs, moutput) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  let output_ = case moutput of
        Nothing -> "Cannot linearize module that doesn't typecheck\n"
        Just checkResult ->
          -- The SAME function @l4 nlg@ calls (see its module header). Both sides
          -- used to spell the payload out and a comment asked the reader to keep
          -- them in step; they now cannot diverge. The dependencies ride along:
          -- a heralded call in a directive can name a rule an imported module
          -- defines, and its sentence is read from there.
          let deps = map (.module') (Rules.transitiveDependencies checkResult)
          in Text.unlines $ Nlg.linearizeDirectives Nothing checkResult.module' deps
  -- Strip ANSI codes and normalize whitespace for cross-platform consistency
  let output = normalizeWhitespace $ stripAnsiCodes $
        if isOk
          then output_
          else output_ <> "\n" <> Text.unlines (fmap (Text.strip . sanitizeFilePaths) errs)
  pure
    Golden
      { output
      , encodePretty = Text.unpack
      , writeToFile = Text.writeFile
      , readFromFile = fmap (normalizeWhitespace . stripAnsiCodes) . Text.readFile
      , goldenFile = dir </> takeFileName inputFile -<.> "nlg.golden"
      , actualFile = Just (dir </> takeFileName inputFile -<.> "nlg.actual")
      , failFirstTime = True
      }

-- | What @l4 render --format text@ prints for a file, then what it left out: every
-- definition appears exactly once, or is named here.
jl4RenderGolden :: JL4Lazy.EvalConfig -> String -> FilePath -> IO (Golden Text)
jl4RenderGolden evalConfig dir inputFile = do
  (_, moutput) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  let output = normalizeWhitespace $ case moutput of
        Nothing -> "Cannot render a module that doesn't typecheck\n"
        Just checkResult ->
          let rawDeps = map (.module') (Rules.transitiveDependencies checkResult)
              cfg = Doc.defaultExportConfig
                { Doc.moduleDispositions = Doc.hiddenImports (const False) rawDeps
                , Doc.mixfixHeadings = Doc.mixfixHeadingsFromRegistry checkResult.mixfixRegistry
                }
              (mainModule, deps) = Nlg.prepareModules Nothing checkResult.module' rawDeps
              doc = Doc.buildDocument cfg mainModule deps
          in Render.renderText Render.defaultRenderConfig doc
               <> coverageNote (Doc.buildPlan cfg mainModule deps) doc
  pure
    Golden
      { output
      , encodePretty = Text.unpack
      , writeToFile = Text.writeFile
      , readFromFile = fmap normalizeWhitespace . Text.readFile
      , goldenFile = dir </> takeFileName inputFile -<.> "render.golden"
      , actualFile = Just (dir </> takeFileName inputFile -<.> "render.actual")
      , failFirstTime = True
      }

-- | Which of a module's definitions a document does not show once.
coverageNote :: Doc.ExportPlan -> Doc.Document -> Text
coverageNote plan doc =
  "\n\nCoverage\n" <> Text.unlines
    ( [ "left out: " <> u.planHeading | u <- units, u.planId `notElem` shown ]
   <> [ "shown twice: " <> u.planHeading | u <- units, length (filter (== u.planId) shown) > 1 ]
    )
 where
  units = [ u | m <- plan.planModules, m.planModuleIsMain, u <- m.planUnits ]
  shown = concatMap sectionIds doc.docSections
  sectionIds s = [ b.blockId | g <- s.sectionGroups, b <- g.groupBlocks ] <> concatMap sectionIds s.sectionSubs

jl4JsonSchemaGolden :: JL4Lazy.EvalConfig -> String -> FilePath -> IO (Golden String)
jl4JsonSchemaGolden evalConfig dir inputFile = do
  (_, moutput) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  let output = case moutput of
        Nothing -> "Cannot generate schema for module that doesn't typecheck\n"
        Just checkResult ->
          let exports = Export.getExportedFunctions checkResult.module'
              defaultExport = selectDefaultExport exports
          in case defaultExport of
               Nothing -> "No @export annotations found in file\n"
               Just export ->
                 let ctx = buildSchemaContext checkResult.module'
                     schema = JsonSchema.generateJsonSchema ctx export
                 -- NOT 'BL.unpack'. 'Data.ByteString.Lazy.Char8.unpack' maps
                 -- each BYTE to a 'Char', and 'AP.encodePretty' returns UTF-8
                 -- bytes — so every non-ASCII character arrived here as its
                 -- individual bytes, and 'writeFile' then re-encoded each of
                 -- those as UTF-8. Double encoding: source @ä@ (@c3 a4@) was
                 -- stored as @c3 83 c2 a4@, i.e. @Ã¤@.
                 --
                 -- It survived because it ROUND-TRIPS. 'readFromFile' was
                 -- 'readFile', which decodes UTF-8 and so undid the damage
                 -- symmetrically; golden and actual agreed and the suite stayed
                 -- green while the file on disk held mojibake. The @.ep.golden@
                 -- beside it, written from 'Text', held the same source text
                 -- correctly — which is the control that makes this visible.
                 -- smucclaw/l4-ide#962.
                 in Text.unpack (TE.decodeUtf8 (BL.toStrict (AP.encodePretty schema))) ++ "\n"
  pure
    Golden
      { output
      , encodePretty = id
      , writeToFile = writeFile
      , readFromFile = readFile
      , goldenFile = dir </> takeFileName inputFile -<.> "schema.golden"
      , actualFile = Just (dir </> takeFileName inputFile -<.> "schema.actual")
      , failFirstTime = True
      }

selectDefaultExport :: [ExportedFunction] -> Maybe ExportedFunction
selectDefaultExport exports =
  case List.find (.exportIsDefault) exports of
    Just e -> Just e
    Nothing -> listToMaybe exports

buildSchemaContext :: Module Resolved -> SchemaContext
buildSchemaContext (MkModule _ _ section) =
  JsonSchema.emptyContext{ctxDeclares = collectDeclares section}
 where
  collectDeclares :: Section Resolved -> Map.Map Text (Declare Resolved)
  collectDeclares (MkSection _ _ _ decls) =
    Map.fromList $ concatMap collectDecl decls

  collectDecl :: TopDecl Resolved -> [(Text, Declare Resolved)]
  collectDecl = \case
    Declare _ decl@(MkDeclare _ _ appForm _) ->
      [(getDeclName appForm, decl)]
    Section _ sub -> Map.toList $ collectDeclares sub
    _ -> []

  getDeclName (MkAppForm _ name _ _) = rawNameToText (rawName (getActual name))

-- ----------------------------------------------------------------------------
-- Test helpers
-- ----------------------------------------------------------------------------

sanitizeFilePaths :: Text -> Text
sanitizeFilePaths = stripAnsiCodes . RE.replaceAll regex
  where
  mkFileName (Text.null -> hadNoWhiteSpace) (Text.unpack -> fp)
    = Text.pack $ (if hadNoWhiteSpace then id else (' ' :)) case OsPath.decodeUtf . OsPath.takeFileName =<< OsPath.encodeUtf fp of
      Just p | not (null p) -> p
      _ -> fp

  regex = mkFileName <$> RE.manyTextOf CharSet.space <* RE.text "file://" <*>
      RE.manyTextOf (CharSet.not $ CharSet.space `CharSet.union` CharSet.singleton ':')

-- | Strip ANSI color codes from text output
-- Handles both proper ANSI codes (\x1b[...m) and literal bracket codes
stripAnsiCodes :: Text -> Text
stripAnsiCodes text =
  -- First strip proper ANSI codes with escape character
  let text' = Text.pack $ stripAnsiCodesGo $ Text.unpack text
  -- Then strip literal bracket codes and any colored spaces pattern
  in foldr (\code -> Text.replace code "") text'
       ["[42m    [0m", "[41m    [0m", "[42m", "[41m", "[36m", "[32m", "[31m", "[0m", "[42m ", "[41m "]

-- | Strip ANSI codes from String (for Golden tests using String type)
stripAnsiCodesString :: String -> String
stripAnsiCodesString str =
  let str' = stripAnsiCodesGo str
  -- Strip literal bracket codes
  in foldl (\s code -> replaceString code "" s) str'
       ["[42m    [0m", "[41m    [0m", "[42m", "[41m", "[36m", "[32m", "[31m", "[0m", "[42m ", "[41m "]
  where
    replaceString :: String -> String -> String -> String
    replaceString _ _ [] = []
    replaceString old new s@(x:xs)
      | old `List.isPrefixOf` s = new ++ replaceString old new (drop (length old) s)
      | otherwise = x : replaceString old new xs

-- | Core ANSI stripping logic for proper escape sequences
stripAnsiCodesGo :: String -> String
stripAnsiCodesGo [] = []
stripAnsiCodesGo ('\x1b':'[':rest) = stripAnsiCodesGo (drop 1 $ dropWhile (/= 'm') rest)
stripAnsiCodesGo (c:cs) = c : stripAnsiCodesGo cs

-- | Normalize whitespace only on diagnostic label lines.
-- This is a targeted fix for cross-platform prettyprinter differences
-- without affecting L4's whitespace-sensitive output.
normalizeWhitespace :: Text -> Text
normalizeWhitespace = Text.unlines . map normalizeLine . Text.lines
  where
    normalizeLine line
      | isDiagnosticLabel line = normalizeSpaces line
      | otherwise = line
    -- Only normalize lines that look like diagnostic labels
    isDiagnosticLabel line = any (`Text.isPrefixOf` Text.stripStart line) diagnosticLabels
    diagnosticLabels = ["File:", "Hidden:", "Range:", "Source:", "Severity:", "Code:", "Message:"]
    normalizeSpaces line =
      let (indent, rest) = Text.span (== ' ') line
      in indent <> Text.unwords (Text.words rest)

-- | String version of targeted whitespace normalization
normalizeWhitespaceString :: String -> String
normalizeWhitespaceString = unlines . map normalizeLine . lines
  where
    normalizeLine line
      | isDiagnosticLabel line = normalizeSpaces line
      | otherwise = line
    isDiagnosticLabel line = any (`List.isPrefixOf` dropWhile (== ' ') line) diagnosticLabels
    diagnosticLabels = ["File:", "Hidden:", "Range:", "Source:", "Severity:", "Code:", "Message:"]
    normalizeSpaces line =
      let (indent, rest) = span (== ' ') line
      in indent ++ unwords (words rest)

checkFile :: JL4Lazy.EvalConfig -> Bool -> FilePath -> IO ()
checkFile evalConfig isOk file = do
  (errs, isJust ->  success) <- oneshotL4ActionAndErrors evalConfig file \nfp -> runMaybeT do
      let uri = normalizedFilePathToUri nfp
      _        <- lift   $ Shake.addVirtualFileFromFS nfp
      _        <- MaybeT $ Shake.use GetParsedAst uri        <* liftIO (Text.putStrLn "Parsing successful")
      checked  <- MaybeT $ Shake.use SuccessfulTypeCheck uri <* liftIO (Text.putStrLn "Typechecking successful")
      results' <- MaybeT $ Shake.use EvaluateLazy uri
      when (not (null results')) $ liftIO $ Text.putStrLn "Evaluation successful"
      let msgs  =    map typeErrorToMessage checked.infos
                  <> map evalLazyDirectiveResultToMessage results'
          formatted = foldMap (sanitizeFilePaths . renderMessage) $ sortOn fst msgs
      liftIO $ Text.putStr formatted
  -- NOTE: if we're okay, we don't expect any errors, if we are not, we do expect them
  success `shouldBe` isOk
  unless success do
    Text.putStr $ foldMap sanitizeFilePaths errs

 where
  typeErrorToMessage err = (JL4.rangeOf err, JL4.prettyCheckErrorWithContext err)
  evalLazyDirectiveResultToMessage res@(JL4Lazy.MkEvalDirectiveResult r _ _) =
    (r, Text.lines (JL4Lazy.prettyEvalDirectiveResult res))
  renderMessage (r, txt) = cliErrorMessage r txt

cliErrorMessage :: Maybe JL4.SrcRange -> [Text] -> Text
cliErrorMessage mrange msg =
  Text.unlines
    ( JL4.prettySrcRangeM  mrange <> ":"
        : map ("  " <>) msg
    )
