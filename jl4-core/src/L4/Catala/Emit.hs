-- | Render a 'CatModule' to one literate @.catala_en@ document.
--
-- The output is a Markdown file whose code lives in fences: a
-- @```catala-metadata@ fence for public declarations, @```catala@ fences for
-- scope bodies, private toplevels and @#[test]@ scopes, @```catala-test-cli@
-- fences for expected outputs, and plain Markdown prose (law text, headings)
-- between them (spec §7, R8).
--
-- Output is built as plain 'Text' (not a 'Doc') so indentation is exact and
-- golden-stable, following the OpenFisca emitter.
--
-- The first line is @> Module \<name\>@, which Catala requires to equal the
-- capitalised basename of the file it is written to — the CLI is responsible
-- for keeping 'CatModule.modName' and the @-o@ path in agreement.
module L4.Catala.Emit
  ( renderModule
  , renderCatType
  , renderCatExpr
  ) where

import Base
import Data.Ratio (denominator, numerator)
import qualified Data.Text as Text

import L4.Catala.IR

-- ---------------------------------------------------------------------------
-- Top level
-- ---------------------------------------------------------------------------

-- | The @> Module X@ header, then the literate weave the lowering laid out.
--
-- Everything else — the document title, the provenance note, the disclosure of
-- shape divergences, and the law text — arrives as 'SegProse', because R8 makes
-- the weave's structure a /lowering/ decision (which L4 @§@ section a rule sits
-- under, which inert scaffolding annotates it) rather than a rendering one.
renderModule :: CatModule -> Text
renderModule m =
  Text.unlines $
    ("> Module " <> m.modName) : concatMap segmentLines m.modSegments

segmentLines :: CatSegment -> [Text]
segmentLines = \case
  SegProse ls      -> "" : map proseLine ls
  SegMetadata ds   -> fence "catala-metadata" (intersperseBlank (map declLines ds))
  SegCode items    -> fence "catala"          (intersperseBlank (map itemLines items))
  SegTestCli t     -> fence "catala-test-cli" (("$ " <> t.tcCommand) : t.tcOutput)
 where
  fence _ []   = []
  fence tag ls = ["", "```" <> tag] <> ls <> ["```"]

-- | Make one line of prose safe to sit in a @.catala_en@ file.
--
-- Two sequences are load-bearing to Catala's own reader rather than to
-- Markdown's: a line beginning with @>@ is a /directive/ (@> Module@,
-- @> Using@, @> Include@) and a triple backtick opens or closes a code fence.
-- Law text carried over from an L4 source is arbitrary — a quoted statute may
-- well start with a chevron — so both are defused here rather than trusted.
-- Checked against catala 1.2.1: an unescaped @>@ line fails the parse with
-- "Unclosed block or missing newline at the end of file".
proseLine :: Text -> Text
proseLine l
  | ">" `Text.isPrefixOf` Text.stripStart l = "\\" <> l'
  | otherwise                               = l'
 where
  l' = Text.replace "```" "'''" l

-- | Join blocks with a single blank line between them, dropping empty blocks.
intersperseBlank :: [[Text]] -> [Text]
intersperseBlank blocks = case filter (not . null) blocks of
  []       -> []
  (b : bs) -> b <> concatMap ([""] <>) bs

itemLines :: CatItem -> [Text]
itemLines = \case
  ItemDecl d  -> declLines d
  ItemScope s -> scopeBodyLines s

-- ---------------------------------------------------------------------------
-- Declarations
-- ---------------------------------------------------------------------------

declLines :: CatDecl -> [Text]
declLines = \case
  DStruct s -> structLines s
  DEnum e   -> enumLines e
  DScope s  -> scopeDeclLines s
  DTopdef t -> topdefLines t

-- | @#[description = "…"]@ on its own line, when a @\@desc@ was present (R8).
descAttr :: Maybe Text -> [Text]
descAttr = maybe [] (\d -> [ "#[description = " <> catStr d <> "]" ])

structLines :: CatStruct -> [Text]
structLines s =
     descAttr s.stDesc
  <> [ "declaration structure " <> s.stName <> ":" ]
  <> [ ind 1 <> "data " <> f.fdName <> " content " <> renderCatType f.fdType
     | f <- s.stFields
     ]

