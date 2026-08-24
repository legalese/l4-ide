-- | The tiny XML tree that both directions of the Blawx bridge use, and a
-- __recogniser__ for the Blockly serialiser's output (BLAWX-EXPORT-SPEC §10
-- P5, ruling P5-5).
--
-- 'XNode', 'renderNode', 'escapeText' and 'escapeAttr' were "L4.Blawx.EmitXml"'s
-- private machinery and are /relocated/ here, not copied: the P1\/P3 goldens
-- are the regression gate on the whole P5 extension, and two copies of an
-- escaper is exactly how a golden moves for a reason nobody can find.
--
-- __This is not an XML parser.__ It is a recogniser for one serialiser's
-- output, and it __refuses__ everything outside that subset rather than
-- guessing: no XML declaration, no DOCTYPE, no processing instruction, no
-- CDATA, no unquoted or single-quoted attribute value, no entity outside the
-- five named ones plus numeric character references, no text outside
-- @\<field\>@ and @\<comment\>@. The cost of being wrong is a silent
-- mis-parse of a legal rule, so the failure mode is deliberately loud.
--
-- Measured over all 1,953 blocks of the 15 shipped examples, the wild grammar
-- is closed: 8 elements (@xml block field value statement next mutation
-- comment@), zero CDATA\/DOCTYPE\/PI\/self-closing tags, attribute values
-- always double-quoted, and @&quot;@ the only entity. What forces the parser
-- to be /wider/ than the wild corpus is our own emitter, which the round-trip
-- property @lift . emit = id@ must read back:
--
-- 1. __Numeric character references.__ 'escapeAttr' emits @&#10;@, @&#13;@ and
--    @&#9;@, and 'escapeText' emits @&#13;@. The wild corpus has none.
-- 2. __Inter-tag whitespace.__ @L4.Blawx.Emit.renderBlawxYaml@ stores XML as
--    three lines, so the reader must skip whitespace between tags without
--    treating it as text; all 132 wild rows are single-line.
-- 3. __XML normalisation semantics.__ To behave as
--    @Blockly.utils.xml.textToDom@ (a real @DOMParser@) does, input is
--    end-of-line normalised (CRLF and lone CR to LF) before tokenising, and
--    literal tab\/LF\/CR in an attribute value become spaces while character
--    references stay literal. 'escapeAttr' escapes precisely those characters
--    /because/ of this rule, so on our own output both passes are no-ops.
--
-- Offsets in an 'XmlError' are into the end-of-line-normalised text, which is
-- what the parser actually consumed; on a CRLF-free document (every row in
-- both corpora) that is the input offset.
module L4.Blawx.Xml
  ( -- * The tree
    XNode (..)
  , renderNode
  , escapeText
  , escapeAttr
  , unrepresentable
    -- * Reading one back
  , parseXml
  , XmlError (..)
  , renderXmlError
    -- * Small accessors
  , elemText
  , childElems
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (chr, digitToInt, isDigit, isHexDigit, isSpace)

-- ---------------------------------------------------------------------------
-- The tree
-- ---------------------------------------------------------------------------

-- | Built as a tree rather than as text so "L4.Blawx.EmitXml" can assign the
-- id counter in one document-order pass and the layout in another, which is
-- also why attributes come out in Blockly's own order (@type@, @id@, @x@,
-- @y@).
data XNode
  = XElem !Text ![(Text, Text)] ![XNode]
  | XText !Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Never self-closing: @Blockly.Xml.domToText@ round-trips through
-- @XMLSerializer@, which writes @\<mutation …\>\<\/mutation\>@ and
-- @\<field name=\"prefix\"\>\<\/field\>@, and matching it keeps our XML
-- diffable against a re-save.
renderNode :: XNode -> Text
renderNode = \case
  XText t -> escapeText t
  XElem name attrs kids ->
    "<" <> name
      <> Text.concat [" " <> k <> "=\"" <> escapeAttr v <> "\"" | (k, v) <- attrs]
      <> ">"
      <> Text.concat (map renderNode kids)
      <> "</" <> name <> ">"

-- | Text content: @&@, @\<@, @\>@ — and @\\r@, which XML 1.0 end-of-line
-- normalisation rewrites to @\\n@ in element content just as it does in an
-- attribute value, so a literal CR in a @\<field\>@ would come back changed.
-- Apostrophes are NOT escaped — the NLG slots are full of them (@\'s score
-- is@) and escaping them would change the field value the generator reads
-- back. Tab and LF survive normalisation in element content and stay literal.
--
-- 'unrepresentable' characters are dropped here for totality only: they are
-- rejected up front by @L4.Blawx.EmitXml@'s @representable@, which turns them
-- into an @XmlGap@ rather than a silent rewrite.
escapeText :: Text -> Text
escapeText = Text.concatMap $ \case
  '&'  -> "&amp;"
  '<'  -> "&lt;"
  '>'  -> "&gt;"
  '\r' -> "&#13;"
  c | unrepresentable c -> ""
    | otherwise -> Text.singleton c

