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
-- == THREE askers, not two
--
-- [@decl@] Declaration order. The boolean expression evaluated lazily,
--   left-to-right, with @AND@\/@OR@ short-circuit and the seam's
--   @scope IMPLIES requirement@ read as "ask scope; ask requirement only if
--   scope holds". An atom is asked the moment its value is demanded and not
--   before.
--
-- [@plan@] Plan order — this is M3. Repeatedly call 'BDQ.queryDecision' on what
--   is known so far and ask its top-'ranked' atom, i.e. the atom with the
--   highest information gain about the VERDICT, ties broken by declaration
--   order. Adaptive: the next question depends on the previous answers, so it
--   needs the compiled query and the ranker AT RUNTIME, inside the interview.
--
-- [@stat@] Static order — the cheap alternative M3 has to beat, added in the
--   second run of this measurement (2026-08-17) because reporting only
--   @decl@ vs @plan@ silently assumes the only way to get plan order's benefit
--   is to ship the planner. Each @AND@\/@OR@ node's operands are sorted ONCE,
--   at compile time, by the planner's fresh-state (nothing known) info-gain
--   ranking; then the same lazy declaration-order walk is run over the
--   reordered expression. Stable sort, so atoms the ranker cannot separate keep
--   declaration order. The seam's scope\/requirement split is NOT reordered:
--   asking a rule's requirement before its applicability is a semantic change,
--   not a reordering. This is a pure source-to-source rewrite of the emitted
--   Python expression — no BDD in the artifact, no Python port of the ranker,
--   no second implementation of the semantics to keep in sync.
--
-- == TWO ladder forms, because the baseline must be the EMITTER's shape
--
-- 'LadderViz.doVisualize' takes a @shouldSimplify@ flag. With it on it runs
-- 'L4.Transform.simplify' = @cnf . nnf@, so @(A AND B) OR C@ becomes
-- @(A OR C) AND (B OR C)@. Under a lazy left-to-right walk those two shapes do
-- NOT demand the same atoms: the distributed form can demand an atom the source
-- form never reaches, and the error is one-directional — CNF distribution only
-- ever ADDS demands. Measuring declaration order over the CNF therefore inflates
-- the baseline and flatters the planner, which is exactly the bias this
-- measurement was commissioned to look for.
--
-- @L4.Docassemble.Lower@ compiles from "L4.Syntax" and imports nothing from
-- @LSP.L4.Viz.*@, so a real interview's declaration order is the SOURCE operand
-- order. Both forms are therefore measured and reported side by side:
--
--   * @source@ — @shouldSimplify = False@. The shape the docassemble emitter
--     lowers, and the HEADLINE arm.
--   * @cnf@ — @shouldSimplify = True@. The shape @l4 verify@, the ladder
--     visualiser and the shipped web wizard see. Reported so the size of the
--     distortion is a measured column rather than an argument.
--
-- The BDD is canonical, so @plan@ is only weakly affected by the choice (the
-- ranker's tie-break reads the variable order, which is the nub of the form's
-- left-to-right traversal); @decl@ is strongly affected. Both askers are run
-- inside each form, so within an arm the comparison is like-for-like.
--
-- == The stopping rule is shared, deliberately
--
-- All three askers stop on the same predicate: 'BDQ.Verdict' settled, i.e. not
-- 'BDQ.Undetermined'. NOT on @determined@. For a seam, @Complies@ and
-- @NotApplicable@ are both @determined = Just True@ (see the haddock on
-- 'BDQ.QueryOutcome'), so an asker that stopped on @determined@ would quit on a
-- different question from one that stopped on the verdict, and the difference
-- between the askers would be an artifact of the stopping rule rather than of
-- the ordering. Same predicate, evaluated the same way, from the same BDD.
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
-- questions. It can also run the other way: two @EQUALS@ guards on the same
-- field are two atoms and ONE question.
--
-- This program therefore also reports, for every asker, the count of distinct
-- INPUT REFS the ladder recorded for the atoms asked (@declRefsMean@ \/
-- @planRefsMean@ \/ @statRefsMean@, transitively closed through
-- @varDepsByUnique@). Read that as a second, coarser handle on the same
-- comparison and NOT as a question count: the ladder's ref map is measurably
-- incomplete. On @seam.l4@ it records @t@ (the whole record, no path) for the
-- scope atom and only @t.written notice was given@ for the requirement atom,
-- missing @t.months of notice given@ — so it under-counts a known 3-question
-- interview as 2. The reconciliation of atoms to real questions is done
-- EMPIRICALLY instead, by driving the emitted interviews; see
-- @etc\/m3-baseline-check.py@. Every asker is charged identically either way, so
-- the comparison is fair at either granularity; only the absolute numbers
-- differ.
--
-- == The population is a call graph, not a set of interviews
--
-- 'foldTopLevelDecides' picks up every top-level @DECIDE@\/@MEANS@, so a rule
-- AND each of its helper predicates are separate rows, while the rule charges
-- ONE atom for a helper that costs the user several questions. Two columns make
-- that visible instead of leaving it to be discovered: @exported@ (the decision
-- carries @\@export@, i.e. it is a decision a generated interview can be
-- ENTERED at) and @subPredicate@ (the decision's name occurs inside an atom
-- label of some OTHER measured decision in the same run, i.e. it is also
-- counted as one atom somewhere else). Per-decision means are therefore NOT
-- composable into a per-interview question count, and must not be read as one.
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
import qualified Data.List as List
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

