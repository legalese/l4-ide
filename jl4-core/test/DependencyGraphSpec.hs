{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | Structure of the global dependency graph ('L4.DependencyGraph').
--
-- The cross-module test doubles as the referee for a contradiction the tree
-- used to carry: a comment in "L4.Export.Document" claimed a call site in the
-- importing module and the definition in a dependency do not share 'Unique's,
-- while 'L4.TypeCheck.Types.unionImportedCheckEnv' unions the dependency's
-- environment into the importer's, handing importer-side resolution the
-- dependency's own 'Unique'. The cross-module edge asserted below exists only
-- if the call-site @Ref@ carries the dependency's exact 'Unique' — so a green
-- run settles the question in favour of sharing.
module DependencyGraphSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.API.VirtualFS (VFS, checkWithImports, emptyVFS, vfsFromList)
import L4.DependencyGraph
import L4.Import.Resolution (TypeCheckWithDepsResult (..), ResolvedImport (..))
import L4.Syntax (Unique)
import L4.TypeCheck.Types (CheckResult (..))

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

buildFor :: VFS -> [Text] -> Either [Text] DepGraph
buildFor vfs src =
  case checkWithImports vfs (Text.unlines src) of
    Left errs -> Left errs
    Right r
      | r.tcdSuccess ->
          Right
            (buildDepGraph
               r.tcdEntityInfo
               r.tcdModule
               [ri.riTypeChecked.program | ri <- r.tcdResolvedImports])
      | otherwise -> Left (map (Text.pack . show) r.tcdErrors)

withGraphVFS :: VFS -> [Text] -> (DepGraph -> Expectation) -> Expectation
withGraphVFS vfs src k = case buildFor vfs src of
  Left errs -> expectationFailure (show errs)
  Right g -> k g

withGraph :: [Text] -> (DepGraph -> Expectation) -> Expectation
withGraph = withGraphVFS emptyVFS

-- | The unique node of the given kind and name; fails the test otherwise.
node :: DepGraph -> DepKind -> Text -> IO Unique
node g k nm =
  case [u | (u, i) <- Map.toList g.nodes, i.kind == k, i.name == nm] of
    [u] -> pure u
    us -> do
      expectationFailure
        ("expected exactly one " <> show k <> " node named "
           <> Text.unpack nm <> ", found " <> show (length us))
      pure (error "unreachable")

hasEdge :: DepGraph -> Unique -> Unique -> Bool
hasEdge g a b = Set.member b (edgesOf g a)

edgesOf :: DepGraph -> Unique -> Set.Set Unique
edgesOf g a = Map.findWithDefault Set.empty a g.edges

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

helperVFS :: VFS
helperVFS =
  vfsFromList
    [ ( "helper"
      , Text.unlines
          [ "GIVEN x IS A NUMBER"
          , "GIVETH A NUMBER"
          , "double x MEANS x * 2"
          ]
      )
    ]

crossModuleSrc :: [Text]
crossModuleSrc =
  [ "IMPORT helper"
  , "quadruple MEANS double 4"
  ]

recursionSrc :: [Text]
recursionSrc =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "loop n MEANS loop n"
  ]

mutualSrc :: [Text]
mutualSrc =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "ping n MEANS pong n"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "pong n MEANS ping n"
  ]

-- | The cycle the intra-record check in "L4.Desugar" cannot see: each record's
-- computed field reaches the other record's through a top-level definition.
crossRecordCycleSrc :: [Text]
crossRecordCycleSrc =
  [ "DECLARE RecA HAS"
  , "    baseA IS A NUMBER"
  , "    va IS A NUMBER"
  , "        MEANS vbOf"
  , "DECLARE RecB HAS"
  , "    baseB IS A NUMBER"
  , "    vb IS A NUMBER"
  , "        MEANS vaOf"
  , "vbOf MEANS someB's vb"
  , "vaOf MEANS someA's va"
  , "someA MEANS RecA WITH baseA IS 1"
  , "someB MEANS RecB WITH baseB IS 2"
  ]

projectionSrc :: [Text]
projectionSrc =
  [ "DECLARE Person HAS"
  , "    age IS A NUMBER"
  , "    adult IS A BOOLEAN"
  , "        MEANS age >= 18"
  , "alice MEANS Person WITH age IS 21"
  , "`stored read` MEANS alice's age"
  , "`proj read` MEANS alice's adult"
  , "`app read` MEANS adult OF alice"
  ]

paramsSrc :: [Text]
paramsSrc =
  [ "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "f x MEANS x + 1"
  ]

whereSrc :: [Text]
whereSrc =
  [ "g MEANS 5"
  , "f MEANS y + 1"
  , "  WHERE"
  , "    y MEANS g"
  ]

