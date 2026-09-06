{-# LANGUAGE ViewPatterns, DataKinds #-}
module LSP.L4.Actions where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text

import Control.Applicative
import Control.Monad.Trans.Maybe
import qualified Data.Aeson as Aeson
import Data.Char (isAlphaNum)
import qualified Data.List as List
import Data.Ord (Down (..))
import Data.Text.Mixed.Rope (Rope)
import qualified Data.Text.Mixed.Rope as Rope
import qualified Text.Fuzzy as Fuzzy

import L4.Annotation
import L4.FindDefinition
import L4.Lexer (annotations, directives, keywords)
import L4.Parser.SrcSpan
import L4.Print
import L4.Syntax
import L4.TypeCheck
import qualified L4.Evaluate.ValueLazy   as EL
import qualified L4.EvaluateLazy         as EL
import qualified L4.EvaluateLazy.Machine as EL
import qualified L4.Utils.IntervalMap as IV
import LSP.Core.PositionMapping
import LSP.Core.Shake
import LSP.L4.Rules

import qualified LSP.L4.Viz.Ladder as Ladder
import qualified LSP.L4.Viz.VizExpr as Ladder
import qualified LSP.L4.Viz.CustomProtocol as Ladder
import           LSP.L4.Viz.CustomProtocol (EvalAppRequestParams (..),
                                            EvalAppResult (..))
import qualified LSP.L4.Viz.QueryPlan as VizQueryPlan

import Language.LSP.Protocol.Message
import Language.LSP.Protocol.Types
import Language.LSP.Protocol.Types as CompletionItem (CompletionItem (..))
import L4.Nlg (simpleLinearizer)

-- ----------------------------------------------------------------------------
-- LSP Autocompletions
-- ----------------------------------------------------------------------------

buildCompletionItem :: RawName -> CheckEntity -> [CompletionItem]
buildCompletionItem raw = \ case
  KnownTerm ty term ->
    pure (defaultTopDeclCompletionItem ty)
      { CompletionItem._kind = Just $ case (term, ty) of
         (Constructor, _) -> CompletionItemKind_Constructor
         (Selector, _) -> CompletionItemKind_Field
         (ComputedSelector, _) -> CompletionItemKind_Field
         (_, unrollForall -> Fun {}) -> CompletionItemKind_Function
         _ -> CompletionItemKind_Constant
      , CompletionItem._detail = case term of
         ComputedSelector -> Just "(computed)"
         _ -> Nothing
      }
  KnownType kind _args _tydec ->
    pure (defaultTopDeclCompletionItem (typeFunction kind))
      { CompletionItem._kind = Just CompletionItemKind_Class
      }
  KnownSection (MkSection _ (Just n) _ _ _) ->
    pure (defaultCompletionItem $  nameToText $ getOriginal n)
      { CompletionItem._kind = Just CompletionItemKind_Module
      }
  KnownSection (MkSection _ Nothing _ _ _) ->
    -- NOTE: a section without name is just the toplevel section - we don't need to
    -- autocomplete anything there
    []
  KnownTypeVariable ->
    pure (defaultCompletionItem prepared)
     { CompletionItem._kind = Just CompletionItemKind_TypeParameter
     }
  where
    -- a function (but also a constant, in theory) can be polymorphic, so we have to strip
    -- all the foralls to get to the "actual" type.
    unrollForall :: Type' Resolved -> Type' Resolved
    unrollForall (Forall _ _ ty) = unrollForall ty
    unrollForall ty = ty

    defaultTopDeclCompletionItem :: Type' Resolved -> CompletionItem
    defaultTopDeclCompletionItem ty = (defaultCompletionItem $ quoteIfNeeded prepared)
      { CompletionItem._filterText = Just prepared
      , CompletionItem._labelDetails
        = Just CompletionItemLabelDetails
          { _description = Nothing
          , _detail = Just $ " IS A " <> prettyLayout ty
          }
      }

    prepared :: Text
    prepared = rawNameToText raw

defaultCompletionItem :: Text -> CompletionItem
defaultCompletionItem label = CompletionItem label
  Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing
  Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- ----------------------------------------------------------------------------
-- LSP Go to Definition
-- ----------------------------------------------------------------------------

gotoDefinition :: Position -> TypeCheckResult -> PositionMapping -> Maybe Location
gotoDefinition pos m positionMapping = do
  oldPos <- fromCurrentPosition positionMapping pos
  range <- findDefinition (lspPositionToSrcPos oldPos) m.module'
  let lspRange = srcRangeToLspRange (Just range)
  newRange <- toCurrentRange positionMapping lspRange
  pure (Location (fromNormalizedUri range.moduleUri) newRange)


-- ----------------------------------------------------------------------------
-- Ladder evalApp
-- ----------------------------------------------------------------------------

evalApp
  :: forall m.
  (MonadIO m)
  => EL.EvalConfig
  -> EL.EntityInfo
  -> (EL.Environment, Module Resolved)
  -> Ladder.EvalAppRequestParams
  -> RecentlyVisualised
  -> ExceptT (TResponseError ('Method_CustomMethod Ladder.EvalAppMethodName)) m Aeson.Value
evalApp evalConfig entityInfo contextModule evalParams recentViz =
  case Ladder.lookupAppExprMaker recentViz.vizState evalParams.appExpr of
    Nothing -> defaultResponseError "No expr maker found" -- TODO: Improve error codehere
    Just evalAppMaker -> do
      let appExpr = evalAppMaker evalParams
      res <- liftIO $ EL.execEvalExprInContextOfModule evalConfig entityInfo appExpr contextModule
      case res of
        Just evalRes -> Aeson.toJSON <$> evalResultToLadderEvalAppResult evalRes
        Nothing -> defaultResponseError "No eval result found"
  where
    evalResultToLadderEvalAppResult :: EL.EvalDirectiveResult -> ExceptT (TResponseError method) m EvalAppResult
    evalResultToLadderEvalAppResult (EL.MkEvalDirectiveResult _ res _mtrace _ledger) = case res of
      EL.Assertion EL.Holds   -> pure $ EvalAppResult (toUBoolValue True)
      EL.Assertion EL.Fails   -> pure $ EvalAppResult (toUBoolValue False)
      EL.Assertion a@(EL.FailsBecause _) -> defaultResponseError $ EL.prettyAssertionOutcome a
      -- A refusal has NO ladder value: the visualiser is a boolean evaluator
      -- and 'UnknownV' means "not yet supplied", which a refusal is not. So it
      -- is reported by name, with the author's reason, rather than drawn as
      -- either verdict.
      EL.Assertion (EL.Refused r) -> defaultResponseError $ Text.unlines $ EL.prettyRefusal r
      EL.Assertion a@(EL.Errored _) -> defaultResponseError $ EL.prettyAssertionOutcome a
      EL.Reduction v ->
        case v of
          EL.Reduced (EL.MkNF val) ->
            case EL.boolView val of
              Just b  -> pure $ EvalAppResult (toUBoolValue b)
              Nothing -> throwExpectBoolResultError
          EL.Reduced EL.Omitted    -> defaultResponseError "Evaluation exceeded maximum depth limit"
          EL.ReducedRefused r      -> defaultResponseError $ Text.unlines $ EL.prettyRefusal r
          EL.ReducedErrored err    -> defaultResponseError $ Text.unlines $ EL.prettyEvalException err

    throwExpectBoolResultError :: ExceptT (TResponseError method) m a
    throwExpectBoolResultError = defaultResponseError "Ladder visualizer is expecting a boolean result (and it should be impossible to have got a fn with a non-bool return type in the first place)"

    toUBoolValue :: Bool -> Ladder.UBoolValue
    toUBoolValue b = if b then Ladder.TrueV else Ladder.FalseV

-- ----------------------------------------------------------------------------
-- Ladder visualisation
-- ----------------------------------------------------------------------------

visualise
  :: Monad m
  => Maybe TypeCheckResult
  -> (m (Maybe RecentlyVisualised), RecentlyVisualised -> m ())
  -> VersionedTextDocumentIdentifier
  -- ^ The VersionedTextDocumentIdentifier of the document whose Decides should be visualised
  -> Maybe (SrcPos, Bool)
  -- ^ The location of the `Decide` to visualize and whether or not to simplify it
  -> ExceptT (TResponseError method) m (Aeson.Value |? Null)
visualise mtcRes (getRecVis, setRecVis) verTextDocId msrcPos = do
  let uri = verTextDocId._uri

  -- Try to pinpoint a Decide (and VizConfig) based on how the command was issued (autorefresh vs code action/code lens)
  mdecide :: Maybe (Decide Resolved, Ladder.VizConfig) <- case msrcPos of
    -- a. the command was issued by autorefresh
    -- NOTE: when we get the typecheck results via autorefresh, we can be lenient about it, i.e. we return 'Nothing
    -- exits by returning Nothing instead of throwing an error
    Nothing -> runMaybeT do
      tcRes <- hoistMaybe mtcRes
      recentlyVisualised <- MaybeT $ lift getRecVis
      -- Since this is from autorefresh, we want to get the most up-to-date version of the Decide
      decide <- hoistMaybe $ (.getOne) $  foldTopLevelDecides (matchOnAvailableDecides recentlyVisualised) tcRes.module'
      let updatedVizConfig = updateVizConfig verTextDocId tcRes recentlyVisualised
      pure (decide, updatedVizConfig)

    -- b. the command was issued by a code action or codelens
    Just (srcPos, simp) -> do
      tcRes <- do
        case mtcRes of
          Nothing -> defaultResponseError $ "Could not check " <> Text.pack (show uri.getUri) <> "."
          Just tcRes -> pure tcRes
      case foldTopLevelDecides (\d -> [d | decideNodeStartsAtPos srcPos d]) tcRes.module' of
        [decide] ->
          let vizConfig = Ladder.mkVizConfig verTextDocId tcRes.module' tcRes.substitution simp
          in pure $ Just (decide, vizConfig)
        -- NOTE: if this becomes a problem, we should use
        -- https://hackage.haskell.org/package/lsp-types-2.3.0.1/docs/Language-LSP-Protocol-Types.html#t:VersionedTextDocumentIdentifier
        _ -> defaultResponseError "The program was changed in the time between pressing the code lens and rendering the program"

  -- Makes a 'RecentlyVisualised' iff the given 'Decide' has a valid range and a resolved type.
  -- Assumes the vizConfig in the given vizState is up-to-date.
  let recentlyVisualisedDecide decide@(MkDecide Anno {range = Just range, extra = Extension {resolvedInfo = Just (TypeInfo ty _)}} _tydec appform _expr) vizState
        = Just RecentlyVisualised
          { pos = range.start
          , name = rawName $ getName appform
          , type' = applyFinalSubstitution (Ladder.getVizConfig vizState).substitution (Ladder.getVizConfig vizState).moduleUri ty
          , vizState = vizState
          , decide
          }
      recentlyVisualisedDecide _ _ = Nothing

  case mdecide of
    Nothing -> pure (InR Null)
    Just (decide, vizConfig) ->
      case Ladder.doVisualize decide vizConfig of
        Right (vizProgramInfo, vizState) -> do
          traverse_ (lift . setRecVis) $ recentlyVisualisedDecide decide vizState
          pure $ InL $ Aeson.toJSON (VizQueryPlan.annotateLadderWithAtomIds vizProgramInfo vizState)
        Left vizError ->
          defaultResponseError $ Text.unlines
            [ "Could not visualize:"
            , getUri uri
            , Ladder.prettyPrintVizError vizError
            ]
  where
    -- TODO: in the future we want to be a bit more clever wrt. which
    -- DECIDE/MEANS we snap to. We can use the type of the 'Decide' here
    -- (by requiring extra = Just ty) or the name of the 'Decide' by the means
    -- of checking its 'Resolved'
    matchOnAvailableDecides :: RecentlyVisualised -> Decide Resolved -> One (Decide Resolved)
    matchOnAvailableDecides v decide = One do
      guard (decideNodeStartsAtPos v.pos decide)
        <|> guard case decide of
               (MkDecide _ _ appform _) -> rawName (getName appform) == v.name
        -- NOTE: this heuristic is wrong if there are ambiguous names in scope. that's why it will
        -- only succeed if there's exactly one match

      pure decide

{- | Make a new 'Ladder.VizConfig' by combining (i) old config (e.g. whether to
simplify) from the 'RecentlyVisualised' (which itself contains a VizConfig) with
(ii) up-to-date versions of potentially stale info (verTxtDocId, tcRes).

Crucially this refreshes @module'@ from the current typecheck result too. @module'@
is what 'Ladder.collectDefsForInlining' reads to decide @canInline@ (the +/unfold
affordance); if it stayed frozen at the snapshot taken by the last *manual* Visualize,
auto-refresh would recompute the ladder structure but keep a stale @canInline@ — so a
newly-added DECIDE would not surface its inline affordance until a manual re-visualize.
See smucclaw/l4-ide#557. -}
updateVizConfig :: VersionedTextDocumentIdentifier -> TypeCheckResult -> RecentlyVisualised -> Ladder.VizConfig
updateVizConfig verTxtDocId tcRes recentlyVisualised =
  Ladder.getVizConfig recentlyVisualised.vizState
    & set #verDocId (Ladder.fromLspVerDocId verTxtDocId)
    & set #moduleUri (toNormalizedUri verTxtDocId._uri)
    & set #substitution tcRes.substitution
    & set #module' tcRes.module'

-- | the 'Monoid' 'Maybe' that returns the only occurrence of 'Just'
newtype One a = One {getOne :: Maybe a}
  deriving stock (Eq, Ord, Show)

instance Semigroup (One a) where
  One (Just a) <> One Nothing = One (Just a)
  One Nothing <> One (Just a) = One (Just a)
  _ <> _ = One Nothing

instance Monoid (One a) where
  mempty = One Nothing

defaultResponseError :: Monad m => Text -> ExceptT (TResponseError method) m a
defaultResponseError _message
  = throwError TResponseError { _code = InL LSPErrorCodes_RequestFailed , _xdata = Nothing, _message }

decideNodeStartsAtPos :: SrcPos -> Decide Resolved -> Bool
decideNodeStartsAtPos pos d = Just pos == do
  node <- rangeOfNode d
  pure node.start

-- ----------------------------------------------------------------------------
-- LSP Code Actions
-- ----------------------------------------------------------------------------

completions :: Rope -> NormalizedUri -> TypeCheckResult -> Position -> [CompletionItem]
completions rope nuri typeCheck pos@(Position ln col) = do
  let textBeforeCursor =
        Rope.toText
        $ fst -- we don't care for the rest of the line
        $ Rope.charSplitAt (fromIntegral col)
        $ Rope.getLine (fromIntegral ln) rope

      completionPrefix = Text.takeWhileEnd isAlphaNum textBeforeCursor

      -- Check if the user already typed a leading backtick before the alphanumeric prefix.
      -- If so, we need textEdits that include it in the replacement range to avoid doubling it.
      hasLeadingBacktick =
        let beforePrefix = Text.dropEnd (Text.length completionPrefix) textBeforeCursor
        in maybe False ((== '`') . snd) (Text.unsnoc beforePrefix)

      prefixLen = fromIntegral (Text.length completionPrefix)
      editStart = Position ln (col - prefixLen - if hasLeadingBacktick then 1 else 0)
      editRange = Range editStart (Position ln col)

      -- For backtick-quoted completion items, set a textEdit so VS Code replaces
      -- the user's leading backtick + prefix together, avoiding a doubled backtick.
      -- Also update filterText to include the backtick, since VS Code filters against
      -- the text covered by the textEdit range.
      addBacktickTextEdit item
        | hasLeadingBacktick
        , Text.isPrefixOf "`" item._label
        = item { CompletionItem._textEdit = Just (InL (TextEdit editRange item._label))
               , CompletionItem._filterText = Just item._label
               }
        | otherwise = item

      filterMatchesOn f is =
        map Fuzzy.original $ Fuzzy.filter
          completionPrefix
          is
          mempty
          mempty
          f
          False

      mkKeyWordCompletionItem kw = (defaultCompletionItem kw)
        { CompletionItem._kind =  Just CompletionItemKind_Keyword
        }
      keyWordMatches = filterMatchesOn id
        $ Map.keys keywords
        <> Map.keys directives
        <> annotations

      keywordItems = map mkKeyWordCompletionItem keyWordMatches

      -- NOTE: combine toplevel check info and info brought in scope
      finalCheckInfos
        = Map.unionsWith (\a b -> nub $ a <> b)
        $ map (uncurry combineEnvironmentEntityInfo)
        $ (typeCheck.environment, typeCheck.entityInfo)
            : map snd (IV.search (lspPositionToSrcPos pos) typeCheck.scopeMap)

      scopedItems
        = filterMatchesOn CompletionItem._label
        $ foldMap
            (\(name, ces) ->
              foldMap
                (buildCompletionItem name . applyFinalSubstitution typeCheck.substitution nuri)
                ces
            )
        $ Map.toList finalCheckInfos

  map addBacktickTextEdit (keywordItems <> scopedItems)

-- ----------------------------------------------------------------------------
-- LSP Hovers
-- ----------------------------------------------------------------------------

referenceHover :: Position -> IV.IntervalMap SrcPos (NormalizedUri, Int, Maybe Text) -> Maybe Hover
referenceHover pos refs = do
  -- NOTE: it's fine to cut of the tail here because we shouldn't ever get overlapping intervals
  let ivToRange (iv, (uri, len, reference)) = (IV.intervalToSrcRange uri len iv, reference)
  -- NOTE: this is subtle: if there are multiple results for a location, then we want to
  -- prefer Just's, so we reverse sort the references we get.
  -- Squashing on snd also wouldn't make sense because if we'd had all 'Nothing' that would
  -- mean that we'd get no result, when actually we want to have a list with a single element
  -- that is Nothing, on that range.
  (range, mreference) <- listToMaybe
    $ List.sortOn (Down . snd)
    $ ivToRange
    <$> IV.search (lspPositionToSrcPos pos) refs
  let lspRange = srcRangeToLspRange (Just range)
  pure $ Hover
    (InL
      (MarkupContent
        -- TODO: should be more descriptive
        { _value = fromMaybe "Reference not found" mreference
        , _kind = MarkupKind_Markdown}
      )
    )
    (Just lspRange)

typeHover :: Position -> NormalizedUri -> TypeCheckResult -> PositionMapping -> Maybe Hover
typeHover pos nuri tcRes positionMapping = do
  oldPos <- fromCurrentPosition positionMapping pos
  let oldLspPos = lspPositionToSrcPos oldPos
  (range, i) <- IV.smallestContaining nuri oldLspPos tcRes.infoMap
  let mNlg = IV.smallestContaining nuri oldLspPos tcRes.nlgMap
  let mDesc = IV.smallestContaining nuri oldLspPos tcRes.descMap
  let lspRange = srcRangeToLspRange (Just range)
  newLspRange <- toCurrentRange positionMapping lspRange
  pure (infoToHover nuri tcRes.substitution newLspRange i (fmap snd mNlg) (fmap snd mDesc))

infoToHover :: NormalizedUri -> Substitution -> Range -> Info -> Maybe Nlg -> Maybe Text -> Hover
infoToHover nuri subst r i mNlg mDesc =
  Hover (InL (mkMarkdown x)) (Just r)
  where
    x =
      case i of
        TypeInfo t _ ->
          -- Render the type via 'prettyTypeForDisplay' (not raw 'prettyLayout') so
          -- residual inference variables — e.g. an un-annotated lambda parameter,
          -- whose 'InfVar' prints @rawName <> uniq@ like @x10@ — are normalised to
          -- stable names (@a@, @b@, …). This also makes hover consistent with the
          -- deployed schema's @returnType@, which already uses this renderer. See #313.
          mdCodeBlock (prettyTypeForDisplay (applyFinalSubstitution subst nuri t)) <>
            case mNlg of
              Nothing -> mempty
              Just nlg -> mdSeparator <> mdCodeBlock (simpleLinearizer nlg)
            <>
            case mDesc of
              Nothing -> mempty
              Just desc -> mdSeparator <> desc
        KindInfo k -> mdCodeBlock $ prettyLayout $ typeFunction k
        TypeVariable -> "TYPE VAR"

mdCodeBlock :: Text -> Text
mdCodeBlock c =
  Text.unlines
    [ "```"
    , c
    , "```"
    ]

mdSeparator :: Text
mdSeparator = "\n---\n\n"

-- ----------------------------------------------------------------------------
-- Common utility functions
-- ----------------------------------------------------------------------------

-- a list : Type -> Type should be pretty printed as FUNCTION FROM TYPE TO TYPE
typeFunction :: Kind -> Type' Resolved
typeFunction 0 = Type emptyAnno
typeFunction n | n > 0 = Fun emptyAnno (replicate n (MkOptionallyNamedType emptyAnno Nothing (Type emptyAnno))) (Type emptyAnno)
typeFunction _ = error "Internal error: negative arity of type constructor"

-- ----------------------------------------------------------------------------
-- The out-of-scope quick fix: declare the name as a GIVEN
-- ----------------------------------------------------------------------------

-- | What the out-of-scope quick fix does: a title for the editor's menu and
-- the one insertion that carries it out. See 'outOfScopeGivenFix'.
data GivenFix = MkGivenFix
  { title :: Text
  , edit  :: TextEdit
  }
  deriving stock (Eq, Show)

-- | The quick fix for a name @n@ that no definition supplies, of inferred
-- type @ty@.
--
-- Until 2026-09-06 this inserted @ASSUME n IS A ty@ above the enclosing
-- declaration — the spelling IMPLICIT-PROPS-DESIGN.md §11.1 deprecates and
-- the checker now warns about ('L4.TypeCheck.Types.DeprecatedAssume'), so the
-- IDE's one automated repair generated code the same release warns about
-- (§11.14 Finding 2). It now declares the name the ruled way:
--
--  * under the nearest enclosing @§@ heading, as a parameter of that section's
--    @GIVEN@ (R4): appended to the section's existing @GIVEN@ block, aligned
--    with its first parameter, or as a new @GIVEN@ line right after the
--    heading, indented four columns past the @§@ — the spelling
--    @doc/reference/syntax/section-given.md@ teaches;
--
--  * where the use sits under no heading at all — the case the migration
--    script refuses as @root-section@ — as a parameter of the enclosing
--    declaration's own @GIVEN@, the rule @GIVEN@ that
--    @doc/reference/types/ASSUME.md@ teaches for exercising a rule inside the
--    file: appended to an existing @GIVEN@, or inserted as a new line above
--    the declaration's own first line (the @GIVETH@ when it has one, else the
--    head), so that any annotation above the declaration stays above it.
--
-- 'Nothing' when the type still has an inference variable (there is no
-- snippet support to leave a hole for the author), or when no @DECIDE@ or
-- @MEANS@ encloses the use.
outOfScopeGivenFix :: Module Resolved -> Name -> Type' Resolved -> Maybe GivenFix
outOfScopeGivenFix (MkModule _ _ rootSection) name ty = do
  guard (not (hasTypeInferenceVars ty))
  target <- rangeOf name
  let param = prettyLayout name <> " IS A " <> prettyLayout ty
  case innermostNamedSection target.start rootSection of
    Just sec -> sectionGivenFix sec param
    Nothing  -> do
      decide <- enclosingDecide target.start rootSection
      ruleGivenFix decide param
  where
    shown = quotedName name

    -- The named section nearest to the use: sections nest by containment, so
    -- the last named one whose range holds the position wins.
    innermostNamedSection :: SrcPos -> Section Resolved -> Maybe (Section Resolved)
    innermostNamedSection pos = go Nothing
      where
        go best sec@(MkSection _ mn _ _ decls) =
          let best' = case (mn, rangeOf sec) of
                (Just _, Just r) | pos `inRange` r -> Just sec
                _                                  -> best
          in List.foldl' (\ b d -> case d of Section _ s -> go b s; _ -> b) best' decls

    enclosingDecide :: SrcPos -> Section Resolved -> Maybe (Decide Resolved)
    enclosingDecide pos (MkSection _ _ _ _ decls) = asum (map go decls)
      where
        go = \ case
          Decide _ d | Just r <- rangeOf d, pos `inRange` r -> Just d
          Section _ s                                        -> enclosingDecide pos s
          _                                                  -> Nothing

    sectionGivenFix :: Section Resolved -> Text -> Maybe GivenFix
    sectionGivenFix sec@(MkSection _ mn maka mgiven _) param = do
      heading <- mn
      let headingShown = "§ " <> quotedName (getName heading)
      case mgiven of
        Just (MkGivenSig _ otns@(_ : _)) -> do
          ins <- appendParameter otns param
          pure (MkGivenFix ("Add " <> shown <> " to the GIVEN of " <> headingShown) ins)
        _ -> do
          secRange     <- rangeOf sec
          headingRange <- rangeOf heading
          let lastHeadingLine = maximum (headingRange.end.line : [ r.end.line | Just aka <- [maka], Just r <- [rangeOf aka] ])
              col   = secRange.start.column + 4
              text  = Text.replicate (col - 1) " " <> "GIVEN " <> param <> "\n"
          pure (MkGivenFix ("Declare " <> shown <> " as a GIVEN of " <> headingShown)
                           (insertAtLineStart (lastHeadingLine + 1) text))

    ruleGivenFix :: Decide Resolved -> Text -> Maybe GivenFix
    ruleGivenFix (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) mGiveth) appForm _) param = do
      let ruleShown = quotedName (getName appForm)
      case otns of
        (_ : _) -> do
          ins <- appendParameter otns param
          pure (MkGivenFix ("Add " <> shown <> " to the GIVEN of " <> ruleShown) ins)
        [] -> do
          -- The line the declaration's own text starts on, and its column:
          -- the GIVETH if there is one, else the head. An annotation above
          -- the declaration is not part of either, so it stays above.
          anchor <- case mGiveth of
            Just giveth -> (.start) <$> rangeOf giveth
            Nothing     -> (.start) <$> rangeOf appForm
          let col  = case mGiveth of
                Just _  -> anchor.column
                Nothing -> 1
              text = Text.replicate (col - 1) " " <> "GIVEN " <> param <> "\n"
          pure (MkGivenFix ("Declare " <> shown <> " as a GIVEN of " <> ruleShown)
                           (insertAtLineStart anchor.line text))

    -- A further parameter line after the last one, aligned with the first.
    appendParameter :: [OptionallyTypedName Resolved] -> Text -> Maybe TextEdit
    appendParameter [] _ = Nothing
    appendParameter (firstP : rest) param = do
      firstRange <- rangeOf firstP
      lastRange  <- rangeOf (List.foldl' (\ _ p -> p) firstP rest)
      let col = firstRange.start.column
      pure (insertAtLineStart (lastRange.end.line + 1) (Text.replicate (col - 1) " " <> param <> "\n"))

    insertAtLineStart :: Int -> Text -> TextEdit
    insertAtLineStart line text =
      TextEdit
        { _range = pointRange (srcPosToLspPosition (MkSrcPos line 1))
        , _newText = text
        }

-- | Does the type still carry an inference variable? A quick fix cannot
-- spell one (LSP 3.17 has no snippet support for code actions).
hasTypeInferenceVars :: Type' Resolved -> Bool
hasTypeInferenceVars = \ case
  Type   _ -> False
  TyApp  _ _n ns -> any hasTypeInferenceVars ns
  Fun    _ opts ty -> any hasNamedTypeInferenceVars opts || hasTypeInferenceVars ty
  Forall _ _ ty -> hasTypeInferenceVars ty
  InfVar {} -> True

hasNamedTypeInferenceVars :: OptionallyNamedType Resolved -> Bool
hasNamedTypeInferenceVars = \ case
  MkOptionallyNamedType _ _ ty -> hasTypeInferenceVars ty
