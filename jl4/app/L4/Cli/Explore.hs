-- | @l4 explore FILE [--contract NAME [--at T]] [--until T] [--json | --dot]@
-- — every position a contract can reach, as an explicit labelled
-- transition system: the states, the events between them, and a coverage
-- line that says how much of the contract that is.
--
-- This is work package WP1 of
-- @specs/proposals/REGULATIVE-LOWERING-SPEC.md@ (§4): the graph is
-- "L4.Lts.Explore" iterating "L4.Lts.WhatIf"'s replay, so every edge is the
-- evaluator's own answer, and this module only loads the file and prints.
--
-- Exit status, so that a CI job cannot read an incomplete run as green
-- (§4.2): 0 when the frontier was exhausted with nothing refused and
-- nothing untried; 1 when the file does not type-check, an option names
-- nothing, or a contract cannot be run at its outset; 2 when an act was
-- refused (a variable of a type with no finite set of values) or a
-- candidate could not be tried; 3 when nothing was refused or untried but
-- the depth or state bound stopped the exploration. A tick past @--until@
-- is outside the exploration asked for, not a failure of it: it is counted
-- on the coverage line and does not change the status.
module L4.Cli.Explore
  ( ExploreCliOptions (..)
  , exploreOptionsParser
  , exploreCmd
  ) where

import Base (catMaybes, for, when)
import Data.Char (isDigit)
import qualified Base.Set as Set
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encode.Pretty as AesonPretty
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)

import Development.IDE.Graph (Action)
import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (NormalizedUri, normalizedFilePathToUri)

import L4.Lts.Explore
import L4.Lts.WhatIf (Rig (..))
import L4.Syntax (Module, Resolved)

import L4.Cli.Common

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
  , exJson      :: Bool
  , exDot       :: Bool
  , exFixedNow  :: FixedNowOpt
  }

exploreOptionsParser :: Parser ExploreCliOptions
exploreOptionsParser = ExploreCliOptions
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
  <*> switch (long "json" <> help "Print the graph as JSON, one object per contract explored")
  <*> switch (long "dot" <> help "Print the graph in GraphViz's DOT language")
  <*> fixedNowParser

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

exploreCmd :: ExploreCliOptions -> IO ()
exploreCmd opts = do
  when (opts.exJson && opts.exDot) do
    hPutStrLn stderr "--json and --dot are two renderings of one graph: choose one"
    exitWith (ExitFailure 1)
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
        exitWith ExitSuccess
      let sites = keepCells ([ (c, True) | c <- opts.exKeep ] <> [ (c, False) | c <- opts.exKeepLatest ]) (readSitesOf rig.rigModule imported)
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
      if opts.exJson
        then BL.putStrLn (AesonPretty.encodePretty' jsonConfig (Aeson.toJSON (map graphJson graphs)))
        else if opts.exDot
          then TIO.putStr (Text.intercalate "\n" (map graphDot graphs))
          else TIO.putStr (Text.intercalate "\n" (map renderGraph graphs))
      -- JSON and DOT carry the coverage inside them; the line goes to
      -- stderr as well, so a run piped into a checker still says, where a
      -- person will see it, how much it covered
      when (opts.exJson || opts.exDot) $
        mapM_ (\ g -> TIO.hPutStrLn stderr (coverageLine g.gCoverage)) graphs
      exitWith (statusOf (length graphs < length starts) (map (.gCoverage) graphs))

-- | The exit status of the whole run (see the module header).
statusOf :: Bool -> [Coverage] -> ExitCode
statusOf startFailed cvs
  | startFailed = ExitFailure 1
  | any (\ cv -> not (null cv.cvRefused) || not (null cv.cvUntried)) cvs = ExitFailure 2
  | any (\ cv -> not (null cv.cvStops)) cvs = ExitFailure 3
  | otherwise = ExitSuccess

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
