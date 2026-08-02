-- | @l4 verify FILE@ — drafting-consistency analysis over the boolean decision
-- skeleton, using the query planner's ROBDD.
--
-- == What it looks for
--
-- Four families, all of them statements about the /propositional structure/ of a
-- @DECIDE@, none of them about arithmetic or about the world:
--
-- [@unsat@] A conjunction — the whole decision, or one nested @AND@ read in the
--   context that reaches it — that no assignment of its atoms satisfies. A
--   decision whose body is @unsat@ is TRUE for nobody: as drafting, that is a
--   requirement no one can ever meet. A nested one is the double bind: two
--   clauses that must both hold and cannot.
--
-- [@dead-branch@] A disjunct of an @OR@ that is unsatisfiable in its context.
--   The rule would read identically with the limb deleted, which means either
--   the limb is inoperative or the draftsman meant something else by it.
--
-- [@vacuous-guard@] Either (a) the scope of a seam (the @scope IMPLIES
--   requirement@ shape the ladder draws with two lamps) is unsatisfiable, so the
--   rule never reaches anybody and is vacuously true; or (b) a conjunct that its
--   own siblings already entail, so it excludes nothing and is a guard in name
--   only.
--
-- [@unreachable-outcome@] One of a rule's two verdicts cannot be reached.
--   @scope AND requirement@ unsatisfiable means whoever the rule /does/ reach is
--   necessarily in breach — @Complies@ is unreachable. @scope AND NOT
--   requirement@ unsatisfiable means the scope already entails the requirement,
--   so @InBreach@ is unreachable and the requirement is decorative. For a
--   decision with no seam, a body that is valid has an unreachable FALSE.
--
-- == The bound, stated plainly
--
-- See 'propositionalBound', which is also the @--help@ footer, because a
-- verifier whose limits live only in a source comment is a verifier that will be
-- over-claimed by the next person to quote it.
--
-- == How it reaches the ROBDD
--
-- Exactly the path the web wizard takes, and deliberately so: the wizard and the
-- verifier must not disagree about what the atoms of a rule are.
--
-- @
-- Decide -> LSP.L4.Viz.Ladder.doVisualize            -- ladder IR, AND\/OR normal form
--        -> LSP.L4.Viz.QueryPlan.vizExprToBoolExpr   -- BoolExpr Int + labels + order
--        -> L4.Decision.BooleanDecisionQuery.compileDecisionQuery  -- the ROBDD
-- @
--
-- Satisfiability is then read off the compiled diagram: a reduced ordered BDD is
-- the constant @0@ node if and only if the formula it encodes is unsatisfiable,
-- so @queryDecision@'s @determined@ field answers the question with no search.
-- That is the one thing a BDD gives away for free, and it is the whole engine
-- here.
module L4.Cli.Verify
  ( VerifyOptions (..)
  , VerifyFormat (..)
  , verifyOptionsParser
  , verifyCmd
  , propositionalBound
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Map.Strict as Map
import Options.Applicative
import System.Exit (ExitCode (..), exitSuccess, exitWith)

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
-- The honest bound
----------------------------------------------------------------------------

-- | What this command does and does not prove. Printed as the @--help@ footer
-- and at the foot of the text report.
--
-- Every sentence here is a limitation somebody would otherwise have to discover
-- by being wrong in public.
propositionalBound :: String
propositionalBound =
  unlines
    [ "WHAT A CLEAN RUN PROVES, AND WHAT IT DOES NOT"
    , ""
    , "  The analysis is PROPOSITIONAL. Every leaf of a decision -- a record"
    , "  projection, a comparison, a call, an arithmetic test -- is an opaque"
    , "  atom. `amount > 5000000' and `amount > 1000000' are two unrelated"
    , "  atoms, so no numeric, interval, string or date contradiction is"
    , "  visible to this command. Neither is anything about the world."
    , ""
    , "  Findings are SOUND, not COMPLETE. A reported finding is a real"
    , "  property of the boolean skeleton. Silence is not a consistency proof:"
    , "  it means nothing was found at this level of abstraction, which is a"
    , "  much weaker claim and must be reported as the weaker one."
    , ""
    , "  The unit of analysis is the LADDER's AND/OR normal form of each"
    , "  boolean DECIDE, not the L4 source. Guarded chains (IF/BRANCH/CONSIDER"
    , "  over booleans) are expanded; whatever the ladder treats as a leaf is a"
    , "  leaf here too. A DECIDE that does not return BOOLEAN is not analysed,"
    , "  and is reported as skipped rather than as clean."
    , ""
    , "  Each decision is read ON ITS OWN. A call to another DECIDE is a leaf,"
    , "  not an inlined body, so a contradiction that only appears once two"
    , "  named rules are unfolded against each other is out of range. In a"
    , "  corpus written as many small named limbs -- which is the house style --"
    , "  that is most of the corpus, and it is why a clean run over such a file"
    , "  is a weak statement."
    , ""
    , "  The normal form is CONJUNCTIVE, and reaching it MANUFACTURES clauses"
    , "  the draftsman never wrote: `x XOR y' distributes into a conjunction"
    , "  containing `x OR NOT x'. So a conjunct that is valid ON ITS OWN is not"
    , "  reported as a vacuous guard -- only CONTINGENT entailment is, i.e."
    , "  this condition adds nothing GIVEN THE OTHERS. A hand-written"
    , "  always-true guard therefore goes unreported. That is deliberate: a"
    , "  checker that fires on every XOR is a checker nobody runs twice."
    , ""
    , "  Atom identity matters more here than anything else. By default,"
    , "  syntactically identical leaves are MERGED into one variable, keyed by"
    , "  the same stable atomId the web wizard uses to decide that two leaves"
    , "  are one question. With --no-coalesce-atoms each OCCURRENCE is its own"
    , "  variable, which makes even `p AND NOT p' invisible -- independence"
    , "  only ever makes a formula more satisfiable, so that mode can miss"
    , "  findings but cannot invent them."
    ]

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data VerifyFormat = VfText | VfJson
  deriving (Eq, Show)

data VerifyOptions = VerifyOptions
  { verifyFile      :: FilePath
  , verifyFormat    :: VerifyFormat
  , verifyOutput    :: Maybe FilePath
  , verifyDecisions :: [Text]
  , verifyCoalesce  :: Bool
  , verifyMaxNodes  :: Int
  , verifyFixedNow  :: FixedNowOpt
  }

verifyFormatReader :: ReadM VerifyFormat
verifyFormatReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "text" -> Right VfText
    "json" -> Right VfJson
    other  -> Left $ "Invalid format: " <> Text.unpack other <> " (expected text|json)"

verifyOptionsParser :: Parser VerifyOptions
verifyOptionsParser = VerifyOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to verify")
  <*> option verifyFormatReader
        ( long "format"
       <> metavar "FMT"
       <> value VfText
       <> showDefaultWith (const "text")
       <> help "Output format: text|json"
        )
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write to FILE instead of stdout"
            )
        )
  <*> many
        ( fmap Text.pack $ strOption
            ( long "decision"
           <> metavar "NAME"
           <> help "Analyse only this decision (repeatable; default: every boolean DECIDE)"
            )
        )
  <*> flag True False
        ( long "no-coalesce-atoms"
       <> help "Treat every leaf OCCURRENCE as its own variable instead of merging identical leaves by atomId. Strictly weaker; see the bound printed below"
        )
  <*> option auto
        ( long "max-nodes"
       <> metavar "N"
       <> value 4096
       <> showDefault
       <> help "Skip a decision whose ladder exceeds N nodes. The AND/OR normal form is exponential in the width of a disjunction of conjunctions, so this is a refusal, not a tuning knob"
        )
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Result types
----------------------------------------------------------------------------