import qualified L4.Export as Export
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
  , optSynthPriors :: Int
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
    <*> option
      auto
      ( long "synthetic-priors"
          <> value 0
          <> showDefault
          <> metavar "N"
          <> help
            ( "Additionally run N draws of SYNTHETIC per-atom priors ~ U(0.05,0.95), fed to BOTH "
                <> "the ranker and the world distribution. The corpus carries no TYPICALLY priors, "
                <> "so without this the uniform and prior-weighted arms coincide by construction and "
                <> "say nothing about whether priors are where adaptive ordering earns its keep."
            )
      )

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

-- | What one asker cost in one world.
data Counts = Counts
  { cAtoms :: Double
  , cFields :: Double
  }

data Weighted = Weighted
  { wDeclAtoms :: Double
  , wPlanAtoms :: Double
  , wStatAtoms :: Double
  , wDeclFields :: Double
  , wPlanFields :: Double
  , wStatFields :: Double
  , wDeclLazyOnly :: Double
  , wWins :: Double
  -- ^ probability mass of worlds where plan asks strictly fewer atoms than decl
  , wTies :: Double
  , wLosses :: Double
  , wFieldWins :: Double
  , wFieldTies :: Double
  , wFieldLosses :: Double
  , wStatWins :: Double
  -- ^ probability mass of worlds where STATIC asks strictly fewer atoms than decl
  , wStatTies :: Double
  , wStatLosses :: Double
  , wStatVsPlanBehind :: Double
  -- ^ probability mass of worlds where static asks strictly MORE than plan —
  -- i.e. the mass on which adaptivity actually buys something reordering cannot.
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
  , mSynth :: [Weighted]
  -- ^ One entry per @--synthetic-priors@ draw. Empty when the flag is 0.
  , mWorstDecl :: Int
  , mWorstPlan :: Int
  , mWorstStat :: Int
  , mWorstDeclFields :: Int
  , mWorstPlanFields :: Int
  , mWorstStatFields :: Int
  , mAnomalies :: [Text]
  , mTraces :: [(Text, [Text], [Text], [Text])]
  -- ^ (world as a bit string over atom order, decl, plan, stat ask sequences)
  }

data Row = Row
  { rFile :: FilePath
  , rName :: Text
  , rExported :: Bool
  , rSource :: Either Text Measured
  -- ^ @shouldSimplify = False@: the shape the docassemble emitter lowers.
  -- @Left@ is a refusal, carrying its reason verbatim.
  , rCnf :: Either Text Measured
  -- ^ @shouldSimplify = True@: the shape @l4 verify@ and the wizard see.
  }

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

