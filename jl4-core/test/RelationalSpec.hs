{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Pure specs for the relational middle-end — the properties that a golden
-- cannot witness, because they are laws rather than outputs.
--
-- The file-based goldens live in @jl4-test@ ('RelationalExport'), which already
-- has @hspec-golden@, @Glob@, @filepath@ and @Paths_jl4@; this suite has none of
-- those and no way to locate @jl4\/examples\/@ at all, so hosting them here
-- would cost four dependencies plus a @..\/jl4\/examples@ relative path that is
-- correct only under cabal's package-root cwd and wrong in an sdist. The split
-- is deliberate.
--
-- Everything here calls the REAL functions. A spec that restates the algorithm
-- it is checking tests its own copy and drifts silently, which is why
-- 'L4.Relational.Lower' exports 'stratify' and 'buildDepGraph' rather than
-- leaving this file to re-derive them.
module RelationalSpec (spec) where

import Test.Hspec

import Data.List (sort)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import L4.API.VirtualFS (moduleNameToProjectUri)
import L4.Relational.IR
import L4.Relational.Lower (buildDepGraph, stratify)
import L4.Syntax (Unique (..))

spec :: Spec
spec = do
  describe "complementCmp" $ do
    -- This is the whole warrant for "NOT over a comparison never touches
    -- negation semantics" (BLAWX-EXPORT-SPEC §4.3): the rewrite is sound
    -- exactly because the operator table is a total involution. Asserting it is
    -- cheaper than believing it.
    it "is an involution" $
      mapM_ (\op -> complementCmp (complementCmp op) `shouldBe` op) allOps
    it "never maps an operator to itself" $
      mapM_ (\op -> complementCmp op `shouldNotBe` op) allOps
    it "pairs the order relations across the boundary" $ do
      complementCmp RLt `shouldBe` RGeq
      complementCmp RGt `shouldBe` RLeq
      complementCmp REq `shouldBe` RNeq

  describe "buildDepGraph" $ do
    it "signs an RNotCall negative and an RCall positive" $
      sortedEdges (buildDepGraph [pred_ "p" [clause [RCall (nm "q") [], RNotCall (nm "r") []] 0]])
        `shouldBe` [("p", "q", RPositive), ("p", "r", RNegative)]

    it "does NOT sign a goal negative merely for sitting in a materialised guard prefix" $ do
      -- The prefix is the lowering of ¬g, and NOT was pushed to the literals
      -- before it was built: whatever negation ¬g took is already inside these
      -- goals. A surviving call is a positive occurrence — `NOT (q x AT LEAST
      -- 5)` becomes `q(X, V), V < 5`, which needs q's value. Signing by position
      -- invented negative edges that were never in the source, and a negative
      -- edge invented inside a component is a stratified program reported as
      -- unstratified, which Blawx v1 rejects.
      sortedEdges (buildDepGraph [pred_ "p" [clause [RCall (nm "q") [], RCall (nm "r") []] 1]])
        `shouldBe` [("p", "q", RPositive), ("p", "r", RPositive)]

    it "signs a call negative when a later goal FALSIFIES its output" $
      -- The other half of that rule, and the reason the prefix rule looked right
      -- for so long: `NOT <computed boolean>` in a guard lowers to a call plus
      -- `V = FALSE`, not to an RNotCall, so the negation is visible only in the
      -- unification. This is the shape a Blawx emitter peepholes to `-p(A)`.
      sortedEdges
        ( buildDepGraph
            [ valued "q"
            , pred_ "p"
                [ clause [RCall (nm "q") [RTVar (var 0)], RUnify (var 0) (RTBool False)] 0 ]
            ]
        )
        `shouldBe` [("p", "q", RNegative)]

    it "leaves the same call positive when its output is asserted TRUE" $
      sortedEdges
        ( buildDepGraph
            [ valued "q"
            , pred_ "p"
                [ clause [RCall (nm "q") [RTVar (var 0)], RUnify (var 0) (RTBool True)] 0 ]
            ]
        )
        `shouldBe` [("p", "q", RPositive)]

    it "treats a projection as a positive dependency on its input predicate" $
      sortedEdges (buildDepGraph [pred_ "p" [clause [RProj (RTNum 1) (nm "f") (var 0)] 0]])
        `shouldBe` [("p", "f", RPositive)]

    it "signs a projection negative when its output is falsified" $
      -- `proj(A, isVeteran, V), V = FALSE` — the image of NOT over a projected
      -- boolean ("L4.Relational.IR", RUnify).
      sortedEdges
        ( buildDepGraph
            [ pred_ "p"
                [ clause [RProj (RTNum 1) (nm "f") (var 0), RUnify (var 0) (RTBool False)] 0 ]
            ]
        )
        `shouldBe` [("p", "f", RNegative)]

    it "reaches INSIDE a findall body, so a generator's callees are not invisible" $
      -- `sum (map (GIVEN i YIELD i's price) xs)` puts the membership generator
      -- and the projection inside the collection body. If those edges did not
      -- escape the RFindAll, a program whose only path to a predicate ran
      -- through an aggregate would be declared to depend on nothing — and the
      -- stratifier would then certify it on a graph missing the edge that
      -- mattered.
      sortedEdges
        ( buildDepGraph
            [ pred_ "p"
                [ clause [RFindAll (var 0) [RCall (nm "member") [], RProj (RTNum 1) (nm "f") (var 0)] (var 1)] 0 ]
            ]
        )
        `shouldBe` [("p", "f", RPositive), ("p", "member", RPositive)]

    it "gives an aggregation goal no edge of its own" $
      -- RAggregate reduces a list that some earlier goal already bound; it calls
      -- nothing, so it must not manufacture a dependency. The edge that matters
      -- came from whatever built the list.
      buildDepGraph [pred_ "p" [clause [RAggregate RSum (var 0) (var 1)] 0]] `shouldBe` []

  describe "stratify (Apt–Blair–Walker), recorded and not enforced" $ do
    it "puts a pure positive chain in one stratum" $
      strataOf [edge "p" "q" RPositive, edge "q" "r" RPositive]
        `shouldBe` Just [("p", 0), ("q", 0), ("r", 0)]

    it "lifts a caller one stratum above a negated callee" $
      strataOf [edge "p" "q" RNegative, edge "q" "r" RPositive]
        `shouldBe` Just [("p", 1), ("q", 0), ("r", 0)]

    it "stacks two negations" $
      strataOf [edge "p" "q" RNegative, edge "q" "r" RNegative]
        `shouldBe` Just [("p", 2), ("q", 1), ("r", 0)]

    it "admits a POSITIVE cycle" $
      -- Mutual positive recursion IS stratified — it is one stratum — which is
      -- why the check has to look for a negative edge inside a component rather
      -- than for a cycle.
      isStratified (stratOf [edge "p" "q" RPositive, edge "q" "p" RPositive])
        `shouldBe` True

    it "rejects a cycle THROUGH a negation, and names the component" $ do
      let s = stratOf [edge "p" "q" RNegative, edge "q" "p" RNegative]
      isStratified s `shouldBe` False
      case s of
        RUnstratified comps -> map (sort . map (.rnText)) comps `shouldBe` [["p", "q"]]
        RStratified _       -> expectationFailure "expected RUnstratified"

    it "rejects negation through a self-loop" $
      isStratified (stratOf [edge "p" "p" RNegative]) `shouldBe` False

    it "admits a POSITIVE self-loop — the shape every structural recursion has" $
      -- `running total([X|Xs], …) :- running total(Xs, …)` and the synthesised
      -- `member/2` both put a predicate in a one-element cycle with itself. That
      -- is stratified, and must stay so: if a positive self-edge tripped the
      -- check, admitting structural recursion would make every recursive module
      -- report NOT stratified and Blawx would reject its own seeds.
      isStratified (stratOf [edge "p" "p" RPositive]) `shouldBe` True

    it "has no error channel: the result is a value inside a successful lowering" $
      -- Turning non-stratification into a LowerError here would break the ASP
      -- leg before it exists (swipl rejects, Blawx rejects in v1, ASP treats it
      -- as the source of the multiple stable models that are the point).
      case stratOf [edge "p" "q" RNegative, edge "q" "p" RNegative] of
        RUnstratified _ -> pure ()
        RStratified _   -> expectationFailure "expected RUnstratified"
 where
  allOps = [RLt, RLeq, RGt, RGeq, REq, RNeq]

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | A fixture name whose 'Unique' is derived from the WHOLE text.
--
-- 'RName' identity is the 'Unique' alone, so a fixture that hashed only the
-- first character would make @member@ and @minimum@ — or @p@ and @price@, which
-- is the vocabulary of the RFindAll spec above — the same predicate, and
-- 'buildDepGraph' would fold two intended nodes into one. The assertion would
-- then read as a lowering bug. (It was also partial: @Text.head ""@ throws.)
nm :: Text -> RName
nm t = MkRName
  { rnText   = t
  , rnBase   = t
  , rnUnique = MkUnique { sort = 't', unique = hashText t, moduleUri = testUri }
  }
 where
  testUri = moduleNameToProjectUri "relational-spec"
  hashText = Text.foldl' (\acc c -> acc * 31 + fromEnum c) 7

var :: Int -> RVar
var i = MkRVar { rvId = i, rvHint = "V" }

edge :: Text -> Text -> RSign -> RDepEdge
edge f t s = MkRDepEdge { redFrom = nm f, redTo = nm t, redSign = s }

clause :: [RGoal] -> Int -> RClause
clause gs k = MkRClause
  { rcHead = [], rcBody = gs, rcGuardPrefix = k
  , rcProv = MkRProv { rpvUnique = (nm "x").rnUnique, rpvRange = Nothing }
  }

pred_ :: Text -> [RClause] -> RPred
pred_ n cs = MkRPred
  { rpName = nm n, rpKind = RComputed, rpParams = [], rpResult = Nothing
  , rpRecursion = RNonRecursive, rpClauses = cs, rpExported = False, rpDesc = Nothing
  , rpNlg = Nothing, rpRef = Nothing
  , rpProv = MkRProv { rpvUnique = (nm n).rnUnique, rpvRange = Nothing }
  }

-- | A clause-less predicate that DOES carry an output argument, which is what
-- tells 'buildDepGraph' that the last term of a call to it is a result and not
-- an input. A boolean goal ('pred_') has no output to falsify.
valued :: Text -> RPred
valued n = (pred_ n []) { rpResult = Just RSBool }

sortedEdges :: [RDepEdge] -> [(Text, Text, RSign)]
sortedEdges es = sort [ (e.redFrom.rnText, e.redTo.rnText, e.redSign) | e <- es ]

-- | The stratifier reads names off the predicates AND the edges, so a spec that
-- supplies only edges exercises exactly the graph it wrote.
stratOf :: [RDepEdge] -> RStratification
stratOf = stratify []

strataOf :: [RDepEdge] -> Maybe [(Text, Int)]
strataOf es = case stratOf es of
  RStratified m   -> Just (sort [ (n.rnText, v) | (n, v) <- Map.toList m ])
  RUnstratified _ -> Nothing
