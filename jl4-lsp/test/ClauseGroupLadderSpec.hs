{-# LANGUAGE OverloadedRecordDot #-}
-- | A BOOLEAN rule written as DECIDE clauses is drawn, in the editor's ladder
-- and in the core one, as the CONSIDER it stands for.
--
-- The desugarer compiles clauses to CONSIDERs, and to LETs that hold the
-- clauses not yet tried; none of them has a source range. Both ladders read the
-- generated LETs through, prune what earlier clauses settled, and join the
-- CONSIDERs on one input, so that the group is the CONSIDER a drafter would
-- write. These ladders draw a CONSIDER as one box whose atomId hashes its
-- printed text, so each hand-written form is the CONSIDER as the clauses read
-- through, nested where a table's rows are, and the two must print and be named
-- alike.
module ClauseGroupLadderSpec (spec) where

import Control.Exception (evaluate)
import Data.Foldable (for_)
import System.Timeout (timeout)
import qualified Data.Text as T

import Language.LSP.Protocol.Types (CodeLens (..), Command (..), VersionedTextDocumentIdentifier (..), toNormalizedUri)

import L4.Syntax
  ( AppForm (..)
  , Decide (..)
  , Expr
  , Module (..)
  , Resolved
  , Section (..)
  , TopDecl (..)
  , getOriginal
  , rawName
  , rawNameToText
  )
import qualified L4.Viz.Ladder as Core
import qualified L4.Viz.VizExpr as V
import qualified L4.Transform as Transform (holdsGeneratedNodes)
import LSP.L4.Actions (decisionGraphCodeLenses)
import qualified LSP.L4.Viz.Ladder as Ladder
import LSP.L4.Rules (TypeCheckResult (..))

import CheckSource (checkSource)

import Test.Hspec

-- | Each leaf of a ladder, as its label and atomId, in drawing order.
leaves :: V.IRExpr -> [(T.Text, T.Text)]
leaves = \ case
  V.And _ xs           -> concatMap leaves xs
  V.Or _ xs            -> concatMap leaves xs
  V.Not _ x            -> leaves x
  V.UBoolVar _ n _ _ a _ _ -> [(n.label, a)]
  V.App _ n xs a _     -> (n.label, a) : concatMap leaves xs
  _                    -> []

-- | The top-level definition called @rule@.
ruleOf :: TypeCheckResult -> Decide Resolved
ruleOf tc = case [ d | d@(MkDecide _ _ (MkAppForm _ n _ _) _) <- go section, textOf n == "rule" ] of
  d : _ -> d
  []    -> error "no rule called rule"
  where
    MkModule _ _ section = tc.module'
    go (MkSection _ _ _ _ decls) = concatMap top decls
    top = \ case
      Decide _ d -> [d]
      Section _ s -> go s
      _           -> []
    textOf = rawNameToText . rawName . getOriginal

-- | The editor's ladder of @rule@, as the editor asks for it (not simplified),
-- or the message it refuses with.
ideLadder :: VersionedTextDocumentIdentifier -> TypeCheckResult -> Either T.Text V.FunDecl
ideLadder = ideLadderWith False

-- | The same, simplified or not. @jl4-service@ simplifies the ladder it plans from.
ideLadderWith :: Bool -> VersionedTextDocumentIdentifier -> TypeCheckResult -> Either T.Text V.FunDecl
ideLadderWith simplify verId tc =
  either (Left . Ladder.prettyPrintVizError) (Right . (.funDecl) . fst)
    (Ladder.doVisualize (ruleOf tc) (Ladder.mkVizConfig verId tc.module' tc.substitution simplify))

-- | The core ladder of @rule@ (the REPL's and the browser's), or the message
-- it refuses with.
coreLadder :: VersionedTextDocumentIdentifier -> TypeCheckResult -> Either T.Text V.FunDecl
coreLadder = coreLadderWith False

-- | The same, simplified or not.
coreLadderWith :: Bool -> VersionedTextDocumentIdentifier -> TypeCheckResult -> Either T.Text V.FunDecl
coreLadderWith simplify verId tc =
  either (Left . Core.prettyPrintVizError) (Right . (.funDecl))
    (Core.visualizeByName (toNormalizedUri verId._uri) "" 0 tc.module' tc.substitution simplify "rule")

-- | Check a source, under its own stem, so that two sources are two documents.
check :: String -> T.Text -> IO (VersionedTextDocumentIdentifier, TypeCheckResult)
check = checkSource

-- | Both ladders of a rule written as clauses, and of its hand-written form,
-- draw the same leaves, named alike, and the clauses' leaves name nothing the
-- desugarer made up.
sameAsHandWritten :: String -> T.Text -> T.Text -> Spec
sameAsHandWritten name clauses hand =
  it ("draws as its hand-written CONSIDER, in the editor and the core ladder: " <> name) $ do
    (verC, tcC) <- check ("cg-" <> name) clauses
    (verH, tcH) <- check ("hw-" <> name) hand
    case (ideLadder verC tcC, ideLadder verH tcH) of
      (Right c, Right h) -> do
        leaves c.body `shouldBe` leaves h.body
        for_ (map fst (leaves c.body)) \ label ->
          for_ ["the result of", "input 1", "__pm_", "LET"] \ g ->
            (g, g `T.isInfixOf` label) `shouldBe` (g, False)
      (c, h) -> expectationFailure ("editor ladder: " <> outcome c <> " / hand-written: " <> outcome h)
    case (coreLadder verC tcC, coreLadder verH tcH) of
      (Right c, Right h) -> leaves c.body `shouldBe` leaves h.body
      (c, h) -> expectationFailure ("core ladder: " <> outcome c <> " / hand-written: " <> outcome h)
  where
    outcome = either T.unpack (const "drawn")

spec :: Spec
spec = describe "a BOOLEAN rule written as DECIDE clauses" $ do
  sameAsHandWritten "enum"
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "GIVETH A BOOLEAN"
      , "DECIDE rule Red IS TRUE", "DECIDE rule Green IS FALSE", "DECIDE rule Blue IS FALSE" ])
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "GIVETH A BOOLEAN"
      , "DECIDE rule c IS", "  CONSIDER c", "    WHEN Red THEN TRUE", "    WHEN Green THEN FALSE", "    WHEN Blue THEN FALSE" ])

  -- Rows that share an earlier column: the desugarer tests it again in every
  -- later clause, and the ladder reads each test with what the branches around
  -- it already decided.
  sameAsHandWritten "table"
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
      , "DECIDE rule Red TRUE IS TRUE", "DECIDE rule Red FALSE IS FALSE"
      , "DECIDE rule Green b IS b", "DECIDE rule Blue b IS NOT b" ])
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
      , "DECIDE rule c b IS", "  CONSIDER c"
      , "    WHEN Red THEN", "      CONSIDER b", "        WHEN TRUE THEN TRUE", "        WHEN FALSE THEN FALSE"
      , "    WHEN Green THEN b", "    WHEN Blue THEN NOT b" ])

  -- `EXACTLY Blue` is settled as `Blue` is, once the checker has stamped
  -- `Blue` a constructor.
  sameAsHandWritten "exactly"
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
      , "DECIDE rule (EXACTLY Blue) TRUE IS TRUE", "DECIDE rule (EXACTLY Blue) FALSE IS FALSE"
      , "DECIDE rule c b IS b" ])
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
      , "DECIDE rule c b IS", "  CONSIDER c"
      , "    WHEN EXACTLY Blue THEN", "      CONSIDER b", "        WHEN TRUE THEN TRUE", "        WHEN FALSE THEN FALSE", "        OTHERWISE b"
      , "    OTHERWISE b" ])

  -- A last clause whose pattern is a new name is the OTHERWISE.
  sameAsHandWritten "newname"
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "      a IS A BOOLEAN", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
      , "DECIDE rule Red a b IS a", "DECIDE rule Green a b IS b", "DECIDE rule other a b IS a AND b" ])
    (T.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
      , "GIVEN c IS A Colour", "      a IS A BOOLEAN", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
      , "DECIDE rule c a b IS", "  CONSIDER c"
      , "    WHEN Red THEN a", "    WHEN Green THEN b", "    OTHERWISE a AND b" ])

  -- Clauses whose CONSIDER, written out, would be more than 20,000 parts: both
  -- ladders refuse them, saying why, and do not draw the generated LETs as one
  -- leaf that asks nothing.
  it "refuses clauses too long to read through, in both ladders, naming why" $ do
    (ver, tc) <- check "too-long" tooLong
    either id (const "drawn") (ideLadder ver tc) `shouldSatisfy` ("too long to draw" `T.isInfixOf`)
    either id (const "drawn") (coreLadder ver tc) `shouldSatisfy` ("too long to draw" `T.isInfixOf`)

  -- A group whose first clause names each of its inputs as the GIVEN does (or is
  -- `_`) has nothing to read through: the clauses after it are never reached,
  -- and the body is that clause's result, as a rule written without clauses has
  -- it. `main` draws such a rule however long its result is, so both ladders
  -- do. The limits on clauses guard the reading through, which such a group
  -- does not do. A first clause that matches every input through a new name
  -- does not qualify (see the next block).
  describe "catch-all: a group whose first clause names each input as the GIVEN does" $ do
    -- The premise of the rest: the desugarer generates nothing for such a group
    -- (the clauses after the first are checked and dropped), where a group that
    -- tests its input generates CONSIDERs and LETs, and what a drafter wrote is
    -- never taken for generated.
    it "holds no node the desugarer generated, where a group that tests its input does" $ do
      (_, tcCatchAll) <- check "premise-catchall" (catchAllDnf 3 True)
      (_, tcGroup) <- check "premise-group" colourGroup
      (_, tcTable) <- check "premise-table" colourTable
      (_, tcByHand) <- check "premise-by-hand" colourByHand
      (_, tcNewName) <- check "premise-new-name" (newNameDnf 3)
      (_, tcExactly) <- check "premise-exactly" (T.replace "DECIDE rule n " "DECIDE rule (EXACTLY n) " (catchAllDnf 3 True))
      map (Transform.holdsGeneratedNodes . bodyOf) [tcCatchAll, tcGroup, tcTable, tcByHand, tcNewName, tcExactly]
        `shouldBe` [False, True, True, False, True, True]
    it "is drawn in both ladders when its simplified ladder is more than 300 boxes" $ do
      (ver, tc) <- check "catchall-dnf" (catchAllDnf 6 True)
      (verH, tcH) <- check "catchall-dnf-by-hand" (catchAllDnf 6 False)
      -- the premise: the rule, drawn as it is written, is more than 300 boxes
      either T.unpack (\ f -> show (V.irExceeds 300 f.body)) (ideLadderWith True verH tcH) `shouldBe` "True"
      either T.unpack (\ f -> show (V.irExceeds 300 f.body)) (coreLadderWith True verH tcH) `shouldBe` "True"
      -- and the group draws as it does
      fmap (leaves . (.body)) (ideLadderWith True ver tc) `shouldBe` fmap (leaves . (.body)) (ideLadderWith True verH tcH)
      fmap (leaves . (.body)) (coreLadderWith True ver tc) `shouldBe` fmap (leaves . (.body)) (coreLadderWith True verH tcH)
    it "is drawn in both ladders when its result is more than 20000 parts long" $ do
      (ver, tc) <- check "catchall-huge" catchAllHuge
      either id (const "drawn") (ideLadder ver tc) `shouldBe` "drawn"
      either id (const "drawn") (coreLadder ver tc) `shouldBe` "drawn"
    it "keeps its lens, titled as an ordinary rule's is" $ do
      (ver, tc) <- check "lens-catchall-huge" (catchAllHuge <> smallRule)
      lensTitles ver tc `shouldBe` ["Show decision graph", "Show decision graph"]

  -- A first clause that matches every input through a NEW name is a test the
  -- desugarer generates, with the clauses after it as the other answer, so it is
  -- read through and limited like any group. `main` answers such a group with
  -- "Can only visualize, as a ladder diagram, a DECIDE that returns a boolean",
  -- so neither side draws it; these pin what this branch says.
  describe "a group whose first clause gives an input a new name" $ do
    it "is refused as too long, in both ladders, when its result is more than 20000 parts long" $ do
      (ver, tc) <- check "newname-huge" newNameHuge
      either id (const "drawn") (ideLadder ver tc) `shouldSatisfy` ("too long to draw" `T.isInfixOf`)
      either id (const "drawn") (coreLadder ver tc) `shouldSatisfy` ("too long to draw" `T.isInfixOf`)
    it "keeps its lens, titled with why, when its result is more than 20000 parts long" $ do
      (ver, tc) <- check "lens-newname-huge" (newNameHuge <> smallRule)
      lensTitles ver tc `shouldBe` ["No decision graph: these clauses are too long to draw", "Show decision graph"]
    it "is drawn as written, but refused once simplified, when its simplified ladder is more than 300 boxes" $ do
      (ver, tc) <- check "newname-dnf-6" (newNameDnf 6 <> smallRule)
      either id (const "drawn") (ideLadderWith False ver tc) `shouldBe` "drawn"
      either id (const "drawn") (coreLadderWith False ver tc) `shouldBe` "drawn"
      either id (const "drawn") (ideLadderWith True ver tc) `shouldSatisfy` ("more than 300 boxes" `T.isInfixOf`)
      either id (const "drawn") (coreLadderWith True ver tc) `shouldSatisfy` ("more than 300 boxes" `T.isInfixOf`)
      -- the editor does not simplify, so it draws the group and keeps the ordinary lens
      lensTitles ver tc `shouldBe` ["Show decision graph", "Show decision graph"]
    it "is drawn, simplified too, when its simplified ladder is less than 300 boxes" $ do
      (ver, tc) <- check "newname-dnf-5" (newNameDnf 5)
      either id (const "drawn") (ideLadderWith True ver tc) `shouldBe` "drawn"
      either id (const "drawn") (coreLadderWith True ver tc) `shouldBe` "drawn"
    it "is refused in the editor too, with its lens saying so, when it is drawn as written with more than 300 boxes" $ do
      (ver, tc) <- check "newname-wide" (newNameWide 301 <> smallRule)
      either id (const "drawn") (ideLadder ver tc) `shouldSatisfy` ("more than 300 boxes" `T.isInfixOf`)
      either id (const "drawn") (coreLadder ver tc) `shouldSatisfy` ("more than 300 boxes" `T.isInfixOf`)
      lensTitles ver tc `shouldBe` ["No decision graph: these clauses would draw more than 300 boxes", "Show decision graph"]
    it "is not refused when it names each input as the GIVEN does, however many boxes it draws" $ do
      (ver, tc) <- check "ownname-wide" (newNameWide' "n" 301 <> smallRule)
      either id (const "drawn") (ideLadder ver tc) `shouldBe` "drawn"
      either id (const "drawn") (coreLadder ver tc) `shouldBe` "drawn"
      lensTitles ver tc `shouldBe` ["Show decision graph", "Show decision graph"]

  -- A table of optional inputs taken apart with `JUST`, with new names for the
  -- others, was refused only after a minute (24 clauses) or two (48): reading the
  -- clauses through rebuilt the clauses below a clause once for every name it
  -- bound. A renaming applied where a name is read does not, so such a table is
  -- refused as fast as one written with the GIVEN's names, and one that is drawn
  -- is drawn in about a second. The limit on the wait is far above that and far
  -- below the minute.
  describe "a table of optional inputs taken apart, with new names for the others" $ do
    it "is refused in both ladders, and its lens says so, within seconds, at 24 and at 48 clauses" $
      for_ [24, 48 :: Int] \ k -> do
        (ver, tc) <- check ("maybe-new-" <> show k) (maybeTable False k <> smallRule)
        answers <- within 8
          ([ refusalOrDrawn (ideLadder ver tc), refusalOrDrawn (coreLadder ver tc)
           , refusalOrDrawn (ideLadderWith True ver tc), refusalOrDrawn (coreLadderWith True ver tc)
           , T.intercalate " | " (lensTitles ver tc) ])
        case answers of
          Nothing -> expectationFailure (show k <> " clauses: no answer within 8 seconds")
          Just xs -> do
            take 4 xs `shouldSatisfy` all ("too long to draw" `T.isInfixOf`)
            drop 4 xs `shouldBe` ["No decision graph: these clauses are too long to draw | Show decision graph"]
    it "is still drawn at 8 clauses, with new names or with the GIVEN's, within seconds" $
      for_ [False, True] \ own -> do
        (ver, tc) <- check ("maybe-8-" <> show own) (maybeTable own 8 <> smallRule)
        answers <- within 8 [refusalOrDrawn (ideLadder ver tc), refusalOrDrawn (coreLadderWith True ver tc), T.intercalate " | " (lensTitles ver tc)]
        answers `shouldBe` Just ["drawn", "drawn", "Show decision graph | Show decision graph"]

  -- A rule written as clauses that is refused keeps its lens, titled with
  -- why: a lens that silently went missing would not tell its drafter anything.
  -- Clicking it answers with the whole message ('LSP.L4.Actions.visualise').
  describe "the decision-graph lens" $ do
    it "keeps the lens of clauses too long to draw, titled with the refusal, beside an ordinary one" $ do
      (ver, tc) <- check "lens-too-long" (tooLong <> smallRule)
      lensTitles ver tc `shouldBe` ["No decision graph: these clauses are too long to draw", "Show decision graph"]
    it "gives a rule that does not return a boolean no lens, however it is written" $ do
      (ver, tc) <- check "lens-number" (T.unlines ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "DECIDE f 0 IS 1", "DECIDE f n IS n"] <> smallRule)
      lensTitles ver tc `shouldBe` ["Show decision graph"]

