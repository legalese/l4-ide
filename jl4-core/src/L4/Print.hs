module L4.Print where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import L4.Evaluate.ValueLazy as Lazy
import qualified L4.Lexer as Lexer
import L4.Print.Columnar (Cell, Grid, DittoOpts, defaultDittoOpts, renderDittoGrid)
import L4.Syntax
import qualified L4.TypeCheck.Environment as TCEnv
import qualified L4.TypeCheck.Types as TC

import Data.Char
import Data.Time (UTCTime, toGregorian)
import Data.Time.LocalTime (TimeOfDay(..))
import qualified Data.Time.Format as TimeFormat
import qualified Data.Time.Zones as TZ
import qualified Data.Time.Zones.All as TZAll
import qualified Data.Text.Encoding as TE
import Control.Exception (SomeException, catch)
import qualified Optics
import System.IO.Unsafe (unsafePerformIO)
import Prettyprinter
import Prettyprinter.Render.Text
import qualified Data.List.NonEmpty as NE
import L4.Utils.Ratio (prettyRatio)
import L4.Evaluate.Operators
import L4.Names
import L4.Desugar
import Control.Category ((>>>))
import System.FilePath (takeFileName)

prettyLayout :: LayoutPrinter a => a -> Text
prettyLayout a = docText $ printWithLayout a

docText :: Doc ann -> Text
docText = renderStrict . layoutPretty (LayoutOptions Unbounded)

-- | A map from constructor 'Unique' to its field names (in order).
-- Used for pretty-printing constructor values with named fields.
type ConstructorFieldNames = Map Unique [Text]

-- | Build a 'ConstructorFieldNames' map from type-checker 'EntityInfo'.
-- For each constructor, extracts the parameter names from its function type.
extractConstructorFieldNames :: TC.EntityInfo -> ConstructorFieldNames
extractConstructorFieldNames ei = Map.fromList
  [ (u, names)
  | (u, (_name, TC.KnownTerm ty Constructor)) <- Map.toList ei
  , let names = fieldNamesFromType ty
  , not (null names)
  ]
  where
    fieldNamesFromType :: Type' Resolved -> [Text]
    fieldNamesFromType (Fun _ params _) = mapMaybe paramName params
    fieldNamesFromType (Forall _ _ inner) = fieldNamesFromType inner
    fieldNamesFromType _ = []

    paramName :: OptionallyNamedType Resolved -> Maybe Text
    paramName (MkOptionallyNamedType _ (Just n) _) = Just (resolvedToText n)
    paramName _ = Nothing

    resolvedToText :: Resolved -> Text
    resolvedToText r = case rawName (getActual r) of
      NormalName t -> t
      QualifiedName _ t -> t
      PreDef t -> t

-- | Hack to get the lines of a document as 'Doc'. Used for the trace printer
-- and in situations where we need to prefix all the lines with something else.
--
docLines :: Doc ann -> [Doc ann]
docLines = fmap pretty . Text.lines . docText

prettyLayout' :: LayoutPrinter a => a -> String
prettyLayout' = Text.unpack . prettyLayout

-- | Ditto-aware printer for 'MultiWayIf' (BUILD-SPEC §5.2, preferred minimal
-- wiring). Renders the @BRANCH@ header structurally and delegates the arm block
-- to 'renderDittoGrid' so that repeated guard tokens collapse to column-aligned
-- carets (@^@). For any other expression it falls back to the canonical
-- 'prettyLayout', leaving the default printer untouched.
--
-- This adds NO AST node: ditto is an emission-layer concern only. The guard of
-- each arm is decomposed into per-field @[field, operator, value]@ slots with an
-- @AND@ connector between present conjuncts; @IF@, @THEN@ and the result
-- expression are kept spelled out on every arm (only the guard cells ditto). The
-- shared field ordering across arms is what makes column @j@ a stable logical
-- slot — the precondition 'renderDittoGrid' needs to align carets correctly.
prettyLayoutDitto :: LayoutPrinterWithName a => DittoOpts -> Expr a -> Text
prettyLayoutDitto opts = \ case
  MultiWayIf _ conds o ->
    let grid      = multiWayIfGrid conds
        gridText  = renderDittoGrid opts grid
        gridLines = if null conds then [] else Text.splitOn "\n" gridText
        results   = map (\ (MkGuardedExpr _ _ r) -> prettyLayout r) conds
        armLines  = zipWith (\ g r -> "  IF " <> g <> " THEN " <> r) gridLines results
        otherLine = "  OTHERWISE " <> prettyLayout o
    in Text.intercalate "\n" (["BRANCH"] <> armLines <> [otherLine])
  e -> prettyLayout e

-- | 'prettyLayoutDitto' with 'defaultDittoOpts'.
prettyLayoutDitto' :: LayoutPrinterWithName a => Expr a -> Text
prettyLayoutDitto' = prettyLayoutDitto defaultDittoOpts

-- | Build the guard 'Grid' for a list of BRANCH arms. Each arm's guard is split
-- into conjuncts (an @AND@-chain), each conjunct into @[field, op, value]@; the
-- conjuncts are then placed into columns keyed by field text, using first-
-- appearance order across all arms so identical fields share a column.
multiWayIfGrid :: LayoutPrinterWithName a => [GuardedExpr a] -> Grid
multiWayIfGrid conds = map row armConjs
  where
    guardOf :: GuardedExpr a -> Expr a
    guardOf (MkGuardedExpr _ g _) = g

    -- per arm: the list of (field-key, [fieldCell, opCell, valCell]) conjuncts
    armConjs :: [[(Text, [Cell])]]
    armConjs = map (map conjunctCells . scanAnd . guardOf) conds

    -- global column order: every distinct field, first-appearance order
    fieldOrder :: [Text]
    fieldOrder = nub [ k | arm <- armConjs, (k, _) <- arm ]

    row :: [(Text, [Cell])] -> [Cell]
    row arm = concat (zipWith fieldBlock [0 ..] fieldOrder)
      where
        present :: Text -> Bool
        present k = isJust (lookup k arm)

        anyEarlier :: Int -> Bool
        anyEarlier idx = any present (take idx fieldOrder)

        fieldBlock :: Int -> Text -> [Cell]
        fieldBlock idx k =
          let conn = if idx > (0 :: Int)
                       then [ if present k && anyEarlier idx then Just "AND" else Nothing ]
                       else []
              body = fromMaybe [Nothing, Nothing, Nothing] (lookup k arm)
          in conn <> body

-- | Decompose one guard conjunct into a field key plus its @[field, op, value]@
-- cells. Recognised comparison operators get a three-cell decomposition;
-- anything else becomes a single spelled-out cell (keyed by its own text) with
-- empty operator/value slots.
conjunctCells :: LayoutPrinterWithName a => Expr a -> (Text, [Cell])
conjunctCells e = case e of
  Equals _ l r -> cmp l "EQUALS"        r
  Leq    _ l r -> cmp l "AT MOST"       r
  Geq    _ l r -> cmp l "AT LEAST"      r
  Lt     _ l r -> cmp l "LESS THAN"     r
  Gt     _ l r -> cmp l "GREATER THAN"  r
  _            -> let t = prettyLayout e in (t, [Just t, Nothing, Nothing])
  where
    cmp :: LayoutPrinterWithName a => Expr a -> Text -> Expr a -> (Text, [Cell])
    cmp l op r =
      let lt = prettyLayout l
      in (lt, [Just lt, Just op, Just (prettyLayout r)])

-- | 'vcat' whose line breaks cannot be flattened away.
--
-- Prettyprinter's 'vcat'/'vsep' separators are @FlatAlt Line _@: inside a
-- 'group' — which 'prettyConj' and 'printLetBinding' both introduce, and which
-- @layoutPretty (LayoutOptions Unbounded)@ always resolves in favour of the
-- flattened branch — they collapse to nothing (or to a space), jamming keywords
-- together: @PARTY AliceMUST deliverWITHIN 5HENCE FULFILLEDLEST BREACH@. Those
-- newlines are load-bearing for the layout parser, so every structural break in
-- this module uses 'hardline', which 'flatten' turns into a failure and so
-- forces 'group' to keep the vertical rendering.
vcatHard :: [Doc ann] -> Doc ann
vcatHard = concatWith (\ x y -> x <> hardline <> y)

