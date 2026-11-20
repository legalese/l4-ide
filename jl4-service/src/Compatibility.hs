{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Backwards-compatibility guard for deployment updates.
--
-- When an existing deployment is re-deployed (PUT), the new bundle's
-- exported-function interface must stay compatible with the currently
-- deployed one so existing integrations keep working. This module
-- recursively diffs the two interfaces and reports every
-- backwards-incompatible ("breaking") change.
--
-- Compatibility is directional:
--
--   * Inputs (request parameters): adding a new /optional/ parameter is
--     safe; removing one, renaming it, changing its type/format, making
--     it required, or narrowing its accepted enum values is breaking.
--
--   * Outputs (return value): the mirror image — removing/renaming a
--     field, dropping it from "always present", changing its type, or
--     widening its enum (new values a consumer may not handle) is
--     breaking; adding a new field is safe.
--
-- New functions are safe; removed functions are breaking. The client-side
-- check in the editor's Deploy panel
-- (ts-apps/webview/src/lib/breaking-changes.ts, with its tests beside it)
-- applies the same rules, the ones below for a oneOf, the tagged object and a
-- change of form included, in the same directions, so that the panel's
-- warning before a redeploy says what this gate decides. A rule changed here
-- is changed there.
--
-- A type with a constructor that carries fields and one that carries none is
-- a @oneOf@ of two forms, its names (a string) and its tagged constructors (an
-- object); a node without a @oneOf@ is one form, of its own type. The forms
-- are matched by their type. One the new interface removes is breaking in
-- both directions. One it adds is not breaking on an input, and is breaking on
-- a result, as a name added to a result's enum is (MULLET, Meng, 2026-11-18;
-- the result direction STOWAWAY, Meng, 2026-11-19). Two that match are
-- compared as any node is, so a name removed from an input or added to a
-- result is breaking (comparing a matched form by the rules above is assumed,
-- not ruled).
--
-- A record's object (an object of its fields) on one side and an object keyed
-- by constructor on the other, as when a type whose only constructor is named
-- like it gains a second, is reported as a change of form, naming both, in
-- either direction (review of #779, 2026-11-20).
--
-- The keys of the tagged object are constructors, alternatives of which a value
-- holds one, not fields a value holds together, so they are compared as an
-- enum's names are: one added to a result is breaking ("may now return new
-- values"), one removed from an input is breaking ("no longer accepts"), and
-- the fields of one on both sides are compared by the rules above. That is
-- STOWAWAY's rule carried to the constructors within the tagged form (assumed,
-- not ruled). The schema tells the tagged object from a record by its
-- @required@: a record's object always has one, the tagged object never does
-- ('L4.FunctionSchema.shapeToParameter'); an EITHER's object has none either,
-- and its keys are alternatives too.
module Compatibility
  ( FnIface (..)
  , ifaceFromFunction
  , ifaceFromSummary
  , detectBreakingChanges
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, isJust)

import L4.FunctionSchema (Parameter (..), Parameters (..))
import Types (Function (..), FunctionSummary (..))

-- | The compatibility-relevant slice of a deployed/incoming function.
data FnIface = FnIface
  { ifName         :: !Text
  , ifParams       :: !Parameters
  , ifReturnType   :: !Text
  -- ^ Display name (e.g. "BOOLEAN", "DEONTIC"); a change here also
  -- covers deontic ⇄ non-deontic (different request envelope).
  , ifReturnSchema :: !(Maybe Parameter)
  -- ^ Structured return schema. Present from the live in-memory
  -- 'Function'; 'Nothing' for cached metadata 'FunctionSummary'.
  }

ifaceFromFunction :: Function -> FnIface
ifaceFromFunction f =
  FnIface f.name f.parameters f.returnType f.returnSchema

ifaceFromSummary :: FunctionSummary -> FnIface
ifaceFromSummary s =
  FnIface s.fsName s.fsParameters s.fsReturnType s.fsReturnSchema

data Dir = In | Out deriving stock (Eq)

kindOf :: Dir -> Text
kindOf In  = "parameter"
kindOf Out = "return value"

-- | @subject fn dir loc@ — the human-readable location prefix, e.g.
-- @"myFn parameter address.zip"@ or @"myFn return value"@.
subject :: Text -> Dir -> Text -> Text
subject fn dir loc =
  fn <> " " <> kindOf dir <> if Text.null loc then "" else " " <> loc

childLoc :: Text -> Text -> Text
childLoc loc k = if Text.null loc then k else loc <> "." <> k

