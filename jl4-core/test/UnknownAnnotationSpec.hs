{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | An annotation this version of L4 does not know (a line annotation spelled
-- @\@something@) is trivia and a warning, not a lexer error.
--
-- The model is GHC's @-Wunrecognised-pragmas@: an unknown @{-# FOO #-}@ is
-- treated as a comment, and the compiler says so. The point is forward
-- compatibility. A lexer error leaves a file with no tokens at all, so a
-- module that uses an annotation from a newer L4 loses its highlighting in
-- every editor still running an older one, as well as failing to check.
--
-- These tests go through the lexer and the parser, not through the warning
-- (which is a diagnostic: "UnknownAnnotationLspSpec" in jl4-lsp-test and
-- jl4-cli's @l4 check@ test cover that).
module UnknownAnnotationSpec (spec) where

import Base
import Data.Either (isLeft)
import qualified Base.Set as Set
import qualified Base.Text as Text

import L4.ExactPrint (exactprint)
import L4.Lexer
  ( AnnoType (..)
  , FixityDirection (..)
  , PError (..)
  , PosToken (..)
  , TAnnotations (..)
  , TSpaces (..)
  , TokenType (..)
  , computedPayload
  , displayTokenType
  , execLexer
  , knownAnnotationHeralds
  )
import L4.Parser (execProgramParserWithHintPass)
import L4.Parser.SrcSpan (SrcRange (..), SrcPos (..))
import L4.IgnoredAnnotation
  ( IgnoredAnnotation (..)
  , Problem (..)
  , ignoredAnnotationMessage
  , ignoredAnnotations
  , nearestKnownHerald
  , renderIgnoredAnnotation
  )
import Test.Hspec

specUri :: NormalizedUri
specUri = toNormalizedUri (Uri "file:///unknown-annotation-spec")

lexed :: Text -> IO [PosToken]
lexed src =
  case execLexer specUri src of
    Left errs -> do
      expectationFailure $ "the lexer refused the source: " <> show errs
      error "unreachable"
    Right toks -> pure toks

-- | The annotation tokens of a source, as the lexer classes them.
annotationTokens :: Text -> IO [TAnnotations]
annotationTokens src = do
  toks <- lexed src
  pure [ a | t <- toks, TAnnotations a <- [computedPayload t] ]

-- | Lexing loses no byte: the tokens print back to the source.
lexRoundTrips :: Text -> Expectation
lexRoundTrips src = do
  toks <- lexed src
  Text.concat [ displayTokenType (computedPayload t) | t <- toks ] `shouldBe` src

-- | Exactprint of the parsed module is the source, byte for byte.
exactprintRoundTrips :: Text -> Expectation
exactprintRoundTrips src =
  case execProgramParserWithHintPass specUri src of
    Left errs -> expectationFailure $ "the parser refused the source: " <> show errs
    Right (m, _hints, _warnings) ->
      case exactprint m of
        Left err -> expectationFailure $ "exactprint failed: " <> show err
        Right printed -> printed `shouldBe` src

rule :: [Text]
rule =
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE `add one` n IS n + 1"
  ]

-- | Where an unknown annotation can sit. Each is a whole module.
positions :: [(String, Text)]
positions =
  [ ("on the first line", Text.unlines $ "@future-annotation some text" : rule)
  , ("between two rules"
    , Text.unlines $ rule <> ["", "@future-annotation some text", ""] <> rule)
  , ("between GIVETH and DECIDE"
    , Text.unlines ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "@future-annotation some text", "DECIDE `add one` n IS n + 1"])
  , ("between two known annotations"
    , Text.unlines $ ["@desc one", "@future-annotation some text", "@desc two"] <> rule)
  , ("after the last rule, with no newline"
    , Text.unlines rule <> "@future-annotation some text")
  , ("with nothing after the herald"
    , Text.unlines $ "@future-annotation" : rule)
  , ("with a hyphenated and a numbered herald"
    , Text.unlines $ ["@future-annotation-2 x", "@v2 y"] <> rule)
  ]

-- | A KNOWN annotation that does not have the form it needs. Only @\@lang@ can
-- fail this way: every other herald accepts a bare herald, a trailing space, a
-- tab and a non-ASCII letter (the test "can only be @lang" below keeps that true).
-- The lexer used to stop at each of these, which blanks the whole file in an
-- editor just as an unknown annotation did.
malformedLangs :: [(String, Text)]
malformedLangs =
  [ ("a bare @lang", "@lang\n")
  , ("@lang at the end of the file, with no newline", "@lang")
  , ("@lang and nothing but spaces", "@lang   \n")
  , ("@lang then a tab, where a space goes", "@lang\ten\n")
  , ("@lang then a non-ASCII code", "@lang \233\n")
  , ("@lang then a colon, as @nlg:he has", "@lang:en\n")
  ]

