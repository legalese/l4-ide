-- | Presentation of the 'L4.Export.Document' IR: plain text, a styled
-- standalone HTML document, and Akoma Ntoso XML.
--
-- This lives in @jl4-core@ so the @l4 render@ CLI and the @jl4-lsp@ server
-- share one rendering implementation, and both default to the same document:
-- sections and clauses numbered. Subclause @(a)(b)@ lettering is always on.
module L4.Export.Render
  ( RenderConfig (..)
  , defaultRenderConfig
  , isRtlLang
  , rtlLangTags
  , rtlScripts
  , ltrScripts
  , scriptSubtag
  , aknLanguage
  , renderHtml
  , renderText
  , renderAkn
  ) where

import Base

import qualified Base.Text as Text
import Data.Char (isAsciiLower, isAsciiUpper, toUpper)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Export.Document
import L4.Lexer (LangTag (..))
import L4.Syntax (defaultModuleLang)

-- | Rendering knobs. Section headings and top-level clauses are numbered by
-- default, as in the Render tab, and there is no table of contents; 'docLang'
-- defaults to 'defaultModuleLang'.
data RenderConfig = MkRenderConfig
  { numberSections :: !Bool
  , numberClauses  :: !Bool
  , toc            :: !Bool   -- ^ prepend a linked table of contents (HTML)
  , docLang        :: !LangTag
    -- ^ The language this document is being rendered in. The caller decides it;
    -- 'L4.Cli.Render' uses @--lang@ if given (and if the module renders
    -- anything in it), else the module's own @\@lang@, else
    -- 'defaultModuleLang'.
    --
    -- Two writers report it, each in its own vocabulary: HTML as
    -- @<html lang="…">@ plus a @dir@ when 'isRtlLang' says so, and Akoma Ntoso
    -- as the language component of the Expression-level FRBR URIs
    -- ('aknLanguage'). @text@, @json@ and @plan@ do not read it.
  }
  deriving stock (Eq, Show, Generic)

defaultRenderConfig :: RenderConfig
defaultRenderConfig =
  MkRenderConfig
    { numberSections = True
    , numberClauses = True
    , toc = False
    , docLang = defaultModuleLang
    }

-- | The language subtags whose default script runs right to left.
--
-- One explicit list rather than a lookup into a locale database: the whole
-- point of @dir@ is that a browser's bidi heuristics are not enough, and a
-- short list we can read is worth more here than a complete one we cannot.
-- Extend it when a corpus needs one — that is a one-line change with a test
-- next to it, not a dependency.
--
-- __This table answers the question only when the tag names no script.__ It is
-- keyed on the PRIMARY subtag, so @he-IL@ and @ar-EG@ are covered by @he@ and
-- @ar@ without an entry each — but @he-Latn@ is Hebrew romanised in Latin
-- script and runs left to right, and @az-Arab@ is Azerbaijani in Arabic script
-- and runs right to left, and neither can be read off a primary subtag at all.
-- So 'isRtlLang' consults 'scriptSubtag' FIRST, and only falls through to this
-- table when the tag carries no script (or one neither script table knows).
-- Comparison is case-insensitive: BCP 47 says subtags are case-insensitive, and
-- @--lang HE@ is a thing a user types.
rtlLangTags :: Set.Set Text
rtlLangTags = Set.fromList
  [ "he"   -- Hebrew
  , "iw"   -- Hebrew, the deprecated ISO 639-1 code older locale stacks still emit
  , "ar"   -- Arabic
  , "fa"   -- Persian
  , "prs"  -- Dari (Afghan Persian)
  , "ur"   -- Urdu
  , "yi"   -- Yiddish
  , "ji"   -- Yiddish, deprecated code (as @iw@ is for Hebrew)
  , "ps"   -- Pashto
  , "ckb"  -- Central Kurdish (Sorani)
  , "sd"   -- Sindhi (Arabic script by default; @sd-Deva@ is not)
  , "ug"   -- Uyghur
  , "ks"   -- Kashmiri (Arabic script by default)
  , "dv"   -- Divehi / Dhivehi
  , "arc"  -- Aramaic
  , "syr"  -- Syriac
  , "nqo"  -- N'Ko
  ]

-- | The script subtags whose writing direction is right to left.
--
-- The script is the part of a language tag that actually decides direction, so
-- this table outranks 'rtlLangTags': a tag that names a script is answered from
-- here whatever its language is.
rtlScripts :: Set.Set Text
rtlScripts = Set.fromList
  [ "arab"  -- Arabic — and so @az-Arab@, @pa-Arab@, @ku-Arab@
  , "aran"  -- Nastaliq (a style of Arabic script; @ur-Aran@ is a real CLDR tag)
  , "hebr"  -- Hebrew
  , "syrc"  -- Syriac
  , "thaa"  -- Thaana (Divehi)
  , "nkoo"  -- N'Ko
  , "adlm"  -- Adlam (Fulani)
  , "rohg"  -- Hanifi Rohingya
  ]

-- | Script subtags whose writing direction is left to right.
--
-- Deliberately short, and short for a reason: this table only ever decides a
-- case that 'rtlLangTags' would otherwise get WRONG — an RTL language written
-- in a non-RTL script. In practice that is romanisation, so @Latn@ is the
-- entry that does the work (@he-Latn@, @ar-Latn@, @fa-Latn@); @Cyrl@ covers the
-- Central Asian spellings. Every other script here is LTR anyway by its
-- language's primary subtag, and is listed only so a reader can see that the
-- omission of a script is not a claim about it.
--
-- A script in NEITHER table falls through to 'rtlLangTags', which is the
-- behaviour this code had before script subtags were read at all.
ltrScripts :: Set.Set Text
ltrScripts = Set.fromList
  [ "latn", "cyrl", "grek", "armn", "geor"
  , "hans", "hant", "hani", "jpan", "kana", "hira", "kore", "hang"
  , "deva", "beng", "guru", "gujr", "taml", "telu", "knda", "mlym", "sinh"
  , "thai", "laoo", "mymr", "khmr", "tibt", "ethi"
  ]

