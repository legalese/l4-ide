{-# LANGUAGE ViewPatterns #-}
module Main (main) where

import Base
import Control.Monad.Trans.Maybe
import Data.Char (isAlphaNum)
import qualified Data.Aeson.Encode.Pretty as AP
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified L4.Annotation as JL4
import qualified L4.EvaluateLazy as JL4Lazy
import L4.TracePolicy (lspDefaultPolicy)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Export (ExportedFunction (..))
import qualified L4.Export as Export
import L4.JsonSchema (SchemaContext (..))
import qualified L4.JsonSchema as JsonSchema
import qualified L4.Nlg as Nlg
import L4.DirectiveFilter (filterIdeDirectives)
import L4.Parser (execProgramParserWithHintPass)
import qualified L4.Parser.SrcSpan as JL4
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as JL4

import qualified Paths_jl4
import qualified Paths_jl4_core

import qualified Base.Text as Text
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types
import Optics
import System.Environment (lookupEnv, setEnv)
import System.FilePath
import System.FilePath.Glob
import System.IO.Silently
import Test.Hspec
import Text.Read (readMaybe)
import Test.Hspec.Golden
import qualified Regex.Text as RE
import qualified Data.CharSet as CharSet
import qualified System.OsPath as OsPath
import LSP.L4.Rules

import qualified BpmnExport
import qualified Hover
import qualified SemanticTokens
import qualified VizAutoRefresh
import qualified VizImplies
import qualified VizGuardedRows
import qualified DmnExport

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
    -- Invariant: the *other* printer round-trips too. `l4 batch` (and the REPL)
    -- reconstruct a module by running the typechecked AST through
    -- 'filterIdeDirectives' and 'prettyLayout', then re-parsing the result; if
    -- that text does not parse, the command fails before it evaluates anything
    -- (smucclaw/l4-ide#932). Unlike exactprint this path has no golden at all,
    -- so it is asserted as a property over the whole corpus rather than on a
    -- fixture: exactly the files the "ok files" block typechecks.
    describe "prettyLayout round-trip (filter -> print -> parse; #932)" $
      forM_ (okFiles <> legalFiles <> librariesFiles) $ \inputFile ->
        it (makeRelative examplesRoot inputFile) $
          jl4PrettyLayoutRoundTrip evalConfig inputFile
    describe "tc fails" $ tests evalConfig (False, True) tcFailsFiles examplesRoot
    describe "nlg fails" $ tests evalConfig (True, False) nlgFailsFiles examplesRoot
    describe "export placement (typechecks; no default export)" $
      tests evalConfig (True, True) exportPlacementFiles examplesRoot
    describe "lsp" $ SemanticTokens.semanticTokenTests evalConfig semanticTokenFiles examplesRoot
    describe "lsp hover" $ Hover.hoverTests evalConfig hoverFiles examplesRoot
    describe "viz" VizAutoRefresh.spec
    describe "viz implies" VizImplies.spec
    describe "viz guarded rows" VizGuardedRows.spec
    DmnExport.spec examplesRoot
    describe "bpmn export" BpmnExport.spec
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
  scrubLibPath <- mkLibraryPathScrubber
  let normalize = scrubLibPath . normalizeWhitespaceString . stripAnsiCodesString
  pure
    Golden
      { output = normalize output
      , encodePretty = show
      , writeToFile = writeFile
      , readFromFile = fmap normalize . readFile
      , goldenFile = dir </> (takeFileName inputFile -<.> "golden")
      , actualFile = Just (dir </> (takeFileName inputFile -<.> "actual"))
      , failFirstTime = True
      }

-- | Build a scrubber that replaces the (absolute, machine-specific)
-- @JL4_LIBRARY_PATH@ prefix with a stable @$JL4_LIBRARY_PATH@ token, so goldens
-- that capture import-resolution logs like @Found on filesystem: <abspath>@ are
-- portable across machines and CI. In jl4-test @JL4_LIBRARY_PATH@ is always set
-- (see 'main'), so a library import is always resolved from the filesystem at
-- that path; the only environment-dependent part of the log is the prefix.
-- No-op when the variable is unset or empty.
mkLibraryPathScrubber :: IO (String -> String)
mkLibraryPathScrubber = do
  mp <- lookupEnv "JL4_LIBRARY_PATH"
  pure $ case mp of
    Just p | not (null p) ->
      Text.unpack . Text.replace (Text.pack p) "$JL4_LIBRARY_PATH" . Text.pack
    _ -> id

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

-- | Assert @parse (prettyLayout (filterIdeDirectives (typecheck f)))@ succeeds:
-- the AST pretty-printer emits source the layout parser accepts. This is the
-- exact pipeline of @jl4/app/L4/Cli/Batch.hs@ (typecheck, filter, print, write
-- the text to @<file>.batchN.l4@, re-run the front end on it), so a failure here
-- is a failure of @l4 batch@ on that file. We stop at the parser because the
-- reported defect is a parser diagnostic; a stricter re-typecheck would fold in
-- unrelated name-resolution questions.
jl4PrettyLayoutRoundTrip :: JL4Lazy.EvalConfig -> FilePath -> IO ()
jl4PrettyLayoutRoundTrip evalConfig inputFile = do
  (errs, mtc) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  case mtc of
    Nothing ->
      expectationFailure $
        "typecheck produced no module for " <> inputFile <> ":\n"
          <> Text.unpack (Text.unlines errs)
    Just tc -> do
      let printed = prettyLayout (filterIdeDirectives tc.module')
          printUri = toNormalizedUri (Uri "file:///pretty-layout-roundtrip")
      -- Debugging affordance: prettyLayout output for a corpus module runs to
      -- thousands of columns, so the inline excerpt below is rarely enough to
      -- diagnose a layout failure. Point JL4_PRETTY_DUMP_DIR at a scratch
      -- directory to get the whole emitted module written out for inspection
      -- (it is then a plain .l4 file you can run `l4 check` on).
      mDump <- lookupEnv "JL4_PRETTY_DUMP_DIR"
      for_ mDump $ \d ->
        Text.writeFile (d </> takeFileName inputFile <> ".pl.l4") printed
      -- No gensym may reach the output. Every inference variable in the
      -- type-checked module is rendered exactly as `seed <> uniq` by the
      -- 'Type'' printer, so we can name the forbidden strings precisely rather
      -- than pattern-matching on "looks like an identifier ending in digits" —
      -- which would false-positive on `identity1`, `const1a`, `s24`.
      let leaked = leakedInfVars tc.module' printed
      unless (null leaked) $
        expectationFailure $
          "prettyLayout leaked an inference variable (gensym) for " <> inputFile
            <> "\n--- leaked ---\n"
            <> unlines [ "  " <> Text.unpack v | v <- leaked ]
      case execProgramParserWithHintPass printUri printed of
        Left perrs ->
          expectationFailure $
            "prettyLayout output did NOT re-parse for " <> inputFile
              <> "\n--- parser errors ---\n"
              <> show perrs
              <> "\n--- printed (offending lines) ---\n"
              <> Text.unpack (offending printed perrs)
        -- Parsing is necessary but not sufficient: `l4 batch` re-runs the whole
        -- front end on the printed text, and a printer that drops brackets can
        -- produce source that parses into a DIFFERENT tree. (`f OF x AND y`
        -- re-parses as `f OF (x AND y)`.) So the printed module must also
        -- type-check, from the ORIGINAL file's directory, exactly as batch
        -- places its `<file>.batchN.l4`.
        Right _ -> do
          let virtualPath = inputFile <> ".prettylayout.l4"
          (errs2, mtc2) <- oneshotL4ActionAndErrors evalConfig virtualPath \_nfp -> do
            let uri2 = normalizedFilePathToUri (toNormalizedFilePath virtualPath)
            _ <- Shake.addVirtualFile (toNormalizedFilePath virtualPath) printed
            Shake.use Rules.SuccessfulTypeCheck uri2
          case mtc2 of
            Just tc2 | tc2.success -> pure ()
            _ ->
              expectationFailure $
                "prettyLayout output re-parsed but did NOT type-check for " <> inputFile
                  <> "\n--- checker errors ---\n"
                  <> Text.unpack (Text.unlines (map sanitizeFilePaths errs2))
  where
    -- Show only the lines the parser complained about (plus one of context);
    -- prettyLayout output for a corpus module is thousands of columns wide.
    offending printed perrs =
      let ls    = zip [1 :: Int ..] (Text.lines printed)
          rows  = [ r | r <- errorRows (show perrs), r > 0 ]
          keep  = [ (i, l) | (i, l) <- ls
                  , any (\r -> i >= r - contextBefore && i <= r + contextAfter) rows ]
          shown = if null keep then take 5 ls else keep
      in Text.unlines [ Text.pack (show i) <> " | " <> Text.take 400 l | (i, l) <- shown ]
    contextBefore = 18 :: Int
    contextAfter  = 3 :: Int
    -- Pull "line N" style row numbers out of the rendered error; a miss just
    -- means we print the head of the document instead.
    errorRows s =
      [ n | w <- words (map (\c -> if c `elem` (":,()" :: String) then ' ' else c) s)
          , Just n <- [readMaybe w] ]

-- | The renderings of every inference variable in @m@ that occur as a whole
-- token in @printed@.
--
-- 'L4.Print' renders @InfVar _ raw uniq@ as @raw <> uniq@; that is the exact
-- string we forbid. Word-boundary matching keeps a legitimate identifier that
-- merely ends in the same characters from counting (and, conversely, catches a
-- gensym wherever it appears — binder annotation, GIVETH, nested type).
leakedInfVars :: Module Resolved -> Text -> [Text]
leakedInfVars m printed =
  List.nub [ v | v <- renderings, v `elem` tokens ]
  where
    renderings =
      [ rawNameToText raw <> Text.pack (show uniq)
      | InfVar _ raw uniq <- toListOf (gplate @(Type' Resolved)) m
      ]
    tokens = Text.split (not . isTokenChar) printed
    isTokenChar c = isAlphaNum c || c == '_'

jl4NlgAnnotationsGolden :: JL4Lazy.EvalConfig -> Bool -> String -> FilePath -> IO (Golden Text)
jl4NlgAnnotationsGolden evalConfig isOk dir inputFile = do
  (errs, moutput) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  let output_ = case moutput of
        Nothing -> "Cannot linearize module that doesn't typecheck\n"
        Just checkResult ->
          let
            mod' = checkResult.module'
            directives = toListOf (gplate @(Directive Resolved)) mod'
          in
            Text.unlines $ fmap Nlg.simpleLinearizer directives
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
                 in BL.unpack (AP.encodePretty schema) ++ "\n"
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
  evalLazyDirectiveResultToMessage res@(JL4Lazy.MkEvalDirectiveResult r _ _ _) =
    (r, Text.lines (JL4Lazy.prettyEvalDirectiveResult res))
  renderMessage (r, txt) = cliErrorMessage r txt

cliErrorMessage :: Maybe JL4.SrcRange -> [Text] -> Text
cliErrorMessage mrange msg =
  Text.unlines
    ( JL4.prettySrcRangeM  mrange <> ":"
        : map ("  " <>) msg
    )