-- | Builtins that survive type checking as an @App@ of their own name, but
-- whose surface syntax is a prefix KEYWORD rather than @f OF x@. 'carameliseNode'
-- restores the operators listed in 'L4.Desugar.builtinUnaryFunctions' (only
-- @NOT@); FETCH and ENV are desugared the same way but are not on that list, so
-- the printer has to recognise them here or emit @ENV OF "HOME"@, which the
-- lexer reads as the keyword ENV followed by a stray OF.
prefixKeywordBuiltin :: RawName -> Maybe (Doc ann)
prefixKeywordBuiltin r
  | t == nameText TCEnv.fetchName = Just "FETCH"
  | t == nameText TCEnv.envName   = Just "ENV"
  | otherwise                     = Nothing
  where
    t = rawNameToText r
    nameText = rawNameToText . rawName

quotedName :: Name -> Text
quotedName n =
    renderStrict
  $ layoutPretty (LayoutOptions Unbounded)
  $ pretty . quote . rawNameToText . rawName $ n

class LayoutPrinter a where
  printWithLayout :: a -> Doc ann
  parensIfNeeded :: a -> Doc ann
  parensIfNeeded = printWithLayout

type LayoutPrinterWithName name = (LayoutPrinter name, HasName name)

instance LayoutPrinter Name where
  printWithLayout n = printWithLayout (rawName n)

instance LayoutPrinter Resolved where
  printWithLayout r = printWithLayout (getActual r)