main :: IO ()
main = do
  opts <- execParser (info (optionsParser <**> helper) (fullDesc <> progDesc "M3 gate: information-gain question ordering vs L4 declaration order."))
  rows <- concat <$> traverse (measureFile opts) opts.optFiles
  let subs = subPredicateNames rows
  case opts.optOutCsv of
    Nothing -> pure ()
    Just f -> Text.writeFile f (renderCsv subs rows)
  case opts.optOutJson of
    Nothing -> pure ()
    Just f ->
      BSL8.writeFile
        f
        ( Aeson.encode
            ( Aeson.object
                [ "seed" .= opts.optSeed
                , "exhaustiveMax" .= opts.optExhaustiveMax
                , "samples" .= opts.optSamples
                , "maxNodes" .= opts.optMaxNodes
                , "decisions" .= map (rowJson subs) rows
                ]
            )
        )
  Text.putStr (renderSummary subs rows)

-- | A decision counted BOTH as a row of its own and as a single atom inside
-- some other row: its name occurs in another measured decision's atom label.
-- Purely a disclosure column — nothing in the measurement depends on it — but
-- without it "11 of 138 decisions" reads as "11 of 138 independent rules",
-- which it is not.
subPredicateNames :: [Row] -> Set Text
subPredicateNames rows =
  Set.fromList
    [ nm
    | (nm, own) <- named
    , (lbl, from) <- allLabels
    , from /= own
    , nm `Text.isInfixOf` lbl
    ]
  where
    named = [(stripTicks r.rName, r.rName <> Text.pack r.rFile) | r <- rows, Right _ <- [r.rSource], not (Text.null (stripTicks r.rName))]
    allLabels =
      [ (a.aiLabel, r.rName <> Text.pack r.rFile)
      | r <- rows
      , Right m <- [r.rSource]
      , a <- m.mAtomInfo
      ]
    stripTicks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")

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
      pure [Row file (Text.pack file) False (Left "file did not type-check") (Left "file did not type-check")]
    Just tc -> pure [measureDecide opts file tc dec | dec <- foldTopLevelDecides (\x -> [x]) tc.module']

measureDecide :: Options -> FilePath -> Rules.TypeCheckResult -> Decide Resolved -> Row
measureDecide opts file tc decide =
  Row
    { rFile = file
    , rName = srcName
    , rExported = Export.isExportedDecide decide
    , rSource = srcRes
    , rCnf = cnfRes
    }
  where
    (srcName, srcRes) = arm False
    (_, cnfRes) = arm True

    arm shouldSimplify = case LadderViz.doVisualize decide (vizCfg shouldSimplify) of
      Left err -> (astName, Left (LadderViz.prettyPrintVizError err))
      Right (ladderInfo, vizState)
        | nodes > opts.optMaxNodes ->
            (fnName, Left ("ladder exceeds --max-nodes=" <> Text.pack (show opts.optMaxNodes)))
        | otherwise -> (fnName, Right (runMeasurement opts ladderInfo vizState))
        where
          nodes = ladderNodeCount opts.optMaxNodes ladderInfo.funDecl.body
          fnName = ladderInfo.funDecl.fnName.label

    vizCfg shouldSimplify = LadderViz.mkVizConfig verDocId tc.module' tc.substitution shouldSimplify
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

varsOf :: BDQ.BoolExpr Int -> [Int]
varsOf = \case
  BDQ.BTrue -> []
  BDQ.BFalse -> []
  BDQ.BVar v -> [v]
  BDQ.BNot e -> varsOf e
  BDQ.BAnd es -> concatMap varsOf es
  BDQ.BOr es -> concatMap varsOf es
  BDQ.BImplies p q -> varsOf p <> varsOf q

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
-- The three askers
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
askLazy :: BDQ.CompiledDecisionQuery Int -> Map Int Double -> BDQ.BoolExpr Int -> Map Int Bool -> [Int]
askLazy compiled priors expr world = go Map.empty []
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

-- | Plan-order asker: ask the top-ranked atom, restrict, repeat. This is M3.
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

-- | Compile-time operand reordering — the cheap alternative to M3.
--
-- Sort each @AND@\/@OR@ node's operands by the planner's FRESH-STATE ranking
-- (what 'BDQ.queryDecision' ranks with nothing known), keying an operand by the
-- best-ranked atom anywhere inside it. 'List.sortOn' is stable, so operands the
-- ranker cannot separate keep their declaration order. The seam is left alone:
-- swapping a rule's scope and requirement is a semantic change, not a
-- reordering.
--
-- The result is a rewritten expression, and the ordering it induces is then
-- whatever the ordinary lazy walk demands. Nothing adaptive survives into the
-- artifact: an emitter can do this once and emit plain Python.
staticReorder :: Map Int Int -> BDQ.BoolExpr Int -> BDQ.BoolExpr Int
staticReorder rank = go
  where
    go = \case
      BDQ.BAnd es -> BDQ.BAnd (List.sortOn keyOf (map go es))
      BDQ.BOr es -> BDQ.BOr (List.sortOn keyOf (map go es))
      BDQ.BNot e -> BDQ.BNot (go e)
      BDQ.BImplies p q -> BDQ.BImplies (go p) (go q)
      e -> e
    keyOf e = minimum (maxBound : [Map.findWithDefault maxBound v rank | v <- varsOf e])

freshRank :: BDQ.CompiledDecisionQuery Int -> Map Int Double -> Map Int Int
freshRank compiled priors =
  Map.fromList (zip (BDQ.queryDecision compiled priors Map.empty).ranked [0 ..])

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
    , mUniform = summarise priors uniformWorlds uniformWeights
    , mPrior = summarise priors priorWorlds priorWeights
    , mSynth = synthArms
    , mWorstDecl = maximum0 [length (declSeq w) | w <- uniformWorlds]
    , mWorstPlan = maximum0 [length (planSeq w) | w <- uniformWorlds]
    , mWorstStat = maximum0 [length (statSeq w) | w <- uniformWorlds]
    , mWorstDeclFields = maximum0 [fieldCost refsByAtom (declSeq w) | w <- uniformWorlds]
    , mWorstPlanFields = maximum0 [fieldCost refsByAtom (planSeq w) | w <- uniformWorlds]
    , mWorstStatFields = maximum0 [fieldCost refsByAtom (statSeq w) | w <- uniformWorlds]
    , mAnomalies = anomalies
    , mTraces =
        if opts.optTraces && nClasses <= 6
          then
            [ ( Text.pack [if Map.findWithDefault False v w then 'T' else 'F' | v <- order']
              , [labelOf v | v <- declSeq w]
              , [labelOf v | v <- planSeq w]
              , [labelOf v | v <- statSeq w]
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

    staticExprFor ps = staticReorder (freshRank compiled ps) expr'
    staticExpr = staticExprFor priors

    declSeq w = askLazy compiled priors expr' w
    planSeq w = askPlan compiled priors w
    statSeq w = askLazy compiled priors staticExpr w
    lazySeq w = askDeclLazyOnly expr' w

    countsWith ps sExpr w =
      let d = askLazy compiled ps expr' w
          p = askPlan compiled ps w
          s = askLazy compiled ps sExpr w
       in ( Counts (fromIntegral (length d)) (fromIntegral (fieldCost refsByAtom d))
          , Counts (fromIntegral (length p)) (fromIntegral (fieldCost refsByAtom p))
          , Counts (fromIntegral (length s)) (fromIntegral (fieldCost refsByAtom s))
          , fromIntegral (length (askDeclLazyOnly expr' w)) :: Double
          )

    -- One draw of SYNTHETIC per-atom priors. The corpus carries none, so
    -- without this the uniform and prior-weighted arms coincide by construction
    -- and the measurement is silent on the question the previous run named as
    -- its own reopening condition: is a skewed prior distribution where
    -- adaptive ordering earns something a compile-time reorder cannot?
    -- The draw feeds BOTH the ranker and the world distribution, which is the
    -- arrangement that most flatters the planner.
    synthPriorsFor :: Int -> Map Int Double
    synthPriorsFor drawIx =
      Map.fromList (go (opts.optSeed + 1000003 * fromIntegral (drawIx + 1)) order')
      where
        go _ [] = []
        go s (v : vs) = let (r, s') = nextD s in (v, 0.05 + 0.9 * r) : go s' vs

    synthArms
      | opts.optSynthPriors <= 0 || nClasses < 2 = []
      | otherwise =
          [ let ps = synthPriorsFor i
                sE = staticExprFor ps
                ws
                  | exhaustive = uniformWorlds
                  | otherwise = sampleWorlds (opts.optSeed + 104729 * fromIntegral (i + 1)) opts.optSamples [(v, Map.findWithDefault 0.5 v ps) | v <- order']
                wts
                  | exhaustive = map (worldWeight ps) ws
                  | otherwise = replicate (length ws) 1
             in summariseWith (countsWith ps sE) ws wts
          | i <- [0 .. opts.optSynthPriors - 1]
          ]

    summarise ps = summariseWith (countsWith ps (staticExprFor ps))

    summariseWith countsOf ws weights =
      let total = sum weights
          pairs = [(countsOf w, wt) | (w, wt) <- zip ws weights]
          wsum f = sum [f c * wt | (c, wt) <- pairs] / total
          cmp f g =
            ( sum [wt | (c, wt) <- pairs, g c < f c] / total
            , sum [wt | (c, wt) <- pairs, g c == f c] / total
            , sum [wt | (c, wt) <- pairs, g c > f c] / total
            )
          dAtoms (dd, _, _, _) = dd.cAtoms
          pAtoms (_, pp, _, _) = pp.cAtoms
          sAtoms (_, _, ss, _) = ss.cAtoms
          dFields (dd, _, _, _) = dd.cFields
          pFields (_, pp, _, _) = pp.cFields
          sFields (_, _, ss, _) = ss.cFields
          (aw, at, al) = cmp dAtoms pAtoms
          (fw, ft, fl) = cmp dFields pFields
          (sw, st, sl) = cmp dAtoms sAtoms
       in Weighted
            { wDeclAtoms = wsum dAtoms
            , wPlanAtoms = wsum pAtoms
            , wStatAtoms = wsum sAtoms
            , wDeclFields = wsum dFields
            , wPlanFields = wsum pFields
            , wStatFields = wsum sFields
            , wDeclLazyOnly = wsum (\(_, _, _, l) -> l)
            , wWins = aw
            , wTies = at
            , wLosses = al
            , wFieldWins = fw
            , wFieldTies = ft
            , wFieldLosses = fl
            , wStatWins = sw
            , wStatTies = st
            , wStatLosses = sl
            , wStatVsPlanBehind = sum [wt | (c, wt) <- pairs, sAtoms c > pAtoms c] / total
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

rowJson :: Set Text -> Row -> Aeson.Value
rowJson subs r =
  Aeson.object
    ( [ "file" .= r.rFile
      , "decision" .= r.rName
      , "exported" .= r.rExported
      , "subPredicate" .= Set.member (stripTicks r.rName) subs
      , "measured" .= isRight r.rSource
      , "source" .= armJson r.rSource
      , "cnf" .= armJson r.rCnf
      ]
        <> ["reason" .= reason | Left reason <- [r.rSource]]
    )
  where
    stripTicks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
    isRight = \case Right _ -> True; Left _ -> False

armJson :: Either Text Measured -> Aeson.Value
armJson = \case
  Left reason -> Aeson.object ["measured" .= False, "reason" .= reason]
  Right m ->
    Aeson.object
      [ "measured" .= True
      , "atomClasses" .= m.mAtomClasses
      , "atomsRaw" .= m.mAtomsRaw
      , "ladderNodes" .= m.mLadderNodes
      , "priors" .= m.mPriorCount
      , "sampling" .= m.mSampling
      , "worlds" .= m.mWorlds
      , "atoms" .= [Aeson.object ["unique" .= a.aiUnique, "label" .= a.aiLabel, "refs" .= a.aiRefs, "prior" .= a.aiPrior] | a <- m.mAtomInfo]
      , "uniform" .= weightedJson m.mUniform
      , "priorWeighted" .= weightedJson m.mPrior
      , "syntheticPriorDraws" .= map weightedJson m.mSynth
      , "worstCase"
          .= Aeson.object
            [ "declAtoms" .= m.mWorstDecl
            , "planAtoms" .= m.mWorstPlan
            , "statAtoms" .= m.mWorstStat
            , "declRefs" .= m.mWorstDeclFields
            , "planRefs" .= m.mWorstPlanFields
            , "statRefs" .= m.mWorstStatFields
            ]
      , "anomalies" .= m.mAnomalies
      , "traces" .= [Aeson.object ["world" .= w, "decl" .= d, "plan" .= p, "stat" .= s] | (w, d, p, s) <- m.mTraces]
      ]

weightedJson :: Weighted -> Aeson.Value
weightedJson w =
  Aeson.object
    [ "declAtomsMean" .= w.wDeclAtoms
    , "planAtomsMean" .= w.wPlanAtoms
    , "statAtomsMean" .= w.wStatAtoms
    , "declRefsMean" .= w.wDeclFields
    , "planRefsMean" .= w.wPlanFields
    , "statRefsMean" .= w.wStatFields
    , "declLazyOnlyMean" .= w.wDeclLazyOnly
    , "atomWinFrac" .= w.wWins
    , "atomTieFrac" .= w.wTies
    , "atomLossFrac" .= w.wLosses
    , "fieldWinFrac" .= w.wFieldWins
    , "fieldTieFrac" .= w.wFieldTies
    , "fieldLossFrac" .= w.wFieldLosses
    , "statWinFrac" .= w.wStatWins
    , "statTieFrac" .= w.wStatTies
    , "statLossFrac" .= w.wStatLosses
    , "planBeatsStatFrac" .= w.wStatVsPlanBehind
    ]

renderCsv :: Set Text -> [Row] -> Text
renderCsv subs rows = Text.unlines (csvHeader : map line rows)
  where
    csvHeader =
      Text.intercalate
        ","
        [ "file"
        , "decision"
        , "exported"
        , "subPredicate"
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
        , "statAtomsMean_uniform"
        , "declAtomsMean_prior"
        , "planAtomsMean_prior"
        , "statAtomsMean_prior"
        , "declRefsMean_uniform"
        , "planRefsMean_uniform"
        , "statRefsMean_uniform"
        , "declLazyOnlyMean_uniform"
        , "atomWinFrac_uniform"
        , "atomTieFrac_uniform"
        , "atomLossFrac_uniform"
        , "planBeatsStatFrac_uniform"
        , "worstDeclAtoms"
        , "worstPlanAtoms"
        , "worstStatAtoms"
        , "worstDeclRefs"
        , "worstPlanRefs"
        , "cnf_atomClasses"
        , "cnf_ladderNodes"
        , "cnf_declAtomsMean_uniform"
        , "cnf_planAtomsMean_uniform"
        , "cnf_statAtomsMean_uniform"
        , "anomalies"
        ]
    stripTicks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
    line r = case r.rSource of
      Left reason ->
        Text.intercalate
          ","
          ( [ q (Text.pack r.rFile)
            , q r.rName
            , b r.rExported
            , b (Set.member (stripTicks r.rName) subs)
            , "refused"
            , q reason
            ]
              <> replicate 31 ""
          )
      Right m ->
        Text.intercalate
          ","
          [ q (Text.pack r.rFile)
          , q r.rName
          , b r.rExported
          , b (Set.member (stripTicks r.rName) subs)
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
          , d m.mUniform.wStatAtoms
          , d m.mPrior.wDeclAtoms
          , d m.mPrior.wPlanAtoms
          , d m.mPrior.wStatAtoms
          , d m.mUniform.wDeclFields
          , d m.mUniform.wPlanFields
          , d m.mUniform.wStatFields
          , d m.mUniform.wDeclLazyOnly
          , d m.mUniform.wWins
          , d m.mUniform.wTies
          , d m.mUniform.wLosses
          , d m.mUniform.wStatVsPlanBehind
          , n m.mWorstDecl
          , n m.mWorstPlan
          , n m.mWorstStat
          , n m.mWorstDeclFields
          , n m.mWorstPlanFields
          , cnfCol (n . (.mAtomClasses))
          , cnfCol (n . (.mLadderNodes))
          , cnfCol (d . (.wDeclAtoms) . (.mUniform))
          , cnfCol (d . (.wPlanAtoms) . (.mUniform))
          , cnfCol (d . (.wStatAtoms) . (.mUniform))
          , q (Text.intercalate "; " m.mAnomalies)
          ]
        where
          cnfCol f = case r.rCnf of
            Left _ -> ""
            Right c -> f c
    n = Text.pack . show
    b x = if x then "true" else "false"
    d x = Text.pack (show (fromIntegral (round (x * 10000) :: Int) / 10000 :: Double))
    q t = "\"" <> Text.replace "\"" "\"\"" t <> "\""

renderSummary :: Set Text -> [Row] -> Text
renderSummary subs rows =
  Text.unlines $
    [ "decisions seen      : " <> tshow (length rows)
    , "  refused by ladder : " <> tshow (length refused)
    , "  measured          : " <> tshow (length measured)
    , "    with 0 atoms    : " <> tshow (length [m | m <- measured, m.mAtomClasses == 0])
    , "    with >= 2 atoms : " <> tshow (length reorderable)
    , "  decisions carrying any TYPICALLY prior: " <> tshow (length [m | m <- measured, m.mPriorCount > 0])
    , ""
    , "POPULATION SHAPE (of the " <> tshow (length reorderable) <> " with >= 2 atom classes):"
    , "  carrying @export (enterable as an interview) : " <> tshow (length [() | (r, m) <- reorderablePairs, r.rExported, m.mAtomClasses >= 2])
    , "  also counted as ONE atom inside another row  : " <> tshow (length [() | (r, _) <- reorderablePairs, Set.member (stripTicks r.rName) subs])
    ]
      <> armSummary "SOURCE FORM (shouldSimplify = False) -- the shape the docassemble emitter lowers. HEADLINE." reorderable
      <> armSummary "CNF FORM (shouldSimplify = True) -- the shape `l4 verify` and the wizard see." reorderableCnf
      <> [ ""
         , "Anomalies reported (source form): " <> tshow (length [m | m <- measured, not (null m.mAnomalies)])
         ]
  where
    stripTicks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
    measured = [m | r <- rows, Right m <- [r.rSource]]
    refused = [() | r <- rows, Left _ <- [r.rSource]]
    reorderablePairs = [(r, m) | r <- rows, Right m <- [r.rSource], m.mAtomClasses >= 2]
    reorderable = map snd reorderablePairs
    reorderableCnf = [m | r <- rows, Right s <- [r.rSource], s.mAtomClasses >= 2, Right m <- [r.rCnf]]
    tshow :: Show a => a -> Text
    tshow = Text.pack . show

    armSummary title ms =
      [ ""
      , title
      , "  decisions in arm: " <> tshow (length ms)
      , "  mean questions, declaration order (uniform worlds) : " <> fmt (avg [m.mUniform.wDeclAtoms | m <- ms])
      , "  mean questions, PLAN order        (uniform worlds) : " <> fmt (avg [m.mUniform.wPlanAtoms | m <- ms])
      , "  mean questions, STATIC reorder    (uniform worlds) : " <> fmt (avg [m.mUniform.wStatAtoms | m <- ms])
      , "  mean questions, declaration order (prior worlds)   : " <> fmt (avg [m.mPrior.wDeclAtoms | m <- ms])
      , "  mean questions, PLAN order        (prior worlds)   : " <> fmt (avg [m.mPrior.wPlanAtoms | m <- ms])
      , "  mean questions, STATIC reorder    (prior worlds)   : " <> fmt (avg [m.mPrior.wStatAtoms | m <- ms])
      , "  per-decision, plan vs decl : fewer " <> tshow (cnt ms (\m -> m.mUniform.wPlanAtoms < m.mUniform.wDeclAtoms - eps)) <> "  tie " <> tshow (cnt ms (\m -> abs (m.mUniform.wPlanAtoms - m.mUniform.wDeclAtoms) <= eps)) <> "  more " <> tshow (cnt ms (\m -> m.mUniform.wPlanAtoms > m.mUniform.wDeclAtoms + eps))
      , "  per-decision, stat vs decl : fewer " <> tshow (cnt ms (\m -> m.mUniform.wStatAtoms < m.mUniform.wDeclAtoms - eps)) <> "  tie " <> tshow (cnt ms (\m -> abs (m.mUniform.wStatAtoms - m.mUniform.wDeclAtoms) <= eps)) <> "  more " <> tshow (cnt ms (\m -> m.mUniform.wStatAtoms > m.mUniform.wDeclAtoms + eps))
      , "  per-decision, plan vs stat : fewer " <> tshow (cnt ms (\m -> m.mUniform.wPlanAtoms < m.mUniform.wStatAtoms - eps)) <> "  tie " <> tshow (cnt ms (\m -> abs (m.mUniform.wPlanAtoms - m.mUniform.wStatAtoms) <= eps)) <> "  more " <> tshow (cnt ms (\m -> m.mUniform.wPlanAtoms > m.mUniform.wStatAtoms + eps))
      , "  share of the plan saving that STATIC reordering already captures : " <> fmt (capture ms)
      , "  refs (field proxy): decl " <> fmt (avg [m.mUniform.wDeclFields | m <- ms]) <> "  plan " <> fmt (avg [m.mUniform.wPlanFields | m <- ms]) <> "  stat " <> fmt (avg [m.mUniform.wStatFields | m <- ms])
      , "  per-decision refs, plan vs decl : fewer " <> tshow (cnt ms (\m -> m.mUniform.wPlanFields < m.mUniform.wDeclFields - eps)) <> "  tie " <> tshow (cnt ms (\m -> abs (m.mUniform.wPlanFields - m.mUniform.wDeclFields) <= eps)) <> "  more " <> tshow (cnt ms (\m -> m.mUniform.wPlanFields > m.mUniform.wDeclFields + eps))
      , "  world mass (uniform), plan vs decl : fewer " <> fmt (avg [m.mUniform.wWins | m <- ms]) <> "  tie " <> fmt (avg [m.mUniform.wTies | m <- ms]) <> "  more " <> fmt (avg [m.mUniform.wLosses | m <- ms])
      , "  world mass (uniform), plan beats STATIC : " <> fmt (avg [m.mUniform.wStatVsPlanBehind | m <- ms])
      , "  worst case improves (plan): " <> tshow (cnt ms (\m -> m.mWorstPlan < m.mWorstDecl)) <> "  worsens: " <> tshow (cnt ms (\m -> m.mWorstPlan > m.mWorstDecl))
      , "  worst case improves (stat): " <> tshow (cnt ms (\m -> m.mWorstStat < m.mWorstDecl)) <> "  worsens: " <> tshow (cnt ms (\m -> m.mWorstStat > m.mWorstDecl))
      , "  max ladder nodes in arm: " <> tshow (maximum0 [m.mLadderNodes | m <- ms])
      ]
        <> synthLines ms

    -- Synthetic priors, averaged over draws. Reported as "what a corpus that
    -- actually carried TYPICALLY priors would look like", which is the one
    -- regime this corpus cannot exhibit.
    synthLines ms
      | null draws = []
      | otherwise =
          [ "  SYNTHETIC PRIORS ~ U(0.05,0.95), " <> tshow nDraws <> " draws, fed to the ranker AND the world distribution:"
          , "    decl " <> fmt (mean [w.wDeclAtoms | w <- draws]) <> "  plan " <> fmt (mean [w.wPlanAtoms | w <- draws]) <> "  stat " <> fmt (mean [w.wStatAtoms | w <- draws])
          , "    share of the plan saving that STATIC reordering captures under skewed priors: " <> fmt synthCapture
          , "    world mass on which plan beats stat: " <> fmt (mean [w.wStatVsPlanBehind | w <- draws])
          ]
      where
        nDraws = maximum0 (0 : [length m.mSynth | m <- ms])
        draws = concatMap (.mSynth) ms
        mean [] = 0 :: Double
        mean xs = sum xs / fromIntegral (length xs)
        synthCapture =
          let pS = sum [w.wDeclAtoms - w.wPlanAtoms | w <- draws]
              sS = sum [w.wDeclAtoms - w.wStatAtoms | w <- draws]
           in if abs pS < eps then 0 else sS / pS
    eps = 1e-9 :: Double
    cnt ms p = length (filter p ms)
    capture ms =
      let planSave = sum [m.mUniform.wDeclAtoms - m.mUniform.wPlanAtoms | m <- ms]
          statSave = sum [m.mUniform.wDeclAtoms - m.mUniform.wStatAtoms | m <- ms]
       in if abs planSave < eps then 0 else statSave / planSave
    avg [] = 0 :: Double
    avg xs = sum xs / fromIntegral (length xs)
    fmt x = Text.pack (show (fromIntegral (round (x * 10000) :: Int) / 10000 :: Double))
