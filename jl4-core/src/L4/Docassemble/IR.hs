-- | Target intermediate representation for the docassemble backend.
--
-- A docassemble interview is a sequence of /blocks/: @objects:@ blocks that
-- instantiate objects, @question:@ blocks that define variables by asking,
-- @code:@ blocks that define variables by computing, one @mandatory:@ driver
-- that pulls on the goal, and terminal @event:@ screens. Docassemble discovers
-- evaluation order at runtime by backchaining on undefined variables, so this
-- IR carries /definitions, not sequence/ — which is exactly the shape of an L4
-- module (DOCASSEMBLE-EXPORT-SPEC.md, one-line summary).
--
-- The IR is deliberately small: 'L4.Docassemble.Lower' produces it from a
-- typechecked @Module Resolved@ together with a
-- 'L4.Interchange.Fidelity.FidelityReport', and 'L4.Docassemble.Emit' renders
-- it to a single self-contained interview YAML. All L4-derived prose is stored
-- /raw/ here; escaping is the emitter's job (spec R9: one escape function).
module L4.Docassemble.IR
  ( DAPackage (..)
  , DABlock (..)
  , DAQuestion (..)
  , DAFieldControl (..)
  , DACode (..)
  , DACodeBody (..)
  , DADriver (..)
  , DAScreen (..)
  , DAExpr (..)
  , DABinOp (..)
  , DACmpOp (..)
  ) where

import Base

-- | A small Python expression IR: 'L4.OpenFisca.IR.OFExpr' at the same
-- altitude, minus numpy — docassemble @code:@ blocks are plain CPython, and
-- CPython short-circuit is the question pruner (spec §2), so operand order is
-- question order and must be preserved by construction.
data DAExpr
  = DANum     !Rational        -- ^ numeric literal
  | DAStrLit  !Text            -- ^ string literal (also enum constructor values, R6)
  | DABoolLit !Bool
  | DAVar     !Text            -- ^ a seekable interview variable or attribute path
  | DABin     !DABinOp !DAExpr !DAExpr
  | DACmp     !DACmpOp !DAExpr !DAExpr
  | DAAnd     !DAExpr !DAExpr  -- ^ Python @and@ — short-circuit = pruning
  | DAOr      !DAExpr !DAExpr
  | DANot     !DAExpr
  | DACond    !DAExpr !DAExpr !DAExpr   -- ^ @<then> if <cond> else <else>@
  | DAIsNone  !DAExpr          -- ^ @<e> is None@ — the MAYBE BOOLEAN absence
                               --   test (R8: @yesnomaybe@ stores NOTHING as None)
  deriving stock (Eq, Show, Generic)

data DABinOp = DAAdd | DASub | DAMul | DADiv | DAMod
  deriving stock (Eq, Show, Generic)

data DACmpOp = DALt | DALeq | DAGt | DAGeq | DAEq | DANeq
  deriving stock (Eq, Show, Generic)

