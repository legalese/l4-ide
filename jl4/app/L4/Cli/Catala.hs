{-# LANGUAGE PatternSynonyms #-}

-- | @l4 catala FILE@ — compile the constitutive subset of an L4 file to a
-- literate Catala @.catala_en@ module.
--
-- Selection, lowering and emission live in @jl4-core@ ('L4.Catala.Lower' /
-- 'L4.Catala.Emit') so the CLI and any future LSP/service surface share one
-- implementation; this module handles option parsing, loading + type checking
-- the file, writing the output — and one job that only the CLI can do:
-- /populating the expected values of the emitted test blocks from L4's own
-- evaluator/ (R7, §8.7). The oracle is L4, so a mismatch under @clerk test@
-- fails rather than self-accepts, which is exactly what @clerk test --reset@
-- would not give us.
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

import Base (Map, Text)
import qualified Base.Text as Text
import Data.Ratio (denominator, numerator)
import qualified Data.Map.Strict as Map
import Data.Time.Format.ISO8601 (iso8601Show)
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (takeBaseName)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Catala.Emit (renderModule)
import L4.Catala.IR (CatModule (..), CatSegment (..), CatTestCli (..), catIdent, catUpper)
import L4.Catala.Lower (LowerOptions (..), lowerModuleWith, renderLowerError)
import L4.Evaluate.ValueLazy (NF (..), Value (..))
import L4.EvaluateLazy (EvalDirectiveResult (..), EvalDirectiveValue (..))
import L4.EvaluateLazy.Machine (pattern ValBool)
import L4.Parser.SrcSpan (SrcRange)
import L4.Print (ConstructorFieldNames, extractConstructorFieldNames)
import L4.Syntax (Resolved, getUnique, rawName, rawNameToText, getOriginal)
import qualified L4.TypeCheck.Environment as TC

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
       <> help "Emit only the Mode A boolean rendering; no exception ladders, no equivalence grids"
        )
  <*> fixedNowParser

catalaCmd :: CatalaOptions -> IO ()
catalaCmd opts = do
  evalConfig <- makeEvalConfig opts.catFixedNow
  (errs, (mTc, mEval)) <- runOneshot evalConfig opts.catFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    tc   <- Shake.use Rules.SuccessfulTypeCheck uri
    eval <- Shake.use Rules.EvaluateLazy uri
    pure (tc, eval)

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      -- Surface non-fatal diagnostics, but proceed: a clean type-check is the
      -- precondition that matters for lowering.
      putDiagnostics errs
      let lowerOpts = LowerOptions { loBooleanOnly = opts.catBooleanOnly }
      case lowerModuleWith lowerOpts tc.module' of
        Left lerrs -> do
          putDiagnostics
            ( "l4 catala: cannot compile these decisions to Catala:"
            : map (("  - " <>) . renderLowerError) lerrs
            )
          exitFailure
        Right m0 -> do
          let fields        = extractConstructorFieldNames tc.entityInfo
              oracle        = evalOracle (fromMaybe [] mEval)
              (m1, tNotes)  = fillTests fields oracle m0
              m             = nameFor opts.catOutput m1
          -- Warnings are advice, not failure: fallbacks and elisions must be
          -- visible (R4, R11), but they do not stop emission.
          mapM_ (\w -> hPutStrLn stderr ("l4 catala: " <> Text.unpack w))
                (m.modWarnings <> tNotes)
          let out = renderModule m
          case opts.catOutput of
            Just f  -> Text.writeFile f out
            Nothing -> Text.putStr out
          exitSuccess
 where
  fromMaybe d = maybe d id

  -- @-o Benefit.catala_en@ fixes the module name; keep the document's own
  -- top-level heading in step with it so the artifact does not name itself two
  -- different things.
  nameFor Nothing  m = m
  nameFor (Just f) m =
    let nm = catUpper (Text.pack (takeBaseName f))
    in m { modName = nm, modSegments = retitle nm m.modSegments }
  retitle nm (SegProse (l : ls) : rest)
    | "# " `Text.isPrefixOf` l = SegProse (("# " <> nm) : ls) : rest
  retitle _ segs = segs

-- ---------------------------------------------------------------------------
-- R7: the expected blocks are filled from L4's evaluator
-- ---------------------------------------------------------------------------

-- | Directive results, keyed by the source range the lowering recorded.
evalOracle :: [EvalDirectiveResult] -> Map SrcRange EvalDirectiveValue
evalOracle rs = Map.fromList [ (r, res.result) | res <- rs, Just r <- [res.range] ]