-- | The script subtag of a BCP 47 language tag, lowercased, if it carries one.
--
-- __Four letters, all alphabetic, is what identifies a script__ — BCP 47 gives
-- every other subtag a shape that cannot collide with that: a region is two
-- letters or three digits, an extended language subtag three letters, a variant
-- five to eight alphanumerics or four starting with a DIGIT. So the position of
-- the subtag does not have to be tracked; @zh-yue-Hant-HK@ answers @hant@ by
-- the same rule as @az-Arab@.
--
-- Scanning stops at a one-character subtag: @-u-@, @-t-@, @-x-@ and friends are
-- singletons introducing an extension or private use, and a four-letter subtag
-- after one of those is that extension's payload, not a script.
scriptSubtag :: Text -> Maybe Text
scriptSubtag tag =
  listToMaybe
    [ Text.toLower s
    | s <- takeWhile ((/= 1) . Text.length) (drop 1 (Text.splitOn "-" tag))
    , Text.length s == 4
    , Text.all (\ c -> isAsciiLower c || isAsciiUpper c) s
    ]

-- | Does this language tag need @dir="rtl"@?
--
-- The script decides when the tag names one; otherwise the language does. See
-- 'rtlLangTags' for why that order and not the other.
isRtlLang :: LangTag -> Bool
isRtlLang (MkLangTag tag) =
  case scriptSubtag tag of
    Just script
      | script `Set.member` rtlScripts -> True
      | script `Set.member` ltrScripts -> False
    _ -> Text.toLower (Text.takeWhile (/= '-') tag) `Set.member` rtlLangTags

-- ----------------------------------------------------------------------------
-- Prose: the words of a rule, chosen once
-- ----------------------------------------------------------------------------

-- | A stretch of a sentence, tagged with what it is so that each writer can mark
-- it up in its own way. A writer decides how a 'Flow' looks, never what it says,
-- which is what keeps @l4 render --format text@, the HTML of the Render tab and
-- Akoma Ntoso saying the same thing.
data Span
  = Word Text       -- ^ a word of the sentence frame
  | Phrase Text     -- ^ text from the rule, whose backticked names are terms
  | Key Text        -- ^ a structural word: "If", "Otherwise"
  | Condition Text  -- ^ the condition of a branch
  | Modal Text      -- ^ must, may, shall, must not
  | Glue Text       -- ^ punctuation, set against what comes before it

-- | A sentence or a list entry: what it says, what hangs off it, and the local
-- definitions that go with it.
data Flow = MkFlow
  { flowLead  :: ![Span]
  , flowBody  :: !Body
  , flowWhere :: ![(Text, Flow)]
  }

data Body
  = NoBody
  | Items !Sep ![Flow]
  | Fields ![(Text, Text)]
  | Grid ![Text] ![[Flow]]

-- | How the entries of a list follow one another.
data Sep
  = Joined Text   -- ^ a semicolon each, with this word before the last entry
  | Sentences     -- ^ each entry is a sentence of its own

said :: [Span] -> Flow
said spans = MkFlow spans NoBody []

prefixed :: [Span] -> Flow -> Flow
prefixed spans f = f { flowLead = spans <> f.flowLead }

-- | The flow of one block: its heading is printed by the writer, and this is
-- everything after it.
blockFlow :: Block -> Flow
blockFlow b = finish "." (ruleFlow (isJust b.blockSentence || readsAsClause b.blockHeading) b.blockConnector b.blockBody)

-- | What a block is called: its sentence, or else its name. Either way it opens
-- the block, so it takes a capital.
blockTitle :: Block -> Text
blockTitle b = capitalize (maybe (displayName b.blockHeading) displayVars b.blockSentence)

-- | A rule's body, opened by the connector. The connector is chosen by
-- "L4.Export.Document" from the rule's type and the shape of its body, and the
-- frame is fitted to what follows, so that a rule never reads "holds if as
-- follows" or "is determined by, depending on".
ruleFlow :: Bool -> Text -> Clause -> Flow
ruleFlow titledAsClause conn clause = case clause of
  CLeaf "" -> said [Word opening]
  CLeaf t  -> said [Word opening, Phrase t]
  CDeontic{} -> prefixed [Word opening] inner
  CChain lead _ -> inner { flowLead = [Word opening, Word lead] }
  CIf{} -> inner { flowLead = [Word ifFrame] }
  CCases s _ -> inner { flowLead = [Word casesFrame, Phrase s] }
  CWhere body defs -> (ruleFlow titledAsClause conn body) { flowWhere = map whereDef defs }
  _ -> inner { flowLead = [Word opening] }
 where
  inner = clauseFlow clause
  -- A rule named as a clause reads straight on: "the public task basis applies
  -- if". A rule named as a noun needs the verb: "eligibility holds if".
  clausal = conn == "holds if" && titledAsClause
  opening = if clausal then "if" else conn
  ifFrame
    | conn == "holds if" = if clausal then "as follows" else "holds as follows"
    | conn == "means"    = "is"
    | otherwise          = conn
  casesFrame
    | conn == "holds if" = if clausal then "depending on" else "holds depending on"
    | otherwise          = "depends on"

whereDef :: (Text, Text, Clause) -> (Text, Flow)
whereDef (h, c, cl) = (h, finish "." (ruleFlow (readsAsClause h) c cl))

