-- | Build the standing equivalence apparatus that every Mode B rewrite carries
-- with it (R4, §8.4).
--
-- The ruling that made Mode B the primary emission also hardened its gate: a
-- module that ships exception ladders must ship, in the same file, the means of
-- re-checking that those ladders say what the boolean rendering says — so the
-- check re-runs under @clerk test@ on every validation rather than once, at
-- development time.
--
-- What makes an /exhaustive/ check affordable is that both renderings are built
-- from the same atomic conditions. Mode A is @c₁ ? v₁ : c₂ ? v₂ : … : d@ and
-- Mode B is the priority ladder over the same @cᵢ@; whether they agree is a
-- question about control flow, not about what the @cᵢ@ mean. The apparatus
-- therefore lifts the atoms into boolean /inputs/ and enumerates all @2ⁿ@ truth
-- assignments — a strictly stronger check than Appendix B's hand-picked
-- boundary grid over one record type, and one that needs no constraint solving
-- to realise an assignment.
--
-- For a rewrite over a @content@ variable the arms' values are stood in for by
-- pairwise-distinct decimal witnesses. That is sound because Catala's exception
-- mechanism does not inspect the value it selects: the rewrite is uniform in
-- the consequence type, and distinct witnesses make "which arm won" observable.
-- The emitted prose says so, so a reader is not left to infer it.
--
-- Emitted per rewrite: a row structure, a Mode A reference scope, a Mode B
-- scope, an @Agree@ comparison scope, and a @#[test]@ grid whose expected
-- answer is @true@ by construction (so, unlike an R7 test block, it needs no
-- oracle).
--
-- __The guarantee is narrower than "the emitted rule was checked", and the
-- emitted prose says so.__ Two limits follow from lifting the atoms:
--
--   * the atoms are scope /inputs/, so no assignment can exhibit an atom that
--     /raises/ (a division by zero inside a guard, say). Strictness divergences
--     between L4 and Catala are therefore invisible here; they are handled in
--     the lowering instead, which emits short-circuiting conditionals for
--     @AND@\/@OR@\/@IMPLIES@ ('catAnd', 'catOr') and declines to ship a ladder
--     whose non-first conditions could raise;
--   * the scopes below are freshly built from 'provisoLadder' \/ 'armLadder'
--     and never mention the emitted rule, so the grid is a property test of the
--     ladder /construction/ at this shape and arity — it is invariant under an
--     edit to the rule's own text. That the emitted text is well-typed is
--     @catala typecheck@'s claim; that it computes what L4 computes is the R7
--     @#[test]@ scopes' claim.
module L4.Catala.Equivalence
  ( EqvUnit (..)
  , equivalenceUnit
  ) where

import Base
import qualified Data.Text as Text

import L4.Catala.Emit (renderCatExpr)
import L4.Catala.IR

-- | One rewrite's worth of comparison apparatus.
data EqvUnit = EqvUnit
  { euDecls :: ![CatDecl]   -- ^ row structure + four scope declarations (metadata fence)
  , euItems :: ![CatItem]   -- ^ the four scope bodies (code fence)
  , euProse :: ![Text]      -- ^ the heading and the claim the grid discharges
  , euTest  :: !CatTestCli  -- ^ the @catala-test-cli@ block for the grid
  , euNames :: ![Text]      -- ^ the capitalised names this unit claims
  }
  deriving stock (Eq, Show, Generic)