-- | The answers, if each comes within @secs@ seconds (a minute's wait is far
-- longer, and is what this guards against). Each is waited for on its own: a
-- ladder takes about a second, and the lens is another ladder.
within :: Int -> [T.Text] -> IO (Maybe [T.Text])
within secs xs = sequence <$> mapM (\ x -> timeout (secs * 1000000) (evaluate (T.length x) >> pure x)) xs

-- | A ladder's refusal, or that it is drawn.
refusalOrDrawn :: Either T.Text a -> T.Text
refusalOrDrawn = either id (const "drawn")

-- | A table of @k@ clauses over five @MAYBE BOOLEAN@ inputs, each clause taking
-- three of them apart with @(JUST x)@ (inputs @i@, @i+1@, @i+2@, going round)
-- and returning the @AND@ of what it took apart. The other two inputs are given
-- new names, or, when @own@, are written as the @GIVEN@ names them. The last
-- clause names every input and is @IS FALSE@.
maybeTable :: Bool -> Int -> T.Text
maybeTable own k =
  T.unlines $
    ["@export Maybes"]
      <> [ (if c == 1 then "GIVEN " else "      ") <> "a" <> T.pack (show c) <> " IS A MAYBE BOOLEAN" | c <- [1 .. m] ]
      <> ["GIVETH A BOOLEAN"]
      <> [ "DECIDE rule " <> T.unwords [ pat i c | c <- [1 .. m] ] <> " IS " <> T.intercalate " AND " [ name i c | c <- taken i ] | i <- [1 .. k - 1] ]
      <> [ "DECIDE rule " <> T.unwords [ other k c | c <- [1 .. m] ] <> " IS FALSE" ]
  where
    m = 5 :: Int
    taken i = [ ((i + d - 1) `mod` m) + 1 | d <- [0 .. 2] ]
    name i c = "p" <> T.pack (show i) <> "c" <> T.pack (show c)
    other i c = if own then "a" <> T.pack (show c) else name i c
    pat i c = if c `elem` taken i then "(JUST " <> name i c <> ")" else other i c

