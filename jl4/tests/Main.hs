{-# LANGUAGE ViewPatterns #-}
module Main (main) where

import Base
import Control.Exception (SomeException, evaluate, throwIO, try)
import Control.Monad.Trans.Maybe
import Data.Char (isAlphaNum)
import qualified Data.Aeson.Encode.Pretty as AP
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text.Encoding as TE
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified L4.Annotation as JL4
import qualified L4.EvaluateLazy as JL4Lazy
import qualified L4.ExactPrint as ExactPrint
import L4.TracePolicy (lspDefaultPolicy)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Export (ExportedFunction (..))
import qualified L4.Export as Export
import L4.JsonSchema (SchemaContext (..))
import qualified L4.JsonSchema as JsonSchema
import qualified L4.Nlg as Nlg
import L4.DirectiveFilter (filterIdeDirectives)
import L4.Parser (PError (..), execProgramParserWithHintPass, execProgramParserWithHintPassUnmemoised)
import qualified L4.Parser.SrcSpan as JL4
import L4.Print (prettyLayout, restoreMixfixPatterns)
import L4.Syntax
import qualified L4.TypeCheck as JL4

import qualified Paths_jl4
import qualified Paths_jl4_core

import qualified Base.Text as Text
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics, oneshotL4ActionAndErrors)
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types
import Optics
import System.Directory (XdgDirectory (XdgData), getXdgDirectory)
import System.Environment (getExecutablePath, lookupEnv, setEnv)
import System.FilePath
import System.FilePath.Glob
import System.IO.Silently
import GHC.Clock (getMonotonicTimeNSec)
import Test.Hspec
import Text.Read (readMaybe)
import Test.Hspec.Golden
import qualified Regex.Text as RE
import qualified Data.CharSet as CharSet
import qualified System.OsPath as OsPath
import LSP.L4.Rules