enumLines :: CatEnum -> [Text]
enumLines e =
     descAttr e.enDesc
  <> [ "declaration enumeration " <> e.enName <> ":" ]
  <> [ ind 1 <> "-- " <> c.caName <> maybe "" ((" content " <>) . renderCatType) c.caContent
     | c <- e.enCases
     ]

scopeDeclLines :: CatScopeDecl -> [Text]
scopeDeclLines s =
     descAttr s.sdDesc
  <> [ (if s.sdIsTest then "#[test] " else "") <> "declaration scope " <> s.sdName <> ":" ]
  <> concatMap varLines s.sdVars
 where
  varLines v =
       map (ind 1 <>) (descAttr v.svDesc)
    <> [ ind 1 <> varKind v.svKind <> " " <> v.svName <> varShape v.svShape ]

varKind :: CatVarKind -> Text
varKind = \case
  VarInput         -> "input"
  VarOutput        -> "output"
  VarInputOutput   -> "input output"
  VarInternal      -> "internal"
  VarContext       -> "context"
  VarContextOutput -> "context output"

varShape :: CatVarShape -> Text
varShape = \case
  ShContent t -> " content " <> renderCatType t
  ShCondition -> " condition"

topdefLines :: CatTopdef -> [Text]
topdefLines t =
     descAttr t.tdDesc
  <> [ "declaration " <> t.tdName <> " content " <> renderCatType t.tdReturn ]
  <> params
  <> [ ind 1 <> "equals " <> renderCatExpr t.tdBody ]
 where
  params
    | null t.tdParams = []
    | otherwise =
        [ ind 1 <> "depends on "
            <> Text.intercalate ", "
                 [ p <> " content " <> renderCatType ty | (p, ty) <- t.tdParams ]
        ]

-- ---------------------------------------------------------------------------
-- Scope bodies
-- ---------------------------------------------------------------------------

scopeBodyLines :: CatScopeBody -> [Text]
scopeBodyLines b =
  ("scope " <> b.sbName <> ":") : intersperseBlank (map ruleLines b.sbRules)

-- | Emit the chosen rendering of a rule. When the emitter falls back from Mode
-- B to Mode A the reason is written as a Catala comment, so the fallback is
-- visible in the artifact and never silent (R4, §8.4).
ruleLines :: CatRuleDef -> [Text]
ruleLines rd =
     [ ind 1 <> "# Mode A fallback: " <> reason
     | ModeA <- [rd.rdEmitted], Just reason <- [rd.rdFallback]
     ]
  <> intersperseBlank [ clauseLines rd.rdVar c | c <- emittedClauses rd ]

clauseLines :: Text -> CatClause -> [Text]
clauseLines var cl =
     [ ind 1 <> kindPrefix cl.clKind <> keyword <> " " <> var ]
  <> conditionLines
  <> conseqLines
 where
  keyword = case cl.clConseq of
    ConsEquals _ -> "definition"
    _            -> "rule"

  conditionLines = case cl.clCondition of
    Nothing -> []
    Just c  -> [ ind 2 <> "under condition", ind 3 <> renderCatExpr c ]

  -- Catala's @consequence@ keyword belongs to the /condition/ clause
  -- (@condition_consequence := UNDER_CONDITION expr CONSEQUENCE@,
  -- @compiler\/surface\/parser.mly:597@), so an unconditional rule or definition
  -- must not write it: it is @rule v fulfilled@, not
  -- @rule v consequence fulfilled@.
  conseqLines = case (cl.clConseq, isJust cl.clCondition) of
    (ConsFulfilled,    True)  -> [ ind 2 <> "consequence fulfilled" ]
    (ConsFulfilled,    False) -> [ ind 2 <> "fulfilled" ]
    (ConsNotFulfilled, True)  -> [ ind 2 <> "consequence not fulfilled" ]
    (ConsNotFulfilled, False) -> [ ind 2 <> "not fulfilled" ]
    (ConsEquals e,     True)  -> [ ind 2 <> "consequence equals", ind 3 <> renderCatExpr e ]
    (ConsEquals e,     False) -> [ ind 2 <> "equals", ind 3 <> renderCatExpr e ]