data Finding = Finding
  { findingKind    :: Text
  , findingSite    :: Text
  , findingAtoms   :: [Text]
  , findingMessage :: Text
  }

instance Aeson.ToJSON Finding where
  toJSON f =
    Aeson.object
      [ "kind" .= f.findingKind
      , "site" .= f.findingSite
      , "atoms" .= f.findingAtoms
      , "message" .= f.findingMessage
      ]

data Analysis = Analysis
  { anAtoms       :: Int
  -- ^ Distinct BDD variables before coalescing, i.e. leaf OCCURRENCES.
  , anAtomClasses :: Int
  -- ^ Distinct variables actually compiled. Below 'anAtoms' exactly when
  -- occurrences of one question were merged.
  , anLadderNodes :: Int
  , anFindings    :: [Finding]
  }

data DecisionReport = DecisionReport
  { drName   :: Text
  , drResult :: Either Text Analysis
  -- ^ @Left@ names why the decision was not analysed. Never silently dropped:
  -- a decision this command cannot read is a hole in what a clean run means.
  }

instance Aeson.ToJSON DecisionReport where
  toJSON d = case d.drResult of
    Left reason ->
      Aeson.object
        [ "name" .= d.drName
        , "analysed" .= False
        , "reason" .= reason
        ]
    Right a ->
      Aeson.object
        [ "name" .= d.drName
        , "analysed" .= True
        , "atoms" .= a.anAtoms
        , "atomClasses" .= a.anAtomClasses
        , "ladderNodes" .= a.anLadderNodes
        , "findings" .= a.anFindings
        ]