-- | The titles of the decision-graph lenses of a module, top to bottom.
lensTitles :: VersionedTextDocumentIdentifier -> TypeCheckResult -> [T.Text]
lensTitles ver tc = [ c._title | CodeLens { _command = Just c } <- decisionGraphCodeLenses ver tc ]

-- | A small rule after the one under test, which is drawn.
smallRule :: T.Text
smallRule = T.unlines ["", "GIVEN a IS A BOOLEAN", "GIVETH A BOOLEAN", "DECIDE `small` a IS a"]

-- | Sixty rows of one NUMBER input, each a sum of two hundred ones: long, not
-- branching, and more than 20,000 parts written out (24,301).
tooLong :: T.Text
tooLong =
  T.unlines $
    ["GIVEN n IS A NUMBER", "GIVETH A BOOLEAN"]
      <> [ "DECIDE rule " <> T.pack (show i) <> " IS n" <> T.concat (replicate 200 " + 1") <> " GREATER THAN 0" | i <- [0 .. 59 :: Int] ]
      <> ["DECIDE rule n IS FALSE"]


-- | @k@ pairs of BOOLEAN inputs. The first clause names every input, so it
-- matches all of them, and the clause after it is never reached; its result is
-- a disjunction of conjunctions, whose conjunctive normal form is 449 boxes at
-- @k@ = 6. Without the second clause it is a rule written without clauses.
catchAllDnf :: Int -> Bool -> T.Text
catchAllDnf k withClauses =
  T.unlines $
    ["GIVEN n IS A NUMBER"]
      <> concat [ ["      a" <> j <> " IS A BOOLEAN", "      b" <> j <> " IS A BOOLEAN"] | j <- js ]
      <> ["GIVETH A BOOLEAN"]
      <> ["DECIDE rule n " <> inputs <> " IS " <> T.intercalate " OR " [ "(a" <> j <> " AND b" <> j <> ")" | j <- js ]]
      <> [ "DECIDE rule 0 " <> inputs <> " IS FALSE" | withClauses ]
  where
    js = [ T.pack (show i) | i <- [1 .. k] ]
    inputs = T.unwords (concat [ ["a" <> j, "b" <> j] | j <- js ])

