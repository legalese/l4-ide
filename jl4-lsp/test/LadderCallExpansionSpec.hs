{-# LANGUAGE OverloadedRecordDot, OverloadedStrings, PatternSynonyms, TupleSections #-}
-- | Call expansions on the ladder's render path (WHERE-INLINING-SPEC §10).
--
-- A call leaf carries the called rule's body with the call's arguments put in
-- place of its parameters, translated in the CALLER's context. The identity rule
-- under test: two boxes are the same proposition exactly when they carry the
-- same atomId, and an inlined box is the same proposition as a direct one
-- exactly when, after substitution, they say the same thing about the same
-- inputs.
module LadderCallExpansionSpec (spec) where

import Control.Exception (evaluate)
import Data.List (nub)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Maybe (isJust)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath (takeDirectory, (</>))
import System.Timeout (timeout)

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Syntax (Decide, Resolved, foldTopLevelDecides)
import L4.TracePolicy (lspDefaultPolicy)
import qualified L4.Viz.VizExpr as V
import qualified LSP.Core.Shake as Shake
import LSP.L4.Actions (renderAfterInlining)
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)
import qualified LSP.L4.Viz.Ladder as Ladder
import qualified LSP.L4.Viz.QueryPlan as VizQueryPlan

import Test.Hspec

checkSource :: FilePath -> T.Text -> IO (VersionedTextDocumentIdentifier, TypeCheckResult)
checkSource path source = do
  createDirectoryIfMissing True (takeDirectory path)
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mRes) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure $ fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc
  maybe (fail "fixture did not type-check") pure mRes

scratch :: String -> IO FilePath
scratch stem = do
  tmp <- getTemporaryDirectory
  pure (tmp </> "jl4-ladder-call-expansion-spec" </> (stem <> ".l4"))

-- | What a client that asks for expansions gets (@l4.visualize@ with
-- @{"expandCalls": true}@; the "Show decision graph" lens does not ask):
-- expansions on, no simplification, atomIds annotated.
data Rendered = MkRendered
  { funDecl :: V.FunDecl
  , decide :: Decide Resolved
  , vizState :: Ladder.VizState
  }

