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

import L4.API (l4VisualizeByName)
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import qualified L4.EvaluateLazy as EL
import L4.Export.Document (buildDocument, defaultExportConfig)
import qualified L4.Lexer as Lexer
import L4.Print (prettyLayout)
import qualified L4.StateGraph as SG
import L4.TracePolicy (apiDefaultPolicy)
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
evalAll src = case frontEnd src of
  Left msg -> do
    expectationFailure ("the module did not check:\n" <> Text.unpack msg)
    pure []
  Right r -> do
    cfg <- EL.resolveEvalConfigWithSafeMode Nothing apiDefaultPolicy True
    (_, results) <- EL.execEvalModuleWithEnv cfg r.tcdEntityInfo mempty r.tcdModule
    pure (map EL.prettyEvalDirectiveResult results)

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

    -- An #ASSERT whose expression refuses is decided neither way: it reports
    -- the refusal under "assertion could not be evaluated:", in either
    -- polarity. 'refusesWith' rejects the word "assertion", so this case has
    -- its own matcher.
    it "leaves an #ASSERT that refuses undecided, in either polarity, with the reason" $ do
      outs <- evalAll $ Text.unlines
        [ "GIVETH A BOOLEAN"
        , "`not modelled` MEANS REFUSE \"not modelled\""
        , ""
        , "#ASSERT `not modelled`"
        , "#ASSERT NOT `not modelled`"
        ]
      length outs `shouldBe` 2
      for_ outs $ \out -> do
        out `shouldSatisfy` Text.isInfixOf "assertion could not be evaluated:"
        out `shouldSatisfy` Text.isInfixOf "The model refuses to answer:"
        out `shouldSatisfy` Text.isInfixOf "not modelled"
        for_ ["assertion satisfied", "assertion failed"] $ \verdict ->
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

    it "is named in an evaluation trace, with its reason" $ do
      out <- evalOne "#EVALTRACE 1 PLUS REFUSE \"traced\"\n"
      out `shouldSatisfy` Text.isInfixOf "↯ refused: traced"

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
