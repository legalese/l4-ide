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
--   (which jl4-service dropped on its own wire until 2026-09-15).
--
-- * For a violated prohibition (SHANT/MUST NOT with no LEST), the machine
--   reuses the violating event's timestamp as the deadline sentinel, so
--   @deadline == timestamp@ on the wire; see the Contract10 'DMustNot'
--   branch in "L4.EvaluateLazy.Machine".
--
-- * The blame set (R-T3, EVERY-EACH-QUANTIFIER-SPEC §6.1, built 2026-09-15;
--   per-entry detail and no dedup RULED the same day): a breach names every
--   obligation that failed. The wire stays additive over the one-party form:
--
--     - the scalars @obligatedParty@ \/ @obligationAction@ \/ @deadline@ (and
--       @party@ \/ @reason@ for an explicit breach) describe the ANCHOR — the
--       failure the breach's time comes from — so they are one coherent
--       obligation, and for a single obligation's breach exactly what the
--       old wire carried. (The brief said "the head"; the head is the
--       anchor only for a left-anchored compound, and a head party beside
--       the anchor's action and deadline named an obligation nobody had —
--       measured on the first build, spec §6.1.1.)
--     - @obligatedParties@ \/ @parties@: every party named, in operand \/
--       roll order, WITH duplicates; an entry naming nobody adds nothing.
--     - @failures@: one object per failed obligation, in the same order —
--       @{"type":"deadline_missed","party","action","deadline"}@ or
--       @{"type":"explicit_breach","party","reason"}@ (@null@ where absent).
--     - @anchor@: the index into @failures@ of the anchoring failure.
module L4.Evaluate.ValueLazyJSON () where

import Base
import Data.Aeson (ToJSON(..), object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.Types as Aeson.Types
import qualified Data.List.NonEmpty as NE
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
  toJSON (ValQuantified{})        = toJSON ("<quantified-obligation>" :: Text)
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

instance ToJSON a => ToJSON (Failure a) where
  toJSON (MissedDeadline party action deadline) = object
    [ "type" .= ("deadline_missed" :: Text)
    , "party" .= party
    , "action" .= prettyLayout action
    , "deadline" .= (fromRational deadline :: Double)
    ]
  toJSON (DeclaredBreach mParty mReason) = object
    [ "type" .= ("explicit_breach" :: Text)
    , "party" .= mParty
    , "reason" .= mReason
    ]

instance ToJSON a => ToJSON (ReasonForBreach a) where
  -- Field labels follow the constructor:
  --   DeadlineMissed <event party> <event action> <event timestamp> <blame>
  -- (the first three describe the event that *revealed* the anchoring
  -- deadline expiry; the scalars below describe the anchoring obligation;
  -- the arrays describe every failure — see the module header).
  toJSON (DeadlineMissed evParty evAction stamp blame) = object $
    [ "type" .= ("deadline_missed" :: Text)
    , "eventParty" .= evParty
    , "eventAction" .= evAction
    , "timestamp" .= (fromRational stamp :: Double)
    ]
    <> case blame.anchor of
      MissedDeadline party action deadline ->
        [ "obligatedParty" .= party
        , "obligationAction" .= prettyLayout action
        , "deadline" .= (fromRational deadline :: Double)
        ]
      -- unreachable by construction (a DeadlineMissed is anchored at a
      -- missed deadline); still a well-formed object rather than a crash
      DeclaredBreach mParty mReason ->
        [ "obligatedParty" .= mParty
        , "reason" .= mReason
        ]
    <> blameFields "obligatedParties" blame
  toJSON (ExplicitBreach blame) = object $
    [ "type" .= ("explicit_breach" :: Text) ]
    <> case blame.anchor of
      DeclaredBreach mParty mReason ->
        [ "party" .= mParty
        , "reason" .= mReason
        ]
      -- unreachable by construction, as above
      MissedDeadline party action deadline ->
        [ "party" .= party
        , "obligationAction" .= prettyLayout action
        , "deadline" .= (fromRational deadline :: Double)
        ]
    <> blameFields "parties" blame

-- | The array fields every breach carries: the parties (under the given
-- key), the failures, and the anchor's index.
blameFields :: ToJSON a => Key.Key -> Blame a -> [Aeson.Types.Pair]
blameFields partiesKey blame =
  [ partiesKey .= blameParties blame
  , "failures" .= NE.toList (blameList blame)
  , "anchor" .= anchorIndex blame
  ]
