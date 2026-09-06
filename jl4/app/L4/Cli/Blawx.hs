-- | @l4 blawx FILE@ — compile the decision-rule subset of an L4 file to a
-- Blawx project: an import-shaped @.blawx@ fixture stream plus a sibling
-- @.pl@ dump of the concatenated s(CASP) (BLAWX-EXPORT-SPEC R1) — and
-- @l4 blawx --import FILE@, the other direction (R14).
--
-- Selection and relationalization live in the shared middle-end
-- ('L4.Relational.Lower'); classification and emission live in
-- @jl4-core@ ('L4.Blawx.Lower' / 'L4.Blawx.Emit') so the CLI and any future
-- LSP/service surface share one implementation; this module only handles
-- option parsing, loading + type checking the file, and writing the output.
--
-- Output placement: with @--output FILE@ the @.blawx@ YAML goes to FILE and
-- the s(CASP) dump to FILE with a @.pl@ extension; without it the YAML goes
-- to stdout (a sibling of stdout does not exist, so no @.pl@ is written).
-- @--scasp@ selects the s(CASP) dump instead of the YAML, to stdout or
-- @--output@. A YAML destination that itself ends @.pl@ is refused — it
-- would be its own sibling, and the dump would clobber the YAML.
--
-- __The import direction owns the YAML layer, and only the YAML layer.__
-- @jl4-core@ is cross-compiled for @wasm32-wasi@ and the @yaml@ package
-- depends on a bundled C library, so the dumpdata reader lives here (the
-- @yaml@ dependency was already in this package, for @l4 batch@) and hands
-- @L4.Blawx.Parse@ a plain record of decoded 'Text'. The YAML side must be a
-- real parser rather than a line reader: @xml_content@ is a PLAIN multi-line
-- scalar in 131 of the corpus's rows, so a spec-compliant reader folds the
-- dumper's ~80-column hard wraps back to single spaces — and a field like
-- @\<field name=\"postfix\"\>is a penguin\<\/field\>@ is split across a line
-- boundary mid-tag.
module L4.Cli.Blawx
  ( BlawxOptions(..)
  , blawxOptionsParser
  , blawxCmd
  ) where

import Control.Monad (forM_, unless, when)
import qualified Base.Text as Text
import Data.Aeson (Value (..))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.List (sort)
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import qualified Data.Yaml as Yaml
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (replaceExtension, takeBaseName, takeExtension, takeFileName)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.EvaluateLazy (EvalDirectiveResult (..))

import L4.Blawx.Blocks (BlockTree (..), toBlockTrees)
import L4.Blawx.Emit (blawxXmlGaps, renderBlawxYaml, renderPlDump)
import L4.Blawx.IR (BlawxDoc (..))
import L4.Blawx.Lift (LiftContext (..), liftBlawx, renderLiftDiag)
import L4.Blawx.Lower (lowerBlawx)
import L4.Blawx.Parse
import L4.Blawx.Xml (parseXml)
import L4.Relational.IR (renderLowerError)
import L4.Relational.Lower (defaultLowerOptions, lowerModule)

import L4.Cli.Common

data BlawxOptions = BlawxOptions
  { bxFile      :: FilePath
  , bxOutput    :: Maybe FilePath
  , bxScasp     :: Bool
  , bxImport    :: Bool
  , bxParseOnly :: Bool
  , bxReemit    :: Bool
  , bxRoundtrip :: Bool
  }

blawxOptionsParser :: Parser BlawxOptions
blawxOptionsParser = BlawxOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to compile to a Blawx project \
                                          \(or, with --import, the .blawx file to read)")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the .blawx YAML to FILE (plus the s(CASP) dump to FILE \
                   \with a .pl extension) instead of stdout"
            )
        )
  <*> switch
        ( long "scasp"
       <> help "Emit the concatenated s(CASP) dump instead of the .blawx YAML"
        )
  <*> switch
        ( long "import"
       <> help "Read a .blawx project and lift it to L4 (the other direction, R14)"
        )
  <*> switch
        ( long "parse-only"
       <> help "With --import: parse and report, without lifting. Prints one \
               \CENSUS summary line to stdout and every diagnostic to stderr"
        )
  <*> switch
        ( long "reemit"
       <> help "With --import: write the .blawx re-emitted from the parsed \
               \blocks (regenerated s(CASP) and XML) instead of the lifted L4"
        )
  <*> switch
        ( long "roundtrip"
       <> help "Self-check: emit the .blawx for FILE, parse it back, and assert \
               \that the block IR and the re-emitted bytes are unchanged"
        )

