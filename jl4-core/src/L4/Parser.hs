{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ViewPatterns #-}
module L4.Parser (
  -- * Public API
  parseFile,
  execParser,
  execParserWithHints,
  execParserForTokens,
  execParserForTokensWithHints,
  module',
  PError (..),
  mkPError,
  PState (..),
  langTagOfToken,
  declaredModuleLang,
  MixfixHintRegistry,
  buildMixfixHintRegistry,
  emptyMixfixHintRegistry,
  hasMixfixHints,
  showKeywords,

  -- * Debug combinators
  expr,
  spaceOrAnnotations,

  -- * High-level JL4 parser
  execProgramParser,
  execProgramParserForTokens,
  execProgramParserWithHints,
  execProgramParserForTokensWithHints,
  execProgramParserWithHintPass,
  execProgramParserWithHintPassUnmemoised,
) where

import Base

import qualified Control.Applicative as Applicative
import Generics.SOP.BasicFunctors
import Generics.SOP.NS
import qualified Data.IntMap.Strict as IntMap
import qualified Data.List.Extra as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import GHC.Generics hiding (Fixity)
import GHC.Records
import Optics
import Text.Megaparsec hiding (parseTest)
import qualified Text.Megaparsec.Char.Lexer as Lexer
import qualified Text.Megaparsec.Internal as Megaparsec
import Text.Pretty.Simple

import L4.Annotation
import L4.Lexer as L
import qualified L4.Parser.ResolveAnnotation as Resolve
import qualified L4.ParserCombinators as P
import L4.Syntax hiding (app, forall', fun, Env)
import qualified L4.Syntax
import L4.Parser.SrcSpan
import qualified Generics.SOP as SOP
import L4.Parser.Anno
import L4.Parser.MixfixRegistry

-- | The memo of bracketed groups ('GroupMemo') sits BELOW megaparsec, where
-- backtracking cannot roll it back: a group parsed inside an alternative that
-- then fails stays parsed. Everything above megaparsec ('Env', 'PState') is
-- rolled back with the parser state, as before.
type Parser = ReaderT Env (StateT PState (ParsecT Void TokenStream (StateT GroupMemo Identity)))

data Env = Env
  { moduleUri :: NormalizedUri
  , mixfixHints :: MixfixHintRegistry
  , ofIsAnchor :: Bool
    -- ^ Are we parsing the DURATION of a @WITHIN@ (or the offset of an
    -- @AFTER@)? There @OF@ introduces the edge's anchor — @WITHIN 5 OF THE
    -- JOIN@, @WITHIN d OF closingDate@, @AFTER 3 OF THE JOIN@
    -- (EVERY-EACH-QUANTIFIER-SPEC §5.1.1, R-Q7A; §5.1.2, R-X5) — and not a
    -- function's arguments, so 'app' does not take @OF@-arguments while this
    -- is set and an application spelled @f OF x@ in that slot must be
    -- parenthesised. Set by 'deadline' and 'opening'; reset by 'paren' and
    -- inside the anchor itself ('inExprSlot'). Everywhere else it is
    -- 'False' — including inside a @BEFORE@, which takes no anchor.
    --
    -- This is the only field any parser changes with 'local', which is why
    -- 'memoGroup' keys on it and on nothing else of the 'Env'.
  , memoiseGroups :: Bool
    -- ^ Does 'memoGroup' memoise? 'True' for every parse the tools run.
    -- 'False' parses a bracketed group afresh wherever it is reached, as the
    -- parser did before MATRYOSHKA, in time exponential in how deeply groups
    -- nest. It exists so that a test can check that the memo changes nothing
    -- ('execProgramParserWithHintPassUnmemoised'). Fixed for a whole run.
  }
  deriving stock (Show, Eq, Generic)
  deriving anyclass (SOP.Generic)
-- | Only ever prepended to, and read only once the parse is over: 'memoGroup' replays a group's additions on that basis.
data PState = PState
  { comments :: [Comment]
  , nlgs :: [Nlg]
  , refs :: [Ref]
  , descs :: [Desc]
  , fixities :: [Fixity]
  , langs :: [LangTag]
    -- ^ @\@lang@ declarations seen, most recent first. A list rather than a
    -- 'Maybe' so that a second declaration is a fact we could report on later
    -- rather than one silently overwriting the other.
  }
  deriving stock (Show, Eq, Generic)
  deriving (Semigroup, Monoid) via Generically PState

addNlg :: Nlg -> PState -> PState
addNlg n s = over #nlgs (n:) s

addLang :: LangTag -> PState -> PState
addLang l s = over #langs (l:) s

addRef :: Ref -> PState -> PState
addRef ref s = over #refs (ref:) s

addDesc :: Desc -> PState -> PState
addDesc desc s = over #descs (desc:) s

addFixity :: Fixity -> PState -> PState
addFixity fx s = over #fixities (fx:) s

spaces :: Parser [PosToken]
spaces =
  takeWhileP (Just "space token") isSpaceToken

spaceOrAnnotations :: Parser (Lexeme ())
spaceOrAnnotations = do
  ws <- spaces
  nlgs :: [NS Epa [Ref, Nlg, Desc, Fixity, (), LangTag]] <- many (fmap (S . S . S . S . S . Z) langP <|> fmap (S . S . S . S . Z) refAdditionalP <|> fmap (S . S . S . Z) fixityP <|> fmap (S . S . Z) descP <|> fmap (S . Z) nlgAnnotationP <|> fmap Z refP)
  traverse_ addAnnotation nlgs
  let
    epaNlgs = fmap (collapse_NS . map_NS (K . epaToHiddenCluster)) nlgs
  pure $ Lexeme
    { trailingTokens = ws
    , payload = ()
    , hiddenClusters = epaNlgs
    }

-- | @\@lang he@. Collected like any other annotation, so its tokens ride in
-- the same hidden cluster and exactprint re-emits the line unchanged.
langP :: Parser (Epa LangTag)
langP = hidden $ spacedTokenWs langTagOfToken "Language declaration"

-- | The language tag a @\@lang@ token carries, if that is what this token is.
--
-- Factored out so that the two things that read a @\@lang@ declaration — the
-- parser, through 'langP', and 'declaredModuleLang', which scans a bare token
-- stream — agree on what the token looks like by construction rather than by
-- both being edited together.
langTagOfToken :: TokenType -> Maybe LangTag
langTagOfToken = \ case
  TAnnotations (TLang tag _) -> Just tag
  _ -> Nothing

-- | A module's declared @\@lang@, read straight off its token stream, or
-- 'Nothing' when it declares none.
--
-- The LAST declaration in source order wins, which is the same rule
-- 'execParserForTokensWithHints' applies below: it takes @listToMaybe
-- pstate.langs@, and 'addLang' accumulates by prepending, so that head IS the
-- last one written. Stated in both places because the two have different
-- inputs (a token list here, the parser state there); they are checked against
-- each other by @jl4-test@'s corpus, every file of which goes through both.
--
-- This exists because a consumer downstream of the parse — @l4 render@, which
-- labels its HTML @<html lang="…">@ — needs the declaration itself, not its
-- effect on annotations. The effect ('withDefaultLang') is unrecoverable for a
-- module that declares a language and carries no @\@nlg@ at all.
declaredModuleLang :: [PosToken] -> Maybe LangTag
declaredModuleLang ts =
  listToMaybe [ tag | t <- reverse ts, Just tag <- [langTagOfToken t.payload] ]

refP :: Parser (Epa Ref)
refP = do
  refExpr <- refAnnotationP
  -- The Anno keeps the tokens verbatim, so exactprint re-emits the citation
  -- byte for byte; the stored Text is the READER's copy and is decoded here.
  -- Measured: mangling this Text turns three reader tests red (Blawx twice,
  -- Catala's literate weave) while `exactprint identity` stays green, so this
  -- field is off the print path. See 'L4.Lexer.unescapeRefText'.
  pure $ fmap (MkRef (mkSimpleEpaAnno refExpr)) (fmap unescapeRefText refExpr)

descP :: Parser (Epa Desc)
descP = do
  e <- hidden $ spacedTokenWs (\ case
    TAnnotations (TDesc t) -> Just t
    TAnnotations (TExport t) -> Just (" export" <> t)
    TAnnotations (TNonexhaustive t) -> Just (" nonexhaustive" <> t)
    _ -> Nothing
    )
    "Description annotation"
  pure $ fmap (MkDesc (mkSimpleEpaAnno e)) e

fixityP :: Parser (Epa Fixity)
fixityP = do
  e <- hidden $ spacedTokenWs (\ case
    TAnnotations (TFixity dir t) -> Just (dir, t)
    _ -> Nothing
    )
    "Fixity annotation"
  pure $ fmap (\ (dir, t) -> MkFixity (mkSimpleEpaAnno e) dir t) e


nlgAnnotationP :: Parser (Epa Nlg)
nlgAnnotationP = do
  currentPosition <- getSourcePos
  moduleUri <- asks (.moduleUri)
  rawAnno <- hidden $ spacedTokenWs (\ case
    TAnnotations (TNlg mtag t ty) -> Just (mtag, ty, toNlgAnno mtag t ty)
    _ -> Nothing)
    "Natural Language Annotation"

  let
    -- The reconstructed text MUST still carry the tag: it is what gets
    -- re-lexed below, and 'mkPosTokens' seeds the inner tokens' positions by
    -- advancing over it.
    (mLangTag, nlgAnnoTy) = case rawAnno.payload of (m, ty, _) -> (m, ty)
    rawText = (\ (_, _, t) -> t) <$> rawAnno

    nlgParser :: Parser Nlg
    nlgParser =
      blockNlg <|> lineNlg

    blockNlg :: Parser Nlg
    blockNlg = do
      (open, a, close) <- P.between (plainToken $ TSymbols TNlgOpen) (plainToken $ TSymbols TNlgClose) (nlgFragment True)
      attachAnno $
        MkParsedNlg emptyAnno
          <$  annoEpa  (pure (tokenToEpa open))
          -- The tag field's hole, in FIELD order. It has no surface of its own
          -- here (the bare form cannot be tagged), but an empty-surface field
          -- still occupies a holeFit slot in the generic exactprint traversal
          -- — see the RecallMode note in 'L4.Syntax'. Without it the fragments
          -- land in the tag's slot and exactprint emits the herald with no
          -- text after it, silently, on every annotation in the corpus.
          <*> annoHole (pure mLangTag)
          <*> annoHole (pure a)
          <*  annoEpa  (pure (tokenToEpa close))

    lineNlg :: Parser Nlg
    lineNlg = do
      attachAnno $
        MkParsedNlg emptyAnno
          <$  annoLexeme (spacedTokenWsSatisfy isNlgPrefixToken "@nlg annotation herald")
          -- Field order, as in 'blockNlg' above. The tag's surface — the @:he@
          -- — is inside the herald token that the lexeme just emitted, so this
          -- hole is empty and sits exactly where the surface already went.
          <*> annoHole   (pure mLangTag)
          <*> annoHole   (nlgFragment False)

    nlgFragment :: Bool -> Parser [NlgFragment Name]
    nlgFragment isBlock = do
      many $
            try nameRefP
        <|> textFragment isBlock

    runNlgParserForInputAt initPos input = case execNlgLexer initPos moduleUri input of
      Left err -> do
        -- TODO: We should delay the parse error since parser failures in the
        -- annotation are not immediately fatal, we could report much more errors this way.
        -- Just like we when parsing fails
        fancyFailure $ Set.singleton $ ErrorFail $ errorBundlePretty err
      Right toks ->
        case execNlgParserForTokens (nlgParser <* eof) moduleUri rawText.payload toks of
          Left err -> do
            traverse_ registerParseError (bundleErrors err)
            attachAnno $
              MkInvalidNlg emptyAnno
                <$ annoEpa (pure $ (\ t -> TNlg mLangTag t nlgAnnoTy) <$> rawText)

          Right nlg ->
            pure nlg

  nlg <- runNlgParserForInputAt currentPosition rawText.payload
  case toNodesEither nlg of
    Left err -> do
      fancyFailure $ Set.singleton $
        ErrorFail $ "Internal error while parsing NLG annotation: " <> Text.unpack (prettyTraverseAnnoError err)
    Right csns -> do
      pure $ Epa
        { payload = nlg
        , original = concatMap allClusterTokens csns
        , trailingTokens = rawText.trailingTokens
        , hiddenClusters = []
        }

nameRefP :: Parser (NlgFragment Name)
nameRefP = do
  (open, n, close) <- P.between
    -- The delimiters are tight: a reference is @%name%@ with no whitespace inside.
    -- Annotation prose contains literal percent signs ("a 5% levy on %amount%"),
    -- and a spaced opening delimiter would let one of those pair with the opening
    -- delimiter of the next real reference, capturing the word between them as an
    -- identifier -- silently, when that word happens to be in scope, and taking the
    -- intended reference down to plain text with it. See smucclaw/l4-ide#957.
    (hidden $ plainToken_ $ TSymbols TPercent)
    -- We don't want to consume trailing whitespace, because we would need to "reproduce"
    -- the whitespace during natural language generation. Otherwise, the text looks scuffed.
    -- Thus, only parse the 'TPercent' here, and let the 'textFragment' parser
    -- take care of any leading whitespace.
    (plainToken_ $ TSymbols TPercent)
    tightName
  attachAnno $
    MkNlgRef emptyAnno
      <$  annoLexeme (pure open)
      <*> annoHole   (pure n)
      <*  annoLexeme (pure close)

textFragment :: Bool -> Parser (NlgFragment Name)
textFragment isBlock = do
  when isBlock $ do
    notFollowedBy (plainToken (TSymbols TNlgClose) *> eof)
  attachAnno $
    MkNlgText emptyAnno
      <$> annoEpa (wrapInEpa <$> anySingle)
  where
    -- We replace any 'PosToken' we are parsing with 'TNlgString' to make sure
    -- it is highlighted correctly
    wrapInEpa :: PosToken -> Epa Text
    wrapInEpa posToken =
      displayTokenType . (.payload) <$> tokenToEpa (posToken & #payload %~ replaceTokenType)

    replaceTokenType :: TokenType -> TokenType
    replaceTokenType tt@(TSpaces (TSpace _)) = tt
    replaceTokenType tt = TAnnotations $ TNlgString $ displayTokenType tt

refAnnotationP :: Parser (Epa Text)
refAnnotationP = hidden $ spacedTokenWs (\ case
  TAnnotations (TRef t ty) -> Just $ toRefAnno t ty
  _ -> Nothing)
  "Reference Annotation"


-- TODO:
-- (1) should ref-src /ref-map be allowed anywhere else than at the toplevel
-- (2) should we add it to the AST at all? Currently we don't need it
refAdditionalP :: Parser (Epa ())
refAdditionalP = hidden $ spacedTokenWs (\ case
  TAnnotations (TRefSrc _t) -> Just ()
  TAnnotations (TRefMap _t) -> Just ()
  _ -> Nothing
  )
  "Reference source or map annotation"

lexeme :: Parser a -> Parser (Lexeme a)
lexeme p = do
  a <- p
  wsOrAnnotation <- spaceOrAnnotations
  pure $ Lexeme
    { payload = a
    , trailingTokens = wsOrAnnotation.trailingTokens
    , hiddenClusters = wsOrAnnotation.hiddenClusters
    }

addAnnotation :: NS Epa (Ref : Nlg : Desc : Fixity : () : LangTag : xs) -> Parser ()
addAnnotation = \ case
  S (S (S (Z fx))) -> modify' (addFixity fx.payload)
  S (S (Z desc)) -> modify' (addDesc desc.payload)
  S (Z nlg) -> modify' (addNlg nlg.payload)
  Z ref -> modify' (addRef ref.payload)
  S (S (S (S (S (Z lang))))) -> modify' (addLang lang.payload)
  _ -> pure ()

lexemeWs :: Parser a -> Parser (Lexeme a)
lexemeWs p = do
  a <- p
  trailingTokens <- spaces
  pure $ Lexeme
    { trailingTokens = trailingTokens
    , payload = a
    , hiddenClusters = []
    }

spacedTokenWs :: (TokenType -> Maybe a) -> String -> Parser (Epa a)
spacedTokenWs cond lbl =
  lexToEpa' <$>
    lexemeWs
      (token
        (\ t -> (t,) <$> cond t.payload)
        Set.empty
      )
    <?> lbl

-- | 'spacedTokenWs' for a token type that carries a payload, discarding the
-- payload.
--
-- Replaced the equality-matching @spacedTokenWs_@, which became dead when the
-- @\@nlg@ herald gained a language tag: its last caller was 'lineNlg'.
--
-- 'plainToken' matches by EQUALITY on the whole 'TokenType', so it cannot
-- match a constructor whose argument varies — @TNlgPrefix (Just "he")@ is not
-- @TNlgPrefix Nothing@. Anything with a payload needs this instead.
spacedTokenWsSatisfy :: (TokenType -> Bool) -> String -> Parser (Lexeme PosToken)
spacedTokenWsSatisfy f lbl =
  lexemeWs (satisfyToken f lbl)

satisfyToken :: (TokenType -> Bool) -> String -> Parser PosToken
satisfyToken f lbl =
  token (\ t -> if f (computedPayload t) then Just t else Nothing) Set.empty
    <?> lbl

isNlgPrefixToken :: TokenType -> Bool
isNlgPrefixToken = \ case
  TAnnotations (TNlgPrefix _) -> True
  _ -> False

plainToken :: TokenType -> Parser PosToken
plainToken tt = do
  uri <- asks (.moduleUri)
  token
    (\ t -> if computedPayload t == tt then Just t else Nothing)
    (Set.singleton (Tokens (L.trivialToken uri tt :| [])))

plainToken_ :: TokenType -> Parser (Lexeme PosToken)
plainToken_ tt =
  mkLexeme [] <$> plainToken tt

spacedKeyword_ :: TKeywords -> Parser (Lexeme PosToken)
spacedKeyword_ tt = spacedToken_ (TKeywords tt)

spacedSymbol_ :: TSymbols -> Parser (Lexeme PosToken)
spacedSymbol_ tt = spacedToken_ (TSymbols tt)

spacedToken_ :: TokenType -> Parser (Lexeme PosToken)
spacedToken_ tt =
  lexeme (plainToken tt)

spacedToken :: Is k An_AffineFold => Optic' k is TokenType a -> String -> Parser (Epa a)
spacedToken cond lbl =
  lexToEpa' <$>
    lexeme
      (token
        (\ t -> (t,) <$> preview cond (computedPayload t))
        Set.empty
      )
    <?> lbl

(<<$>>) :: (Functor f, Functor g) => (a -> b) -> f (g a) -> f (g b)
fab <<$>> fga = (fmap . fmap) fab fga

-- | A quoted identifier between backticks.
quotedName :: Parser (Epa Name)
quotedName =
  (MkName emptyAnno . NormalName) <<$>> spacedToken (#_TIdentifiers % #_TQuoted) "quoted identifier"

simpleName :: Parser (Epa Name)
simpleName =
  (MkName emptyAnno . NormalName) <<$>> spacedToken (#_TIdentifiers % #_TIdentifier) "identifier"

qualifiedName :: Parser (Epa Name)
qualifiedName = do
  -- Allow both regular identifiers and quoted identifiers in qualified names
  let nameAndQualifiers = List.unsnoc . mapMaybe (either (const Nothing) (Just . snd))
      identToken = tokOf $ #_TIdentifiers % #_TIdentifier
      quotedToken = tokOf $ #_TIdentifiers % #_TQuoted
      identOrQuoted = identToken <|> quotedToken
  res@(nameAndQualifiers -> Just (q : qs, n)) <- do
    x <- identOrQuoted
    dotOrIdentifier <- some do
      d <- tokOf $ #_TSymbols % #_TDot
      i <- identOrQuoted
      pure [Left $ fst d, Right i]
    pure $ (Right x :) $ mconcat dotOrIdentifier
  wsOrAnnotation <- spaceOrAnnotations
  let e = Epa
        { original = map (either id fst) res
        , trailingTokens = wsOrAnnotation.trailingTokens
        , payload = QualifiedName (q :| qs) n
        , hiddenClusters = wsOrAnnotation.hiddenClusters
        }
  pure $ MkName emptyAnno <$> e

 where
 tokOf p = token (\t -> (t,) <$> preview p (computedPayload t)) Set.empty

name :: Parser Name
name = attachEpa (try qualifiedName <|> quotedName <|> simpleName) <?> "identifier"

-- | Like 'spacedToken', but does not consume trailing whitespace.
--
-- For syntax where adjacency is meaningful rather than incidental -- see 'tightName'.
tightToken :: Is k An_AffineFold => Optic' k is TokenType a -> String -> Parser (Epa a)
tightToken cond lbl =
  lexToEpa' . mkLexeme [] <$>
    token
      (\ t -> (t,) <$> preview cond (computedPayload t))
      Set.empty
    <?> lbl

tightQuotedName :: Parser (Epa Name)
tightQuotedName =
  (MkName emptyAnno . NormalName) <<$>> tightToken (#_TIdentifiers % #_TQuoted) "quoted identifier"

tightSimpleName :: Parser (Epa Name)
tightSimpleName =
  (MkName emptyAnno . NormalName) <<$>> tightToken (#_TIdentifiers % #_TIdentifier) "identifier"

-- | 'name', but without consuming the whitespace that follows it.
--
-- Only 'nameRefP' wants this: an nlg reference is delimited on both sides by @%@,
-- and if the name swallowed the space before the closing delimiter then @% word %@
-- would parse as a reference, which is how a literal percent sign in prose captures
-- the following word. See smucclaw/l4-ide#957.
--
-- There is deliberately no qualified-name alternative here. 'nlgTokenPayload' lexes
-- no symbols, so an annotation never contains a @.@ token and @qualifiedName@ could
-- not match inside one: @p.a@ arrives as the identifier @p@ followed by the text
-- @.a@, which the closing delimiter then fails against.
tightName :: Parser Name
tightName = attachEpa (tightQuotedName <|> tightSimpleName) <?> "identifier"

tokenAsName :: TokenType -> Parser Name
tokenAsName tt =
  attachEpa (lexToEpa' . fmap convert <$> spacedToken_ tt)
  where
    convert :: PosToken -> (PosToken, Name)
    convert p@(MkPosToken range _) = (MkPosToken range (TIdentifiers $ TIdentifier t), MkName emptyAnno (NormalName t))
      where
        t = displayPosToken p

indented :: Parser b -> Pos -> Parser b
indented parser pos =
  withIndent GT pos $ \ _ -> parser

indented' :: AnnoParser b -> Pos -> AnnoParser b
indented' parser pos = wrapAnnoParser $ indented (unwrapAnnoParser parser) pos

-- | Like 'indented', but admits the parser at a column greater than OR EQUAL to
-- @pos@. Used only for a @•@ bullet block in argument position, so a child
-- bullet can line up directly under the parent's head word (e.g. the @item@ of
-- @• item "Sub"@) — which the "• " marker shifts two columns right of the
-- bullet — rather than being forced strictly past it.
indentedGE :: Parser b -> Pos -> Parser b
indentedGE parser pos = do
  actual <- Lexer.indentLevel
  if actual >= pos
    then parser
    else
      -- Megaparsec's 'ErrorIndentation' only has LT/EQ/GT variants, so a
      -- failed >= check is reported as "greater than" — imprecise (it should
      -- say "greater than or equal to"), but the failing case (actual < pos)
      -- is identical for both orderings, so the reported column is correct.
      fancyFailure . Set.singleton $ ErrorIndentation GT pos actual

module' :: NormalizedUri -> Parser (Module Name)
module' uri = do
  attachAnno $
    MkModule emptyAnno uri
      <$  annoLexeme_ spaceOrAnnotations
      <*> annoHole anonymousSection

manyLines :: (Pos -> Parser a) -> Parser [a]
manyLines p = do
  current <- Lexer.indentLevel
  manyLinesPos current p

manyLinesPos :: Pos -> (Pos -> Parser a) -> Parser [a]
manyLinesPos current p = do
  many (withIndent EQ current p)

someLines :: (Pos -> Parser a) -> Parser [a]
someLines p = do
  current <- Lexer.indentLevel
  someLinesPos current p

someLinesPos :: Pos -> (Pos -> Parser a) -> Parser [a]
someLinesPos current p = do
  some (withIndent EQ current p)

-- | Run the parser only when the indentation is correct and fail otherwise.
-- Note that indentLevel returns the indentation of the next token, so we only
-- check that next token. If the given parser then consumes additional tokens,
-- they can start at arbitrary positions, but of course their parsers can
-- implement their own checks.
--
withIndent :: (TraversableStream s, MonadParsec e s m) => Ordering -> Pos -> (Pos -> m b) -> m b
withIndent ordering current p = do
  actual <- Lexer.indentLevel
  if compare actual current == ordering
    then do
      p actual
    else do
      fancyFailure . Set.singleton $
        ErrorIndentation ordering current actual

anonymousSection :: Parser (Section Name)
anonymousSection =
  attachAnno $
    MkSection emptyAnno
      <$> annoHole (pure Nothing)
      <*> annoHole (pure Nothing)
      -- The anonymous root section has no '\u00a7' to indent past, so it can never
      -- carry a section binder; the hole is still emitted so that the
      -- 'ToConcreteNodes' \/ 'ToSemTokens' hole order is the same for both
      -- section parsers.
      <*> annoHole (pure Nothing)
      <*> annoHole (lsepBy (const (topdeclWithRecovery 0)) (spacedSymbol_ TSemicolon))

section :: Int -> Parser (Section Name)
section n = do
  -- 'Lexer.indentLevel' reports the column of the NEXT token -- here, of the
  -- '\u00a7' itself, because it peeks and never consumes (see 'withIndent'). That
  -- single fact is what lets ONE combinator accept both ruled spellings of a
  -- section binder: the taught form on the next line indented past the '\u00a7',
  -- and the heading-line form '\u00a7 NAME GIVEN ...', whose GIVEN also sits at a
  -- column greater than the '\u00a7'.
  headingCol <- Lexer.indentLevel
  attachAnno $
    MkSection emptyAnno
      <$> (wrapAnnoParser (try do
             wa@WithAnno {payload = syms} <- unwrapAnnoParser sectionSymbols
             guard (syms >= n)
             pure wa) *> annoHole (optional name)
          )
      <*> annoHole (optional aka)
      -- A GIVEN whose keyword column is greater than the heading's belongs to
      -- the section (R4). 'indented' peeks and fails WITHOUT consuming, so a
      -- column-1 GIVEN falls straight through to 'lsepBy' and stays the next
      -- declaration's signature, exactly as it always was.
      --
      -- The 'try' is load-bearing: 'givens' consumes the GIVEN keyword before
      -- its parameter list can fail, and without backtracking a malformed
      -- section-level parameter list would kill the whole section instead of
      -- falling back to today's reading.
      --
      -- Consuming the binder here also restores the section body's alignment
      -- column: 'lsepBy' \/ 'manyLines' fixes that column from the first token
      -- it sees, so eating a heading-line GIVEN leaves the body at column 1
      -- where it belongs.
      <*> annoHole (optional (try (indented givens headingCol)))
      <*> annoHole (lsepBy (const (topdeclWithRecovery n)) (spacedSymbol_ TSemicolon))

sectionSymbols :: AnnoParser Int
sectionSymbols =
  length <$> Applicative.some (annoLexeme (spacedSymbol_ TParagraph))

topdeclWithRecovery :: Int -> Parser (TopDecl Name)
topdeclWithRecovery n = do
  start <- lookAhead anySingle
  withRecovery
    (\e -> do
      -- Ignoring tokens here is fine, as we will fail parsing any way.
      _ <- takeWhileP Nothing (\t -> not (isSpaceToken t) && t.range.start.column > 1)
      current <- lookAhead anySingle
      registerParseError e
      -- If we didn't make any progress whatsoever,
      -- end parsing to avoid endless loops.
      if start == current
        then parseError e
        else topdeclWithRecovery n

    )
    topdecl
      <|> attachAnno (Section   emptyAnno <$> annoHole (section (n + 1)))

topdecl :: Parser (TopDecl Name)
topdecl =
  -- TIMEZONE IS must be tried before withTypeSig because the meansKW
  -- alternative inside decide would consume TIMEZONE as an identifier
  -- via appForm, preventing backtracking to timezone'.
      try timezone'
  <|> withTypeSig (\ sig -> attachAnno $
        Declare   emptyAnno <$> annoHole (declare sig)
    <|> Decide    emptyAnno <$> annoHole (try (decidePatternMatch sig) <|> decide sig)
    <|> Assume    emptyAnno <$> annoHole (assume sig)
  ) <|> attachAnno
        (Directive emptyAnno <$> annoHole directive)
    <|> attachAnno
        (Import    emptyAnno <$> annoHole import')

localdecl :: Parser (LocalDecl Name)
localdecl =
  withTypeSig (\ sig -> attachAnno $
        LocalDecide    emptyAnno <$> annoHole (decide sig)
    <|> LocalAssume    emptyAnno <$> annoHole (assume sig)
  )

-- | Keywords and operators accepted for bindings in LET...IN blocks: IS, BE, MEAN, MEANS, =
letBindingKeyword :: Parser (Lexeme PosToken)
letBindingKeyword = spacedKeyword_ TKIs
                <|> spacedKeyword_ TKBe
                <|> spacedKeyword_ TKMean
                <|> spacedKeyword_ TKMeans
                <|> spacedToken_ (TOperators TEquals)

-- | Parse an application form for LET bindings
-- Parses: name followed by optional parameters
-- Example: "even n" or "factorial n" or just "x" (no parameters)
-- Similar to appForm but without the OF keyword alternative and without AKA
letAppForm :: Pos -> Parser (AppForm Name)
letAppForm current =
  attachAnno $
    MkAppForm emptyAnno
      <$> annoHole name
      <*> annoHole (lmany (const (indented name current)))
      <*> annoHole (pure Nothing)  -- No AKA for LET bindings

-- | Parse a Decide for use in LET bindings
-- Returns a Decide with proper source range annotations (required by type checker)
letDecide :: Pos -> Parser (Decide Name)
letDecide current =
  letDecideWithExprIndent current current

-- | Like 'letDecide', but allows controlling the indentation threshold for the RHS expression.
-- This is useful for constrained layout relaxations of LET bindings.
letDecideWithExprIndent :: Pos -> Pos -> Parser (Decide Name)
letDecideWithExprIndent bindingIndent exprIndent =
  attachAnno $
    MkDecide emptyAnno
      <$> annoHole (pure emptyTypeSig)
      <*> annoHole (letAppForm bindingIndent)
      <*  annoLexeme letBindingKeyword
      <*> annoHole (indentedExpr exprIndent)
  where
    emptyTypeSig = MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing

-- | Parse a local declaration in a LET block
-- Supports both simple bindings and parameterized function bindings:
--   - Simple: "x IS 5"
--   - Parameterized: "double n IS n TIMES 2"
--   - Multiple params: "add x y IS x PLUS y"
-- Supports @desc annotations both inline and as line annotations.
-- Example: "LET foo BE 1 @desc foo is the loneliest number IN ..."
letLocalDecl :: Parser (LocalDecl Name)
letLocalDecl = do
  current <- Lexer.indentLevel
  attachAnno $
    LocalDecide emptyAnno <$> annoHole (letDecide current)

-- | Parse a LET...IN expression
letInExpr :: Parser (Expr Name)
letInExpr = do
  current <- Lexer.indentLevel
  letLine <- unPos . sourceLine <$> getSourcePos
  attachAnno do
    LetIn emptyAnno
      <$  annoLexeme (spacedKeyword_ TKLet)
      <*> annoHole (try (singleInlineLetDeclRelaxed current letLine) <|> many (indented letLocalDecl current))
      <*  annoLexeme (spacedKeyword_ TKIn)
      <*> annoHole (indentedExpr current)

-- | Parse a single LET binding whose name appears on the same line as the LET keyword,
-- while relaxing the indentation requirement for the RHS expression to be relative to
-- the LET keyword (instead of the binding name). This is intentionally constrained:
-- it only applies when the LET contains exactly one binding (enforced by the caller,
-- which expects IN immediately after parsing this binding).
singleInlineLetDeclRelaxed :: Pos -> Int -> Parser [LocalDecl Name]
singleInlineLetDeclRelaxed letIndent letLine = do
  nextTok <- lookAhead anySingle
  guard (nextTok.range.start.line == letLine)
  bindingIndent <- Lexer.indentLevel
  decl <- attachAnno $
    LocalDecide emptyAnno <$> annoHole (letDecideWithExprIndent bindingIndent letIndent)
  -- Constraint: only apply this relaxation when the LET has exactly one binding.
  -- If another binding starts instead of IN, this alternative must fail so that
  -- we fall back to the regular multi-binding LET parser.
  void $ lookAhead (spacedKeyword_ TKIn)
  pure [decl]

withTypeSig :: (TypeSig Name -> Parser (d Name)) -> Parser (d Name)
withTypeSig p = do
  sig <- typeSig
  p sig

directive :: Parser (Directive Name)
directive =
  attachAnno $
    choice
      -- Use singleLineExpr for simple directives to make them line-oriented.
      -- Continuation to next line requires '# ' prefix (like C preprocessor).
      [ LazyEval emptyAnno
          <$ annoLexeme (spacedToken_ (TDirectives TLazyEvalDirective))
          <*> annoHole singleLineExpr
      , LazyEvalTrace emptyAnno
          <$ annoLexeme (spacedToken_ (TDirectives TLazyEvalTraceDirective))
          <*> annoHole singleLineExpr
      , Check emptyAnno
          <$ annoLexeme (spacedToken_ (TDirectives TCheckDirective))
          <*> annoHole singleLineExpr
      , Contract emptyAnno
          <$ annoLexeme (spacedToken_ (TDirectives TContractDirective))
          <*> annoHole singleLineExpr
          <* optional (annoLexeme (spacedKeyword_ TKStarting))
          <* annoLexeme (spacedKeyword_ TKAt)
          <*> annoHole singleLineExpr
          <* annoLexeme (spacedKeyword_ TKWith)
          <*> contractEvents
      -- #ASSERT REFUSED e [BECAUSE "message"].  'tryParser' is load-bearing:
      -- this alternative consumes the #ASSERT token before it can discover
      -- there is no REFUSED, and without backtracking the plain #ASSERT
      -- alternative below would never be reached.
      --
      -- The BECAUSE payload is a LITERAL ('lit'), matching 'refuse' -- REFUSE's
      -- own message is a literal for the same reason, and the two must agree.
      -- The directive's job is to pin a refusal's reason, and the comparison is
      -- decided statically in 'evalDirective' without evaluating the payload; a
      -- payload the evaluator cannot read statically would silently degrade to
      -- "no constraint", i.e. an assertion that holds for ANY refusal reason.
      -- So a non-literal payload is a parse error, not a vacuous success.
      , tryParser $
          AssertRefused emptyAnno
          <$ annoLexeme (spacedToken_ (TDirectives TAssertDirective))
          <* annoLexeme (spacedKeyword_ TKRefused)
          <*> annoHole singleLineExpr
          <*> optionalWithHole (annoLexeme (spacedKeyword_ TKBecause) *> annoHole lit)
      , Assert emptyAnno
          <$ annoLexeme (spacedToken_ (TDirectives TAssertDirective))
          <*> annoHole singleLineExpr
      ]

contractEvents :: AnnoParser [Expr Name]
contractEvents = annoHole $ lmany (const expr)

import' :: Parser (Import Name)
import' =
  attachAnno $
    MkImport emptyAnno
      <$  annoLexeme (spacedKeyword_ TKImport)
      <*> annoHole name
      <*> pure Nothing

-- | Parse @TIMEZONE IS <expr>@
-- TIMEZONE is not a keyword — it's matched as an identifier so it can
-- also be used as a builtin name in expressions.
--
-- The TIMEZONE and IS tokens are captured into the node's 'Anno' (via
-- 'annoLexeme') rather than skipped with '*>', so exactprint reproduces the
-- @TIMEZONE IS <expr>@ source instead of emitting just the bare expression.
timezone' :: Parser (TopDecl Name)
timezone' =
  attachAnno $
    Timezone emptyAnno
      <$  annoLexeme (spacedToken_ (TIdentifiers (TIdentifier "TIMEZONE")))
      <*  annoLexeme (spacedKeyword_ TKIs)
      <*> annoHole expr

assume :: TypeSig Name -> Parser (Assume Name)
assume sig = do
  current <- Lexer.indentLevel
  attachAnno $
    MkAssume emptyAnno
      <$> annoHole (pure sig)
      <*  annoLexeme (spacedKeyword_ TKAssume)
      <*> annoHole appForm
      <*> optionalHole (annoLexeme (spacedKeyword_ TKIs) *> {- optional article *> -} annoHole (indented type' current))
      <*> optionalHole (annoLexeme (spacedKeyword_ TKTypically) *> annoHole atomicExpr')

declare :: TypeSig Name -> Parser (Declare Name)
declare sig =
  attachAnno $
    MkDeclare emptyAnno
      <$> annoHole (pure sig)
      <*  annoLexeme (spacedKeyword_ TKDeclare)
      <*> annoHole appForm
      <*> annoHole typeDecl

typeDecl :: Parser (TypeDecl Name)
typeDecl =
  recordDecl <|> enumOrSynonymDecl <|> opaqueDecl

-- | A bodiless @DECLARE T@: an opaque nominal type ('OpaqueDecl'). Tried
-- LAST, so any body that is present wins, and it consumes no input: a
-- @DECLARE@ whose body is missing or malformed therefore parses as opaque
-- and the next token is judged as the start of the following declaration
-- (megaparsec keeps the @HAS@\/@IS@ hints, so the error still lists them).
-- The node's 'Anno' is empty — the same shape a 'TypeSig' with no @GIVEN@
-- already has — which both printers render as nothing.
opaqueDecl :: Parser (TypeDecl Name)
opaqueDecl =
  attachAnno $ pure (OpaqueDecl emptyAnno)

recordDecl :: Parser (TypeDecl Name)
recordDecl =
  attachAnno $
    RecordDecl emptyAnno
      <$> annoHole (pure Nothing)
      <*> recordDecl'

recordDecl' :: AnnoParser [TypedName Name]
recordDecl' =
     annoLexeme (spacedKeyword_ TKHas)
  *> annoHole (lsepBy (const reqParam) (spacedSymbol_ TComma))

enumOrSynonymDecl :: Parser (TypeDecl Name)
enumOrSynonymDecl =
  attachAnno $
       annoLexeme (spacedKeyword_ TKIs)
    *> (enumDecl <|> synonymDecl)

separator :: Parser (Lexeme PosToken)
separator = spacedKeyword_ TKIs <|> hidden (spacedSymbol_ TColon)

enumDecl :: AnnoParser (TypeDecl Name)
enumDecl =
  EnumDecl emptyAnno
    <$  annoLexeme (spacedKeyword_ TKOne)
    <*  annoLexeme (spacedKeyword_ TKOf)
    <*> annoHole (lsepBy (const conDecl) (spacedSymbol_ TComma))

synonymDecl :: AnnoParser (TypeDecl Name)
synonymDecl =
  SynonymDecl emptyAnno
    <$> annoHole type'

conDecl :: Parser (ConDecl Name)
conDecl =
  attachAnno $
    MkConDecl emptyAnno
      <$> annoHole name
      <*> option [] recordDecl'

decide :: TypeSig Name -> Parser (Decide Name)
decide sig = do
  current <- Lexer.indentLevel
  decideKW current <|> meansKW current
  where
    decideKW current =
      attachAnno $
        MkDecide emptyAnno
          <$> annoHole (pure sig)
          <*  annoLexeme (spacedKeyword_ TKDecide)
          <*> annoHole appForm
          <*  annoLexeme (spacedKeyword_ TKIs <|> spacedKeyword_ TKIf)
          <*> annoHole (clauseBody current)

    meansKW current =
      attachAnno $
        MkDecide emptyAnno
          <$> annoHole (pure sig)
          <*> annoHole appForm
          <*  annoLexeme (spacedKeyword_ TKMeans)
          <*> annoHole (clauseBody current)

-- ----------------------------------------------------------------------------
-- Pattern matching in function definitions (Phase 1)
--
-- Haskell-style multi-clause function definitions with literal and constructor
-- patterns on the DECIDE/MEANS left-hand side, desugared here (in the parser) to
-- the existing CONSIDER/WHEN machinery. See
-- specs/todo/PATTERN-MATCHING-SPEC.md, "Approach 1: Desugar to CONSIDER/WHEN".
--
-- Note: the anonymous wildcard @_@ from the spec is not currently accepted by
-- the lexer; per the spec's own guidance, an ignored argument reuses its GIVEN
-- name instead (which desugars to nothing).
--
-- Example:
--
-- > GIVEN n IS A NUMBER
-- > GIVETH A NUMBER
-- > DECIDE factorial 0 IS 1
-- > DECIDE factorial n IS n * factorial (n - 1)
--
-- is lowered to a single 'MkDecide' whose body is:
--
-- > CONSIDER n
-- > WHEN 0 THEN 1
-- > OTHERWISE n * factorial (n - 1)
--
-- The clauses share a single GIVEN/GIVETH signature (as in Haskell, the type
-- signature precedes the clauses), so an entire pattern-matching function is
-- one 'TopDecl'.
-- ----------------------------------------------------------------------------

-- | A single parsed clause of a (potentially) multi-clause pattern-matching
-- function. This is an internal parser artifact only; it never enters the AST.
-- (Positional rather than record fields because this module uses
-- @NoFieldSelectors@.)
data PMClause = PMClause Name [Pattern Name] (Maybe (Aka Name)) (Expr Name)

pmHead :: PMClause -> Name
pmHead (PMClause h _ _ _) = h

pmPats :: PMClause -> [Pattern Name]
pmPats (PMClause _ ps _ _) = ps

pmAka :: PMClause -> Maybe (Aka Name)
pmAka (PMClause _ _ ak _) = ak

pmBody :: PMClause -> Expr Name
pmBody (PMClause _ _ _ b) = b

-- | Parse a group of one-or-more DECIDE/MEANS clauses that share a head name
-- and arity (and the enclosing GIVEN/GIVETH signature), and lower them to a
-- single 'MkDecide'. Fails (so the caller falls back to the ordinary 'decide'
-- parser) unless at least one clause carries a /distinguishable/ pattern (a
-- literal, an applied constructor, a cons, or an EXACTLY expression), or the
-- run has two clauses or more whose bare names differ in some column. This
-- keeps ordinary single-clause definitions (including mixfix and @OF@ forms) on
-- the existing code path; a run of the second kind that turns out to be
-- overloads is separated again by the checker ('L4.TypeCheck.separateOverloads').
decidePatternMatch :: TypeSig Name -> Parser (Decide Name)
decidePatternMatch sig = do
  clauseCol <- Lexer.indentLevel
  -- A clause of a run already turned down below starts no group either, so
  -- fail at once, with the error the run failed with (see 'turnDownRun').
  start <- getOffset
  turnedDown <- runTurnedDown start
  for_ turnedDown parseError
  recordRunFailure $ do
    -- Capture the raw token span of the whole clause group. The clauses are
    -- fused into a single CONSIDER tree below (whose synthetic nodes carry no
    -- source tokens), so exactprint cannot reproduce the multi-clause source
    -- structurally. Instead we store these verbatim tokens as one visible CSN on
    -- the resulting Decide's annotation, and drop the hole for the fused body, so
    -- @l4 format@ round-trips the source (see 'desugarPatternClauses').
    (rawToks, (firstClause, rest, restStarts)) <- match $ do
      firstClause <- pmClause clauseCol
      let firstHead  = pmHead firstClause
          firstArity = length (pmPats firstClause)
      rest <- many (try (withIndent EQ clauseCol (\ _ -> (,) <$> getOffset <*> sameHeadClause clauseCol firstHead firstArity)))
      pure (firstClause, map snd rest, map fst rest)
    let clauses = firstClause : rest
    -- Treat this as pattern matching when either:
    --
    --  * at least one clause carries a clearly /distinguishable/ pattern (a
    --    literal, an applied constructor, a cons, or an EXACTLY expression); or
    --
    --  * it is a genuine multi-clause group (>= 2 clauses) discriminated only by
    --    differing nullary columns, e.g. @DECIDE f TRUE IS 1 / DECIDE f FALSE IS
    --    0@ or an enum decision table. A bare @PatApp n []@ is ambiguous at parse
    --    time between a variable and a nullary constructor (@TRUE@ / @EMPTY@), so
    --    we require >= 2 clauses AND at least one column whose bare names actually
    --    differ across the group before committing.
    --
    -- The second kind can gather overloads: @show n MEANS n + 1@ followed by
    -- @show b MEANS b AND TRUE@ is two definitions told apart by their types,
    -- and its bare names differ too. Which it is depends on whether any of the
    -- names is a constructor, which only resolving them tells, so the checker
    -- turns such a group back into the separate definitions it is made of when
    -- none is ('L4.TypeCheck.separateOverloads'). Overloads that each carry their
    -- own GIVEN/GIVETH signature (such as the two @`is leap year`@ overloads in
    -- daydate.l4) are never gathered here: an intervening GIVEN makes
    -- 'sameHeadClause' fail. A lone bare-name clause still falls through to the
    -- ordinary 'decide' path.
    let isGroup = any clauseIsPatternMatching clauses || nullaryOnlyDiscriminatingGroup clauses
    unless isGroup $ turnDownRun (start : restStarts)
    guard isGroup
    pure (desugarPatternClauses sig rawToks firstClause rest)
  where
    sameHeadClause clauseCol h ar = do
      c <- pmClause clauseCol
      guard (rawName (pmHead c) == rawName h && length (pmPats c) == ar)
      pure c
    clauseIsPatternMatching c = any isDistinguishablePat (pmPats c)
    -- A >= 2-clause group in which every argument column is a bare name and at
    -- least one column's bare names differ across clauses (the hallmark of
    -- discrimination by nullary constructors / booleans / enums).
    nullaryOnlyDiscriminatingGroup cs =
         length cs >= 2
      && all (all isBareNullaryPat . pmPats) cs
      && any columnDiffers (List.transpose (map pmPats cs))
    isBareNullaryPat (PatApp _ _ []) = True
    isBareNullaryPat _               = False
    columnDiffers col =
      length (List.nub [ rawName n | PatApp _ n [] <- col ]) > 1

-- | Record that the clauses starting at these positions start no clause group.
--
-- 'topdecl' tries 'decidePatternMatch' at every definition. When it turns a
-- run of same-headed clauses down, it has read them all, and each of them is
-- then parsed as a definition of its own, where 'decidePatternMatch' is tried
-- again and would read the rest of the run again: a run of @n@ clauses was
-- read about @n * n / 2@ times, so a file of 4,000 lines @f x MEANS i@ took
-- minutes to check. Every suffix of a run turned down is turned down too: no
-- clause in it has a distinguishable pattern, and either it has one clause or
-- no column of it holds two different names, and both stay true of every
-- suffix. So the positions of its clauses are recorded below megaparsec,
-- where backtracking does not undo them (as 'memoGroup' does), and
-- 'decidePatternMatch' fails at once at any of them.
--
-- It fails there with the error the run itself failed with
-- ('recordRunFailure'): reading the rest of the run from any of its clauses
-- fails at the same place, the run's end, in the same way, so the error a
-- file reports is the same whether the run is read again or not. The
-- positions wait in 'turnedDownRun' until the attempt fails, which it does at
-- once, and are then recorded with its error.
--
-- Like 'memoGroup', this is off when 'memoiseGroups' is, so that jl4-test's
-- "parser memo changes nothing" check covers it too.
turnDownRun :: [Int] -> Parser ()
turnDownRun starts = do
  memo <- asks (.memoiseGroups)
  when memo $
    lift (lift (lift (modify' (over #turnedDownRun (starts <>)))))

-- | The error a run turned down at this position failed with
-- ('turnDownRun'), if there is one.
runTurnedDown :: Int -> Parser (Maybe (ParseError TokenStream Void))
runTurnedDown start = do
  memo <- asks (.memoiseGroups)
  if memo
    then lift (lift (lift (gets (IntMap.lookup start . view #notClauseGroups))))
    else pure Nothing

-- | Run an attempt at a clause group, and when it fails having turned a run
-- down ('turnDownRun'), record the error it failed with at every clause of
-- that run. The error is the one handed on to what follows, hints included,
-- so failing with it again is failing as the attempt did.
--
-- Every definition is tried as a clause group, and every definition that is
-- not one fails here, so recording costs only the run just turned down, and
-- nothing when there is none: a file of @n@ definitions with @n@ different
-- names fails here @n@ times.
recordRunFailure :: Parser a -> Parser a
recordRunFailure p =
  ReaderT \ env -> StateT \ st -> Megaparsec.ParsecT \ s cok cerr eok eerr ->
    let record e = do
          run <- gets (view #turnedDownRun)
          unless (null run) $
            modify' (over #notClauseGroups (IntMap.union (IntMap.fromList [ (o, e) | o <- run ])) . set #turnedDownRun [])
    in Megaparsec.unParser (runStateT (runReaderT p env) st) s cok
         (\ e s' -> record e >> cerr e s')
         eok
         (\ e s' -> record e >> eerr e s')

-- | Parse a single clause, in either the @DECIDE head pats IS body@ form or the
-- @head pats MEANS body@ form. Argument patterns are parsed with
-- 'atomicPattern', so applied constructors must be parenthesised (as in
-- Haskell), e.g. @(JUST n)@ or @(x FOLLOWED BY xs)@.
pmClause :: Pos -> Parser PMClause
pmClause clauseCol =
      pmDecideForm
  <|> pmMeansForm
  where
    pmArgs = many (indented atomicPattern clauseCol)
    pmDecideForm = do
      _  <- spacedKeyword_ TKDecide
      hd <- name
      ps <- pmArgs
      ak <- optional aka
      _  <- spacedKeyword_ TKIs <|> spacedKeyword_ TKIf
      b  <- clauseBody clauseCol
      pure (PMClause hd ps ak b)
    pmMeansForm = do
      hd <- name
      ps <- pmArgs
      ak <- optional aka
      _  <- spacedKeyword_ TKMeans
      b  <- clauseBody clauseCol
      pure (PMClause hd ps ak b)

-- | The body of a @DECIDE@ or @MEANS@ clause that starts in column @col@,
-- parsed at most once per position ('memoGroupAt'). Every definition is read
-- first as a clause ('pmClause', for 'decidePatternMatch') and, unless it
-- starts a clause group, again as an ordinary definition ('decide'); both
-- readings parse the same body at the same position with the same column,
-- so the second replays the first instead of parsing the body again.
clauseBody :: Pos -> Parser (Expr Name)
clauseBody col = memoGroupAt (unPos col) #clauseBodies (indentedExpr col)


-- | Extract the term (value) parameter names from a GIVEN signature, skipping
-- type parameters (@x IS A TYPE@). These are used as the CONSIDER scrutinees.
givenTermNames :: TypeSig Name -> [Name]
givenTermNames = map fst . givenTermParams

-- | The term parameters of a GIVEN signature, each with whether it declares
-- a type.
givenTermParams :: TypeSig Name -> [(Name, Bool)]
givenTermParams (MkTypeSig _ (MkGivenSig _ otns) _) =
  [ (n, isJust mt) | MkOptionallyTypedName _ n mt _ <- otns, notTypeParam mt ]
  where
    notTypeParam (Just (Type _)) = False
    notTypeParam _               = True

-- | Lower a non-empty list of same-head clauses to a single 'MkDecide' whose
-- body is a (possibly nested) CONSIDER. Clauses are tried top-to-bottom,
-- first match wins (Haskell semantics). If no clause matches at runtime, the
-- generated CONSIDER falls through with no OTHERWISE, which the evaluator turns
-- into a 'NonExhaustivePatterns' error (Haskell's non-exhaustive-match error).
desugarPatternClauses :: TypeSig Name -> [PosToken] -> PMClause -> [PMClause] -> Decide Name
desugarPatternClauses sig rawToks firstC restCs =
  MkDecide decideAnno sig theAppForm body
  where
    clauses  = firstC : restCs
    headName = pmHead firstC
    mAka     = listToMaybe (mapMaybe pmAka clauses)
    arity    = length (pmPats firstC)
    givenNs  = givenTermNames sig
    appFormAnno = mkHoleAnnoFor headName
    usesGivenNames = length givenNs == arity && arity > 0
    -- Whether the GIVEN declares each column's type; a synthesized column
    -- has none.
    typesDeclared
      | usesGivenNames = map snd (givenTermParams sig)
      | otherwise      = replicate arity False
    -- The inputs are the GIVEN's names, written into the definition here at
    -- the GIVEN's own location ('givenInputBinding'), or, when the GIVEN does
    -- not name one input per pattern, names the desugarer makes up.
    (theAppForm, scrutinees)
      | usesGivenNames =
          (MkAppForm appFormAnno headName (map givenInputBinding givenNs) mAka, givenNs)
      | otherwise =
          let synth = [ generatedName ("input " <> Text.pack (show i)) | i <- [1 .. arity] ]
          in (MkAppForm appFormAnno headName synth mAka, synth)
    grp = MkPmGroup { groupHead = rawName headName, clauseCount = length clauses }
    body = matchClauses grp scrutinees typesDeclared clauses
    -- The signature is exact-printed structurally (via its hole); the whole
    -- clause group is reproduced verbatim from the captured raw tokens as a
    -- single visible CSN. We deliberately emit NO holes for 'theAppForm' or the
    -- fused 'body', so exactprint never descends into the synthetic CONSIDER
    -- tree (whose nodes carry no source tokens) — it would otherwise emit
    -- nothing and drop the clause bodies. The resulting annotation still spans
    -- the sig + all clauses, giving the Decide a real, distinct SrcRange for the
    -- type checker's per-function 'FunTypeSig' keying.
    --
    -- The source clause matrix is additionally recorded in the annotation's
    -- 'Extension' ('setPmMatrix'), for the type checker's clause-matrix
    -- exhaustiveness analysis: 'matchClauses' below destroys the per-clause
    -- structure (its synthetic CONSIDERs are rangeless and OTHERWISE-total),
    -- so the analysis must see the matrix as the drafter wrote it. We attach
    -- it for EVERY fused group, n = 1 included, and the checker analyses
    -- every one: the synthetic CONSIDERs are marked ('PmConsider') and never
    -- warn about missing branches themselves. Exactprint is
    -- unaffected: it reads the 'payload' CSNs, never the 'extra' field, and
    -- 'fixAnnoSrcRange' sets only the range.
    decideAnno =
      setPmMatrix matrix (fixAnnoSrcRange (mkHoleAnnoFor sig <> rawTokensAnno rawToks))
    matrix = MkPmMatrix
      { scrutinees = scrutinees
      , synthesizedScrutinees = not usesGivenNames
      , clauses =
          [ MkPmMatrixClause
              { headRange = rangeOf (pmHead c)
              , patterns  = pmPats c
              , clauseHead = pmHead c
              , clauseAka = pmAka c
              , clauseDescs = []
              , clauseNlgs = []
              , bodyRange = rangeOf (pmBody c)
              }
          | c <- clauses
          ]
      , catchAll = List.findIndex (clauseMatchesAnything scrutinees . pmPats) clauses
      }

-- | A name the desugarer makes up, spelled with 'PreDef', which no source can
-- write: a backticked @`input 1`@ is a 'NormalName', and so a different name.
-- Neither direction can capture the other, so a drafter may use any name at
-- all, and the generated code still means what the desugarer wrote. The text
-- is how the name reads wherever it is shown (@l4 render@, a trace).
--
-- The one place it can be captured is a /printed/ module (@l4 batch@, the
-- REPL), which writes it back as source.
generatedName :: Text -> Name
generatedName = MkName emptyAnno . PreDef

-- | The binding of a GIVEN input in the definition of a multi-clause group.
-- The drafter wrote the name once, in the GIVEN, so this copy has the GIVEN's
-- location, to say where the input is defined (a message about it would
-- otherwise call it "predefined"), but none of its tokens, so that nothing
-- prints or highlights it twice. A name's location is read off its anno's
-- elements, so the location is kept as a hole that holds no tokens.
givenInputBinding :: Name -> Name
givenInputBinding n = overAnno (set #payload [mkHoleWithSrcRangeHint (rangeOf n)]) n

-- | How a generated CONSIDER reads the input it tests: by the input's name
-- respelled with 'PreDef' (see 'generatedName'), so that a pattern variable an
-- earlier column binds, which may have the same name, cannot capture it. For a
-- GIVEN input the type checker makes this spelling another name of the input
-- ('L4.TypeCheck.clauseInputSpellings'); a made-up input is already spelled so.
scrutineeRef :: Name -> Expr Name
scrutineeRef s = App emptyAnno (generatedName (nameToText s)) []

-- | Build an annotation whose single visible concrete-syntax node holds the
-- given tokens verbatim (no holes). Used to make a fused pattern-matching
-- 'Decide' exact-print back to its original multi-clause source.
--
-- The last clause's final lexeme also consumed the whitespace, comments and
-- annotations after the group (up to the next definition's first token).
-- They are kept as trailing tokens (a hidden node): exactprint still
-- reproduces them, but they are outside the node's range, so the group's
-- range stops at its last clause and does not run over the next
-- definition's comments, @\@desc@, @\@export@ or @\@nlg@. (An @\@nlg@ the
-- group's range ran over was not the next definition's to take, and went
-- unused or to a node of the group's.)
rawTokensAnno :: [PosToken] -> Anno
rawTokensAnno toks =
  mkSimpleEpaAnno Epa
    { original       = reverse revBody
    , trailingTokens = reverse revTrailing
    , payload        = ()
    , hiddenClusters = []
    }
  where
    (revTrailing, revBody) = span isTrailingTrivia (reverse toks)
    isTrailingTrivia t = isSpaceToken t || isAnnotationToken t

-- | Build a decision list from the clauses. The last clause is compiled without
-- an OTHERWISE fallthrough so that a non-match becomes a runtime
-- non-exhaustive-pattern error.
--
-- To keep the emitted tree /linear/ in (clauses x columns) rather than
-- exponential, we never duplicate the desugaring of the remaining clauses.
-- 'matchOne' references the fall-through in every WHEN and OTHERWISE position,
-- so if we inlined it we would copy the whole clause tail once per
-- distinguishable column, compounding multiplicatively. Instead, at each
-- non-final clause boundary we bind the remaining-clauses expression to a single
-- fresh local (a nullary @LET ... IN@) and let 'matchOne' refer to it by name.
-- The name says which clauses the binding holds (see 'fallthroughName'), and
-- is spelled so that no source can write it ('generatedName'): a clause body
-- naming a definition @`the result of clauses 2 to 3`@ reads that definition,
-- never this binding. Nothing downstream reads the name: the binding and
-- every generated CONSIDER are marked with 'PmSynthetic'.
matchClauses :: PmGroup -> [Name] -> [Bool] -> [PMClause] -> Expr Name
matchClauses grp scrutinees typesDeclared = go 0
  where
    columns = zip3 [1 ..] typesDeclared scrutinees
    go :: Int -> [PMClause] -> Expr Name
    go _ []  = error "L4.Parser.matchClauses: empty clause list (impossible)"
    go _ [c] = matchLast grp columns (pmPats c) (pmBody c)
    go k (c : cs) =
      -- Bind the desugaring of the remaining clauses ONCE, then reference it
      -- by name from every WHEN/OTHERWISE that 'matchOne' emits.
      --
      -- When every column of @c@ matches unconditionally, @c@ always fires and
      -- 'matchOne' returns its body without referencing the fall-through, so
      -- the binding is dead and the remaining clauses never run. It is bound
      -- anyway, marked 'PmUnreachable', so that they are still type-checked
      -- (the checker gives it the group's result type, see
      -- 'L4.TypeCheck.checkClausesLet') and then dropped from the
      -- checked tree, which is therefore the one this function emitted before
      -- it bound them: evaluation and every exporter see no difference. The
      -- checker warns that they are unreachable (from 'PmMatrix' @catchAll@).
      let ftName = fallthroughName grp (k + 2)
          ftExpr = go (k + 1) cs
          tree   = matchOne grp columns (pmPats c) (pmBody c) (Var emptyAnno ftName)
          mark
            | clauseMatchesAnything scrutinees (pmPats c) = PmUnreachable grp
            | otherwise                                   = PmFallthrough grp
      in bindFallthrough mark ftName (clausesSrcAnno cs) ftExpr tree

-- | Does every column of this clause match unconditionally? Then the clause
-- always fires, and no clause after it is ever tried. This must mirror
-- 'matchOne' / 'patAlwaysMatchesAs'.
clauseMatchesAnything :: [Name] -> [Pattern Name] -> Bool
clauseMatchesAnything scrutinees pats = and (zipWith patAlwaysMatchesAs scrutinees pats)

-- | The name of the once-bound fall-through holding the clauses from clause
-- @i@ (counting from 1) to the last: @the result of clauses 2 to 3@, or
-- @the result of clause 3@. It is unique to its nesting level, so no two
-- bindings of one group share a name.
fallthroughName :: PmGroup -> Int -> Name
fallthroughName grp i =
  generatedName $ "the result of " <> case grp.clauseCount of
    n | n == i    -> "clause " <> Text.pack (show n)
      | otherwise -> "clauses " <> Text.pack (show i) <> " to " <> Text.pack (show n)

-- | The source range of the binding of the clauses from the first of @cs@ on:
-- the range of that clause's body. The synthesized fall-through 'MkDecide'
-- needs a present, distinct src range because the type checker keys each
-- function's 'FunTypeSig' by its Decide annotation's range (see
-- 'scanFunSigDecide' / 'inferDecide'). Each level's first clause is a
-- different clause, so these ranges are non-empty and mutually distinct.
--
-- Only the body, never more: anything that looks nodes up by position (hover,
-- go-to-definition) finds this binding wherever its range reaches and no
-- written node is closer. An earlier range, the hull of all the bodies, also
-- covered the heads and patterns of the clauses between them, and hover on a
-- pattern there answered with the type of the binding.
-- Note: @cs@ is always non-empty here (the singleton clause list is handled by
-- the @[c]@ case of 'matchClauses', so a fall-through is only bound when at least
-- one further clause remains).
clausesSrcAnno :: [PMClause] -> Anno
clausesSrcAnno []      = emptyAnno
clausesSrcAnno (c : _) = fixAnnoSrcRange (mkHoleAnnoFor (pmBody c))

-- | Bind @ftExpr@ to @ftName@ via a nullary @LET ... IN@, so the fall-through is
-- emitted exactly once and referenced by name from the CONSIDER tree. Evaluates
-- identically to inlining @ftExpr@ at each reference (it is a pure, argument-less
-- binding), but keeps the emitted AST linear. @ftAnno@ supplies the Decide's
-- source range (see 'clausesSrcAnno').
bindFallthrough :: PmSynthetic -> Name -> Anno -> Expr Name -> Expr Name -> Expr Name
bindFallthrough mark ftName ftAnno ftExpr body =
  LetIn emptyAnno
    [ LocalDecide emptyAnno
        (MkDecide (setPmSynthetic mark ftAnno) emptyTypeSig (MkAppForm emptyAnno ftName [] Nothing) ftExpr)
    ]
    body
  where
    emptyTypeSig = MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing

-- | A CONSIDER the desugarer generates to test the input in column @col@.
generatedConsider :: PmGroup -> (Int, Bool, Name) -> [Branch Name] -> Expr Name
generatedConsider grp (col, declared, s) =
  Consider (setPmSynthetic (PmConsider grp col declared) emptyAnno) (scrutineeRef s)

-- | Compile one non-final clause: match every column against its scrutinee; on
-- any mismatch, fall through to @ft@ (the desugaring of the remaining clauses).
matchOne :: PmGroup -> [(Int, Bool, Name)] -> [Pattern Name] -> Expr Name -> Expr Name -> Expr Name
matchOne _   _                  []       body _  = body
matchOne grp (c@(_, _, s) : ss) (p : ps) body ft
  -- A variable pattern that reuses the scrutinee's name (as the spec mandates),
  -- or the anonymous wildcard, always matches and needs no (re)binding.
  | patAlwaysMatchesAs s p = matchOne grp ss ps body ft
  -- Everything else gets a WHEN plus an OTHERWISE fall-through. We must emit the
  -- OTHERWISE even for a bare @PatApp n []@ because, at desugar time (pre
  -- scope-check), we cannot tell a fresh variable (always matches) from a
  -- nullary constructor such as @TRUE@ / @EMPTY@ / @NOTHING@ (can fail). Emitting
  -- the fall-through is correct for both: a variable simply leaves it dead.
  | otherwise =
      generatedConsider grp c
        [ MkBranch emptyAnno (When emptyAnno p) (matchOne grp ss ps body ft)
        , MkBranch emptyAnno (Otherwise emptyAnno) ft
        ]
matchOne _   []                 (_ : _)  body _  = body -- more patterns than scrutinees: ignore extras

-- | Compile the final clause without an OTHERWISE branch (so a non-match is a
-- runtime non-exhaustive error, matching Haskell semantics).
matchLast :: PmGroup -> [(Int, Bool, Name)] -> [Pattern Name] -> Expr Name -> Expr Name
matchLast _   _                  []       body = body
matchLast grp (c@(_, _, s) : ss) (p : ps) body
  | patAlwaysMatchesAs s p = matchLast grp ss ps body
  | otherwise =
      generatedConsider grp c
        [ MkBranch emptyAnno (When emptyAnno p) (matchLast grp ss ps body) ]
matchLast _   []                 (_ : _)  body = body -- more patterns than scrutinees: ignore extras


appForm :: Parser (AppForm Name)
appForm = do
  current <- Lexer.indentLevel
  attachAnno $
    MkAppForm emptyAnno
      <$> annoHole name
      <*> (   annoLexeme (spacedKeyword_ TKOf) *> annoHole (lsepBy1 (const name) (spacedSymbol_ TComma))
          <|> annoHole (lmany (const (indented name current)))
          )
      <*> annoHole (optional aka)

aka :: Parser (Aka Name)
aka =
  attachAnno $
    MkAka emptyAnno
      <$  annoLexeme (spacedKeyword_ TKAka)
      <*> annoHole (lsepBy (const name) (spacedSymbol_ TComma))

typeSig :: Parser (TypeSig Name)
typeSig =
  attachAnno $
    MkTypeSig emptyAnno
      <$> annoHole (option (MkGivenSig emptyAnno []) givens)
      <*> annoHole (optional giveth)

givens :: Parser (GivenSig Name)
givens =
  attachAnno $
    MkGivenSig emptyAnno
      <$  annoLexeme (spacedKeyword_ TKGiven)
      <*> annoHole (lsepBy (const param) (spacedSymbol_ TComma))

giveth :: Parser (GivethSig Name)
giveth = do
  current <- Lexer.indentLevel
  attachAnno $
    MkGivethSig emptyAnno
      <$  annoLexeme (spacedKeyword_ TKGiveth <|> spacedKeyword_ TKGives)
--      <*  optional article
      <*> annoHole (indented type' current)

-- This isn't ideal, because it says an expr must be indented
-- (and `mkPos` does not allow 0).
--
expr :: Parser (Expr Name)
expr =
  indentedExpr (mkPos 1)

type' :: Parser (Type' Name)
type' =
      withOptionalArticle
      (   typeKind
      <|> tyApp
      <|> fun
      )
  <|> forall'
  <|> paren type'

typeKind :: Parser (Type' Name)
typeKind =
  attachAnno $
  Type emptyAnno <$ annoLexeme (spacedKeyword_ TKType)

atomicType :: Parser (Type' Name)
atomicType =
      withOptionalArticle
      (   typeKind
      <|> nameAsApp TyApp
      )
  <|> paren type'

paren :: (AnnoToken a ~ PosToken, HasAnno a, HasSrcRange a) => Parser a -> Parser a
paren p =
  inlineAnnoHole $
    id
    <$  annoLexeme (spacedSymbol_ TPOpen)
    <*> annoHole (inExprSlot p)
    <*  annoLexeme (spacedSymbol_ TPClose)

-- | Parse @p@ as an ordinary expression: inside parentheses (and inside a
-- deadline's anchor) @OF@ is application again, whatever the enclosing
-- @WITHIN@ slot says. See 'Env'.
inExprSlot :: Parser a -> Parser a
inExprSlot = local \ e -> e { ofIsAnchor = False }

-- | A bracketed expression, @(e)@, parsed at most once per position: see
-- 'memoGroup'.
parenExpr :: Parser (Expr Name)
parenExpr = memoGroup #exprGroups (paren expr)

-- | A bracketed pattern, @(p)@, parsed at most once per position: see
-- 'memoGroup'.
parenPattern :: Parser (Pattern Name)
parenPattern = memoGroup #patternGroups (paren pattern')

-- | Every outcome 'memoGroup' has recorded in one run of the parser, by
-- position. It lives below megaparsec in the 'Parser' stack, so backtracking
-- does not discard it.
data GroupMemo = MkGroupMemo
  { exprGroups :: !(IntMap.IntMap (GroupReply (Expr Name)))
  , patternGroups :: !(IntMap.IntMap (GroupReply (Pattern Name)))
  , clauseBodies :: !(IntMap.IntMap (GroupReply (Expr Name)))
    -- ^ The body of a @DECIDE@ or @MEANS@ clause ('clauseBody').
  , notClauseGroups :: !(IntMap.IntMap (ParseError TokenStream Void))
    -- ^ The positions of clauses that start no clause group, every clause of
    -- a run 'decidePatternMatch' has turned down, with the error the run
    -- failed with ('turnDownRun').
  , turnedDownRun :: ![Int]
    -- ^ The positions of the run just turned down, until the attempt that
    -- turned it down fails ('recordRunFailure').
  }
  deriving stock Generic

emptyGroupMemo :: GroupMemo
emptyGroupMemo = MkGroupMemo IntMap.empty IntMap.empty IntMap.empty IntMap.empty []

-- | Everything one parse of a group came to, as megaparsec reports it: the
-- state it left (offset, input, delayed errors), whether it consumed input,
-- and either the value with its hints and the annotations it collected, or
-- the error. 'Megaparsec.runParsecT' produces it and 'memoGroup' replays it.
type GroupReply a = Megaparsec.Reply Void TokenStream (a, PState)

-- | @memoGroup table p@ behaves exactly as @p@, but parses at most once at
-- each position, for each value of 'ofIsAnchor' (MATRYOSHKA,
-- smucclaw/l4-ide#1017).
--
-- __Why.__ A bracketed group can be parsed more than once at the same
-- position, by two alternatives that both start with it. In pattern position
-- the group is tried as a pattern and then as an expression
-- ('parenPatternOrExpr'); when it holds a @CONSIDER@ or a @MUST@ whose own
-- pattern slot holds the next bracket, the failed pattern attempt has already
-- parsed the inner group, and the expression reading parses it again. Nested,
-- that doubles with every level. Here the second parse of a group at a
-- position replays the first.
--
-- __Why replaying is exact.__ The first parse runs @p@ to completion with
-- 'Megaparsec.runParsecT', which records everything megaparsec would have
-- handed on to what follows: the state @p@ left, whether it consumed input,
-- and its value and hints or its error. Replaying hands exactly that on, to
-- the same continuations. That gives the same answer as parsing again
-- because what @p@ does depends on nothing but the position and
-- 'ofIsAnchor', which together are the key:
--
--   * the input at a position is always the same, because the stream only
--     ever advances by dropping the tokens consumed (and their text), and no
--     parser sets the input;
--
--   * the source position cached in the state ('statePosState') is read
--     from the tokens themselves by a token stream's 'reachOffset', so every
--     position a parser asks for is the same after a replay. Two parts of
--     it do depend on what was reached before. Its line prefix is read only
--     when an error bundle is rendered, and the bundle is rendered from the
--     run's initial state. Its offset must never move backwards
--     ('reachOffset' splits the tokens at the distance from it), and a
--     replayed state was only advanced to offsets at or below the group's
--     end, which is where parsing resumes;
--
--   * of the 'Env', only 'ofIsAnchor' is ever changed with 'local'; the
--     module's URI and the mixfix hints are fixed for a whole run, and so is
--     this memo, which a run starts empty ('runJl4Parser');
--
--   * nothing reads the collected annotations ('PState') or megaparsec's
--     delayed errors while parsing; they are only ever added to, at the
--     front. So @p@ runs with both empty, and what it added is put in front
--     of what was there, which is what running it with them would have made.
--
-- Nothing fails loudly when one of these stops being true: the memo would
-- replay a wrong syntax tree or a wrong error, with no other symptom. So
-- jl4-test parses its whole corpus with the memo on and off ('memoiseGroups')
-- and requires the same answer ("parser memo changes nothing"), and
-- jl4-core-test does the same on nests that replay often
-- (NestedParenParserSpec).
memoGroup :: Lens' GroupMemo (IntMap.IntMap (GroupReply a)) -> Parser a -> Parser a
memoGroup = memoGroupAt 0

-- | 'memoGroup' for a parser that also depends on one more number, which
-- becomes part of the key: @memoGroupAt k table p@ must behave exactly as
-- @p@ wherever it is reached at the same position, with the same
-- 'ofIsAnchor' and the same @k@. 'clauseBody' passes its column. (Numbers
-- from 4095 up share one key; no column is that wide.)
memoGroupAt :: Int -> Lens' GroupMemo (IntMap.IntMap (GroupReply a)) -> Parser a -> Parser a
memoGroupAt extra table p =
  ReaderT \ env ->
    if env.memoiseGroups
      then memoised env
      else runReaderT p env
  where
    memoised env = StateT \ outer -> Megaparsec.ParsecT \ s cok cerr eok eerr -> do
      let key = (2 * s.stateOffset + fromEnum env.ofIsAnchor) * 4096 + min 4095 extra
      known <- gets (IntMap.lookup key . view table)
      Megaparsec.Reply s' consumption result <- case known of
        Just reply -> pure reply
        Nothing -> do
          reply <- Megaparsec.runParsecT (runStateT (runReaderT p env) mempty) s { stateParseErrors = [] }
          modify' (over table (IntMap.insert key reply))
          pure reply
      let s'' = s' { stateParseErrors = s'.stateParseErrors ++ s.stateParseErrors }
      case (consumption, result) of
        (Megaparsec.Consumed, Megaparsec.OK hs (a, added)) -> cok (a, added <> outer) s'' hs
        (Megaparsec.Consumed, Megaparsec.Error err) -> cerr err s''
        (Megaparsec.NotConsumed, Megaparsec.OK hs (a, added)) -> eok (a, added <> outer) s'' hs
        (Megaparsec.NotConsumed, Megaparsec.Error err) -> eerr err s''

-- We don't actually currently allow parsing an optional name
optionallyNamedType :: Parser (OptionallyNamedType Name)
optionallyNamedType = do
  attachAnno $
    MkOptionallyNamedType emptyAnno
    <$> annoHole (pure Nothing)
    <*> annoHole type'

tyApp :: Parser (Type' Name)
tyApp = do
  current <- Lexer.indentLevel
  attachAnno $
    TyApp emptyAnno
    <$> annoHole (tokenAsName (TKeywords TKList) <|> name)
    <*> (   annoLexeme (spacedKeyword_ TKOf) *> annoHole (lsepBy1 (const (indented type' current)) (spacedSymbol_ TComma))
        <|> annoHole (lmany (const (indented atomicType current)))
        )

fun :: Parser (Type' Name)
fun = do
  current <- Lexer.indentLevel
  attachAnno $
    Fun emptyAnno
    <$  annoLexeme (spacedKeyword_ TKFunction)
    <*  annoLexeme (spacedKeyword_ TKFrom)
    <*> annoHole (lsepBy1 (const (indented optionallyNamedType current)) (spacedKeyword_ TKAnd))
    <*  annoLexeme (spacedKeyword_ TKTo)
    <*> annoHole (indented type' current)

forall' :: Parser (Type' Name)
forall' = do
  -- current <- Lexer.indentLevel
  attachAnno $
    Forall emptyAnno
    <$  annoLexeme (spacedKeyword_ TKFor)
    <*  annoLexeme (spacedKeyword_ TKAll)
    <*> annoHole (lsepBy1 (const name) (spacedKeyword_ TKAnd))
--    <*  optional article
    <*> annoHole type' -- (indented type' current)

article :: AnnoParser PosToken
article =
  annoLexeme (spacedKeyword_ TKA <|> spacedKeyword_ TKAn <|> spacedKeyword_ TKThe)

withOptionalArticle :: (HasSrcRange a, HasAnno a, AnnoToken a ~ PosToken, AnnoExtra a ~ Extension) => Parser a -> Parser a
withOptionalArticle p =
  inlineAnnoHole $
    id
    <$  optional article
    <*> annoHole p

{-
enumType :: AnnoParser (Type' Name)
enumType =
  Enum emptyAnno
    <$  annoLexeme (spacedToken_ TKOne)
    <*  annoLexeme (spacedToken_ TKOf)
    <*> annoHole (lsepBy1 name (spacedToken_ TComma))
-}

lmany :: (Pos -> Parser a) -> Parser [a]
lmany pp =
  fmap concat $ manyLines $ \ p -> some (pp p)

lsepBy :: forall a. (HasAnno a, HasField "range" (AnnoToken a) SrcRange) => (Pos -> Parser a) -> Parser (Lexeme_ (AnnoToken a) (AnnoToken a)) -> Parser [a]
lsepBy pp sep =
  fmap concat $ manyLines $ \ p -> do
    ps <- P.sepBy1 (pp p) sep
    pure $ P.zipSepBy1 id zipAnno ps
  where
    zipAnno :: a -> Lexeme_ (AnnoToken a) (AnnoToken a) -> a
    zipAnno p s = setAnno (fixAnnoSrcRange $ getAnno p <> mkSimpleEpaAnno (lexToEpa s)) p

lsepBy1 :: forall a. (HasAnno a, HasField "range" (AnnoToken a) SrcRange) => (Pos -> Parser a) -> Parser (Lexeme_ (AnnoToken a) (AnnoToken a)) -> Parser [a]
lsepBy1 pp sep =
  fmap concat $ someLines $ \ p -> do
    ps <- P.sepBy1 (pp p) sep
    pure $ P.zipSepBy1 id zipAnno ps
  where
    zipAnno :: a -> Lexeme_ (AnnoToken a) (AnnoToken a) -> a
    zipAnno p s = setAnno (fixAnnoSrcRange $ getAnno p <> mkSimpleEpaAnno (lexToEpa s)) p

reqParam :: Parser (TypedName Name)
reqParam = do
  current <- Lexer.indentLevel
  attachAnno $
    MkTypedName emptyAnno
      <$> annoHole name
      <*  annoLexeme separator
--      <*  optional article
      <*> annoHole type'
      <*> optionalHole (annoLexeme (spacedKeyword_ TKTypically) *> annoHole atomicExpr')
      <*> optionalHole (annoLexeme (spacedKeyword_ TKMeans) *> annoHole (indentedExpr current))

param :: Parser (OptionallyTypedName Name)
param =
  attachAnno $
    MkOptionallyTypedName emptyAnno
      <$> annoHole name
      <*> optionalHole (annoLexeme separator *> {- optional article *> -} annoHole type')
      <*> optionalHole (annoLexeme (spacedKeyword_ TKTypically) *> annoHole atomicExpr')

-- |
-- An expression is a base expression followed by
-- a sequence of expression continuations, which are
-- themselves a binary operator followed by an expression.
--
-- For each expression continuation, we store its indentation,
-- and then in a post-processing step, we determine the correct
-- order of precedence.
--
-- An indented expression must in principle occur all to
-- the right of the given column threshold.
--
indentedExpr :: Pos -> Parser (Expr Name)
indentedExpr p =
  withIndent GT p $ \ _ -> do
    l <- currentLine
    -- Use mixfixChainExpr to collect linear mixfix chains before operator parsing
    e <- mixfixChainExpr
    efs <- many (expressionCont p)
    mw <- optional (whereExpr p)
    pure ((maybe id id mw) (combine End l e efs))

whereExpr :: Pos -> Parser (Expr Name -> Expr Name)
whereExpr p =
  withIndent GT p $ \ _ -> do
    ann <- opToken $ TKeywords TKWhere
    ds <- many (indented localdecl p)
    pure (\ e -> Where (mkHoleAnnoFor e <> ann <> mkHoleAnnoFor ds) e ds)

-- | Parse a single-line expression for use in directives like #EVAL.
-- This parser only continues parsing expression operators if the next token
-- is on the same line OR if the next line starts with '# ' (continuation marker).
--
-- This makes directives line-oriented (like C preprocessor directives)
-- while still allowing explicit multi-line continuation.
--
-- For example:
--   #EVAL 1 + 2        -- parses "1 + 2" as one expression
--   #EVAL 1 + 2 * 3    -- parses "1 + 2 * 3" as one expression
--   #EVAL 1            -- parses just "1", next line is separate
--     + 2              -- this is NOT part of the #EVAL (no # prefix)
--   #EVAL 1            -- parses "1 + 2" as one expression
--   # + 2              -- continuation line with # prefix
--
-- CAVEAT (pre-existing): the HEAD of a directive expression parses via
-- 'mixfixChainExpr', which accepts an aligned mixfix chain keyword on the
-- next line even without a '#' marker — so a directive head can absorb an
-- unmarked continuation line that starts with a chain keyword at the right
-- column. Operand positions ('singleLineExpressionCont') use
-- 'mixfixChainOperand' (same-line only) and do not have this hole.
--
-- IMPORTANT: When stripping directives with grep (e.g., `grep -v '^#'`), be aware
-- that L4 supports multiline strings with literal newlines. If a string literal
-- contains a line starting with '#', that line would be incorrectly stripped.
-- Example of problematic content:
--   someString MEANS "This is a string
--   # this looks like a directive but isn't
--   end of string"
-- In such cases, more sophisticated parsing is needed rather than simple grep.
--
singleLineExpr :: Parser (Expr Name)
singleLineExpr = do
  startLine <- currentLine
  -- Use mixfixChainExpr for the initial expression to collect linear mixfix chains
  e <- mixfixChainExpr
  -- Only apply line checking to expression continuations (operators)
  efs <- many (singleLineExpressionCont startLine)
  pure (combine End startLine e efs)

-- | Like 'expressionCont' but only parses if:
--   1. The operator is on the same line as the expression started, OR
--   2. There is a '# ' continuation marker at the start of the line
singleLineExpressionCont :: Pos -> Parser (Cont Expr)
singleLineExpressionCont startLine = try $ do
  -- Check if we have a continuation marker or are on the same line
  nextTok <- lookAhead anySingle
  let sameLine = fromIntegral nextTok.range.start.line == unPos startLine
  let isContinuation = nextTok.payload == TDirectives TDirectiveContinue
  guard (sameLine || isContinuation)
  -- If it's a continuation marker, consume it
  when isContinuation $ void $ spacedToken_ (TDirectives TDirectiveContinue)
  -- Now parse the operator and argument (mixfixChainOperand, in lockstep with
  -- expressionCont, so #EVAL operands admit user-defined infix operators too;
  -- same-line keywords only, preserving the directive's line discipline)
  (prio, assoc, op) <- operator
  l <- currentLine
  arg <- mixfixChainOperand
  pure (MkCont op prio assoc l (mkPos 1) arg)

data Stack a =
    Frame (Stack a) (a Name) (a Name -> a Name -> a Name) !Prio !Assoc !Pos !Pos
  | End

-- | This function decides how stack frames and continuations are combined
-- into a single expression.
--
-- For this, we take line and column information of various entities into
-- account. The general rule of thumb is: If items occur on a single line,
-- then normal precedence prevails. Similarly, if items occur on different
-- lines, but all start on the same column, then normal precedence should
-- prevail.
--
-- In other scenarios, we use the indentation for grouping.
--
-- Initially, the stack is empty, the given entity is the starting point,
-- and we have a number of continuation frames. We need the line of the
-- starting point.
--
-- The general process of moving through an expression is best demonstrated
-- by example:
--
-- a + b * c + d = e * f
--
-- We mark the focused position by [_], we write the stack to the left,
-- elements separated by commas, and the continuations to the right,
-- elements separated by commas.
--
-- Note that the stack and the continuations have exactly the same
-- structure.
--
-- [a] + b, * c,   + d,  = e, * f   -- empty stack, always push
-- a +  [b] * c,   + d,  = e, * f   -- * is stronger than + => push
-- a +, b *  [c]   + d,  = e, * f   -- + is weaker than * => pop
-- a +, [(b * c)]  + d,  = e, * f   -- + is like +, depends on associativity, left-associative => pop
-- [(a + (b * c))] + d,  = e, * f   -- empty stack, always push
-- (a + (b * c)) +  [d]  = e, * f   -- = is weaker than + => pop
-- [((a + (b * c)) + d)] = e, * f   -- empty stack, always push
-- ((a + (b * c)) + d) =  [e] * f   -- * is stronger than => push
-- ((a + (b * c)) + d) =, e *  [f]  -- empty continuation, always pop
-- ((a + (b * c)) + d) =, [(e * f)] -- empty continuation, always pop
-- [((a + (b * c)) + d) = (e * f)]  -- final result
--
-- The only difference between the process depicted above and the
-- real process is that the rules for which operator is stronger factor
-- in layout information. So in general, operators that are indented
-- more are seen to be stronger.
--
-- The exceptions are if either the whole expression is on the same line,
-- or if all operators are on the same column.
--
-- NOTE: The line which is the second argument of combine is the line
-- of the operand (not operator) currently under consideration.
--
-- The line stored on top of the stack is the line where the previous
-- expression starts, the line on top of the continuations is the line
-- where the subsequent expression continues.
--
-- Operators are considered to be "on the same line" if both operands
-- are on the same line, meaning that both the top stack frame and the
-- top continuation frame have to have the same line number to make
-- a real same-line choice.
--
combine :: Stack a -> Pos -> a Name -> [Cont a] -> a Name

-- If we have a single expression and nothing on the stack, then we
-- can just return it.
combine End _l e [] = e

-- If there is no continuation, we always pop. The line passed to
-- combine is always the starting point of the currently focused
-- expression, so we take the line stored on the stack.
combine (Frame s e1 op _ _ l1 _) _l2 e2 [] =
  combine s l1 (e1 `op` e2) []

-- If there is nothing on the stack, we always push.
combine End l1 e1 (MkCont op1 prio1 assoc1 l2 p2 e2 : efs) =
  combine (Frame End e1 op1 prio1 assoc1 l1 p2) l2 e2 efs

-- This is the standard case. We have something on the stack and a
-- continuation. We have to compare the two operators. If the operator
-- on the continuation side is stronger, we push. Otherwise, we pop.
--
combine s1@(Frame s e1 op1 prio1 assoc1 l1 p1) l e2 (MkCont op2 prio2 assoc2 l2 p2 e3 : efs)
  | (l2, p2, prio2, assoc2) `stronger` (l1, p1, prio1, assoc1) =
  combine (Frame s1 e2 op2 prio2 assoc2 l p2) l2 e3 efs -- push
  -- NOTE: the topmost frame now starts with e2, thus at line l
  | otherwise =
  combine s l1 (e1 `op1` e2) (MkCont op2 prio2 assoc2 l2 p2 e3 : efs) -- pop
  where
    stronger (ly, py, prioy, assocy) (lx, px, priox, assocx)
      | lx == ly  = priostronger
      | otherwise = py > px || py == px && priostronger
      where
        priostronger =
          case compare prioy priox of
            GT -> True
            EQ -> assocstronger
            LT -> False
        assocstronger =
          case (assocx, assocy) of
            (AssocRight, AssocRight) -> True
            (AssocLeft , AssocLeft ) -> False
            _                        -> True -- this should be a parse error, but we tolerate it and treat it as right-associative

-- Older thoughts on the operator layout parsing problem:
--
-- The real problem is:
--
--          e1
--   OR     e2
--      AND e3
--
-- Why? Because "OR e" occurs sequentially, but we have to reorder it.
-- So we cannot use a representation for "continuations" which already
-- associates the operators and base expressions.
--
-- But can we really do anything until the very end?
--
-- In the situation above, the following could happen:
--
-- Nothing further is in the input.
-- Final output: e1 OR (e2 AND e3)
--
--          e1
--   OR     e2
--      AND e3
--
-- Hmmm, I guess what we really know is that "e1 OR" belong together!
-- We also know that "e2 AND" belong together. So really *this* should
-- be our stack.
--
-- [ (e1, OR@3), (e2, AND@6), e3 ]
--
-- Now let's say what follows is `OP@i e4`. What do we do?
--
-- If i > 6, say 8, then
--
-- [ (e1, OR@3), (e2, AND@6), (e3, OP@8), e4 ]
--
-- If i < 6, but > 3, say 4, then we know e2 and e3 belong together; we get
--
-- [ (e1, OR@3), (e2 AND e3, OP@4), e4 ]
--
-- If i == 6, then
--
-- [ (e1, OR@3), (e2 AND e3, OP@6), e4 ]   (same as above; only in principle we have to resolve the associativity in the `e2 AND e3` expr)
--
-- If i < 3, say 2, then
--
-- [ (e1 OR (e2 AND e3), OP@2, e4 ]

data Cont a =
  MkCont
    { _op    :: a Name -> a Name -> a Name
    , _prio  :: !Prio
    , _assoc :: !Assoc
    , _line  :: !Pos
    , _pos   :: !Pos
    , _arg   :: a Name
    }

cont :: Parser (Prio, Assoc, a Name -> a Name -> a Name) -> Parser (a Name) -> Pos -> Parser (Cont a)
cont pop pbase p =
  -- Use try so that if the right operand fails to parse, we backtrack.
  -- This is needed for mixfix operators (backticked names) which can also
  -- be standalone expressions - if followed by a keyword instead of an
  -- expression, we backtrack and let the backticked name be parsed differently.
  try $ withIndent GT p $ \ pos -> do
    (prio, assoc, op) <- pop
    -- parg <- Lexer.indentGuard spaces GT p
    l <- currentLine
    arg <- pbase
    pure (MkCont op prio assoc l pos arg) -- the line we store is the line of the argument, not the operator

-- TODO: We should think whether we can obtain this more cheaply.
currentLine :: Parser Pos
currentLine = sourceLine <$> getSourcePos

-- | The operand after a built-in operator parses via 'mixfixChainOperand' —
-- the chain-head production ('indentedExpr', 'singleLineExpr') restricted to
-- same-line chain keywords — so a user-defined infix operator is admitted on
-- both sides of every built-in operator and binds tighter than all of them,
-- exactly as prefix application already does. The assembled chain reaches
-- 'combine' as a single pre-built operand. Before this, a user-defined
-- infix call was admitted only at the outermost level of an expression or
-- inside parentheses (SET-OPERATORS-SPEC §17.3). Same-line only, because
-- operand position lacks the @withIndent GT@ column guard that protects
-- chain heads from capturing an aligned next-line declaration.
expressionCont :: Pos -> Parser (Cont Expr)
expressionCont p = cont operator mixfixChainOperand p

data ExprLineInfo =
  MkExprLineInfo
    { exprEndLine :: !Int
    , exprIndentColumn :: !(Maybe Int)
    }
  deriving stock (Eq, Show)

defaultExprLineInfo :: ExprLineInfo
defaultExprLineInfo = MkExprLineInfo 0 Nothing

mkExprLineInfo :: SrcRange -> ExprLineInfo
mkExprLineInfo MkSrcRange{start = MkSrcPos{column}, end = MkSrcPos{line}} =
  MkExprLineInfo
    { exprEndLine = line
    , exprIndentColumn = Just column
    }

exprLineInfoWithFallback :: ExprLineInfo -> Maybe SrcRange -> Maybe Int -> ExprLineInfo
exprLineInfoWithFallback fallback Nothing fallbackIndent =
  fallback {exprIndentColumn = fallback.exprIndentColumn <|> fallbackIndent}
exprLineInfoWithFallback _ (Just rng) _ = mkExprLineInfo rng

isQuotedIdentifierToken :: PosToken -> Bool
isQuotedIdentifierToken MkPosToken{payload = L.TIdentifiers (L.TQuoted _)} = True
isQuotedIdentifierToken _ = False

keywordAlignedWith :: Bool -> ExprLineInfo -> SrcPos -> Bool
keywordAlignedWith allowNextLine MkExprLineInfo{..} MkSrcPos{line = tokLine, column = tokColumn} =
  tokLine == exprEndLine
    || (allowNextLine
        && maybe False
            (\ indent ->
               tokColumn == indent
                 && (exprEndLine == 0 || tokLine == exprEndLine + 1))
            exprIndentColumn)

-- | Like 'postfixP' but passes the ending line of the parsed expression to
-- a line-aware postfix parser. This is used for mixfix postfix operators
-- which must be on the same line as the base expression.
postfixPWithLine :: (HasAnno a, HasSrcRange a) => (ExprLineInfo -> Parser (a -> a)) -> Parser (a -> a) -> Parser a -> Parser a
postfixPWithLine lineAwareOps regularOps p =
  p >>= postfixAfter lineAwareOps regularOps

-- | The postfix half of 'postfixPWithLine', on an operand that has already
-- been parsed: at most one postfix operator.
postfixAfter :: (HasAnno a, HasSrcRange a) => (ExprLineInfo -> Parser (a -> a)) -> Parser (a -> a) -> a -> Parser a
postfixAfter lineAwareOps regularOps a = do
  let exprInfo = postfixLineInfo a
  mf <- optional (try (lineAwareOps exprInfo) <|> try regularOps)
  case mf of
    Nothing -> pure a
    Just f -> pure $ f a

-- | Where an operand ends, as the postfix operators see it.
postfixLineInfo :: (HasAnno a, HasSrcRange a) => a -> ExprLineInfo
postfixLineInfo a =
  let exprRange = rangeOf a <|> (getAnno a).range
  in  exprLineInfoWithFallback defaultExprLineInfo exprRange Nothing

type Prio = Int
data Assoc = AssocLeft | AssocRight

-- TODO: My ad-hoc fix for multi-token operators can probably be done more elegantly.
operator :: Parser (Prio, Assoc, Expr Name -> Expr Name -> Expr Name)
operator =
      (\ op -> (1, AssocRight, infix2  Implies   op)) <$> (spacedKeyword_ TKImplies <|> spacedTokenOp_ TImplies )
  <|> (\ op -> (1, AssocRight, infixUnless       op)) <$> spacedKeyword_ TKUnless
  <|> (\ op -> (2, AssocRight, infix2  Or        op)) <$> (spacedKeyword_ TKOr      <|> spacedTokenOp_ TOr      <|> spacedSymbol_ TEllipsisOr)
  <|> (\ op -> (3, AssocRight, infix2  And       op)) <$> (spacedKeyword_ TKAnd     <|> spacedTokenOp_ TAnd     <|> spacedSymbol_ TEllipsis)
  <|> (\ op -> (2, AssocRight, infix2  ROr       op)) <$> spacedKeyword_ TKROr
  <|> (\ op -> (3, AssocRight, infix2  RAnd      op)) <$> spacedKeyword_ TKRAnd
  <|> (\ op -> (4, AssocRight, infix2  Equals    op)) <$> (spacedKeyword_ TKEquals <|> spacedTokenOp_ TEquals)
  <|> (\ op -> (4, AssocRight, infix2' Leq       op)) <$> (try ((<>) <$> opToken (TKeywords TKAt) <*> opToken (TKeywords TKMost)) <|> opToken (TOperators TLessEquals))
  <|> (\ op -> (4, AssocRight, infix2' Geq       op)) <$> (try ((<>) <$> opToken (TKeywords TKAt) <*> opToken (TKeywords TKLeast)) <|> opToken (TOperators TGreaterEquals))
  <|> (\ op -> (4, AssocRight, infix2' Lt        op)) <$> ((<>) <$> opToken (TKeywords TKLess) <*> opToken (TKeywords TKThan) <|> opToken (TKeywords TKBelow) <|> opToken (TOperators TLessThan))
  <|> (\ op -> (4, AssocRight, infix2' Gt        op)) <$> ((<>) <$> opToken (TKeywords TKGreater) <*> opToken (TKeywords TKThan) <|> opToken (TKeywords TKAbove) <|> opToken (TOperators TGreaterThan))
  <|> (\ op -> (5, AssocRight, infix2' Cons      op)) <$> ((<>) <$> opToken (TKeywords TKFollowed) <*> opToken (TKeywords TKBy))
  <|> (\ op -> (6, AssocLeft,  infix2  Plus      op)) <$> (spacedKeyword_ TKPlus   <|> spacedTokenOp_ TPlus  )
  <|> (\ op -> (6, AssocLeft,  infix2  Minus     op)) <$> (spacedKeyword_ TKMinus  <|> spacedTokenOp_ TMinus )
  <|> (\ op -> (7, AssocLeft,  infix2  Times     op)) <$> (spacedKeyword_ TKTimes  <|> spacedTokenOp_ TTimes )
  <|> (\ op -> (7, AssocLeft,  infix2' DividedBy op)) <$> (((<>) <$> opToken (TKeywords TKDivided) <*> opToken (TKeywords TKBy)) <|> opToken (TOperators TDividedBy))
  <|> (\ op -> (7, AssocLeft,  infix2  Modulo    op)) <$> spacedKeyword_ TKModulo
  -- NOTE: Mixfix infix operators are now handled by mixfixChainExpr, not here.
  -- This allows collecting all mixfix tokens linearly rather than nesting binary ops.
  where
    spacedTokenOp_ = spacedToken_ . TOperators

-- | Regular postfix operators (percent, AS type)
regularPostfixOperator :: Parser (Expr Name -> Expr Name)
regularPostfixOperator =
      (\ op -> (postfix Percent   op)) <$> (spacedSymbol_ TPercent)
  <|> hidden postfixAsType
  where
    postfixAsType = do
      asAnno <- opToken (TKeywords TKAs)
      -- Optional article: AS A STRING / AS AN STRING / AS STRING
      articleLex <- optional (spacedKeyword_ TKA <|> spacedKeyword_ TKAn)
      typename <- name
      let articleAnno = maybe emptyAnno (mkSimpleEpaAnno . lexToEpa) articleLex
          typenameAnno = getAnno typename
          op = asAnno <> articleAnno <> typenameAnno
      -- For now, we only support AS STRING, but parser accepts any type name
      pure $ \ l -> AsString (fixAnnoSrcRange $ mkHoleAnnoFor l <> op) l

-- | Line-aware mixfix postfix operator parser.
-- Takes the ending line number of the base expression and only matches
-- if the postfix operator is on the same line.
-- e.g., `50 `percent`` becomes `App anno percent [50]`
-- We use `try` because if this is actually a binary operator (followed by
--
-- @notFollowedByOperand@ answers the one question 'mixfixPostfixHead' leaves
-- open: is the keyword followed, on the line its argument ends (which it is
-- given), by an operand of its own, which would make it infix rather than
-- postfix? It must succeed exactly when there is no such operand. Neither
-- caller parses that operand to find out, because parsing it here and again
-- as the infix operand is exponential when operands nest (MATRYOSHKA): see
-- 'postfixOrInfix' and 'genitiveAhead'.
mixfixPostfixOpWith :: (Int -> Parser ()) -> ExprLineInfo -> Parser (Expr Name -> Expr Name)
mixfixPostfixOpWith notFollowedByOperand exprLineInfo = hidden $ try $ do
  (eN, sameLine) <- mixfixPostfixHead exprLineInfo
  unless sameLine $ do
    nextAfterKeyword <- optional (lookAhead (spaceOrAnnotations *> anySingle))
    let allowsPostfixNewline =
          case (exprLineInfo.exprIndentColumn, nextAfterKeyword) of
            (_, Nothing) -> True
            (Just indent, Just peekTok) -> peekTok.range.start.column < indent
            _ -> False
    guard allowsPostfixNewline
  -- Check that this is NOT followed by an expression ON THE SAME LINE
  -- (which would make it infix). Expressions on subsequent lines don't count.
  notFollowedByOperand exprLineInfo.exprEndLine
  let funcName = eN.payload
      op = mkSimpleEpaAnno eN
  pure $ \l -> App (fixAnnoSrcRange $ mkAnno [AnnoHole Nothing] <> mkHoleAnnoFor l <> op) funcName [l]

-- | The guards of a mixfix postfix operator, and its keyword, with whether
-- the keyword is on the line where its argument ends. 'mixfixPostfixOpWith'
-- and 'infixAhead' both start here, and must agree on it.
mixfixPostfixHead :: ExprLineInfo -> Parser (Epa Name, Bool)
mixfixPostfixHead exprLineInfo = do
  hints <- asks (.mixfixHints)
  let allowNextLine = hasMixfixHints hints
  -- Peek at the next token to check its line number
  nextTok <- lookAhead (spaceOrAnnotations *> anySingle)
  let allowWithToken = allowNextLine || isQuotedIdentifierToken nextTok
      tokStart = nextTok.range.start
      sameLine = tokStart.line == exprLineInfo.exprEndLine
  -- Only proceed if the keyword is on the same line or aligned with the
  -- previous operand's indentation on the next line.
  guard (keywordAlignedWith allowWithToken exprLineInfo tokStart)
  -- Accept both backticked names (`cubed`) and bare identifiers (cubed)
  -- The typechecker will validate if the identifier is a registered mixfix operator
  eN <- (MkName emptyAnno . NormalName) <<$>>
    (spacedToken (#_TIdentifiers % #_TQuoted) "mixfix postfix operator"
     <|> spacedToken (#_TIdentifiers % #_TIdentifier) "postfix identifier")
  let candidateRaw = rawName eN.payload
  when (hasMixfixHints hints) $
    guard (isKnownMixfixKeyword candidateRaw hints)
  pure (eN, sameLine)

opToken :: TokenType -> Parser Anno
opToken t =
  (mkSimpleEpaAnno . lexToEpa) <$> spacedToken_ t

infix2 :: HasSrcRange (a n) => (Anno -> a n -> a n -> a n) -> Lexeme PosToken -> a n -> a n -> a n
infix2 f op l r =
  f (fixAnnoSrcRange $ mkHoleAnnoFor l <> mkSimpleEpaAnno (lexToEpa op) <> mkHoleAnnoFor r) l r

infix2' :: HasSrcRange (a n) => (Anno -> a n -> a n -> a n) -> Anno -> a n -> a n -> a n
infix2' f op l r =
  f (fixAnnoSrcRange $ mkHoleAnnoFor l <> op <> mkHoleAnnoFor r) l r

-- | UNLESS is syntactic sugar for AND NOT.
-- `l UNLESS r` desugars to `l AND (NOT r)`
-- UNLESS has precedence 1 (lower than OR at 2), so it binds to entire expressions:
--   `A OR B OR C UNLESS D` becomes `(A OR B OR C) AND (NOT D)`
--   `A AND B AND C UNLESS D` becomes `(A AND B AND C) AND (NOT D)`
infixUnless :: Lexeme PosToken -> Expr Name -> Expr Name -> Expr Name
infixUnless op l r =
  let opAnno = mkSimpleEpaAnno (lexToEpa op)
      -- The synthesized NOT has no keyword in the source, so its anno is just
      -- the operand hole: exactprint emits @r@ alone. (Putting the UNLESS
      -- token here too would print it twice — @l UNLESS UNLESS r@.)
      notAnno = fixAnnoSrcRange $ mkHoleAnnoFor r
      notR = Not notAnno r
      -- The single UNLESS token lives on the outer AND, between l and (NOT r),
      -- so exactprint reproduces the source @l UNLESS r@.
      andAnno = fixAnnoSrcRange $ mkHoleAnnoFor l <> opAnno <> mkHoleAnnoFor r
  in And andAnno l notR

postfix :: HasSrcRange (a n) => (Anno -> a n -> a n) -> Lexeme PosToken -> a n -> a n
postfix f op l =
  f (fixAnnoSrcRange $ mkHoleAnnoFor l <> mkSimpleEpaAnno (lexToEpa op)) l

-- | A same-line mixfix keyword and the operand after it, found by
-- 'postfixOrInfix' and already parsed: the keyword, the layout of the
-- operand's first token (what 'peekNextTokenLayout' reports there), and the
-- operand as 'baseExpr'' parsed it, before any postfix operator.
data InfixAhead = MkInfixAhead (Epa Name) ExprLineInfo (Expr Name)

-- | A base expression and at most one postfix operator; or, when a same-line
-- mixfix keyword with an operand after it follows the base expression, the
-- base expression and that keyword and operand ('InfixAhead').
-- 'mixfixChainExprNextLine', the only caller, continues the chain from an
-- 'InfixAhead' exactly as it would have from the keyword.
baseExprStep :: Parser (Expr Name, Maybe InfixAhead)
baseExprStep = baseExpr' >>= postfixOrInfix

-- | The postfix half of 'baseExprStep', on a base expression already parsed.
--
-- __Why the operand is parsed here (MATRYOSHKA).__ In @a kw b@, a keyword
-- @kw@ that passes the postfix guards is still not a postfix operator when an
-- operand @b@ follows it on the same line: then it is infix, and the chain
-- needs @b@. This used to be decided by parsing @b@ inside a 'notFollowedBy'
-- and then, when that succeeded, parsing @b@ again as the chain's operand.
-- Nested, that doubles per level: @1 `plus` (1 `plus` (1 `plus` 1))@ nested
-- ten deep took more than a minute. 'infixAhead' parses @b@ once and keeps it.
--
-- When 'infixAhead' fails, the operand look-ahead of the postfix reading is
-- certain to fail too, so the postfix reading skips it. Both start with
-- 'mixfixPostfixHead', and after it 'infixAhead' fails only where that
-- look-ahead fails: the keyword is not on the argument's last line, no token
-- follows the keyword on that line, or 'baseExpr'' fails there.
--
-- And when 'infixAhead' succeeds, the chain is certain to take the keyword:
-- for a keyword on the argument's last line, 'mixfixKeywordAligned' checks
-- what 'mixfixPostfixHead' checked, against the same line (both compute it
-- from the argument's range, and the head fails when it has none).
postfixOrInfix :: Expr Name -> Parser (Expr Name, Maybe InfixAhead)
postfixOrInfix a = do
  mAhead <- optional (infixAhead (postfixLineInfo a))
  case mAhead of
    Just ahead -> pure (a, Just ahead)
    Nothing -> do
      a' <- postfixAfter (mixfixPostfixOpWith (\ _ -> pure ())) regularPostfixOperator a
      pure (a', Nothing)

-- | A mixfix keyword on the line where the argument ends, and the base
-- expression after it on that line.
--
-- Like the look-ahead it replaces, it fails without consuming input or
-- leaving hints: the keyword's guards are 'hidden', and every later failure
-- happens past the keyword, so 'optional' discards it.
infixAhead :: ExprLineInfo -> Parser InfixAhead
infixAhead exprLineInfo = try $ do
  (kw, sameLine) <- hidden (mixfixPostfixHead exprLineInfo)
  guard sameLine
  tok <- lookAhead anySingle
  guard (tok.range.start.line == exprLineInfo.exprEndLine)
  operandLayout <- peekNextTokenLayout
  operand <- baseExpr'
  pure (MkInfixAhead kw operandLayout operand)

-- | Parse a mixfix chain expression.
-- After parsing a base expression, if it's followed by a backticked keyword,
-- collect all (keyword, expression) pairs linearly.
--
-- Example: `a `op1` b `op2` c` becomes:
--   App op1 [a, Var op2, b, c]
--
-- This representation allows the type checker to:
-- 1. Look up `op1` in the mixfix registry
-- 2. Validate that `op2` matches the expected keyword pattern
-- 3. Extract the actual arguments [a, b, c]
--
-- The curried representation means partial application works naturally.
peekNextTokenLayout :: Parser ExprLineInfo
peekNextTokenLayout = do
  tok <- lookAhead (spaceOrAnnotations *> anySingle)
  pure $
    MkExprLineInfo
      { exprEndLine = tok.range.start.line
      , exprIndentColumn = Just tok.range.start.column
      }

-- | Chain-head positions ('indentedExpr', 'singleLineExpr', 'implicitSeq')
-- admit an aligned chain keyword on the following line: their operand column
-- is guarded by @withIndent GT@, so a following sibling declaration can never
-- align with the operand and be captured. Operand position after a built-in
-- operator has no such column guard — an aligned next-line token there is
-- routinely the NEXT declaration's head, or an unmarked next line of a
-- directive — so 'mixfixChainOperand' forms chains from same-line keywords
-- only. (Found by adversarial review: cross-line capture turned
-- previously-valid programs into parse errors.)
mixfixChainExpr :: Parser (Expr Name)
mixfixChainExpr = mixfixChainExprNextLine True

mixfixChainOperand :: Parser (Expr Name)
mixfixChainOperand = mixfixChainExprNextLine False

mixfixChainExprNextLine :: Bool -> Parser (Expr Name)
mixfixChainExprNextLine nextLineOk = do
  hints <- asks (.mixfixHints)
  let allowNextLine = nextLineOk && hasMixfixHints hints
  firstLayoutHint <- peekNextTokenLayout
  (firstExpr, firstAhead) <- baseExprStep
  -- Compute end-line + indentation info for alignment-aware keywords.
  -- Try multiple fallbacks because rangeOf can return Nothing for some expression types:
  -- 1. rangeOf firstExpr - standard approach (fails for App with empty args)
  -- 2. (getAnno firstExpr).range - direct access to cached range
  -- 3. exprNameRange - extract range from name inside App/Var
  let exprRange = exprRangeWithName firstExpr
      firstExprInfo =
        exprLineInfoWithFallback firstLayoutHint exprRange Nothing
  -- Try to parse a mixfix chain starting with a backticked keyword
  -- The keyword must be on the same line or aligned with the first expression
  -- When 'baseExprStep' has already parsed a same-line keyword and its
  -- operand, the chain starts from them; see 'postfixOrInfix' for why the
  -- keyword is certain to be one 'mixfixChainCont' would have taken.
  mChain <- case firstAhead of
    Just ahead -> Just <$> mixfixChainFrom allowNextLine hints ahead
    Nothing -> optional $ try (mixfixChainCont allowNextLine hints firstExprInfo)
  case mChain of
    Nothing -> pure firstExpr
    Just (firstKeyword, firstArg, moreKwArgs) ->
      -- Build: App firstKeyword [firstExpr, firstArg, kw2, arg2, kw3, arg3, ...]
      -- For binary: a `plus` b -> App plus [a, b]
      -- For ternary+: a `f1` b `f2` c -> App f1 [a, b, Var f2, c]
      --
      -- IMPORTANT: genericToNodes for App expects exactly 2 holes:
      -- 1. One for the function name (whose Name carries no tokens here)
      -- 2. One for the args list (all args together)
      -- The exactprinter emits them in exactly that order, so keyword
      -- tokens stored in this outer anno would print *before* the args,
      -- rewriting the infix call `1 UNION 2` to prefix `UNION 1 2`
      -- (issue #918). Instead, every keyword's tokens live inside the args
      -- list, in source position: the first keyword as a leading hidden
      -- cluster on the argument that follows it (hidden clusters are
      -- exact-printed in place but ignored by 'rangeOf', keeping that
      -- argument's own range precise), and each later keyword in its
      -- marker node ('pairToArgs').
      let allArgs = firstExpr : prependHiddenEpa firstKeyword firstArg : concatMap pairToArgs moreKwArgs
          combinedAnno = mkAnno [AnnoHole Nothing, mkHoleWithSrcRange allArgs]
      in pure $ App combinedAnno firstKeyword.payload allArgs
  where
    -- Parse: `keyword` expr (`keyword` expr)*
    -- Returns: (firstKeyword, firstArg, [(kw2, arg2), (kw3, arg3), ...])
    -- The keyword MUST be on the given line (same line as previous expression)
    mixfixChainCont :: Bool -> MixfixHintRegistry -> ExprLineInfo -> Parser (Epa Name, Expr Name, [(Epa Name, Expr Name)])
    mixfixChainCont allowNextLine hints prevInfo = do
      firstKw <- mixfixKeywordAligned allowNextLine hints prevInfo
      firstArgLayout <- peekNextTokenLayout
      (firstArg, ahead) <- baseExprStep
      let firstArgInfo = advanceInfo firstArgLayout firstArg
      rest <- gatherChain allowNextLine hints firstArgInfo ahead
      pure (firstKw, firstArg, rest)

    -- 'mixfixChainCont' from a keyword and operand 'baseExprStep' has
    -- already parsed: the operand still takes its postfix step.
    mixfixChainFrom :: Bool -> MixfixHintRegistry -> InfixAhead -> Parser (Epa Name, Expr Name, [(Epa Name, Expr Name)])
    mixfixChainFrom allowNextLine hints (MkInfixAhead firstKw firstArgLayout operand) = do
      (firstArg, ahead) <- postfixOrInfix operand
      let firstArgInfo = advanceInfo firstArgLayout firstArg
      rest <- gatherChain allowNextLine hints firstArgInfo ahead
      pure (firstKw, firstArg, rest)

    -- The next (keyword, operand) pair: the one an operand's 'baseExprStep'
    -- already parsed, if any, else one found here.
    gatherChain :: Bool -> MixfixHintRegistry -> ExprLineInfo -> Maybe InfixAhead -> Parser [(Epa Name, Expr Name)]
    gatherChain allowNextLine hints _ (Just (MkInfixAhead kw argLayout operand)) = do
      (arg, ahead) <- postfixOrInfix operand
      let nextInfo = advanceInfo argLayout arg
      ((kw, arg) :) <$> gatherChain allowNextLine hints nextInfo ahead
    gatherChain allowNextLine hints info Nothing = do
      mNext <- optional . try $ do
        kw <- mixfixKeywordAligned allowNextLine hints info
        argLayout <- peekNextTokenLayout
        (arg, ahead) <- baseExprStep
        let nextInfo = advanceInfo argLayout arg
        pure ((kw, arg), nextInfo, ahead)
      case mNext of
        Nothing -> pure []
        Just ((kw, arg), nextInfo, ahead) ->
          ((kw, arg) :) <$> gatherChain allowNextLine hints nextInfo ahead

    -- Parse a mixfix keyword only if it's aligned with the specified anchor.
    -- Accepts both backticked names (`plus`) and bare identifiers (plus)
    -- The typechecker will validate if the identifier is a registered mixfix
    mixfixKeywordAligned :: Bool -> MixfixHintRegistry -> ExprLineInfo -> Parser (Epa Name)
    mixfixKeywordAligned allowNextLine hints anchorInfo = do
      tok <- lookAhead (spaceOrAnnotations *> anySingle)
      -- The quoted-token allowance also rides the position's next-line policy:
      -- in operand position even a backticked keyword must be same-line.
      let allowWithToken = allowNextLine || (nextLineOk && isQuotedIdentifierToken tok)
      guard (keywordAlignedWith allowWithToken anchorInfo tok.range.start)
      kw <- (MkName emptyAnno . NormalName) <<$>>
        (spacedToken (#_TIdentifiers % #_TQuoted) "mixfix keyword"
         <|> spacedToken (#_TIdentifiers % #_TIdentifier) "infix identifier")
      when (hasMixfixHints hints) $
        guard (isKnownMixfixKeyword (rawName kw.payload) hints)
      pure kw

    -- Convert (keyword, expr) pair to [Var keyword, expr]
    -- These are the "additional" keywords beyond the first one.
    -- The marker node carries the keyword's own tokens, so it exact-prints
    -- in source position within the args list.
    pairToArgs :: (Epa Name, Expr Name) -> [Expr Name]
    pairToArgs (kw, e) =
      let kwVar = App (mkSimpleEpaAnno kw) kw.payload []  -- Var keyword
      in [kwVar, e]

    -- Attach a keyword's tokens to the front of an expression's anno as a
    -- hidden cluster (plus any structured hidden clusters it carries, e.g.
    -- comments): exact-printed in source position, but invisible to
    -- 'rangeOf', so the expression's own source range is unchanged.
    prependHiddenEpa :: Epa Name -> Expr Name -> Expr Name
    prependHiddenEpa kw =
      overAnno (over #payload (fmap mkCluster (epaToHiddenCluster kw : kw.hiddenClusters) <>))

    -- Extract range from name inside App/Var expressions
    -- Used as fallback when rangeOf on the App itself returns Nothing
    -- Uses .range directly to bypass visibility filtering in rangeOf
    advanceInfo :: ExprLineInfo -> Expr Name -> ExprLineInfo
    advanceInfo layout exprNode =
      exprLineInfoWithFallback layout (exprRangeWithName exprNode) Nothing

    exprRangeWithName :: Expr Name -> Maybe SrcRange
    exprRangeWithName e =
      rangeOf e <|> (getAnno e).range <|> exprNameRange e

    exprNameRange :: Expr Name -> Maybe SrcRange
    exprNameRange (App _ n _) = (getAnno n).range
    exprNameRange (AppNamed _ n _ _) = (getAnno n).range
    exprNameRange _ = Nothing

baseExpr' :: Parser (Expr Name)
baseExpr' =
      try projection
  <|> negation
  <|> fetchExpr
  <|> envExpr
  <|> postExpr
  <|> recordOrCommitExpr
  <|> recallExpr
  <|> concatExpr
  <|> ifthenelse
  <|> multiWayIf
  <|> try event
  <|> regulative
  <|> breach
  <|> refuse
  <|> lam
  <|> consider
  <|> try namedApp -- This is not nice
  <|> app
  <|> lit
  <|> try bulletBlock   -- offside '•' bullet list (guarded; 0-cost on miss)
  <|> list
  <|> letInExpr
  <|> parenExprOrProjection  -- (e), and (e)'s f: see 'projection'

event :: Parser (Expr Name)
event = attachAnno $ Event emptyAnno <$> annoHole parseEvent

parseEvent :: Parser (Event Name)
parseEvent =
  attachAnno (MkEvent emptyAnno <$> parseParty <*> parseDoes <*> parseAt <*> pure False)
  <|> attachAnno do
    -- NOTE: allow to specify AT first, without breaking backwards
    -- compatibility
    timestamp <- parseAt
    party <- parseParty
    action <- parseDoes
    pure MkEvent {anno = emptyAnno, atFirst = True, ..}
  where
    parseParty =
      annoLexeme (spacedKeyword_ TKParty)
      *> annoHole expr
    parseDoes =
      annoLexeme (spacedKeyword_ TKDoes)
      *> annoHole expr
    parseAt =
      annoLexeme (spacedKeyword_ TKAt)
      *> annoHole expr

atomicExpr' :: Parser (Expr Name)
atomicExpr' =
      lit
  <|> nameAsApp App
  <|> parenExpr

nameAsApp :: (HasField "range" (AnnoToken b) SrcRange, HasAnno b, HasSrcRange a) => (Anno -> Name -> [a] -> b) -> Parser b
nameAsApp f =
  attachAnno $
    f emptyAnno
    <$> annoHole name
    <*> annoHole (pure [])

lit :: Parser (Expr Name)
lit = attachAnno $
  Lit emptyAnno <$> annoHole rawLit

rawLit :: Parser Lit
rawLit = try decimalLit <|> intLit <|> stringLit

list :: Parser (Expr Name)
list = do
  threshold <- listItemThreshold TKList
  attachAnno $
    List emptyAnno
      <$  annoLexeme (spacedKeyword_ TKList)
      <*> annoHole (lsepBy (const (indentedExpr threshold)) (spacedSymbol_ TComma))

concatExpr :: Parser (Expr Name)
concatExpr = do
  threshold <- listItemThreshold TKConcat
  attachAnno $
    Concat emptyAnno
      <$  annoLexeme (spacedKeyword_ TKConcat)
      <*> annoHole (lsepBy (const (indentedExpr threshold)) (spacedSymbol_ TComma))

-- | Pick the indent threshold for items inside a `LIST …` / `CONCAT …`
-- block based on whether the first item sits on the same line as the
-- keyword.
--
--   Same line  (`LIST 1, 2, 3`): keep the keyword's own column as the
--     threshold so items must be deeper than the keyword (matches the
--     historical behaviour, including how WHERE clauses bubble up to
--     the surrounding expression rather than being absorbed by the
--     last item).
--
--   Next line  (`LIST\n  1, 2, 3`): the first item is to the LEFT of
--     the keyword's column. Lower the threshold to one column below
--     the first item so the item itself still passes `indentedExpr`'s
--     `> p` check, but anything outdented further (including a
--     trailing WHERE) still bubbles out.
--
-- Implementation lookahead-only — the keyword and the first item are
-- not consumed here; the caller does that via the usual lexeme
-- machinery.
listItemThreshold :: TKeywords -> Parser Pos
listItemThreshold tk = do
  keywordCol <- Lexer.indentLevel
  keywordLine <- currentLine
  -- Peek past the keyword + its trailing whitespace to inspect the
  -- first non-blank token's position. We do this without consuming
  -- input by wrapping in `lookAhead`.
  lookAhead $ do
    _ <- plainToken (TKeywords tk)
    _ <- spaces
    firstItemLine <- currentLine
    firstItemCol <- Lexer.indentLevel
    pure $ if firstItemLine == keywordLine
             then keywordCol
             else mkPos (max 1 (unPos firstItemCol - 1))

-- | The bullet marker. @•@ (U+2022) has no arithmetic meaning, so it is
-- unambiguous everywhere — including as a function argument, which is what lets
-- bullet children nest under a constructor. (An earlier @-@ marker was dropped:
-- @-@ doubles as binary subtraction, so an indented @- x@ collides with a
-- wrapped subtraction continuation and could not be used in argument position.
-- Rather than ship two markers with different reach, @•@ is the only bullet.)
bulletMarker :: TokenType
bulletMarker = TSymbols TBullet

-- | Lookahead guard: are we at an offside @•@ bullet marker — a @•@ followed
-- by at least one space and a body token on the SAME line? Consumes nothing.
bulletAhead :: Parser ()
bulletAhead = void $ lookAhead $ do
  markLine <- currentLine
  _        <- plainToken bulletMarker
  sp       <- spaces
  bodyLine <- currentLine
  guard (not (null sp) && bodyLine == markLine)

-- | A block of offside @•@ bullets aligned at a common column, desugaring to
-- the same 'List' node as a @LIST@ literal:
--
-- >   • a
-- >   • b
--
-- is @LIST a, b@.
bulletBlock :: Parser (Expr Name)
bulletBlock = do
  bulletAhead
  blockCol <- Lexer.indentLevel
  attachAnno $
    List emptyAnno
      <$> annoHole (someLinesPos blockCol bulletItem)

-- | A single bullet: a line-leading @•@ marker, then a full expression as the
-- body. The body threshold is the marker's column, so 'indentedExpr' admits
-- the same-line body and any deeper continuation. The @•@ marker token is
-- prepended to the item's annotation (mirroring how 'lsepBy' folds a
-- separator into an item) so that exact-printing round-trips the bullet
-- syntax rather than dropping the marker.
bulletItem :: Pos -> Parser (Expr Name)
bulletItem markCol = do
  bulletAhead
  mark <- spacedToken_ bulletMarker
  e    <- indentedExpr markCol
  pure $ setAnno (fixAnnoSrcRange $ mkSimpleEpaAnno (lexToEpa mark) <> getAnno e) e

intLit :: Parser Lit
intLit =
  attachAnno $
    NumericLit emptyAnno
      <$> annoEpa (spacedToken (#_TLiterals % #_TIntLit % _2 % Optics.to fromIntegral) "Numeric Literal")

decimalLit :: Parser Lit
decimalLit =
  attachAnno $
    NumericLit emptyAnno
      <$> annoEpa (spacedToken (#_TLiterals % #_TRationalLit % _2) "Float Literal")

stringLit :: Parser Lit
stringLit =
  attachAnno $
    StringLit emptyAnno
      <$> annoEpa (spacedToken (#_TLiterals % #_TStringLit % _2) "String Literal")

-- Note: The `...` syntax is now handled by `implicitAndCont` as syntactic sugar for AND.
-- String literals in boolean context are converted to Inert nodes during type checking.

-- | Parser for function application.
--
-- Tries two alternatives for the argument list:
--
--   1. __OF syntax__ – @f OF x, y@ – arguments are explicitly
--      comma-separated via 'lsepBy1'.
--
--   2. __Juxtaposition__ – @f x y@ – arguments are parsed by
--      'parseAppArgs' using indentation only.
app :: Parser (Expr Name)
app = do
  current <- Lexer.indentLevel
  -- In the duration slot of a WITHIN, @OF@ is the deadline's anchor (see
  -- 'Env' and 'deadline'), so a bare name there takes juxtaposed arguments
  -- only: @WITHIN period OF THE JOIN@ is the nullary @period@ anchored at
  -- the join, not @period@ applied to @THE@.
  anchorSlot <- asks (.ofIsAnchor)
  attachAnno do
    fname <- annoHole name
    args <-
      ( (if anchorSlot then empty else annoLexeme (spacedKeyword_ TKOf))
          *> annoHole (lsepBy1 (const (indentedExpr current)) (spacedSymbol_ TComma))
      )
        <|> annoHole (parseAppArgs current fname)
    pure (App emptyAnno fname args)

-- | Parse function arguments supplied by juxtaposition (without @OF@).
--
-- Each argument must be an atomic expression ('atomicExpr'') that is
-- indented to the right of @current@ (the column of the enclosing
-- expression).  Arguments are collected greedily: the parser keeps going
-- as long as it can find indented atomic expressions.
--
-- Commas are never consumed here.  If you need comma-separated arguments,
-- use the @OF@ syntax (@f OF x, y@) instead.
--
-- __Mixfix guard.__  On the first argument only, 'guardMixfixKeyword'
-- checks that we are not about to consume a token that should be
-- interpreted as a mixfix keyword on a continuation line.
parseAppArgs :: Pos -> Name -> Parser [Expr Name]
parseAppArgs current fname = go True
  where
    funcLine = nameEndLine fname

    go allowBreak = do
      mArg <- optional $ try $ parseOne allowBreak
      case mArg of
        Nothing -> pure []
        Just arg -> (arg :) <$> go False

    parseOne allowBreak = do
      when allowBreak $ guardMixfixKeyword funcLine
      -- '•' is collision-free, so a '•' bullet block may be a function
      -- argument (feeding e.g. an arity-overloaded list constructor). It is
      -- admitted at >= the function column (indentedGE) so a child bullet can
      -- align under the parent's head word; ordinary arguments keep the strict
      -- '> column' rule.
      try (indentedGE bulletBlock current) <|> indented atomicExpr' current

guardMixfixKeyword :: Maybe Int -> Parser ()
guardMixfixKeyword Nothing = pure ()
guardMixfixKeyword (Just line) = do
  hints <- asks (.mixfixHints)
  if hasMixfixHints hints
    then do
      shouldBlock <- mixfixKeywordAhead hints line
      when shouldBlock Applicative.empty
    else pure ()

mixfixKeywordAhead :: MixfixHintRegistry -> Int -> Parser Bool
mixfixKeywordAhead hints line = do
  nextTok <- lookAhead anySingle
  if nextTok.range.start.line /= line
    then pure False
    else do
      mName <- optional $ lookAhead (try name)
      case mName of
        Just kwName -> pure (isKnownMixfixKeyword (rawName kwName) hints)
        Nothing -> pure False

nameEndLine :: Name -> Maybe Int
nameEndLine n =
  fmap (.end.line) $
    rangeOf n <|> (getAnno n).range

namedApp :: Parser (Expr Name)
namedApp = do
  attachAnno $
    AppNamed emptyAnno
    <$> annoHole name
    <*> (   annoLexeme (spacedKeyword_ TKWith) *> annoHole (lsepBy1 namedExpr (spacedSymbol_ TComma))
        )
    <*> pure Nothing

namedExpr :: Pos -> Parser (NamedExpr Name)
namedExpr current =
  attachAnno $
    MkNamedExpr emptyAnno
      <$> annoHole   name
      <*  annoLexeme separator
      <*  optional article
      <*> annoHole   (indentedExpr current)

fetchExpr :: Parser (Expr Name)
fetchExpr = do
  current <- Lexer.indentLevel
  attachAnno $
    Fetch emptyAnno
      <$  annoLexeme (spacedKeyword_ TKFetch)
      <*> annoHole (indentedExpr current)

envExpr :: Parser (Expr Name)
envExpr = do
  current <- Lexer.indentLevel
  attachAnno $
    L4.Syntax.Env emptyAnno
      <$  annoLexeme (spacedKeyword_ TKEnv)
      <*> annoHole (indentedExpr current)

postExpr :: Parser (Expr Name)
postExpr = do
  current <- Lexer.indentLevel
  attachAnno $
    Post emptyAnno
      <$  annoLexeme (spacedKeyword_ TKPost)
      <*> annoHole (indentedExpr current)
      <*> annoHole (indentedExpr current)
      <*> annoHole (indentedExpr current)

-- | @RECORD <cell> IS <expr>@ (own ledger) and
-- @COMMIT|ATTEST <cell> IS <expr>@ (official record) — STATE-AS-LEDGER M1,
-- with an optional trailing @HENCE <expr>@ continuation (M5).
-- Both lower to the same 'Record' node; the keyword choice sets the
-- @isOfficial@ flag ('False' for @RECORD@, 'True' for @COMMIT@/@ATTEST@).
--
-- M5: the value is parsed with 'indentedExpr current', which STOPS at the
-- reserved @HENCE@ keyword (the deontic-followup parser relies on the same
-- property) and may not dedent past the RECORD, so the value never swallows
-- @HENCE k@. When a @HENCE@ follows, it is parsed into the 'Record' node's
-- optional continuation, making the write an event-free deontic step.
--
-- The HENCE *continuation* is parsed at the lenient block threshold @mkPos 1@
-- (exactly as top-level 'expr' is), NOT at @current@: in the idiomatic flat
-- chain the chained @HENCE@ sits to the LEFT of @RECORD@ (aligned with the
-- enclosing obligation's @HENCE@s), so anchoring to the RECORD's own column
-- would wrongly reject it. @mkPos 1@ still halts cleanly at the next col-1 token
-- (e.g. a following @#TRACE@ or top-level declaration).
-- NOTE on exactprint hole-ordering: the generic ToConcreteNodes traversal
-- (L4.Annotation) renders ONE holeFit per 'Record' constructor field, in
-- field-declaration order — mParty, cell, val, isOfficial, mHence
-- (Syntax.hs ~240) — and 'flattenConcreteNodes' pops one holeFit per
-- 'AnnoHole' in this node's surface-ordered anno payload. Correct round-trip
-- therefore REQUIRES exactly one 'annoHole' per field, emitted in
-- field-declaration order. 'isOfficial :: Bool' renders to an empty surface
-- (Syntax.hs ~817) but STILL consumes a holeFit slot, so it gets a placeholder
-- 'annoHole (pure …)'. Keyword tokens (RECORD/COMMIT/ATTEST, IS) are
-- 'AnnoCsn' and do NOT consume holeFits, so they may be interleaved freely to
-- match the surface order. If anyone reorders the 'Record' fields in Syntax.hs,
-- the hole order below MUST move in lockstep (the ledger ep.goldens guard this).
recordOrCommitExpr :: Parser (Expr Name)
recordOrCommitExpr = do
  current <- Lexer.indentLevel
  attachAnno $ do
    -- mParty hole (field 1). Only RECORD takes the optional <party>'s recipient
    -- (the symmetric WRITE to RECALL <party>'s). COMMIT/ATTEST write the OFFICIAL
    -- record, which has no recipient: their mParty placeholder hole is forced to
    -- 'Nothing' WITHOUT calling recordRecipient, so the Record invariant
    -- (isOfficial ==> mParty == Nothing) stays genuinely parser-enforced,
    -- mirroring recallOfficialKw's OFFICIAL-vs-<party>'s split.
    (isOfficial, mParty) <-
          ((\mp -> (False, mp)) <$> (annoLexeme (spacedKeyword_ TKRecord) *> recordRecipient))
      <|> ((True, Nothing) <$ annoLexeme (spacedKeyword_ TKCommit) <* annoHole (pure (Nothing :: Maybe (Expr Name))))
      <|> ((True, Nothing) <$ annoLexeme (spacedKeyword_ TKAttest) <* annoHole (pure (Nothing :: Maybe (Expr Name))))
    cell  <- annoHole cellExpr                                -- cell hole (field 2)
    _     <- annoLexeme (spacedKeyword_ TKIs)
    val   <- annoHole (indentedExpr current)                  -- val hole (field 3)
    _     <- annoHole (pure isOfficial)                       -- isOfficial placeholder hole (field 4)
    mHence <- optionalWithHole (hence (mkPos 1) <|> implicitSeq current)  -- mHence hole (field 5)
    pure (Record emptyAnno mParty cell val isOfficial mHence)

-- | The optional NOTIFY-v1 /recipient/ qualifier of a @RECORD@ — the symmetric
-- WRITE to 'recallPartyAtom'\'s cross-party READ. @RECORD q's <cell> IS <v>@
-- writes into party @q@'s OWN ledger. We reuse the EXACT party atom ('partyAtom',
-- a bare 'name' wrapped as a @Var@ / @App … []@ so it is name-resolved as a
-- PARTY), with @try (… <* lookAhead genitive)@ so that — absent a following @'s@
-- — it backtracks and the token falls through to 'cellExpr'. No new keyword.
-- Only @RECORD@ takes this qualifier (see 'recordOrCommitExpr'); @COMMIT@/@ATTEST@
-- write the official record, which has no recipient, so they reject a
-- @<party>'s@ qualifier at parse time. That makes the 'Record' invariant
-- @isOfficial ==> mParty == Nothing@ genuinely parser-enforced (mirroring
-- 'recallOfficialKw'\'s @OFFICIAL's@-vs-@<party>'s@ split).
-- The fallthrough (absent recipient) must STILL emit exactly one (empty)
-- mParty hole so the unqualified RECORD slots its mParty field correctly under
-- the generic exactprint traversal (same fix shape as 'optionalWithHole').
recordRecipient :: AnnoParser (Maybe (Expr Name))
recordRecipient =
      (Just <$> (annoHole (try (partyAtom <* lookAhead genitive))
                  <* annoLexeme genitive))
  <|> annoHole (pure Nothing)
  where
    genitive = spacedToken_ (TIdentifiers TGenitive)

-- | A bare party reference (a @Var@ / @App … []@) used by the @<party>'s@
-- qualifier of RECORD and RECALL. Built via 'attachAnno' so the name token is
-- captured into the 'App' node's OWN anno (a hole) — WITHOUT this the App
-- renders empty and exactprint drops the party on round-trip. The party is
-- name-resolved exactly like any other reference.
partyAtom :: Parser (Expr Name)
partyAtom =
  attachAnno $
    (\fname -> App emptyAnno fname []) <$> annoHole name

-- | @RECALL [<party>'s | OFFICIAL's] <cell>@ — STATE-AS-LEDGER M1.5 + M4.5.
-- Reads a cell back from a ledger, yielding @MAYBE a@. The cell uses the SAME
-- 'cellExpr' surface as RECORD/COMMIT/ATTEST (a backtick ident or a string
-- literal), so a read and a write name a cell the same way.
--
-- After @RECALL@ we parse an OPTIONAL qualifier (M4.5), then the cell:
--
--   * @OFFICIAL's@      => @(Nothing, True)@  — read the shared OFFICIAL record.
--   * @<party>'s@       => @(Just party, False)@ — read another party's OWN ledger.
--     The party is a minimal name atom (NOT a full expression), wrapped as a
--     @Var@ ('App' with no args), so it is name-resolved exactly like a PARTY.
--   * (no qualifier)    => @(Nothing, False)@ — read the CURRENT party's own ledger.
--
-- Disambiguation: @OFFICIAL@ is a reserved, case-sensitive keyword (@TKOfficial@),
-- tried first.
-- The party branch uses @try (name <* TGenitive)@ so that, absent a following
-- @'s@, it backtracks and the token is parsed as the cell instead (a backtick
-- 'cellExpr' name and a backtick party 'name' otherwise overlap). 'cellExpr'
-- being restrictive (backtick/string) keeps it from colliding with the cell.
-- NOTE on exactprint hole-ordering: 'ReadCell' fields are mParty, isOfficial,
-- mode, cell (Syntax.hs ~266); the generic traversal renders one holeFit per
-- field in THAT order, so we must emit exactly one 'annoHole' per field in field
-- order — even though the SURFACE order is @RECALL [ALL] [OFFICIAL's|q's] cell@.
-- 'isOfficial :: Bool' and 'mode :: RecallMode' render to empty surface
-- (Syntax.hs ~814/~817) but STILL consume a holeFit each, so they get
-- placeholder holes. The ALL / OFFICIAL's / q's keyword tokens are 'AnnoCsn'
-- (do NOT consume holeFits) and are emitted in their surface positions. We
-- therefore emit the field holes in field order while keeping the ALL /
-- OFFICIAL's / q's keyword tokens in their surface positions. The try/back-
-- tracking of the OFFICIAL's-vs-q's-vs-none split and ALL-vs-none is preserved
-- by 'recallModeKw' / 'recallPartyAtom' / 'recallOfficialKw'.
recallExpr :: Parser (Expr Name)
recallExpr =
  attachAnno $ do
    _    <- annoLexeme (spacedKeyword_ TKRecall)
    -- SURFACE order is @RECALL [ALL] [OFFICIAL's|q's] cell@; FIELD order is
    -- mParty, isOfficial, mode, cell. Keyword tokens (ALL, OFFICIAL, 's) are
    -- 'AnnoCsn' and do NOT consume holeFits, so we emit ALL first (its surface
    -- position) while keeping the four field holes in field order. The party-atom
    -- 'q' is itself the mParty hole; its 's genitive is an adjacent token. The
    -- 'OFFICIAL' keyword + 's render adjacent to the (empty) isOfficial hole.
    mode <- recallModeKw                        -- emits the ALL keyword token (no hole)
    -- mParty hole (field 1): the q's party atom, or empty when OFFICIAL's/none.
    mParty <- recallPartyAtom
    -- isOfficial hole (field 2): empty placeholder; the OFFICIAL's tokens render here.
    isOff  <- recallOfficialKw
    _    <- annoHole (pure mode)                -- mode placeholder hole (field 3)
    cell <- annoHole cellExpr                   -- cell hole (field 4)
    pure (ReadCell emptyAnno mParty isOff mode cell)

-- | The optional @ALL@ collect-all marker — emits ONLY the ALL keyword token
-- (no hole). Mode field hole is emitted in field order by 'recallExpr'.
recallModeKw :: AnnoParser RecallMode
recallModeKw =
      (RecallAll <$ annoLexeme (spacedKeyword_ TKAll))
  <|> pure RecallLast

-- | The optional @q's@ party atom of a RECALL: emits the mParty field hole
-- (field 1) holding the party atom, with the 's genitive as an adjacent token.
-- Absent a following @'s@ it backtracks (the token falls through to the cell)
-- and emits an empty mParty hole. OFFICIAL's is handled separately by
-- 'recallOfficialKw', so this only matches a bare @<party>'s@.
recallPartyAtom :: AnnoParser (Maybe (Expr Name))
recallPartyAtom =
      (Just <$> (annoHole (try (partyAtom <* lookAhead genitive))
                  <* annoLexeme genitive))
  <|> annoHole (pure Nothing)
  where
    genitive = spacedToken_ (TIdentifiers TGenitive)

-- | The optional @OFFICIAL's@ qualifier of a RECALL: emits the isOfficial field
-- hole (field 2, empty surface) with the OFFICIAL keyword + 's genitive rendered
-- adjacent as tokens. Tried with backtracking; @OFFICIAL@ is a reserved keyword.
recallOfficialKw :: AnnoParser Bool
recallOfficialKw =
      tryParser (annoLexeme (spacedKeyword_ TKOfficial)
                  *> annoLexeme (spacedToken_ (TIdentifiers TGenitive))
                  *> annoHole (pure True))
  <|> annoHole (pure False)

-- | The cell (path) of a RECORD/COMMIT/ATTEST. For M1 it is a string-keyed
-- path, so we accept either a backtick-quoted identifier (e.g. @`x`@) or a
-- plain string literal, lowering BOTH to a 'StringLit'. This keeps the cell
-- out of name resolution: it is data (a key), not a variable reference.
cellExpr :: Parser (Expr Name)
cellExpr =
  attachAnno (Lit emptyAnno <$> annoHole cellLit)

cellLit :: Parser Lit
cellLit =
      attachAnno (StringLit emptyAnno <$> annoEpa (spacedToken (#_TIdentifiers % #_TQuoted) "quoted cell name"))
  <|> stringLit

negation :: Parser (Expr Name)
negation = do
  current <- Lexer.indentLevel
  attachAnno $
    Not emptyAnno
      <$  annoLexeme (spacedKeyword_ TKNot)
      <*  optional (annoLexeme (spacedKeyword_ TKOf))
      <*> annoHole (indentedExpr current)

lam :: Parser (Expr Name)
lam = do
  current <- Lexer.indentLevel
  attachAnno $
    Lam emptyAnno
      <$> annoHole givens
      <* annoLexeme (spacedKeyword_ TKYield)
      <*> annoHole (indentedExpr current)

ifthenelse :: Parser (Expr Name)
ifthenelse = do
  current <- Lexer.indentLevel
  attachAnno $
    IfThenElse emptyAnno
      <$  annoLexeme (spacedKeyword_ TKIf)
      <*> annoHole (indentedExpr current)
      <*  annoLexeme (spacedKeyword_ TKThen)
      <*> annoHole (indentedExpr current)
      <*  annoLexeme (spacedKeyword_ TKElse)
      <*> annoHole (indentedExpr current)

-- NOTE: this is a bit subtle: each of the
-- indents is scoped over only one token,
-- so we need to be careful to apply it to
-- each of them
multiWayIf :: Parser (Expr Name)
multiWayIf = do
  current <- Lexer.indentLevel
  attachAnno do
    _ <- annoLexeme (spacedKeyword_ TKBranch)
    let ind = flip indented' current
    MultiWayIf emptyAnno
      <$> annoHole (many (parseGuardedExpr current))
      <*> ind do
        annoLexeme (spacedKeyword_ TKOtherwise)
          *> annoHole (indentedExpr current)

parseGuardedExpr :: Pos -> Parser (GuardedExpr Name)
parseGuardedExpr pos = attachAnno $
  MkGuardedExpr emptyAnno
    <$> ind do
       annoLexeme (spacedKeyword_ TKIf)
        *> annoHole (indentedExpr pos)
    <*> ind do
       annoLexeme (spacedKeyword_ TKThen)
        *> annoHole (indentedExpr pos)
  where
  ind = flip indented' pos

regulative :: Parser (Expr Name)
regulative = attachAnno $
  Regulative emptyAnno <$> annoHole obligation

-- | Parse BREACH [BY party] [BECAUSE reason]
-- Terminal clause for explicit breach declaration
breach :: Parser (Expr Name)
breach = do
  current <- Lexer.indentLevel
  attachAnno $
    Breach emptyAnno
      <$  annoLexeme (spacedKeyword_ TKBreach)
      <*> optionalWithHole (annoLexeme (spacedKeyword_ TKBy) *> annoHole (indentedExpr current))
      <*> optionalWithHole (annoLexeme (spacedKeyword_ TKBecause) *> annoHole (indentedExpr current))

-- | Parse @REFUSE "message"@.
--
-- The message is a LITERAL, not an arbitrary expression. That is deliberate:
-- a refusal's reason is meant to be statically readable (so it can be reported
-- without running the program), and a literal payload means 'Refuse' needs no
-- machine 'Frame' and so no 'unwindFrame' arm. @REFUSE 42@ parses and is
-- rejected by the type checker; @REFUSE (something computed)@ does not parse.
refuse :: Parser (Expr Name)
refuse = attachAnno $
  Refuse emptyAnno
    <$  annoLexeme (spacedKeyword_ TKRefuse)
    <*> annoHole lit

optionalWithHole :: HasSrcRange a => AnnoParser a -> AnnoParser (Maybe a)
optionalWithHole p = Just <$> p <|> annoHole (pure Nothing)

-- | A deonton: @PARTY p@ or @EVERY [Cast] v [IN roll] [WHO f]@, then the modal and
-- action, then the optional @AFTER@ \/ @WITHIN@-or-@BEFORE@ \/ @ONCE …@ \/
-- @HENCE@ \/ @LEST@ clauses.
--
-- The column of the head keyword (@PARTY@ or @EVERY@) is the layout threshold
-- for every body that follows, exactly as before the quantified form existed.
-- One hole per field, in field order ('L4.Syntax.Deonton').
--
-- The window's two edges are written in ONE order, opening then closing
-- (@AFTER 3 WITHIN 30@); the other order is a parse error that names the
-- order ('edgeOrderGuard'). Meng's "order carries meaning" idea — the two
-- orders reading as the two windows — was put and REJECTED on 2026-09-16 as
-- a footgun (EVERY-EACH-QUANTIFIER-SPEC §5.1.2): the two readings are told
-- apart by an anchor, not by word order.
obligation :: Parser (Deonton Name)
obligation = do
  current <- Lexer.indentLevel
  attachAnno $
    MkDeonton emptyAnno
      <$> annoHole (subject current)
      <*> annoHole (must current)
      <*> optionalWithHole (opening current)
      <*> optionalWithHole (closingEdge current)
      <*  edgeOrderGuard
      <*> optionalWithHole (joinLine current)
      <*> optionalWithHole (hence current)
      <*> optionalWithHole (lest current)

-- | After the closing-edge slot, an @AFTER@ can only be the opening edge
-- written in the wrong place (@WITHIN 30 AFTER 3@), or a second one; a
-- @WITHIN@ or @BEFORE@ there can only be a second closing edge (@WITHIN 30
-- BEFORE date@ — 'closingEdge' is one slot, and the join line's @WITHIN@
-- follows @ONCE@\/@UPON@, never the act's edge directly). Fail there with
-- the rule spelled out, rather than with megaparsec's list of what may
-- follow a @WITHIN@. Consumes nothing and records no hole. Both look-aheads
-- are 'hidden' so that neither word joins the list of tokens expected
-- after a @WITHIN@ in every other parse error — they are not accepted
-- there, so listing them would be a lie (and would move the two
-- @every-join-misindented@ goldens, which quote that list). The second
-- look-ahead was added by the adversarial pass of 2026-09-16 (R1-5).
edgeOrderGuard :: AnnoParser ()
edgeOrderGuard = wrapAnnoParser $ WithAnno [] <$> do
  misplaced <- optional (lookAhead (hidden (spacedKeyword_ TKAfter)))
  for_ misplaced \ _ -> fancyFailure (Set.singleton (ErrorFail orderMsg))
  secondCloser <- optional (lookAhead (hidden (spacedKeyword_ TKWithin <|> spacedKeyword_ TKBefore)))
  for_ secondCloser \ _ -> fancyFailure (Set.singleton (ErrorFail oneCloserMsg))
  where
    orderMsg = "AFTER, the window's opening edge, comes first and once: \
          \PARTY p MUST act AFTER 3 WITHIN 30 - one AFTER, then WITHIN or BEFORE. \
          \This AFTER comes too late: after the closing edge, or after another AFTER."
    oneCloserMsg = "One closing edge: WITHIN d [OF anchor] or BEFORE date, not both and not twice. \
          \The window is [AFTER d1] then one of WITHIN d2 / BEFORE date; \
          \this second closing edge has nothing to close."

-- | The subject of a deonton (EVERY-EACH-QUANTIFIER-SPEC §2.4, RULED 2026-09-07;
-- the @IN@ roll RULED and built 2026-09-08, §11.0.2):
--
-- > PARTY e
-- > EVERY v            [IN roll] [WHO filter]  -- every value of the party type
-- > EVERY Cast v       [IN roll] [WHO filter]  -- every value built by the constructor Cast
--
-- After @EVERY@ come one or two names; with two, the first is the cast and the
-- second the variable (the variable is always last). Both are plain names
-- (backticked names included), not expressions, so @EVERY Tenant t MUST …@
-- cannot be misread as the application @Tenant t@. The filter word is @WHO@
-- only: @WHERE@ stays the local-definition keyword ('L4.Parser.whereBlock') and
-- is not overloaded here (R-Q4, RULED 2026-09-07).
--
-- @IN@ comes before @WHO@, in reading order — /every tenant t in tenants who is
-- not carol/. It needs no new keyword: @TKIn@ already exists for @LET … IN@,
-- and one name cannot be mistaken for it, since 'name' never matches a keyword
-- token. The roll expression is open-tailed, but every word that can follow it
-- (@WHO@, @MUST@, @MAY@, @SHANT@, @DO@) is a keyword, so it cannot swallow
-- them; the PRINTER is where the open tail has to be handled ('L4.Print').
--
-- Holes, in order: cast (empty when absent), variable, roll (empty when
-- absent), filter (empty when absent) — matching the 'Every' constructor's
-- fields positionally. Exactprint and semantic tokens are DERIVED by zipping
-- holes against fields ('L4.Syntax'), so this order is load-bearing and a
-- mismatch would not fail to compile.
subject :: Pos -> Parser (Subject Name)
subject current =
      attachAnno
        ( Party emptyAnno
            <$  annoLexeme (spacedKeyword_ TKParty)
            <*> annoHole (indentedExpr current)
        )
  <|> attachAnno
        ( (\ n1 mn2 roll filt -> case mn2 of
              Nothing -> Every emptyAnno Nothing n1 roll filt
              Just n2 -> Every emptyAnno (Just n1) n2 roll filt)
            <$  annoLexeme (spacedKeyword_ TKEvery)
            <*> indented' (annoHole name) current
            <*> optionalWithHole (indented' (annoHole name) current)
            <*> optionalWithHole (annoLexeme (spacedKeyword_ TKIn) *> annoHole (indentedExpr current))
            <*> optionalWithHole (annoHole (quantifierFilter current))
        )

-- | The quantifier's filter clause: @WHO e@ or @WHOSE e@ ('L4.Syntax.Filter').
--
-- Both take one bracketed expression, for the reason 'L4.Print' gives: an
-- open-tailed expression would otherwise swallow the modal that follows it.
-- The keyword is a token of the 'Filter' node's own 'Anno', which is what lets
-- the printer re-emit the word the drafter wrote.
quantifierFilter :: Pos -> Parser (Filter Name)
quantifierFilter current =
      attachAnno
        ( Who emptyAnno
            <$  annoLexeme (spacedKeyword_ TKWho)
            <*> annoHole (indentedExpr current)
        )
  <|> attachAnno
        ( Whose emptyAnno
            <$  annoLexeme (spacedKeyword_ TKWhose)
            <*> annoHole (indentedExpr current)
        )

-- | The join line of a quantified obligation (EVERY-EACH-QUANTIFIER-SPEC
-- §2.2.7.4 and §2.4, R-Q1 RULED 2026-09-07):
--
-- > ONCE ALL HAVE [WITHIN d]     -- the barrier (level-triggered)
-- > UPON EACH     [WITHIN d]     -- the fork    (edge-triggered)
--
-- Two alternatives rather than two thresholds, because the fork is not a
-- threshold: see 'L4.Syntax.Join'. @UPON@ is a keyword here; @EACH@ is NOT,
-- and is matched as the identifier token spelled @EACH@ — the device
-- 'timezone'' uses for @TIMEZONE@ — so a program may still name a value
-- @EACH@.
--
-- Layout: EVERY word of the join line — the head keyword, the marker words,
-- and the @WITHIN@ body — must sit strictly right of the deonton's head
-- keyword column.
--
-- The join line is the ONLY clause whose keyword is itself column-checked, and
-- it has to be. @WITHIN@, @HENCE@ and @LEST@ each guard their body expression
-- with 'indentedExpr', so a dedented one of those still fails on its body; a
-- bare @ONCE ALL HAVE@ or @UPON EACH@ has no body, so without this guard it
-- had NO positional constraint at all and was silently absorbed by whatever
-- deonton was open — measured 2026-09-07: a fork written at the OUTER rule's
-- clause column attached to a nested @EVERY@ inside the outer's @HENCE@,
-- checked clean, and exactprinted identically, so nothing in the toolchain
-- showed the author that the fork had bound to the wrong rule.
-- Barrier-versus-fork is exactly the distinction 'ContinuationWithoutJoin'
-- refuses to guess at, so deciding it by invisible layout was the worst
-- available default.
--
-- Phase 3 adds the count and measure thresholds (@SOME 2 OF … HAVE@,
-- @sum OF amount AT LEAST rent@) as further 'Threshold' alternatives, all of
-- them under @ONCE@.
--
-- The deadline slot takes the closing edge's grammar ('closingEdge') so
-- that a @BEFORE@ written there is refused by the checker by name rather
-- than as an unexpected token; no @AFTER@ is offered on a join line.
joinLine :: Pos -> AnnoParser (Join Name)
joinLine current = annoHole $
      attachAnno
        ( JoinOnce emptyAnno
            <$  indented' (annoLexeme (spacedKeyword_ TKOnce)) current
            <*> annoHole (joinThreshold current)
            <*> optionalWithHole (closingEdge current)
        )
  <|> attachAnno
        ( JoinUpon emptyAnno
            <$> annoHole (uponEach current)
            <*> optionalWithHole (closingEdge current)
        )

-- | @ONCE@'s threshold. Phase 1 has only the barrier; the count and measure
-- forms of spec §2.2.7.4 become further alternatives here.
joinThreshold :: Pos -> Parser (Threshold Name)
joinThreshold current =
  attachAnno
    ( AllHave emptyAnno
        <$  indented' (annoLexeme (spacedKeyword_ TKAll)) current
        <*  indented' (annoLexeme (spacedKeyword_ TKHave)) current
    )

-- | The fork's words, @UPON EACH@ (R-Q1 RULED 2026-09-07). The printer's twin
-- is 'L4.Print.uponEachWords', which the diagnostics read; changing the
-- spelling is those two definitions and the goldens that quote them.
--
-- @UPON@ in THIS position is the join line. @UPON <event>@ as a /rule head/ —
-- @specs\/todo\/UPON-EXTERNAL-EVENTS-SPEC.md@, status OPEN — is a different
-- construct in a different position, and is not built; the two never compete,
-- because a rule head cannot appear after an act.
uponEach :: Pos -> Parser UponEach
uponEach current = attachAnno $
  MkUponEach emptyAnno
    <$  indented' (annoLexeme (spacedKeyword_ TKUpon)) current
    <*  indented' (annoLexeme (spacedToken_ (TIdentifiers (TIdentifier "EACH")))) current

must :: Pos -> Parser (RAction Name)
must current = attachAnno $
   MkAction emptyAnno
     <$> asum
      -- Parse MUST, then check for optional NOT to determine modal
      [ annoLexeme (spacedKeyword_ TKMust) *>
        (DMustNot <$ annoLexeme (spacedKeyword_ TKNot) <* optional (annoLexeme (spacedKeyword_ TKDo))
         <|> DMust <$ optional (annoLexeme (spacedKeyword_ TKDo)))
      , DMay <$ annoLexeme (spacedKeyword_ TKMay)
        <* optional (annoLexeme (spacedKeyword_ TKDo))
      , DMustNot <$ annoLexeme (spacedKeyword_ TKShant)
        <* optional (annoLexeme (spacedKeyword_ TKDo))
      , DDo <$ annoLexeme (spacedKeyword_ TKDo)
      ]
     <*> annoHole (indentedPattern current)
     <*> optionalWithHole do
      annoLexeme (spacedKeyword_ TKProvided)
        *> annoHole (indentedExpr current)

-- | The act's closing edge: @WITHIN d [OF anchor]@ or @BEFORE date@
-- (EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X5). The two are alternatives in ONE
-- slot, so the parent records one hole either way and @WITHIN@ and @BEFORE@
-- cannot both be written. The checker discriminates the argument's type
-- (a DATE after @WITHIN@ names @BEFORE@, a NUMBER after @BEFORE@ names
-- @WITHIN@: 'L4.TypeCheck.checkDeadline').
closingEdge :: Pos -> AnnoParser (Deadline Name)
closingEdge current = deadline current <|> before current

-- | @BEFORE date@ — the absolute closing edge. One hole, the instant; the
-- @BEFORE@ keyword is a token of the 'Deadline' node's own 'Anno'. The
-- instant is parsed as an ordinary expression ('inExprSlot'): a @BEFORE@
-- takes no anchor, so @OF@ inside it is application, as everywhere else.
--
-- Parsed on a join line too, where the checker refuses it by name: a
-- @BEFORE@ there is not built (it would need 'Barrier3'\/'Barrier4' to
-- lower a DATE).
before :: Pos -> AnnoParser (Deadline Name)
before current = annoHole $ attachAnno $
  MkBefore emptyAnno
    <$  annoLexeme (spacedKeyword_ TKBefore)
    <*> annoHole (inExprSlot (indentedExpr current))

-- | The window's opening edge, @AFTER d [OF anchor]@ or @AFTER date@
-- (EVERY-EACH-QUANTIFIER-SPEC §5.1.2, R-X5; RE-ANCHORS, §5.1.2.2). The
-- same shape as 'deadline' — one hole for the offset, one for the optional
-- anchor, the keyword in the node's own 'Anno' — and the same @OF@ rule:
-- in the offset slot @OF@ is the anchor, so @AFTER period OF closingDate@
-- is @period@ anchored at @closingDate@, never @period@ applied. A date
-- offset with an anchor (@AFTER (YMD 2026 6 1) OF THE JOIN@) parses and is
-- refused by the checker: a DATE is already an instant.
--
-- Act position only ('obligation'); the join line takes no @AFTER@.
opening :: Pos -> AnnoParser (Opening Name)
opening current = annoHole $ attachAnno $
  MkOpening emptyAnno
    <$  annoLexeme (spacedKeyword_ TKAfter)
    <*> annoHole (local (\ e -> e { ofIsAnchor = True }) (indentedExpr current))
    <*> optionalWithHole (anchor current)

-- | @WITHIN d [OF anchor]@, in either position — the act's deadline
-- ('closingEdge') or the join line's ('joinLine'). One hole for the
-- duration, one for the optional anchor, in that order ('L4.Syntax.Deadline');
-- the @WITHIN@ keyword is a token of the 'Deadline' node's own 'Anno'.
--
-- The duration is parsed with 'ofIsAnchor' set, so that @OF@ after it is the
-- anchor and not an application's argument list (see 'Env'): otherwise
-- @WITHIN period OF closingDate@ would silently be @period@ applied to
-- @closingDate@, and @WITHIN period OF THE JOIN@ a parse error at @THE@.
-- An application in the duration is written @WITHIN (f OF x) OF …@ or with
-- juxtaposed arguments, @WITHIN f x OF …@ — which is also how
-- 'L4.Print.prettyLayout' prints it back, so the round trip holds.
deadline :: Pos -> AnnoParser (Deadline Name)
deadline current = annoHole $ attachAnno $
  MkDeadline emptyAnno
    <$  annoLexeme (spacedKeyword_ TKWithin)
    <*> annoHole (local (\ e -> e { ofIsAnchor = True }) (indentedExpr current))
    <*> optionalWithHole (anchor current)

-- | The anchor of an edge — a deadline's, or an opening's — @OF …@
-- (EVERY-EACH-QUANTIFIER-SPEC §5.1.1, RULED 2026-09-07):
--
-- > OF THE JOIN | OF THE DEADLINE | OF THE ARMING     -- R-Q7B, the lifecycle anchors
-- > OF e                                              -- R-Q7C, a NUMBER or DATE expression
--
-- @THE@ is a keyword ('TKThe', otherwise used only in type position); the
-- three nouns are NOT keywords and are matched as the identifier tokens so
-- spelled — the device 'uponEach' uses for @EACH@ — so a program may still
-- name a value @DEADLINE@. The alternatives are disjoint on their first
-- token, because no expression begins with @THE@.
--
-- The expression form is parsed as an ordinary expression ('inExprSlot'):
-- inside the anchor @OF@ is application again.
anchor :: Pos -> AnnoParser (Anchor Name)
anchor current = annoHole $ attachAnno $
  annoLexeme (spacedKeyword_ TKOf) *>
    (   annoLexeme (spacedKeyword_ TKThe) *>
          (   AnchorJoin emptyAnno     <$ annoLexeme (spelled "JOIN")
          <|> AnchorDeadline emptyAnno <$ annoLexeme (spelled "DEADLINE")
          <|> AnchorArming emptyAnno   <$ annoLexeme (spelled "ARMING")
          )
    <|> AnchorAt emptyAnno <$> annoHole (inExprSlot (indentedExpr current))
    )
  where
    spelled = spacedToken_ . TIdentifiers . TIdentifier

hence :: Pos -> AnnoParser (Expr Name)
hence current =
  annoLexeme (spacedKeyword_ TKHence) *> annoHole (indentedExpr current)

lest :: Pos -> AnnoParser (Expr Name)
lest current =
  annoLexeme (spacedKeyword_ TKLest) *> annoHole (indentedExpr current)

-- | The /block/ (layout) sugar for a RECORD/COMMIT/ATTEST continuation: a second
-- way into the 'Record' node's @mHence@ slot besides the explicit @HENCE@
-- keyword. When the line immediately following @RECORD <cell> IS <val>@ begins
-- EXACTLY at the RECORD's own column (@current@), that aligned same-column
-- sibling is parsed as the continuation provision — yielding the IDENTICAL
-- right-nested AST as if an explicit @HENCE@ had separated them:
--
-- @
--   HENCE RECORD "a" IS "x"        ===   HENCE RECORD "a" IS "x"
--         RECORD "b" IS "y"              HENCE RECORD "b" IS "y"
--         PARTY p MUST serve            HENCE PARTY p MUST serve
-- @
--
-- This is anchored ONLY on the 'Record' continuation slot (see
-- 'recordOrCommitExpr'), reached identically whether the first RECORD arrived
-- via @HENCE RECORD@ or @LEST RECORD@. @hence@ is tried FIRST, so the explicit
-- flat chain and flat/block mixing are unchanged. The continuation parser body
-- is the SAME as 'indentedExpr' EXCEPT the leading guard demands EQ-@current@
-- (the sibling must start EXACTLY at the RECORD column) rather than GT-@current@.
--
-- Crucially the OPERATOR/where continuations inside the body keep the standard
-- GT-@current@ discipline (via 'expressionCont'/'whereExpr'), so a RAND/ROR
-- operand sitting on an aligned next line (col == @current@) does NOT attach —
-- it dedents to @current@, not GT — which is exactly the block-boundary the spec
-- (R4) requires. The terminal non-RECORD provision (PARTY…MUST…, BREACH BY…, a
-- RAND/ROR expr) is parsed by the LAST sibling's value/continuation path through
-- the SAME @current@ and the SAME operator machinery the flat HENCE chain uses,
-- so it lowers to the identical AST.
--
-- 'withIndent EQ' fails WITHOUT consuming on a column mismatch (it is a peek at
-- the indent level), so when no aligned sibling follows, the surrounding
-- 'optionalWithHole' cleanly falls through to its @Nothing@ arm (empty
-- continuation). A column-aligned sibling whose body is then malformed is a
-- genuine hard parse error (acceptable — the input is malformed).
implicitSeq :: Pos -> AnnoParser (Expr Name)
implicitSeq current =
  annoHole $
    withIndent EQ current $ \ _ -> do
      l   <- currentLine
      e   <- mixfixChainExpr
      efs <- many (expressionCont current)
      mw  <- optional (whereExpr current)
      pure ((maybe id id mw) (combine End l e efs))

consider :: Parser (Expr Name)
consider = do
  current <- Lexer.indentLevel
  attachAnno $
    Consider emptyAnno
      <$  annoLexeme (spacedKeyword_ TKConsider)
      <*> annoHole (indentedExpr current)
      <*> annoHole (lsepBy (const branch) (spacedSymbol_ TComma))

branch :: Parser (Branch Name)
branch =
  when' <|> otherwise'

when' :: Parser (Branch Name)
when' = do
  current <- Lexer.indentLevel
  attachAnno $
    MkBranch emptyAnno
      <$> annoHole do
            attachAnno $
              When emptyAnno
                <$  annoLexeme (spacedKeyword_ TKWhen)
                <*> annoHole (indentedPattern current)
      <*  annoLexeme (spacedKeyword_ TKThen)
      <*> annoHole (indentedExpr current)

otherwise' :: Parser (Branch Name)
otherwise' = do
  current <- Lexer.indentLevel
  attachAnno $
    MkBranch emptyAnno
      <$> annoHole do
            attachAnno $
              Otherwise emptyAnno
                <$  annoLexeme (spacedKeyword_ TKOtherwise)
      <*> annoHole (indentedExpr current)

indentedPattern :: Pos -> Parser (Pattern Name)
indentedPattern p =
  withIndent GT p $ \ _ -> do
    l <- currentLine
    pat <- basePattern
    pfs <- many (patternCont p)
    pure (combine End l pat pfs)

-- This isn't ideal, because it says a pattern must be indented
-- (and 'mkPos' does not allow 0).
--
-- See also 'expr'.
--
pattern' :: Parser (Pattern Name)
pattern' =
  indentedPattern (mkPos 1)


basePattern :: Parser (Pattern Name)
basePattern =
  patLit
  <|> patExpr
  <|> patApp
  <|> parenPatternOrExpr

atomicPattern :: Parser (Pattern Name)
atomicPattern =
  patLit
  <|> patExpr
  <|> nameAsPatApp
  <|> parenPatternOrExpr

-- | A bracketed thing in pattern position: a pattern if it can be one, an
-- expression otherwise (R2 of @specs\/todo\/PATTERN-REFERENCE-RULE-SPEC.md@).
--
-- This is what admits @MUST pay (price PLUS 50)@ and
-- @MUST Deliver (t's landlord) what@ without the @EXACTLY@ keyword. The
-- pattern reading is tried first, so @MUST pay (Money 1000 "USD")@ — a
-- constructor application — keeps its existing pattern semantics exactly.
--
-- An unbracketed operator expression (@MUST pay price PLUS 50@) is still not
-- admitted, and deliberately: argument juxtaposition would make it ambiguous.
--
-- __The cost__ (MATRYOSHKA). A group that is not a pattern is read twice,
-- once as each. That compounded when the group holds a @CONSIDER@ or a
-- @MUST@ whose own pattern slot holds the next bracket, as in
-- @((CONSIDER x WHEN (…) THEN …) PLUS 1)@: the failed pattern attempt had
-- already parsed the inner bracket, and the expression reading parsed it
-- again, so the time doubled with every level (twelve levels took six
-- seconds). Both readings now go through 'memoGroup', which keeps a separate
-- table for each, so a bracket nested inside is parsed at most once as a
-- pattern and at most once as an expression, and a later parse of it in the
-- same reading replays the first. The two readings, their order, and so every
-- parse and every error, are what they were before the memo.
parenPatternOrExpr :: Parser (Pattern Name)
parenPatternOrExpr =
  try parenPattern
  <|> attachAnno (PatExpr emptyAnno <$> annoHole parenExpr)

patLit :: Parser (Pattern Name)
patLit = attachAnno $ PatLit emptyAnno <$> annoHole rawLit

patExpr :: Parser (Pattern Name)
patExpr = attachAnno $
  PatExpr emptyAnno
    <$> do
      annoLexeme (spacedKeyword_ TKExact)
        *> annoHole expr

nameAsPatApp :: Parser (Pattern Name)
nameAsPatApp =
  attachAnno $
    PatApp emptyAnno
    <$> annoHole name
    <*> annoHole (pure [])

patternCont :: Pos -> Parser (Cont Pattern)
patternCont = cont patOperator basePattern

patOperator :: Parser (Prio, Assoc, Pattern Name -> Pattern Name -> Pattern Name)
patOperator =
  (\ op -> (5, AssocRight, infix2' PatCons      op)) <$> ((\ l1 l2 -> mkSimpleEpaAnno (lexToEpa l1) <> mkSimpleEpaAnno (lexToEpa l2)) <$> spacedKeyword_ TKFollowed <*> spacedKeyword_ TKBy)

patApp :: Parser (Pattern Name)
patApp = do
  current <- Lexer.indentLevel
  attachAnno $
    PatApp emptyAnno
    <$> annoHole name
    <*> (      annoLexeme (spacedKeyword_ TKOf)
            *> annoHole (lsepBy (const (indented basePattern current)) (spacedSymbol_ TComma))
        <|> annoHole (lmany (const (indented atomicPattern current)))
        )

-- Some manual left-factoring here to prevent left-recursion
-- TODO: the interaction between projection and application has to be properly sorted out
--
-- A projection whose head is a literal or a name. A parenthesised head is
-- 'parenExprOrProjection''s (MATRYOSHKA): 'baseExpr'' tries this first, and
-- when it was tried over a parenthesised group with no @'s@ after it, the
-- group was parsed here, thrown away, and parsed again by the plain
-- parenthesis alternative -- twice per level of nesting, so
-- @((1 PLUS 1) PLUS 1)@ nested 16 deep took 15 s.
projection :: Parser (Expr Name)
projection =
      -- TODO: should 'TGenitive' be part of 'Name' or 'Proj'?
      -- May affect the source span of the name.
      -- E.g. Goto definition of `name's` would be affected, as clicking on `'s` would not be part
      -- of the overall name source span. It is possible to implement this, but slightly annoying.
      foldl' projectField
  <$> projectionHead
  <*> some genitiveField

-- | The head of a 'projection': a literal or a name, then at most one postfix
-- operator. A projection must go on with @'s@, so a postfix keyword here
-- needs 'genitiveAhead' rather than an operand look-ahead.
projectionHead :: Parser (Expr Name)
projectionHead =
  postfixPWithLine (mixfixPostfixOpWith genitiveAhead) regularPostfixOperator (lit <|> nameAsApp App)

-- | A parenthesised expression, with the projections that follow it if any:
-- @(e)@, @(e)'s f@, @(e)'s f's g@. The group is parsed once, and then the
-- projections are tried after it, exactly as 'projection' would have tried
-- them on that head: one postfix operator, then at least one @'s@.
--
-- The first @'s@ is 'hidden' because 'projection''s attempt left no trace
-- when it failed -- the plain alternative after it succeeded on the same
-- group and discarded its error -- so a missing @'s@ must not start appearing
-- in the "expecting" list of a parse error just after a closing bracket.
parenExprOrProjection :: Parser (Expr Name)
parenExprOrProjection = do
  e <- parenExpr
  fromMaybe e <$> optional (try (projectionsAfter e))
  where
    projectionsAfter e = do
      a <- postfixAfter (mixfixPostfixOpWith genitiveAhead) regularPostfixOperator e
      f <- (,) <$> hidden (spacedToken_ (TIdentifiers TGenitive)) <*> name
      fs <- many genitiveField
      pure (foldl' projectField a (f : fs))

genitiveField :: Parser (Lexeme PosToken, Name)
genitiveField = (,) <$> spacedToken_ (TIdentifiers TGenitive) <*> name

projectField :: Expr Name -> (Lexeme PosToken, Name) -> Expr Name
projectField e (gen, n') =
  Proj (fixAnnoSrcRange $ mkHoleAnnoFor e <> mkSimpleEpaAnno (lexToEpa gen) <> mkHoleAnnoFor n')
    e
    n'

-- | The operand test of a postfix keyword in a projection's head: is it
-- followed by @'s@? This stands in for the look-ahead that parses a whole
-- operand ('mixfixPostfixOpWith'), and decides the projection identically:
-- when @'s@ follows, no operand can (no expression begins with @'s@), so
-- both accept the keyword; when it does not, the projection fails whichever
-- way the keyword is read, because @'s@ must come next either way.
genitiveAhead :: Int -> Parser ()
genitiveAhead _ = void (lookAhead (plainToken (TIdentifiers TGenitive)))

_example1 :: Text
_example1 =
  Text.unlines
    [ "     foo"
    , " AND bar"
    ]

_example1b :: Text
_example1b =
  Text.unlines
    [ "     foo"
    , " AND NOT bar"
    ]

_example2 :: Text
_example2 =
  Text.unlines
    [ "        foo"
    , "     OR bar"
    , " AND baz"
    ]

_example3 :: Text
_example3 =
  Text.unlines
    [ "        foo"
    , "     OR bar"
    , " AND    foo"
    , "     OR baz"
    ]

_example3b :: Text
_example3b =
  Text.unlines
    [ "     NOT    foo"
    , "         OR bar"
    , " AND        foo"
    , "     OR NOT baz"
    ]

_example4 :: Text
_example4 =
  Text.unlines
    [ "        foo"
    , "    AND bar"
    , " OR     baz"
    ]

_example5 :: Text
_example5 =
  Text.unlines
    [ "        foo"
    , "    AND bar"
    , "    AND foobar"
    , " OR     baz"
    ]

_example6 :: Text
_example6 =
  Text.unlines
    [ "            foo"
    , "        AND bar"
    , "     OR     baz"
    , " AND        foobar"
    ]

_example7 :: Text
_example7 =
  Text.unlines
    [ "            foo IS x"
    , "        AND bar IS y"
    , "     OR     baz IS z"
    ]

_example7b :: Text
_example7b =
  Text.unlines
    [ "               foo"
    , "            IS x"
    , "        AND    bar"
    , "            IS y"
    , "     OR        baz"
    , "            IS z"
    ]

_example8 :: Text
_example8 =
  Text.unlines
    [ "          b's stage     IS Seed"
    , "    AND   b's sector    IS `Information Technology`"
    , "    AND   b's stage_com IS Pre_Revenue"
    , " AND      b's stage     IS `Series A`"
    , "    OR    b's sector    IS `Information Technology`"
    , "    AND   b's stage_com IS Pre_Profit"
    , " OR     inv's wants_ESG"
    , "    AND   b's has_ESG"
    ]

_example9 :: Text
_example9 =
  Text.unlines
    [ "     foo"
    , " AND bar"
    , " OR  foo"
    , " AND baz"
    ]

_example9b :: Text
_example9b =
  Text.unlines
    [ "     foo"
    , " OR  bar"
    , " AND foo"
    , " OR  baz"
    ]

_example10 :: Text
_example10 =
  Text.unlines
    [ "     foo"
    , " AND bar"
    , " AND baz"
    ]

-- This looks wrong, should be foo (AND bar) OR baz
_example11a :: Text
_example11a =
      " foo AND bar OR baz"

-- This is unclear
_example11b :: Text
_example11b =
  Text.unlines
    [ " foo "
    , "     AND bar"
    , "             OR baz"
    ]

_example11c :: Text
_example11c =
  Text.unlines
    [ "                foo"
    , "     AND        bar"
    , "             OR baz"
    ]

-- This is unclear, probably (foo AND bar) OR baz
_example11d :: Text
_example11d =
  Text.unlines
    [ " foo AND bar"
    , "     OR  baz"
    ]

-- Hannes says: (foo OR bar) AND baz
_example11e :: Text
_example11e =
  Text.unlines
    [ " foo OR  bar"
    , "     AND baz"
    ]

-- ----------------------------------------------------------------------------
-- Nlg Annotation parsers.
-- Parse NLG annotations such that we can process them later.
-- ----------------------------------------------------------------------------

execNlgParserForTokens :: Parser a -> NormalizedUri -> Text -> [PosToken] -> Either (ParseErrorBundle TokenStream Void) a
execNlgParserForTokens p uri input ts =
  case runJl4Parser env st p (showNormalizedUri uri) stream of
    Left err -> Left err
    Right (a, _pstate) -> Right a
  where
    env = Env
      { moduleUri = uri
      , mixfixHints = emptyMixfixHintRegistry
      , ofIsAnchor = False
      , memoiseGroups = True
      }
    st = PState
      { nlgs = []
      , comments = []
      , refs = []
      , descs = []
      , fixities = []
      , langs = []
      }
    stream = MkTokenStream (Text.unpack input) ts

-- ----------------------------------------------------------------------------
-- JL4 parsers
-- ----------------------------------------------------------------------------

execParser :: (Resolve.HasNlg a, Resolve.HasDesc a, Resolve.HasRef a, Resolve.HasFixity a) => Parser a -> NormalizedUri -> Text -> Either (NonEmpty PError) (a, [Resolve.Warning], PState)
execParser = execParserWithHints mempty

execParserWithHints :: (Resolve.HasNlg a, Resolve.HasDesc a, Resolve.HasRef a, Resolve.HasFixity a) => MixfixHintRegistry -> Parser a -> NormalizedUri -> Text -> Either (NonEmpty PError) (a, [Resolve.Warning], PState)
execParserWithHints hints p uri input =
  case execLexer uri input of
    Left errs -> Left errs
    Right ts -> execParserForTokensWithHints hints p uri input ts

execParserForTokens :: (Resolve.HasNlg a, Resolve.HasDesc a, Resolve.HasRef a, Resolve.HasFixity a) => Parser a -> NormalizedUri -> Text -> [PosToken] -> Either (NonEmpty PError) (a, [Resolve.Warning], PState)
execParserForTokens = execParserForTokensWithHints mempty

execParserForTokensWithHints :: (Resolve.HasNlg a, Resolve.HasDesc a, Resolve.HasRef a, Resolve.HasFixity a) => MixfixHintRegistry -> Parser a -> NormalizedUri -> Text -> [PosToken] -> Either (NonEmpty PError) (a, [Resolve.Warning], PState)
execParserForTokensWithHints = execParserForTokensWith True

-- | 'execParserForTokensWithHints', with 'memoGroup' on ('True') or off; see
-- 'memoiseGroups'.
execParserForTokensWith :: (Resolve.HasNlg a, Resolve.HasDesc a, Resolve.HasRef a, Resolve.HasFixity a) => Bool -> MixfixHintRegistry -> Parser a -> NormalizedUri -> Text -> [PosToken] -> Either (NonEmpty PError) (a, [Resolve.Warning], PState)
execParserForTokensWith memoise hints p file input ts =
  case runJl4Parser env st p (showNormalizedUri file) stream  of
    Left err -> Left (fmap (mkPError "parser") $ errorBundleToErrorMessages err)
    Right (a, pstate)  ->
      let
        -- The module's declared language, or `en` (R-M2). Taken as the
        -- LAST declaration in source order: `langs` accumulates by
        -- prepending, so the head is the last one written. Two declarations
        -- in one module is not diagnosed here — the list keeps both, so a
        -- check for it has something to read.
        moduleLang = fromMaybe defaultModuleLang (listToMaybe pstate.langs)
        -- Stamp every untagged annotation with it BEFORE attachment, which is
        -- what makes `@lang he` mean exactly "tag every herald in this module
        -- `:he`" rather than a second mechanism with its own precedence — and
        -- makes it order-independent, since pstate is complete by now.
        localisedNlgs = fmap (withDefaultLang moduleLang) pstate.nlgs
        (withNlg, nlgS) = Resolve.addNlgCommentsToAst moduleLang localisedNlgs a
        (withDesc, _descS) = Resolve.addDescCommentsToAst pstate.descs withNlg
        (withFixity, fixityS) = Resolve.addFixityCommentsToAst pstate.fixities withDesc
        (annotatedA, refS) = Resolve.addRefCommentsToAst pstate.refs withFixity
        refWarnings = fmap Resolve.renderRefWarning refS.refWarnings
        fixityWarnings = fmap Resolve.renderFixityWarning fixityS.fixityWarnings
      in
        Right (annotatedA, nlgS.warnings ++ refWarnings ++ fixityWarnings, pstate)
  where
    env = Env
      { moduleUri = file
      , mixfixHints = hints
      , ofIsAnchor = False
      , memoiseGroups = memoise
      }
    st = PState
      { nlgs = []
      , comments = []
      , refs = []
      , descs = []
      , fixities = []
      , langs = []
      }
    stream = MkTokenStream (Text.unpack input) ts

runJl4Parser :: Env -> PState -> Parser a -> FilePath -> TokenStream -> Either (ParseErrorBundle TokenStream Void) (a, PState)
runJl4Parser env initState p input stream =
  evalState
    (runParserT (runStateT (runReaderT (p <* eof) env) initState) input stream)
    emptyGroupMemo

-- ----------------------------------------------------------------------------
-- JL4 Program parser
-- ----------------------------------------------------------------------------

execProgramParser :: NormalizedUri -> Text -> Either (NonEmpty PError) (Module Name, [Resolve.Warning])
execProgramParser uri input =
  forgetPState $ execParser (module' uri) uri input
  where
    forgetPState = fmap (\(p, warns, _) -> (p, warns))

execProgramParserForTokens :: NormalizedUri -> Text -> [PosToken] -> Either (NonEmpty PError) (Module Name, [Resolve.Warning])
execProgramParserForTokens uri input ts =
  forgetPState $  execParserForTokens (module' uri) uri input ts
  where
    forgetPState = fmap (\(p, warns, _) -> (p, warns))

execProgramParserWithHints :: MixfixHintRegistry -> NormalizedUri -> Text -> Either (NonEmpty PError) (Module Name, [Resolve.Warning])
execProgramParserWithHints hints uri input =
  forgetPState $ execParserWithHints hints (module' uri) uri input
  where
    forgetPState = fmap (\(p, warns, _) -> (p, warns))

execProgramParserForTokensWithHints :: MixfixHintRegistry -> NormalizedUri -> Text -> [PosToken] -> Either (NonEmpty PError) (Module Name, [Resolve.Warning])
execProgramParserForTokensWithHints hints uri input ts =
  forgetPState $ execParserForTokensWithHints hints (module' uri) uri input ts
  where
    forgetPState = fmap (\(p, warns, _) -> (p, warns))

-- | Two-pass parser helper: first parse without hints to collect mixfix keywords,
-- then re-run the parser with the discovered hints so later phases can rely on them.
execProgramParserWithHintPass ::
  NormalizedUri ->
  Text ->
  Either (NonEmpty PError) (Module Name, MixfixHintRegistry, [Resolve.Warning])
execProgramParserWithHintPass = programParserWithHintPass True

-- | 'execProgramParserWithHintPass' with 'memoGroup' switched off, so that
-- every bracketed group is parsed afresh wherever it is reached. That takes
-- time exponential in how deeply groups nest, and the answer must be
-- identical: it exists for the tests that check so (see 'memoGroup').
execProgramParserWithHintPassUnmemoised ::
  NormalizedUri ->
  Text ->
  Either (NonEmpty PError) (Module Name, MixfixHintRegistry, [Resolve.Warning])
execProgramParserWithHintPassUnmemoised = programParserWithHintPass False

programParserWithHintPass ::
  Bool ->
  NormalizedUri ->
  Text ->
  Either (NonEmpty PError) (Module Name, MixfixHintRegistry, [Resolve.Warning])
programParserWithHintPass memoise uri input = do
  ts <- execLexer uri input
  (firstModule, _) <- programParser mempty ts
  let hints = buildMixfixHintRegistry firstModule
  (finalModule, finalWarnings) <- programParser hints ts
  pure (finalModule, hints, finalWarnings)
  where
    programParser hints ts =
      (\ (m, warns, _) -> (m, warns)) <$> execParserForTokensWith memoise hints (module' uri) uri input ts

-- ----------------------------------------------------------------------------
-- Debug helpers
-- ----------------------------------------------------------------------------

-- | Parse a source file and pretty-print the resulting syntax tree.
parseFile :: (Show a, Resolve.HasNlg a, Resolve.HasDesc a, Resolve.HasRef a, Resolve.HasFixity a) => Parser a -> NormalizedUri -> Text -> IO ()
parseFile p uri input =
  case execParser p uri input of
    Left errs -> Text.putStr $ Text.unlines $ fmap (.message) (toList errs)
    Right (x, _, _pState) -> pPrint x

-- ----------------------------------------------------------------------------
-- jl4 specific annotation helpers
-- ----------------------------------------------------------------------------

type AnnoParser = AnnoParser_ Parser PosToken

type Epa = Epa_ PosToken

type Lexeme = Lexeme_ PosToken
