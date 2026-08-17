{-# LANGUAGE NamedFieldPuns #-}

-- | @m3-measure@ — does information-gain question ordering ask fewer questions
-- than L4 declaration order?
--
-- == Why this exists
--
-- The docassemble backend spec gates milestone M3 (embedding the compiled
-- decision query and a Python port of the info-gain ranker into the generated
-- interview) on a MEASURED demo: plan-driven ordering must ask strictly fewer
-- questions than declaration order on real corpus. This program is that
-- measurement, and it is committed rather than run once and quoted so that the
-- number that decides a milestone can be re-derived by someone else.
--
-- It is not a test. It has no pass/fail; it emits a table.
--
-- == What it compares
--
-- Two askers over the SAME boolean skeleton — the ladder's AND\/OR normal form
-- of a top-level @DECIDE@, which is the same skeleton @l4 verify@ analyses and
-- the same one the web wizard plans over:
--
-- [@decl@] Declaration order. The boolean expression evaluated lazily,
--   left-to-right, with @AND@\/@OR@ short-circuit and the seam's
--   @scope IMPLIES requirement@ read as "ask scope; ask requirement only if
--   scope holds". An atom is asked the moment its value is demanded and not
--   before. This is the shape the emitted docassemble interview has, because
--   the emitter compiles each decision to a Python expression evaluated by the
--   same rules (see @L4.Cli.Docassemble@), and it is validated against the real
--   interview by @etc\/m3-baseline-check.py@.
--
-- [@plan@] Plan order. Repeatedly call 'BDQ.queryDecision' on what is known so
--   far and ask its top-'ranked' atom — which is the atom with the highest
--   information gain about the VERDICT, ties broken by declaration order.
--
-- == The stopping rule is shared, deliberately
--
-- Both askers stop on the same predicate: 'BDQ.Verdict' settled, i.e. not
-- 'BDQ.Undetermined'. NOT on @determined@. For a seam, @Complies@ and
-- @NotApplicable@ are both @determined = Just True@ (see the haddock on
-- 'BDQ.QueryOutcome'), so an asker that stopped on @determined@ would quit on a
-- different question from one that stopped on the verdict, and the difference
-- between the two askers would be an artifact of the stopping rule rather than
-- of the ordering. Same predicate, evaluated the same way, from the same BDD.
--
-- Because the stopping predicate is read off the BDD rather than off the lazy
-- evaluator, @decl@ can occasionally stop EARLIER than a literal lazy walk
-- would: @p AND NOT p@ compiles to the constant-false diagram, so the verdict is
-- settled before any question. That divergence is measured rather than argued —
-- see @declLazyOnlyMean@, the count from a lazy walk with no verdict pre-check.
--
-- == The unit, stated once
--
-- One "question" is one ATOM CLASS of the ladder: a leaf of the AND\/OR normal
-- form, after merging leaves that share an atomId (the same coalescing
-- @l4 verify@ does, and the same notion of sameness a wizard user answers once).
-- It is exactly @l4 verify@'s @atomClasses@.
--
-- An atom class is NOT one docassemble question. A ladder atom is a named
-- predicate; a docassemble question is a record FIELD, and the map is
-- one-to-many — the emitter inlines @WHERE@-bound @MEANS@ that the ladder keeps
-- as a single leaf. @seam.l4@ has two atom classes and its interview asks three
-- questions.
--
-- This program therefore also reports, for both askers, the count of distinct
-- INPUT REFS the ladder recorded for the atoms asked (@declRefsMean@ \/
-- @planRefsMean@, transitively closed through @varDepsByUnique@). Read that as a
-- second, coarser handle on the same comparison and NOT as a question count: the
-- ladder's ref map is measurably incomplete. On @seam.l4@ it records @t@ (the
-- whole record, no path) for the scope atom and only
-- @t.written notice was given@ for the requirement atom, missing
-- @t.months of notice given@ — so it under-counts a known 3-question interview
-- as 2. The reconciliation of atoms to real questions is done EMPIRICALLY
-- instead, by driving the emitted interviews; see @etc\/m3-baseline-check.py@.
-- Both askers are charged identically either way, so the comparison is fair at
-- either granularity; only the absolute numbers differ.
--
-- == Sampling
--
-- A "world" is a total assignment of the atom classes. For a decision with at
-- most @--exhaustive-max@ atoms every world is enumerated, which removes a whole
-- class of doubt. Above that, worlds are sampled from a fixed seed.
--
-- Two weightings are reported side by side, because the ranker consumes the same
-- @TYPICALLY@ priors that a prior-weighted world distribution would be drawn
-- from, and testing a planner on its own assumptions flatters it:
--
--   * @uniform@ — every world equally likely.
--   * @prior@ — world probability is the product of the per-atom @TYPICALLY@
--     priors (0.9 \/ 0.1), 0.5 for an atom with no prior.
--
-- When a decision has NO priors the two are identical by construction, and the
-- emitted @priors@ column says so per decision rather than leaving a reader to
-- infer it from two equal numbers.
module Main (main) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import Data.Bits (shiftL, shiftR, xor)
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.IntMap.Lazy as IntMap
import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Word (Word64)
import Options.Applicative

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import qualified Language.LSP.Protocol.Types as LSP
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import qualified L4.Decision.BooleanDecisionQuery as BDQ
import qualified L4.Decision.QueryPlan as QP
import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.QueryPlan as VizQP
import qualified LSP.L4.Viz.VizExpr as VizExpr

