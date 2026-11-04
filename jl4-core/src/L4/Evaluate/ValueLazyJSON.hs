{-# OPTIONS_GHC -Wno-orphans #-}
-- | ToJSON instances for the lazy evaluator's value types, used by
-- @l4 batch --json@ (via the ToJSON instances for eval results in
-- "L4.EvaluateLazy").
--
-- These are orphan instances (precedent: "L4.Instances.Serialise"): they
-- cannot live in "L4.Evaluate.ValueLazy" because the breach serializer
-- renders the obligation's action with 'prettyLayout', and "L4.Print"
-- imports "L4.Evaluate.ValueLazy".
--
-- Wire-format notes for 'ReasonForBreach':
--
-- * The field vocabulary of @deadline_missed@ deliberately matches the
--   hand-rolled @serializeBreachReason@ in jl4-service (Backend.Jl4), so the
--   two wire surfaces stay convergent: @eventParty@ / @eventAction@ /
--   @timestamp@ / @obligationAction@ / @deadline@, plus @obligatedParty@
--   (which jl4-service currently drops on its own wire).
--
-- * For a violated prohibition (SHANT/MUST NOT with no LEST), the machine
--   reuses the violating event's timestamp as the deadline sentinel, so
--   @deadline == timestamp@ on the wire; see the Contract10 'DMustNot'
--   branch in "L4.EvaluateLazy.Machine".
module L4.Evaluate.ValueLazyJSON () where

import Base
import Data.Aeson (ToJSON(..), object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import Data.Ratio (numerator, denominator)
import qualified Data.Vector as Vector

import L4.Evaluate.ValueLazy
import L4.Print (prettyLayout)
import L4.Syntax

-- | Get the constructor name as Text from a Resolved name.
resolvedNameText :: Resolved -> Text
resolvedNameText = rawNameToText . rawName . getOriginal

-- | Flatten a ValCons/ValNil chain into a JSON array.
-- If the structure is not a proper list, fall back to a two-element array.
flattenList :: ToJSON a => a -> a -> Aeson.Value
flattenList x xs = case toJSON xs of
  Aeson.Array arr -> Aeson.Array (Vector.cons (toJSON x) arr)
  _               -> toJSON [toJSON x, toJSON xs]

instance ToJSON NF where
  toJSON (MkNF val) = toJSON val
  toJSON Omitted    = Aeson.Null

instance ToJSON a => ToJSON (Value a) where
  toJSON (ValNumber r)
    | denominator r == 1 = toJSON (numerator r)
    | otherwise          = toJSON (fromRational r :: Double)
  toJSON (ValString s)            = toJSON s
  toJSON (ValDate d)              = toJSON (show d)
  toJSON (ValTime t)              = toJSON (show t)
  toJSON (ValDateTime utc tz)     = object ["utc" .= utc, "timezone" .= tz]
  toJSON ValNil                   = toJSON ([] :: [Aeson.Value])
  toJSON (ValCons x xs)           = flattenList x xs
  toJSON (ValConstructor name [])
    | cname == "NOTHING"          = Aeson.Null
    | cname == "EMPTY"            = toJSON ([] :: [Aeson.Value])
    | cname == "TRUE"             = Aeson.Bool True
    | cname == "FALSE"            = Aeson.Bool False
    | otherwise                   = toJSON cname
    where cname = resolvedNameText name
  toJSON (ValConstructor name [v])
    | resolvedNameText name == "JUST" = toJSON v
  toJSON (ValConstructor name fields) = object
    [ Key.fromText (resolvedNameText name) .= toJSON fields ]
  toJSON (ValClosure{})           = toJSON ("<function>" :: Text)
  toJSON (ValObligation{})        = toJSON ("<obligation>" :: Text)
  toJSON (ValROp{})               = toJSON ("<deferred-op>" :: Text)
  toJSON (ValNullaryBuiltinFun{}) = toJSON ("<builtin>" :: Text)
  toJSON (ValUnaryBuiltinFun{})   = toJSON ("<builtin>" :: Text)
  toJSON (ValBinaryBuiltinFun{})  = toJSON ("<builtin>" :: Text)
  toJSON (ValTernaryBuiltinFun{}) = toJSON ("<builtin>" :: Text)
  toJSON (ValPartialTernary{})    = toJSON ("<partial>" :: Text)
  toJSON (ValPartialTernary2{})   = toJSON ("<partial>" :: Text)
  toJSON (ValUnappliedConstructor r) = toJSON (resolvedNameText r)
  toJSON (ValAssumed r)           = toJSON ("<assumed:" <> resolvedNameText r <> ">" :: Text)
  toJSON (ValEnvironment{})       = toJSON ("<environment>" :: Text)
  toJSON (ValBreached reason)     = object ["breached" .= toJSON reason]

instance ToJSON a => ToJSON (ReasonForBreach a) where
  -- Field labels follow the constructor:
  --   DeadlineMissed <event party> <event action> <event timestamp>
  --                  <obligated party> <obligation action> <deadline>
  -- (the first three describe the event that *revealed* the deadline expiry;
  -- the last three describe the obligation that was missed).
  toJSON (DeadlineMissed evParty evAction stamp party action deadline) = object
    [ "type" .= ("deadline_missed" :: Text)
    , "eventParty" .= evParty
    , "eventAction" .= evAction
    , "timestamp" .= (fromRational stamp :: Double)
    , "obligatedParty" .= party
    , "obligationAction" .= prettyLayout action
    , "deadline" .= (fromRational deadline :: Double)
    ]
  toJSON (ExplicitBreach mParty mReason) = object
    [ "type" .= ("explicit_breach" :: Text)
    , "party" .= mParty
    , "reason" .= mReason
    ]