-- | Replace each bound (empty) @catala-test-cli@ block with the value L4
-- computed for the directive it came from.
--
-- A directive whose value has no Catala rendering — a string (R11), a closure,
-- an evaluation that raised — loses its expected block rather than acquiring a
-- wrong one, and says so on stderr. A block with no expectation is still a
-- meaningful test to @clerk test@ (it re-runs the scope and fails on an error),
-- so the scope itself stays.
fillTests
  :: ConstructorFieldNames -> Map SrcRange EvalDirectiveValue -> CatModule
  -> (CatModule, [Text])
fillTests fields oracle m =
  ( m { modSegments = concatMap fst filled }, concatMap snd filled )
 where
  filled = map onSegment m.modSegments

  onSegment seg = case seg of
    SegTestCli t | Just rng <- t.tcBinding, null t.tcOutput ->
      case Map.lookup rng oracle of
        Nothing ->
          ([], [ note t "L4 produced no value for it (was the directive evaluated?)" ])
        Just (Reduction (Left _)) ->
          ([], [ note t "evaluating it in L4 raised" ])
        Just (Assertion b) ->
          ([ SegTestCli t { tcOutput = [ wrap (if b then "true" else "false") ] } ], [])
        Just (Reduction (Right v)) -> case catalaJson fields v of
          Nothing   -> ([], [ note t "its value has no Catala JSON rendering" ])
          Just json -> ([ SegTestCli t { tcOutput = [ wrap json ] } ], [])
    _ -> ([seg], [])

  wrap v = "{\"result\":" <> v <> "}"
  note t why = "no expected output for `" <> t.tcCommand <> "`: " <> why

-- | Render an L4 normal form the way @catala interpret -F json@ prints the
-- corresponding Catala value.
--
-- The shapes were read off the real toolchain (catala 1.2.1): numbers are exact
-- rationals rendered as strings (@\"1000\"@, @\"5/2\"@, @\"1/3\"@), booleans are
-- JSON booleans, dates are @\"YYYY-MM-DD\"@, a payload-free constructor is its
-- own name, a constructor with a payload is a one-key object, a record is an
-- object keyed by its (mangled) field names, and a list is an array. Using JSON
-- rather than the human renderer is R7's amendment: the pretty printer writes
-- @1,000.0@ where L4 writes @1000@, and there is no reason to solve a
-- canonicalisation problem we can decline to have.
catalaJson :: ConstructorFieldNames -> NF -> Maybe Text
catalaJson fields = goNF
 where
  goNF Omitted    = Nothing
  goNF (MkNF val) = goVal val

  goVal = \case
    ValBool b     -> Just (if b then "true" else "false")
    ValNumber r   -> Just (quoted (rational r))
    ValDate d     -> Just (quoted (Text.pack (iso8601Show d)))
    ValNil        -> Just "[]"
    v@(ValCons _ _) -> listJson v
    ValConstructor r vs
      | u == TC.nothingUnique, null vs -> Just (quoted "Absent")
      | u == TC.justUnique, [x] <- vs  -> object1 "Present" x
      | Just names <- Map.lookup u fields
      , length names == length vs
      , not (null vs) ->
          (\ps -> "{" <> Text.intercalate "," ps <> "}")
            <$> sequenceA [ (\j -> quoted (catIdent n) <> ":" <> j) <$> goNF x
                          | (n, x) <- zip names vs ]
      | null vs   -> Just (quoted (catUpper (conName r)))
      | [x] <- vs -> object1 (catUpper (conName r)) x
      where u = getUnique r
    _ -> Nothing

  object1 c x = (\j -> "{" <> quoted c <> ":" <> j <> "}") <$> goNF x

  listJson v = (\xs -> "[" <> Text.intercalate "," xs <> "]") <$> traverse goNF (spine v)
  spine (ValCons hd tl) = hd : case tl of
    MkNF v -> spine v
    Omitted -> []
  spine _ = []

-- | The /defining/ name of a constructor, which is what 'L4.Catala.Lower'
-- mangles when it emits the enumeration case.
conName :: Resolved -> Text
conName = rawNameToText . rawName . getOriginal

quoted :: Text -> Text
quoted t = "\"" <> t <> "\""

-- | Catala's JSON decimals are exact rationals: @n@ when the denominator is 1,
-- @n/d@ otherwise, in lowest terms — which is what 'Rational' already holds.
rational :: Rational -> Text
rational r
  | d == 1    = tshow n
  | otherwise = tshow n <> "/" <> tshow d
 where
  n = numerator r
  d = denominator r

tshow :: Show a => a -> Text
tshow = Text.pack . show
