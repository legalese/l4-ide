{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Unit coverage for 'L4.Catala.Lower'.
--
-- The centrepiece is Appendix A of @specs\/todo\/CATALA-EXPORT-SPEC.md@: the
-- worked example whose emitted Catala the spec executed against the real
-- toolchain. Lowering it here pins the IR shape that emission depends on —
-- the scope split (R1), the @condition@\/@content@ choice for the output, the
-- cross-decision scope call, and the Mode A\/Mode B pair (R4).
--
-- The rest of the file pins the fragment boundary: which §6 constructs lower,
-- which are rejected, and that rejections are batched rather than
-- first-error-wins.
module CatalaLowerSpec (spec) where

import Test.Hspec

import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Catala.IR
import L4.Catala.Emit (renderModule)
import L4.Catala.Lower (lowerModule, renderLowerError)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))

-- ---------------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------------

-- | Typecheck a snippet and lower it. A typecheck failure is distinguished
-- from a lowering rejection, so a broken fixture can never masquerade as the
-- rejection a test is asserting.
lower :: Text -> Either [Text] CatModule
lower src = case checkWithImports emptyVFS src of
  Left errs -> Left [ "TYPECHECK FAILED: " <> e | e <- errs ]
  Right r   -> case lowerModule r.tcdModule of
    Left es -> Left (map renderLowerError es)
    Right m -> Right m

lowerOk :: HasCallStack => Text -> IO CatModule
lowerOk src = case lower src of
  Left es -> do
    expectationFailure (Text.unpack ("expected a successful lowering, got:\n  "
                                     <> Text.intercalate "\n  " es))
    fail "unreachable"
  Right m -> pure m

lowerErrs :: HasCallStack => Text -> IO [Text]
lowerErrs src = case lower src of
  Left es -> do
    -- A typecheck failure is never the rejection under test.
    mapM_ (\e -> if "TYPECHECK FAILED:" `Text.isPrefixOf` e
                   then expectationFailure (Text.unpack e)
                   else pure ()) es
    pure es
  Right _ -> do
    expectationFailure "expected the lowering to reject this module, but it succeeded"
    pure []

-- ---------------------------------------------------------------------------
-- IR accessors
-- ---------------------------------------------------------------------------

decls :: CatModule -> [CatDecl]
decls m = concat [ ds | SegMetadata ds <- m.modSegments ]

items :: CatModule -> [CatItem]
items m = concat [ is | SegCode is <- m.modSegments ]

structs :: CatModule -> [CatStruct]
structs m = [ s | DStruct s <- decls m ]

enums :: CatModule -> [CatEnum]
enums m = [ e | DEnum e <- decls m ]

scopeDecls :: CatModule -> [CatScopeDecl]
scopeDecls m = [ s | DScope s <- decls m ]

scopeBodies :: CatModule -> [CatScopeBody]
scopeBodies m = [ b | ItemScope b <- items m ]

topdefs :: CatModule -> [CatTopdef]
topdefs m = [ t | ItemDecl (DTopdef t) <- items m ]

scopeDecl :: HasCallStack => Text -> CatModule -> CatScopeDecl
scopeDecl n m = case [ s | s <- scopeDecls m, s.sdName == n ] of
  (s : _) -> s
  []      -> error ("no scope declaration named " <> Text.unpack n)

scopeBody :: HasCallStack => Text -> CatModule -> CatScopeBody
scopeBody n m = case [ b | b <- scopeBodies m, b.sbName == n ] of
  (b : _) -> b
  []      -> error ("no scope body named " <> Text.unpack n)

ruleOf :: HasCallStack => Text -> CatScopeBody -> CatRuleDef
ruleOf v b = case [ r | r <- b.sbRules, r.rdVar == v ] of
  (r : _) -> r
  []      -> error ("no rule for " <> Text.unpack v)

