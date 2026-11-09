{-# LANGUAGE MultiWayIf #-}
{- | What a ladder box's @atomId@ names: a proposition, keyed by its term.

Ruling R3 (WHERE-INLINING-SPEC §10.1, ruled 2026-10-07): two boxes of one
diagram are the same proposition exactly when they carry the same C1 term key
(UNKNOWN-EVALUATION-SPEC C1). A call box's key is the called rule together with
the keys of its arguments, and an expansion's leaves are keyed in the caller's
context after substitution. This module is that key, and the @atomId@ is its
hash.

It replaces a hash of the leaf's PRINTED label and input refs, which merged any
two terms that print alike (smucclaw/l4-ide#1004: two mixfix operators sharing a
head keyword) and rendered some refs by 'Unique', so an edit above a rule could
move its ids (smucclaw/l4-ide#1013).

= The key

'termKey' strips every annotation from the leaf's expression (source ranges,
inferred types, tokens, mixfix stamps), renames every name, and shows the
result. So two keys are equal exactly when the two expressions are structurally
equal after renaming. Names are renamed three ways:

* A binder DEFINED INSIDE the term (a lambda or quantifier variable, a pattern
  variable, a @LET@ inside the leaf) is named by its scope, de Bruijn style
  ('boundLevels'): two alpha-equivalent terms share a key, and so do two copies
  of one lambda that substitution put into one leaf.
* A free name of THIS module becomes its binder path from 'mkKeyEnv': the
  top-level declaration it belongs to and its own name, qualified by the named
  sections around it only where an earlier binder has that path. It carries no
  'Unique' and no source position, so it survives a recompile and an edit
  elsewhere in the module, a section heading renamed or inserted included.
* A free name of ANOTHER module, or a builtin, keeps its 'Unique' together with
  a name for its module: the last segment of the module's URI, its file name,
  so the key does not depend on where the source sits on disk. Two modules this
  one reaches that share a file name (a vendored copy of a library beside the
  library itself) are numbered apart, in the order of their full URIs. Every
  module numbers its own names, so an edit to the importing module does not move
  these; an edit to the imported module, or an L4 upgrade that renumbers the
  prelude, can.

A @WHERE@ or @LET@ local is not a name of its own here: the leaf's local
bindings, and the decision's @WHERE@ locals it reads ('withLocalsInScope'), are
put in before keying, as a callee's are before its expansion is drawn. A local
that cannot be put in (a recursive one) stays in the term with its definition.

Three more things are normalised away before the term is shown, each because it
would split one proposition into two keys: an inference variable's counter (an
untyped lambda parameter's type carries one, and it moves when anything checked
earlier changes), the named form of a call whose arguments are all given (keyed
as the positional call), and a record field read written as its selector
applied, @adult p@ (keyed as @p's adult@, 'fieldReads'). One thing that is NOT in the term is
put back: the type a @JSONDECODE@ decodes into, which the evaluator reads off
the node's annotation, so two decodes into different record types stay apart.

One kind of leaf is keyed per occurrence instead: one whose value depends on
WHEN it is evaluated, because it reads or writes the ledger or the network, or
calls a rule that does ('isEffectful'). C1 keys a built-in by its term because it
is a function of its operands; a @RECALL@ is not. The ladders number such leaves
in drawing order ('LSP.L4.Viz.Ladder.getFreshLeaves').

= What it knowingly leaves

* __Same-named binders__ are told apart by the sections around the later one,
  and where those are the same too (two overloads in one section, or two
  unnamed sections declaring one name), by a source-order ordinal. That keeps the
  map injective, so it never merges two binders, but the later of two such
  binders moves with its section's name, and adding a same-named binder ABOVE an
  existing one moves the existing one.
* __A rule of another module is assumed not to touch the ledger__, since its
  body is not here to read; a call to one that does is keyed by its term.
* __The encoding is 'show' of the AST.__ A change to the shape of 'Expr' changes
  the key of every term it touches, and so its @atomId@: an L4 release, not a
  recompile.
* __Equal propositions can still get two keys__ where they are different terms:
  @a AND b@ and @b AND a@ inside one leaf, or a call to a rule against the same
  rule's body written out (a rule call is a call box, R3).
  That is the safe direction (C1: "undetermined" where the truth is "no", never
  the reverse); what must never happen is two different propositions sharing a
  key.
-}
module L4.Viz.AtomKey
  ( KeyEnv
  , mkKeyEnv
  , emptyKeyEnv
  , termKey
  , termKeyWith
  , textKey
  , digestKey
  , DigestStats (..)
  , digestPrefix
  , digestThreshold
  , inlinedSize
  , atomIdOfKey
  , withTypeExpander
  , withLocalsInScope
  , isEffectful
  , fieldReads
  , binderPaths
  , unmappedMarker
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text.Encoding as Text (encodeUtf8)
import Numeric (showHex)
import Optics

import L4.Annotation (Anno_ (..), emptyAnno, getAnno)
import L4.Syntax
import L4.TypeCheck.Environment (jsonDecodeUnique)
import qualified L4.Transform as Transform (hasLocalScopes, inlineLocalBindings, positionalCall)
import qualified L4.Crypto.SHA1 as SHA1
import qualified L4.Crypto.UUID5 as UUID5
import qualified L4.Transform as Transform (Unfoldable (..), callees, pruneRecursive, unfoldableDecide)

-- | What 'termKey' needs to know about the module a term comes from.
data KeyEnv = MkKeyEnv
  { thisModule :: !NormalizedUri
  -- ^ The URI the type checker stamped on this module's own names: the one on
  -- 'MkModule', not a document id a caller supplies.
  , paths :: !(Map Unique Text)
  -- ^ Every binder of this module, by its path ('mkKeyEnv').
  , modules :: !(Map NormalizedUri Text)
  -- ^ Every other module this one names, by a name no other of them has.
  , expandType :: Type' Resolved -> Type' Resolved
  -- ^ The type checker's final substitution, for the one place a key reads a
  -- type ('withTypeExpander').
  , effectfulRules :: !(Set Unique)
  -- ^ The module's rules whose body touches the ledger or the network, directly
  -- or through another such rule ('isEffectful').
  }

-- | No module: every name is foreign. Only a placeholder until 'mkKeyEnv' runs.
emptyKeyEnv :: KeyEnv
emptyKeyEnv = MkKeyEnv (toNormalizedUri (Uri "")) Map.empty Map.empty id Set.empty

-- | Resolve the inferred types a key reads with the checker's final
-- substitution. A key reads a type in one place: the result type of a
-- @JSONDECODE@, which is what the evaluator decodes into.
withTypeExpander :: (Type' Resolved -> Type' Resolved) -> KeyEnv -> KeyEnv
withTypeExpander f env = env { expandType = f }

-- | The path of every binder in the module, rendered.
binderPaths :: KeyEnv -> Map Unique Text
binderPaths env = env.paths

-- | Marks a name of this module that 'mkKeyEnv' did not reach. Such a key falls
-- back to the 'Unique', so it is injective but not stable; a test sweeps the
-- corpus for it.
unmappedMarker :: Text
unmappedMarker = "UNMAPPED"

-- | Walk the module once and give every binder that a leaf can name freely a
-- stable, unique path.
--
-- A binder's path is short where it can be: a section's @GIVEN@ parameter or a
-- top-level declaration is its name, and any other such binder of a top-level
-- declaration (its parameters, its @WHERE@ locals and theirs, a record's fields
-- and constructors) is the declaration's name and its own. Only where that is
-- already taken by an earlier binder, in source order, does the path also carry
-- the named sections around it, and only if THAT is taken too, an ordinal. So
-- renaming a section heading, or inserting one above a rule, moves no id unless
-- two binders share a name across sections; the earlier of two such binders
-- keeps the short path.
--
-- The traversal is the derived 'Foldable' over the names, which visits no
-- annotation, so an inferred type can never contribute a binder or shift an
-- ordinal. Binders that only ever occur inside one leaf (lambda and quantifier
-- variables, pattern variables, a @LET@'s) get no path: 'termKey' names them by
-- scope. Numbering them here as well would let renaming a lambda's variable in
-- one leaf shift the ordinal of a @WHERE@ local named the same in another.
mkKeyEnv :: Module Resolved -> KeyEnv
mkKeyEnv (MkModule _ uri root) =
  MkKeyEnv
    { thisModule = uri
    , paths = numberPaths [b | b@(u, _, _) <- sectionBinders [] root, not (Set.member u termLocal)]
    , modules = nameModules [u.moduleUri | r <- toList root, let u = getUnique r, u.moduleUri /= uri]
    , expandType = id
    , effectfulRules = effectfulRulesOf root
    }
  where
    -- Every binder inside an expression, less those a WHERE binds directly (a
    -- decision's WHERE is ladder structure, so its locals are named freely by
    -- the leaves under it). One pass over the expressions, plus each WHERE.
    termLocal = Set.fromList exprDefs `Set.difference` Set.fromList whereDefs
    exprs = toListOf (gplate @(Expr Resolved)) (over (gplate @Anno) (const emptyAnno) root)
    exprDefs = [u | e <- exprs, Def u _ <- toList e]
    whereDefs =
      [ d
      | e <- exprs
      , w@Where {} <- toListOf cosmosExpr e
      , d <- directDefs w
      ]

-- | Does this leaf's value depend on WHEN it is evaluated? C1 keys a built-in
-- operation by its term because it is a function of its operands. A ledger read
-- (@RECALL@) is not: a @RECORD@ evaluated earlier in the same rule changes its
-- answer, so two occurrences of one @RECALL@ term can be FALSE and then TRUE in
-- one evaluation (found by adversarial review of smucclaw/l4-ide#1013, where it
-- made @l4 verify@ report a satisfiable rule unsatisfiable). Such a leaf is C1's
-- @fresh@: the ladders key each occurrence apart.
--
-- A leaf is effectful when its term records, recalls, fetches or posts, or
-- calls WITH ARGUMENTS a rule of this module that does, directly or through
-- another. A bare reference to such a rule is not: a rule of no parameters is
-- evaluated once and shared, so every reference to it reads the same value. A
-- rule from another module is assumed not to; its body is not here to read.
isEffectful :: KeyEnv -> Expr Resolved -> Bool
isEffectful env = anyOf cosmosExpr $ \case
  App _ r (_ : _) -> Set.member (getUnique r) env.effectfulRules
  AppNamed _ r _ _ -> Set.member (getUnique r) env.effectfulRules
  -- @a's f@ is @f a@ (R3b): a rule that reads the ledger, called by projection,
  -- read either side of a RECORD, was keyed as one atom, and @l4 verify@
  -- reported a satisfiable rule unsatisfiable (found by adversarial review).
  Proj _ _ r -> Set.member (getUnique r) env.effectfulRules
  e -> touchesWorld e

touchesWorld :: Expr Resolved -> Bool
touchesWorld = \case
  Record {} -> True
  ReadCell {} -> True
  Fetch {} -> True
  Post {} -> True
  _ -> False

-- | The rules of the module whose body touches the ledger or the network, or
-- names (at any arity) a rule that does: a fixpoint over the call graph.
effectfulRulesOf :: Section Resolved -> Set Unique
effectfulRulesOf root = grow direct
  where
    bodies =
      [ (getUnique n, body)
      | MkDecide _ _ (MkAppForm _ n _ _) body <- toListOf (gplate @(Decide Resolved)) root
      ]
    direct = Set.fromList [u | (u, body) <- bodies, anyOf cosmosExpr touchesWorld body]
    calls = [(u, Set.fromList [getUnique r | r <- toList body]) | (u, body) <- bodies]
    grow known =
      let known' = known <> Set.fromList [u | (u, named) <- calls, not (Set.disjoint named known)]
       in if known' == known then known else grow known'

-- | A name for each foreign module: its file name, or, where two share one, the
-- file name and an ordinal for every one after the first, in the order of their
-- full URIs. Injective, and independent of where the files sit unless two of
-- them share a name.
nameModules :: [NormalizedUri] -> Map NormalizedUri Text
nameModules uris =
  Map.fromList
    [ (m, if k == 0 then tl else tl <> "#" <> Text.pack (show k))
    | sharing <- Map.elems byTail
    , (k, m) <- zip [0 :: Int ..] sharing
    , let tl = uriTail m
    ]
  where
    byTail = Map.fromListWith (flip (<>)) [(uriTail m, [m]) | m <- sortOn uriText (firstOccurrences uris)]
    uriText m = (fromNormalizedUri m).getUri

-- | A binder, the named sections around it, and the rest of its path.
type Placed = (Unique, [Text], [Text])

sectionBinders :: [Text] -> Section Resolved -> [Placed]
sectionBinders secs (MkSection _ mn maka mgiven decls) =
  defsUnder secs [] (maybeToList mn <> foldMap toList maka)
    <> defsUnder here [] (foldMap toList mgiven)
    <> concatMap (topDeclBinders here) decls
  where
    here = secs <> maybe [] (pure . nameText) mn

topDeclBinders :: [Text] -> TopDecl Resolved -> [Placed]
topDeclBinders here = \case
  Section _ s -> sectionBinders here s
  Decide _ d@(MkDecide _ _ (MkAppForm _ n _ maka) _) -> headed n maka (toList d)
  Assume _ a@(MkAssume _ _ (MkAppForm _ n _ maka) _ _) -> headed n maka (toList a)
  Declare _ d@(MkDeclare _ _ (MkAppForm _ n _ maka) _) -> headed n maka (toList d)
  Directive _ d -> defsUnder here ["#directive"] (toList d)
  Import _ i -> defsUnder here [] (toList i)
  Timezone _ e -> defsUnder here ["#timezone"] (toList e)
  where
    headed n maka inner =
      defsUnder here [] (n : foldMap toList maka)
        <> defsUnder here [nameText n] inner

defsUnder :: [Text] -> [Text] -> [Resolved] -> [Placed]
defsUnder secs lead rs = [(u, secs, lead <> [rawNameToText (rawName nm)]) | Def u nm <- rs]

-- | First occurrence of a 'Unique' wins. A binder takes its short path unless an
-- earlier binder already took it; then the path with its sections; then that
-- with the first free ordinal. Rendered with 'show', so no name can spell
-- another binder's path or ordinal.
numberPaths :: [Placed] -> Map Unique Text
numberPaths = go Set.empty Set.empty Map.empty
  where
    go _ _ acc [] = acc
    go shortTaken taken acc ((u, secs, rest) : more)
      | Map.member u acc = go shortTaken taken acc more
      | otherwise =
          let candidate = if Set.member rest shortTaken then (secs, rest) else ([], rest)
              rendered = firstFree candidate 0
           in go (Set.insert rest shortTaken) (Set.insert rendered taken) (Map.insert u rendered acc) more
      where
        firstFree c k =
          let r = Text.pack (show c) <> (if k == 0 then "" else "#" <> Text.pack (show (k :: Int)))
           in if Set.member r taken then firstFree c (k + 1) else r

-- | The leaf as it reads: wrapped in the definitions of the @WHERE@ locals in
-- scope that it uses, transitively, so that 'termKey' can put them in. A
-- caller's own local is keyed by what it means, as the same local is inside a
-- callee's expansion (whose locals are inlined before it is drawn); and two
-- copies of one local made by unfolding two calls, which keep its one Unique,
-- are keyed apart by their different definitions, even when the local is
-- recursive and so cannot be inlined (found by adversarial review of
-- smucclaw/l4-ide#1013: @l4 verify@ coalesced two such copies and reported a
-- satisfiable rule as unsatisfiable). The locals keep their source order.
withLocalsInScope :: [LocalDecl Resolved] -> Expr Resolved -> Expr Resolved
withLocalsInScope locals e
  | null needed = e
  | otherwise = Where emptyAnno e needed
  where
    defined = Map.fromList [(getUnique n, body) | LocalDecide _ (MkDecide _ _ (MkAppForm _ n _ _) body) <- locals]
    needed = [d | d@(LocalDecide _ (MkDecide _ _ (MkAppForm _ n _ _) _)) <- locals, Set.member (getUnique n) reach]
    reach = grow (namesIn e)
    grow seen =
      let seen' = seen <> foldMap namesIn (Map.restrictKeys defined seen)
       in if seen' == seen then seen else grow seen'
    namesIn x = Set.fromList [getUnique r | r <- toList x, Map.member (getUnique r) defined]

-- | The size, in expression nodes, past which a leaf is no longer keyed by the
-- 'show' of its term. ASSUMED, NOT RULED (WHERE-INLINING-SPEC §10.1, R3c). Compared
-- with the leaf's 'inlinedSize': the number of nodes of the leaf with its locals put
-- in, which is the size of the term the key is a key OF.
--
-- The unit is expression nodes, not time. The largest leaf over every .l4 under
-- jl4/examples that is not a deliberate error (537 files, 8,085 leaves),
-- jl4-core/libraries and doc (130 files, 687 leaves), with its locals put in, is
-- 313 nodes (measured 2026-10-12), and the largest with a local in it is 267; the
-- threshold is the next power of two above four times the largest. A leaf at the
-- threshold has a key of about 600,000 characters (305 a node, measured on a body
-- of AND, NOT and variables).
digestThreshold :: Int
digestThreshold = 2048

-- | How many expression nodes 'Transform.inlineLocalBindings' would leave of this
-- term, worked out WITHOUT putting the locals in: a pass over the term, plus one
-- evaluation of each local for each distinct set of argument sizes it is called
-- with. The sizes saturate just above 'digestThreshold', so nothing here is ever
-- exponential, and a result over the threshold means only "over".
--
-- An estimate, not the pass. It equals the real count for the body of every rule
-- the ladder can draw under jl4/examples/ok and legal (jl4-lsp's AtomKeySizeSpec,
-- which also requires more than ten of them to have a WHERE or a LET; canon
-- agreed too, run once), and on the shapes in jl4-core's AtomKeySpec. Where it can
-- differ is a declaration that STAYS (one that cannot be put in, or is still named
-- after the calls are): which of the others it keeps is decided by a rule that can
-- keep one more than the real pass does ('scope'). The exponential of a chain of
-- locals is the one thing it never counts.
inlinedSize :: Expr Resolved -> Int
inlinedSize = inlinedSizeUpTo digestThreshold

-- | 'inlinedSize' saturating just above the given limit instead.
inlinedSizeUpTo :: Int -> Expr Resolved -> Int
inlinedSizeUpTo limit expr
  -- With no local in it there is nothing to put in, and the count is the number
  -- of nodes (stopped just past the limit, as the sizes below are).
  | not (Transform.hasLocalScopes expr) = length (take (limit + 1) (toListOf cosmosExpr expr))
  | otherwise = evalState (size Set.empty Map.empty expr) Map.empty
  where
    cap = limit + 1
    clamp = min cap

    -- Every local the term declares that can be put in, wherever it sits: names
    -- are resolved to Uniques, so one flat map is as good as scoping.
    usable :: Map Unique Transform.Unfoldable
    usable =
      Transform.pruneRecursive . Map.fromList $
        [ p
        | LocalDecide _ d <- concatMap localsOf (toListOf cosmosExpr expr)
        , Just p <- [Transform.unfoldableDecide d]
        ]

    localsOf = \case
      Where _ _ ds -> ds
      LetIn _ ds _ -> ds
      _ -> []

    -- @blocked@ are the locals whose calls are NOT put in here: inside a
    -- declaration that stays, the pass that puts in its own scope's locals has
    -- already run past it.
    size :: Set Unique -> Map Unique Int -> Expr Resolved -> State (Map (Unique, [Int]) Int) Int
    size blocked params e = case e of
      Where _ body ds -> scope blocked params body ds
      LetIn _ ds body -> scope blocked params body ds
      -- a parameter is replaced by its argument, whole
      App _ r [] | Just n <- Map.lookup (getUnique r) params -> pure n
      _ | Just (r, args) <- Transform.positionalCall e
        , not (Set.member (getUnique r) blocked)
        , Just (Transform.MkUnfoldable ps body) <- Map.lookup (getUnique r) usable
        , length args == length ps -> do
            sizes <- traverse (size blocked params) args
            call (getUnique r) ps body sizes
      _ -> do
        ks <- traverse (size blocked params) (toListOf (gplate @(Expr Resolved)) e)
        pure (clamp (1 + sum ks))

    -- A scope disappears when every local in it is put in and none is named again;
    -- otherwise it stays round the body, with the declarations that are left. Those
    -- are the ones that cannot be put in, and the ones that can but are still named
    -- after the calls are replaced: a call at another arity (a local passed as a
    -- value), or a mention in a declaration that stays. This takes every mention in
    -- the body and the local bodies, whether or not the call it sits in is
    -- replaced, so it can keep a declaration that 'Transform.inlineLocalBindings'
    -- drops.
    scope blocked params body ds = do
      b <- size blocked params body
      let here = Map.fromList [(u, length ps) | d <- ds, Just (u, Transform.MkUnfoldable ps _) <- [unfoldable d], Map.member u usable]
          stays = [d | d <- ds, not (putIn d)]
          bodiesPutIn = [e | d <- ds, Just (u, Transform.MkUnfoldable _ e) <- [unfoldable d], Map.member u usable]
          named =
            foldMap (offArity here) (body : bodiesPutIn)
              <> foldMap Transform.callees [e | d <- stays, e <- toListOf (gplate @(Expr Resolved)) d]
          stillNamed = [d | d <- ds, putIn d, Just (u, _) <- [unfoldable d], Set.member u named]
          left = stays <> stillNamed
      ks <- traverse (declSize (blocked <> Map.keysSet here) params) left
      pure (clamp (if null left then b else 1 + b + sum ks))

    unfoldable = \case
      LocalDecide _ d -> Transform.unfoldableDecide d
      _ -> Nothing

    putIn d = case unfoldable d of
      Just (u, _) -> Map.member u usable
      Nothing -> False

    declSize blocked params d = sum <$> traverse (size blocked params) (toListOf (gplate @(Expr Resolved)) d)

    -- The memo is keyed by the callee and the sizes of its arguments: the size of
    -- a call depends on nothing else about them.
    call u ps body sizes = do
      memo <- get
      case Map.lookup (u, sizes) memo of
        Just n -> pure n
        Nothing -> do
          n <- size Set.empty (Map.fromList (zip ps sizes)) body
          modify' (Map.insert (u, sizes) n)
          pure n

-- | The locals of the given arities (by Unique) that the expression names other
-- than by a call with exactly that many arguments: a local passed as a value, or
-- called with too few or too many. Such a local is not put in at that name, so it
-- stays.
offArity :: Map Unique Int -> Expr Resolved -> Set Unique
offArity here = foldMapOf cosmosExpr \e ->
  case e of
    App _ r _ -> check r e
    AppNamed _ r _ _ -> check r e
    _ -> Set.empty
  where
    check r e = case Map.lookup (getUnique r) here of
      Just arity | maybe True ((/= arity) . length . snd) (Transform.positionalCall e) -> Set.singleton (getUnique r)
      _ -> Set.empty

-- | The C1 key of a term (see the module header).
--
-- A key is a function of the TREE the leaf means: the leaf with its locals put in.
-- Two spellings of one tree (a @LET@, and its body written out where it is used)
-- have one key. Which form the key takes depends only on the size of that tree
-- ('digestThreshold'):
--
-- * at or under it, the key is 'textKey': the 'show' of the tree, as it has
--   always been, so no id that exists moves;
-- * over it, the key is 'digestKey': 'digestPrefix' and a digest of the same tree
--   computed without building it, which a chain of locals that each name the
--   previous one twice (exponential once put in, linear in the source) needs.
--
-- 'digestKey' declines a term it cannot digest exactly (see there), and such a
-- term is keyed by 'textKey' at any size: exponentially, if it is a doubling
-- chain that ALSO has a recursive local, or a local passed as a value, or a
-- binder of its own (a lambda, a quantifier, a pattern variable).
termKey :: KeyEnv -> Expr Resolved -> Text
termKey = termKeyWith digestThreshold

-- | 'termKey' with the threshold given, so a test can reach the digest on a term
-- too small to need it.
termKeyWith :: Int -> KeyEnv -> Expr Resolved -> Text
termKeyWith threshold env expr
  | inlinedSizeUpTo threshold expr > threshold
  , Just (key, _) <- digestKey env expr =
      key
  | otherwise = textKey env expr

-- | The key of a term as the 'show' of the term with its locals put in.
textKey :: KeyEnv -> Expr Resolved -> Text
textKey env expr =
  Text.pack (show (fmap nameKey normalised)) <> decodes
  where
    -- A local binding inside the term (a LET, or the WHERE that
    -- 'withLocalsInScope' put round it) is put in first, as a callee's are before
    -- its expansion is drawn; one that cannot be (a recursive one) stays, and is
    -- keyed with its definition.
    inlined = Transform.inlineLocalBindings expr
    normalised =
      boundLevels
        . positional
        . over (gplate @(Type' Resolved)) eraseInfVars
        . over (gplate @Anno) (const emptyAnno)
        -- before the annotations go: they are what says a name is a selector
        $ fieldReads inlined

    -- JSONDECODE decodes into its node's inferred type, which is an annotation,
    -- so the stripped term no longer says what it decodes into: keep each
    -- decode's type beside it, in traversal order.
    decodes = case decodeTypes of
      [] -> ""
      tys -> "|decodes " <> Text.pack (show (map (fmap nameKey) tys))
    decodeTypes =
      [ eraseInfVars (over (gplate @Anno) (const emptyAnno) (env.expandType ty))
      | App (Anno {extra = Extension {resolvedInfo = Just (TypeInfo ty _)}}) r _ <- toListOf cosmosExpr inlined
      , getUnique r == jsonDecodeUnique
      ]

    nameKey = nameKeyIn env

-- | How a key names a name. See 'termKey'.
nameKeyIn :: KeyEnv -> Resolved -> Text
nameKeyIn env r =
  let u = getUnique r
   in if
        | u.moduleUri == boundUri -> "bound#" <> Text.pack (show u.unique)
        | u.moduleUri == supplyUri -> Text.pack (show ("WITH" :: Text, nameText r))
        | u.moduleUri == holeUri -> "child#"
        | u.moduleUri == env.thisModule ->
            fromMaybe
              (Text.pack (show (unmappedMarker, nameText r, u.sort, u.unique)))
              (Map.lookup u env.paths)
        | otherwise ->
            Text.pack
              (show
                ( Map.findWithDefault (uriTail u.moduleUri) u.moduleUri env.modules
                , nameText r, u.sort, u.unique ))

-- | An inference variable carries the checker's counter, which moves whenever
-- anything checked before it changes; an untyped lambda's parameter type is one.
-- What it stood for is fixed by the rest of the term, so drop the number.
eraseInfVars :: Type' Resolved -> Type' Resolved
eraseInfVars = transformOf (gplate @(Type' Resolved)) $ \case
  InfVar _ _ _ -> InfVar emptyAnno (NormalName "_") 0
  t -> t

-- | A call with named arguments, all of them given, is the positional call it
-- stands for (R3: a call box is its rule and its arguments), so
-- @f WITH b IS y, a IS x@ and @f x y@ key alike. Which named calls those are is
-- 'Transform.positionalCall''s to say, the same function the ladder expands a
-- call through, so a call that is keyed as its positional form is also drawn
-- with its positional form's expansion. The checker records which parameter
-- each argument supplies; a negative entry supplies a section binder rather than
-- a parameter, and such a call keeps its named form, with each supply keyed by
-- the name it supplies.
positional :: Expr Resolved -> Expr Resolved
positional expr
  -- 'positionalStep' rewrites a named call and nothing else.
  | anyOf cosmosExpr isNamedCall expr = transformOf (gplate @(Expr Resolved)) positionalStep expr
  | otherwise = expr
  where
    isNamedCall = \case
      AppNamed {} -> True
      _           -> False

-- | 'positional' at one node.
positionalStep :: Expr Resolved -> Expr Resolved
positionalStep = \case
  call@(AppNamed ann f _ _)
    | Just (_, args) <- Transform.positionalCall call -> App ann f args
  -- Some arguments supply section binders (a negative entry). The checker
  -- resolves such a name in the CALLER's scope, but what it supplies is matched
  -- by name, so the same call written in two sections names two binders for
  -- one supply. Key a supply by the name it supplies, after the parameters, in
  -- name order.
  AppNamed ann f nes (Just order) ->
        let pairs = zip nes order
            params = sortOn snd [p | p@(_, j) <- pairs, j >= 0]
            supplies =
              sortOn (\(MkNamedExpr _ rn _, _) -> nameText rn)
                [(MkNamedExpr a (bySupplyName rn) e, j) | (MkNamedExpr a rn e, j) <- pairs, j < 0]
              -- sorted AFTER renaming, so by the written name, not by the binder
            kept = params <> supplies
         in AppNamed ann f (map fst kept) (Just (map snd kept))
  e -> e
  where
    -- The name as the writer spelled it, unqualified: the binder it resolved to
    -- in the caller's scope carries that scope's section in its own name.
    bySupplyName rn =
      let written = MkName emptyAnno (NormalName (unqualifiedRawNameToText (rawName (getActual rn))))
       in Ref written (MkUnique 's' 0 supplyUri) written

-- | A record field read written as its selector applied, @adult p@, is the field
-- read @p's adult@: the projection is sugar for the selector's application, and
-- the evaluator desugars it so (@L4.EvaluateLazy.Machine@, the 'Proj' case), so
-- the two spellings read one field of one record and are one proposition. Keyed
-- alike, they are one atom (smucclaw/l4-ide#1033, gap 3, ruled by Meng
-- 2026-10-11: "record accessor function desugaring").
--
-- Both are keyed as the projection, not the other way round, for two reasons.
-- It is the evaluator's own term for both: a selector applied to an unknown
-- record gives 'L4.Evaluate.ValueLazy.TField', the field read, whichever way it
-- was written. And it leaves the key of every @p's adult@ where it was; only the
-- rarer @adult p@ moves.
--
-- A name is a selector when the checker said so, on the reference or on the
-- definition it refers to (the second because a reference with no source range
-- carries no stamp; "L4.Dmn.Lower" reads computed selectors the same way). A
-- computed field (@MEANS@ in a @DECLARE@) is read the same way, by projection or
-- by its selector. Only an application to exactly one argument is a field read,
-- written positionally or by name (@adult WITH `_self` IS p@,
-- 'Transform.positionalCall'); a selector's type parameters are implicit, so it
-- never takes more.
--
-- The checker's @ComputedSelector@ stamp is not trusted alone: it goes on ANY
-- rule whose name is the name of a computed field of some record in the module
-- (@scanFunSigDecide@), so @bonus n@ over a NUMBER, beside a record with a
-- computed @bonus@, was read as the field read @n's bonus@, moved its atomId and
-- named the input @n.bonus@ (found by adversarial review). A computed field's
-- function is the one 'L4.Desugar.makeComputedDecide' synthesises, whose one
-- parameter is @_self@ ('L4.Desugar.isComputedFieldDecide' tests the same
-- shape), so that is required too.
--
-- The folded projection names the field as a projection writes it, unqualified:
-- a selector written with its section, @`Alpha`.w OF r@, would otherwise name the
-- input @r.Alpha.w@ where @r's w@ names @r.w@ (found by adversarial review). The
-- key does not see the spelling, only the 'Unique'.
fieldReads :: Expr Resolved -> Expr Resolved
fieldReads expr
  -- Whether a node is a field read is a fact about the node alone, so an
  -- expression with none in it is returned as it is.
  | anyOf cosmosExpr (isJust . selectorRead) expr = transformOf (gplate @(Expr Resolved)) (\ e -> fromMaybe e (selectorRead e)) expr
  | otherwise = expr
  where
    selectorRead = \case
      Proj {} -> Nothing
      e | Just (f, [record]) <- Transform.positionalCall e
        , isSelector f -> Just (Proj (getAnno e) record (asWritten f))
      _ -> Nothing
    isSelector r = any selectorKind [getActual r, getOriginal r]
    selectorKind (MkName a _) = case a.extra.resolvedInfo of
      Just (TypeInfo _ (Just Selector)) -> True
      Just (TypeInfo ty (Just ComputedSelector)) -> takesSelf ty
      _ -> False
    takesSelf = \case
      Forall _ _ t -> takesSelf t
      Fun _ [MkOptionallyNamedType _ (Just n) _] _ -> rawName (getOriginal n) == NormalName "_self"
      _ -> False
    asWritten = \case
      Ref _ u o -> Ref (unqualified o) u o
      r -> r
    unqualified (MkName a raw) = MkName a (NormalName (unqualifiedRawNameToText raw))

-- | Rename every binder defined inside the term by its scope: how many binding
-- nodes enclose it, and its place among its own node's binders (de Bruijn
-- levels). Lexical scoping makes that sound, since the binders in scope at any
-- point sit at different depths. It is blind to the binders' Uniques, so two
-- alpha-equivalent lambdas key alike, and so do two copies of ONE lambda that
-- substitution put into one leaf, which share a Unique.
boundLevels :: Expr Resolved -> Expr Resolved
boundLevels = go 0 Map.empty
  where
    go :: Int -> Map Unique Unique -> Expr Resolved -> Expr Resolved
    go depth env e =
      let ds = directDefs e
          env' = foldl' (\m (i, d) -> Map.insert d (MkUnique 'b' (depth * levelWidth + i) boundUri) m) env (zip [0 ..] ds)
          depth' = if null ds then depth else depth + 1
       in over (gplate @Resolved) (rename env') (over (gplate @(Expr Resolved)) (go depth' env') e)
    rename env r = case Map.lookup (getUnique r) env of
      Nothing -> r
      Just v -> case r of
        Def _ _ -> Def v placeholder
        Ref _ _ _ -> Ref placeholder v placeholder
        OutOfScope _ _ -> OutOfScope v placeholder
    placeholder = MkName emptyAnno (NormalName "_")
    levelWidth = 1000000

-- | Where a renamed bound variable's synthetic Unique lives. No module has it.
boundUri :: NormalizedUri
boundUri = toNormalizedUri (Uri "jl4:bound")

-- | Where a section-binder supply's name is put ('positional'): it is keyed by
-- its spelling, not by any binder. No module has it.
supplyUri :: NormalizedUri
supplyUri = toNormalizedUri (Uri "jl4:supply")

-- | Where the stand-in for a child expression lives ('digestKey'). No module has it.
holeUri :: NormalizedUri
holeUri = toNormalizedUri (Uri "jl4:child")

-- | The binders an expression node defines itself, not inside one of its child
-- expressions: a lambda's parameters, a pattern's variables, a @WHERE@'s or
-- @LET@'s local names and their parameters. In order, with repeats.
directDefs :: Expr Resolved -> [Unique]
directDefs e = minus (defsIn e) (concatMap defsIn (toListOf (gplate @(Expr Resolved)) e))
  where
    defsIn x = [u | Def u _ <- toList x]
    minus xs ys = go (Map.fromListWith (+) [(y, 1 :: Int) | y <- ys]) xs
      where
        go _ [] = []
        go counts (x : rest) = case Map.lookup x counts of
          Just n | n > 0 -> go (Map.insert x (n - 1) counts) rest
          _ -> x : go counts rest

-- | The @atomId@ of a key, in the diagram of the decision named @fn@: a UUIDv5,
-- the same shape the id has always had.
atomIdOfKey :: Text -> Text -> Text
atomIdOfKey fn key =
  UUID5.toText (UUID5.generateNamed UUID5.namespaceURL (Text.encodeUtf8 (Text.pack (show (fn, key)))))

nameText :: Resolved -> Text
nameText = rawNameToText . rawName . getOriginal

-- | The last segment of a URI: a file's name, @prelude.l4@ for the embedded
-- prelude, the whole @jl4:builtin@ for builtins. Never a directory, so the key
-- does not depend on where the source sits on disk.
uriTail :: NormalizedUri -> Text
uriTail uri = case Text.splitOn "/" (fromNormalizedUri uri).getUri of
  [] -> ""
  segs -> last segs

firstOccurrences :: Ord a => [a] -> [a]
firstOccurrences = go Set.empty
  where
    go _ [] = []
    go seen (x : xs)
      | Set.member x seen = go seen xs
      | otherwise = x : go (Set.insert x seen) xs

------------------------------------------------------------------------
-- The digest key
------------------------------------------------------------------------

-- | What 'digestKey' did, for the tests: counts, so that a test can say how the
-- work grows without timing anything.
data DigestStats = MkDigestStats
  { callsEvaluated :: !Int
  -- ^ A local evaluated, once for each distinct set of argument digests it is
  -- called with.
  , nodesDigested :: !Int
  -- ^ Nodes of the term, and of the bodies of the locals, digested.
  }
  deriving stock (Eq, Show)

-- | Begins every 'digestKey'. No 'textKey' begins with it: a 'textKey' is the
-- 'show' of an 'Expr', and that begins with the name of a constructor, which is a
-- capital letter. So the two kinds of key can never be equal, and a reader can
-- tell them apart.
digestPrefix :: Text
digestPrefix = "~"

data Walk = MkWalk
  { memo :: !(Map (Unique, [BS.ByteString]) BS.ByteString)
  , calls :: !Int
  , nodes :: !Int
  }

-- | The key of a term as a digest of the tree it means, worked out without
-- building the tree: 'Nothing' for a term this cannot do exactly.
--
-- The tree is the term with its locals put in (what 'textKey' shows). A node's
-- digest is a hash of the node with each child expression replaced by a stand-in
-- (its 'show', the same one 'textKey' is made of), and of its children's digests,
-- in order. A reference to a local, or a call of one, has the digest of the local's
-- body with the arguments' digests in place of its parameters, and that is
-- remembered by the local and the digests it was given. So a chain of locals that
-- each name the previous one twice digests each local once, not twice each time.
-- Because the digest of a node does not depend on how its child was written, a
-- @LET@ and its body written out where it is used have one digest, as they have
-- one 'textKey'.
--
-- What it declines ('Nothing'), after which the term is keyed by 'textKey', which
-- for a chain of locals is exponential:
--
-- * a local that cannot be put in (a recursive one, or one that applies a
--   parameter as a function), or one put in at one name and not another (a local
--   passed as a value), because such a local stays in the tree, with its
--   definition, and this does not digest that;
-- * two declarations of one Unique, which happens when the same local is copied by
--   unfolding two calls, and means the one definition 'locals' would find is not
--   always the right one;
-- * a binder of the term's own (a lambda, a quantifier, a pattern variable). The
--   key names a bound variable by how many binders enclose it, so the digest of a
--   subterm depends on where it is put, and a local's body or an argument is put
--   in several places. Without binders there is nothing to name by depth.
--
-- Not covered here, and wanted when @fieldReads@ lands (R3b): it rewrites a node
-- before the annotations go, so it belongs in 'digestKey' in the same place, at
-- the node, before 'stripNode'.
digestKey :: KeyEnv -> Expr Resolved -> Maybe (Text, DigestStats)
digestKey env expr
  | not eligible = Nothing
  | otherwise =
      let (root, w) = runState (digest Map.empty expr) (MkWalk Map.empty 0 0)
       in Just (digestPrefix <> hexDigest root, MkDigestStats w.calls w.nodes)
  where
    decls = concat [ds | e <- toListOf cosmosExpr expr, ds <- [declsOf e]]
    declsOf = \case
      Where _ _ ds -> ds
      LetIn _ ds _ -> ds
      _ -> []

    unfoldables = [p | LocalDecide _ d <- decls, Just p <- [Transform.unfoldableDecide d]]
    locals :: Map Unique Transform.Unfoldable
    locals = Map.fromList unfoldables

    eligible =
      length unfoldables == length decls
        && Map.size locals == length decls
        && Map.size (Transform.pruneRecursive locals) == Map.size locals
        && Set.null (offArity (Map.map (\(Transform.MkUnfoldable ps _) -> length ps) locals) expr)
        && all binderFree (toListOf cosmosExpr expr)

    -- a node other than a scope defines no name of its own
    binderFree = \case
      Where {} -> True
      LetIn {} -> True
      e -> not (any isDef (toList (withHoles e)))
    isDef = \case
      Def {} -> True
      _ -> False

    -- The digest of an expression, given the digests of the parameters in scope.
    digest :: Map Unique BS.ByteString -> Expr Resolved -> State Walk BS.ByteString
    digest params e = case e of
      -- a scope puts its locals in, and is not itself in the tree
      Where _ body _ -> digest params body
      LetIn _ _ body -> digest params body
      App _ r [] | Just d <- Map.lookup (getUnique r) params -> pure d
      _
        | Just (r, args) <- Transform.positionalCall e
        , Just (Transform.MkUnfoldable ps body) <- Map.lookup (getUnique r) locals -> do
            ds <- traverse (digest params) args
            call (getUnique r) ps body ds
        | otherwise -> node params e

    node params e = do
      let e' = positionalStep e
      ds <- traverse (digest params) (toListOf (gplate @(Expr Resolved)) e')
      modify' (\w -> w {nodes = w.nodes + 1})
      pure (combine (shape e') ds)

    call u ps body ds = do
      w <- get
      case Map.lookup (u, ds) w.memo of
        Just d -> pure d
        Nothing -> do
          modify' (\w' -> w' {calls = w'.calls + 1})
          d <- digest (Map.fromList (zip ps ds)) body
          modify' (\w' -> w' {memo = Map.insert (u, ds) d w'.memo})
          pure d

    -- The node as 'textKey' would show it, less its children: annotations gone,
    -- inference variables erased, and what a JSONDECODE decodes into put back.
    shape :: Expr Resolved -> Text
    shape e =
      Text.pack (show (fmap (nameKeyIn env) (stripNode (withHoles e)))) <> decoded
      where
        decoded = case e of
          App (Anno {extra = Extension {resolvedInfo = Just (TypeInfo ty _)}}) r _
            | getUnique r == jsonDecodeUnique ->
                "|decodes " <> Text.pack (show (fmap (nameKeyIn env) (stripType (env.expandType ty))))
          _ -> ""

    stripNode = over (gplate @(Type' Resolved)) eraseInfVars . over (gplate @Anno) (const emptyAnno)
    stripType = eraseInfVars . over (gplate @Anno) (const emptyAnno)

-- | The node with each child expression replaced by one fixed stand-in, which
-- 'nameKeyIn' shows as @child#@.
withHoles :: Expr Resolved -> Expr Resolved
withHoles = over (gplate @(Expr Resolved)) (const hole)
  where
    hole = App emptyAnno (Ref n (MkUnique 'h' 0 holeUri) n) []
    n = MkName emptyAnno (NormalName "child")

-- | A node's digest from its shape and its children's digests. The shape is given
-- its length first, so that no two (shape, children) pairs hash the same bytes.
combine :: Text -> [BS.ByteString] -> BS.ByteString
combine sh ds = SHA1.sha1 (BS.concat ([Text.encodeUtf8 (Text.pack (show (BS.length bytes) <> ":")), bytes] <> ds))
  where
    bytes = Text.encodeUtf8 sh

hexDigest :: BS.ByteString -> Text
hexDigest = Text.pack . concatMap byte . BS.unpack
  where
    byte b = let h = showHex b "" in if length h == 1 then '0' : h else h
