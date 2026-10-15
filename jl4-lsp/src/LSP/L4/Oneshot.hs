module LSP.L4.Oneshot where

import qualified LSP.Core.FileStore as Store
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Location (normalizeFilePath)
import LSP.Logger (Pretty, Recorder, WithPriority, cmapWithPrio, makeRefRecorder, pretty)

import qualified LSP.L4.Rules as Rules

import Base.Text (Text)
import Control.Concurrent.STM (atomically)
import Development.IDE.Graph (Action)
import Development.IDE.Graph.Database (shakeRunDatabase)
import Language.LSP.Protocol.Types (NormalizedFilePath)
import LSP.Core.Types.Diagnostics (FileDiagnostic)
import System.FilePath

import L4.EvaluateLazy (EvalConfig)

data Log
  = ShakeLog Shake.Log
  | RulesLog Rules.Log
  | StoreLog Store.Log

instance Pretty Log where
  pretty = \ case
    ShakeLog l -> pretty l
    RulesLog l -> pretty l
    StoreLog l -> pretty l

oneshotL4ActionAndErrors :: EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO ([Text], b)
oneshotL4ActionAndErrors = oneshotL4ActionAndErrorsIn Rules.AmbientLibraries

-- | 'oneshotL4ActionAndErrors' under a chosen 'Rules.LibraryScope'. A host that
-- serves bundles somebody else uploaded asks for 'Rules.EmbeddedStdlibOnly', so
-- that nothing on the host can stand in for the stdlib.
oneshotL4ActionAndErrorsIn :: Rules.LibraryScope -> EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO ([Text], b)
oneshotL4ActionAndErrorsIn scope evalConfig fp act = do
  (getLog, recorder) <- fmap (cmapWithPrio pretty) <$> makeRefRecorder
  res <- oneshotL4ActionIn scope recorder evalConfig fp act
  errs <- getLog
  pure (errs, res)

-- | 'oneshotL4ActionAndErrors' plus the structured diagnostics.
--
-- The rendered @[Text]@ is a log, so a caller reading it can only pattern-match
-- on wording; the @[FileDiagnostic]@ carries severity and source. A host that
-- serves bundles somebody else uploaded uses it to say why a file of one did
-- not parse: that file has no check result, and the reason is only here.
oneshotL4ActionAndDiagnostics
  :: EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([Text], [FileDiagnostic], b)
oneshotL4ActionAndDiagnostics = oneshotL4ActionAndDiagnosticsIn Rules.AmbientLibraries

-- | 'oneshotL4ActionAndDiagnostics' under a chosen 'Rules.LibraryScope'. A host
-- that serves bundles somebody else uploaded asks for
-- 'Rules.EmbeddedStdlibOnly', as it does for 'oneshotL4ActionAndErrorsIn'.
oneshotL4ActionAndDiagnosticsIn
  :: Rules.LibraryScope
  -> EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([Text], [FileDiagnostic], b)
oneshotL4ActionAndDiagnosticsIn scope evalConfig fp act = do
  (getLog, recorder) <- fmap (cmapWithPrio pretty) <$> makeRefRecorder
  (diags, res) <- oneshotL4ActionWithDiagsIn scope recorder evalConfig fp act
  errs <- getLog
  pure (errs, diags, res)

oneshotL4Action :: Recorder (WithPriority Log) -> EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO b
oneshotL4Action = oneshotL4ActionIn Rules.AmbientLibraries

-- | 'oneshotL4Action' under a chosen 'Rules.LibraryScope'.
oneshotL4ActionIn :: Rules.LibraryScope -> Recorder (WithPriority Log) -> EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO b
oneshotL4ActionIn scope recorder evalConfig fp act = snd <$> oneshotL4ActionWithDiagsIn scope recorder evalConfig fp act

-- | Like 'oneshotL4Action', but also returns every diagnostic published to the
-- Shake store during the run, across all files in the import closure.
oneshotL4ActionWithDiags
  :: Recorder (WithPriority Log)
  -> EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([FileDiagnostic], b)
oneshotL4ActionWithDiags = oneshotL4ActionWithDiagsIn Rules.AmbientLibraries

-- | 'oneshotL4ActionWithDiags' under a chosen 'Rules.LibraryScope'.
oneshotL4ActionWithDiagsIn
  :: Rules.LibraryScope
  -> Recorder (WithPriority Log)
  -> EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([FileDiagnostic], b)
oneshotL4ActionWithDiagsIn scope recorder evalConfig fp act = do
  let curDir = takeDirectory fp
  state <- Shake.oneshotIdeState (cmapWithPrio ShakeLog recorder) curDir do
    Store.fileStoreRules (cmapWithPrio StoreLog recorder) (const $ pure False)
    Rules.jl4RulesIn scope evalConfig curDir (cmapWithPrio RulesLog recorder)

  let nfp = normalizeFilePath fp

  [res] <- shakeRunDatabase state.shakeDb [act nfp]
  diags <- atomically (Shake.getDiagnostics state)
  pure (diags, res)
