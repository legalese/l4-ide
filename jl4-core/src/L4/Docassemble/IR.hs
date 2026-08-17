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
  , DAReview (..)
  , DAReviewRow (..)
  , DAAttachment (..)
  , DAExpr (..)
  , DAQuantOp (..)
  , DABinOp (..)
  , DACmpOp (..)
  , DAFile (..)
  , DAPackageTree (..)
  , runtimeExports
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
  | DAIsBool  !DAExpr !Bool
    -- ^ M4: @\<e\> is True@ \/ @\<e\> is False@ — the payload-VALUE match on a
    -- @MAYBE BOOLEAN@ (@WHEN JUST FALSE@, R8 scope ruling). Identity, not
    -- equality: @yesnomaybe@ stores the three states as @True@\/@False@\/@None@
    -- and @None == False@ is False in Python but @0 == False@ is True, so @is@
    -- is the comparison that cannot be fooled by a numeric zero.
  | DADateLit !Text
    -- ^ M4 (R12): a date literal, ISO @YYYY-MM-DD@, emitted as
    -- @as_datetime('…')@. A submitted @datatype: date@ answer enters the
    -- interview as @as_datetime(\<submitted string\>)@
    -- (@interview\/views.py:1372@ at @1b6678384@), i.e. a tz-aware
    -- @DADateTime@; a bare string compared against one raises @TypeError@.
  | DAAttr    !DAExpr !Text    -- ^ @\<e\>.name@ — @DATE_YEAR@\/@_MONTH@\/@_DAY@
  | DAMethod  !DAExpr !Text ![(Text, DAExpr)]
    -- ^ @\<e\>.name(kw=v, …)@ — the @DADateTime.plus@\/@.minus@ calendar
    -- arithmetic (R12).
  | DAQuant   !DAQuantOp !Text !DAExpr !DAExpr
    -- ^ M4: @all(\<body\> for \<var\> in \<list\>)@ \/ @any(…)@ over a gathered
    -- @DAList@. A GENERATOR expression, never a list comprehension: the
    -- generator is lazy, so @all@ stops at the first false element and the
    -- elements after it are never read — which is what keeps per-element
    -- question pruning alive inside a gather.
  deriving stock (Eq, Show, Generic)

data DAQuantOp = DAAll | DAAny
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
  | DAInstantiateList !Text
    -- ^ M4: @var = DAList('var', object_type=\<Class\>)@ — a @LIST OF\<record\>@
    -- input. @object_type@ is load-bearing, not decoration: a @DAList@ with no
    -- @object_type@ fails on the first element access (ablation-probed against
    -- 1.10.7). @there_are_any@ is deliberately NOT preset, because presetting it
    -- makes the empty list unreachable and the empty list is a real answer.
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
  , qShowIf  :: !(Maybe DAExpr)
    -- ^ M4: a server-side @show if:@ guard, rendered with its @code:@ sub-key.
    -- The @{variable:, is:}@ spelling is browser-side JavaScript only
    -- (@parse.py:3998-4002@ sets @show_if_var@\/@show_if_val@ and no
    -- @showif_code@), so the engine shows every field and an API or headless
    -- drive DEFINES them all; only the code form leaves a hidden field
    -- genuinely undefined (@parse.py:6316-6325@ sets @extras['ok'][n] = False@).
    -- Two things ride on it: the constructor payload that was not chosen
    -- (R6) and the value half of a @MAYBE NUMBER@\/@DATE@ pair (R8).
  }
  deriving stock (Eq, Show, Generic)

