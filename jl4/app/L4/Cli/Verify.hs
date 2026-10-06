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
import qualified L4.Transform as Transform
import qualified L4.TypeCheck as TC
import L4.Annotation (Anno_ (..), getAnno)
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
    , "  projection, a comparison, an arithmetic test, a call that is not read"
    , "  through (below) -- is an opaque"
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
    , "  A local WHERE / LET binding is substituted into the rule before"
    , "  analysis, with arguments put in place of parameters, so"
    , "  `m AND NOT e WHERE e MEANS m' is found unsat, as the same rule written"
    , "  flat always was."
    , ""
    , "  A call to another DECIDE that returns BOOLEAN -- in this file or in one"
    , "  it imports -- stays ONE leaf of the ladder, but not an opaque one: it is"
    , "  READ THROUGH. Its meaning (the called rule, unfolded all the way down,"
    , "  arguments in place of parameters) is used in every satisfiability"
    , "  check. So a rule that calls an exception and the offence it defeats and"
    , "  asks for both is found unsat. Findings are still reported only at this"
    , "  rule's own sites: a limb of the CALLED rule that is dead only in this"
    , "  caller's context is not reported here -- the called rule has its own"
    , "  entry. Recursive rules, and rules that do not return BOOLEAN, stay"
    , "  opaque leaves. Reading through needs atoms matched across rules by"
    , "  atomId, so --no-coalesce-atoms turns it off."
    , ""
    , "  A call whose meaning is too large to draw (past --max-nodes) stays an"
    , "  opaque leaf, and the report NAMES it on its rule (`call left as a"
    , "  leaf') and counts it in summary.callsLeftOpaque. At that atom the"
    , "  analysis is the weaker, per-rule one, and it says so."
    , ""
    , "  A definition nested in a WHERE clause is still not visited AS A"
    , "  DECISION OF ITS OWN, so `analysed + skipped' does NOT total the"
    , "  decisions in the file."
    , "  The count that is missing is reported as summary.nestedNotVisited, and"
    , "  it is a number rather than a caveat because an exclusion nobody can"
    , "  size is an exclusion nobody believes."
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
  , drUnfolding :: Unfolding
  -- ^ Whether calls to other rules were read through, or left as leaves.
  }

-- | What happened to a decision's calls to other rules. See 'callMeanings' and
-- specs/todo/WHERE-INLINING-SPEC.md §9.
data Unfolding = Unfolding
  { readThrough :: Int
  -- ^ Call atoms whose meaning the satisfiability checks used.
  , leftOpaque :: [Text]
  -- ^ Call atoms that stayed opaque, each with the reason. Reported, never
  -- silent: each one is a place where the analysis is the weaker, per-rule one.
  }

noUnfolding :: Unfolding
noUnfolding = Unfolding 0 []

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
        , "callsReadThrough" .= d.drUnfolding.readThrough
        , "callsLeftOpaque" .= d.drUnfolding.leftOpaque
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
          nested = nestedNotVisited tc
      emit opts (render opts reports total nested)
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
  [ analyseDecide opts tc callees decide
  | decide <- topLevelDecides tc
  -- Filter on the name as written BEFORE analysing: a report's name comes out of
  -- the analysis, so filtering on it analysed every decision just to discard
  -- most of them.
  , wanted (decideName decide)
  ]
  where
    callees = unfoldableRules tc
    wanted nm
      | null opts.verifyDecisions = True
      | otherwise = any (`matches` nm) opts.verifyDecisions
    -- A decision's rendered name carries L4's backticks; match with or without.
    matches want nm = want == nm || want == stripBackticks nm

topLevelDecides :: Rules.TypeCheckResult -> [Decide Resolved]
topLevelDecides tc = foldTopLevelDecides (\d -> [d]) tc.module'