-- | A clause inside a rule, where no connector leads into it.
clauseFlow :: Clause -> Flow
clauseFlow = \case
  CLeaf t    -> said [Phrase t]
  CFields fs -> MkFlow [] (Fields fs) []
  CAll cs    -> MkFlow [Word "all of the following"] (Items (Joined "and") (map clauseFlow cs)) []
  CAny cs    -> MkFlow [Word "any of the following"] (Items (Joined "or") (map clauseFlow cs)) []
  CIf chain els -> MkFlow []
    (Items (Joined "") (zipWith branch [0 ..] chain <> maybe [] (pure . otherwiseFlow) els)) []
  CCases s brs -> MkFlow [Word "depending on", Phrase s] (Items (Joined "") (map (caseFlow s) brs)) []
  CChain lead items ->
    MkFlow [Word lead] (Items (Joined (chainWord lead)) (map (said . pure . Phrase) items)) []
  CDeontic p m a due prov h l -> deonticFlow p m a due prov h l
  CTable cols rows -> MkFlow [] (Grid cols (map (map clauseFlow) rows)) []
  CWhere inner defs -> (clauseFlow inner) { flowWhere = map whereDef defs }
 where
  branch :: Int -> (Text, Clause) -> Flow
  branch i (cond, then_) =
    prefixed [Key (if i == 0 then "If" else "Otherwise, if"), Condition cond, Glue ":"] (clauseFlow then_)
  otherwiseFlow = prefixed [Key "Otherwise", Glue ":"] . clauseFlow
  caseFlow s (pat, cl)
    | pat == "otherwise" = otherwiseFlow cl
    | otherwise = prefixed [Key "If", Condition (subject s <> " " <> pat), Glue ":"] (clauseFlow cl)
  -- Each case names what it tests, unless that is too long to repeat on every
  -- line; the lead-in has named it, and "it" then reads clearly.
  subject s = if Text.length (stripBackticks s) <= 36 then s else "it"
  chainWord lead
    | any (`Text.isPrefixOf` lead) ["the sum", "the product", "a list"] = "and"
    | otherwise = ""

-- | An obligation, with what follows it. What @HENCE@ and @LEST@ mean depends on
-- the modal ('consequenceWords').
deonticFlow :: Text -> Text -> Text -> Maybe Text -> Maybe Clause -> Maybe Clause -> Maybe Clause -> Flow
deonticFlow party modal act due prov hence lest =
  case catMaybes [fmap (onHence,) hence, fmap (onLest,) lest] of
    [] | null longProviso -> said base
    [(lab, c)] | isSentence (clauseFlow c), null longProviso ->
      said (base <> [Glue ".", Word lab] <> (clauseFlow c).flowLead)
    conseq -> MkFlow base (Items Sentences (longProviso <> [ prefixed [Word lab] (clauseFlow c) | (lab, c) <- conseq ])) []
 where
  base = [Phrase party, Modal modal, Phrase act]
           <> maybe [] (pure . Phrase) due
           <> shortProviso
  -- A proviso that is a single condition stays in the sentence. One with its own
  -- structure is an entry of the list, so that its structure can be seen.
  (shortProviso, longProviso) = case prov of
    Nothing -> ([], [])
    Just c
      | isSentence (clauseFlow c) -> ([Glue ",", Word "provided that"] <> (clauseFlow c).flowLead, [])
      | otherwise -> ([], [prefixed [Word "Provided that"] (clauseFlow c)])
  (onHence, onLest) = consequenceWords modal
  isSentence f = case f.flowBody of
    NoBody -> null f.flowWhere
    _      -> False

-- | What leads into @HENCE@ and @LEST@. An obligation continues with @HENCE@ once
-- it is met and with @LEST@ if it is not. A permission continues with @HENCE@
-- whether or not it is used. A prohibition is the other way round: @LEST@ is what
-- follows doing the thing.
consequenceWords :: Text -> (Text, Text)
consequenceWords = \case
  "may"      -> ("Whether or not that is done,", "Failing that,")
  "must not" -> ("If that is not done,", "If that is done,")
  _          -> ("Once that is done,", "Failing that,")

-- | Punctuate a flow, ending it with this text. A list's lead ends in a colon and
-- its last entry carries the end of the whole; every other entry ends in a
-- semicolon, with the list's connective before the last entry, as in drafting:
-- "(a) …; (b) …; and (c) …."
finish :: Text -> Flow -> Flow
finish end f = case f.flowBody of
  NoBody -> f { flowLead = ending end f.flowLead }
  Items sep items -> f
    { flowLead = opens f.flowLead
    , flowBody = Items sep (closeItems sep end items)
    }
  Fields _ -> f { flowLead = opens f.flowLead }
  Grid _ _ -> f { flowLead = opens f.flowLead }
 where
  ending e spans
    | Text.null e || null spans = spans
    | otherwise                 = spans <> [Glue e]
  opens spans
    | null spans                              = spans
    | Glue ":" <- List.last spans             = spans
    | otherwise                               = spans <> [Glue ":"]

closeItems :: Sep -> Text -> [Flow] -> [Flow]
closeItems sep end items = zipWith close (reverse [0 .. length items - 1]) items
 where
  close :: Int -> Flow -> Flow
  close i it = case sep of
    Sentences -> finish "." it
    Joined _ | i == 0 -> finish end it
    Joined w | i == 1, not (Text.null w) -> finish ("; " <> w) it
    Joined _ -> finish ";" it

-- | Lay out spans as text, each through a writer's own function.
joinSpans :: (Span -> Text) -> [Span] -> Text
joinSpans f = List.foldl' step ""
 where
  step acc = \case
    Glue g -> acc <> g
    s | Text.null acc -> f s
      | otherwise     -> acc <> " " <> f s

-- | Does this heading read as a clause, so that "if" can follow it directly?
readsAsClause :: Text -> Bool
readsAsClause h = any (`Set.member` clauseVerbs) (Text.words (Text.toLower (displayName h)))

clauseVerbs :: Set.Set Text
clauseVerbs = Set.fromList
  [ "is", "are", "was", "were", "has", "have", "had", "may", "must", "shall", "can"
  , "will", "does", "applies", "apply", "holds", "exists", "exist", "meets", "qualifies"
  , "qualify", "counts", "covers", "falls", "owes", "satisfies", "satisfy", "contains"
  , "requires", "require", "resides", "reside", "owns", "pays", "receives", "provides"
  , "permits", "allows", "includes", "exceeds" ]

-- ----------------------------------------------------------------------------
-- Plain-text rendering
-- ----------------------------------------------------------------------------

