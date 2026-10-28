{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
module L4.TemporalContext
  ( TemporalContext (..)
  , initialTemporalContext
  )
where

import Base
import qualified Base.Text as Text
import Data.Time (UTCTime (..))

-- | The temporal context carried during evaluation: the moment `TODAY`,
-- `NOW` and `CURRENTTIME` read, and the time zone set by `TIMEZONE IS`.
data TemporalContext = TemporalContext
  { tcSystemTime :: !UTCTime
  , tcDocumentTimezone :: !(Maybe Text.Text)  -- ^ IANA timezone name (e.g. "Asia/Singapore")
  }
  deriving stock (Eq, Show, Generic)

-- | Seed an initial temporal context from the wall-clock (or fixed) time.
initialTemporalContext :: UTCTime -> TemporalContext
initialTemporalContext now =
  TemporalContext
    { tcSystemTime = now
    , tcDocumentTimezone = Nothing
    }