import L4.Print (prettyLayout)
import L4.Syntax

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data Options = Options
  { optFiles :: [FilePath]
  , optMaxNodes :: Int
  , optExhaustiveMax :: Int
  , optSamples :: Int
  , optSeed :: Word64
  , optOutJson :: Maybe FilePath
  , optOutCsv :: Maybe FilePath
  , optTraces :: Bool
  }

optionsParser :: Parser Options
optionsParser =
  Options
    <$> some (argument str (metavar "FILE..." <> help "L4 corpus files to measure"))
    <*> option
      auto
      ( long "max-nodes"
          <> value 4096
          <> showDefault
          <> metavar "N"
          <> help "Refuse a ladder with more than N nodes, exactly as `l4 verify` does."
      )
    <*> option
      auto
      ( long "exhaustive-max"
          <> value 12
          <> showDefault
          <> metavar "N"
          <> help "Enumerate all 2^k worlds when a decision has at most N atom classes; sample above."
      )
    <*> option
      auto
      ( long "samples"
          <> value 2000
          <> showDefault
          <> metavar "N"
          <> help "Worlds to draw per weighting when not exhaustive."
      )
    <*> option
      auto
      ( long "seed"
          <> value 20260817
          <> showDefault
          <> metavar "N"
          <> help "PRNG seed. The generator is a xorshift64* written out in this file, so a run reproduces anywhere."
      )
    <*> optional (strOption (long "json" <> metavar "FILE" <> help "Write the full per-decision record here."))
    <*> optional (strOption (long "csv" <> metavar "FILE" <> help "Write the per-decision table here."))
    <*> switch (long "traces" <> help "Include per-world ask traces for decisions with at most 6 atom classes (for baseline validation).")

----------------------------------------------------------------------------
-- The measured record
----------------------------------------------------------------------------

-- | One atom class, as the measurement sees it.
data AtomInfo = AtomInfo
  { aiUnique :: Int
  , aiLabel :: Text
  , aiRefs :: [Text]
  -- ^ Rendered transitive input refs — the record fields a docassemble
  -- interview would have to ask to settle this atom. @rootLabel.path.path@.
  , aiPrior :: Maybe Double
  }

data Counts = Counts
  { cAtoms :: Double
  , cFields :: Double
  , cLazyOnly :: Double
  }

data Weighted = Weighted
  { wDeclAtoms :: Double
  , wPlanAtoms :: Double
  , wDeclFields :: Double
  , wPlanFields :: Double
  , wDeclLazyOnly :: Double
  , wWins :: Double
  -- ^ probability mass of worlds where plan asks strictly fewer atoms
  , wTies :: Double
  , wLosses :: Double
  , wFieldWins :: Double
  , wFieldTies :: Double
  , wFieldLosses :: Double
  }

data Measured = Measured
  { mAtomClasses :: Int
  , mAtomsRaw :: Int
  , mLadderNodes :: Int
  , mAtomInfo :: [AtomInfo]
  , mPriorCount :: Int
  , mSampling :: Text
  , mWorlds :: Int
  , mUniform :: Weighted
  , mPrior :: Weighted
  , mWorstDecl :: Int
  , mWorstPlan :: Int
  , mWorstDeclFields :: Int
  , mWorstPlanFields :: Int
  , mAnomalies :: [Text]
  , mTraces :: [(Text, [Text], [Text])]
  -- ^ (world as a bit string over atom order, decl ask sequence, plan ask sequence)
  }

