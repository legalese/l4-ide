module L4.Nlg (
  simpleLinearizer,
  selectLanguage,
  carriesLanguage,
  Linearize (..),
  lin,
  unescapeNlgText,
) where

import Base
import qualified Base.Text as Text

import L4.Annotation
import L4.Lexer (LangTag, PosToken, isNlgEscapable)
import L4.Syntax
import L4.Utils.Ratio (prettyRatio)
import L4.Desugar
import Optics

-- | Convert a deontic modal to its text representation for NLG
deonticModalText :: DeonticModal -> Text
deonticModalText = \case
  DMust    -> "must"
  DMay     -> "may"
  DMustNot -> "must not"
  DDo      -> "do"

-- TODO: I would like to be able to attach meta information and
-- to be able to tell apart variables, parameters and global definitions.
-- So, perhaps we rather want a 'Doc' type?
-- Or, like GF, a typed LinTree type that performs pre-analysis steps
data LinToken = MkLinToken
  { payload :: Text
  , type' :: LinType
  }
  deriving stock (Show, Eq, Ord, Generic)

data LinType
  = LinText
  | LinVar
  | LinUser
  | LinPossessive
  | LinPunctuation
  deriving stock (Show, Eq, Ord, Generic)

newtype LinTree = MkLinTree
  { tokens :: [LinToken]
  }
  deriving stock (Show, Eq, Ord, Generic)
  deriving newtype (Semigroup, Monoid)

instance IsString LinTree where
  fromString = text . Text.pack

-- | Linearize an expression into plain text.
-- This linearizer does not attempt to do any smart operations, such as capitalization.
simpleLinearizer :: Linearize a => a -> Text
simpleLinearizer a =
  let
    tree = linearize a

    sp :: Text
    sp = " "

    prettyLinTok :: LinToken -> Text
    prettyLinTok t = case t.type' of
      LinPossessive -> "'" <> t.payload
      LinPunctuation -> t.payload <> sp
      LinUser -> t.payload
      LinVar -> "`" <> t.payload <> "`"
      LinText -> t.payload
  in
    case tree.tokens of
      [] -> ""
      (x:xs) -> Text.stripStart (prettyLinTok x) <> mconcat (fmap prettyLinTok xs)

