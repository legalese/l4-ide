-- | @l4 lts FILE [--steps] [--json] [--contract NAME]...@ — for every
-- @#TRACE@ in the file, what the contract owes after the trace's events,
-- what would discharge it, what would breach it, and the next deadline.
-- A plain list, for a reader who does not program.
--
-- This is the P2a′ list baseline of
-- @specs/todo/lexipedia-superset/LTS-VISUALISER.md@ (§1.1a, §7.2). The verb
-- is named for the view it is the first rendering of — the LTS
-- (labelled transition system) view of §2.3 — so that the picture, if
-- §7.3's gate ever lets one be built, lands on the same verb as a format
-- flag rather than as a second command a reader has to know to look for.
--
-- Every answer is the evaluator's: the list is "L4.Lts.List" over
-- "L4.Lts.WhatIf"'s replay, and this module only loads the file and
-- prints. Exits 1 on a typecheck failure or an unknown @--contract@; exits
-- 0 with a note when the file has nothing to list.
module L4.Cli.Lts
  ( LtsOptions (..)
  , ltsOptionsParser
  , ltsCmd
  ) where

import Base (catMaybes, for)
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Encode.Pretty as AesonPretty
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Lts.List
import L4.Lts.WhatIf (Rig (..), Trace (..), tracesOf)
import L4.Print (prettyLayout)
import L4.Syntax (Module, Resolved)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data LtsOptions = LtsOptions
  { ltsFile      :: FilePath
  , ltsSteps     :: Bool
  , ltsJson      :: Bool
  , ltsContracts :: [Text.Text]
  , ltsFixedNow  :: FixedNowOpt
  }

ltsOptionsParser :: Parser LtsOptions
ltsOptionsParser = LtsOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file with #TRACE directives")
  <*> switch (long "steps" <> help "Also print the step log: what the contract did with each event, in order")
  <*> switch (long "json" <> help "Print the same answers as JSON, one object per trace")
  <*> many (strOption
        ( long "contract"
        <> metavar "NAME"
        <> help "List this top-level rule at its outset (as `#TRACE NAME AT 0 WITH` with no events) instead of the file's own #TRACE directives; repeatable"
        ))
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

ltsCmd :: LtsOptions -> IO ()
ltsCmd opts = do
  evalConfig <- makeEvalConfig opts.ltsFixedNow
  (errs, mRig) <- runOneshot evalConfig opts.ltsFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use Rules.SuccessfulTypeCheck uri
    case mTc of
      Nothing -> pure Nothing
      Just tcRes -> do
        -- The base environment is the imports' heaps, exactly as the
        -- EvaluateLazy rule assembles it; the module's own heap is built by
        -- the replay, per candidate.
        imports <- Shake.use_ Rules.GetImports uri
        deps <- Shake.uses (Shake.AttachCallStack [uri] Rules.GetLazyEvaluationDependencies) (map (.moduleUri) imports)
        let env = mconcat (fst <$> catMaybes deps)
        pure $ Just MkRig
          { rigConfig = evalConfig
          , rigEntityInfo = tcRes.entityInfo
          , rigEnv = env
          , rigModule = tcRes.module'
          }
  case mRig of
    Nothing -> do
      putDiagnostics errs
      hPutStrLn stderr "Type checking failed — nothing to list"
      exitFailure
    Just rig -> do
      (rig', traces) <- selectTraces rig opts.ltsContracts
      reports <- fmap catMaybes $ for traces \tr -> do
        mr <- reportOf rig' tr
        case mr of
          Nothing -> do
            hPutStrLn stderr ("A #TRACE produced no result and is not listed: " <> Text.unpack (prettyLayout tr.trContract))
            pure Nothing
          Just r -> pure (Just r)
      if opts.ltsJson
        then BL.putStrLn (AesonPretty.encodePretty' jsonConfig (Aeson.toJSON (map (reportJson opts.ltsSteps) reports)))
        else case reports of
          [] -> TIO.putStrLn "Nothing to list: the file has no #TRACE directive. Add one (`#TRACE c AT 0 WITH`) or name a rule with --contract."
          _  -> TIO.putStr (Text.intercalate "\n" (map (renderReport opts.ltsSteps) reports))
      exitSuccess

-- | The file's own traces, or the fresh positions asked for with
-- @--contract@. An unknown name is an error, not a silent empty list.
selectTraces :: Rig -> [Text.Text] -> IO (Rig, [Trace])
selectTraces rig [] = pure (rig, tracesOf rig.rigModule)
selectTraces rig names = go rig.rigModule [] names
  where
    go :: Module Resolved -> [Trace] -> [Text.Text] -> IO (Rig, [Trace])
    go m acc [] = pure (rig {rigModule = m}, reverse acc)
    go m acc (n : ns) = case freshTrace m n of
      Left why -> do
        hPutStrLn stderr ("--contract: " <> Text.unpack why)
        exitFailure
      Right (m', tr) -> go m' (tr : acc) ns

jsonConfig :: AesonPretty.Config
jsonConfig = AesonPretty.defConfig {AesonPretty.confIndent = AesonPretty.Spaces 2, AesonPretty.confCompare = compare}