spec :: Spec
spec = do
  describe "an unknown annotation" $
    forM_ positions $ \(where_, src) -> describe where_ $ do
      it "lexes (it is not a lexer error)" $
        void (lexed src)
      it "is not read as any known annotation" $ do
        annos <- annotationTokens src
        -- the only annotation tokens are the @desc ones the sources write
        length annos `shouldBe` length [ () | l <- Text.lines src, "@desc" `Text.isPrefixOf` l ]
      it "keeps every byte when lexed" $
        lexRoundTrips src
      it "parses" $
        case execProgramParserWithHintPass specUri src of
          Left errs -> expectationFailure $ "the parser refused the source: " <> show errs
          Right _ -> pure ()
      it "is reproduced byte for byte by exactprint" $
        exactprintRoundTrips src

  describe "a known annotation that is malformed" $
    forM_ malformedLangs $ \(what, line) ->
      forM_ [("on the first line", line <> Text.unlines (""  : rule)), ("between two rules", Text.unlines rule <> line <> Text.unlines ("" : rule))] $ \(where_, src) ->
        describe (what <> ", " <> where_) $ do
          it "lexes (it is not a lexer error)" $
            void (lexed src)
          it "is read as no annotation at all" $ do
            annos <- annotationTokens src
            annos `shouldBe` []
          it "keeps every byte when lexed" $
            lexRoundTrips src
          it "parses" $
            case execProgramParserWithHintPass specUri src of
              Left errs -> expectationFailure $ "the parser refused the source: " <> show errs
              Right _ -> pure ()
          it "is reproduced byte for byte by exactprint" $
            exactprintRoundTrips src

  describe "a known annotation" $ do
    it "is lexed as before" $ do
      annos <- annotationTokens (Text.unlines everyKnownAnnotation)
      length annos `shouldBe` length everyKnownAnnotation

    -- 'knownAnnotationHeralds' is a list kept by hand next to the lexers. This
    -- reads the names off the tokens instead, by a function that must name
    -- every constructor, so adding an annotation to the lexer breaks this
    -- file's build until the table here and the list there are both updated.
    it "has exactly the names in knownAnnotationHeralds" $ do
      annos <- annotationTokens (Text.unlines everyKnownAnnotation)
      Set.fromList (mapMaybe heraldOf annos)
        `shouldBe` Set.fromList knownAnnotationHeralds

    it "is never taken for an unknown one" $ do
      toks <- lexed (Text.unlines everyKnownAnnotation)
      [ n | t <- toks, TSpaces (TIgnoredAnnotation n _) <- [computedPayload t] ]
        `shouldBe` []

  describe "the token an unknown annotation makes" $ do
    it "holds the name without the @, and the rest of the line verbatim" $ do
      toks <- lexed "@future-annotation  some text -- and a comment\nGIVEN x IS A NUMBER\n"
      [ (n, r) | t <- toks, TSpaces (TIgnoredAnnotation n r) <- [computedPayload t] ]
        `shouldBe` [("future-annotation", "  some text -- and a comment")]

    it "ends the name at a hyphen that no name character follows" $ do
      toks <- lexed "@foo-- bar\n"
      [ n | t <- toks, TSpaces (TIgnoredAnnotation n _) <- [computedPayload t] ]
        `shouldBe` ["foo"]

    it "is not made of an @ with no name after it" $
      forM_ ["@\n", "@ foo\n", "@1x\n", "@-x\n", "@"] $ \src ->
        execLexer specUri src `shouldSatisfy` isLeft

    -- The error that remains must still say what could have stood where the @
    -- is. Reading ahead for the annotation shape used to leave its own failure
    -- in the error, which swallowed that list and said only "expecting end of
    -- input or whitespace": false mid-file, and worse than before annotations
    -- were ignored (found in review).
    it "still lists what could have stood there, annotations included" $
      forM_ ["@\n", "@ foo\n", "@1x\n", "@-x\n", "@"] $ \src ->
        case execLexer specUri src of
          Right _ -> expectationFailure ("the lexer accepted " <> show src)
          Left (e :| _) -> do
            e.message `shouldSatisfy` Text.isInfixOf "unexpected '@'"
            e.message `shouldSatisfy` Text.isInfixOf "\"@export\""
            e.message `shouldSatisfy` Text.isInfixOf "\"--\""

  describe "a known annotation that is malformed" $ do
    it "makes the same token an unknown one does, named for the annotation" $
      forM_ malformedLangs $ \(what, line) -> do
        toks <- lexed (line <> "\n")
        (what, [ n | t <- toks, TSpaces (TIgnoredAnnotation n _) <- [computedPayload t] ])
          `shouldBe` (what, ["lang"])

    -- The claim in the lexer and in the warning is that @lang is the only known
    -- annotation that can be refused. This is that claim, measured: write each
    -- known annotation bare and in three odd forms, and see which come back as
    -- ignored. A new annotation with structured arguments joins the list or
    -- changes the message, and this is what tells whoever adds it.
    it "can only be @lang" $ do
      refused <- fmap concat $ forM knownAnnotationHeralds $ \h ->
        fmap concat $ forM ["@" <> h <> "\n", "@" <> h <> " \n", "@" <> h <> "\tx\n", "@" <> h <> " \233\n"] $ \src -> do
          toks <- lexed src
          pure [ h | t <- toks, TSpaces (TIgnoredAnnotation _ _) <- [computedPayload t] ]
      Set.toList (Set.fromList refused) `shouldBe` ["lang"]

  describe "ignoredAnnotations" $ do
    it "reports each one with its range and its problem, and nothing for a known annotation" $ do
      toks <- lexed $ Text.unlines
        [ "@desc known"
        , "@future-annotation some text"
        , "GIVEN n IS A NUMBER"
        , "  @another one"
        , "@lang"
        , "@exprot"
        ]
      [ (u.name, u.range.start, u.range.length, u.problem) | u <- ignoredAnnotations toks ]
        `shouldBe`
          [ ("future-annotation", MkSrcPos 2 1, Text.length "@future-annotation some text", Unrecognised Nothing)
          , ("another", MkSrcPos 4 3, Text.length "@another one", Unrecognised Nothing)
          , ("lang", MkSrcPos 5 1, Text.length "@lang", Malformed)
          , ("exprot", MkSrcPos 6 1, Text.length "@exprot", Unrecognised (Just "export"))
          ]

  describe "renderIgnoredAnnotation" $
    it "is line:column: message" $ do
      toks <- lexed "GIVEN n IS A NUMBER @oops\n"
      [ renderIgnoredAnnotation a | a <- ignoredAnnotations toks ]
        `shouldBe` [ "1:21: " <> ignoredAnnotationMessage a | a <- ignoredAnnotations toks ]

  describe "nearestKnownHerald" $ do
    forM_ [ ("exprot", "export"), ("Desc", "desc"), ("EXPORT", "export")
          , ("ref_src", "ref-src"), ("refsrc", "ref-src"), ("infxl", "infixl")
          , ("nonexaustive", "nonexhaustive"), ("langs", "lang")
          ] $ \(typo, intended) ->
      it (Text.unpack typo <> " is a misspelling of " <> Text.unpack intended) $
        nearestKnownHerald typo `shouldBe` Just intended

    forM_ ["description", "zebra", "x", "future-annotation", "ab"] $ \name ->
      it (Text.unpack name <> " is near nothing") $
        nearestKnownHerald name `shouldBe` Nothing

  describe "ignoredAnnotationMessage" $ do
    let anAnnotation n problem = MkIgnoredAnnotation
          { range = MkSrcRange (MkSrcPos 1 1) (MkSrcPos 1 5) 4 specUri
          , name = n
          , problem
          }
        unrecognised n = anAnnotation n (Unrecognised (nearestKnownHerald n))
    it "names the annotation and says what happens to it" $
      ignoredAnnotationMessage (unrecognised "exprot") `shouldSatisfy`
        \m -> all (`Text.isInfixOf` m)
          [ "`@exprot`", "ignored", "the rest of its line" ]
    it "suggests the nearest known annotation" $
      ignoredAnnotationMessage (unrecognised "exprot") `shouldSatisfy`
        Text.isSuffixOf "Did you mean `@export`?"
    it "lists the annotations it knows when it has no suggestion" $
      ignoredAnnotationMessage (unrecognised "future-annotation") `shouldSatisfy`
        \m -> all (\k -> ("@" <> k) `Text.isInfixOf` m) knownAnnotationHeralds
    it "says what a malformed @lang needs, with an example" $
      ignoredAnnotationMessage (anAnnotation "lang" Malformed) `shouldBe`
        "Malformed annotation `@lang`: it needs a language code after a space, such as `@lang en` (letters, digits and hyphens), so this line is ignored."

  -- A name that BEGINS with a known annotation is read as that annotation with
  -- stray text, as it always was: `@descr x` is `@desc` with the text "r x". The
  -- lexer ignores only what it used to refuse. This is the lexer half of a check
  -- that the service deploys what it deployed before: 12 annotations by 5
  -- suffixes (`x`, `2`, `_x`, `-x`, a non-ASCII letter), written above a rule and
  -- deployed to a build from before this change and to this one gave identical
  -- outcomes, 50 accepted with the same functions and 10 refused; the 50 are the
  -- forms that lex as a known annotation below, the 10 are `@lang` with any
  -- suffix and `@nonassertable` with all but `-x` (which lexes, and then fails
  -- in the parser, as it did).
  describe "a name that begins with a known annotation" $ do
    let ignoredNames src = do
          toks <- lexed src
          pure [ n | t <- toks, TSpaces (TIgnoredAnnotation n _) <- [computedPayload t] ]
        suffixes = ["x", "2", "_x", "-x", "\233"]
    forM_ (filter (`notElem` ["lang", "nonassertable"]) knownAnnotationHeralds) $ \herald ->
      forM_ suffixes $ \suffix ->
        it ("@" <> Text.unpack (herald <> suffix) <> " is @" <> Text.unpack herald <> " with stray text, as before") $ do
          let src = "@" <> herald <> suffix <> " some text\n"
          ignoredNames src >>= (`shouldBe` [])
          annos <- annotationTokens src
          length annos `shouldBe` 1
    forM_ suffixes $ \suffix ->
      it ("@lang" <> Text.unpack suffix <> " is ignored (its lexer needs a space and a code), and so was a lexer error") $
        ignoredNames ("@lang" <> suffix <> " some text\n") >>= (`shouldBe` ["lang" <> suffix])
    forM_ (filter (/= "-x") suffixes) $ \suffix ->
      it ("@nonassertable" <> Text.unpack suffix <> " is ignored (its lexer refuses a name character after it)") $
        ignoredNames ("@nonassertable" <> suffix <> " some text\n") >>= (`shouldBe` ["nonassertable" <> suffix])
    it "@nonassertable-x is @nonassertable and then source, as before (the parser refuses it)" $ do
      let src = "@nonassertable-x some text\n"
      ignoredNames src >>= (`shouldBe` [])
      annos <- annotationTokens src
      annos `shouldBe` [TNonassertable]

  -- The tokens themselves, as the lexer built them before this change (compared
  -- by review with the build from before it, through `l4 ast`): the known
  -- annotation, and the rest of the name as the first characters of its text.
  describe "the token a name that begins with a known annotation makes" $
    forM_ [ ("@descr longer", TDesc "r longer")
          , ("@ref-x citation", TRef "-x citation" LineAnno)
          , ("@nlgg the number", TNlg Nothing "g the number" LineAnno)
          , ("@exports default x", TExport "s default x")
          , ("@infixlx 6", TFixity FixityLeft "x 6")
          ] $ \(src, expected) ->
      it (Text.unpack src <> " is " <> show expected) $
        annotationTokens (src <> "\n") >>= (`shouldBe` [expected])

  describe "a known annotation" $
    forM_ [ "@nlg x", "@nlg:he x", "@nlg: see below", "@nlg", "@desc x", "@desc: x"
          , "@desc-- a comment", "@export default x", "@ref x", "@ref-src x"
          , "@ref-map x y", "@infix 5", "@infixl 5", "@infixr 5"
          , "@nonexhaustive", "@nonexhaustive x", "@nonassertable", "@nonassertable -- x"
          ] $ \line ->
      it (Text.unpack line <> " is lexed as the annotation it names") $ do
        let src = line <> "\n"
        annos <- annotationTokens src
        length annos `shouldBe` 1
        toks <- lexed src
        [ n | t <- toks, TSpaces (TIgnoredAnnotation n _) <- [computedPayload t] ]
          `shouldBe` []

