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
  , ImportCycle (..)
  , importCycles
  , blockingErrorsIn
  ) where

import Control.Monad (foldM)
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import Development.IDE.Graph (Action)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import Language.LSP.Protocol.Types (Diagnostic (..), DiagnosticSeverity (..), NormalizedUri)
import LSP.Core.Shake (use)
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import LSP.L4.Rules (GetImportEdges (..))

-- | An Error-severity diagnostic from any source /except/ @\"eval\"@: parse
-- errors, type errors, an @IMPORT@ that resolves to nothing, and an import
-- cycle.
--
-- The evaluator publishes every @#EVAL@ and @#ASSERT@ outcome with source
-- @\"eval\"@, a failed assertion at Error severity. Those are left out: a rule
-- whose test verdict is FALSE is still a rule that can be deployed.
isBlockingDiagnostic :: FileDiagnostic -> Bool
isBlockingDiagnostic fd =
  fd.fdLspDiagnostic._severity == Just DiagnosticSeverity_Error
    && fd.fdLspDiagnostic._source /= Just "eval"

hasBlockingError :: [FileDiagnostic] -> Bool
hasBlockingError = any isBlockingDiagnostic

-- | The file and every module it imports, transitively, root first. Each module
-- appears once. The walk follows 'GetImportEdges', which needs only a first
-- parse of each module, so it reaches modules whose typecheck failed or that sit
-- in a cycle. A module that does not parse is included but not walked further.
importClosure :: NormalizedUri -> Action [NormalizedUri]
importClosure root = reverse . snd <$> go (Set.empty, []) root
  where
    go acc@(seen, out) uri
      | uri `Set.member` seen = pure acc
      | otherwise = do
          edges <- fromMaybe [] <$> use GetImportEdges uri
          foldM go (Set.insert uri seen, uri : out) (map snd edges)

-- | An @IMPORT@ that closes a cycle: the file it is in, its line (1-based, when
-- known), and the cycle from the imported module back to it, e.g.
-- @[dua, dub, dua]@.
data ImportCycle = ImportCycle
  { importer :: NormalizedUri
  , line :: Maybe Int
  , cycle :: [NormalizedUri]
  }

-- | The import cycles reachable from the file, each reported once, at the
-- @IMPORT@ that closes it.
--
-- The engine reports a cycle as a raw exception on one of the modules in it,
-- which names rules and not files; this names the files. A module that imports
-- itself is left out: the engine reports that one in words.
importCycles :: NormalizedUri -> Action [ImportCycle]
importCycles root = reverse . snd <$> go [] (Set.empty, []) root
  where
    go path (done, out) uri
      | uri `Set.member` done = pure (done, out)
      | otherwise = do
          edges <- fromMaybe [] <$> use GetImportEdges uri
          let path' = uri : path
              step acc@(done', out') (range, target)
                | target == uri = pure acc
                | target `elem` path' =
                    pure (done', ImportCycle
                      { importer = uri
                      , line = (.start.line) <$> range
                      , cycle = dropWhile (/= target) (reverse path') <> [target]
                      } : out')
                | otherwise = go path' acc target
          (done', out') <- foldM step (done, out) edges
          pure (Set.insert uri done', out')

-- | The blocking diagnostics among the given ones that belong to a file in the
-- closure.
blockingErrorsIn :: [NormalizedUri] -> [FileDiagnostic] -> [FileDiagnostic]
blockingErrorsIn closure =
  filter (\fd -> isBlockingDiagnostic fd && fd.fdFilePath `Set.member` files)
  where
    files = Set.fromList closure
