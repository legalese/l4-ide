-- | Lower a typechecked L4 module to the yscript 'YsRule' IR.
--
-- The accepted source fragment is @specs\/todo\/YSCRIPT-EXPORT-SPEC.md@ R1-R3,
-- verbatim: the boolean closure of every @\@export@-annotated NULLARY
-- @DECIDE@\/@MEANS@ — every @Decide@\/@ASSUME@ the closure reaches must also be
-- nullary — over @AND@\/@OR@ and bare references to other in-fragment nullary
-- Decides or nullary @ASSUME BOOLEAN@ facts. Everything else (a parameterised
-- Decide anywhere in the closure, @NOT@\/@IMPLIES@\/@EQUALS@, a non-boolean
-- ASSUME, records, deontics, recursion, ...) is rejected with a 'LowerError'
-- naming the offender. Errors are batched, not first-error-wins (R5): a single
-- run reports every offending Decide\/ASSUME, and — because a yscript
-- consultation with a silently-dropped rule edge fails by asking a raw,
-- unexplained question rather than by erroring — ANY error means NO rules are
-- returned at all ('lowerModule' is all-or-nothing).
module L4.Yscript.Lower
  ( lowerModule
  , LowerError (..)
  , renderLowerError
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import Optics ((^.))

import L4.Annotation (getAnno, rangeOf)
import L4.Desugar (carameliseNode)
import L4.Export (collectExportedDecides)
import L4.Parser.SrcSpan (SrcRange, prettySrcRange)
import L4.Print (docText, prefixKeywordBuiltin, prettyTypeForDisplay)
import L4.Syntax
import L4.TypeCheck.Environment (booleanUnique)

import L4.Yscript.IR

----------------------------------------------------------------------------
-- Diagnostics
----------------------------------------------------------------------------

-- | A reason a Decide/ASSUME could not be compiled to yscript.
data LowerError = LowerError
  { errName  :: !Text              -- ^ the offending definition (empty = module-level)
  , errRange :: !(Maybe SrcRange)  -- ^ where in the L4 source it sits
  , errMsg   :: !Text
  }
  deriving stock (Eq, Show)

renderLowerError :: LowerError -> Text
renderLowerError e = prefix <> e.errMsg <> suffix
 where
  prefix | Text.null e.errName = ""
         | otherwise           = "`" <> e.errName <> "`: "
  suffix = maybe "" (\r -> " (" <> prettySrcRange r <> ")") e.errRange

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

lowerModule :: Module Resolved -> Either [LowerError] [YsRule]
lowerModule mod' =
  case collectExportedDecides mod' of
    [] -> Left [LowerError "" Nothing
                  "no @export-annotated nullary DECIDE found to compile to yscript"]
    entries ->
      let decides = allDecidesFromModule mod'
          assumes = allAssumesFromModule mod'
          finalSt = execState (mapM_ (visitEntry decides assumes) entries) emptyState
      in if null finalSt.wsErrors
           then Right [ finalSt.wsRules Map.! u | u <- reverse finalSt.wsOrder ]
           else Left (reverse finalSt.wsErrors)

----------------------------------------------------------------------------
-- Module-wide indices
----------------------------------------------------------------------------

type DecideIx = Map.Map Unique (Anno, Decide Resolved)
type AssumeIx = Map.Map Unique (Assume Resolved)

-- | Every top-level DECIDE (in any section), keyed by the 'Unique' of the
-- name it defines, paired with the OUTER (TopDecl-level) 'Anno' — needed
-- alongside the DECIDE's own inner 'Anno' because a @\@ref@ written directly
-- above @DECIDE@ may attach to either, depending on whether a @GIVEN@ clause
-- sits between them (mirrors 'L4.Docassemble.Lower.collectTopDecides').
allDecidesFromModule :: Module Resolved -> DecideIx
allDecidesFromModule (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide topAnn d@(MkDecide _ _ (MkAppForm _ name _ _) _) -> [(getUnique name, (topAnn, d))]
    Section _ sub -> goSection sub
    _ -> []

-- | Every top-level ASSUME (in any section), keyed the same way. Unlike
-- 'L4.Export.assumesFromModule' this keeps function-typed and parameterised
-- ASSUMEs too (they are refused here, by name, rather than silently absent).
allAssumesFromModule :: Module Resolved -> AssumeIx
allAssumesFromModule (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Assume _ assume@(MkAssume _ _ (MkAppForm _ name _ _) _ _) -> [(getUnique name, assume)]
    Section _ sub -> goSection sub
    _ -> []

resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

----------------------------------------------------------------------------
-- The closure walk
----------------------------------------------------------------------------

data WalkState = WalkState
  { wsErrors :: ![LowerError]             -- ^ reverse order
  , wsRules  :: !(Map.Map Unique YsRule)
  , wsOrder  :: ![Unique]                 -- ^ reverse discovery order (pre-order DFS)
  , wsActive :: !(Set.Set Unique)         -- ^ on the current DFS stack (cycle guard)
  , wsDone   :: !(Set.Set Unique)         -- ^ fully resolved, memoised
  }

emptyState :: WalkState
emptyState = WalkState [] Map.empty [] Set.empty Set.empty

type W = State WalkState

addError :: Text -> Maybe SrcRange -> Text -> W ()
addError nm rng msg = modify' \s -> s { wsErrors = LowerError nm rng msg : s.wsErrors }

markDone :: Unique -> W ()
markDone u = modify' \s -> s { wsDone = Set.insert u s.wsDone, wsActive = Set.delete u s.wsActive }

-- | Re-attribute every otherwise-anonymous error 'lowerBody' adds while
-- running @action@ to @owner@ — mirrors 'L4.Catala.Lower.vIn'. An error a
-- NESTED call already named (a referenced Decide/ASSUME's own shape problem)
-- is left alone; only errors still carrying @errName = ""@ when @action@
-- returns are claimed, so nesting composes correctly (an inner
-- 'attributeTo' always resolves its own anonymities before an outer one
-- inspects the accumulator).
attributeTo :: Text -> W a -> W a
attributeTo owner action = do
  before <- gets \s -> length s.wsErrors
  result <- action
  modify' \s ->
    let n = length s.wsErrors - before
        (newOnes, rest) = splitAt (max 0 n) s.wsErrors
        renamed = [ if Text.null e.errName then e { errName = owner } else e | e <- newOnes ]
    in s { wsErrors = renamed <> rest }
  pure result

visitEntry :: DecideIx -> AssumeIx -> Decide Resolved -> W ()
visitEntry decides assumes (MkDecide _ _ (MkAppForm _ name _ _) _) =
  visitUnique decides assumes (getUnique name) (resolvedToText name)

-- | Resolve one closure member by 'Unique': validate its shape, recurse
-- into a Decide's body, and record the outcome. Memoised via 'wsDone', and
-- guarded against recursion via 'wsActive' (R1's framing is that yscript
-- disallows recursion by design — research memo §B — so a cycle anywhere in
-- the closure is refused rather than looped over forever).
visitUnique :: DecideIx -> AssumeIx -> Unique -> Text -> W ()
visitUnique decides assumes u nm = do
  st <- gets id
  if Set.member u st.wsDone then pure ()
  else if Set.member u st.wsActive
    then addError nm Nothing
           "is referenced through a cycle of definitions; yscript's execution model \
           \disallows recursion (research memo §B), so a cyclic closure is refused"
    else case Map.lookup u decides of
      Just (topAnn, d@(MkDecide innerAnn (MkTypeSig _ (MkGivenSig _ params) _) _ body)) ->
        if not (null params)
          then do
            addError nm (rangeOf (getAnno d)) "has parameters; yscript has no functional/predicate \
                                               \layer to receive them (R1)"
            markDone u
          else do
            -- Record discovery order HERE, before recursing — so a parent
            -- is followed by its children in true left-to-right encounter
            -- order once 'lowerModule' reverses the whole (prepended, so
            -- backwards) list at the end, rather than by the children
            -- finishing (and so being prepended) before their parent does.
            modify' \s -> s { wsActive = Set.insert u s.wsActive
                            , wsOrder  = u : s.wsOrder
                            }
            cond <- attributeTo nm (lowerBody decides assumes body)
            let lbl = fromMaybe nm (refLabel topAnn innerAnn)
                rule = YsRule { label = lbl, provides = nm, condition = cond }
            modify' \s -> s { wsRules = Map.insert u rule s.wsRules }
            markDone u
      Nothing -> case Map.lookup u assumes of
        Just assume -> do
          case checkAssumeShape assume of
            Left msg -> addError nm (rangeOf (getAnno assume)) msg
            Right () -> pure ()
          markDone u
        Nothing -> do
          addError nm Nothing
            "is not a Decide or ASSUME this module declares; yscript can only reference \
            \facts and rules it defines (R1)"
          markDone u

checkAssumeShape :: Assume Resolved -> Either Text ()
checkAssumeShape (MkAssume _ (MkTypeSig _ (MkGivenSig _ params) _) _ mty _)
  | not (null params) =
      Left "has parameters; yscript has no functional/predicate layer to receive them (R1)"
  | Just ty <- mty, isBooleanTy ty = Right ()
  | Just ty <- mty =
      Left ("is typed " <> prettyTypeForDisplay ty
             <> ", not BOOLEAN; yscript's fact model is propositional-only (R1/R3)")
  | otherwise =
      Left "has no declared type; a yscript leaf fact needs to be ASSUMEd as a BOOLEAN (R3)"

isBooleanTy :: Type' Resolved -> Bool
isBooleanTy = \case
  TyApp _ n [] -> getUnique n == booleanUnique
  _            -> False

-- | @\@ref@ citation text for a definition, if present — the outer
-- (TopDecl-level) and inner ('MkDecide') annos are both consulted, first
-- non-empty wins. Mirrors 'L4.Docassemble.Lower.decideAnns'/'citationText'.
refLabel :: Anno -> Anno -> Maybe Text
refLabel outerAnn innerAnn = listToMaybe (mapMaybe citationText (refsOf [outerAnn, innerAnn]))
 where
  refsOf anns = [ getRef r | ann <- anns, Just r <- [ann ^. annRef] ]
  citationText raw =
    let stripped    = Text.strip raw
        afterHerald = Text.strip (fromMaybe stripped (Text.stripPrefix "@ref" stripped))
        unwrapped   = case Text.stripPrefix "<<" afterHerald of
          Just inner -> Text.strip (fromMaybe inner (Text.stripSuffix ">>" inner))
          Nothing    -> afterHerald
    in if Text.null unwrapped then Nothing else Just unwrapped

----------------------------------------------------------------------------
-- Body lowering (R2)
----------------------------------------------------------------------------

-- | Lower one Decide/MEANS body. Runs 'carameliseNode' at every node before
-- matching, because post-typecheck an infix @a AND b@ has already been
-- desugared to @App __AND__ [a, b]@ (see 'L4.Desugar.carameliseNode' and its
-- use throughout "L4.Print") — matching on the literal 'And'/'Or' AST
-- constructors alone would silently miss every real-world body.
lowerBody :: DecideIx -> AssumeIx -> Expr Resolved -> W YsExpr
lowerBody decides assumes = go
 where
  go e0 = case carameliseNode e0 of
    And _ a b -> YAnd <$> go a <*> go b
    Or  _ a b -> YOr  <$> go a <*> go b
    Not _ _ ->
      refuseHere e0
        "uses NOT: yscript's own negation spelling could not be confirmed against a primary \
        \source, so it is refused rather than guessed (R2)"
    Implies _ _ _ ->
      refuseHere e0 "uses IMPLIES, which has no attested yscript counterpart (R2)"
    Equals _ _ _ ->
      refuseHere e0 "uses EQUALS, which has no attested yscript counterpart (R2)"
    App _ n [] -> do
      let nm = resolvedToText n
      visitUnique decides assumes (getUnique n) nm
      pure (YAtom nm)
    App _ n args@(_ : _)
      | Just kw <- prefixKeywordBuiltin (rawName (getActual n)) ->
          refuseHere e0 ("uses " <> docText kw <> " — yscript answers questions about a fact \
                         \situation and does not act on external systems (research memo §D)")
      | otherwise ->
          refuseHere e0
            ("applies `" <> resolvedToText n <> "` to " <> tshow (length args)
              <> " argument(s); only bare references to already-nullary Decides/ASSUMEs are \
                 \atoms in yscript's propositional fragment (R1/R2)")
    other -> refuseHere other (describeUnsupported other)

  refuseHere e msg = do
    addError "" (rangeOf (getAnno e)) msg
    pure (YAtom "")

tshow :: Show a => a -> Text
tshow = Text.pack . show

describeUnsupported :: Expr Resolved -> Text
describeUnsupported e = "uses a construct outside yscript's propositional fragment (R2): " <> case e of
  Lit{}        -> "a literal — only references to ASSUME BOOLEAN facts or other Decides are atoms"
  Proj{}       -> "a record projection — records are out of the exportable fragment (research memo §D)"
  Where{}      -> "a WHERE binding"
  LetIn{}      -> "a LET binding"
  IfThenElse{} -> "an IF/THEN/ELSE — yscript has no boolean IF, only AND/OR"
  MultiWayIf{} -> "a BRANCH"
  Consider{}   -> "a CONSIDER"
  Lam{}        -> "a lambda"
  AppNamed{}   -> "a named-argument application"
  Regulative{} -> "a deontic/regulative clause — yscript concludes facts, not obligations \
                  \(research memo §D)"
  RAnd{}       -> "a regulative AND"
  ROr{}        -> "a regulative OR"
  Plus{}       -> "arithmetic (PLUS)"
  Minus{}      -> "arithmetic (MINUS)"
  Times{}      -> "arithmetic (TIMES)"
  DividedBy{}  -> "arithmetic (DIVIDED BY)"
  Modulo{}     -> "arithmetic (MODULO)"
  Cons{}       -> "a list cons"
  Leq{}        -> "a numeric comparison (AT MOST)"
  Geq{}        -> "a numeric comparison (AT LEAST)"
  Lt{}         -> "a numeric comparison (LESS THAN)"
  Gt{}         -> "a numeric comparison (GREATER THAN)"
  List{}       -> "a list literal"
  Event{}      -> "an EVENT"
  Fetch{}      -> "FETCH"
  Env{}        -> "an environment lookup"
  Post{}       -> "POST"
  Record{}     -> "a ledger RECORD/COMMIT/ATTEST write"
  ReadCell{}   -> "a ledger RECALL read"
  Concat{}     -> "string concatenation"
  AsString{}   -> "a string coercion"
  Breach{}     -> "BREACH"
  Refuse{}     -> "REFUSE"
  Percent{}    -> "a PERCENT literal"
  Inert{}      -> "inert grammatical scaffolding"
  _            -> "an unrecognised expression form"
