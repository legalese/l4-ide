{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module UnifySpec (spec) where

import Test.Hspec
import Control.Exception (evaluate)
import System.CPUTime (getCPUTime)
import System.Timeout (timeout)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import Base (NormalizedUri, Uri (..), toNormalizedUri)
import L4.API.VirtualFS
import L4.Annotation (emptyAnno)
import L4.Syntax (Name (MkName), RawName (NormalName), Resolved (Def), Type' (..), Unique (MkUnique), getOriginal, getUnique, rawName, rawNameToText)
import L4.TypeCheck (initialCheckEnv, initialCheckState, prettyCheckErrorWithContext, runWith)
import L4.TypeCheck.Types (CheckEntity (..), CheckEnv (..), CheckError (..), CheckErrorWithContext (..), runCheck)
import L4.TypeCheck.Unify (unify)

-- | Run the type checker on a snippet under a watchdog: unification bugs
-- in this area historically caused nontermination, so a hang is reported
-- as a test failure instead of hanging the suite.
checks :: Text -> IO Bool
checks source = do
  mb <- timeout (30 * 1000000) (evaluate accepted)
  case mb of
    Nothing -> fail "type checker did not terminate within 30s"
    Just b -> pure b
  where
    accepted = case checkWithImports emptyVFS source of
      Left _errs -> False
      Right r -> r.tcdSuccess

-- | Whether a snippet checks, and the members of each synonym cycle it is
-- reported to contain, under the same watchdog as 'checks'.
cycleReport :: Text -> IO (Bool, [[Text]])
cycleReport = cycleReportWith emptyVFS

-- | 'cycleReport' for a snippet that imports from a VFS.
cycleReportWith :: VFS -> Text -> IO (Bool, [[Text]])
cycleReportWith vfs source = do
  mb <- timeout (30 * 1000000) $ case checkWithImports vfs source of
    Left errs -> fail ("unexpected pipeline failure: " <> show errs)
    Right r -> do
      let cycles = [ rawNameToText . rawName <$> ns | MkCheckErrorWithContext (CyclicTypeSynonyms ns) _ <- r.tcdErrors ]
      ok <- evaluate r.tcdSuccess
      _ <- evaluate (sum (Text.length <$> concat cycles))
      pure (ok, cycles)
  maybe (fail "type checker did not terminate within 30s") pure mb

-- | The messages a snippet is reported with, rendered as the user sees them.
messagesOf :: Text -> IO Text
messagesOf source = do
  mb <- timeout (30 * 1000000) $ case checkWithImports emptyVFS source of
    Left errs -> fail ("unexpected pipeline failure: " <> show errs)
    Right r -> evaluate (Text.unlines (concatMap prettyCheckErrorWithContext r.tcdErrors))
  maybe (fail "type checker did not terminate within 30s") pure mb

spec :: Spec
spec = describe "Unification" $ do
  describe "sibling inference-variable rebinding (soundness)" $ do
    it "rejects PAIR OF a, a instantiated at two different types" $ do
      -- The pre-fix unifier let the second pair component silently rebind
      -- the inference variable already bound by the first, accepting this.
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "      p IS A PAIR OF a, a"
        , "GIVETH AN a"
        , "firstOf p MEANS"
        , "  CONSIDER p"
        , "  WHEN PAIR OF x, y THEN x"
        , ""
        , "GIVETH A NUMBER"
        , "n MEANS firstOf (PAIR OF \"hello\", 42)"
        ]
      ok `shouldBe` False

    it "accepts PAIR OF a, a at a consistent instantiation" $ do
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "      p IS A PAIR OF a, a"
        , "GIVETH AN a"
        , "firstOf p MEANS"
        , "  CONSIDER p"
        , "  WHEN PAIR OF x, y THEN x"
        , ""
        , "GIVETH A NUMBER"
        , "n MEANS firstOf (PAIR OF 41, 42)"
        ]
      ok `shouldBe` True

  describe "cyclic substitutions (termination)" $ do
    it "terminates and accepts swapped type arguments fed the same unknown" $ do
      -- Pre-fix this built the cyclic substitution a := b, b := a and
      -- looped forever in applySubst.
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "      b IS A TYPE"
        , "      p IS A PAIR OF a, b"
        , "      q IS A PAIR OF b, a"
        , "GIVETH A PAIR OF a, b"
        , "swappy p q MEANS p"
        , ""
        , "ASSUME mystery"
        , ""
        , "oops MEANS swappy mystery mystery"
        ]
      ok `shouldBe` True

  describe "type synonym cycles (termination)" $ do
    it "rejects a self-recursive type synonym" $ do
      ok <- checks $ Text.unlines
        [ "DECLARE Loop IS A Loop"
        , ""
        , "GIVETH A Loop"
        , "oops MEANS 42"
        ]
      ok `shouldBe` False

    it "rejects mutually recursive type synonyms" $ do
      ok <- checks $ Text.unlines
        [ "DECLARE Ping IS A Pong"
        , "DECLARE Pong IS A Ping"
        , ""
        , "GIVETH A Ping"
        , "oops MEANS 42"
        ]
      ok `shouldBe` False

    it "accepts a chain of non-cyclic synonyms" $ do
      ok <- checks $ Text.unlines
        [ "DECLARE Score IS A NUMBER"
        , "DECLARE Scores IS A LIST OF Score"
        , ""
        , "GIVETH A Scores"
        , "top MEANS LIST 1, 2"
        ]
      ok `shouldBe` True

    it "rejects a self-recursive synonym hidden behind an AKA alias" $ do
      -- The cycle detector must see references through aliases, or the
      -- cycle evades declaration-time rejection and keeps its body (the
      -- expansion fuel bounds how deep it is followed, not how much work
      -- that takes).
      let result = checkWithImports emptyVFS $ Text.unlines
            [ "DECLARE Loop AKA L IS A L"
            , ""
            , "GIVETH A Loop"
            , "oops MEANS 42"
            ]
      case result of
        Left errs -> fail ("unexpected pipeline failure: " <> show errs)
        Right r -> do
          r.tcdSuccess `shouldBe` False
          [e | MkCheckErrorWithContext e@(CyclicTypeSynonyms _) _ <- r.tcdErrors]
            `shouldSatisfy` (not . null)

    it "does not let an alias shadow a sibling synonym's primary name (either order)" $ do
      -- Wrap's alias 'Beta' collides with the sibling synonym Beta; the
      -- body reference 'Beta' resolves (by arity) to the sibling, so the
      -- program is acyclic and must be accepted regardless of
      -- declaration order.
      let prog beforeWrap =
            Text.unlines $
              [ "DECLARE Duo OF a, b"
              , "  HAS fst IS AN a"
              , "      snd IS A  b"
              ]
              <> (if beforeWrap then ["DECLARE Beta IS A NUMBER"] else [])
              <> [ "DECLARE Wrap a AKA Beta IS A Duo OF a, Beta" ]
              <> (if beforeWrap then [] else ["DECLARE Beta IS A NUMBER"])
              <> [ ""
                 , "GIVEN p IS A Wrap OF STRING"
                 , "GIVETH A Duo OF STRING, NUMBER"
                 , "unwrap p MEANS p"
                 ]
      okBefore <- checks (prog True)
      okAfter  <- checks (prog False)
      (okBefore, okAfter) `shouldBe` (True, True)

    it "rejects a synonym that reaches itself through an alias it shares with a one-parameter sibling" $ do
      -- `B1` in W1's body has no arguments, so it can only be W1's own alias:
      -- the sibling `B1` takes one parameter. W1 is then `Duo OF W1, W1`, and
      -- so is W2. The detector used to give the name to the sibling, found no
      -- cycle, and left both bodies live: unifying W1 with W2 branched twice
      -- per expansion, 500 deep (4 GiB and still going).
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "DECLARE Duo OF a, b"
        , "  HAS fst IS AN a"
        , "      snd IS A  b"
        , ""
        , "DECLARE W1 AKA B1 IS A Duo OF B1, B1"
        , "DECLARE B1 a IS A LIST OF a"
        , "DECLARE W2 AKA B2 IS A Duo OF B2, B2"
        , "DECLARE B2 a IS A LIST OF a"
        , ""
        , "GIVEN x IS A W1"
        , "GIVETH A W2"
        , "f x MEANS x"
        ]
      ok `shouldBe` False
      cycles `shouldMatchList` [["W1"], ["W2"]]

    it "rejects a synonym whose body is its own alias, even when a sibling takes the same spelling" $ do
      -- The single-synonym form of the case above. The cycle is W = W; this
      -- used to check clean, with no report at all.
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "DECLARE W AKA B IS A B"
        , "DECLARE B a IS A LIST OF a"
        ]
      ok `shouldBe` False
      cycles `shouldBe` [["W"]]

    it "reads a use with an argument as the sibling that takes one, not the alias that takes none" $ do
      -- The converse: `B OF NUMBER` is the one-parameter sibling `B`, so
      -- there is no cycle and the program is accepted.
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "DECLARE W AKA B IS A NUMBER"
        , "DECLARE B a IS A LIST OF a"
        , "DECLARE C IS A B OF NUMBER"
        , ""
        , "GIVETH A C"
        , "top MEANS LIST 1, 2"
        ]
      (ok, cycles) `shouldBe` (True, [])

    it "still quarantines a cyclic synonym that names itself with the wrong number of arguments" $ do
      -- `B` takes one parameter and its body says `B` bare, which is a kind
      -- error; the checker still resolves the name to B. The spelling-based
      -- pass, which reads only uses with the right number of arguments,
      -- does not see that; the pass over the resolved bodies does, and
      -- without it two doubling bodies would stay live.
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE B a IS A PAIR OF B, B"
        , "DECLARE C a IS A PAIR OF C, C"
        , ""
        , "GIVEN x IS A B OF NUMBER"
        , "GIVETH A C OF NUMBER"
        , "f x MEANS x"
        ]
      ok `shouldBe` False
      cycles `shouldMatchList` [["B"], ["C"]]

    it "accepts a synonym that shares its name with a record of another arity" $ do
      -- The record `Box a` takes one argument, so `Box OF NUMBER` is the
      -- record and the bare `Box` is the synonym. The synonym does not refer
      -- to itself, and `Box OF 41` is a box of a number.
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "DECLARE Box a HAS item IS AN a"
        , ""
        , "DECLARE Box IS A Box OF NUMBER"
        , ""
        , "GIVEN b IS A Box"
        , "GIVETH A NUMBER"
        , "contents b MEANS b's item"
        , ""
        , "GIVETH A NUMBER"
        , "answer MEANS contents (Box OF 41) + 1"
        ]
      (ok, cycles) `shouldBe` (True, [])

    it "accepts a synonym whose alias is a record's name, used inside a list at that record's arity" $ do
      -- `Crate OF NUMBER` is the one-parameter record; the synonym `Shelf`
      -- answers to `Crate` bare, which takes no arguments.
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Crate a HAS item IS AN a"
        , "DECLARE Shelf AKA Crate IS A LIST OF (Crate OF NUMBER)"
        , ""
        , "GIVETH A Shelf"
        , "shelf MEANS LIST (Crate OF 1)"
        ]
      (ok, cycles) `shouldBe` (True, [])

    it "accepts a synonym whose alias is a two-parameter record's name, applied to two arguments" $ do
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Pair2 a b HAS one IS AN a"
        , "                      two IS A b"
        , "DECLARE Cell AKA Pair2 IS A Pair2 OF NUMBER, STRING"
        , ""
        , "GIVETH A Cell"
        , "cell MEANS Pair2 OF 1, \"x\""
        ]
      (ok, cycles) `shouldBe` (True, [])

    it "accepts a synonym whose alias is a record's name, where the record's field is an enum" $ do
      (ok, cycles) <- cycleReport $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Status IS ONE OF Active, Closed"
        , "DECLARE Tagged a HAS tag IS A Status"
        , "                     val IS AN a"
        , "DECLARE Account AKA Tagged IS A Tagged OF NUMBER"
        , ""
        , "GIVETH A Account"
        , "account MEANS Tagged OF Active, 100"
        ]
      (ok, cycles) `shouldBe` (True, [])

    it "accepts a synonym that shares its alias with an imported record of another arity" $ do
      let vfs = vfsFromList [ ( "boxlib", "DECLARE Box a HAS item IS AN a\n" ) ]
      (ok, cycles) <- cycleReportWith vfs $ Text.unlines
        [ "IMPORT boxlib"
        , ""
        , "DECLARE Shelf AKA Box IS A Box OF NUMBER"
        , ""
        , "GIVETH A Shelf"
        , "w MEANS Box OF 1"
        ]
      (ok, cycles) `shouldBe` (True, [])

    it "terminates when the cyclic synonyms come from an imported module" $ do
      -- Imports are acyclic, and the imported module's own check quarantines
      -- its cyclic synonyms, so the importer meets them with no body.
      let vfs = vfsFromList
            [ ( "loops"
              , Text.unlines
                  [ "IMPORT prelude"
                  , "DECLARE Loop1 IS A PAIR OF Loop1, Loop1"
                  , "DECLARE Loop2 IS A PAIR OF Loop2, Loop2"
                  ]
              )
            ]
          source = Text.unlines
            [ "IMPORT prelude"
            , "IMPORT loops"
            , ""
            , "GIVEN x IS A Loop1"
            , "GIVETH A Loop2"
            , "f x MEANS x"
            ]
      mb <- timeout (30 * 1000000) $ case checkWithImports vfs source of
        Left errs -> fail ("unexpected pipeline failure: " <> show errs)
        Right r -> evaluate r.tcdSuccess
      mb `shouldBe` Just False

    it "terminates when a cycle only the resolved bodies show comes from an imported module" $ do
      -- The same, for the cycle that is found among the resolved bodies
      -- rather than by spelling (a use at the wrong number of arguments): the
      -- module that declares it has them quarantined before anyone imports it.
      let vfs = vfsFromList
            [ ( "wloops"
              , Text.unlines
                  [ "IMPORT prelude"
                  , "DECLARE B1 a IS A PAIR OF B1, B1"
                  , "DECLARE B2 a IS A PAIR OF B2, B2"
                  ]
              )
            ]
          source = Text.unlines
            [ "IMPORT prelude"
            , "IMPORT wloops"
            , ""
            , "GIVEN x IS A B1 OF NUMBER"
            , "GIVETH A B2 OF NUMBER"
            , "f x MEANS x"
            ]
      mb <- timeout (30 * 1000000) $ case checkWithImports vfs source of
        Left errs -> fail ("unexpected pipeline failure: " <> show errs)
        Right r -> evaluate r.tcdSuccess
      mb `shouldBe` Just False

    it "terminates promptly unifying two distinct cyclic doubling synonyms" $ do
      -- Both synonyms are flagged at declaration time, but checking
      -- continues; with their bodies still expandable this unification
      -- was a 2^(fuel/2)-wide recursion tree — an effective hang from a
      -- 4-line file. Quarantining cyclic synonym bodies makes it fail
      -- fast instead.
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "DECLARE Loop1 IS A PAIR OF Loop1, Loop1"
        , "DECLARE Loop2 IS A PAIR OF Loop2, Loop2"
        , ""
        , "GIVEN x IS A Loop1"
        , "GIVETH A Loop2"
        , "f x MEANS x"
        ]
      ok `shouldBe` False

    it "terminates when a cyclic synonym is applied as a function (matchFunTy fuel)" $ do
      -- Decl-time errors do not stop checking. The cyclic synonym's body
      -- is quarantined, so the application below reports IllegalApp
      -- instead of driving matchFunTy's expansion loop (whose fuel only
      -- bounds a chain of synonyms too long to follow); pre-fix this hung
      -- forever.
      ok <- checks $ Text.unlines
        [ "DECLARE Loop IS A Loop"
        , ""
        , "GIVETH A Loop"
        , "f MEANS 42"
        , ""
        , "result MEANS f 1"
        ]
      ok `shouldBe` False

    it "accepts a deep acyclic synonym chain well within the fuel budget" $ do
      -- A 500-link alias chain needs 500 expansions along one path; the
      -- budget (1000) must not reject legitimate depth.
      ok <- checks $ Text.unlines $
        synonymChain 500
          <> [ ""
             , "GIVETH A S500"
             , "x MEANS 42"
             ]
      ok `shouldBe` True

    it "rejects (terminating) past the documented fuel bound of 1000 expansions" $ do
      -- Documented completeness boundary: a >1000-deep chain exhausts the
      -- per-path expansion fuel and is rejected rather than hanging (with
      -- the limit's own message, see the test below). If this test starts
      -- failing because the budget changed, update the constant in the
      -- test name and move on.
      ok <- checks $ Text.unlines $
        synonymChain 1200
          <> [ ""
             , "GIVETH A S1200"
             , "x MEANS 42"
             ]
      ok `shouldBe` False

    it "says that the expansion limit was reached, and not that the types differ" $ do
      -- The chain is valid, and S1200 stands for NUMBER. Reporting "must
      -- match ... S1200 but is here of type NUMBER" tells the user their
      -- types disagree when they do not; the message has to name the limit
      -- and a synonym in the chain.
      let source = Text.unlines $
            synonymChain 1200
              <> [ ""
                 , "GIVETH A S1200"
                 , "x MEANS 42"
                 ]
      mismatches <- do
        mb <- timeout (30 * 1000000) $ case checkWithImports emptyVFS source of
          Left errs -> fail ("unexpected pipeline failure: " <> show errs)
          Right r -> evaluate (length [ () | MkCheckErrorWithContext (TypeMismatch {}) _ <- r.tcdErrors ])
        maybe (fail "type checker did not terminate within 30s") pure mb
      msgs <- messagesOf source
      mismatches `shouldBe` 0
      msgs `shouldSatisfy` Text.isInfixOf "1000"
      msgs `shouldSatisfy` Text.isInfixOf "`S"

    it "unifies identical doubling-synonym towers in linear time (equality short-circuit)" $ do
      -- DAG-shaped synonyms (body mentions the parameter chain twice)
      -- explode exponentially if expanded before comparison; identical
      -- sides must short-circuit. Pre-fix n=22 took >60s; this must
      -- finish within the watchdog.
      ok <- checks $ Text.unlines $
        doublingTower 22
          <> [ ""
             , "GIVEN p IS A D22"
             , "GIVETH A D22"
             , "same p MEANS p"
             ]
      ok `shouldBe` True

  describe "cost of unifying nested types" $ do
    -- Unifying a type with its instance used to substitute the whole
    -- remaining subtree at every step of the descent, so the cost grew with
    -- the SQUARE of the nesting: `idf v` fifty times at depth 400 took
    -- 15.3 s to check, and 1.9 s once only the head is walked (16.8 s in
    -- the review of legalese/l4-ide#545, finding F5). Timed by the
    -- ratio of two sizes, not by a bound in seconds, so that a slow machine
    -- does not fail it; and in CPU time, so that time spent waiting for a busy
    -- machine is not counted. Four times the depth takes about four times as
    -- long when the cost is linear and sixteen times as long when it is
    -- quadratic; the test fails above 'deepLimit'.
    it "checks a use of a generic function at a nested type in time linear in the nesting" $
      checksInLinearTime 100 400 deepLimit \ depth -> deepIdentity depth 10

  describe "cost of unifying types nested on the left" $ do
    -- The first difference between @P OF (P OF (... a ...), a), a@ and the
    -- same type at NUMBER is at the bottom. Unification used to compare the
    -- two for structural equality at every level on the way down, and each
    -- comparison walked to that bottom, so the cost was the square of the
    -- depth. This unifies the two directly, with no parsing or name
    -- resolution to add their own cost, so that nothing but the descent is
    -- timed (the same shape through `l4 check` is mostly the cost of
    -- everything else, and the square only shows far down). Four times the
    -- depth takes about four times as long when the descent is linear, up
    -- to about six when the larger heap makes collection dearer, and about
    -- fifteen times as long when it is quadratic.
    it "unifies a type nested on the left with its instance in time linear in the nesting" $
      unifiesInLinearTime 4000 16000 10

  describe "occurs check within one walk" $ do
    it "rejects PAIR OF a, a against PAIR OF b, LIST OF b" $ do
      -- Pre-fix, the overwrite in bind masked this indirect infinite
      -- type: the first component bound b := a, then the second rebound
      -- rather than noticing a occurs in LIST OF a.
      ok <- checks $ Text.unlines
        [ "IMPORT prelude"
        , ""
        , "GIVEN a IS A TYPE"
        , "GIVETH A PAIR OF a, a"
        , "ASSUME diag"
        , ""
        , "GIVEN b IS A TYPE"
        , "      p IS A PAIR OF b, LIST OF b"
        , "GIVETH A BOOLEAN"
        , "g p MEANS TRUE"
        , ""
        , "bad MEANS g diag"
        ]
      ok `shouldBe` False

  describe "cyclic substitutions via function types" $ do
    it "terminates and accepts swapped FUNCTION type arguments fed the same unknown" $ do
      -- Same shape as the PAIR case but through unifyBase's Fun branch,
      -- which re-substitutes independently of the TyApp branch.
      ok <- checks $ Text.unlines
        [ "GIVEN a IS A TYPE"
        , "      b IS A TYPE"
        , "      f IS A FUNCTION FROM a TO b"
        , "      g IS A FUNCTION FROM b TO a"
        , "GIVETH A BOOLEAN"
        , "duo f g MEANS TRUE"
        , ""
        , "ASSUME mystery"
        , ""
        , "ok MEANS duo mystery mystery"
        ]
      ok `shouldBe` True

  describe "synonym expansion exposing inference variables" $ do
    it "accepts an identity synonym used at an inferred instantiation" $ do
      -- Expanding 'Id OF ?a' yields the bare inference variable ?a, which
      -- the expansion path must handle (it re-enters the InfVar cases).
      ok <- checks $ Text.unlines
        [ "DECLARE Id a IS AN a"
        , ""
        , "GIVEN a IS A TYPE"
        , "      x IS AN Id OF a"
        , "GIVETH AN a"
        , "unwrap x MEANS x"
        , ""
        , "n MEANS unwrap 42"
        ]
      ok `shouldBe` True

    it "reads a variable bound by an earlier sibling through the synonym that expands to it" $ do
      -- Only the head of a type is looked through when unification descends,
      -- so `Id OF a` is met with `a` still written as the variable that the
      -- first component has since bound to NUMBER. The expansion must look
      -- through it again, and must not take it for a fresh unknown.
      let prog second = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "DECLARE Id a IS AN a"
            , ""
            , "GIVEN a IS A TYPE"
            , "      p IS A PAIR OF a, Id OF a"
            , "GIVETH AN a"
            , "firstOf p MEANS"
            , "  CONSIDER p"
            , "  WHEN PAIR OF x, y THEN x"
            , ""
            , "GIVETH A NUMBER"
            , "n MEANS firstOf (PAIR OF 41, " <> second <> ")"
            ]
      agree <- checks (prog "42")
      clash <- checks (prog "\"hello\"")
      (agree, clash) `shouldBe` (True, False)

    it "does not report a cycle when a synonym's parameter matches a sibling's name" $ do
      -- Name resolution rejects the shadowed reference as ambiguous, which
      -- is fine — but the cycle detector must not pile on with a spurious
      -- cycle: a synonym's own type parameters do not count as references
      -- to a like-named sibling synonym.
      let result = checkWithImports emptyVFS $ Text.unlines
            [ "DECLARE Score IS A NUMBER"
            , "DECLARE Tagged Score IS A LIST OF Score"
            , ""
            , "GIVETH A Tagged OF NUMBER"
            , "top MEANS LIST 1, 2"
            ]
      case result of
        Left errs -> fail ("unexpected pipeline failure: " <> show errs)
        Right r -> do
          r.tcdSuccess `shouldBe` False
          [e | MkCheckErrorWithContext e@(CyclicTypeSynonyms _) _ <- r.tcdErrors]
            `shouldBe` []

-- | DECLARE S0 IS A NUMBER, then a linear alias chain S1 .. Sn.
synonymChain :: Int -> [Text]
synonymChain n =
  "DECLARE S0 IS A NUMBER"
    : [ "DECLARE S" <> tshow i <> " IS A S" <> tshow (i - 1) | i <- [1 .. n] ]

-- | A DAG-shaped synonym tower: each level pairs the previous level
-- with itself, so naive expansion is exponential in the height.
doublingTower :: Int -> [Text]
doublingTower n =
  "IMPORT prelude"
    : "DECLARE D0 IS A NUMBER"
    : [ "DECLARE D" <> tshow i <> " IS A PAIR OF D" <> tshow (i - 1) <> ", D" <> tshow (i - 1)
      | i <- [1 .. n]
      ]

tshow :: Int -> Text
tshow = Text.pack . show

-- | @P OF (P OF (... (t), (t)) ..., (t)), (t)@, @d@ levels of @P@ deep: the
-- shape that made unification quadratic.
nestedP :: Int -> Text -> Text
nestedP 0 t = t
nestedP d t = "P OF (" <> nestedP (d - 1) t <> "), (" <> t <> ")"

-- | A generic identity over a type nested @depth@ deep, applied @uses@ times
-- to a value of its instance at NUMBER: each use unifies the whole nest.
deepIdentity :: Int -> Int -> Text
deepIdentity depth uses =
  Text.unlines $
    [ "DECLARE P OF a, b"
    , "  HAS fst IS AN a"
    , "      snd IS A  b"
    , ""
    , "GIVEN a IS A TYPE"
    , "      x IS A " <> nestedP depth "a"
    , "GIVETH A " <> nestedP depth "a"
    , "idf x MEANS x"
    , ""
    , "ASSUME v IS A " <> nestedP depth "NUMBER"
    , ""
    ]
      <> [ "w" <> tshow i <> " MEANS idf v" | i <- [1 .. uses] ]

-- | How many times longer 'checksInLinearTime' lets the larger program take.
deepLimit :: Double
deepLimit = 8

-- | @checksInLinearTime small large limit program@: checking @program large@
-- takes less than @limit@ times the CPU time of checking @program small@, and
-- both are accepted. A ratio short of twice the limit is measured again, up
-- to twice, so that one pause does not fail it.
checksInLinearTime :: Int -> Int -> Double -> (Int -> Text) -> Expectation
checksInLinearTime smallSize largeSize limit program = do
  let timeCheck k = do
        src <- evaluate (program k)
        _ <- evaluate (Text.length src)
        t0 <- getCPUTime
        ok <- checks src
        t1 <- getCPUTime
        ok `shouldBe` True
        pure (fromIntegral (t1 - t0) :: Double)
      fastest k tries = minimum <$> traverse (const (timeCheck k)) [1 .. tries :: Int]
  small <- fastest smallSize 3
  let ratio large = large / max small 1.0e9
      settle tries = do
        r <- ratio <$> timeCheck largeSize
        if r < limit || r >= 2 * limit || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
  r <- settle 3
  r `shouldSatisfy` (< limit)

-- | @unifiesInLinearTime small large limit@: unifying a type nested on the
-- left @large@ deep with its instance at NUMBER takes less than @limit@
-- times the CPU time of doing so @small@ deep. Measured like
-- 'checksInLinearTime'.
unifiesInLinearTime :: Int -> Int -> Double -> Expectation
unifiesInLinearTime smallSize largeSize limit = do
  let timeUnify k = do
        let (t1, t2) = leftNestedPair k
        _ <- evaluate (typeSize t1 + typeSize t2)
        t0 <- getCPUTime
        let (errs, ok) = case runCheck (unify t1 t2) unifyEnv initialCheckState of
              [(w, _)] -> runWith w
              _        -> error "expected exactly one result"
        _ <- evaluate (length errs)
        _ <- evaluate ok
        t1' <- getCPUTime
        (null errs, ok) `shouldBe` (True, True)
        pure (fromIntegral (t1' - t0) :: Double)
      fastest k tries = minimum <$> traverse (const (timeUnify k)) [1 .. tries :: Int]
  small <- fastest smallSize 3
  let ratio large = large / max small 1.0e9
      settle tries = do
        r <- ratio <$> timeUnify largeSize
        if r < limit || r >= 2 * limit || tries <= (1 :: Int) then pure r else min r <$> settle (tries - 1)
  r <- settle 3
  r `shouldSatisfy` (< limit)

-- | The module the hand-built types below live in.
unifySpecUri :: NormalizedUri
unifySpecUri = toNormalizedUri (Uri "file:///unify-spec")

nominal :: Int -> Text -> Resolved
nominal k t = Def (MkUnique 't' k unifySpecUri) (MkName emptyAnno (NormalName t))

-- | A checker environment that knows the two type constructors 'leftNestedPair'
-- uses, @P@ (two parameters) and @NUMBER@.
unifyEnv :: CheckEnv
unifyEnv =
  (initialCheckEnv unifySpecUri)
    { entityInfo = Map.fromList
        [ (getUnique pName, (getOriginal pName, KnownType 2 [] Nothing))
        , (getUnique numName, (getOriginal numName, KnownType 0 [] Nothing))
        ]
    }

pName, numName :: Resolved
pName = nominal 1 "P"
numName = nominal 2 "NUMBER"

-- | @P OF (P OF (... (v), (v)) ..., (v)), (v)@, @d@ levels of @P@ deep, with
-- @v@ an inference variable on one side and NUMBER on the other.
leftNestedPair :: Int -> (Type' Resolved, Type' Resolved)
leftNestedPair d = (nest (InfVar emptyAnno (NormalName "a") 0), nest (TyApp emptyAnno numName []))
  where
    nest leaf = go d
      where
        go 0 = leaf
        go k = TyApp emptyAnno pName [go (k - 1 :: Int), leaf]

-- | The number of nodes in a type; forcing it builds the whole type.
typeSize :: Type' Resolved -> Int
typeSize = \ case
  TyApp _ _ ts -> 1 + sum (typeSize <$> ts)
  _            -> 1
