{-# LANGUAGE OverloadedStrings #-}
-- | Deep Maybe lifting for partial evaluation
--
-- Transforms types by wrapping them in MAYBE at every level, enabling
-- uniform handling of missing/null values in JSON input.
--
-- Example:
--   Original: DECLARE Inputs HAS x IS A BOOLEAN, y IS A NUMBER
--   Lifted:   DECLARE MaybeInputs HAS x IS A MAYBE BOOLEAN, y IS A MAYBE NUMBER
--
-- This allows JSON like {"x": true} (with y missing) to decode successfully,
-- with y becoming NOTHING.
module Backend.MaybeLift
  ( liftTypeToMaybe
  , liftTypeText
  , isPrimitiveType
  ) where

import Base
import qualified Data.Text as Text
import L4.Syntax (Type'(..), Resolved)
import L4.Print (prettyLayout)

-- | Check if a type name is a primitive that should be lifted
-- Note: DATE, TIME and DATETIME are not included here because they need special
-- handling (converted to STRING for JSON, then parsed with TODATE, TOTIME or TODATETIME)
isPrimitiveType :: Text -> Bool
isPrimitiveType name = name `elem` ["BOOLEAN", "NUMBER", "STRING"]

-- | Check if a type arrives as a JSON string that the wrapper parses:
-- DATE, TIME and DATETIME, the three types 'Backend.CodeGen.stringConversionFn'
-- converts. Lifting only DATE left TIME and DATETIME inputs typed as themselves
-- in the wrapper's record, so TOTIME and TODATETIME were applied to a value that
-- was not a string, and the wrapper failed to type-check.
isStringCodedType :: Text -> Bool
isStringCodedType name = Text.toUpper (Text.strip name) `elem` ["DATE", "TIME", "DATETIME"]

-- | The inner type of a MAYBE type, in either spelling: @MAYBE BOOLEAN@, or
-- @MAYBE OF BOOLEAN@, which is how 'prettyLayout' prints every type application
-- (@T OF p1, p2@). Reading only the first spelling let @MAYBE OF NUMBER@ through
-- unlifted, and in the wrapper's record its @OF@ swallowed the next field's line.
maybeInner :: Text -> Maybe Text
maybeInner tyText
  | "MAYBE OF " `Text.isPrefixOf` upper = Just (Text.strip (Text.drop 9 tyText))
  | "MAYBE " `Text.isPrefixOf` upper    = Just (Text.strip (Text.drop 6 tyText))
  | otherwise                           = Nothing
  where
    upper = Text.toUpper tyText

-- | Whether the whole text is one bracketed group, as in @(LIST OF NUMBER)@.
-- Brackets inside a backticked name do not count.
isBracketed :: Text -> Bool
isBracketed t = case Text.uncons t of
  Just ('(', rest) -> go (1 :: Int) False rest
  _ -> False
  where
    go depth inTick s = case Text.uncons s of
      Nothing -> False
      Just (c, rest)
        | c == '`' -> go depth (not inTick) rest
        | inTick -> go depth inTick rest
        | c == '(' -> go (depth + 1) inTick rest
        | c == ')' -> if depth == 1 then Text.null rest else go (depth - 1) inTick rest
        | otherwise -> go depth inTick rest

-- | Bracket a type that would otherwise read as more than one argument of
-- @MAYBE@: anything with a space outside a backticked name, unless it is
-- already one bracketed group.
bracketIfNeeded :: Text -> Text
bracketIfNeeded t
  | isBracketed t = t
  | hasBareSpace False (Text.unpack t) = "(" <> t <> ")"
  | otherwise = t
  where
    hasBareSpace _ [] = False
    hasBareSpace inTick (c : cs)
      | c == '`' = hasBareSpace (not inTick) cs
      | c == ' ' && not inTick = True
      | otherwise = hasBareSpace inTick cs

-- | Lift a type to MAYBE, handling primitives and complex types
--
-- For primitives (BOOLEAN, NUMBER, STRING, and DATE, TIME, DATETIME as STRING):
--   lift BOOLEAN = MAYBE BOOLEAN
--
-- For records (represented as type applications with field types):
--   Each field type is recursively lifted
--
-- For lists:
--   LIST OF a becomes MAYBE (LIST OF (lift a))
--
-- For already-MAYBE types, in either spelling:
--   Don't double-wrap, but DO recurse into the inner type if complex
--   MAYBE OF BOOLEAN becomes MAYBE BOOLEAN (primitive, already done)
--   MAYBE (LIST OF BOOLEAN) stays MAYBE (LIST OF BOOLEAN) (bracketed: not recursed into)
--
-- The result never contains @MAYBE OF@: it is a record field's type in the
-- generated wrapper, and an @OF@ there would read the next field as another argument.
liftTypeText :: Text -> Text
liftTypeText tyText0
  -- Already wrapped in MAYBE
  | Just inner <- maybeInner tyText =
      let innerUpper = Text.toUpper inner
      in if isPrimitiveType innerUpper
         then "MAYBE " <> inner  -- MAYBE primitive - already fully lifted
         else if isStringCodedType inner
              -- MAYBE DATE / TIME / DATETIME -> MAYBE STRING (JSON has none of them)
              -- CodeGen handles the conversion with TODATE, TOTIME or TODATETIME
              then "MAYBE STRING"
         else if "LIST OF " `Text.isPrefixOf` innerUpper
              -- MAYBE (LIST OF x) - recurse into list element
              then let elemType = Text.strip $ Text.drop 8 inner
                   in "MAYBE (LIST OF (" <> liftTypeText elemType <> "))"
              -- MAYBE complex - keep as is (record fields handled by JSON decoder)
              else "MAYBE " <> bracketIfNeeded inner
  -- DATE, TIME, DATETIME - convert to STRING for JSON compatibility
  -- The CodeGen module will add the TODATE/TOTIME/TODATETIME conversion when unwrapping
  | isStringCodedType tyText =
      "MAYBE STRING"
  -- Primitive types - wrap in MAYBE
  | isPrimitiveType (Text.toUpper tyText) =
      "MAYBE " <> tyText
  -- LIST OF - wrap list and lift element type
  | "LIST OF " `Text.isPrefixOf` Text.toUpper tyText =
      let elemType = Text.strip $ Text.drop 8 tyText
      in "MAYBE (LIST OF (" <> liftTypeText elemType <> "))"
  -- Other types (records, enums, custom types) - just wrap in MAYBE
  -- The JSON decoder will handle field-level nulls
  | otherwise =
      "MAYBE " <> bracketIfNeeded tyText
  where
    -- A bracketed element type, such as the @(MAYBE OF NUMBER)@ of
    -- @LIST OF (MAYBE OF NUMBER)@, is read without its brackets.
    tyText = unbracket (Text.strip tyText0)
    unbracket t
      | isBracketed t = unbracket (Text.strip (Text.drop 1 (Text.dropEnd 1 t)))
      | otherwise = t

-- | Lift a resolved type to MAYBE
-- This version works with the AST representation
liftTypeToMaybe :: Type' Resolved -> Text
liftTypeToMaybe ty = liftTypeText (prettyLayout ty)
