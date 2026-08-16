-- | @l4 catala FILE@ — compile the constitutive subset of an L4 file to a
-- literate Catala @.catala_en@ module.
--
-- Selection, lowering and emission live in @jl4-core@ ('L4.Catala.Lower' /
-- 'L4.Catala.Emit') so the CLI and any future LSP/service surface share one
-- implementation; this module only handles option parsing, loading + type
-- checking the file, and writing the output.
--
-- Catala requires a module's @> Module \<Name\>@ header to equal the
-- capitalised basename of the file it lives in, so when @-o@ names an output
-- file the module name is taken from that basename; otherwise it comes from
-- the L4 source's basename.
module L4.Cli.Catala
  ( CatalaOptions(..)
  , catalaOptionsParser
  , catalaCmd
  ) where

import qualified Base.Text as Text
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (takeBaseName)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Catala.Emit (renderModule)
import L4.Catala.IR (CatModule (..), CatMode (..), CatRuleDef (..), CatSegment (..), CatItem (..),
                     CatScopeBody (..), catUpper)
import L4.Catala.Lower (lowerModule, renderLowerError)

import L4.Cli.Common

data CatalaOptions = CatalaOptions
  { catFile        :: FilePath
  , catOutput      :: Maybe FilePath
  , catBooleanOnly :: Bool
  , catFixedNow    :: FixedNowOpt
  }

catalaOptionsParser :: Parser CatalaOptions
catalaOptionsParser = CatalaOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to compile to Catala")
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the generated .catala_en to FILE instead of stdout"
            )
        )
  <*> switch
        ( long "boolean-only"
       <> help "Emit only the Mode A boolean rendering; never emit exception ladders"
        )
  <*> fixedNowParser

catalaCmd :: CatalaOptions -> IO ()
catalaCmd opts = do
  evalConfig <- makeEvalConfig opts.catFixedNow
  (errs, mTc) <- runOneshot evalConfig opts.catFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      -- Surface non-fatal diagnostics, but proceed: a clean type-check is the
      -- precondition that matters for lowering.
      putDiagnostics errs
      case lowerModule tc.module' of
        Left lerrs -> do
          putDiagnostics
            ( "l4 catala: cannot compile these decisions to Catala:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right m0 -> do
          let m = nameFor opts.catOutput (booleanOnly opts.catBooleanOnly m0)
          -- Warnings are advice, not failure: fallbacks and elisions must be
          -- visible (R4, R11), but they do not stop emission.
          mapM_ (\w -> hPutStrLn stderr ("l4 catala: " <> Text.unpack w)) m.modWarnings
          let out = renderModule m
          case opts.catOutput of
            Just f  -> Text.writeFile f out
            Nothing -> Text.putStr out
          exitSuccess
 where
  nameFor Nothing  m = m
  nameFor (Just f) m = m { modName = catUpper (Text.pack (takeBaseName f)) }

-- | @--boolean-only@: force every rule to its Mode A reference rendering
-- (§8.4's escape flag). The Mode B ladders stay in the IR; they are simply not
-- the rendering selected for emission.
booleanOnly :: Bool -> CatModule -> CatModule
booleanOnly False m = m
booleanOnly True  m = m { modSegments = map onSegment m.modSegments }
 where
  onSegment = \case
    SegCode items -> SegCode (map onItem items)
    other         -> other
  onItem = \case
    ItemScope b -> ItemScope b { sbRules = map forceA b.sbRules }
    other       -> other
  forceA rd = rd { rdEmitted = ModeA }
