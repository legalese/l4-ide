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

data CatClauseKind
  = ClPlain                     -- ^ no label
  | ClLabel     !Text           -- ^ @label L …@
  | ClException !(Maybe Text)   -- ^ @exception [L] …@
  deriving stock (Eq, Show, Generic)

-- | @consequence fulfilled@ \/ @consequence not fulfilled@ (a @rule@), or
-- @equals e@ (a @definition@).
data CatConseq
  = ConsFulfilled
  | ConsNotFulfilled
  | ConsEquals !CatExpr
  deriving stock (Eq, Show, Generic)

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
data CatTestCli = CatTestCli
  { tcCommand :: !Text     -- ^ e.g. @catala test-scope Test1 -F json@
  , tcOutput  :: ![Text]
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
