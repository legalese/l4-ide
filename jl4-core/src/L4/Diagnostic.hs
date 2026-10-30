-- | Shared diagnostic types and conversions.
--
-- This module provides platform-agnostic diagnostic types that can be
-- used by both the native LSP server and the WASM browser implementation.
-- Each platform can then convert to their specific output format (LSP types
-- or JSON).
--
-- The goal is to share the diagnostic creation logic while allowing
-- platform-specific serialization at the edges.
module L4.Diagnostic
  ( -- * Types
    SimpleDiagnostic(..)
  , DiagnosticSeverity(..)
  , DiagnosticLocation(..)
    -- * Conversions from L4 types
  , checkErrorToDiagnostic
  , parseErrorToDiagnostic
  , evalResultToDiagnostic
  , evalResultSeverity
  , evalResultSuccess
    -- * Severity conversion
  , fromCheckSeverity
    -- * Helpers
  , severityToInt
  , locStart
  , locEnd
  ) where

import Base
import qualified Base.Text as Text

import L4.Annotation (HasSrcRange(..))
import L4.Parser.SrcSpan (SrcRange(..), SrcPos(..), SrcSpan(..))
import L4.Lexer (PError(..))
import L4.TypeCheck.Types (CheckErrorWithContext(..), Severity(..), severity)
import L4.TypeCheck (prettyCheckError)
import qualified L4.EvaluateLazy as EL

-- | Platform-agnostic diagnostic severity.
-- Matches LSP DiagnosticSeverity values for easy conversion.
data DiagnosticSeverity
  = DSError       -- ^ 1
  | DSWarning     -- ^ 2
  | DSInformation -- ^ 3
  | DSHint        -- ^ 4
  deriving stock (Eq, Show, Generic)

-- | A diagnostic location. Can be from a full SrcRange (type check errors)
-- or just a SrcSpan (parse errors, which don't have a URI yet).
data DiagnosticLocation
  = RangeLoc SrcRange  -- ^ Full range with URI and length
  | SpanLoc SrcSpan    -- ^ Just start/end positions (no URI)
  deriving stock (Eq, Show, Generic)

-- | Get start position from a diagnostic location.
locStart :: DiagnosticLocation -> SrcPos
locStart (RangeLoc r) = r.start
locStart (SpanLoc s) = s.start

-- | Get end position from a diagnostic location.
locEnd :: DiagnosticLocation -> SrcPos
locEnd (RangeLoc r) = r.end
locEnd (SpanLoc s) = s.end

-- | Platform-agnostic diagnostic type.
-- Contains all the information needed to display an error/warning to the user.
data SimpleDiagnostic = SimpleDiagnostic
  { sdLocation :: Maybe DiagnosticLocation
    -- ^ Location of the diagnostic. Nothing means start of file.
  , sdSeverity :: DiagnosticSeverity
    -- ^ Error, warning, info, or hint
  , sdMessage  :: Text
    -- ^ The diagnostic message to display
  , sdSource   :: Text
    -- ^ Source identifier (e.g., "parser", "check", "eval")
  }
  deriving stock (Eq, Show, Generic)

-- | Convert L4's internal severity to diagnostic severity.
fromCheckSeverity :: Severity -> DiagnosticSeverity
fromCheckSeverity = \case
  SError -> DSError
  SWarn  -> DSWarning
  SInfo  -> DSInformation

-- | Convert diagnostic severity to LSP integer (1=Error, 2=Warning, 3=Info, 4=Hint).
severityToInt :: DiagnosticSeverity -> Int
severityToInt DSError       = 1
severityToInt DSWarning     = 2
severityToInt DSInformation = 3
severityToInt DSHint        = 4

-- | Convert a type check error to a platform-agnostic diagnostic.
checkErrorToDiagnostic :: CheckErrorWithContext -> SimpleDiagnostic
checkErrorToDiagnostic err = SimpleDiagnostic
  { sdLocation = RangeLoc <$> rangeOf err
  , sdSeverity = fromCheckSeverity (severity err)
  , sdMessage  = Text.unlines (prettyCheckError err.kind)
  , sdSource   = "check"
  }

-- | Convert a parse error to a platform-agnostic diagnostic.
-- Note: Parse errors have a SrcSpan (no URI) rather than a full SrcRange.
parseErrorToDiagnostic :: PError -> SimpleDiagnostic
parseErrorToDiagnostic err = SimpleDiagnostic
  { sdLocation = Just $ SpanLoc err.range
  , sdSeverity = DSError
  , sdMessage  = err.message
  , sdSource   = "parser"
  }

-- | Convert an evaluation result to a platform-agnostic diagnostic, with the
-- severity 'evalResultSeverity' gives it.
evalResultToDiagnostic :: EL.EvalDirectiveResult -> SimpleDiagnostic
evalResultToDiagnostic r@(EL.MkEvalDirectiveResult mrange res _mtrace) = SimpleDiagnostic
  { sdLocation = RangeLoc <$> mrange
  , sdSeverity = evalResultSeverity res
  , sdMessage  = EL.prettyEvalDirectiveResult r
  , sdSource   = "eval"
  }

-- | The severity with which an editor shows a directive's result. A refusal,
-- of an #EVAL or of an #ASSERT, is a warning: the model declined to answer,
-- which is neither a success nor a defect in the program. A failed assertion,
-- and an evaluation that raised, are errors. Everything else is information.
--
-- The language server and the browser editor both take a result's severity
-- from here.
evalResultSeverity :: EL.EvalDirectiveValue -> DiagnosticSeverity
evalResultSeverity = \case
  EL.Assertion EL.Holds              -> DSInformation
  EL.Assertion EL.Fails              -> DSError
  EL.Assertion (EL.FailsBecause _)   -> DSError
  EL.Assertion (EL.Refused _)        -> DSWarning
  EL.Assertion (EL.Errored _)        -> DSError
  EL.Reduction (EL.Reduced _)        -> DSInformation
  EL.Reduction (EL.ReducedRefused _) -> DSWarning
  EL.Reduction (EL.ReducedErrored _) -> DSError

-- | Whether a directive's result is a success: an answer or a holding
-- assertion is, a failure or an evaluation that raised is not, and a refusal,
-- of an #EVAL or of an #ASSERT, is neither.
--
-- L4.API's 'l4Eval' and 'l4EvalDirective' and the language server's Inspector
-- all take a result's success from here.
evalResultSuccess :: EL.EvalDirectiveValue -> Maybe Bool
evalResultSuccess = \case
  EL.Assertion EL.Holds              -> Just True
  EL.Assertion EL.Fails              -> Just False
  EL.Assertion (EL.FailsBecause _)   -> Just False
  EL.Assertion (EL.Refused _)        -> Nothing
  EL.Assertion (EL.Errored _)        -> Just False
  EL.Reduction (EL.Reduced _)        -> Just True
  EL.Reduction (EL.ReducedRefused _) -> Nothing
  EL.Reduction (EL.ReducedErrored _) -> Just False