mentions :: Text -> [Text] -> Bool
mentions needle = any (needle `Text.isInfixOf`)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | Appendix A, with one deviation the spec's own listing needs: @\@export@
-- must sit /above/ @GIVEN@, not between @GIVETH@ and @DECIDE@, or the
-- annotation does not attach and the export is not registered.
appendixA :: Text
appendixA = Text.unlines
  [ "DECLARE Applicant HAS"
  , "    age       IS A NUMBER"
  , "    income    IS A NUMBER"
  , "    isVeteran IS A BOOLEAN"
  , ""
  , "@export"
  , "GIVEN a IS AN Applicant"
  , "GIVETH A BOOLEAN"
  , "DECIDE `eligible for benefit` IF"
  , "       a's age AT LEAST 65"
  , "    OR a's isVeteran"
  , "  UNLESS a's income GREATER THAN 100000"
  , ""
  , "@export"
  , "GIVEN a IS AN Applicant"
  , "GIVETH A NUMBER"
  , "`benefit amount` a MEANS"
  , "    IF `eligible for benefit` a THEN 1000 PLUS bonus ELSE 0"
  , "    WHERE bonus MEANS IF a's isVeteran THEN 250 ELSE 0"
  ]

-- ---------------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Appendix A (the spec's worked example)" $ do
    it "emits one structure whose NUMBER fields become decimals (R2)" $ do
      m <- lowerOk appendixA
      map (.stName) (structs m) `shouldBe` ["Applicant"]
      map (\s -> map (\f -> (f.fdName, f.fdType)) s.stFields) (structs m)
        `shouldBe` [[("age", TDecimal), ("income", TDecimal), ("is_veteran", TBool)]]

    it "emits one scope per @export decision, with the record passed whole (R1a)" $ do
      m <- lowerOk appendixA
      map (.sdName) (scopeDecls m) `shouldBe` ["EligibleForBenefit", "BenefitAmount"]
      let d = scopeDecl "EligibleForBenefit" m
      map (\v -> (v.svName, v.svKind, v.svShape)) d.sdVars
        `shouldBe` [ ("a", VarInput, ShContent (TNamed "Applicant"))
                   , ("eligible_for_benefit", VarOutput, ShCondition)
                   ]

    it "gives a non-BOOLEAN decision a `content` output, not a `condition`" $ do
      m <- lowerOk appendixA
      let d = scopeDecl "BenefitAmount" m
      [ v.svShape | v <- d.sdVars, v.svKind == VarOutput ] `shouldBe` [ShContent TDecimal]

    it "renders the boolean decision as a rule with `consequence fulfilled` (Mode A)" $ do
      m <- lowerOk appendixA
      let r = ruleOf "eligible_for_benefit" (scopeBody "EligibleForBenefit" m)
      map (.clConseq) r.rdModeA `shouldBe` [ConsFulfilled]
      map (.clKind) r.rdModeA `shouldBe` [ClPlain]

    it "derives the UNLESS proviso ladder as Mode B (R4, §4.4)" $ do
      m <- lowerOk appendixA
      let r = ruleOf "eligible_for_benefit" (scopeBody "EligibleForBenefit" m)
      case r.rdModeB of
        Nothing -> expectationFailure "no Mode B ladder was derived for the UNLESS proviso"
        Just cs -> do
          map (.clKind) cs
            `shouldBe` [ ClLabel "eligible_for_benefit_p0"
                       , ClException (Just "eligible_for_benefit_p0")
                       ]
          map (.clConseq) cs `shouldBe` [ConsFulfilled, ConsNotFulfilled]
          -- the base keeps the disjunction; the exception carries the proviso
          map (.clCondition) cs
            `shouldBe` [ Just (EBin BOr (EBin BGeq (EProj (EVar "a") "age") (ELit (LDec 65)))
                                        (EProj (EVar "a") "is_veteran"))
                       , Just (EBin BGt (EProj (EVar "a") "income") (ELit (LDec 100000)))
                       ]

    it "keeps Mode A as the emitted rendering until the §8.4 gate exists" $ do
      m <- lowerOk appendixA
      let r = ruleOf "eligible_for_benefit" (scopeBody "EligibleForBenefit" m)
      r.rdEmitted `shouldBe` ModeA
      emittedClauses r `shouldBe` r.rdModeA
      r.rdFallback `shouldSatisfy` maybe False (Text.isInfixOf "equivalence")

    it "compiles a WHERE helper to `let … in` and a cross-decision call to a scope call" $ do
      m <- lowerOk appendixA
      let r = ruleOf "benefit_amount" (scopeBody "BenefitAmount" m)
      case map (.clConseq) r.rdModeA of
        [ConsEquals (ELet "bonus" _ body)] ->
          body `shouldBe`
            EIf (EScopeOut "EligibleForBenefit" [("a", EVar "a")] "eligible_for_benefit")
                (EBin BAdd (ELit (LDec 1000)) (EVar "bonus"))
                (ELit (LDec 0))
        other -> expectationFailure ("unexpected body shape: " <> show other)

    it "emits no helper toplevels: nothing is reachable but the two exports" $ do
      m <- lowerOk appendixA
      topdefs m `shouldBe` []

  describe "the §6 fragment" $ do
    it "lowers a reachable non-exported helper to a private toplevel (R1)" $ do
      m <- lowerOk $ Text.unlines
        [ "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`doubled` n MEANS n TIMES 2"
        , ""
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`unused helper` n MEANS n PLUS 1"
        , ""
        , "@export"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`answer` n MEANS `doubled` n"
        ]
      map (.tdName) (topdefs m) `shouldBe` ["doubled"]
      map (\t -> (t.tdParams, t.tdReturn)) (topdefs m)
        `shouldBe` [([("n", TDecimal)], TDecimal)]
      -- `unused helper` is unreachable, so R1 does not emit it at all
      map (.tdL4) (topdefs m) `shouldNotContain` ["unused helper"]

    it "lowers CONSIDER over an enum to a match with payload binders (§4.3)" $ do
      m <- lowerOk $ Text.unlines
        [ "DECLARE Status IS ONE OF"
        , "    Employed HAS salary IS A NUMBER"
        , "    Retired"
        , ""
        , "@export"
        , "GIVEN s IS A Status"
        , "GIVETH A NUMBER"
        , "`income of` s MEANS"
        , "  CONSIDER s"
        , "  WHEN Employed sal THEN sal"
        , "  WHEN Retired      THEN 20000"
        ]
      map (\e -> (e.enName, map (.caName) e.enCases)) (enums m)
        `shouldBe` [("Status", ["Employed", "Retired"])]
      let r = ruleOf "income_of" (scopeBody "IncomeOf" m)
      map (.clConseq) r.rdModeA `shouldBe`
        [ ConsEquals (EMatch (EVar "s")
            [ CatArm (PCon "Employed" (Just "sal")) (EVar "sal")
            , CatArm (PCon "Retired" Nothing) (ELit (LDec 20000))
            ]) ]

    it "fills a @nonexhaustive CONSIDER's missing arms with `impossible` (§4.3)" $ do
      m <- lowerOk $ Text.unlines
        [ "DECLARE Colour IS ONE OF Red, Green, Blue"
        , ""
        , "@export nonexhaustive"
        , "GIVEN c IS A Colour"
        , "GIVETH A NUMBER"
        , "`partial` c MEANS"
        , "  CONSIDER c"
        , "  WHEN Red   THEN 1"
        , "  WHEN Green THEN 2"
        ]
      let r = ruleOf "partial" (scopeBody "Partial" m)
      case map (.clConseq) r.rdModeA of
        [ConsEquals (EMatch _ arms)] -> do
          map (.armPat) arms `shouldBe`
            [PCon "Red" Nothing, PCon "Green" Nothing, PCon "Blue" Nothing]
          case map (.armBody) arms of
            [_, _, EImpossible (Just msg)] -> msg `shouldSatisfy` Text.isInfixOf "Blue"
            other -> expectationFailure ("expected an impossible arm, got " <> show other)
        other -> expectationFailure ("unexpected shape: " <> show other)

    it "lowers MAYBE to `optional of` with Present/Absent (§4.1)" $ do
      m <- lowerOk $ Text.unlines
        [ "@export"
        , "GIVEN m IS A MAYBE NUMBER"
        , "GIVETH A NUMBER"
        , "`or zero` m MEANS"
        , "  CONSIDER m"
        , "  WHEN NOTHING THEN 0"
        , "  WHEN JUST x  THEN x"
        ]
      let d = scopeDecl "OrZero" m
      [ v.svShape | v <- d.sdVars, v.svKind == VarInput ]
        `shouldBe` [ShContent (TOption TDecimal)]
      let r = ruleOf "or_zero" (scopeBody "OrZero" m)
      map (.clConseq) r.rdModeA `shouldBe`
        [ ConsEquals (EMatch (EVar "m")
            [ CatArm (PCon "Absent" Nothing) (ELit (LDec 0))
            , CatArm (PCon "Present" (Just "x")) (EVar "x")
            ]) ]

    it "absorbs prelude combinators into Catala's binder forms (R5, §4.7)" $ do
      m <- lowerOk $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Household HAS members IS A LIST OF NUMBER"
        , ""
        , "@export"
        , "GIVEN h IS A Household"
        , "GIVETH A BOOLEAN"
        , "`ok` h MEANS"
        , "  sum (h's members) GREATER THAN 0"
        , "  AND all (GIVEN m YIELD m AT LEAST 0) (h's members)"
        ]
      let r = ruleOf "ok" (scopeBody "Ok" m)
          ms = EProj (EVar "h") "members"
      map (.clCondition) r.rdModeA `shouldBe`
        [ Just (EBin BAnd
                 (EBin BGt (EStdCall "Decimal.sum" [ms]) (ELit (LDec 0)))
                 (EForAll "m" ms (EBin BGeq (EVar "m") (ELit (LDec 0))))) ]

    it "turns TYPICALLY into a context variable with an in-scope default (R10)" $ do
      m <- lowerOk $ Text.unlines
        [ "@export"
        , "GIVEN n IS A NUMBER TYPICALLY 1000"
        , "GIVETH A BOOLEAN"
        , "`big` n MEANS n GREATER THAN 500"
        ]
      let d = scopeDecl "Big" m
      [ v.svKind | v <- d.sdVars, v.svName == "n" ] `shouldBe` [VarContext]
      let b = scopeBody "Big" m
      map (.rdVar) b.sbRules `shouldBe` ["n", "big"]
      map (.clConseq) (ruleOf "n" b).rdModeA `shouldBe` [ConsEquals (ELit (LDec 1000))]

    it "builds a first-match priority ladder for BRANCH (R4, §4.4)" $ do
      m <- lowerOk $ Text.unlines
        [ "@export"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`band` n MEANS"
        , "  BRANCH"
        , "    IF n GREATER THAN 100 THEN 3"
        , "    IF n GREATER THAN  50 THEN 2"
        , "    OTHERWISE 1"
        ]
      let r = ruleOf "band" (scopeBody "Band" m)
      -- Mode A is the nested if/else; Mode B is base + two chained exceptions,
      -- highest priority last, so Catala's "the exception wins" reproduces
      -- L4's first-match.
      map (.clConseq) r.rdModeA `shouldBe`
        [ ConsEquals (EIf (EBin BGt (EVar "n") (ELit (LDec 100))) (ELit (LDec 3))
                       (EIf (EBin BGt (EVar "n") (ELit (LDec 50))) (ELit (LDec 2))
                          (ELit (LDec 1)))) ]
      case r.rdModeB of
        Nothing -> expectationFailure "no Mode B ladder was derived for the BRANCH"
        Just cs -> do
          map (.clKind) cs `shouldBe`
            [ ClLabel "band_r0"
            , ClLabelExc "band_r1" "band_r0"
            , ClException (Just "band_r1")
            ]
          map (.clConseq) cs `shouldBe`
            [ ConsEquals (ELit (LDec 1))    -- the OTHERWISE is the base
            , ConsEquals (ELit (LDec 3))    -- first arm: highest priority, applied last
            , ConsEquals (ELit (LDec 2))
            ]

    it "maps a literal YMD to a date literal and an out-of-range one to `impossible` (R3)" $ do
      m <- lowerOk $ Text.unlines
        [ "IMPORT daydate"
        , ""
        , "@export"
        , "GIVETH A DATE"
        , "`millennium` MEANS YMD 2000 1 1"
        , ""
        , "@export"
        , "GIVETH A DATE"
        , "`no such day` MEANS YMD 2023 2 29"
        ]
      map (.clConseq) (ruleOf "millennium" (scopeBody "Millennium" m)).rdModeA
        `shouldBe` [ConsEquals (ELit (LDate 2000 1 1))]
      case map (.clConseq) (ruleOf "no_such_day" (scopeBody "NoSuchDay" m)).rdModeA of
        [ConsEquals (EImpossible (Just msg))] -> msg `shouldSatisfy` Text.isInfixOf "2023-2-29"
        other -> expectationFailure ("expected an `impossible` refusal, got " <> show other)

  describe "R11: uninspected strings are elided, inspected ones are errors" $ do
    it "drops a STRING field from the structure and says so" $ do
      m <- lowerOk $ Text.unlines
        [ "DECLARE Person HAS"
        , "    name IS A STRING"
        , "    age  IS A NUMBER"
        , ""
        , "@export"
        , "GIVEN p IS A Person"
        , "GIVETH A BOOLEAN"
        , "`adult` p MEANS p's age AT LEAST 18"
        ]
      map (.fdName) (concatMap (.stFields) (structs m)) `shouldBe` ["age"]
      m.modWarnings `shouldSatisfy` mentions "field `name`"
      m.modWarnings `shouldSatisfy` mentions "R11"

    it "keeps a record built with an elided field constructible" $ do
      m <- lowerOk $ Text.unlines
        [ "DECLARE Person HAS"
        , "    name IS A STRING"
        , "    age  IS A NUMBER"
        , ""
        , "@export"
        , "GIVETH A BOOLEAN"
        , "`sample` MEANS (Person WITH name IS \"bob\", age IS 30)'s age AT LEAST 18"
        ]
      let r = ruleOf "sample" (scopeBody "Sample" m)
      map (.clCondition) r.rdModeA `shouldBe`
        [ Just (EBin BGeq (EProj (EStruct "Person" [("age", ELit (LDec 30))]) "age")
                          (ELit (LDec 18))) ]

    it "rejects reading a string, naming the field and the range" $ do
      es <- lowerErrs $ Text.unlines
        [ "DECLARE Person HAS name IS A STRING"
        , ""
        , "@export"
        , "GIVEN p IS A Person"
        , "GIVETH A BOOLEAN"
        , "`named bob` p MEANS p's name EQUALS \"bob\""
        ]
      es `shouldSatisfy` mentions "field `name` is a STRING"
      es `shouldSatisfy` mentions "string literals have no Catala counterpart"

  describe "the fragment boundary is a diagnostic, not a silent narrowing (§6)" $ do
    it "rejects recursion and names the cycle (R6)" $ do
      es <- lowerErrs $ Text.unlines
        [ "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`fact` n MEANS IF n AT MOST 1 THEN 1 ELSE n TIMES `fact` (n MINUS 1)"
        , ""
        , "@export"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`f` n MEANS `fact` n"
        ]
      es `shouldSatisfy` mentions "recursion has no Catala counterpart"
      es `shouldSatisfy` mentions "fact → fact"

    it "rejects a partial CONSIDER that is not marked @nonexhaustive (§4.3)" $ do
      es <- lowerErrs $ Text.unlines
        [ "DECLARE Colour IS ONE OF Red, Green, Blue"
        , ""
        , "@export"
        , "GIVEN c IS A Colour"
        , "GIVETH A NUMBER"
        , "`partial` c MEANS"
        , "  CONSIDER c"
        , "  WHEN Red   THEN 1"
        , "  WHEN Green THEN 2"
        ]
      es `shouldSatisfy` mentions "does not cover `Blue`"

    it "rejects a list pattern as the structural recursion it is (R6, §4.7)" $ do
      es <- lowerErrs $ Text.unlines
        [ "@export"
        , "GIVEN xs IS A LIST OF NUMBER"
        , "GIVETH A NUMBER"
        , "`head or zero` xs MEANS"
        , "  CONSIDER xs"
        , "  WHEN EMPTY            THEN 0"
        , "  WHEN x FOLLOWED BY ys THEN x"
        ]
      es `shouldSatisfy` mentions "list pattern"

    it "rejects a WHERE binding that takes parameters (§4.2)" $ do
      es <- lowerErrs $ Text.unlines
        [ "@export"
        , "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "`twice` n MEANS dbl n"
        , "  WHERE dbl x MEANS x TIMES 2"
        ]
      es `shouldSatisfy` mentions "local function"

    it "reports every broken decision in one batch, not just the first (§6)" $ do
      es <- lowerErrs $ Text.unlines
        [ "DECLARE Person HAS"
        , "    name IS A STRING"
        , "    age  IS A NUMBER"
        , ""
        , "@export"
        , "GIVEN p IS A Person"
        , "GIVETH A BOOLEAN"
        , "`one` p MEANS p's name EQUALS \"a\""
        , ""
        , "@export"
        , "GIVEN p IS A Person"
        , "GIVETH A NUMBER"
        , "`two` p MEANS p's age MODULO 2"
        ]
      es `shouldSatisfy` mentions "one"
      es `shouldSatisfy` mentions "two"
      es `shouldSatisfy` mentions "modulo"
      length es `shouldSatisfy` (>= 3)

    it "says so when there is nothing to export" $ do
      lower "GIVETH A NUMBER\n`x` MEANS 1\n"
        `shouldBe` Left ["no @export-annotated DECIDE found to compile to Catala"]

  describe "provenance" $ do
    it "names the module after the source file's basename" $ do
      m <- lowerOk appendixA
      -- checkWithImports synthesises an in-memory URI; the module name is
      -- derived from its basename, so it is at least non-empty and capitalised.
      m.modName `shouldSatisfy` (not . Text.null)
      Text.take 1 m.modName `shouldBe` Text.toUpper (Text.take 1 m.modName)
      m.modSource `shouldSatisfy` (not . Text.null)

  describe "name mangling" $ do
    it "splits camel humps and keeps Catala keywords safe" $ do
      map catIdent ["isVeteran", "benefit amount", "date", "2ndTry"]
        `shouldBe` ["is_veteran", "benefit_amount", "date_", "v_2nd_try"]
      map catUpper ["eligible for benefit", "applicant"]
        `shouldBe` ["EligibleForBenefit", "Applicant"]

    it "reports mangling collisions rather than conflating definitions" $ do
      es <- lowerErrs $ Text.unlines
        [ "@export"
        , "GIVETH A NUMBER"
        , "`net pay` MEANS 1"
        , ""
        , "@export"
        , "GIVETH A NUMBER"
        , "`net-pay` MEANS 2"
        ]
      es `shouldSatisfy` mentions "name collision"

  -- The emitter is a later phase's subject, but one of its rules was found by
  -- running the real toolchain over a ladder base and is easy to regress:
  -- Catala's `consequence` keyword belongs to the *condition* clause
  -- (`condition_consequence := UNDER_CONDITION expr CONSEQUENCE`), so an
  -- unconditional rule is `rule v fulfilled`, never
  -- `rule v consequence fulfilled` — which catala 1.2.1 rejects outright.
  describe "emission of an unconditional rule (the Mode B ladder base)" $ do
    it "omits `consequence` when there is no `under condition`" $ do
      let m = CatModule
            { modName = "T", modSource = "t.l4", modWarnings = []
            , modSegments =
                [ SegCode [ ItemScope (CatScopeBody "S"
                    [ CatRuleDef
                        { rdVar = "v"
                        , rdModeA =
                            [ CatClause (ClLabel "v_r0") Nothing ConsNotFulfilled
                            , CatClause (ClException (Just "v_r0"))
                                (Just (ELit (LBool True))) ConsFulfilled
                            ]
                        , rdModeB = Nothing, rdEmitted = ModeA, rdFallback = Nothing
                        } ]) ]
                ]
            }
          out = renderModule m
      out `shouldSatisfy` Text.isInfixOf "label v_r0 rule v\n    not fulfilled"
      out `shouldSatisfy` Text.isInfixOf "consequence fulfilled"
      out `shouldNotSatisfy` Text.isInfixOf "consequence not fulfilled"
