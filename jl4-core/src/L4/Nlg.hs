module L4.Nlg (
  simpleLinearizer,
  simpleLinearizerIn,
  linearizeDirectives,
  linearizeDirectivesIn,
  selectLanguage,
  NlgSite (..),
  decideNlg,
  decideNlgSite,
  promoteHeadInputNlg,
  carriesLanguage,
  Linearize (..),
  lin,
  unescapeNlgText,
  -- * Splicing a call's arguments into its herald
  NlgFnInfo,
  nlgFnInfo,
  substituteNlgCalls,
  substituteNlgCallsIn,
  substituteNlgDirective,
  substituteNlgDirectiveIn,
  renderNlgWith,
  renderNlgWithIn,
  normalizeWs,
  oxford,
) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Annotation
import L4.Lexer (LangTag, PosToken, isNlgEscapable)
import L4.Syntax
import L4.Utils.Ratio (prettyRatio)
import L4.Desugar
import L4.Nlg.Phrasebook (Phrasebook, phrasebookFor, maqaf)
import Optics
import Data.Ratio (denominator, numerator)
import Data.Time (fromGregorianValid)
import qualified Data.Time.Format as TimeFormat
import Data.Char (isLetter)

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
  | LinFrame
    -- ^ A word the LINEARIZER supplies rather than the author: "is equal to",
    -- "with", "not". Only these are looked up in a phrasebook ('localize');
    -- an author's text, a literal and a name never are.
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
  fromString = frame . Text.pack

-- | Linearize an expression into plain text.
-- This linearizer does not attempt to do any smart operations, such as capitalization.
simpleLinearizer :: Linearize a => a -> Text
simpleLinearizer = renderLinTree . linearize

-- | 'simpleLinearizer' with the frame words in a language, plus the English
-- frame words that language's phrasebook had no entry for.
--
-- With 'Nothing', or a language that has no phrasebook, the text is exactly
-- 'simpleLinearizer''s and the set is empty.
simpleLinearizerIn :: Linearize a => Maybe LangTag -> a -> (Text, Set.Set Text)
simpleLinearizerIn mlang a = first renderLinTree (localizeIn mlang (linearize a))

renderLinTree :: LinTree -> Text
renderLinTree tree =
  let
    sp :: Text
    sp = " "

    prettyLinTok :: LinToken -> Text
    prettyLinTok t = case t.type' of
      LinPossessive -> "'" <> t.payload
      LinPunctuation -> t.payload <> sp
      LinUser -> t.payload
      LinVar -> "`" <> t.payload <> "`"
      LinText -> t.payload
      LinFrame -> t.payload
  in
    case tree.tokens of
      [] -> ""
      (x:xs) -> Text.stripStart (prettyLinTok x) <> mconcat (fmap prettyLinTok xs)

localizeIn :: Maybe LangTag -> LinTree -> (LinTree, Set.Set Text)
localizeIn mlang tree = case phrasebookFor =<< mlang of
  Nothing -> (tree, Set.empty)
  Just pb -> localize pb tree

