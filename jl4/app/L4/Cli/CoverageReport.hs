{-# LANGUAGE PatternSynonyms #-}
-- | @l4 coverage FILE [--decision NAME]… [--all] [--json]@ — the buckets of
-- every decision of a file, with a witness for each one the evaluator can
-- realise and a proof for each one nothing can.
--
-- The verb, the flags, the exit statuses, the layout of the report, its
-- coverage line and the limits in its @--help@ footer were ruled by Meng on
-- 2026-11-12 (TALLYSTICK; CATALA-EXPORT-SPEC §8.4, "A standalone report"),
-- as they were printed in the example run he ruled on.
-- Two things came after that run and were ruled separately, later the same
-- day (CROSSWORD; the same section): the row for a bucket whose inputs give
-- different answers, and the line that names the inputs no condition reads,
-- with its paragraph in the footer and its @inputsNoConditionReads@ key in
-- the JSON.
--
-- A decision's cover points are the leaves of the conditions it branches on,
-- and a bucket is one combination of their truth values ("L4.Cli.Coverage",
-- which also backs @l4 export catala@'s witness gate, and does not need
-- Catala). Each bucket is one of three things, and the report says which:
--
-- [witnessed] some input realises it, found among a fixed set of candidates
--   and confirmed by the evaluator, which also gives the decision's answer
--   there;
-- [proved impossible] no input realises it, which the solver (z3, @Z3_EXE@
--   else @PATH@) proved;
-- [undecided] neither, with the reason: no solver, a timeout, a solver
--   answer of @unknown@, an input the evaluator could not run.
--
-- A decision whose leaves cannot all be taken separately is covered at rung
-- level, the conditions as written, and the report says so and says why. A
-- decision that cannot be covered at all is named, with the reason.
--
-- Exit status, so that a script cannot read an incomplete run as complete: 0
-- when every decision is covered at leaf level and every bucket is witnessed
-- or proved impossible; 1 when the file does not type-check or an option
-- names no decision; 2 when some bucket is undecided; 3 when none is, but
-- some decision is covered only at rung level or not at all.
module L4.Cli.CoverageReport
  ( CoverageOptions (..)
  , coverageOptionsParser
  , coverageCmd
  , coverageBound
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.Encode.Pretty as AesonPretty
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Options.Applicative
import System.Exit (ExitCode (..), exitWith)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Annotation (rangeOf)
import L4.Coverage.Rungs (rungsOf)
import L4.Parser.SrcSpan (SrcRange, prettySrcRange)
import L4.Print (extractConstructorFieldNames, prettyLayoutNF)
import L4.Syntax
import qualified L4.TypeCheck as TC

import L4.Cli.Common
import L4.Cli.Coverage
import L4.Cli.Prove (Solver (..), findZ3)

----------------------------------------------------------------------------
-- The honest bound
----------------------------------------------------------------------------

-- | What a run does and does not establish; the @--help@ footer.
coverageBound :: String
coverageBound =
  unlines
    [ "WHAT THIS COVERS, AND WHAT IT DOES NOT"
    , ""
    , "  The cover points of a decision are the separate yes-or-no conditions in"
    , "  the conditions it branches on (an UNLESS chain, a BRANCH or IF, or the"
    , "  body of a BOOLEAN decision): `a OR b' is two, a condition used twice is"
    , "  one. A bucket is one combination of their truth values; with n cover"
    , "  points there are 2^n buckets, and past 12 the decision is covered by"
    , "  its conditions as written instead."
    , ""
    , "  WITNESSED means an input realises the bucket and the evaluator agrees;"
    , "  the inputs come from a fixed set of candidates (each number the rule"
    , "  mentions, one either side of it, zero, both truth values, every"
    , "  constructor), at most 8 per bucket, so the witnesses do not depend on"
    , "  the solver. PROVED IMPOSSIBLE is the solver's claim alone: nothing"
    , "  else checks it. UNDECIDED is neither, with its reason, and is never"
    , "  counted as covered."
    , ""
    -- The next paragraph came after the example run that was ruled on, and
    -- was ruled separately (CROSSWORD).
    , "  An input that no condition reads is tried at one value only (zero, for"
    , "  a number), so a bucket whose answer varies with such an input shows"
    , "  one answer; the report names those inputs. When the inputs that"
    , "  realise one bucket give different answers, the row says so and shows"
    , "  an input for each answer."
    , ""
    , "  A call to another rule is one cover point and its body is not read."
    , "  A condition inside the result of an arm, or a condition that raises at"
    , "  an input where an earlier condition of its rung already decides it,"
    , "  is not a cover point; the second keeps the decision at rung level."
    , "  A decision that reads an ASSUME is not covered, since a witness"
    , "  cannot supply one."
    , ""
    , "  Exit status: 0 every decision covered at leaf level and every bucket"
    , "  witnessed or proved impossible; 1 the file does not type-check or an"
    , "  option names no decision; 2 some bucket undecided; 3 none undecided,"
    , "  but some decision covered only at rung level or not at all."
    ]

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data CoverageOptions = CoverageOptions
  { covFile      :: FilePath
  , covDecisions :: [Text]
  , covAll       :: Bool
  , covJson      :: Bool
  , covTimeout   :: Int
  , covFixedNow  :: FixedNowOpt
  }

coverageOptionsParser :: Parser CoverageOptions
coverageOptionsParser = CoverageOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file")
  <*> many (strOption
        ( long "decision"
       <> metavar "NAME"
       <> help "Cover only this decision (repeat for several); the default is every DECIDE of the file that branches on a condition"
        ))
  <*> switch
        ( long "all"
       <> help "List every witness of every bucket, and every bucket proved impossible, not the first witness and the first few"
        )
  <*> switch (long "json" <> help "Write the report as JSON to standard output; the coverage line goes to standard error")
  <*> option auto
        ( long "timeout"
       <> metavar "SECONDS"
       <> value 10
       <> showDefault
       <> help "Give the solver this long per bucket; past it the bucket is undecided"
        )
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

-- | What one decision came to.
data Outcome
  = Covered (Cover Text)
  | NotCovered Text

data Entry = Entry
  { enName   :: Text
  , enRange  :: Maybe SrcRange
  , enParams :: [Text]
  , enUnread :: [Text]
    -- ^ the inputs no cover point mentions: they are tried at one value, so
    -- the answer can vary with them where the report shows one
  , enResult :: Outcome
  }

coverageCmd :: CoverageOptions -> IO ()
coverageCmd opts = do
  evalConfig <- makeEvalConfig opts.covFixedNow
  (errs, res) <- runOneshot evalConfig opts.covFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mtc <- Shake.use Rules.SuccessfulTypeCheck uri
    imports <- fromMaybe [] <$> Shake.use Rules.GetImports uri
    deps <- catMaybes <$> Shake.uses Rules.GetLazyEvaluationDependenciesFile (map (.moduleUri) imports)
    pure (mtc, mconcat (map fst deps))
  case res of
    (Nothing, _) -> do
      putDiagnostics errs
      exitWith (ExitFailure 1)
    (Just tc, importEnv) -> do
      let all' = decideTargets tc
          wanted = opts.covDecisions
          unknown = [ n | n <- wanted, n `notElem` map fst all' ]
      unless (null unknown) $ do
        hPutStrLn stderr ("l4 coverage: no decision named " <> Text.unpack (Text.intercalate ", " unknown)
                          <> " in " <> opts.covFile)
        exitWith (ExitFailure 1)
      let chosen = [ t | t@(n, _) <- all', null wanted || n `elem` wanted ]
      msolver <- either (const Nothing) Just <$> findZ3
      let fields = extractConstructorFieldNames tc.entityInfo
          ce = CoverEnv
            { ceEval = evalConfig, ceTc = tc, ceImportEnv = importEnv
            , ceSolver = msolver, ceSolverSecs = opts.covTimeout
            , ceAnswer = \nf -> Just (Text.strip (prettyLayoutNF fields nf))
            , ceFallbackOnUndecided = False }
      entries <- for chosen \(name, mt) -> case mt of
        Left why -> pure (Entry name Nothing [] [] (NotCovered why))
        Right (rng, params, target) -> do
          r <- coverTarget ce target
          pure (Entry name rng params (either (const []) (unreadBy target) r) (either NotCovered Covered r))
      let (silent, shown) = partitionEntries (null wanted) entries
          solverNote = fmap (.solverVersion) msolver
          line = coverageLine solverNote (length silent) shown
          status = statusOf shown
      if opts.covJson
        then do
          BSL8.putStrLn (AesonPretty.encodePretty' jsonConfig (reportJson opts solverNote (length silent) shown line))
          Text.hPutStrLn stderr line
        else do
          Text.putStr (Text.unlines (renderReport opts shown))
          Text.putStrLn line
      exitWith status

-- | The inputs of a target that none of a cover's points mentions.
-- Naming them in the report is ruled (CROSSWORD; CATALA-EXPORT-SPEC §8.4).
unreadBy :: CoverTarget -> Cover Text -> [Text]
unreadBy t c =
  [ nameToText (getOriginal n) | (n, _) <- t.ctParams, not (Set.member (getUnique n) mentioned) ]
 where
  mentioned = Set.fromList [ getUnique r | p <- c.cvPoints, r <- toList p.cpExpr ]

-- | Without @--decision@, a decision with no condition to branch on is not
-- listed one by one (a file's arithmetic helpers would drown the report); it
-- is counted on the coverage line. A decision named by @--decision@ is always
-- listed, with its reason.
partitionEntries :: Bool -> [Entry] -> ([Entry], [Entry])
partitionEntries unfiltered es
  | unfiltered = ([ e | e <- es, isNoCondition e ], [ e | e <- es, not (isNoCondition e) ])
  | otherwise = ([], es)
 where
  isNoCondition e = case e.enResult of
    NotCovered why -> why == noConditionReason
    _ -> False

noConditionReason :: Text
noConditionReason = "it branches on no condition"

-- | Every top-level DECIDE of the module, by name, with what covering it needs
-- or why it cannot be covered.
decideTargets
  :: Rules.TypeCheckResult
  -> [(Text, Either Text (Maybe SrcRange, [Text], CoverTarget))]
decideTargets tc =
  [ (nameText fnRes, build d)
  | d@(MkDecide _ _ (MkAppForm _ fnRes _ _) _) <- foldTopLevelDecides (: []) tc.module' ]
 where
  mods = tc.module' : map (.module') (Rules.transitiveDependencies tc)
  nameText = nameToText . getOriginal
  assumeUniques = Set.fromList
    [ getUnique n | m <- mods, MkAssume _ _ (MkAppForm _ n _ _) _ _ <- _foldNodeType (: []) m :: [Assume Resolved] ]
  refsOf = Map.fromList
    [ (getUnique fn, Set.fromList (map getUnique (toList body)))
    | m <- mods, MkDecide _ _ (MkAppForm _ fn _ _) body <- foldTopLevelDecides (: []) m ]
  reaches seen [] = seen
  reaches seen (u : us)
    | Set.member u seen = reaches seen us
    | otherwise = reaches (Set.insert u seen) (Set.toList (Map.findWithDefault Set.empty u refsOf) <> us)
  readsAssume fn = not (Set.null (Set.intersection assumeUniques (reaches Set.empty [getUnique fn])))

  build d@(MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth) (MkAppForm _ fnRes appArgs _) body) =
    case rungsOf (isBoolean mGiveth) body of
      Nothing | wrapped body -> Left "its body is wrapped in WHERE or LET, which this report does not look inside unless the decision is BOOLEAN"
              | otherwise -> Left noConditionReason
      Just [] -> Left noConditionReason
      Just rungs
        | readsAssume fnRes -> Left "it reads an ASSUME, which a witness input cannot supply"
        | otherwise -> Right
            ( rangeOf d
            , [ nameToText (getOriginal n) | MkOptionallyTypedName _ n _ _ <- givens ]
            , CoverTarget
                { ctName = fnRes, ctDecide = d
                , ctParams = [ (n, ty) | MkOptionallyTypedName _ n ty _ <- givens ]
                , ctAppArgs = appArgs, ctRungs = rungs, ctReadsAssumes = False } )
  isBoolean = \case
    Just (MkGivethSig _ (TyApp _ r [])) -> getUnique r == TC.booleanUnique
    _ -> False
  wrapped = \case
    Where {} -> True
    LetIn {} -> True
    _ -> False

----------------------------------------------------------------------------
-- Status and the coverage line
----------------------------------------------------------------------------

statusOf :: [Entry] -> ExitCode
statusOf es
  | any undecided covers = ExitFailure 2
  | any coarse es = ExitFailure 3
  -- a run that covered nothing is not a complete one: the line says so, and
  -- so does the status
  | null covers = ExitFailure 3
  | otherwise = ExitSuccess
 where
  covers = [ c | Entry { enResult = Covered c } <- es ]
  undecided = hasUndecided
  coarse e = case e.enResult of
    NotCovered _ -> True
    Covered c -> c.cvLevel /= LeafLevel

-- | The coverage line, in the house style of @l4 explore@: what was covered,
-- and in capitals what was not.
coverageLine :: Maybe Text -> Int -> [Entry] -> Text
coverageLine solver silent es = "Coverage: " <> Text.intercalate "; " (filter (not . Text.null) (
  if null covers
    then [ "NOTHING COVERED" ] <> skipped <> unlisted
    else
      [ count (length covers) "decision" <> " covered (" <> count points "cover point" <> ", " <> count buckets "bucket" <> ")"
      , tshow witnessed <> " witnessed by " <> count witnesses "input" <> ", at most " <> tshow perCombination <> " per bucket"
      , tshow impossible <> " proved impossible" <> (if impossible > 0 then maybe " (no solver)" (\ v -> " by " <> solverName v <> ", whose claim it is alone") solver else "")
      , if undecided == 0 then "nothing undecided" else "UNDECIDED " <> tshow undecided
      , case [ e | e@Entry { enResult = Covered c } <- es, c.cvLevel /= LeafLevel ] of
          [] -> "every decision at leaf level"
          rs -> "AT RUNG LEVEL: " <> Text.intercalate ", " [ "`" <> e.enName <> "`" | e <- rs ]
      ] <> skipped <> unlisted <>
      [ "a call to another rule is one cover point, and conditions inside an arm's result are not cover points" ])) <> "."
 where
  skipped = [ case [ e | e@Entry { enResult = NotCovered _ } <- es ] of
                [] -> "nothing skipped"
                ns -> "NOT COVERED: " <> Text.intercalate ", " [ "`" <> e.enName <> "`" | e <- ns ] ]
  unlisted = [ count silent "decision" <> " with no condition to branch on not listed" | silent > 0 ]
  covers = [ c | Entry { enResult = Covered c } <- es ]
  points = sum [ length c.cvPoints | c <- covers ]
  buckets = sum [ length c.cvBuckets | c <- covers ]
  statuses = [ b.bkStatus | c <- covers, b <- c.cvBuckets ]
  witnessed = length [ () | Witnessed _ <- statuses ]
  witnesses = sum [ length rs | Witnessed rs <- statuses ]
  impossible = length [ () | Impossible <- statuses ]
  undecided = length [ () | Undecided _ <- statuses ]
  -- "Z3 version 4.16.0 - 64 bit" is more than a reader needs
  solverName v = Text.strip (Text.replace " - 64 bit" "" v)

count :: Int -> Text -> Text
count n w = tshow n <> " " <> w <> (if n == 1 then "" else "s")

tshow :: Show a => a -> Text
tshow = Text.pack . show

----------------------------------------------------------------------------
-- The text report
----------------------------------------------------------------------------

renderReport :: CoverageOptions -> [Entry] -> [Text]
renderReport opts es =
  ["l4 coverage: " <> Text.pack opts.covFile] <> concatMap (("" :) . renderEntry opts) es <> [""]

renderEntry :: CoverageOptions -> Entry -> [Text]
renderEntry opts e = case e.enResult of
  NotCovered why ->
    ["Decision `" <> e.enName <> "`" <> at e.enRange, "  NOT COVERED: " <> why <> "."]
  Covered c ->
    [ "Decision `" <> e.enName <> "`" <> at e.enRange ]
    <> [ "  Inputs: " <> Text.intercalate ", " (map name' e.enParams) | not (null e.enParams) ]
    <> [ "  Inputs no condition reads (tried at one value only, so the answers below may vary with them): "
           <> Text.intercalate ", " e.enUnread
       | not (null e.enUnread) ]
    <> levelLine c
    <> [ "  Cover points (" <> tshow (length c.cvPoints) <> "):" ]
    <> [ "    " <> pointId i <> "  " <> padTo textWidth p.cpText <> maybe "" (("  " <>) . prettySrcRange) p.cpRange
       | (i, p) <- zip [0 :: Int ..] c.cvPoints ]
    <> [ "" ]
    <> [ "  Buckets (" <> bucketSummary c <> "):" ]
    <> [ "    " <> Text.unwords (map (padTo 2 . pointId) [0 .. length c.cvPoints - 1]) <> "   status" ]
    <> concatMap (bucketLines opts e.enParams) (shownBuckets opts c)
    <> omitted opts c
 where
  textWidth = maximum (1 : [ Text.length p.cpText | Covered c' <- [e.enResult], p <- c'.cvPoints ])
  name' n = n
  at = maybe "" (\ r -> "  (" <> prettySrcRange r <> ")")
  levelLine c = case c.cvLevel of
    LeafLevel -> []
    RungLevel why ->
      [ "  AT RUNG LEVEL: the cover points below are the conditions as written, not the separate"
      , "  conditions inside them: " <> why <> "." ]

pointId :: Int -> Text
pointId i = "c" <> tshow i

padTo :: Int -> Text -> Text
padTo n t = t <> Text.replicate (n - Text.length t) " "

bucketSummary :: Cover Text -> Text
bucketSummary c =
  tshow (length c.cvBuckets) <> " combinations: " <> tshow w <> " witnessed, " <> tshow i <> " proved impossible, "
    <> (if u == 0 then "none undecided" else tshow u <> " UNDECIDED")
 where
  ss = [ b.bkStatus | b <- c.cvBuckets ]
  w = length [ () | Witnessed _ <- ss ]
  i = length [ () | Impossible <- ss ]
  u = length [ () | Undecided _ <- ss ]

-- | Impossible buckets are listed in full only with @--all@: a nine-band rate
-- table has 502 of them, and they are one claim, not 502.
impossibleShown :: Int
impossibleShown = 16

shownBuckets :: CoverageOptions -> Cover Text -> [Bucket Text]
shownBuckets opts c = [ b | b <- sorted, keep b ]
 where
  sorted = sortOn (.bkAssignment) c.cvBuckets
  impossibles = [ b.bkAssignment | b <- sorted, Impossible <- [b.bkStatus] ]
  kept = Set.fromList (take impossibleShown impossibles)
  keep b = case b.bkStatus of
    Impossible -> opts.covAll || Set.member b.bkAssignment kept
    _ -> True

omitted :: CoverageOptions -> Cover Text -> [Text]
omitted opts c
  | opts.covAll || n <= impossibleShown = []
  | otherwise =
      [ "    ... and " <> tshow (n - impossibleShown) <> " more proved impossible (--all lists them, --json carries them)" ]
 where
  n = length [ () | Bucket _ Impossible <- c.cvBuckets ]

bucketLines :: CoverageOptions -> [Text] -> Bucket Text -> [Text]
bucketLines opts params b = case b.bkStatus of
  Impossible ->
    [ row <> "   proved impossible: no input makes these conditions hold together" ]
  Undecided why ->
    [ row <> "   UNDECIDED: " <> why ]
  Witnessed rows -> case distinct [ r.rowAnswer | r <- rows ] of
    [one] ->
      (row <> "   witnessed by " <> count (length rows) "input" <> "; L4 answers " <> one)
        : [ "          " <> witnessText params r | r <- (if opts.covAll then rows else take 1 rows) ]
    answers ->
      -- the answer varies inside the bucket (it depends on more than the
      -- conditions decide), so it is not one value: say so, and show an input
      -- for each value (all of them with --all).
      (row <> "   witnessed by " <> count (length rows) "input" <> "; L4's answer DIFFERS across them: "
         <> count (length answers) "different value" <> " (" <> Text.intercalate ", " (take 3 answers)
         <> (if length answers > 3 then ", ..." else "") <> ")")
        : [ "          " <> witnessText params r
          | r <- if opts.covAll then rows else firstOfEach rows ]
 where
  row = "    " <> Text.unwords (map (padTo 2 . (\ x -> if x then "T" else "F")) b.bkAssignment)
  distinct = foldr (\ x acc -> x : filter (/= x) acc) []
  -- the first witness for each distinct answer, in order, at most three
  firstOfEach rs = take 3 [ r | (k, r) <- zip [0 :: Int ..] rs, r.rowAnswer `notElem` map (.rowAnswer) (take k rs) ]

witnessText :: [Text] -> Row Text -> Text
witnessText params r =
  Text.intercalate ", " [ n <> " = " <> v | (n, v) <- zip (params <> repeat "_") r.rowArgsText ]
    <> " gives " <> r.rowAnswer
    <> (if r.rowFromSolver then " (found by the solver: no candidate input realises this bucket)" else "")

----------------------------------------------------------------------------
-- JSON
----------------------------------------------------------------------------

jsonConfig :: AesonPretty.Config
jsonConfig = AesonPretty.defConfig { AesonPretty.confIndent = AesonPretty.Spaces 2, AesonPretty.confCompare = compare }

reportJson :: CoverageOptions -> Maybe Text -> Int -> [Entry] -> Text -> Aeson.Value
reportJson opts solver silent es line = Aeson.object
  [ "file" .= opts.covFile
  , "solver" .= solver
  , "decisions" .= map entryJson es
  , "withoutCondition" .= silent
  , "coverage" .= line
  ]

entryJson :: Entry -> Aeson.Value
entryJson e = case e.enResult of
  NotCovered why -> Aeson.object
    [ "name" .= e.enName, "range" .= fmap prettySrcRange e.enRange, "covered" .= False, "why" .= why ]
  Covered c -> Aeson.object
    [ "name" .= e.enName
    , "range" .= fmap prettySrcRange e.enRange
    , "covered" .= True
    , "level" .= (case c.cvLevel of LeafLevel -> "leaf" :: Text; RungLevel _ -> "rung")
    , "levelReason" .= (case c.cvLevel of LeafLevel -> Nothing; RungLevel why -> Just why)
    , "inputs" .= e.enParams
    , "inputsNoConditionReads" .= e.enUnread
    , "coverPoints" .=
        [ Aeson.object [ "id" .= pointId i, "text" .= p.cpText, "atomId" .= p.cpAtomId, "range" .= fmap prettySrcRange p.cpRange ]
        | (i, p) <- zip [0 :: Int ..] c.cvPoints ]
    , "buckets" .= [ bucketJson e.enParams b | b <- sortOn (.bkAssignment) c.cvBuckets ]
    ]

bucketJson :: [Text] -> Bucket Text -> Aeson.Value
bucketJson params b = Aeson.object (("assignment" .= b.bkAssignment) : case b.bkStatus of
  Impossible -> [ "status" .= ("proved impossible" :: Text) ]
  Undecided why -> [ "status" .= ("undecided" :: Text), "why" .= why ]
  Witnessed rows ->
    [ "status" .= ("witnessed" :: Text)
    , "witnesses" .=
        [ Aeson.object
            [ "inputs" .= Aeson.object [ Key.fromText n .= v | (n, v) <- zip params r.rowArgsText ]
            , "answer" .= r.rowAnswer
            , "foundBySolver" .= r.rowFromSolver ]
        | r <- rows ]
    ])