-- | Attribute values: additionally @\"@ (the evidence ships
-- @&quot;@-escaped attributes), and the three legal whitespace controls as
-- character references — an XML parser normalises literal newlines and tabs
-- in an attribute value to spaces, which would corrupt the datum silently.
-- Nothing we put in an attribute can contain them today (every mutation
-- attribute is a Blawx atom, a section ref, a type keyword or @ov@); this is
-- the belt for the braces.
escapeAttr :: Text -> Text
escapeAttr = Text.concatMap $ \case
  '&'  -> "&amp;"
  '<'  -> "&lt;"
  '>'  -> "&gt;"
  '"'  -> "&quot;"
  '\n' -> "&#10;"
  '\r' -> "&#13;"
  '\t' -> "&#9;"
  c | unrepresentable c -> ""
    | otherwise -> Text.singleton c

-- | C0 controls other than tab\/LF\/CR cannot be represented in XML 1.0 at
-- all — not even as a character reference.
unrepresentable :: Char -> Bool
unrepresentable c = c < ' ' && c /= '\t' && c /= '\n' && c /= '\r'

-- | The concatenated character data directly inside an element. Blockly puts
-- a field's value in exactly one text node, but concatenating is what a DOM
-- @textContent@ does and costs nothing.
elemText :: XNode -> Text
elemText = \case
  XElem _ _ kids -> Text.concat [t | XText t <- kids]
  XText t -> t

-- | The element children of an element, in document order.
childElems :: XNode -> [XNode]
childElems = \case
  XElem _ _ kids -> [k | k@XElem{} <- kids]
  XText _ -> []

-- ---------------------------------------------------------------------------
-- Errors
-- ---------------------------------------------------------------------------

-- | Where the recogniser stopped, and why. The offset is into the
-- end-of-line-normalised input.
data XmlError = MkXmlError
  { xeOffset  :: !Int
  , xeMessage :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

renderXmlError :: XmlError -> Text
renderXmlError e = "offset " <> Text.textShow e.xeOffset <> ": " <> e.xeMessage

-- ---------------------------------------------------------------------------
-- The recogniser
-- ---------------------------------------------------------------------------

data PState = MkPState
  { psOff  :: !Int
  , psRest :: !Text
  }

type P = StateT PState (Either XmlError)

-- | Parse one document: optional whitespace, exactly one element, optional
-- whitespace, end of input.
parseXml :: Text -> Either XmlError XNode
parseXml src = evalStateT doc (MkPState 0 (normaliseEol src))
 where
  doc = do
    skipSpaces
    n <- element
    skipSpaces
    s <- get
    unless (Text.null s.psRest) $
      perr "trailing content after the root element"
    pure n

-- | XML 1.0 end-of-line normalisation, which every conforming parser (and
-- therefore @DOMParser@, and therefore Blockly) applies before anything else.
normaliseEol :: Text -> Text
normaliseEol = Text.replace "\r" "\n" . Text.replace "\r\n" "\n"

perr :: Text -> P a
perr m = do
  s <- get
  lift (Left (MkXmlError s.psOff m))

peekC :: P (Maybe Char)
peekC = do
  s <- get
  pure (fst <$> Text.uncons s.psRest)

-- | Is this literal next?
lookingAt :: Text -> P Bool
lookingAt t = do
  s <- get
  pure (t `Text.isPrefixOf` s.psRest)

advance :: Int -> P ()
advance n = modify' \s -> MkPState (s.psOff + n) (Text.drop n s.psRest)

munch :: (Char -> Bool) -> P Text
munch p = do
  s <- get
  let (taken, rest) = Text.span p s.psRest
  put (MkPState (s.psOff + Text.length taken) rest)
  pure taken

expectChar :: Char -> P ()
expectChar c = do
  mc <- peekC
  case mc of
    Just c' | c' == c -> advance 1
    Just c' -> perr ("expected " <> Text.singleton c <> ", found " <> Text.singleton c')
    Nothing -> perr ("expected " <> Text.singleton c <> ", found end of input")

skipSpaces :: P ()
skipSpaces = void (munch isSpace)

-- | @Name@ in the Blockly subset: an ASCII word run. Colons are deliberately
-- NOT accepted — a prefixed element would mean a namespace we do not resolve,
-- and the wild corpus declares namespaces only as default @xmlns@ attributes.
xmlName :: P Text
xmlName = do
  n <- munch nameChar
  when (Text.null n) $ perr "expected an element or attribute name"
  pure n
 where
  nameChar c = c == '_' || c == '-' || c == '.' || isAsciiAlphaNum c
  isAsciiAlphaNum c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')

