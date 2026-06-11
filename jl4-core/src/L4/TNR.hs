-- | TNR ("Times New Roman") rendering: generate legislative-style prose
-- from an L4 module.
--
-- This is Phase 1 of @specs/todo/NLG-TNR-ROUNDTRIP-SPEC.md@: a module-level
-- document renderer producing Markdown in conventional drafting house style
-- (Coode tabulation: conditions as lettered paragraphs ending \"; and\" /
-- \"; or\", nested disjunctions one tabulation level down).
--
-- Every rendered block carries a hidden anchor comment tying it back to the
-- L4 node it came from; anchors are the identity used by the round-trip
-- ingestion path (spec §3.2), and are keyed on declaration kind + name, never
-- on line or section numbers.
--
-- Design constraints (spec §2.5 — faithfulness):
--
--   * prose for connectives comes only from the fixed house-style table
--     below and from author annotations (@nlg/@desc); we never paraphrase.
--   * #EVAL/#CHECK directives are tests, not law: suppressed (counted in
--     the trailing coverage comment).
--   * bare BOOLEAN ASSUMEs are atoms that appear inline inside provisions;
--     they get no separate definition entry (counted as \"inlined\").
module L4.TNR (
  TnrOptions (..),
  defaultTnrOptions,
  renderModuleTnr,
) where

import Base
import qualified Base.Text as Text

import L4.Annotation
import L4.Desugar (carameliseNode)
import L4.Lexer (PosToken)
import L4.Nlg (LinToken (..), LinTree (..), LinType (..), Linearize (..), lin)
import L4.Syntax
import Optics

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data TnrOptions = MkTnrOptions
  { anchors :: Bool
  -- ^ emit hidden @\<!-- l4: ... --\>@ anchor comments (round-trip identity)
  }

defaultTnrOptions :: TnrOptions
defaultTnrOptions = MkTnrOptions{anchors = True}

----------------------------------------------------------------------------
-- Document IR (spec §2.3)
----------------------------------------------------------------------------

-- | Coode tabulation tree: either a leaf clause or a group of clauses
-- joined by a single conjunction, optionally with an explicit lead-in
-- (\"none of the following applies—\").
data Tab
  = TLeaf Text
  | TGroup (Maybe Text) Conj [Tab]

data Conj = CAnd | COr

data Block
  = DocHeading Int Text
  | DocProvision
      { anchor :: Text
      , marginalNote :: Maybe Text -- ^ from @desc on the declaration
      , number :: Int
      , leadIn :: Text
      , tabulation :: Maybe Tab
      , trailing :: [Text] -- ^ extra paragraphs (e.g. WHERE-clause definitions)
      }

-- | Counters threaded through the walk; surfaced in the coverage comment.
data Acc = MkAcc
  { provisionNum :: Int
  , inlinedAtoms :: Int
  , suppressedDirectives :: Int
  }

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

renderModuleTnr :: TnrOptions -> Module Resolved -> Text
renderModuleTnr opts (MkModule _ _ topSection) =
  let
    (acc, docs) = sectionDocs 1 (MkAcc 1 0 0) topSection
    body = Text.intercalate "\n\n" (concatMap (renderDoc opts) docs)
    coverage =
      "<!-- tnr-coverage: "
        <> Text.pack (show (acc.provisionNum - 1))
        <> " provisions; "
        <> Text.pack (show acc.inlinedAtoms)
        <> " boolean atoms inlined; "
        <> Text.pack (show acc.suppressedDirectives)
        <> " directives suppressed -->"
  in
    body <> "\n\n" <> coverage <> "\n"

----------------------------------------------------------------------------
-- Walking the module
----------------------------------------------------------------------------

sectionDocs :: Int -> Acc -> Section Resolved -> (Acc, [Block])
sectionDocs depth acc0 (MkSection _ mname _maka decls) =
  let
    heading = case mname of
      Just n -> [DocHeading depth (titleCase (resolvedText n))]
      Nothing -> []
    -- an anonymous section is a transparent wrapper: children stay at
    -- the same heading depth
    childDepth = case mname of
      Just _ -> depth + 1
      Nothing -> depth
    (acc1, childDocs) = foldl' step (acc0, []) decls
    step (acc, docs) decl =
      let (acc', new) = topDeclDocs childDepth acc decl
      in (acc', docs <> new)
  in
    (acc1, heading <> childDocs)

topDeclDocs :: Int -> Acc -> TopDecl Resolved -> (Acc, [Block])
topDeclDocs depth acc = \case
  Section _ sub -> sectionDocs depth acc sub
  Decide _ d -> provision acc (decideDoc d)
  Assume _ a -> assumeDocs acc a
  Declare _ d -> provision acc (declareDoc d)
  Directive _ _ -> (acc{suppressedDirectives = acc.suppressedDirectives + 1}, [])
  Import _ _ -> (acc, [])
  Timezone _ _ -> (acc, [])
 where
  provision acc' mk =
    let n = acc'.provisionNum
    in (acc'{provisionNum = n + 1}, [mk n])

-- | Bare BOOLEAN assumptions are atoms whose names already read as full
-- clauses inside provisions; rendering them again as definitions would be
-- noise. Everything else becomes an undefined-term entry.
assumeDocs :: Acc -> Assume Resolved -> (Acc, [Block])
assumeDocs acc (MkAssume _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ name _args _) mty)
  | null givens, isBooleanType mty =
      (acc{inlinedAtoms = acc.inlinedAtoms + 1}, [])
  | otherwise =
      let n = acc.provisionNum
          doc =
            DocProvision
              { anchor = "assume:" <> resolvedText name
              , marginalNote = Nothing
              , number = n
              , leadIn =
                  "In this Act, \x201C"
                    <> resolvedText name
                    <> "\x201D denotes "
                    <> maybe "a term left undefined" typeText mty
                    <> givensSuffix
                    <> "."
              , tabulation = Nothing
              , trailing = []
              }
      in (acc{provisionNum = n + 1}, [doc])
 where
  givensSuffix = case givens of
    [] -> ""
    _ ->
      ", in relation to "
        <> commaAnd (map givenText givens)

isBooleanType :: Maybe (Type' Resolved) -> Bool
isBooleanType = \case
  Just (TyApp _ r []) -> resolvedText r == "BOOLEAN"
  _ -> False

----------------------------------------------------------------------------
-- DECIDE → provision
----------------------------------------------------------------------------

decideDoc :: Decide Resolved -> Int -> Block
decideDoc d@(MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ name _args _) body) n =
  DocProvision
    { anchor = "decide:" <> resolvedText name
    , marginalNote = descOf d
    , number = n
    , leadIn = leadIn'
    , tabulation = mtab
    , trailing = whereTrailing body
    }
 where
  conclusion = sentenceCase (qualifier <> resolvedText name)
  qualifier = case givens of
    [] -> ""
    _ -> "in relation to " <> commaAnd (map givenText givens) <> ", "

  -- peel a top-level WHERE: its locals are rendered as trailing
  -- definition paragraphs, the wrapped expression is the body proper
  mainBody = case carameliseNode body of
    Where _ e _ -> e
    _ -> body

  (leadIn', mtab) = case carameliseNode mainBody of
    Regulative _ deonton ->
      (sentenceCase (deontonText deonton), Nothing)
    e
      | isBooleanStructure e ->
          case toTab mainBody of
            TGroup Nothing conj items
              | null givens
              , Just (lead, items') <- negativeUniversal (resolvedText name) items ->
                  (lead, Just (TGroup Nothing conj items'))
            TGroup mlead conj items ->
              ( conclusion <> " if" <> maybe "\x2014" (\l -> " " <> l) mlead
              , Just (TGroup Nothing conj items)
              )
            TLeaf t ->
              (conclusion <> " if " <> t <> ".", Nothing)
      | otherwise ->
          (conclusion <> " means " <> proseExpr mainBody <> ".", Nothing)

isBooleanStructure :: Expr Resolved -> Bool
isBooleanStructure e = case carameliseNode e of
  And{} -> True
  Or{} -> True
  RAnd{} -> True
  ROr{} -> True
  Not{} -> True
  Implies{} -> True
  _ -> False

-- | WHERE-bound local definitions become trailing paragraphs:
-- \"For the purposes of this provision— ...\"
whereTrailing :: Expr Resolved -> [Text]
whereTrailing body = case carameliseNode body of
  Where _ _ lcls | not (null lcls) ->
    [ "For the purposes of this provision\x2014"
    ]
      <> map localDeclText lcls
  _ -> []

localDeclText :: LocalDecl Resolved -> Text
localDeclText = \case
  LocalDecide _ (MkDecide _ _ (MkAppForm _ name _ _) e) ->
    "\x201C" <> resolvedText name <> "\x201D means " <> proseExpr e <> ";"
  LocalAssume _ (MkAssume _ _ (MkAppForm _ name _ _) mty) ->
    "\x201C"
      <> resolvedText name
      <> "\x201D denotes "
      <> maybe "a term left undefined" typeText mty
      <> ";"

----------------------------------------------------------------------------
-- DECLARE → definition provision
----------------------------------------------------------------------------

declareDoc :: Declare Resolved -> Int -> Block
declareDoc d@(MkDeclare _ _ (MkAppForm _ name _args _) tydecl) n =
  DocProvision
    { anchor = "declare:" <> resolvedText name
    , marginalNote = descOf d
    , number = n
    , leadIn = leadIn'
    , tabulation = mtab
    , trailing = []
    }
 where
  quoted = "\x201C" <> resolvedText name <> "\x201D"
  (leadIn', mtab) = case tydecl of
    RecordDecl _ _ fields ->
      ( "In this Act, " <> quoted <> " means a record consisting of\x2014"
      , Just (TGroup Nothing CAnd (map fieldTab fields))
      )
    EnumDecl _ conDecls ->
      ( "In this Act, " <> quoted <> " means one of the following\x2014"
      , Just (TGroup Nothing COr (map conTab conDecls))
      )
    SynonymDecl _ ty ->
      ("In this Act, " <> quoted <> " means " <> typeText ty <> ".", Nothing)

  fieldTab (MkTypedName _ fname fty _mcomputed) =
    TLeaf $
      "\x201C"
        <> resolvedText fname
        <> "\x201D, being "
        <> typeText fty

  conTab (MkConDecl _ cname cfields) =
    TLeaf $
      "\x201C"
        <> resolvedText cname
        <> "\x201D"
        <> case cfields of
          [] -> ""
          _ ->
            ", having "
              <> commaAnd
                [ articleFor (resolvedText fn)
                    <> " \x201C" <> resolvedText fn <> "\x201D (" <> typeText ft <> ")"
                | MkTypedName _ fn ft _ <- cfields
                ]

----------------------------------------------------------------------------
-- Negative-universal rewriting (deterministic de-stilting)
----------------------------------------------------------------------------

-- | Classical negative-universal drafting: a conclusion of the form
-- \"the X must not VP\" whose conditions are all predicated of \"the X\"
-- rewrites as
--
-- > No X may VP who—
-- >     (a) is a body corporate;
-- >     ...
-- >     (e) has—
-- >         (i) an unspent conviction for fraud; ...
--
-- The subject is hoisted out of every condition; nested groups are
-- verb-factored (longest common word-prefix, trailing function words
-- trimmed). Purely syntactic and total: if any condition does not carry
-- the subject prefix, the whole rewrite declines and the provision falls
-- back to the \"X if—\" form.
negativeUniversal :: Text -> [Tab] -> Maybe (Text, [Tab])
negativeUniversal conclusion items = do
  rest <- Text.stripPrefix "the " conclusion
  let (subj, m) = Text.breakOn " must not " rest
  vp <- Text.stripPrefix " must not " m
  if Text.null subj || Text.null vp
    then Nothing
    else do
      items' <- traverse (elideSubject ("the " <> subj <> " ")) items
      pure
        ( "No " <> subj <> " may " <> vp <> " " <> relPron subj <> "\x2014"
        , items'
        )

-- | Strip the subject from a condition; for one level of nested grouping,
-- additionally factor out the common verb phrase as the group lead-in.
elideSubject :: Text -> Tab -> Maybe Tab
elideSubject subjPfx = \case
  TLeaf t -> TLeaf <$> Text.stripPrefix subjPfx t
  TGroup Nothing c subs -> do
    stripped <-
      traverse
        ( \case
            TLeaf t -> Text.stripPrefix subjPfx t
            TGroup{} -> Nothing
        )
        subs
    (verb, subs') <- factorVerb stripped
    pure (TGroup (Just (verb <> "\x2014")) c (map TLeaf subs'))
  TGroup (Just _) _ _ -> Nothing -- author-supplied lead-in: leave alone

-- | Longest common word-prefix across clauses, with trailing function
-- words trimmed back so we never factor mid-noun-phrase
-- (\"has an unspent…\" / \"has an alcohol…\" factors as \"has\", not \"has an\").
factorVerb :: [Text] -> Maybe (Text, [Text])
factorVerb ts =
  case dropTrailingStop (lcpWords (map Text.words ts)) of
    [] -> Nothing
    common -> do
      let pfxText = Text.unwords common
      rest <- traverse (Text.stripPrefix (pfxText <> " ")) ts
      pure (pfxText, rest)
 where
  dropTrailingStop = reverse . dropWhile (`elem` stopWords) . reverse
  stopWords :: [Text]
  stopWords = ["a", "an", "the", "of", "for", "to", "in", "with", "or", "and", "not", "no"]

lcpWords :: [[Text]] -> [Text]
lcpWords [] = []
lcpWords xs = foldr1 lcp2 xs
 where
  lcp2 a b = map fst (takeWhile (uncurry (==)) (zip a b))

-- | \"who\" for natural-person subjects, \"that\" otherwise.
relPron :: Text -> Text
relPron subj
  | lastWord `elem` personWords = "who"
  | otherwise = "that"
 where
  lastWord = case reverse (Text.words subj) of
    (w : _) -> w
    [] -> subj
  personWords :: [Text]
  personWords =
    [ "person", "individual", "applicant", "officer", "proprietor"
    , "citizen", "employee", "director", "member", "child", "parent"
    , "driver", "owner", "occupier", "operator", "licensee"
    , "borrower", "lender", "keeper", "tenant", "landlord"
    , "buyer", "seller", "vendor", "purchaser"
    ]

----------------------------------------------------------------------------
-- Coode tabulation
----------------------------------------------------------------------------

-- | Build a tabulation tree from a boolean expression.
--
-- An expression carrying an @nlg annotation is always a leaf: the author's
-- prose overrides structural decomposition (mirrors 'L4.Nlg.lin').
toTab :: Expr Resolved -> Tab
toTab e
  | hasNlgAnno e = TLeaf (exprText e)
  | otherwise = case carameliseNode e of
      And{} -> TGroup Nothing CAnd (map toTab (conjuncts e))
      RAnd{} -> TGroup Nothing CAnd (map toTab (conjuncts e))
      Or{} -> TGroup Nothing COr (map toTab (disjuncts e))
      ROr{} -> TGroup Nothing COr (map toTab (disjuncts e))
      Not _ inner
        | not (hasNlgAnno inner) ->
            case carameliseNode inner of
              And{} ->
                TGroup (Just "it is not the case that\x2014") CAnd (map toTab (conjuncts inner))
              Or{} ->
                TGroup (Just "none of the following applies\x2014") COr (map toTab (disjuncts inner))
              _ -> TLeaf (negateClause (exprText inner))
        | otherwise -> TLeaf (negateClause (exprText inner))
      _ -> TLeaf (exprText e)

-- | Flatten a chain of binary ANDs into its conjuncts. A subtree with its
-- own @nlg annotation is opaque (the author's phrasing wins).
conjuncts :: Expr Resolved -> [Expr Resolved]
conjuncts e
  | hasNlgAnno e = [e]
  | otherwise = case carameliseNode e of
      And _ a b -> conjuncts a <> conjuncts b
      RAnd _ a b -> conjuncts a <> conjuncts b
      _ -> [e]

disjuncts :: Expr Resolved -> [Expr Resolved]
disjuncts e
  | hasNlgAnno e = [e]
  | otherwise = case carameliseNode e of
      Or _ a b -> disjuncts a <> disjuncts b
      ROr _ a b -> disjuncts a <> disjuncts b
      _ -> [e]

-- | Conservative grammatical negation of an atomic clause.
--
-- PROVISIONAL (spec §8 open question 1): until a negative-form @nlg hint
-- exists, we negate the copula/auxiliary where that is unambiguous and fall
-- back to the clumsy-but-faithful \"it is not the case that\" otherwise.
negateClause :: Text -> Text
negateClause t
  | Just t' <- swapFirst " is " " is not " t = t'
  | Just t' <- swapFirst " are " " are not " t = t'
  | Just t' <- swapFirst " has " " does not have " t = t'
  | Just t' <- swapFirst " have " " do not have " t = t'
  | otherwise = "it is not the case that " <> t

swapFirst :: Text -> Text -> Text -> Maybe Text
swapFirst needle replacement t =
  case Text.breakOn needle t of
    (before', after')
      | Text.null after' -> Nothing
      | otherwise -> Just (before' <> replacement <> Text.drop (Text.length needle) after')

----------------------------------------------------------------------------
-- Deontics and prose fallback
----------------------------------------------------------------------------

deontonText :: Deonton Resolved -> Text
deontonText (MkDeonton _ party (MkAction _ modal pat mprovided) due hence lest) =
  exprText party
    <> " "
    <> modalText modal
    <> " "
    <> actionText pat
    <> maybe "" (\p -> ", provided that " <> proseExpr p) mprovided
    <> maybe "" (\d -> ", within " <> proseExpr d) due
    <> "."
    <> followup " Upon compliance, " hence
    <> followup " Failing which, " lest
 where
  -- HENCE/LEST FULFILLED is the implicit terminal: drafting leaves it unsaid
  followup lead = maybe "" \e -> case carameliseNode e of
    Var _ r | resolvedText r == "FULFILLED" -> ""
    _ -> lead <> proseExpr e <> "."

-- | The action of a deontic: the event-constructor name reads as the verb
-- phrase; plain variable binders are dropped (they are introduced
-- implicitly and referenced from the PROVIDED clause); structured
-- sub-patterns are kept.
actionText :: Pattern Resolved -> Text
actionText = \case
  PatApp _ ctor args ->
    Text.unwords
      ( resolvedText ctor
          : [flatLinTree (linearize a) | a <- args, not (isVarPat a)]
      )
   where
    isVarPat = \case
      PatVar{} -> True
      _ -> False
  p -> flatLinTree (linearize p)

modalText :: DeonticModal -> Text
modalText = \case
  DMust -> "must"
  DMay -> "may"
  DMustNot -> "must not"
  DDo -> "is to"

-- | Recursive prose rendering for expressions that are not Coode-tabulated:
-- deontics and conditionals get sentential treatment, everything else falls
-- through to the annotation-aware linearizer.
proseExpr :: Expr Resolved -> Text
proseExpr e = case carameliseNode e of
  Regulative _ deonton -> deontonText deonton
  IfThenElse _ c t el ->
    "if "
      <> proseExpr c
      <> ", then "
      <> proseExpr t
      <> "; otherwise, "
      <> proseExpr el
  Where _ inner _ -> proseExpr inner
  _ -> exprText e

----------------------------------------------------------------------------
-- Rendering the Doc IR to Markdown
----------------------------------------------------------------------------

renderDoc :: TnrOptions -> Block -> [Text]
renderDoc opts = \case
  DocHeading depth t ->
    [Text.replicate (min depth 6) "#" <> " " <> t]
  DocProvision{anchor, marginalNote, number, leadIn, tabulation, trailing} ->
    anchorLine
      <> headingAndLead
      <> tabLines
      <> trailing
   where
    anchorLine =
      [ "<!-- l4: " <> anchor <> " -->" | opts.anchors ]
    numText = Text.pack (show number)
    headingAndLead = case marginalNote of
      Just note ->
        [ "**" <> numText <> ". " <> note <> "**"
        , leadIn
        ]
      Nothing ->
        ["**" <> numText <> ".** " <> leadIn]
    tabLines = case tabulation of
      Nothing -> []
      Just (TGroup _ conj items) -> renderTabItems 0 conj "." items
      Just (TLeaf t) -> [indent 0 <> t <> "."]

-- | Render the items of one tabulation level: every item ends \";\", the
-- penultimate ends \"; and\" / \"; or\", and the last inherits the
-- terminal punctuation of the enclosing context.
renderTabItems :: Int -> Conj -> Text -> [Tab] -> [Text]
renderTabItems depth conj terminal items =
  concat (zipWith one [1 ..] items)
 where
  total = length items
  conjWord = case conj of
    CAnd -> " and"
    COr -> " or"
  sep i
    | i == total = terminal
    | i == total - 1 = ";" <> conjWord
    | otherwise = ";"
  one i item = case item of
    TLeaf t ->
      [indent depth <> marker i <> " " <> t <> sep i]
    TGroup mlead c subs ->
      [indent depth <> marker i <> " " <> fromMaybe (defaultLead c) mlead]
        <> renderTabItems (depth + 1) c (sep i) subs
  marker i = "(" <> markerText depth i <> ")"

defaultLead :: Conj -> Text
defaultLead = \case
  CAnd -> "all of the following apply\x2014"
  COr -> "any of the following applies\x2014"

-- | Paragraph (a) → subparagraph (i) → sub-subparagraph (A) → (1), cycling.
markerText :: Int -> Int -> Text
markerText depth i = case depth `mod` 4 of
  0 -> letters i
  1 -> toRoman i
  2 -> Text.toUpper (letters i)
  _ -> Text.pack (show i)

letters :: Int -> Text
letters i =
  let j = (i - 1) `mod` 26
      rep = (i - 1) `div` 26 + 1
  in Text.replicate rep (Text.singleton (toEnum (fromEnum 'a' + j)))

toRoman :: Int -> Text
toRoman = go [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")]
 where
  go _ 0 = ""
  go [] _ = ""
  go pairs@((v, sym) : rest) n
    | n >= v = sym <> go pairs (n - v)
    | otherwise = go rest n

indent :: Int -> Text
indent depth = Text.replicate ((depth + 1) * 4) " "

----------------------------------------------------------------------------
-- Leaf text via the annotation-aware linearizer
----------------------------------------------------------------------------

-- | Like 'L4.Nlg.simpleLinearizer', but variables are rendered bare
-- (no backticks): TNR output is prose, not code.
flatLinTree :: LinTree -> Text
flatLinTree tree =
  Text.strip $ case dropSpaceBeforePossessive tree.tokens of
    [] -> ""
    (x : xs) -> Text.stripStart (tok x) <> mconcat (fmap tok xs)
 where
  -- "p 's English name" → "p's English name"
  dropSpaceBeforePossessive = \case
    (a : b : rest)
      | a.type' == LinText
      , Text.all (== ' ') a.payload
      , b.type' == LinPossessive ->
          dropSpaceBeforePossessive (b : rest)
    (a : rest) -> a : dropSpaceBeforePossessive rest
    [] -> []
  tok t = case t.type' of
    LinPossessive -> "'" <> t.payload
    LinPunctuation -> t.payload <> " "
    LinUser -> t.payload
    LinVar -> t.payload
    LinText -> t.payload

exprText :: Expr Resolved -> Text
exprText = flatLinTree . lin

resolvedText :: Resolved -> Text
resolvedText = flatLinTree . linearize

givenText :: OptionallyTypedName Resolved -> Text
givenText (MkOptionallyTypedName _ n mty) =
  case mty of
    Just ty -> typeText ty <> " \x201C" <> resolvedText n <> "\x201D"
    Nothing -> "\x201C" <> resolvedText n <> "\x201D"

typeText :: Type' Resolved -> Text
typeText = \case
  Type _ -> "a type"
  TyApp _ r [] -> withArticle (resolvedText r)
  TyApp _ r [arg]
    | resolvedText r == "MAYBE" -> "an optional " <> typeTextBare arg
    | resolvedText r == "LIST" -> "a list of " <> typeTextBare arg
  TyApp _ r args -> withArticle (Text.unwords (resolvedText r : map typeTextBare args))
  Fun _ _ res -> "a function yielding " <> typeText res
  Forall _ _ ty -> typeText ty
  InfVar _ raw _ -> withArticle (rawNameToText raw)
 where
  typeTextBare = \case
    TyApp _ r [] -> resolvedText r
    other -> typeText other

withArticle :: Text -> Text
withArticle t = articleFor t <> " " <> t

articleFor :: Text -> Text
articleFor t = case Text.uncons t of
  Just (c, _)
    | Text.toLower (Text.singleton c) `Text.isInfixOf` "aeiou" -> "an"
  _ -> "a"

----------------------------------------------------------------------------
-- Small text helpers
----------------------------------------------------------------------------

hasNlgAnno ::
  (HasAnno a, AnnoExtra a ~ Extension, AnnoToken a ~ PosToken) => a -> Bool
hasNlgAnno a = isJust (a ^. annoOf % annNlg)

descOf ::
  (HasAnno a, AnnoExtra a ~ Extension, AnnoToken a ~ PosToken) => a -> Maybe Text
descOf a = getDesc <$> a ^. annoOf % annDesc

sentenceCase :: Text -> Text
sentenceCase t = case Text.uncons t of
  Just (c, rest) -> Text.toUpper (Text.singleton c) <> rest
  Nothing -> t

titleCase :: Text -> Text
titleCase = sentenceCase

commaAnd :: [Text] -> Text
commaAnd = \case
  [] -> ""
  [x] -> x
  [x, y] -> x <> " and " <> y
  (x : xs) -> x <> ", " <> commaAnd xs