-- | The prefix spelling of a canonical mixfix name, if this is one.
--
-- The type checker resolves a mixfix call site (@3 \`plus\` 5@) to the
-- operator's CANONICAL name — the slot/keyword pattern @_ plus _@ — while the
-- DEFINITION keeps only the head keyword (@DECIDE plus a b IS …@, which is what
-- 'L4.Mixfix' restructures the AppForm to). Printing the canonical name at the
-- call site therefore emits an identifier that is defined nowhere: "I could not
-- find a definition for the identifier @`_ plus _`@".
--
-- The head keyword is the first maximal run of non-slot tokens: @_ plus _@ →
-- @plus@, @_ is eligible for _@ → @is eligible for@,
-- @myif _ mythen _ myelse _@ → @myif@, @_ percent@ → @percent@. Measured
-- against the parser on the four shapes in @mixfix-basic.l4@: @plus OF 3, 5@,
-- @percent OF 50@, @`is eligible for` OF "a", "b"@ and @myif OF TRUE, 42, 0@
-- all type-check against the mixfix definitions.
--
-- A name that is ONLY slots (the @_@ wildcard) is left alone.
--
-- The leading\/trailing-slot guard is what keeps this from rewriting a name the
-- AUTHOR wrote. A backtick-quoted identifier may contain anything printable
-- (@L4.Lexer.quotedIdentifier@), so @`a _ b`@ is a perfectly ordinary function
-- name with the same word shape as a canonical pattern; without the guard it
-- printed as @a@, which silently renames it and collides with any real @a@ in
-- scope. Measured: @`a _ b` OF n@ alongside @a OF n@ round-tripped correctly
-- before the mixfix repair and failed after it with "multiple definitions for
-- the identifier a".
--
-- The guard costs nothing, because a canonical name that a CALL SITE can carry
-- always has a slot at one end: 'L4.Mixfix.buildCanonicalNameFromKeywords' — the
-- only reconstruction the type checker performs at a use — emits
-- @_ kw _ kw _@ for a param-first pattern and @kw _ kw _@ for a keyword-first
-- one. Both end in @_@. A @kw _ kw@ circumfix is unreachable for the same
-- reason, and indeed does not type-check today: @`mag` n `stop` MEANS …@ is
-- read as a one-argument @mag@ applied to two arguments.
--
-- KNOWN BOUND. Two operators that share a head keyword, an arity and an
-- argument type vector print to the same text and the module then fails to
-- re-check with "There are multiple definitions for the identifier". The corpus
-- witness is @ok/mixfix-garden-path.l4@ — @tax on _ item costing _ as GST in _@
-- beside @tax on _ item costing _ as VAT in _@ — and it only stays green
-- because both call sites live in @#EVAL@ directives, which
-- 'L4.DirectiveFilter.filterIdeDirectives' strips before @l4 batch@ prints. It
-- is a LOUD failure, and it is not a regression: before the head-keyword repair
-- the same file printed @`_ tax on _ item costing _ as VAT in _`@, an
-- identifier defined nowhere.
--
-- Re-emitting the SURFACE form instead (interleaving the arguments back into
-- the pattern, @`tax on` c `item costing` p `as GST in` k@) was built and
-- MEASURED, and it does not work: a DEFINITION prints from its restructured
-- AppForm, i.e. @DECIDE andop a b c IS …@, so the printed module registers a
-- plain n-ary function and no longer has the later keywords to match against.
-- @ok/fixity-nary-guard.l4@'s @1 andop 2 hadop 3@ went from evaluating to 1006
-- to failing resolution outright. Call sites and definitions have to agree, and
-- the head keyword is the only spelling both can produce. A real fix needs the
-- mixfix registry ('L4.Mixfix.MixfixRegistry', already threaded into
-- 'L4.Export.Document' by 'mixfixHeadingsFromRegistry') to reach the printer.
mixfixHeadKeyword :: Text -> Maybe Text
mixfixHeadKeyword t = case mixfixSlots t of
  Just ws | kws@(_ : _) <- takeWhile (/= "_") (dropWhile (== "_") ws)
          -> Just (Text.unwords kws)
  _ -> Nothing

-- | The word list of a canonical mixfix name, if @t@ is shaped like one.
mixfixSlots :: Text -> Maybe [Text]
mixfixSlots t = case Text.words t of
  ws | "_" `elem` ws
     , listToMaybe ws == Just "_" || listToMaybe (reverse ws) == Just "_"
     -> Just ws
  _ -> Nothing

instance LayoutPrinter RawName where
  printWithLayout = \ case
    NormalName t -> pretty $ quoteIfNeeded (fromMaybe t (mixfixHeadKeyword t))
    -- Emit the section-qualified *syntax* (@`Section A`.sharedValue@), which is
    -- what 'L4.Parser.qualifiedName' reads back. The former rendering
    -- (@sharedValue (qualified at section Section A)@) was a debugging gloss
    -- that no parser accepts, so any module using a cross-section reference
    -- printed to unparseable source.
    QualifiedName qs t ->
      pretty (Text.intercalate "." (fmap quoteIfNeeded (NE.toList qs) <> [quoteIfNeeded t]))
    PreDef t -> pretty $ quoteIfNeeded t

instance LayoutPrinterWithName a => LayoutPrinter (Type' a) where
  printWithLayout = \ case
    Type _ -> "TYPE"
    -- A type application's arguments are COMMA-separated, so a nested
    -- application flattens ambiguously: `PAIR OF PAIR OF NUMBER, NUMBER, PAIR
    -- OF NUMBER, NUMBER` re-parses as a four-argument PAIR. The source keeps
    -- them apart with layout; on one line only brackets will do. (Measured:
    -- `PAIR OF (PAIR OF NUMBER, NUMBER), (PAIR OF NUMBER, NUMBER)` checks.)
    TyApp _ n ps -> printWithLayout n <> case ps of
      [] -> mempty
      params@(_:_) -> space <> "OF" <+> hsep (punctuate comma (fmap parensIfNeeded params))
    -- `FUNCTION FROM … AND … TO …` needs no brackets: its separators are
    -- keywords, not commas, so a nested application cannot run past them.
    Fun _ args ty ->
      "FUNCTION FROM" <+> hsep (punctuate (space <> "AND") (fmap printWithLayout args))
        <+> "TO" <+> printWithLayout ty
    Forall _ vals ty -> "FOR ALL" <+> hsep (punctuate (space <> "AND") (fmap printWithLayout vals))
        <+> printWithLayout ty
    InfVar _ raw uniq -> printWithLayout raw <> pretty uniq

  parensIfNeeded :: LayoutPrinterWithName a => Type' a -> Doc ann
  parensIfNeeded t = case t of
    Type _        -> printWithLayout t
    TyApp _ _ []  -> printWithLayout t
    InfVar{}      -> printWithLayout t
    _             -> surround (printWithLayout t) "(" ")"

-- | Render a type for user-facing display. Residual inference variables carry a
-- global, edit-order-dependent id (e.g. @res184@, @A3@) — the 'InfVar' instance
-- above prints @prefix <> uniq@. Left raw, that makes hover and the deployed
-- schema's @returnType@ non-deterministic across compiles, which trips the
-- deploy breaking-change check. Here we normalise every inference variable to a
-- stable type-variable name (@a@, @b@, @c@, …) by order of first appearance.
-- The plain 'prettyLayout' instance keeps the raw id, which is what we want for
-- internal debugging.
prettyTypeForDisplay :: Type' Resolved -> Text
prettyTypeForDisplay ty = docText (goDisplayTy naming ty)
  where
    naming = Map.fromList (zip (collectInfVarUniques ty) displayTypeVarNames)

-- | Distinct inference-variable uniques, in order of first appearance.
collectInfVarUniques :: Type' Resolved -> [Int]
collectInfVarUniques = ordNub . go
  where
    ordNub = foldr (\x xs -> x : filter (/= x) xs) []
    go = \ case
      Type _          -> []
      TyApp _ _ ps     -> concatMap go ps
      Fun _ args ty'   -> concatMap (go . ontType) args <> go ty'
      Forall _ _ ty'   -> go ty'
      InfVar _ _ uniq  -> [uniq]
    ontType (MkOptionallyNamedType _ _ t) = t

-- | a, b, …, z, a1, b1, … — an unbounded, stable supply of display names.
displayTypeVarNames :: [Text]
displayTypeVarNames =
  [ Text.singleton c | c <- ['a' .. 'z'] ]
  <> [ Text.singleton c <> Text.pack (show n) | n <- [(1 :: Int) ..], c <- ['a' .. 'z'] ]

-- | Mirror of the 'Type'' layout instance, but emit the normalised name for
-- each inference variable (falling back to a hole when, defensively, a uniq is
-- somehow missing from the map).
goDisplayTy :: Map Int Text -> Type' Resolved -> Doc ann
goDisplayTy m = \ case
  Type _ -> "TYPE"
  TyApp _ n ps -> printWithLayout n <> case ps of
    [] -> mempty
    params@(_ : _) -> space <> "OF" <+> hsep (punctuate comma (fmap (goDisplayTy m) params))
  Fun _ args ty' ->
    "FUNCTION FROM" <+> hsep (punctuate (space <> "AND") (fmap (goDisplayTy m . ontType) args))
      <+> "TO" <+> goDisplayTy m ty'
  Forall _ vals ty' ->
    "FOR ALL" <+> hsep (punctuate (space <> "AND") (fmap printWithLayout vals)) <+> goDisplayTy m ty'
  InfVar _ _ uniq -> pretty (Map.findWithDefault "_" uniq m)
  where
    ontType (MkOptionallyNamedType _ _ t) = t

-- We currently have no syntax for actual names occurring here
instance LayoutPrinterWithName a => LayoutPrinter (OptionallyNamedType a) where
  printWithLayout = \ case
    MkOptionallyNamedType _ _ ty ->
      printWithLayout ty
  parensIfNeeded = \ case
    MkOptionallyNamedType _ _ ty -> parensIfNeeded ty

-- | Does this type mention an inference variable?
--
-- An 'InfVar' is a hole the CHECKER opened while inferring, and the 'Type''
-- instance renders it as its seed name plus a global counter — @x809@,
-- @purpose254@. That gensym is not an identifier in any scope, so emitting one
-- turns a binder the author deliberately left unannotated into a reference to
-- something undefined. See 'OptionallyTypedName' below.
hasInferenceVariable :: Type' a -> Bool
hasInferenceVariable = \ case
  InfVar{}        -> True
  Type _          -> False
  TyApp _ _ ps    -> any hasInferenceVariable ps
  Fun _ args ty   -> any (hasInferenceVariable . ontType) args || hasInferenceVariable ty
  Forall _ _ ty   -> hasInferenceVariable ty
  where
    ontType (MkOptionallyNamedType _ _ t) = t

instance LayoutPrinterWithName a => LayoutPrinter (OptionallyTypedName a) where
  printWithLayout = \ case
    MkOptionallyTypedName _ a ty typically ->
      -- Drop an annotation the checker invented. `GIVEN x YIELD x` type-checks
      -- to `MkOptionallyTypedName x (Just (InfVar "x" 12))`, which printed as
      -- `GIVEN x IS x12 YIELD x` — source that parses and then fails with "I
      -- could not find a definition for the identifier x12". The binder's type
      -- is optional in the grammar precisely because it can be re-inferred, so
      -- the repair is to emit what the author wrote and let the checker do its
      -- job again. This is the gensym leak PR legalese#206 reported as
      -- `GIVEN purpose IS purpose254` reaching the DMN exporter's raw-L4
      -- fallback.
      printWithLayout a <> case ty of
        Just ty' | not (hasInferenceVariable ty') -> space <> "IS" <+> printWithLayout ty'
        _ -> mempty
      <> case typically of
        Nothing -> mempty
        Just e -> space <> "TYPICALLY" <+> printWithLayout e

instance LayoutPrinterWithName a => LayoutPrinter (TypedName a) where
  printWithLayout = \ case
    MkTypedName _ a ty mTypically Nothing ->
      printWithLayout a <+> "IS" <+> printWithLayout ty
        <> printTypically mTypically
    MkTypedName _ a ty mTypically (Just meansExpr) ->
      align $ vcatHard
        [ printWithLayout a <+> "IS" <+> printWithLayout ty <> printTypically mTypically
        , indent 4 ("MEANS" <+> printWithLayout meansExpr)
        ]
    where
      printTypically = \ case
        Nothing -> mempty
        Just e -> space <> "TYPICALLY" <+> printWithLayout e

instance LayoutPrinterWithName a => LayoutPrinter (TypeSig a) where
  printWithLayout = \ case
    MkTypeSig _ given mGiveth ->
      case given of
        MkGivenSig _ [] -> case mGiveth of
          Just giveth -> printWithLayout giveth
          Nothing -> mempty
        MkGivenSig _ (_:_) ->
          printWithLayout given <> case mGiveth of
            Just giveth -> line <> printWithLayout giveth
            Nothing -> mempty

instance LayoutPrinterWithName a => LayoutPrinter (GivenSig a) where
  printWithLayout = \ case
    MkGivenSig _ ns -> case ns of
      [] -> mempty
      names@(_:_) -> "GIVEN" <+> align (vcatHard (fmap printWithLayout names))

instance LayoutPrinterWithName a => LayoutPrinter (GivethSig a) where
  printWithLayout = \ case
    MkGivethSig _ ty -> "GIVETH" <+> printWithLayout ty

instance LayoutPrinterWithName a => LayoutPrinter (Declare a) where
  printWithLayout = \ case
    MkDeclare _ tySig appForm tyDecl  ->
      -- `vcatHard` (not `fillCat`, and not `vcat`): under the Unbounded layout
      -- `fillCat`'s separators render empty, and a plain `vcat` flattens to the
      -- same thing inside a `group`, jamming a non-empty GIVEN signature
      -- straight onto `DECLARE` (`... IS TYPEDECLARE ...`), which does not
      -- re-parse. Mirrors the Decide instance below.
      vcatHard
        [ printWithLayout tySig
        , "DECLARE" <+> printWithLayout appForm
        , indent 2 (printWithLayout tyDecl)
        ]

instance LayoutPrinterWithName a => LayoutPrinter (AppForm a) where
  printWithLayout = \ case
    MkAppForm _ n ns maka ->
      (printWithLayout n <> case ns of
        [] -> mempty
        _ -> space <> hsep (fmap printWithLayout ns)
      ) <>
      case maka of
        Nothing  -> mempty
        Just aka -> space <> printWithLayout aka

instance LayoutPrinterWithName a => LayoutPrinter (Aka a) where
  printWithLayout = \ case
    -- `hsep`, not `vsep`: the alias list is comma-separated, so a line break
    -- between aliases would leave a dangling comma for the layout parser.
    MkAka _ ns -> "AKA" <+> hsep (punctuate comma $ fmap printWithLayout ns)

instance LayoutPrinterWithName a => LayoutPrinter (TypeDecl a) where
  printWithLayout = \ case
    RecordDecl _ _ fields  ->
      vcatHard
        [ "HAS"
        , indent 2 (vcatHard (fmap printWithLayout fields))
        ]
    EnumDecl _ enums ->
      vcatHard
        [ "IS ONE OF"
        , indent 2 (vcatHard (fmap printWithLayout enums))
        ]
    SynonymDecl _ t ->
      vcatHard
        [ "IS"
        , indent 2 (printWithLayout t)
        ]

instance LayoutPrinterWithName a => LayoutPrinter (ConDecl a) where
  printWithLayout = \ case
    MkConDecl _ n fields  ->
      printWithLayout n <> case fields of
        [] -> mempty
        -- One field per line, column-aligned and WITHOUT commas. A trailing
        -- comma is not a separator the layout parser can see past here: it is
        -- swallowed by the preceding field's own type-argument list
        -- (`Node HAS left IS Tree OF a,` continues `OF a, …`), which is how
        -- `datatypes.l4` printed source the parser rejected.
        _:_ -> space <> "HAS" <+> align (vcatHard (fmap printWithLayout fields))

instance LayoutPrinterWithName a => LayoutPrinter (Assume a) where
  printWithLayout = \ case
    MkAssume _ tySig appForm ty typically ->
      -- `vcatHard` (not `fillCat`): see the Declare note above — `fillCat` jams
      -- a non-empty GIVEN signature onto `ASSUME` under the Unbounded layout.
      vcatHard
        [ printWithLayout tySig
        , "ASSUME" <+> printWithLayout appForm <> case ty of
            Nothing -> mempty
            Just ty' -> space <> "IS" <+> printWithLayout ty'
          <> case typically of
            Nothing -> mempty
            Just e -> space <> "TYPICALLY" <+> printWithLayout e
        ]

instance LayoutPrinterWithName a => LayoutPrinter (Decide a) where
  printWithLayout = \ case
    MkDecide ann tySig appForm expr ->
      vcatHard $
        -- Re-emit the desc annotation: its leading keywords carry the
        -- @export/@nonexhaustive flags, so a printed module must round-trip it.
        -- 'l4 batch' re-typechecks the printed source; dropping the desc
        -- here used to strip @nonexhaustive from the generated wrapper module,
        -- resurrecting the suppressed missing-branch warning and failing
        -- every batch row of a deliberately-partial exported function.
        [ "@desc" <+> pretty (Text.strip (getDesc d))
        | Just d <- [Optics.view annDesc ann]
        ]
        <>
        [ printWithLayout tySig
        , "DECIDE" <+> printWithLayout appForm <+> "IS"
        , indent 2 (printWithLayout expr)
        ]

instance LayoutPrinterWithName a => LayoutPrinter (Directive a) where
  printWithLayout = \ case
    LazyEval _ e ->
      "#EVAL" <+> printWithLayout e
    LazyEvalTrace _ e ->
      "#EVALTRACE" <+> printWithLayout e
    Check _ e ->
      "#CHECK" <+> printWithLayout e
    -- NOTE: AT and WITH are mandatory in the #TRACE grammar, and the events
    -- are parsed with layout ('lmany'), so they must each go on their own
    -- (indented) line for the printed directive to round-trip through the
    -- parser (e.g. for @l4 batch@'s print-and-reparse of the module).
    Contract _ e t stmts -> vcatHard $
      ("#TRACE" <+> printWithLayout e <+> "AT" <+> printWithLayout t <+> "WITH") :
      map (indent 2 . printWithLayout) stmts
    Assert _ e ->
      "#ASSERT" <+> printWithLayout e

instance LayoutPrinterWithName a => LayoutPrinter (Import a) where
  printWithLayout = \ case
    MkImport _ n _mr -> "IMPORT" <+> printWithLayout n

instance (LayoutPrinterWithName a, n ~ Int) => LayoutPrinter (n, Section a) where
  printWithLayout = \ case
    -- An anonymous section carries no heading, so it adds no LEVEL either: its
    -- children stay at `i`. Incrementing here pushed every top-level `§` in the
    -- module out to `§§` (the module's root section is the anonymous one), and
    -- section-qualified resolution is level-sensitive — `\`Beta\`.yes` stopped
    -- resolving in the re-emitted `cross-section-qualified-additive.l4` for
    -- exactly this reason, and re-resolved as soon as the headings were shifted
    -- back by one.
    (i, MkSection _ Nothing _ ds)    ->
      vcatHard (map (printWithLayout . (i ,)) ds)
    (i, MkSection _ name maka ds) ->
      vcatHard $
        [ pretty (replicate i '§') <+>
          case maka of
            Nothing  -> maybe mempty printWithLayout name
            Just aka -> maybe mempty printWithLayout name <+> printWithLayout aka
        ]
        <> case ds of
          [] -> mempty
          _ -> map (printWithLayout . (i + 1 ,)) ds

instance LayoutPrinterWithName a => LayoutPrinter (Module  a) where
  printWithLayout = \ case
    MkModule _ _ sect -> printWithLayout (1, sect)

instance LayoutPrinterWithName a => LayoutPrinter (TopDecl a) where
  printWithLayout t = printWithLayout (1, t)

instance (LayoutPrinterWithName a, n ~ Int) => LayoutPrinter (n, TopDecl a) where
  printWithLayout = \ case
    (_, Declare   _ t) -> printWithLayout t
    (_, Decide    _ t) -> printWithLayout t
    (_, Assume    _ t) -> printWithLayout t
    (_, Directive _ t) -> printWithLayout t
    (_, Import    _ t) -> printWithLayout t
    (i, Section   _ t) -> printWithLayout (i, t)
    (_, Timezone  _ e) -> "TIMEZONE IS" <+> printWithLayout e

instance LayoutPrinterWithName a => LayoutPrinter (Expr a) where
  printWithLayout :: LayoutPrinter a => Expr a -> Doc ann
  printWithLayout = carameliseNode >>> \ case
    e@And{} ->
      let
        conjunction = scanAnd e
      in
        prettyConj "AND" (fmap parensIfOpenTailed conjunction)
    e@Or{} ->
      let
        disjunction = scanOr e
      in
        prettyConj "OR" (fmap parensIfOpenTailed disjunction)
    e@RAnd{} ->
      let
        conjunction = scanRAnd e
      in
        prettyConj "RAND" (fmap parensIfOpenTailed conjunction)
    e@ROr{} ->
      let
        disjunction = scanROr e
      in
        prettyConj "ROR" (fmap parensIfOpenTailed disjunction)
    Implies    _ e1 e2 ->
      parensIfNeeded e1 <+> "IMPLIES" <+> parensIfNeeded e2
    Equals     _ e1 e2 ->
      parensIfNeeded e1 <+> "EQUALS" <+> parensIfNeeded e2
    Not        _ e1 ->
      "NOT" <+> printWithLayout e1
    Plus       _ e1 e2 ->
      parensIfNeeded e1 <+> "PLUS" <+> parensIfNeeded e2
    Minus      _ e1 e2 ->
      parensIfNeeded e1 <+> "MINUS" <+> parensIfNeeded e2
    Times      _ e1 e2 ->
      parensIfNeeded e1 <+> "TIMES" <+> parensIfNeeded e2
    DividedBy  _ e1 e2 ->
      parensIfNeeded e1 <+> "DIVIDED BY" <+> parensIfNeeded e2
    Modulo     _ e1 e2 ->
      parensIfNeeded e1 <+> "MODULO" <+> parensIfNeeded e2
    Cons       _ e1 e2 ->
      parensIfNeeded e1 <+> "FOLLOWED BY" <+> parensIfNeeded e2
    Leq        _ e1 e2 ->
      parensIfNeeded e1 <+> "AT MOST" <+> parensIfNeeded e2
    Geq        _ e1 e2 ->
      parensIfNeeded e1 <+> "AT LEAST" <+> parensIfNeeded e2
    Lt         _ e1 e2 ->
      parensIfNeeded e1 <+> "LESS THAN" <+> parensIfNeeded e2
    Gt         _ e1 e2 ->
      parensIfNeeded e1 <+> "GREATER THAN" <+> parensIfNeeded e2
    Proj       _ e1 n ->
      parensIfNeeded e1 <> "'s" <+> printWithLayout n
    Var        _ n ->
      printWithLayout n
    Lam        _ given expr ->
      printWithLayout given <+> "YIELD" <+> printWithLayout expr
    -- FETCH/ENV survive type checking as ordinary applications of their builtin
    -- names ('L4.TypeCheck.desugarUnaryOpToFunction'), and 'carameliseNode'
    -- only un-desugars the operators in 'builtinUnaryFunctions'. Printing them
    -- as applications yields `ENV OF "HOME"`, but ENV and FETCH are *keywords*
    -- with a prefix grammar, so that never re-parses.
    App        _ n [e] | Just kw <- prefixKeywordBuiltin (rawName (getName n)) ->
      kw <+> parensIfNeeded e
    App        _ n es -> printWithLayout n <> case es of
      [] -> mempty
      exprs@(_:_) -> space <> "OF" <+> hsep (punctuate comma (fmap parensIfNeeded exprs))
    AppNamed   _ n namedExpr _ ->
          printWithLayout n
      <+> "WITH"
      <+> align (vcatHard (fmap printWithLayout namedExpr))
    IfThenElse _ cond then' else' ->
      -- Use single-line format to avoid layout/indentation issues when re-parsing
      "IF" <+> parensIfNeeded cond
        <+> "THEN" <+> parensIfNeeded then'
        <+> "ELSE" <+> parensIfNeeded else'
    -- `hang 2`: every arm must be indented STRICTLY past the BRANCH keyword's
    -- own column ('L4.Parser.multiWayIf' threads that column into each
    -- 'parseGuardedExpr'), and `hang` measures from the keyword rather than
    -- from the enclosing nesting level, so a BRANCH nested inside another
    -- construct still indents relative to itself.
    MultiWayIf _ conds o ->
      hang 2 $ vcatHard $
        [ "BRANCH" ]
        <> map (\(MkGuardedExpr _ a b) -> "IF" <+> printWithLayout a <+> "THEN" <+> printWithLayout b) conds
        <> [ "OTHERWISE" <+> printWithLayout o ]
    Regulative _ (MkDeonton _ p a t f l) -> prettyObligation p a t f l
    -- One branch per line, aligned, and WITHOUT the comma separator.
    -- 'L4.Parser.consider' reads the branch list with `lsepBy`, i.e.
    -- `manyLines` over comma-separated groups: continuation lines must start at
    -- EXACTLY the first branch's column, and a comma at end of line is instead
    -- eaten by whatever comma-list the branch body ended in (`… THEN LIST x,`
    -- continues the LIST). That pair of facts is smucclaw/l4-ide#932.
    Consider   _ expr branches ->
      hang 2 $ vcatHard $
        ("CONSIDER" <+> printWithLayout expr) : fmap printWithLayout branches

    Lit        _ lit -> printWithLayout lit
    Percent    _ expr -> parensIfNeeded expr <+> "%"
    List       _ exprs ->
      "LIST" <+> hsep (punctuate comma (fmap parensIfNeeded exprs))
    Where      _ e1 decls ->
      align $ vcatHard
        [ indent 2 (printWithLayout e1)
        , "WHERE"
        , indent 2 (vcatHard $ fmap printWithLayout decls)
        ]
    -- `align`: 'L4.Parser.letInExpr' indexes the bindings and the body off the
    -- LET keyword's own column, so an inline LET (`10 PLUS (LET …`) must indent
    -- relative to where LET actually sits, not to the enclosing statement.
    LetIn _ decls e1 ->
      align $ vcatHard
        [ "LET"
        , indent 2 (vcatHard $ fmap printLetBinding decls)
        , "IN"
        , indent 2 (printWithLayout e1)
        ]
    Event _ MkEvent {timestamp, party, action} ->
      align $ vcatHard
        [ "PARTY" <+> printWithLayout party
        , "DOES" <+> printWithLayout action
        , "AT" <+> printWithLayout timestamp -- TODO: better timestamp rendering
        ]
    Fetch _ e ->
      "FETCH" <+> printWithLayout e
    Env _ e ->
      "ENV" <+> printWithLayout e
    -- One argument per line, indented past POST. 'L4.Parser.postExpr' reads
    -- each of the three as a full `indentedExpr`, and on a single line the
    -- first one's mixfix chain swallows the other two — leaving nothing for
    -- argument 2, which then fails against whatever follows the POST. Measured:
    -- `POST "url" "hdr" body` on one line is rejected, the same three tokens on
    -- their own indented lines are accepted. `parensIfNeeded` in addition,
    -- because an application argument (`JSONENCODE OF (…)`) needs brackets.
    Post _ e1 e2 e3 ->
      hang 2 $ vcatHard
        [ "POST", parensIfNeeded e1, parensIfNeeded e2, parensIfNeeded e3 ]
    -- The genitive clitic is lexed as the literal string @'s@
    -- ('L4.Lexer.TGenitive'), and the parser spells the ledger qualifiers
    -- @<party>'s@ and @OFFICIAL's@ the same way. These three sites emitted an
    -- upper-case @'S@, which is not that token: every recipient-qualified
    -- RECORD/COMMIT/RECALL printed to source the lexer rejects with
    -- @unexpected '''@. (The 'Proj' instance above already had it right.)
    Record _ mParty cell val isOfficial mHence ->
      (if isOfficial then "COMMIT" else "RECORD")
        <> maybe mempty (\p -> space <> printWithLayout p <> "'s") mParty
        <+> printWithLayout cell <+> "IS" <+> printWithLayout val
        <> maybe mempty (\k -> " HENCE" <+> printWithLayout k) mHence
    ReadCell _ mParty isOfficial mode cell ->
      "RECALL"
        <> (case mode of RecallAll -> " ALL"; RecallLast -> mempty)
        <> (if isOfficial then " OFFICIAL's" else mempty)
        <> maybe mempty (\p -> space <> printWithLayout p <> "'s") mParty
        <+> printWithLayout cell
    Concat _ exprs ->
      "CONCAT" <+> hsep (punctuate comma (fmap parensIfNeeded exprs))
    AsString _ e ->
      parensIfNeeded e <+> "AS STRING"
    Breach _ mParty mReason ->
      "BREACH" <>
        maybe mempty (\p -> " BY" <+> printWithLayout p) mParty <>
        maybe mempty (\r -> " BECAUSE" <+> printWithLayout r) mReason
    -- An inert element is a bare string literal in boolean position; the
    -- type checker is what turns it into an 'Inert' node, and it will do so
    -- again on re-parse. `...` is NOT a prefix marker for one — it is the
    -- infix AND operator ('TEllipsis'), so the old rendering printed a binary
    -- operator with no left operand.
    Inert _ txt _ctx ->
      surround (pretty $ escapeStringLiteral txt) "\"" "\""

  parensIfNeeded :: LayoutPrinter a => Expr a -> Doc ann
  parensIfNeeded e = case e of
    Lit{} -> printWithLayout e
    App _ _ [] -> printWithLayout e
    Var{} -> printWithLayout e
    -- A BREACH with neither BY nor BECAUSE is a single keyword, i.e. an atom.
    Breach _ Nothing Nothing -> printWithLayout e
    _ -> surround (printWithLayout e) "(" ")"

-- | Bracket a conjunct of an @AND@/@OR@/@RAND@/@ROR@ chain, but only when its
-- rendering has an OPEN TAIL — a comma list, a clause list, a binding group —
-- that would otherwise swallow the connective that follows it.
--
-- @issuer is eligible OF plan AND rest@ re-parses as
-- @issuer is eligible OF (plan AND rest)@: it still parses, and then fails type
-- checking with the arguments transposed. That was the second half of
-- smucclaw/l4-ide#932 — @l4 batch@ on @regcf-wizard.l4@ got past the parser
-- only to be rejected by the checker. @PARTY … MUST … WITHIN …@ is the same
-- shape for the regulative connectives: the obligation has no closing token, so
-- a following @ROR@ reads as another of its own clauses.
--
-- A conjunct that is ITSELF a logical connective is the second reason, and it
-- is not about open tails at all — it is about grouping. @scanAnd@\/@scanOr@
-- flatten only their OWN operator, so an @And@ reaching this function is
-- necessarily nested inside an @Or@ (or a regulative chain), and vice versa;
-- printing it bare hands the grouping back to the parser's precedence table,
-- which does not agree with the tree. Measured, before this clause:
--
--   * @(TRUE OR FALSE) AND FALSE@ and @TRUE OR (FALSE AND FALSE)@ printed to
--     the SAME string, @TRUE OR FALSE AND FALSE@, so the first re-parsed as the
--     second and flipped from FALSE to TRUE;
--   * @(NOT TRUE) OR TRUE@ printed as @NOT TRUE OR TRUE@, which the parser
--     reads as @NOT (TRUE OR TRUE)@ — TRUE became FALSE;
--   * @(FALSE IMPLIES FALSE) AND FALSE@ likewise.
--
-- That is a SILENT wrong answer rather than a diagnostic: @ok/logic.l4@ went
-- from @LIST TRUE, TRUE, FALSE, FALSE@ to @LIST TRUE, TRUE, TRUE, TRUE@ and an
-- assertion in @legal/regcf/regcf.l4@ went from satisfied to failed, both
-- through @l4 batch@, with no error anywhere. Comparisons (@EQUALS@,
-- @GREATER THAN@, …) were measured SAFE in the same harness and stay bare, so
-- the corpus's @`mkt cap` GREATER THAN … AND …@ does not grow noise.
--
-- Everything else is CLOSED — the remaining binary operators bracket their own
-- operands, projection\/postfix bind tighter than a connective, literals and
-- variables are atoms — and the parser's precedence table reassembles the chain
-- correctly. Bracketing those too would be safe but is pure noise in every
-- rendering this printer feeds: evaluation traces, @#EVAL@ output, ladder
-- labels.
parensIfOpenTailed :: LayoutPrinterWithName a => Expr a -> Doc ann
parensIfOpenTailed e
  -- Classify what will be PRINTED, not what is stored: `carameliseNode` turns
  -- `App __GEQ__ [a, b]` back into `Geq a b`, and the printer applies it before
  -- rendering. Without it every desugared operator looks like an application
  -- and gets brackets it does not need (`(tranche AT LEAST 1) AND …`).
  | openTailed (carameliseNode e) = surround (printWithLayout e) "(" ")"
  | otherwise                     = printWithLayout e
  where
    openTailed = \ case
      -- Grouping, not tails: a connective nested in a chain of a DIFFERENT
      -- connective. See the note above — bare, these re-associate silently.
      And{}         -> True
      Or{}          -> True
      RAnd{}        -> True
      ROr{}         -> True
      Implies{}     -> True
      App _ _ (_:_) -> True  -- `f OF x, y` — comma-separated, open-ended
      AppNamed{}    -> True  -- `R WITH a IS 1` — open field list
      Concat{}      -> True  -- comma list
      List{}        -> True  -- comma list
      Consider{}    -> True  -- open branch list
      MultiWayIf{}  -> True  -- open arm list
      IfThenElse{}  -> True  -- the ELSE branch keeps consuming
      Regulative{}  -> True  -- open WITHIN/HENCE/LEST clause list
      Record{}      -> True  -- open HENCE continuation
      ReadCell{}    -> True
      LetIn{}       -> True  -- the IN body keeps consuming
      Where{}       -> True  -- open local-declaration block
      Lam{}         -> True  -- the YIELD body keeps consuming
      Breach _ Nothing Nothing -> False -- a bare BREACH is an atom
      Breach{}      -> True  -- open BY/BECAUSE clauses
      -- `NOT` binds LOOSER than the connectives, not tighter: measured,
      -- `NOT TRUE AND FALSE` evaluates as `NOT (TRUE AND FALSE)`. So a negated
      -- conjunct is always bracketed — inheriting the operand's tail was not
      -- enough, and `(NOT TRUE) OR TRUE` silently became `NOT (TRUE OR TRUE)`.
      Not{}         -> True
      Post{}        -> True  -- three juxtaposed arguments
      Event{}       -> True
      _             -> False

prettyObligation
  :: (LayoutPrinter p, LayoutPrinter a, LayoutPrinter t,  LayoutPrinter f, LayoutPrinter l)
  => p -> a ->  Maybe t -> Maybe f -> Maybe l -> Doc ann
-- | @group (hang 2 …)@: an obligation prints on ONE line whenever it can.
--
-- Two constraints meet here. (1) 'L4.Parser.obligation' takes the PARTY
-- keyword's own column as the threshold for the action pattern and the
-- WITHIN/HENCE/LEST bodies, all of which must be indented strictly past it — a
-- plain 'vcat' put them at the ENCLOSING nesting level, a column to the LEFT of
-- PARTY whenever the obligation is not the leftmost thing on its line (the usual
-- case: `HENCE RECORD "a" IS TRUE HENCE PARTY P`). (2) A @#TRACE@ directive is
-- line-oriented, so a contract expression broken across lines loses its own
-- @AT … WITH@.
--
-- 'group' satisfies (2): under the Unbounded layout the flattened branch always
-- fits, so the obligation collapses to a single well-formed line. When an
-- operand contains a hard break of its own (a nested CONSIDER, say) flattening
-- fails and 'hang' satisfies (1) by indenting relative to PARTY.
prettyObligation p a t f l =
  Prettyprinter.group $ hang 2 $ vsep $
    [ "PARTY" <+> printWithLayout p
    , printWithLayout a
    ]
    <> mprint "WITHIN" t
    <> mprint "HENCE" f
    <> mprint "LEST" l

-- | @WITHIN@/@HENCE@/@LEST@ bodies are bracketed via 'parensIfNeeded'.
--
-- A nested obligation in a HENCE slot has no closing token, so its own optional
-- HENCE/LEST clauses swallow the OUTER obligation's: printing
-- @HENCE PARTY Bob MUST deliver WITHIN 10@ followed by the outer @LEST@ makes
-- the inner obligation consume that LEST and then fail on its indentation. The
-- corpus writes these parenthesised for the same reason
-- (@HENCE (PARTY Bob MUST deliver WITHIN 10)@). Atoms — @FULFILLED@, a
-- deadline literal — are left bare by 'parensIfNeeded'.
mprint :: (Foldable t, LayoutPrinter a) => Doc ann -> t a -> [Doc ann]
mprint kw = foldMap \x -> [kw <+> parensIfNeeded x]

instance LayoutPrinterWithName n => LayoutPrinter (RAction n) where
  printWithLayout MkAction {modal, action, provided} = hsep $
    [ printDeonticModal modal, printWithLayout action
    ]
    <> mprint "PROVIDED" provided

-- | Print deontic modal keyword
printDeonticModal :: DeonticModal -> Doc ann
printDeonticModal = \case
  DMust -> "MUST"
  DMay -> "MAY"
  DMustNot -> "MUST NOT"
  DDo -> "DO"

instance LayoutPrinterWithName a => LayoutPrinter (NamedExpr a) where
  printWithLayout = \ case
    MkNamedExpr _ name e ->
      printWithLayout name <+> "IS" <+> printWithLayout e

-- | Print a LocalDecl in LET context (without DECIDE keyword and without type signature)
-- Uses "BE" as the binding keyword in honour of The Beatles' "Let It Be"
printLetBinding :: LayoutPrinterWithName a => LocalDecl a -> Doc ann
printLetBinding = \ case
  LocalDecide _ (MkDecide _ _tySig appForm expr) ->
    Prettyprinter.group $ printWithLayout appForm <+> "BE" <+> Prettyprinter.align (printWithLayout expr)
  LocalAssume _ t -> printWithLayout t

instance LayoutPrinterWithName a => LayoutPrinter (LocalDecl a) where
  printWithLayout = \ case
    LocalDecide _ t -> printWithLayout t
    LocalAssume _ t -> printWithLayout t

instance LayoutPrinter Lit where
  printWithLayout = \ case
    NumericLit _ t -> pretty (prettyRatio t)
    StringLit _ t -> surround (pretty $ escapeStringLiteral t) "\"" "\""

instance LayoutPrinterWithName a => LayoutPrinter (BranchLhs a) where
  printWithLayout = \ case
    (When _ pat) -> "WHEN" <+> printWithLayout pat <+> "THEN"
    (Otherwise _) -> "OTHERWISE"

instance LayoutPrinterWithName a => LayoutPrinter (Branch a) where
  printWithLayout (MkBranch _ c e) = printWithLayout c <+> printWithLayout e

instance LayoutPrinterWithName a => LayoutPrinter (Pattern a) where
  printWithLayout = \ case
    PatVar _ n -> printWithLayout n
    -- `hsep`, not `vsep`: under the Unbounded layout `vsep` always breaks, and
    -- a constructor pattern's arguments then land at the enclosing nesting
    -- level — to the left of the column 'L4.Parser.indentedPattern' demands.
    -- Pattern arguments are juxtaposed atoms; one line is always well-formed.
    --
    -- `parensIfNeeded` on the arguments: constructor application in a pattern
    -- is juxtaposition, so `PAIR (PAIR a b) (PAIR c d)` flattened to
    -- `PAIR PAIR a b PAIR c d` still parses — as a six-argument application of
    -- PAIR, which then fails arity checking. The corpus writes the brackets.
    PatApp _ n pats -> printWithLayout n <> case pats of
      [] -> mempty
      pats'@(_:_) -> space <> hsep (fmap parensIfNeeded pats')
    PatCons _ patHead patTail -> parensIfNeeded patHead <+> "FOLLOWED BY" <+> parensIfNeeded patTail
    PatExpr _ expr -> "EXACTLY" <+> printWithLayout expr
    PatLit _ lit -> printWithLayout lit

  parensIfNeeded :: LayoutPrinterWithName a => Pattern a -> Doc ann
  parensIfNeeded p = case p of
    PatVar{}      -> printWithLayout p
    PatLit{}      -> printWithLayout p
    PatApp _ _ [] -> printWithLayout p
    _             -> surround (printWithLayout p) "(" ")"

instance LayoutPrinter Nlg where
  printWithLayout = \ case
    MkInvalidNlg _ -> "Invalid Nlg"
    MkParsedNlg _ frags -> prettyNlgs frags
    MkResolvedNlg _ frags -> prettyNlgs frags
    where
      prettyNlgs [] = mempty
      prettyNlgs [x@MkNlgRef{}] = printWithLayout x
      prettyNlgs (x@MkNlgRef{}:xs) = printWithLayout x <+> prettyNlgs xs
      prettyNlgs (x:xs) = printWithLayout x <> prettyNlgs xs

instance LayoutPrinter Desc where
  printWithLayout = \ case
    MkDesc _ann n -> pretty n

instance LayoutPrinterWithName a => LayoutPrinter (NlgFragment a) where
  printWithLayout = \ case
    MkNlgText _ t -> pretty t
    MkNlgRef  _ n -> "%" <> printWithLayout n <> "%"

instance (LayoutPrinter a, LayoutPrinter b) => LayoutPrinter (Either a b) where
  printWithLayout = either printWithLayout printWithLayout

instance LayoutPrinter a => LayoutPrinter (Lazy.Value a) where
  printWithLayout = \ case
    Lazy.ValNumber i               -> pretty (prettyRatio i)
    Lazy.ValString t               -> surround (pretty $ escapeStringLiteral t) "\"" "\""
    Lazy.ValDate day               ->
      let (y, m, d) = toGregorian day
      in "DATE OF" <+> hsep [pretty d <> ",", pretty m <> ",", pretty y]
    Lazy.ValTime tod               ->
      let h = todHour tod; mi = todMin tod; s = todSec tod
      in "TIME OF" <+> hsep [pretty h <> ",", pretty mi <> ",", pretty (realToFrac s :: Double)]
    Lazy.ValDateTime utc tzName    ->
      pretty (formatDateTimeIso utc tzName)
    Lazy.ValNil                    -> "EMPTY"
    Lazy.ValCons v1 v2             -> "(" <> printWithLayout v1 <> " FOLLOWED BY " <> printWithLayout v2 <> ")" -- TODO: parens
    Lazy.ValClosure{}              -> "<function>"
    Lazy.ValNullaryBuiltinFun{}    -> "<builtin-function>"
    Lazy.ValUnaryBuiltinFun{}      -> "<builtin-function>"
    Lazy.ValBinaryBuiltinFun{}     -> "<function>"
    Lazy.ValTernaryBuiltinFun{}    -> "<builtin-function>"
    Lazy.ValPartialTernary{}       -> "<partial-function>"
    Lazy.ValPartialTernary2{}      -> "<partial-function>"
    Lazy.ValAssumed r              -> printWithLayout r
    Lazy.ValUnappliedConstructor r -> printWithLayout r
    Lazy.ValConstructor r vs       -> printWithLayout r <> case vs of
      [] -> mempty
      vals@(_:_) -> space <> "OF" <+> hsep (punctuate comma (fmap parensIfNeeded vals))
    Lazy.ValEnvironment _env       -> "<environment>"
    Lazy.ValBreached reason        -> vcat
      [ "DEONTIC BREACHED:"
      , indent 2 $ printWithLayout reason
      ]
    Lazy.ValObligation _env p a t f l -> case t of
      Left te -> prettyObligation p a te (Just f) l
      Right tv -> prettyObligation p a (Just tv) (Just f) l
    Lazy.ValROp _env op l r -> hsep
      [ printWithLayout l
      , case op of ValROr -> "OR"; ValRAnd -> "AND"
      , printWithLayout r
      ]
  parensIfNeeded :: Lazy.Value a -> Doc ann
  parensIfNeeded v = case v of
    Lazy.ValNumber{}               -> printWithLayout v
    Lazy.ValString{}               -> printWithLayout v
    Lazy.ValDate{}                 -> printWithLayout v
    Lazy.ValTime{}                 -> printWithLayout v
    Lazy.ValDateTime{}             -> printWithLayout v
    Lazy.ValNil                    -> "EMPTY"
    Lazy.ValClosure{}              -> printWithLayout v
    Lazy.ValUnappliedConstructor{} -> printWithLayout v
    Lazy.ValAssumed{}              -> printWithLayout v
    Lazy.ValConstructor r []       -> printWithLayout r
    _ -> surround (printWithLayout v) "(" ")"

-- | Pretty-print an 'NF' value, using named fields (WITH / IS syntax) for
-- constructors whose field names are provided in the map.
prettyNFWithConstructorFields :: ConstructorFieldNames -> Lazy.NF -> Doc ann
prettyNFWithConstructorFields fields = goNF
  where
    goNF :: Lazy.NF -> Doc ann
    goNF (Lazy.MkNF v)  = goVal v
    goNF Lazy.Omitted    = "…"

    goVal :: Lazy.Value Lazy.NF -> Doc ann
    goVal = \case
      Lazy.ValConstructor r vs
        | Just names <- Map.lookup (getUnique r) fields
        , length names == length vs
        , not (null vs)
        -> printWithLayout r <+> "WITH"
           <+> hsep (punctuate comma (zipWith fieldPair names vs))
      -- For everything else, delegate to the standard LayoutPrinter,
      -- but recurse into nested NF values with field-name awareness.
      Lazy.ValCons hd tl ->
        "LIST" <+> goList hd tl
      Lazy.ValConstructor r vs -> printWithLayout r <> case vs of
        [] -> mempty
        vals@(_:_) -> space <> "OF" <+> hsep (punctuate comma (fmap goNFParens vals))
      other -> printWithLayout other

    fieldPair :: Text -> Lazy.NF -> Doc ann
    fieldPair name val = pretty (quoteIfNeeded name) <+> "IS" <+> goNF val

    goList :: Lazy.NF -> Lazy.NF -> Doc ann
    goList v1 (Lazy.MkNF Lazy.ValNil)        = goNF v1
    goList v1 (Lazy.MkNF (Lazy.ValCons v2 v3)) = goNF v1 <> comma <+> goList v2 v3
    goList Lazy.Omitted Lazy.Omitted         = "..."
    goList v1 Lazy.Omitted                   = goNF v1 <> comma <+> "..."
    goList v1 v                              = goNF v1 <> comma <+> goNF v

    goNFParens :: Lazy.NF -> Doc ann
    goNFParens nf = case nf of
      Lazy.MkNF v -> goValParens v
      Lazy.Omitted -> "…"

    goValParens :: Lazy.Value Lazy.NF -> Doc ann
    goValParens v = case v of
      Lazy.ValNumber{}               -> goVal v
      Lazy.ValString{}               -> goVal v
      Lazy.ValDate{}                 -> goVal v
      Lazy.ValTime{}                 -> goVal v
      Lazy.ValDateTime{}             -> goVal v
      Lazy.ValNil                    -> "EMPTY"
      Lazy.ValClosure{}              -> goVal v
      Lazy.ValUnappliedConstructor{} -> goVal v
      Lazy.ValAssumed{}              -> goVal v
      Lazy.ValConstructor _ []       -> goVal v
      _ -> surround (goVal v) "(" ")"

-- | Pretty-print an 'NF' to 'Text', using named fields when available.
prettyLayoutNF :: ConstructorFieldNames -> Lazy.NF -> Text
prettyLayoutNF fields nf = docText $ prettyNFWithConstructorFields fields nf

instance LayoutPrinter BinOp where
  printWithLayout = \ case
    BinOpPlus -> "PLUS"
    BinOpMinus -> "MINUS"
    BinOpTimes -> "TIMES"
    BinOpDividedBy -> "DIVIDED BY"
    BinOpModulo -> "MODULO"
    BinOpExponent -> "TO THE POWER OF"
    BinOpTrunc -> "TRUNC"
    BinOpCons -> "FOLLOWED BY"
    BinOpEquals -> "EQUALS"
    BinOpLeq -> "AT MOST"
    BinOpGeq -> "AT LEAST"
    BinOpLt -> "LESS THAN"
    BinOpGt -> "GREATER THAN"
    BinOpContains -> "CONTAINS"
    BinOpStartsWith -> "STARTSWITH"
    BinOpEndsWith -> "ENDSWITH"
    BinOpIndexOf -> "INDEXOF"
    BinOpSplit -> "SPLIT"
    BinOpCharAt -> "CHARAT"
    BinOpWhenLast -> "WHEN LAST"
    BinOpWhenNext -> "WHEN NEXT"
    BinOpValueAt -> "VALUE AT"

instance LayoutPrinter a => LayoutPrinter (ReasonForBreach a) where
  printWithLayout = \ case
    DeadlineMissed ev'party ev'action ev'time party action deadline -> vcat
      [ "party"
      , i2 $ printWithLayout ev'party
      , "who did action"
      , i2 $ printWithLayout ev'action
      , "at"
      , i2 $ pretty (prettyRatio ev'time)
      , "surpassed the deadline of party"
      , i2 $ printWithLayout party
      , "who had to do obligatory action"
      , i2 $ printWithLayout action
      , "before their deadline, which was at"
      , i2 $ pretty (prettyRatio deadline)
      ]
      where i2 = indent 2
    ExplicitBreach mParty mReason -> vcat $
      [ "BREACH" ]
      <> maybe [] (\p -> [ "BY" <+> printWithLayout p ]) mParty
      <> maybe [] (\r -> [ "BECAUSE" <+> printWithLayout r ]) mReason

instance LayoutPrinter Lazy.NF where
  printWithLayout = \ case
    Lazy.Omitted -> "..."
    Lazy.MkNF (ValCons v1 v2) -> "LIST" <+> printList v1 v2
    Lazy.MkNF v -> printWithLayout v
    where
      printList v1 (Lazy.MkNF (ValNil))                          = printWithLayout v1
      printList v1 (Lazy.MkNF (ValCons v2 v3))                   = printWithLayout v1 <> comma <+> printList v2 v3
      printList Lazy.Omitted Lazy.Omitted                        = "..."
      printList v1 Lazy.Omitted                                  = printWithLayout v1 <> comma <+> "..."
      printList v1 v                                             = printWithLayout v1 <> comma <+> printWithLayout v -- fallback, should not happen

  parensIfNeeded :: Lazy.NF -> Doc ann
  parensIfNeeded v = case v of
    MkNF (Lazy.ValNumber{})               -> printWithLayout v
    MkNF (Lazy.ValString{})               -> printWithLayout v
    MkNF Lazy.ValNil                      -> printWithLayout v
    MkNF (Lazy.ValClosure{})              -> printWithLayout v
    MkNF (Lazy.ValUnappliedConstructor{}) -> printWithLayout v
    MkNF (Lazy.ValAssumed{})              -> printWithLayout v
    MkNF (Lazy.ValConstructor r [])       -> printWithLayout r
    _ -> surround (printWithLayout v) "(" ")"

instance LayoutPrinter Reference where
  printWithLayout rf = printWithLayout rf.address

instance LayoutPrinter Address where
  printWithLayout (MkAddress u a) =
    let fullUri = (fromNormalizedUri u).getUri
        -- Extract just filename for consistent output across platforms
        fileName = case Text.stripPrefix "file://" fullUri of
            Just path -> Text.pack $ takeFileName $ Text.unpack path
            Nothing -> Text.pack $ takeFileName $ Text.unpack fullUri
    in "&" <> pretty a <> "@" <> pretty fileName

quoteIfNeeded :: Text.Text -> Text.Text
quoteIfNeeded n = case Text.uncons n of
  Nothing -> n
  Just (firstChar, _)
    -- If the identifier doesn't start with alpha, it must be quoted
    -- (L4 lexer requires unquoted identifiers to start with alphabetic char)
    | not (isAlpha firstChar) -> quote n
    -- A bare word that spells a reserved word lexes as that KEYWORD, not as a
    -- name. The prelude's set-difference operator is literally named `LESS`
    -- (the first word of `LESS THAN`) and its source spells it with backticks
    -- for exactly this reason; dropping them printed `DECIDE LESS p q IS`,
    -- which the parser rejects with "unexpected LESS, expecting identifier".
    | Map.member n Lexer.keywords && n `notElem` keywordsUsableAsNames -> quote n
    -- Otherwise check if all chars are valid identifier chars
    | Text.all isIdentChar n -> n
    | otherwise -> quote n
  where
    -- Match lexer: identifiers can contain alphanumeric chars and underscores
    isIdentChar x = isAlphaNum x || x == '_'

-- | Keywords the grammar ALSO accepts in name position, so they need no
-- backticks. There is exactly one: 'L4.Parser.tyApp' reads a type head with
-- @tokenAsName (TKeywords TKList) <|> name@, which is why every corpus type is
-- spelled @LIST OF NUMBER@ and not @`LIST` OF NUMBER@. Grep 'tokenAsName' in
-- the parser before adding to this list.
keywordsUsableAsNames :: [Text.Text]
keywordsUsableAsNames = ["LIST"]

quote :: Text.Text -> Text.Text
quote n = "`" <> n <> "`"

-- | Flatten a chain of one associative connective into its operands.
--
-- The match runs on @carameliseNode e@, not on @e@: a chain the type checker
-- left as @App __AND__ [a, b]@ does not match the @And@ constructor, so an
-- un-caramelised scan peeled exactly one level and handed the REST back as a
-- single operand. That was invisible while conjuncts printed bare; once
-- 'parensIfOpenTailed' started bracketing a nested connective (which it must —
-- see the note there) it turned @a AND b AND c AND d@ into
-- @a AND (b AND (c AND d))@, bracketing an associative nest that needs none.
-- Caramelising as we descend flattens the chain properly, so the only operand
-- that can still BE a connective is one of a genuinely different kind.
scanOp :: HasName a => (forall r. Expr a -> (r, Expr a -> Expr a -> r) -> r) -> Expr a -> [Expr a]
scanOp match e = match (carameliseNode e) ([e], \e1 e2 -> scanOp match e1 <> scanOp match e2)

scanOr :: HasName a => Expr a -> [Expr a]
scanOr = scanOp \case
  Or _ e1 e2 -> \t -> snd t e1 e2
  _ -> fst

scanAnd :: HasName a => Expr a -> [Expr a]
scanAnd = scanOp \case
  And _ e1 e2 -> \t -> snd t e1 e2
  _ -> fst

scanROr :: HasName a => Expr a -> [Expr a]
scanROr = scanOp \case
  ROr _ e1 e2 -> \t -> snd t e1 e2
  _ -> fst

scanRAnd :: HasName a => Expr a -> [Expr a]
scanRAnd = scanOp \case
  RAnd _ e1 e2 -> \t -> snd t e1 e2
  _ -> fst

prettyConj :: Text -> [Doc ann] -> Doc ann
prettyConj _ [] = mempty
prettyConj cnj (d:ds) =
  -- Use group with softline so it prefers single-line when possible
  -- This avoids layout issues when the output is re-parsed
  Prettyprinter.group $ d <> mconcat [softline <> pretty cnj <+> x | x <- ds]


escapeStringLiteral :: Text -> Text
escapeStringLiteral = Text.concatMap (\ case
  '\"' -> "\\\""
  '\\' -> "\\\\"
  c -> Text.singleton c
  )

-- | Format a UTCTime with timezone offset as ISO-8601
formatDateTimeIso :: UTCTime -> Text -> Text
formatDateTimeIso utc tzName =
  case tryLoadTZPure tzName of
    Just tz ->
      let localTime' = TZ.utcToLocalTimeTZ tz utc
          offset = TZ.timeZoneForUTCTime tz utc
          offsetStr = TimeFormat.formatTime TimeFormat.defaultTimeLocale "%z" offset
      in Text.pack (TimeFormat.formatTime TimeFormat.defaultTimeLocale "%Y-%m-%dT%H:%M:%S" localTime') <> Text.pack offsetStr
    Nothing ->
      -- Fallback: format as UTC
      Text.pack $ TimeFormat.formatTime TimeFormat.defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" utc

-- | Pure wrapper for TZ loading (uses unsafePerformIO since TZ data is static)
tryLoadTZPure :: Text -> Maybe TZ.TZ
tryLoadTZPure name = unsafePerformIO $ tryLoadTZ (Text.unpack name)
{-# NOINLINE tryLoadTZPure #-}

tryLoadTZ :: String -> IO (Maybe TZ.TZ)
tryLoadTZ name =
  (Just <$> TZ.loadTZFromDB name) `catch` \(_ :: SomeException) ->
    -- Fall back to the embedded timezone database when the system DB is unavailable.
    pure $ TZAll.tzByLabel <$> TZAll.fromTZName (TE.encodeUtf8 (Text.pack name))
