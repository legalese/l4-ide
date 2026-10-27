{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | @REFUSE "reason"@: the model declines to answer, with the author's reason.
--
-- These pin the language half of it: the keyword, the grammar (the message is
-- a string literal), the type rule (a refusal has any type), and what the
-- evaluator does with one (it stops at the directive that asked, which reports
-- the reason, and nothing in between can observe it). Demand order is part of
-- the meaning, so it is pinned in both directions: AND, OR and IF are lazy and
-- left to right, and a refusal that is never demanded is never raised.
module RefuseSpec (spec) where

import Test.Hspec

import Data.Char (isDigit)
import Data.Foldable (for_)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

import Base (Uri (..), toNormalizedUri)
import L4.API (l4Eval, l4EvalDirective, l4VisualizeByName)
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.DirectiveFilter (filterIdeDirectives)
import qualified L4.EvaluateLazy as EL
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Export.Document (buildDocument, defaultExportConfig)
import qualified L4.Lexer as Lexer
import L4.Lint.AndOrDepth (checkAndOrDepth)
import L4.Parser (execProgramParser)
import L4.Print (prettyLayout)
import qualified L4.StateGraph as SG
import L4.TracePolicy (TraceDestination (..), TraceFormat (..), TracePolicy, apiDefaultPolicy, traceAll)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..), Severity (..))

-- | The front end's verdict: the parse errors, or the type checker's errors,
-- as text; or the checked module.
frontEnd :: Text -> Either Text TypeCheckWithDepsResult
frontEnd src = case checkWithImports emptyVFS src of
  Left errs -> Left (Text.unlines errs)
  Right r -> case filter ((== SError) . TC.severity) r.tcdErrors of
    [] -> Right r
    errs -> Left (Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))

-- | Every directive's result, printed the way the golden suite prints it.
evalAll :: Text -> IO [Text]
evalAll = evalAllWith apiDefaultPolicy

-- | Every directive's result under the given trace policy, printed the way the
-- golden suite prints it, with its trace below it when the policy keeps one.
evalAllWith :: TracePolicy -> Text -> IO [Text]
evalAllWith policy = evalAllConfigured policy id

-- | Every directive's result under the given trace policy, evaluated under a
-- configuration the caller adjusts.
evalAllConfigured :: TracePolicy -> (EL.EvalConfig -> EL.EvalConfig) -> Text -> IO [Text]
evalAllConfigured policy adjust src = case frontEnd src of
  Left msg -> do
    expectationFailure ("the module did not check:\n" <> Text.unpack msg)
    pure []
  Right r -> do
    cfg <- EL.resolveEvalConfigWithSafeMode Nothing policy True
    (_, results) <- EL.execEvalModuleWithEnv (adjust cfg) r.tcdEntityInfo mempty r.tcdModule
    pure (map EL.prettyEvalDirectiveResult results)

-- | The last line of a directive's printed result: the root of its trace,
-- when it has one.
rootOf :: Text -> Text
rootOf out = Text.strip (last ("" : Text.lines (Text.strip out)))

-- | Two rules that answer a list of n numbers and then refuse: with the
-- refusal as one more element, and as the rest of the list.
deepRefusals :: [Text]
deepRefusals =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A LIST OF NUMBER"
  , "`refusal in the list` n MEANS"
  , "  IF n EQUALS 0 THEN LIST (REFUSE \"deep\") ELSE n FOLLOWED BY `refusal in the list` (n MINUS 1)"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A LIST OF NUMBER"
  , "`refusal as the rest` n MEANS"
  , "  IF n EQUALS 0 THEN REFUSE \"deep\" ELSE n FOLLOWED BY `refusal as the rest` (n MINUS 1)"
  , ""
  ]

-- | Whether a directive's result is a refusal.
refuses :: Text -> Bool
refuses = Text.isInfixOf "The model refuses to answer:"

-- | The result of a module's one directive.
evalOne :: Text -> IO Text
evalOne src = do
  results <- evalAll src
  case results of
    [one] -> pure one
    _ -> do
      expectationFailure ("expected exactly one directive result, got " <> show (length results) <> ": " <> show results)
      pure ""

-- | The output of a refusal: the outcome, the author's reason, and none of
-- the words an error or a loop would bring with it.
refusesWith :: Text -> Text -> Expectation
refusesWith reason out = do
  out `shouldSatisfy` Text.isInfixOf "The model refuses to answer:"
  out `shouldSatisfy` Text.isInfixOf reason
  for_ ["Internal error", "Please report", "Infinite loop", "assertion"] $ \word ->
    out `shouldNotSatisfy` Text.isInfixOf word

-- | The state graph of a module whose one rule, @r@, is the given obligation,
-- with the given top-level definitions beside the rule.
withStateGraphBeside :: [Text] -> [Text] -> (SG.StateGraph -> Expectation) -> Expectation
withStateGraphBeside defs body k = case frontEnd src of
  Left msg -> expectationFailure ("the module did not check:\n" <> Text.unpack msg)
  Right r -> case SG.extractStateGraphs r.tcdModule of
    [g] -> k g
    gs -> expectationFailure ("expected one state graph, got " <> show (length gs))
 where
  src = Text.unlines $
    [ "DECLARE Person IS ONE OF Seller, Buyer"
    , "DECLARE Action IS ONE OF pay"
    , ""
    ]
    <> defs
    <> [ ""
       , "GIVETH DEONTIC Person Action"
       , "r MEANS"
       ]
    <> map ("  " <>) body