renderText :: RenderConfig -> Document -> Text
renderText cfg doc =
  Text.intercalate "\n"
    ( doc.docTitle
    : Text.replicate (Text.length doc.docTitle) "="
    : ""
    : concatMap (sectionText 1) doc.docSections
    )
 where
  sectionText depth sec =
    let childDepth = if Text.null sec.sectionNumber then depth else depth + 1
    in sectionHeadingText depth sec
         <> concatMap groupText sec.sectionGroups
         <> concatMap (sectionText childDepth) sec.sectionSubs

  sectionHeadingText depth sec =
    case sectionLabel cfg.numberSections depth sec of
      Nothing -> []
      Just h  -> ["", h, ""]

  groupText g =
    maybe [] (\l -> [l <> ":", ""]) g.groupLabel
      <> concat (zipWith blockText [1 ..] g.groupBlocks)

  blockText n b =
    let num = Text.pack (show (n :: Int))
        marker = if cfg.numberClauses then num <> ". " else "• "
        title = blockTitle b
    in case b.blockRenderedAs of
      RenderedReference forced ->
        [ marker <> title
            <> "  (" <> fromMaybe "referenced" b.blockCitation <> ")"
            <> (if forced then " [kept: still required]" else "")
        , ""
        ]
      RenderedInline ->
        let f = blockFlow b
        in (marker <> title <> " " <> leadText f)
             : map ("    " <>) (bodyLines 0 f <> sourceLines b)
             <> [""]

  sourceLines b = [ "Source: " <> s | s <- b.blockSources ]

  leadText f = joinSpans spanText f.flowLead

  spanText = \case
    Word t      -> t
    Phrase t    -> displayVars t
    Key t       -> t
    Condition t -> displayVars t
    Modal t     -> t
    Glue t      -> t

  bodyLines :: Int -> Flow -> [Text]
  bodyLines depth f = contentLines depth f.flowBody <> whereLines f.flowWhere

  contentLines depth = \case
    NoBody -> []
    Items _ items -> concat (zipWith (itemLines depth) [0 ..] items)
    Fields fs -> map fieldLine fs
    Grid cols rows -> tableLines cols rows

  itemLines depth i f =
    let mark = listMarker depth i <> " "
    in case leadText f of
         ""   -> mark : map ("    " <>) (bodyLines (depth + 1) f)
         lead -> (mark <> lead) : map ("    " <>) (bodyLines (depth + 1) f)

  whereLines [] = []
  whereLines defs = "where:" : concatMap whereLine defs

  whereLine (h, f) =
    ("- " <> capitalize (displayName h) <> " " <> leadText f)
      : map ("    " <>) (bodyLines 0 f)

  -- A plain-text table with padded columns; complex cells collapse to one line.
  tableLines cols rows =
    let cellText c = Text.unwords (Text.words (Text.intercalate " " (leadText (finish "" c) : bodyLines 0 (finish "" c))))
        textRows = [ map cellText row | row <- rows ]
        widths = [ maximum (Text.length h : [ Text.length (r !! i) | r <- textRows, i < length r ])
                 | (i, h) <- zip [0 ..] cols ]
        pad w t = t <> Text.replicate (w - Text.length t) " "
        renderRow cells = "| " <> Text.intercalate " | " (zipWith pad widths cells) <> " |"
        sep = "|" <> Text.intercalate "|" (map (\w -> Text.replicate (w + 2) "-") widths) <> "|"
    in renderRow cols : sep : map renderRow textRows

  fieldLine (k, v) = "- " <> displayVars k <> (if Text.null v then "" else " — " <> displayVars v)

-- | The marker of a list entry at a depth, matching the HTML rendering's counters.
listMarker :: Int -> Int -> Text
listMarker depth i = "(" <> label <> ")"
 where
  label = case depth `mod` 4 of
    0 -> alpha i
    1 -> Text.toLower (roman (i + 1))
    2 -> Text.pack (show (i + 1))
    _ -> Text.toUpper (alpha i)
  alpha n
    | n < 26    = Text.singleton (toEnum (fromEnum 'a' + n))
    | otherwise = alpha (n `div` 26 - 1) <> alpha (n `mod` 26)

roman :: Int -> Text
roman = go [ (1000,"M"),(900,"CM"),(500,"D"),(400,"CD"),(100,"C"),(90,"XC")
           , (50,"L"),(40,"XL"),(10,"X"),(9,"IX"),(5,"V"),(4,"IV"),(1,"I") ]
 where
  go _ 0 = ""
  go [] _ = ""
  go table@((v, s) : rest) n
    | n >= v    = s <> go table (n - v)
    | otherwise = go rest n

-- ----------------------------------------------------------------------------
-- HTML rendering
-- ----------------------------------------------------------------------------

