-- | What another package can add to the @l4@ command line.
--
-- The community @l4@ is @'L4.Cli.Main.mainWith' 'noExtensions'@: this record
-- empty. A package that depends on the @l4-cli@ sublibrary of @jl4@ can build
-- another executable, @mainWith myExtensions@, which is the community @l4@
-- and whatever the record adds. Nothing here is a plug-in loaded at run time:
-- the extension is compiled into its own executable. In this repository the
-- packages cloned into @etc/verify/@ are built when present (@cabal.project@,
-- @optional-packages@).
--
-- == What can be added
--
-- * 'extCommands': top-level subcommands, listed in @l4 --help@ after the
--   built-in ones. A name has no dot in it, so that @l4 foo.l4@ still runs
--   the file.
-- * 'extExports': @l4 export FORMAT@ subcommands, listed in @l4 export --help@
--   after the built-in formats.
-- * 'extEmitTargets': files that @l4 explore --emit DIR@ writes into @DIR@
--   beside the built-in ones (@.aut@, @.tla@, @.smv@, @.dot@, @.pnml@).
--   With at least one target, @l4 explore@ gains @--target NAME@ (write only
--   the named targets' files; repeatable; the default is every target) and
--   @--target-opt NAME.KEY=VALUE@ (passed to that target as a map). With none
--   it gains neither, and its help is the community edition's.
-- * 'extEdition': the name of the edition. @l4 --version@ appends it, and a
--   message that names the extension says it. Editions that are combined with
--   '<>' are joined with @+@, each name once, in the order first met.
--
-- A subcommand is a name and an @optparse-applicative@ 'ParserInfo' whose
-- parser yields the action to run. An export format that reads an L4 file
-- can use 'L4.Cli.Common.loadChecked', which gives back the checked module and
-- its imports; 'L4.Cli.Common' exports the type they come in, so the package
-- needs @jl4-lsp@ only if it runs the pipeline itself, and @jl4-core@
-- ("L4.Syntax") to look inside the syntax tree. An emit target is a function of its
-- options and the 'EmitInput' that the built-in emitters are built from: the
-- explored graph (@eiGraph@), the properties and their labels, and @--fair@.
-- For the shape the built-in Tla, Smv and Pnml emitters read, apply
-- 'L4.Lts.Explore.Emit.Model.buildModel' to it. An extension that runs its own
-- checks over an explored graph can use 'L4.Cli.Explore.statusOf',
-- 'L4.Cli.Explore.requestsOf' and 'L4.Cli.Explore.importedModules'.
--
-- == How it fails
--
-- Loud, before any argument is read, so that @--version@ and @--help@ stop too
-- (exit 1, with a message that names the extension):
--
-- * A command or export-format name that a built-in or another extension
--   already has. An extension cannot replace a built-in.
-- * Two emit targets, commands or export formats of one name in one record.
-- * A command name with a dot in it.
--
-- Loud, when @--emit@ runs, naming the target, and the file where there is one
-- (exit 1; the other files are still written, and a refused file is not
-- written at all):
--
-- * A 'Left' from a target.
-- * An exception raised while a target's files are computed, or while one is
--   written (a directory of that name is in the way, say). The files of the
--   target that come before and after it are still written, unless the list
--   itself could not be read to its end, and so are the other targets'.
-- * A file name that 'emitNameProblem' refuses: empty, @.@, a path separator,
--   a colon, @..@, a control character, longer than 255 bytes in UTF-8, or a
--   device name that Windows reserves. Nothing is written outside the @--emit@
--   directory.
-- * A file name that is the same as one already written, by a built-in
--   emitter or an earlier target. Names are compared case-folded, because
--   APFS and HFS+ as they are usually set up would treat them as one file.
-- * A @--target@ or @--target-opt@ that names no target, a @--target-opt@
--   for a target that @--target@ leaves out, a malformed or repeated
--   @--target-opt@, or either flag without @--emit@.
--
-- Silent:
--
-- * Case folding is Unicode case folding, not normalisation: two names that
--   differ only in the Unicode normal form of a letter are two files here and
--   one on those file systems.
-- * A target that @--target@ leaves out is not run, so a fault in it is not
--   found by that run.
-- * An option a target does not read is passed to it and ignored by it.
-- * Of the Windows rules for file names, only the reserved device names are
--   checked: a name that ends in a dot or a space, or a device name with a
--   superscript digit, is not refused here.
module L4.Cli.Extensions
  ( Extensions (..)
  , ExtCommand (..)
  , EmitTarget (..)
  , TargetOptions
  , noExtensions
  , checkExtensions
  , extensionLabel
  , emitNameProblem
  ) where

import Base.Text (Text)
import qualified Base.Map as Map
import qualified Base.Text as Text
import Data.Char (isControl)
import Data.List (group, intercalate, nub, sort)
import Options.Applicative (ParserInfo)

import L4.Lts.Explore.Emit.Model (EmitInput)

-- | The places an extension can add to. Every list is empty in the community
-- build, and 'extEdition' is 'Nothing'.
--
-- Records combine with '<>': the lists are appended, in order, and the
-- editions are joined with @+@ when both are given.
data Extensions = MkExtensions
  { extEdition     :: Maybe String
  , extCommands    :: [ExtCommand]
  , extExports     :: [ExtCommand]
  , extEmitTargets :: [EmitTarget]
  }

instance Semigroup Extensions where
  a <> b = MkExtensions
    { extEdition = case (a.extEdition, b.extEdition) of
        (Just x, Just y) -> Just (joinEditions x y)
        (Nothing, y) -> y
        (x, Nothing) -> x
    , extCommands = a.extCommands <> b.extCommands
    , extExports = a.extExports <> b.extExports
    , extEmitTargets = a.extEmitTargets <> b.extEmitTargets
    }

instance Monoid Extensions where
  mempty = noExtensions

-- | The names between the plus signs of both, each once, in the order first
-- met, so that combining editions is associative: @A <> A <> B@ is @A+B@
-- however it is bracketed. (A name with a plus sign in it is two names.)
joinEditions :: String -> String -> String
joinEditions x y = intercalate "+" (nub (names x <> names y))
  where
    names s = case break (== '+') s of
      (name, []) -> [name]
      (name, _ : rest) -> name : names rest

-- | A subcommand: @l4 NAME ...@, or @l4 export NAME ...@. Build the
-- 'ParserInfo' as the built-in ones are built, @info (helper <*> parser)
-- (progDesc "...")@.
data ExtCommand = MkExtCommand
  { ecName :: String
  , ecInfo :: ParserInfo (IO ())
  }

-- | What @--target-opt NAME.KEY=VALUE@ gave a target: KEY to VALUE.
type TargetOptions = Map.Map Text Text

-- | A set of files written by @l4 explore --emit DIR@, by name and contents.
-- The result has the shape of the built-in emitters' (@emitFiles@ in
-- "L4.Lts.Explore.Emit"): 'Left' for a file that cannot be written
-- faithfully, with why.
data EmitTarget = MkEmitTarget
  { etName  :: String
    -- ^ what @--target@ and @--target-opt@ call it, and what a message about
    -- its files says; shown in @l4 explore --help@
  , etFiles :: TargetOptions -> EmitInput -> [Either Text (Text, Text)]
  }

