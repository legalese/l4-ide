{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | The outline of a module, as the editor's outline view and breadcrumbs show
-- it: one symbol per declaration, with a symbol kind that says what it is.
--
-- It is a function of the checked module and what inference learned, so that a
-- test can ask it what the server answers to @textDocument/documentSymbol@
-- without a server.
module LSP.L4.DocumentSymbols
  ( documentSymbols
  , functionSymbolKind
  ) where

import Base

import qualified Data.Map as Map
import qualified Base.Text as Text
import Language.LSP.Protocol.Types (DocumentSymbol (..), SymbolKind (..))
import qualified Language.LSP.Protocol.Types as LSP

import L4.Annotation
import L4.Print
import L4.Syntax
import L4.TypeCheck
import LSP.L4.Actions (outlineGivenParams, outlineLocals)
import LSP.L4.Rules (TypeCheckResult (..), srcRangeToLspRange)

-- | The outline of a checked module.
documentSymbols :: TypeCheckResult -> [DocumentSymbol]
documentSymbols typeCheck =
  let MkModule _ moduleNuri section = typeCheck.module'
      subst = typeCheck.substitution
      entInfo = typeCheck.entityInfo
  in sectionToSymbols moduleNuri subst entInfo section

sectionToSymbols :: NormalizedUri -> Substitution -> EntityInfo -> Section Resolved -> [DocumentSymbol]
sectionToSymbols moduleNuri subst entInfo (MkSection _ _ _ _ topDecls) =
  concatMap (topDeclToSymbol moduleNuri subst entInfo) topDecls

topDeclToSymbol :: NormalizedUri -> Substitution -> EntityInfo -> TopDecl Resolved -> [DocumentSymbol]
topDeclToSymbol moduleNuri subst entInfo = \case
  Section _ s@(MkSection _ mName _ _ _) ->
    case rangeOfNode s of
      Just rng ->
        let name = maybe "§" (nameToText . getOriginal) mName
            lspRange = srcRangeToLspRange (Just rng)
            selRange = maybe lspRange nameSelRange mName
        in [ DocumentSymbol
              { _name = name
              , _detail = Nothing
              , _kind = SymbolKind_Namespace
              , _tags = Nothing
              , _deprecated = Nothing
              , _range = lspRange
              , _selectionRange = selRange
              , _children = Just $ sectionToSymbols moduleNuri subst entInfo s
              }
           ]
      Nothing -> sectionToSymbols moduleNuri subst entInfo s

  Declare _ decl@(MkDeclare _ _ (MkAppForm _ n _ _) typeDecl) ->
    case rangeOfNode decl of
      Just rng ->
        let lspRange = srcRangeToLspRange (Just rng)
            selRange = nameSelRange n
            originalName = nameToText (getOriginal n)
        in case typeDecl of
          RecordDecl{} ->
            [ mkSymbol originalName Nothing SymbolKind_TypeParameter lspRange selRange ]
          EnumDecl _ cons ->
            let children = map (conDeclToSymbol originalName lspRange) cons
            in [ mkSymbolWithChildren originalName Nothing SymbolKind_Enum lspRange selRange children ]
          SynonymDecl _ ty ->
            let detail = prettyLayout ty
            in [ mkSymbol originalName (Just detail) SymbolKind_Variable lspRange selRange ]
          -- An opaque type has no body to describe, so no detail.
          -- 'SymbolKind_TypeParameter' is what the @ASSUME T IS A
          -- TYPE@ spelling of the same declaration already yields
          -- ('typeToSymbolKind' falls through on @"TYPE"@), and is
          -- what a record yields; a migration between the two
          -- spellings leaves the outline unchanged.
          OpaqueDecl _ ->
            [ mkSymbol originalName Nothing SymbolKind_TypeParameter lspRange selRange ]
      Nothing -> []

  Decide _ decide@(MkDecide _ (MkTypeSig _ (MkGivenSig _ givenParams) _) (MkAppForm _ n _ _) body) ->
    case rangeOfNode decide of
      Just rng ->
        let lspRange = srcRangeToLspRange (Just rng)
            selRange = nameSelRange n
            retTy = inferredReturnTy moduleNuri subst entInfo n
            detail = prettyLayout <$> retTy
            kind = functionSymbolKind (isRegulativeBody body) retTy
            paramChildren = map (givenParamToSymbol lspRange) (outlineGivenParams givenParams)
            localChildren = concatMap (localDeclToSymbol moduleNuri subst entInfo lspRange) (outlineLocals body)
        in [ mkSymbolWithChildren (nameToText (getOriginal n)) detail kind lspRange selRange (paramChildren <> localChildren) ]
      Nothing -> []

  Assume _ assume@(MkAssume _ _ (MkAppForm _ n _ _) mTy _) ->
    case rangeOfNode assume of
      Just rng ->
        let lspRange = srcRangeToLspRange (Just rng)
            selRange = nameSelRange n
            (detail, kind) = case mTy of
              Nothing -> (Nothing, SymbolKind_Variable)
              Just ty ->
                let tyText = prettyLayout ty
                in (Just tyText, typeToSymbolKind tyText)
        in [ mkSymbol (nameToText (getOriginal n)) detail kind lspRange selRange ]
      Nothing -> []

  Directive _ d ->
    case rangeOfNode d of
      Just rng ->
        let lspRange = srcRangeToLspRange (Just rng)
            (label, dExpr) = case d of
              LazyEval _ e      -> ("#EVAL", e)
              LazyEvalTrace _ e -> ("#EVALTRACE", e)
              Check _ e         -> ("#CHECK", e)
              Contract _ e _ _  -> ("#CHECK", e)
              Assert _ e        -> ("#ASSERT", e)
              AssertRefused _ e _ -> ("#ASSERT REFUSED", e)
            detail = prettyLayout dExpr
        in [ mkSymbol label (Just detail) SymbolKind_Operator lspRange lspRange ]
      Nothing -> []

  Import _ imp@(MkImport _ n _) ->
    case rangeOfNode imp of
      Just rng ->
        let lspRange = srcRangeToLspRange (Just rng)
            selRange = nameSelRange n
        in [ mkSymbol (nameToText (getOriginal n)) Nothing SymbolKind_File lspRange selRange ]
      Nothing -> []

  _ -> []

nameSelRange :: Resolved -> LSP.Range
nameSelRange n = srcRangeToLspRange (rangeOf (getOriginal n))

-- | The type a rule returns, once inference has finished: the type its name is
-- bound to, with the final substitution applied, and a function's result.
inferredReturnTy :: NormalizedUri -> Substitution -> EntityInfo -> Resolved -> Maybe (Type' Resolved)
inferredReturnTy moduleNuri subst entInfo n =
  case Map.lookup (getUnique n) entInfo of
    Just (_, KnownTerm ty _) ->
      let resolved = applyFinalSubstitution subst moduleNuri ty
      in Just case resolved of
           Fun _ _ ret -> ret
           other       -> other
    _ -> Nothing

-- | What the outline calls a rule: an event when it is a contract, a function
-- otherwise.
--
-- A rule is a contract when its body is a regulative one, or when the type it
-- returns is @DEONTIC@ ('isContractType'). The type is the test, not how it was
-- written: a rule that returns @PROVISION OF P, A@, the deprecated alias, has
-- the same type, and the outline used to look for the prefix @DEONTIC@ in the
-- printed name, which that spelling does not have.
functionSymbolKind :: Bool -> Maybe (Type' Resolved) -> SymbolKind
functionSymbolKind regulativeBody retTy
  | regulativeBody = SymbolKind_Event
  | Just ty <- retTy, isContractType ty = SymbolKind_Event
  | otherwise = SymbolKind_Function

isRegulativeBody :: Expr Resolved -> Bool
isRegulativeBody = \case
  Regulative{} -> True
  _ -> False

mkSymbol :: Text -> Maybe Text -> SymbolKind -> LSP.Range -> LSP.Range -> DocumentSymbol
mkSymbol name detail kind range selRange = mkSymbolWithChildren name detail kind range selRange []

mkSymbolWithChildren :: Text -> Maybe Text -> SymbolKind -> LSP.Range -> LSP.Range -> [DocumentSymbol] -> DocumentSymbol
mkSymbolWithChildren name detail kind range selRange children = DocumentSymbol
  { _name = name
  , _detail = detail
  , _kind = kind
  , _tags = Nothing
  , _deprecated = Nothing
  , _range = range
  , _selectionRange = clampRange range selRange
  , _children = case children of
      [] -> Nothing
      cs -> Just cs
  }

conDeclToSymbol :: Text -> LSP.Range -> ConDecl Resolved -> DocumentSymbol
conDeclToSymbol _enumName parentRange (MkConDecl _ n _) =
  let variantName = nameToText (getOriginal n)
      selRange = nameSelRange n
  in mkSymbol variantName Nothing SymbolKind_EnumMember parentRange selRange

givenParamToSymbol :: LSP.Range -> OptionallyTypedName Resolved -> DocumentSymbol
givenParamToSymbol parentRange (MkOptionallyTypedName _ n mTy _) =
  let paramName = nameToText (getOriginal n)
      selRange = nameSelRange n
      (detail, kind) = case mTy of
        Nothing -> (Nothing, SymbolKind_Variable)
        Just ty ->
          let tyText = prettyLayout ty
          in (Just tyText, typeToSymbolKind tyText)
  in mkSymbol paramName detail kind parentRange selRange

typeToSymbolKind :: Text -> SymbolKind
typeToSymbolKind tyText
  | tyText == "BOOLEAN"                       = SymbolKind_Boolean
  | tyText `elem` ["NUMBER", "INTEGER"]       = SymbolKind_Number
  | tyText `elem` ["STRING", "TEXT"]           = SymbolKind_String
  | "LIST" `Text.isPrefixOf` tyText           = SymbolKind_Array
  | Just inner <- Text.stripPrefix "MAYBE OF " tyText = typeToSymbolKind inner
  | Just inner <- Text.stripPrefix "MAYBE " tyText = typeToSymbolKind inner
  | "FUNCTION" `Text.isPrefixOf` tyText        = SymbolKind_Field
  | otherwise                                 = SymbolKind_TypeParameter

localDeclToSymbol :: NormalizedUri -> Substitution -> EntityInfo -> LSP.Range -> LocalDecl Resolved -> [DocumentSymbol]
localDeclToSymbol moduleNuri subst entInfo parentRange = \case
  LocalDecide _ decide@(MkDecide _ (MkTypeSig _ (MkGivenSig _ givenParams) _) (MkAppForm _ n _ _) localBody) ->
    case rangeOfNode decide of
      Just rng ->
        let lspRange = srcRangeToLspRange (Just rng)
            selRange = nameSelRange n
            -- entityInfo gave no type to the one local rule measured, which had a
            -- GIVEN and a GIVETH (no detail comes out), so for a local rule like
            -- that this decides by the body alone. The question is the one asked
            -- above, and it uses the type whenever entityInfo has one.
            retTy = inferredReturnTy moduleNuri subst entInfo n
            detail = prettyLayout <$> retTy
            kind = functionSymbolKind (isRegulativeBody localBody) retTy
            paramChildren = map (givenParamToSymbol lspRange) givenParams
            nestedLocals = concatMap (localDeclToSymbol moduleNuri subst entInfo lspRange) (outlineLocals localBody)
        in [ mkSymbolWithChildren (nameToText (getOriginal n)) detail kind parentRange selRange (paramChildren <> nestedLocals) ]
      Nothing -> []
  LocalAssume _ assume@(MkAssume _ _ (MkAppForm _ n _ _) mTy _) ->
    case rangeOfNode assume of
      Just _ ->
        let selRange = nameSelRange n
            detail = fmap prettyLayout mTy
        in [ mkSymbol (nameToText (getOriginal n)) detail SymbolKind_Variable parentRange selRange ]
      Nothing -> []

-- | Ensure selectionRange is contained within fullRange (LSP requirement).
-- Falls back to fullRange if selectionRange is not contained.
clampRange :: LSP.Range -> LSP.Range -> LSP.Range
clampRange full sel
  | containsRange full sel = sel
  | otherwise = full

containsRange :: LSP.Range -> LSP.Range -> Bool
containsRange (LSP.Range fStart fEnd) (LSP.Range sStart sEnd) =
  posLeq fStart sStart && posLeq sEnd fEnd

posLeq :: LSP.Position -> LSP.Position -> Bool
posLeq a b = a._line < b._line || (a._line == b._line && a._character <= b._character)