kindPrefix :: CatClauseKind -> Text
kindPrefix = \case
  ClPlain              -> ""
  ClLabel l            -> "label " <> l <> " "
  ClException Nothing  -> "exception "
  ClException (Just l) -> "exception " <> l <> " "
  ClLabelExc l m       -> "label " <> l <> " exception " <> m <> " "

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

renderCatType :: CatType -> Text
renderCatType = \case
  TBool     -> "boolean"
  TInteger  -> "integer"
  TDecimal  -> "decimal"
  TMoney    -> "money"
  TDate     -> "date"
  TDuration -> "duration"
  TNamed n  -> n
  TList t   -> "list of " <> renderCatType t
  TOption t -> "optional of " <> renderCatType t

-- ---------------------------------------------------------------------------
-- Expressions
-- ---------------------------------------------------------------------------

-- | Render an expression on a single line.
--
-- Compound nodes are fully parenthesised: Catala's precedence table is not
-- L4's, and an unparenthesised @a >= b or c@ would be at the mercy of it.
-- Parentheses are always legal, so the emitter buys safety at the cost of some
-- noise — the same trade the OpenFisca emitter makes for numpy's operators.
renderCatExpr :: CatExpr -> Text
renderCatExpr = go
 where
  go = \case
    ELit l          -> renderLit l
    EVar v          -> v
    EStruct n fs    -> n <> " { " <> Text.concat [ "-- " <> f <> ": " <> go e <> " " | (f, e) <- fs ] <> "}"
    EReplace e fs   -> paren (go e <> " but replace { " <> Text.concat [ "-- " <> f <> ": " <> go v <> " " | (f, v) <- fs ] <> "}")
    EProj e f       -> atom e <> "." <> f
    ECon c Nothing  -> c
    ECon c (Just e) -> paren (c <> " content " <> go e)
    EMatch e arms   ->
      paren ("match " <> go e <> " with pattern "
              <> Text.intercalate " " [ renderPat a.armPat <> " : " <> go a.armBody | a <- arms ])
    EIf c t e       -> paren ("if " <> go c <> " then " <> go t <> " else " <> go e)
    ELet x e b      -> paren ("let " <> x <> " equals " <> go e <> " in " <> go b)
    EBin op a b     -> paren (go a <> " " <> binOp op <> " " <> go b)
    EUn UNot a      -> paren ("not " <> go a)
    EUn UNeg a      -> paren ("- " <> go a)
    ECall f []      -> f
    ECall f as      -> paren (f <> " of " <> Text.intercalate ", " (map go as))
    EScopeOut s fs v ->
      paren ("output of " <> s
              <> (if null fs then ""
                    else " with { " <> Text.concat [ "-- " <> f <> ": " <> go e <> " " | (f, e) <- fs ] <> "}"))
        <> "." <> v
    EList es        -> "[ " <> Text.intercalate "; " (map go es) <> " ]"
    EMapEach x l e  -> paren ("map each " <> x <> " among " <> go l <> " to " <> go e)
    EFilter x l e   -> paren ("list of " <> x <> " among " <> go l <> " such that " <> go e)
    EFold x acc l i e ->
      paren ("combine all " <> x <> " among " <> go l
              <> " in " <> acc <> " initially " <> go i <> " with " <> go e)
    EExists x l e   -> paren ("exists " <> x <> " among " <> go l <> " such that " <> go e)
    EForAll x l e   -> paren ("for all " <> x <> " among " <> go l <> " we have " <> go e)
    EContains l e   -> paren (go l <> " contains " <> go e)
    EAppend a b     -> paren (go a <> " ++ " <> go b)
    ENumberOf l     -> paren ("number of " <> go l)
    EExtremum big l d ->
      paren ((if big then "maximum" else "minimum") <> " of " <> go l
              <> " or if list empty then " <> go d)
    ECoerce t e     -> paren (renderCatType t <> " of " <> go e)
    EStdCall f as   -> paren (f <> " of " <> Text.intercalate ", " (map go as))
    EImpossible msg ->
      maybe "" (\t -> "#[error.message = " <> catStr t <> "] ") msg <> "impossible"

  -- Projection binds tighter than anything we render, but its target still has
  -- to be an atom; wrap when it is not already parenthesised.
  atom e = case e of
    EVar v      -> v
    EProj p f   -> atom p <> "." <> f
    ECall f []  -> f
    other       -> let t = go other
                   in if "(" `Text.isPrefixOf` t then t else paren t

  renderPat = \case
    PCon c Nothing  -> "-- " <> c
    PCon c (Just x) -> "-- " <> c <> " content " <> x
    PAnything       -> "-- anything"

  binOp = \case
    BAdd -> "+"; BSub -> "-"; BMul -> "*"; BDiv -> "/"
    BAnd -> "and"; BOr -> "or"; BXor -> "xor"
    BEq -> "="; BNeq -> "!="; BLt -> "<"; BLeq -> "<="; BGt -> ">"; BGeq -> ">="

