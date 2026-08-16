-- | Target intermediate representation for the Catala backend.
--
-- This is a Catala /surface/ IR: it models the concrete @.catala_en@ literate
-- file we emit, not Catala's dcalc kernel. We emit source text and
-- @catala typecheck@ is the downstream gate (spec §7).
--
-- Shape, per @specs\/todo\/CATALA-EXPORT-SPEC.md@:
--
--   * a module has a name (which must equal the capitalised basename of the
--     emitted file) and a list of /segments/ — law-text prose interleaved with
--     @catala-metadata@, @catala@ and @catala-test-cli@ fences;
--   * public declarations (structures, enumerations, scope declarations) live
--     in the metadata fence; private toplevel declarations and scope bodies
--     live in plain @catala@ fences (R1, §8.1);
--   * every rule definition carries /both/ renderings — the Mode B exception
--     ladder that is the primary emission and the Mode A boolean reference it
--     is checked against (R4, §8.4). Which one is emitted is recorded per rule,
--     together with the reason when Mode B was not available.
--
-- 'L4.Catala.Lower' produces this from a typechecked @Module Resolved@;
-- 'L4.Catala.Emit' renders it to one literate @.catala_en@ 'Text'.
module L4.Catala.IR
  ( -- * Modules and segments
    CatModule (..)
  , CatSegment (..)
  , CatItem (..)
    -- * Declarations
  , CatDecl (..)
  , CatStruct (..)
  , CatField (..)
  , CatEnum (..)
  , CatCase (..)
  , CatScopeDecl (..)
  , CatScopeVar (..)
  , CatVarKind (..)
  , CatVarShape (..)
  , CatTopdef (..)
    -- * Scope bodies, rules, and the two renderings
  , CatScopeBody (..)
  , CatRuleDef (..)
  , CatMode (..)
  , CatClause (..)
  , CatClauseKind (..)
  , CatConseq (..)
  , emittedClauses
    -- * Ladder construction (shared by the lowering and the equivalence harness)
  , provisoLadder
  , armLadder
    -- * The equivalence descriptor (R4's standing gate)
  , CatEqv (..)
  , CatEqvKind (..)
  , eqvAtomCount
  , eqvRowLimit
    -- * Tests
  , CatTest (..)
  , CatTestCli (..)
    -- * Types and expressions
  , CatType (..)
  , CatExpr (..)
  , CatLit (..)
  , CatDurUnit (..)
  , CatBinOp (..)
  , CatUnOp (..)
  , CatArm (..)
  , CatPat (..)
    -- * Name mangling (injective-by-check, keyword-safe)
  , catIdent
  , catUpper
  , catReserved
  , nameCollisions
  ) where

import Base
import Data.Char (isAlphaNum, isAscii, isDigit, isUpper, toLower, toUpper)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

import L4.Parser.SrcSpan (SrcRange)

-- ---------------------------------------------------------------------------
-- Modules
-- ---------------------------------------------------------------------------

-- | One emitted literate @.catala_en@ file.
data CatModule = CatModule
  { modName     :: !Text        -- ^ @> Module \<name\>@; must equal the capitalised file basename
  , modSource   :: !Text        -- ^ provenance: the L4 source file's basename
  , modWarnings :: ![Text]      -- ^ non-fatal notes (R11 elisions, Mode B fallbacks) — emitted as prose
  , modSegments :: ![CatSegment]
  }
  deriving stock (Eq, Show, Generic)

-- | A segment of the literate weave, in emission order.
data CatSegment
  = SegProse    ![Text]      -- ^ law text \/ Markdown headings, verbatim lines
  | SegMetadata ![CatDecl]   -- ^ a @```catala-metadata@ fence (public declarations)
  | SegCode     ![CatItem]   -- ^ a @```catala@ fence (bodies, private toplevels, test scopes)
  | SegTestCli  !CatTestCli  -- ^ a @```catala-test-cli@ fence (expected output, R7)
  deriving stock (Eq, Show, Generic)

-- | An item inside a @```catala@ fence.
data CatItem
  = ItemDecl  !CatDecl
  | ItemScope !CatScopeBody
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Declarations
-- ---------------------------------------------------------------------------

data CatDecl
  = DStruct !CatStruct
  | DEnum   !CatEnum
  | DScope  !CatScopeDecl
  | DTopdef !CatTopdef
  deriving stock (Eq, Show, Generic)

-- | @declaration structure X: data f content T@
data CatStruct = CatStruct
  { stName   :: !Text          -- ^ mangled, Capitalised
  , stL4     :: !Text          -- ^ original L4 name, for collision reporting
  , stDesc   :: !(Maybe Text)  -- ^ @\@desc@ → @#[description = "…"]@
  , stFields :: ![CatField]
  }
  deriving stock (Eq, Show, Generic)

data CatField = CatField
  { fdName :: !Text
  , fdL4   :: !Text
  , fdType :: !CatType
  , fdDesc :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | @declaration enumeration X: -- C content T@
data CatEnum = CatEnum
  { enName  :: !Text
  , enL4    :: !Text
  , enDesc  :: !(Maybe Text)
  , enCases :: ![CatCase]
  }
  deriving stock (Eq, Show, Generic)

data CatCase = CatCase
  { caName    :: !Text
  , caL4      :: !Text
  , caContent :: !(Maybe CatType)   -- ^ payload type, if the constructor carries one
  }
  deriving stock (Eq, Show, Generic)

-- | @declaration scope S: input x content T … output y content U@
data CatScopeDecl = CatScopeDecl
  { sdName   :: !Text
  , sdL4     :: !Text
  , sdDesc   :: !(Maybe Text)
  , sdIsTest :: !Bool            -- ^ carries the @#[test]@ attribute (R7)
  , sdVars   :: ![CatScopeVar]
  }
  deriving stock (Eq, Show, Generic)

data CatScopeVar = CatScopeVar
  { svName  :: !Text
  , svL4    :: !Text
  , svKind  :: !CatVarKind
  , svShape :: !CatVarShape
  , svDesc  :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | Catala's variable qualifiers. @VarContext@ is where a @TYPICALLY@-annotated
-- parameter lands (R10, §8.10).
data CatVarKind
  = VarInput
  | VarOutput
  | VarInputOutput
  | VarInternal
  | VarContext
  | VarContextOutput
  deriving stock (Eq, Show, Generic)

-- | @content T@ or the boolean-shaped @condition@.
data CatVarShape = ShContent !CatType | ShCondition
  deriving stock (Eq, Show, Generic)

-- | A private helper: @declaration f content T depends on x content U equals e@.
data CatTopdef = CatTopdef
  { tdName   :: !Text
  , tdL4     :: !Text
  , tdDesc   :: !(Maybe Text)
  , tdParams :: ![(Text, CatType)]
  , tdReturn :: !CatType
  , tdBody   :: !CatExpr
  }
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Scope bodies: Mode A and Mode B side by side (R4)
-- ---------------------------------------------------------------------------

-- | @scope S: …@ — the definitions and rules of one scope.
data CatScopeBody = CatScopeBody
  { sbName  :: !Text
  , sbRules :: ![CatRuleDef]
  }
  deriving stock (Eq, Show, Generic)

-- | One scope variable's definition, in both renderings.
--
-- @rdModeA@ is the boolean\/if-else reference rendering — always present,
-- semantics-identical to the L4 source by construction. @rdModeB@ is the
-- exception ladder, present only when the lowering could build one. @rdEmitted@
-- says which rendering the emitter writes; when it is 'ModeA' despite a Mode B
-- being expected, @rdFallback@ names the reason so the fallback is warned rather
-- than silent (§8.4).
data CatRuleDef = CatRuleDef
  { rdVar      :: !Text
  , rdModeA    :: ![CatClause]
  , rdModeB    :: !(Maybe [CatClause])
  , rdEmitted  :: !CatMode
  , rdFallback :: !(Maybe Text)
  , rdEqv      :: !(Maybe CatEqv)
    -- ^ the propositional shape of the Mode B rewrite, from which
    -- 'L4.Catala.Equivalence' builds the module's standing equivalence scopes.
    -- Present exactly when @rdEmitted = 'ModeB'@.
  }
  deriving stock (Eq, Show, Generic)

data CatMode = ModeA | ModeB
  deriving stock (Eq, Show, Generic)

-- | The clauses the emitter should actually write for a rule.
emittedClauses :: CatRuleDef -> [CatClause]
emittedClauses rd = case rd.rdEmitted of
  ModeA -> rd.rdModeA
  ModeB -> fromMaybe rd.rdModeA rd.rdModeB

-- | One @[label L | exception [L]] (rule|definition) v [under condition c] …@.
data CatClause = CatClause
  { clKind      :: !CatClauseKind
  , clCondition :: !(Maybe CatExpr)
  , clConseq    :: !CatConseq
  }
  deriving stock (Eq, Show, Generic)

-- | Catala's grammar admits a label /and/ an exception target on one clause
-- (@label = ioption(label) ; except = ioption(exception_to) ; RULE@,
-- @compiler\/surface\/parser.mly:608-614@), and an n-rung priority ladder needs
-- exactly that: every rung but the highest-priority one is both an exception to
-- the rung below it and the label the rung above it points at.
data CatClauseKind
  = ClPlain                     -- ^ no label
  | ClLabel     !Text           -- ^ @label L …@
  | ClException !(Maybe Text)   -- ^ @exception [L] …@
  | ClLabelExc  !Text !Text     -- ^ @label L exception M …@
  deriving stock (Eq, Show, Generic)

-- | @consequence fulfilled@ \/ @consequence not fulfilled@ (a @rule@), or
-- @equals e@ (a @definition@).
data CatConseq
  = ConsFulfilled
  | ConsNotFulfilled
  | ConsEquals !CatExpr
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Ladder construction
-- ---------------------------------------------------------------------------
--
-- Both builders live here rather than in the lowering because the equivalence
-- harness has to build the /same/ ladders over abstract atoms: a check that
-- reconstructed the ladder by a second, independent code path would be checking
-- the wrong thing.

-- | @base@ holds unless a proviso fires. Provisos are chained rather than made
-- siblings: two sibling exceptions to one label that fire together is Catala's
-- @Conflict@ error, and @c AND NOT d1 AND NOT d2@ has no such failure mode.
provisoLadder :: Text -> CatExpr -> [CatExpr] -> [CatClause]
provisoLadder var base provisos =
  CatClause (ClLabel (lbl 0)) (Just base) ConsFulfilled : rungs
 where
  n     = length provisos
  lbl :: Int -> Text
  lbl i = var <> "_p" <> Text.pack (show i)
  rungs =
    [ CatClause kind (Just p) ConsNotFulfilled
    | (i, p) <- zip [1 :: Int ..] provisos
    , let kind | i == n    = ClException (Just (lbl (i - 1)))
               | otherwise = ClLabelExc (lbl i) (lbl (i - 1))
    ]

-- | An n-arm first-match cascade as a priority ladder.
--
-- L4 takes the /first/ matching arm, so arm 1 must outrank arm 2, which must
-- outrank arm 3, …, and every arm must outrank the unconditional base. In
-- Catala @exception L@ means "this rule wins over the rule labelled @L@", so
-- the chain runs upwards from the base: the last arm is an exception to the
-- base, and arm @i@ is an exception to arm @i+1@.
--
-- The obvious reading of the previous sentence is the wrong way round, and the
-- first version of this function got it wrong: it made arm @i@ an exception to
-- arm @i-1@, which reverses the cascade. On non-overlapping guards nothing
-- shows; on a rate table where each band's guard implies the next
-- (@income > 100000@ implies @income > 50000@) it silently picks the /widest/
-- matching band. The equivalence grid this backend now ships (R4, §8.4) is what
-- caught it — @all_agree = false@ on a three-band table — which is precisely
-- the class of bug an unchecked semantic rewrite in a legal transpiler exists
-- to prevent.
armLadder :: Text -> CatVarShape -> [(CatExpr, CatExpr)] -> CatExpr -> Maybe [CatClause]
armLadder var shape arms dflt = case shape of
  ShContent _ -> Just (base (ConsEquals dflt) : [ rung i c (ConsEquals v) | (i, (c, v)) <- indexed ])
  ShCondition -> do
    d  <- boolConseq dflt
    ks <- traverse (boolConseq . snd) arms
    pure (base d : [ rung i c k | ((i, (c, _)), k) <- zip indexed ks ])
 where
  n       = length arms
  indexed = zip [1 :: Int ..] arms
  lbl :: Int -> Text
  lbl i   = var <> "_r" <> Text.pack (show i)
  base    = CatClause (ClLabel (lbl 0)) Nothing
  rung i c = CatClause (ClLabelExc (lbl i) (if i == n then lbl 0 else lbl (i + 1)))
                       (Just c)
  -- A `condition`-shaped variable can only be `fulfilled`/`not fulfilled`, so a
  -- ladder over it exists only when every arm value is a literal.
  boolConseq = \case
    ELit (LBool True)  -> Just ConsFulfilled
    ELit (LBool False) -> Just ConsNotFulfilled
    _                  -> Nothing

-- ---------------------------------------------------------------------------
-- The equivalence descriptor (R4, §8.4)
-- ---------------------------------------------------------------------------

-- | What a Mode B rewrite did, propositionally.
--
-- Mode A and Mode B are built from the /same/ atomic conditions; whether they
-- agree is therefore a question about the ladder's control flow alone, not
-- about the atoms' contents. That is what makes an exhaustive check affordable:
-- 'eqAtoms' are the atoms as they appear in the emitted rule (kept only so the
-- generated prose can name them), and the harness re-runs both renderings over
-- every one of the @2^n@ truth assignments to them.
data CatEqv = CatEqv
  { eqKind  :: !CatEqvKind
  , eqAtoms :: ![CatExpr]
  }
  deriving stock (Eq, Show, Generic)

data CatEqvKind
  = EqvProviso !Int
    -- ^ a @condition@ rewritten as base-plus-@n@-provisos; @n+1@ atoms
    -- (the base's condition first, then each proviso).
  | EqvArmsCond ![Bool] !Bool
    -- ^ an @n@-arm first-match cascade over a @condition@: each arm's literal
    -- boolean consequence, then the default's. @n@ atoms.
  | EqvArmsValue !Int
    -- ^ an @n@-arm first-match cascade over a @content@ variable. @n@ atoms;
    -- the arms' values are checked through pairwise-distinct witnesses, because
    -- the rewrite is uniform in the consequence type.
  deriving stock (Eq, Show, Generic)

-- | How many independent booleans the truth table ranges over.
eqvAtomCount :: CatEqv -> Int
eqvAtomCount = length . (.eqAtoms)

-- | The largest truth table the emitter will write out (@2^8 = 256@ rows). A
-- rewrite with more atoms than this falls back to Mode A rather than shipping
-- an unchecked ladder or a megabyte of grid.
eqvRowLimit :: Int
eqvRowLimit = 8

-- ---------------------------------------------------------------------------
-- Tests (R7)
-- ---------------------------------------------------------------------------

-- | A @#[test]@ scope: its declaration, its body, and the expected-output
-- block. The oracle is L4 (§8.7), so @ctExpected@ is populated from L4
-- evaluation, never from @clerk test --reset@.
data CatTest = CatTest
  { ctDecl     :: !CatScopeDecl
  , ctBody     :: !CatScopeBody
  , ctExpected :: !(Maybe CatTestCli)
  }
  deriving stock (Eq, Show, Generic)

-- | A @```catala-test-cli@ block: the command line and its expected output.
--
-- @tcBinding@ is the source range of the L4 directive whose value the block
-- expects. The lowering leaves @tcOutput@ empty for a bound block and the CLI
-- fills it from L4's own evaluator, so the oracle is L4 and never
-- @clerk test --reset@ (R7, §8.7). An unbound block (@tcBinding = Nothing@)
-- carries its expectation already — the equivalence grids, whose expected
-- answer is @true@ by construction.
data CatTestCli = CatTestCli
  { tcCommand :: !Text     -- ^ e.g. @catala test-scope Test1 -F json@
  , tcOutput  :: ![Text]
  , tcBinding :: !(Maybe SrcRange)
  }
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Catala's type language, restricted to the v1 fragment (§6). @NUMBER@
-- lowers to 'TDecimal'; @TMoney@ exists but is never inferred (R2, §8.2).
data CatType
  = TBool
  | TInteger
  | TDecimal
  | TMoney
  | TDate
  | TDuration
  | TNamed !Text          -- ^ a declared structure or enumeration
  | TList !CatType
  | TOption !CatType      -- ^ @optional of T@ — the landing spot for @MAYBE@
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Expressions
-- ---------------------------------------------------------------------------

-- | The §6 fragment as Catala surface expressions.
data CatExpr
  = ELit      !CatLit
  | EVar      !Text                                -- ^ a local, parameter, or scope variable
  | EStruct   !Text ![(Text, CatExpr)]             -- ^ @X { -- f: v }@
  | EReplace  !CatExpr ![(Text, CatExpr)]          -- ^ @x but replace { -- f: v }@
  | EProj     !CatExpr !Text                       -- ^ @x.f@
  | ECon      !Text !(Maybe CatExpr)               -- ^ @C@ \/ @C content e@
  | EMatch    !CatExpr ![CatArm]                   -- ^ @match e with pattern …@
  | EIf       !CatExpr !CatExpr !CatExpr
  | ELet      !Text !CatExpr !CatExpr              -- ^ @let x equals e in b@
  | EBin      !CatBinOp !CatExpr !CatExpr
  | EUn       !CatUnOp !CatExpr
  | ECall     !Text ![CatExpr]                     -- ^ toplevel call: @f of a, b@
  | EScopeOut !Text ![(Text, CatExpr)] !Text       -- ^ @(output of S with { -- x: e }).v@
  | EList     ![CatExpr]
  | EMapEach  !Text !CatExpr !CatExpr              -- ^ @map each x among l to e@
  | EFilter   !Text !CatExpr !CatExpr              -- ^ @list of x among l such that e@
  | EFold     !Text !Text !CatExpr !CatExpr !CatExpr
    -- ^ @combine all x among l in acc initially i with e@ (elem, acc, list, init, step)
  | EExists   !Text !CatExpr !CatExpr              -- ^ @exists x among l such that e@
  | EForAll   !Text !CatExpr !CatExpr              -- ^ @for all x among l we have e@
  | EContains !CatExpr !CatExpr                    -- ^ @l contains e@
  | EAppend   !CatExpr !CatExpr                    -- ^ @l1 ++ l2@
  | ENumberOf !CatExpr                             -- ^ @number of l@
  | EExtremum !Bool !CatExpr !CatExpr
    -- ^ @maximum\/minimum of l or if list empty then d@ (True = maximum)
  | ECoerce   !CatType !CatExpr                    -- ^ @decimal of e@, @integer of e@
  | EStdCall  !Text ![CatExpr]                     -- ^ a qualified stdlib call, e.g. @Decimal.sum of l@
  | EImpossible !(Maybe Text)                      -- ^ @#[error.message = "…"] impossible@ (R3)
  deriving stock (Eq, Show, Generic)

data CatLit
  = LBool  !Bool
  | LInt   !Integer
  | LDec   !Rational
  | LMoney !Rational                    -- ^ never produced by v1 lowering (R2)
  | LDate  !Integer !Int !Int           -- ^ @|YYYY-MM-DD|@
  | LDuration ![(Integer, CatDurUnit)]  -- ^ @n day + m month@
  deriving stock (Eq, Show, Generic)

data CatDurUnit = DUDay | DUMonth | DUYear
  deriving stock (Eq, Show, Generic)

data CatBinOp
  = BAdd | BSub | BMul | BDiv
  | BAnd | BOr | BXor
  | BEq | BNeq | BLt | BLeq | BGt | BGeq
  deriving stock (Eq, Show, Generic)

data CatUnOp = UNot | UNeg
  deriving stock (Eq, Show, Generic)

data CatArm = CatArm
  { armPat  :: !CatPat
  , armBody :: !CatExpr
  }
  deriving stock (Eq, Show, Generic)

data CatPat
  = PCon !Text !(Maybe Text)   -- ^ @-- C [content x]@
  | PAnything                  -- ^ @-- anything@
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- Name mangling
-- ---------------------------------------------------------------------------

-- | Mangle an L4 name to a Catala lowercase snake_case identifier.
--
-- Total and deterministic, so a definition and every reference to it agree.
-- It is /not/ injective on its own — @\`foo bar\`@ and @foo-bar@ both land on
-- @foo_bar@ — so the lowering must run 'nameCollisions' over every mangled
-- name it emits and reject a clash by name, exactly as the OpenFisca backend's
-- @checkCollisions@ does (its @pyIdent@ had the same hazard).
catIdent :: Text -> Text
catIdent raw =
  let split   = Text.concatMap splitCamel raw
      cleaned = Text.map (\c -> if isIdentChar c then toLower c else ' ') split
      joined  = Text.intercalate "_" (Text.words cleaned)
  in keywordSafe (ensureLetter (if Text.null joined then "v" else joined))
 where
  isIdentChar c = isAscii c && (isAlphaNum c || c == '_')
  -- @isVeteran@ is one word to L4 and two to Catala's house style; break at the
  -- camel humps so the emitted name reads as @is_veteran@.
  splitCamel c
    | isAscii c && isUpper c = Text.pack [' ', c]
    | otherwise              = Text.singleton c
  ensureLetter t = case Text.uncons t of
    Just (h, _) | isDigit h || h == '_' -> "v_" <> t
    _                                   -> t
  keywordSafe t
    | t `Set.member` catReserved = t <> "_"
    | otherwise                  = t

-- | Mangle an L4 name to a Catala Capitalised name — used for structures,
-- enumerations, enum constructors, scopes, and the module name. Catala's
-- lexer requires an uppercase initial for all of these.
catUpper :: Text -> Text
catUpper raw =
  let parts = Text.words (Text.map (\c -> if isIdentChar c then c else ' ') raw)
      camel = Text.concat (map capitalise parts)
  in if Text.null camel then "X" else ensureUpper camel
 where
  isIdentChar c = isAscii c && (isAlphaNum c || c == '_')
  capitalise t = case Text.uncons t of
    Just (h, rest) -> Text.cons (toUpper h) rest
    Nothing        -> t
  ensureUpper t = case Text.uncons t of
    Just (h, _) | isDigit h || h == '_' -> Text.cons 'X' t
                | otherwise             -> Text.cons (toUpper h) (Text.drop 1 t)
    Nothing                             -> "X"

-- | Catala's English reserved words, read out of
-- @compiler\/surface\/lexer_en.cppo.ml@ (catala 1.2.1), plus the sort\/order
-- words the cheat sheet uses. A mangled identifier colliding with one of these
-- gets a trailing underscore.
catReserved :: Set Text
catReserved = Set.fromList
  [ "all", "among", "and", "anything", "as", "assertion", "boolean", "but"
  , "code_location", "combine", "condition", "consequence", "contains"
  , "content", "context", "data", "date", "day", "decimal", "declaration"
  , "decreasing", "definition", "depends", "down", "duration", "each", "else"
  , "empty", "enumeration", "equals", "exception", "exists", "external"
  , "false", "for", "fulfilled", "have", "if", "impossible", "in", "increasing"
  , "initially", "input", "integer", "internal", "is", "label", "let", "list"
  , "map", "match", "maximum", "minimum", "money", "month", "not", "number"
  , "of", "on", "optional", "or", "order", "output", "pattern", "replace"
  , "round", "rule", "scope", "sort", "state", "structure", "such", "sum"
  , "that", "then", "to", "true", "type", "under", "up", "we", "with", "xor"
  , "year"
  ]

-- | Group original names by the mangled name they land on, returning only the
-- groups where two /distinct/ originals collide. The caller turns each into a
-- @LowerError@: distinct L4 definitions sharing an emitted name would silently
-- conflate in Catala's flat namespace.
nameCollisions :: [(Text, Text)] -> [(Text, [Text])]
nameCollisions pairs =
  [ (mangled, origs)
  | (mangled, origs) <- Map.toList grouped
  , length origs > 1
  ]
 where
  grouped =
    Map.map (Set.toList . Set.fromList)
      (Map.fromListWith (<>) [ (m, [o]) | (m, o) <- pairs ])
