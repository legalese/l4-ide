-- | The single-line @NOT … AND …@ refusal (SET-OPERATORS-SPEC §18.1, ruling
-- R-NOT-1).
--
-- @NOT@ has no precedence. Its operand is delimited by LAYOUT: 'L4.Parser.negation'
-- records the column the @NOT@ sits in and then keeps absorbing operators for as
-- long as they start strictly to the right of it. On one line everything after
-- the @NOT@ is to its right, so
--
-- @
--   NOT a AND b        -- reads as NOT (a AND b)
--   NOT (a) AND b      -- ALSO reads as NOT (a AND b): the operand's bracket
--                      -- closes, and the NOT carries on absorbing
-- @
--
-- Both parse, both type-check, and both return the wrong BOOLEAN for anyone
-- who read them as @(NOT a) AND b@ — which is how most people read them. Ten
-- sites in this repository did, one of them declaring a dead, unwilling
-- representative willing to act (§18.2). The ruling keeps the layout rule and
-- refuses the one spelling that is silently wrong: a @NOT@ whose operand
-- contains a connective — @AND@, @OR@ or @IMPLIES@ — on the @NOT@'s own line,
-- outside any bracket of its own.
--
-- What is NOT refused, and why:
--
-- * @(NOT a) AND b@ — the bracket closes around the @NOT@, so its operand is
--   just @a@ and there is no connective in it.
-- * @NOT (a AND b)@ — the connective sits inside the operand's own brackets;
--   the wide reading was spelled out, so it is what was meant.
-- * @NOT a@ ⏎ @AND b@ at the same column, and @NOT a@ ⏎ @····AND b@ deeper —
--   the multi-line forms, where the columns are doing visible work. The
--   corpus writes the second on purpose (@`perm3 — negation over a group`@).
-- * @NOT n EQUALS 0@ — comparisons are outside the ruling. The tight reading
--   of a comparison is either ill-typed or a no-op, so there is only one
--   parse anyone means; see the header of @etc/check-not-precedence.mjs@.
-- * @NOT "(3)" ... x@ — the statutory-label idiom, where an inert string is
--   joined to its node by the implicit-AND token (house style, see
--   @doc/concepts/reviewing/reviewing-encoded-law.md@). The parser builds an
--   @And@ whose left operand is the label, but a label is a citation
--   fragment and not a claim, so @(NOT "(3)") ... x@ is nothing anyone
--   means: there is only one reading, and it is the one that evaluates.
--   Seven such sites in @legal/regcf/denovo/regcf-denovo.l4@, measured
--   2026-09-07, are why this is spelled out.
--
-- This is a structural check over the parsed module, reported through the
-- checker as an ordinary error (severity 'L4.TypeCheck.Types.SError'), in the
-- same way as 'L4.Desugar.detectMisattachedSectionGivens'. It runs BEFORE
-- desugaring and name resolution, on the tree the parser built, because the
-- question is about where the tokens sit and nothing else.
module L4.Lint.NotReach
  ( NotReachSite (..)
  , detectSameLineNotReach
  , sameLineNotReach
  ) where

import Base
import Control.Applicative ((<|>))
import qualified Optics

import L4.Annotation
import L4.Lexer (PosToken (..), TKeywords (..), TSymbols (..), TokenType (..))
import L4.Parser.SrcSpan
import L4.Syntax