-- | One @code:@ block defining one variable (R3 survival).
data DACode = MkDACode
  { cId   :: !Text            -- ^ deterministic @id:@
  , cVar  :: !Text            -- ^ the variable set (also emitted under @sets:@)
  , cL4   :: !(Maybe Text)    -- ^ the original L4 name, for the provenance comment
  , cBody :: !DACodeBody
  , cDeps :: ![Text]          -- ^ direct free variables → @depends on:@ (stale-value trap, R9.3)
  , cCite :: !(Maybe Text)
    -- ^ M2: this rule's @\@ref@ citation, herald-stripped and raw (escaping is
    -- the emitter's job). Emitted as an @explain(…)@ call /after/ the
    -- assignment, so a rule that raised on a missing input — and therefore
    -- decided nothing yet — records nothing. Because CPython short-circuits,
    -- the accumulated list is exactly the rules that fired, in order.
  , cFresh :: !Bool
    -- ^ M4 (spec §8.4): emit @reconsider: True@, so the block is re-run from
    -- the current answers on every assemble pass instead of surviving as a
    -- cached value. Without it, changing an earlier answer leaves the VERDICT
    -- stale, not merely its citations (measured). True for every derived value;
    -- FALSE for an object instantiation, where re-running would replace the
    -- @DAObject@\/@DAList@ and throw away everything gathered into it.
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
  , sCites   :: !Bool
    -- ^ M2: render the accumulated @\@ref@ citations through
    -- @logic_explanation()@. False when the module emitted no @explain(…)@ at
    -- all, so a module without citations keeps its v1 screen byte for byte.
  , sAttach  :: !Bool
    -- ^ M4: assemble the module's letter on this screen ('pkgAttach'). The
    -- document is attached to the VERDICT screens, because a citizen who is
    -- told \"no\" is exactly the citizen who needs the document explaining why.
  }
  deriving stock (Eq, Show, Generic)

-- | M4: the compliance-checklist view (spec §10). One passive row per emitted
-- question, whether or not the interview ever asked it — which is the half a
-- plain answer summary cannot do, because a backchaining interview leaves the
-- short-circuited questions with no answer to summarise.
--
-- Reached by firing 'rvEvent' as an action; a review block is unreachable
-- otherwise (probed: without the action the interview simply ends).
data DAReview = MkDAReview
  { rvId    :: !Text
  , rvEvent :: !Text
  , rvTitle :: !Text            -- ^ generated prose (ASCII, not L4-derived)
  , rvRows  :: ![DAReviewRow]
  }
  deriving stock (Eq, Show, Generic)