-- | How many decisions this command never looked at.
--
-- @foldTopLevelDecides@ is one level deep, so a definition in a @WHERE@ clause
-- is invisible to the analysis — and, being invisible, would otherwise also be
-- invisible to the /accounting/, which is the part that matters. A reader who
-- sees @analysed + skipped@ equal to nothing in particular has no way to tell
-- whether the remainder is two definitions or two hundred.
--
-- @foldDecides@ is the cosmos fold: it yields a decision and everything nested
-- inside it, so subtracting the top-level count leaves exactly the nested ones.
--
-- Descending into them AS DECISIONS OF THEIR OWN is deliberately not done:
-- "LSP.L4.Viz.Ladder"'s own entry point is @foldTopLevelDecides@, and a verifier
-- that disagreed with the ladder about what a rule is would be reporting on a
-- program the wizard never shows anyone.
--
-- That reasoning used to be given for leaving them opaque INSIDE their callers
-- too, and there it was wrong: a rule and the same rule with one limb named are
-- the same program, so reading them differently was the disagreement, not the
-- fix for it. Local bindings are now inlined before analysis, parameterised
-- ones by beta reduction ('L4.Transform.inlineLocalBindingsInDecide';
-- specs/todo/WHERE-INLINING-SPEC.md §5 and §9).
-- What the ladder and the verifier must agree about is what a rule MEANS; how
-- much of it either chooses to draw at once is a separate question, and the
-- @l4\/inlineExprs@ gesture exists precisely so a reader can choose.
nestedNotVisited :: Rules.TypeCheckResult -> Int
nestedNotVisited tc =
  sum [length (foldDecides (\_ -> [() :: ()]) d) | d <- tops] - length tops
  where
    tops = topLevelDecides tc

-- | A decision's name as the drafter wrote it.
decideName :: Decide Resolved -> Text
decideName (MkDecide _ _ (MkAppForm _ n _ _) _) = prettyLayout (getOriginal n)

-- | Analyse one decision.
--
-- The unit of analysis is the decision's OWN ladder, as written: every finding
-- names a site in this rule's text. Local @WHERE@ / @LET@ bindings are substituted
-- first ('Transform.inlineLocalBindingsInDecide'), because a rule means the same
-- thing however its limbs are named.
--
-- A call to another boolean rule is still one leaf of that ladder, but it is no
-- longer an OPAQUE leaf: 'callMeanings' works out what it means, and every
-- satisfiability check below uses that meaning. So a rule that calls an exception
-- and the offence it defeats and asks for both is found unsatisfiable, while the
-- callee's own internal structure — a limb that is dead only in THIS caller's
-- context, say — is not reported here. The callee has its own entry in the report,
-- where its structure is its own text. See specs/todo/WHERE-INLINING-SPEC.md §9.
analyseDecide
  :: VerifyOptions -> Rules.TypeCheckResult -> Map Unique Transform.Unfoldable -> Decide Resolved -> DecisionReport
analyseDecide opts tc callees decide0 =
  case LadderViz.doVisualize decide (vizConfig opts tc True) of
    Left err ->
      DecisionReport
        { drName = decideName decide
        , drResult = Left (LadderViz.prettyPrintVizError err)
        , drUnfolding = noUnfolding
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
                , drUnfolding = noUnfolding
                }
            else
              let (boolExpr, labels, order) = VizQP.vizExprToBoolExpr ladderInfo.funDecl.body
                  atomIds = atomIdsOf fnName ladderInfo vizState
                  (expr', labels', order')
                    | opts.verifyCoalesce = coalesceByAtomId atomIds boolExpr labels order
                    | otherwise = (boolExpr, labels, order)
                  -- Reading through needs atoms to be matched across rules, and
                  -- the atomId is the only identity that crosses a rule boundary,
                  -- so --no-coalesce-atoms turns it off too.
                  meanings
                    | opts.verifyCoalesce = callMeanings opts tc callees decide fnName atomIds labels' vizState order'
                    | otherwise = noMeanings
               in DecisionReport
                    { drName = fnName
                    , drResult =
                        Right
                          Analysis
                            { anAtoms = length order
                            , anAtomClasses = length order'
                            , anLadderNodes = nodes
                            , anFindings =
                                analyseBody labels' (if null meanings.cmOrder then order' else meanings.cmOrder) meanings.cmDefs expr'
                            }
                    , drUnfolding = Unfolding (Map.size meanings.cmDefs) meanings.cmOpaque
                    }
  where
    decide = Transform.inlineLocalBindingsInDecide decide0