-- | The community edition: nothing added.
noExtensions :: Extensions
noExtensions = MkExtensions
  { extEdition = Nothing
  , extCommands = []
  , extExports = []
  , extEmitTargets = []
  }

-- | The faults of an 'Extensions' that can be found without the built-in
-- commands, one message each, naming the extension. 'L4.Cli.Main.mainWith'
-- stops on the first, before it reads an argument.
checkExtensions :: Extensions -> [String]
checkExtensions exts = concat
  [ [ who <> " adds two commands named `" <> n <> "`" | n <- duplicates (map (.ecName) exts.extCommands) ]
  , [ who <> " adds two export formats named `" <> n <> "`" | n <- duplicates (map (.ecName) exts.extExports) ]
  , [ who <> " adds two emit targets named `" <> n <> "`" | n <- duplicates (map (.etName) exts.extEmitTargets) ]
  , [ who <> " adds an emit target named `" <> t.etName <> "`: a name with a dot or an equals sign could not be given to --target-opt"
    | t <- exts.extEmitTargets, any (`elem` ['.', '=']) t.etName ]
  , [ who <> " adds a command named `" <> c.ecName <> "`: a name with a dot in it would stand where `l4 FILE` runs a file"
    | c <- exts.extCommands, '.' `elem` c.ecName ]
  ]
  where
    who = extensionLabel exts
    duplicates xs = [ x | x : _ : _ <- group (sort xs) ]

-- | How a message names the extension: by its edition, if it has one.
extensionLabel :: Extensions -> String
extensionLabel exts = maybe "an extension" (\ e -> "the " <> e <> " extension") exts.extEdition

-- | Why a file name given by an emit target cannot be written into the
-- @--emit@ directory, or 'Nothing' if it can. It is refused if it is empty or
-- @.@; has a path separator (so an absolute name is refused), a colon (a
-- drive, or a stream on Windows), @..@ or a control character, NUL included,
-- in it; is longer than 255 bytes in UTF-8, which is as long as a name can be
-- on the usual file systems; or is a device name that Windows reserves
-- (@CON@, @PRN@, @AUX@, @NUL@, @COM1@ to @COM9@, @LPT1@ to @LPT9@), as it
-- stands or before its first dot, in any case.
emitNameProblem :: Text -> Maybe Text
emitNameProblem name
  | Text.null name = Just "the name is empty"
  | name == "." = Just "the name is `.`, the directory itself"
  | Text.any (\ c -> c == '/' || c == '\\') name = Just "the name has a path separator in it"
  | Text.any (== ':') name = Just "the name has a colon in it"
  | ".." `Text.isInfixOf` name = Just "the name has `..` in it"
  | Text.any isControl name = Just "the name has a control character in it"
  | utf8Length name > 255 = Just "the name is longer than 255 bytes in UTF-8"
  | Just device <- reservedDevice name = Just ("the name is `" <> device <> "`, a device name that Windows reserves")
  | otherwise = Nothing

-- | The length of the text in UTF-8, in bytes.
utf8Length :: Text -> Int
utf8Length = Text.foldl' (\ n c -> n + width c) 0
  where
    width c
      | c < '\x80' = 1
      | c < '\x800' = 2
      | c < '\x10000' = 3
      | otherwise = 4

-- | The Windows device that the name stands for, if it does: the text before
-- its first dot, compared without regard to case.
reservedDevice :: Text -> Maybe Text
reservedDevice name
  | stem `elem` devices = Just (Text.toUpper stem)
  | otherwise = Nothing
  where
    stem = Text.toCaseFold (Text.takeWhile (/= '.') name)
    devices = ["con", "prn", "aux", "nul"] <> [ d <> Text.pack (show n) | d <- ["com", "lpt"], n <- [1 .. 9 :: Int] ]