renderHtml :: RenderConfig -> Document -> Text
renderHtml cfg doc =
  Text.intercalate "\n"
    [ "<!DOCTYPE html>"
    , "<html" <> langAttrs <> ">"
    , "<head>"
    , "<meta charset=\"utf-8\">"
    , "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
    , "<title>" <> esc doc.docTitle <> "</title>"
    , "<style>" <> css <> "</style>"
    , "</head>"
    , "<body>"
    , "<article class=\"l4-doc" <> (if cfg.numberClauses then " num-clauses" else "") <> "\">"
    , "<h1>" <> esc doc.docTitle <> "</h1>"
    , if cfg.toc then tocHtml cfg doc.docSections else ""
    , Text.concat (map (sectionHtml 1) doc.docSections)
    , "</article>"
    , "</body>"
    , "</html>"
    ]
 where
  -- @lang@ always; @dir@ only for a right-to-left language. An explicit
  -- @dir="ltr"@ for everything else would be correct but is not what the rest
  -- of the world writes, and the HTML default is already @ltr@ — so the
  -- attribute appearing at all is the signal that this document is RTL.
  langAttrs =
    let MkLangTag tag = cfg.docLang
    in " lang=\"" <> esc tag <> "\""
         <> (if isRtlLang cfg.docLang then " dir=\"rtl\"" else "")

  linkMap = collectLinks doc

  sectionHtml depth sec =
    let childDepth = if Text.null sec.sectionNumber then depth else depth + 1
    in headingHtml depth sec
         <> Text.concat (map groupHtml sec.sectionGroups)
         <> Text.concat (map (sectionHtml childDepth) sec.sectionSubs)

  headingHtml depth sec =
    case sectionLabel cfg.numberSections depth sec of
      Nothing -> ""
      Just h  ->
        let tag = "h" <> Text.pack (show (min 4 (depth + 1)))
        in "<" <> tag <> " id=\"" <> sectionAnchor sec <> "\" class=\"section\">"
             <> esc h <> "</" <> tag <> ">\n"

  groupHtml g =
    maybe "" (\l -> "<p class=\"group-label\">" <> esc l <> "</p>\n") g.groupLabel
      <> "<ol class=\"clauses\">\n"
      <> Text.concat (map blockHtml g.groupBlocks)
      <> "</ol>\n"

  blockHtml b =
    let kindClass = case b.blockKind of
          RuleUnit       -> "rule"
          TypeUnit       -> "type"
          AssumptionUnit -> "assumption"
        anchor = " id=\"def_" <> anchorOf b <> "\""
    in case b.blockRenderedAs of
      RenderedInline ->
        "<li class=\"clause " <> kindClass <> "\"" <> anchor <> ">"
          <> termHtml b <> " " <> flowHtml (blockFlow b)
          <> Text.concat [ "<div class=\"source\">" <> esc s <> "</div>" | s <- b.blockSources ]
          <> "</li>\n"
      RenderedReference forced ->
        "<li class=\"clause reference " <> kindClass <> "\"" <> anchor <> ">"
          <> "<span class=\"term\">" <> esc (capitalize (displayName b.blockHeading)) <> "</span> — "
          <> "<em class=\"citation\">" <> esc (fromMaybe "referenced" b.blockCitation) <> "</em>"
          <> (if forced then " <span class=\"forced\">(retained — still required)</span>" else "")
          <> "</li>\n"

  termHtml b =
    let inner = esc (blockTitle b)
        quoted = if b.blockKind == TypeUnit then "“" <> inner <> "”" else inner
    in "<span class=\"term\">" <> quoted <> "</span>"

  flowHtml f =
    joinSpans spanHtml f.flowLead <> contentHtml f.flowBody <> whereHtml f.flowWhere

  spanHtml = \case
    Word t      -> esc t
    Phrase t    -> "<span class=\"prose\">" <> lk t <> "</span>"
    Key t       -> "<span class=\"kw\">" <> esc t <> "</span>"
    Condition t -> "<span class=\"cond\">" <> lk t <> "</span>"
    Modal t     -> "<strong>" <> esc t <> "</strong>"
    Glue t      -> esc t

  contentHtml = \case
    NoBody -> ""
    Items _ items ->
      "\n<ol class=\"tree\">\n"
        <> Text.concat (map (\f -> "<li>" <> flowHtml f <> "</li>\n") items)
        <> "</ol>\n"
    Fields fs -> fieldsHtml fs
    Grid cols rows -> tableHtml cols rows

  whereHtml [] = ""
  whereHtml defs =
    " <span class=\"where-label\">where:</span>"
      <> "\n<ol class=\"where-defs\">\n"
      <> Text.concat (map whereDefLi defs)
      <> "</ol>"
   where
    whereDefLi (h, f) =
      "<li><span class=\"term\">" <> esc (capitalize (displayName h)) <> "</span> "
        <> flowHtml f <> "</li>\n"

  tableHtml cols rows =
    "<table class=\"l4-table\">\n<thead><tr>"
      <> Text.concat (map (\c -> "<th>" <> esc (displayName c) <> "</th>") cols)
      <> "</tr></thead>\n<tbody>\n"
      <> Text.concat (map rowHtml rows)
      <> "</tbody></table>\n"
   where
    rowHtml cells =
      "<tr>" <> Text.concat (map (\c -> "<td>" <> flowHtml (finish "" c) <> "</td>") cells) <> "</tr>\n"

  -- Options and data fields are a reference table for the reader. The lettered
  -- list stays with the conditions, where a letter is something a lawyer cites.
  fieldsHtml fs
    | all (Text.null . snd) fs =
        "\n<ul class=\"options\">\n"
          <> Text.concat (map (\(k, _) -> "<li>" <> lk k <> "</li>\n") fs)
          <> "</ul>\n"
    | otherwise =
        "\n<table class=\"l4-dict\"><tbody>\n"
          <> Text.concat (map fieldRow fs)
          <> "</tbody></table>\n"
   where
    fieldRow (k, v) =
      "<tr><td class=\"field\">" <> lk k <> "</td><td><span class=\"prose\">" <> lk v <> "</span></td></tr>\n"

  lk = proseHtml linkMap

-- ----------------------------------------------------------------------------
-- Akoma Ntoso (AKN/XML) rendering
-- ----------------------------------------------------------------------------

-- | The code an Akoma Ntoso Expression-level FRBR URI wants for a language.
--
-- AKN identifies an expression by @\/akn\/doc\/main\/\<lang\>\@\<version\>@, and
-- @\<lang\>@ there is an ISO 639-2 code (the /terminological/ variant where the
-- two differ — @deu@, not @ger@), not a BCP 47 tag. So the document's language
-- is translated on the way out rather than pasted in: @he@ becomes @heb@.
--
-- Keyed on the primary subtag, because that is the part AKN has a place for —
-- @he-IL@ is still the Hebrew expression. __A subtag this table does not know is
-- emitted as it stands__, lowercased: a two-letter code where a three-letter one
-- belongs is wrong in the same way the old hard-coded @eng@ was wrong, but it at
-- least says which language was meant, and it keeps this table a short readable
-- list rather than a vendored copy of the ISO register.
aknLanguage :: LangTag -> Text
aknLanguage (MkLangTag tag) =
  Map.findWithDefault primary primary iso639_2T
 where
  primary = Text.toLower (Text.takeWhile (/= '-') tag)

  -- Every language this repo's corpus renders in, plus the rest of
  -- 'rtlLangTags' so the two tables cannot disagree about a language we
  -- deliberately support the direction of.
  iso639_2T :: Map.Map Text Text
  iso639_2T = Map.fromList
    [ ("en", "eng"), ("he", "heb"), ("iw", "heb"), ("ar", "ara")
    , ("fa", "fas"), ("ur", "urd"), ("yi", "yid"), ("ji", "yid")
    , ("ps", "pus"), ("sd", "snd"), ("ug", "uig"), ("ks", "kas")
    , ("dv", "div"), ("de", "deu"), ("fr", "fra"), ("ms", "msa")
    , ("zh", "zho"), ("es", "spa"), ("id", "ind"), ("ta", "tam")
    -- `arc`, `syr`, `nqo`, `ckb`, `prs` are already three letters and are
    -- their own ISO 639-2/-3 codes, so the fall-through is right for them.
    ]

