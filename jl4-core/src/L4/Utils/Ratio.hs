module L4.Utils.Ratio (Rational, denominator, numerator, isInteger, prettyRatio, prettyRatioExact) where

import Data.Ratio
import Base
import qualified Base.Text as Text
import qualified Data.Scientific as Sci

isInteger :: Rational -> Maybe Integer
isInteger r =
  if denominator r == 1
    then Just $ numerator r
    else Nothing

prettyRatio :: Rational -> Text
prettyRatio r = case isInteger r of
  Nothing -> Text.pack $ Sci.formatScientific Sci.Fixed Nothing $ Sci.fromFloatDigits (fromRational @Double r)
  Just i -> Text.textShow i

-- | A number as source text that reads back as the same number: the exact
-- decimal when it terminates, as every literal written in a source file does.
-- 'prettyRatio' goes through 'Double' and loses digits past the seventeenth,
-- which is right for showing a result and wrong for re-emitting a literal:
-- @l4 batch@ re-prints the module it runs, so a lossy literal there is a
-- different program (TYPICALLY-ONE-BEHAVIOUR-SPEC.md §4.1, review m1). A
-- number with no terminating decimal falls back to 'prettyRatio'.
prettyRatioExact :: Rational -> Text
prettyRatioExact r = case isInteger r of
  Just i -> Text.textShow i
  Nothing -> case Sci.fromRationalRepetend (Just 1000) r of
    Right (s, Nothing) -> Text.pack (Sci.formatScientific Sci.Fixed Nothing s)
    _                  -> prettyRatio r