vizConfig :: VerifyOptions -> Rules.TypeCheckResult -> Bool -> LadderViz.VizConfig
vizConfig opts tc = LadderViz.mkVizConfig verDocId tc.module' tc.substitution
  where
    verDocId =
      LSP.VersionedTextDocumentIdentifier
        { LSP._uri = LSP.filePathToUri opts.verifyFile
        , LSP._version = 1
        }

-- | Each leaf's stable atomId: the identity the wizard asks one question for,
-- and the only identity that is the same for one proposition in two rules.
atomIdsOf :: Text -> VizExpr.RenderAsLadderInfo -> LadderViz.VizState -> Map Int Text
atomIdsOf fnName ladderInfo vizState =
  QP.atomIdByUnique fnName (VizQP.buildParamsByUnique ladderInfo) (VizQP.buildQueryPlanCache ladderInfo vizState)

-- | What the call atoms of one decision mean, in that decision's atom space.
data CallMeanings = CallMeanings
  { cmDefs :: Map Int (BDQ.BoolExpr Int)
  -- ^ A call atom -> its meaning: the called rule's body, unfolded all the way
  -- down, arguments in place of parameters, over the caller's atoms.
  , cmOrder :: [Int]
  -- ^ The variable order for the whole analysis: the caller's atoms, each call
  -- atom followed at once by the atoms its meaning introduces. A decision
  -- diagram's size depends on its order, and appending those atoms at the end
  -- instead (sorted, as they came out of a map) separated each CONSIDER arm from
  -- its own guard: a 22-arm rule in the miles-card corpus went from 5 s to past
  -- ten minutes. Measured 2026-09-29.
  , cmOpaque :: [Text]
  -- ^ Call atoms that stayed opaque, each with the reason.
  }

noMeanings :: CallMeanings
noMeanings = CallMeanings Map.empty [] []

-- | Work out what each call atom of a decision means.
--
-- For every atom whose leaf is a call to a rule in @callees@: unfold the call
-- ('Transform.unfoldCalls'), substitute local bindings, and draw the result as a
-- ladder of its own — under the caller's name and parameters, so a leaf such as
-- @f's `harm was caused`@ gets the SAME atomId it has in the caller — WITHOUT the
-- CNF simplification. The decision diagram does not need a normal form, and the
-- normal form is where the size goes: s 325 of the Penal Code has four atoms and an
-- unfolded CNF past 4096 nodes. Its atoms are then renumbered into the caller's
-- space by atomId, fresh numbers for atoms the caller does not mention.
--
-- A call whose meaning cannot be drawn, or is over @--max-nodes@ even without the
-- normal form, stays opaque and is named in 'cmOpaque'.
callMeanings
  :: VerifyOptions
  -> Rules.TypeCheckResult
  -> Map Unique Transform.Unfoldable
  -> Decide Resolved
  -> Text
  -> Map Int Text
  -> Map Int Text
  -> LadderViz.VizState
  -> [Int]
  -> CallMeanings