-- | Replace a linearization's frame phrases with a phrasebook's renderings,
-- and report the English words it has no entry for.
--
-- A RUN is a maximal stretch of frame tokens separated only by the spaces
-- 'hcat' puts between them. So "is", "equal" and "to" arrive as one run and
-- can match the single phrase "is equal to". Within a run the longest phrase
-- wins. A word with no entry stays English and is reported; a token with no
-- letter in it ("%", a space) is neither translated nor reported.
--
-- A rendering that ends in a maqaf is a prefix, and it swallows the space
-- after it, so "שווה ל־" meets its value as "שווה ל־200".
localize :: Phrasebook -> LinTree -> (LinTree, Set.Set Text)
localize pb (MkLinTree toks0) = first MkLinTree (go toks0)
 where
  go [] = ([], Set.empty)
  go ts@(t : rest0)
    | isFrameWord t =
        let (run, rest)     = spanRun ts
            (out, misses)   = translate (concatMap (Text.words . (.payload)) (filter isFrameWord run))
            glue            = case reverse out of
                                (w : _) -> Text.takeEnd 1 w == Text.singleton maqaf
                                []      -> False
            rest'           = if glue then dropSpace rest else rest
            (more, misses') = go rest'
        in (intersperse spaceTok (map frameTok out) <> more, misses <> misses')
    | otherwise = first (t :) (go rest0)

  -- A run keeps the spaces BETWEEN its words but not a trailing one. That
  -- space separates the run from whatever follows, so it is emitted after it.
  spanRun ts =
    let (run, rest) = span (\ t -> isFrameWord t || isSpaceTok t) ts
        trailing    = reverse (takeWhile isSpaceTok (reverse run))
    in (take (length run - length trailing) run, trailing <> rest)

  dropSpace (t : ts) | isSpaceTok t = ts
  dropSpace ts = ts

  translate [] = ([], Set.empty)
  translate ws@(w : ws') =
    case [ (n, r) | n <- [length ws, length ws - 1 .. 1]
                  , Just r <- [Map.lookup (take n ws) pb] ] of
      (n, r) : _ -> first (r :) (translate (drop n ws))
      []         -> bimap (w :) (if Text.any isLetter w then Set.insert w else id)
                          (translate ws')

  isFrameWord t = t.type' == LinFrame && Text.any isLetter t.payload
  isSpaceTok t  = t.type' `elem` [LinText, LinFrame] && not (Text.null t.payload)
                  && Text.all (== ' ') t.payload
  frameTok w    = MkLinToken { payload = w, type' = LinFrame }
  spaceTok      = MkLinToken { payload = " ", type' = LinText }

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

-- ----------------------------------------------------------------------------
-- Where a DECIDE's @nlg landed, and what to do about a head's input
-- ----------------------------------------------------------------------------

-- | Which annotation-bearing position of a @DECIDE@ its @\@nlg@ was found in.
--
-- Only 'decideNlgSite' produces these. 'promoteHeadInputNlg' reads them to
-- tell an INPUT's annotation apart from the rule's own, and 'decideNlg' reads
-- them to refuse a @GIVEN@ gloss as the rule's sentence. Inferring
-- that from the 'Nlg' after the fact is not possible — the same sentence can
-- legitimately sit in either place.
data NlgSite
  = NlgOnDeclaration
    -- ^ The enclosing 'TopDecl'\'s annotation, the @DECIDE@\'s own, the app
    -- form's, or the body's. All four mean "the rule", so they are one case.
  | NlgOnHeadName
    -- ^ The rule's name in its head.
  | NlgOnHeadInput Resolved
    -- ^ An appform argument THE AUTHOR WROTE IN THE HEAD, which is that input's
    -- BINDING occurrence. This is the case the two projections used to disagree
    -- about; see 'promoteHeadInputNlg'.
  | NlgOnHoistedInput Resolved
    -- ^ An appform argument the TYPE CHECKER put there. A head with no arguments
    -- gets the @GIVEN@\'s term names hoisted into it
    -- (@L4.TypeCheck.checkTermAppFormTypeSigConsistency@, whose own @TODO@ says
    -- "the appform occurrences aren't truly there"), so an annotation found on
    -- one of these was written in the @GIVEN@ and is an input gloss.
    --
    -- The two are told apart by whether the argument still has a source range:
    -- the hoist applies 'L4.Annotation.clearSourceAnno', which sets @range@ to
    -- 'Nothing'. That is the only place in the pipeline where an appform argument
    -- has no range, and it is exactly the distinction that matters here.
  | NlgOnGivenName Resolved
    -- ^ A @GIVEN@ name that is not in the appform at all — in practice a type
    -- variable, which @filter isTerm@ leaves out of the hoist.
  deriving stock (Show, Eq, Generic)

-- | The @\@nlg@ attached to a @DECIDE@, __wherever it landed__, with the
-- position it was found in.
--
-- __One lookup, three projections.__ Authors place a herald differently for
-- @MEANS@ (where it lands on an appform argument) and for @DECIDE … IF@ (where
-- it lands on the head name), so every annotation-bearing position of the
-- declaration is searched. This used to be two hand-kept copies of the same
-- list — one private to 'L4.Export.Document', one in 'L4.Relational.Lower' —
-- and @l4 nlg@ had no copy at all, which is exactly how the three came to
-- disagree (smucclaw\/l4-ide#972). It is one function now, and the order below
-- is the order both copies had.
--
-- The optional 'Anno' is the enclosing 'TopDecl'\'s, where an annotation
-- written above the declaration lands; pass 'Nothing' where you do not have it.
-- Measured on @jl4\/examples\/relational\/tiers.l4@: a @\@ref@ written on the
-- line above @GIVEN@ is found /only/ there.
decideNlgSite :: Maybe Anno -> Decide Resolved -> Maybe (NlgSite, Nlg)
decideNlgSite mouter (MkDecide decAnno (MkTypeSig _ (MkGivenSig _ names) _) (MkAppForm afAnno headName appArgs _) body) =
  -- 'asum' rather than @foldr (<|>) Nothing@: same first-Just semantics, and
  -- '<|>' is not in scope in this module.
  asum $
       [ (NlgOnDeclaration,) <$> (outer ^. annNlg) | outer <- toList mouter ]
    <> [ (NlgOnDeclaration,) <$> decAnno ^. annNlg
       , (NlgOnDeclaration,) <$> afAnno ^. annNlg
       , (NlgOnDeclaration,) <$> body ^. annoOf % annNlg
       , (NlgOnHeadName,)    <$> getOriginal headName ^. annoOf % annNlg
       ]
    <> [ (siteOfAppArg a,)   <$> getOriginal a ^. annoOf % annNlg | a <- appArgs ]
    <> [ (NlgOnGivenName r,) <$> getOriginal r ^. annoOf % annNlg | MkOptionallyTypedName _ r _ _ <- names ]
 where
  siteOfAppArg a
    | isJust (rangeOf (getOriginal a)) = NlgOnHeadInput a
    | otherwise                        = NlgOnHoistedInput a

-- | The rule's OWN sentence: 'decideNlgSite', kept only when the herald was
-- found at a position that means the rule.
--
-- __A herald written in the @GIVEN@ is an input gloss, never the rule's
-- sentence__ ('NlgOnHoistedInput', 'NlgOnGivenName'). A head with no arguments
-- has the @GIVEN@ names hoisted into it, so without this filter
-- @GIVEN amount IS A NUMBER \@nlg the sum of money@ over
-- @DECIDE \`p seven\` IF …@ came back as the rule's sentence, and every
-- consumer printed it that way: @l4 render@ wrote "P seven holds if the sum of
-- money.", and @l4 nlg@ (through 'nlgFnInfo') wrote "the sum of money with 200"
-- at a positional call (smucclaw\/l4-ide#977). The gloss still reaches the
-- output where it belongs, as the input's label in a @WITH@ call.
--
-- Returning 'Nothing' rather than searching on is exact: a hoisted argument
-- only exists when the head has no argument of its own, and the positions after
-- it are further hoisted arguments and @GIVEN@ names.
decideNlg :: Maybe Anno -> Decide Resolved -> Maybe Nlg
decideNlg mouter d = case decideNlgSite mouter d of
  Just (site, nlg) | isRuleSite site -> Just nlg
  _                                  -> Nothing
 where
  isRuleSite = \case
    NlgOnDeclaration    -> True
    NlgOnHeadName       -> True
    NlgOnHeadInput _    -> True
    NlgOnHoistedInput _ -> False
    NlgOnGivenName _    -> False

-- | Move a herald written on a rule head's INPUT onto the rule, so a call site
-- linearizes the author's sentence instead of the rule's bare name.
--
-- __The defect this repairs, and the narrow shape of it__ (smucclaw\/l4-ide#972,
-- measured 2026-09-21). A head may name its inputs a second time —
-- @\`is large\` amount MEANS …@ — and the appform argument is then that input's
-- BINDING occurrence, because 'L4.TypeCheck.ensureNameConsistency' does @def@ on
-- it and @mkref@ on the @GIVEN@ one. A herald written after it therefore sits
-- with the INPUT. 'decideNlgSite' searches the appform arguments on purpose, so
-- @l4 render@ reads such a herald as the rule's sentence; this linearizer's
-- 'Linearize' instance for 'Resolved' sees only the 'Name' a call site resolves
-- to, so at a POSITIONAL call site it printed the rule's bare name. Same bytes,
-- two answers. Measured over the nine modules of canon's
-- @il\/ofek-hadash-2008\/encodings\/legalese@: 65 heralds written, 65 read by
-- @l4 render@, 0 by @l4 nlg@.
--
-- __A rewrite rather than a change to 'Linearize', for the reason
-- 'selectLanguage' gives.__ Every consumer of an annotation reads 'annNlg' and
-- nothing else, and 'Linearize' is handed one node at a time with no way back up
-- to the enclosing @DECIDE@. Putting the sentence where the readers already look
-- makes them all agree without any of them being touched.
--
-- __It MOVES rather than copies, and that is the judgement in here.__ Leaving the
-- herald on the input as well prints the sentence twice in one line at a
-- named-argument call site — once as the call's heading and again as the input's
-- gloss. After the move, a head that repeats its input renders exactly as the
-- same rule with the herald written above its head, which is the placement the
-- reference page recommends; the two become indistinguishable, which is what
-- "the projections agree" has to mean.
--
-- __Three cases it deliberately leaves alone.__
--
--   * A rule whose head name carries its own herald: 'decideNlgSite' finds that
--     one first, so nothing is promoted and the rule keeps the sentence its
--     author wrote for it.
--   * A herald written in the @GIVEN@ ('NlgOnHoistedInput', or 'NlgOnGivenName'
--     for a type variable). That is a genuine input gloss, and @l4 nlg@ already
--     gets it right while @l4 render@ does not — measured,
--     @GIVEN amount IS A NUMBER \@nlg the sum of money@ on a head with no input
--     renders as "P seven holds if the sum of money." Agreement is not worth
--     propagating a wrong answer into a second projection, so the disagreement is
--     fixed from whichever side is right about each case. The @GIVEN@ side is a
--     separate defect and needs its own issue.
--
--     This exclusion is load-bearing and it is not the one you would write first.
--     A head with no arguments does not reach here with an empty @appArgs@ list:
--     the type checker hoists the @GIVEN@\'s term names into it, so the herald IS
--     found on an appform argument and a naive @NlgOnHeadInput@ test promotes it.
--     Measured — that is exactly what the first cut of this function did to the
--     probe above.
--   * A collision — two heralds in one language on one input — attaches neither,
--     so there is nothing to find and nothing to move.
promoteHeadInputNlg :: Module Resolved -> Module Resolved
promoteHeadInputNlg m
  | Map.null promote = m
  | otherwise        = over (gplate @Resolved) fixup m
 where
  (promote, suppress) = foldTopLevelDecides collect m

  collect :: Decide Resolved -> (Map Unique (Nlg, [Nlg]), Set Unique)
  collect d@(MkDecide _ _ (MkAppForm _ headName _ _) _) =
    case decideNlgSite Nothing d of
      Just (NlgOnHeadInput input, nlg) ->
        ( Map.singleton (getUnique headName)
            (unslot nlg, fmap unslot (getOriginal input ^. annoOf % annNlgAlts))
        , Set.singleton (getUnique input)
        )
      _ -> mempty

  fixup :: Resolved -> Resolved
  fixup r
    | Just (nlg, alts) <- Map.lookup (getUnique r) promote =
        overBothNames (annoOf %~ setNlgs nlg alts) r
    | Set.member (getUnique r) suppress =
        overBothNames (annoOf %~ (annNlg .~ Nothing) . (annNlgAlts .~ [])) r
    | otherwise = r

-- | Apply a function to both 'Name's a 'Resolved' carries.
--
-- 'traverseResolved' deliberately reaches only the ACTUAL name, and that is not
-- enough here: 'Linearize' for 'Resolved' consults the ORIGINAL at a referring
-- occurrence, and the original is a copy taken when the reference was resolved,
-- so writing to one and not the other leaves the two disagreeing about the same
-- name.
overBothNames :: (Name -> Name) -> Resolved -> Resolved
overBothNames f = \ case
  Def u n        -> Def u (f n)
  Ref r u o      -> Ref (f r) u (f o)
  OutOfScope u n -> OutOfScope u (f n)

-- | Clear the annotations on a sentence's own @%slot%@ references.
--
-- A slot names an input, and the sentence being moved is the one that input was
-- carrying, so without this the slot would expand to the whole sentence again.
unslot :: Nlg -> Nlg
unslot = \ case
  MkResolvedNlg a t fs -> MkResolvedNlg a t (fmap (fmap (overBothNames clear)) fs)
  other                -> other
 where
  clear = annoOf %~ (annNlg .~ Nothing) . (annNlgAlts .~ [])

-- | The payload of @l4 nlg@ and of @jl4-test@\'s @\<stem\>.nlg.golden@.
--
-- __Shared rather than duplicated, deliberately.__ Both used to spell this
-- expression out, with a comment in @L4.Cli.Nlg@ saying that changing one
-- without the other breaks the command and the golden at once. Two rewrites now
-- have to be applied in the right order as well, which is more than a comment
-- should be asked to hold.
--
-- Order matters: 'promoteHeadInputNlg' moves a herald and its other-language
-- renderings together, and 'selectLanguage' then picks from where they now are.
--
-- Then the splice: a heralded call in a directive reads as its sentence with
-- the arguments in the @%slots%@ ('substituteNlgDirective'). The table is built
-- over the dependencies too — prepared the same way, since a rule a directive
-- calls can live in an imported module and its sentence is read from there.
linearizeDirectives :: Maybe LangTag -> Module Resolved -> [Module Resolved] -> [Text]
linearizeDirectives mlang mod'' deps'' = fst (linearizeDirectivesIn mlang mod'' deps'')

-- | 'linearizeDirectives', plus the English frame words the language's
-- phrasebook had no entry for ('localize'). The set is empty for 'Nothing',
-- for @en@, and for a language with no phrasebook at all.
--
-- The misses are counted on the directive BEFORE the splice. A spliced call
-- is 'Inert' text by the time the line is rendered, so its arguments' frame
-- words cannot be seen there. The unspliced directive has the same frame
-- words, plus the "with", "and" and "where" of the calls themselves, and those
-- are all in every phrasebook, so the two sets of misses are equal.
linearizeDirectivesIn :: Maybe LangTag -> Module Resolved -> [Module Resolved] -> ([Text], Set.Set Text)
linearizeDirectivesIn mlang mod'' deps'' =
  ( fmap (fst . simpleLinearizerIn mlang . substituteNlgDirectiveIn mlang heralds) directives
  , foldMap (snd . simpleLinearizerIn mlang) directives
  )
 where
  prepare    = selectLanguage mlang . promoteHeadInputNlg
  mod'       = prepare mod''
  heralds    = nlgFnInfo (mod' : map prepare deps'')
  directives = toListOf (gplate @(Directive Resolved)) mod'

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
      , frame "and"
      , lin e2
      ]
    Or _ e1 e2 -> hcat
      [ lin e1
      , frame "or"
      , lin e2
      ]
    RAnd _ e1 e2 -> hcat
      [ lin e1
      , frame "and"
      , lin e2
      ]
    ROr _ e1 e2 -> hcat
      [ lin e1
      , frame "or"
      , lin e2
      ]
    Implies _ e1 e2 -> hcat
      [ lin e1
      , frame "implies"
      , lin e2
      ]
    Equals _ e1 e2 -> hcat
      [ lin e1
      , frame "is"
      , frame "equal"
      , frame "to"
      , lin e2
      ]
    Not _ e -> hcat
      [ frame "not"
      , lin e
      ]
    Plus _ e1 e2 -> hcat
      [ frame "the"
      , frame "sum"
      , frame "of"
      , lin e1
      , frame "and"
      , lin e2
      ]
    Minus _ e1 e2 -> hcat
      [ frame "the"
      , frame "difference"
      , frame "between"
      , lin e2
      , frame "and"
      , lin e1
      ]
    Times _ e1 e2 -> hcat
      [ frame "the"
      , frame "product"
      , frame "of"
      , lin e1
      , frame "and"
      , lin e2
      ]
    DividedBy _ e1 e2 -> hcat
      [ frame "the"
      , frame "result"
      , frame "of"
      , frame "dividing"
      , lin e1
      , frame "by"
      , lin e2
      ]
    Modulo _ e1 e2 -> hcat
      [ frame "the"
      , frame "result"
      , frame "of"
      , lin e1
      , frame "modulo"
      , lin e2
      ]
    Cons _ e1 e2 -> hcat
      [ lin e1
      , frame "followed"
      , frame "by"
      , lin e2
      ]
    Leq _ e1 e2 -> hcat
      [ lin e1
      , frame "is"
      , frame "at"
      , frame "most"
      , lin e2
      ]
    Geq _ e1 e2 -> hcat
      [ lin e1
      , frame "is"
      , frame "at"
      , frame "least"
      , lin e2
      ]
    Lt _ e1 e2 -> hcat
      [ lin e1
      , frame "is"
      , frame "less"
      , frame "than"
      , lin e2
      ]
    Gt _ e1 e2 -> hcat
      [ lin e1
      , frame "is"
      , frame "greater"
      , frame "than"
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
      , frame "then"
      , lin e
      ]
    App _ n es
      | Just (d, m, y) <- daydateLiteral n es -> hcat [ text d, frame m, text y ]
    App _ n es -> hcat $
      [ linearize n
      ]
      <> ifNonEmpty es
            [ frame "with"
            , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin es)
            ]
    AppNamed _ n es _order -> hcat
      [ linearize n
      , frame "where"
      , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin es)
      ]
    IfThenElse _ cond then' else' -> hcat
      [ frame "if"
      , lin cond
      , frame "then"
      , lin then'
      , frame "else"
      , lin else'
      ]
    MultiWayIf _ conds o -> hcat $
      foldMap (\(MkGuardedExpr _ c f) -> ["if", lin c, "then", lin f]) conds
      <> ["otherwise", lin o ]
    Regulative _ (MkDeonton _ subj (MkAction _ modal rule mprovided) mopens mdeadline mjoin mfollowup mlest) -> hcat $
      linSubject subj
      <> [ frame (deonticModalText modal)
         , lin rule
         ]
      <> maybe [] (\ provided -> [ frame "provided that", lin provided ]) mprovided
      <> maybe [] linOpening mopens
      <> maybe [] (linClosing (isJust mopens)) mdeadline
      <> maybe [] linJoin mjoin
      <> maybe [] (\ followup -> [ frame "hence",  lin followup ]) mfollowup
      <> maybe [] (\ lest -> [ frame "lest",  lin lest ]) mlest
      where
        linJoin j = case j of
          -- follows 'L4.Print' (uponEachWords); R-Q1 RULED 2026-09-07
          JoinOnce _ th mdue ->
            [ frame "once" ]
            <> (case th of AllHave _ -> [ frame "all", frame "have" ])
            <> linJoinDue mdue
          JoinUpon _ _ mdue -> [ frame "upon", frame "each" ] <> linJoinDue mdue
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
            [ frame "within", lin d ]
            <> maybe (if afterOpening then [ frame "of", frame "that" ] else [])
                     (\ a -> [ frame "of" ] <> linAnchor a) ma
          MkBefore _ e -> [ frame "before", lin e ]
        -- @after d [of anchor]@ — the window's opening edge
        linOpening (MkOpening _ d ma) =
          [ frame "after", lin d ]
          <> maybe [] (\ a -> [ frame "of" ] <> linAnchor a) ma
        linAnchor = \ case
          AnchorJoin _     -> [ frame "the", frame "join" ]
          AnchorDeadline _ -> [ frame "the", frame "deadline" ]
          AnchorArming _   -> [ frame "the", frame "arming" ]
          AnchorAt _ e     -> [ lin e ]
        linSubject = \ case
          Party _ party -> [ frame "party", lin party ]
          Every _ mCast v mRoll mFilter ->
            [ frame "every" ]
            -- Resolved can't use 'lin', as it doesn't have an 'Anno'
            <> maybe [] (\ c -> [ linearize c ]) mCast
            <> [ linearize v ]
            <> maybe [] (\ r -> [ frame "in", lin r ]) mRoll
            <> maybe [] (\ f -> [ frame "who", lin f ]) mFilter
    Consider _ e br -> hcat
      [ frame "consider"
      , frame "the"
      , frame "case"
      , frame "distinctions"
      , frame "of"
      , lin e
      , punctuate ":"
      , enumerate (punctuate ".") (punctuate ".") (fmap lin br)
      ]
    Lit _ l -> lin l
    -- Glued, not punctuated: 'punctuate' carries a trailing space and 'hcat'
    -- adds another, which printed @50 %  and …@.
    Percent _ l -> lin l <> frame "%"
    List _ es -> hcat
      [ frame "list"
      , frame "of"
      , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin es)
      ]
    Where _ e lcl -> hcat
      [ lin e
      , frame "where"
      , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin lcl)
      ]
    LetIn _ lcl e -> hcat
      [ frame "let"
      , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin lcl)
      , frame "in"
      , lin e
      ]
    Event _ ev -> lin ev
    Fetch _ e -> hcat [ frame "fetch", lin e ]
    Env _ e -> hcat [ frame "environment variable", lin e ]
    Post _ e1 e2 e3 -> hcat [ frame "post", lin e1, lin e2, lin e3 ]
    Record _ mParty cell val isOfficial mHence -> hcat ([ frame (if isOfficial then "commit" else "record") ] <> maybe [] (\p -> [ lin p, frame "'s" ]) mParty <> [ lin cell, frame "is", lin val ] <> maybe [] (\k -> [ frame "hence", lin k ]) mHence)
    ReadCell _ mParty isOfficial mode cell -> hcat ([ frame "recall" ] <> (case mode of RecallAll -> [ frame "all" ]; RecallLast -> []) <> (if isOfficial then [ frame "official's" ] else []) <> maybe [] (\p -> [ lin p, frame "'s" ]) mParty <> [ lin cell ])
    Concat _ exprs -> hcat [ frame "concatenate", enumerate (punctuate ",") (spaced $ frame "and") (fmap lin exprs) ]
    AsString _ e -> hcat [ lin e, frame "as", frame "string" ]
    Breach _ mParty mReason -> hcat $
      [ frame "breach" ]
      <> maybe [] (\p -> [ frame "by", lin p ]) mParty
      <> maybe [] (\r -> [ frame "because", lin r ]) mReason
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
      [ "executing contract", lin e, "at", lin t, "with the following events:" ]
      <> map lin es
    Assert _ e -> linearize e
    AssertRefused _ e _mmsg -> hcat [ "the following must refuse:", lin e ]


instance Linearize (NamedExpr Resolved) where
  linearize = \ case
    MkNamedExpr _ n e -> hcat
      [ linearize n
      , frame "is"
      , lin e
      ]

-- | daydate's date constructors, applied to three whole-number literals, read
-- as the date they name: @YMD 2025 7 16@ and @Date 16 7 2025@ both become
-- @16 July 2025@ rather than @`YMD` with 2025, 7 and 16@.
--
-- Deliberately narrow, and every miss falls through to the ordinary call:
--
--   * the name must be daydate's own, in either spelling (@`YMD` AKA `Year
--     month day`@, @`Date` AKA `Days to date`@ — the defining name at a call
--     site is the alias), and its definition must come from @daydate.l4@, so a
--     user's own @YMD@ is not touched;
--   * all three arguments must be whole-number literals, since a variable has
--     no date to print;
--   * the date must be VALID. @Date@ rolls an out-of-range component forward
--     and @YMD@ refuses it; printing either as a calendar date would state
--     something the rule does not, so neither is rendered.
--
-- The month name is a frame word ('LinFrame'), so a phrasebook translates it.
daydateLiteral :: Resolved -> [Expr Resolved] -> Maybe (Text, Text, Text)
daydateLiteral r args@[_, _, _] = do
  guard (fromDaydate r)
  order <- lookup (unqualifiedRawNameToText (rawName (getActual r))) orders
  [a, b, c] <- traverse wholeLit args
  let (y, m, d) = order (a, b, c)
  day <- fromGregorianValid y (fromInteger m) (fromInteger d)
  -- The month is a frame word, so a phrasebook can name it; the day and
  -- the year are figures in every language we render.
  let fmt f = Text.pack (TimeFormat.formatTime TimeFormat.defaultTimeLocale f day)
  pure (fmt "%-d", fmt "%B", fmt "%Y")
 where
  ymd (y, m, d) = (y, m, d)
  dmy (d, m, y) = (y, m, d)
  orders =
    [ ("YMD", ymd), ("Year month day", ymd)
    , ("Date", dmy), ("Days to date", dmy) ]
  wholeLit = \ case
    Lit _ (NumericLit _ q) | denominator q == 1 -> Just (numerator q)
    _ -> Nothing
  fromDaydate x =
    "daydate.l4" `Text.isSuffixOf` (fromNormalizedUri (getUnique x).moduleUri).getUri
daydateLiteral _ _ = Nothing

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
      [ frame "when"
      , lin pat
      , frame "then"
      , lin e
      ]
    MkBranch _ (Otherwise _) e -> hcat
      [ frame "in"
      , frame "any"
      , frame "other"
      , frame "case"
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
      , frame "has"
      , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin pats)
      ]
    PatCons _ start rest -> hcat
      [ lin start
      , frame "is"
      , frame "followed"
      , frame "by"
      , lin rest
      ]
    PatExpr _ expr -> hcat [ "is", "exactly", lin expr ]
    PatLit _ lit -> hcat [ lin lit ]

instance Linearize (GivenSig Resolved) where
  linearize = \ case
    MkGivenSig _ args -> hcat
      [ frame "given"
      , enumerate (punctuate ",") (spaced $ frame "and") (fmap lin args)
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
    MkInvalidNlg _ -> frame "(internal error)"
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
-- LSP document webview and @l4 export blawx@ all rendered the backslash literally.
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

-- | A frame word: one the linearizer supplies, as opposed to the author's
-- text. A string literal in an instance body is one of these too, through
-- 'IsString'. See 'LinFrame'.
frame :: Text -> LinTree
frame t = MkLinTree
  [ MkLinToken
    { type' = LinFrame
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

-- ----------------------------------------------------------------------------
-- Splicing a call's arguments into its herald
-- ----------------------------------------------------------------------------

-- | For every function that carries an @\@nlg@ annotation: its authored
-- sentence and its GIVEN parameter uniques (in order), so a call's positional
-- arguments can be matched to the sentence's @%parameter%@ slots.
--
-- Keyed by @(function name, arity)@ rather than 'Unique': a call site in the
-- importing module and the definition in a dependency module do not share
-- 'Unique's (each module is resolved independently), so a unique-based key
-- would never match across an @IMPORT@. The inner @%param%@ substitution stays
-- 'Unique'-based — those refs are self-consistent within the defining module.
type NlgFnInfo = Map.Map (Text, Int) (Nlg, [Unique])

nlgFnInfo :: [Module Resolved] -> NlgFnInfo
nlgFnInfo mods = Map.fromList
  [ ((resolvedText headName, length appArgs), (nlg, [ getUnique a | a <- appArgs ]))
    -- Value parameters are the appform arguments, not the GIVEN names: a
    -- polymorphic function (@GIVEN a IS A TYPE@) lists its type parameter in
    -- GIVEN but never in the appform, so keying arity off GIVEN would not match
    -- the call's positional argument count.
  | m <- mods
  , d@(MkDecide _ _ (MkAppForm _ headName appArgs _) _) <- foldTopLevelDecides (: []) m
  , Just nlg <- [ decideNlg Nothing d ]
  ]

-- | Replace a call to an @\@nlg@-annotated function with its authored sentence,
-- splicing the call's arguments into the @%parameter%@ slots. Bottom-up, so
-- nested @\@nlg@ calls inside the arguments are expanded first.
--
-- __An argument the herald never mentions is appended, never dropped.__ A
-- herald with no slot for one of its parameters used to swallow that argument
-- silently — @l4 render@ printed the sentence and the value was gone, exit 0.
-- The unmentioned arguments now follow the sentence as @with a, b and c@, which
-- is what the bare linearizer says for every call, so a herald that covers all
-- its parameters reads as prose and one that covers none degrades to exactly
-- what it read as before.
substituteNlgCalls :: NlgFnInfo -> Expr Resolved -> Expr Resolved
substituteNlgCalls = substituteNlgCallsIn Nothing

-- | 'substituteNlgCalls' with the arguments, and the "with" and "and" of any
-- appended ones, rendered with a language's frame words. The herald's own
-- text is the author's and is never touched.
substituteNlgCallsIn :: Maybe LangTag -> NlgFnInfo -> Expr Resolved -> Expr Resolved
substituteNlgCallsIn mlang info = transformOf (gplate @(Expr Resolved)) $ \case
  App ann n args
    | Just (nlg, params) <- Map.lookup (resolvedText n, length args) info
    , length params == length args ->
        let bound    = zip params args
            leftover = [ a | (p, a) <- bound, p `notElem` nlgRefs nlg ]
            sentence = renderNlgWithIn mlang (Map.fromList bound) nlg
            -- Joined as the bare linearizer joins arguments ("a, b and c",
            -- no serial comma), so one line does not carry both styles.
            rest     = case map (fst . simpleLinearizerIn mlang) leftover of
              []  -> ""
              [x] -> " " <> word "with" <> " " <> x
              xs  -> " " <> word "with" <> " " <> Text.intercalate ", " (init xs)
                       <> " " <> prefix (word "and") <> last xs
        in Inert ann (sentence <> rest) InertCtxNone
  e -> e
 where
  word w = fromMaybe w (Map.lookup [w] =<< phrasebookFor =<< mlang)
  -- A maqaf-final rendering is written against the next word.
  prefix w | Text.takeEnd 1 w == Text.singleton maqaf = w
           | otherwise                                = w <> " "

-- | The same splice, applied to every expression a directive carries — the
-- subject of an @#EVAL@ or @#ASSERT@, and the contract, time and events of a
-- @#TRACE@. This is what makes @l4 nlg@ and the @.nlg.golden@ producer read a
-- heralded call as its sentence rather than as the bare name followed by
-- @with@ and the arguments.
substituteNlgDirective :: NlgFnInfo -> Directive Resolved -> Directive Resolved
substituteNlgDirective = substituteNlgDirectiveIn Nothing

substituteNlgDirectiveIn :: Maybe LangTag -> NlgFnInfo -> Directive Resolved -> Directive Resolved
substituteNlgDirectiveIn mlang info = over (gplate @(Expr Resolved)) (substituteNlgCallsIn mlang info)

-- | The parameters a herald actually refers to.
nlgRefs :: Nlg -> [Unique]
nlgRefs = \case
  MkResolvedNlg _ _ frags -> [ getUnique r | MkNlgRef _ r <- frags ]
  _                       -> []

-- | Render an @\@nlg@ annotation, substituting each parameter reference with the
-- corresponding call argument.
renderNlgWith :: Map.Map Unique (Expr Resolved) -> Nlg -> Text
renderNlgWith = renderNlgWithIn Nothing

renderNlgWithIn :: Maybe LangTag -> Map.Map Unique (Expr Resolved) -> Nlg -> Text
renderNlgWithIn mlang argMap = \case
  MkResolvedNlg _ _ frags -> normalizeWs (Text.concat (map frag frags))
  other                 -> simpleLinearizer other
 where
  -- Escapes decode HERE, not in the lexer: the annotation token carries
  -- @\%@ / @\]@ verbatim so exactprint can re-emit it. Without this call
  -- @10\%and\%20@ reaches text, html, json, akn and the LSP webview with the
  -- backslash still in it.
  frag (MkNlgText _ t) = unescapeNlgText t
  -- An unsubstituted reference (definition view, or a name with no matching
  -- argument) renders as the bare parameter name — NOT via 'simpleLinearizer',
  -- which would re-expand that parameter's own @\@nlg@ and recurse when the
  -- annotation is attached to a parameter it also references.
  frag (MkNlgRef _ r)  = case Map.lookup (getUnique r) argMap of
    Just a  -> fst (simpleLinearizerIn mlang a)
    Nothing -> resolvedText r

resolvedText :: Resolved -> Text
resolvedText = nameToText . getActual

normalizeWs :: Text -> Text
normalizeWs t0 =
  let t1 = Text.replace "it 's" "its" t0
      t2 = Text.replace " 's"  "'s"  t1
      t3 = Text.replace " %"   "%"   t2
      t4 = Text.replace " ,"   ","   t3
      t5 = Text.replace " ."   "."   t4
      t6 = Text.replace " :"   ":"   t5
      t7 = Text.replace " ;"   ";"   t6
      -- Collapse empty list slots that produce ",," / ", ,".
      t8 = Text.replace ", ," "," (Text.replace ",," "," t7)
      t9 = Text.replace "is equal to" "is" t8
  in Text.unwords (Text.words t9)

oxford :: Text -> [Text] -> Text
oxford conj = \case
  []     -> ""
  [a]    -> a
  [a, b] -> a <> " " <> conj <> " " <> b
  xs     -> Text.intercalate ", " (init xs) <> ", " <> conj <> " " <> last xs
