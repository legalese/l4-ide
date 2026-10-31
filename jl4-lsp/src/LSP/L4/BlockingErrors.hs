-- | Which diagnostics stop an L4 file from being deployed.
--
-- A file is deployable when no blocking error was published anywhere in its
-- import closure. The file's own 'LSP.L4.Rules.TypeCheckResult' is not enough:
-- 'LSP.L4.Rules.GetTypeCheckDependencies' drops an import whose typecheck
-- produced no result (an import cycle, an imported file that does not parse, an
-- @IMPORT@ that resolves to no module), so the importing file can still report
-- success.
--
-- The editor's Deploy buttons (via @l4/getExportedFunctions@) use this rule.
module LSP.L4.BlockingErrors
  ( isBlockingDiagnostic
  , hasBlockingError
  , importClosure
  , blockingErrorsIn
  ) where

import qualified Data.Set as Set
import Language.LSP.Protocol.Types (Diagnostic (..), DiagnosticSeverity (..), NormalizedUri)
import LSP.Core.Types.Diagnostics (FileDiagnostic (..), diagnosticCode)
import LSP.L4.Rules (importClosure)

-- | An Error-severity diagnostic from any source /except/ @\"eval\"@: parse
-- errors, type errors, an @IMPORT@ that resolves to nothing, and an import
-- cycle.
--
-- The evaluator publishes every @#EVAL@ and @#ASSERT@ outcome with source
-- @\"eval\"@, a failed assertion at Error severity. Those are left out: a rule
-- whose test verdict is FALSE is still a rule that can be deployed.
--
-- The error on an @IMPORT@ of a module with errors is left out too: it points
-- at an error in that module, which is counted there. That goes by its code,
-- because an @IMPORT@ that closes a ring of imports has the same source and
-- nothing else reports the ring.
isBlockingDiagnostic :: FileDiagnostic -> Bool
isBlockingDiagnostic fd =
  fd.fdLspDiagnostic._severity == Just DiagnosticSeverity_Error
    && fd.fdLspDiagnostic._source /= Just "eval"
    && fd.fdLspDiagnostic._code /= diagnosticCode "import/module-has-errors"

hasBlockingError :: [FileDiagnostic] -> Bool
hasBlockingError = any isBlockingDiagnostic

-- | The blocking diagnostics among the given ones that belong to a file in the
-- closure.
blockingErrorsIn :: [NormalizedUri] -> [FileDiagnostic] -> [FileDiagnostic]
blockingErrorsIn closure =
  filter (\fd -> isBlockingDiagnostic fd && fd.fdFilePath `Set.member` files)
  where
    files = Set.fromList closure
