-- | The derivation lint for override phrases (SUBJECT-TO-NOTWITHSTANDING-SPEC
-- §12.1, ruling D2).
--
-- A provision that opens "Subject to section 6" yields to section 6, and an
-- encoding that honours the words has to /call/ the decision that encodes
-- section 6. The corpus already does so: ``s 8(3) …`` conjoins
-- ``NOT (`s 6(1) …` g)`` (§12.1's witness). So the override edge is already
-- data in the call graph, and a decision whose prose promises an edge its body
-- does not make is a /missing conjunct/ — the bug class §12.2 records.
--
-- This module reads the prose a decision carries, finds the override phrases
-- that name a provision, and checks each against the call graph. It adds no
-- syntax and changes no semantics: a module that type-checks is judged, never
-- altered.
--
-- = Three sources of prose
--
-- §12.1 names two: the @\@ref@ citations and the identifier names. This module
-- reads a third, the string literals in the decision's body ('SrcText'), because
-- the inert-style encodings quote the provision in the body and hang the logic
-- off it (@"Subject to section 6,"@ in §12.1's own witness). Over the canon
-- mirror (@jl4\/examples\/canon@, 61 files, measured 2026-10-30), the lint finds
-- 11 mentions; 6 of them are read from the body text and nowhere else. Reading
-- the third source is an extension of the ruling, not part of it.
--
-- It does not read comments. Over the commons checkout (5,974 files, a looser
-- regular expression than this module's matcher, 2026-10-30) a phrase followed
-- by a provision number sits on 1,650 comment lines, against 11 @\@ref@ lines,
-- 37 string-literal lines and 288 lines inside a backticked name (definitions
-- and the places that call them). The commons style keeps the statute's
-- words in comments, where they bind nothing, so most of its phrases are out of
-- this lint's reach by construction.
--
-- = What is a mention, and what is not
--
-- A phrase counts only when a provision follows it: @subject to section 6@,
-- @despite subsection (8)@, @notwithstanding anything in section 18(g)@. The
-- bare words are common English with no provision behind them (@subject to
-- tax@, @subject to the process of the court@, @despite reasonable efforts@),
-- and a lint that fired on them would be switched off in a day.
--
-- Three further shapes are recognised and set aside rather than judged:
--
-- * /open-class/ targets (@notwithstanding any other provision@, @subject to
--   the provisions of this Act@): §12.1 records that no static edge reaches
--   them;
-- * provisions of another instrument (@section 15(d) of the Exchange Act@):
--   the callee, if any, is in another module;
-- * ranges (@sections 6 to 8@): which of the provisions the author meant to
--   call is not for a lint to guess.
--
-- = Direction
--
-- @Subject to X@ looks forward: the provision yields to X, so its own body
-- should call X. @Notwithstanding X@ (and @despite X@) looks back: the provision
-- prevails over X, and the edge may sit on either side — X's body can call the
-- prevailing provision (the two-layer defeat idiom), or the prevailing
-- provision can consult X, or a third decision can call both. Only the first
-- direction is demanded of the speaker's own body ('Yields'); the second is
-- satisfied by any of the three ('Prevails').
module L4.Lint.Override
  ( -- * Reading override phrases out of prose
    Phrase (..)
  , Direction (..)
  , phraseDirection
  , phraseText
  , Unit (..)
  , Target (..)
  , renderTarget
  , Mention (..)
  , MentionClass (..)
  , findMentions
    -- * Provision keys
  , ProvKey (..)
  , provKeyOfName
  , renderKey
  , keyMatches
    -- * The lint
  , Source (..)
  , sourceText
  , How (..)
  , Outcome (..)
  , outcomeText
  , isFinding
  , Finding (..)
  , lintModule
  ) where

import Base
import Data.Char (isAlphaNum, isDigit, isUpper)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Optics (gplate, toListOf, (^.))

import L4.Annotation (Anno_ (..), getAnno)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax

----------------------------------------------------------------------------
-- Phrases and targets
----------------------------------------------------------------------------

-- | The four override phrases of the ruling.
data Phrase
  = PhSubjectTo
  | PhNotwithstanding
  | PhDespite
  | PhExcept
    -- ^ @except as provided in@, @except under@, @except pursuant to@: only
    -- with one of those leads, because a bare @except@ is everywhere.
  deriving stock (Show, Eq, Ord, Enum, Bounded)

-- | Which way the edge is expected to run (spec §1.2).
data Direction
  = Yields
    -- ^ "I yield to that provision": the speaker's own body should reach it.
  | Prevails
    -- ^ "I override that provision": either side may carry the edge.
  deriving stock (Show, Eq)

phraseDirection :: Phrase -> Direction
phraseDirection = \case
  PhSubjectTo       -> Yields
  PhExcept          -> Yields
  PhNotwithstanding -> Prevails
  PhDespite         -> Prevails

phraseText :: Phrase -> Text
phraseText = \case
  PhSubjectTo       -> "subject to"
  PhNotwithstanding -> "notwithstanding"
  PhDespite         -> "despite"
  PhExcept          -> "except"

-- | The kind of provision a reference names. A decision named @s 6(1) …@ and
-- one named @reg 6@ are different provisions; @section@ and @subsection@ are
-- one kind (a subsection is a part of a section).
data Unit
  = USection
  | URegulation
  | URule
  | UArticle
  | UClause
  | USchedule
  | UParagraph
    -- ^ resolved only for @paragraph (N)@ in an article, regulation, rule or
    -- clause, where it is that provision's own subdivision; in a section a
    -- paragraph is relative to a subsection the lint does not track
  deriving stock (Show, Eq, Ord)

-- | One provision named after an override phrase.
data Target = MkTarget
  { unit     :: Unit
  , noun     :: Text
    -- ^ the noun as the prose wrote it, lower-cased: @section@, @s@, @subsection@
  , number   :: Maybe Text
    -- ^ the provision number, normalised ('Nothing' for a relative reference
    -- such as @subsection (8)@)
  , path     :: [Text]
    -- ^ the bracket groups, brackets removed: @6(1)(a)@ is @["1","a"]@
  , relative :: Bool
  }
  deriving stock (Show, Eq)

-- | The reference as the prose wrote it, normalised: @section 6(1)@.
renderTarget :: Target -> Text
renderTarget t =
  t.noun <> " " <> fromMaybe "" t.number <> Text.concat [ "(" <> g <> ")" | g <- t.path ]

data MentionClass
  = Linted [Target]
    -- ^ a phrase followed by provisions of this instrument
  | External [Target]
    -- ^ ... of another one (@section 15(d) of the Exchange Act@)
  | Ranged [Target]
    -- ^ ... as a range (@sections 6 to 8@); the first end only
  | OpenClass
    -- ^ ... of no provision in particular (@notwithstanding any other provision@)
  | NoProvision
    -- ^ the phrase, followed by something that is not a provision (@subject to tax@)
  deriving stock (Show, Eq)

data Mention = MkMention
  { phrase  :: Phrase
  , excerpt :: Text
    -- ^ the words after the phrase, for a message
  , klass   :: MentionClass
  }
  deriving stock (Show, Eq)

----------------------------------------------------------------------------
-- Tokens
----------------------------------------------------------------------------

-- | A whitespace-separated word, with the punctuation peeled off it.
data Chunk = MkChunk
  { word :: !Text
  , stop :: !Bool
    -- ^ the word ended a clause: it was followed by a comma, semicolon, colon,
    -- full stop or closing bracket, or it is a dash
  , hard :: !Bool
    -- ^ ... and the stop was more than a comma: a list of provisions does not
    -- run on past it
  }

chunksOf :: Text -> [Chunk]
chunksOf = concatMap chunk . Text.words

chunk :: Text -> [Chunk]
chunk raw
  | Text.null core = []
  | core `elem` ["—", "–", "-", "--", "―"] = [MkChunk "—" True True]
  | "§" `Text.isPrefixOf` core, Text.length core > 1 =
      let (sigils, num) = Text.span (== '§') core
      in [MkChunk sigils False False, MkChunk num stp hrd]
  | Just (nm, num) <- dottedNoun core = [MkChunk nm False False, MkChunk num stp hrd]
  | otherwise = [MkChunk core stp hrd]
 where
  w1 = Text.dropWhile (`elem` ("\"“”‘’'«" :: String)) raw
  w2 = if "(" `Text.isPrefixOf` w1 && not (startsGroup w1) then Text.drop 1 w1 else w1
  (core, stp, hrd) = peelTrailing w2

  -- @s.8@ and @ss.8@: the full stop belongs to the noun.
  dottedNoun w
    | Text.toLower nm `elem` ["s", "ss"]
    , Just num <- Text.stripPrefix "." rest
    , Just (d, _) <- Text.uncons num
    , isDigit d
    = Just (nm, num)
    | otherwise = Nothing
   where
    (nm, rest) = Text.break (== '.') w

startsGroup :: Text -> Bool
startsGroup w = case parseGroupAt w of
  Just _  -> True
  Nothing -> False

-- | Peel trailing punctuation, remembering whether any of it ended a clause and
-- whether any of that was more than a comma.
peelTrailing :: Text -> (Text, Bool, Bool)
peelTrailing = go False False
 where
  go stp hrd t = case Text.unsnoc t of
    Just (i, l)
      | l == ','                                         -> go True hrd i
      | l `elem` (";:" :: String)                        -> go True True i
      | l == '.', not (isNounWord i)                     -> go True True i
      | l `elem` ("\"”’'»" :: String)                    -> go stp hrd i
      | l == ')', Text.count ")" t > Text.count "(" t    -> go True True i
    _ -> (t, stp, hrd)

lw :: Chunk -> Text
lw = Text.toLower . (.word)

----------------------------------------------------------------------------
-- Nouns and provision numbers
----------------------------------------------------------------------------

-- | How a noun anchors the reference that follows it.
data NounKind = Plain | Sub | Para
  deriving stock (Eq)

nounTable :: [(Text, (Unit, NounKind))]
nounTable =
  [ (w, (USection, Plain))     | w <- ["section", "sections", "s", "ss", "sec", "secs", "§", "§§"] ] <>
  [ (w, (USection, Sub))       | w <- ["subsection", "subsections"] ] <>
  [ (w, (UParagraph, Para))    | w <- ["paragraph", "paragraphs", "para", "paras"] ] <>
  [ (w, (URegulation, Plain))  | w <- ["regulation", "regulations", "reg", "regs"] ] <>
  [ (w, (URule, Plain))        | w <- ["rule", "rules"] ] <>
  [ (w, (UArticle, Plain))     | w <- ["article", "articles", "art", "arts"] ] <>
  [ (w, (UClause, Plain))      | w <- ["clause", "clauses", "cl"] ] <>
  [ (w, (USchedule, Plain))    | w <- ["schedule", "schedules", "sch"] ]

nounOf :: Text -> Maybe (Unit, NounKind)
nounOf w = lookup (Text.toLower (Text.dropWhileEnd (== '.') w)) nounTable

-- | Is this (without its full stop) a noun, so that its full stop is the
-- noun's own (@s.@, @art.@)?
isNounWord :: Text -> Bool
isNounWord w = isJust (nounOf w)

-- | A provision number with its bracket groups: @6@, @6A(2)(b)@, @76.21(2)@,
-- @(8)@. The number is 'Nothing' when only brackets are written.
parseBody :: Text -> Maybe (Maybe Text, [Text])
parseBody w = case Text.uncons w of
  Just (c, _)
    | isDigit c ->
        let (numPart, groupsPart) = Text.break (== '(') w
        in if validNumber numPart
             then (\gs -> (Just (normNum numPart), gs)) <$> parseGroups groupsPart
             else Nothing
    | c == '(' -> (\gs -> (Nothing, gs)) <$> parseGroups w
  _ -> Nothing

validNumber :: Text -> Bool
validNumber n =
  not (Text.null n)
    && isDigit (Text.head n)
    && Text.all (\c -> isAlphaNum c || c == '.' || c == '-') n
    && not (Text.last n `elem` ['.', '-'])

normNum :: Text -> Text
normNum = Text.toLower . Text.filter (/= '-')

parseGroups :: Text -> Maybe [Text]
parseGroups t
  | Text.null t = Just []
  | otherwise = do
      (g, rest) <- parseGroupAt t
      (g :) <$> parseGroups rest

-- | One bracket group at the head: its content (lower-cased) and the rest.
parseGroupAt :: Text -> Maybe (Text, Text)
parseGroupAt t = do
  afterOpen <- Text.stripPrefix "(" t
  let (inner, rest) = Text.break (== ')') afterOpen
  afterClose <- Text.stripPrefix ")" rest
  if not (Text.null inner) && Text.length inner <= 8 && Text.all (\c -> isAlphaNum c || c == '.') inner
    then Just (Text.toLower inner, afterClose)
    else Nothing

----------------------------------------------------------------------------
-- Finding the mentions
----------------------------------------------------------------------------

-- | Every override phrase in a piece of prose, classified.
findMentions :: Text -> [Mention]
findMentions = go . chunksOf
 where
  go [] = []
  go (c : cs) = case phraseHead c cs of
    Just (ph, after) -> mkMention ph after : go cs
    Nothing          -> go cs

phraseHead :: Chunk -> [Chunk] -> Maybe (Phrase, [Chunk])
phraseHead c cs = case (lw c, cs) of
  ("subject", d : rest) | lw d == "to", not c.stop -> Just (PhSubjectTo, rest)
  ("notwithstanding", _)                           -> Just (PhNotwithstanding, cs)
  ("despite", _)                                   -> Just (PhDespite, cs)
  ("except", d : _) | lw d `elem` exceptLeads, not c.stop -> Just (PhExcept, cs)
  _                                                -> Nothing
 where
  exceptLeads = ["as", "under", "in", "by", "pursuant"]

-- | Words that may stand between the phrase and the provision: "the provisions
-- of", "anything contained in", "as otherwise provided by". Short on purpose:
-- "subject to a trust under section 12" must not match.
fillerWords :: [Text]
fillerWords =
  [ "the", "provisions", "provision", "requirements", "requirement", "conditions"
  , "condition", "restrictions", "restriction", "limitations", "limitation"
  , "of", "in", "under", "by", "as", "provided", "otherwise", "to", "with"
  , "accordance", "pursuant", "specified", "permitted", "set", "out", "contained"
  , "referred", "anything", "applicable", "relevant", "and"
  ]

dropFiller :: Int -> [Chunk] -> [Chunk]
dropFiller 0 cs = cs
dropFiller n (c : cs)
  | lw c `elem` fillerWords, not c.stop = dropFiller (n - 1) cs
dropFiller _ cs = cs

mkMention :: Phrase -> [Chunk] -> Mention
mkMention ph after =
  MkMention
    { phrase  = ph
    , excerpt = Text.unwords (map (.word) (take 10 after))
    , klass   = classify
    }
 where
  classify = case parseTargets (dropFiller 6 after) of
    Just (ts, ranged, rest)
      | ranged            -> Ranged ts
      | externalAfter rest -> External ts
      | otherwise         -> Linted ts
    Nothing
      | openClass after   -> OpenClass
      | otherwise         -> NoProvision

-- | The targets that open a clause, whether a range ended the list, and what
-- follows the list.
parseTargets :: [Chunk] -> Maybe ([Target], Bool, [Chunk])
parseTargets (n : b : rest)
  | Just (u, anchor) <- nounOf n.word
  , not n.stop
  , Just (mnum, grp) <- parseBody b.word
  = Just (continueList [mkTarget u anchor n.word mnum grp] b rest)
parseTargets _ = Nothing

mkTarget :: Unit -> NounKind -> Text -> Maybe Text -> [Text] -> Target
mkTarget u anchor nounWord mnum grp = case (anchor, mnum) of
  (Para, _)        -> MkTarget { unit = UParagraph, noun = nm, number = mnum, path = grp, relative = True }
  (_, Just _)      -> MkTarget { unit = u, noun = nm, number = mnum, path = grp, relative = False }
  (_, Nothing)     -> MkTarget { unit = USection, noun = nm, number = Nothing, path = grp, relative = True }
 where
  nm = Text.toLower (Text.dropWhileEnd (== '.') nounWord)

-- | Extend a list of targets over "and" / "or" and ", and": "sections 6 and 7",
-- "section 6(1) and (2)". A comma alone does not extend it, because "Subject
-- to section 6, 4 persons may ..." is not a list.
continueList :: [Target] -> Chunk -> [Chunk] -> ([Target], Bool, [Chunk])
continueList acc lastChunk rest = case rest of
  (j : more)
    | lw j == "to", not lastChunk.stop, rangeEnd more -> (acc, True, rest)
    | lw j `elem` ["and", "or"]
    , not lastChunk.hard
    , Just (t, endChunk, more') <- nextTarget (last acc) more
    -> continueList (acc <> [t]) endChunk more'
  _ -> (acc, False, rest)
 where
  rangeEnd = \case
    (x : _) | isJust (parseBody x.word) -> True
    (x : y : _) | isJust (nounOf x.word), isJust (parseBody y.word) -> True
    _ -> False

nextTarget :: Target -> [Chunk] -> Maybe (Target, Chunk, [Chunk])
nextTarget prev = \case
  (x : y : rest)
    | Just (u, an) <- nounOf x.word, Just (mn, g) <- parseBody y.word
    -> Just (mkTarget u an x.word mn g, y, rest)
  (x : rest)
    | Just (mn, g) <- parseBody x.word
    -> Just (inherit mn g, x, rest)
  _ -> Nothing
 where
  inherit mn g = case mn of
    Just _  -> MkTarget { unit = prev.unit, noun = prev.noun, number = mn, path = g, relative = False }
    Nothing -> MkTarget { unit = prev.unit, noun = prev.noun, number = prev.number, path = siblingPath g, relative = prev.relative }
  siblingPath g
    | prev.relative || null prev.path = g
    | otherwise = init prev.path <> g

-- | "section 6 of the Wills Act": the provisions belong to another instrument.
-- "of this Act" and "of the Act" are this one.
externalAfter :: [Chunk] -> Bool
externalAfter (o : more) | lw o == "of" = case dropThe more of
  (t : _)
    | lw t `elem` ["this", "these", "same"] -> False
    | t.word == "Act"                       -> False
    | lw t == "that"                        -> True
    | startsUpper t.word                    -> True
  _ -> False
 where
  dropThe (x : xs) | lw x == "the" = xs
  dropThe xs = xs
  -- a proper name ("the Wills Act") or a year-led title ("the 2008 Regulations")
  startsUpper w = maybe False (\c -> isUpper c || isDigit c) (fmap fst (Text.uncons w))
externalAfter _ = False

-- | "notwithstanding any other provision", "subject to the provisions of this
-- Act": a target of no provision in particular (spec §12.1: out of reach of
-- any static edge).
openClass :: [Chunk] -> Bool
openClass after =
  let win = map lw (takeThroughStop 8 after)
  in any (`elem` openPairs) (zip win (drop 1 win))
 where
  openPairs =
    [ ("this", x) | x <- ["act", "section", "part", "division", "regulation", "regulations", "schedule", "subsection", "rule", "rules", "code", "ordinance", "chapter", "title", "law"] ] <>
    [ ("any", x)  | x <- ["other", "provision", "law", "enactment", "written", "rule", "statute"] ] <>
    [ ("the", "act") ]

takeThroughStop :: Int -> [Chunk] -> [Chunk]
takeThroughStop 0 _ = []
takeThroughStop _ [] = []
takeThroughStop n (c : cs)
  | c.stop    = [c]
  | otherwise = c : takeThroughStop (n - 1) cs

----------------------------------------------------------------------------
-- Provision keys: what a decision's name says it encodes
----------------------------------------------------------------------------

-- | The provision a decision is named after: @s 6(1) — granted to more than 4
-- persons@ is section 6, subsection 1.
data ProvKey = MkProvKey
  { unit   :: Unit
  , number :: Text
  , path   :: [Text]
  }
  deriving stock (Show, Eq)

renderKey :: ProvKey -> Text
renderKey k = unitWord k.unit <> " " <> k.number <> Text.concat [ "(" <> g <> ")" | g <- k.path ]
 where
  unitWord = \case
    USection    -> "s"
    URegulation -> "reg"
    URule       -> "rule"
    UArticle    -> "art"
    UClause     -> "clause"
    USchedule   -> "sch"
    UParagraph  -> "para"

-- | The provision a decision's name starts with, if it starts with one. The
-- conventions are the corpus's (measured over the commons checkout,
-- 2026-10-30): @s N@, @section N@, @reg N@, @Art N@, @art. N@, @Article N@,
-- @Sch N@, @clause N@, each with bracket groups.
provKeyOfName :: Text -> Maybe ProvKey
provKeyOfName t = case chunksOf (Text.take 120 t) of
  (n : b : _)
    | Just (u, an) <- nounOf n.word
    , an /= Para
    , not n.stop
    , Just (Just num, g) <- parseBody b.word
    -> Just MkProvKey { unit = u, number = num, path = g }
  _ -> Nothing

-- | Does a decision named for @decl@ encode (some of) the provision @want@?
-- Yes when they share a unit and a number and one path is a prefix of the
-- other: a decision for @s 6@ covers @s 6(1)@ and a decision for @s 6(1)@
-- covers a reference to @s 6@.
keyMatches :: ProvKey -> ProvKey -> Bool
keyMatches decl want =
  decl.unit == want.unit
    && decl.number == want.number
    && (want.path `isPrefixOf` decl.path || decl.path `isPrefixOf` want.path)

----------------------------------------------------------------------------
-- The lint
----------------------------------------------------------------------------

-- | Where the phrase was read.
data Source
  = SrcRef
    -- ^ an @\@ref@ citation attached to the decision
  | SrcName
    -- ^ the decision's own name
  | SrcText
    -- ^ a string literal in the decision's body (the third source, see above)
  deriving stock (Show, Eq, Ord)

sourceText :: Source -> Text
sourceText = \case
  SrcRef  -> "@ref"
  SrcName -> "name"
  SrcText -> "text"

-- | How an edge was found.
data How
  = Direct
    -- ^ the decision's body calls a decision for the provision
  | ViaHelper
    -- ^ ... through other decisions of the module
  | FromTarget
    -- ^ the other way round: the provision's decision reaches this one
    -- (the defeat idiom)
  | AtJoin
    -- ^ neither reaches the other, but a third decision calls both
  deriving stock (Show, Eq, Ord)

data Outcome
  = Wired How
  | MissingConjunct
    -- ^ FINDING: "Subject to X" in the prose; decisions for X exist in the
    -- module; the body reaches none of them, and nothing reaches it from them
  | OverrideUnwired
    -- ^ FINDING: "Notwithstanding X" in the prose; decisions for X exist; no
    -- edge joins the two in either direction and no decision calls both
  | TargetNotEncoded
    -- ^ no decision in the module is named for X: nothing for the body to call
  | CitationOnly
    -- ^ the decision's whole body is one quotation: it computes nothing, so it
    -- cannot answer where the override should have changed the answer
  | SelfReference
    -- ^ X is the provision the decision itself encodes
  | UnresolvedRelative
    -- ^ "subsection (8)" or "paragraph (a)" of a decision whose name carries no
    -- provision number to be relative to
  | ExternalInstrument
  | RangeOfProvisions
  | OpenClassTarget
  deriving stock (Show, Eq, Ord)

outcomeText :: Outcome -> Text
outcomeText = \case
  Wired Direct     -> "wired (direct call)"
  Wired ViaHelper  -> "wired (through a helper)"
  Wired FromTarget -> "wired (the provision's decision calls this one)"
  Wired AtJoin     -> "wired (a third decision calls both)"
  MissingConjunct  -> "missing-conjunct"
  OverrideUnwired  -> "override-unwired"
  TargetNotEncoded -> "target-not-encoded"
  CitationOnly     -> "citation-only"
  SelfReference    -> "self-reference"
  UnresolvedRelative -> "unresolved-relative"
  ExternalInstrument -> "external-instrument"
  RangeOfProvisions -> "range"
  OpenClassTarget       -> "open-class"

-- | The two outcomes that are reported as findings; every other outcome is
-- census.
isFinding :: Outcome -> Bool
isFinding o = o == MissingConjunct || o == OverrideUnwired

data Finding = MkFinding
  { decision   :: Text
  , at         :: Maybe SrcRange
  , phrase     :: Phrase
  , written    :: Text
    -- ^ the target as the prose wrote it; for an open-class mention, the excerpt
  , resolved   :: Maybe Text
    -- ^ the provision it names, in the spelling of a decision's name
  , sources    :: [Source]
  , outcome    :: Outcome
  , candidates :: [Text]
    -- ^ the decisions of the module that encode the target
  }
  deriving stock (Show, Eq)

-- | A top-level decision, with what the lint needs of it.
data Host = MkHost
  { name    :: Text
  , uniq    :: Unique
  , range   :: Maybe SrcRange
  , key     :: Maybe ProvKey
  , texts   :: [(Source, Text)]
  , callees :: Set Unique
  , calleeKeys :: [ProvKey]
    -- ^ the provision every name the body mentions is named for, including
    -- names imported from other modules, whose decisions the lint does not see
  , citationOnly :: Bool
    -- ^ the body is one string literal, so no call is missing from it: it
    -- answers with the quotation and never with a verdict
  }

-- | Lint every top-level decision of a type-checked module.
lintModule :: Module Resolved -> [Finding]
lintModule m = sortOn order (concatMap hostFindings hosts)
 where
  hosts = [ mkHost a d | (a, d) <- topDecides m ]
  uniques = Set.fromList [ h.uniq | h <- hosts ]

  -- the call graph restricted to the module's own decisions
  graph :: Map Unique (Set Unique)
  graph = Map.fromList [ (h.uniq, Set.intersection uniques (Set.delete h.uniq h.callees)) | h <- hosts ]

  reach :: Unique -> Set Unique
  reach u = go Set.empty (Set.toList (Map.findWithDefault Set.empty u graph))
   where
    go seen [] = seen
    go seen (x : xs)
      | x `Set.member` seen = go seen xs
      | otherwise = go (Set.insert x seen) (Set.toList (Map.findWithDefault Set.empty x graph) <> xs)

  order :: Finding -> (Maybe (Int, Int), Phrase, Text)
  order f = (fmap (\r -> (r.start.line, r.start.column)) f.at, f.phrase, f.written)

  hostFindings :: Host -> [Finding]
  hostFindings h = map (finish h) (groupItems (itemsOf h))

  finish :: Host -> ([Source], Item) -> Finding
  finish h (srcs, it) = case it.cls of
    ToCheck k ->
      let (oc, cands) = judge h k it.phrase
      in MkFinding h.name h.range it.phrase it.written (Just (renderKey k)) srcs oc (map (.name) cands)
    Settled oc -> MkFinding h.name h.range it.phrase it.written Nothing srcs oc []

  -- the verdict on one resolved target
  judge :: Host -> ProvKey -> Phrase -> (Outcome, [Host])
  judge h k ph
    | selfRef = (SelfReference, [])
    | any (`keyMatches` k) h.calleeKeys = (Wired Direct, tgts)
    | null tgts = (TargetNotEncoded, [])
    | otherwise = (verdict, tgts)
   where
    selfRef = case h.key of
      Just hk -> hk.unit == k.unit && hk.number == k.number && k.path `isPrefixOf` hk.path
      Nothing -> False
    tgts = [ o | o <- hosts, o.uniq /= h.uniq, Just ok <- [o.key], keyMatches ok k ]
    tgtSet = Set.fromList (map (.uniq) tgts)
    direct = not (Set.null (Set.intersection (Map.findWithDefault Set.empty h.uniq graph) tgtSet))
    helper = not (Set.null (Set.intersection (reach h.uniq) tgtSet))
    fromTarget = any (\t -> h.uniq `Set.member` reach t.uniq) tgts
    -- A decision that combines the two. For "subject to" it must call both
    -- itself; for "notwithstanding" and "despite" it may reach either through
    -- helpers, as `meets the charity test` does in the Jersey charity-test case
    -- study (`... AND NOT the Article 5(2) knock-out bites`, a wrapper around
    -- the Article 5(2) decision that said "despite paragraph (1)").
    atJoin = any (\c -> c.uniq /= h.uniq && joins c) hosts
    joins c
      | phraseDirection ph == Yields =
          h.uniq `Set.member` Map.findWithDefault Set.empty c.uniq graph
            && not (Set.null (Set.intersection (Map.findWithDefault Set.empty c.uniq graph) tgtSet))
      | otherwise =
          h.uniq `Set.member` reach c.uniq
            && not (Set.null (Set.intersection (reach c.uniq) tgtSet))
    verdict
      | direct = Wired Direct
      | helper = Wired ViaHelper
      | fromTarget = Wired FromTarget
      | atJoin = Wired AtJoin
      | h.citationOnly = CitationOnly
      | phraseDirection ph == Yields = MissingConjunct
      | otherwise = OverrideUnwired

-- | What kind of verdict an item awaits.
data ItemClass
  = ToCheck ProvKey
  | Settled Outcome

data Item = MkItem
  { phrase  :: Phrase
  , written :: Text
  , cls     :: ItemClass
  , src     :: Source
  }

-- | Collapse the same phrase and target found in several sources into one
-- item that lists them.
groupItems :: [Item] -> [([Source], Item)]
groupItems its =
  [ (sort (nubOrd (map (.src) grp)), it)
  | grp@(it : _) <- groupBy' (map (\i -> (identity i, i)) its)
  ]
 where
  identity :: Item -> (Phrase, Text)
  identity i = (i.phrase, case i.cls of ToCheck k -> renderKey k; Settled _ -> i.written)
  groupBy' :: [((Phrase, Text), Item)] -> [[Item]]
  groupBy' kvs = Map.elems (Map.fromListWith (flip (<>)) [ (k, [i]) | (k, i) <- kvs ])

itemsOf :: Host -> [Item]
itemsOf h =
  [ it
  | (s, t) <- h.texts
  , mn <- findMentions t
  , it <- itemsFor s mn
  ]
 where
  itemsFor :: Source -> Mention -> [Item]
  itemsFor s mn = case mn.klass of
    Linted ts -> [ one s mn t | t <- ts ]
    External ts -> [ MkItem mn.phrase (renderTarget t) (Settled ExternalInstrument) s | t <- ts ]
    Ranged ts -> [ MkItem mn.phrase (renderTarget t) (Settled RangeOfProvisions) s | t <- take 1 ts ]
    OpenClass -> [ MkItem mn.phrase mn.excerpt (Settled OpenClassTarget) s ]
    NoProvision -> []
  one :: Source -> Mention -> Target -> Item
  one s mn t = case resolveTarget h.key t of
    Just k  -> MkItem mn.phrase (renderTarget t) (ToCheck k) s
    Nothing -> MkItem mn.phrase (renderTarget t) (Settled UnresolvedRelative) s

-- | The provision a target names, resolving "subsection (8)" against the
-- decision's own section.
resolveTarget :: Maybe ProvKey -> Target -> Maybe ProvKey
resolveTarget hostKey t = case (t.number, hostKey) of
  (Just n, _) | t.unit /= UParagraph -> Just MkProvKey { unit = t.unit, number = n, path = t.path }
  (Nothing, Just hk) | t.relative, t.unit == USection -> Just MkProvKey { unit = hk.unit, number = hk.number, path = t.path }
  -- Where an article, regulation, rule or clause is divided into numbered
  -- "paragraphs" (Jersey's Charities Law, for one), "paragraph (2)" is the
  -- subsection of the one the decision is named for.
  (Nothing, Just hk) | t.relative, t.unit == UParagraph, hk.unit `elem` [UArticle, URegulation, URule, UClause] ->
    Just MkProvKey { unit = hk.unit, number = hk.number, path = t.path }
  _ -> Nothing

topDecides :: Module Resolved -> [(Anno, Decide Resolved)]
topDecides (MkModule _ _ sec) = goSection sec
 where
  goSection (MkSection _ _ _ _ ds) = concatMap goDecl ds
  goDecl = \case
    Decide a d  -> [(a, d)]
    Section _ s -> goSection s
    _           -> []

mkHost :: Anno -> Decide Resolved -> Host
mkHost outer (MkDecide inner _ (MkAppForm _ nm _ _) body) =
  MkHost
    { name    = nm'
    , uniq    = getUnique nm
    , range   = (getAnno (getOriginal nm)).range
    , key     = provKeyOfName nm'
    , texts   = [ (SrcRef, refCitation r) | ann <- [outer, inner], r <- ann ^. annRefs ]
                <> [ (SrcName, nm') ]
                <> [ (SrcText, s) | e <- universeExpr body, s <- stringsIn e ]
    , callees = Set.fromList [ u | Ref _ u _ <- toList body ]
    , calleeKeys = mapMaybe (provKeyOfName . nameToText . getOriginal) [ r | r@Ref {} <- toList body ]
    , citationOnly = isQuotation body
    }
 where
  nm' = nameToText (getOriginal nm)

-- | A body that is one string literal and nothing else. A string among
-- AND/OR operands is 'Inert' and evaluates to the operator's identity, so a
-- chain of quotations alone answers @TRUE@; that is not a citation, and is
-- exactly the failure the lint exists to catch.
isQuotation :: Expr Resolved -> Bool
isQuotation = \case
  Lit _ (StringLit _ _) -> True
  _                     -> False

-- | The text of a string literal. The type checker turns a string that sits
-- in an AND or OR chain into an 'Inert' node, so both shapes are read.
stringsIn :: Expr Resolved -> [Text]
stringsIn = \case
  Lit _ (StringLit _ s) -> [s]
  Inert _ s _           -> [s]
  _                     -> []

universeExpr :: Expr Resolved -> [Expr Resolved]
universeExpr e = e : concatMap universeExpr (toListOf (gplate @(Expr Resolved)) e)