-- | The two rules draw one state graph, compared as the DOT text a reader is
-- shown, and no state is named after the refusal. Both modules hold the same
-- named refusal, @`not modelled`@, beside the rule, so they differ only in
-- the rule: the first writes the refusal, the second names it.
sameStateGraph :: [Text] -> [Text] -> Expectation
sameStateGraph written named =
  withStateGraphBeside [notModelled] written $ \g1 ->
    withStateGraphBeside [notModelled] named $ \g2 -> do
      dot g1 `shouldBe` dot g2
      [s.stateName | s <- g1.sgStates, "not modelled" `Text.isInfixOf` s.stateName] `shouldBe` []
 where
  notModelled = "`not modelled` MEANS REFUSE \"not modelled\""
  dot = SG.stateGraphToDot SG.defaultStateGraphOptions

-- | A module whose one rule, @r@, has the given type and body, and one
-- directive that asks for it.
ruleOfType :: Text -> Text -> Text
ruleOfType ty body = Text.unlines
  [ "DECLARE Person HAS"
  , "  name IS A STRING"
  , "  age IS A NUMBER"
  , ""
  , "GIVETH " <> ty
  , "r MEANS " <> body
  , ""
  , "#EVAL r"
  ]

spec :: Spec
spec = describe "REFUSE" $ do
  describe "the keyword" $ do
    it "is in the lexer's keyword table" $
      Map.member "REFUSE" Lexer.keywords `shouldBe` True

    it "is reserved: a name spelled REFUSE does not parse unquoted" $
      case checkWithImports emptyVFS "GIVETH A NUMBER\nREFUSE MEANS 1\n" of
        Left _ -> pure ()
        Right _ -> expectationFailure "a definition named REFUSE parsed without backticks"

    it "is still usable as a name in backticks (a control for the case above)" $ do
      out <- evalOne "GIVETH A NUMBER\n`REFUSE` MEANS 1\n\n#EVAL `REFUSE`\n"
      Text.strip out `shouldBe` "1"

    it "REFUSED, the word of #ASSERT REFUSED, is in the lexer's keyword table too" $
      Map.member "REFUSED" Lexer.keywords `shouldBe` True

  describe "the grammar and the type rule" $ do
    it "rejects a computed message at the parser, naming what it expects" $
      case checkWithImports emptyVFS "GIVETH A NUMBER\nr MEANS REFUSE (1 PLUS 1)\n" of
        Left errs -> Text.unlines errs `shouldSatisfy` Text.isInfixOf "expecting String Literal or space token"
        Right _ -> expectationFailure "REFUSE with a computed message parsed"

    it "rejects a message that is a literal but not a STRING, at the type checker" $
      case frontEnd "GIVETH A NUMBER\nr MEANS REFUSE 42\n" of
        Left msg -> msg `shouldSatisfy` Text.isInfixOf "The message of a REFUSE is expected to be a string literal"
        Right _ -> expectationFailure "REFUSE 42 type-checked"

    for_
      [ ("a NUMBER", "A NUMBER")
      , ("a BOOLEAN", "A BOOLEAN")
      , ("a STRING", "A STRING")
      , ("a LIST", "A LIST OF NUMBER")
      , ("a MAYBE", "A MAYBE NUMBER")
      , ("a record", "A Person")
      ] $ \(what, ty) ->
      it ("has any type: here " <> what) $ do
        out <- evalOne (ruleOfType ty "REFUSE \"not modelled\"")
        refusesWith "not modelled" out

    it "has any type: one polymorphic refusal serves a NUMBER and a BOOLEAN" $ do
      outs <- evalAll $ Text.unlines
        [ "GIVEN a IS A TYPE"
        , "GIVETH AN a"
        , "`not written yet` MEANS REFUSE \"not written yet\""
        , ""
        , "GIVETH A NUMBER"
        , "amount MEANS 1 PLUS `not written yet`"
        , ""
        , "GIVETH A BOOLEAN"
        , "eligible MEANS TRUE AND `not written yet`"
        , ""
        , "#EVAL amount"
        , "#EVAL eligible"
        ]
      length outs `shouldBe` 2
      for_ outs (refusesWith "not written yet")

    it "has any type: an IF branch and a CONSIDER arm" $ do
      branch <- evalOne (ruleOfType "A NUMBER" "IF TRUE THEN REFUSE \"branch\" ELSE 1")
      refusesWith "branch" branch
      arm <- evalOne $ Text.unlines
        [ "GIVETH A NUMBER"
        , "r MEANS"
        , "  CONSIDER JUST 1"
        , "    WHEN NOTHING THEN 0"
        , "    WHEN JUST n THEN REFUSE \"arm\""
        , ""
        , "#EVAL r"
        ]
      refusesWith "arm" arm

    it "is accepted as a function's argument" $ do
      out <- evalOne $ Text.unlines
        [ "GIVEN x IS A NUMBER"
        , "GIVETH A NUMBER"
        , "double x MEANS x TIMES 2"
        , ""
        , "#EVAL double OF (REFUSE \"argument\")"
        ]
      refusesWith "argument" out

    -- The type a REFUSE takes is a fresh type variable named after the
    -- construct, as the fresh types of IF and CONSIDER are named after
    -- theirs, so #CHECK prints "refused" and a number.
    it "takes a fresh type named after the construct, which #CHECK prints" $
      case checkWithImports emptyVFS "#CHECK REFUSE \"x\"\n" of
        Left errs -> expectationFailure ("the module did not parse:\n" <> Text.unpack (Text.unlines errs))
        Right r -> do
          let checked = [ prettyLayout t | MkCheckErrorWithContext (CheckInfo t _) _ <- r.tcdErrors ]
              freshRefused t = case Text.stripPrefix "refused" (Text.strip t) of
                Just n -> not (Text.null n) && Text.all isDigit n
                Nothing -> False
          checked `shouldSatisfy` (not . null)
          checked `shouldSatisfy` all freshRefused

  describe "evaluation" $ do
    it "reports the author's reason at the directive that asked" $ do
      out <- evalOne "#EVAL REFUSE \"a reason written in place\"\n"
      refusesWith "a reason written in place" out

    -- The reason is printed as written, after the indent: an empty one leaves
    -- a line that holds only the indent, and a blank or padded one keeps its
    -- own spaces. The lines are compared exactly, so a printer that drops the
    -- empty line or trims the reason is caught.
    it "accepts an empty, a blank or a padded message, and prints it as written under the heading" $ do
      outs <- evalAll "#EVAL REFUSE \"\"\n#EVAL REFUSE \"   \"\n#EVAL REFUSE \"  padded  \"\n"
      map Text.lines outs `shouldBe`
        [ ["The model refuses to answer:", "  "]
        , ["The model refuses to answer:", "     "]
        , ["The model refuses to answer:", "    padded  "]
        ]

    it "indents every line of a reason that runs over several lines" $ do
      out <- evalOne "#EVAL REFUSE \"line one\\nline two\"\n"
      Text.lines out `shouldBe` ["The model refuses to answer:", "  line one", "  line two"]

    it "is not observed by a CONSIDER, a LET or a WHERE on the way out" $ do
      consider <- evalOne $ Text.unlines
        [ "GIVETH A MAYBE NUMBER"
        , "m MEANS REFUSE \"maybe\""
        , ""
        , "GIVETH A NUMBER"
        , "r MEANS"
        , "  CONSIDER m"
        , "    WHEN NOTHING THEN 0"
        , "    WHEN JUST n THEN n"
        , ""
        , "#EVAL r"
        ]
      refusesWith "maybe" consider
      letIn <- evalOne (ruleOfType "A NUMBER" "LET x MEANS REFUSE \"let\" IN x PLUS 1")
      refusesWith "let" letIn
      whereBound <- evalOne $ Text.unlines
        [ "GIVETH A NUMBER"
        , "r MEANS"
        , "  y PLUS 1"
        , "  WHERE"
        , "    y MEANS REFUSE \"where\""
        , ""
        , "#EVAL r"
        ]
      refusesWith "where" whereBound

    describe "demand order: lazy, left to right" $ do
      for_
        [ ("FALSE AND <refusal> is FALSE", "FALSE AND REFUSE \"r\"", "FALSE")
        , ("TRUE OR <refusal> is TRUE", "TRUE OR REFUSE \"r\"", "TRUE")
        , ("an IF does not reach the branch it does not take", "IF FALSE THEN REFUSE \"r\" ELSE 1", "1")
        ] $ \(name, expr, value) ->
        it name $ do
          out <- evalOne ("#EVAL " <> expr <> "\n")
          Text.strip out `shouldBe` value
      for_
        [ ("<refusal> AND FALSE refuses", "REFUSE \"left\" AND FALSE", "left")
        , ("<refusal> OR TRUE refuses", "REFUSE \"left\" OR TRUE", "left")
        , ("TRUE AND <refusal> refuses", "TRUE AND REFUSE \"right\"", "right")
        , ("FALSE OR <refusal> refuses", "FALSE OR REFUSE \"right\"", "right")
        , ("NOT <refusal> refuses", "NOT (REFUSE \"negated\")", "negated")
        , ("an IF whose condition refuses refuses", "IF REFUSE \"condition\" THEN 1 ELSE 2", "condition")
        ] $ \(name, expr, reason) ->
        it name $ do
          out <- evalOne ("#EVAL " <> expr <> "\n")
          refusesWith reason out

    it "refuses every time a named refusal is reached, not only the first" $ do
      outs <- evalAll $ Text.unlines
        [ "GIVETH A NUMBER"
        , "`not modelled` MEANS REFUSE \"twice\""
        , ""
        , "#EVAL `not modelled`"
        , "#EVAL `not modelled` PLUS 1"
        , "#EVAL `not modelled` TIMES 2"
        ]
      length outs `shouldBe` 3
      for_ outs (refusesWith "twice")

    -- An #ASSERT whose expression refuses is decided neither way, and it is
    -- not an error either: it reports the refusal under "assertion refused:",
    -- in either polarity. 'refusesWith' rejects the word "assertion", so this
    -- case has its own matcher.
    it "reports an #ASSERT that refuses as refused, in either polarity, with the reason" $ do
      outs <- evalAll $ Text.unlines
        [ "GIVETH A BOOLEAN"
        , "`not modelled` MEANS REFUSE \"not modelled\""
        , ""
        , "#ASSERT `not modelled`"
        , "#ASSERT NOT `not modelled`"
        ]
      length outs `shouldBe` 2
      for_ outs $ \out -> do
        out `shouldSatisfy` Text.isPrefixOf "assertion refused:"
        out `shouldSatisfy` Text.isInfixOf "The model refuses to answer:"
        out `shouldSatisfy` Text.isInfixOf "not modelled"
        for_ ["assertion satisfied", "assertion failed", "could not be evaluated"] $ \verdict ->
          out `shouldNotSatisfy` Text.isInfixOf verdict

    -- A directive reads its answer to a depth of 200 (the evaluator's
    -- 'maximumStackSize'), each cell of a list one level below the one before
    -- it. It evaluates the first 201 elements of a list answer, and whether the
    -- list goes on after them, and prints the first 200. So a refusal far down
    -- a list answer is not reached, exactly as a division by zero there is
    -- not, and the printed answer ends in "...". A directive that demands the
    -- whole list, here by totalling it, refuses.
    it "is not reached past the depth to which a directive prints its answer, as a division by zero there is not" $ do
      outs <- evalAll $ Text.unlines
        [ "GIVEN n IS A NUMBER, final IS A NUMBER"
        , "GIVETH A LIST OF NUMBER"
        , "countdown n final MEANS"
        , "  IF n EQUALS 0 THEN LIST final ELSE n FOLLOWED BY (countdown OF (n MINUS 1), final)"
        , ""
        , "GIVEN xs IS A LIST OF NUMBER"
        , "GIVETH A NUMBER"
        , "total xs MEANS"
        , "  CONSIDER xs"
        , "    WHEN EMPTY THEN 0"
        , "    WHEN x FOLLOWED BY rest THEN x PLUS total rest"
        , ""
        , "#EVAL countdown OF 3, REFUSE \"the last entry\""
        , "#EVAL countdown OF 205, REFUSE \"the last entry\""
        , "#EVAL total (countdown OF 205, REFUSE \"the last entry\")"
        , "#EVAL countdown OF 205, 1 DIVIDED BY 0"
        ]
      case outs of
        [short, long, totalled, divided] -> do
          refusesWith "the last entry" short
          refusesWith "the last entry" totalled
          long `shouldNotSatisfy` Text.isInfixOf "The model refuses to answer:"
          Text.strip long `shouldSatisfy` Text.isSuffixOf ", ..."
          long `shouldBe` divided
        _ -> expectationFailure ("expected four directive results, got " <> show (length outs))

    -- The limit itself: a refusal that is the 201st element of a list answer
    -- is reached and the 202nd is not, and a refusal that is the rest of the
    -- list after 201 numbers is reached and after 202 it is not.
    it "is reached at the last depth a directive reads, and not one level below it" $ do
      outs <- evalAll $ Text.unlines $ deepRefusals <>
        [ "#EVAL `refusal in the list` 200"
        , "#EVAL `refusal in the list` 201"
        , "#EVAL `refusal as the rest` 201"
        , "#EVAL `refusal as the rest` 202"
        ]
      map refuses outs `shouldBe` [True, False, True, False]

    -- `l4 batch` and the service's wrapper ask for an answer as
    -- `JUST (f args)`, and say so with 'EL.answerInJust'. That JUST is the
    -- caller's, not the rule's, so the answer inside it is read as deep as a
    -- bare answer is. A JUST inside the caller's is the rule's own and takes
    -- a level, so the last two calls reach a refusal one element sooner.
    -- Without the setting the caller's JUST is part of the answer and takes a
    -- level too, which the second half pins. A traced call is read the same
    -- as an untraced one, so each call is asked both ways, and the verdict is
    -- read from the answer above the trace.
    it "is reached inside a caller's JUST at the depth a bare answer is, when the caller says the answer is wrapped" $ do
      let calls =
            [ "JUST (`refusal in the list` 199)"
            , "JUST (`refusal in the list` 200)"
            , "JUST (`refusal in the list` 201)"
            , "JUST (`refusal as the rest` 200)"
            , "JUST (`refusal as the rest` 201)"
            , "JUST (`refusal as the rest` 202)"
            , "JUST (JUST (`refusal in the list` 199))"
            , "JUST (JUST (`refusal in the list` 200))"
            ]
          src = Text.unlines $ deepRefusals
            <> map ("#EVAL " <>) calls
            <> map ("#EVALTRACE " <>) calls
          answerRefuses = refuses . fst . Text.breakOn "─────"
      wrapped <- evalAllConfigured apiDefaultPolicy (\cfg -> cfg { EL.answerInJust = True }) src
      map (Text.isInfixOf "─────") wrapped `shouldBe` (map (const False) calls <> map (const True) calls)
      map answerRefuses wrapped `shouldBe` concat (replicate 2 [True, True, False, True, True, False, True, False])
      plain <- evalAll src
      map answerRefuses plain `shouldBe` concat (replicate 2 [True, False, False, True, False, False, False, False])

    -- The setting reads past a JUST and nothing else: an answer whose head is
    -- another constructor of one field is read as it is without the setting,
    -- its constructor taking a level, and each constructor inside it takes
    -- one more, so a list in a box in a crate is reached two elements sooner.
    it "is reached one element sooner inside any other constructor, when the caller says the answer is wrapped" $ do
      let src = Text.unlines $ deepRefusals <>
            [ "DECLARE Box IS ONE OF box HAS contents IS A LIST OF NUMBER"
            , "DECLARE Crate IS ONE OF crate HAS held IS A Box"
            , "#EVAL box (`refusal in the list` 199)"
            , "#EVAL box (`refusal in the list` 200)"
            , "#EVAL crate (box (`refusal in the list` 198))"
            , "#EVAL crate (box (`refusal in the list` 199))"
            ]
      wrapped <- evalAllConfigured apiDefaultPolicy (\cfg -> cfg { EL.answerInJust = True }) src
      map refuses wrapped `shouldBe` [True, False, True, False]
      plain <- evalAll src
      map refuses plain `shouldBe` [True, False, True, False]

    it "is named in an evaluation trace, with its reason" $ do
      out <- evalOne "#EVALTRACE 1 PLUS REFUSE \"traced\"\n"
      out `shouldSatisfy` Text.isInfixOf "↯ refused: traced"

    -- The root of a trace carries the directive's outcome. The trace records
    -- the reduction to weak head normal form, and a refusal inside a JUST or
    -- at the end of a list is met only after it, while the answer is read in
    -- full; the root names it all the same, and an error met there likewise.
    -- The root's line is the trace's last.
    it "is named at the root of an evaluation trace when it is met below the answer's head" $ do
      outs <- evalAll $ Text.unlines
        [ "GIVETH A NUMBER"
        , "`deep` MEANS REFUSE \"deep\""
        , ""
        , "GIVETH A NUMBER"
        , "`broken` MEANS 1 DIVIDED BY 0"
        , ""
        , "#EVALTRACE JUST `deep`"
        , "#EVALTRACE LIST 1, 2, REFUSE \"deep\""
        , "#EVALTRACE JUST `broken`"
        ]
      case outs of
        [inJust, inList, errored] -> do
          for_ [inJust, inList] $ \out -> do
            refusesWith "deep" (fst (Text.breakOn "─────" out))
            rootOf out `shouldSatisfy` Text.isSuffixOf "↯ refused: deep"
          rootOf errored `shouldSatisfy` Text.isInfixOf "↯ "
          rootOf errored `shouldNotSatisfy` Text.isInfixOf "refused"
          rootOf errored `shouldNotSatisfy` Text.isInfixOf "JUST"
        _ -> expectationFailure ("expected three directive results, got " <> show (length outs))

    -- An assertion's trace, kept when the policy traces every directive, has
    -- the same root: an #ASSERT REFUSED that holds because the answer refuses
    -- below its head has that refusal at the root of its trace.
    it "is named at the root of an assertion's trace when it is met below the answer's head" $ do
      outs <- evalAllWith (traceAll TextTrace ApiResponse defaultGraphVizOptions) $ Text.unlines
        [ "GIVETH A NUMBER"
        , "`deep` MEANS REFUSE \"deep\""
        , ""
        , "#ASSERT REFUSED JUST `deep`"
        , "#ASSERT REFUSED LIST 1, 2, REFUSE \"deep\""
        ]
      case outs of
        [inJust, inList] -> for_ [inJust, inList] $ \out -> do
          Text.strip (fst (Text.breakOn "─────" out)) `shouldBe` "assertion satisfied"
          rootOf out `shouldSatisfy` Text.isSuffixOf "↯ refused: deep"
        _ -> expectationFailure ("expected two directive results, got " <> show (length outs))

  -- #ASSERT REFUSED e [BECAUSE "reason"] holds when e refuses and, when a
  -- reason is named, when e refuses with exactly that reason. Otherwise it
  -- fails and says why; and an e that raises is reported as a plain #ASSERT
  -- reports one, because an error is not a refusal.
  describe "#ASSERT REFUSED" $ do
    let beside directives = Text.unlines $
          [ "GIVETH A NUMBER"
          , "`not modelled` MEANS REFUSE \"not modelled\""
          , ""
          ] <> directives
        outcomes directives = map Text.strip <$> evalAll (beside directives)
        notDecided out = do
          out `shouldSatisfy` Text.isPrefixOf "assertion could not be evaluated:"
          for_ ["assertion satisfied", "assertion failed", "assertion refused", "The model refuses"] $ \word ->
            out `shouldNotSatisfy` Text.isInfixOf word
        -- The column of the parse error's caret: the megaparsec excerpt puts
        -- one space after the gutter's bar, then one per column before it.
        caretColumn msg = case [ l | l <- Text.lines msg, "|" `Text.isInfixOf` l, "^" `Text.isInfixOf` l ] of
          l : _ -> Just (Text.length (fst (Text.breakOn "^" l)) - Text.length (fst (Text.breakOn "|" l)) - 1)
          [] -> Nothing

    it "holds for a refusal, with no reason named and with its own reason named" $ do
      outs <- outcomes
        [ "#ASSERT REFUSED `not modelled`"
        , "#ASSERT REFUSED `not modelled` BECAUSE \"not modelled\""
        ]
      outs `shouldBe` ["assertion satisfied", "assertion satisfied"]

    it "fails, saying why, for an expression that answers, a refusal it never demands included" $ do
      outs <- outcomes
        [ "#ASSERT REFUSED 1 PLUS 1"
        , "#ASSERT REFUSED FALSE AND REFUSE \"never demanded\""
        ]
      outs `shouldBe` replicate 2 "assertion failed: expected a refusal, but the expression produced a value"

    it "fails, naming both reasons, for a refusal with another reason" $ do
      outs <- outcomes [ "#ASSERT REFUSED `not modelled` BECAUSE \"some other reason\"" ]
      outs `shouldBe` ["assertion failed: expected the refusal \"some other reason\", got \"not modelled\""]

    it "compares the reasons exactly, so one trailing space makes another reason" $ do
      outs <- outcomes [ "#ASSERT REFUSED `not modelled` BECAUSE \"not modelled \"" ]
      outs `shouldBe` ["assertion failed: expected the refusal \"not modelled \", got \"not modelled\""]

    -- Each reason is quoted as it is written, a quotation mark or a letter
    -- outside ASCII included, and nothing in it is escaped.
    it "names both reasons as they are written, with no escaping" $ do
      outs <- map Text.strip <$> evalAll (Text.unlines
        [ "GIVETH A NUMBER"
        , "`not modelled` MEANS REFUSE \"café, \\\"quoted\\\"\""
        , ""
        , "#ASSERT REFUSED `not modelled` BECAUSE \"naïve\""
        ])
      outs `shouldBe` ["assertion failed: expected the refusal \"naïve\", got \"café, \"quoted\"\""]

    it "is not satisfied by an error, with or without a reason named" $ do
      outs <- outcomes
        [ "#ASSERT REFUSED (1 DIVIDED BY 0)"
        , "#ASSERT REFUSED (1 DIVIDED BY 0) BECAUSE \"not modelled\""
        ]
      length outs `shouldBe` 2
      for_ outs notDecided

    it "is not satisfied by an assumed term, which is undecided, as a plain #ASSERT reports one" $ do
      outs <- evalAll "ASSUME `the rate` IS A NUMBER\n\n#ASSERT REFUSED `the rate`\n"
      length outs `shouldBe` 1
      for_ (map Text.strip outs) notDecided

    it "takes an expression of any type, because a refusal is at any type" $ do
      outs <- outcomes
        [ "#ASSERT REFUSED (`not modelled` EQUALS 1)"
        , "#ASSERT REFUSED (LIST 2, `not modelled`)"
        , "#ASSERT REFUSED \"an answer\""
        ]
      outs `shouldBe`
        [ "assertion satisfied"
        , "assertion satisfied"
        , "assertion failed: expected a refusal, but the expression produced a value"
        ]

    -- A directive reads a value only so deep. An #ASSERT REFUSED of a value
    -- that goes deeper cannot say whether it refuses, so it is undecided,
    -- whatever lies past that depth: a refusal, a division by zero, or more
    -- numbers. A refusal within the depth satisfies it, and a value that ends
    -- within the depth fails it.
    it "is undecided for a value that goes deeper than a directive reads, whatever lies past that depth" $ do
      outs <- map Text.strip <$> evalAll (Text.unlines $ deepRefusals <>
        [ "GIVEN n IS A NUMBER"
        , "GIVETH A LIST OF NUMBER"
        , "`division in the list` n MEANS"
        , "  IF n EQUALS 0 THEN LIST (1 DIVIDED BY 0) ELSE n FOLLOWED BY `division in the list` (n MINUS 1)"
        , ""
        , "GIVEN n IS A NUMBER"
        , "GIVETH A LIST OF NUMBER"
        , "`numbers` n MEANS"
        , "  IF n EQUALS 0 THEN EMPTY ELSE n FOLLOWED BY `numbers` (n MINUS 1)"
        , ""
        , "#ASSERT REFUSED `refusal in the list` 200"
        , "#ASSERT REFUSED `refusal as the rest` 201"
        , "#ASSERT REFUSED `refusal in the list` 201"
        , "#ASSERT REFUSED `refusal as the rest` 202"
        , "#ASSERT REFUSED `division in the list` 201"
        , "#ASSERT REFUSED `numbers` 300"
        , "#ASSERT REFUSED `numbers` 150"
        ])
      length outs `shouldBe` 7
      take 2 outs `shouldBe` replicate 2 "assertion satisfied"
      for_ (take 4 (drop 2 outs)) $ \out -> do
        notDecided out
        out `shouldSatisfy` Text.isInfixOf "The value goes deeper than a directive reads"
      drop 6 outs `shouldBe` ["assertion failed: expected a refusal, but the expression produced a value"]

    it "rejects a computed reason at the parser, at the reason, naming what it expects" $ do
      let directive = "#ASSERT REFUSED `not modelled` BECAUSE `the reason`"
          src = beside ["GIVETH A STRING", "`the reason` MEANS \"not modelled\"", "", directive]
      case checkWithImports emptyVFS src of
        Left errs -> do
          let msg = Text.unlines errs
          msg `shouldSatisfy` Text.isInfixOf "expecting String Literal or space token"
          caretColumn msg `shouldBe` Just (1 + Text.length (fst (Text.breakOn "`the reason`" directive)))
        Right _ -> expectationFailure "an #ASSERT REFUSED with a computed reason parsed"

    it "rejects a reason that is a literal but not a STRING, at the type checker" $
      case frontEnd (beside ["#ASSERT REFUSED `not modelled` BECAUSE 42"]) of
        Left msg -> msg `shouldSatisfy` Text.isInfixOf "The BECAUSE clause of an #ASSERT REFUSED is expected to be a string literal"
        Right _ -> expectationFailure "an #ASSERT REFUSED with the reason 42 type-checked"

    -- A BECAUSE may start a line of its own when it is indented further than
    -- the #ASSERT, and it is then the directive's reason, compared as one on
    -- the directive's line is.
    it "takes a BECAUSE on a line of its own, indented further than the #ASSERT" $ do
      outs <- outcomes
        [ "#ASSERT REFUSED `not modelled`"
        , "  BECAUSE \"not modelled\""
        , "#ASSERT REFUSED `not modelled`"
        , "  BECAUSE \"some other reason\""
        ]
      outs `shouldBe`
        [ "assertion satisfied"
        , "assertion failed: expected the refusal \"some other reason\", got \"not modelled\""
        ]

    -- A BECAUSE further left is an error at the BECAUSE. The service's text
    -- filter ends a directive at the first line that is neither blank nor
    -- indented further than it, so a reason there would be cut from the
    -- directive.
    it "rejects a BECAUSE that starts a line no further right than the #ASSERT, at the BECAUSE" $ do
      let src = beside ["#ASSERT REFUSED `not modelled`", "BECAUSE \"not modelled\""]
      case checkWithImports emptyVFS src of
        Left errs -> do
          let msg = Text.unlines errs
          msg `shouldSatisfy` Text.isInfixOf "only when it is indented further than the #ASSERT"
          msg `shouldSatisfy` Text.isInfixOf "5 | BECAUSE"
          caretColumn msg `shouldBe` Just 1
        Right _ -> expectationFailure "an #ASSERT REFUSED with its BECAUSE at the left margin parsed"

    -- In a section the #ASSERT is indented, and a BECAUSE on a line of its own
    -- is measured against the #ASSERT's column, not the margin's. Columns are
    -- counted as everywhere in L4's layout: a tab goes on to the next multiple
    -- of eight, so one tab is further right than four spaces.
    it "measures a BECAUSE on a line of its own against the #ASSERT's column, in a section" $ do
      let section directives = Text.unlines $
            [ "§ `Fees`"
            , "    GIVETH A NUMBER"
            , "    `not modelled` MEANS REFUSE \"not modelled\""
            , ""
            ] <> directives
      case checkWithImports emptyVFS (section ["    #ASSERT REFUSED `not modelled`", "    BECAUSE \"not modelled\""]) of
        Left errs -> do
          let msg = Text.unlines errs
          msg `shouldSatisfy` Text.isInfixOf "only when it is indented further than the #ASSERT"
          msg `shouldSatisfy` Text.isInfixOf "6 |     BECAUSE"
          caretColumn msg `shouldBe` Just 5
        Right _ -> expectationFailure "an #ASSERT REFUSED with its BECAUSE level with it, in a section, parsed"
      outs <- map Text.strip <$> evalAll (section
        [ "    #ASSERT REFUSED `not modelled`"
        , "      BECAUSE \"not modelled\""
        , "    #ASSERT REFUSED `not modelled`"
        , "\tBECAUSE \"some other reason\""
        ])
      outs `shouldBe`
        [ "assertion satisfied"
        , "assertion failed: expected the refusal \"some other reason\", got \"not modelled\""
        ]
      -- and an #ASSERT indented by a tab is at column nine, right of two spaces
      case checkWithImports emptyVFS "\t#ASSERT REFUSED REFUSE \"x\"\n  BECAUSE \"x\"\n" of
        Left errs -> do
          let msg = Text.unlines errs
          msg `shouldSatisfy` Text.isInfixOf "only when it is indented further than the #ASSERT"
          msg `shouldSatisfy` Text.isInfixOf "2 |   BECAUSE"
        Right _ -> expectationFailure "a BECAUSE two spaces in, below an #ASSERT a tab in, parsed"

    -- A BREACH takes a BECAUSE of its own, so outside parentheses it can take
    -- one written for the directive, which would then name no reason and hold
    -- for a refusal with any reason. So a BECAUSE in the expression and outside
    -- parentheses is an error, at that BECAUSE, whatever follows it.
    it "rejects a BECAUSE that a BREACH in the expression takes outside parentheses, at that BECAUSE" $
      for_
        [ "#ASSERT REFUSED BREACH BECAUSE \"not modelled\""
        , "#ASSERT REFUSED IF TRUE THEN REFUSE \"wrong\" ELSE BREACH BECAUSE \"right\""
        , "#ASSERT REFUSED IF TRUE THEN REFUSE \"wrong\" ELSE BREACH BECAUSE `a reason`"
          -- parentheses that close before the BECAUSE leave it outside them
        , "#ASSERT REFUSED IF (TRUE) THEN REFUSE \"wrong\" ELSE BREACH BECAUSE \"right\""
        , "#ASSERT REFUSED (1 EQUALS 1) AND BREACH BECAUSE \"right\""
          -- and a BECAUSE in the middle of the expression, with more after it
        , "#ASSERT REFUSED IF FALSE THEN BREACH BECAUSE \"b\" ELSE REFUSE \"a\""
        ] $ \directive -> do
          let src = beside ["GIVETH A STRING", "`a reason` MEANS \"right\"", "", directive]
          case checkWithImports emptyVFS src of
            Left errs -> do
              let msg = Text.unlines errs
              msg `shouldSatisfy` Text.isInfixOf "This BECAUSE belongs to the BREACH before it"
              caretColumn msg `shouldBe` Just (1 + Text.length (fst (Text.breakOn "BECAUSE" directive)))
            Right _ -> expectationFailure ("parsed: " <> Text.unpack directive)

    it "takes a BREACH and its BECAUSE in parentheses, and a BECAUSE after them as the directive's" $ do
      outs <- outcomes
        [ "#ASSERT REFUSED (IF TRUE THEN REFUSE \"wrong\" ELSE BREACH BECAUSE \"right\")"
        , "#ASSERT REFUSED (IF TRUE THEN REFUSE \"wrong\" ELSE BREACH) BECAUSE \"right\""
        ]
      outs `shouldBe`
        [ "assertion satisfied"
        , "assertion failed: expected the refusal \"right\", got \"wrong\""
        ]

    -- The browser editor and the Inspector call 'l4Eval' and
    -- 'l4EvalDirective'. A failed #ASSERT REFUSED is a false assertion there,
    -- as a clean FALSE #ASSERT is, and one that holds is a true one.
    it "is a false assertion to the editor's API when it fails, and a true one when it holds" $ do
      let src = beside
            [ "#ASSERT REFUSED 1"
            , "#ASSERT REFUSED `not modelled` BECAUSE \"some other reason\""
            , "#ASSERT REFUSED `not modelled`"
            ]
      out <- l4Eval src
      -- one "success" for the whole call, and one for each result
      Text.count "\"success\":false" out `shouldBe` 2
      Text.count "\"success\":true" out `shouldBe` 2
      for_ [4, 5] $ \line -> do
        one <- l4EvalDirective src line 1 "assert"
        one `shouldSatisfy` Text.isInfixOf "assertion failed: expected"
        one `shouldSatisfy` Text.isInfixOf "\"success\":false"
        one `shouldSatisfy` Text.isInfixOf "\"structuredValue\":false"
      held <- l4EvalDirective src 6 1 "assert"
      held `shouldSatisfy` Text.isInfixOf "\"success\":true"
      held `shouldSatisfy` Text.isInfixOf "\"structuredValue\":true"

    -- l4 batch and the REPL remove the IDE directives from a module, print
    -- it and run it again. An #ASSERT REFUSED is one of those directives.
    it "is removed with the other IDE directives from a module that is run again" $
      case frontEnd (beside ["#ASSERT REFUSED `not modelled`", "#ASSERT REFUSED `not modelled` BECAUSE \"not modelled\""]) of
        Left msg -> expectationFailure ("the module did not check:\n" <> Text.unpack msg)
        Right r -> do
          prettyLayout r.tcdModule `shouldSatisfy` Text.isInfixOf "#ASSERT REFUSED"
          let filtered = prettyLayout (filterIdeDirectives r.tcdModule)
          filtered `shouldNotSatisfy` Text.isInfixOf "#ASSERT"
          filtered `shouldSatisfy` Text.isInfixOf "REFUSE \"not modelled\""

    -- The editor's AND/OR lint reads the expression of an #ASSERT REFUSED as
    -- it reads a plain #ASSERT's: an AND and an OR at one column, on lines of
    -- their own, are warned about at the same places.
    it "is read by the AND/OR lint as a plain #ASSERT is" $ do
      let lintOf directive =
            fmap (checkAndOrDepth . fst) $
              execProgramParser (toNormalizedUri (Uri "file:///refuse-spec-lint")) (beside directive)
          plain = lintOf ["#ASSERT `not modelled` EQUALS 1", "# AND TRUE", "# OR FALSE"]
          refused = lintOf ["#ASSERT REFUSED `not modelled` EQUALS 1", "# AND TRUE", "# OR FALSE", "  BECAUSE \"not modelled\""]
      fmap length plain `shouldBe` Right 2
      refused `shouldBe` plain

  describe "readers of the program" $ do
    it "the exported document reads a refusal as one, with its reason" $
      case frontEnd (ruleOfType "A NUMBER" "REFUSE \"not encoded\"") of
        Left msg -> expectationFailure ("the module did not check:\n" <> Text.unpack msg)
        Right r -> do
          let doc = Text.pack (show (buildDocument defaultExportConfig r.tcdModule []))
          doc `shouldSatisfy` Text.isInfixOf "the model refuses to answer"
          doc `shouldSatisfy` Text.isInfixOf "not encoded"

    it "the exported document reads a refusal after an obligation in quotes" $
      case frontEnd (Text.unlines
             [ "DECLARE Person IS ONE OF Seller, Buyer"
             , "DECLARE Action IS ONE OF pay"
             , ""
             , "GIVETH DEONTIC Person Action"
             , "r MEANS"
             , "  PARTY Buyer"
             , "  MUST pay"
             , "  WITHIN 3"
             , "  HENCE REFUSE \"after payment\""
             ]) of
        Left msg -> expectationFailure ("the module did not check:\n" <> Text.unpack msg)
        Right r -> do
          let doc = Text.pack (show (buildDocument defaultExportConfig r.tcdModule []))
          -- 'show' writes the curly quotes as their code points.
          doc `shouldSatisfy` Text.isInfixOf "the model refuses to answer: \\8220after payment\\8221"

    it "the exported document quotes a refusal's reason wherever the refusal sits" $
      case frontEnd (Text.unlines
             [ "DECLARE Rec HAS amount IS A NUMBER"
             , ""
             , "GIVETH A NUMBER"
             , "`the rate` MEANS REFUSE \"rates are not encoded\" %"
             , ""
             , "GIVETH A NUMBER"
             , "`the amount` MEANS (REFUSE \"no record\")'s amount"
             , ""
             , "GIVETH A BOOLEAN"
             , "`is eligible` MEANS TRUE AND REFUSE \"not modelled\""
             ]) of
        Left msg -> expectationFailure ("the module did not check:\n" <> Text.unpack msg)
        Right r -> do
          let doc = Text.pack (show (buildDocument defaultExportConfig r.tcdModule []))
          -- Unquoted, the "%" and the "'s amount" around a refusal read as
          -- part of its reason. 'show' writes the curly quotes as code points.
          for_ ["rates are not encoded", "no record", "not modelled"] $ \reason ->
            doc `shouldSatisfy` Text.isInfixOf ("the model refuses to answer: \\8220" <> reason <> "\\8221")

    it "the exported document reads arithmetic over a refusal as prose, not as a formula" $
      case frontEnd (Text.unlines
             [ "GIVEN n IS A NUMBER"
             , "GIVETH A NUMBER"
             , "`the fee` n MEANS n PLUS REFUSE \"not encoded\""
             ]) of
        Left msg -> expectationFailure ("the module did not check:\n" <> Text.unpack msg)
        Right r -> do
          let doc = Text.pack (show (buildDocument defaultExportConfig r.tcdModule []))
          -- Formula mode would write "n + …", reading the refusal as a quantity.
          doc `shouldSatisfy` Text.isInfixOf "the sum of n and the model refuses to answer"
          doc `shouldSatisfy` Text.isInfixOf "not encoded"
          doc `shouldNotSatisfy` Text.isInfixOf "n + "

    -- A refusal is not a deontic outcome, so the graph draws no state for it,
    -- and it draws a written refusal as it draws any target it does not
    -- follow, a name included. A refusal written in the rule and one reached
    -- through a name therefore draw the same graph.
    describe "the state graph draws a refusal as any other target, with no state of its own" $ do
      it "after HENCE: the next state, as for a named target" $ do
        sameStateGraph ["PARTY Buyer", "MAY pay", "HENCE REFUSE \"not modelled\""]
                       ["PARTY Buyer", "MAY pay", "HENCE `not modelled`"]
        withStateGraphBeside [] ["PARTY Buyer", "MAY pay", "HENCE REFUSE \"not modelled\""] $ \g -> do
          map (.stateType) g.sgStates `shouldNotContain` [SG.TerminalBreach]
          [ (s.stateName, s.stateType)
            | t <- g.sgTransitions, t.transType == SG.HenceTransition
            , s <- g.sgStates, s.stateId == t.transTo ]
            `shouldBe` [("next", SG.IntermediateState)]
      it "after LEST: the failure state, as for a named target" $
        sameStateGraph ["PARTY Buyer", "MUST pay", "WITHIN 3", "LEST REFUSE \"not modelled\""]
                       ["PARTY Buyer", "MUST pay", "WITHIN 3", "LEST `not modelled`"]
      it "beside an obligation: nothing, as for a named rule beside it" $
        sameStateGraph ["(PARTY Buyer MAY pay) RAND (REFUSE \"not modelled\")"]
                       ["(PARTY Buyer MAY pay) RAND `not modelled`"]

    it "the ladder draws a refusal as a leaf, labelled with its source" $ do
      let src = Text.unlines
            [ "GIVEN registered IS A BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "eligible registered MEANS registered AND REFUSE \"not modelled\""
            ]
          out = l4VisualizeByName src "file:///refuse-spec.l4" 1 "eligible" False
      out `shouldNotSatisfy` Text.isInfixOf "\"error\""
      out `shouldSatisfy` Text.isInfixOf "REFUSE \\\"not modelled\\\""