-- | Build the apparatus for one Mode B rewrite.
--
-- @base@ is a capitalised prefix unique within the module (the lowering derives
-- it from the scope name); @human@ is the L4 name the prose should use.
-- 'Nothing' means the rewrite is out of the harness's reach — no atoms, or more
-- than 'eqvRowLimit' of them — and the caller must fall back to Mode A.
equivalenceUnit :: Text -> Text -> CatEqv -> Maybe EqvUnit
equivalenceUnit base human eqv
  | n <= 0 || n > eqvRowLimit = Nothing
  | otherwise = Just EqvUnit
      { euDecls =
          [ DStruct CatStruct
              { stName   = rowT
              , stL4     = rowT
              , stDesc   = Just ("One row of the exhaustive truth table for `" <> human <> "`.")
              , stFields = [ CatField (pfield i) (pfield i) TBool Nothing | i <- idx ]
              }
          , DScope (scopeDecl modeAS ("Mode A (boolean reference) rendering of `" <> human <> "`."))
          , DScope (scopeDecl modeBS ("Mode B (exception ladder) rendering of `" <> human <> "`."))
          , DScope CatScopeDecl
              { sdName   = agreeS
              , sdL4     = agreeS
              , sdDesc   = Just "True when both renderings agree on this row."
              , sdIsTest = False
              , sdVars   =
                  [ CatScopeVar "row" "row" VarInput (ShContent (TNamed rowT)) Nothing
                  , CatScopeVar "agree" "agree" VarOutput (ShContent TBool) Nothing
                  ]
              }
          , DScope CatScopeDecl
              { sdName   = gridS
              , sdL4     = gridS
              , sdDesc   = Just ("Exhaustive " <> tshow rows <> "-row agreement grid for `"
                                 <> human <> "`.")
              , sdIsTest = True
              , sdVars   = [ CatScopeVar "all_agree" "all_agree" VarOutput (ShContent TBool) Nothing ]
              }
          ]
      , euItems =
          [ ItemScope (CatScopeBody modeAS [plainRule outVar modeAClauses])
          , ItemScope (CatScopeBody modeBS [plainRule outVar modeBClauses])
          , ItemScope (CatScopeBody agreeS
              [ plainRule "agree"
                  [ CatClause ClPlain Nothing (ConsEquals
                      (EBin BEq (EScopeOut modeAS [("row", EVar "row")] outVar)
                                (EScopeOut modeBS [("row", EVar "row")] outVar))) ] ])
          , ItemScope (CatScopeBody gridS
              [ plainRule "all_agree"
                  [ CatClause ClPlain Nothing (ConsEquals
                      (EForAll "r" (EList gridRows)
                        (EScopeOut agreeS [("row", EVar "r")] "agree"))) ] ])
          ]
      , euProse = prose
      -- @--disable-warnings@ is not cosmetic: @clerk test@ compares the whole
      -- of the command's output against the block, and interpreting one scope
      -- makes every /other/ scope in the module dead code, which the compiler
      -- duly warns about. Those warnings depend on which scope is being run,
      -- so leaving them in makes the expected block order-dependent — checked
      -- against catala 1.2.1, where it flipped a passing block to failing.
      , euTest  = CatTestCli ("catala test-scope " <> gridS <> " --disable-warnings -F json")
                    ["{\"all_agree\":true}"] Nothing
      , euNames = [rowT, modeAS, modeBS, agreeS, gridS]
      }
 where
  n    = eqvAtomCount eqv
  idx  = [0 .. n - 1]
  rows = 2 ^ n :: Int

  rowT   = base <> "Row"
  modeAS = base <> "ModeA"
  modeBS = base <> "ModeB"
  agreeS = base <> "Agree"
  gridS  = base <> "Grid"

  pfield :: Int -> Text
  pfield i = "p_" <> tshow i
  atom :: Int -> CatExpr
  atom i   = EProj (EVar "row") (pfield i)

  -- What the two rendered scopes compute, and under what shape.
  (outVar, outShape) = case eqv.eqKind of
    EqvArmsValue _ -> ("value",   ShContent TDecimal)
    _              -> ("verdict", ShCondition)

  scopeDecl nm desc = CatScopeDecl
    { sdName   = nm
    , sdL4     = nm
    , sdDesc   = Just desc
    , sdIsTest = False
    , sdVars   =
        [ CatScopeVar "row" "row" VarInput (ShContent (TNamed rowT)) Nothing
        , CatScopeVar outVar outVar VarOutput outShape Nothing
        ]
    }

  plainRule v cs = CatRuleDef
    { rdVar = v, rdModeA = cs, rdModeB = Nothing
    , rdEmitted = ModeA, rdFallback = Nothing, rdEqv = Nothing, rdNotes = [] }

  -- The two renderings, over the lifted atoms. These mirror the lowering's own
  -- constructions exactly: 'provisoLadder' and 'armLadder' are the same
  -- functions the emitted rule was built with, and the Mode A shapes below are
  -- the same folds 'L4.Catala.Lower' applies to an @AND NOT@ chain and to a
  -- @MultiWayIf@ respectively.
  modeAClauses = case eqv.eqKind of
    EqvProviso k ->
      [ CatClause ClPlain
          (Just (foldl (\acc i -> catAnd acc (EUn UNot (atom i))) (atom 0) [1 .. k]))
          ConsFulfilled ]
    EqvArmsCond ks d ->
      [ CatClause ClPlain
          (Just (cascade [ (atom i, boolLit b) | (i, b) <- zip idx ks ] (boolLit d)))
          ConsFulfilled ]
    EqvArmsValue k ->
      [ CatClause ClPlain Nothing
          (ConsEquals (cascade [ (atom i, witness i) | i <- [0 .. k - 1] ] (witness k))) ]

  modeBClauses = case eqv.eqKind of
    EqvProviso k    -> provisoLadder outVar (atom 0) [ atom i | i <- [1 .. k] ]
    EqvArmsCond ks d ->
      fromMaybe [] (armLadder outVar ShCondition
                      [ (atom i, boolLit b) | (i, b) <- zip idx ks ] (boolLit d))
    EqvArmsValue k ->
      fromMaybe [] (armLadder outVar (ShContent TDecimal)
                      [ (atom i, witness i) | i <- [0 .. k - 1] ] (witness k))

  cascade :: [(CatExpr, CatExpr)] -> CatExpr -> CatExpr
  cascade arms dflt = foldr (\(c, v) acc -> EIf c v acc) dflt arms
  boolLit :: Bool -> CatExpr
  boolLit b = ELit (LBool b)
  witness :: Int -> CatExpr
  witness i = ELit (LDec (fromIntegral (i + 1)))

  gridRows =
    [ EStruct rowT [ (pfield i, boolLit (testBit' r i)) | i <- idx ]
    | r <- [0 .. rows - 1]
    ]
  testBit' :: Int -> Int -> Bool
  testBit' r i = odd (r `div` (2 ^ i))

  prose =
       [ "### Equivalence check for `" <> human <> "`"
       , ""
       , "The rule above is emitted as an exception ladder (Mode B). The scopes below"
       , "rebuild both renderings — the ladder and the boolean reference form Mode A —"
       , "from the same ladder builders the rule above was built with, over every one of"
       , "the " <> tshow rows <> " truth assignments to its " <> tshow n <> " atomic condition"
         <> (if n == 1 then "" else "s") <> ", and `" <> gridS <> "` fails"
       , "if they ever disagree. The check is part of the artifact, so it re-runs on"
       , "every validation (R4, §8.4)."
       , ""
       , "**What this does and does not establish.** The atoms are lifted to boolean"
       , "*inputs*, so the grid decides a question about control flow: that the ladder's"
       , "priority order reproduces first-match for a rewrite of this shape and this"
       , "arity. It does not evaluate the atom expressions themselves, so it cannot see"
       , "a difference that lives inside one of them; and it exercises freshly built"
       , "copies rather than the text of the rule above, so it does not detect an edit"
       , "made to that text after emission. Those two claims belong to `catala"
       , "typecheck` and to the `#[test]` scopes whose expected values L4 computed."
       , ""
       , "The atoms, as they appear in the emitted rule:"
       , ""
       ]
    <> [ "- `" <> pfield i <> "` stands for `" <> renderCatExpr a <> "`"
       | (i, a) <- zip idx eqv.eqAtoms
       ]
    <> valueNote

  valueNote = case eqv.eqKind of
    EqvArmsValue _ ->
      [ ""
      , "The arms' values are stood in for by pairwise-distinct decimal witnesses."
      , "Catala's exception mechanism does not inspect the value it selects, so the"
      , "rewrite is uniform in the consequence type and distinct witnesses make"
      , "*which arm won* observable — which is the whole of what the ladder decides."
      ]
    _ -> []

tshow :: Show a => a -> Text
tshow = Text.pack . show
