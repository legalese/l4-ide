-- | What a foreign notation could not carry.
--
-- Shared by every L4 interchange backend (DMN, BPMN, …). The report is not an
-- apology for the exporter: the losses it names are properties of the /target/
-- notation, and naming them precisely is the deliverable. A reader told "BPMN
-- has no way to say that skipping this task is a breach" has learned something
-- about BPMN.
--
-- Kept deliberately small and dependency-free so the decision-side and
-- process-side tracks can share it without coupling to each other.
module L4.Interchange.Fidelity
  ( FidelityNote (..)
  , FidelitySeverity (..)
  , FidelityReport (..)
  , emptyReport
  , addNote
  , renderReport
  ) where

import Base
import qualified Base.Text as Text
import L4.Parser.SrcSpan (SrcRange, prettySrcRange)

-- | How much the loss costs the reader.
data FidelitySeverity
  = Blocking
    -- ^ the target cannot express this at all; we emitted a fallback
  | Lossy
    -- ^ expressed, but something the source said is gone
  | Advisory
    -- ^ expressed faithfully, but a target-side capability is forfeited
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | One named, located loss.
data FidelityNote = MkFidelityNote
  { code     :: Text            -- ^ stable identifier, e.g. @\"F1\"@, @\"D-NONFEEL\"@
  , severity :: FidelitySeverity
  , element  :: Text            -- ^ the emitted element's id, or the L4 name
  , range    :: Maybe SrcRange  -- ^ where in the source, when the IR carries it
  , message  :: Text            -- ^ one sentence, in the reader's vocabulary
  , lost     :: Text            -- ^ what capability is thereby forfeited
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Notes accumulate in emission order.
data FidelityReport = MkFidelityReport
  { target :: Text
  , notes  :: [FidelityNote]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

emptyReport :: Text -> FidelityReport
emptyReport t = MkFidelityReport { target = t, notes = [] }

addNote :: FidelityNote -> FidelityReport -> FidelityReport
addNote n r = r { notes = r.notes <> [n] }

-- | Human-readable rendering, one block per note.
renderReport :: FidelityReport -> Text
renderReport r =
  Text.unlines $
    ("fidelity report — " <> r.target)
      : if null r.notes
          then ["  (nothing lost)"]
          else concatMap renderNote r.notes

renderNote :: FidelityNote -> [Text]
renderNote n =
  [ "  [" <> n.code <> "] " <> sev <> " — " <> n.element <> loc
  , "      " <> n.message
  , "      lost: " <> n.lost
  ]
  where
    sev = case n.severity of
      Blocking -> "blocking"
      Lossy    -> "lossy"
      Advisory -> "advisory"
    loc = maybe "" (\sr -> "  (" <> prettySrcRange sr <> ")") n.range
