module LSP.L4.Oneshot where

import qualified LSP.Core.FileStore as Store
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Location (normalizeFilePath)
import LSP.Logger (Pretty, Recorder, WithPriority, cmapWithPrio, makeRefRecorder, pretty)

import qualified LSP.L4.Rules as Rules

import Base.Text (Text)
import Development.IDE.Graph (Action)
import Development.IDE.Graph.Database (shakeRunDatabase)
import Language.LSP.Protocol.Types (NormalizedFilePath)
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

oneshotL4Action :: Recorder (WithPriority Log) -> EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO b
oneshotL4Action = oneshotL4ActionIn Rules.AmbientLibraries

-- | 'oneshotL4Action' under a chosen 'Rules.LibraryScope'.
oneshotL4ActionIn :: Rules.LibraryScope -> Recorder (WithPriority Log) -> EvalConfig -> FilePath -> (NormalizedFilePath -> Action b) -> IO b
oneshotL4ActionIn scope recorder evalConfig fp act = do
  let curDir = takeDirectory fp
  state <- Shake.oneshotIdeState (cmapWithPrio ShakeLog recorder) curDir do
    Store.fileStoreRules (cmapWithPrio StoreLog recorder) (const $ pure False)
    Rules.jl4RulesIn scope evalConfig curDir (cmapWithPrio RulesLog recorder)

  let nfp = normalizeFilePath fp

  [res] <- shakeRunDatabase state.shakeDb [act nfp]
  pure res