data Row = Row
  { rFile :: FilePath
  , rName :: Text
  , rOutcome :: Either Text Measured
  -- ^ @Left@ is a refusal, carrying its reason verbatim.
  }

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

main :: IO ()
main = do
  opts <- execParser (info (optionsParser <**> helper) (fullDesc <> progDesc "M3 gate: information-gain question ordering vs L4 declaration order."))
  rows <- concat <$> traverse (measureFile opts) opts.optFiles
  case opts.optOutCsv of
    Nothing -> pure ()
    Just f -> Text.writeFile f (renderCsv rows)
  case opts.optOutJson of
    Nothing -> pure ()
    Just f -> BSL8.writeFile f (Aeson.encode (Aeson.object ["seed" .= opts.optSeed, "exhaustiveMax" .= opts.optExhaustiveMax, "samples" .= opts.optSamples, "maxNodes" .= opts.optMaxNodes, "decisions" .= map rowJson rows]))
  Text.putStr (renderSummary rows)

measureFile :: Options -> FilePath -> IO [Row]
measureFile opts file = do
  hPutStrLn stderr ("m3-measure: " <> file)
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig file \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri
  case mTc of
    Nothing -> do
      putDiagnostics errs
      pure [Row file (Text.pack file) (Left "file did not type-check")]
    Just tc -> pure [measureDecide opts file tc dec | dec <- foldTopLevelDecides (\x -> [x]) tc.module']

measureDecide :: Options -> FilePath -> Rules.TypeCheckResult -> Decide Resolved -> Row
measureDecide opts file tc decide =
  case LadderViz.doVisualize decide vizCfg of
    Left err -> Row file astName (Left (LadderViz.prettyPrintVizError err))
    Right (ladderInfo, vizState)
      | nodes > opts.optMaxNodes ->
          Row
            file
            fnName
            ( Left
                ( "ladder exceeds --max-nodes="
                    <> Text.pack (show opts.optMaxNodes)
                )
            )
      | otherwise -> Row file fnName (Right (runMeasurement opts ladderInfo vizState))
      where
        nodes = ladderNodeCount opts.optMaxNodes ladderInfo.funDecl.body
        fnName = ladderInfo.funDecl.fnName.label
  where
    vizCfg = LadderViz.mkVizConfig verDocId tc.module' tc.substitution True
    verDocId =
      LSP.VersionedTextDocumentIdentifier
        { LSP._uri = LSP.filePathToUri file
        , LSP._version = 1
        }
    astName = case decide of
      MkDecide _ _ (MkAppForm _ n _ _) _ -> prettyLayout (getOriginal n)

-- | Node count of a ladder body, fuel-limited. Copied from @L4.Cli.Verify@ so
-- the two commands refuse the same ladders; if that copy ever drifts the two
-- would disagree about which decisions exist, which is worse than the
-- duplication.
ladderNodeCount :: Int -> VizExpr.IRExpr -> Int
ladderNodeCount budget root = go 0 [root]
  where
    go n _ | n > budget = n
    go n [] = n
    go n (e : rest) = go (n + 1) (children e <> rest)
    children = \case
      VizExpr.And _ xs -> xs
      VizExpr.Or _ xs -> xs
      VizExpr.Not _ x -> [x]
      VizExpr.Implies _ s r _ -> [s, r]
      VizExpr.App _ _ args _ -> args
      VizExpr.UBoolVar{} -> []
      VizExpr.TrueE{} -> []
      VizExpr.FalseE{} -> []
      VizExpr.InertE{} -> []

----------------------------------------------------------------------------
-- Atom coalescing (mirror of L4.Cli.Verify)
----------------------------------------------------------------------------

coalesceByAtomId ::
  Map Int Text ->
  BDQ.BoolExpr Int ->
  Map Int Text ->
  [Int] ->
  (BDQ.BoolExpr Int, Map Int Text, [Int], Int -> Int)
coalesceByAtomId atomIds expr labels order =
  (mapVars rep expr, labels', order', rep)
  where
    repOf = Map.fromListWith (\_new old -> old) [(aid, u) | u <- order, Just aid <- [Map.lookup u atomIds]]
    rep u = fromMaybe u (Map.lookup u atomIds >>= \aid -> Map.lookup aid repOf)
    order' = nubOrd (fmap rep order)
    labels' = Map.fromList [(u, lbl) | (u, lbl) <- Map.toList labels, rep u == u]

mapVars :: (Int -> Int) -> BDQ.BoolExpr Int -> BDQ.BoolExpr Int
mapVars f = \case
  BDQ.BTrue -> BDQ.BTrue
  BDQ.BFalse -> BDQ.BFalse
  BDQ.BVar v -> BDQ.BVar (f v)
  BDQ.BNot e -> BDQ.BNot (mapVars f e)
  BDQ.BAnd es -> BDQ.BAnd (fmap (mapVars f) es)
  BDQ.BOr es -> BDQ.BOr (fmap (mapVars f) es)
  BDQ.BImplies p q -> BDQ.BImplies (mapVars f p) (mapVars f q)

----------------------------------------------------------------------------
-- Input-ref closure (mirror of the private closure in L4.Decision.QueryPlan)
----------------------------------------------------------------------------

-- | Transitive input refs per atom unique: an atom's own refs, plus the refs of
-- every atom it depends on. This is the same closure @QP.atomIdByUnique@ takes,
-- and it is the set of record fields a wizard has to fill in to settle the atom.
refsClosure :: QP.CachedDecisionQuery -> IntMap.IntMap (Set QP.InputRef)
refsClosure cached = foldl' (\memo u -> snd (go memo IntSet.empty u)) IntMap.empty allUniques
  where
    depMap = cached.varDepsByUnique
    directRefs = cached.varInputRefsByUnique
    allUniques =
      IntSet.toList $
        IntSet.fromList (Map.keys cached.varLabelByUnique)
          <> IntSet.fromList (IntMap.keys depMap)
          <> IntSet.fromList (IntMap.keys directRefs)
          <> IntSet.unions (IntMap.elems depMap)
    go memo visiting u
      | u `IntSet.member` visiting = (Set.empty, memo)
      | otherwise = case IntMap.lookup u memo of
          Just cachedRefs -> (cachedRefs, memo)
          Nothing ->
            let visiting' = IntSet.insert u visiting
                own = IntMap.findWithDefault Set.empty u directRefs
                deps = IntSet.toList (IntMap.findWithDefault IntSet.empty u depMap)
                (fromDeps, memo') =
                  foldl'
                    (\(acc, m) d -> let (rs, m') = go m visiting' d in (acc <> rs, m'))
                    (Set.empty, memo)
                    deps
                res = own <> fromDeps
             in (res, IntMap.insert u res memo')

renderRef :: Map Int Text -> QP.InputRef -> Text
renderRef paramsByUnique ref =
  Text.intercalate "." (stripTicks root : map stripTicks ref.path)
  where
    root = Map.findWithDefault (Text.pack (show ref.rootUnique)) ref.rootUnique paramsByUnique
    stripTicks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")

----------------------------------------------------------------------------
-- The two askers
----------------------------------------------------------------------------

-- | The value of a lazily evaluated subexpression, or the first atom whose value
-- it demands.
data Lazy = LVal !Bool | LNeed !Int

-- | Lazy left-to-right evaluation with short-circuit — declaration order.
lazyEval :: Map Int Bool -> BDQ.BoolExpr Int -> Lazy
lazyEval binds = \case
  BDQ.BTrue -> LVal True
  BDQ.BFalse -> LVal False
  BDQ.BVar v -> maybe (LNeed v) LVal (Map.lookup v binds)
  BDQ.BNot e -> case lazyEval binds e of
    LVal x -> LVal (not x)
    need -> need
  BDQ.BAnd es -> goAnd es
  BDQ.BOr es -> goOr es
  -- The seam: ask the scope; a rule that does not reach you never asks after its
  -- requirement. That is exactly what the emitted interview does, and exactly
  -- what 'BDQ.verdictOf' calls NotApplicable.
  BDQ.BImplies scope requirement -> case lazyEval binds scope of
    LVal False -> LVal True
    LVal True -> lazyEval binds requirement
    need -> need
  where
    goAnd [] = LVal True
    goAnd (e : rest) = case lazyEval binds e of
      LVal False -> LVal False
      LVal True -> goAnd rest
      need -> need
    goOr [] = LVal False
    goOr (e : rest) = case lazyEval binds e of
      LVal True -> LVal True
      LVal False -> goOr rest
      need -> need

settled :: BDQ.CompiledDecisionQuery Int -> Map Int Double -> Map Int Bool -> Bool
settled compiled priors binds = (BDQ.queryDecision compiled priors binds).verdict /= BDQ.Undetermined

-- | Declaration-order asker. Stops on the shared predicate (verdict settled),
-- and otherwise asks whatever the lazy evaluator demands next.
askDecl :: BDQ.CompiledDecisionQuery Int -> Map Int Double -> BDQ.BoolExpr Int -> Map Int Bool -> [Int]
askDecl compiled priors expr world = go Map.empty []
  where
    go binds acc
      | settled compiled priors binds = reverse acc
      | otherwise = case lazyEval binds expr of
          LNeed v -> go (Map.insert v (Map.findWithDefault False v world) binds) (v : acc)
          LVal _ -> reverse acc

-- | The same walk with NO verdict pre-check: what a literal lazy evaluator
-- asks. Reported alongside so the effect of the shared stopping rule on the
-- baseline is visible rather than assumed away.
askDeclLazyOnly :: BDQ.BoolExpr Int -> Map Int Bool -> [Int]
askDeclLazyOnly expr world = go Map.empty []
  where
    go binds acc = case lazyEval binds expr of
      LNeed v -> go (Map.insert v (Map.findWithDefault False v world) binds) (v : acc)
      LVal _ -> reverse acc

-- | Plan-order asker: ask the top-ranked atom, restrict, repeat.
askPlan :: BDQ.CompiledDecisionQuery Int -> Map Int Double -> Map Int Bool -> [Int]
askPlan compiled priors world = go Map.empty []
  where
    go binds acc =
      let res = BDQ.queryDecision compiled priors binds
       in if res.verdict /= BDQ.Undetermined
            then reverse acc
            else case res.ranked of
              [] -> reverse acc
              (v : _) -> go (Map.insert v (Map.findWithDefault False v world) binds) (v : acc)

-- | Ref cost of an ask sequence: the distinct input refs the ladder recorded
-- for the atoms asked. NOT a question count -- see the module haddock for the
-- measured incompleteness of the ladder's ref map.
fieldCost :: Map Int (Set Text) -> [Int] -> Int
fieldCost refsBy = Set.size . foldl' (\acc v -> acc <> Map.findWithDefault Set.empty v refsBy) Set.empty

----------------------------------------------------------------------------
-- Worlds
----------------------------------------------------------------------------

-- | xorshift64*, written out so a seeded run reproduces on any machine and in
-- any language. Returns a uniform double in [0,1).
nextD :: Word64 -> (Double, Word64)
nextD s0 =
  let s1 = s0 `xor` (s0 `shiftR` 12)
      s2 = s1 `xor` (s1 `shiftL` 25)
      s3 = s2 `xor` (s2 `shiftR` 27)
      out = s3 * 2685821657736338717
   in (fromIntegral (out `shiftR` 11) / 9007199254740992.0, s3)

sampleWorlds :: Word64 -> Int -> [(Int, Double)] -> [Map Int Bool]
sampleWorlds seed n atomsWithP = go (seed + 1) n
  where
    go _ 0 = []
    go s k =
      let (w, s') = foldl' step (Map.empty, s) atomsWithP
       in w : go s' (k - 1)
    step (acc, s) (v, p) = let (r, s') = nextD s in (Map.insert v (r < p) acc, s')

exhaustiveWorlds :: [Int] -> [Map Int Bool]
exhaustiveWorlds [] = [Map.empty]
exhaustiveWorlds (v : rest) =
  [Map.insert v b w | w <- exhaustiveWorlds rest, b <- [False, True]]

worldWeight :: Map Int Double -> Map Int Bool -> Double
worldWeight priors = Map.foldrWithKey (\v b acc -> acc * (let p = Map.findWithDefault 0.5 v priors in if b then p else 1 - p)) 1

----------------------------------------------------------------------------
-- Running one decision
----------------------------------------------------------------------------

runMeasurement :: Options -> VizExpr.RenderAsLadderInfo -> LadderViz.VizState -> Measured
runMeasurement opts ladderInfo vizState =
  Measured
    { mAtomClasses = nClasses
    , mAtomsRaw = length order
    , mLadderNodes = ladderNodeCount opts.optMaxNodes ladderInfo.funDecl.body
    , mAtomInfo = atomInfos
    , mPriorCount = Map.size priors
    , mSampling = if exhaustive then "exhaustive" else "sampled"
    , mWorlds = length uniformWorlds
    , mUniform = summarise uniformWorlds uniformWeights
    , mPrior = summarise priorWorlds priorWeights
    , mWorstDecl = maximum0 [length (declSeq w) | w <- uniformWorlds]
    , mWorstPlan = maximum0 [length (planSeq w) | w <- uniformWorlds]
    , mWorstDeclFields = maximum0 [fieldCost refsByAtom (declSeq w) | w <- uniformWorlds]
    , mWorstPlanFields = maximum0 [fieldCost refsByAtom (planSeq w) | w <- uniformWorlds]
    , mAnomalies = anomalies
    , mTraces =
        if opts.optTraces && nClasses <= 6
          then
            [ ( Text.pack [if Map.findWithDefault False v w then 'T' else 'F' | v <- order']
              , [labelOf v | v <- declSeq w]
              , [labelOf v | v <- planSeq w]
              )
            | w <- uniformWorlds
            ]
          else []
    }
  where
    body = ladderInfo.funDecl.body
    (boolExpr, labels, order) = VizQP.vizExprToBoolExpr body
    cache = VizQP.buildQueryPlanCache ladderInfo vizState
    paramsBy = VizQP.buildParamsByUnique ladderInfo
    atomIds = QP.atomIdByUnique ladderInfo.funDecl.fnName.label paramsBy cache
    (expr', labels', order', rep) = coalesceByAtomId atomIds boolExpr labels order
    nClasses = length order'

    -- Priors are keyed by the PRE-coalescing unique; re-key them onto the class
    -- representative. Where two merged occurrences disagree (they cannot, since
    -- they are the same leaf, but the type permits it) the first wins.
    priors :: Map Int Double
    priors = Map.fromListWith (\_new old -> old) [(rep u, p) | (u, p) <- Map.toList (VizExpr.boolPriorsFromBody body)]

    closure = refsClosure cache
    refsByAtom :: Map Int (Set Text)
    refsByAtom =
      Map.fromListWith
        (<>)
        [ (rep u, Set.map (renderRef paramsBy) (IntMap.findWithDefault Set.empty u closure))
        | u <- order
        ]

    labelOf v = Map.findWithDefault (Text.pack (show v)) v labels'

    atomInfos =
      [ AtomInfo
          { aiUnique = v
          , aiLabel = labelOf v
          , aiRefs = Set.toList (Map.findWithDefault Set.empty v refsByAtom)
          , aiPrior = Map.lookup v priors
          }
      | v <- order'
      ]

    compiled = BDQ.compileDecisionQuery order' expr'

    exhaustive = nClasses <= opts.optExhaustiveMax
    uniformWorlds
      | exhaustive = exhaustiveWorlds order'
      | otherwise = sampleWorlds opts.optSeed opts.optSamples [(v, 0.5) | v <- order']
    priorWorlds
      | exhaustive = uniformWorlds
      | otherwise = sampleWorlds (opts.optSeed + 7919) opts.optSamples [(v, Map.findWithDefault 0.5 v priors) | v <- order']
    uniformWeights = replicate (length uniformWorlds) 1
    priorWeights
      | exhaustive = map (worldWeight priors) priorWorlds
      | otherwise = replicate (length priorWorlds) 1

    declSeq w = askDecl compiled priors expr' w
    planSeq w = askPlan compiled priors w
    lazySeq w = askDeclLazyOnly expr' w

    countsOf w =
      let d = declSeq w
          p = planSeq w
       in ( Counts (fromIntegral (length d)) (fromIntegral (fieldCost refsByAtom d)) (fromIntegral (length (lazySeq w)))
          , Counts (fromIntegral (length p)) (fromIntegral (fieldCost refsByAtom p)) 0
          )

    summarise ws weights =
      let total = sum weights
          pairs = [(countsOf w, wt) | (w, wt) <- zip ws weights]
          wsum f = sum [f c * wt | (c, wt) <- pairs] / total
          cmp f =
            ( sum [wt | ((dd, pp), wt) <- pairs, f pp < f dd] / total
            , sum [wt | ((dd, pp), wt) <- pairs, f pp == f dd] / total
            , sum [wt | ((dd, pp), wt) <- pairs, f pp > f dd] / total
            )
          (aw, at, al) = cmp (.cAtoms)
          (fw, ft, fl) = cmp (.cFields)
       in Weighted
            { wDeclAtoms = wsum (\(dd, _) -> dd.cAtoms)
            , wPlanAtoms = wsum (\(_, pp) -> pp.cAtoms)
            , wDeclFields = wsum (\(dd, _) -> dd.cFields)
            , wPlanFields = wsum (\(_, pp) -> pp.cFields)
            , wDeclLazyOnly = wsum (\(dd, _) -> dd.cLazyOnly)
            , wWins = aw
            , wTies = at
            , wLosses = al
            , wFieldWins = fw
            , wFieldTies = ft
            , wFieldLosses = fl
            }

    anomalies =
      concat
        [ ["plan asker ran out of ranked atoms with the verdict undetermined" | any stalled uniformWorlds]
        , ["decl asker stopped earlier than a literal lazy walk (BDD saw determinism the evaluator could not)" | any lazier uniformWorlds]
        ]
    stalled w =
      let binds = Map.fromList [(v, Map.findWithDefault False v w) | v <- planSeq w]
       in not (settled compiled priors binds)
    lazier w = length (declSeq w) < length (lazySeq w)

maximum0 :: [Int] -> Int
maximum0 [] = 0
maximum0 xs = maximum xs

----------------------------------------------------------------------------
-- Output
----------------------------------------------------------------------------

rowJson :: Row -> Aeson.Value
rowJson r = case r.rOutcome of
  Left reason -> Aeson.object ["file" .= r.rFile, "decision" .= r.rName, "measured" .= False, "reason" .= reason]
  Right m ->
    Aeson.object
      [ "file" .= r.rFile
      , "decision" .= r.rName
      , "measured" .= True
      , "atomClasses" .= m.mAtomClasses
      , "atomsRaw" .= m.mAtomsRaw
      , "ladderNodes" .= m.mLadderNodes
      , "priors" .= m.mPriorCount
      , "sampling" .= m.mSampling
      , "worlds" .= m.mWorlds
      , "atoms" .= [Aeson.object ["unique" .= a.aiUnique, "label" .= a.aiLabel, "refs" .= a.aiRefs, "prior" .= a.aiPrior] | a <- m.mAtomInfo]
      , "uniform" .= weightedJson m.mUniform
      , "priorWeighted" .= weightedJson m.mPrior
      , "worstCase" .= Aeson.object ["declAtoms" .= m.mWorstDecl, "planAtoms" .= m.mWorstPlan, "declRefs" .= m.mWorstDeclFields, "planRefs" .= m.mWorstPlanFields]
      , "anomalies" .= m.mAnomalies
      , "traces" .= [Aeson.object ["world" .= w, "decl" .= d, "plan" .= p] | (w, d, p) <- m.mTraces]
      ]

weightedJson :: Weighted -> Aeson.Value
weightedJson w =
  Aeson.object
    [ "declAtomsMean" .= w.wDeclAtoms
    , "planAtomsMean" .= w.wPlanAtoms
    , "declRefsMean" .= w.wDeclFields
    , "planRefsMean" .= w.wPlanFields
    , "declLazyOnlyMean" .= w.wDeclLazyOnly
    , "atomWinFrac" .= w.wWins
    , "atomTieFrac" .= w.wTies
    , "atomLossFrac" .= w.wLosses
    , "fieldWinFrac" .= w.wFieldWins
    , "fieldTieFrac" .= w.wFieldTies
    , "fieldLossFrac" .= w.wFieldLosses
    ]

renderCsv :: [Row] -> Text
renderCsv rows = Text.unlines (csvHeader : map line rows)
  where
    csvHeader =
      Text.intercalate
        ","
        [ "file"
        , "decision"
        , "status"
        , "reason"
        , "atomClasses"
        , "atomsRaw"
        , "ladderNodes"
        , "priors"
        , "sampling"
        , "worlds"
        , "declAtomsMean_uniform"
        , "planAtomsMean_uniform"
        , "declAtomsMean_prior"
        , "planAtomsMean_prior"
        , "declRefsMean_uniform"
        , "planRefsMean_uniform"
        , "declLazyOnlyMean_uniform"
        , "atomWinFrac_uniform"
        , "atomTieFrac_uniform"
        , "atomLossFrac_uniform"
        , "worstDeclAtoms"
        , "worstPlanAtoms"
        , "anomalies"
        ]
    line r = case r.rOutcome of
      Left reason -> Text.intercalate "," ([q (Text.pack r.rFile), q r.rName, "refused", q reason] <> replicate 19 "")
      Right m ->
        Text.intercalate
          ","
          [ q (Text.pack r.rFile)
          , q r.rName
          , if m.mAtomClasses == 0 then "measured-no-atoms" else "measured"
          , ""
          , n m.mAtomClasses
          , n m.mAtomsRaw
          , n m.mLadderNodes
          , n m.mPriorCount
          , m.mSampling
          , n m.mWorlds
          , d m.mUniform.wDeclAtoms
          , d m.mUniform.wPlanAtoms
          , d m.mPrior.wDeclAtoms
          , d m.mPrior.wPlanAtoms
          , d m.mUniform.wDeclFields
          , d m.mUniform.wPlanFields
          , d m.mUniform.wDeclLazyOnly
          , d m.mUniform.wWins
          , d m.mUniform.wTies
          , d m.mUniform.wLosses
          , n m.mWorstDecl
          , n m.mWorstPlan
          , q (Text.intercalate "; " m.mAnomalies)
          ]
    n = Text.pack . show
    d x = Text.pack (show (fromIntegral (round (x * 10000) :: Int) / 10000 :: Double))
    q t = "\"" <> Text.replace "\"" "\"\"" t <> "\""

renderSummary :: [Row] -> Text
renderSummary rows =
  Text.unlines $
    [ "decisions seen      : " <> Text.pack (show (length rows))
    , "  refused by ladder : " <> Text.pack (show (length refused))
    , "  measured          : " <> Text.pack (show (length measured))
    , "    with 0 atoms    : " <> Text.pack (show (length [m | m <- measured, m.mAtomClasses == 0]))
    , "    with >= 2 atoms : " <> Text.pack (show (length reorderable))
    , "  decisions carrying any TYPICALLY prior: " <> Text.pack (show (length [m | m <- measured, m.mPriorCount > 0]))
    , ""
    , "Over the " <> Text.pack (show (length reorderable)) <> " decisions with >= 2 atom classes, unweighted across decisions:"
    , "  mean questions, declaration order (uniform worlds) : " <> fmt (avg [m.mUniform.wDeclAtoms | m <- reorderable])
    , "  mean questions, plan order        (uniform worlds) : " <> fmt (avg [m.mUniform.wPlanAtoms | m <- reorderable])
    , "  mean questions, declaration order (prior worlds)   : " <> fmt (avg [m.mPrior.wDeclAtoms | m <- reorderable])
    , "  mean questions, plan order        (prior worlds)   : " <> fmt (avg [m.mPrior.wPlanAtoms | m <- reorderable])
    , ""
    , "Per-decision verdict (uniform worlds, comparing the two means):"
    , "  plan strictly fewer : " <> Text.pack (show (length [m | m <- reorderable, m.mUniform.wPlanAtoms < m.mUniform.wDeclAtoms - 1e-9]))
    , "  tie                 : " <> Text.pack (show (length [m | m <- reorderable, abs (m.mUniform.wPlanAtoms - m.mUniform.wDeclAtoms) <= 1e-9]))
    , "  plan strictly more  : " <> Text.pack (show (length [m | m <- reorderable, m.mUniform.wPlanAtoms > m.mUniform.wDeclAtoms + 1e-9]))
    , ""
    , "World-level mass (uniform), pooled over those decisions:"
    , "  plan fewer : " <> fmt (avg [m.mUniform.wWins | m <- reorderable])
    , "  tie        : " <> fmt (avg [m.mUniform.wTies | m <- reorderable])
    , "  plan more  : " <> fmt (avg [m.mUniform.wLosses | m <- reorderable])
    , ""
    , "Anomalies reported: " <> Text.pack (show (length [m | m <- measured, not (null m.mAnomalies)]))
    ]
  where
    measured = [m | r <- rows, Right m <- [r.rOutcome]]
    refused = [() | r <- rows, Left _ <- [r.rOutcome]]
    reorderable = [m | m <- measured, m.mAtomClasses >= 2]
    avg [] = 0 :: Double
    avg xs = sum xs / fromIntegral (length xs)
    fmt x = Text.pack (show (fromIntegral (round (x * 10000) :: Int) / 10000 :: Double))