element :: P XNode
element = do
  expectChar '<'
  isPI <- lookingAt "?"
  when isPI $ perr "an XML declaration or processing instruction is not part of the Blockly subset"
  isBang <- lookingAt "!"
  when isBang $
    perr "a DOCTYPE, comment or CDATA section is not part of the Blockly subset"
  isClose <- lookingAt "/"
  when isClose $ perr "unexpected close tag"
  name <- xmlName
  (attrs, selfClosed) <- attributes
  if selfClosed
    then pure (XElem name attrs [])
    else do
      kids <- children name
      pure (XElem name attrs kids)

attributes :: P ([(Text, Text)], Bool)
attributes = go []
 where
  go acc = do
    skipSpaces
    mc <- peekC
    case mc of
      Nothing -> perr "unexpected end of input inside a start tag"
      Just '>' -> do
        advance 1
        pure (reverse acc, False)
      Just '/' -> do
        slashGt <- lookingAt "/>"
        unless slashGt $ perr "expected /> "
        advance 2
        pure (reverse acc, True)
      Just _ -> do
        k <- xmlName
        skipSpaces
        expectChar '='
        skipSpaces
        q <- peekC
        case q of
          Just '"' -> pure ()
          Just '\'' -> perr "a single-quoted attribute value is not part of the Blockly subset"
          _ -> perr "expected a double-quoted attribute value"
        advance 1
        s0 <- get
        raw <- munch (/= '"')
        expectChar '"'
        -- Attribute-value normalisation: literal tab/LF/CR become spaces,
        -- character references do not. Hence: normalise, THEN decode.
        v <- decodeRefsAt s0.psOff (Text.map attrWs raw)
        go ((k, v) : acc)
  attrWs c = if c == '\t' || c == '\n' then ' ' else c

-- | The children of an element, up to its matching close tag. Text is kept
-- only inside @\<field\>@ and @\<comment\>@ — the only two elements that bear
-- any in either corpus — and blank text elsewhere is dropped, because that is
-- the inter-tag whitespace our own emitter writes between root blocks.
children :: Text -> P [XNode]
children parent = go []
 where
  go acc = do
    mc <- peekC
    case mc of
      Nothing -> perr ("unexpected end of input; <" <> parent <> "> is not closed")
      Just '<' -> do
        isClose <- lookingAt "</"
        if isClose
          then do
            advance 2
            n <- xmlName
            skipSpaces
            expectChar '>'
            unless (n == parent) $
              perr ("mismatched close tag </" <> n <> "> (expected </" <> parent <> ">)")
            pure (reverse acc)
          else do
            e <- element
            go (e : acc)
      Just _ -> do
        s <- get
        raw <- munch (/= '<')
        t <- decodeRefsAt s.psOff raw
        if bearsText parent
          then go (XText t : acc)
          else
            if Text.all isSpace t
              then go acc
              else do
                put s
                perr ("character data is not allowed inside <" <> parent <> ">")
  bearsText p = p == "field" || p == "comment"

-- | @&amp; &lt; &gt; &quot; &apos;@ and numeric character references. Anything
-- else is refused by name rather than passed through, because an unresolved
-- entity in a rule is a changed rule.
decodeRefsAt :: Int -> Text -> P Text
decodeRefsAt base t = go 0 t
 where
  go !i s = case Text.breakOn "&" s of
    (pre, rest)
      | Text.null rest -> pure pre
      | otherwise -> do
          let atRef = i + Text.length pre
              body = Text.drop 1 rest
              (name, after) = Text.breakOn ";" body
          when (Text.null after) $ failAt atRef "unterminated entity reference"
          c <- refChar atRef name
          more <- go (atRef + Text.length name + 2) (Text.drop 1 after)
          pure (pre <> c <> more)
  refChar at name = case name of
    "amp" -> pure "&"
    "lt" -> pure "<"
    "gt" -> pure ">"
    "quot" -> pure "\""
    "apos" -> pure "'"
    _ | Just hex <- Text.stripPrefix "#x" name -> codepoint at 16 isHexDigit hex
      | Just dec <- Text.stripPrefix "#" name -> codepoint at 10 isDigit dec
      | otherwise -> failAt at ("unknown entity reference &" <> name <> ";")
  codepoint at radix ok ds
    | Text.null ds || not (Text.all ok ds) =
        failAt at "malformed numeric character reference"
    | otherwise =
        let n = Text.foldl' (\ !a d -> a * radix + digitToInt d) 0 ds
        in  if n <= 0 || n > 0x10FFFF
              then failAt at "numeric character reference out of range"
              else pure (Text.singleton (chr n))
  failAt at m = do
    modify' \s -> MkPState (base + at) s.psRest
    perr m
