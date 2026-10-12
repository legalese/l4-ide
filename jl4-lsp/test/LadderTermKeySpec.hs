{-# LANGUAGE OverloadedRecordDot, OverloadedStrings, PatternSynonyms, TupleSections #-}
-- | An atomId is the hash of its leaf's TERM (WHERE-INLINING-SPEC §10.1, ruling
-- R3; smucclaw/l4-ide#1013), not of what the leaf prints as.
--
-- What each case would catch, if the key were still the printed label:
--
-- * two mixfix calls that print alike sharing one atom (#1004);
-- * a callee's section @GIVEN@ seen through an expansion sharing an atom with
--   the caller's own input of the same name;
-- * an id moving when a declaration is added above, because some part of it was
--   a 'Unique';
-- * the diagram and the query plan, or the browser's ladder and the IDE's,
--   naming one atom two ways (smucclaw/l4-ide#935).
--
-- Distinctness is asserted, never key text: the key's spelling is not a
-- contract, and a same-named binder added later may renumber it.
module LadderTermKeySpec (spec) where

import Control.Monad (forM, forM_)
import qualified Data.IntMap.Strict as IntMap
import Data.List (nub, sort)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, getTemporaryDirectory, listDirectory)
import System.FilePath (takeDirectory, takeExtension, (</>))

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri, toNormalizedFilePath)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import qualified L4.Decision.QueryPlan as QP
import L4.Syntax (Module (..), foldTopLevelDecides)
import L4.TracePolicy (lspDefaultPolicy)
import qualified L4.Viz.AtomKey as AtomKey
import qualified L4.Viz.Ladder as CoreLadder
import qualified L4.Viz.VizExpr as V
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)
import qualified LSP.L4.Viz.Ladder as Ladder
import qualified LSP.L4.Viz.QueryPlan as VizQueryPlan

import Test.Hspec

checkSource :: String -> T.Text -> IO (VersionedTextDocumentIdentifier, TypeCheckResult)
checkSource stem source = do
  tmp <- getTemporaryDirectory
  let path = tmp </> "jl4-ladder-term-key-spec" </> (stem <> ".l4")
  createDirectoryIfMissing True (takeDirectory path)
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mRes) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure $ fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc
  maybe (fail ("fixture " <> stem <> " did not type-check")) pure mRes

data Opts = MkOpts { expand :: Bool, simplify :: Bool }

plain, expanded :: Opts
plain = MkOpts False False
expanded = MkOpts True False

-- | Every decision of a module, drawn by the IDE's ladder WITHOUT any atomId
-- reconciliation: the ids are the ones the ladder minted itself.
drawAll :: Opts -> VersionedTextDocumentIdentifier -> TypeCheckResult -> [(V.FunDecl, Ladder.VizState)]
drawAll opts verId tc =
  [ (info.funDecl, st)
  | d <- foldTopLevelDecides (\d -> [d]) tc.module'
  , Right (info, st) <- [Ladder.doVisualize d cfg]
  ]
  where
    cfg0 = Ladder.mkVizConfig verId tc.module' tc.substitution opts.simplify
    cfg = if opts.expand then Ladder.withCallExpansions cfg0 else cfg0

draw :: Opts -> String -> T.Text -> T.Text -> IO (V.FunDecl, Ladder.VizState)
draw opts stem source target = do
  (verId, tc) <- checkSource stem source
  case [r | r@(fd, _) <- drawAll opts verId tc, fd.fnName.label == target] of
    [r] -> pure r
    other -> fail ("expected one rule named " <> T.unpack target <> ", found " <> show (length other))