-- | 'catchAllDnf' with the first clause's first input given a new name, @m@
-- for the @n@ of the @GIVEN@. A clause that does not name each of its inputs as
-- the @GIVEN@ does is not one that always matches: the desugarer reads it as a
-- test of @n@ with the clause after it as the other answer, so there is
-- something to read through.
newNameDnf :: Int -> T.Text
newNameDnf k = T.replace "DECIDE rule n " "DECIDE rule m " (catchAllDnf k True)

-- | A first clause that names its input and whose result is 22,000 parts or so:
-- more than the 20,000 that clauses are limited to when they are read through.
catchAllHuge :: T.Text
catchAllHuge =
  T.unlines
    [ "GIVEN n IS A NUMBER", "GIVETH A BOOLEAN"
    , "DECIDE rule n IS n" <> T.concat (replicate 11000 " + 1") <> " GREATER THAN 0"
    , "DECIDE rule 0 IS FALSE" ]

-- | 'catchAllHuge' with the first clause's input given a new name.
newNameHuge :: T.Text
newNameHuge = T.replace "DECIDE rule n IS n" "DECIDE rule m IS m" catchAllHuge

-- | A first clause that gives @n@ a new name, @m@, over @k@ BOOLEAN inputs
-- ANDed together: drawn as written it is @k@ atoms and an AND, so more than 300
-- boxes at @k@ = 301, and its conjunctive normal form is no larger.
newNameWide :: Int -> T.Text
newNameWide = newNameWide' "m"