deadCodeSrc :: [Text]
deadCodeSrc =
  [ "live MEANS 1"
  , "`also live` MEANS live + 1"
  , "dead MEANS 2"
  , "#EVAL `also live`"
  ]

exportSrc :: [Text]
exportSrc =
  [ "@export the main entry"
  , "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "f x MEANS x + g"
  , "g MEANS 1"
  , "dead MEANS 2"
  ]

timezoneSrc :: [Text]
timezoneSrc =
  [ "tz MEANS \"Etc/UTC\""
  , "TIMEZONE IS tz"
  , "dead MEANS 2"
  ]

chainSrc :: [Text]
chainSrc =
  [ "c MEANS 1"
  , "b MEANS c + 1"
  , "a MEANS b + 1"
  ]

declareSrc :: [Text]
declareSrc =
  [ "DECLARE Color IS ONE OF Red, Green"
  , "DECLARE Person HAS"
  , "    age IS A NUMBER"
  , "ASSUME threshold IS A NUMBER"
  , "GIVEN p IS A Person"
  , "GIVETH A NUMBER"
  , "f p MEANS p's age + threshold"
  ]

--------------------------------------------------------------------------------
-- Spec
--------------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "cross-module identity" $ do
    it "resolves an imported call to the dependency's own Unique" $
      withGraphVFS helperVFS crossModuleSrc $ \g -> do
        quadU <- node g DepFunction "quadruple"
        dblU <- node g DepFunction "double"
        (g.nodes Map.! dblU).moduleUri `shouldNotBe` g.mainUri
        (g.nodes Map.! quadU).moduleUri `shouldBe` g.mainUri
        hasEdge g quadU dblU `shouldBe` True

    it "sees the importer from the dependency in the reverse slice" $
      withGraphVFS helperVFS crossModuleSrc $ \g -> do
        quadU <- node g DepFunction "quadruple"
        dblU <- node g DepFunction "double"
        Set.member quadU (closure (reverseEdges g) (Set.singleton dblU))
          `shouldBe` True

  describe "cycles" $ do
    it "keeps a direct recursion's self-edge and reports it as an SCC" $
      withGraph recursionSrc $ \g -> do
        loopU <- node g DepFunction "loop"
        hasEdge g loopU loopU `shouldBe` True
        cyclicSccs g `shouldBe` [[loopU]]

    it "reports mutual recursion as an SCC but not as a computed-field cycle" $
      withGraph mutualSrc $ \g -> do
        pingU <- node g DepFunction "ping"
        pongU <- node g DepFunction "pong"
        map Set.fromList (cyclicSccs g)
          `shouldBe` [Set.fromList [pingU, pongU]]
        computedFieldCycles g `shouldBe` []

    it "flags a cross-record cycle through computed fields" $
      withGraph crossRecordCycleSrc $ \g -> do
        vaU <- node g DepComputedField "va"
        vbU <- node g DepComputedField "vb"
        vaOfU <- node g DepFunction "vaOf"
        vbOfU <- node g DepFunction "vbOf"
        map Set.fromList (computedFieldCycles g)
          `shouldBe` [Set.fromList [vaU, vbU, vaOfU, vbOfU]]

  describe "projection edges" $ do
    it "gives x's f edges to both the selector and the receiver" $
      withGraph projectionSrc $ \g -> do
        rdU <- node g DepFunction "stored read"
        ageU <- node g DepSelector "age"
        aliceU <- node g DepFunction "alice"
        hasEdge g rdU ageU `shouldBe` True
        hasEdge g rdU aliceU `shouldBe` True

    it "covers both spellings of a computed-field read" $
      withGraph projectionSrc $ \g -> do
        adultU <- node g DepComputedField "adult"
        aliceU <- node g DepFunction "alice"
        projU <- node g DepFunction "proj read"
        appU <- node g DepFunction "app read"
        hasEdge g projU adultU `shouldBe` True
        hasEdge g projU aliceU `shouldBe` True
        hasEdge g appU adultU `shouldBe` True
        hasEdge g appU aliceU `shouldBe` True

  describe "binders" $ do
    it "gives GIVEN parameters neither nodes nor edges" $
      withGraph paramsSrc $ \g -> do
        fU <- node g DepFunction "f"
        Map.size g.nodes `shouldBe` 1
        edgesOf g fU `shouldBe` Set.empty

    it "neither mints a node for a WHERE local nor loses the global it references" $
      withGraph whereSrc $ \gr -> do
        fU <- node gr DepFunction "f"
        gU <- node gr DepFunction "g"
        Map.size gr.nodes `shouldBe` 2
        edgesOf gr fU `shouldBe` Set.singleton gU

  describe "entry points and reachability" $ do
    it "classifies a definition unreachable from the entry points as dead" $
      withGraph deadCodeSrc $ \g -> do
        liveU <- node g DepFunction "live"
        alsoU <- node g DepFunction "also live"
        deadU <- node g DepFunction "dead"
        ((EntryEval, alsoU) `elem` g.entryPoints) `shouldBe` True
        let reach = reachableFrom g RootsEntryPoints
        Set.member liveU reach `shouldBe` True
        Set.member alsoU reach `shouldBe` True
        Set.member deadU reach `shouldBe` False
        unreachableFrom g RootsEntryPoints `shouldBe` Set.singleton deadU

    it "treats the whole main module as roots under RootsMainModule" $
      withGraph deadCodeSrc $ \g ->
        unreachableFrom g RootsMainModule `shouldBe` Set.empty

    it "roots reachability at @export functions and harvests their description" $
      withGraph exportSrc $ \gr -> do
        fU <- node gr DepFunction "f"
        gU <- node gr DepFunction "g"
        deadU <- node gr DepFunction "dead"
        ((EntryExport, fU) `elem` gr.entryPoints) `shouldBe` True
        (gr.nodes Map.! fU).desc `shouldBe` Just "the main entry"
        let reach = reachableFrom gr RootsEntryPoints
        Set.member gU reach `shouldBe` True
        Set.member deadU reach `shouldBe` False

    it "keeps a definition alive that only TIMEZONE references" $
      withGraph timezoneSrc $ \g -> do
        tzU <- node g DepFunction "tz"
        deadU <- node g DepFunction "dead"
        ((EntryTimezone, tzU) `elem` g.entryPoints) `shouldBe` True
        let reach = reachableFrom g RootsEntryPoints
        Set.member tzU reach `shouldBe` True
        Set.member deadU reach `shouldBe` False

  describe "slices" $ do
    it "bounds a forward slice by depth and completes it unbounded" $
      withGraph chainSrc $ \g -> do
        aU <- node g DepFunction "a"
        bU <- node g DepFunction "b"
        cU <- node g DepFunction "c"
        closureUpTo (Just 0) g.edges (Set.singleton aU)
          `shouldBe` Set.fromList [aU]
        closureUpTo (Just 1) g.edges (Set.singleton aU)
          `shouldBe` Set.fromList [aU, bU]
        closure g.edges (Set.singleton aU)
          `shouldBe` Set.fromList [aU, bU, cU]
        closure (reverseEdges g) (Set.singleton cU)
          `shouldBe` Set.fromList [aU, bU, cU]

  describe "DECLARE structure" $ do
    it "mints kinds per the spec's node table" $
      withGraph declareSrc $ \g -> do
        _ <- node g DepConstructor "Color"
        _ <- node g DepConstructor "Red"
        _ <- node g DepConstructor "Green"
        _ <- node g DepSelector "age"
        _ <- node g DepAssume "threshold"
        _ <- node g DepFunction "f"
        -- Color, Red, Green, Person (type), Person (ctor), age, threshold, f
        Map.size g.nodes `shouldBe` 8

    it "keeps a record's schema reachable from its type, and points the constructor home" $
      withGraph declareSrc $ \g -> do
        ageU <- node g DepSelector "age"
        let persons =
              [ u
              | (u, i) <- Map.toList g.nodes
              , i.kind == DepConstructor
              , i.name == "Person"
              ]
        length persons `shouldBe` 2
        -- One node is the type (carries the schema edge to the selector), the
        -- other the constructor (points at the type); see the intra-DECLARE
        -- attribution note in the module haddock.
        [ ()
          | tyU <- persons
          , ctorU <- persons
          , tyU /= ctorU
          , hasEdge g tyU ageU
          , hasEdge g ctorU tyU
          ]
          `shouldBe` [()]

    it "keeps an enum's constructors reachable from its type" $
      withGraph declareSrc $ \g -> do
        colorU <- node g DepConstructor "Color"
        redU <- node g DepConstructor "Red"
        greenU <- node g DepConstructor "Green"
        hasEdge g colorU redU `shouldBe` True
        hasEdge g colorU greenU `shouldBe` True

    it "routes a GIVEN-typed projection to selector and assume, not to the parameter" $
      withGraph declareSrc $ \g -> do
        fU <- node g DepFunction "f"
        ageU <- node g DepSelector "age"
        thU <- node g DepAssume "threshold"
        hasEdge g fU ageU `shouldBe` True
        hasEdge g fU thU `shouldBe` True
        [i.name | i <- Map.elems g.nodes, i.name == "p"] `shouldBe` []