callMeanings opts tc callees (MkDecide ann sig appForm _) fnName atomIds labels vizState order =
  CallMeanings
    { cmDefs = Map.fromList [(v, renumber d) | (v, Right d) <- attempts]
    , cmOrder = placed
    , cmOpaque = [label v <> " \8212 " <> why | (v, Left why) <- attempts]
    }
  where
    label v = stripBackticks (Map.findWithDefault (Text.pack (show v)) v labels)

    attempts :: [(Int, Either Text (BDQ.BoolExpr Text))]
    attempts =
      [ (v, meaningOf x)
      | v <- order
      , Just e <- [LadderViz.getLeafExpr vizState v]
      , Just x <- [unfolded e]
      ]

    -- The call unfolded, or Nothing if the leaf is not a call to a known rule.
    unfolded e = case Transform.unfoldCalls unfoldBudget callees e of
      Right (_, 0) -> Nothing
      Right (x, _) -> Just (Right x)
      Left size ->
        Just (Left ("unfolding it grew past " <> Text.pack (show unfoldBudget) <> " expression nodes (it reached " <> Text.pack (show size) <> ")"))

    meaningOf :: Either Text (Expr Resolved) -> Either Text (BDQ.BoolExpr Text)
    meaningOf = \case
      Left why -> Left why
      Right x ->
        case LadderViz.doVisualize (MkDecide ann sig appForm (Transform.inlineLocalBindings x)) (vizConfig opts tc False) of
          Left err -> Left ("its meaning could not be drawn: " <> LadderViz.prettyPrintVizError err)
          Right (li, vs)
            | ladderNodeCount opts.verifyMaxNodes li.funDecl.body > opts.verifyMaxNodes ->
                Left ("its meaning exceeds --max-nodes=" <> Text.pack (show opts.verifyMaxNodes))
            | otherwise ->
                let (bx, _, _) = VizQP.vizExprToBoolExpr li.funDecl.body
                    aids = atomIdsOf fnName li vs
                 in Right (mapVarsTo (\u -> Map.findWithDefault (localKey u) u aids) bx)

    -- An atom with no atomId is its own proposition; key it so it cannot meet
    -- anything else. (Uniques from different ladders must not be compared.)
    localKey u = "\0local:" <> Text.pack (show u)

    -- The caller's atoms, by atomId.
    callerIndex :: Map Text Int
    callerIndex = Map.fromList [(aid, v) | v <- order, Just aid <- [Map.lookup v atomIds]]

    -- Fresh numbers for the atoms only meanings mention, minted in the order
    -- they are first met walking the caller's atoms: each call atom's meaning in
    -- turn, its atoms in ladder order.
    meaningKeys = nubOrd [k | (_, Right d) <- attempts, k <- varsOfT d, not (Map.member k callerIndex)]
    freshFor :: Map Text Int
    freshFor = Map.fromList (zip meaningKeys [firstFresh ..])
    firstFresh = 1 + maximum (0 : order)

    -- Each caller atom, then the fresh atoms its own meaning introduces.
    placed = go Map.empty order
      where
        meaningOfAtom = Map.fromList [(v, d) | (v, Right d) <- attempts]
        go _ [] = []
        go seen (v : vs) =
          let new = case Map.lookup v meaningOfAtom of
                Nothing -> []
                Just d -> nubOrd [n | k <- varsOfT d, Just n <- [Map.lookup k freshFor], not (Map.member n seen)]
              seen' = foldr (\n -> Map.insert n ()) seen new
           in v : new <> go seen' vs

    renumber = mapVarsTo (\k -> Map.findWithDefault (freshFor Map.! k) k callerIndex)

    varsOfT :: BDQ.BoolExpr Text -> [Text]
    varsOfT = \case
      BDQ.BTrue -> []
      BDQ.BFalse -> []
      BDQ.BVar k -> [k]
      BDQ.BNot x -> varsOfT x
      BDQ.BAnd xs -> concatMap varsOfT xs
      BDQ.BOr xs -> concatMap varsOfT xs
      BDQ.BImplies x y -> varsOfT x <> varsOfT y

mapVarsTo :: (a -> b) -> BDQ.BoolExpr a -> BDQ.BoolExpr b
mapVarsTo f = \case
  BDQ.BTrue -> BDQ.BTrue
  BDQ.BFalse -> BDQ.BFalse
  BDQ.BVar v -> BDQ.BVar (f v)
  BDQ.BNot x -> BDQ.BNot (mapVarsTo f x)
  BDQ.BAnd xs -> BDQ.BAnd (map (mapVarsTo f) xs)
  BDQ.BOr xs -> BDQ.BOr (map (mapVarsTo f) xs)
  BDQ.BImplies x y -> BDQ.BImplies (mapVarsTo f x) (mapVarsTo f y)

