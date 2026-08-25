{-# LANGUAGE ApplicativeDo #-}

module L4.Parser.ResolveAnnotation (
  -- * main function
  HasNlg(..),
  addNlgCommentsToAst,
  HasDesc(..),
  addDescCommentsToAst,
  HasFixity(..),
  addFixityCommentsToAst,
  renderFixityWarning,
  FixityS(..),
  FixityWarning(..),
  FixityWithSpan,
  HasRef(..),
  addRefCommentsToAst,
  -- * Annotate Syntax Nodes with definite 'SrcSpan's.
  WithSpan (..),
  NlgWithSpan,
  DescWithSpan,
  RefWithSpan,
  -- * Warnings and state
  NlgS(..),
  Warning (..),
  DescS(..),
  DescWarning(..),
  RefS(..),
  RefWarning(..),
  renderRefWarning,
  -- * NlgA / NlgM monad
  NlgA(..),
  NlgM(..),
  liftNlgA,
  extendNlgA,
  registerSrcSpanNlgA,
  hoistNlgA,
  registerNlgA,
  -- * Internals, helpful for testing
  LocRange(..),
  prettyLocRange,
  UpperBound(..),
  locRangeTo,
  LowerBound(..),
  locRangeFrom,
)
where

import Base

import Data.Char (isSpace)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Generics.SOP as SOP
import L4.Annotation
import L4.Syntax
import L4.Parser.SrcSpan

-- | Warnings for attaching Nlg comments to the ast.
--
-- Although named for the nlg pass, this is the shared diagnostic-warning type
-- surfaced by the parser. The @Ref*@ constructors carry ref-attachment
-- warnings ('RefWarning') so they can travel through the same @[Warning]@
-- channel and be rendered alongside nlg warnings (see 'renderRefWarning').
data Warning
  = NotAttached NlgWithSpan
  | UnknownLocation Nlg
  | Ambiguous Name [NlgWithSpan] -- Must be at least two
  | RefUnattached RefWithSpan
    -- ^ A @ref could not be attached to any following AST node.
  | RefNoLocation Ref
    -- ^ A @ref had no source location. That's a bug.
  | FixityAnnotationMisplaced FixityWithSpan
    -- ^ A fixity annotation (@infixl\/@infixr\/@infix) was not on the line
    -- directly above a binary operator definition; it is ignored.
  | FixityAnnotationNoLocation Fixity
    -- ^ A fixity annotation had no source location. That's a bug.
  deriving stock (Show, Eq, Generic)
  deriving anyclass (SOP.Generic)

type NlgWithSpan = WithSpan Nlg

-- ----------------------------------------------------------------------------
-- Desc attachment scaffolding
-- ----------------------------------------------------------------------------

type DescWithSpan = WithSpan Desc

data DescWarning
  = DescMissingLocation Desc
  | DescDuplicatePreferInline DescWithSpan DescWithSpan
  deriving stock (Show, Eq, Generic)
  deriving anyclass (SOP.Generic)

data DescS = DescS
  { descs :: ![DescWithSpan]
  , descWarnings :: ![DescWarning]
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

addDescCommentsToAst :: HasDesc a => [Desc] -> a -> (a, DescS)
addDescCommentsToAst descs ast =
  let
    (withSpan, missing) = preprocessDescs descs
    initialS =
      DescS
        { descs = List.sortOn (.range.start) withSpan
        , descWarnings = fmap DescMissingLocation missing
        }
  in
    runState (addDesc ast) initialS

preprocessDescs :: [Desc] -> ([DescWithSpan], [Desc])
preprocessDescs = foldl' go ([], [])
 where
  go (located, missing) desc =
    case rangeOf desc of
      Nothing -> (located, desc : missing)
      Just r -> (WithSpan (fromSrcRange r) desc : located, missing)

-- | Attach any payload with a 'SrcSpan'.
data WithSpan a = WithSpan
  { range :: SrcSpan
  , payload :: a
  }
  deriving stock (Show, Eq, Ord, Functor, Generic)

-- | Add the given 'Nlg' comments to the 'Program Name' based on
-- the 'SrcRange'. Modifies the 'Program Name'.
--
-- Note, the 'Program Name's exactprint annotations are not modified,
-- we merely add structured data to the ast node's respective 'Anno'.
addNlgCommentsToAst :: HasNlg a => [Nlg] -> a -> (a, NlgS)
addNlgCommentsToAst nlgs p = do
  let
    (nlgWithSpan, unfindable) = preprocessNlgs nlgs

    initialNlgS = NlgS
      { nlgs = nlgWithSpan
      , warnings = fmap UnknownLocation unfindable
      }

  runNlg initialNlgS $ do
    a <- addNlg p
    leftoversToWarnings
    pure a
 where
  locRange = MkLocRange StartOfFile EndOfFile

  runNlg initState act =
    runState
      (act.computation.runNlgM locRange)
      initState

leftoversToWarnings :: NlgA ()
leftoversToWarnings = do
  liftNlgA $ do
    ns <- use #nlgs
    traverse_ addWarning $ fmap NotAttached ns

addWarning :: Warning -> NlgM ()
addWarning warn = do
  modifying' #warnings (warn:)

-- | Attach for each 'Nlg' its 'SrcSpan' for convenient access.
-- If a 'Nlg' doesn't have a 'SrcRange', then that's a bug.
-- We need to report such 'Nlg's as 'Warning's.
preprocessNlgs :: [Nlg] -> ([NlgWithSpan], [Nlg])
preprocessNlgs nlgs =
  -- TODO: this is a known space leak, a lazy accumulator with `foldl'`.
  foldl' go ([], []) nlgs
 where
  go (nlg, unprocessable) n = case rangeOf n of
    Nothing -> (nlg, n : unprocessable)
    Just r -> (WithSpan (fromSrcRange r) n : nlg, unprocessable)

-- ----------------------------------------------------------------------------
-- HasNlg Class and Instances
-- ----------------------------------------------------------------------------

-- | Add 'Nlg' annotations that are in "scope" for the abstract syntax node 'a'.
-- Any type that implements this type class declares that it can either
-- have 'Nlg' annotations, or that one of its children can be annotated with
-- an 'Nlg' comment.
class HasNlg a where
  -- | Add 'Nlg' annotations that are applicable to the current AST node 'a'
  -- based on the 'SrcSpan' of 'a' and its neighbours.
  addNlg :: a -> NlgA a

instance (HasSrcRange n, HasNlg n) => HasNlg (Module n) where
  addNlg a = extendNlgA a $ case a of
    MkModule uri ann sect -> MkModule uri ann <$> addNlg sect

instance (HasSrcRange n, HasNlg n) => HasNlg (Section n) where
  addNlg a = extendNlgA a $ case a of
    MkSection ann lbl maka topDecls -> do
      lbl' <- traverse addNlg lbl
      maka' <- traverse addNlg maka
      topDecls' <- traverse addNlg topDecls
      pure (MkSection ann lbl' maka' topDecls')

instance (HasSrcRange n, HasNlg n) => HasNlg (TopDecl n) where
  addNlg a = extendNlgA a $ case a of
    Declare ann declare -> do
      declare' <- addNlg declare
      pure $ Declare ann declare'
    Decide ann decide -> do
      decide' <- addNlg decide
      pure $ Decide ann decide'
    Assume ann assume -> do
      assume' <- addNlg assume
      pure $ Assume ann assume'
    Directive ann directive -> do
      directive' <- addNlg directive
      pure $ Directive ann directive'
    Import ann import_ -> do
      import_' <- addNlg import_
      pure $ Import ann import_'
    Section ann s -> do
      section <- addNlg s
      pure $ Section ann section
    Timezone ann e -> do
      pure $ Timezone ann e

instance (HasSrcRange n, HasNlg n) => HasNlg (Declare n) where
  addNlg a = extendNlgA a $ case a of
    MkDeclare ann tySig appFormAka tyDecl -> do
      tySig' <- addNlg tySig
      appFormAka' <- addNlg appFormAka
      tyDecl' <- addNlg tyDecl
      pure $ MkDeclare ann tySig' appFormAka' tyDecl'

instance (HasSrcRange n, HasNlg n) => HasNlg (Decide n) where
  addNlg a = extendNlgA a $ case a of
    MkDecide ann tySig appFormAka expr -> do
      tySig' <- addNlg tySig
      appFormAka' <- addNlg appFormAka
      expr' <- addNlg expr
      pure $ MkDecide ann tySig' appFormAka' expr'

instance (HasSrcRange n, HasNlg n) => HasNlg (Assume n) where
  addNlg a = extendNlgA a $ case a of
    MkAssume ann tySig appFormAka order mTypically -> do
      tySig' <- addNlg tySig
      appFormAka' <- addNlg appFormAka
      mTypically' <- traverse addNlg mTypically
      pure $ MkAssume ann tySig' appFormAka' order mTypically'

instance (HasSrcRange n, HasNlg n) => HasNlg (Directive n) where
  addNlg a = extendNlgA a $ case a of
    LazyEval ann e -> do
      e' <- addNlg e
      pure $ LazyEval ann e'
    LazyEvalTrace ann e -> do
      e' <- addNlg e
      pure $ LazyEvalTrace ann e'
    Check ann e -> do
      e' <- addNlg e
      pure $ Check ann e'
    Contract ann e t evs -> do
      e' <- addNlg e
      t' <- addNlg t
      evs' <- traverse addNlg evs
      pure $ Contract ann e' t' evs'
    Assert ann e -> do
      e' <- addNlg e
      pure $ Assert ann e'

instance (HasSrcRange n, HasNlg n) => HasNlg (Event n) where
  addNlg a@(MkEvent ann party act timestamp atFirst) = extendNlgA a do
    party' <- addNlg party
    act' <- addNlg act
    timestamp' <- addNlg timestamp
    pure (MkEvent ann party' act' timestamp' atFirst)


instance (HasSrcRange n, HasNlg n) => HasNlg (Import n) where
  addNlg a = extendNlgA a $ case a of
    MkImport ann n mr -> do
      n' <- addNlg n
      pure $ MkImport ann n' mr

instance (HasSrcRange n, HasNlg n) => HasNlg (TypeDecl n) where
  addNlg a = extendNlgA a $ case a of
    RecordDecl ann mcon typedNames -> do
      typedNames' <- traverse addNlg typedNames
      pure $ RecordDecl ann mcon typedNames'
    EnumDecl ann conDecls -> do
      conDecls' <- traverse addNlg conDecls
      pure $ EnumDecl ann conDecls'
    SynonymDecl ann ty -> do
      ty' <- addNlg ty
      pure $ SynonymDecl ann ty'

instance (HasSrcRange n, HasNlg n) => HasNlg (TypedName n) where
  addNlg a = extendNlgA a $ case a of
    MkTypedName ann n ty mTypically mExpr -> do
      n' <- addNlg n
      ty' <- addNlg ty
      mTypically' <- traverse addNlg mTypically
      pure $ MkTypedName ann n' ty' mTypically' mExpr

instance (HasSrcRange n, HasNlg n) => HasNlg (ConDecl n) where
  addNlg a = extendNlgA a $ case a of
    MkConDecl ann n typedNames -> do
      n' <- addNlg n
      typedNames' <- traverse addNlg typedNames
      pure $ MkConDecl ann n' typedNames'

instance (HasSrcRange n, HasNlg n) => HasNlg (TypeSig n) where
  addNlg a = extendNlgA a $ case a of
    MkTypeSig ann givenSig givethSig -> do
      givenSig' <- addNlg givenSig
      givethSig' <- traverse addNlg givethSig
      pure $ MkTypeSig ann givenSig' givethSig'

instance (HasSrcRange n, HasNlg n) => HasNlg (GivenSig n) where
  addNlg a = extendNlgA a $ case a of
    MkGivenSig ann tys -> do
      tys' <- traverse addNlg tys
      pure $ MkGivenSig ann tys'

instance (HasSrcRange n, HasNlg n) => HasNlg (OptionallyTypedName n) where
  addNlg a = extendNlgA a $ case a of
    MkOptionallyTypedName ann n mty mTypically -> do
      n' <- addNlg n
      tys' <- traverse addNlg mty
      mTypically' <- traverse addNlg mTypically
      pure $ MkOptionallyTypedName ann n' tys' mTypically'

instance (HasSrcRange n, HasNlg n) => HasNlg (GivethSig n) where
  addNlg a = extendNlgA a $ case a of
    MkGivethSig ann mty -> do
      mty' <- addNlg mty
      pure $ MkGivethSig ann mty'

instance (HasSrcRange n, HasNlg n) => HasNlg (Type' n) where
  addNlg a = extendNlgA a $ case a of
    Type   ann -> do
      pure $ Type ann
    TyApp  ann n tys -> do
      n' <- addNlg n
      tys' <- traverse addNlg tys
      pure $ TyApp ann n' tys'
    Fun    ann names ty -> do
      names' <- traverse addNlg names
      ty' <- addNlg ty
      pure $ Fun ann names' ty'
    Forall ann ns ty -> do
      ns' <- traverse addNlg ns
      ty' <- addNlg ty
      pure $ Forall ann ns' ty'
    InfVar ann raw i -> do
      pure $ InfVar ann raw i

instance (HasSrcRange n, HasNlg n) => HasNlg (OptionallyNamedType n) where
  addNlg a = extendNlgA a $ case a of
    MkOptionallyNamedType ann mName ty -> do
      mName' <- traverse addNlg mName
      ty' <- addNlg ty
      pure $ MkOptionallyNamedType ann mName' ty'

instance (HasSrcRange n, HasNlg n) => HasNlg (AppForm n) where
  addNlg a = extendNlgA a $ case a of
    MkAppForm ann n ns maka -> do
      n' <- addNlg n
      ns' <- traverse addNlg ns
      maka' <- traverse addNlg maka
      pure $ MkAppForm ann n' ns' maka'

instance (HasSrcRange n, HasNlg n) => HasNlg (Aka n) where
  addNlg a = extendNlgA a $ case a of
    MkAka ann ns -> do
      ns' <- traverse addNlg ns
      pure $ MkAka ann ns'

instance HasNlg Name where
  addNlg a = extendNlgA a $ case a of
    MkName ann raw -> do
      ann' <- liftNlgA $ do
        nlgs <- takeNlgComments
        case nlgs of
          [nlg] -> do
            pure $ setNlg nlg.payload ann
          [] ->
            pure ann
          ns -> do
            addWarning $ Ambiguous a ns
            pure ann

      pure $ MkName ann' raw

instance (HasSrcRange n, HasNlg n) => HasNlg (Expr n) where
  addNlg expr = extendNlgA expr $ case expr of
    And ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ And ann e1' e2'
    Or ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Or ann e1' e2'
    RAnd ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ RAnd ann e1' e2'
    ROr ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ ROr ann e1' e2'
    Implies ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Implies ann e1' e2'
    Equals ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Equals ann e1' e2'
    Not ann e -> do
      e' <- addNlg e
      pure $ Not ann e'
    Plus ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Plus ann e1' e2'
    Minus ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Minus ann e1' e2'
    Times ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Times ann e1' e2'
    DividedBy ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ DividedBy ann e1' e2'
    Modulo ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Modulo ann e1' e2'
    Cons ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Cons ann e1' e2'
    Leq ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Leq ann e1' e2'
    Lt ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Lt ann e1' e2'
    Gt ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Gt ann e1' e2'
    Geq ann e1 e2 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ Geq ann e1' e2'
    Proj ann e1 n -> do
      e1' <- addNlg e1
      n' <- addNlg n
      pure $ Proj ann e1' n'
    Var ann v -> do
      v' <- addNlg v
      pure $ Var ann v'
    Lam ann sig body -> do
      sig' <- addNlg sig
      body' <- addNlg body
      pure $ Lam ann sig' body'
    App ann n ns -> do
      n' <- addNlg n
      ns' <- traverse addNlg ns
      pure $ App ann n' ns'
    AppNamed ann n ns order -> do
      n' <- addNlg n
      ns' <- traverse addNlg ns
      pure $ AppNamed ann n' ns' order
    IfThenElse ann b e1 e2 -> do
      b' <- addNlg b
      e1' <- addNlg e1
      e2' <- addNlg e2
      pure $ IfThenElse ann b' e1' e2'
    MultiWayIf ann es e2 -> do
      es' <- for es \(MkGuardedExpr ann' l r) -> do
        l' <- addNlg l
        r' <- addNlg r
        pure $ MkGuardedExpr ann' l' r'
      e2' <- addNlg e2
      pure $ MultiWayIf ann es' e2'
    Regulative ann r -> do
      r' <- addNlg r
      pure $ Regulative ann r'
    Consider ann e branches  -> do
      e' <- addNlg e
      branches' <- traverse addNlg branches
      pure $ Consider ann e' branches'
    Lit{} -> do
      pure expr
    Percent{} -> do
      pure expr
    List ann es -> do
      es' <- traverse addNlg es
      pure $ List ann es'
    Where ann e lcl -> do
      e' <- addNlg e
      lcl' <- traverse addNlg lcl
      pure $ Where ann e' lcl'
    LetIn ann lcl e -> do
      lcl' <- traverse addNlg lcl
      e' <- addNlg e
      pure $ LetIn ann lcl' e'
    Event ann e -> Event ann <$> addNlg e
    Fetch ann e -> Fetch ann <$> addNlg e
    Env ann e -> Env ann <$> addNlg e
    Post ann e1 e2 e3 -> do
      e1' <- addNlg e1
      e2' <- addNlg e2
      e3' <- addNlg e3
      pure $ Post ann e1' e2' e3'
    Record ann mParty cell val isOfficial mHence -> do
      mParty' <- traverse addNlg mParty
      cell' <- addNlg cell
      val' <- addNlg val
      mHence' <- traverse addNlg mHence
      pure $ Record ann mParty' cell' val' isOfficial mHence'
    ReadCell ann mParty isOfficial mode cell -> do
      mParty' <- traverse addNlg mParty
      cell' <- addNlg cell
      pure $ ReadCell ann mParty' isOfficial mode cell'
    Concat ann es -> do
      es' <- traverse addNlg es
      pure $ Concat ann es'
    AsString ann e -> AsString ann <$> addNlg e
    Breach ann mParty mReason -> do
      mParty' <- traverse addNlg mParty
      mReason' <- traverse addNlg mReason
      pure $ Breach ann mParty' mReason'
    Inert ann txt ctx -> pure $ Inert ann txt ctx

instance (HasSrcRange n, HasNlg n) => HasNlg (Deonton n) where
  addNlg (MkDeonton ann' party event deadline followup lest) = do
    party' <- addNlg party
    event' <- addNlg event
    deadline' <- traverse addNlg deadline
    followup' <- traverse addNlg followup
    lest' <- traverse addNlg lest
    pure $  MkDeonton ann' party' event' deadline' followup' lest'

instance (HasSrcRange n, HasNlg n) => HasNlg (RAction n) where
  addNlg (MkAction ann modal rule provided) = do
    rule' <- addNlg rule
    provided' <- traverse addNlg provided
    pure $  MkAction ann modal rule' provided'

instance (HasSrcRange n, HasNlg n) => HasNlg (Branch n) where
  addNlg a = extendNlgA a $ case a of
    MkBranch ann' (When ann pat) e -> do
      pat' <- addNlg pat
      e' <- addNlg e
      pure $ MkBranch ann' (When ann pat') e'
    MkBranch ann' (Otherwise ann) e -> do
      e' <- addNlg e
      pure $ MkBranch ann' (Otherwise ann) e'

instance (HasSrcRange n, HasNlg n) => HasNlg (Pattern n) where
  addNlg a = extendNlgA a $ case a of
    PatVar ann n -> do
      n' <- addNlg n
      pure $ PatVar ann n'
    PatApp ann n pats -> do
      n' <- addNlg n
      pats' <- traverse addNlg pats
      pure $ PatApp ann n' pats'
    PatCons ann patHead patTail -> do
      patHead' <- addNlg patHead
      patTail' <-addNlg patTail
      pure $ PatCons ann patHead' patTail'
    PatExpr ann expr -> pure $ PatExpr ann expr
    PatLit ann lit -> pure $ PatLit ann lit

instance (HasSrcRange n, HasNlg n) => HasNlg (NamedExpr n) where
  addNlg a = extendNlgA a $ case a of
    MkNamedExpr ann n e -> do
      n' <- addNlg n
      e' <- addNlg e
      pure $ MkNamedExpr ann n' e'

instance (HasSrcRange n, HasNlg n) => HasNlg (LocalDecl n) where
  addNlg a = extendNlgA a $ case a of
    LocalDecide ann decide -> do
      decide' <- addNlg decide
      pure $ LocalDecide ann decide'
    LocalAssume ann assume -> do
      assume' <- addNlg assume
      pure $ LocalAssume ann assume'

-- ----------------------------------------------------------------------------
-- HasDesc Class and Instances
-- ----------------------------------------------------------------------------

class HasDesc a where
  addDesc :: a -> State DescS a

instance HasDesc (Module n) where
  addDesc (MkModule uri ann sect) =
    MkModule uri ann <$> addDesc sect

instance HasDesc (Section n) where
  addDesc (MkSection ann lbl maka decls) = do
    decls' <- traverse addDesc decls
    pure $ MkSection ann lbl maka decls'

instance HasDesc (TopDecl n) where
  addDesc = \ case
    Declare ann decl -> Declare ann <$> addDesc decl
    Decide ann dec -> Decide ann <$> addDesc dec
    Assume ann asm -> Assume ann <$> addDesc asm
    Directive ann dir -> Directive ann <$> addDesc dir
    Import ann imp -> Import ann <$> addDesc imp
    Section ann sect -> Section ann <$> addDesc sect
    Timezone ann e -> pure $ Timezone ann e

instance HasDesc (Declare n) where
  addDesc decl@(MkDeclare ann tySig appForm tyDecl) = do
    ann' <- attachLeadingDesc decl ann
    tySig' <- addDesc tySig
    app' <- addDesc appForm
    tyDecl' <- addDesc tyDecl
    pure $ MkDeclare ann' tySig' app' tyDecl'

instance HasDesc (Decide n) where
  addDesc dec@(MkDecide ann tySig appForm expr) = do
    -- Attach leading desc to Decide FIRST, before processing children.
    -- This ensures @export annotations are claimed by Decide before
    -- parameters in the tySig can consume them.
    ann' <- attachLeadingDesc dec ann
    tySig' <- addDesc tySig
    app' <- addDesc appForm
    expr' <- addDesc expr
    pure $ MkDecide ann' tySig' app' expr'

instance HasDesc (Assume n) where
  addDesc asm@(MkAssume ann tySig appForm mType mTypically) = do
    ann' <- attachLeadingDesc asm ann
    tySig' <- addDesc tySig
    app' <- addDesc appForm
    mType' <- traverse addDesc mType
    mTypically' <- traverse addDesc mTypically
    pure $ MkAssume ann' tySig' app' mType' mTypically'

instance HasDesc (Directive n) where
  addDesc = \ case
    LazyEval ann e -> LazyEval ann <$> addDesc e
    LazyEvalTrace ann e -> LazyEvalTrace ann <$> addDesc e
    Check ann e -> Check ann <$> addDesc e
    Contract ann e t evs -> Contract ann <$> addDesc e <*> addDesc t <*> traverse addDesc evs
    Assert ann e -> Assert ann <$> addDesc e

instance HasDesc (Import n) where
  addDesc a = pure a

instance HasDesc (TypeSig n) where
  addDesc (MkTypeSig ann given giveth) =
    MkTypeSig ann <$> addDesc given <*> traverse addDesc giveth

instance HasDesc (GivenSig n) where
  addDesc (MkGivenSig ann names) =
    MkGivenSig ann <$> traverse addDesc names

instance HasDesc (OptionallyTypedName n) where
  addDesc name@(MkOptionallyTypedName ann n mType mTypically) = do
    mType' <- traverse addDesc mType
    mTypically' <- traverse addDesc mTypically
    ann' <- attachLeadingOrInlineDesc name ann
    pure $ MkOptionallyTypedName ann' n mType' mTypically'

instance HasDesc (GivethSig n) where
  addDesc (MkGivethSig ann ty) = do
    ty' <- addDesc ty
    pure $ MkGivethSig ann ty'

instance HasDesc (TypeDecl n) where
  addDesc = \ case
    RecordDecl ann mcon names ->
      RecordDecl ann mcon <$> traverse addDesc names
    EnumDecl ann cons ->
      EnumDecl ann <$> traverse addDesc cons
    SynonymDecl ann ty ->
      SynonymDecl ann <$> addDesc ty

instance HasDesc (ConDecl n) where
  addDesc (MkConDecl ann name names) =
    MkConDecl ann name <$> traverse addDesc names

instance HasDesc (TypedName n) where
  addDesc name@(MkTypedName ann n ty mTypically mExpr) = do
    ty' <- addDesc ty
    mTypically' <- traverse addDesc mTypically
    ann' <- attachLeadingOrInlineDesc name ann
    pure $ MkTypedName ann' n ty' mTypically' mExpr

instance HasDesc (Type' n) where
  addDesc = pure

instance HasDesc (AppForm n) where
  addDesc (MkAppForm ann name args maka) =
    MkAppForm ann name args <$> traverse addDesc maka

instance HasDesc (Aka n) where
  addDesc (MkAka ann names) = pure (MkAka ann names)

instance HasDesc (Expr n) where
  addDesc = pure

takeMatchingDescs :: (DescWithSpan -> Bool) -> State DescS [DescWithSpan]
takeMatchingDescs predicate = do
  s <- get
  let (matches, rest) = List.partition predicate s.descs
  put s{descs = rest}
  pure matches

attachLeadingDesc :: (HasSrcRange a) => a -> Anno -> State DescS Anno
attachLeadingDesc node ann =
  case nodeSpan node of
    Nothing -> pure ann
    Just nodeRange -> do
      matches <- takeMatchingDescs (descPrecedesNode nodeRange)
      pure $ maybe ann (\d -> setDesc d.payload ann) (pickLeadingDesc matches)

attachLeadingOrInlineDesc :: (HasSrcRange a) => a -> Anno -> State DescS Anno
attachLeadingOrInlineDesc node ann =
  case nodeSpan node of
    Nothing -> pure ann
    Just nodeRange -> do
      leadingMatches <- takeMatchingDescs (descPrecedesNode nodeRange)
      inlineMatches <- takeMatchingDescs (descInlineFor nodeRange)
      let mLeading = lastMaybe leadingMatches
          mInline = lastMaybe inlineMatches
      case (mLeading, mInline) of
        (Nothing, Nothing) -> pure ann
        (Just d, Nothing) -> pure $ setDesc d.payload ann
        (Nothing, Just d) -> pure $ setDesc d.payload ann
        (Just leadingD, Just inlineD) -> do
          addDescWarning $ DescDuplicatePreferInline leadingD inlineD
          pure $ setDesc inlineD.payload ann

-- | Choose which leading desc to attach to a node when there are multiple
-- candidates. Prefers the latest match that carries an @export\/@default
-- keyword so the export marker is still detected when @desc lines sit
-- between the @export annotation and the function definition.
-- Falls back to the latest match (closest to the node) otherwise.
pickLeadingDesc :: [DescWithSpan] -> Maybe DescWithSpan
pickLeadingDesc matches =
  case lastMaybe (filter (descIsExportMarked . (.payload)) matches) of
    Just d  -> Just d
    Nothing -> lastMaybe matches

-- | True if a Desc's text begins with the @export, @default or @nonexhaustive
-- keyword, mirroring how 'L4.Export.parseDescText' consumes the leading
-- tokens.
descIsExportMarked :: Desc -> Bool
descIsExportMarked d =
  let token = Text.toLower (Text.takeWhile (not . isSpace) (Text.stripStart (getDesc d)))
  in token == "export" || token == "default" || token == "nonexhaustive"

addDescWarning :: DescWarning -> State DescS ()
addDescWarning w = modify' $ \s -> s{descWarnings = w : s.descWarnings}

nodeSpan :: (HasSrcRange a) => a -> Maybe SrcSpan
nodeSpan = fmap fromSrcRange . rangeOf

descPrecedesNode :: SrcSpan -> WithSpan a -> Bool
descPrecedesNode nodeRange desc =
  let
    nodeStart = nodeRange.start
    descEnd = desc.range.end
    descStart = desc.range.start
    beforeNode =
      descEnd.line < nodeStart.line
        || (descEnd.line == nodeStart.line && descEnd.column <= nodeStart.column)
    alignedWithNode =
      descStart.column <= nodeStart.column + topLevelColumnSlack
  in
    beforeNode && alignedWithNode

descInlineFor :: SrcSpan -> WithSpan a -> Bool
descInlineFor nodeRange desc =
  let
    nodeEnd = nodeRange.end
    descStart = desc.range.start
  in
    descStart.line == nodeEnd.line && descStart.column >= nodeEnd.column

topLevelColumnSlack :: Int
topLevelColumnSlack = 8

lastMaybe :: [a] -> Maybe a
lastMaybe [] = Nothing
lastMaybe xs = Just (last xs)

-- ----------------------------------------------------------------------------
-- Fixity attachment (mirrors the Desc pass)
-- ----------------------------------------------------------------------------

type FixityWithSpan = WithSpan Fixity

data FixityWarning
  = FixityMissingLocation Fixity
    -- ^ A fixity annotation had no source range. Internal error.
  | FixityMisplaced FixityWithSpan
    -- ^ A fixity annotation was not on the line directly above a binary
    -- operator definition: it sat above a directive, import, type
    -- declaration or section, inline on a parameter, inside a WHERE body, or
    -- was superseded by a later annotation on the same definition. Ignored.
  deriving stock (Show, Eq, Generic)
  deriving anyclass (SOP.Generic)

data FixityS = FixityS
  { fixities :: ![FixityWithSpan]
  , fixityWarnings :: ![FixityWarning]
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

addFixityCommentsToAst :: HasFixity a => [Fixity] -> a -> (a, FixityS)
addFixityCommentsToAst fixities ast =
  let
    (withSpan, missing) = preprocessFixities fixities
    initialS =
      FixityS
        { fixities = List.sortOn (.range.start) withSpan
        , fixityWarnings = fmap FixityMissingLocation missing
        }
    (ast', s) = runState (addFixity ast) initialS
  in
    -- Any annotation still unclaimed after the whole module was walked (e.g.
    -- a trailing annotation with no following definition) is misplaced too.
    ( ast'
    , s { fixities = []
        , fixityWarnings = fmap FixityMisplaced s.fixities <> s.fixityWarnings
        }
    )

preprocessFixities :: [Fixity] -> ([FixityWithSpan], [Fixity])
preprocessFixities = foldl' go ([], [])
 where
  go (located, missing) fx =
    case rangeOf fx of
      Nothing -> (located, fx : missing)
      Just r -> (WithSpan (fromSrcRange r) fx : located, missing)

addFixityWarning :: FixityWarning -> State FixityS ()
addFixityWarning w = modify' $ \s -> s{fixityWarnings = w : s.fixityWarnings}

-- | Bridge a fixity-attachment warning into the shared parser warning
-- channel (rendered by 'L4.Rules').
renderFixityWarning :: FixityWarning -> Warning
renderFixityWarning = \ case
  FixityMissingLocation fx -> FixityAnnotationNoLocation fx
  FixityMisplaced fxs      -> FixityAnnotationMisplaced fxs

class HasFixity a where
  addFixity :: a -> State FixityS a

instance HasFixity (Module n) where
  addFixity (MkModule uri ann sect) =
    MkModule uri ann <$> addFixity sect

instance HasFixity (Section n) where
  -- A section only sequences its declarations; each leaf construct below
  -- claims the annotations that precede it. A fixity above a section header
  -- therefore becomes the leading annotation of the section's first
  -- declaration — the nearest following construct.
  addFixity (MkSection ann lbl maka decls) = do
    decls' <- traverse addFixity decls
    pure $ MkSection ann lbl maka decls'

instance HasFixity (TopDecl n) where
  -- Only DECIDE/ASSUME can define a binary operator, so only they honor a
  -- leading fixity annotation. Every other top-level construct still CLAIMS
  -- (and reports) any fixity annotation stranded on it, so that a stray
  -- annotation cannot leak past it to a later, unrelated definition.
  -- Processing runs in document order, which bounds a Decide's leading
  -- annotation to genuine adjacency: any intervening construct claims first.
  addFixity = \ case
    Declare ann decl  -> do rejectFixityAround decl; pure (Declare ann decl)
    Decide ann dec    -> Decide ann <$> honorDecideFixity dec
    Assume ann asm    -> Assume ann <$> honorAssumeFixity asm
    Directive ann dir -> do rejectFixityAround dir; pure (Directive ann dir)
    Import ann imp    -> do rejectFixityAround imp; pure (Import ann imp)
    Section ann sect  -> Section ann <$> addFixity sect
    Timezone ann e    -> do rejectFixityAround e; pure (Timezone ann e)

honorDecideFixity :: Decide n -> State FixityS (Decide n)
honorDecideFixity dec@(MkDecide ann tySig appForm expr) = do
  ann' <- honorLeadingFixity dec ann
  pure (MkDecide ann' tySig appForm expr)

honorAssumeFixity :: Assume n -> State FixityS (Assume n)
honorAssumeFixity asm@(MkAssume ann tySig appForm mType mTypically) = do
  ann' <- honorLeadingFixity asm ann
  pure (MkAssume ann' tySig appForm mType mTypically)

takeMatchingFixities :: (FixityWithSpan -> Bool) -> State FixityS [FixityWithSpan]
takeMatchingFixities predicate = do
  s <- get
  let (matches, rest) = List.partition predicate s.fixities
  put s{fixities = rest}
  pure matches

-- | Claim every not-yet-attached fixity annotation positioned before this
-- construct ends, split into those preceding its start (@leading@) and those
-- falling inside it (@interior@ — inline on a parameter, or within a WHERE
-- body). Because processing runs in document order and each construct removes
-- what it claims, a construct only ever sees annotations since the previous
-- construct.
claimFixitiesAround :: HasSrcRange a => a -> State FixityS ([FixityWithSpan], [FixityWithSpan])
claimFixitiesAround node =
  case nodeSpan node of
    Nothing -> pure ([], [])
    Just r -> do
      claimed <- takeMatchingFixities (\fx -> posLt fx.range.start r.end)
      pure (List.partition (\fx -> posLe fx.range.end r.start) claimed)

-- | Attach the closest leading fixity annotation to a binary-operator
-- candidate's 'Anno' (the typechecker validates that it really is a binary
-- operator, see 'L4.TypeCheck.applyFixityAnnotation'). A superseded stacked
-- annotation, or any annotation sitting inside the definition, is reported as
-- misplaced and dropped.
honorLeadingFixity :: HasSrcRange a => a -> Anno -> State FixityS Anno
honorLeadingFixity node ann = do
  (leading, interior) <- claimFixitiesAround node
  case reverse leading of
    closest : superseded -> do
      warnMisplaced (superseded <> interior)
      pure (setFixity closest.payload ann)
    [] -> do
      warnMisplaced interior
      pure ann

-- | Claim and report every fixity annotation preceding or inside a construct
-- that cannot carry fixity (a directive, import, DECLARE, or timezone).
rejectFixityAround :: HasSrcRange a => a -> State FixityS ()
rejectFixityAround node = do
  (leading, interior) <- claimFixitiesAround node
  warnMisplaced (leading <> interior)

warnMisplaced :: [FixityWithSpan] -> State FixityS ()
warnMisplaced = mapM_ (addFixityWarning . FixityMisplaced)

posLt :: SrcPos -> SrcPos -> Bool
posLt a b = a.line < b.line || (a.line == b.line && a.column < b.column)

posLe :: SrcPos -> SrcPos -> Bool
posLe a b = a.line < b.line || (a.line == b.line && a.column <= b.column)

-- ----------------------------------------------------------------------------
-- Ref attachment scaffolding
-- ----------------------------------------------------------------------------

type RefWithSpan = WithSpan Ref

data RefWarning
  = RefMissingLocation Ref
    -- ^ A 'Ref' had no 'SrcRange', so we could not place it. That's a bug.
  | RefNotAttached RefWithSpan
    -- ^ A 'Ref' could not be attached to any following AST node.
  deriving stock (Show, Eq, Generic)
  deriving anyclass (SOP.Generic)

data RefS = RefS
  { refs :: ![RefWithSpan]
    -- ^ Refs that have not yet been attached to an AST node.
  , refWarnings :: ![RefWarning]
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

-- | Convert a ref-attachment warning into the shared 'Warning' type so it can
-- be surfaced as a diagnostic alongside nlg warnings. This is a faithful
-- 1:1 mapping onto the dedicated @Ref*@ constructors of 'Warning'.
renderRefWarning :: RefWarning -> Warning
renderRefWarning = \ case
  RefNotAttached r     -> RefUnattached r
  RefMissingLocation r -> RefNoLocation r

-- | Attach @ref annotations to the AST nodes that immediately follow them.
--
-- Unlike @nlg (which targets 'Name' nodes) or @desc (which targets top-level
-- declarations), a @ref can attach to /any/ AST node. The attachment rule is
-- \"the immediately following AST node, regardless of type\".
--
-- We rely on the fact that a pre-order traversal of a well-formed AST visits
-- nodes in non-decreasing start position. Therefore, the first node whose
-- start position is at or after a ref's end position is the immediately
-- following node, and it claims the ref. Refs are removed from the state as
-- soon as they are claimed, so each ref is used at most once.
--
-- Like 'addNlgCommentsToAst', we merely add structured data to the ast node's
-- respective 'Anno'; the exact-print annotations are left untouched.
addRefCommentsToAst :: HasRef a => [Ref] -> a -> (a, RefS)
addRefCommentsToAst refs0 ast =
  let
    (withSpan, missing) = preprocessRefs refs0
    initialS =
      RefS
        { refs = List.sortOn (.range.start) withSpan
        , refWarnings = fmap RefMissingLocation missing
        }
    (ast', s') = runState (addRef ast) initialS
    -- Any refs that were never claimed become warnings.
    leftovers = fmap RefNotAttached s'.refs
  in
    (ast', s'{refs = [], refWarnings = s'.refWarnings <> leftovers})

preprocessRefs :: [Ref] -> ([RefWithSpan], [Ref])
preprocessRefs = foldl' go ([], [])
 where
  go (located, missing) ref =
    case rangeOf ref of
      Nothing -> (located, ref : missing)
      Just r -> (WithSpan (fromSrcRange r) ref : located, missing)

takeMatchingRefs :: (RefWithSpan -> Bool) -> State RefS [RefWithSpan]
takeMatchingRefs predicate = do
  s <- get
  let (matches, rest) = List.partition predicate s.refs
  put s{refs = rest}
  pure matches

addRefWarning :: RefWarning -> State RefS ()
addRefWarning w = modify' $ \s -> s{refWarnings = w : s.refWarnings}

-- | True if a ref sits (entirely) before the given node's start position, i.e.
-- the node is a candidate for being the ref's \"immediately following node\".
refPrecedesNode :: SrcSpan -> RefWithSpan -> Bool
refPrecedesNode nodeRange ref =
  let
    nodeStart = nodeRange.start
    refEnd = ref.range.end
  in
    refEnd.line < nodeStart.line
      || (refEnd.line == nodeStart.line && refEnd.column <= nodeStart.column)

-- | Attach at most one pending ref (the one closest to the node) to the node's
-- 'Anno'. When multiple refs precede the same node, the nearest one wins and
-- the others are reported as 'RefNotAttached' warnings (a node's 'Anno' can
-- only carry a single 'Ref').
attachRef :: HasSrcRange a => a -> Anno -> State RefS Anno
attachRef node ann =
  case nodeSpan node of
    Nothing -> pure ann
    Just nodeRange -> do
      matches <- takeMatchingRefs (refPrecedesNode nodeRange)
      case reverse (List.sortOn (.range.start) matches) of
        [] -> pure ann
        (nearest : extras) -> do
          traverse_ (addRefWarning . RefNotAttached) extras
          pure $ setRef nearest.payload ann

-- ----------------------------------------------------------------------------
-- HasRef Class and Instances
-- ----------------------------------------------------------------------------

-- | Any type that implements this type class can either carry a @ref
-- annotation on its own 'Anno', or has children that can. The traversal
-- visits every node in concrete-syntax (source) order and, at each node,
-- attaches any pending refs that precede it.
class HasRef a where
  addRef :: a -> State RefS a

instance (HasSrcRange n, HasRef n) => HasRef (Module n) where
  -- Do NOT attach at the container level: a leading @ref shares its start with
  -- the first declaration, and the Module (visited first in the pre-order walk)
  -- would greedily claim it. Mirror 'HasDesc (Module n)': recurse only.
  addRef (MkModule ann uri sect) =
    MkModule ann uri <$> addRef sect

instance (HasSrcRange n, HasRef n) => HasRef (Section n) where
  -- As with 'HasRef (Module n)', do NOT attach at the container level; recurse
  -- only so a leading @ref reaches the first child declaration.
  addRef (MkSection ann lbl maka decls) = do
    lbl' <- traverse addRef lbl
    maka' <- traverse addRef maka
    decls' <- traverse addRef decls
    pure $ MkSection ann lbl' maka' decls'

instance (HasSrcRange n, HasRef n) => HasRef (TopDecl n) where
  addRef a = case a of
    Declare ann d -> attachRef a ann >>= \ann' -> Declare ann' <$> addRef d
    Decide ann d -> attachRef a ann >>= \ann' -> Decide ann' <$> addRef d
    Assume ann d -> attachRef a ann >>= \ann' -> Assume ann' <$> addRef d
    Directive ann d -> attachRef a ann >>= \ann' -> Directive ann' <$> addRef d
    Import ann d -> attachRef a ann >>= \ann' -> Import ann' <$> addRef d
    Section ann d -> attachRef a ann >>= \ann' -> Section ann' <$> addRef d
    Timezone ann e -> attachRef a ann >>= \ann' -> Timezone ann' <$> addRef e

instance (HasSrcRange n, HasRef n) => HasRef (Declare n) where
  addRef d@(MkDeclare ann tySig appForm tyDecl) = do
    ann' <- attachRef d ann
    tySig' <- addRef tySig
    appForm' <- addRef appForm
    tyDecl' <- addRef tyDecl
    pure $ MkDeclare ann' tySig' appForm' tyDecl'

instance (HasSrcRange n, HasRef n) => HasRef (Decide n) where
  addRef d@(MkDecide ann tySig appForm expr) = do
    ann' <- attachRef d ann
    tySig' <- addRef tySig
    appForm' <- addRef appForm
    expr' <- addRef expr
    pure $ MkDecide ann' tySig' appForm' expr'

instance (HasSrcRange n, HasRef n) => HasRef (Assume n) where
  addRef a@(MkAssume ann tySig appForm order typically) = do
    ann' <- attachRef a ann
    tySig' <- addRef tySig
    appForm' <- addRef appForm
    order' <- traverse addRef order
    typically' <- traverse addRef typically
    pure $ MkAssume ann' tySig' appForm' order' typically'

instance (HasSrcRange n, HasRef n) => HasRef (Directive n) where
  addRef a = case a of
    LazyEval ann e -> attachRef a ann >>= \ann' -> LazyEval ann' <$> addRef e
    LazyEvalTrace ann e -> attachRef a ann >>= \ann' -> LazyEvalTrace ann' <$> addRef e
    Check ann e -> attachRef a ann >>= \ann' -> Check ann' <$> addRef e
    Contract ann e t evs -> attachRef a ann >>= \ann' ->
      Contract ann' <$> addRef e <*> addRef t <*> traverse addRef evs
    Assert ann e -> attachRef a ann >>= \ann' -> Assert ann' <$> addRef e

instance (HasSrcRange n, HasRef n) => HasRef (Event n) where
  addRef a@(MkEvent ann party act timestamp atFirst) = do
    ann' <- attachRef a ann
    party' <- addRef party
    act' <- addRef act
    timestamp' <- addRef timestamp
    pure $ MkEvent ann' party' act' timestamp' atFirst

instance (HasSrcRange n, HasRef n) => HasRef (Import n) where
  addRef a@(MkImport ann n mr) = do
    ann' <- attachRef a ann
    n' <- addRef n
    pure $ MkImport ann' n' mr

instance (HasSrcRange n, HasRef n) => HasRef (TypeDecl n) where
  addRef a = case a of
    RecordDecl ann mcon typedNames -> attachRef a ann >>= \ann' ->
      RecordDecl ann' mcon <$> traverse addRef typedNames
    EnumDecl ann conDecls -> attachRef a ann >>= \ann' ->
      EnumDecl ann' <$> traverse addRef conDecls
    SynonymDecl ann ty -> attachRef a ann >>= \ann' ->
      SynonymDecl ann' <$> addRef ty

instance (HasSrcRange n, HasRef n) => HasRef (TypedName n) where
  addRef a@(MkTypedName ann n ty mExpr typically) = do
    ann' <- attachRef a ann
    n' <- addRef n
    ty' <- addRef ty
    mExpr' <- traverse addRef mExpr
    typically' <- traverse addRef typically
    pure $ MkTypedName ann' n' ty' mExpr' typically'

instance (HasSrcRange n, HasRef n) => HasRef (ConDecl n) where
  addRef a@(MkConDecl ann n typedNames) = do
    ann' <- attachRef a ann
    n' <- addRef n
    typedNames' <- traverse addRef typedNames
    pure $ MkConDecl ann' n' typedNames'

instance (HasSrcRange n, HasRef n) => HasRef (TypeSig n) where
  addRef a@(MkTypeSig ann givenSig givethSig) = do
    ann' <- attachRef a ann
    givenSig' <- addRef givenSig
    givethSig' <- traverse addRef givethSig
    pure $ MkTypeSig ann' givenSig' givethSig'

instance (HasSrcRange n, HasRef n) => HasRef (GivenSig n) where
  addRef a@(MkGivenSig ann tys) = do
    ann' <- attachRef a ann
    tys' <- traverse addRef tys
    pure $ MkGivenSig ann' tys'

instance (HasSrcRange n, HasRef n) => HasRef (OptionallyTypedName n) where
  addRef a@(MkOptionallyTypedName ann n mty typically) = do
    ann' <- attachRef a ann
    n' <- addRef n
    mty' <- traverse addRef mty
    typically' <- traverse addRef typically
    pure $ MkOptionallyTypedName ann' n' mty' typically'

instance (HasSrcRange n, HasRef n) => HasRef (GivethSig n) where
  addRef a@(MkGivethSig ann mty) = do
    ann' <- attachRef a ann
    mty' <- addRef mty
    pure $ MkGivethSig ann' mty'

instance (HasSrcRange n, HasRef n) => HasRef (Type' n) where
  addRef a = case a of
    Type ann -> attachRef a ann >>= \ann' -> pure (Type ann')
    TyApp ann n tys -> attachRef a ann >>= \ann' -> do
      n' <- addRef n
      tys' <- traverse addRef tys
      pure $ TyApp ann' n' tys'
    Fun ann names ty -> attachRef a ann >>= \ann' -> do
      names' <- traverse addRef names
      ty' <- addRef ty
      pure $ Fun ann' names' ty'
    Forall ann ns ty -> attachRef a ann >>= \ann' -> do
      ns' <- traverse addRef ns
      ty' <- addRef ty
      pure $ Forall ann' ns' ty'
    InfVar ann raw i -> attachRef a ann >>= \ann' -> pure (InfVar ann' raw i)

instance (HasSrcRange n, HasRef n) => HasRef (OptionallyNamedType n) where
  addRef a@(MkOptionallyNamedType ann mName ty) = do
    ann' <- attachRef a ann
    mName' <- traverse addRef mName
    ty' <- addRef ty
    pure $ MkOptionallyNamedType ann' mName' ty'

instance (HasSrcRange n, HasRef n) => HasRef (AppForm n) where
  addRef a@(MkAppForm ann n ns maka) = do
    ann' <- attachRef a ann
    n' <- addRef n
    ns' <- traverse addRef ns
    maka' <- traverse addRef maka
    pure $ MkAppForm ann' n' ns' maka'

instance (HasSrcRange n, HasRef n) => HasRef (Aka n) where
  addRef a@(MkAka ann ns) = do
    ann' <- attachRef a ann
    ns' <- traverse addRef ns
    pure $ MkAka ann' ns'

instance HasRef Name where
  addRef a@(MkName ann raw) = do
    ann' <- attachRef a ann
    pure $ MkName ann' raw

instance (HasSrcRange n, HasRef n) => HasRef (Expr n) where
  addRef expr = case expr of
    And ann e1 e2 -> bin And ann e1 e2
    Or ann e1 e2 -> bin Or ann e1 e2
    RAnd ann e1 e2 -> bin RAnd ann e1 e2
    ROr ann e1 e2 -> bin ROr ann e1 e2
    Implies ann e1 e2 -> bin Implies ann e1 e2
    Equals ann e1 e2 -> bin Equals ann e1 e2
    Plus ann e1 e2 -> bin Plus ann e1 e2
    Minus ann e1 e2 -> bin Minus ann e1 e2
    Times ann e1 e2 -> bin Times ann e1 e2
    DividedBy ann e1 e2 -> bin DividedBy ann e1 e2
    Modulo ann e1 e2 -> bin Modulo ann e1 e2
    Cons ann e1 e2 -> bin Cons ann e1 e2
    Leq ann e1 e2 -> bin Leq ann e1 e2
    Lt ann e1 e2 -> bin Lt ann e1 e2
    Gt ann e1 e2 -> bin Gt ann e1 e2
    Geq ann e1 e2 -> bin Geq ann e1 e2
    Not ann e -> attachRef expr ann >>= \ann' -> Not ann' <$> addRef e
    Proj ann e1 n -> attachRef expr ann >>= \ann' -> do
      e1' <- addRef e1
      n' <- addRef n
      pure $ Proj ann' e1' n'
    Var ann v -> attachRef expr ann >>= \ann' -> Var ann' <$> addRef v
    Lam ann sig body -> attachRef expr ann >>= \ann' -> do
      sig' <- addRef sig
      body' <- addRef body
      pure $ Lam ann' sig' body'
    App ann n ns -> attachRef expr ann >>= \ann' -> do
      n' <- addRef n
      ns' <- traverse addRef ns
      pure $ App ann' n' ns'
    AppNamed ann n ns order -> attachRef expr ann >>= \ann' -> do
      n' <- addRef n
      ns' <- traverse addRef ns
      pure $ AppNamed ann' n' ns' order
    IfThenElse ann b e1 e2 -> attachRef expr ann >>= \ann' -> do
      b' <- addRef b
      e1' <- addRef e1
      e2' <- addRef e2
      pure $ IfThenElse ann' b' e1' e2'
    MultiWayIf ann es e2 -> attachRef expr ann >>= \ann' -> do
      es' <- for es \(MkGuardedExpr gann l r) -> do
        gann' <- attachRef (MkGuardedExpr gann l r) gann
        l' <- addRef l
        r' <- addRef r
        pure $ MkGuardedExpr gann' l' r'
      e2' <- addRef e2
      pure $ MultiWayIf ann' es' e2'
    Regulative ann r -> attachRef expr ann >>= \ann' -> Regulative ann' <$> addRef r
    Consider ann e branches -> attachRef expr ann >>= \ann' -> do
      e' <- addRef e
      branches' <- traverse addRef branches
      pure $ Consider ann' e' branches'
    Record ann mParty cell val isOfficial mHence -> attachRef expr ann >>= \ann' -> do
      mParty' <- traverse addRef mParty
      cell' <- addRef cell
      val' <- addRef val
      mHence' <- traverse addRef mHence
      pure $ Record ann' mParty' cell' val' isOfficial mHence'
    ReadCell ann mParty isOfficial mode cell -> attachRef expr ann >>= \ann' -> do
      mParty' <- traverse addRef mParty
      cell' <- addRef cell
      pure $ ReadCell ann' mParty' isOfficial mode cell'
    Lit ann lit -> attachRef expr ann >>= \ann' -> pure (Lit ann' lit)
    Percent ann e -> attachRef expr ann >>= \ann' -> Percent ann' <$> addRef e
    List ann es -> attachRef expr ann >>= \ann' -> List ann' <$> traverse addRef es
    Where ann e lcl -> attachRef expr ann >>= \ann' -> do
      e' <- addRef e
      lcl' <- traverse addRef lcl
      pure $ Where ann' e' lcl'
    LetIn ann lcl e -> attachRef expr ann >>= \ann' -> do
      lcl' <- traverse addRef lcl
      e' <- addRef e
      pure $ LetIn ann' lcl' e'
    Event ann e -> attachRef expr ann >>= \ann' -> Event ann' <$> addRef e
    Fetch ann e -> attachRef expr ann >>= \ann' -> Fetch ann' <$> addRef e
    Env ann e -> attachRef expr ann >>= \ann' -> Env ann' <$> addRef e
    Post ann e1 e2 e3 -> attachRef expr ann >>= \ann' -> do
      e1' <- addRef e1
      e2' <- addRef e2
      e3' <- addRef e3
      pure $ Post ann' e1' e2' e3'
    Concat ann es -> attachRef expr ann >>= \ann' -> Concat ann' <$> traverse addRef es
    AsString ann e -> attachRef expr ann >>= \ann' -> AsString ann' <$> addRef e
    Breach ann mParty mReason -> attachRef expr ann >>= \ann' -> do
      mParty' <- traverse addRef mParty
      mReason' <- traverse addRef mReason
      pure $ Breach ann' mParty' mReason'
    Inert ann txt ctx -> attachRef expr ann >>= \ann' -> pure (Inert ann' txt ctx)
   where
    bin f ann e1 e2 = do
      ann' <- attachRef expr ann
      e1' <- addRef e1
      e2' <- addRef e2
      pure $ f ann' e1' e2'

instance (HasSrcRange n, HasRef n) => HasRef (Deonton n) where
  addRef (MkDeonton ann party event deadline followup lest) = do
    -- 'Deonton' has no 'HasSrcRange' handle of its own here; attach via children.
    party' <- addRef party
    event' <- addRef event
    deadline' <- traverse addRef deadline
    followup' <- traverse addRef followup
    lest' <- traverse addRef lest
    pure $ MkDeonton ann party' event' deadline' followup' lest'

instance (HasSrcRange n, HasRef n) => HasRef (RAction n) where
  addRef (MkAction ann modal rule provided) = do
    rule' <- addRef rule
    provided' <- traverse addRef provided
    pure $ MkAction ann modal rule' provided'

instance (HasSrcRange n, HasRef n) => HasRef (Branch n) where
  addRef a = case a of
    MkBranch bann (When wann pat) e -> do
      bann' <- attachRef a bann
      pat' <- addRef pat
      e' <- addRef e
      pure $ MkBranch bann' (When wann pat') e'
    MkBranch bann (Otherwise wann) e -> do
      bann' <- attachRef a bann
      e' <- addRef e
      pure $ MkBranch bann' (Otherwise wann) e'

instance (HasSrcRange n, HasRef n) => HasRef (Pattern n) where
  addRef a = case a of
    PatVar ann n -> attachRef a ann >>= \ann' -> PatVar ann' <$> addRef n
    PatApp ann n pats -> attachRef a ann >>= \ann' -> do
      n' <- addRef n
      pats' <- traverse addRef pats
      pure $ PatApp ann' n' pats'
    PatCons ann patHead patTail -> attachRef a ann >>= \ann' -> do
      patHead' <- addRef patHead
      patTail' <- addRef patTail
      pure $ PatCons ann' patHead' patTail'
    PatExpr ann e -> attachRef a ann >>= \ann' -> PatExpr ann' <$> addRef e
    PatLit ann lit -> attachRef a ann >>= \ann' -> pure (PatLit ann' lit)

instance (HasSrcRange n, HasRef n) => HasRef (NamedExpr n) where
  addRef a@(MkNamedExpr ann n e) = do
    ann' <- attachRef a ann
    n' <- addRef n
    e' <- addRef e
    pure $ MkNamedExpr ann' n' e'

instance (HasSrcRange n, HasRef n) => HasRef (LocalDecl n) where
  addRef a = case a of
    LocalDecide ann d -> attachRef a ann >>= \ann' -> LocalDecide ann' <$> addRef d
    LocalAssume ann d -> attachRef a ann >>= \ann' -> LocalAssume ann' <$> addRef d

-- ----------------------------------------------------------------------------
-- NlgA Definition
-- ----------------------------------------------------------------------------

-- | 'NlgA' provides a way to propagate location information from surrounding
-- computations:
--
-- @
--   left_neighbour <*> NlgA inner_span inner_m <*> right_neighbour
-- @
--
-- Here, the following holds:
--
-- * the 'left_neighbour' will only see Nlg comments until 'bufSpanStart' of 'inner_span'
-- * the 'right_neighbour' will only see Nlg comments after 'bufSpanEnd' of 'inner_span'
-- * the 'inner_m' will only see Nlg comments between its 'left_neighbour' and its 'right_neighbour'
--
-- In other words, every computation:
--
--  * delimits the surrounding computations
--  * is delimited by the surrounding computations
--
-- Therefore, a 'NlgA' computation must be always considered in the context in
-- which it is used.
--
-- This implementation is taken from GHC, as Haddock comments have similar semantics to
-- our 'Nlg' comments.
-- Thus, we include the GHC note explaining the implementation in more detail.
-- See Note [Adding Haddock comments to the syntax tree].
-- However, our implementation is currently much simpler.
data NlgA a = MkNlgA
  { range :: !(Maybe SrcSpan)
  -- ^ 'SrcSpan' of the processed AST element.
  --
  -- @
  -- Just b  <=> BufSpan occupied by the processed AST element.
  --             The surrounding computations will not look inside.
  -- @
  --
  -- @
  -- Nothing <=> No BufSpan (e.g. when the HdkA is constructed by 'pure' or 'liftHdkA').
  --             The surrounding computations are not delimited.
  -- @
  , computation :: !(NlgM a)
  -- ^ The stateful computation that looks up 'Nlg' comments and
  -- adds them to the resulting AST node.
  }
  deriving (Functor, Generic)
  deriving anyclass (SOP.Generic)

instance Applicative NlgA where
  MkNlgA l1 m1 <*> MkNlgA l2 m2 =
    MkNlgA
      (l1 <> l2)
      (delim1 m1 <*> delim2 m2)
   where
    -- Delimit the LHS by the location information from the RHS
    delim1 = inLocRange (locRangeTo (fmap (.start) l2))
    -- Delimit the RHS by the location information from the LHS
    delim2 = inLocRange (locRangeFrom (fmap (.end) l1))

  pure a =
    liftNlgA (pure a)

liftNlgA :: NlgM a -> NlgA a
liftNlgA = MkNlgA mempty

extendNlgA :: (HasSrcRange e) => e -> NlgA a -> NlgA a
extendNlgA l' (MkNlgA l m) = MkNlgA (l2 <> l) m
 where
  l2 = fromSrcRange <$> rangeOf l'

registerSrcSpanNlgA :: Maybe SrcSpan -> NlgA ()
registerSrcSpanNlgA l = MkNlgA l (pure ())

-- | Modify the action of a NlgA computation.
hoistNlgA :: (NlgM a -> NlgM b) -> NlgA a -> NlgA b
hoistNlgA f (MkNlgA l m) = MkNlgA l (f m)

registerNlgA :: (HasSrcRange a) => a -> NlgA ()
registerNlgA a = registerSrcSpanNlgA (fromSrcRange <$> rangeOf a)

-- ----------------------------------------------------------------------------
-- NlgM Definition
-- ----------------------------------------------------------------------------

-- | The state of 'NlgM' contains a list of pending 'Nlg' comments. We go
-- over the AST, looking up these comments using 'takeNlgComments' and removing
-- them from the state. Also, using a state means we never use the same
-- 'Nlg' twice.
--
-- See Note [Adding Haddock comments to the syntax tree].
newtype NlgM a = MkNlgM {runNlgM :: LocRange -> (State NlgS) a}
  deriving (Functor, Applicative, Monad, MonadState NlgS, MonadReader LocRange) via (ReaderT LocRange (State NlgS))

data NlgS = NlgS
  { nlgs :: ![NlgWithSpan]
    -- ^ Nlg annotations that haven't been assigned to a specific 'Name' or
    -- other abstract syntax node.
  , warnings :: [Warning]
    -- ^ Warnings uncovered while trying to attach 'Nlg' annotations
    -- to the ast.
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

-- | Represents a predicate on SrcPos:
--
-- @
--   UpperLocBound |   SrcPos -> Bool
--   --------------+-----------------
--   EndOfFile     |   const True
--   EndPos p      |   (<= p)
-- @
--
--  The semigroup instance corresponds to (&&).
--
--  We don't use the  SrcPos -> Bool  representation
--  as it would lead to redundant checks.
--
--  That is, instead of
--
-- @
--    (pos <= 40) && (pos <= 30) && (pos <= 20)
-- @
--
--  We'd rather only do the (<=20) check. So we reify the predicate to make
--  sure we only check for the most restrictive bound.
data UpperBound = EndOfFile | EndPos !SrcPos
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

data LowerBound = StartOfFile | StartPos !SrcPos
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

instance Semigroup UpperBound where
  EndOfFile <> l = l
  l <> EndOfFile = l
  EndPos l <> EndPos r = EndPos (min l r) -- See the docs for 'UpperBound'

instance Semigroup LowerBound where
  StartOfFile <> l = l
  l <> StartOfFile = l
  StartPos l <> StartPos r = StartPos (max l r) -- See the docs for 'UpperBound'.

upperBoundToSrcSpan :: UpperBound -> SrcPos
upperBoundToSrcSpan = \ case
  EndOfFile -> MkSrcPos maxBound maxBound
  EndPos p -> p

lowerBoundToSrcSpan :: LowerBound -> SrcPos
lowerBoundToSrcSpan = \ case
  -- No position is lower than 1.
  -- Don't use 'minBound' because it is ugly during debugging.
  StartOfFile -> MkSrcPos 1 1
  StartPos p -> p

instance Monoid LowerBound where
  mempty = StartOfFile

data LocRange = MkLocRange
  { rangeFrom :: LowerBound
  , rangeTo :: UpperBound
  -- , column :: !Int
  -- Required indentation. Unused right now.
  }
  deriving stock (Generic, Eq, Show)
  deriving anyclass (SOP.Generic)

-- | The location range from the specified position to the end of the file.
locRangeFrom :: Maybe SrcPos -> LocRange
locRangeFrom (Just l) = mempty{rangeFrom = StartPos l}
locRangeFrom Nothing = mempty

-- | The location range from the start of the file to the specified position.
locRangeTo :: Maybe SrcPos -> LocRange
locRangeTo (Just l) = mempty{rangeTo = EndPos l}
locRangeTo Nothing = mempty

instance Semigroup LocRange where
  MkLocRange f1 t1 <> MkLocRange f2 t2 =
    MkLocRange
      (f1 <> f2)
      (t1 <> t2)

instance Monoid LocRange where
  mempty = MkLocRange StartOfFile EndOfFile

prettyLocRange :: LocRange -> Text
prettyLocRange locRange =
  prettySrcPos start <> "-" <> prettySrcPos end
 where
  end = case locRange.rangeTo of
    EndOfFile -> MkSrcPos maxBound maxBound
    EndPos p -> p
  start = case locRange.rangeFrom of
    -- No position is lower than 1, don't use 'minBound'
    StartOfFile -> MkSrcPos 1 1
    StartPos p -> p

-- ----------------------------------------------------------------------------
-- Workers
-- ----------------------------------------------------------------------------

-- | Restrict the range in which a NlgM computation will look up comments:
--
--   inLocRange r1 $
--   inLocRange r2 $
--     takeNlgComments ...  -- Only takes comments in the (r1 <> r2) location range.
--
-- Note that it does not blindly override the range but tightens it using (<>).
-- At many use sites, you will see something along the lines of:
--
--   inLocRange (locRangeTo end_pos) $ ...
--
-- And 'locRangeTo' defines a location range from the start of the file to
-- 'end_pos'. This does not mean that we now search for every comment from the
-- start of the file, as this restriction will be combined with other
-- restrictions. Somewhere up the callstack we might have:
--
--   inLocRange (locRangeFrom start_pos) $ ...
--
-- The net result is that the location range is delimited by 'start_pos' on
-- one side and by 'end_pos' on the other side.
--
-- In 'NlgA', every (<*>) may restrict the location range of its
-- subcomputations.
inLocRange :: LocRange -> NlgM a -> NlgM a
inLocRange r (MkNlgM m) = MkNlgM $ \r' -> m (r <> r')

-- | Get all the 'Nlg' comments that are within
-- the range of 'LocRange'.
--
-- @
--   'takeNlgsInRange' locRange nlgs
-- @
--
-- The first component of the result are the 'nlgs' within the 'LocRange',
-- and the second component are the nlgs that aren't within the 'LocRange'.
takeNlgsInRange :: LocRange -> [NlgWithSpan] -> ([NlgWithSpan], [NlgWithSpan])
takeNlgsInRange locRange nlgs =
  partition
    (\nlg -> nlg.range `subRangeOf` desiredRange)
    nlgs
 where
  desiredRange = MkSrcSpan start end
  end = upperBoundToSrcSpan locRange.rangeTo
  start = lowerBoundToSrcSpan locRange.rangeFrom

-- | Monadic version of 'takeNlgsInRange'.
-- Takes the 'Nlg's that are currently in scope and removes
-- them from the internal state.
--
takeNlgComments :: NlgM [NlgWithSpan]
takeNlgComments = do
  s <- get
  locRange <- ask
  let
    (taken, rest) = takeNlgsInRange locRange s.nlgs
  put (s{nlgs = rest})
  pure taken

{- Note [Adding Haddock comments to the syntax tree]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
'addHaddock' traverses the AST in concrete syntax order, building a computation
(represented by HdkA) that reconstructs the AST but with Haddock comments
inserted in appropriate positions:

  addHaddock :: HasHaddock a => a -> HdkA a

Consider this code example:

  f :: Int  -- ^ comment on argument
    -> Bool -- ^ comment on result

In the AST, the "Int" part of this snippet is represented like this
(pseudo-code):

  L (BufSpan 6 8) (HsTyVar "Int") :: LHsType GhcPs

And the comments are represented like this (pseudo-code):

  L (BufSpan 11 35) (HdkCommentPrev "comment on argument")
  L (BufSpan 46 69) (HdkCommentPrev "comment on result")

So when we are traversing the AST and 'addHaddock' is applied to HsTyVar "Int",
how does it know to associate it with "comment on argument" but not with
"comment on result"?

The trick is to look in the space between syntactic elements. In the example above,
the location range in which we search for HdkCommentPrev is as follows:

  f :: Int████████████████████████
   ████Bool -- ^ comment on result

We search for comments after  HsTyVar "Int"  and until the next syntactic
element, in this case  HsTyVar "Bool".

Ignoring the "->" allows us to accommodate alternative coding styles:

  f :: Int ->   -- ^ comment on argument
       Bool     -- ^ comment on result

Sometimes we also need to take indentation information into account.
Compare the following examples:

    class C a where
      f :: a -> Int
      -- ^ comment on f

    class C a where
      f :: a -> Int
    -- ^ comment on C

Notice how "comment on f" and "comment on C" differ only by indentation level.

Therefore, in order to know the location range in which the comments are applicable
to a syntactic elements, we need three nuggets of information:
  1. lower bound on the BufPos of a comment
  2. upper bound on the BufPos of a comment
  3. minimum indentation level of a comment

This information is represented by the 'LocRange' type.

In order to propagate this information, we have the 'HdkA' applicative.
'HdkA' is defined as follows:

  data HdkA a = HdkA (Maybe BufSpan) (HdkM a)

The first field contains a 'BufSpan', which represents the location
span taken by a syntactic element:

  addHaddock (L bufSpan ...) = HdkA (Just bufSpan) ...

The second field, 'HdkM', is a stateful computation that looks up Haddock
comments in the specified location range:

  HdkM a ≈
       LocRange                  -- The allowed location range
    -> [PsLocated HdkComment]    -- Unallocated comments
    -> (a,                       -- AST with comments inserted into it
        [PsLocated HdkComment])  -- Leftover comments

The 'Applicative' instance for 'HdkA' is defined in such a way that the
location range of every computation is defined by its neighbours:

  addHaddock aaa <*> addHaddock bbb <*> addHaddock ccc

Here, the 'LocRange' passed to the 'HdkM' computation of  addHaddock bbb
is determined by the BufSpan recorded in  addHaddock aaa  and  addHaddock ccc.

This is why it's important to traverse the AST in the order of the concrete
syntax. In the example above we assume that  aaa, bbb, ccc  are ordered by location:

  * getBufSpan (getLoc aaa) < getBufSpan (getLoc bbb)
  * getBufSpan (getLoc bbb) < getBufSpan (getLoc ccc)

Violation of this assumption would lead to bugs, and care must be taken to
traverse the AST correctly. For example, when dealing with class declarations,
we have to use 'flattenBindsAndSigs' to traverse it in the correct order.
-}