import qualified BpmnExport
import qualified LtsList
import qualified Hover
import qualified SemanticTokens
import qualified VizAutoRefresh
import qualified VizImplies
import qualified VizInline
import qualified VizGuardedRows
import qualified DmnExport
import qualified RelationalExport

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
  -- The VENDORED canon mirror (etc/canon-pin.json, etc/sync-canon.mjs). Same
  -- semantics as legal/**: four goldens per file, failFirstTime. It is a copy
  -- of blessed directories in legalese/canon at a pinned SHA -- do not edit it
  -- here and do not re-bless it here; edit in canon, re-bless there, and bump
  -- the pin. The `Canon Mirror` CI job fails when this tree and canon@pin
  -- disagree.
  canonFiles <- sort <$> globDir1 (compile "canon/**/*.l4") examplesRoot
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
  -- A cross-IMPORT refusal takes two files: the module that declares the
  -- section binder, and the importer whose @export reaches it. Imports resolve
  -- importer-relative, so the two have to share a directory -- and only the
  -- importer is meant to fail. Hence a glob that picks the importer out by
  -- name rather than one that takes the whole directory. The library beside it
  -- is deliberately in no glob at all.
  importRefusalFiles <- sort <$> globDir1 (compile "not-ok/import/*-refused.l4") examplesRoot
  -- The unresolvable-IMPORT diagnostic (smucclaw/l4-ide#971). Its own glob
  -- rather than the whole directory, for the reason above: the *-refused pair's
  -- library must stay out of every glob. These two import a module that exists
  -- nowhere, so they need no neighbour at all.
  importUnresolvedFiles <- sort <$> globDir1 (compile "not-ok/import/unresolved-*.l4") examplesRoot
  -- ONE name for the corpus these three blocks share. It was written out
  -- three times, and adding canon/** would have made that four places to keep
  -- in step -- the exact shape of drift CLAUDE.md warns about, and invisible
  -- when it happens because a block that silently covers fewer files still
  -- passes.
  let goldenCorpus = okFiles <> legalFiles <> librariesFiles <> canonFiles
  -- What the goldens of one file share. See 'CheckMemo'.
  --
  -- The prettyLayout block starts from something its file's "parses and checks"
  -- golden derives (see 'checkFile'), for the files of the corpus both read.
  -- @JL4_EVALDIFF@ needs the module itself, which is not what is held, so that
  -- mode takes the unshared path.
  evalDiff <- lookupEnv "JL4_EVALDIFF"
  let keep = if isJust evalDiff then Set.empty else Set.fromList goldenCorpus
  checkMemo <- newCheckMemo keep
  hspec do
    describe "corpus sanity (every glob matched something)" $ do
      let corpusNonEmpty nm xs = it (nm <> " corpus is non-empty") $ xs `shouldSatisfy` (not . null)
      corpusNonEmpty "ok"              okFiles
      corpusNonEmpty "libraries"       librariesFiles
      corpusNonEmpty "legal"           legalFiles
      corpusNonEmpty "canon"           canonFiles
      corpusNonEmpty "tc-fails"        tcFailsFiles
      corpusNonEmpty "nlg-fails"       nlgFailsFiles
      corpusNonEmpty "semantic-tokens" semanticTokenFiles
      corpusNonEmpty "hover"           hoverFiles
      corpusNonEmpty "export-placement" exportPlacementFiles
      corpusNonEmpty "import-refusal"   importRefusalFiles
      corpusNonEmpty "import-unresolved" importUnresolvedFiles
    describe "ok files" $ tests checkMemo evalConfig (True, True) goldenCorpus examplesRoot
    -- The built-in connectives used to be closures over two parameters named
    -- @a@ and @b@, whose @IF a THEN b ELSE FALSE@ bodies showed in every trace
    -- that reached one. They are frames now, with no parameters to name
    -- (UNKNOWN-EVALUATION-SPEC §4.4, U2b), so no golden may show those bodies.
    describe "connective traces name no parameters (U2b)" $ do
      goldens <- runIO (sort <$> globDir1 (compile "**/*.golden") examplesRoot)
      it "has goldens to read" $ goldens `shouldSatisfy` (not . null)
      it "no golden shows a connective's old IF body" $ do
        let oldBodies =
              [ "IF a THEN b ELSE FALSE", "IF a THEN TRUE ELSE b"
              , "IF a THEN b ELSE TRUE", "IF a THEN FALSE ELSE TRUE" ]
        hits <- fmap concat $ for goldens $ \ g -> do
          txt <- Text.readFile g
          pure [ g | any (`Text.isInfixOf` txt) oldBodies ]
        hits `shouldBe` []
    -- Invariant: exactprint is the identity on the source for every parseable
    -- corpus file. This is the single guard against the whole class of
    -- format-mangling bugs (mixfix/event reordering, dropped TIMEZONE/DECIDE
    -- tokens, duplicated UNLESS, re-escaped unicode). Unlike the per-file
    -- ".ep.golden" test — which blesses whatever exactprint currently emits, so
    -- it silently records mangled output — this compares against the verbatim
    -- source and so cannot bless a regression.
    describe "exactprint identity (source round-trips l4 format)" $
      forM_ goldenCorpus $ \inputFile ->
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
      forM_ goldenCorpus $ \inputFile ->
        it (makeRelative examplesRoot inputFile) $
          jl4PrettyLayoutRoundTrip checkMemo evalConfig inputFile
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
      forM_ (goldenCorpus <> tcFailsFiles <> nlgFailsFiles <> semanticTokenFiles <> hoverFiles <> exportPlacementFiles <> importRefusalFiles <> importUnresolvedFiles) $ \inputFile ->
        it (makeRelative examplesRoot inputFile) $
          jl4ParserMemoChangesNothing inputFile
    describe "tc fails" $ tests checkMemo evalConfig (False, True) tcFailsFiles examplesRoot
    describe "import refusal (@export whose read-set crosses an IMPORT)" $
      tests checkMemo evalConfig (False, True) importRefusalFiles examplesRoot
    describe "unresolvable IMPORT (#971)" $
      tests checkMemo evalConfig (False, True) importUnresolvedFiles examplesRoot
    describe "nlg fails" $ tests checkMemo evalConfig (True, False) nlgFailsFiles examplesRoot
    describe "export placement (typechecks; no default export)" $
      tests checkMemo evalConfig (True, True) exportPlacementFiles examplesRoot
    describe "lsp" $ SemanticTokens.semanticTokenTests evalConfig semanticTokenFiles examplesRoot
    describe "lsp hover" $ Hover.hoverTests evalConfig hoverFiles examplesRoot
    describe "viz" VizAutoRefresh.spec
    describe "viz implies" VizImplies.spec
    describe "viz inline" VizInline.spec
    describe "viz guarded rows" VizGuardedRows.spec
    DmnExport.spec examplesRoot
    RelationalExport.spec examplesRoot
    describe "bpmn export" BpmnExport.spec
    describe "lts list" LtsList.spec
  where
    tests memo evalConfig (tcOk, nlgOk) files root =
      forM_ files $ \inputFile -> do
        let testCase = makeRelative root inputFile
        let goldenDir = takeDirectory inputFile </> "tests"
        describe testCase $ do
          it "parses and checks" $
            l4Golden memo evalConfig tcOk root goldenDir inputFile
          it "exactprints" $
            jl4ExactPrintGolden memo evalConfig goldenDir inputFile
          it "natural language annotations" $
            jl4NlgAnnotationsGolden memo evalConfig nlgOk goldenDir inputFile
          it "json schema" $
            jl4JsonSchemaGolden memo evalConfig goldenDir inputFile

l4Golden :: CheckMemo -> JL4Lazy.EvalConfig -> Bool -> String -> String -> String -> IO (Golden String)
l4Golden memo evalConfig isOk examplesRoot dir inputFile = do
  (output, _) <- capture (checkFile memo evalConfig isOk inputFile)
  scrubPaths <- mkPathScrubber examplesRoot
  let normalize = scrubPaths . normalizeWhitespaceString . stripAnsiCodesString
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

-- | Build a scrubber that replaces the two absolute, machine-specific path
-- prefixes that reach golden output with stable tokens, so goldens capturing
-- import-resolution logs like @Found on filesystem: <abspath>@ are portable
-- across machines and CI.
--
-- There are TWO such prefixes and scrubbing only one is not enough:
--
--   * @JL4_LIBRARY_PATH@ -> @$JL4_LIBRARY_PATH@, for an import resolved out of
--     the stdlib. In jl4-test the variable is always set (see 'main').
--   * the examples root -> @$JL4_EXAMPLES@, for an import resolved
--     /importer-relative/ — one corpus file importing its neighbour. Nothing
--     scrubbed this until 2026-09-08, when the first goldens to capture such a
--     resolution (@not-ok/import/**@) were committed with a developer\'s own
--     worktree path baked in. They passed on that machine, deterministically,
--     and failed in CI, whose checkout lives at @/__w/l4-ide/l4-ide@ — a green
--     local run is structurally unable to catch this, so the scrub belongs
--     here rather than in a reviewer\'s eye.
--
--   * the XDG data store and the executable's own directory, for a module that
--     resolves NOWHERE. The not-found diagnostic lists every tier it probed, and
--     two of those tiers are machine-global: @$XDG_DATA_HOME\/jl4\/libraries@ and
--     @<exeDir>\/..\/..\/libraries@ (the VSCode bundle). So the moment a golden
--     captures an unresolvable IMPORT it captures a home directory and a
--     dist-newstyle path -- which is why nothing could be goldened for
--     smucclaw\/l4-ide#971 until these two were scrubbed. Both are computed here
--     exactly as 'LSP.L4.Rules.resolveLibrary' computes them, in this same
--     process, so they cannot drift from what the resolver printed.
--
-- Each replacement is a no-op when its prefix is empty.
mkPathScrubber :: String -> IO (String -> String)
mkPathScrubber examplesRoot = do
  mp <- lookupEnv "JL4_LIBRARY_PATH"
  xdgJl4 <- getXdgDirectory XdgData "jl4"
  exeDir <- takeDirectory <$> getExecutablePath
  let sub prefix token
        | null prefix = id
        | otherwise = Text.unpack . Text.replace (Text.pack prefix) token . Text.pack
      -- TWO SPELLINGS of each directory are scrubbed, because two reach the
      -- output. The candidate paths the resolver builds from its root directory
      -- keep whatever spelling 'examplesRoot' has; the importer-relative
      -- candidate is built from 'fromNormalizedFilePath', which is
      -- 'System.FilePath.normalise'. The not-found diagnostic lists every tier,
      -- so it prints both -- and a scrubber that knew only one of them left the
      -- other absolute. Measured 2026-09-21: the first golden ever to capture an
      -- unresolvable IMPORT came out with "$JL4_EXAMPLES/not-ok/import/..." on
      -- one line and the developer's own "/Users/.../jl4/examples/not-ok/..." on
      -- the next, which is CLAUDE.md §3.1.1's forever-green-here,
      -- forever-red-in-CI trap. The two spellings differed by a "/./" that
      -- `normalise` removes, which is why scrubbing both fixes it.
      --
      -- 'null' is checked before 'normalise', which turns "" into "." -- a
      -- prefix that would match a dot anywhere in the output.
      spellings p
        | null p = []
        | otherwise = List.nub [p, normalise p]
      -- Longest prefix first. None of these nests inside another on any layout we
      -- build in today, but if one ever does, substituting the shorter one first
      -- would leave the longer one half-replaced -- and a half-scrubbed golden is
      -- machine-specific again while looking scrubbed.
      subs = List.sortOn (negate . length . fst) $ concat
        [ [ (p, "$JL4_LIBRARY_PATH") | p <- spellings (fromMaybe "" mp) ]
        , [ (p, "$JL4_EXAMPLES")     | p <- spellings examplesRoot ]
        , [ (p, "$EXE_DIR")          | p <- spellings exeDir ]
        , [ (p, "$XDG_DATA_JL4")     | p <- spellings xdgJl4 ]
        ]
  pure $ \ txt -> foldl' (\ acc (prefix, token) -> sub prefix token acc) txt subs

jl4ExactPrintGolden :: CheckMemo -> JL4Lazy.EvalConfig -> String -> String -> IO (Golden Text)
jl4ExactPrintGolden memo evalConfig dir inputFile = do
  -- The golden is the exact-printer's output, which is a pure function of the
  -- parse the "parses and checks" golden's session already has. When that
  -- session ran for this file and the printer succeeded, read it from there.
  -- Otherwise (the printer failed, or no parse, or that golden did not run)
  -- start the session of its own, because then the session's log is the
  -- golden. The identity test below still goes through 'Rules.ExactPrint' for
  -- every file, so the rule itself stays covered.
  shared <- readIORef memo.exactPrint
  (errs, moutput) <- case shared of
    Just (f, Just printed) | f == inputFile -> do
      logEvent "exactprint-golden-memo" inputFile
      pure ([], Just printed)
    _ -> logSession "exactprint-golden" inputFile $ oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
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
  (errs, moutput) <- logSession "exactprint-identity" inputFile $ oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
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

-- | Assert @parse (prettyLayout (filterIdeDirectives (typecheck f)))@ succeeds:
-- the AST pretty-printer emits source the layout parser accepts. This is the
-- exact pipeline of @jl4/app/L4/Cli/Batch.hs@ (typecheck, filter, print, write
-- the text to @<file>.batchN.l4@, re-run the front end on it), so a failure here
-- is a failure of @l4 batch@ on that file. We stop at the parser because the
-- reported defect is a parser diagnostic; a stricter re-typecheck would fold in
-- unrelated name-resolution questions.
jl4PrettyLayoutRoundTrip :: CheckMemo -> JL4Lazy.EvalConfig -> FilePath -> IO ()
jl4PrettyLayoutRoundTrip memo evalConfig inputFile = do
  -- Either what the "parses and checks" golden already derived from this file's
  -- module (or the exception deriving it raised: it is raised again here, in
  -- the test it belongs to), or a module of our own, which may still come from
  -- the slot ('LogNeededOnFailure': the log is read only when there is no
  -- module, so a memoised module is fine and a memoised failure is not).
  kept <- atomicModifyIORef' memo.kept \m -> (Map.delete inputFile m, Map.lookup inputFile m)
  derived <- case kept of
    Just (Left e) -> throwIO e
    Just (Right p) -> logEvent "prettylayout-tc-kept" inputFile >> pure (Right (Nothing, p))
    Nothing -> do
      (errs, mtc) <- typeCheckedShared memo "prettylayout-tc" evalConfig inputFile LogNeededOnFailure Forget
      pure case mtc of
        Nothing -> Left errs
        Just tc -> Right (Just tc, printedOf tc)
  case derived of
    Left errs ->
      expectationFailure $
        "typecheck produced no module for " <> inputFile <> ":\n"
          <> Text.unpack (Text.unlines errs)
    Right (mtc, MkPrinted printed leaked) -> do
      let printUri = toNormalizedUri (Uri "file:///pretty-layout-roundtrip")
      -- Debugging affordance: prettyLayout output for a corpus module runs to
      -- thousands of columns, so the inline excerpt below is rarely enough to
      -- diagnose a layout failure. Point JL4_PRETTY_DUMP_DIR at a scratch
      -- directory to get the whole emitted module written out for inspection
      -- (it is then a plain .l4 file you can run `l4 check` on).
      mDump <- lookupEnv "JL4_PRETTY_DUMP_DIR"
      for_ mDump $ \d ->
        Text.writeFile (d </> takeFileName inputFile <> ".pl.l4") printed
      -- Second affordance, for the property this one does NOT assert:
      -- EVALUATION equality. `JL4_EVALDIFF=1` writes the UNFILTERED print (the
      -- directives kept, so `#EVAL`/`#ASSERT` still fire) next to each source
      -- file, at `<file>.evaldiff.l4`. Next to it, and not in a scratch dir,
      -- because a printed module has to resolve the same IMPORTs. Then
      -- `l4 run` both and compare the `Result:` blocks; see CLAUDE.md §3.2 for
      -- the loop and the cleanup, which you MUST run — these files are inside
      -- the corpus globs and a later run would try to golden them.
      -- (This mode keeps no module for later, so @mtc@ is always there.)
      mEvalDiff <- lookupEnv "JL4_EVALDIFF"
      for_ (mEvalDiff *> mtc) $ \tc ->
        Text.writeFile (inputFile <> ".evaldiff.l4") (prettyLayout (restoreMixfixPatterns tc.mixfixRegistry tc.module'))
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
          (errs2, mtc2) <- logSession "prettylayout-retc" inputFile $ oneshotL4ActionAndErrors evalConfig virtualPath \_nfp -> do
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

-- | What the prettyLayout round-trip derives from a type-checked module before it
-- re-parses the result: the printed module, and the inference variables that
-- leaked into it.
data Printed = MkPrinted !Text ![Text]

printedOf :: TypeCheckResult -> Printed
printedOf tc = MkPrinted printed leaked
  where
    -- No gensym may reach the output. Every inference variable in the
    -- type-checked module is rendered exactly as `seed <> uniq` by the
    -- 'Type'' printer, so we can name the forbidden strings precisely rather
    -- than pattern-matching on "looks like an identifier ending in digits" —
    -- which would false-positive on `identity1`, `const1a`, `s24`.
    leaked = leakedInfVars tc.module' printed
    -- restoreMixfixPatterns first: without it the printer emits only a mixfix
    -- name's head keyword and two operators sharing one collapse together
    -- (smucclaw/l4-ide#967).
    printed = prettyLayout (filterIdeDirectives (restoreMixfixPatterns tc.mixfixRegistry tc.module'))

jl4NlgAnnotationsGolden :: CheckMemo -> JL4Lazy.EvalConfig -> Bool -> String -> FilePath -> IO (Golden Text)
jl4NlgAnnotationsGolden memo evalConfig isOk dir inputFile = do
  -- The session's log is part of the golden when the file is expected NOT to
  -- linearize (@not isOk@), and a log belongs to the session that wrote it, so
  -- that case keeps its own session. Otherwise the log is dropped below and the
  -- module may come from the memo.
  (errs, moutput) <-
    if isOk
      then typeCheckedShared memo "nlg-golden" evalConfig inputFile LogNotNeeded Remember
      else typeCheckedFresh "nlg-golden" evalConfig inputFile
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

jl4JsonSchemaGolden :: CheckMemo -> JL4Lazy.EvalConfig -> String -> FilePath -> IO (Golden String)
jl4JsonSchemaGolden memo evalConfig dir inputFile = do
  (_, moutput) <- typeCheckedShared memo "schema-golden" evalConfig inputFile LogNotNeeded Remember
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
  collectDeclares (MkSection _ _ _ _ decls) =
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

checkFile :: CheckMemo -> JL4Lazy.EvalConfig -> Bool -> FilePath -> IO ()
checkFile memo evalConfig isOk file = do
  (errs, diags, (isJust -> typechecked, (mparsed, mchecked))) <- logSession "check-golden" file $ oneshotL4ActionAndDiagnostics evalConfig file \nfp -> do
    -- What @SuccessfulTypeCheck@ answered, whether or not the evaluation after
    -- it did: this is the value the goldens that only read the type-checked
    -- module can be handed instead of starting a session of their own.
    checkedRef <- liftIO (newIORef Nothing)
    parsedRef <- liftIO (newIORef Nothing)
    done <- runMaybeT do
      let uri = normalizedFilePathToUri nfp
      _        <- lift   $ Shake.addVirtualFileFromFS nfp
      parsed   <- MaybeT $ Shake.use GetParsedAst uri        <* liftIO (Text.putStrLn "Parsing successful")
      liftIO $ writeIORef parsedRef (Just parsed)
      checked  <- MaybeT $ Shake.use SuccessfulTypeCheck uri <* liftIO (Text.putStrLn "Typechecking successful")
      liftIO $ writeIORef checkedRef (Just checked)
      results' <- MaybeT $ Shake.use EvaluateLazy uri
      when (not (null results')) $ liftIO $ Text.putStrLn "Evaluation successful"
      let msgs  =    map typeErrorToMessage checked.infos
                  <> map evalLazyDirectiveResultToMessage results'
          formatted = foldMap (sanitizeFilePaths . renderMessage) $ sortOn fst msgs
      liftIO $ Text.putStr formatted
    (,) done <$> liftIO ((,) <$> readIORef parsedRef <*> readIORef checkedRef)
  writeIORef memo.slot (Just (file, mchecked))
  -- The prettyLayout round-trip comes much later in the tree and starts from
  -- the same module. Holding the MODULE of every corpus file until then also
  -- works and is as fast (measured on nye, 2026-10-18: 298 s and 345 s against
  -- 302-307 s for what is done here), but takes the run from 0.6 GB to 1.4-1.5
  -- GB resident and the collector's maximum residency from 0.17 GB to 0.43-0.49
  -- GB. So derive what that test needs now and hold only that, the printed text
  -- and the leaked-gensym list. An exception the derivation raises is held too,
  -- and raised again in the test that owns it, so a failure still lands on the
  -- prettyLayout example.
  when (file `Set.member` memo.keepFor) $
    for_ mchecked \tc -> do
      derived <- try @SomeException $ evaluate case printedOf tc of
        p@(MkPrinted printed leaked) -> rnf (printed, leaked) `seq` p
      modifyIORef' memo.kept (Map.insert file derived)
  writeIORef memo.exactPrint
    (Just (file, mparsed >>= either (const Nothing) Just . ExactPrint.exactprint))
  -- NOTE: if we're okay, we don't expect any errors, if we are not, we do expect them
  --
  -- 'typechecked' alone is not the whole verdict: a rule OTHER than the
  -- typechecker can publish an Error that 'SuccessfulTypeCheck' does not gate.
  -- 'Rules.GetImports''s unresolvable-IMPORT error is the case that forced this
  -- (smucclaw/l4-ide#971): a module that imports a module existing nowhere, and
  -- happens to reference nothing from it, typechecks -- so this suite passed it
  -- while @l4 check@ on the same file exited 1. A test harness that cannot see a
  -- whole class of error is worse than no harness for that class, because it
  -- reads as coverage.
  let success = typechecked && not (any isStructuralError diags)
  success `shouldBe` isOk
  unless success do
    Text.putStr $ foldMap sanitizeFilePaths errs

 where
  -- The same partition 'L4.Cli.Common.hasBlockingError' makes, and for the same
  -- reason: a diagnostic whose source is @eval@ is an #EVAL directive's outcome,
  -- which several corpus files deliberately expect to fail, not a structural
  -- error in the module.
  isStructuralError FileDiagnostic{fdLspDiagnostic = Diagnostic{_severity, _source}} =
    _severity == Just DiagnosticSeverity_Error && _source /= Just "eval"

  typeErrorToMessage err = (JL4.rangeOf err, JL4.prettyCheckErrorWithContext err)
  evalLazyDirectiveResultToMessage res@(JL4Lazy.MkEvalDirectiveResult r _ _ _ _ _ _) =
    (r, Text.lines (JL4Lazy.prettyEvalDirectiveResult res))
  renderMessage (r, txt) = cliErrorMessage r txt

-- | What the goldens of one corpus file share, so that the file is not parsed and
-- type-checked once per golden.
--
-- A file's goldens ("parses and checks", "exactprints", "natural language
-- annotations", "json schema") each used to start a Shake session of their own,
-- and so did the exactprint-identity and prettyLayout blocks much later. The
-- "parses and checks" golden's session now leaves what the others need. It is
-- NOT a cache of sessions: only pure values cross (a rule's result is forced to
-- normal form and carries no handle on the session that produced it).
--
-- The rule for what may be read from here is about the session's /log/. Every
-- session has its own recorder, and what it holds depends on the rules that ran
-- in the session: the check golden's session also runs @EvaluateLazy@, and its
-- log carries every #EVAL result as a diagnostic that a session which only
-- type-checks never publishes (measured 2026-10-18: 322 of the 598 files have a
-- different log in the two sessions). Some goldens print that log. A golden may
-- take a value from here only if it does not print the log, or prints it only on
-- a path that falls back to a session of its own ('LogNeed'; the exactprint
-- golden, and the nlg golden of a file expected NOT to linearize, do the same).
--
-- The per-file slots hold ONE file, keyed by path: the goldens of a file are
-- adjacent in the tree, so a slot never holds more than one file's closure, and
-- under @--match@, @--skip@ or @--randomize@ a golden whose neighbours did not
-- run simply finds another file there and starts its own session, as it always
-- did. Nothing here needs another example to have run first.
data CheckMemo = CheckMemo
  { slot :: IORef (Maybe (FilePath, Maybe TypeCheckResult))
    -- ^ what @SuccessfulTypeCheck@ answered for the last file; read by the nlg
    -- and schema goldens
  , exactPrint :: IORef (Maybe (FilePath, Maybe Text))
    -- ^ the exact-printer's output for the last file the check golden parsed,
    -- 'Nothing' when there was no parse or the printer failed (lazy: computed
    -- by the first golden that asks); read by the exactprints golden
  , kept :: IORef (Map FilePath (Either SomeException Printed))
    -- ^ for the prettyLayout round-trip, which runs long after the file's other
    -- goldens: one entry per file, taken (and so dropped) by the test that
    -- reads it. See 'checkFile'.
  , keepFor :: Set.Set FilePath
    -- ^ the files whose entry is made: none when the run is filtered
  }

newCheckMemo :: Set.Set FilePath -> IO CheckMemo
newCheckMemo keepFor = do
  slot <- newIORef Nothing
  exactPrint <- newIORef Nothing
  kept <- newIORef Map.empty
  pure CheckMemo{slot, exactPrint, kept, keepFor}

-- | Does the caller read the session's log?
data LogNeed
  = LogNotNeeded
    -- ^ it never reads it.
  | LogNeededOnFailure
    -- ^ it reads it only when there is no type-checked module.

-- | Does a golden that had to start its own session leave the answer in the slot?
data Remembers
  = Remember
    -- ^ yes: its neighbours in the tree read the same file next.
  | Forget
    -- ^ no: nothing is next to it, and holding the module would only keep a
    -- whole file's closure alive while the golden goes on to type-check
    -- /another/ module (the prettyLayout round-trip does).

-- | @SuccessfulTypeCheck@ for a file, from the memo slot when it holds this file
-- and the caller can do without the log; otherwise from a session of its own.
typeCheckedShared :: CheckMemo -> String -> JL4Lazy.EvalConfig -> FilePath -> LogNeed -> Remembers -> IO ([Text], Maybe TypeCheckResult)
typeCheckedShared memo site evalConfig inputFile logNeed remembers = do
  slot <- readIORef memo.slot
  case slot of
    Just (f, r)
      | f == inputFile, usable r -> do
          logEvent (site <> "-memo") inputFile
          pure ([], r)
    _ -> do
      (errs, r) <- typeCheckedFresh site evalConfig inputFile
      case remembers of
        Remember -> writeIORef memo.slot (Just (inputFile, r))
        Forget -> pure ()
      pure (errs, r)
  where
    usable r = case logNeed of
      LogNotNeeded -> True
      LogNeededOnFailure -> isJust r

-- | A session of its own: @SuccessfulTypeCheck@ and nothing else. This is what
-- every golden that reads the type-checked module ran before the memo existed.
typeCheckedFresh :: String -> JL4Lazy.EvalConfig -> FilePath -> IO ([Text], Maybe TypeCheckResult)
typeCheckedFresh site evalConfig inputFile =
  logSession site inputFile $ oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

cliErrorMessage :: Maybe JL4.SrcRange -> [Text] -> Text
cliErrorMessage mrange msg =
  Text.unlines
    ( JL4.prettySrcRangeM  mrange <> ":"
        : map ("  " <>) msg
    )

-- | Test-support instrumentation: with @JL4_TEST_SESSION_LOG=<file>@ set, append
-- one line per Shake session the suite starts: @site<TAB>file<TAB>seconds@.
logEvent :: String -> FilePath -> IO ()
logEvent site file = do
  mLog <- lookupEnv "JL4_TEST_SESSION_LOG"
  for_ mLog \logFile -> appendFile logFile (site <> "\t" <> file <> "\t0\n")

logSession :: String -> FilePath -> IO a -> IO a
logSession site file act = do
  mLog <- lookupEnv "JL4_TEST_SESSION_LOG"
  case mLog of
    Nothing -> act
    Just logFile -> do
      t0 <- getMonotonicTimeNSec
      r <- act
      t1 <- getMonotonicTimeNSec
      appendFile logFile (site <> "\t" <> file <> "\t" <> show (fromIntegral (t1 - t0) / 1e9 :: Double) <> "\n")
      pure r
