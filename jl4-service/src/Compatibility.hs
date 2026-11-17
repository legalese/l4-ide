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
-- New functions are safe; removed functions are breaking. The deploy
-- sidebar makes the same kind of check on the client, with one difference: it
-- strips the DEONTIC envelope (@startTime@, @events@) from both sides first,
-- because the schema its language server builds locally has no envelope. This
-- check compares the envelope too, so a changed party or action type (under
-- @events@) is flagged here and not there, and so is a change in how the
-- service publishes that type: a deployment that was cached by an older run and
-- has not been loaded since (@--lazy-load@) is compared against the old schema.
--
-- A changed default is NOT breaking (U2 option B, bench ruling 2026-11-17: a
-- redeploy that changes a published default is accepted and reported).
-- 'detectDefaultChanges' lists those changes as notices, beside the breaking
-- ones and never among them.
module Compatibility
  ( FnIface (..)
  , ifaceFromFunction
  , ifaceFromSummary
  , detectBreakingChanges
  , detectDefaultChanges
  ) where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)

import L4.FunctionSchema (Parameter (..), Parameters (..))
import Types (DefaultChange (..), Function (..), FunctionSummary (..))

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
  -- A type change makes deeper diffing noise; report and stop here.
  | not (Text.null old.parameterType)
      && not (Text.null new.parameterType)
      && old.parameterType /= new.parameterType =
      [ subject fn dir loc <> " type changed from "
          <> old.parameterType <> " to " <> new.parameterType ]
  | otherwise =
      formatMsgs ++ enumMsgs ++ objectMsgs ++ itemsMsgs
 where
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
      (mo, mn) ->
        diffObject dir fn loc
          (fromMaybe Map.empty mo) (fromMaybe [] old.parameterRequired)
          (fromMaybe Map.empty mn) (fromMaybe [] new.parameterRequired)

  itemsMsgs =
    case (old.parameterItems, new.parameterItems) of
      (Just oi, Just ni) ->
        diffNode dir fn (if Text.null loc then "[]" else loc <> "[]") oi ni
      _ -> []

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

-- ----------------------------------------------------------------------------
-- Changed defaults (non-blocking notices)
-- ----------------------------------------------------------------------------

-- | Every published default the incoming interface changes, one notice per
-- changed default. A notice never blocks a deploy and does not move the
-- BREAKING counter: 'detectBreakingChanges' does not look at defaults at all.
--
-- A default is compared only when BOTH sides carry one. A default present on
-- one side only is not a change: adding one makes the input optional
-- (compatible), removing one makes it required (breaking by the existing rule,
-- reported there), and cached metadata written by a service older than the
-- published @default@ has none, so a missing one is /unknown/, never a change.
--
-- Limits, none of which is visible from here:
--
--   * Only a default the schema publishes is seen: a literal on a rule's own
--     input, a section input or a record field. Not one that is another
--     expression, and not one on a written ASSUME, which stays metadata
--     ('L4.Export.extractAssumeParamsWithDefaults').
--   * Two numbers that differ only beyond about 16 significant digits compare
--     equal, because the schema carries the published value through a 'Double'
--     (@typicallyToJson@ in "L4.FunctionSchema").
--   * A rate written in a rule body is not seen: this compares schemas, not
--     answers.
--
-- A node whose type changed is skipped, as 'diffNode' stops there: the type
-- change is reported as breaking and the defaults of a retyped input are not
-- comparable. Functions are matched by name; a function present on one side
-- only has nothing to compare. Notices come out in the old interface's
-- function order, then by input name.
detectDefaultChanges
  :: [FnIface]  -- ^ currently deployed
  -> [FnIface]  -- ^ incoming
  -> [DefaultChange]
detectDefaultChanges old new =
  let newByName = Map.fromList [(f.ifName, f) | f <- new]
  in [ c
     | o <- old
     , Just n <- [Map.lookup o.ifName newByName]
     , c <- diffDefaultProps o.ifName ""
              o.ifParams.parameterMap n.ifParams.parameterMap
     ]

-- | The inputs two property sets share, each compared at its own path.
diffDefaultProps
  :: Text -> Text
  -> Map.Map Text Parameter -> Map.Map Text Parameter
  -> [DefaultChange]
diffDefaultProps fn loc oldProps newProps =
  concat
    [ diffDefault fn (childLoc loc k) ov nv
    | (k, ov) <- Map.toList oldProps
    , Just nv <- [Map.lookup k newProps]
    ]

diffDefault :: Text -> Text -> Parameter -> Parameter -> [DefaultChange]
diffDefault fn loc old new
  | not (Text.null old.parameterType)
      && not (Text.null new.parameterType)
      && old.parameterType /= new.parameterType = []
  | otherwise = own ++ nested ++ elements
 where
  own = case (old.parameterDefault, new.parameterDefault) of
    (Just od, Just nd) | od /= nd -> [DefaultChange fn loc od nd]
    _ -> []
  nested = case (old.parameterProperties, new.parameterProperties) of
    (Just op, Just np) -> diffDefaultProps fn loc op np
    _ -> []
  elements = case (old.parameterItems, new.parameterItems) of
    (Just oi, Just ni) -> diffDefault fn (loc <> "[]") oi ni
    _ -> []
