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
--   clauses that must both hold and cannot. A decision whose body is the
--   literal @FALSE@ is not reported: it is listed as a constant ('literalBody').
--
-- [@dead-branch@] A disjunct of an @OR@ that is unsatisfiable in its context.
--   The rule would read identically with the limb deleted, which means either
--   the limb is inoperative or the draftsman meant something else by it.
--
-- [@vacuous-guard@] Either (a) the scope of a seam (the @scope IMPLIES
--   requirement@ shape the ladder draws with two lamps) is unsatisfiable, so the
--   rule never reaches anybody and is vacuously true; or (b) a condition the
--   draftsman wrote that its own siblings already entail, so it excludes nothing
--   and is a guard in name only. (b) is read off the rule AS WRITTEN, not off the
--   normal form the other families read, because the normal form manufactures
--   conjuncts nobody wrote ('Written', smucclaw/l4-ide#1093).
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
  , verifyLimitsNote
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.IntMap.Strict as IntMap
import qualified Data.IntSet as IntSet
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
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
import qualified L4.Viz.GuardedRows as GR
import L4.Annotation (Anno_ (..), getAnno)
import qualified LSP.L4.Viz.Ladder as LadderViz
import qualified LSP.L4.Viz.QueryPlan as VizQP
import qualified LSP.L4.Viz.VizExpr as VizExpr

import L4.Parser.SrcSpan (SrcPos (..), prettySrcPos)
import L4.Print (prettyLayout)
import L4.Syntax

import L4.Cli.Common
import L4.EvaluateLazy (EvalConfig)

----------------------------------------------------------------------------
-- The honest bound
----------------------------------------------------------------------------

-- | What this command does and does not prove. Printed as the @--help@ footer
-- and at the foot of the text report.
--
-- Every sentence here is a limitation somebody would otherwise have to discover
-- by being wrong in public.
-- | The @--help@ footer's note on the four limit flags (decided by Claude
-- 2026-11-21, pending Meng's review). The command takes them, as every command
-- that evaluates does (ruled by Meng 2026-11-21, extending L2), but it only type-checks and reads
-- the ladder: nothing here applies a function, so no count can fire.
verifyLimitsNote :: String
verifyLimitsNote =
  unlines
    [ "THE LIMIT FLAGS"
    , ""
    , "  --max-open, --max-steps, --eval-timeout and --max-eval-memory-mb are"
    , "  accepted here as on the l4 commands that work out values, but they"
    , "  never stop anything here: this command reads each rule's AND/OR"
    , "  shape and works out no values."
    ]

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
    , "  property of the boolean skeleton, with one exception: a condition in a"
    , "  local definition used more than once can be reported because another"
    , "  use repeats it, although nothing is redundant (a limit, stated below)."
    , "  Silence is not a consistency proof:"
    , "  it means nothing was found at this level of abstraction, which is a"
    , "  much weaker claim and must be reported as the weaker one."
    , ""
    , "  The unit of analysis is the LADDER's AND/OR normal form of each"
    , "  boolean DECIDE (for a redundant condition, the ladder drawn without"
    , "  the normal form: see below), not the L4 source. Guarded chains"
    , "  (IF/BRANCH/CONSIDER over booleans) are expanded; whatever the ladder"
    , "  treats as a leaf is a leaf here too. A DECIDE that does not return"
    , "  BOOLEAN is not analysed, and is reported as skipped rather than as"
    , "  clean."
    , ""
    , "  A DECIDE whose body is the literal TRUE or FALSE, as written, is a"
    , "  CONSTANT: it is listed as one and counted (summary.constants), and"
    , "  nothing in it is checked, so a FALSE one is not reported as unsat."
    , "  A body that is FALSE without being the literal -- `FALSE OR FALSE',"
    , "  or a call read through to a constant -- is analysed as usual."
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
    , "  containing `x OR NOT x', and `(a AND b) OR ((NOT a) AND e)' into four"
    , "  clauses, the last of which, `b OR e', follows from two of the others."
    , "  So a redundant condition is looked for in the rule AS WRITTEN, drawn"
    , "  without the normal form, and reported as a vacuous guard at its place"
    , "  there, with the line and column of its first word in the source: a"
    , "  condition its siblings already entail, or an alternative the others"
    , "  already cover. It is looked for under a NOT too, at a site such as"
    , "  `body.not.or[0]'; there a condition the normal form has, negated, as"
    , "  a dead branch is reported as that dead branch alone, if the dead"
    , "  branch is in the same part of the rule (its scope or its"
    , "  requirement, when the rule is an IMPLIES; otherwise the whole rule)"
    , "  and names no atom outside the NOT. Within those bounds the match is"
    , "  by meaning, not by place. Two"
    , "  conditions that entail each other, such as the two `x' of `x AND x',"
    , "  are both reported, and so are two alternatives that cover each other,"
    , "  although deleting either one alone leaves the rule as it was."
    , "  A condition written in a local definition (WHERE or LET) is placed"
    , "  where the definition writes it, at its opening bracket if its first"
    , "  word is one of the definition's parameters, and at the argument the"
    , "  use passes in if it is a parameter and nothing else."
    -- Placing the next one at its bracket was decided by Claude 2026-11-25,
    -- pending Meng's review ('LadderViz.writtenStart').
    , "  A bracketed group whose first word is a use of a local definition is"
    , "  placed at its bracket, not at that word."
    , "  When a local definition is used more than once, a condition inside it"
    , "  can be reported because another use repeats it, and l4 verify cannot"
    , "  tell such a finding from a real one: `qualifies a AND qualifies b',"
    , "  where `qualifies x' means `x AND c', reports `c' twice, although"
    , "  nothing in the rule is redundant. This is a known limit of this check"
    , "  and is not fixed here."
    , "  In a guarded chain (IF/BRANCH/CONSIDER) each row also carries the"
    , "  negations of the tests before it, which nobody wrote, so the tests are"
    , "  not checked for this, only what each row's THEN, the ELSE and the"
    , "  OTHERWISE say: a redundant condition inside a test goes unreported."
    -- A limit, stated here and on the doc page, not a choice (the note on
    -- the OR case of the walk in 'analyseBody' says where it comes from).
    , "  Nothing inside an alternative is judged against the negations of the"
    , "  alternatives beside it, so what only those make redundant goes"
    , "  unreported too: the `a', or the `NOT a', of"
    , "  `(a AND b) OR ((NOT a) AND b)', which means just `b', and the"
    , "  `c AND d' of `d OR (a AND (b OR (c AND d)))', which can hold only"
    , "  where `d' has already let the case through."
    -- A limit, stated here and on the doc page, not a choice (the note on
    -- 'covered' in 'analyseBody' says why).
    , "  An alternative that can never hold is reported only where the normal"
    , "  form keeps a part of it that is a dead branch there, so in"
    , "  `b OR (a AND c AND (NOT a))' the second alternative, which can never"
    , "  hold, goes unreported, and the rule gets no finding."
    , "  The sites of the other findings, and of the vacuous guard that is a"
    , "  scope nobody can be in, are places in the normal form, which need not"
    , "  exist in the source, and they carry no line and column. So in the"
    , "  JSON, a site is in the rule as written when its finding has a"
    , "  writtenAt, and in the normal form when it has none. Only"
    , "  CONTINGENT entailment is reported, i.e. this condition adds nothing"
    , "  GIVEN THE OTHERS: a hand-written condition that is true on its own,"
    , "  such as `y OR NOT y', is a different defect and goes unreported."
    , ""
    , "  A finding on a rule that reads through a constant names the constant"
    , "  when it is inside the reported condition and has the finding's sign:"
    , "  a FALSE one for a finding that something can never hold, a TRUE one"
    , "  for a finding that something always holds, each the other way round"
    , "  under a NOT or in the scope of an IMPLIES."
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
  , verifyLimits    :: EvalLimits
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
  <*> evalLimitsParser

----------------------------------------------------------------------------
-- Result types
----------------------------------------------------------------------------

data Finding = Finding
  { findingKind    :: Text
  , findingSite    :: Text
  , findingAtoms   :: [Text]
  , findingMessage :: Text
  , findingWrittenAt :: Maybe SrcPos
  -- ^ Where the condition starts in the source, for a finding read off the rule
  -- as written ('AsWritten'): @writtenAt@ in the JSON, ", written at L:C" in the
  -- text (decided by Claude 2026-11-25, pending Meng's review). A finding read
  -- off the normal form has none: that form's nodes are not in the source. Only
  -- the start: the end of an expression's range can run on past it (a
  -- parenthesised limb followed by an operator on the next line ends at that
  -- operator).
  }

instance Aeson.ToJSON Finding where
  toJSON f =
    Aeson.object $
      [ "kind" .= f.findingKind
      , "site" .= f.findingSite
      , "atoms" .= f.findingAtoms
      , "message" .= f.findingMessage
      ]
        <> [ "writtenAt" .= Aeson.object ["line" .= p.line, "column" .= p.column]
           | Just p <- [f.findingWrittenAt]
           ]

data Analysis = Analysis
  { anAtoms       :: Int
  -- ^ Distinct BDD variables before coalescing, i.e. leaf OCCURRENCES.
  , anAtomClasses :: Int
  -- ^ Distinct variables actually compiled. Below 'anAtoms' exactly when
  -- occurrences of one question were merged.
  , anLadderNodes :: Int
  , anFindings    :: [Finding]
  , anConstant    :: Maybe Bool
  -- ^ The literal the body is, for a decision whose body as written is the
  -- literal TRUE or FALSE ('literalBody'). Such a decision has nothing to check
  -- and no findings; it is listed as a constant (smucclaw/l4-ide#1095).
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
      Aeson.object $
        [ "name" .= d.drName
        , "analysed" .= True
        , "atoms" .= a.anAtoms
        , "atomClasses" .= a.anAtomClasses
        , "ladderNodes" .= a.anLadderNodes
        , "callsReadThrough" .= d.drUnfolding.readThrough
        , "callsLeftOpaque" .= d.drUnfolding.leftOpaque
        , "findings" .= a.anFindings
        ]
          -- Present only on a constant, and a string, so that a reader testing
          -- the field for truth is not told a constant FALSE is no constant.
          <> ["constant" .= literalText b | Just b <- [a.anConstant]]

reportFindings :: DecisionReport -> [Finding]
reportFindings d = either (const []) (.anFindings) d.drResult

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

verifyCmd :: VerifyOptions -> IO ()
verifyCmd opts = do
  evalConfig <- withEvalLimits opts.verifyLimits =<< makeEvalConfig opts.verifyFixedNow
  guardRunStop "l4 verify" evalConfig (verifyWith opts evalConfig)

-- | 'verifyCmd' under the limits its flags set (ruled by Meng 2026-11-21, extending L2).
verifyWith :: VerifyOptions -> EvalConfig -> IO ()
verifyWith opts evalConfig = do
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
  [ analyseDecide opts callees cfg decide
  | decide <- topLevelDecides tc
  -- Filter on the name as written BEFORE analysing: a report's name comes out of
  -- the analysis, so filtering on it analysed every decision just to discard
  -- most of them.
  , wanted (decideName decide)
  ]
  where
    callees = unfoldableRules tc
    -- ONE config for the whole file. It carries the key environment, which walks
    -- the module, so a config made per decision (or per call a decision reads
    -- through) paid for that walk each time: quadratic in the size of the file.
    cfg = vizConfig opts tc
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
--
-- A definition the clause desugarer generated is not counted: the @LET@ that
-- binds "the clauses not yet tried" of a rule written as DECIDE clauses
-- ('PmSynthetic'). No drafter wrote it, and the rule around it is analysed as
-- the CONSIDER it stands for, with that @LET@ read through
-- ('L4.Transform.inlineLetsForViz'), so nothing in it went unvisited.
nestedNotVisited :: Rules.TypeCheckResult -> Int
nestedNotVisited tc =
  sum [length (foldDecides drafted d) - length (drafted d) | d <- topLevelDecides tc]
  where
    drafted :: Decide Resolved -> [()]
    drafted (MkDecide ann _ _ _) = [() | isNothing (view annPmSynthetic ann)]

-- | A decision's name as the drafter wrote it.
decideName :: Decide Resolved -> Text
decideName (MkDecide _ _ (MkAppForm _ n _ _) _) = prettyLayout (getOriginal n)

-- | The literal a decision's body is, as the drafter wrote it: @DECIDE x IF
-- FALSE@ and @x MEANS FALSE@ alike. Such a decision is a deliberate constant
-- ("the text says no", a provision switched off), so it is listed as a
-- constant and nothing in it is checked: a FALSE one used to be reported
-- @unsat@, "a requirement nobody can meet" (smucclaw/l4-ide#1095).
--
-- Read off the body as written, before local bindings are put in, and only the
-- literal itself. Not "no atoms": inert prose lowers to a constant too
-- ('interesting'), and a body that is FALSE without being the literal
-- (@FALSE OR FALSE@, or a call read through to a constant) keeps its finding.
--
-- Listed as analysed, with no findings, counted in @summary.constants@ and
-- marked @"constant": "TRUE"@ or @"FALSE"@ in the JSON, and "a constant: its
-- body is the literal FALSE, so there is nothing to check" in the text
-- (decided by Claude 2026-11-25, pending Meng's review).
literalBody :: Decide Resolved -> Maybe Bool
literalBody (MkDecide _ _ _ body) = GR.literalBool body

literalText :: Bool -> Text
literalText b = if b then "TRUE" else "FALSE"

-- | A constant has no findings ('literalBody'); anything else is left alone.
asConstant :: Analysis -> Analysis
asConstant a = case a.anConstant of
  Just _ -> a {anFindings = []}
  Nothing -> a

-- | Analyse one decision.
--
-- The unit of analysis is the decision's OWN ladder: every finding names a site
-- in it, and a site is a place in this rule, not in a rule it calls. Most
-- findings are read off the ladder's normal form, whose sites need not exist in
-- the source; a redundant condition is read off the ladder as written
-- ('Written'), and carries where it starts in the source. Local @WHERE@ /
-- @LET@ bindings are substituted first ('Transform.inlineLocalBindingsInDecide'),
-- because a rule means the same thing however its limbs are named.
--
-- A call to another boolean rule is still one leaf of that ladder, but it is no
-- longer an OPAQUE leaf: 'callMeanings' works out what it means, and every
-- satisfiability check below uses that meaning. So a rule that calls an exception
-- and the offence it defeats and asks for both is found unsatisfiable, while the
-- callee's own internal structure — a limb that is dead only in THIS caller's
-- context, say — is not reported here. The callee has its own entry in the report,
-- where its structure is its own text. See specs/todo/WHERE-INLINING-SPEC.md §9.
analyseDecide
  :: VerifyOptions -> Callees -> LadderViz.VizConfig -> Decide Resolved -> DecisionReport
analyseDecide opts callees cfg decide0 =
  case LadderViz.doVisualize decide cfg of
    Left err ->
      DecisionReport
        { drName = decideName decide
        , drResult = Left (LadderViz.prettyPrintVizError err)
        , drUnfolding = noUnfolding
        }
    -- A rule written as clauses whose whole ladder is one box holding the
    -- CONSIDER the clauses compile to: the ladder could not break it down (a
    -- column matches JUST x, a list or the like), so there is nothing here to
    -- check, and "no findings" would read as a clean bill.
    Right (ladderInfo, vizState)
      | Transform.writtenAsClauses decide
      , VizExpr.UBoolVar _ leaf _ _ _ _ _ <- ladderInfo.funDecl.body
      , Just (Consider leafAnn _ _) <- LadderViz.getLeafExpr vizState leaf.unique
      , Just PmConsider{} <- view annPmSynthetic leafAnn ->
          DecisionReport
            { drName = ladderInfo.funDecl.fnName.label
            , drResult = Left notBrokenDown
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
                    | opts.verifyCoalesce = callMeanings opts callees cfg decide fnName atomIds labels' vizState order'
                    | otherwise = noMeanings
                  analysisOrder = if null meanings.cmOrder then order' else meanings.cmOrder
                  written = writtenForm opts cfg decide fnName atomIds order labels' analysisOrder
               in DecisionReport
                    { drName = fnName
                    , drResult =
                        Right . asConstant $
                          Analysis
                            { anAtoms = length order
                            , anConstant = constant
                            , anAtomClasses = length order'
                            , anLadderNodes = nodes
                            , anFindings =
                                analyseBody labels' analysisOrder meanings.cmDefs meanings.cmListed expr' written
                            }
                    , drUnfolding = Unfolding (Map.size meanings.cmDefs) meanings.cmOpaque
                    }
  where
    -- Local bindings put in before analysis, a rule written as clauses read as
    -- its CONSIDER first ('Transform.inlineLocalBindingsForDrawing'). A rule
    -- written as clauses too long to read through is left as written, and the
    -- ladder refuses it ('LadderViz.ClauseGroupTooLong'); a call to one is
    -- left as a box ('callMeanings').
    constant = literalBody decide0
    decide = case decide0 of
      MkDecide ann sig af body -> MkDecide ann sig af (fromMaybe body (Transform.inlineLocalBindingsForDrawing body))
    notBrokenDown =
      "these clauses were not broken down into questions: a column matches a pattern other than an enum value or a literal (JUST x, a list, and the like), so the whole rule is one box and there is nothing in it to check"

-- | The config every decision of the file is drawn from, with simplification on
-- (a call's meaning is drawn without it: 'LadderViz.withSimplification', which
-- keeps the key environment).
vizConfig :: VerifyOptions -> Rules.TypeCheckResult -> LadderViz.VizConfig
vizConfig opts tc = LadderViz.mkVizConfig verDocId tc.module' tc.substitution True
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
  QP.atomIdByUnique fnName (VizQP.buildQueryPlanCache ladderInfo vizState)

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
  , cmListed :: Set Int
  -- ^ Call atoms whose called rule is itself listed as a constant: its body is
  -- the literal TRUE or FALSE ('literalBody').
  }

noMeanings :: CallMeanings
noMeanings = CallMeanings Map.empty [] [] Set.empty

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
  -> Callees
  -> LadderViz.VizConfig
  -> Decide Resolved
  -> Text
  -> Map Int Text
  -> Map Int Text
  -> LadderViz.VizState
  -> [Int]
  -> CallMeanings
callMeanings opts callees cfg (MkDecide ann sig appForm _) fnName atomIds labels vizState order =
  CallMeanings
    { cmDefs = Map.fromList [(v, renumber d) | (v, Right d) <- attempts]
    , cmOrder = placed
    , cmOpaque = [label v <> " \8212 " <> why | (v, Left why) <- attempts]
    , cmListed =
        Set.fromList
          [ v
          | v <- order
          , Just e <- [LadderViz.getLeafExpr vizState v]
          , Just (r, _) <- [Transform.positionalCall e]
          , Just (Transform.MkUnfoldable _ body) <- [Map.lookup (getUnique r) callees.readable]
          , isJust (GR.literalBool body)
          ]
    }
  where
    label v = stripBackticks (Map.findWithDefault (Text.pack (show v)) v labels)
    tooLongReason =
      "its meaning could not be drawn: " <> LadderViz.prettyPrintVizError (LadderViz.ClauseGroupTooLong Transform.letInliningNodeBudget)

    attempts :: [(Int, Either Text (BDQ.BoolExpr Text))]
    attempts =
      [ (v, meaningOf v x)
      | v <- order
      , Just e <- [LadderViz.getLeafExpr vizState v]
      , Just x <- [unfolded e]
      ]

    -- The call unfolded, or Nothing if the leaf is not a call to a known rule.
    -- A call to a rule written as clauses too long to read through is left as a
    -- box before anything is unfolded, so that refusing it costs only the
    -- bounded reading of its clauses ('Callees'), not the callee's size.
    unfolded e = case Transform.positionalCall e of
      Just (r, _) | Set.member (getUnique r) callees.tooLong -> Just (Left tooLongReason)
      _ -> unfoldedReadable e
    unfoldedReadable e = case Transform.unfoldCalls unfoldBudget callees.readable e of
      Right (_, 0) -> Nothing
      Right (x, _) -> Just (Right x)
      Left size ->
        Just (Left ("unfolding it grew past " <> Text.pack (show unfoldBudget) <> " expression nodes (it reached " <> Text.pack (show size) <> ")"))

    meaningOf :: Int -> Either Text (Expr Resolved) -> Either Text (BDQ.BoolExpr Text)
    meaningOf v = \case
      Left why -> Left why
      Right x -> case Transform.inlineLocalBindingsForDrawing x of
        -- It calls a rule written as clauses too long to read through. Drawn
        -- as it is, the clauses' LETs would be one leaf whose key reads them
        -- through, which does not finish; the call stays a box instead.
        Nothing -> Left tooLongReason
        Just x' -> case LadderViz.doVisualize (MkDecide ann sig appForm x') (LadderViz.withSimplification False cfg) of
          Left err -> Left ("its meaning could not be drawn: " <> LadderViz.prettyPrintVizError err)
          Right (li, vs)
            | ladderNodeCount opts.verifyMaxNodes li.funDecl.body > opts.verifyMaxNodes ->
                Left ("its meaning exceeds --max-nodes=" <> Text.pack (show opts.verifyMaxNodes))
            | otherwise ->
                let (bx, _, _) = VizQP.vizExprToBoolExpr li.funDecl.body
                    aids = atomIdsOf fnName li vs
                    fresh = LadderViz.getFreshLeaves vs
                    key u
                      | IntSet.member u fresh = localKey "fresh" v u
                      | otherwise = Map.findWithDefault (localKey "local" v u) u aids
                 in Right (mapVarsTo key bx)

    -- An atom with no atomId is its own proposition; key it so it cannot meet
    -- anything else. So is an atom whose value depends on when it is evaluated
    -- (a ledger read): its atomId is numbered within its own diagram, and two
    -- meanings drawn apart would otherwise share it. Uniques from different
    -- ladders must not be compared, so the key carries the call atom @v@ whose
    -- meaning drew it.
    localKey :: Text -> Int -> Int -> Text
    localKey kind v u = "\0" <> kind <> ":" <> Text.pack (show v) <> ":" <> Text.pack (show u)

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
      BDQ.BRefuse k -> [k]  -- never built here: the query plan's, not verify's
      BDQ.BNot x -> varsOfT x
      BDQ.BAnd xs -> concatMap varsOfT xs
      BDQ.BOr xs -> concatMap varsOfT xs
      BDQ.BImplies x y -> varsOfT x <> varsOfT y

mapVarsTo :: (a -> b) -> BDQ.BoolExpr a -> BDQ.BoolExpr b
mapVarsTo f = \case
  BDQ.BTrue -> BDQ.BTrue
  BDQ.BFalse -> BDQ.BFalse
  BDQ.BVar v -> BDQ.BVar (f v)
  BDQ.BRefuse v -> BDQ.BRefuse (f v)
  BDQ.BNot x -> BDQ.BNot (mapVarsTo f x)
  BDQ.BAnd xs -> BDQ.BAnd (map (mapVarsTo f) xs)
  BDQ.BOr xs -> BDQ.BOr (map (mapVarsTo f) xs)
  BDQ.BImplies x y -> BDQ.BImplies (mapVarsTo f x) (mapVarsTo f y)

-- | A memory guard on unfolding one call, in expression nodes. Not a tuning knob
-- and it has no flag: a call past it simply stays opaque, and is named.
unfoldBudget :: Int
unfoldBudget = 200000

-- | The rules a call may be read through to, and the rules written as clauses
-- too long to read through ('Transform.clausesReadThrough'), a call to which is
-- left as a box.
data Callees = Callees
  { readable :: Map Unique Transform.Unfoldable
  , tooLong :: Set Unique
  }

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
unfoldableRules :: Rules.TypeCheckResult -> Callees
unfoldableRules tc0 =
  -- Recursion is a property of which calls a body makes, which zonking does not
  -- change, so prune on the bodies as checked. The zonk itself is left as a thunk
  -- in each surviving entry ('Transform.MkUnfoldable' has lazy fields), so a body
  -- is only ever zonked if some call is actually read through to it. Zonking every
  -- rule of every imported module up front, the prelude included, cost seconds
  -- per file for rules nobody called.
  Callees
    { readable = Map.mapWithKey (\u (Transform.MkUnfoldable ps rhs) -> Transform.MkUnfoldable ps (zonkFor u rhs)) readsThrough
    , tooLong = Map.keysSet tooLongToRead
    }
  where
    -- Which rules written as clauses read through is decided on the bodies as
    -- checked too, before any is zonked or unfolded, and on each rule's own body,
    -- as the IDE decides whether to offer a call for expansion. A rule that calls
    -- one that does not read through is still read through itself, with that
    -- call left inside it as a box.
    (readsThrough, tooLongToRead) = Map.partition (\ (Transform.MkUnfoldable _ rhs) -> Transform.clausesReadThrough rhs) kept
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
-- The rule as written
----------------------------------------------------------------------------

-- | The rule as written: its body drawn WITHOUT the normal form, so its
-- conjunctions are the drafter's own, with its atoms in the analysis's atom
-- space. A redundant condition (a conjunct entailed, an alternative covered) is
-- looked for here and nowhere else (smucclaw/l4-ide#1093): the normal form
-- distributes a disjunction of conjunctions into clauses nobody wrote, and some
-- of those are entailed by their siblings (@(a AND b) OR ((NOT a) AND e)@ yields @b OR e@, entailed by
-- @a OR e@ and @NOT a OR b@), although no condition in the source is.
--
-- One expansion is still in this drawing, because the ladder draws it whether
-- it simplifies or not ("L4.Viz.GuardedRows"): each row of a guarded chain
-- (IF, BRANCH, CONSIDER) carries the negations of the guards before it, which
-- nobody wrote. Every occurrence of a guard, negated or not, is drawn as a copy
-- with no source range, so 'wStarts' has no entry for it, and the walk reports
-- a redundant condition only where 'wStarts' has one: a row's THEN and the
-- OTHERWISE are checked, the guards are not.
--
-- Reading this one finding off a second drawing, rather than mapping the normal
-- form's clauses back to the source, was decided by Claude 2026-11-25, pending
-- Meng's review: @Transform.simplify@ builds every node it makes with no
-- annotation, so a clause cannot be traced to a condition, and a condition whose
-- normal form is several clauses (@x AND (x OR (q AND r))@) maps to none of
-- them.
data Written = Written
  { wBody   :: BDQ.BoolExpr Int
  , wLabels :: Map Int Text
  , wOrder  :: [Int]
  -- ^ Every variable of 'wBody' and of the call meanings.
  , wStarts :: Map Text SrcPos
  -- ^ Site -> where the condition at that site starts in the source ('siteStarts').
  }

-- | Draw the rule as written and put its atoms in the analysis's atom space.
--
-- With atoms coalesced, a written atom is joined to the analysed atom with the
-- same atomId, so the call meanings ('callMeanings') apply to it unchanged and
-- are not drawn twice. Two kinds of atom are never joined, and get a variable
-- of their own instead: a leaf keyed apart per occurrence ('LadderViz.getFreshLeaves'),
-- whose atomId is numbered within its own diagram, and a leaf with no atomId.
-- Keeping an atom apart only ever makes a formula more satisfiable, so it can
-- hide a redundant condition but cannot invent one.
--
-- With @--no-coalesce-atoms@ there are no call meanings and no join: the drawing
-- is analysed in its own atom space.
--
-- 'Nothing' if the rule cannot be drawn this way. Then the check for a
-- redundant condition, a conjunct its siblings entail or an alternative the
-- others cover, is not run on the rule, and the report does not say so; the
-- normal form's findings are reported as usual. The drawing here is the one
-- the analysis drew, without its simplification, so it fails for the reasons
-- that one would have failed for first, with one exception: a rule written as
-- DECIDE clauses that reads through, whose ladder, unsimplified, is larger
-- than 'Transform.clauseGroupLadderBudget' when the simplified one is not
-- ('LadderViz.ClauseGroupTooLarge'). That is read from the code, not
-- measured.
writtenForm
  :: VerifyOptions
  -> LadderViz.VizConfig
  -> Decide Resolved
  -> Text
  -> Map Int Text
  -- ^ The analysed drawing's atomIds, by leaf unique.
  -> [Int]
  -- ^ The analysed drawing's leaves, before coalescing.
  -> Map Int Text
  -- ^ The analysis's labels.
  -> [Int]
  -- ^ The analysis's variable order.
  -> Maybe Written
writtenForm opts cfg decide fnName atomIds order labels analysisOrder =
  case LadderViz.doVisualize decide (LadderViz.withSimplification False cfg) of
    Left _ -> Nothing
    Right (li, vs) ->
      let (bx, labelsW, orderW) = VizQP.vizExprToBoolExpr li.funDecl.body
          starts = siteStarts (LadderViz.getNodeStarts vs) li.funDecl.body
       in Just $
            if not opts.verifyCoalesce
              then Written bx labelsW orderW starts
              else joined li vs bx labelsW orderW starts
  where
    joined li vs bx labelsW orderW starts =
      Written
        { wBody = mapVars target bx
        , wLabels = labels <> Map.fromList [(target w, l) | (w, l) <- Map.toList labelsW, not (isJoined (keyOf w))]
        , wOrder = analysisOrder <> [v | k <- newKeys, Just v <- [Map.lookup k newVar]]
        , wStarts = starts
        }
      where
        aidsW = atomIdsOf fnName li vs
        freshW = LadderViz.getFreshLeaves vs
        -- The analysed atom for each atomId: the representative coalescing chose.
        analysed :: Map Text Int
        analysed = Map.fromListWith (\_new old -> old) [(aid, u) | u <- order, Just aid <- [Map.lookup u atomIds]]
        keyOf :: Int -> Either Int Text
        keyOf w
          | IntSet.member w freshW = Left w
          | Just aid <- Map.lookup w aidsW = Right aid
          | otherwise = Left w
        isJoined = either (const False) (`Map.member` analysed)
        newKeys = nubOrd [k | w <- orderW, let k = keyOf w, not (isJoined k)]
        firstNew = 1 + maximum (0 : analysisOrder <> order)
        newVar = Map.fromList (zip newKeys [firstNew ..])
        target w = case keyOf w of
          Right aid | Just v <- Map.lookup aid analysed -> v
          k -> Map.findWithDefault w k newVar

-- | Where each site of a drawing starts in the source: where the text of the
-- node at that site starts, its first word ('LadderViz.getNodeStarts'), named as
-- 'analyseBody' names sites (@body.and[1].or[0]@, and so on).
-- 'VizQP.vizExprToBoolExpr' keeps the drawing's shape node for node, so a site
-- of the formula is the same site of the drawing.
siteStarts :: IntMap.IntMap SrcPos -> VizExpr.IRExpr -> Map Text SrcPos
siteStarts starts = go "body"
  where
    go site e =
      maybe Map.empty (Map.singleton site) (IntMap.lookup (LadderViz.irNodeId e).id starts)
        <> children site e
    children site = \case
      VizExpr.And _ xs -> Map.unions [go (site <> ".and[" <> Text.pack (show i) <> "]") x | (i, x) <- zip [(0 :: Int) ..] xs]
      VizExpr.Or _ xs -> Map.unions [go (site <> ".or[" <> Text.pack (show i) <> "]") x | (i, x) <- zip [(0 :: Int) ..] xs]
      VizExpr.Implies _ s r _ -> go (site <> ".scope") s <> go (site <> ".requirement") r
      VizExpr.Not _ x -> go (site <> ".not") x
      _ -> Map.empty

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
-- inventing a notion of sameness: the atomId already defines one, and it is the
-- one a wizard user answers once.
--
-- Coalescing IS sound only if two different propositions never share an atomId.
-- That held only approximately while the atomId was a hash of the PRINTED label
-- (two mixfix calls sharing a head keyword printed alike: smucclaw/l4-ide#1004);
-- it is the hash of the leaf's term now ("L4.Viz.AtomKey", R3), which names
-- every name by its own binder.
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
  BDQ.BRefuse v -> BDQ.BRefuse (f v)
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
  BDQ.BRefuse v -> [v]
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

-- | Which findings a walk over one drawing of a rule reports ('analyseBody').
data Pass
  = Normalised
  -- ^ Over the ladder's normal form, the drawing the rest of the analysis
  -- reads: @unsat@, @dead-branch@, the seam's @vacuous-guard@ (a) and
  -- @unreachable-outcome@.
  | AsWritten
  -- ^ Over the rule as written ('Written'): the @vacuous-guard@ (b), a
  -- condition its own siblings already entail or an alternative the others
  -- already cover, and only that.
  deriving stock Eq

analyseBody
  :: Map Int Text -> [Int] -> Map Int (BDQ.BoolExpr Int) -> Set Int -> BDQ.BoolExpr Int -> Maybe Written -> [Finding]
analyseBody labels order defs listed body written
  | not (sat [] body) =
      [ Finding
          { findingKind = "unsat"
          , findingSite = "body"
          , findingAtoms = atomLabels labels body
          , findingMessage =
              "the decision is TRUE for no assignment of its atoms: as drafting, a requirement nobody can meet."
                <> readsThroughConstants False labels body
          , findingWrittenAt = Nothing
          }
      ]
  | otherwise =
      topTautology
        <> map fst normal
        <> foldMap
             (\w -> map fst (walk AsWritten (satisfiable (nubOrd (w.wOrder <> order)) defs) w.wLabels w.wStarts deadLimbs [] "body" w.wBody))
             written
  where
    normal = walk Normalised sat labels Map.empty [] [] "body" body
    -- The limbs the normal form reports as dead branches, with their sites,
    -- for the walk over the rule as written not to report the same condition
    -- again ('walk'). Both drawings' atoms are in one atom space, so a limb
    -- can be compared with a written condition; the written walk's order is
    -- widened by the analysis's to cover both.
    deadLimbs = [(f.findingSite, e) | (f, e) <- normal, f.findingKind == "dead-branch"]
    sat = satisfiable order defs
    atomLabels labs e = [label labs u | u <- nubOrd (varsOf e)]
    label labs u = stripBackticks (Map.findWithDefault (Text.pack (show u)) u labs)

    -- A sentence naming each constant inside the reported condition whose
    -- value, read where it stands, is the finding's sign: FALSE for a finding
    -- that something can never hold, TRUE for one that something always holds.
    -- A call atom whose meaning ('cmDefs') is a literal ('constantMeaning') is
    -- read as the other literal where it stands under an odd number of NOTs,
    -- or in the scope of an IMPLIES ('polarities'): `NOT t`, with `t` the
    -- constant TRUE, can make a condition unsatisfiable, and `t` itself cannot.
    -- A constant of the other sign is not named. The constant is called one
    -- ("which is the constant FALSE") only when the rule called is itself
    -- listed as one, its body being the literal ('cmListed', 'literalBody'); a
    -- rule whose meaning comes out a literal only once read through has that
    -- meaning ("whose meaning is FALSE"). A finding through a constant is often
    -- what the drafter meant, and the sentence lets a reader see that the cause
    -- may be the constant and not this rule. The name keeps its backticks,
    -- which the atoms line drops, so that a name of several words reads as one
    -- inside the sentence (smucclaw/l4-ide#1095).
    -- Wording decided by Claude 2026-11-25, pending Meng's review.
    readsThroughConstants sign labs e =
      mconcat
        [ " It reads through " <> Map.findWithDefault (Text.pack (show v)) v labs
            <> (if Set.member v listed then ", which is the constant " else ", whose meaning is ")
            <> literalText b <> "."
        | v <- nubOrd (varsOf e)
        , Just meaning <- [Map.lookup v defs]
        , Just b <- [constantMeaning meaning]
        , any (\positive -> (b == positive) == sign) (Map.findWithDefault [] v (polarities e))
        ]
    -- Each variable, with whether it stands under an even number of negations
    -- (True) or an odd one (False) at each place it occurs. The scope of an
    -- IMPLIES counts as negated: @s IMPLIES r@ is @NOT s OR r@.
    polarities :: BDQ.BoolExpr Int -> Map Int [Bool]
    polarities = go True
      where
        go p = \case
          BDQ.BVar v -> Map.singleton v [p]
          BDQ.BNot x -> go (not p) x
          BDQ.BAnd xs -> Map.unionsWith (<>) (map (go p) xs)
          BDQ.BOr xs -> Map.unionsWith (<>) (map (go p) xs)
          BDQ.BImplies sc rq -> Map.unionWith (<>) (go (not p) sc) (go p rq)
          _ -> Map.empty
    constantMeaning = \case
      BDQ.BTrue -> Just True
      BDQ.BFalse -> Just False
      _ -> Nothing

    isSeam BDQ.BImplies{} = True
    isSeam _ = False

    topTautology
      | isSeam body = []
      | interesting body
      , not (sat [] (BDQ.BNot body)) =
          [ Finding
              { findingKind = "unreachable-outcome"
              , findingSite = "body"
              , findingAtoms = atomLabels labels body
              , findingMessage =
                  "the decision is TRUE for every assignment of its atoms, so its FALSE outcome is unreachable and the atoms it names do not affect the answer."
                    <> readsThroughConstants True labels body
              , findingWrittenAt = Nothing
              }
          ]
      | otherwise = []

    -- One walk over one drawing. Both walks stop at the same places: below an
    -- unsatisfiable conjunction, a dead limb or an unsatisfiable scope,
    -- everything is entailed (anything follows from a contradiction), so a walk
    -- that went on would report every condition there as redundant.
    --
    -- Each finding comes with the subterm it is about. The written walk is
    -- given the normal form's dead limbs ('deadLimbs'; none for the normal
    -- form's own walk).
    walk
      :: Pass
      -> ([BDQ.BoolExpr Int] -> BDQ.BoolExpr Int -> Bool)
      -> Map Int Text
      -> Map Text SrcPos
      -> [(Text, BDQ.BoolExpr Int)]
      -> [BDQ.BoolExpr Int]
      -> Text
      -> BDQ.BoolExpr Int
      -> [(Finding, BDQ.BoolExpr Int)]
    walk pass sat' labs starts dead = go []
      where
        normalised = pass == Normalised
        -- The sign is the finding's: False for one that says something can
        -- never hold, True for one that says something always holds
        -- ('readsThroughConstants').
        finding kind sign site e message =
          ( Finding
              { findingKind = kind
              , findingSite = site
              , findingAtoms = atomLabels labs e
              , findingMessage = message <> readsThroughConstants sign labs e
              , findingWrittenAt = Map.lookup site starts
              }
          , e
          )

        -- Is this subterm capable of being false at all?
        --
        -- Only CONTINGENT entailment is reported: this condition adds nothing
        -- GIVEN THE OTHERS. A condition that is true on its own (@y OR NOT y@)
        -- excludes nothing whatever it stands beside, which is a different
        -- defect, and is not looked for — see the note in 'propositionalBound'.
        -- Until the redundancy check read the rule as written, this gate was
        -- also what kept the clauses the normal form manufactures out of the
        -- report: @x XOR y@ distributes into a conjunction containing
        -- @x OR NOT x@.
        contingent e = sat' [] (BDQ.BNot e)

        -- Whether a site stands under an odd number of NOTs: its path is how it
        -- was reached, and @.not@ is the one step of it that negates. Under
        -- one, a conjunct is read the other way round, as an alternative, and
        -- an entailed conjunct can be an alternative that cannot hold where it
        -- sits, which the normal form reports as a dead branch:
        -- @a AND NOT (a AND b)@ is @a AND ((NOT a) OR (NOT b))@, whose @NOT a@
        -- is dead. So a conjunct under an odd number of NOTs whose negation is
        -- a limb the normal form reports dead ('deadLimbs') is not reported
        -- again here, if that limb is in the same part of the rule (its scope,
        -- its requirement, or the whole of a rule with no seam: 'seamPart';
        -- an IMPLIES inside the rule is drawn as an OR, and is no seam)
        -- and has no atom that the NOT the conjunct stands under does not
        -- have. A limb that means the same but is in the other part, or
        -- names other atoms (a call where the NOT writes out what it means),
        -- is a different condition, and the conjunct is reported. Within those
        -- bounds the match is still by meaning, not by place (decided by
        -- Claude 2026-11-25, pending Meng's review). Any other entailed
        -- conjunct is reported: one entailed only with its siblings' help is,
        -- read the other way round, an alternative the others cover
        -- (@NOT (a AND (a OR b))@ is
        -- @(NOT a) OR ((NOT a) AND (NOT b))@), and inside an OR the normal
        -- form distributes the NOT away and reports no dead branch for it.
        -- An alternative the others cover is looked for under a NOT as
        -- anywhere (decided by Claude 2026-11-25, pending Meng's review).
        underOddNot site = odd (Text.count ".not" site)
        reportedDead nv site ei =
          any
            ( \(ds, d) ->
                seamPart ds == seamPart site
                  && all (`elem` nv) (varsOf d)
                  && not (sat' [d] ei)
                  && not (sat' [BDQ.BNot d] (BDQ.BNot ei))
            )
            dead
        -- The steps of a site up to its first that is not a seam's.
        seamPart = takeWhile (`elem` ["body", "scope", "requirement"]) . Text.splitOn "."

        -- The first argument is the atoms of the NOT the subterm stands
        -- under, the nearest one; none outside every NOT.
        go :: [Int] -> [BDQ.BoolExpr Int] -> Text -> BDQ.BoolExpr Int -> [(Finding, BDQ.BoolExpr Int)]
        go nv ctx site = \case
          e@(BDQ.BAnd es)
            | not (sat' ctx e) ->
                -- Stop here. Everything below an unsatisfiable conjunction is
                -- vacuously dead, and saying so once per descendant is noise.
                [ finding "unsat" False site e
                    "these conditions cannot all hold at once in the context that reaches them — a double bind."
                | normalised
                ]
            | otherwise ->
                concat
                  [ entailed <> go nv ctx' arm ei
                  | (i, ei) <- zip [(0 :: Int) ..] es
                  , let arm = site <> ".and[" <> Text.pack (show i) <> "]"
                  , let ctx' = ctx <> [ej | (j, ej) <- zip [(0 :: Int) ..] es, j /= i]
                  , let entailed =
                          [ finding "vacuous-guard" True arm ei
                              "this condition is already entailed by the ones it is conjoined with, so it excludes nothing."
                          | not normalised
                            -- Only a node drawn from source has a place in it.
                            -- The ones without are a guarded chain's copies
                            -- ('Written'): the negations of earlier guards that
                            -- each row carries, which nobody wrote, and the
                            -- guard itself. Mutually exclusive rows make those
                            -- negations entailed by the row's own guard, in a
                            -- rule with nothing redundant in it. Skipping every
                            -- copy also skips a redundancy written inside a
                            -- guard (decided by Claude 2026-11-25, pending
                            -- Meng's review).
                          , Map.member arm starts
                          , not (underOddNot site && reportedDead nv site ei)
                          , interesting ei
                          , contingent ei
                          , not (sat' ctx' (BDQ.BNot ei))
                          ]
                  ]
          BDQ.BOr es ->
            concat
              [ covered <>
                if interesting ei && not (sat' ctx ei)
                  then
                    [ finding "dead-branch" False arm ei
                        "this limb cannot hold in the context that reaches it; the rule reads identically with it deleted."
                    | normalised
                    ]
                  -- Into the alternative with the context of the OR, and
                  -- not the negations of the alternatives beside it, so a
                  -- condition that only they make redundant, such as the @a@
                  -- of @(a AND b) OR ((NOT a) AND b)@, is not reported. That
                  -- is a limit, stated in the help and the doc page, not a
                  -- choice.
                  else go nv ctx arm ei
              | (i, ei) <- zip [(0 :: Int) ..] es
              , let arm = site <> ".or[" <> Text.pack (show i) <> "]"
              , let others = [ej | (j, ej) <- zip [(0 :: Int) ..] es, j /= i]
                -- The dual of a redundant condition: an alternative every case
                -- of which the others already let through, so the rule reads
                -- the same with it deleted. It is reported as a vacuous guard,
                -- the kind the normal form's clauses used to report it under,
                -- with a message of its own (decided by Claude 2026-11-25,
                -- pending Meng's review). A dead limb is covered vacuously, and
                -- is not reported here: it is left to the other pass, whose
                -- dead branch is a literal of the normal form's clauses. That
                -- pass reports the limb only where a literal of it survives in
                -- a clause and is dead there, so an alternative that can never
                -- hold, such as the @a AND c AND (NOT a)@ of
                -- @b OR (a AND c AND (NOT a))@, goes unreported. That is a
                -- limit, stated in the help and the doc page, not a choice.
                -- Where the context already entails the whole disjunction,
                -- every alternative is covered: that is the condition the
                -- disjunction makes being redundant, or true on its own, and
                -- is not said again here.
              , let covered =
                      [ finding "vacuous-guard" False arm ei
                          "this alternative is already covered by the ones it is joined with, so it admits nothing new."
                      | not normalised
                      , Map.member arm starts
                      , interesting ei
                      , not (null others)
                      , sat' ctx ei
                      , sat' ctx (BDQ.BNot (BDQ.BOr es))
                      , not (sat' (ctx <> [ei]) (BDQ.BNot (BDQ.BOr others)))
                      ]
              ]
          BDQ.BImplies scope req
            | not (sat' ctx scope) ->
                [ finding "vacuous-guard" False (site <> ".scope") scope
                    "the scope of this rule is unsatisfiable, so it reaches nobody and its requirement is never tested. Note the decision still evaluates TRUE — vacuously."
                | normalised
                ]
            | otherwise ->
                concat
                  [ [ finding "unreachable-outcome" False site (BDQ.BAnd [scope, req])
                        "no case both falls within the scope and meets the requirement: whoever this rule reaches is necessarily in breach."
                    | normalised
                    , interesting req
                    , not (sat' (ctx <> [scope]) req)
                    ]
                    -- Built over the implication, which this finding says
                    -- always holds, so that a constant in the scope is read
                    -- the other way round, as there ('readsThroughConstants').
                  , [ finding "unreachable-outcome" True site (BDQ.BImplies scope req)
                        "the scope already entails the requirement, so nothing within scope can breach it and the requirement adds nothing."
                    | normalised
                    , interesting req
                    , contingent req
                    , not (sat' (ctx <> [scope]) (BDQ.BNot req))
                    ]
                  , go nv ctx (site <> ".scope") scope
                  , go nv (ctx <> [scope]) (site <> ".requirement") req
                  ]
          -- Not descended into for the normal form's findings: under a negation
          -- the polarity flips, and "dead branch" would come to mean its own
          -- opposite. Reporting that under the same word would be worse than
          -- not reporting it. A redundant condition or a covered alternative is
          -- looked for under it, in the same context: deleting one leaves what
          -- the negation applies to unchanged, so it leaves the negation
          -- unchanged too (decided by Claude 2026-11-25, pending Meng's review).
          BDQ.BNot e
            | normalised -> []
            | otherwise -> go (nubOrd (varsOf e)) ctx (site <> ".not") e
          BDQ.BVar _ -> []
          BDQ.BRefuse _ -> []
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
          , -- Analysed decisions whose body is the literal TRUE or FALSE.
            "constants" .= length [() | a <- analysed, isJust a.anConstant]
          ]
    ]
  where
    analysed = [a | r <- reports, Right a <- [r.drResult]]
    allFindings = concatMap reportFindings reports

boundOneLine :: Text
boundOneLine =
  "propositional only: every leaf is an opaque atom, so no numeric, interval, date or \
  \string contradiction is visible. Findings are sound, except for a condition in a local \
  \definition used more than once; silence is not a consistency proof."

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
            <> ( case a.anConstant of
                   Just b -> "a constant: its body is the literal " <> literalText b <> ", so there is nothing to check"
                   Nothing
                     | null a.anFindings -> "no propositional findings"
                     | otherwise -> Text.pack (show (length a.anFindings)) <> " finding(s)"
               )
        ]
          <> [ "    call left as a leaf: " <> why | why <- r.drUnfolding.leftOpaque ]
          <> concatMap finding a.anFindings

    finding f =
      [ "    [" <> f.findingKind <> "] at " <> f.findingSite
          <> maybe "" (\p -> ", written at " <> prettySrcPos p) f.findingWrittenAt
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
        <> ( if constants == 0
              then ""
              else
                " "
                  <> Text.pack (show constants)
                  <> " of the analysed decision(s) are constants: a body that is\n  \
                     \the literal TRUE or FALSE, with nothing in it to check."
           )
    opaque = sum [length r.drUnfolding.leftOpaque | r <- reports]
    constants = length [() | a <- analysed, isJust a.anConstant]

-- | Strip the backticks L4 uses to quote identifiers containing spaces. The
-- wizard's JSON does the same thing for the same reason.
stripBackticks :: Text -> Text
stripBackticks t = fromMaybe t (Text.stripPrefix "`" t >>= Text.stripSuffix "`")
