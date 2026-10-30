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
--   built-in ones.
-- * 'extExports': @l4 export FORMAT@ subcommands, listed in @l4 export --help@
--   after the built-in formats.
-- * 'extEmitTargets': files that @l4 explore --emit DIR@ writes into @DIR@
--   beside the built-in ones (@.aut@, @.tla@, @.smv@, @.dot@, @.pnml@).
--
-- A subcommand is a name and an @optparse-applicative@ 'ParserInfo' whose
-- parser yields the action to run. An emit target is a function of the
-- 'EmitInput' that the built-in emitters are built from: the explored graph
-- (@eiGraph@), the properties and their labels, and @--fair@. For the shape
-- the built-in Tla, Smv and Pnml emitters read, apply
-- 'L4.Lts.Explore.Emit.Model.buildModel' to it.
--
-- == How it fails
--
-- Loud:
--
-- * A command or export format whose name a built-in or another extension
--   already has stops @l4@ at start-up, for every invocation (even @--help@),
--   naming the clash. An extension cannot replace a built-in.
-- * An emit target that cannot write a file faithfully returns 'Left' with
--   why. It is reported on stderr as the built-in ones are ("@--emit: not
--   written@"), the other files are still written, and the exit status is 1.
-- * An emit target that names a file an earlier one (a built-in's, or an
--   earlier extension's) already wrote has that file refused in the same way,
--   and is not written over it.
--
-- Silent:
--
-- * Every emit target runs on every @--emit@. There is no flag to choose
--   among them. @l4 explore --help@ names the extension targets of the
--   executable you are running, in the help of @--emit@.
-- * A file name is joined to the @--emit@ directory as given. A name with a
--   path separator in it writes where it says; the extension is trusted code.
module L4.Cli.Extensions
  ( Extensions (..)
  , ExtCommand (..)
  , EmitTarget (..)
  , noExtensions
  ) where

import Base.Text (Text)
import Options.Applicative (ParserInfo)

import L4.Lts.Explore.Emit.Model (EmitInput)

-- | The three places an extension can add to. Every list is empty in the
-- community build.
data Extensions = MkExtensions
  { extCommands    :: [ExtCommand]
  , extExports     :: [ExtCommand]
  , extEmitTargets :: [EmitTarget]
  }

-- | A subcommand: @l4 NAME ...@, or @l4 export NAME ...@. Build the
-- 'ParserInfo' as the built-in ones are built, @info (helper <*> parser)
-- (progDesc "...")@.
data ExtCommand = MkExtCommand
  { ecName :: String
  , ecInfo :: ParserInfo (IO ())
  }

-- | A set of files written by @l4 explore --emit DIR@, by name and contents.
-- The result has the shape of the built-in emitters' (@emitFiles@ in
-- "L4.Lts.Explore.Emit"): 'Left' for a file that cannot be written
-- faithfully, with why.
data EmitTarget = MkEmitTarget
  { etName  :: String
    -- ^ shown in @l4 explore --help@, so that a person can tell which files
    -- this edition adds
  , etFiles :: EmitInput -> [Either Text (Text, Text)]
  }

-- | The community edition: nothing added.
noExtensions :: Extensions
noExtensions = MkExtensions
  { extCommands = []
  , extExports = []
  , extEmitTargets = []
  }
