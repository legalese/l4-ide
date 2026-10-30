-- | @l4 explore FILE [--contract NAME [--at T]] [--until T] [--json | --dot]
-- [--always P] [--reachable P] [--stays P] [--eventually P [--if-always Q]]
-- [--unwritten CELL]… [--emit DIR [--fair NAME]…]@
-- — every position a contract can reach, as an explicit labelled
-- transition system: the states, the events between them, and a coverage
-- line that says how much of the contract that is; and, when properties are
-- named, whether each holds on it; and, with @--emit@, the graph written
-- for mCRL2, TLC, NuSMV, GraphViz and a Petri net tool.
--
-- This is work packages WP1, WP2 and WP3 of
-- @specs/proposals/REGULATIVE-LOWERING-SPEC.md@ (§4, §5, §6.1): the graph is
-- "L4.Lts.Explore" iterating "L4.Lts.WhatIf"'s replay, so every edge is the
-- evaluator's own answer; the checks are "L4.Lts.Explore.Check", the
-- emitted files "L4.Lts.Explore.Emit", and this module only loads the file,
-- prints and writes.
--
-- @--emit DIR@ writes, per contract explored, @<base>.aut@, @<base>.tla@
-- with @<base>.cfg@ and one @<base>.<property>.cfg@ per property,
-- @<base>.smv@, @<base>.dot@ and @<base>.pnml@ into @DIR@, where @<base>@
-- is the file's stem as an identifier (@d1-naive.l4@ gives @d1_naive@). The
-- properties named are emitted as the predicates and properties of the
-- TLA+ and NuSMV models. @--fair NAME@ names an actor whose acts that move
-- are given weak fairness in them; no other act is, so a liveness property
-- that needs fairness fails, loudly, until the agent is named (see
-- "L4.Lts.Explore.Emit.Model" for why the default is none). A @--fair@ that
-- names no act of any graph explored is an option that names nothing.
--
-- A property is a boolean decision of the file or a file it imports, named
-- by a flag that says its class (the spec's @--check@: L4 has no syntax for
-- the class, so the flag carries it). The cells the properties read are
-- kept in the state whether or not a @RECALL@ in the file reads them, as
-- @--keep@ and @--keep-latest@ would keep them.
--
-- Two rules follow from what a run's observers are (REGULATIVE-LOWERING-SPEC
-- §4.1; ruled 2026-10-26). A property input named for a cell that no literal
-- @RECORD@, @COMMIT@ or @ATTEST@ of the file or its imports writes is
-- refused, exit 1, naming the property and the cell: the cell is empty in
-- every state, which a misspelt input would give too, and nothing else
-- says which it is. @--unwritten CELL@ says the cell is written by
-- something the text cannot show, or is legitimately empty in this design
-- (one set of properties serves several), and lifts the refusal for that
-- cell alone. And @--emit@ with no property named keeps, in the state, the
-- cell every property-shaped rule of the file and its imports reads, since
-- the emitted model goes to a consumer whose properties this run cannot
-- see; the cells are listed on stderr. A run with neither @--emit@ nor a
-- property keeps only what the rules read, as before.
--
-- Exit status, so that a CI job cannot read an incomplete run, or an
-- unanswered check, as green (§4.2): 0 when the frontier was exhausted with
-- nothing refused and nothing untried, and every property named holds; 1
-- when the file does not type-check, an option names nothing (a property
-- among them), or a contract cannot be run at its outset; 4 when a property
-- is violated (its counterexample is printed, and is real whatever else the
-- run did); 2 when an act was refused (a variable of a type with no finite
-- set of values) or a candidate could not be tried; 3 when nothing was
-- refused or untried but the depth or state bound stopped the exploration;
-- 5 when the exploration was complete but a property's verdict is unknown
-- (every liveness property; a state that could not be labelled). A tick
-- past @--until@ is outside the exploration asked for, not a failure of
-- it: it is counted on the coverage line and does not change the status.
-- With @--emit@, a file that could not be written, or could not be written
-- faithfully (an @.aut@ label mCRL2 would merge with another), makes the
-- status 1; the other files are written all the same.
--
-- An executable built with "L4.Cli.Extensions" can add files to what @--emit@
-- writes: each 'EmitTarget' is given the same 'EmitInput' as the built-in
-- emitters and its files follow theirs, written, reported and counted in the
-- exit status in the same way. A file name already written is refused.
module L4.Cli.Explore
  ( ExploreCliOptions (..)
  , PropertyFlag (..)
  , exploreOptionsParser
  , exploreCmd
    -- * For an extension that runs its own checks over an explored graph
  , requestsOf
  , statusOf
  , importedModules
  ) where