-- | Diff every old function against the new set. Returns one message
-- per backwards-incompatible change (empty list ⇒ compatible).
detectBreakingChanges
  :: [FnIface]  -- ^ currently deployed
  -> [FnIface]  -- ^ incoming
  -> [Text]
detectBreakingChanges old new =
  let newByName = Map.fromList [(f.ifName, f) | f <- new]
      changed = concat
        [ maybe [] (diffFn o) (Map.lookup o.ifName newByName) | o <- old ]
      removed =
        [ "rule " <> o.ifName <> " removed"
        | o <- old, not (o.ifName `Map.member` newByName) ]
  in changed ++ removed
  -- New functions (present in @new@, absent from @old@) are not breaking.

diffFn :: FnIface -> FnIface -> [Text]
diffFn old new =
  let fn = old.ifName
      returnTypeChanged =
        not (Text.null old.ifReturnType)
          && not (Text.null new.ifReturnType)
          && old.ifReturnType /= new.ifReturnType
      retMsg
        | returnTypeChanged =
            [ fn <> " return type changed from "
                <> old.ifReturnType <> " to " <> new.ifReturnType ]
        | otherwise = []
      paramMsgs =
        diffObject In fn ""
          (old.ifParams.parameterMap) (old.ifParams.required)
          (new.ifParams.parameterMap) (new.ifParams.required)
      -- Return-value diff only when the return type itself is unchanged
      -- and both sides expose a structured schema.
      retSchemaMsgs =
        case (returnTypeChanged, old.ifReturnSchema, new.ifReturnSchema) of
          (False, Just os, Just ns) -> diffNode Out fn "" os ns
          _                         -> []
  in retMsg ++ paramMsgs ++ retSchemaMsgs