-- | A memory guard on unfolding one call, in expression nodes. Not a tuning knob
-- and it has no flag: a call past it simply stays opaque, and is named.
unfoldBudget :: Int
unfoldBudget = 200000

-- | The rules a call may be unfolded into: every top-level DECIDE that returns a
-- BOOLEAN, in this module and in every module it imports (transitively), minus the
-- recursive ones ('Transform.pruneRecursive').
--
-- Boolean only, because the point is the propositional structure: a numeric
-- helper unfolded into a comparison leaves the leaf a leaf, just with a longer
-- label.
--
-- Each body is first zonked with its OWN module's substitution. The checked
-- program's annotations are not zonked when the result is built, and an importer
-- starts from an EMPTY substitution (see "LSP.L4.Rules"), so a rule whose return
-- type was inferred rather than declared (no @GIVETH@) carries an inference
-- variable. Measured: without the zonk such an imported rule is never recognised
-- as boolean, is never unfolded, and a contradiction through it is missed
-- (tests-cli/fixtures/verify-unfold-rules.l4 is written that way on purpose).
unfoldableRules :: Rules.TypeCheckResult -> Map Unique Transform.Unfoldable
unfoldableRules tc0 =
  -- Recursion is a property of which calls a body makes, which zonking does not
  -- change, so prune on the bodies as checked. The zonk itself is left as a thunk
  -- in each surviving entry ('Transform.MkUnfoldable' has lazy fields), so a body
  -- is only ever zonked if some call is actually read through to it. Zonking every
  -- rule of every imported module up front, the prelude included, cost seconds
  -- per file for rules nobody called.
  Map.mapWithKey (\u (Transform.MkUnfoldable ps rhs) -> Transform.MkUnfoldable ps (zonkFor u rhs)) kept
  where
    candidates :: [(Unique, (Transform.Unfoldable, Rules.TypeCheckResult))]
    candidates = concatMap fromModule (Map.elems modules)
    kept = Transform.pruneRecursive (Map.fromList [(u, unf) | (u, (unf, _)) <- candidates])
    owners = Map.fromList [(u, m) | (u, (_, m)) <- candidates]
    zonkFor u rhs = case Map.lookup u owners of
      Just m -> TC.applyFinalSubstitution m.substitution (moduleUri m) rhs
      Nothing -> rhs

    modules :: Map LSP.NormalizedUri Rules.TypeCheckResult
    modules = collect Map.empty [tc0]

    collect acc [] = acc
    collect acc (m : ms)
      | moduleUri m `Map.member` acc = collect acc ms
      | otherwise = collect (Map.insert (moduleUri m) m acc) (m.dependencies ++ ms)

    moduleUri :: Rules.TypeCheckResult -> LSP.NormalizedUri
    moduleUri m = case m.module' of MkModule _ uri _ -> uri

    fromModule m =
      [ (u, (unf, m))
      | d <- topLevelDecides m
      , Just (u, unf@(Transform.MkUnfoldable _ rhs)) <- [Transform.unfoldableDecide d]
      , returnsBoolean m rhs
      ]

    -- Only the body's TYPE is zonked for this test: that is what an inferred
    -- return type needs, and it is cheap.
    returnsBoolean m e = case getAnno e of
      Anno {extra = Extension {resolvedInfo = Just (TypeInfo ty _)}} ->
        case TC.applyFinalSubstitution m.substitution (moduleUri m) ty of
          TyApp _ (Ref _ u _) [] -> u == TC.booleanUnique
          _ -> False
      _ -> False

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
      VizExpr.App _ _ args _ _ -> args
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
-- | Is @e@, together with the context, satisfiable? Every call atom with a
-- meaning in @defs@ is replaced by that meaning first ('callMeanings'); the
-- meanings are fully unfolded already, so one pass suffices.
satisfiable :: [Int] -> Map Int (BDQ.BoolExpr Int) -> [BDQ.BoolExpr Int] -> BDQ.BoolExpr Int -> Bool
satisfiable order defs ctx e =
  let expand = \case
        BDQ.BVar v -> Map.findWithDefault (BDQ.BVar v) v defs
        BDQ.BNot x -> BDQ.BNot (expand x)
        BDQ.BAnd xs -> BDQ.BAnd (map expand xs)
        BDQ.BOr xs -> BDQ.BOr (map expand xs)
        BDQ.BImplies x y -> BDQ.BImplies (expand x) (expand y)
        other -> other
      compiled = BDQ.compileDecisionQuery order (expand (BDQ.BAnd (e : ctx)))
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