reportFindings :: DecisionReport -> [Finding]
reportFindings d = either (const []) (.anFindings) d.drResult

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

verifyCmd :: VerifyOptions -> IO ()
verifyCmd opts = do
  evalConfig <- makeEvalConfig opts.verifyFixedNow
  (errs, mTc) <- runOneshot evalConfig opts.verifyFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitWith (ExitFailure 1)
    Just tc -> do
      putDiagnostics errs
      let reports = analyseModule opts tc
          total = length (concatMap reportFindings reports)
      emit opts (render opts reports total)
      if total > 0 then exitWith (ExitFailure 1) else exitSuccess

emit :: VerifyOptions -> Either BSL8.ByteString Text -> IO ()
emit opts = \case
  Left bytes -> case opts.verifyOutput of
    Just f  -> BSL8.writeFile f (bytes <> "\n")
    Nothing -> BSL8.putStrLn bytes
  Right txt -> case opts.verifyOutput of
    Just f  -> Text.writeFile f txt
    Nothing -> Text.putStr txt

----------------------------------------------------------------------------
-- Analysis, per module
----------------------------------------------------------------------------

analyseModule :: VerifyOptions -> Rules.TypeCheckResult -> [DecisionReport]
analyseModule opts tc =
  [ r
  | decide <- foldTopLevelDecides (\d -> [d]) tc.module'
  , let r = analyseDecide opts tc decide
  , wanted r.drName
  ]
  where
    wanted nm
      | null opts.verifyDecisions = True
      | otherwise = any (`matches` nm) opts.verifyDecisions
    -- A decision's rendered name carries L4's backticks; match with or without.
    matches want nm = want == nm || want == stripBackticks nm