renderAkn :: RenderConfig -> Document -> Text
renderAkn cfg doc =
  Text.concat
    [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    , "<akomaNtoso xmlns=\"http://docs.oasis-open.org/legaldocml/ns/akn/3.0\">\n"
    , "<act name=\"act\">\n"
    , aknMeta
    , "<preface><longTitle><p>" <> xesc doc.docTitle <> "</p></longTitle></preface>\n"
    , "<body>\n"
    , Text.concat (map sectionAkn doc.docSections)
    , "</body>\n</act>\n</akomaNtoso>\n"
    ]
 where
  -- The EXPRESSION is where a language belongs in FRBR: the Work is the act,
  -- the Expression is the act in one language, the Manifestation is that
  -- expression as a file. This literal used to be `eng` whatever was rendered,
  -- which labelled a Hebrew act an English expression — the AKN sibling of the
  -- `<html lang="en">` defect (smucclaw/l4-ide#970).
  aknLang = aknLanguage cfg.docLang

  aknMeta =
    "<meta><identification source=\"#l4\">"
      <> frbr "FRBRWork" "/akn/doc/main" "/akn/doc"
      <> frbr "FRBRExpression" ("/akn/doc/main/" <> aknLang <> "@") ("/akn/doc/" <> aknLang <> "@")
      <> frbr "FRBRManifestation" ("/akn/doc/main/" <> aknLang <> "@.xml") ("/akn/doc/" <> aknLang <> "@.xml")
      <> "</identification></meta>\n"
  frbr el this uri =
    "<" <> el <> "><FRBRthis value=\"" <> this <> "\"/><FRBRuri value=\"" <> uri
      <> "\"/><FRBRdate date=\"1970-01-01\" name=\"generation\"/><FRBRauthor href=\"#l4\"/></" <> el <> ">"

  sectionAkn sec
    | Text.null sec.sectionNumber, sec.sectionHeading == Nothing =
        Text.concat (map groupAkn sec.sectionGroups)
          <> Text.concat (map sectionAkn sec.sectionSubs)
    | otherwise =
        "<section eId=\"sec_" <> idSafe sec.sectionNumber <> "\">"
          <> (if Text.null sec.sectionNumber then "" else "<num>" <> xesc sec.sectionNumber <> "</num>")
          <> maybe "" (\h -> "<heading>" <> xesc h <> "</heading>") sec.sectionHeading
          <> Text.concat (map groupAkn sec.sectionGroups)
          <> Text.concat (map sectionAkn sec.sectionSubs)
          <> "</section>\n"

  groupAkn g =
    maybe "" (\l -> "<hcontainer name=\"crossHeading\"><heading>" <> xesc l <> "</heading></hcontainer>") g.groupLabel
      <> Text.concat (map blockAkn g.groupBlocks)

  blockAkn b =
    "<paragraph eId=\"para_" <> anchorOf b <> "\">"
      <> "<heading>" <> xesc (blockTitle b) <> "</heading>"
      <> "<content>" <> bodyAkn b <> "</content>"
      <> "</paragraph>\n"

  bodyAkn b = case b.blockRenderedAs of
    RenderedReference _ -> p (xesc (fromMaybe "referenced" b.blockCitation))
    RenderedInline -> flowAkn (blockFlow b) <> Text.concat [ p ("Source: " <> xesc s) | s <- b.blockSources ]

  flowAkn f =
    (if null f.flowLead then "" else p (joinSpans spanAkn f.flowLead))
      <> contentAkn f.flowBody
      <> whereAkn f.flowWhere

  spanAkn = \case
    Word t      -> xesc t
    Phrase t    -> xt t
    Key t       -> xesc t
    Condition t -> xt t
    Modal t     -> xesc t
    Glue t      -> xesc t

  contentAkn = \case
    NoBody -> ""
    Items _ items -> blockList (map (item . flowAkn) items)
    Fields fs -> blockList [ item (p (xt k <> if Text.null v then "" else " — " <> xt v)) | (k, v) <- fs ]
    Grid cols rows -> tableAkn cols rows

  whereAkn [] = ""
  whereAkn defs = p "where:" <> blockList (map whereItem defs)
   where
    whereItem (h, f) = item (p (xt (capitalize (displayName h))) <> flowAkn f)

  tableAkn cols rows =
    "<table>"
      <> "<tr>" <> Text.concat (map (\c -> "<th>" <> p (xesc (displayName c)) <> "</th>") cols) <> "</tr>"
      <> Text.concat
           (map (\row -> "<tr>" <> Text.concat (map (\c -> "<td>" <> flowAkn (finish "" c) <> "</td>") row) <> "</tr>") rows)
      <> "</table>"

  blockList items = "<blockList>" <> Text.concat items <> "</blockList>"
  item content = "<item>" <> content <> "</item>"
  p content = "<p>" <> content <> "</p>"

-- ----------------------------------------------------------------------------
-- Shared helpers
-- ----------------------------------------------------------------------------

sectionLabel :: Bool -> Int -> DocSection -> Maybe Text
sectionLabel numbered depth sec =
  let num = sec.sectionNumber
      marker
        | not numbered   = ""
        | Text.null num  = ""
        | depth <= 1     = "§ " <> num <> "  "
        | otherwise      = num <> "  "
      body = Text.stripEnd (marker <> fromMaybe "" sec.sectionHeading)
  in if Text.null body then Nothing else Just body

capitalize :: Text -> Text
capitalize t = case Text.uncons t of
  Just (c, rest) -> Text.cons (toUpper c) rest
  Nothing        -> t

stripBackticks :: Text -> Text
stripBackticks = Text.filter (/= '`')

-- | A name as a reader sees it. The values L4 writes in capitals read as words,
-- and a run-together name is spaced. A mixfix pattern is left alone: its
-- underscores mark where the arguments go.
displayName :: Text -> Text
displayName = \case
  "TRUE"    -> "true"
  "FALSE"   -> "false"
  "NOTHING" -> "no value"
  "EMPTY"   -> "an empty list"
  n | "_" `elem` Text.words n -> n
    | otherwise -> spaceCamel (Text.map (\c -> if c == '_' then ' ' else c) n)

-- | Every backticked name in a text, as a reader sees it, without the backticks.
displayVars :: Text -> Text
displayVars t = case Text.splitOn "`" t of
  []       -> ""
  x : rest -> x <> go rest
 where
  go (name : after : more) = displayName name <> after <> go more
  go rest                  = Text.concat rest

xt :: Text -> Text
xt = xesc . displayVars

xesc :: Text -> Text
xesc =
    Text.replace "<" "&lt;"
  . Text.replace ">" "&gt;"
  . Text.replace "&" "&amp;"

idSafe :: Text -> Text
idSafe = Text.map (\c -> if c `elem` (" :/.#" :: String) then '_' else c)

-- | A short, stable, path-free anchor for a block: @<sort>_<n>_<module>@.
anchorOf :: Block -> Text
anchorOf b =
  let parts   = Text.splitOn ":" b.blockId
      sortIdx = Text.intercalate "_" (take 2 parts)
      uriPart = Text.intercalate ":" (drop 2 parts)
      lastSeg = if Text.null uriPart then "" else List.last (Text.splitOn "/" uriPart)
      base    = fromMaybe lastSeg (Text.stripSuffix ".l4" lastSeg)
  in idSafe (sortIdx <> (if Text.null base then "" else "_" <> base))

-- | Variable spans (the linearizer's @`backticks`@) become links to the
-- defining clause when the name is a defined term — with a @title@ tooltip
-- showing the definition — otherwise plain italic.
proseHtml :: Map.Map Text (Text, Text) -> Text -> Text
proseHtml linkMap t =
  case Text.splitOn "`" t of
    []         -> ""
    [x]        -> esc x
    (x : rest) -> esc x <> wrap rest
 where
  wrap [] = ""
  wrap [x] = esc x
  wrap (varSeg : afterSeg : more) = renderVar varSeg <> esc afterSeg <> wrap more
  renderVar name = case Map.lookup name linkMap of
    Just (anchor, tip) ->
      "<a class=\"ref\" href=\"#def_" <> anchor <> "\" title=\"" <> esc tip <> "\">"
        <> esc (displayName name) <> "</a>"
    Nothing -> "<span class=\"var\">" <> esc (displayName name) <> "</span>"

-- | Each defined term -> (anchor of its clause, a short definition for the
-- hover tooltip).
collectLinks :: Document -> Map.Map Text (Text, Text)
collectLinks doc = Map.fromList (concatMap sec doc.docSections)
 where
  sec s = concatMap grp s.sectionGroups <> concatMap sec s.sectionSubs
  grp g = map (\b -> (b.blockHeading, (anchorOf b, blockTip b))) g.groupBlocks

blockTip :: Block -> Text
blockTip b =
  Text.strip (Text.take 200 (displayVars (b.blockConnector <> " " <> clauseSummary b.blockBody)))

-- | A one-line gist of a clause for tooltips.
clauseSummary :: Clause -> Text
clauseSummary = \case
  CLeaf t        -> t
  CFields fs     -> "a record with " <> Text.intercalate ", " (map fst fs)
  CAll _         -> "all of several conditions"
  CAny _         -> "any of several conditions"
  CIf _ _        -> "determined by conditions"
  CCases s _     -> "depending on " <> s
  CChain lead items -> lead <> " " <> Text.pack (show (length items)) <> " terms"
  CDeontic p m a _ _ _ _ -> p <> " " <> m <> " " <> a
  CTable cols _  -> "a table of " <> Text.intercalate ", " cols
  CWhere body _  -> clauseSummary body

-- | A stable anchor for a section heading (from its number, else its heading).
sectionAnchor :: DocSection -> Text
sectionAnchor sec =
  "sec_" <> if Text.null sec.sectionNumber
              then idSafe (fromMaybe "" sec.sectionHeading)
              else idSafe sec.sectionNumber

-- | A linked, nested table of contents from the section hierarchy.
tocHtml :: RenderConfig -> [DocSection] -> Text
tocHtml cfg secs =
  let body = level 1 secs
  in if Text.null body
       then ""
       else "<nav class=\"toc\"><div class=\"toc-title\">Contents</div>" <> body <> "</nav>"
 where
  level depth ss =
    let entries = Text.concat (map (entry depth) ss)
    in if Text.null entries then "" else "<ul>" <> entries <> "</ul>"
  entry depth s =
    let childDepth = if Text.null s.sectionNumber then depth else depth + 1
        subs = level childDepth s.sectionSubs
    in case sectionLabel cfg.numberSections depth s of
      Nothing -> subs   -- the unnumbered document-body root: splice children up
      Just h  ->
        "<li><a href=\"#" <> sectionAnchor s <> "\">" <> esc h <> "</a>" <> subs <> "</li>"

esc :: Text -> Text
esc =
    Text.replace "<" "&lt;"
  . Text.replace ">" "&gt;"
  . Text.replace "\"" "&quot;"
  . Text.replace "&" "&amp;"

-- | Styling that mimics a printed legal contract.
--
-- Every direction-sensitive rule is written with LOGICAL properties
-- (@padding-inline-start@, @inset-inline-start@, @text-align:start@) rather
-- than @left@\/@right@, so the whole page mirrors when the document carries
-- @dir="rtl"@ (see 'isRtlLang'). In a left-to-right document each one is
-- exactly the physical property it replaced, so this changes nothing there —
-- and without it a Hebrew document would run right to left while its clause
-- numbers and indents stayed on the left, which looks like a layout bug
-- rather than like a translation.
css :: Text
css = Text.intercalate "\n"
  [ "  :root { --ink:#000; --muted:#3a3a3a; }"
  , "  * { box-sizing:border-box; }"
  , "  body { margin:0; background:#fff; color:var(--ink);"
  , "         font:15px/1.6 'Times New Roman', Times, serif; }"
  , "  .l4-doc { width:100%; max-width:1024px; margin:0 auto; padding:56px 64px;"
  , "            background:#fff; }"
  , "  h1 { text-align:center; font-size:1.65rem; font-weight:700; line-height:1.2;"
  , "       text-transform:uppercase; letter-spacing:.02em; margin:0 0 2.2rem; }"
  , "  .section { font-weight:700; margin:2.1rem 0 .9rem; line-height:1.3; }"
  , "  h2.section { font-size:1.3rem; }"
  , "  h3.section { font-size:1.12rem; }"
  , "  h4.section { font-size:1.02rem; }"
  , "  .group-label { font-weight:700; font-style:italic; margin:1.25rem 0 .55rem; }"
  , "  .term { font-weight:700; }"
  , "  .prose .var { font-style:italic; }"
  , "  li.reference { color:var(--muted); }"
  , "  .citation { font-style:italic; }"
  , "  .source { font-size:.85em; font-style:italic; color:var(--muted); margin-top:.15rem; }"
  , "  .forced { font-size:.85em; color:#8a2b2b; font-style:normal; }"
  -- Table of contents.
  , "  nav.toc { margin:0 0 2rem; padding:1rem 1.25rem; background:#fafafa;"
  , "            border:1px solid #e6e6e6; }"
  , "  nav.toc .toc-title { font-weight:700; text-transform:uppercase;"
  , "       letter-spacing:.08em; font-size:.8rem; color:var(--muted); margin-bottom:.5rem; }"
  , "  nav.toc ul { margin:0; padding-inline-start:1.2rem; list-style:none; }"
  , "  nav.toc > ul { padding-inline-start:0; }"
  , "  nav.toc li { margin:.15rem 0; }"
  , "  nav.toc a { color:inherit; text-decoration:none;"
  , "       border-bottom:1px dotted color-mix(in srgb, currentColor 45%, transparent); }"
  , "  nav.toc a:hover { border-bottom-style:solid; }"
  , "  ol.clauses { margin:0 0 1rem; padding:0; list-style:none; counter-reset:clause; }"
  , "  ol.clauses > li.clause { position:relative; margin:0 0 1rem; }"
  , "  ol.tree { margin:.35rem 0; margin-inline-start:1.6rem; padding:0;"
  , "            list-style:none; counter-reset:t; }"
  , "  ol.tree > li { position:relative; margin:.28rem 0; padding-inline-start:1.9rem; }"
  , "  ol.tree > li::before {"
  , "       counter-increment:t; content:'(' counter(t, lower-alpha) ')';"
  , "       position:absolute; inset-inline-start:0; top:0; width:1.5rem;"
  , "       color:var(--muted); }"
  , "  ol.tree ol.tree > li::before { content:'(' counter(t, lower-roman) ')'; }"
  , "  ol.tree ol.tree ol.tree > li::before { content:'(' counter(t, decimal) ')'; }"
  , "  ol.tree ol.tree ol.tree ol.tree > li::before { content:'(' counter(t, upper-alpha) ')'; }"
  , "  .kw { font-weight:700; }"
  , "  .cond { font-style:italic; color:#333; }"
  , "  a.ref { color:inherit; text-decoration:none;"
  , "          border-bottom:1px dotted color-mix(in srgb, currentColor 45%, transparent); }"
  , "  a.ref:hover { border-bottom-style:solid; }"
  , "  .field { font-weight:600; }"
  -- Data fields and enum options: a reference table, not a lettered clause.
  , "  table.l4-dict { border-collapse:collapse; margin:.3rem 0 .5rem; margin-inline-start:1.6rem; }"
  , "  table.l4-dict td { padding:.1rem 0; padding-inline-end:1.1rem; vertical-align:top; }"
  , "  ul.options { margin:.3rem 0 .5rem; margin-inline-start:1.6rem; padding-inline-start:1rem; }"
  , "  ul.options > li { margin:.1rem 0; }"
  -- Local WHERE / LET definitions attached to a rule.
  , "  .where-label { font-style:italic; color:var(--muted); margin-inline-start:.15rem; }"
  , "  ol.where-defs { margin:.25rem 0 .35rem; margin-inline-start:1.6rem;"
  , "                  padding-inline-start:0; list-style:none; }"
  , "  ol.where-defs > li { margin:.2rem 0; }"
  -- Tables for list-of-record definitions.
  , "  table.l4-table { border-collapse:collapse; margin:.6rem 0; width:100%;"
  , "                   font-size:.95em; }"
  , "  table.l4-table th, table.l4-table td {"
  , "       border:1px solid #cfcfcf; padding:.3rem .55rem; text-align:start;"
  , "       vertical-align:top; }"
  , "  table.l4-table th { background:#f0f0f0; font-weight:700; }"
  , "  table.l4-table tbody tr:nth-child(even) { background:#fafafa; }"
  , "  table.l4-table table.l4-table { margin:.2rem 0; }"
  , "  .num-clauses ol.clauses > li.clause { padding-inline-start:2.4rem; }"
  , "  .num-clauses ol.clauses > li.clause::before {"
  , "       counter-increment:clause; content:counter(clause) '.';"
  , "       position:absolute; inset-inline-start:0; top:0; width:1.9rem; text-align:end;"
  , "       font-variant-numeric:tabular-nums; }"
  -- Tighten the page margins on narrow viewports (e.g. the IDE preview
  -- pane) so the content isn't crowded by generous desktop padding.
  , "  @media (max-width:640px) {"
  , "    .l4-doc { padding:24px 20px 40px; }"
  , "    ol.tree { margin-inline-start:.4rem; }"
  , "    table.l4-dict, ul.options, ol.where-defs { margin-inline-start:.4rem; }"
  , "  }"
  , "  @page { size:A4; margin:25mm 22mm; }"
  , "  @media print {"
  , "    body { background:#fff; }"
  , "    .l4-doc { width:auto; margin:0; padding:0; border:0; box-shadow:none; }"
  , "    ol.clauses > li.clause { break-inside:avoid; }"
  , "    h1, .section { break-after:avoid; }"
  , "  }"
  ]
