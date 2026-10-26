{-# LANGUAGE OverloadedStrings #-}
-- | The project file, @l4-project.json@, read for the aliases it defines
-- (specs\/proposals\/RELATIVE-IMPORTS-SPEC.md §4.7, C6; PROPOSED, FOR MENG, not
-- ruled).
--
-- The file marks the root of a project ('L4.Import.Resolution.projectMarkerFile')
-- and, when it holds an @aliases@ object, names folders of the project that an
-- @IMPORT \`\@alias\/path\`@ can start from:
--
-- @
-- { "aliases": { "vn10": "subjects\/vn\/nd67" } }
-- @
--
-- Nothing here touches the filesystem, so a resolver without one (the browser
-- build of Stage 2) can use it, and the text it is given may come from an open
-- editor buffer or an uploaded file as well as from the disk. The content is
-- read only when an alias import needs it: a root-relative import looks for the
-- file and never opens it.
module L4.Import.ProjectManifest
  ( ProjectManifest (..)
  , ManifestProblem (..)
  , parseProjectManifest
  , renderManifestProblem
  , AliasProblem (..)
  , aliasFolder
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import qualified Data.Text.Encoding as TextEncoding
import System.FilePath (joinPath)

import L4.Import.Resolution (CollapsedPath (..), collapsePath)

-- | What a project file says. Keys it does not know are ignored, so a file may
-- carry more than aliases in a later version and still be read by this one.
newtype ProjectManifest = MkProjectManifest
  { aliases :: Map Text Text
    -- ^ alias to the folder it stands for, as written, relative to the folder
    -- that holds the file. See 'aliasFolder' for what a folder may be.
  }
  deriving stock (Eq, Show)

-- | Why a project file could not be used.
data ManifestProblem
  = ManifestNotJson !Int !Int !(Maybe Char)
    -- ^ It is not JSON: the line and column (both from 1) of the first
    -- character that no JSON text could have at that place, and that character;
    -- or, with 'Nothing', the file ended before the JSON was complete (the
    -- position is then the end of the file).
  | ManifestShape !Text !Text
    -- ^ It is JSON, but not the shape this reads: where (@aliases.vn10@) and
    -- what is wrong there.
  | ManifestUnreadable !Text
    -- ^ It could not be read at all: not UTF-8, or the operating system said no.
    -- 'parseProjectManifest' never returns this; the reader of the file does.
  deriving stock (Eq, Show)

-- | The second line of the message for a project file that cannot be used: what
-- is wrong with it, and where.
renderManifestProblem :: ManifestProblem -> Text
renderManifestProblem = \ case
  ManifestNotJson line column (Just c) ->
    "It is not valid JSON: line " <> Text.textShow line <> ", column " <> Text.textShow column
      <> ", unexpected " <> quoted c <> "."
  ManifestNotJson line column Nothing ->
    "It is not valid JSON: the file ends before the JSON is complete (line "
      <> Text.textShow line <> ", column " <> Text.textShow column <> ")."
  ManifestShape place what -> "It is valid JSON, but " <> place <> " " <> what <> "."
  ManifestUnreadable why -> "It could not be read: " <> why <> "."

-- | A character as a person is told about it: one that cannot be seen is named.
quoted :: Char -> Text
quoted = \ case
  '\n' -> "a line break"
  '\t' -> "a tab"
  ' '  -> "a space"
  c    -> "`" <> Text.singleton c <> "`"

-- | Read the text of a project file. A leading byte-order mark is ignored.
--
-- Choices a rule author would see, all proposed and not ruled: the top level
-- must be an object (@{}@ is the smallest file); @aliases@ is optional, and
-- when present is an object whose values are all text; every other key is
-- ignored. An alias written twice keeps whichever copy the JSON reader keeps,
-- which is the first (measured on aeson 2.2.3.0, and pinned by a test in
-- jl4-core-test, so that an upgrade that changes it fails there), and is not an
-- error. A reader of the same file elsewhere may keep the last, as JSON.parse
-- does.
parseProjectManifest :: Text -> Either ManifestProblem ProjectManifest
parseProjectManifest raw = case decodeText text of
  Left _ -> Left (notJson text)
  Right value -> shape value
  where
    text = fromMaybe raw (Text.stripPrefix "\xFEFF" raw)

shape :: Aeson.Value -> Either ManifestProblem ProjectManifest
shape = \ case
  Aeson.Object top -> case KeyMap.lookup "aliases" top of
    Nothing -> Right (MkProjectManifest Map.empty)
    Just (Aeson.Object as) ->
      MkProjectManifest <$> Map.traverseWithKey folderOf (KeyMap.toMapText as)
    Just _ ->
      Left (ManifestShape "aliases" "must be an object that gives each alias a folder, like {\"vn10\": \"subjects/vn\"}")
  _ -> Left (ManifestShape "the top level" "must be an object, like {}")
  where
    folderOf alias = \ case
      Aeson.String folder -> Right folder
      _ -> Left (ManifestShape ("aliases." <> alias) "must be the folder the alias stands for, written as text")

decodeText :: Text -> Either String Aeson.Value
decodeText = Aeson.eitherDecodeStrict . TextEncoding.encodeUtf8

-- | Where a text that is not JSON first goes wrong.
--
-- The JSON parser reports what it did not expect, but not where, and its
-- excerpt of the rest of the input is cut short. So the position is found by
-- asking it about prefixes of the text: a prefix either is, or could still grow
-- into, a JSON text, or no continuation can save it, and the first prefix that
-- is of the last kind ends in the culprit. Whether a failed parse is of the
-- second kind is read off the parser's wording ("Unexpected end-of-input"), which
-- jl4-core-test pins with a malformed file for each kind.
notJson :: Text -> ManifestProblem
notJson text = case firstImpossible of
  Nothing -> let (line, column) = position (Text.length text) in ManifestNotJson line column Nothing
  Just i -> let (line, column) = position i in ManifestNotJson line column (Just (Text.index text i))
  where
    couldGrow t = case decodeText t of
      Right _ -> True
      Left why -> "Unexpected end-of-input" `isPrefixOf` why

    firstImpossible
      | couldGrow text = Nothing
      | otherwise = Just (narrow 0 (Text.length text))

    -- Invariant: the first lo characters could grow, the first hi could not.
    narrow lo hi
      | hi - lo <= 1 = lo
      | couldGrow (Text.take mid text) = narrow mid hi
      | otherwise = narrow lo mid
      where
        mid = (lo + hi) `div` 2

    position i =
      let before = Text.take i text
       in (Text.count "\n" before + 1, Text.length (snd (Text.breakOnEnd "\n" before)) + 1)

-- | Why a folder an alias stands for cannot be used.
data AliasProblem
  = AliasIsAlias !Text
    -- ^ it starts with @\@@, so it names another alias, which an alias may not do
  | AliasLeavesRoot !FilePath
    -- ^ it climbs above the folder that holds the project file: the folder once
    -- @.@ and @..@ were worked through
  deriving stock (Eq, Show)

-- | The folder an alias stands for, relative to the folder that holds the
-- project file (which is the project root), with its @.@ and @x\/..@ worked
-- through.
--
-- Assumed, not ruled: empty segments are dropped, so a leading @\/@ is harmless
-- and @""@ and @"."@ both stand for the root itself; a folder is a folder, so
-- it takes no @.l4@. A folder that starts with @\@@ is refused rather than read
-- as a folder of that name; to name one, write @.\/\@name@.
aliasFolder :: Text -> Either AliasProblem FilePath
aliasFolder folder
  | Text.isPrefixOf "@" folder = Left (AliasIsAlias folder)
  | collapsed.cpEscaped = Left (AliasLeavesRoot collapsed.cpPath)
  | otherwise = Right collapsed.cpPath
  where
    collapsed = collapsePath (joinPath (filter (not . null) (map Text.unpack (Text.splitOn "/" folder))))