-- | One checklist row: the L4 label, and the variable whose answer it shows.
--
-- Emitted as a @note:@ carrying @showifdef(\<var\>, \<marker\>)@. That is the
-- only recipe that renders a row for a NEVER-ASKED variable: a note row has no
-- @saveas@ to evaluate, so it renders whether or not the variable exists.
-- @skip undefined: False@ does not do this — it FORCE-ASKS every undefined row
-- (@parse.py:5876-5904@), and the default silently drops them into a debug log
-- line (both measured).
data DAReviewRow = MkDAReviewRow
  { rrLabel :: !Text            -- ^ the L4 name, verbatim (escaped at emit)
  , rrVar   :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | M4: the assembled document (spec §10's document-assembly demo).
--
-- 'atVar' is not tidiness: without @variable name:@ docassemble files the
-- document under @_internal['docvar'][n]@ (@parse.py:4997-5003@) and there is
-- nothing left to assert about — and the failure this defends against is not an
-- exception but a SUCCESSFUL EMPTY RENDER, which raises nothing and logs
-- nothing.
data DAAttachment = MkDAAttachment
  { atVar     :: !Text   -- ^ @variable name:@ — the DAFileCollection
  , atName    :: !Text   -- ^ @name:@, generated prose
  , atFile    :: !Text   -- ^ @filename:@, no extension
  , atSource  :: !Text   -- ^ the template file's basename, for provenance
  , atContent :: !Text
    -- ^ the template body, VERBATIM. This is the one string the emitter does
    -- not put through 'L4.Docassemble.Emit.escapeL4': it is the author's own
    -- Mako, written to be rendered, not L4-derived prose being quoted into a
    -- Mako-rendered position (R9.1 governs the latter). Indentation still keeps
    -- it clear of the @^--- *$@ block splitter.
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
  | DAReviewBlock !DAReview
  deriving stock (Eq, Show, Generic)

data DAPackage = MkDAPackage
  { pkgSource :: !Text        -- ^ provenance (source file basename) for the header
  , pkgTitle  :: !Text        -- ^ interview @metadata: title@
  , pkgBlocks :: ![DABlock]   -- ^ in stable emission order
  , pkgGloss  :: ![(Text, Text)]
    -- ^ M2: the @auto terms:@ glossary — (L4 defined term, its @\@desc@), in
    -- declaration order. Empty for a module that defines no glossed term, and
    -- the block is then not emitted at all.
  , pkgAttach :: !(Maybe DAAttachment)
    -- ^ M4: the letter this module assembles, if the author put a template
    -- beside the @.l4@. Held once here and rendered into each screen whose
    -- 'sAttach' is set, so the @--package@ tree can also ship the template
    -- under @data\/templates@.
  , pkgFresh  :: !(Maybe Text)
    -- ^ M4 (spec §8.4): the citation-reset sentinel variable, present exactly
    -- when some block carries a citation. Its block calls
    -- @clear_explanations()@ and is @reconsider@ed, so it runs once per
    -- assemble; the driver references it BEFORE the goal, which is what makes
    -- the accumulated list the rules that fired /this/ time rather than a
    -- session-long log.
  , pkgPlan   :: !(Maybe Text)
    -- ^ reserved slot for M3's embedded compiled decision query (spec R1
    -- cost: the IR anticipates M3 so M3 does not rework Emit). Always
    -- 'Nothing' in v1; the emitter ignores it.
  }
  deriving stock (Eq, Show, Generic)

-- | One file of a generated docassemble package tree.
data DAFile = MkDAFile
  { dafPath :: ![Text]   -- ^ path segments relative to the package root
  , dafBody :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | The installable package tree (R11, M2): the modern PEP 420 shape, whose
-- exemplar is @docassemble_demo/@ at the 1.10.7 pin — @pyproject.toml@ only,
-- @MANIFEST.in@ grafting @data/@, and deliberately __no__
-- @docassemble/__init__.py@ (setuptools' pyproject path defaults to PEP 420
-- namespace finding, and a namespace @__init__.py@ would turn @docassemble@
-- into a regular package that shadows the installed @docassemble.base@).
--
-- The @.l4@ source itself is /not/ a 'DAFile': provenance means the bytes, so
-- the caller copies the file rather than re-encoding its text. 'ptSourceCopy'
-- and 'ptFidelity' say where.
data DAPackageTree = MkDAPackageTree
  { ptDistName   :: !Text      -- ^ @docassemble.l4\<slug\>@
  , ptFiles      :: ![DAFile]  -- ^ every generated text file, root-relative
  , ptSourceCopy :: ![Text]    -- ^ where to copy the @.l4@ source, byte for byte
  , ptFidelity   :: ![Text]    -- ^ where to write the fidelity report
  }
  deriving stock (Eq, Show, Generic)

-- | The @__all__@ of the generated @l4runtime.py@ (R11, M2), declared here
-- because /two/ modules must agree on it and neither may drift.
--
-- 'L4.Docassemble.Emit' writes it into the module. 'L4.Docassemble.Lower'
-- reserves the names an L4 identifier could actually land on, because
-- @modules: [.l4runtime]@ is exec'd as @from \<pkg\>.l4runtime import *@
-- (@parse.py:8572@ at @1b6678384@) into the interview dict on every assemble
-- pass: a star-import cannot collide with an interview variable only in the
-- sense that @__all__@ bounds /which/ names arrive — it does nothing to stop an
-- interview variable from being one of them, and the loser is the interview's.
--
-- Only the lower-case entries are reachable from L4: 'L4.Docassemble.Lower's
-- @pyIdent@ lower-cases, and Python names are case-sensitive, so no L4 name can
-- sanitise onto @L4_SOURCE_NAME@. That filter is applied where the names are
-- reserved, not here — this list is the module's contract, verbatim.
runtimeExports :: [Text]
runtimeExports =
  [ "L4_SOURCE_NAME"
  , "L4_PACKAGE_NAME"
  , "L4_GENERATOR"
  , "L4_DOCASSEMBLE_PIN"
  , "l4_source_path"
  , "l4_source_text"
  ]