analyseDecide :: VerifyOptions -> Rules.TypeCheckResult -> Decide Resolved -> DecisionReport
analyseDecide opts tc decide =
  case LadderViz.doVisualize decide vizCfg of
    Left err ->
      DecisionReport
        { drName = astName
        , drResult = Left (LadderViz.prettyPrintVizError err)
        }
    Right (ladderInfo, vizState) ->
      let fnName = ladderInfo.funDecl.fnName.label
          nodes = ladderNodeCount opts.verifyMaxNodes ladderInfo.funDecl.body
       in if nodes > opts.verifyMaxNodes
            then
              DecisionReport
                { drName = fnName
                , drResult =
                    Left $
                      "ladder exceeds --max-nodes="
                        <> Text.pack (show opts.verifyMaxNodes)
                        <> "; the AND/OR normal form is exponential in the width of a disjunction of conjunctions, so this is refused rather than attempted"
                }
            else
              let (boolExpr, labels, order) = VizQP.vizExprToBoolExpr ladderInfo.funDecl.body
                  (expr', labels', order')
                    | opts.verifyCoalesce =
                        let cache = VizQP.buildQueryPlanCache ladderInfo vizState
                            paramsBy = VizQP.buildParamsByUnique ladderInfo
                            atomIds = QP.atomIdByUnique fnName paramsBy cache
                         in coalesceByAtomId atomIds boolExpr labels order
                    | otherwise = (boolExpr, labels, order)
               in DecisionReport
                    { drName = fnName
                    , drResult =
                        Right
                          Analysis
                            { anAtoms = length order
                            , anAtomClasses = length order'
                            , anLadderNodes = nodes
                            , anFindings = analyseBody labels' order' expr'
                            }
                    }
  where
    vizCfg = LadderViz.mkVizConfig verDocId tc.module' tc.substitution True
    verDocId =
      LSP.VersionedTextDocumentIdentifier
        { LSP._uri = LSP.filePathToUri opts.verifyFile
        , LSP._version = 1
        }
    astName = case decide of
      MkDecide _ _ (MkAppForm _ n _ _) _ -> prettyLayout (getOriginal n)

-- | Node count of a ladder body, fuel-limited: it stops the moment @budget@ is
-- blown, so an oversized ladder costs @O(budget)@ to refuse rather than
-- @O(size)@ to measure. Mirrors @exceedsNodeBudget@ in @jl4-service@.
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
-- Atom coalescing
----------------------------------------------------------------------------

-- | Merge BDD variables that the wizard would put to a user as ONE question.
--
-- Two occurrences of the same leaf get different uniques from the ladder
-- translator (see @leafFromExpr@ in "LSP.L4.Viz.Ladder", which mints a fresh id
-- per occurrence), so without this step @p AND NOT p@ compiles to two
-- independent variables and is satisfiable. That is not a soundness bug —
-- independence only ever makes a formula more satisfiable, so findings stay true
-- — but it is a large hole in coverage, and closing it does not require
-- inventing a notion of sameness: @generateAtomId@ already defines one, and it
-- is the one a wizard user answers once.
--
-- The representative of an atomId class is its first unique in variable order,
-- so the coalesced order is a subsequence of the original and the planner's
-- ordering is preserved.
coalesceByAtomId
  :: Map Int Text
  -- ^ unique -> stable atomId
  -> BDQ.BoolExpr Int
  -> Map Int Text
  -- ^ unique -> label
  -> [Int]
  -- ^ variable order
  -> (BDQ.BoolExpr Int, Map Int Text, [Int])
coalesceByAtomId atomIds expr labels order =
  (mapVars rep expr, labels', order')
  where
    repOf :: Map Text Int
    repOf =
      Map.fromListWith
        (\_new old -> old)
        [(aid, u) | u <- order, Just aid <- [Map.lookup u atomIds]]

    rep :: Int -> Int
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
  BDQ.BImplies s r -> BDQ.BImplies (mapVars f s) (mapVars f r)

----------------------------------------------------------------------------
-- Analysis, per decision
----------------------------------------------------------------------------

-- | Is the formula satisfiable, given a context of things that must hold?
--
-- Read straight off the ROBDD: the diagram reduces to the constant @0@ node
-- exactly when the formula has no satisfying assignment, and @queryDecision@'s
-- @determined@ field reports that node. Everything else the planner computes
-- (support, ranking, information gain) is lazy and is never forced here.
--
-- @order@ must list every variable occurring in @ctx@ and @e@, or the compiler
-- errors; callers pass the decision's whole variable order.
satisfiable :: [Int] -> [BDQ.BoolExpr Int] -> BDQ.BoolExpr Int -> Bool
satisfiable order ctx e =
  let compiled = BDQ.compileDecisionQuery order (BDQ.BAnd (e : ctx))
      result = BDQ.queryDecision compiled mempty mempty
   in result.determined /= Just False

varsOf :: BDQ.BoolExpr Int -> [Int]
varsOf = \case
  BDQ.BTrue -> []
  BDQ.BFalse -> []
  BDQ.BVar v -> [v]
  BDQ.BNot e -> varsOf e
  BDQ.BAnd es -> concatMap varsOf es
  BDQ.BOr es -> concatMap varsOf es
  BDQ.BImplies s r -> varsOf s <> varsOf r

-- | A subterm worth reporting on: one that mentions at least one atom.
--
-- The ladder lowers inert prose to a constant (@True@ inside an @AND@, @False@
-- inside an @OR@). Reporting "this constant is entailed by its siblings" for
-- every line of narrative in an inert-style corpus would bury the findings that
-- mean something.
interesting :: BDQ.BoolExpr Int -> Bool
interesting = not . null . varsOf

analyseBody :: Map Int Text -> [Int] -> BDQ.BoolExpr Int -> [Finding]
analyseBody labels order body
  | not (sat [] body) =
      [ Finding
          { findingKind = "unsat"
          , findingSite = "body"
          , findingAtoms = atomLabels body
          , findingMessage =
              "the decision is TRUE for no assignment of its atoms: as drafting, a requirement nobody can meet."
          }
      ]
  | otherwise = topTautology <> go [] "body" body
  where
    sat = satisfiable order
    atomLabels e = [label u | u <- nubOrd (varsOf e)]
    label u = stripBackticks (Map.findWithDefault (Text.pack (show u)) u labels)

    -- Is this subterm capable of being false at all?
    --
    -- The gate that keeps "this condition excludes nothing" from crying wolf.
    -- The ladder body is in CONJUNCTIVE normal form, and reaching CNF
    -- MANUFACTURES valid clauses: `x XOR y' written out as
    -- @(x AND NOT y) OR (NOT x AND y)@ distributes to a conjunction that
    -- contains @x OR NOT x@. That clause is not in the draftsman's text and
    -- telling him it adds nothing is telling him about our normaliser.
    --
    -- So only CONTINGENT entailment is reported: this condition adds nothing
    -- GIVEN THE OTHERS. The price is that a hand-written always-true guard goes
    -- unreported, which is the right side to err on — see the note in
    -- 'propositionalBound'.
    contingent e = sat [] (BDQ.BNot e)

    isSeam BDQ.BImplies{} = True
    isSeam _ = False

    topTautology
      | isSeam body = []
      | interesting body
      , not (sat [] (BDQ.BNot body)) =
          [ Finding
              { findingKind = "unreachable-outcome"
              , findingSite = "body"
              , findingAtoms = atomLabels body
              , findingMessage =
                  "the decision is TRUE for every assignment of its atoms, so its FALSE outcome is unreachable and the atoms it names do not affect the answer."
              }
          ]
      | otherwise = []

    go :: [BDQ.BoolExpr Int] -> Text -> BDQ.BoolExpr Int -> [Finding]
    go ctx site = \case
      e@(BDQ.BAnd es)
        | not (sat ctx e) ->
            -- Stop here. Everything below an unsatisfiable conjunction is
            -- vacuously dead, and saying so once per descendant is noise.
            [ Finding
                { findingKind = "unsat"
                , findingSite = site
                , findingAtoms = atomLabels e
                , findingMessage =
                    "these conditions cannot all hold at once in the context that reaches them — a double bind."
                }
            ]
        | otherwise ->
            concat
              [ entailed <> go ctx' arm ei
              | (i, ei) <- zip [(0 :: Int) ..] es
              , let arm = site <> ".and[" <> Text.pack (show i) <> "]"
              , let ctx' = ctx <> [ej | (j, ej) <- zip [(0 :: Int) ..] es, j /= i]
              , let entailed =
                      [ Finding
                          { findingKind = "vacuous-guard"
                          , findingSite = arm
                          , findingAtoms = atomLabels ei
                          , findingMessage =
                              "this condition is already entailed by the ones it is conjoined with, so it excludes nothing."
                          }
                      | interesting ei
                      , contingent ei
                      , not (sat ctx' (BDQ.BNot ei))
                      ]
              ]
      BDQ.BOr es ->
        concat
          [ if interesting ei && not (sat ctx ei)
              then
                [ Finding
                    { findingKind = "dead-branch"
                    , findingSite = arm
                    , findingAtoms = atomLabels ei
                    , findingMessage =
                        "this limb cannot hold in the context that reaches it; the rule reads identically with it deleted."
                    }
                ]
              else go ctx arm ei
          | (i, ei) <- zip [(0 :: Int) ..] es
          , let arm = site <> ".or[" <> Text.pack (show i) <> "]"
          ]
      BDQ.BImplies scope req
        | not (sat ctx scope) ->
            [ Finding
                { findingKind = "vacuous-guard"
                , findingSite = site <> ".scope"
                , findingAtoms = atomLabels scope
                , findingMessage =
                    "the scope of this rule is unsatisfiable, so it reaches nobody and its requirement is never tested. Note the decision still evaluates TRUE — vacuously."
                }
            ]
        | otherwise ->
            concat
              [ [ Finding
                    { findingKind = "unreachable-outcome"
                    , findingSite = site
                    , findingAtoms = atomLabels (BDQ.BAnd [scope, req])
                    , findingMessage =
                        "no case both falls within the scope and meets the requirement: whoever this rule reaches is necessarily in breach."
                    }
                | interesting req
                , not (sat (ctx <> [scope]) req)
                ]
              , [ Finding
                    { findingKind = "unreachable-outcome"
                    , findingSite = site
                    , findingAtoms = atomLabels (BDQ.BAnd [scope, req])
                    , findingMessage =
                        "the scope already entails the requirement, so nothing within scope can breach it and the requirement adds nothing."
                    }
                | interesting req
                , contingent req
                , not (sat (ctx <> [scope]) (BDQ.BNot req))
                ]
              , go ctx (site <> ".scope") scope
              , go (ctx <> [scope]) (site <> ".requirement") req
              ]
      -- Not descended into: under a negation the polarity flips, and "dead
      -- branch" would come to mean its own opposite. Reporting that under the
      -- same word would be worse than not reporting it.
      BDQ.BNot _ -> []
      BDQ.BVar _ -> []
      BDQ.BTrue -> []
      BDQ.BFalse -> []

----------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------

render :: VerifyOptions -> [DecisionReport] -> Int -> Either BSL8.ByteString Text
render opts reports total = case opts.verifyFormat of
  VfJson -> Left (Aeson.encode (jsonEnvelope opts reports total))
  VfText -> Right (textReport opts reports total)

jsonEnvelope :: VerifyOptions -> [DecisionReport] -> Int -> Aeson.Value
jsonEnvelope opts reports total =
  Aeson.object
    [ "file" .= opts.verifyFile
    , "ok" .= (total == 0)
    , "coalesceAtoms" .= opts.verifyCoalesce
    , "bound" .= boundOneLine
    , "decisions" .= reports
    , "summary"
        .= Aeson.object
          [ "decisions" .= length reports
          , "analysed" .= length analysed
          , "skipped" .= (length reports - length analysed)
          , "findings" .= total
          , "byKind" .= Map.fromListWith (+) [(f.findingKind, 1 :: Int) | f <- allFindings]
          , "mergedAtomOccurrences" .= sum [a.anAtoms - a.anAtomClasses | a <- analysed]
          ]
    ]
  where
    analysed = [a | r <- reports, Right a <- [r.drResult]]
    allFindings = concatMap reportFindings reports

boundOneLine :: Text
boundOneLine =
  "propositional only: every leaf is an opaque atom, so no numeric, interval, date or \
  \string contradiction is visible. Findings are sound; silence is not a consistency proof."

textReport :: VerifyOptions -> [DecisionReport] -> Int -> Text
textReport opts reports total =
  Text.unlines $
    [ "l4 verify — propositional consistency of the boolean decision skeleton"
    , "file: " <> Text.pack opts.verifyFile
    , "atom coalescing: "
        <> ( if opts.verifyCoalesce
              then "ON (identical leaves merged by the wizard's stable atomId)"
              else "OFF (--no-coalesce-atoms: every leaf occurrence is its own variable)"
           )
    , ""
    ]
      <> concatMap one reports
      <> ["", summary, ""]
      <> fmap Text.pack (lines propositionalBound)
  where
    analysed = [a | r <- reports, Right a <- [r.drResult]]

    one r = case r.drResult of
      Left reason -> [r.drName <> "  — NOT ANALYSED: " <> reason]
      Right a ->
        [ r.drName
            <> "  ("
            <> Text.pack (show a.anAtomClasses)
            <> " atoms"
            <> ( if a.anAtoms /= a.anAtomClasses
                  then " merged from " <> Text.pack (show a.anAtoms) <> " occurrences"
                  else ""
               )
            <> ", "
            <> Text.pack (show a.anLadderNodes)
            <> " ladder nodes) — "
            <> ( if null a.anFindings
                  then "no propositional findings"
                  else Text.pack (show (length a.anFindings)) <> " finding(s)"
               )
        ]
          <> concatMap finding a.anFindings

    finding f =
      [ "    [" <> f.findingKind <> "] at " <> f.findingSite
      , "      " <> f.findingMessage
      , "      atoms: " <> (if null f.findingAtoms then "(none)" else Text.intercalate ", " f.findingAtoms)
      ]

    summary =
      Text.pack (show (length analysed))
        <> " decision(s) analysed, "
        <> Text.pack (show (length reports - length analysed))
        <> " skipped, "
        <> Text.pack (show total)
        <> " finding(s)."

-- | Strip the backticks L4 uses to quote identifiers containing spaces. The
-- wizard's JSON does the same thing for the same reason.
stripBackticks :: Text -> Text
stripBackticks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