analyseBody :: Map Int Text -> [Int] -> Map Int (BDQ.BoolExpr Int) -> BDQ.BoolExpr Int -> [Finding]
analyseBody labels order defs body
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
    sat = satisfiable order defs
    atomLabels e = [label u | u <- nubOrd (varsOf e)]
    label u = stripBackticks (Map.findWithDefault (Text.pack (show u)) u labels)

    -- Is this subterm capable of being false at all?
    --
    -- The gate that keeps "this condition excludes nothing" from crying wolf.
    -- The ladder body is in CONJUNCTIVE normal form, and reaching CNF
    -- MANUFACTURES valid clauses: `x XOR y' written out as
    -- @(x AND NOT y) OR ((NOT x) AND y)@ distributes to a conjunction that
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

render :: VerifyOptions -> [DecisionReport] -> Int -> Int -> Either BSL8.ByteString Text
render opts reports total nested = case opts.verifyFormat of
  VfJson -> Left (Aeson.encode (jsonEnvelope opts reports total nested))
  VfText -> Right (textReport opts reports total nested)

jsonEnvelope :: VerifyOptions -> [DecisionReport] -> Int -> Int -> Aeson.Value
jsonEnvelope opts reports total nested =
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
          , -- Call atoms read through to the rules they call, and those left
            -- opaque. Every opaque one is also named on its decision.
            "callsReadThrough" .= sum [r.drUnfolding.readThrough | r <- reports]
          , "callsLeftOpaque" .= sum [length r.drUnfolding.leftOpaque | r <- reports]
          , -- Decisions nested in a WHERE clause: neither analysed nor skipped,
            -- because never visited. Reported so that the three numbers above
            -- cannot be mistaken for a total. See 'nestedNotVisited'.
            "nestedNotVisited" .= nested
          ]
    ]
  where
    analysed = [a | r <- reports, Right a <- [r.drResult]]
    allFindings = concatMap reportFindings reports

boundOneLine :: Text
boundOneLine =
  "propositional only: every leaf is an opaque atom, so no numeric, interval, date or \
  \string contradiction is visible. Findings are sound; silence is not a consistency proof."

textReport :: VerifyOptions -> [DecisionReport] -> Int -> Int -> Text
textReport opts reports total nested =
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
            <> " ladder nodes"
            <> ( if r.drUnfolding.readThrough == 0
                  then ""
                  else ", " <> Text.pack (show r.drUnfolding.readThrough) <> " call(s) read through"
               )
            <> ") — "
            <> ( if null a.anFindings
                  then "no propositional findings"
                  else Text.pack (show (length a.anFindings)) <> " finding(s)"
               )
        ]
          <> [ "    call left as a leaf: " <> why | why <- r.drUnfolding.leftOpaque ]
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
        <> ( if nested == 0
              then ""
              else
                " "
                  <> Text.pack (show nested)
                  <> " further decision(s) nested in a WHERE clause were NOT visited\n  \
                     \(neither analysed nor skipped) \8212 see the bound below."
           )
        <> ( if opaque == 0
              then ""
              else
                " "
                  <> Text.pack (show opaque)
                  <> " call(s) were left as leaves rather than read through \8212 the\n  \
                     \weaker analysis at those atoms; each is named on its rule."
           )
    opaque = sum [length r.drUnfolding.leftOpaque | r <- reports]

-- | Strip the backticks L4 uses to quote identifiers containing spaces. The
-- wizard's JSON does the same thing for the same reason.
stripBackticks :: Text -> Text
stripBackticks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