-- | Diff a single schema node (old vs new). Recurses into object
-- properties and array items so nested record/list shapes are compared
-- at every depth.
diffNode :: Dir -> Text -> Text -> Parameter -> Parameter -> [Text]
diffNode dir fn loc old new
  | isJust old.parameterOneOf || isJust new.parameterOneOf =
      concat
        [ case lookup ty newForms of
            Nothing -> [ subject fn dir loc <> " no longer " <> takesOrGives <> " " <> formName ty ]
            Just nf -> diffNode dir fn loc of' nf
        | (ty, of') <- oldForms
        ]
        ++ [ subject fn dir loc <> " may now return " <> formName ty
           | dir == Out
           , (ty, _) <- newForms
           , ty `notElem` map fst oldForms
           ]
  -- A type change makes deeper diffing noise; report and stop here.
  | not (Text.null old.parameterType)
      && not (Text.null new.parameterType)
      && old.parameterType /= new.parameterType =
      [ subject fn dir loc <> " type changed from "
          <> old.parameterType <> " to " <> new.parameterType ]
  -- A record's object and an object keyed by constructor are both objects,
  -- and a key-by-key diff of one against the other reports each field of the
  -- record as removed (or no longer returned), which is not what changed. A
  -- type whose only constructor is named like it is a record, its fields
  -- alone; given a second constructor, it is keyed by constructor. Report
  -- that the form changed, and stop here (review of #779, 2026-11-20).
  | formChanged =
      [ subject fn dir loc <> " form changed from " <> objectForm old <> " to " <> objectForm new ]
  | otherwise =
      formatMsgs ++ enumMsgs ++ objectMsgs ++ itemsMsgs
 where
  formChanged =
    (isRecordObject old && isAlternatives new) || (isAlternatives old && isRecordObject new)
  objectForm p =
    (if isAlternatives p then "an object keyed by its constructor (" else "an object of its fields (")
      <> Text.intercalate ", " (maybe [] Map.keys p.parameterProperties) <> ")"
  oldForms = formsOf old
  newForms = formsOf new
  takesOrGives = case dir of In -> "accepts"; Out -> "returns"
  formName ty = "a" <> (if Text.take 1 ty `elem` ["a", "e", "i", "o", "u"] then "n " else " ") <> ty
  oFmt = fromMaybe "" old.parameterFormat
  nFmt = fromMaybe "" new.parameterFormat
  formatMsgs
    | oFmt /= nFmt && not (Text.null oFmt && Text.null nFmt) =
        [ subject fn dir loc <> " format changed from "
            <> nonEmpty oFmt <> " to " <> nonEmpty nFmt ]
    | otherwise = []
  nonEmpty t = if Text.null t then "none" else t

  oEnum = old.parameterEnum
  nEnum = new.parameterEnum
  enumMsgs
    | not (null oEnum) && not (null nEnum) =
        case dir of
          In ->
            let dropped = filter (`notElem` nEnum) oEnum
            in [ subject fn dir loc <> " no longer accepts "
                   <> Text.intercalate ", " dropped
               | not (null dropped) ]
          Out ->
            let added = filter (`notElem` oEnum) nEnum
            in [ subject fn dir loc <> " may now return new values "
                   <> Text.intercalate ", " added
               | not (null added) ]
    | dir == In && null oEnum && not (null nEnum) =
        [ subject fn dir loc <> " is now restricted to a fixed set of values" ]
    | dir == Out && not (null oEnum) && null nEnum =
        [ subject fn dir loc <> " is no longer limited to a fixed set of values" ]
    | otherwise = []

  objectMsgs =
    case (old.parameterProperties, new.parameterProperties) of
      (Nothing, Nothing) -> []
      (Just oa, Just na)
        | isAlternatives old && isAlternatives new -> diffAlternatives dir fn loc oa na
      (mo, mn) ->
        diffObject dir fn loc
          (fromMaybe Map.empty mo) (fromMaybe [] old.parameterRequired)
          (fromMaybe Map.empty mn) (fromMaybe [] new.parameterRequired)

  itemsMsgs =
    case (old.parameterItems, new.parameterItems) of
      (Just oi, Just ni) ->
        diffNode dir fn (if Text.null loc then "[]" else loc <> "[]") oi ni
      _ -> []

-- | An object whose keys are alternatives, of which a value holds exactly one:
-- the tagged constructors of a type with a constructor that carries fields, or
-- the two sides of an EITHER. Their schema has no @required@, which a record's
-- always has.
isAlternatives :: Parameter -> Bool
isAlternatives p = isJust p.parameterProperties && p.parameterRequired == Nothing

-- | A record's object: its schema always has a @required@
-- ('L4.FunctionSchema.shapeToParameter').
isRecordObject :: Parameter -> Bool
isRecordObject p = isJust p.parameterProperties && isJust p.parameterRequired

-- | Diff the keys of two objects of alternatives ('isAlternatives') as an enum's
-- names are diffed: one added to a result, or removed from an input, is
-- breaking, and one on both sides is compared as any node.
diffAlternatives :: Dir -> Text -> Text -> Map.Map Text Parameter -> Map.Map Text Parameter -> [Text]
diffAlternatives dir fn loc oldAlts newAlts =
  [ subject fn dir loc <> " no longer accepts " <> Text.intercalate ", " dropped
  | dir == In, not (null dropped) ]
    ++ [ subject fn dir loc <> " may now return new values " <> Text.intercalate ", " added
       | dir == Out, not (null added) ]
    ++ concat
         [ diffNode dir fn (childLoc loc k) ov nv
         | (k, ov) <- Map.toList oldAlts, Just nv <- [Map.lookup k newAlts] ]
 where
  dropped = Map.keys (Map.difference oldAlts newAlts)
  added = Map.keys (Map.difference newAlts oldAlts)

-- | The forms a node's value takes, by their type: its @oneOf@'s members, or
-- itself.
formsOf :: Parameter -> [(Text, Parameter)]
formsOf p = case p.parameterOneOf of
  Just members -> [ (m.parameterType, m) | m <- members ]
  Nothing -> [ (p.parameterType, p) ]

-- | Diff an object's property set (used for both the top-level parameter
-- object and every nested record), honouring required-ness in the
-- compatibility direction.
diffObject
  :: Dir -> Text -> Text
  -> Map.Map Text Parameter -> [Text]  -- ^ old properties, old required
  -> Map.Map Text Parameter -> [Text]  -- ^ new properties, new required
  -> [Text]
diffObject dir fn loc oldProps oldReq newProps newReq =
  concatMap checkOld (Map.toList oldProps) ++ concatMap checkNew (Map.keys newProps)
 where
  checkOld (k, ov) =
    let cl = childLoc loc k
    in case Map.lookup k newProps of
      Nothing ->
        [ subject fn dir cl
            <> (if dir == In then " removed" else " no longer returned") ]
      Just nv ->
        let reqMsg = case dir of
              In | k `elem` newReq && k `notElem` oldReq ->
                   [ subject fn dir cl <> " is now required" ]
              Out | k `elem` oldReq && k `notElem` newReq ->
                   [ subject fn dir cl <> " may now be absent from the result" ]
              _ -> []
        in reqMsg ++ diffNode dir fn cl ov nv

  checkNew k
    -- New optional input / new output field → compatible. Only a new
    -- *required* input breaks existing callers.
    | k `Map.member` oldProps = []
    | dir == In && k `elem` newReq =
        [ fn <> " has a new required parameter " <> childLoc loc k ]
    | otherwise = []