-- | The body of a @code:@ block that defines one variable.
data DACodeBody
  = DAAssign !DAExpr
    -- ^ @var = expr@
  | DAIfChain ![(DAExpr, DAExpr)] !DAExpr
    -- ^ @if c1: var = v1 / elif c2: var = v2 / … / else: var = d@ — the
    -- CONSIDER-over-enum and BRANCH rendering (R6); the OTHERWISE arm is
    -- mandatory by construction.
  | DAInstantiate !Text
    -- ^ @var = <Class>('var')@ — a nested-record attribute object, with the
    -- instance name passed explicitly (R2's mechanical contract: docassemble
    -- otherwise sniffs the caller's bytecode to recover it).
  deriving stock (Eq, Show, Generic)

-- | How a single-field question renders its input widget (R6/R8).
data DAFieldControl
  = CtlYesNoRadio      -- ^ BOOLEAN → @datatype: yesnoradio@
  | CtlYesNoMaybe      -- ^ MAYBE BOOLEAN → @datatype: yesnomaybe@ (None = NOTHING, exact)
  | CtlNumber          -- ^ NUMBER → @datatype: number@ (Rational→float, Advisory)
  | CtlText            -- ^ STRING → @datatype: text@
  | CtlTextOptional    -- ^ MAYBE STRING → @datatype: text@ + @required: False@
  | CtlDate            -- ^ DATE → @datatype: date@
  | CtlRadio ![Text]   -- ^ enum → @datatype: radio@; choices are the L4
                       --   constructor names, verbatim, as homogeneous strings
  deriving stock (Eq, Show, Generic)

-- | One question block asking for one variable (R2: one question per /field/,
-- so unneeded inputs are never demanded).
data DAQuestion = MkDAQuestion
  { qId      :: !Text                 -- ^ deterministic @id:@
  , qVar     :: !Text                 -- ^ the variable set (bare or attribute path)
  , qLabel   :: !Text                 -- ^ the L4 name, verbatim (escaped at emit)
  , qText    :: !Text                 -- ^ question prose (escaped at emit)
  , qHelp    :: !(Maybe Text)         -- ^ field/type @desc@, if any
  , qControl :: !DAFieldControl
  , qDefault :: !(Maybe DAExpr)       -- ^ TYPICALLY → @default:@ (R7); literals only
  }
  deriving stock (Eq, Show, Generic)

-- | One @code:@ block defining one variable (R3 survival).
data DACode = MkDACode
  { cId   :: !Text            -- ^ deterministic @id:@
  , cVar  :: !Text            -- ^ the variable set (also emitted under @sets:@)
  , cL4   :: !(Maybe Text)    -- ^ the original L4 name, for the provenance comment
  , cBody :: !DACodeBody
  , cDeps :: ![Text]          -- ^ direct free variables → @depends on:@ (stale-value trap, R9.3)
  }
  deriving stock (Eq, Show, Generic)

-- | The single @mandatory:@ driver. Idempotent by construction: pure
-- references and conditionals only, never wrapping exceptions (R9.6).
data DADriver
  = DASeamDriver !Text !Text !Text !Text !Text !Text !Text !Text
    -- ^ id, goal L4 name, scope var, requirement var, verdict var,
    --   complies event, in-breach event, not-applicable event.
    --   Scope-first if/else — NEVER @not scope or requirement@ (R4).
  | DABoolDriver !Text !Text !Text !Text !Text
    -- ^ id, goal L4 name, goal var, holds event, fails event
  | DAValueDriver !Text !Text !Text !Text
    -- ^ id, goal L4 name, goal var, result event
  deriving stock (Eq, Show, Generic)

-- | A terminal @event:@ screen (one per verdict value, R4). The L4-derived
-- pieces are kept apart from the generated prose so the emitter can escape
-- exactly the L4-derived parts.
data DAScreen = MkDAScreen
  { sId      :: !Text
  , sEvent   :: !Text           -- ^ the event variable the driver references
  , sGoalL4  :: !Text           -- ^ L4 name of the goal (escaped at emit)
  , sDesc    :: !(Maybe Text)   -- ^ the goal's @desc prose (escaped at emit)
  , sVerdict :: !Text           -- ^ Complies | InBreach | NotApplicable | Holds | Fails | Result
  , sExplain :: !Text           -- ^ generated explanation sentence (ASCII, not L4-derived)
  , sShowVar :: !(Maybe Text)   -- ^ value screens: variable rendered via @${ … }@
  }
  deriving stock (Eq, Show, Generic)

data DABlock
  = DAObjectsBlock ![(Text, Text)]
    -- ^ @objects:@ — (variable, class) pairs; record-typed parameters as
    -- plain @DAObject@ instances (R2, v1 narrowing: real subclasses arrive
    -- with M2's @--package@)
  | DAQuestionBlock !DAQuestion
  | DACodeBlock !DACode
  | DADriverBlock !DADriver
  | DAScreenBlock !DAScreen
  deriving stock (Eq, Show, Generic)

data DAPackage = MkDAPackage
  { pkgSource :: !Text        -- ^ provenance (source file basename) for the header
  , pkgTitle  :: !Text        -- ^ interview @metadata: title@
  , pkgBlocks :: ![DABlock]   -- ^ in stable emission order
  , pkgPlan   :: !(Maybe Text)
    -- ^ reserved slot for M3's embedded compiled decision query (spec R1
    -- cost: the IR anticipates M3 so M3 does not rework Emit). Always
    -- 'Nothing' in v1; the emitter ignores it.
  }
  deriving stock (Eq, Show, Generic)