renderLit :: CatLit -> Text
renderLit = \case
  LBool b        -> if b then "true" else "false"
  LInt n         -> tshow n
  LDec r         -> renderDecimal r
  LMoney r       -> "$" <> renderDecimal r
  LDate y m d    -> "|" <> pad 4 y <> "-" <> pad 2 (toInteger m) <> "-" <> pad 2 (toInteger d) <> "|"
  LDuration []   -> "0 day"
  LDuration ps   -> Text.intercalate " + " [ tshow n <> " " <> durUnit u | (n, u) <- ps ]
 where
  pad :: Int -> Integer -> Text
  pad n v = Text.justifyRight n '0' (tshow v)
  durUnit = \case DUDay -> "day"; DUMonth -> "month"; DUYear -> "year"

-- | Render a rational as a Catala @decimal@ literal.
--
-- Catala decimals are exact rationals, so nothing is lost either way: a value
-- that terminates in base 10 prints as a decimal literal (always with a point,
-- so @1000@ prints @1000.0@ and is not lexed as an @integer@); anything else
-- prints as an exact division, whose result type in Catala is already decimal.
renderDecimal :: Rational -> Text
renderDecimal r
  | d == 1    = sign <> tshow (abs n) <> ".0"
  | otherwise = case terminating (abs n) d of
      Just t  -> sign <> t
      Nothing ->
        let q = "(" <> tshow (abs n) <> ".0 / " <> tshow d <> ".0)"
        in if n < 0 then "(- " <> q <> ")" else q
 where
  n    = numerator r
  d    = denominator r
  sign = if n < 0 then "-" else ""

-- | If @num\/den@ (den > 0, num >= 0) terminates in base 10, render it with at
-- least one fractional digit.
terminating :: Integer -> Integer -> Maybe Text
terminating num den =
  let places = max 1 (countFactors 2 den `max` countFactors 5 den)
  in if stripFactors 5 (stripFactors 2 den) == 1
       then Just (format places (num * (10 ^ places) `div` den))
       else Nothing
 where
  countFactors p x = go (0 :: Integer) x
    where go acc y | y `mod` p == 0 && y /= 0 = go (acc + 1) (y `div` p)
                   | otherwise               = acc
  stripFactors p x | x `mod` p == 0 && x /= 0 = stripFactors p (x `div` p)
                   | otherwise                = x
  format places scaled =
    let s             = Text.justifyRight (fromIntegral places + 1) '0' (tshow scaled)
        (whole, frac) = Text.splitAt (Text.length s - fromIntegral places) s
    in whole <> "." <> frac

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- | A Catala string literal (used only inside attributes: Catala has no string
-- /type/, R11).
catStr :: Text -> Text
catStr t = "\"" <> Text.concatMap esc t <> "\""
 where
  esc '"'  = "\\\""
  esc '\\' = "\\\\"
  esc '\n' = " "
  esc c    = Text.singleton c

paren :: Text -> Text
paren t = "(" <> t <> ")"

tshow :: Show a => a -> Text
tshow = Text.pack . show

ind :: Int -> Text
ind n = Text.replicate (n * 2) " "