-- | Every decision of the module, optionally with 'Transform.simplify' on, as
-- the IDE's own lens asks for. A leaf must be keyed alike either way: an expansion is
-- simplified on its own, and R3's "two copies of limb a b share every atom" has
-- to hold for whatever shape that leaves.
renderAllWith :: Bool -> String -> T.Text -> IO [Rendered]
renderAllWith simplify stem source = do
  path <- scratch stem
  (verId, tc) <- checkSource path source
  let cfg = Ladder.withCallExpansions (Ladder.mkVizConfig verId tc.module' tc.substitution simplify)
  pure
    [ MkRendered (VizQueryPlan.annotateLadderWithAtomIds info st).funDecl d st
    | d <- foldTopLevelDecides (\d -> [d]) tc.module'
    , Right (info, st) <- [Ladder.doVisualize d cfg]
    ]

render :: String -> T.Text -> T.Text -> IO Rendered
render = renderWith False

renderWith :: Bool -> String -> T.Text -> T.Text -> IO Rendered
renderWith simplify stem source target = do
  rs <- renderAllWith simplify stem source
  case [r | r <- rs, r.funDecl.fnName.label == target] of
    [r] -> pure r
    other -> fail ("expected one rule named " <> T.unpack target <> ", found " <> show (length other))

-- | Leaves drawn directly (an App's arguments included), not inside expansions.
directLeaves :: V.IRExpr -> [(T.Text, T.Text)]
directLeaves = \case
  V.And _ xs -> concatMap directLeaves xs
  V.Or _ xs -> concatMap directLeaves xs
  V.Not _ x -> directLeaves x
  V.Implies _ p q _ -> directLeaves p <> directLeaves q
  V.UBoolVar _ nm _ _ a _ _ -> [(nm.label, a)]
  V.App _ nm args a _ -> (nm.label, a) : concatMap directLeaves args
  _ -> []

-- | Every leaf, through every expansion.
allLeaves :: V.IRExpr -> [(T.Text, T.Text)]
allLeaves = \case
  V.And _ xs -> concatMap allLeaves xs
  V.Or _ xs -> concatMap allLeaves xs
  V.Not _ x -> allLeaves x
  V.Implies _ p q _ -> allLeaves p <> allLeaves q
  V.UBoolVar _ nm _ _ a _ x -> (nm.label, a) : foldMap allLeaves x
  V.App _ nm args a x -> (nm.label, a) : concatMap allLeaves args <> foldMap allLeaves x
  _ -> []

-- | The call leaves drawn directly, with their expansions.
calls :: V.IRExpr -> [(T.Text, Maybe V.IRExpr)]
calls = \case
  V.And _ xs -> concatMap calls xs
  V.Or _ xs -> concatMap calls xs
  V.Not _ x -> calls x
  V.Implies _ p q _ -> calls p <> calls q
  V.UBoolVar _ nm _ True _ _ x -> [(nm.label, x)]
  V.App _ nm args _ x -> (nm.label, x) : concatMap calls args
  _ -> []

expansionOf :: T.Text -> V.FunDecl -> IO V.IRExpr
expansionOf label fd = case [x | (l, x) <- calls fd.body, l == label] of
  [Just x] -> pure x
  other -> fail ("expected one expanded call " <> T.unpack label <> ", found " <> show (length other, map isJust other))

-- | How deep expansions nest.
expansionDepth :: V.IRExpr -> Int
expansionDepth = \case
  V.And _ xs -> maximum (0 : map expansionDepth xs)
  V.Or _ xs -> maximum (0 : map expansionDepth xs)
  V.Not _ x -> expansionDepth x
  V.Implies _ p q _ -> max (expansionDepth p) (expansionDepth q)
  V.UBoolVar _ _ _ _ _ _ x -> maybe 0 ((+ 1) . expansionDepth) x
  V.App _ _ args _ x -> maximum (maybe 0 ((+ 1) . expansionDepth) x : map expansionDepth args)
  _ -> 0

atomIdsOf :: T.Text -> [(T.Text, T.Text)] -> [T.Text]
atomIdsOf label ls = nub [a | (l, a) <- ls, l == label]

limb :: [T.Text]
limb =
  [ "GIVEN p IS A BOOLEAN"
  , "      q IS A BOOLEAN"
  , "DECIDE `limb` p q IF p AND q"
  , ""
  ]

-- | @leading@ inputs shift every resolver unique after them (as in
-- "LadderAtomIdSpec"), so a test that passes by a coincidence of numbering
-- fails under one of the two.
booleans :: [T.Text] -> [T.Text]
booleans [] = []
booleans (n : ns) = ("GIVEN " <> n <> " IS A BOOLEAN") : map (\m -> "      " <> m <> " IS A BOOLEAN") ns

caller :: [T.Text] -> T.Text -> [T.Text] -> [T.Text] -> T.Text
caller leading name inputs body =
  T.unlines $ limb <> booleans (leading <> inputs) <>
    ["DECIDE `" <> name <> "` " <> T.unwords (leading <> inputs) <> " IF"] <> body

creditworthy :: T.Text
creditworthy = T.unlines
  [ "DECLARE Person"
  , "  HAS `has stable income`   IS A BOOLEAN"
  , "      `has recent default`  IS A BOOLEAN"
  , "      `has collateral`      IS A BOOLEAN"
  , ""
  , "GIVEN p IS A Person"
  , "GIVETH A BOOLEAN"
  , "DECIDE `is creditworthy` p IF"
  , "      p's `has stable income`"
  , "  AND NOT p's `has recent default`"
  , ""
  , "GIVEN a IS A Person"
  , "GIVETH A BOOLEAN"
  , "DECIDE `record pass through` a IF"
  , "      `is creditworthy` a"
  , "  AND a's `has stable income`"
  , ""
  , "GIVEN a IS A Person"
  , "      b IS A Person"
  , "GIVETH A BOOLEAN"
  , "DECIDE `may lend jointly` a b IF"
  , "      `is creditworthy` a"
  , "  AND `is creditworthy` b"
  , "  AND (   a's `has collateral`"
  , "       OR b's `has collateral`"
  , "       OR `is creditworthy` a )"
  ]

spec :: Spec
spec = describe "call expansions on the ladder's render path (WHERE-INLINING-SPEC §10)" $ do
  let numberings =
        [ (name <> simplified, leading, simplify)
        | (name, leading) <- [("as written", []), ("shifted by one unused input", ["z"])]
        , (simplified, simplify) <- [("", False), (", simplified", True)]
        ]

  mapM_ (\(numbering, leading, simplify) -> describe numbering $ do
    let n = show (length leading) <> (if simplify then "s" else "")
        renderS = renderWith simplify

    it "(i) an argument inlined from `limb a b AND a` is the caller's own `a`" $ do
      r <- renderS ("pass-" <> n) (caller leading "pass through" ["a", "b"] ["      `limb` a b", "  AND a"]) "`pass through`"
      x <- expansionOf "limb OF a, b" r.funDecl
      let direct = [a | (V.UBoolVar _ nm _ _ a _ _) <- topConjuncts r.funDecl.body, nm.label == "a"]
      direct `shouldSatisfy` ((== 1) . length)
      atomIdsOf "a" (allLeaves x) `shouldBe` direct

    it "(ii) `limb a b AND limb c d`: the two expansions share no atomId" $ do
      r <- renderS ("diff-" <> n) (caller leading "different actuals" ["a", "b", "c", "d"] ["      `limb` a b", "  AND `limb` c d"]) "`different actuals`"
      x1 <- expansionOf "limb OF a, b" r.funDecl
      x2 <- expansionOf "limb OF c, d" r.funDecl
      let ids1 = map snd (allLeaves x1)
          ids2 = map snd (allLeaves x2)
      [i | i <- ids1, i `elem` ids2] `shouldBe` []
      map fst (allLeaves x1) `shouldBe` ["a", "b"]
      map fst (allLeaves x2) `shouldBe` ["c", "d"]

    it "(iii) `limb a b AND limb a b`: the two expansions are pairwise the same atoms" $ do
      r <- renderS ("same-" <> n) (caller leading "same actuals" ["a", "b"] ["      `limb` a b", "  AND `limb` a b"]) "`same actuals`"
      case [x | (l, Just x) <- calls r.funDecl.body, l == "limb OF a, b"] of
        [x1, x2] -> do
          allLeaves x1 `shouldBe` allLeaves x2
          length (allLeaves x1) `shouldBe` 2
        other -> expectationFailure ("expected two expanded calls, found " <> show (length other))
    ) numberings

  it "(iv) a record argument: the inlined `a's has stable income` links to the direct one" $ do
    r <- render "record" creditworthy "`record pass through`"
    x <- expansionOf "`is creditworthy` OF a" r.funDecl
    let inlined = [l | (l, _) <- allLeaves x]
    inlined `shouldSatisfy` all ("a's " `T.isPrefixOf`)
    let direct = atomIdsOf "a's `has stable income`" (directLeaves r.funDecl.body)
    direct `shouldSatisfy` ((== 1) . length)
    atomIdsOf "a's `has stable income`" (allLeaves x) `shouldBe` direct
    -- and the other inlined atom is a different proposition
    let recentDefault = atomIdsOf "a's `has recent default`" (allLeaves x)
    recentDefault `shouldSatisfy` ((== 1) . length)
    recentDefault `shouldSatisfy` all (`notElem` direct)

  it "(v) an all-BOOLEAN call (a V.App) has an expansion" $ do
    r <- render "app" (caller [] "pass through" ["a", "b"] ["      `limb` a b", "  AND a"]) "`pass through`"
    [isJust x | V.App _ nm _ _ x <- topConjuncts r.funDecl.body, nm.label == "limb OF a, b"] `shouldBe` [True]

  it "(vi) a recursive rule terminates and is expanded exactly one level" $ do
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A BOOLEAN"
          , "DECIDE `counts down` n IF"
          , "      n <= 0"
          , "   OR `counts down` (n - 1)"
          ]
    -- Under a timeout, so a guard that fails reports instead of hanging: the
    -- whole render runs inside it, since knowing that 'Ladder.doVisualize'
    -- succeeded already means translating every expansion.
    depth <- timeout 20000000 (render "recursive" src "`counts down`" >>= evaluate . expansionDepth . (.funDecl.body))
    depth `shouldBe` Just 1

  it "(vii) l4/inlineExprs keeps every atomId of the render path" $ do
    r <- render "joint" creditworthy "`may lend jointly`"
    let callUniques = [nm.unique | V.UBoolVar _ nm _ True _ _ _ <- universeIR r.funDecl.body, nm.label == "`is creditworthy` OF a"]
    u <- case callUniques of
      (u : _) -> pure u
      [] -> fail "no `is creditworthy` OF a call leaf"
    case renderAfterInlining r.vizState r.decide [u] of
      Left e -> expectationFailure (show e)
      Right (_, info, _, _) -> do
        let drawn = allLeaves r.funDecl.body
            unfolded = directLeaves info.funDecl.body
            -- untouched by the expand
            untouched = ["a's `has collateral`", "b's `has collateral`"]
        mapM_ (\l -> atomIdsOf l unfolded `shouldBe` atomIdsOf l drawn) untouched
        mapM_ (\l -> atomIdsOf l drawn `shouldSatisfy` ((== 1) . length)) untouched
        -- and what the expand drew directly is what the expansion drew inline
        atomIdsOf "a's `has stable income`" unfolded `shouldBe` atomIdsOf "a's `has stable income`" drawn

  it "(vii-b) l4/inlineExprs: two calls' copies of a callee's WHERE local are two propositions" $ do
    -- Unfolding copied the callee's body WITH its WHERE block, once per call, and
    -- each copy kept the local's one unique, so `big` from `ok x` and `big` from
    -- `ok y` were one atom though one means x > 3 and the other y > 3 (found by
    -- adversarial review of smucclaw/l4-ide#1013). The locals are inlined first now.
    let src = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A BOOLEAN"
          , "DECIDE `ok` n IF `big`"
          , "  WHERE `big` MEANS n GREATER THAN 3"
          , ""
          , "GIVEN x IS A NUMBER"
          , "      y IS A NUMBER"
          , "GIVETH A BOOLEAN"
          , "DECIDE `x qualifies and y does not` x y IF `ok` x AND NOT `ok` y"
          ]
    r <- render "inline-where" src "`x qualifies and y does not`"
    let callUniques = [nm.unique | V.UBoolVar _ nm _ True _ _ _ <- universeIR r.funDecl.body]
    callUniques `shouldSatisfy` (not . null)
    case renderAfterInlining r.vizState r.decide callUniques of
      Left e -> expectationFailure (show e)
      Right (_, info, _, _) -> do
        let ls = directLeaves info.funDecl.body
        length ls `shouldBe` 2
        length (nub (map snd ls)) `shouldBe` 2

  describe "(viii) a callee's WHERE definitions are inlined, not drawn as names (A1)" $ do
    -- A local name has ONE unique in every call of its rule and means something
    -- different in each. Drawn as a leaf keyed by its name, it linked
    -- propositions that are not the same; each case below did, measured on the
    -- wire 2026-10-05 (scratchpad ladder/attack-identity/, confrev-where.l4).
    let localNames = ["ok", "both", "helper OF b", "helper OF q", "p", "q", "r"]
        expansionLabels rr = nub [l | (Just x) <- map snd (calls rr.funDecl.body), (l, _) <- allLeaves x]

    it "`ok WHERE ok MEANS p`, called with a and with b: two propositions, each the caller's input" $ do
      let src = T.unlines $
            [ "GIVEN p IS A BOOLEAN"
            , "DECIDE `callee ok` p IF ok"
            , "  WHERE ok MEANS p"
            , ""
            ] <> booleans ["a", "b"] <>
            [ "DECIDE `two actuals` a b IF `callee ok` a AND `callee ok` b" ]
      r <- render "where-ok" src "`two actuals`"
      xa <- expansionOf "`callee ok` OF a" r.funDecl
      xb <- expansionOf "`callee ok` OF b" r.funDecl
      let directA = atomIdsOf "a" (directLeaves r.funDecl.body)
          directB = atomIdsOf "b" (directLeaves r.funDecl.body)
      directA `shouldSatisfy` ((== 1) . length)
      directB `shouldSatisfy` ((== 1) . length)
      allLeaves xa `shouldBe` map ("a",) directA
      allLeaves xb `shouldBe` map ("b",) directB

    it "a callee's local named like the caller's input is drawn as what it means, under its NOT" $ do
      let src = T.unlines $
            [ "GIVEN p IS A BOOLEAN"
            , "DECIDE contrary p IF a"
            , "  WHERE a MEANS NOT p"
            , ""
            ] <> booleans ["a"] <>
            [ "DECIDE `shadowing local` a IF contrary a OR a" ]
      r <- render "where-shadow" src "`shadowing local`"
      x <- expansionOf "contrary OF a" r.funDecl
      let direct = [i | (V.UBoolVar _ nm _ _ i _ _) <- topDisjuncts r.funDecl.body, nm.label == "a"]
      direct `shouldSatisfy` ((== 1) . length)
      case x of
        V.Not _ (V.UBoolVar _ nm _ _ i _ _) -> (nm.label, [i]) `shouldBe` ("a", direct)
        other -> expectationFailure ("expected NOT a, got " <> show other)

    it "caller and callee both define `both`, with different bodies: no expansion leaf is the caller's `both`" $ do
      let src = T.unlines $
            [ "GIVEN p IS A BOOLEAN"
            , "      q IS A BOOLEAN"
            , "DECIDE guarded p q IF both"
            , "  WHERE both MEANS p AND q"
            , ""
            ] <> booleans ["a", "b"] <>
            [ "DECIDE `two boths` a b IF guarded a b AND both"
            , "  WHERE both MEANS a OR b"
            ]
      r <- render "where-both" src "`two boths`"
      x <- expansionOf "guarded OF a, b" r.funDecl
      let callers = atomIdsOf "both" (directLeaves r.funDecl.body)
      callers `shouldSatisfy` ((== 1) . length)
      map fst (allLeaves x) `shouldBe` ["a", "b"]
      map snd (allLeaves x) `shouldSatisfy` all (`notElem` callers)

    it "two callees whose locals alias different fields of one record: different propositions" $ do
      let src = T.unlines
            [ "DECLARE Person"
            , "  HAS `is resident` IS A BOOLEAN"
            , "      `is adult`    IS A BOOLEAN"
            , ""
            , "GIVEN p IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `resident check` p IF ok"
            , "  WHERE ok MEANS p's `is resident`"
            , ""
            , "GIVEN p IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult check` p IF ok"
            , "  WHERE ok MEANS p's `is adult`"
            , ""
            , "GIVEN a IS A Person"
            , "GIVETH A BOOLEAN"
            , "DECIDE `two field locals` a IF `resident check` a AND `adult check` a"
            ]
      r <- render "where-fields" src "`two field locals`"
      xr <- expansionOf "`resident check` OF a" r.funDecl
      xa <- expansionOf "`adult check` OF a" r.funDecl
      map fst (allLeaves xr) `shouldBe` ["a's `is resident`"]
      map fst (allLeaves xa) `shouldBe` ["a's `is adult`"]
      [i | (_, i) <- allLeaves xr, i `elem` map snd (allLeaves xa)] `shouldBe` []

    it "a parameterised local is beta-reduced too: different actuals share only the shared input" $ do
      let src args2 = T.unlines $
            [ "GIVEN p IS A BOOLEAN"
            , "      q IS A BOOLEAN"
            , "DECIDE `guarded` p q IF both AND `helper` q"
            , "  WHERE"
            , "    both MEANS p AND q"
            , "    GIVEN r IS A BOOLEAN"
            , "    `helper` r MEANS p AND r"
            , ""
            ] <> booleans ["a", "b", "c", "d"] <>
            [ "DECIDE `two calls` a b c d IF"
            , "      `guarded` a b"
            , "  AND `guarded` " <> args2
            ]
      rDiff <- render "where-diff" (src "c b") "`two calls`"
      rSame <- render "where-same" (src "a b") "`two calls`"
      expansionLabels rDiff `shouldSatisfy` all (`notElem` localNames)
      expansionLabels rSame `shouldSatisfy` all (`notElem` localNames)
      case [x | (_, Just x) <- calls rDiff.funDecl.body] of
        [x1, x2] -> do
          let shared = nub [i | (_, i) <- allLeaves x1, i `elem` map snd (allLeaves x2)]
          shared `shouldBe` atomIdsOf "b" (directLeaves rDiff.funDecl.body)
          shared `shouldSatisfy` ((== 1) . length)
        other -> expectationFailure ("expected two expansions, found " <> show (length other))
      case [x | (_, Just x) <- calls rSame.funDecl.body] of
        [x1, x2] -> allLeaves x1 `shouldBe` allLeaves x2
        other -> expectationFailure ("expected two expansions, found " <> show (length other))

    it "a call whose body keeps a local binding (a recursive WHERE) is not expanded" $ do
      let src = T.unlines $
            [ "GIVEN p IS A BOOLEAN"
            , "DECIDE `loops` p IF spin"
            , "  WHERE spin MEANS p AND spin"
            , ""
            ] <> booleans ["a"] <>
            [ "DECIDE `calls a loop` a IF `loops` a AND a" ]
      r <- render "where-recursive" src "`calls a loop`"
      [x | (l, x) <- calls r.funDecl.body, l == "loops OF a"] `shouldBe` [Nothing]
      -- positive control: the same call to a body without the local IS expanded
      r' <- render "where-recursive-ctl" (T.replace "spin\n  WHERE spin MEANS p AND spin" "p" src) "`calls a loop`"
      [isJust x | (l, x) <- calls r'.funDecl.body, l == "loops OF a"] `shouldBe` [True]

  describe "atomIds of rules a callee reads (S5)" $ do
    -- That the rule's atomId survives a line added above it is pinned below. It
    -- used not to: a ref to a module rule that was not a plan variable rendered
    -- by its unique. An atomId is now the hash of the leaf's term, which names a
    -- module rule by its path (R3, "L4.Viz.AtomKey").
    let shadowSrc = T.unlines
          [ "DECIDE ready IF TRUE"
          , ""
          , "GIVEN p IS A BOOLEAN"
          , "DECIDE gate p IF p AND ready"
          , ""
          , "GIVEN a IS A BOOLEAN"
          , "      ready IS A BOOLEAN"
          , "DECIDE `shadow caller` a ready IF gate a AND ready"
          ]
        inlinedReady rr = do
          x <- expansionOf "gate OF a" rr.funDecl
          pure (atomIdsOf "ready" (allLeaves x))

    it "a caller's input that shadows the module's rule is not the rule the callee reads" $ do
      r <- render "global-shadow" shadowSrc "`shadow caller`"
      inlined <- inlinedReady r
      let direct = atomIdsOf "ready" (directLeaves r.funDecl.body)
      direct `shouldSatisfy` ((== 1) . length)
      inlined `shouldSatisfy` ((== 1) . length)
      inlined `shouldSatisfy` all (`notElem` direct)

    it "the module rule's atomId survives a line added above it" $ do
      r <- render "global-shadow" shadowSrc "`shadow caller`"
      r' <- render "global-shadow-shifted" (T.unlines ["GIVEN z IS A BOOLEAN", "DECIDE unrelated z IF z", ""] <> shadowSrc) "`shadow caller`"
      inlined <- inlinedReady r
      inlined' <- inlinedReady r'
      inlined `shouldSatisfy` ((== 1) . length)
      inlined' `shouldBe` inlined
      allLeaves r'.funDecl.body `shouldBe` allLeaves r.funDecl.body

    it "a call with a module rule as its argument has one atomId drawn directly and inside another call's expansion" $ do
      let src = T.unlines
            [ "GIVEN p IS A BOOLEAN"
            , "      q IS A BOOLEAN"
            , "DECIDE limb p q IF p AND q"
            , ""
            , "DECIDE `the season is open` IF TRUE"
            , ""
            , "GIVEN r IS A BOOLEAN"
            , "DECIDE wrap r IF limb `the season is open` r"
            , ""
            , "GIVEN a IS A BOOLEAN"
            , "DECIDE outer a IF limb `the season is open` a AND wrap a"
            ]
      r <- render "global-arg" src "outer"
      let label = "limb OF `the season is open`, a"
          ids = atomIdsOf label (allLeaves r.funDecl.body)
      length [() | (l, _) <- allLeaves r.funDecl.body, l == label] `shouldBe` 2
      ids `shouldSatisfy` ((== 1) . length)

  it "an expansion's atomIds do not move when a line is added above" $ do
    let src = T.unlines $
          [ "GIVEN p IS A BOOLEAN"
          , "      q IS A BOOLEAN"
          , "DECIDE c1 p q IF `helper` q"
          , "  WHERE"
          , "    GIVEN x IS A BOOLEAN"
          , "    `helper` x MEANS x AND p"
          , ""
          , "GIVEN p IS A BOOLEAN"
          , "      q IS A BOOLEAN"
          , "DECIDE c2 p q IF `helper` q"
          , "  WHERE"
          , "    GIVEN x IS A BOOLEAN"
          , "    `helper` x MEANS x AND NOT p"
          , ""
          ] <> booleans ["a", "b"] <>
          [ "DECIDE `two helpers` a b IF c1 a b AND c2 a b" ]
    r <- render "helper" src "`two helpers`"
    r' <- render "helper-shifted" (T.unlines ["GIVEN z IS A BOOLEAN", "DECIDE unrelated z IF z", ""] <> src) "`two helpers`"
    allLeaves r.funDecl.body `shouldSatisfy` (not . null)
    allLeaves r'.funDecl.body `shouldBe` allLeaves r.funDecl.body

  it "expansions stop at the decision's node budget" $ do
    -- Each level calls the one below twice, so fully expanded the top call
    -- would draw 2^12 leaves: far past the budget.
    let level :: Int -> [T.Text]
        level 0 = ["GIVEN a IS A BOOLEAN", "      b IS A BOOLEAN", "DECIDE `r0` a b IF a AND b", ""]
        level k =
          [ "GIVEN a IS A BOOLEAN", "      b IS A BOOLEAN"
          , "DECIDE `r" <> T.pack (show k) <> "` a b IF `r" <> T.pack (show (k - 1)) <> "` a b OR `r" <> T.pack (show (k - 1)) <> "` b a"
          , "" ]
        src = T.unlines (concatMap level [0 .. 12])
    r <- render "budget" src "r12"
    let inExpansions = length (universeIR r.funDecl.body) - length (directUniverse r.funDecl.body)
    inExpansions `shouldSatisfy` (<= Ladder.expansionNodeBudget)
    inExpansions `shouldSatisfy` (> 0)
    -- some call somewhere was left unexpanded
    [() | V.App _ _ _ _ Nothing <- universeIR r.funDecl.body] `shouldSatisfy` (not . null)
    -- and the depth is uniform: both calls the rule makes are expanded, so the
    -- first in reading order did not eat the budget
    map (isJust . snd) (calls r.funDecl.body) `shouldBe` [True, True]

  describe "a call with named arguments is expanded as its positional call (smucclaw/l4-ide#1033, gap 1)" $ do
    let big = T.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A BOOLEAN"
          , "DECIDE `caller` IF"
          , "      `big` WITH k IS n"
          , "  AND `big` n"
          , ""
          , "GIVEN n IS A NUMBER"
          , "GIVETH A BOOLEAN"
          , "DECIDE `named alone` IF `big` WITH k IS n"
          , ""
          , "GIVEN k IS A NUMBER"
          , "GIVETH A BOOLEAN"
          , "DECIDE `big` k IF k > 3"
          ]

    it "the issue's repro: both spellings open, onto the same atoms" $ do
      r <- render "named-big" big "caller"
      named <- expansionOf "big WITH k IS n" r.funDecl
      positional <- expansionOf "big OF n" r.funDecl
      allLeaves named `shouldBe` allLeaves positional
      length (allLeaves named) `shouldBe` 1
      -- and the two call boxes are one atom, as R3 already keyed them
      atomIdsOf "big WITH k IS n" (directLeaves r.funDecl.body)
        `shouldBe` atomIdsOf "big OF n" (directLeaves r.funDecl.body)

    it "written alone, a named call opens" $ do
      r <- render "named-alone" big "`named alone`"
      x <- expansionOf "big WITH k IS n" r.funDecl
      length (allLeaves x) `shouldBe` 1

    it "an all-BOOLEAN named call, arguments out of order: each is put in for the parameter it names" $ do
      let src = caller [] "named limb" ["a", "b"]
            [ "      `limb` WITH q IS b, p IS a"
            , "  AND a"
            , "  AND b"
            ]
      r <- render "named-limb" src "`named limb`"
      case [(nm.label, args, x) | V.App _ nm args _ x <- topConjuncts r.funDecl.body] of
        [(label, args, Just x)] -> do
          label `shouldSatisfy` ("limb WITH" `T.isPrefixOf`)
          -- the argument boxes are drawn as written: q's first
          map fst (concatMap directLeaves args) `shouldBe` ["b", "a"]
          -- the expansion is p AND q with p := a and q := b, each the caller's own
          map fst (allLeaves x) `shouldBe` ["a", "b"]
          map snd (allLeaves x) `shouldBe` (atomIdsOf "a" (directLeaves r.funDecl.body) <> atomIdsOf "b" (directLeaves r.funDecl.body))
        other -> expectationFailure ("expected one expanded limb call, found " <> show (length other))

    it "a named call and the positional call it stands for share their atomId; the swapped call does not" $ do
      let src = caller [] "named and swapped" ["a", "b"]
            [ "      `limb` WITH q IS b, p IS a"
            , "  AND `limb` a b"
            , "  AND `limb` WITH q IS a, p IS b"
            ]
      r <- render "named-swapped" src "`named and swapped`"
      case [(nm.label, i) | V.App _ nm _ i _ <- topConjuncts r.funDecl.body] of
        [(_, named), (_, positional), (_, swapped)] -> do
          named `shouldBe` positional
          swapped `shouldNotBe` positional
        other -> expectationFailure ("expected three calls, found " <> show (length other))

    it "l4/inlineExprs unfolds a named call leaf" $ do
      r <- render "named-inline" big "`named alone`"
      x <- expansionOf "big WITH k IS n" r.funDecl
      let callUniques = [nm.unique | V.UBoolVar _ nm _ True _ _ _ <- universeIR r.funDecl.body]
      callUniques `shouldSatisfy` ((== 1) . length)
      case renderAfterInlining r.vizState r.decide callUniques of
        Left e -> expectationFailure (show e)
        Right (_, info, _, _) -> directLeaves info.funDecl.body `shouldBe` allLeaves x

    it "a WHERE helper called by name is keyed as its unfolding, as one called positionally is" $ do
      let src spelling = T.unlines
            [ "GIVEN x IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "DECIDE `local helper` x IF " <> spelling <> " OR x > 3"
            , "  WHERE"
            , "    GIVEN r IS A NUMBER"
            , "    `helper` r MEANS r > 3"
            ]
      -- parenthesised: a WITH argument runs to the end of the line, OR included
      rNamed <- render "named-local" (src "(`helper` WITH r IS x)") "`local helper`"
      rPositional <- render "positional-local" (src "(`helper` x)") "`local helper`"
      let ids rr = nub (map snd (directLeaves rr.funDecl.body))
      ids rNamed `shouldSatisfy` ((== 1) . length)
      ids rNamed `shouldBe` ids rPositional

  it "the wire omits `expansion` when a leaf has none" $ do
    r <- render "wire" (caller [] "pass through" ["a", "b"] ["      `limb` a b", "  AND a"]) "`pass through`"
    let direct = [e | e@(V.UBoolVar _ nm _ _ _ _ _) <- topConjuncts r.funDecl.body, nm.label == "a"]
    map (T.isInfixOf "expansion" . T.pack . BL.unpack . Aeson.encode) direct `shouldBe` [False]
    -- and carries it when it has one
    [T.isInfixOf "\"expansion\"" (T.pack (BL.unpack (Aeson.encode e))) | e@(V.App _ nm _ _ _) <- topConjuncts r.funDecl.body, nm.label == "limb OF a, b"] `shouldBe` [True]
  where
    topConjuncts = \case
      V.And _ xs -> xs
      e -> [e]
    topDisjuncts = \case
      V.Or _ xs -> xs
      e -> [e]

-- | Every node drawn directly: through App arguments, not into expansions.
directUniverse :: V.IRExpr -> [V.IRExpr]
directUniverse e = e : case e of
  V.And _ xs -> concatMap directUniverse xs
  V.Or _ xs -> concatMap directUniverse xs
  V.Not _ x -> directUniverse x
  V.Implies _ p q _ -> directUniverse p <> directUniverse q
  V.App _ _ args _ _ -> concatMap directUniverse args
  _ -> []

-- | Every node, through App arguments and expansions.
universeIR :: V.IRExpr -> [V.IRExpr]
universeIR e = e : case e of
  V.And _ xs -> concatMap universeIR xs
  V.Or _ xs -> concatMap universeIR xs
  V.Not _ x -> universeIR x
  V.Implies _ p q _ -> universeIR p <> universeIR q
  V.UBoolVar _ _ _ _ _ _ x -> foldMap universeIR x
  V.App _ _ args _ x -> concatMap universeIR args <> foldMap universeIR x
  _ -> []