import Base (catMaybes, for, for_, unless, when)
import Control.Monad (foldM)
import Data.Char (isDigit)
import Data.Either (lefts, rights)
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encode.Pretty as AesonPretty
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.List as List
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Directory (createDirectoryIfMissing)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>), takeBaseName, takeFileName)
import System.IO (hPutStrLn, stderr)

import Development.IDE.Graph (Action)
import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (NormalizedUri, normalizedFilePathToUri)

import L4.Lts.Explore
import L4.Lts.Explore.Check
import L4.Lts.Explore.Emit
import L4.EvaluateLazy (EvalConfig, EvalDirectiveResult (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Lts.WhatIf (Rig (..))
import L4.Syntax (Module, Resolved)

import L4.Cli.Common
import L4.Cli.Extensions (EmitTarget (..), TargetOptions, emitNameProblem)

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data ExploreCliOptions = ExploreCliOptions
  { exFile      :: FilePath
  , exContracts :: [Text.Text]
  , exAt        :: Rational
  , exUntil     :: Maybe Rational
  , exMaxDepth  :: Int
  , exMaxStates :: Int
  , exMaxActs   :: Int
  , exGrid      :: Maybe Rational
  , exKeep      :: [Text.Text]
  , exKeepLatest :: [Text.Text]
  , exUnwritten :: [Text.Text]
  , exProperties :: [PropertyFlag]
  , exJson      :: Bool
  , exDot       :: Bool
  , exEmit      :: Maybe FilePath
  , exFair      :: [Text.Text]
  , exFixedNow  :: FixedNowOpt
  , exTargets   :: [Text.Text]
    -- ^ @--target@: the extension targets whose files @--emit@ writes; none
    -- named is all of them. Always empty without extension targets.
  , exTargetOpts :: [(Text.Text, Text.Text, Text.Text)]
    -- ^ @--target-opt NAME.KEY=VALUE@, as (NAME, KEY, VALUE)
  }

-- | One property flag, in the order given: an @--if-always@ is the premise
-- of the @--eventually@ before it.
data PropertyFlag
  = FlagProperty PropertyKind Text.Text
  | FlagIfAlways Text.Text

-- | The targets are those of the executable's 'Extensions', for @--emit@'s help.
exploreOptionsParser :: [EmitTarget] -> Parser ExploreCliOptions
exploreOptionsParser targets = ExploreCliOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file")
  <*> many (strOption
        ( long "contract"
        <> metavar "NAME"
        <> help "Explore this rule (one that takes no inputs) from its outset, instead of the contracts the file's #TRACE directives name; repeatable"
        ))
  <*> option rationalReader
        ( long "at"
        <> metavar "T"
        <> value 0
        <> help "With --contract: the instant the contract starts at, as a #TRACE's AT (default 0)"
        )
  <*> optional (option rationalReader
        ( long "until"
        <> metavar "T"
        <> help "Bound the clock: no event later than T. A tick past T is not taken, and is counted on the coverage line"
        ))
  <*> option auto
        ( long "max-depth"
        <> metavar "N"
        <> value defaultExploreOptions.eoMaxDepth
        <> help "Expand no state reached by more than N events (default 100)"
        )
  <*> option auto
        ( long "max-states"
        <> metavar "N"
        <> value defaultExploreOptions.eoMaxStates
        <> help "Add no more than N states (default 10000)"
        )
  <*> option auto
        ( long "max-acts"
        <> metavar "N"
        <> value defaultExploreOptions.eoMaxActs
        <> help "Refuse a variable whose type names more than N acts (default 4096)"
        )
  <*> optional (option rationalReader
        ( long "grid"
        <> metavar "N"
        <> help "Fire acts on a grid of N and keep the clock in the state, for a guard that reads the clock arithmetically; sound only when every event time and deadline is a multiple of N"
        ))
  <*> many (strOption
        ( long "keep"
        <> metavar "CELL"
        <> help "Keep this ledger cell's whole history in the state although no RECALL in the file reads it (a cell a property reads as a LIST); repeatable"
        ))
  <*> many (strOption
        ( long "keep-latest"
        <> metavar "CELL"
        <> help "Keep this ledger cell's latest entry in the state although no RECALL in the file reads it (a cell a property reads as a MAYBE); repeatable"
        ))
  <*> many (strOption
        ( long "unwritten"
        <> metavar "CELL"
        <> help "A property input named for this cell is not refused although no RECORD, COMMIT or ATTEST in the file or its imports writes it: the cell is written by something the text cannot show, or is empty by design in this file; repeatable"
        ))
  <*> many (asum
        [ FlagProperty Always <$> strOption
            ( long "always" <> metavar "P"
            <> help "Check that the boolean decision P is TRUE in every reachable state (safety); a counterexample is printed as a #TRACE. Repeatable, as are the three below")
        , FlagProperty Reachable <$> strOption
            ( long "reachable" <> metavar "P"
            <> help "Check that P is TRUE in some reachable state; the witness is printed as a #TRACE")
        , FlagProperty Stays <$> strOption
            ( long "stays" <> metavar "P"
            <> help "Check that no step goes from a state where P is TRUE to one where it is FALSE (once true, always true)")
        , FlagProperty Eventually <$> strOption
            ( long "eventually" <> metavar "P"
            <> help "Label the states with P, a liveness property; its verdict is unknown here, for a model checker to decide")
        , FlagIfAlways <$> strOption
            ( long "if-always" <> metavar "Q"
            <> help "After --eventually P: the property is that if Q is always TRUE, P is eventually TRUE")
        ])
  <*> switch (long "json" <> help "Print the graph as JSON, one object per contract explored")
  <*> switch (long "dot" <> help "Print the graph in GraphViz's DOT language")
  <*> optional (strOption
        ( long "emit"
        <> metavar "DIR"
        <> help ("Write the graph into DIR for other tools: <base>.aut (mCRL2), <base>.tla with <base>.cfg and one cfg per property (TLC), <base>.smv (NuSMV), <base>.dot, <base>.pnml; the properties named become the models' predicates and properties"
             <> extensionFiles)
        ))
  <*> many (strOption
        ( long "fair"
        <> metavar "NAME"
        <> help "With --emit: give weak fairness, in the TLA+ and NuSMV models, to every act of this actor that moves (a party, an act's constructor, or the first words of a constructor's name, as Alice in `Alice buys dinner`). No other act is fair; repeatable"
        ))
  <*> fixedNowParser
  -- the flags exist only where there is a target to choose, so that the
  -- community edition's help is the same as before they were added
  <*> (if null targets then pure [] else many (strOption
        ( long "target"
        <> metavar "NAME"
        <> help ("With --emit: write only the files of this extension target, not every target's (" <> names <> "); repeatable")
        )))
  <*> (if null targets then pure [] else many (option (eitherReader targetOptReader)
        ( long "target-opt"
        <> metavar "NAME.KEY=VALUE"
        <> help "With --emit: give the extension target NAME the option KEY with value VALUE; repeatable"
        )))
  where
    names = List.intercalate ", " [ t.etName | t <- targets ]
    -- empty in the community build, where the help is the built-in files alone
    extensionFiles = case targets of
      [] -> ""
      _ -> "; and, in this edition, the files of: " <> names

-- | @NAME.KEY=VALUE@: the name ends at the first dot, the key at the first
-- equals sign after it, and the value is the rest.
targetOptReader :: String -> Either String (Text.Text, Text.Text, Text.Text)
targetOptReader s = case break (== '=') s of
  (lhs, '=' : val) | (name, '.' : key) <- break (== '.') lhs, not (null name), not (null key) ->
    Right (Text.pack name, Text.pack key, Text.pack val)
  _ -> Left ("expected NAME.KEY=VALUE, got " <> s)

-- | A number as a @#TRACE@ writes one: digits, an optional fraction.
rationalReader :: ReadM Rational
rationalReader = eitherReader \ s -> case break (== '.') s of
  (whole, "") | ok whole -> Right (fromInteger (read whole))
  (whole, '.' : frac) | ok whole, ok frac ->
    Right (fromInteger (read whole) + fromInteger (read frac) / (10 ^ length frac))
  _ -> Left ("not a number: " <> s)
  where
    ok t = not (null t) && all isDigit t

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

exploreCmd :: [EmitTarget] -> ExploreCliOptions -> IO ()
exploreCmd targets opts = do
  when (opts.exJson && opts.exDot) do
    hPutStrLn stderr "--json and --dot are two renderings of one graph: choose one"
    exitWith (ExitFailure 1)
  case opts.exEmit of
    Nothing | not (null opts.exFair) -> do
      hPutStrLn stderr "--fair says which acts the emitted models assume fair, so it needs --emit DIR"
      exitWith (ExitFailure 1)
    _ -> pure ()
  selected <- selectTargets targets opts
  evalConfig <- makeEvalConfig opts.exFixedNow
  (errs, mLoaded) <- runOneshot evalConfig opts.exFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use Rules.SuccessfulTypeCheck uri
    case mTc of
      Nothing -> pure Nothing
      Just tcRes -> do
        -- the base environment is the imports' heaps, exactly as `l4 lts`
        -- assembles it; the module's own heap is built by every replay
        imports <- Shake.use_ Rules.GetImports uri
        deps <- Shake.uses (Shake.AttachCallStack [uri] Rules.GetLazyEvaluationDependencies) (map (.moduleUri) imports)
        let env = mconcat (fst <$> catMaybes deps)
        -- every module imported, transitively, for the RECALL sites (§4.1)
        imported <- importedModules (Set.singleton uri) (map (.moduleUri) imports)
        pure $ Just
          ( MkRig
              { rigConfig = evalConfig
              , rigEntityInfo = tcRes.entityInfo
              , rigEnv = env
              , rigModule = tcRes.module'
              }
          , imported )
  case mLoaded of
    Nothing -> do
      putDiagnostics errs
      hPutStrLn stderr "Type checking failed — nothing to explore"
      exitWith (ExitFailure 1)
    Just (rig, imported) -> do
      starts <- case opts.exContracts of
        [] -> pure (startsOf rig.rigModule)
        names -> for names \ n -> case startNamed rig.rigModule n opts.exAt of
          Left why -> do
            hPutStrLn stderr ("--contract: " <> Text.unpack why)
            exitWith (ExitFailure 1)
          Right s -> pure s
      when (null starts) do
        TIO.putStrLn "Nothing to explore: the file has no #TRACE directive. Add one (`#TRACE c AT 0 WITH`) or name a rule with --contract."
        -- a property, an --emit or a --fair was asked for and none can be
        -- answered, so a CI job must not read this as green
        let asked = not (null opts.exProperties) || not (null opts.exEmit) || not (null opts.exFair)
        when asked do
          hPutStrLn stderr "Nothing was checked, written or made fair: --always, --reachable, --stays, --eventually, --emit and --fair need something to explore."
        exitWith (if asked then ExitFailure 1 else ExitSuccess)
      requests <- either (\ why -> hPutStrLn stderr why >> exitWith (ExitFailure 1)) pure (requestsOf opts.exProperties)
      props <- for requests \ rq -> case resolveProperty rig.rigEntityInfo (rig.rigModule : imported) rq of
        Left why -> do
          hPutStrLn stderr ("--" <> Text.unpack (kindWord rq.rqKind) <> " " <> Text.unpack rq.rqName <> ": " <> Text.unpack why)
          exitWith (ExitFailure 1)
        Right p -> pure p
      -- an input named for a cell nothing writes is empty in every state,
      -- as a misspelt one would be: refused, unless the cell is named (§4.1, A)
      case unwrittenInputs opts.exUnwritten props of
        [] -> pure ()
        bad -> do
          for_ bad \ (request, cell) -> hPutStrLn stderr
            ("--" <> Text.unpack request <> ": its input `" <> Text.unpack cell <> "` is named for a cell that no RECORD, COMMIT or ATTEST in the file or its imports writes, "
              <> "so it is empty in every state, as a misspelt input would be. If the name is wrong, correct it; if the cell is written by something the text cannot show, "
              <> "or is empty by design in this file, say so with --unwritten '" <> Text.unpack cell <> "'")
          exitWith (ExitFailure 1)
      -- an emitted model goes to a consumer whose properties this run cannot
      -- see: with none named, keep what every property of the modules reads (§4.1, A+)
      let emitCells = case opts.exEmit of
            Just _ | null props -> allPropertyCells rig.rigEntityInfo (rig.rigModule : imported)
            _ -> []
      unless (null emitCells) $
        hPutStrLn stderr ("--emit with no property named keeps, in the state, every cell a property of the file or its imports reads: "
          <> Text.unpack (Text.intercalate ", " [ "`" <> c <> "`" | c <- Set.toList (Set.fromList (map fst emitCells)) ]))
      let sites = keepCells ([ (c, True) | c <- opts.exKeep ] <> [ (c, False) | c <- opts.exKeepLatest ] <> propertyCells props <> emitCells)
                    (readSitesOf rig.rigModule imported)
          options = defaultExploreOptions
            { eoMaxDepth = opts.exMaxDepth
            , eoMaxStates = opts.exMaxStates
            , eoUntil = opts.exUntil
            , eoTime = maybe Regions Grid opts.exGrid
            , eoMaxActs = opts.exMaxActs
            }
      results <- for starts \ s -> explore options sites rig s
      graphs <- fmap catMaybes $ for (zip starts results) \ (s, r) -> case r of
        Left why -> do
          hPutStrLn stderr (Text.unpack s.stName <> ": " <> Text.unpack why)
          pure Nothing
        Right g -> pure (Just g)
      checked <- for graphs \ g -> if null props
        then pure (g, [], mempty)
        else do
          original <- TIO.readFile opts.exFile
          (rs, labels) <- checkGraph options rig (Just (sourceReplay evalConfig opts.exFile original)) g props
          pure (g, rs, labels)
      -- a --fair that names no act is a typo, and a typo here would leave
      -- the agent unfair without a word
      case [ n | n <- opts.exFair, not (any (\ (g, _, _) -> fairMatches g n) checked) ] of
        [] -> pure ()
        bad -> do
          for_ bad \ n -> hPutStrLn stderr ("--fair " <> Text.unpack n
            <> ": names no party, no act's constructor, and no first words of a constructor's name, of any act in the graph explored")
          exitWith (ExitFailure 1)
      if opts.exJson
        then BL.putStrLn (AesonPretty.encodePretty' jsonConfig (Aeson.toJSON
               [ if null props then graphJson g else checksJson g rs labels (graphJson g) | (g, rs, labels) <- checked ]))
        else if opts.exDot
          then TIO.putStr (Text.intercalate "\n" (map graphDot graphs))
          else TIO.putStr (Text.intercalate "\n" [ if null props then renderGraph g else checkedText g rs | (g, rs, _) <- checked ])
      -- JSON and DOT carry the coverage inside them; the line goes to
      -- stderr as well, so a run piped into a checker still says, where a
      -- person will see it, how much it covered, and what the checks found
      when (opts.exJson || opts.exDot) $
        for_ checked \ (g, rs, _) -> do
          unless (null rs) $ TIO.hPutStrLn stderr (checksSummary rs)
          TIO.hPutStrLn stderr (coverageLine g.gCoverage)
      emitted <- maybe (pure True) (\ dir -> emitAll selected dir opts props checked) opts.exEmit
      exitWith if emitted
        then statusOf (length graphs < length starts) [ (g.gCoverage, map (.crVerdict) rs) | (g, rs, _) <- checked ]
        else ExitFailure 1

-- | The extension targets this run writes the files of, each with its options.
-- A @--target@ or @--target-opt@ that cannot be honoured is refused, exit 1:
-- a name that is no target would otherwise leave a typo silently unwritten.
selectTargets :: [EmitTarget] -> ExploreCliOptions -> IO [(EmitTarget, TargetOptions)]
selectTargets targets opts = do
  let refuse why = hPutStrLn stderr why >> exitWith (ExitFailure 1)
      known = [ Text.pack t.etName | t <- targets ]
      listed = Text.unpack (Text.intercalate ", " known)
      chosen n = null opts.exTargets || n `elem` opts.exTargets
  when ((not (null opts.exTargets) || not (null opts.exTargetOpts)) && null opts.exEmit) $
    refuse "--target and --target-opt choose among the files --emit writes, so they need --emit DIR"
  for_ opts.exTargets \ n -> unless (n `elem` known) $
    refuse ("--target " <> Text.unpack n <> ": names no emit target; this edition has: " <> listed)
  for_ (zip [0 :: Int ..] opts.exTargetOpts) \ (i, (n, k, v)) -> do
    let shown = "--target-opt " <> Text.unpack n <> "." <> Text.unpack k <> "=" <> Text.unpack v <> ": "
    unless (n `elem` known) $ refuse (shown <> "names no emit target; this edition has: " <> listed)
    unless (chosen n) $ refuse (shown <> "--target leaves out " <> Text.unpack n <> ", so the option would be ignored")
    when (any (\ (n', k', _) -> n' == n && k' == k) (take i opts.exTargetOpts)) $
      refuse (shown <> "this option is given twice")
  pure [ (t, Map.fromList [ (k, v) | (n, k, v) <- opts.exTargetOpts, n == Text.pack t.etName ])
       | t <- targets, chosen (Text.pack t.etName) ]

-- | Write every emitted file of every graph into the directory, and say on
-- stderr what was written and what was not. 'False' when a file was not.
emitAll :: [(EmitTarget, TargetOptions)] -> FilePath -> ExploreCliOptions -> [Property] -> [(Graph, [CheckResult], Labels)] -> IO Bool
emitAll selected dir opts props checked = do
  createDirectoryIfMissing True dir
  let stem = Text.pack (takeBaseName opts.exFile)
  (oks, _) <- foldM (\ (acc, taken) (k, (g, _, labels)) -> do
    let input = MkEmitInput
          { eiBase = emitBase stem (length checked) k
          , eiSource = Text.pack (takeFileName opts.exFile)
          , eiGraph = g
          , eiProperties = props
          , eiLabels = labels
          , eiFair = opts.exFair
          }
        (files, taken') = withTargets taken (emitFiles input) [ (t.etName, t.etFiles o input) | (t, o) <- selected ]
    for_ (rights files) \ (name, text) -> TIO.writeFile (dir </> Text.unpack name) text
    for_ (lefts files) \ why -> TIO.hPutStrLn stderr ("--emit: not written: " <> why)
    unless (null (rights files)) $
      TIO.hPutStrLn stderr ("Emitted to " <> Text.pack dir <> ": " <> Text.intercalate ", " (map fst (rights files)))
    pure (null (lefts files) : acc, taken')) ([], []) (zip [1 ..] checked)
  pure (and oks)

-- | The file names written so far in a run: case-folded, with the name as it
-- was written and who wrote it.
type Taken = [(Text.Text, (Text.Text, Text.Text))]

-- | The built-in files, then the selected extension targets' (see
-- "L4.Cli.Extensions"), each target's results after its name. A target's file
-- is refused, with the target and file named, and not written if its name
-- could leave the directory ('emitNameProblem') or is the same file, ignoring
-- case, as one written earlier in the run by a built-in emitter or another
-- target (the file systems of macOS and Windows do not tell them apart). With
-- no targets the files are the built-in ones unchanged.
withTargets
  :: Taken
  -> [Either Text.Text (Text.Text, Text.Text)]
  -> [(String, [Either Text.Text (Text.Text, Text.Text)])]
  -> ([Either Text.Text (Text.Text, Text.Text)], Taken)
withTargets taken0 builtin targets = (builtin <> extra, taken')
  where
    (extra, taken') = go ([ (Text.toCaseFold n, (n, "a built-in emitter")) | (n, _) <- rights builtin ] <> taken0)
                         [ (who, r) | (who, rs) <- targets, r <- rs ]
    go taken [] = ([], taken)
    go taken ((who, r) : rest) =
      let here = "target " <> Text.pack who
          refused why = let (more, t) = go taken rest in (Left (here <> ": " <> why) : more, t)
      in case r of
        Left why -> refused why
        Right (name, text)
          | Just why <- emitNameProblem name -> refused ("file `" <> name <> "`: " <> why <> "; not written")
          | Just (_, (earlier, by)) <- List.find ((== Text.toCaseFold name) . fst) taken ->
              refused ("file `" <> name <> "` is the same file as `" <> earlier <> "`, written by " <> by
                <> " (names are compared without regard to case); not written over it")
          | otherwise ->
              let (more, t) = go ((Text.toCaseFold name, (name, here)) : taken) rest
              in (Right (name, text) : more, t)

-- | Run a @#TRACE@, given as source, appended to the file explored: a
-- virtual file beside it, so that its imports resolve as the file's own do,
-- and with the file's own directives in it, run too and set aside. The
-- trace's result is the one whose directive starts below the file's last
-- line. This is how a counterexample is run as what it is printed as
-- ("L4.Lts.Explore.Check", 'SourceReplay').
sourceReplay :: EvalConfig -> FilePath -> Text.Text -> SourceReplay
sourceReplay evalConfig path original trace = do
  let src = original <> (if "\n" `Text.isSuffixOf` original then "" else "\n") <> "\n" <> trace
      below = length (Text.lines original)
  (errs, mres) <- runOneshot evalConfig (path <> ".explore-replay.l4") \ nfp -> do
    _ <- Shake.addVirtualFile nfp src
    Shake.use Rules.EvaluateLazy (normalizedFilePathToUri nfp)
  pure case mres of
    Nothing -> Left ("did not type-check: " <> Text.intercalate "; " (take 3 errs))
    Just results -> case [ l | MkEvalDirectiveResult {range = Just MkSrcRange {start = MkSrcPos {line = n}}, ledger = l} <- results, n > below ] of
      [l] -> Right l
      ls -> Left ("gave " <> Text.pack (show (length ls)) <> " results below the file's own text, not one")

-- | With properties named, the text is the graph's heading, the checks,
-- and the coverage line last; the states and transitions are what a run
-- without them prints.
checkedText :: Graph -> [CheckResult] -> Text.Text
checkedText g rs = Text.unlines $
  take 1 (Text.lines (renderGraph g))
  <> [""] <> renderChecks g rs
  <> ["", coverageLine g.gCoverage]

-- | The flags, paired: each @--if-always@ with the @--eventually@ before it.
requestsOf :: [PropertyFlag] -> Either String [Request]
requestsOf = go
  where
    go = \ case
      [] -> Right []
      FlagProperty Eventually p : FlagIfAlways q : rest -> (MkRequest Eventually p (Just q) :) <$> go rest
      FlagProperty k p : rest -> (MkRequest k p Nothing :) <$> go rest
      FlagIfAlways q : _ -> Left ("--if-always " <> Text.unpack q <> ": it is the premise of an --eventually, and must come straight after one")


-- | The exit status of the whole run (see the module header).
statusOf :: Bool -> [(Coverage, [Verdict])] -> ExitCode
statusOf startFailed runs
  | startFailed = ExitFailure 1
  | any (any ((== "violated") . verdictWord)) verdicts = ExitFailure 4
  | any (\ cv -> not (null cv.cvRefused) || not (null cv.cvUntried)) cvs = ExitFailure 2
  | any (\ cv -> not (null cv.cvStops)) cvs = ExitFailure 3
  | any (any ((== "unknown") . verdictWord)) verdicts = ExitFailure 5
  | otherwise = ExitSuccess
  where
    cvs = map fst runs
    verdicts = map snd runs

-- | The resolved modules of every import, transitively, each once.
importedModules :: Set.Set NormalizedUri -> [NormalizedUri] -> Action [Module Resolved]
importedModules seen = \ case
  [] -> pure []
  (u : us)
    | Set.member u seen -> importedModules seen us
    | otherwise -> do
        mTc <- Shake.use Rules.SuccessfulTypeCheck u
        next <- maybe (pure []) (const (map (.moduleUri) <$> Shake.use_ Rules.GetImports u)) mTc
        rest <- importedModules (Set.insert u seen) (us <> next)
        pure (maybe rest (\ tc -> tc.module' : rest) mTc)

jsonConfig :: AesonPretty.Config
jsonConfig = AesonPretty.defConfig {AesonPretty.confIndent = AesonPretty.Spaces 2, AesonPretty.confCompare = compare}