-- | One refused @NOT@.
data NotReachSite = MkNotReachSite
  { range      :: SrcRange
    -- ^ From the @NOT@ keyword to the end of the connective it reaches over:
    -- exactly the stretch of text that the reader and the parser group
    -- differently.
  , connective :: Text
    -- ^ The connective as the reader would name it: @AND@, @OR@ or @IMPLIES@.
  , operand    :: Expr Name
    -- ^ Everything the @NOT@ took — the wide reading, @NOT (operand)@.
  , unit       :: Expr Name
    -- ^ The leftmost thing after the @NOT@, before any connective — what a
    -- reader takes the @NOT@ to apply to.
  , narrowed   :: Expr Name
    -- ^ The operand with @(NOT unit)@ in place of @unit@ — the narrow reading,
    -- spelled so that it parses as such.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Every refused @NOT@ in the module, sub-expressions included.
detectSameLineNotReach :: Module Name -> [NotReachSite]
detectSameLineNotReach m = mapMaybe sameLineNotReach (allExprs m)
 where
  allExprs =
    concatMap (Optics.toListOf (Optics.cosmosOf (Optics.gplate @(Expr Name))))
      . Optics.toListOf (Optics.gplate @(Expr Name))

-- | Is this @NOT@ refused? 'Nothing' for any expression that is not a written
-- @NOT@ — a @NOT@ the parser synthesised for @UNLESS@ carries no keyword
-- token, and a reader never saw a keyword there, so it is not this trap.
sameLineNotReach :: Expr Name -> Maybe NotReachSite
sameLineNotReach (Not ann e) = do
  notRange <- notKeyword ann
  (connective, connRange) <- firstSameLineConnective notRange.start.line e
  pure MkNotReachSite
    { range = notRange { end = connRange.end, length = spanLength notRange connRange }
    , connective
    , operand = e
    , unit = leftmostUnit e
    , narrowed = narrow e
    }
sameLineNotReach _ = Nothing

-- | The first connective, in source order, that the @NOT@ on the given line
-- reaches over: a bare @And@\/@Or@\/@Implies@ node whose keyword sits on that
-- line. A bracketed node ends the search below it: its brackets are its own,
-- and a connective inside them was grouped by the writer.
firstSameLineConnective :: Int -> Expr Name -> Maybe (Text, SrcRange)
firstSameLineConnective line = go
 where
  go = \ case
    And ann l r     -> binary "AND" ann l r
    Or ann l r      -> binary "OR" ann l r
    Implies ann l r -> binary "IMPLIES" ann l r
    _               -> Nothing
  binary kw ann l r
    | bracketed ann = Nothing
    | isLabel l = go r
    | Just kwRange <- connectiveKeyword ann
    , kwRange.start.line == line = Just (kw, kwRange)
    | otherwise = go l <|> go r

-- | Down the left spine, through every bare connective, to the thing a
-- reader takes the @NOT@ to be about.
leftmostUnit :: Expr Name -> Expr Name
leftmostUnit = \ case
  And ann l r     | not (bracketed ann) -> leftmostUnit (if isLabel l then r else l)
  Or ann l _      | not (bracketed ann) -> leftmostUnit l
  Implies ann l _ | not (bracketed ann) -> leftmostUnit l
  e -> e

-- | The same tree with the leftmost unit negated in place. Printed through
-- 'L4.Print.prettyLayout' this comes out as @(NOT unit) AND …@, because the
-- printer brackets a negated conjunct.
narrow :: Expr Name -> Expr Name
narrow = \ case
  And ann l r     | not (bracketed ann) ->
      if isLabel l then And ann l (narrow r) else And ann (narrow l) r
  Or ann l r      | not (bracketed ann) -> Or ann (narrow l) r
  Implies ann l r | not (bracketed ann) -> Implies ann (narrow l) r
  e -> Not emptyAnno e

-- | An inert string in operand position: the statutory-label idiom,
-- @"(3)" ... x@. Not a claim, so never the thing a @NOT@ is about.
isLabel :: Expr Name -> Bool
isLabel (Lit _ (StringLit _ _)) = True
isLabel _ = False

-- ----------------------------------------------------------------------------
-- Reading token positions off an annotation
--
-- A node's 'Anno' lists, in source order, holes for its children and clusters
-- for its own tokens. A binary node is @[hole l, cluster op, hole r]@; a
-- bracketed node has the brackets INLINED around that ('L4.Parser.paren' via
-- 'inlineAnnoHole'), so it is @[cluster "(", hole l, cluster op, hole r,
-- cluster ")"]@. There is no @Paren@ constructor. Only clusters the user
-- actually wrote ('Visible') count: a hidden cluster was inserted by a tool.
-- ----------------------------------------------------------------------------

-- | The written @NOT@ keyword of a 'Not' node, if there is one.
notKeyword :: Anno -> Maybe SrcRange
notKeyword ann =
  listToMaybe
    [ tok.range
    | tok <- writtenTokens ann
    , tok.payload == TKeywords TKNot
    ]

-- | Does the node open with a bracket of its own, before its first child?
bracketed :: Anno -> Bool
bracketed ann =
  any opensBracket (takeWhile (not . isHole) ann.payload)
 where
  opensBracket (AnnoCsn _ c) = any ((== TSymbols TPOpen) . (.payload)) (writtenClusterTokens c)
  opensBracket AnnoHole{}    = False

-- | The keyword of a binary node: the first token the user wrote after the
-- first child.
connectiveKeyword :: Anno -> Maybe SrcRange
connectiveKeyword ann =
  case dropWhile (not . isHole) ann.payload of
    _ : rest ->
      listToMaybe
        [ tok.range
        | AnnoCsn _ c <- rest
        , tok <- writtenClusterTokens c
        ]
    [] -> Nothing

isHole :: AnnoElement_ t -> Bool
isHole AnnoHole{} = True
isHole AnnoCsn{}  = False

writtenTokens :: Anno -> [PosToken]
writtenTokens ann = concat [ writtenClusterTokens c | AnnoCsn _ c <- ann.payload ]

writtenClusterTokens :: CsnCluster_ PosToken -> [PosToken]
writtenClusterTokens c
  | c.payload.visibility == Visible = c.payload.tokens
  | otherwise = []

-- | The length of the text from the start of one range to the end of another,
-- on the convention the lexer keeps ('L4.Lexer.mkPosTokens'): the end
-- position is the one AFTER the last character, and @length = end - start@.
-- Only meaningful on one line, which is the only case this module builds.
spanLength :: SrcRange -> SrcRange -> Int
spanLength openR closeR
  | openR.start.line == closeR.end.line = closeR.end.column - openR.start.column
  | otherwise = openR.length + closeR.length