-- | A leaf: its label, its unique (the planner's variable), its atomId.
data Leaf = MkLeaf { label :: T.Text, unique :: Int, atomId :: T.Text }
  deriving (Eq, Ord, Show)

-- | Leaves drawn directly (an App's arguments included), not inside expansions.
directLeaves :: V.IRExpr -> [Leaf]
directLeaves = leavesWith False

-- | Every leaf, through every expansion.
allLeaves :: V.IRExpr -> [Leaf]
allLeaves = leavesWith True

leavesWith :: Bool -> V.IRExpr -> [Leaf]
leavesWith deep = go
  where
    go = \case
      V.And _ xs -> concatMap go xs
      V.Or _ xs -> concatMap go xs
      V.Not _ x -> go x
      V.Implies _ p q _ -> go p <> go q
      V.UBoolVar _ nm _ _ a _ x -> MkLeaf nm.label nm.unique a : inside x
      V.App _ nm args a x -> MkLeaf nm.label nm.unique a : concatMap go args <> inside x
      _ -> []
    inside x = if deep then foldMap go x else []

idsOf :: T.Text -> [Leaf] -> [T.Text]
idsOf l ls = nub [lf.atomId | lf <- ls, lf.label == l]

-- | The module the mixfix head-keyword collision was found in
-- (jl4/tests-cli/fixtures/batch-mixfix-shared-head.l4).
mixfixSharedHead :: T.Text
mixfixSharedHead = T.unlines
  [ "GIVEN w IS A NUMBER"
  , "      n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the will` w `is duly executed without` n MEANS w GREATER THAN n"
  , ""
  , "GIVEN w IS A NUMBER"
  , "      n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the will` w `is revoked counting` n MEANS w LESS THAN n"
  , ""
  , "GIVEN w IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `gift stands` w IS"
  , "  (`the will` w `is duly executed without` 3) AND NOT (`the will` w `is revoked counting` 3)"
  ]

-- | A callee reads its section's @GIVEN s@; the caller, in the same section,
-- has an input of its own named @s@ that shadows it.
sectionShadow :: T.Text
sectionShadow = T.unlines
  [ "§ `Shared`"
  , "    GIVEN s IS A BOOLEAN"
  , ""
  , "DECIDE `reads s` IF s"
  , ""
  , "GIVEN s IS A BOOLEAN"
  , "DECIDE `shadow caller` s IF `reads s` AND s"
  ]

-- | One of each kind of leaf: a comparison over a field, a Boolean field, a
-- section GIVEN, a rule that reads it, a call to a WHERE definition.
mixedLeaves :: T.Text
mixedLeaves = T.unlines
  [ "DECLARE Person HAS age IS A NUMBER"
  , "                   `is resident` IS A BOOLEAN"
  , ""
  , "§ `Shared`"
  , "    GIVEN `fee waived` IS A BOOLEAN"
  , ""
  , "DECIDE `waiver applies` IF `fee waived`"
  , ""
  , "GIVEN p IS A Person"
  , "      flag IS A BOOLEAN"
  , "DECIDE `eligible` p flag IF"
  , "      p's age AT LEAST 18"
  , "  AND p's `is resident`"
  , "  AND `waiver applies`"
  , "  AND `fee waived`"
  , "  AND `ok` flag"
  , "  WHERE"
  , "    GIVEN x IS A BOOLEAN"
  , "    `ok` x MEANS x OR NOT flag"
  ]

-- | Two callees whose bodies, once their locals are inlined and their
-- parameters put in, are the same text: @JSONDECODE s EQUALS JSONDECODE t@.
-- What tells them apart is the type each decodes into, which is an annotation.
jsonDecodeTypes :: T.Text
jsonDecodeTypes = T.unlines
  [ "DECLARE Summary HAS"
  , "  amount IS A NUMBER"
  , ""
  , "DECLARE Detail HAS"
  , "  amount IS A NUMBER"
  , "  note   IS A STRING"
  , ""
  , "GIVEN s IS A STRING"
  , "      t IS A STRING"
  , "GIVETH A BOOLEAN"
  , "DECIDE `the payloads agree in summary` s t IF a EQUALS b"
  , "  WHERE"
  , "    GIVETH AN EITHER STRING Summary"
  , "    a MEANS JSONDECODE s"
  , "    GIVETH AN EITHER STRING Summary"
  , "    b MEANS JSONDECODE t"
  , ""
  , "GIVEN s IS A STRING"
  , "      t IS A STRING"
  , "GIVETH A BOOLEAN"
  , "DECIDE `the payloads agree in detail` s t IF a EQUALS b"
  , "  WHERE"
  , "    GIVETH AN EITHER STRING Detail"
  , "    a MEANS JSONDECODE s"
  , "    GIVETH AN EITHER STRING Detail"
  , "    b MEANS JSONDECODE t"
  , ""
  , "GIVEN old IS A STRING"
  , "      new IS A STRING"
  , "GIVETH A BOOLEAN"
  , "DECIDE `only the note changed` old new IF"
  , "      `the payloads agree in summary` old new"
  , "  AND NOT `the payloads agree in detail` old new"
  ]

-- | A rule under a section heading, and the same with the heading renamed, and
-- with another section inserted above that re-parents it.
headedRule :: T.Text -> [T.Text] -> T.Text
headedRule heading above = T.unlines $ above <>
  [ "§ `" <> heading <> "`"
  , ""
  , "GIVEN a IS A BOOLEAN"
  , "      b IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE top IF a AND b"
  ]

-- | A caller that names a WHERE local, and a callee whose body, with its own
-- local put in, is the same proposition.
callerLocal :: T.Text
callerLocal = T.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `caller` n IF total GREATER THAN 3 AND `callee` n"
  , "  WHERE total MEANS n PLUS 1"
  , ""
  , "GIVEN x IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `callee` x IF total GREATER THAN 3"
  , "  WHERE total MEANS x PLUS 1"
  ]

-- | Two reads of the ledger on either side of a RECORD: one term, two values.
ledgerReads :: T.Text
ledgerReads = T.unlines
  [ "GIVETH A BOOLEAN"
  , "DECIDE top IF (RECALL `x`) EQUALS JUST 7 OR ((RECORD `x` IS 7) EQUALS 7 AND (RECALL `x`) EQUALS JUST 7)"
  ]

-- | One call that pins a section binder, written at the root and inside a rule
-- of another section: the WITH name resolves to a different binder in each.
withSupplies :: T.Text
withSupplies = T.unlines
  [ "§ `one`"
  , "    GIVEN foo IS A BOOLEAN"
  , ""
  , "GIVETH A BOOLEAN"
  , "DECIDE `reads foo` IF foo"
  , ""
  , "§ `two`"
  , "    GIVEN foo IS A BOOLEAN"
  , ""
  , "GIVEN b IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE `pins` b IF `reads foo` WITH foo IS b"
  , ""
  , "§ `three`"
  , "    GIVEN foo IS A BOOLEAN"
  , ""
  , "GIVEN b IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE `top` b IF (`reads foo` WITH foo IS b) OR `pins` b"
  ]

-- | Shifts every unique in the module that follows it.
unrelatedAbove :: T.Text
unrelatedAbove = T.unlines ["GIVEN z IS A BOOLEAN", "DECIDE unrelated z IF z", ""]

-- | The plan's atomId for each of its variables, and the ladder's own atomId on
-- the leaf of that unique, wherever they differ.
planDisagreements :: V.FunDecl -> Ladder.VizState -> [(Int, Maybe T.Text, T.Text)]
planDisagreements fd st =
  [ (u, Map.lookup u ladderIds, planId)
  | (u, planId) <- Map.toList (QP.atomIdByUnique fd.fnName.label cache)
  , Map.lookup u ladderIds /= Just planId
  ]
  where
    cache = VizQueryPlan.buildQueryPlanCache (V.MkRenderAsLadderInfo (V.MkVersionedDocId "" 0) fd) st
    ladderIds = Map.fromList [(lf.unique, lf.atomId) | lf <- allLeaves fd.body]

spec :: Spec
spec = describe "an atomId is the hash of its leaf's term (R3, smucclaw/l4-ide#1013)" $ do
  it "two mixfix calls that print alike are two atoms (smucclaw/l4-ide#1004)" $ do
    (fd, _) <- draw plain "mixfix" mixfixSharedHead "`gift stands`"
    let ls = directLeaves fd.body
    length ls `shouldBe` 2
    length (nub (map (.atomId) ls)) `shouldBe` 2

  it "a callee's section GIVEN, drawn inside its expansion, is not the caller's input of the same name" $ do
    (fd, _) <- draw expanded "section-shadow" sectionShadow "`shadow caller`"
    -- The label printer qualifies the section's binder ("Shared.s"), so the two
    -- do not print alike here; the ids must differ all the same.
    let direct = idsOf "s" (directLeaves fd.body)
        inlined = [lf.atomId | lf <- allLeaves fd.body, lf `notElem` directLeaves fd.body]
    direct `shouldSatisfy` ((== 1) . length)
    inlined `shouldSatisfy` ((== 1) . length)
    inlined `shouldSatisfy` all (`notElem` direct)

  it "two JSONDECODEs into different record types are two atoms, though they print alike" $ do
    (fd, _) <- draw expanded "json-decode" jsonDecodeTypes "`only the note changed`"
    let inlined = [lf | lf <- allLeaves fd.body, lf `notElem` directLeaves fd.body]
    length inlined `shouldBe` 2
    length (nub (map (.label) inlined)) `shouldBe` 1
    length (nub (map (.atomId) inlined)) `shouldBe` 2

  describe "no atomId moves when a declaration is added above, though every unique does" $
    forM_ [("plain", plain), ("with expansions", expanded), ("simplified", MkOpts True True)] \(name, opts) ->
      it name $ do
        (fd, _) <- draw opts "mixed" mixedLeaves "eligible"
        (fd', _) <- draw opts "mixed-shifted" (unrelatedAbove <> mixedLeaves) "eligible"
        let ls = allLeaves fd.body
            ls' = allLeaves fd'.body
        length ls `shouldSatisfy` (>= 5)
        -- positive control: the edit really did renumber the leaves
        map (.unique) ls' `shouldNotBe` map (.unique) ls
        map (\lf -> (lf.label, lf.atomId)) ls' `shouldBe` map (\lf -> (lf.label, lf.atomId)) ls

  it "no atomId moves when the rule's section heading is renamed, or a section is inserted above it" $ do
    let ids src = do
          (fd, _) <- draw plain "headed" src "top"
          pure [(lf.label, lf.atomId) | lf <- directLeaves fd.body]
    original <- ids (headedRule "Eligibilty" [])
    length original `shouldBe` 2
    ids (headedRule "Eligibility" []) >>= (`shouldBe` original)
    ids (headedRule "Eligibility" ["§ `Part 2`", "", "GIVETH A BOOLEAN", "DECIDE `a new rule` IF FALSE", ""]) >>= (`shouldBe` original)

  it "a caller's own WHERE local is keyed by what it means, as the callee's is in its expansion" $ do
    (fd, _) <- draw expanded "caller-local" callerLocal "caller"
    let direct = [lf | lf <- directLeaves fd.body, lf.label == "total GREATER THAN 3"]
        inlined = [lf | lf <- allLeaves fd.body, lf `notElem` directLeaves fd.body]
    map (.atomId) inlined `shouldBe` map (.atomId) direct
    length inlined `shouldBe` 1

  it "two reads of the ledger with a RECORD between them are two atoms (C1's fresh)" $ do
    (fd, _) <- draw plain "ledger-reads" ledgerReads "top"
    let recalls = [lf | lf <- directLeaves fd.body, "RECALL" `T.isInfixOf` lf.label]
    length recalls `shouldBe` 2
    length (nub (map (.atomId) recalls)) `shouldBe` 2

  it "a call that pins a section binder keys alike wherever it is written" $ do
    (fd, _) <- draw expanded "with-supplies" withSupplies "top"
    let pinned = [lf | lf <- allLeaves fd.body, "WITH" `T.isInfixOf` lf.label]
    length pinned `shouldBe` 2
    length (nub (map (.atomId) pinned)) `shouldBe` 1

  it "the query plan names every one of its atoms exactly as the diagram does" $ do
    forM_ [("mixfix", mixfixSharedHead), ("section-shadow", sectionShadow), ("mixed", mixedLeaves)] \(stem, src) -> do
      (verId, tc) <- checkSource ("plan-" <> stem) src
      forM_ [plain, expanded] \opts ->
        forM_ (drawAll opts verId tc) \(fd, st) ->
          planDisagreements fd st `shouldBe` []

  it "the browser's ladder (jl4-core) names every atom as the IDE's does" $ do
    forM_ [("mixfix", mixfixSharedHead), ("section-shadow", sectionShadow), ("mixed", mixedLeaves)] \(stem, src) -> do
      (verId, tc) <- checkSource ("core-" <> stem) src
      let MkModule _ uri _ = tc.module'
          drawn = drawAll plain verId tc
          -- jl4-core finds a decision by its PRINTED name, and two mixfix
          -- definitions sharing a head keyword print alike, so only a name that
          -- is unique in the module can be looked up there at all.
          names = map ((.fnName.label) . fst) drawn
          lookupable = [r | r@(fd, _) <- drawn, length (filter (== fd.fnName.label) names) == 1]
      lookupable `shouldSatisfy` (not . null)
      forM_ lookupable \(fd, _) ->
        case CoreLadder.visualizeByNameWithState uri "" 0 tc.module' tc.substitution False fd.fnName.label of
          Left err -> expectationFailure ("jl4-core could not draw " <> T.unpack fd.fnName.label <> ": " <> show err)
          Right (core, _) ->
            sort (map (\lf -> (lf.label, lf.atomId)) (directLeaves core.funDecl.body))
              `shouldBe` sort (map (\lf -> (lf.label, lf.atomId)) (directLeaves fd.body))

  -- Every name a leaf mentions must reach 'AtomKey.mkKeyEnv'. One it misses
  -- falls back to its unique: still a distinct key, but one that moves on an
  -- edit above, which is the failure this whole change exists to remove.
  it "across the corpus, every leaf is keyed, no key falls back to a unique, and the plan agrees" $ do
    files <- corpus ["../jl4/examples/ok", "../jl4/examples/legal"]
    length files `shouldSatisfy` (> 100)
    firstFile <- case files of
      f : _ -> pure f
      [] -> fail "no corpus found"
    evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
    (_, results) <- oneshotL4ActionAndErrors evalConfig firstFile \_ ->
      forM files \f -> do
        let nfp = toNormalizedFilePath f
            uri = normalizedFilePathToUri nfp
        _ <- Shake.addVirtualFileFromFS nfp
        mTc <- Shake.use TypeCheck uri
        pure (f, fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc)
    let checked = [(f, verId, tc) | (f, Just (verId, tc)) <- results, tc.success]
        problems =
          [ (f, fd.fnName.label, problem)
          | (f, verId, tc) <- checked
          -- with expansions on, every leaf the plain drawing has is drawn too,
          -- keyed the same way, so one pass covers both
          , (fd, st) <- drawAll expanded verId tc
          , let keys = Ladder.getLeafKeys st
          , problem <-
              [ "unkeyed leaf " <> lf.label | lf <- allLeaves fd.body, IntMap.notMember lf.unique keys ]
              <> [ "key falls back to a unique: " <> k | k <- IntMap.elems keys, AtomKey.unmappedMarker `T.isInfixOf` k ]
              <> [ "plan disagrees at " <> T.pack (show d) | d <- planDisagreements fd st ]
          ]
    length checked `shouldSatisfy` (> 100)
    take 20 problems `shouldBe` []

-- | Every @.l4@ file under the given directories, recursively.
corpus :: [FilePath] -> IO [FilePath]
corpus roots = concat <$> mapM walk roots
  where
    walk dir = do
      exists <- doesDirectoryExist dir
      if not exists
        then pure []
        else do
          entries <- sort <$> listDirectory dir
          concat <$> forM entries \e -> do
            let p = dir </> e
            isDir <- doesDirectoryExist p
            if isDir then walk p else pure [p | takeExtension p == ".l4"]