-- | One line of every annotation the lexer knows, in the forms it takes.
everyKnownAnnotation :: [Text]
everyKnownAnnotation =
  [ "@desc a description"
  , "@export default an export"
  , "@nlg the thing"
  , "@nlg:he the thing"
  , "@ref Section 3"
  , "@ref-src some source"
  , "@ref-map name http://example.com"
  , "@infix 5"
  , "@infixl 5"
  , "@infixr 5"
  , "@nonexhaustive"
  , "@nonassertable"
  , "@lang he"
  ]

-- | The name a token has in 'knownAnnotationHeralds'. Total over 'TAnnotations'
-- on purpose, with no wildcard (see "has exactly the names in
-- knownAnnotationHeralds"). The two constructors that exist only inside an
-- annotation's own text have no herald of their own.
heraldOf :: TAnnotations -> Maybe Text
heraldOf = \case
  TNlg {}          -> Just "nlg"
  TRefSrc {}       -> Just "ref-src"
  TRefMap {}       -> Just "ref-map"
  TRef {}          -> Just "ref"
  TNlgString {}    -> Nothing
  TNlgPrefix {}    -> Nothing
  TDesc {}         -> Just "desc"
  TExport {}       -> Just "export"
  TFixity dir _    -> Just case dir of
                        FixityLeft  -> "infixl"
                        FixityRight -> "infixr"
                        FixityNone  -> "infix"
  TNonexhaustive{} -> Just "nonexhaustive"
  TNonassertable   -> Just "nonassertable"
  TLang {}         -> Just "lang"
