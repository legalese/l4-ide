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

Two more things are normalised away before the term is shown, each because it
would split one proposition into two keys: an inference variable's counter (an
untyped lambda parameter's type carries one, and it moves when anything checked
earlier changes), and the named form of a call whose arguments are all given
(keyed as the positional call). One thing that is NOT in the term is
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
  , atomIdOfKey
  , withTypeExpander
  , withLocalsInScope
  , isEffectful
  , binderPaths
  , unmappedMarker
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text.Encoding as Text (encodeUtf8)
import Optics

import L4.Annotation (Anno_ (..), emptyAnno)
import L4.Syntax
import L4.TypeCheck.Environment (jsonDecodeUnique)
import qualified L4.Transform as Transform (inlineLocalBindings)
import qualified L4.Crypto.UUID5 as UUID5

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
      , w@Where {} <- toListOf (cosmosOf (gplate @(Expr Resolved))) e
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
isEffectful env = anyOf (cosmosOf (gplate @(Expr Resolved))) $ \case
  App _ r (_ : _) -> Set.member (getUnique r) env.effectfulRules
  AppNamed _ r _ _ -> Set.member (getUnique r) env.effectfulRules
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
    direct = Set.fromList [u | (u, body) <- bodies, anyOf (cosmosOf (gplate @(Expr Resolved))) touchesWorld body]
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

-- | The C1 key of a term (see the module header).
termKey :: KeyEnv -> Expr Resolved -> Text
termKey env expr =
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
        $ over (gplate @Anno) (const emptyAnno) inlined

    -- JSONDECODE decodes into its node's inferred type, which is an annotation,
    -- so the stripped term no longer says what it decodes into: keep each
    -- decode's type beside it, in traversal order.
    decodes = case decodeTypes of
      [] -> ""
      tys -> "|decodes " <> Text.pack (show (map (fmap nameKey) tys))
    decodeTypes =
      [ eraseInfVars (over (gplate @Anno) (const emptyAnno) (env.expandType ty))
      | App (Anno {extra = Extension {resolvedInfo = Just (TypeInfo ty _)}}) r _ <- toListOf (cosmosOf (gplate @(Expr Resolved))) inlined
      , getUnique r == jsonDecodeUnique
      ]

    nameKey r =
      let u = getUnique r
       in if
            | u.moduleUri == boundUri -> "bound#" <> Text.pack (show u.unique)
            | u.moduleUri == supplyUri -> Text.pack (show ("WITH" :: Text, nameText r))
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
-- @f WITH b IS y, a IS x@ and @f x y@ key alike. The checker records which
-- parameter each argument supplies; a negative entry supplies a section binder
-- rather than a parameter, and such a call keeps its named form, with each
-- supply keyed by the name it supplies.
positional :: Expr Resolved -> Expr Resolved
positional = transformOf (gplate @(Expr Resolved)) $ \case
  AppNamed ann f nes (Just order)
    | sort order == [0 .. length nes - 1] ->
        App ann f [e | i <- [0 .. length nes - 1], (MkNamedExpr _ _ e, j) <- zip nes order, j == i]
    -- Some arguments supply section binders (a negative entry). The checker
    -- resolves such a name in the CALLER's scope, but what it supplies is matched
    -- by name, so the same call written in two sections names two binders for
    -- one supply. Key a supply by the name it supplies, after the parameters, in
    -- name order.
    | otherwise ->
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
