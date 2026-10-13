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

import Data.Foldable (for_)
import qualified Data.Text as T

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), toNormalizedUri)

import L4.Syntax
  ( AppForm (..)
  , Decide (..)
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
  V.UBoolVar _ n _ _ a -> [(n.label, a)]
  V.App _ n xs a       -> (n.label, a) : concatMap leaves xs
  _                    -> []

-- | The top-level definition called @rule@.
ruleOf :: TypeCheckResult -> Decide Resolved
ruleOf tc = case [ d | d@(MkDecide _ _ (MkAppForm _ n _ _) _) <- go section, textOf n == "rule" ] of
  d : _ -> d
  []    -> error "no rule called rule"
  where
    MkModule _ _ section = tc.module'
    go (MkSection _ _ _ decls) = concatMap top decls
    top = \ case
      Decide _ d -> [d]
      Section _ s -> go s
      _           -> []
    textOf = rawNameToText . rawName . getOriginal

-- | The editor's ladder of @rule@, as the editor asks for it (not simplified),
-- or the message it refuses with.
ideLadder :: VersionedTextDocumentIdentifier -> TypeCheckResult -> Either T.Text V.FunDecl
ideLadder verId tc =
  either (Left . Ladder.prettyPrintVizError) (Right . (.funDecl) . fst)
    (Ladder.doVisualize (ruleOf tc) (Ladder.mkVizConfig verId tc.module' tc.substitution False))

-- | The core ladder of @rule@ (the REPL's and the browser's), or the message
-- it refuses with.
coreLadder :: VersionedTextDocumentIdentifier -> TypeCheckResult -> Either T.Text V.FunDecl
coreLadder verId tc =
  either (Left . Core.prettyPrintVizError) (Right . (.funDecl))
    (Core.visualizeByName (toNormalizedUri verId._uri) "" 0 tc.module' tc.substitution False "rule")

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

-- | Sixty rows of one NUMBER input, each a sum of two hundred ones: long, not
-- branching, and more than 20,000 parts written out (24,301).
tooLong :: T.Text
tooLong =
  T.unlines $
    ["GIVEN n IS A NUMBER", "GIVETH A BOOLEAN"]
      <> [ "DECIDE rule " <> T.pack (show i) <> " IS n" <> T.concat (replicate 200 " + 1") <> " GREATER THAN 0" | i <- [0 .. 59 :: Int] ]
      <> ["DECIDE rule n IS FALSE"]
