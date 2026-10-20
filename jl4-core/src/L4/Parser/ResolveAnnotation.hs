{-# LANGUAGE ApplicativeDo #-}

module L4.Parser.ResolveAnnotation (
  -- * main function
  HasNlg(..),
  addNlgCommentsToAst,
  HasDesc(..),
  addDescCommentsToAst,
  pickDesc,
  HasRef(..),
  addRefCommentsToAst,
  TrailingRefs,
  trailingRefsOf,
  refWarningMessage,
  refUnattachedMessage,
  refTrailingMessage,
  refNoLocationMessage,
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
  splitNlgsInRange,
)
where

import Base

import Data.Char (isSpace)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Generics.SOP as SOP
import L4.Annotation
import L4.Lexer (AnnoType (..), LangTag, PosToken (..), TAnnotations (..), TokenType (..), displayTokenType)
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
  | EmptyNlg Name NlgWithSpan
    -- ^ An @\@nlg@ with no prose in it. Dropped rather than attached: a
    -- rendering REPLACES the thing it annotates, so an empty one erases the
    -- name from the output instead of leaving it alone.
  | Ambiguous Name (Maybe LangTag) [NlgWithSpan]
    -- ^ Two or more annotations on one name IN THE SAME LANGUAGE (the tag, or
    -- 'Nothing' for untagged). Must be at least two. Annotations in other
    -- languages on the same name are unaffected and still attach.
  | LangOverridden (WithSpan LangTag) (WithSpan LangTag)
    -- ^ A @\@lang@ line that names a different language from the LAST @\@lang@
    -- line in the module, which is the one in force. The first is the
    -- overridden line and the second is the line that wins. One per
    -- overridden line; a line that repeats the winning tag contradicts
    -- nothing and is not reported.
  | LoneLangTag Name NlgWithSpan (Maybe LangTag)
    -- ^ A wording tagged with a language that nothing else in the module
    -- backs: the name has no other wording, no other wording in the module
    -- carries the tag, and no @\@lang@ line declares it. A tag exists to tell
    -- renderings of one name apart, so this is the shape of a sentence whose
    -- first word was joined to the colon (@\@nlg:the employee pays@). 'en' and
    -- 'he' are exempt, and so is any tag whose part before the first hyphen is
    -- one of them (@en-GB@), which is taken to be a language and not the first
    -- word of a sentence; so a hyphenated word such as @en-route@ is exempt
    -- too. The wording is attached all the same. The last
    -- field is the module's language, when it differs from this tag only in
    -- case: tags are compared exactly, so @FR@ is not @fr@.
  | SpacedSlot (WithSpan Text) Text
    -- ^ A percent pair with spaces inside it around one name, such as
    -- @% amount %@, in an annotation. It prints as plain text, because a slot
    -- is @%amount%@ with no spaces. The first is the pair as written, with the
    -- range of the whole annotation; the second is the name between the signs.
  | RefUnattached RefWithSpan
    -- ^ A @ref has no AST node after it to attach to: it comes after the last
    -- one, at the end of the file.
  | RefTrailing RefWithSpan (Maybe Text)
    -- ^ A @ref follows code on its line, with nothing after it there. A @ref
    -- refers to what FOLLOWS it, so it cannot cite the code it trails, and it
    -- is attached to nothing rather than to the next construct (ruled
    -- 2026-10-12). The text is that code, when there is some on the line to
    -- quote.
  | RefNoLocation Ref
    -- ^ A @ref had no source location. That's a bug.
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
addNlgCommentsToAst :: HasNlg a => LangTag -> Map.Map LangTag (Maybe LangTag) -> [Nlg] -> a -> (a, NlgS)
addNlgCommentsToAst moduleLang loneTags nlgs p = do
  let
    (nlgWithSpan, unfindable) = preprocessNlgs nlgs

    initialNlgS = NlgS
      { moduleLang = moduleLang
      , loneTags = loneTags
      , nlgs = nlgWithSpan
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

  -- | The ordinary claim, narrowed to the annotations that satisfy a
  -- predicate; the rest stay for a later node. This is how a name claims a
  -- region that is not one contiguous range — see 'addNlgFieldName' and
  -- 'addNlgInput'.
  --
  -- Defaults to the ordinary claim, so only the 'Name' instance has to care.
  addNlgWhere :: (NlgWithSpan -> Bool) -> a -> NlgA a
  addNlgWhere _ = addNlg

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
      tySig' <- signatureBeforeKeyword ann (addNlg tySig)
      appFormAka' <- addNlg appFormAka
      tyDecl' <- addNlgTypeDecl (maybe (const True) indentedPast (fromSrcRange <$> rangeOf a)) tyDecl
      pure $ MkDeclare ann tySig' appFormAka' tyDecl'

instance (HasSrcRange n, HasNlg n) => HasNlg (Decide n) where
  addNlg a = extendNlgA a $ case a of
    MkDecide ann tySig appFormAka expr -> do
      tySig' <- signatureBeforeKeyword ann (addNlg tySig)
      appFormAka' <- case view annPmMatrix ann of
        -- A group's head is its first clause's, and its inputs are the
        -- GIVEN's, located up in the signature ('L4.Parser.givenInputBinding'),
        -- so the head's own region ends before it starts. Claim an @nlg
        -- written directly above the first clause in the head form's region
        -- instead, which a plain definition's head reaches by itself.
        Just _ -> hoistNlgA (>>= claimFirstClauseNlgs) (addNlg appFormAka)
        Nothing -> addNlg appFormAka
      -- Inside the body's region, which runs from the first clause's body to
      -- the last's, so that an annotation between two clauses is in reach.
      -- The ones between two clauses are claimed first, before a name of the
      -- clause below (a pattern, say) can take the one written above it.
      (expr', ann') <- hoistNlgA (\ m -> do
        ann'' <- claimLaterClauseNlgs ann
        e <- m
        pure (e, ann'')) (addNlg expr)
      pure $ MkDecide ann' tySig' appFormAka' expr'

-- | A group's @\@nlg@ written directly above its first clause belongs to the
-- group's head, as it would to a plain definition's: the head takes what is
-- left in the head form's region, which is where a plain definition's head
-- finds it. Its own region took nothing, being cut short by the inputs.
claimFirstClauseNlgs :: HasNlg n => AppForm n -> NlgM (AppForm n)
claimFirstClauseNlgs (MkAppForm aann hd ns maka) = do
  hd' <- case addNlg hd of MkNlgA _ m -> m
  pure (MkAppForm aann hd' ns maka)

-- | Is this the @LET@ that a group of clauses is lowered to, binding the clauses
-- after the first ('L4.Parser.bindFallthrough')? Its declaration holds the
-- LATER clauses and its body the first, so the usual descent, declarations
-- before body, would visit the clauses last to first, against the order the
-- regions between neighbouring nodes are taken in. The descent into this
-- @LET@ takes its body first.
bindsLaterClauses :: [LocalDecl n] -> Bool
bindsLaterClauses = any \ case
  LocalDecide _ (MkDecide dann _ _ _) -> isJust (view annPmSynthetic dann)
  LocalAssume{} -> False

-- | In a group of clauses, an @\@nlg@ written above a later clause belongs to
-- that clause's head ('PmMatrixClause' @clauseHead@). A run of bare names may
-- be overloads, each with its own annotations
-- ('L4.TypeCheck.separateOverloads'); a group that stays a group warns about
-- each ('PmMatrixClause' @clauseNlgs@, 'L4.TypeCheck.checkClauseMatrix').
-- Nothing else in the group's tree is a node it could attach to.
claimLaterClauseNlgs :: Anno -> NlgM Anno
claimLaterClauseNlgs ann = case view annPmMatrix ann of
  Just m | length m.clauses >= 2 -> do
    later <- for (zip m.clauses (drop 1 m.clauses)) \ (prev, cl) ->
      case betweenClauses prev cl of
        Just between -> do
          nlgs <- takeNlgCommentsWhere between
          -- As 'HasNlg Name' attaches them: per language.
          hdAnn <- attachNlgsByLanguage cl.clauseHead (getAnno cl.clauseHead) nlgs
          pure (MkPmMatrixClause cl.headRange cl.patterns (setAnno hdAnn cl.clauseHead) cl.clauseAka cl.clauseDescs (map (.payload) nlgs) cl.bodyRange)
        Nothing -> pure cl
    pure (setPmMatrix (MkPmMatrix m.scrutinees m.synthesizedScrutinees (take 1 m.clauses <> later) m.catchAll) ann)
  _ -> pure ann

-- | Is this annotation written between two clauses: on a line after the one
-- where the clause above ends, its body and the definitions of a @WHERE@ in
-- it included, and ending before the head of this one? Nothing inside the
-- clause above is between the two, whatever its indentation, and nothing
-- written after the clause above is inside it, whatever its indentation. One
-- written on the line where the clause above ends, after its body
-- (@DECIDE f n IS n + 1 \@export ...@), stays with that clause, as it does
-- after a rule written as one definition.
--
-- Nothing if either clause has no range to measure by.
betweenClauses :: PmMatrixClause -> PmMatrixClause -> Maybe (WithSpan a -> Bool)
betweenClauses prev cl = do
  h <- cl.headRange
  prevEnd <- (.end) . fromSrcRange <$> maybe prev.headRange Just prev.bodyRange
  let hs = (fromSrcRange h).start
  pure \ w ->
    let we = w.range.end
    in w.range.start.line > prevEnd.line
         && (we.line < hs.line || (we.line == hs.line && we.column <= hs.column))

instance (HasSrcRange n, HasNlg n) => HasNlg (Assume n) where
  addNlg a = extendNlgA a $ case a of
    -- An ASSUME is one declaration, so an annotation on a line of its own
    -- BELOW it is the next declaration's, as it is below a DECIDE. The test is
    -- the one the last input of a GIVEN list and the last field of a record
    -- have: what is indented past the declaration's start describes the
    -- ASSUME. Nothing after the head is traversed, so without this the head
    -- reaches down to the next declaration.
    MkAssume ann tySig appFormAka order -> do
      tySig' <- signatureBeforeKeyword ann (addNlg tySig)
      appFormAka' <- addNlgAppFormWhere claims appFormAka
      pure $ MkAssume ann tySig' appFormAka' order
     where
      headEnds = [ (fromSrcRange r).end | Just r <- [rangeOf appFormAka, order >>= rangeOf] ]
      belowHead w = not (null headEnds) && all (\ e -> w.range.start.line > e.line) headEnds
      claims w
        | belowHead w = maybe True (\ s -> indentedPast s w) (fromSrcRange <$> rangeOf a)
        | otherwise   = True

-- | An application form whose names claim what @p@ accepts. The head of an
-- ASSUME is the last thing in it that can reach down the file.
addNlgAppFormWhere ::
  (HasSrcRange n, HasNlg n) =>
  (NlgWithSpan -> Bool) -> AppForm n -> NlgA (AppForm n)
addNlgAppFormWhere p a = extendNlgA a $ case a of
  MkAppForm ann n ns maka -> do
    n' <- addNlgWhere p n
    ns' <- traverse (addNlgWhere p) ns
    maka' <- traverse addAka maka
    pure $ MkAppForm ann n' ns' maka'
 where
  addAka k = extendNlgA k $ case k of
    MkAka ann ns -> do
      ns' <- traverse (addNlgWhere p) ns
      pure $ MkAka ann ns'

-- | Cut a declaration's signature off where the declaration's own keyword
-- starts: the DECIDE of @GIVEN … DECIDE `r` IF …@, and likewise ASSUME,
-- DECLARE and a lambda's YIELD. The keyword is a token of the declaration,
-- not a node with a span, so nothing else stops a GIVEN list's last input —
-- which reaches down to the next node ('addNlgInput') — from reaching past a
-- keyword written on a line of its own to an annotation under it.
--
-- The signature is the declaration's first hole, so its keyword is the first
-- token after it. In a @`r` MEANS …@ rule that token is MEANS, which comes
-- after the head, so it bounds nothing the head does not already.
signatureBeforeKeyword :: Anno -> NlgA a -> NlgA a
signatureBeforeKeyword ann =
  hoistNlgA (inLocRange (locRangeTo (listToMaybe keywords)))
 where
  keywords = [ r.start | AnnoCsn (Just r) _ <- drop 1 ann.payload ]

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
  addNlg = addNlgTypeDecl (const True)

-- | A type declaration, given what the LAST field of its field list may take
-- from a later line. 'Declare' passes the column test; see 'addNlgFields'.
addNlgTypeDecl ::
  (HasSrcRange n, HasNlg n) =>
  (NlgWithSpan -> Bool) -> TypeDecl n -> NlgA (TypeDecl n)
addNlgTypeDecl claimsBelow a = extendNlgA a $ case a of
    RecordDecl ann mcon typedNames -> do
      typedNames' <- addNlgFields claimsBelow typedNames
      pure $ RecordDecl ann mcon typedNames'
    EnumDecl ann conDecls
      | Just (cons, lastCon) <- List.unsnoc conDecls -> do
          cons' <- traverse addNlg cons
          lastCon' <- addNlgConDecl claimsBelow lastCon
          pure $ EnumDecl ann (cons' <> [lastCon'])
      | otherwise ->
          pure $ EnumDecl ann conDecls
    SynonymDecl ann ty -> do
      ty' <- addNlg ty
      pure $ SynonymDecl ann ty'

-- | A field list. Every field but the last is bounded by the field after it;
-- the last is bounded only by whatever follows the declaration, so it takes
-- from a later line only what @claimsBelow@ accepts.
--
-- __The last field takes only an annotation indented past the declaration's
-- keyword__, the column test the last input of a GIVEN list has. An annotation
-- at the keyword's column or left of it is the NEXT declaration's herald, as
-- it is anywhere else in a file:
--
-- @
-- DECLARE Rec HAS
--     base IS A NUMBER
--
-- \@nlg the answer           -- the rule's, not @base@'s
-- DECIDE `answer` IS 42
-- @
--
-- The test is the declaration's, so it applies to the last field of the last
-- constructor of an enum too. A herald indented past the keyword is the last
-- field's wherever it is.
addNlgFields ::
  (HasSrcRange n, HasNlg n) =>
  (NlgWithSpan -> Bool) -> [TypedName n] -> NlgA [TypedName n]
addNlgFields claimsBelow typedNames = case List.unsnoc typedNames of
  Just (fields, lastField) -> do
    fields' <- traverse addNlg fields
    lastField' <- addNlgTypedName claimsBelow lastField
    pure (fields' <> [lastField'])
  Nothing -> pure []

-- | Run a computation but advertise NO span for it, so a sibling's range is
-- not cut short by it.
--
-- 'extendNlgA' inside each instance advertises the node's own span, which is
-- what delimits its neighbours. A record field's NAME has to be able to reach
-- PAST its type to the line below, so the type must stop advertising — while
-- still claiming, which is why this is not 'unclaimedSignatureType'.
unspanned :: NlgA a -> NlgA a
unspanned a = liftNlgA a.computation

-- | A type mentioned in a SIGNATURE claims no @\@nlg@ annotation and registers
-- no span, so the name it belongs to claims the whole binder instead.
--
-- __Why a type must not claim.__ @\@nlg@ attaches to the name it FOLLOWS, and
-- the range algebra in 'NlgA' cuts a name off at the start of its sibling\'s
-- span — so in @GIVEN a IS A STRING \@nlg the amount@ the annotation fell
-- outside @a@\'s range and inside the TYPE\'s, and @STRING@ took it. It then
-- rendered nowhere, with no diagnostic, because it HAD attached — to a node
-- nothing reads. The same cut put an @\@nlg@ written on its own line above a
-- @DECIDE@ onto the @GIVETH@ type rather than onto the rule.
--
-- Measured 2026-09-19 before the change: 11 of 116 annotations across ten
-- sampled corpus files sat on a builtin type name, and every annotation in
-- @ok\/nlg-percent.l4@ — the file whose whole job is to witness @\@nlg@ — was
-- dead for this reason, its @.nlg.golden@ showing bare names for all seven.
--
-- __Why claiming nothing is the right shape rather than reordering.__ A name
-- needs to claim on BOTH sides of its type: @GIVEN a [the amount] IS A NUMBER@
-- puts the annotation before the type and @GIVEN a IS A NUMBER \@nlg …@ after
-- it. Those are not one contiguous range, so no ordering of the two siblings
-- can capture both. Dropping the type\'s span removes the cut entirely and the
-- name\'s range covers the whole binder.
--
-- What is given up is annotating a type REFERENCE in a signature, which was
-- never meaningful: it is a use of a global type, so the annotation could only
-- ever describe that one occurrence. Annotating a type DECLARATION still works
-- — that is 'Declare'\'s 'AppForm' head, untouched here.
unclaimedSignatureType :: t -> NlgA t
unclaimedSignatureType = pure

instance (HasSrcRange n, HasNlg n) => HasNlg (TypedName n) where
  addNlg = addNlgTypedName (const True)

-- | One field of a record or constructor, given what its name may take from a
-- later line ('addNlgFields').
addNlgTypedName ::
  (HasSrcRange n, HasNlg n) =>
  (NlgWithSpan -> Bool) -> TypedName n -> NlgA (TypedName n)
addNlgTypedName claimsBelow a = extendNlgA a $ case a of
    -- A RECORD FIELD splits its two lines between the two claimants (ruled
    -- 2026-09-19, Meng). An annotation written UNDERNEATH a field describes
    -- that field:
    --
    -- @
    -- HAS `full name`  IS A STRING
    --     -- describes `full name`
    --     \@nlg the employee's full name
    --     `start date` IS A DATE
    -- @
    --
    -- so the field's NAME claims below-the-line annotations, and to reach
    -- past its own type it needs the type to stop advertising a span —
    -- hence 'unspanned'. The type still CLAIMS, and it runs second, so it
    -- picks up whatever is left on the field's own line. That is what keeps
    -- @ok/nlg_declare1.l4@ working: @head [Get First Element] IS AN a
    -- [Start Element]@ glosses the field and the type parameter separately
    -- and on purpose, both TRAILING, and letting the name take the whole
    -- line would make them collide and lose both.
    --
    -- This is one of the two exceptions to "own line describes what
    -- follows"; the other is a GIVEN list ('addNlgInput'). A field list is a
    -- column of things rather than a sequence of declarations, and all three
    -- independently generated Hebrew encodings measured in 2026-09 annotate
    -- fields this way — 100 heralds, every one below its field.
    MkTypedName ann n ty mExpr -> do
      n' <- addNlgFieldName claimsBelow (fromSrcRange <$> rangeOf ty) n
      -- The type claims what is left on the field's own line, and no further:
      -- it runs second, so with nothing after it, a type that reached down
      -- would take the herald the last field's name has just declined
      -- ('addNlgFields'), and nothing reads an annotation on a type.
      ty' <- unspanned (maybe id (hoistNlgA . inLocRange . upToEndOfLineOf) (rangeOf ty) (addNlg ty))
      pure $ MkTypedName ann n' ty' mExpr

instance (HasSrcRange n, HasNlg n) => HasNlg (ConDecl n) where
  addNlg = addNlgConDecl (const True)

addNlgConDecl ::
  (HasSrcRange n, HasNlg n) =>
  (NlgWithSpan -> Bool) -> ConDecl n -> NlgA (ConDecl n)
addNlgConDecl claimsBelow a = extendNlgA a $ case a of
    MkConDecl ann n typedNames -> do
      n' <- addNlg n
      typedNames' <- addNlgFields claimsBelow typedNames
      pure $ MkConDecl ann n' typedNames'

instance (HasSrcRange n, HasNlg n) => HasNlg (TypeSig n) where
  addNlg a = extendNlgA a $ case a of
    MkTypeSig ann givenSig givethSig -> do
      givenSig' <- addNlg givenSig
      givethSig' <- traverse addNlg givethSig
      pure $ MkTypeSig ann givenSig' givethSig'

-- | Run a computation with its lookup range clamped to the node's own span,
-- extended to the END OF THE LINE the node finishes on.
--
-- __The line, not the span, and that boundary is the whole rule.__ An
-- annotation TRAILING a construct on the same line describes that construct;
-- an annotation starting a line of its own describes what FOLLOWS it, except
-- inside a field list or a GIVEN list, where it describes the item above
-- ('addNlgFieldName', 'addNlgInput'). Those are the two shapes authors
-- actually write:
--
-- @
-- -- trailing: describes `a`
-- GIVEN a IS A STRING \@nlg the amount
--
-- GIVETH A BOOLEAN
-- -- own line: describes the rule below
-- \@nlg 5% with %amount%
-- DECIDE `over threshold` IF …
-- @
--
-- Clamping to the span alone gets the second right and the first wrong — the
-- trailing annotation sits just past the span's end and attaches to nothing.
-- Clamping to the end of that line gets both.
--
-- __Why any clamp is needed.__ 'extendNlgA' only ADVERTISES a span to a node's
-- siblings; it does not restrict what the node's own children may look up, so
-- the last child of the last child reaches as far as the enclosing context
-- allows. That is how a @GIVEN@ parameter came to claim an annotation written
-- on its own line BELOW the whole signature, in a rule with no @GIVETH@ whose
-- span would have stopped it. The last input of a GIVEN list now takes such an
-- annotation only when it is indented past the keyword ('addNlgInput').
confineToEndOfLine :: HasSrcRange e => e -> NlgA a -> NlgA a
confineToEndOfLine e = hoistNlgA (inLocRange r)
 where
  r = case fromSrcRange <$> rangeOf e of
    Nothing    -> mempty
    Just span' ->
      locRangeFrom (Just span'.start)
        <> locRangeTo (Just (endOfLine span'.end))

-- | The lookup range that stops at the end of the line a node ends on.
upToEndOfLineOf :: SrcRange -> LocRange
upToEndOfLineOf r = locRangeTo (Just (endOfLine (fromSrcRange r).end))

-- | The last column of a line, expressed as the first column of the next.
-- Cheaper and more robust than asking how long the line actually is, and
-- the only annotations between the two are on the trailing line by
-- construction.
endOfLine :: SrcPos -> SrcPos
endOfLine pos = MkSrcPos {line = pos.line + 1, column = 1}

instance (HasSrcRange n, HasNlg n) => HasNlg (GivenSig n) where
  addNlg a = extendNlgA a $ case a of
    -- A GIVEN list is a column, like a record's field list, so an annotation
    -- on its own line UNDER an input describes that input — the last input
    -- included (ruled 2026-10-02, Meng):
    --
    -- @
    -- GIVEN floor  IS A NUMBER
    --       amount IS A NUMBER
    --       \@nlg the sum of money
    -- \@nlg the claim of %amount% is large
    -- DECIDE `is large` IF amount GREATER THAN floor
    -- @
    --
    -- The first annotation describes `amount`, the second the rule. An input
    -- before the last gets that for free: the input after it bounds its range.
    -- The last input is bounded only by whatever follows the list — the next
    -- node, or the declaration's own keyword ('signatureBeforeKeyword') — and
    -- with no GIVETH between them the slot under it is also the slot above the
    -- rule. So it takes only an annotation indented further than the GIVEN
    -- keyword, and one at the keyword's column or left of it describes what
    -- follows, as it always did. The keyword's column, not column 1, so a
    -- GIVEN indented under a section heading or a WHERE works the same way.
    --
    -- The range still starts at the keyword: an annotation written ABOVE the
    -- GIVEN is not the first input's to take.
    MkGivenSig ann tys
      | Just (inputs, lastInput) <- List.unsnoc tys
      , Just sigSpan <- fromSrcRange <$> rangeOf a ->
          hoistNlgA (inLocRange (locRangeFrom (Just sigSpan.start))) $ do
            inputs' <- traverse addNlg inputs
            lastInput' <- addNlgInput (indentedPast sigSpan) lastInput
            pure $ MkGivenSig ann (inputs' <> [lastInput'])
      | otherwise -> confineToEndOfLine a $ do
          tys' <- traverse addNlg tys
          pure $ MkGivenSig ann tys'

-- | Does this annotation start at a column further right than where @span'@
-- starts?
indentedPast :: SrcSpan -> NlgWithSpan -> Bool
indentedPast span' w = w.range.start.column > span'.start.column

instance (HasSrcRange n, HasNlg n) => HasNlg (OptionallyTypedName n) where
  addNlg = addNlgInput (const True)

-- | One input of a GIVEN list. Its name claims what is on the input's own
-- lines, plus whatever on a LATER line @claimsBelow@ accepts: everything,
-- for an input with another after it; only what is indented past the GIVEN
-- keyword, for the last (see the 'GivenSig' instance).
addNlgInput ::
  (HasSrcRange n, HasNlg n) =>
  (NlgWithSpan -> Bool) -> OptionallyTypedName n -> NlgA (OptionallyTypedName n)
addNlgInput claimsBelow o = extendNlgA o $ case o of
  MkOptionallyTypedName ann n mty -> do
    n' <- addNlgWhere claims n
    tys' <- traverse unclaimedSignatureType mty
    pure $ MkOptionallyTypedName ann n' tys'
   where
    claims w
      | startsBelow o w = claimsBelow w
      | otherwise       = True

instance (HasSrcRange n, HasNlg n) => HasNlg (GivethSig n) where
  addNlg a = extendNlgA a $ case a of
    MkGivethSig ann mty -> do
      -- A GIVETH type claims nothing either, which is what lets an @nlg
      -- written on its own line between GIVETH and DECIDE fall through to the
      -- rule's own name instead of landing on the return type.
      mty' <- unclaimedSignatureType mty
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
  addNlg = addNlgNameWhere (const True)
  addNlgWhere = addNlgNameWhere

-- | The claim a RECORD FIELD's name makes, given the span of its type.
--
-- Two disjoint regions, which is why it needs the type's span rather than
-- just a range: everything BEFORE the type (the field's own trailing
-- gloss, as always), plus everything on a LATER LINE than the field
-- (ruled 2026-09-19 — an annotation written underneath a field describes
-- that field), as far as @claimsBelow@ accepts: everything, for a field with
-- another after it, and for the last field only what 'addNlgFields' lets it
-- have. What falls between — trailing the type on the field's own line — is
-- left for the type, which runs next.
addNlgFieldName ::
  (HasSrcRange a, HasNlg a) =>
  (NlgWithSpan -> Bool) -> Maybe SrcSpan -> a -> NlgA a
addNlgFieldName claimsBelow mTySpan a =
  addNlgWhere (\ w -> startsBefore mTySpan w || (startsBelow a w && claimsBelow w)) a

-- | The shared body of both of 'Name'\'s claims.
addNlgNameWhere :: (NlgWithSpan -> Bool) -> Name -> NlgA Name
addNlgNameWhere p a = extendNlgA a $ case a of
  MkName ann raw
    -- A name with no location was made up by the desugarer (the CONSIDERs a
    -- group of clauses is lowered to are full of them). Having no range, its
    -- region is not bounded by its neighbours', so it would take every
    -- annotation up to the end of the file, among them the next rule's own.
    | Nothing <- rangeOf a -> pure a
    | otherwise -> do
        ann' <- liftNlgA (attachNlgsByLanguage a ann =<< takeNlgCommentsWhere p)
        pure $ MkName ann' raw

-- | Does this annotation begin on a line strictly below where @e@ ends?
startsBelow :: HasSrcRange e => e -> NlgWithSpan -> Bool
startsBelow e w = case fromSrcRange <$> rangeOf e of
  Nothing    -> False
  Just span' -> w.range.start.line > span'.end.line

-- | Does this annotation begin before the given span starts? A missing span
-- means "no type to be before", so nothing qualifies on that ground.
startsBefore :: Maybe SrcSpan -> NlgWithSpan -> Bool
startsBefore Nothing      _ = False
startsBefore (Just span') w = w.range.start < span'.start

-- | Attach the annotations in scope for one name, partitioned by the language
-- each one declares.
--
-- Before language tags, ANY two annotations on one name were an ambiguity and
-- neither was attached. That is right when both are renderings of the same
-- node in the same language, and it becomes wrong the moment one of them says
-- @\@nlg:he@ — because a bilingual document is exactly a document with two
-- renderings per name, so under the old rule every annotated name in one lost
-- both of them. The tag was recognised and then had nowhere to go.
--
-- So the collision is per-LANGUAGE rather than per-name:
--
--   * Two annotations with different tags both attach. One becomes the
--     default and the rest become 'annNlgAlts'.
--   * Two with the SAME tag — including two untagged ones, which is the only
--     shape that existed before — is still an ambiguity, still warns, and
--     still attaches neither. The warning now says which language.
--   * A collision in one language does not poison the others. Two @\@nlg:he@
--     and one @\@nlg:en@ leaves the English rendering attached, because
--     nothing about it is ambiguous.
--
-- __Which one is the default.__ The untagged annotation if there is one;
-- otherwise the first in source order. An untagged rendering is the one that
-- declined to name a language, so it is what a caller who did not name one
-- should get. The consequence that matters most is the backward-compatible
-- one: a name with exactly ONE annotation lands in the default slot whether
-- it is tagged or not, so every existing reader of 'annNlg' — all ~28 of
-- them, none of which knows tags exist — keeps working, and a monolingual
-- Hebrew document behaves exactly as it did before.
attachNlgsByLanguage :: Name -> Anno -> [NlgWithSpan] -> NlgM Anno
attachNlgsByLanguage a ann nlgs0 = do
  -- An annotation with no prose is dropped, and says so. 'L4.Nlg.lin' renders
  -- a node's annotation INSTEAD of the node, so attaching an empty one makes
  -- the name disappear from the output. Three of these sit in
  -- @ok/contract.l4@ — @`the buyer` IS A Person \@nlg@ with nothing after the
  -- herald — and they were invisible only because they used to land on the
  -- TYPE, where nothing reads them. Repairing the attachment moved them onto
  -- the parameters and blanked all three names, which is how the trap
  -- surfaced.
  let (empties, nlgs) = List.partition (nlgIsBlank . (.payload)) nlgs0
  for_ empties $ \ e -> addWarning $ EmptyNlg a e
  let
    grouped = groupByLanguage nlgs
    unique  = [ (tag, one) | (tag, [one]) <- grouped ]
  for_ grouped $ \ (tag, grp) ->
    case grp of
      (_ : _ : _) -> addWarning $ Ambiguous a tag grp
      _           -> pure ()
  lone <- use #loneTags
  case nlgs0 of
    [one]
      | Just tag <- nlgLangTag one.payload
      , Just caseTwin <- Map.lookup tag lone
      , not (nlgIsBlank one.payload) -> addWarning $ LoneLangTag a one caseTwin
    _ -> pure ()
  lang <- use #moduleLang
  pure $ case pickDefault lang unique of
    Nothing         -> ann
    Just (d, alts)  -> setNlgs d.payload (fmap (.payload) alts) ann

-- | Does this annotation carry any prose at all?
--
-- Whitespace-only counts as blank: @\@nlg@ followed by spaces is the same
-- mistake as @\@nlg@ followed by nothing.
nlgIsBlank :: Nlg -> Bool
nlgIsBlank = \ case
  MkInvalidNlg _        -> True
  MkParsedNlg _ _ frags -> all blankFragment frags
  MkResolvedNlg _ _ frags -> all blankFragment frags
 where
  blankFragment :: NlgFragment n -> Bool
  blankFragment = \ case
    MkNlgText _ t -> Text.all isSpace t
    MkNlgRef{}    -> False

-- | The annotations grouped by declared language: each group in source order,
-- and the groups in order of first appearance.
--
-- Sorted by source position explicitly rather than trusting the order they
-- arrive in. They reach here through two accumulators that each prepend
-- ('addNlg' into the parser state, then 'preprocessNlgs'), so the incoming
-- order is a property of how many times the list has been reversed — which is
-- not a thing to encode "first in source order" on top of.
groupByLanguage :: [NlgWithSpan] -> [(Maybe LangTag, [NlgWithSpan])]
groupByLanguage ns0 =
  [ (tag, filter ((== tag) . lang) ns) | tag <- tagsInOrder ]
 where
  ns = List.sortOn (.range) ns0
  lang = nlgLangTag . (.payload)
  tagsInOrder = List.foldl' (\ seen n -> if lang n `elem` seen then seen else seen <> [lang n]) [] ns

-- | Split the unambiguous renderings into the default one and the rest.
--
-- The default is the rendering in the MODULE's own language, and otherwise the
-- first in source order. Before @\@lang@ existed this read "the untagged one,
-- else the first", which is the same rule: an untagged annotation is stamped
-- with the module's language ('withDefaultLang') before it ever reaches here,
-- so "untagged" and "in the module's language" are now the same set. Saying it
-- this way is what makes @\@lang he@ behave as "tag every herald @:he@"
-- rather than as a separate mechanism with its own precedence.
pickDefault :: LangTag -> [(Maybe LangTag, NlgWithSpan)] -> Maybe (NlgWithSpan, [NlgWithSpan])
pickDefault lang xs = case break ((== Just lang) . fst) xs of
  (before, (_, native) : after) -> Just (native, fmap snd before <> fmap snd after)
  (_, []) -> case xs of
    []              -> Nothing
    ((_, d) : rest) -> Just (d, fmap snd rest)

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
      sig' <- signatureBeforeKeyword ann (addNlg sig)
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
    -- The LET a group of clauses is lowered to binds the clauses after the
    -- first, which are written after its body: source order is the body's.
    LetIn ann lcl e
      | bindsLaterClauses lcl -> do
          e' <- addNlg e
          lcl' <- traverse addNlg lcl
          pure $ LetIn ann lcl' e'
      | otherwise -> do
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
    ann0 <- attachLeadingDesc dec ann
    -- Then the descs above the later clauses of a group, before the body,
    -- whose generated bindings would otherwise claim them.
    ann' <- claimLaterClauseDescs ann0
    tySig' <- addDesc tySig
    app' <- addDesc appForm
    expr' <- addDesc expr
    dropUnclaimedWithinGroup dec ann'
    pure $ MkDecide ann' tySig' app' expr'

-- | A group of clauses claims no @\@desc@ or @\@export@ written inside its
-- own range that is not its own, a clause's ('claimLaterClauseDescs') or an
-- input's: in a @WHERE@ of a clause, say, or between the @GIVETH@ and the first
-- clause. This pass does not read the clauses' bodies (the descent into an
-- expression is 'pure'), so what is left would be the next top-level rule's,
-- which takes every @\@desc@ written before it ('descPrecedesNode'), and a
-- group published the rule after it under a description of its own. They are
-- dropped.
dropUnclaimedWithinGroup :: (HasSrcRange a) => a -> Anno -> State DescS ()
dropUnclaimedWithinGroup node ann =
  case (view annPmMatrix ann, nodeSpan node) of
    (Just _, Just span') ->
      void (takeMatchingDescs \ w -> span'.start <= w.range.start && w.range.end <= span'.end)
    _ -> pure ()

-- | In a group of clauses, the @\@desc@s and @\@export@s written between the
-- clause above and a later clause belong to that clause ('PmMatrixClause'
-- @clauseDescs@): a run of bare names may be overloads, each with its own
-- annotations ('L4.TypeCheck.separateOverloads'), and a group that stays a
-- group warns about each ('L4.TypeCheck.checkClauseMatrix'). Those above the
-- first clause's head are not taken here: they are the group's own, read as
-- a plain definition's are.
claimLaterClauseDescs :: Anno -> State DescS Anno
claimLaterClauseDescs ann = case view annPmMatrix ann of
  Just m | length m.clauses >= 2 -> do
    later <- for (zip m.clauses (drop 1 m.clauses)) \ (prev, cl) ->
      case betweenClauses prev cl of
        Just between -> do
          matches <- takeMatchingDescs between
          pure (MkPmMatrixClause cl.headRange cl.patterns cl.clauseHead cl.clauseAka (map (.payload) matches) cl.clauseNlgs cl.bodyRange)
        Nothing -> pure cl
    pure (setPmMatrix (MkPmMatrix m.scrutinees m.synthesizedScrutinees (take 1 m.clauses <> later) m.catchAll) ann)
  _ -> pure ann

instance HasDesc (Assume n) where
  addDesc asm@(MkAssume ann tySig appForm mType) = do
    ann' <- attachLeadingDesc asm ann
    tySig' <- addDesc tySig
    app' <- addDesc appForm
    mType' <- traverse addDesc mType
    pure $ MkAssume ann' tySig' app' mType'

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
  addDesc name@(MkOptionallyTypedName ann n mType) = do
    mType' <- traverse addDesc mType
    ann' <- attachLeadingOrInlineDesc name ann
    pure $ MkOptionallyTypedName ann' n mType'

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
  addDesc name@(MkTypedName ann n ty mExpr) = do
    ty' <- addDesc ty
    ann' <- attachLeadingOrInlineDesc name ann
    pure $ MkTypedName ann' n ty' mExpr

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

-- | 'pickLeadingDesc' for descs already taken, in source order: the one a
-- definition keeps when several are written above it.
pickDesc :: [Desc] -> Maybe Desc
pickDesc ds =
  case lastMaybe (filter descIsExportMarked ds) of
    Just d  -> Just d
    Nothing -> lastMaybe ds

-- | True if a Desc's text begins with the @export or @default keyword,
-- mirroring how 'L4.Export.parseDescText' consumes the leading tokens.
descIsExportMarked :: Desc -> Bool
descIsExportMarked d =
  let token = Text.toLower (Text.takeWhile (not . isSpace) (Text.stripStart (getDesc d)))
  in token == "export" || token == "default"

addDescWarning :: DescWarning -> State DescS ()
addDescWarning w = modify' $ \s -> s{descWarnings = w : s.descWarnings}

nodeSpan :: (HasSrcRange a) => a -> Maybe SrcSpan
nodeSpan = fmap fromSrcRange . rangeOf

descPrecedesNode :: SrcSpan -> DescWithSpan -> Bool
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

descInlineFor :: SrcSpan -> DescWithSpan -> Bool
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
-- Ref attachment scaffolding
-- ----------------------------------------------------------------------------

type RefWithSpan = WithSpan Ref

data RefWarning
  = RefMissingLocation Ref
    -- ^ A 'Ref' had no 'SrcRange', so we could not place it. That's a bug.
  | RefNotAttached RefWithSpan
    -- ^ A 'Ref' has no AST node after it. See 'RefUnattached'.
  | RefAfterCode RefWithSpan (Maybe Text)
    -- ^ A 'Ref' follows code on its line, and is attached to nothing. See
    -- 'RefTrailing'.
  deriving stock (Show, Eq, Generic)
  deriving anyclass (SOP.Generic)

data RefS = RefS
  { refs :: ![RefWithSpan]
    -- ^ Refs that have not yet been attached to an AST node, sorted by the
    -- position where they END. See 'takeMatchingRefs'.
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
  RefAfterCode r code  -> RefTrailing r code
  RefMissingLocation r -> RefNoLocation r

-- | The words for a warning about where a @ref sits; 'Nothing' for any other
-- warning. What @l4 check@, @l4 run@ and the IDE print, and what
-- @doc\/reference\/syntax\/README.md@ quotes: change the one, change the other.
refWarningMessage :: Warning -> Maybe Text
refWarningMessage = \ case
  RefUnattached r    -> Just (refUnattachedMessage r.payload)
  RefTrailing r code -> Just (refTrailingMessage r.payload code)
  RefNoLocation r    -> Just (refNoLocationMessage r)
  _                  -> Nothing

refUnattachedMessage :: Ref -> Text
refUnattachedMessage r =
  "This @ref" <> quotedCitation r <> " is at the end of the file, so there is nothing after it to attach to."

refTrailingMessage :: Ref -> Maybe Text -> Text
refTrailingMessage r code =
  "This @ref" <> quotedCitation r
    <> " follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above "
    <> maybe "the code it cites" (\c -> "`" <> c <> "`") code
    <> "."

refNoLocationMessage :: Ref -> Text
refNoLocationMessage r =
  "This @ref" <> quotedCitation r <> " has no source location. This might be an internal compiler error."

-- | @ (`the citation`)@, ready to follow \"This @ref\"; nothing for a @ref with no text.
quotedCitation :: Ref -> Text
quotedCitation r = case refCitation r of
  "" -> ""
  c  -> " (`" <> c <> "`)"

-- | Attach @ref annotations to the AST nodes that immediately follow them.
--
-- Unlike @nlg (which targets 'Name' nodes) or @desc (which targets top-level
-- declarations), a @ref can attach to /any/ AST node. The attachment rule is
-- \"the immediately following AST node, regardless of type\", and a node keeps
-- EVERY ref that precedes it, in source order: a stack of refs above a
-- definition is how the corpus writes several citations for one rule.
--
-- We rely on the fact that a pre-order traversal of a well-formed AST visits
-- nodes in non-decreasing start position. Therefore, the first node whose
-- start position is at or after a ref's end position is the immediately
-- following node, and it claims the ref. Refs are removed from the state as
-- soon as they are claimed, so each ref is used at most once.
--
-- Two warnings come out of this pass, both about a ref that cannot do what
-- its author meant, and a ref that draws one is attached to nothing. A ref
-- with nothing after it ('RefNotAttached') has no node to attach to. A ref
-- that follows code on its line ('RefAfterCode'; the 'TrailingRefs' say
-- which, because only the tokens know) is not offered to any node, and not to
-- the next construct either, which would make it that construct's citation;
-- the warning says to put it on the line above (ruled 2026-10-12: a @ref
-- written after code on its line attaches to nothing and warns).
--
-- Like 'addNlgCommentsToAst', we merely add structured data to the ast node's
-- respective 'Anno'; the exact-print annotations are left untouched.
addRefCommentsToAst :: HasRef a => TrailingRefs -> [Ref] -> a -> (a, RefS)
addRefCommentsToAst trailing refs0 ast =
  let
    (withSpan, missing) = preprocessRefs refs0
    isTrailing r = Map.member r.range.start trailing
    -- A ref that trails code is offered to no node, so it cannot be claimed.
    initialS =
      RefS
        { refs = List.sortOn (.range.end) (filter (not . isTrailing) withSpan)
        , refWarnings = []
        }
    (ast', s') = runState (addRef ast) initialS
    afterCode =
      [ (r.range.start, RefAfterCode r code)
      | r <- withSpan
      , Just code <- [Map.lookup r.range.start trailing]
      ]
    -- Any refs that were never claimed become warnings.
    leftovers = [ (r.range.start, RefNotAttached r) | r <- s'.refs ]
    -- In source order.
    placed = fmap snd (List.sortOn fst (afterCode <> leftovers))
  in
    (ast', s'{refs = [], refWarnings = fmap RefMissingLocation missing <> placed})

-- | The @ref tokens that follow code on their line and have nothing after
-- them there, each by where it starts, with the code before it (when there is
-- some to quote).
--
-- Only the token stream can say this: by the time a ref is a 'Ref' it has an
-- 'Anno' and a range and no memory of its neighbours. The line form, @\@ref
-- ...@, runs to the end of the line, so code before it is enough. The inline
-- form, @\<\<...\>\>@, can sit in the middle of an expression, where it binds to
-- the word after it and is right to; it is flagged only when no code follows
-- it on its line. (The ruling is about a ref \"written at the end of a code
-- line\"; a mid-line @\<\<...\>\>@ is outside it and keeps attaching to what
-- follows it.)
type TrailingRefs = Map SrcPos (Maybe Text)

-- | Where the scan for 'TrailingRefs' has got to.
data TrailScan = TrailScan
  { lastCodeLine :: !Int
    -- ^ The line the latest code token ENDED on; 0 before there is one. A
    -- multi-line token ends where code on that line begins to follow it.
  , lineStart    :: !Int
    -- ^ The line 'linePrefix' belongs to.
  , linePrefix   :: [Text]
    -- ^ What the tokens that START on 'lineStart' say, latest first.
  , awaiting     :: [(SrcPos, Maybe Text, Int)]
    -- ^ Inline refs that follow code, with the line they END on, until the
    -- next code token shows whether anything follows them there.
  , found        :: !TrailingRefs
  }

trailingRefsOf :: [PosToken] -> TrailingRefs
trailingRefsOf toks = finish (List.foldl' step start toks)
 where
  start = TrailScan 0 0 [] [] Map.empty

  finish st = List.foldl' (\m (pos, quoted, _) -> Map.insert pos quoted m) st.found st.awaiting

  -- Neither whitespace and comments nor annotations are code. A ref that
  -- follows another ref, or a comment, on a line of its own is on a line of
  -- its own.
  isCode tok = case tok.payload of
    TSpaces _      -> False
    TAnnotations _ -> False
    _              -> True

  step st tok =
    let
      begins = tok.range.start
      ends = tok.range.end
      -- A code token shows what follows each inline ref waiting on one: more
      -- code on the ref's own line, and it is mid-line; or none.
      resolved
        | isCode tok =
            st { awaiting = []
               , found = List.foldl' (\m (pos, quoted, endLine) ->
                           if begins.line == endLine then m else Map.insert pos quoted m)
                           st.found st.awaiting }
        | otherwise = st
      sameLine
        | begins.line == resolved.lineStart = resolved
        | otherwise = resolved { lineStart = begins.line, linePrefix = [] }
      beforeRef = Text.strip (Text.concat (reverse sameLine.linePrefix))
      codeBefore = if Text.null beforeRef then Nothing else Just beforeRef
      scanned = case tok.payload of
        TAnnotations (TRef _ ty) | sameLine.lastCodeLine == begins.line ->
          case ty of
            LineAnno   -> sameLine { found = Map.insert begins codeBefore sameLine.found }
            InlineAnno -> sameLine { awaiting = (begins, codeBefore, ends.line) : sameLine.awaiting }
        _ -> sameLine
    in
      scanned
        { linePrefix = displayTokenType tok.payload : scanned.linePrefix
        , lastCodeLine = if isCode tok then ends.line else scanned.lastCodeLine
        }

preprocessRefs :: [Ref] -> ([RefWithSpan], [Ref])
preprocessRefs = foldl' go ([], [])
 where
  go (located, missing) ref =
    case rangeOf ref of
      Nothing -> (located, ref : missing)
      Just r -> (WithSpan (fromSrcRange r) ref : located, missing)

-- | Remove and return every pending ref that precedes the node
-- ('refPrecedesNode'), still in the order they are kept.
--
-- A ref precedes a node exactly when it ENDS at or before the node's start,
-- and the pending refs are sorted by where they end. So for any node the refs
-- that precede it are a prefix of the list, and 'List.span' finds them by
-- looking at that prefix and one ref more. 'List.partition' looked at every
-- pending ref for every node, so a file with n refs cost n times its number
-- of nodes: 16,000 refs took 30 seconds to check, where the same 16,000
-- definitions without them took 2.
--
-- The list is sorted by end, not by start, so that this holds of any refs and
-- not only of the ones the lexer produces today. Sorted by start, a ref that
-- encloses another would end after it, fail the test, and hide the ref behind
-- it. No ref encloses another now, since each is one lexer token.
takeMatchingRefs :: SrcSpan -> State RefS [RefWithSpan]
takeMatchingRefs nodeRange = do
  s <- get
  let (matches, rest) = List.span (refPrecedesNode nodeRange) s.refs
  put s{refs = rest}
  pure matches

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

-- | Hold on the node's 'Anno' every pending ref that precedes the node, in
-- source order.
attachRef :: HasSrcRange a => a -> Anno -> State RefS Anno
attachRef node ann =
  case nodeSpan node of
    Nothing -> pure ann
    Just nodeRange -> do
      matches <- takeMatchingRefs nodeRange
      pure $ case List.sortOn (.range.start) matches of
        [] -> ann
        rs -> addRefs (fmap (.payload) rs) ann

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
    -- The local definition a group of clauses is lowered to holds the clauses
    -- after the first ('L4.Parser.bindFallthrough'). It is generated and
    -- marked, and its range, the next clause's body, is there to key the
    -- checker. It claims no ref: a ref above that clause is the first node
    -- written in it, which the descent below reaches.
    ann' <- if isJust (view annPmSynthetic ann) then pure ann else attachRef d ann
    tySig' <- addRef tySig
    appForm' <- addRef appForm
    expr' <- addRef expr
    pure $ MkDecide ann' tySig' appForm' expr'

instance (HasSrcRange n, HasRef n) => HasRef (Assume n) where
  addRef a@(MkAssume ann tySig appForm order) = do
    ann' <- attachRef a ann
    tySig' <- addRef tySig
    appForm' <- addRef appForm
    order' <- traverse addRef order
    pure $ MkAssume ann' tySig' appForm' order'

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
  addRef a@(MkTypedName ann n ty mExpr) = do
    ann' <- attachRef a ann
    n' <- addRef n
    ty' <- addRef ty
    mExpr' <- traverse addRef mExpr
    pure $ MkTypedName ann' n' ty' mExpr'

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
  addRef a@(MkOptionallyTypedName ann n mty) = do
    ann' <- attachRef a ann
    n' <- addRef n
    mty' <- traverse addRef mty
    pure $ MkOptionallyTypedName ann' n' mty'

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
    App ann n ns -> do
      -- The range of an infix (mixfix) call is its keyword and no more, so an
      -- operand to the LEFT of the keyword starts before the call does. The
      -- call is where its first left operand begins, so it claims the refs
      -- that precede that operand first. The operands then come before the
      -- call in the walk, so that a ref inside one is claimed by the node it
      -- precedes and not by the whole call.
      let operandStartsBefore a = case (nodeSpan a, nodeSpan expr) of
            (Just sa, Just se) -> sa.start < se.start
            _                  -> False
          (leftOperands, rest) = span operandStartsBefore ns
      annAbove <- case leftOperands of
        []      -> pure ann
        l : _   -> attachRef l ann
      leftOperands' <- traverse addRef leftOperands
      ann' <- attachRef expr annAbove
      n' <- addRef n
      rest' <- traverse addRef rest
      pure $ App ann' n' (leftOperands' <> rest')
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
    Lit ann lit -> attachRef expr ann >>= \ann' -> pure (Lit ann' lit)
    Percent ann e -> attachRef expr ann >>= \ann' -> Percent ann' <$> addRef e
    List ann es -> attachRef expr ann >>= \ann' -> List ann' <$> traverse addRef es
    Where ann e lcl -> attachRef expr ann >>= \ann' -> do
      e' <- addRef e
      lcl' <- traverse addRef lcl
      pure $ Where ann' e' lcl'
    -- The LET a group of clauses is lowered to binds the clauses after the
    -- first, which are written after its body: source order is the body's
    -- ('bindsLaterClauses'). Taken in the other order, the later clauses claim
    -- the refs written inside the first.
    LetIn ann lcl e -> attachRef expr ann >>= \ann' ->
      if bindsLaterClauses lcl
        then do
          e' <- addRef e
          lcl' <- traverse addRef lcl
          pure $ LetIn ann' lcl' e'
        else do
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
    -- The 'Regulative' expression that holds a 'Deonton' (Syntax.hs) starts
    -- where it does and has already taken the refs before it; recurse into
    -- the parts.
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
-- over the AST, looking up these comments using 'takeNlgCommentsWhere' and removing
-- them from the state. Also, using a state means we never use the same
-- 'Nlg' twice.
--
-- See Note [Adding Haddock comments to the syntax tree].
newtype NlgM a = MkNlgM {runNlgM :: LocRange -> (State NlgS) a}
  deriving (Functor, Applicative, Monad, MonadState NlgS, MonadReader LocRange) via (ReaderT LocRange (State NlgS))

data NlgS = NlgS
  { moduleLang :: !LangTag
    -- ^ The module's declared @\@lang@, or 'defaultModuleLang'. Read by
    -- 'pickDefault' to decide which of several renderings is the one a caller
    -- who named no language should get.
  , loneTags :: !(Map.Map LangTag (Maybe LangTag))
    -- ^ The language tags that nothing else in the module backs: no @\@lang@
    -- line declares them and no other wording carries them. A name whose only
    -- wording carries one of these draws a 'LoneLangTag'. Each maps to the
    -- module's language when that differs from it only in case.
  , nlgs :: ![NlgWithSpan]
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
--     takeNlgCommentsWhere ...  -- Only takes comments in the (r1 <> r2) location range.
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

-- | Split the 'Nlg' comments for one node.
--
-- @
--   'splitNlgsInRange' locRange p nlgs
-- @
--
-- The first component of the result are the 'nlgs' that are within the
-- 'LocRange' and satisfy @p@, in the order they came. The second component is
-- what stays for a later node to claim: first the ones within the 'LocRange'
-- that @p@ declined, then the ones outside it, each group in the order it came.
--
-- One strict pass, and the tail of the list after the last annotation in range
-- is shared with the input rather than copied. A module with thousands of
-- annotations asks this once per name, so what a call allocates is what sets
-- how much the garbage collector has to copy.
splitNlgsInRange ::
  LocRange -> (NlgWithSpan -> Bool) -> [NlgWithSpan] -> ([NlgWithSpan], [NlgWithSpan])
splitNlgsInRange locRange p nlgs0 = go [] [] [] 0 nlgs0 nlgs0
 where
  desiredRange = MkSrcSpan start end
  end = upperBoundToSrcSpan locRange.rangeTo
  start = lowerBoundToSrcSpan locRange.rangeFrom
  within nlg = nlg.range `subRangeOf` desiredRange

  -- @taken@ and @declined@ are the ones in range so far, newest first.
  -- @before@ is the ones out of range that precede the last one in range,
  -- newest first, and @skipped@ counts the out-of-range ones after it, which
  -- are the front of @shared@: the input from just after the last one in range.
  go !taken !declined !before !skipped shared = \ case
    [] -> (reverse taken, reverse declined <> (reverse before <> shared))
    n : ns
      | within n ->
          let before' = reverse (List.take skipped shared) <> before
          in if p n
               then go (n : taken) declined before' 0 ns ns
               else go taken (n : declined) before' 0 ns ns
      | otherwise -> go taken declined before (skipped + 1) shared ns

-- | Take the 'Nlg' comments that are within the range of the current
-- 'LocRange' and satisfy @p@, and remove them from the internal state. The
-- rest stay in the state for a later node to claim.
takeNlgCommentsWhere :: (NlgWithSpan -> Bool) -> NlgM [NlgWithSpan]
takeNlgCommentsWhere p = do
  s <- get
  locRange <- ask
  let (taken, rest) = splitNlgsInRange locRange p s.nlgs
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
