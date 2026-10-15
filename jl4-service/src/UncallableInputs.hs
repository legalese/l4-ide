{-# LANGUAGE OverloadedStrings #-}

-- | Which exported inputs no call can fill.
--
-- A request names an input's value in JSON, and the service decodes it against
-- the input's type. For a type with a constructor that carries data (@Circle
-- HAS radius IS A NUMBER@) there is no JSON form the decoder accepts: the
-- constructor's name alone is read as the constructor with nothing in it, and an
-- object is read only as a record. The schema the service publishes lists the
-- constructor's name all the same. So a deploy succeeds, @tools/list@ offers the
-- name, and the call fails with an error that points at the wrong cause. A
-- constructor with no data (@Unspecified@) is not affected: it is sent as its name.
--
-- This module finds those inputs at deploy time, so the operator hears of them
-- first. It decides nothing about what the JSON form of such a constructor
-- should be, and it changes neither the schema nor what is accepted.
--
-- An input is flagged only where a call /must/ supply a value of the type.
-- That excludes a @MAYBE@ (omit it), a @LIST@ (send @[]@), an input with a
-- @TYPICALLY@ default, and a record field with either of those. An optional
-- or list-shaped input of such a type is not callable with a value either, but
-- a call can still be made, so it is not what this reports.
module UncallableInputs (
  uncallableInputWarnings,
) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text

import L4.Export (ExportedParam (..), isRequiredInput)
import L4.Syntax
import L4.TypeCheck.Environment (eitherUnique)
import Types (DeployWarning (..))

-- | The warnings for one exported function, given the type declarations in scope.
uncallableInputWarnings
  :: Map Text (Declare Resolved)
  -> Text                -- ^ the function's name as the deployment shows it
  -> [ExportedParam]
  -> [DeployWarning]
uncallableInputWarnings declares fnName params =
  [ warning fnName path tyName payload plain
  | p <- params
  , isRequiredInput p
  , Just ty <- [p.paramType]
  , (path, tyName, payload, plain) <- walk declares Set.empty [p.paramName] ty
  ]

-- | The positions below a type that need a value of a type with a constructor
-- that carries data: (path, type, constructors with data, constructors without),
-- found by walking the type the way the schema does.
walk
  :: Map Text (Declare Resolved)
  -> Set.Set Text        -- ^ type names already being expanded (records that contain themselves)
  -> [Text]              -- ^ path so far
  -> Type' Resolved
  -> [([Text], Text, [Text], [Text])]
walk declares visited path = \case
  -- Spelled like 'L4.FunctionSchema.typeToParameter': a one-argument LIST or
  -- MAYBE does not need a value of its element type.
  TyApp _ name [_]
    | lowered name `elem` ["list", "listof", "maybe", "optional"] -> []
  TyApp _ name _
    -- EITHER is built in and has no DECLARE; both its constructors carry data.
    | getUnique name == eitherUnique -> [(path, "EITHER", ["LEFT", "RIGHT"], [])]
    | Just (MkDeclare _ _ _ decl) <- Map.lookup tyName declares
    , not (tyName `Set.member` visited) ->
        let visited' = Set.insert tyName visited
        in case decl of
          EnumDecl _ cons
            | payload@(_ : _) <- [nameText c | MkConDecl _ c (_ : _) <- cons] ->
                [(path, tyName, payload, [nameText c | MkConDecl _ c [] <- cons])]
          RecordDecl _ _ fields ->
            concat
              [ walk declares visited' (path <> [nameText fname]) fty
              | MkTypedName _ fname fty mTypically _ <- fields
              , Maybe.isNothing mTypically
              ]
          SynonymDecl _ inner -> walk declares visited' path inner
          _ -> []
   where
    tyName = nameText name
  Forall _ _ inner -> walk declares visited path inner
  _ -> []
 where
  lowered = Text.toLower . nameText

nameText :: Resolved -> Text
nameText = rawNameToText . rawName . getActual

warning :: Text -> [Text] -> Text -> [Text] -> [Text] -> DeployWarning
warning fnName path tyName payload plain =
  DeployWarning
    { dwKind = "uncallable-input"
    , dwFunction = fnName
    , dwParameter = path
    , dwType = tyName
    , dwConstructors = payload
    , dwCanSupply = plain
    , dwMessage =
        "Input " <> spelled path <> " of " <> fnName <> " has type " <> tyName <> ". "
          <> (if single then "Its constructor " else "Its constructors ")
          <> Text.intercalate ", " payload
          <> (if single then " carries" else " carry")
          <> " data, and the service has no JSON form for a constructor that carries data, so "
          <> (if null plain
                then "no call can supply this input"
                else "a call can supply only " <> Text.intercalate ", " plain)
          <> ". To make it callable, make the input a MAYBE, give it a TYPICALLY default, or take the data as separate inputs."
    }
 where
  single = length payload == 1
  spelled = Text.intercalate " > " . map (\n -> "`" <> n <> "`")