blawxCmd :: BlawxOptions -> IO ()
blawxCmd opts
  | opts.bxImport = importCmd opts
  | opts.bxRoundtrip = roundtripCmd opts
  | otherwise = exportCmd opts

-- ---------------------------------------------------------------------------
-- Export (P1/P3, unchanged)
-- ---------------------------------------------------------------------------

exportCmd :: BlawxOptions -> IO ()
exportCmd opts = do
  -- A .blawx destination named *.pl would be its own sibling dump path
  -- (replaceExtension is a fixed point there), so the YAML would be written
  -- and immediately overwritten. Refuse up front rather than clobber.
  case opts.bxOutput of
    Just f | not opts.bxScasp, takeExtension f == ".pl" -> do
      hPutStrLn stderr
        ( "l4 blawx: -o " <> f <> " without --scasp would overwrite the .blawx \
          \YAML with its own sibling s(CASP) dump; pass --scasp for the dump, \
          \or choose a non-.pl output path" )
      exitFailure
    _ -> pure ()
  doc <- loadBlawxDoc opts.bxFile
  -- A workspace or test with no Blockly image ships an empty `xml_content`
  -- beside a non-empty `scasp_encoding`: the Blawx editor draws a blank
  -- canvas for it and its first Save writes that blankness back over the rule
  -- (buttons.js:441-447 loads only `if (output_object.xml_content)`, :22-24
  -- saves `sCASP.workspaceToCode(demoWorkspace)`). That must never be silent,
  -- so say so on stderr, naming the construct.
  forM_ (blawxXmlGaps doc) \g ->
    hPutStrLn stderr
      ("l4 blawx: WARNING no Blockly image, xml_content left empty — " <> Text.unpack g)
  let source = Text.pack (takeFileName opts.bxFile)
      plDump = renderPlDump source doc
  if opts.bxScasp
    then case opts.bxOutput of
      Just f  -> Text.writeFile f plDump
      Nothing -> Text.putStr plDump
    else do
      let yaml = renderBlawxYaml doc
      case opts.bxOutput of
        Just f -> do
          Text.writeFile f yaml
          let sibling = replaceExtension f ".pl"
          Text.writeFile sibling plDump
          hPutStrLn stderr ("l4 blawx: s(CASP) dump written to " <> sibling)
        Nothing -> Text.putStr yaml
  exitSuccess

