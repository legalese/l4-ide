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
oneshotL4ActionAndErrors evalConfig fp act = do
  (getLog, recorder) <- fmap (cmapWithPrio pretty) <$> makeRefRecorder
  res <- oneshotL4Action recorder evalConfig fp act
  errs <- getLog
  pure (errs, res)

-- | 'oneshotL4ActionAndErrors' plus the structured diagnostics.
--
-- The rendered @[Text]@ is a log, so a caller reading it can only pattern-match
-- on wording; the @[FileDiagnostic]@ carries severity and source, which is what
-- a pass\/fail verdict needs. The golden suite uses this so that an Error
-- published by a rule OTHER than the typechecker still counts as a failure:
-- @GetImports@\'s unresolvable-IMPORT error does not block
-- @SuccessfulTypeCheck@, so a module importing a module that does not exist and
-- referencing nothing from it used to pass the suite while @l4 check@ failed it
-- (smucclaw\/l4-ide#971).
oneshotL4ActionAndDiagnostics
  :: EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([Text], [FileDiagnostic], b)
oneshotL4ActionAndDiagnostics evalConfig fp act = do
  (getLog, recorder) <- fmap (cmapWithPrio pretty) <$> makeRefRecorder
  (diags, res) <- oneshotL4ActionWithDiags recorder evalConfig fp act
  errs <- getLog
  pure (errs, diags, res)

oneshotL4Action :: Recorder (WithPriority Log) -> EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO b
oneshotL4Action recorder evalConfig fp act = snd <$> oneshotL4ActionWithDiags recorder evalConfig fp act

-- | Like 'oneshotL4Action', but also returns every diagnostic published to the
-- Shake store during the run — across /all/ files in the import closure, not
-- just the entry file. Needed by callers (e.g. the @l4@ CLI) that must fail on
-- structural errors, such as an import cycle, whose diagnostic the engine
-- attaches to a transitively-imported module rather than the entry file.
oneshotL4ActionWithDiags
  :: Recorder (WithPriority Log)
  -> EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([FileDiagnostic], b)
oneshotL4ActionWithDiags recorder evalConfig fp act = do
  let curDir = takeDirectory fp
  state <- Shake.oneshotIdeState (cmapWithPrio ShakeLog recorder) curDir do
    Store.fileStoreRules (cmapWithPrio StoreLog recorder) (const $ pure False)
    Rules.jl4Rules evalConfig curDir (cmapWithPrio RulesLog recorder)

  let nfp = normalizeFilePath fp

  [res] <- shakeRunDatabase state.shakeDb [act nfp]
  diags <- atomically (Shake.getDiagnostics state)
  pure (diags, res)