-- | The same, with the name the first clause gives the @GIVEN@'s @n@: @n@ itself
-- names it as the @GIVEN@ does.
newNameWide' :: T.Text -> Int -> T.Text
newNameWide' first k =
  T.unlines $
    ["GIVEN n IS A NUMBER"]
      <> [ "      a" <> j <> " IS A BOOLEAN" | j <- js ]
      <> ["GIVETH A BOOLEAN"]
      <> ["DECIDE rule " <> first <> " " <> inputs <> " IS " <> T.intercalate " AND " [ "a" <> j | j <- js ]]
      <> ["DECIDE rule 0 " <> inputs <> " IS FALSE"]
  where
    js = [ T.pack (show i) | i <- [1 .. k] ]
    inputs = T.unwords [ "a" <> j | j <- js ]


-- | The body of @rule@, as checked.
bodyOf :: TypeCheckResult -> Expr Resolved
bodyOf tc = case ruleOf tc of MkDecide _ _ _ body -> body

colourGroup, colourTable, colourByHand :: T.Text
colourGroup = T.unlines
  [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
  , "GIVEN c IS A Colour", "GIVETH A BOOLEAN"
  , "DECIDE rule Red IS TRUE", "DECIDE rule Green IS FALSE", "DECIDE rule Blue IS FALSE" ]
colourTable = T.unlines
  [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
  , "GIVEN c IS A Colour", "      b IS A BOOLEAN", "GIVETH A BOOLEAN"
  , "DECIDE rule Red TRUE IS TRUE", "DECIDE rule Red FALSE IS FALSE"
  , "DECIDE rule Green b IS b", "DECIDE rule Blue b IS NOT b" ]
-- | A CONSIDER and a LET that the drafter wrote.
colourByHand = T.unlines
  [ "DECLARE Colour IS ONE OF Red, Green, Blue", ""
  , "GIVEN c IS A Colour", "GIVETH A BOOLEAN"
  , "DECIDE rule c IS"
  , "  LET warm BE TRUE"
  , "  IN CONSIDER c"
  , "       WHEN Red THEN warm", "       WHEN Green THEN FALSE", "       WHEN Blue THEN FALSE" ]
