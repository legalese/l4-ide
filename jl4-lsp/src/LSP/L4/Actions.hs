{-# LANGUAGE ViewPatterns, DataKinds #-}
module LSP.L4.Actions where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text

import Control.Applicative
import Control.Monad.Trans.Maybe
import qualified Data.Aeson as Aeson
import qualified Optics
import Data.Char (isAlphaNum)
import qualified Data.List as List
import Data.Ord (Down (..))
import Data.Text.Mixed.Rope (Rope)
import qualified Data.Text.Mixed.Rope as Rope
import qualified Text.Fuzzy as Fuzzy

import L4.Annotation
import L4.FindDefinition
import qualified L4.StateGraph.Lens as SGLens
import LSP.L4.SemanticTokens (srcPosToPosition)
import Data.Either (isRight)
import GHC.Generics (Generically (..))
import L4.Lexer (LexFix (..), PError (..), annotations, directives, keywords)
import qualified L4.Lexer as Lexer
import L4.Names (isSynthesisedAnno)
import L4.Parser.SrcSpan
import L4.Print
import qualified L4.SmartPunctuation as SP
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
import qualified L4.Decision.QueryPlan as QP

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
    evalResultToLadderEvalAppResult (EL.MkEvalDirectiveResult _ res _mtrace _ledger _notes _) = case res of
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
-- Code lenses above DECIDEs
-- ----------------------------------------------------------------------------

-- | The ladder's lens: "Show decision graph" above every top-level @DECIDE@
-- the visualiser can draw. The gate is speculative — each candidate is
-- actually visualised and kept only if that succeeds — because there are
-- many @DECIDE@/@MEANS@ shapes the visualiser does not handle yet, and a lens
-- that fails when clicked is worse than none. If this is ever too slow the
-- fix is to cache, or better, to make the visualiser accept more.
decisionGraphCodeLenses :: VersionedTextDocumentIdentifier -> TypeCheckResult -> [CodeLens]
decisionGraphCodeLenses verTextDocId typeCheck =
  foldTopLevelDecides decideToCodeLens typeCheck.module'
  where
    -- Three arguments: the IDE's displayers do not draw call expansions, so
    -- the lens does not ask for them ('VisualiseOptions' has the fourth).
    mkDecisionGraphCodeLens srcPos = CodeLens
      { _command = Just Command
        { _title = "Show decision graph"
        , _command = "l4.visualize"
        , _arguments = Just [Aeson.toJSON verTextDocId, Aeson.toJSON (Generically srcPos), Aeson.toJSON False]
        }
      , _range = pointRange $ srcPosToPosition srcPos
      , _data_ = Nothing
      }

    -- Without simplification — simplification is a toggle inside the panel.
    canVisualize decide =
      let cfg = Ladder.mkVizConfig verTextDocId typeCheck.module' typeCheck.substitution False
      in isRight (Ladder.doVisualize decide cfg)

    decideToCodeLens decide =
      case rangeOfNode decide of
        Just node
          | canVisualize decide -> [mkDecisionGraphCodeLens node.start]
        _ -> []

-- | The state graph's lens: "Show state graph" above every top-level
-- @DECIDE@ whose body is regulative, i.e. for which 'L4.StateGraph' extracts
-- a graph. Same anchor and same argument shape as the ladder's lens (minus
-- the simplify flag), so a host that already routes @l4.visualize@ can route
-- @l4.stateGraph@ the same way. The two lenses never share a line: the
-- ladder refuses a non-@BOOLEAN@ body, and a regulative body is @DEONTIC@
-- (R13, LTS-VISUALISER.md §8).
stateGraphCodeLenses :: VersionedTextDocumentIdentifier -> TypeCheckResult -> [CodeLens]
stateGraphCodeLenses verTextDocId typeCheck =
  map toLens (SGLens.stateGraphTargets typeCheck.module')
  where
    toLens t = CodeLens
      { _command = Just Command
        { _title = "Show state graph"
        , _command = "l4.stateGraph"
        , _arguments = Just [Aeson.toJSON verTextDocId, Aeson.toJSON (Generically t.targetStart)]
        }
      , _range = pointRange $ srcPosToPosition t.targetStart
      , _data_ = Nothing
      }

-- | Serve a click on the state-graph lens: the DOT for the @DECIDE@ starting
-- at the given position, as @{ "name": …, "dot": … }@.
stateGraphAtPos
  :: Monad m
  => Maybe TypeCheckResult
  -> VersionedTextDocumentIdentifier
  -> SrcPos
  -> ExceptT (TResponseError method) m (Aeson.Value |? Null)
stateGraphAtPos mtcRes verTextDocId srcPos = do
  tcRes <- case mtcRes of
    Nothing -> defaultResponseError $ "Could not check " <> Text.pack (show verTextDocId._uri.getUri) <> "."
    Just tcRes -> pure tcRes
  case SGLens.stateGraphAtPos tcRes.module' srcPos of
    Just target -> pure $ InL $ SGLens.stateGraphResponse target.targetGraph
    Nothing -> defaultResponseError
      "No regulative rule starts at that position (the program may have changed between pressing the code lens and rendering it)"

-- ----------------------------------------------------------------------------
-- Ladder visualisation
-- ----------------------------------------------------------------------------

{- | What a client may ask of one @l4.visualize@ render, beyond the decision and
the simplify flag.

On the wire it is an optional FOURTH argument, a JSON object:

> [verDocId, srcPos, simplify]                          -- as before: no expansions
> [verDocId, srcPos, simplify, {"expandCalls": true}]   -- every call leaf carries its expansion

@expandCalls@ (default @false@) attaches to every call leaf the called rule's body
with the call's arguments substituted (WHERE-INLINING-SPEC §10). It is opt-in
because it is not free — on @regcf.l4@ it took a render from about 2.5 s to about
7.1 s and 3.4x the bytes (2026-10-05) — and the IDE's own displayers ignore the
field, so only a client that draws call panels should pay for it. Keys this
version does not know are ignored; an absent key means @false@.

The choice is remembered with the drawing: auto-refresh (@[verDocId]@ alone) and
@l4/inlineExprs@ draw again with the config of the most recent render
('updateVizConfig' keeps it), so a render made with expansions stays with them
and one made without stays without.
-}
newtype VisualiseOptions = VisualiseOptions
  { expandCalls :: Bool
  }
  deriving stock (Eq, Show)

-- | What the three-argument form means: no expansions.
defaultVisualiseOptions :: VisualiseOptions
defaultVisualiseOptions = VisualiseOptions {expandCalls = False}

instance Aeson.FromJSON VisualiseOptions where
  parseJSON = Aeson.withObject "l4.visualize options" \o ->
    VisualiseOptions <$> o Aeson..:? "expandCalls" Aeson..!= False

{- | Decode the arguments of @l4.visualize@ after the document identifier.

* @[srcPos, simplify]@: a render of the @DECIDE@ at @srcPos@, without expansions
  (what the "Show decision graph" lens sends).
* @[srcPos, simplify, options]@: the same, with 'VisualiseOptions'. An options
  value that is not an object of that shape is an error, not a silent default.
* anything else: auto-refresh of the most recent render (@Right Nothing@), as
  it always was.
-}
decodeVisualiseArgs :: [Aeson.Value] -> Either Text (Maybe (SrcPos, Bool, VisualiseOptions))
decodeVisualiseArgs args = case args of
  [Aeson.fromJSON -> Aeson.Success (Generically srcPos), Aeson.fromJSON -> Aeson.Success simplify] ->
    Right (Just (srcPos, simplify, defaultVisualiseOptions))
  [Aeson.fromJSON -> Aeson.Success (Generically srcPos), Aeson.fromJSON -> Aeson.Success simplify, opts] ->
    case Aeson.fromJSON opts of
      Aeson.Success o -> Right (Just (srcPos, simplify, o))
      Aeson.Error e -> Left ("l4.visualize: cannot read the options argument: " <> Text.pack e)
  _ -> Right Nothing

visualise
  :: Monad m
  => Maybe TypeCheckResult
  -> (m (Maybe RecentlyVisualised), RecentlyVisualised -> m ())
  -> VersionedTextDocumentIdentifier
  -- ^ The VersionedTextDocumentIdentifier of the document whose Decides should be visualised
  -> Maybe (SrcPos, Bool, VisualiseOptions)
  -- ^ The location of the `Decide` to visualize, whether or not to simplify it,
  -- and what else the client asked for ('decodeVisualiseArgs'); 'Nothing' is
  -- auto-refresh of the most recent render, with that render's choices.
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
      decide <- hoistMaybe $ (.getOne) $  foldTopLevelDecides (matchOnAvailableDecides recentlyVisualised) (ladderModule tcRes)
      let updatedVizConfig = updateVizConfig verTextDocId tcRes recentlyVisualised
      pure (decide, updatedVizConfig)

    -- b. the command was issued by a code action or codelens
    Just (srcPos, simp, opts) -> do
      tcRes <- do
        case mtcRes of
          Nothing -> defaultResponseError $ "Could not check " <> Text.pack (show uri.getUri) <> "."
          Just tcRes -> pure tcRes
      case foldTopLevelDecides (\d -> [d | decideNodeStartsAtPos srcPos d]) (ladderModule tcRes) of
        [decide] ->
          -- Call leaves carry their expansions only when the client asked
          -- ('VisualiseOptions'). Auto-refresh and l4/inlineExprs inherit
          -- this config, the choice included.
          let baseConfig = Ladder.mkVizConfig verTextDocId (ladderModule tcRes) tcRes.substitution simp
              vizConfig
                | opts.expandCalls = Ladder.withCallExpansions baseConfig
                | otherwise = baseConfig
          in pure $ Just (decide, vizConfig)
        -- NOTE: if this becomes a problem, we should use
        -- https://hackage.haskell.org/package/lsp-types-2.3.0.1/docs/Language-LSP-Protocol-Types.html#t:VersionedTextDocumentIdentifier
        _ -> defaultResponseError "The program was changed in the time between pressing the code lens and rendering the program"

  -- Makes a 'RecentlyVisualised' iff the given 'Decide' has a valid range and a resolved type.
  -- Assumes the vizConfig in the given vizState is up-to-date.
  let recentlyVisualisedDecide decide@(MkDecide Anno {range = Just range, extra = Extension {resolvedInfo = Just (TypeInfo ty _)}} _tydec appform _expr) vizState ladderInfo
        = Just RecentlyVisualised
          { pos = range.start
          , name = rawName $ getName appform
          , type' = applyFinalSubstitution (Ladder.getVizConfig vizState).substitution (Ladder.getVizConfig vizState).moduleUri ty
          , vizState = vizState
          , decide
          , ladderInfo
          }
      recentlyVisualisedDecide _ _ _ = Nothing

  case mdecide of
    Nothing -> pure (InR Null)
    Just (decide, vizConfig) ->
      case Ladder.doVisualize decide vizConfig of
        Right (vizProgramInfo, vizState) -> do
          traverse_ (lift . setRecVis) $ recentlyVisualisedDecide decide vizState vizProgramInfo
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

{- | The reply to @l4/inlineExprs@: unfold the calls the reader asked for in
the decision last drawn, draw the result again, and put its atomIds into the
SAME namespace "Show decision graph" uses ('VizQueryPlan.annotateLadderWithAtomIds').

Without that last step the reply carried the visualiser's raw ids, so every
leaf the expand did not touch changed id across it and a client's answers keyed
by atomId were lost (WHERE-INLINING-SPEC §10). The unfold-everywhere semantics
of 'Ladder.inlineExprs' are unchanged. Returns, besides the annotated reply, the
unfolded decision and the unannotated ladder with its state, which the handler
keeps for the next request ('queryPlanForRecent' plans from them).
-}
renderAfterInlining
  :: Ladder.VizState -> Decide Resolved -> [Int]
  -> Either Ladder.VizError (Decide Resolved, Ladder.RenderAsLadderInfo, Ladder.VizState, Ladder.RenderAsLadderInfo)
renderAfterInlining vizState decide uniques = do
  let postInliningDecide = Ladder.inlineExprs vizState decide uniques
  (info, vizState') <- Ladder.doVisualize postInliningDecide (Ladder.getVizConfig vizState)
  pure (postInliningDecide, VizQueryPlan.annotateLadderWithAtomIds info vizState', vizState', info)

{- | The reply to @l4/queryPlan@: the plan for the decision last drawn, from the
ladder and state that drawing produced.

It used to draw the decision again first. With call expansions on, that ran every
deepening pass and translated every expansion on each request — and the webview
sends one on every change to the bindings — only for 'VizQueryPlan.vizExprToBoolExpr'
to throw every expansion away (measured 2026-10-05: 7–11 ms per request on #520,
about 600 ms with expansions, on the r0..r12 budget module). Drawing again is
also not a no-op for the ids: the plan's compound-leaf @unique@s must be the ones
on the wire the webview holds, and those are the ones this pair carries.
-}
queryPlanForRecent :: RecentlyVisualised -> Text -> [(Text, Bool)] -> QP.QueryPlanResponse
queryPlanForRecent recentViz fnName bindings =
  VizQueryPlan.queryPlanFromLadder fnName
    (VizQueryPlan.buildParamsByUnique recentViz.ladderInfo)
    recentViz.ladderInfo recentViz.vizState bindings

{- | Make a new 'Ladder.VizConfig' by combining (i) old config (e.g. whether to
simplify) from the 'RecentlyVisualised' (which itself contains a VizConfig) with
(ii) up-to-date versions of potentially stale info (verTxtDocId, tcRes).

Crucially this refreshes @module'@ from the current typecheck result too. @module'@
is what 'Ladder.defsForInliningOf' reads to decide @canInline@ (the +/unfold
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
    & set #module' (ladderModule tcRes)

{- | The module a ladder is drawn from: the checked module with every mixfix
call stamped with its pattern ('Ladder.stampMixfixCalls'), so two operators
sharing a head keyword get different labels, and so different atomIds. Every
path that draws for the IDE ('visualise', auto-refresh, and through the stored
config @l4/inlineExprs@) reads the module from here.

The service draws from its compiled module without the registry, so a mixfix
call there still prints its head keyword only: the IDE and the service give
such a call different labels and atomIds (recorded in WHERE-INLINING-SPEC §10.6).
-}
ladderModule :: TypeCheckResult -> Module Resolved
ladderModule tcRes = Ladder.stampMixfixCalls tcRes.mixfixRegistry tcRes.module'

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

      -- NOTE: combine toplevel check info and info brought in scope. A name
      -- the compiler made up (the inputs and clause bindings of a multi-clause
      -- definition, and the second spelling of a GIVEN input it reads them
      -- by) cannot be written in source, so it is never offered.
      finalCheckInfos
        = Map.filterWithKey (\name _ -> not (isGeneratedName name))
        $ Map.unionsWith (\a b -> nub $ a <> b)
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
-- The out-of-scope quick fix: declare the name, as a GIVEN or a DECLARE
-- ----------------------------------------------------------------------------

-- | What the out-of-scope quick fix does: a title for the editor's menu and
-- the one insertion that carries it out. See 'outOfScopeFix'.
data OutOfScopeFix = MkOutOfScopeFix
  { title :: Text
  , edit  :: TextEdit
  }
  deriving stock (Eq, Show)

-- | The quick fix for a name @n@ that no definition supplies, of inferred
-- type @ty@, in a module whose tokens are @tokens@.
--
-- The checker records the role the use gave the name on the name itself: a
-- name it tried to resolve as a type carries a 'KindInfo'
-- ('L4.TypeCheck.resolveType'), a name it tried to resolve as a term a
-- 'TypeInfo'. The two roles have different ruled successors to @ASSUME@
-- (IMPLICIT-PROPS-DESIGN.md §11.1), so they get different fixes: a type gets
-- a bodiless @DECLARE@ ('outOfScopeDeclareFix'), a term a @GIVEN@
-- ('outOfScopeGivenFix').
outOfScopeFix :: [Lexer.PosToken] -> Module Resolved -> Name -> Type' Resolved -> Maybe OutOfScopeFix
outOfScopeFix tokens m name ty = case view annInfo (view annoOf name) of
  Just KindInfo {} -> outOfScopeDeclareFix tokens m name
  _                -> outOfScopeGivenFix m name ty

-- | The quick fix for a name @n@ used as a term, of inferred type @ty@.
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
outOfScopeGivenFix :: Module Resolved -> Name -> Type' Resolved -> Maybe OutOfScopeFix
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

    sectionGivenFix :: Section Resolved -> Text -> Maybe OutOfScopeFix
    sectionGivenFix sec@(MkSection _ mn maka mgiven _) param = do
      heading <- mn
      let headingShown = "§ " <> quotedName (getName heading)
      case mgiven of
        Just (MkGivenSig _ otns@(_ : _)) -> do
          ins <- appendParameter otns param
          pure (MkOutOfScopeFix ("Add " <> shown <> " to the GIVEN of " <> headingShown) ins)
        _ -> do
          secRange     <- rangeOf sec
          headingRange <- rangeOf heading
          let lastHeadingLine = maximum (headingRange.end.line : [ r.end.line | Just aka <- [maka], Just r <- [rangeOf aka] ])
              col   = secRange.start.column + 4
              text  = Text.replicate (col - 1) " " <> "GIVEN " <> param <> "\n"
          pure (MkOutOfScopeFix ("Start a GIVEN for " <> shown <> " under " <> headingShown)
                           (insertAtLineStart (lastHeadingLine + 1) text))

    ruleGivenFix :: Decide Resolved -> Text -> Maybe OutOfScopeFix
    ruleGivenFix (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) mGiveth) appForm _) param = do
      let ruleShown = "the rule " <> quotedName (getName appForm)
      case otns of
        (_ : _) -> do
          ins <- appendParameter otns param
          pure (MkOutOfScopeFix ("Add " <> shown <> " to the GIVEN of " <> ruleShown) ins)
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
          pure (MkOutOfScopeFix ("Start a GIVEN for " <> shown <> " on " <> ruleShown)
                           (insertAtLineStart anchor.line text))

    -- A further parameter line after the last one, aligned with the first.
    appendParameter :: [OptionallyTypedName Resolved] -> Text -> Maybe TextEdit
    appendParameter [] _ = Nothing
    appendParameter (firstP : rest) param = do
      firstRange <- rangeOf firstP
      lastRange  <- rangeOf (List.foldl' (\ _ p -> p) firstP rest)
      let col = firstRange.start.column
      pure (insertAtLineStart (lastRange.end.line + 1) (Text.replicate (col - 1) " " <> param <> "\n"))

-- | The quick fix for a name @T@ used as a type: a bodiless @DECLARE T@, the
-- opaque nominal type that IMPLICIT-PROPS-DESIGN.md §11.1.1 rules as the
-- successor to @ASSUME T IS A TYPE@.
--
-- Until 2026-10-07 a type went through 'outOfScopeGivenFix' like a term and
-- was offered @GIVEN T IS A TYPE@, which makes @T@ a type variable — an input
-- any type can fill — rather than a type of its own; and where no rule
-- encloses the use, as for the type of a @DECLARE@'s field, nothing was
-- offered at all.
--
-- The @DECLARE@ goes on a new line directly above the top-level declaration
-- that contains the use, in the same section and at that declaration's
-- indentation, followed by a blank line. A use in a section's own @GIVEN@ is
-- contained by the section, so the @DECLARE@ goes above its @§@ heading,
-- where the section's binder can see it. It goes above the declaration's
-- leading annotations too (@\@desc@, @\@nlg@, @\@export@ and the rest), since
-- a leading annotation belongs to the next declaration below it
-- ('L4.Parser.ResolveAnnotation') and a @DECLARE@ inserted under one would
-- take it over; and above any comment lines directly above those, which read
-- as part of the same declaration (since 2026-10-07; assumed, not ruled).
--
-- A type applied to arguments (@Box OF NUMBER, STRING@) is declared with one
-- parameter per argument (@DECLARE Box a b@): the use fixes the arity, and a
-- bodiless head with parameters declares a type of exactly that arity
-- (§11.1.1). The parameters are the first of @a@, @b@, … @z@, @a1@, … that no
-- name in the module spells, nor the type itself.
--
-- 'Nothing' when no type at the name's range applies it, or no top-level
-- declaration contains the use.
outOfScopeDeclareFix :: [Lexer.PosToken] -> Module Resolved -> Name -> Maybe OutOfScopeFix
outOfScopeDeclareFix tokens m@(MkModule _ _ rootSection) name = do
  target <- rangeOf name
  arity  <- listToMaybe
    [ length args
    | TyApp _ r args <- Optics.toListOf (Optics.gplate @(Type' Resolved) Optics.% Optics.cosmosOf (Optics.gplate @(Type' Resolved))) m
    , rangeOf (getName r) == Just target
    ]
  (decl, before) <- enclosingTopDecl target.start rootSection
  declRange      <- rangeOf decl
  let line = leadingLine before declRange.start.line
      text = Text.replicate (declRange.start.column - 1) " "
          <> Text.unwords ("DECLARE" : prettyLayout name : take arity params)
          <> "\n\n"
  pure (MkOutOfScopeFix ("Declare " <> quotedName name <> " as a type") (insertAtLineStart line text))
  where
    -- Every name the module spells, and the type's own, so that a parameter
    -- can be named apart from all of them.
    taken :: Set RawName
    taken = Set.fromList (rawName name : map (rawName . getName) (toResolved m))

    params :: [Text]
    params =
      [ p
      | p <- [ Text.pack [c] | c <- ['a' .. 'z'] ] <> [ Text.pack (c : show i) | i <- [1 :: Int ..], c <- ['a' .. 'z'] ]
      , NormalName p `Set.notMember` taken
      ]

    -- The top-level declaration that contains the position, with the last
    -- line of whatever precedes it in its section (0 above the first
    -- declaration of the file). A position among a subsection's declarations
    -- is looked for there; one in the subsection's heading or its own @GIVEN@
    -- is contained by the subsection itself. A section binder's elaboration
    -- ('L4.Desugar.desugarSectionGivens') carries its binder's range but is not
    -- a declaration anyone wrote, so it is passed over.
    enclosingTopDecl :: SrcPos -> Section Resolved -> Maybe (TopDecl Resolved, Int)
    enclosingTopDecl pos = inSection 0
      where
        inSection before sec@(MkSection _ _ _ _ decls) =
          go (max before (headerEnd sec)) (filter (not . isElaboration) decls)
        go _ [] = Nothing
        go before (d : ds) = case rangeOf d of
          Just r
            | pos `inRange` r -> case d of
                Section _ s -> inSection before s <|> Just (d, before)
                _           -> Just (d, before)
            | otherwise     -> go r.end.line ds
          Nothing           -> go before ds
        headerEnd (MkSection _ mn maka mgiven _) =
          maximum (0 : [ r.end.line | Just r <- [mn >>= rangeOf, maka >>= rangeOf, mgiven >>= rangeOf] ])
        isElaboration = \ case
          Assume _ (MkAssume ann _ _ _ _) -> isSynthesisedAnno ann
          _                               -> False

    -- The line the declaration's leading block starts on. Every annotation
    -- between whatever precedes the declaration and its own first line
    -- belongs to it, blank lines and comments notwithstanding, so the block
    -- reaches the first of them; and it takes in the run of comment lines
    -- directly over the declaration, or over that first annotation, which read
    -- as the declaration's own. A comment with a blank line under it stays
    -- where it is. Only comments, annotations and whitespace can sit between
    -- two declarations, so a line there that holds anything but whitespace
    -- holds a comment or an annotation.
    leadingLine :: Int -> Int -> Int
    leadingLine before declLine =
      case [ l | l <- annotationLines, l < top ] of
        [] -> top
        ls -> extendUp (minimum ls)
      where
        between l = before < l && l < declLine
        annotationLines =
          [ l | t <- tokens, Lexer.TAnnotations _ <- [t.payload], let l = t.range.start.line, between l ]
        occupied = Set.fromList
          [ l
          | t <- tokens
          , not (isWhitespace t.payload)
          , l <- [t.range.start.line .. t.range.end.line]
          , between l
          ]
        isWhitespace = \ case
          Lexer.TSpaces (Lexer.TSpace _) -> True
          _                              -> False
        top = extendUp declLine
        extendUp l
          | (l - 1) `Set.member` occupied = extendUp (l - 1)
          | otherwise                     = l

-- | An insertion at the start of the given 1-based line.
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

-- ----------------------------------------------------------------------------
-- Smart punctuation: quick fixes for curly quotes, dashes and NBSP pasted in
-- from a word processor (L4.SmartPunctuation)
-- ----------------------------------------------------------------------------

-- | A quick fix's title and the (possibly several, e.g. a paired-quote fix)
-- edits that carry it out. The one shape every smart-punctuation code action
-- below reduces to, so "LSP.L4.Handlers" only has to wrap it in a
-- 'CodeAction'.
data QuickFix = MkQuickFix
  { title :: Text
  , edits :: [TextEdit]
  }
  deriving stock (Eq, Show)

-- | A lexer 'LexFix' (source-span edits) as a 'QuickFix' (LSP-range edits).
lexFixToQuickFix :: LexFix -> QuickFix
lexFixToQuickFix fix =
  MkQuickFix
    { title = fix.title
    , edits = [ TextEdit (srcSpanToLspRange (Just span_)) repl | (span_, repl) <- fix.edits ]
    }

-- | Every quick fix a confusable-character lexer error carries, in the order
-- 'L4.Lexer.confusableLexError' built them: a paired-quote fix first (when
-- there is one), then the dash's two spellings — ordered by
-- 'L4.SmartPunctuation.dashReplacementFor' so the comment-shaped spelling
-- leads when this dash's own position calls for it — or, for every other
-- confusable, just the single-character replacement. The handler marks the
-- first one preferred.
lexErrorQuickFixes :: PError -> [QuickFix]
lexErrorQuickFixes pErr = map lexFixToQuickFix pErr.fixes

-- | The NBSP lint's one fix: replace the exact offending character with an
-- ordinary space.
nbspQuickFix :: SrcRange -> QuickFix
nbspQuickFix range =
  MkQuickFix
    { title = "Replace with an ordinary space"
    , edits = [ TextEdit (srcRangeToLspRange (Just range)) " " ]
    }

-- | The 'Range' spanning an entire document's text, computed from its own
-- line count and last line's length. Deliberately computed from the TEXT
-- itself (which the caller already has, via 'Rope.toText') rather than
-- queried off a 'Rope' API, so this is correct regardless of which
-- 'text-rope' version is in the plan and needs no IDE to test.
wholeDocumentRange :: Text -> Range
wholeDocumentRange contents =
  Range (Position 0 0) (Position endLine endCol)
  where
    endLine = fromIntegral (Text.count "\n" contents)
    endCol  = fromIntegral (Text.length (Text.takeWhileEnd (/= '\n') contents))

-- | The "Straighten all smart punctuation in this file" action's edit: the
-- whole document, replaced by 'L4.Lexer.straightenDocument's repaired text.
-- 'Nothing' below two replacements — a single confusable already has its own
-- per-character fix, so a whole-document action earns its own menu entry
-- only once it does more than that one fix would.
--
-- __Also 'Nothing' when the repaired text still would not lex.__
-- 'Lexer.straightenDocument''s fixed-point loop can stop with the document
-- still broken — most commonly when a curly quote's matching closer sits on
-- a LATER line than 'SP.pairedQuoteCloser' looks ahead to, so straightening
-- the opener alone turns the rest of the file into unterminated string
-- content. Offering this action's title with a replacement count implies a
-- finished repair; presenting that when the file would still fail to lex,
-- under a diagnostic that no longer even mentions smart punctuation, is
-- worse than not offering the action at all — the per-diagnostic quick fix
-- on whatever error remains is still available either way. So this checks
-- the real lexer on the candidate final text before ever promising success.
straightenDocumentQuickFix :: NormalizedUri -> Text -> Maybe QuickFix
straightenDocumentQuickFix uri contents
  | n < 2                                       = Nothing
  | Left _ <- Lexer.execLexer uri final          = Nothing
  | otherwise = Just MkQuickFix
      { title = "Straighten all smart punctuation in this file (" <> Text.pack (show n) <> " replacements)"
      , edits = [ TextEdit (wholeDocumentRange contents) final ]
      }
  where
    (n, final) = Lexer.straightenDocument uri contents

-- | Every raw name in scope at the given position — the toplevel
-- environment plus whatever a narrower @GIVEN@/@§@ scope adds there. Exactly
-- 'completions''s @finalCheckInfos@ computation (same two sources, same
-- combinator), reused here so the did-you-mean fix considers the same
-- candidate set a completion popup at that position would offer.
inScopeRawNamesAt :: SrcPos -> TypeCheckResult -> [Text]
inScopeRawNamesAt pos typeCheck =
  map rawNameToText $ Map.keys $
    Map.unionsWith (\a b -> nub (a <> b)) $
      map (uncurry combineEnvironmentEntityInfo) $
        (typeCheck.environment, typeCheck.entityInfo)
          : map snd (IV.search pos typeCheck.scopeMap)

-- | For an out-of-scope name whose spelling differs from an in-scope one
-- only in its confusable punctuation — a curly quote pasted into one
-- spelling but not the other, __either direction__ — the exact in-scope
-- spelling to offer as a "did you mean" quick fix. 'Nothing' when no
-- in-scope name straightens to the same text, or the two are already
-- spelled identically (there would be nothing to fix, and the name would not
-- have been out of scope to begin with).
--
-- Direction-symmetric by construction: 'SP.straightenChars' is applied to
-- BOTH the reference and every candidate before comparing, so it does not
-- matter which side carries the curly character. Pure and independent of
-- 'RawName''s internals, so it is testable on plain 'Text'.
confusableDidYouMean :: [Text] -> Text -> Maybe Text
confusableDidYouMean inScopeRaw refRaw =
  listToMaybe
    [ candRaw
    | candRaw <- inScopeRaw
    , candRaw /= refRaw
    , SP.straightenChars candRaw == SP.straightenChars refRaw
    ]

-- | 'confusableDidYouMean', wrapped into the 'QuickFix' a code action needs:
-- the out-of-scope reference's own range, replaced with the matched in-scope
-- name's exact spelling (rendered with backticks when it needs them, via
-- 'quoteIfNeeded' — the same renderer 'quotedName' is built on).
confusableDidYouMeanFix :: SrcRange -> Text -> [Text] -> Maybe QuickFix
confusableDidYouMeanFix range refRaw inScopeRaw = do
  candRaw <- confusableDidYouMean inScopeRaw refRaw
  let shown = quoteIfNeeded candRaw
  pure MkQuickFix
    { title = "Replace with " <> shown
    , edits = [ TextEdit (srcRangeToLspRange (Just range)) shown ]
    }