-- | Render in a particular language, by promoting each node's rendering for
-- that language into the slot every reader already looks at.
--
-- __A rewrite rather than a parameter on 'Linearize', deliberately.__ Every
-- consumer of an annotation reads 'annNlg' and nothing else — this linearizer,
-- LSP hover, the docassemble and Blawx exporters, the relational lowering.
-- Threading a language through all of them means changing all of them, and
-- 'Linearize' has nowhere to put it. Moving the requested rendering into
-- 'annNlg' first makes every one of them language-aware without any of them
-- being touched, and it is exactly what makes a bilingual document SET
-- producible: run the same pipeline twice, once per language.
--
-- @'selectLanguage' 'Nothing'@ is the identity, so every existing caller — the
-- @.nlg.golden@ producer included — is byte-for-byte unaffected.
--
-- It only rewrites 'Name' nodes because those are the only nodes an @\@nlg@
-- annotation ever attaches to (measured 2026-09-19; even an annotation written
-- under an expression lands on the last 'Name' in that expression's range).
selectLanguage :: Maybe LangTag -> Module Resolved -> Module Resolved
selectLanguage Nothing  m = m
selectLanguage mlang    m = over (gplate @Name) promote m
 where
  promote :: Name -> Name
  promote n = case nlgFor mlang (getAnno n) of
    Nothing -> n
    Just r  -> n & annoOf %~ setNlg r

-- | Does any rendering in this module name this language?
--
-- __The question 'selectLanguage' cannot be asked afterwards.__ Selection
-- promotes a rendering where there is one and leaves the node alone where there
-- is not, so a request for a language the module carries nothing for produces
-- exactly the module a request for nothing would: the two are indistinguishable
-- from the result. A caller that has to LABEL the document with the language —
-- @\<html lang="…"\>@, an Akoma Ntoso FRBR URI — needs to tell them apart, or it
-- labels an all-English document Hebrew and lays it out right to left.
--
-- Untagged renderings in a module that declares @\@lang he@ count as Hebrew
-- here: the parser stamps the module's language onto them
-- ('L4.Syntax.withDefaultLang', applied at 'L4.Parser' before anything
-- downstream sees an annotation), so no separate declaration check is needed for
-- a module that has any @\@nlg@ at all. A module that declares a language and
-- carries no annotations is the one case this returns 'False' on — the
-- declaration is the caller's to consult, and 'L4.Cli.Render' does.
--
-- Same traversal as 'selectLanguage', for the same reason: an @\@nlg@ only ever
-- lands on a 'Name'.
carriesLanguage :: LangTag -> Module Resolved -> Bool
carriesLanguage want m = any nodeCarries (toListOf (gplate @Name) m)
 where
  nodeCarries n =
    let a = getAnno n
    in any ((== Just want) . nlgLangTag)
           (toList (view annNlg a) <> view annNlgAlts a)

-- | Translate an 'a' to something that can be linearized.
class Linearize a where
  linearize :: a -> LinTree

instance Linearize (Expr Resolved) where
  linearize expr = case carameliseNode expr of
    And _ e1 e2 -> hcat
      [ lin e1
      , text "and"
      , lin e2
      ]
    Or _ e1 e2 -> hcat
      [ lin e1
      , text "or"
      , lin e2
      ]
    RAnd _ e1 e2 -> hcat
      [ lin e1
      , text "and"
      , lin e2
      ]
    ROr _ e1 e2 -> hcat
      [ lin e1
      , text "or"
      , lin e2
      ]
    Implies _ e1 e2 -> hcat
      [ lin e1
      , text "implies"
      , lin e2
      ]
    Equals _ e1 e2 -> hcat
      [ lin e1
      , text "is"
      , text "equal"
      , text "to"
      , lin e2
      ]
    Not _ e -> hcat
      [ text "not"
      , lin e
      ]
    Plus _ e1 e2 -> hcat
      [ text "the"
      , text "sum"
      , text "of"
      , lin e1
      , text "and"
      , lin e2
      ]
    Minus _ e1 e2 -> hcat
      [ text "the"
      , text "difference"
      , text "between"
      , lin e2
      , text "and"
      , lin e1
      ]
    Times _ e1 e2 -> hcat
      [ text "the"
      , text "product"
      , text "of"
      , lin e1
      , text "and"
      , lin e2
      ]
    DividedBy _ e1 e2 -> hcat
      [ text "the"
      , text "result"
      , text "of"
      , text "dividing"
      , lin e1
      , text "by"
      , lin e2
      ]
    Modulo _ e1 e2 -> hcat
      [ text "the"
      , text "result"
      , text "of"
      , lin e1
      , text "modulo"
      , lin e2
      ]
    Cons _ e1 e2 -> hcat
      [ lin e1
      , text "followed"
      , text "by"
      , lin e2
      ]
    Leq _ e1 e2 -> hcat
      [ lin e1
      , text "is"
      , text "at"
      , text "most"
      , lin e2
      ]
    Geq _ e1 e2 -> hcat
      [ lin e1
      , text "is"
      , text "at"
      , text "least"
      , lin e2
      ]
    Lt _ e1 e2 -> hcat
      [ lin e1
      , text "is"
      , text "less"
      , text "than"
      , lin e2
      ]
    Gt _ e1 e2 -> hcat
      [ lin e1
      , text "is"
      , text "greater"
      , text "than"
      , lin e2
      ]
    Proj _ e1 e2 -> hcat
      [ lin e1
      , possessive "s"
      , linearize e2
      ]
    Var _ v -> linearize v
    Lam _ sig e -> hcat
      [ lin sig
      , text "then"
      , lin e
      ]
    App _ n es -> hcat $
      [ linearize n
      ]
      <> ifNonEmpty es
            [ text "with"
            , enumerate (punctuate ",") (spaced $ text "and") (fmap lin es)
            ]
    AppNamed _ n es _order -> hcat
      [ linearize n
      , text "where"
      , enumerate (punctuate ",") (spaced $ text "and") (fmap lin es)
      ]
    IfThenElse _ cond then' else' -> hcat
      [ text "if"
      , lin cond
      , text "then"
      , lin then'
      , text "else"
      , lin else'
      ]
    MultiWayIf _ conds o -> hcat $
      foldMap (\(MkGuardedExpr _ c f) -> ["if", lin c, "then", lin f]) conds
      <> ["otherwise", lin o ]
    Regulative _ (MkDeonton _ subj (MkAction _ modal rule mprovided) mopens mdeadline mjoin mfollowup mlest) -> hcat $
      linSubject subj
      <> [ text (deonticModalText modal)
         , lin rule
         ]
      <> maybe [] (\ provided -> [ text "provided that", lin provided ]) mprovided
      <> maybe [] linOpening mopens
      <> maybe [] (linClosing (isJust mopens)) mdeadline
      <> maybe [] linJoin mjoin
      <> maybe [] (\ followup -> [ text "hence",  lin followup ]) mfollowup
      <> maybe [] (\ lest -> [ text "lest",  lin lest ]) mlest
      where
        linJoin j = case j of
          -- follows 'L4.Print' (uponEachWords); R-Q1 RULED 2026-09-07
          JoinOnce _ th mdue ->
            [ text "once" ]
            <> (case th of AllHave _ -> [ text "all", text "have" ])
            <> linJoinDue mdue
          JoinUpon _ _ mdue -> [ text "upon", text "each" ] <> linJoinDue mdue
        linJoinDue = maybe [] linDeadline
        -- @within d@, then the anchor: the lifecycle words as prose, or the
        -- expression (R-Q7, §5.1.1); @before date@ for the absolute edge
        -- (R-X5, §5.1.2). Only the WITHIN form sits on a join line.
        linDeadline = linClosing False
        -- The closing edge of an act. Beside an @after@, a bare @within@
        -- counts from the instant the window opened (re-anchor, §5.1.2.2),
        -- and the English says so: "after 3 days, within 30 days of that".
        linClosing afterOpening = \ case
          MkDeadline _ d ma ->
            [ text "within", lin d ]
            <> maybe (if afterOpening then [ text "of", text "that" ] else [])
                     (\ a -> [ text "of" ] <> linAnchor a) ma
          MkBefore _ e -> [ text "before", lin e ]
        -- @after d [of anchor]@ — the window's opening edge
        linOpening (MkOpening _ d ma) =
          [ text "after", lin d ]
          <> maybe [] (\ a -> [ text "of" ] <> linAnchor a) ma
        linAnchor = \ case
          AnchorJoin _     -> [ text "the", text "join" ]
          AnchorDeadline _ -> [ text "the", text "deadline" ]
          AnchorArming _   -> [ text "the", text "arming" ]
          AnchorAt _ e     -> [ lin e ]
        linSubject = \ case
          Party _ party -> [ text "party", lin party ]
          Every _ mCast v mRoll mFilter ->
            [ text "every" ]
            -- Resolved can't use 'lin', as it doesn't have an 'Anno'
            <> maybe [] (\ c -> [ linearize c ]) mCast
            <> [ linearize v ]
            <> maybe [] (\ r -> [ text "in", lin r ]) mRoll
            <> maybe [] (\ f -> [ text "who", lin f ]) mFilter
    Consider _ e br -> hcat
      [ text "consider"
      , text "the"
      , text "case"
      , text "distinctions"
      , text "of"
      , lin e
      , punctuate ":"
      , enumerate (punctuate ".") (punctuate ".") (fmap lin br)
      ]
    Lit _ l -> lin l
    Percent _ l -> hcat [lin l, punctuate "%"]
    List _ es -> hcat
      [ text "list"
      , text "of"
      , enumerate (punctuate ",") (spaced $ text "and") (fmap lin es)
      ]
    Where _ e lcl -> hcat
      [ lin e
      , text "where"
      , enumerate (punctuate ",") (spaced $ text "and") (fmap lin lcl)
      ]
    LetIn _ lcl e -> hcat
      [ text "let"
      , enumerate (punctuate ",") (spaced $ text "and") (fmap lin lcl)
      , text "in"
      , lin e
      ]
    Event _ ev -> lin ev
    Fetch _ e -> hcat [ text "fetch", lin e ]
    Env _ e -> hcat [ text "environment variable", lin e ]
    Post _ e1 e2 e3 -> hcat [ text "post", lin e1, lin e2, lin e3 ]
    Record _ mParty cell val isOfficial mHence -> hcat ([ text (if isOfficial then "commit" else "record") ] <> maybe [] (\p -> [ lin p, text "'s" ]) mParty <> [ lin cell, text "is", lin val ] <> maybe [] (\k -> [ text "hence", lin k ]) mHence)
    ReadCell _ mParty isOfficial mode cell -> hcat ([ text "recall" ] <> (case mode of RecallAll -> [ text "all" ]; RecallLast -> []) <> (if isOfficial then [ text "official's" ] else []) <> maybe [] (\p -> [ lin p, text "'s" ]) mParty <> [ lin cell ])
    Concat _ exprs -> hcat [ text "concatenate", enumerate (punctuate ",") (spaced $ text "and") (fmap lin exprs) ]
    AsString _ e -> hcat [ lin e, text "as", text "string" ]
    Breach _ mParty mReason -> hcat $
      [ text "breach" ]
      <> maybe [] (\p -> [ text "by", lin p ]) mParty
      <> maybe [] (\r -> [ text "because", lin r ]) mReason
    -- A refusal reads as what it is: the model declining to answer, with the
    -- author's reason.
    Refuse _ msg -> hcat [ "the model refuses to answer:", lin msg ]
    Inert _ txt _ctx -> text txt

instance Linearize (Event Resolved) where
  linearize (MkEvent _ p a t _) = hcat
    [ "party", lin p, "did", lin a, "at", lin t]

instance Linearize (Directive Resolved) where
  linearize = \ case
    LazyEval _ e -> linearize e
    LazyEvalTrace _ e -> linearize e
    Check _ e -> linearize e
    Contract _ e t es -> hcat $
      [ "executing contract", lin e, "at", lin t, "with the following events: " ]
      <> map lin es
    Assert _ e -> linearize e
    AssertRefused _ e _mmsg -> hcat [ "the following must refuse:", lin e ]


instance Linearize (NamedExpr Resolved) where
  linearize = \ case
    MkNamedExpr _ n e -> hcat
      [ linearize n
      , text "is"
      , lin e
      ]

instance Linearize (LocalDecl Resolved) where
  linearize = \ case
    LocalDecide _ _decide -> mempty
    LocalAssume _ _assume -> mempty

instance Linearize Lit where
  linearize = \ case
    NumericLit _ num -> text (prettyRatio num)
    StringLit _ t -> text t

instance Linearize (Branch Resolved) where
  linearize = \ case
    MkBranch _ (When _ pat) e -> hcat
      [ text "when"
      , lin pat
      , text "then"
      , lin e
      ]
    MkBranch _ (Otherwise _) e -> hcat
      [ text "in"
      , text "any"
      , text "other"
      , text "case"
      , lin e
      ]

instance Linearize (Pattern Resolved) where
  linearize = \ case
    PatVar _ v ->
      -- Resolved can't use 'lin', as it doesn't have an 'Anno'
      linearize v
    PatApp _ constructor pats -> hcat
      [ -- Resolved can't use 'lin', as it doesn't have an 'Anno'
        linearize constructor
      , text "has"
      , enumerate (punctuate ",") (spaced $ text "and") (fmap lin pats)
      ]
    PatCons _ start rest -> hcat
      [ lin start
      , text "is"
      , text "followed"
      , text "by"
      , lin rest
      ]
    PatExpr _ expr -> hcat [ "is", "exactly", lin expr ]
    PatLit _ lit -> hcat [ lin lit ]

instance Linearize (GivenSig Resolved) where
  linearize = \ case
    MkGivenSig _ args -> hcat
      [ text "given"
      , enumerate (punctuate ",") (spaced $ text "and") (fmap lin args)
      ]

instance Linearize (OptionallyTypedName Resolved) where
  linearize = \ case
    MkOptionallyTypedName _ name _mty _mTypically -> hcat
      [ linearize name
      ]

instance Linearize Name where
  linearize = var . nameToText

instance Linearize Resolved where
  linearize = \ case
    Def _ name -> lin name
    Ref ref _ original
      | hasNlgAnnotation original && not (hasNlgAnnotation ref) ->
          -- If the binding has an NLG annotation, but the use-site does not
          -- have an NLG annotation, we use the NLG annotation of the binding.
        lin original
      | otherwise ->
        -- In all other cases, we just use the NLG annotation of the use-site.
        -- This behaves correctly when there is no NLG annotation at all.
        lin ref
    OutOfScope _ n -> lin n
   where
    hasNlgAnnotation name = isJust $ name ^. annoOf % annNlg

instance Linearize Nlg where
  linearize = \ case
    MkInvalidNlg _ -> text "(internal error)"
    MkParsedNlg _ _ frags -> foldMap linParsedFragment frags
    MkResolvedNlg _ _ frags -> foldMap linResolvedFragment frags
   where
    linParsedFragment :: NlgFragment Name -> LinTree
    linParsedFragment = \ case
      MkNlgText _ t -> user (unescapeNlgText t)
      MkNlgRef  _ n -> linearize n

    linResolvedFragment :: NlgFragment Resolved -> LinTree
    linResolvedFragment = \ case
      MkNlgText _ t -> user (unescapeNlgText t)
      MkNlgRef  _ n -> linearize n

-- | Decode the backslash escapes an NLG annotation may carry.
--
-- The lexer deliberately keeps @\\%@ and @\\]@ verbatim (see
-- 'L4.Lexer.inlineNlgAnno'), because that same text is what exactprint
-- re-emits — decoding earlier makes @l4 format@ strip the backslash and change
-- the annotation's meaning. So the decode happens on the render side instead.
--
-- __Every renderer must call this; two deliberately do not.__ An earlier
-- revision of this comment claimed the 'Linearize' instance below was "the
-- single point where annotation text becomes output". That was false, and it
-- shipped a half-wired feature: @l4 render@ (text, html, json and akn), the
-- LSP document webview and @l4 blawx@ all rendered the backslash literally.
-- The current call sites are this instance, 'L4.Export.Document.renderNlgWith'
-- and 'L4.Blawx.Lower.nlgChunks'. The two abstainers, and why:
--
--   * 'L4.Print' keeps the text raw because it is the printer — exactprint and
--     @prettyLayout@ must re-emit the source bytes.
--   * 'L4.Relational.Lower.linearNlg' keeps it raw because its output is
--     re-scanned for @%name%@ slots by 'L4.Blawx.Lower.scanNlg'. Decoding
--     there would turn @10\\%and\\%20@ back into @10%and%20@ and manufacture
--     exactly the phantom slot the escape exists to prevent —
--     @slotNameShaped "and"@ is 'True'. The decode belongs to the literal
--     chunks that scan returns, which is where 'nlgChunks' applies it.
--
-- @\\%@, @\\]@, @\\[@ and @\\\\@ decode; that set is 'L4.Lexer.isNlgEscapable',
-- which this decoder CALLS rather than restates, and the lexer consumes exactly
-- it, so the two sides cannot disagree about whether an escape happened. Any
-- other @\\x@ is two ordinary characters throughout. @\\[@ joined the set on
-- 2026-09-19 and is the one member that protects nothing — see the ruling at
-- 'L4.Lexer.isNlgEscapable' for why a redundant escape is still worth accepting.
--
-- __Corrected 2026-09-19.__ This comment used to say the tree contained no
-- backslash in any @.l4@ file at all (measured 2026-09-17, 0 lines). That is no
-- longer true: @git grep '\\\\' -- '*.l4'@ finds 10 lines across 4 files. The
-- claim that matters survives re-measurement in a narrower form — exactly ONE
-- of those backslashes is inside an NLG annotation, the @10\\%and\\%20@ in
-- @doc\/reference\/syntax\/annotation-example.l4@, and it is a @\\%@ that
-- already decoded. The rest are @\\"@ and @\\t@ inside ordinary string
-- literals, which this decoder never sees. So no existing annotation changes
-- meaning. State the narrow claim: the broad one drifted within two days of
-- being written, because string literals kept being added.
unescapeNlgText :: Text -> Text
unescapeNlgText t
  | not (Text.any (== '\\') t) = t        -- the overwhelmingly common case
  | otherwise = Text.pack (go (Text.unpack t))
  where
    go = \ case
      '\\' : c : rest | isNlgEscapable c -> c : go rest
      c : rest -> c : go rest
      [] -> []

hcat :: [LinTree] -> LinTree
hcat = mconcat . intersperse space

space :: LinTree
space = text " "

ifNonEmpty :: Monoid m => [a] -> m -> m
ifNonEmpty [] _ = mempty
ifNonEmpty (_:_) f = f

-- | 'lin' is like 'linearize', but first checks whether the 'a' has any 'Nlg'
-- annotations associated with it. If it does, then the 'Nlg' annotations
-- replaces the linearization of 'a'.
--
-- 'Resolved' can't use 'lin', as it doesn't have an 'Anno'
lin :: (HasAnno a, AnnoExtra a ~ Extension, AnnoToken a ~ PosToken, Linearize a) => a -> LinTree
lin a
  | Just nlg <- a ^. annoOf % annNlg =
      linearize nlg
  | otherwise =
      linearize a

text :: Text -> LinTree
text t = MkLinTree
  [ MkLinToken
    { type' = LinText
    , payload = t
    }
  ]

var :: Text -> LinTree
var t = MkLinTree
  [ MkLinToken
    { type' = LinVar
    , payload = t
    }
  ]

user :: Text -> LinTree
user t = MkLinTree
  [ MkLinToken
    { type' = LinUser
    , payload = t
    }
  ]

possessive :: Text -> LinTree
possessive t = MkLinTree
  [ MkLinToken
    { type' = LinPossessive
    , payload = t
    }
  ]

punctuate :: Text -> LinTree
punctuate t = MkLinTree
  [ MkLinToken
    { type' = LinPunctuation
    , payload = t
    }
  ]

enumerate :: LinTree -> LinTree -> [LinTree] -> LinTree
enumerate _   lastSep [x, y] = mconcat [x, lastSep, y]
enumerate _   _       [x]    = x
enumerate _   _       []     = mempty
enumerate sep lastSep (x:xs) = x <> sep <> enumerate sep lastSep xs

spaced :: LinTree -> LinTree
spaced p = text " " <> p <> text " "
