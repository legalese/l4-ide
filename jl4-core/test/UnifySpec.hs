{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module UnifySpec (spec) where

import Test.Hspec
import Control.Exception (evaluate)
import System.Timeout (timeout)
import Data.Text (Text)
import qualified Data.Text as Text
import L4.API.VirtualFS
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..))

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
      -- cycle evades declaration-time rejection and falls through to the
      -- expansion fuel (which, per-path, is the last line of defense).
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
      -- instead of driving matchFunTy's expansion loop (whose fuel
      -- remains as the backstop for cycles arriving via imports);
      -- pre-fix this hung forever.
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
      -- per-path expansion fuel and is reported as a mismatch rather than
      -- hanging. If this test starts failing because the budget changed,
      -- update the constant in the test name and move on.
      ok <- checks $ Text.unlines $
        synonymChain 1200
          <> [ ""
             , "GIVETH A S1200"
             , "x MEANS 42"
             ]
      ok `shouldBe` False

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
