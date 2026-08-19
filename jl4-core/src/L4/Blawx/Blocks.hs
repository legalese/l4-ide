-- | Layer 3 of the import: Blockly XML to a __block tree__, the lossless
-- shape that sits between "L4.Blawx.Xml" and the IR (BLAWX-EXPORT-SPEC §10 P5).
--
-- __Why a layer at all.__ Ruling P5-1 keeps dates out of the IR this phase,
-- while the brief's evidence item 3 wants the date-layer examples to "parse"
-- and be refused later. With one representation those cannot both hold. With
-- 'BlockTree' between XML and IR they both do: a block tree is total over all
-- 47 block types the corpus uses, and the refusal happens at
-- /classification/ ("L4.Blawx.Parse"), by name, with the owning spec cited.
-- The census smoke therefore reports at the layer where the truth is.
--
-- Everything discarded here is discarded __at the boundary__, so no
-- downstream code can accidentally depend on it:
--
--   * __Block @id@s__ (1,849 distinct 20-character Blockly gensyms over a
--     charset that includes @=@) are not a field of the type, so every
--     equality is modulo ids by construction rather than by a comparison
--     someone could forget.
--   * __Menu-cache mutation attributes__ (@category_list@ 9, @attribute_list@
--     4, @type_list@ 1) are dropped silently, matching
--     "L4.Blawx.EmitXml"'s decision never to emit them: every restorer that
--     reads one has an explicit reverse-compatibility branch.
--   * __@xmlns@__ is an ordinary attribute and is ignored; the 880
--     @\<mutation\>@ elements each re-declare the xhtml namespace, and
--     matching is on the local name throughout.
--
-- Two shapes are load-bearing rather than cosmetic:
--
--   * __@\<next\>@ is flattened__ into the enclosing statement list — the
--     inverse of @EmitXml.chainBlocks@. Measured: 369 @\<next\>@ elements, and
--     the six root-capable types (227 top-level blocks, exactly the count of
--     blocks carrying @x@\/@y@) never carry one, so flattening loses nothing.
--   * __@x@\/@y@ are read only on roots__ (227 of 227 roots carry both; no
--     nested block carries either) and only so root order can reproduce
--     Blockly's @getTopBlocks(true)@ sort, @y + sin(3°)·x@. Document order is
--     not canvas order.
--
-- __@disabled=\"true\"@ (ruling P5-3).__ The block is skipped and its
-- @\<next\>@ chain is spliced into its place, which is exactly what Blockly's
-- @Generator.blockToCode@ does (@if (!block.isEnabled()) return
-- this.blockToCode(block.getNextBlock())@, mirrored in the Blawx generator's
-- own @getCodeForSingleBlock@, @scasp_generator.js:84-92@). One warning names
-- each skipped block. The corpus has exactly two, both top-level in @r34@'s
-- deliberately-broken @MaterialInterference@ workspace.
module L4.Blawx.Blocks
  ( BlockTree (..)
  , BlockWarning (..)
  , renderBlockWarning
  , toBlockTrees
    -- * Slot accessors
  , btField
  , btMut
  , btValue
  , btStmt
  , btSlotNames
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (isDigit, isSpace)

import L4.Blawx.Xml (XNode (..), elemText)

-- | One block, with its slots named as they actually occur. The @type@
-- attribute is kept verbatim: classification, not this layer, decides which
-- of the 47 types have an IR landing zone.
data BlockTree = MkBlockTree
  { btType     :: !Text
  , btPos      :: !(Maybe (Int, Int))    -- ^ @x@,@y@ — roots only
  , btMutation :: ![(Text, Text)]        -- ^ menu caches and @xmlns@ already dropped
  , btFields   :: ![(Text, Text)]        -- ^ @\<field name=…\>text@, document order
  , btValues   :: ![(Text, BlockTree)]   -- ^ @\<value name=…\>@
  , btStmts    :: ![(Text, [BlockTree])] -- ^ @\<statement name=…\>@, @\<next\>@ flattened
  , btComment  :: !(Maybe Text)          -- ^ @\<comment\>@ text, newlines intact (P5-4)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Information a caller may want but that is not an error. Currently just
-- P5-3.
data BlockWarning = MkBlockSkipped
  { bskType :: !Text
  , bskPos  :: !(Maybe (Int, Int))
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

renderBlockWarning :: BlockWarning -> Text
renderBlockWarning w =
  "skipped disabled <" <> w.bskType <> ">" <> maybe "" pos w.bskPos
 where
  pos (x, y) = " at (" <> Text.textShow x <> "," <> Text.textShow y <> ")"

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

btField :: Text -> BlockTree -> Maybe Text
btField n b = lookup n b.btFields

btMut :: Text -> BlockTree -> Maybe Text
btMut n b = lookup n b.btMutation

btValue :: Text -> BlockTree -> Maybe BlockTree
btValue n b = lookup n b.btValues

btStmt :: Text -> BlockTree -> [BlockTree]
btStmt n b = fromMaybe [] (lookup n b.btStmts)

-- | Every slot name a block actually carries, for a diagnostic that has to
-- say what it found instead of what it wanted.
btSlotNames :: BlockTree -> [Text]
btSlotNames b = map fst b.btFields <> map fst b.btValues <> map fst b.btStmts

-- ---------------------------------------------------------------------------
-- XML to block trees
-- ---------------------------------------------------------------------------

-- | The canvas roots of one @xml_content@ row, in document order, plus the
-- P5-3 warnings. Root ORDER here is document order; the caller re-sorts by
-- 'btPos' if it needs the generator's order.
toBlockTrees :: XNode -> Either Text ([BlockTree], [BlockWarning])
toBlockTrees = \case
  XElem "xml" _ kids -> blockSeq kids
  XElem n _ _ -> Left ("expected an <xml> root element, found <" <> n <> ">")
  XText _ -> Left "expected an <xml> root element, found character data"

-- | A run of sibling blocks: the children of an @\<xml\>@, of a
-- @\<statement\>@ or of a @\<next\>@.
blockSeq :: [XNode] -> Either Text ([BlockTree], [BlockWarning])
blockSeq nodes = mconcat <$> traverse one nodes
 where
  one (XText t)
    | Text.all isSpace t = pure ([], [])
    | otherwise = Left "unexpected character data where a <block> was expected"
  one (XElem "block" attrs kids) = blockNode attrs kids
  one (XElem n _ _) = Left ("unexpected <" <> n <> "> where a <block> was expected")

blockNode :: [(Text, Text)] -> [XNode] -> Either Text ([BlockTree], [BlockWarning])
blockNode attrs kids = do
  ty <- maybe (Left "a <block> with no type attribute") Right (lookup "type" attrs)
  pos <- position ty
  (nexts, nextWarns) <- blockSeq (concat [ks | XElem "next" _ ks <- kids])
  slots <- foldM (slot ty) emptySlots [k | k@XElem{} <- kids, notNext k]
  let tree =
        MkBlockTree
          { btType = ty
          , btPos = pos
          , btMutation = reverse slots.slMut
          , btFields = reverse slots.slFields
          , btValues = reverse slots.slValues
          , btStmts = reverse slots.slStmts
          , btComment = slots.slComment
          }
  if lookup "disabled" attrs == Just "true"
    then pure (nexts, MkBlockSkipped ty pos : reverse slots.slWarns <> nextWarns)
    else pure (tree : nexts, reverse slots.slWarns <> nextWarns)
 where
  notNext (XElem "next" _ _) = False
  notNext _ = True
  position ty = case (lookup "x" attrs, lookup "y" attrs) of
    (Nothing, Nothing) -> pure Nothing
    (Just x, Just y) -> do
      x' <- int ty "x" x
      y' <- int ty "y" y
      pure (Just (x', y'))
    _ -> Left ("<block type=\"" <> ty <> "\"> carries only one of x/y")
  int ty n t = case Text.uncons t of
    Just ('-', ds) | ok ds -> Right (negate (digits ds))
    _ | ok t -> Right (digits t)
    _ -> Left ("<block type=\"" <> ty <> "\"> has a non-integer " <> n <> "=\"" <> t <> "\"")
  ok t = not (Text.null t) && Text.all isDigit t
  digits = Text.foldl' (\ !a c -> a * 10 + (fromEnum c - fromEnum '0')) 0

data Slots = MkSlots
  { slMut     :: ![(Text, Text)]
  , slFields  :: ![(Text, Text)]
  , slValues  :: ![(Text, BlockTree)]
  , slStmts   :: ![(Text, [BlockTree])]
  , slComment :: !(Maybe Text)
  , slWarns   :: ![BlockWarning]
  }

emptySlots :: Slots
emptySlots = MkSlots [] [] [] [] Nothing []

-- | One child element of a @\<block\>@. @\<comment\>@ is found by scanning
-- rather than by index: it sits at child index 0 on @query@,
-- @unattributed_fact@ and @default_negation@ but at index 2 on
-- @attributed_rule@, after that block's two @\<field\>@s.
slot :: Text -> Slots -> XNode -> Either Text Slots
slot ty acc = \case
  XElem "mutation" mattrs _ ->
    pure acc {slMut = reverse (filter keep mattrs) <> acc.slMut}
  XElem "field" fattrs kids -> do
    n <- named "field" fattrs
    pure acc {slFields = (n, Text.concat [t | XText t <- kids]) : acc.slFields}
  XElem "value" vattrs vkids -> do
    n <- named "value" vattrs
    (bs, ws) <- blockSeq vkids
    case bs of
      [b] -> pure acc {slValues = (n, b) : acc.slValues, slWarns = reverse ws <> acc.slWarns}
      -- an empty (or wholly disabled) value input: an absent slot, which
      -- classification then reports by name
      [] -> pure acc {slWarns = reverse ws <> acc.slWarns}
      _ -> Left ("<value name=\"" <> n <> "\"> on a " <> ty <> " holds more than one block")
  XElem "statement" sattrs skids -> do
    n <- named "statement" sattrs
    (bs, ws) <- blockSeq skids
    pure acc {slStmts = (n, bs) : acc.slStmts, slWarns = reverse ws <> acc.slWarns}
  e@(XElem "comment" _ _) ->
    pure acc {slComment = Just (elemText e)}
  XElem n _ _ -> Left ("unexpected <" <> n <> "> inside a " <> ty <> " block")
  XText t
    | Text.all isSpace t -> pure acc
    | otherwise -> Left ("unexpected character data inside a " <> ty <> " block")
 where
  named what as = maybe (Left ("<" <> what <> "> with no name attribute")) Right (lookup "name" as)
  -- The menu caches, and the namespace re-declaration every serialised
  -- mutation carries.
  keep (k, _) = k `notElem` (["xmlns", "category_list", "attribute_list", "type_list"] :: [Text])