-- | Load and type-check an @.l4@ file, then lower it. Exits on failure; the
-- export path and the round-trip self-check share it.
loadBlawxDoc :: FilePath -> IO BlawxDoc
loadBlawxDoc file = do
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig file \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      -- Surface non-fatal diagnostics, but proceed: a clean type-check is the
      -- precondition that matters for lowering (the `l4 openfisca` posture).
      putDiagnostics errs
      case lowerModule defaultLowerOptions tc.entityInfo tc.module'
             >>= lowerBlawx of
        Left lerrs -> do
          putDiagnostics
            ( "l4 blawx: cannot compile these decisions to Blawx:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right doc -> pure doc

-- ---------------------------------------------------------------------------
-- Import (P5)
-- ---------------------------------------------------------------------------

importCmd :: BlawxOptions -> IO ()
importCmd opts = do
  raw <- Yaml.decodeFileEither opts.bxFile
  stream <- case raw of
    Left e -> do
      hPutStrLn stderr
        ( "l4 blawx: ERROR blawx-parse/yaml: " <> opts.bxFile <> ": "
            <> Yaml.prettyPrintParseException e )
      exitFailure
    Right v -> pure v
  (src, ywarns) <- case readBlawxSource stream of
    Left m -> do
      hPutStrLn stderr ("l4 blawx: ERROR " <> Text.unpack m)
      exitFailure
    Right ok -> pure ok
  forM_ ywarns \w -> hPutStrLn stderr ("l4 blawx: WARNING " <> Text.unpack w)
  let (mDoc, diags) = parseBlawx src
  forM_ diags \d -> hPutStrLn stderr ("l4 blawx: " <> Text.unpack (renderParseDiag d))
  let nErrs = length (filter diagIsError diags)
      nWarns = length diags - nErrs + length ywarns
  when opts.bxParseOnly $
    putStrLn (Text.unpack (censusLine (takeBaseName opts.bxFile) src diags nErrs nWarns))
  case mDoc of
    Nothing -> exitFailure
    Just doc
      | opts.bxParseOnly -> exitSuccess
      -- The Blawx-engine leg of the cross-check, and the R12 fixpoint input:
      -- the .blawx our own renderers rebuild from the parsed blocks. Its
      -- scasp_encoding is what `renderScasp` regenerates, never the stored
      -- (and usually stale) text.
      | opts.bxReemit -> do
          forM_ (blawxXmlGaps doc) \g ->
            hPutStrLn stderr
              ("l4 blawx: WARNING no Blockly image, xml_content left empty — " <> Text.unpack g)
          let yaml = renderBlawxYaml doc
          case opts.bxOutput of
            Just f -> Text.writeFile f yaml
            Nothing -> Text.putStr yaml
          exitSuccess
      | otherwise -> do
          -- The provenance header records the fixture's FILE NAME, not the
          -- path it was read from. Every Blawx fixture arrives from a local
          -- checkout of the Blawx repository, and the checkout's location is a
          -- property of the machine, not of the document: baking it in made
          -- the committed artifacts under jl4/examples/blawx/imported/
          -- regenerable byte-for-byte from ONE checkout only, and the two
          -- committed files disagreed on which (`.../blawx/...` for bird,
          -- `.../blawx-stock/...` for rps) while their inputs were byte-
          -- identical. The basename is the same from any checkout, and from a
          -- copy of the fixture anywhere else.
          let ctx =
                MkLiftContext
                  { lcSource = Text.pack (takeFileName opts.bxFile)
                  , lcNotes = importNotes src diags
                  }
          case liftBlawx ctx doc of
            Left lerrs -> do
              putDiagnostics
                ( "l4 blawx --import: cannot lift this document to L4:"
                : map (("  - " <>) . renderLiftDiag) lerrs
                )
              exitFailure
            Right (lifted, lwarns) -> do
              forM_ lwarns \w -> hPutStrLn stderr ("l4 blawx: " <> Text.unpack (renderLiftDiag w))
              -- The identity the module is checked under. With --output it is
              -- the real destination; without one it is a sibling of the input
              -- that need not exist, because the text is fed through the VFS
              -- and never read back off disk. Either way the directory is
              -- right, which is what importer-relative library resolution
              -- looks at.
              let path = fromMaybe (replaceExtension opts.bxFile ".l4") opts.bxOutput
              recorded <- recordOracles path lifted
              case opts.bxOutput of
                Just f -> Text.writeFile f recorded
                Nothing -> Text.putStr recorded
              exitSuccess

-- | Provenance lines for the lifted module's header: what the YAML and parse
-- layers saw, phrased once, here, rather than re-derived inside the lift.
importNotes :: BlawxSource -> [ParseDiag] -> [Text]
importNotes src diags =
  [ "blocks        " <> Text.textShow nBlocks <> " across "
      <> Text.textShow (Set.size tys) <> " block types"
  ]
    <> [ "WARNING       stored `scasp_encoding` is STALE against the current\n\
         \generator (P5-2) in " <> Text.textShow (length stale) <> " row(s), first " <> first' <> ".\n\
         \The XML is canonical (R14); the encodings were not used."
       | first' <- take 1 stale
       ]
 where
  stale = [d.pdRow | d <- diags, d.pdCode == "blawx-parse/stale-encoding"]
  trees =
    [ t
    | r <- src.bsWorkspaces <> src.bsTests
    , not (Text.null (Text.strip r.brwXml))
    , Right node <- [parseXml r.brwXml]
    , Right (roots, _) <- [toBlockTrees node]
    , t <- concatMap flatten roots
    ]
  flatten b =
    b : concatMap (flatten . snd) b.btValues <> concatMap (concatMap flatten . snd) b.btStmts
  nBlocks = length trees
  tys = Set.fromList (map (\t -> t.btType) trees)

-- | Record each @#EVAL@'s value as a @-- L4 oracle ==>@ line, __by running the
-- L4 engine over the module the lift just produced__ — the same evaluation
-- @l4 run@ performs, through the VFS rather than a temporary file.
--
-- Two things this is and is not. It IS the recording step P5-E1 asks for, and
-- it is what lets the re-emitted @.blawx@ run through
-- @etc\/blawx-tier1-harness.py@ with no change to how that harness finds an
-- oracle. It is NOT evidence on its own: an oracle written by the L4 engine
-- and then compared against the L4 engine proves nothing. The claim P5 makes
-- is the CROSS-engine one — this line versus s(CASP)'s answer to the same
-- query — and that comparison is the harness's, not this function's.
--
-- A module that does not typecheck is a lift bug, so it exits rather than
-- shipping an artifact nobody can run.
-- The typecheck runs even for a document that lifted to no directives at all
-- (a ruledoc whose tests carry no query block): "the artifact runs" is the
-- guarantee, and a module with nothing to evaluate can still fail to compile.
recordOracles :: FilePath -> Text -> IO Text
recordOracles path src = do
      evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
      (errs, (mTc, mEval)) <- runOneshot evalConfig path \nfp -> do
        let uri = normalizedFilePathToUri nfp
        _ <- Shake.addVirtualFile nfp src
        mtc <- Shake.use Rules.SuccessfulTypeCheck uri
        meval <- Shake.use Rules.EvaluateLazy uri
        pure (mtc, meval)
      case (mTc, mEval) of
        (Just tc, Just rs) | tc.success -> do
          -- `result` is a DuplicateRecordFields name in L4.EvaluateLazy, so
          -- there is no HasField instance for it and `.result` does not
          -- resolve; the record pattern is the way in.
          let vals = [firstLine (renderEvalValue v) | MkEvalDirectiveResult {result = v} <- rs]
              n = length [() | l <- Text.lines src, "#EVAL" `Text.isPrefixOf` l]
          unless (length vals == n) $
            hPutStrLn stderr
              ( "l4 blawx --import: WARNING the lifted module has " <> show n
                  <> " #EVAL directives but the engine returned " <> show (length vals)
                  <> " results; some oracle lines are missing" )
          pure (spliceOracles vals src)
        _ -> do
          putDiagnostics errs
          hPutStrLn stderr
            "l4 blawx --import: the lifted module does not typecheck; refusing to \
            \write an artifact that cannot be run (this is a lift bug, not a \
            \property of the input)"
          exitFailure
 where
  firstLine = Text.takeWhile (/= '\n') . Text.strip

-- | Put one @-- L4 oracle ==>@ line after each @#EVAL@ directive. A directive
-- runs to the next blank line — the lift's own layout, so this is reading its
-- own output, not guessing at L4 syntax. The harness contract is that the
-- oracle is the only thing on its line and that nothing else claiming to be a
-- directive intervenes (@etc\/blawx-tier1-harness.py:113-127@).
spliceOracles :: [Text] -> Text -> Text
spliceOracles vs0 src = Text.unlines (go vs0 (Text.lines src))
 where
  go vs (l : ls)
    | "#EVAL" `Text.isPrefixOf` l =
        let (body, rest) = span (not . Text.null) ls
        in  case vs of
              v : vs' -> (l : body) <> ["-- L4 oracle ==> " <> v] <> go vs' rest
              [] -> (l : body) <> go [] rest
    | otherwise = l : go vs ls
  go _ [] = []

-- | The machine-readable summary line the census harness reads, so it need
-- not scrape prose. @blocks@ and @types@ are counted from the block trees
-- (the layer that is total over all 47 corpus block types), not from the IR.
censusLine :: String -> BlawxSource -> [ParseDiag] -> Int -> Int -> Text
censusLine stem src diags nErrs nWarns =
  Text.unwords
    [ "CENSUS"
    , Text.pack stem
    , verdict
    , "blocks=" <> Text.textShow nBlocks
    , "types=" <> Text.textShow (Set.size tys)
    , "workspaces=" <> Text.textShow (length src.bsWorkspaces)
    , "tests=" <> Text.textShow (length src.bsTests)
    , -- rows that store an encoding at all, and how many of those the current
      -- generator no longer reproduces (P5-2). encodings-stale is therefore
      -- the number of rows our parse regenerates BYTE-EXACTLY, which is the
      -- sharpest fidelity signal the wild corpus can give.
      "encodings=" <> Text.textShow nEncodings
    , "stale=" <> Text.textShow nStale
    , "warnings=" <> Text.textShow nWarns
    , "errors=" <> Text.textShow nErrs
    ]
 where
  nEncodings =
    length [() | r <- src.bsWorkspaces <> src.bsTests, not (Text.null (Text.strip r.brwScasp))]
  nStale = length [() | d <- diags, d.pdCode == "blawx-parse/stale-encoding"]
  verdict
    | nErrs > 0 = "refused"
    | nWarns > 0 = "warnings"
    | otherwise = "clean"
  trees =
    [ t
    | r <- src.bsWorkspaces <> src.bsTests
    , not (Text.null (Text.strip r.brwXml))
    , Right node <- [parseXml r.brwXml]
    , Right (roots, _) <- [toBlockTrees node]
    , t <- concatMap flatten roots
    ]
  flatten b =
    b : concatMap (flatten . snd) b.btValues <> concatMap (concatMap flatten . snd) b.btStmts
  nBlocks = length trees
  tys = Set.fromList (map (\t -> t.btType) trees)

-- ---------------------------------------------------------------------------
-- The round-trip self-check (the `lift . emit = id` property, parse half)
-- ---------------------------------------------------------------------------

-- | @emit → parse → the SAME BlawxDoc@, run over a real document rather than
-- a hand-built fixture: lower FILE, render the whole @.blawx@ stream, read it
-- back through the YAML, XML, block and classification layers, and compare.
--
-- Two assertions, because either alone is weak. The __structural__ one is the
-- property R14 states, modulo what the import provably cannot know
-- ('stripProvenance') and modulo the stack\/run distinction the wire format
-- does not carry ('normaliseStacks'). The __byte__ one — re-emitting the
-- parsed document reproduces the original stream exactly — is what catches a
-- datum that survives into the IR but in a different spelling.
roundtripCmd :: BlawxOptions -> IO ()
roundtripCmd opts = do
  doc <- loadBlawxDoc opts.bxFile
  let yaml = renderBlawxYaml doc
  stream <- case Yaml.decodeEither' (TE.encodeUtf8 yaml) of
    Left e -> die ("re-reading our own YAML failed: " <> Text.pack (Yaml.prettyPrintParseException e))
    Right v -> pure v
  (src, ywarns) <- either (die . ("re-reading our own YAML failed: " <>)) pure (readBlawxSource stream)
  unless (null ywarns) $ die ("our own YAML warns: " <> Text.intercalate "; " ywarns)
  let (mDoc, diags) = parseBlawx src
  forM_ diags \d -> hPutStrLn stderr ("l4 blawx: " <> Text.unpack (renderParseDiag d))
  doc' <- maybe (die "parsing our own .blawx produced no document") pure mDoc
  let a = normaliseStacks (stripProvenance doc)
      b = normaliseStacks (stripProvenance doc')
  unless (a == b) $ die ("the parsed IR differs from the emitted one:\n" <> firstIrDiff a b)
  let yaml' = renderBlawxYaml doc'
  unless (yaml == yaml') $ die ("re-emission is not byte-identical:\n" <> firstLineDiff yaml yaml')
  putStrLn ("l4 blawx --roundtrip: " <> opts.bxFile <> ": IR and bytes unchanged")
  exitSuccess
 where
  die m = do
    hPutStrLn stderr ("l4 blawx --roundtrip: " <> opts.bxFile <> ": " <> Text.unpack m)
    exitFailure

-- | Name the first row that differs, so a failure points somewhere rather
-- than dumping two whole documents.
firstIrDiff :: BlawxDoc -> BlawxDoc -> Text
firstIrDiff a b =
  Text.unlines $
    take 1 $
      [ "  ruledoc name: " <> Text.textShow a.bdName <> " vs " <> Text.textShow b.bdName
      | a.bdName /= b.bdName
      ]
        <> [ "  rule text: " <> Text.textShow a.bdRuleText <> "\n         vs " <> Text.textShow b.bdRuleText
           | a.bdRuleText /= b.bdRuleText
           ]
        <> [ "  workspace " <> Text.textShow i <> ":\n    emitted: " <> Text.textShow x
               <> "\n    parsed:  " <> Text.textShow y
           | (i, x, y) <- zip3 [0 :: Int ..] a.bdWorkspaces b.bdWorkspaces
           , x /= y
           ]
        <> [ "  test " <> Text.textShow i <> ":\n    emitted: " <> Text.textShow x
               <> "\n    parsed:  " <> Text.textShow y
           | (i, x, y) <- zip3 [0 :: Int ..] a.bdTests b.bdTests
           , x /= y
           ]
        <> [ "  row counts differ: "
               <> Text.textShow (length a.bdWorkspaces, length a.bdTests)
               <> " vs "
               <> Text.textShow (length b.bdWorkspaces, length b.bdTests)
           ]

firstLineDiff :: Text -> Text -> Text
firstLineDiff x y =
  case [ (i, l, r)
       | (i, l, r) <- zip3 [1 :: Int ..] (Text.splitOn "\n" x) (Text.splitOn "\n" y)
       , l /= r
       ] of
    (i, l, r) : _ ->
      "  line " <> Text.textShow i <> "\n    emitted:   " <> l <> "\n    re-emitted: " <> r
    [] -> "  the two differ only in length"

-- ---------------------------------------------------------------------------
-- The dumpdata YAML reader
-- ---------------------------------------------------------------------------

-- | A Django @dumpdata@ stream: a flat list of @{model, pk, fields}@ rows.
-- Exactly three models occur across all 15 shipped examples —
-- @blawx.ruledoc@ 15, @blawx.workspace@ 110, @blawx.blawxtest@ 41 — and the
-- ruledoc must be row 0, because Blawx's own import view re-parents
-- positionally (@views.py:126-155@ nulls every pk and takes
-- @new_object_list[0]@ as the ruledoc). A file that violated that would not
-- import into Blawx either, so it is an error here.
readBlawxSource :: Value -> Either Text (BlawxSource, [Text])
readBlawxSource stream = do
  rows <- case stream of
    Array v -> traverse asObject (V.toList v)
    _ -> Left "blawx-parse/yaml: the .blawx stream must be a YAML list of dumpdata rows"
  tagged <- traverse rowModel (zip [1 :: Int ..] rows)
  (rdPk, rdFields) <- case tagged of
    (1, "blawx.ruledoc", o) : _ -> (,) <$> reqNumber 1 "pk" o <*> reqObject 1 "fields" o
    _ -> Left "blawx-parse/row-order: the first row must be the blawx.ruledoc"
  when (length [() | (_, m, _) <- tagged, m == "blawx.ruledoc"] /= 1) $
    Left "blawx-parse/row-order: a .blawx stream holds exactly one blawx.ruledoc"
  name <- reqText 1 "ruledoc_name" rdFields
  ruleText <- reqText 1 "rule_text" rdFields
  let akoma = optText "akoma_ntoso" rdFields
      navtree = optText "navtree" rdFields
  wss <- sequence [row i "workspace_name" o | (i, "blawx.workspace", o) <- tagged]
  tss <- sequence [row i "test_name" o | (i, "blawx.blawxtest", o) <- tagged]
  fks <-
    sequence
      [ reqNumber i "ruledoc" =<< reqObject i "fields" o
      | (i, m, o) <- tagged
      , m /= "blawx.ruledoc"
      ]
  unless (all (== rdPk) fks) $
    Left "blawx-parse/dangling-ruledoc: a row's ruledoc foreign key names no ruledoc in this file"
  pure
    ( MkBlawxSource
        { bsRuledocName = name
        , bsRuleText = ruleText
        , bsAkoma = akoma
        , bsNavtree = navtree
        , bsWorkspaces = map snd wss
        , bsTests = map snd tss
        }
    , interleaved (map fst wss) (map fst tss) <> concatMap unknownKeys tagged
    )
 where
  asObject (Object o) = Right o
  asObject _ = Left "blawx-parse/yaml: every dumpdata row must be a mapping"
  rowModel (i, o) = do
    m <- reqText i "model" o
    unless (m `elem` (["blawx.ruledoc", "blawx.workspace", "blawx.blawxtest"] :: [Text])) $
      Left ("blawx-parse/yaml: row " <> Text.textShow i <> ": unknown model " <> m)
    pure (i, m, o)
  row i nameKey o = do
    f <- reqObject i "fields" o
    n <- reqText i nameKey f
    x <- reqText i "xml_content" f
    s <- reqText i "scasp_encoding" f
    pure (i, MkBlawxRow {brwName = n, brwXml = x, brwScasp = s})
  -- Blawx's importer is positional, and the s(CASP) concatenation order and
  -- bdWorkspaces' ordering invariant both follow document order, so a file
  -- that interleaves the two models still imports — it just did not come from
  -- Blawx's own exporter.
  interleaved ws ts
    | null ws || null ts = []
    | maximum ws < minimum ts = []
    | otherwise = ["blawx-parse/row-order-interleaved: workspace and test rows interleave"]

-- | Field keys nothing reads. Reported rather than refused: erroring on an
-- unknown key would refuse a future Blawx version's export for adding one,
-- and the datum is still visible in the file.
unknownKeys :: (Int, Text, KeyMap.KeyMap Value) -> [Text]
unknownKeys (i, model, o) =
  [ "blawx-parse/unknown-field: row " <> Text.textShow i <> " (" <> model <> "): " <> k
  | k <- sort (map Key.toText (KeyMap.keys fields))
  , k `notElem` known
  ]
 where
  fields = case KeyMap.lookup (Key.fromText "fields") o of
    Just (Object f) -> f
    _ -> KeyMap.empty
  known :: [Text]
  known = case model of
    "blawx.ruledoc" ->
      ["ruledoc_name", "rule_text", "scasp_encoding", "tutorial", "owner", "published", "akoma_ntoso", "navtree", "rule_slug"]
    "blawx.workspace" -> ["ruledoc", "workspace_name", "xml_content", "scasp_encoding"]
    _ -> ["ruledoc", "test_name", "xml_content", "scasp_encoding", "tutorial", "view", "fact_scenario"]

reqObject :: Int -> Text -> KeyMap.KeyMap Value -> Either Text (KeyMap.KeyMap Value)
reqObject i k o = case KeyMap.lookup (Key.fromText k) o of
  Just (Object f) -> Right f
  _ -> Left ("blawx-parse/yaml: row " <> Text.textShow i <> ": missing or non-mapping " <> k)

reqText :: Int -> Text -> KeyMap.KeyMap Value -> Either Text Text
reqText i k o = case KeyMap.lookup (Key.fromText k) o of
  Just (String t) -> Right t
  Just Null -> Right ""
  _ -> Left ("blawx-parse/yaml: row " <> Text.textShow i <> ": missing or non-string " <> k)

optText :: Text -> KeyMap.KeyMap Value -> Maybe Text
optText k o = case KeyMap.lookup (Key.fromText k) o of
  Just (String t) -> Just t
  _ -> Nothing

reqNumber :: Int -> Text -> KeyMap.KeyMap Value -> Either Text Double
reqNumber i k o = case KeyMap.lookup (Key.fromText k) o of
  Just (Number n) -> Right (realToFrac n)
  _ -> Left ("blawx-parse/yaml: row " <> Text.textShow i <> ": missing or non-numeric " <> k)
