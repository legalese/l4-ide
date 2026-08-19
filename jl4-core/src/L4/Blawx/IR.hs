-- | The __block-level__ intermediate representation of a Blawx project: one
-- 'BlawxDoc' per L4 module, modelling Blawx's /block/ inventory — categories,
-- attributes, relationships, attributed rules, facts, constraints, abducibles,
-- queries — and never s(CASP) text. Blocks are the pivot because they are the
-- only representation from which __both__ wire formats derive
-- (BLAWX-EXPORT-SPEC R12): the server stores @scasp_encoding@ and
-- @xml_content@ verbatim and derives neither from the other; only the block
-- structure determines both.
--
-- __The two-renderer contract.__ Both of "L4.Blawx.Emit"'s renderers consume
-- this IR and nothing else:
--
--   * @renderScasp :: BlawxDoc -> Text@ — P1; byte-exact against
--     @scasp_generator.js@ at Blawx commit @02eded1@, quirks included (R10),
--     because the fidelity gate is the re-save fixpoint: the Blawx editor
--     regenerates @scasp_encoding@ from blocks on every save, and the stored
--     text must not change (R12).
--   * @renderXml :: BlawxDoc -> Text@ — P3; the paired Blockly XML. In P1
--     every emitted @xml_content@ is the empty string (R12 delegated
--     sub-decision, consistent with the executed tier-2 smoke).
--
-- Anything expressible in this IR must therefore be expressible as /blocks/:
-- a constructor with no block image (e.g. a raw Prolog escape hatch) must not
-- be added, because @renderScasp@ could print it but @renderXml@ could not,
-- and the first UI save would destroy it.
--
-- __The P5 import-pivot role.__ The import direction (R14, @l4 blawx
-- --import@) parses @xml_content@ into /this same IR/ (@L4.Blawx.Parse@) and
-- lifts it to L4 (@L4.Blawx.Lift@); @scasp_encoding@ is only a cross-check —
-- regenerate via @renderScasp@ and diff to detect stale or hand-edited
-- encodings before lifting. The round-trip property @lift . emit = id@
-- (modulo formatting) on the v1 export fragment is stated against this type.
-- Consequently the IR must stay faithful to what blocks /store/ (e.g. NLG
-- prefix\/infix\/postfix as three separate fields, not a fused sentence),
-- or the fixpoint and the import both lose information.
--
-- __Names are already target-lexical here.__ "L4.Blawx.Lower" mangles
-- 'L4.Relational.IR.RName's into 'BName's (@^[a-z]\\w*$@, not ending
-- @_\\d+@ — the UI validator silently rewrites violations) and runs the
-- injective collision check /before/ building the 'BlawxDoc'; the emitters
-- never mangle. Provenance for citations rides along as the original
-- 'Unique'\/'SrcRange' so P4's justification story and the goldens' error
-- messages can still point at L4 source.
module L4.Blawx.IR
  ( -- * The document
    BlawxDoc (..)
  , BRuleText (..)
  , BSection (..)
  , BSectionRef (..)
    -- * Workspaces and blocks
  , BWorkspace (..)
  , BBlock (..)
    -- * Ontology declaration blocks
  , BCategoryDecl (..)
  , BAttributeDecl (..)
  , BRelationshipDecl (..)
  , BValueType (..)
  , BNlgOrder (..)
    -- * Rules and goals
  , BRule (..)
  , BConclusion (..)
  , BGoal (..)
  , BCmpOp (..)
  , BAggFn (..)
  , BArith (..)
  , BArithOp (..)
    -- * Terms and names
  , BTerm (..)
  , BVar (..)
  , BName -- abstract: see 'mkBName'
  , bNameText
  , mkBName
    -- * Tests
  , BTest (..)
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)

import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax (Unique)

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

-- | A Blawx-conforming atom: matches @^[a-z]\w*$@ and does not end @_\d+@.
--
-- Abstract on purpose: the only constructor is 'mkBName', which checks the
-- regex-and-suffix invariant, so an emitter printing a 'BName' verbatim can
-- never emit an atom the UI validator would rewrite (breaking the R12
-- fixpoint). The original L4 identity ('Unique') is carried for provenance
-- joins; equality is on the /text/, because in the target the atom text IS
-- the identity (two distinct L4 names mangling to one atom are a collision
-- "L4.Blawx.Lower" must have rejected already).
data BName = MkBName
  { bnText   :: !Text
  , bnUnique :: !(Maybe Unique)  -- ^ 'Nothing' for synthesised names (skolems, aux)
  }
  deriving stock (Show, Generic)
  deriving anyclass (NFData)

instance Eq  BName where a == b = a.bnText == b.bnText
instance Ord BName where compare a b = compare a.bnText b.bnText

bNameText :: BName -> Text
bNameText n = n.bnText

-- | Smart constructor; 'Nothing' when the text violates the atom invariant.
-- "L4.Blawx.Lower"'s mangler is supposed to produce only valid atoms, so a
-- 'Nothing' at a Lower call site is a mangler bug surfacing as a diagnostic,
-- never a silent rewrite (the UI validator's failure mode this type exists to
-- prevent).
mkBName :: Maybe Unique -> Text -> Maybe BName
mkBName u t
  | validAtom, not endsUnderscoreDigits = Just (MkBName t u)
  | otherwise = Nothing
 where
  validAtom = case Text.uncons t of
    Nothing      -> False
    Just (c, cs) -> isAsciiLower c && Text.all wordChar cs
  wordChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'
  -- @_\d+$@: a nonempty digit suffix immediately preceded by an underscore.
  endsUnderscoreDigits =
    let ds = Text.takeWhileEnd isDigit t
    in  not (Text.null ds) && "_" `Text.isSuffixOf` Text.dropWhileEnd isDigit t

-- | A Blawx variable: capitalised text, unique within its clause. Rendering
-- of unused head variables as @_@\/@_Name@ is the emitter's job.
newtype BVar = MkBVar Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- The document
-- ---------------------------------------------------------------------------

-- | One Blawx project: exactly what one @.blawx@ file (and its sibling @.pl@
-- dump) serialises. Workspaces are ordered: @root_section@ first, then the
-- numbered sections ascending — the emission order of the YAML stream and of
-- the concatenated s(CASP).
data BlawxDoc = MkBlawxDoc
  { bdName       :: !Text        -- ^ @ruledoc_name@
  , bdRuleText   :: !BRuleText   -- ^ structured CLEAN source; rendered by Emit
  , bdWorkspaces :: ![BWorkspace]
  , bdTests      :: ![BTest]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | The CLEAN @rule_text@, kept structured so eIds are predictable (R4): the
-- rendered form is @title\n\n1. …\n2. …@ with flat numbered sections only —
-- section /n/ yields AKN eId @sec_n@, hence workspace @sec_n_section@.
data BRuleText = MkBRuleText
  { brTitle    :: !Text
  , brSections :: ![BSection]   -- ^ numbered 1.. in list order
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data BSection = MkBSection
  { bsNumber :: !Int    -- ^ 1-based; invariant: position in 'brSections' + 1
  , bsText   :: !Text   -- ^ one paragraph, no newlines
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | A workspace name, structurally: never a free-form string, so a typo like
-- @sec1_section@ cannot be constructed. Rendered @root_section@ \/
-- @sec_\<n\>_section@.
data BSectionRef = BRoot | BSec !Int
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data BWorkspace = MkBWorkspace
  { bwName   :: !BSectionRef
  , bwStacks :: ![[BBlock]]
    -- ^ __Top-level block stacks__, mirroring the Blockly canvas: blocks
    -- inside one stack are chained (rendered with no blank line between
    -- them), separate stacks are separated by one blank line. This nesting
    -- is byte-load-bearing for @renderScasp@ (see @p1-design\/emit-plan.md@
    -- §1) and is what @renderXml@ turns into separate @\<block\>@ roots with
    -- @x@\/@y@ placement in P3. Convention from the evidence pair:
    -- declarations form ONE stack; each attributed rule is its OWN stack.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------

-- | One block (or one statement-position block tree). Each constructor
-- corresponds to a block type in @blawx-blocks.js@; nothing here is "raw
-- s(CASP)" — see the module header for why.
data BBlock
  = BDeclareCategory !BCategoryDecl
    -- ^ @new_category_declaration@ — a 44-line s(CASP) image
  | BDeclareAttribute !BAttributeDecl
    -- ^ @new_attribute_declaration@ — a 44-line s(CASP) image
  | BDeclareRelationship !BRelationshipDecl
    -- ^ @relationship_declaration@ (arity 3–10) — a 44-line s(CASP) image
  | BAttributedRule !BRule
    -- ^ @attributed_rule@ — the defeasibility triple with dedup markers
  | BFact !Bool !BName ![BTerm]
    -- ^ a ground assertion; the 'Bool' is the sign (@False@ = classical
    -- @-p(…)@). Used for enum-constructor membership facts in
    -- @root_section@ and for test-scenario facts (NEVER @fact_scenario@,
    -- R11).
  | BConstraint ![BGoal]
    -- ^ @false :- goals.@ — the @#ASSERT@-as-constraint emission (R11)
  | BAbducible !BName ![BTerm]
    -- ^ @#abducible p(…).@ — the interview test's input declarations
  | BQuery !BName ![BTerm]
    -- ^ the test query, rendered as the LAST line @?- p(…).@ (reasoner scan
    -- contract). Only valid inside a 'BTest' body; Lower never puts one in a
    -- workspace.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Blawx attribute\/relationship value types (@scasp_generator.js@ value-type
-- vocabulary; the dropdown options in @blawx-blocks.js@ are @boolean@,
-- @number@, @date@, @time@, @datetime@, @duration@, @list@ plus every declared
-- category). M1\/v1 never constructs the date\/time\/duration members
-- (dates are rejected upstream), but the type names them so P5 import can
-- represent every shipped example.
data BValueType
  = BVBoolean | BVNumber | BVDate | BVTime | BVDatetime | BVDuration
  | BVList
  | BVCategory !BName
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | Argument order of a binary attribute's NLG sentence: @ov@ (object then
-- value → args @X,Y@) or @vo@ (args @Y,X@). v1 always emits 'BOrderOV';
-- carried so the import can read either.
data BNlgOrder = BOrderOV | BOrderVO
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | @new_category_declaration@ fields. NLG slots are stored exactly as the
-- block stores them (prefix\/postfix around @(X)@) — fusing them would break
-- the R12 fixpoint and the P5 lift.
data BCategoryDecl = MkBCategoryDecl
  { bcName    :: !BName
  , bcPrefix  :: !Text
  , bcPostfix :: !Text
  , bcProv    :: !(Maybe (Unique, Maybe SrcRange))
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | @new_attribute_declaration@ fields. A 'BVBoolean' attribute is a UNARY
-- predicate and its infix\/order fields render as the bare atom
-- @not_applicable@ in @blawx_attribute_nlg@ — the emitter, not this type,
-- owns that quirk.
data BAttributeDecl = MkBAttributeDecl
  { baCategory :: !BName        -- ^ the owning category
  , baName     :: !BName        -- ^ the attribute = the global predicate name
  , baType     :: !BValueType
  , baOrder    :: !BNlgOrder
  , baPrefix   :: !Text
  , baInfix    :: !Text         -- ^ ignored (→ @not_applicable@) when boolean
  , baPostfix  :: !Text
  , baProv     :: !(Maybe (Unique, Maybe SrcRange))
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | @relationship_declaration@ fields; arity = @length brTypes@, 3–10
-- (checked in Lower with a named diagnostic — the ceiling is the emitter's
-- to enforce, per "L4.Relational.IR"'s module haddock).
data BRelationshipDecl = MkBRelationshipDecl
  { brName     :: !BName
  , brTypes    :: ![BValueType]
  , brPrefixes :: ![Text]        -- ^ one per argument, same length as 'brTypes'
  , brPostfix  :: !Text
  , brProv     :: !(Maybe (Unique, Maybe SrcRange))
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

-- | One @attributed_rule@ block. The section is carried on the rule (not
-- inferred from the enclosing workspace) because the @doc_selector@ block
-- stores it, and P5 import must detect a rule filed in the wrong workspace.
--
-- Mode A (v1): 'brDefeasible' is always 'False' — the checkbox states the
-- truth, no defeat rules exist. Negative conclusions ('bcSign' = 'False')
-- are never constructed in v1 (no CWA bridges yet, R5 "yes-later").
data BRule = MkBRule
  { brSection    :: !BSectionRef
  , brConclusion :: !BConclusion
  , brConditions :: ![BGoal]     -- ^ ordered; order is semantics (inherited from RClause)
  , brDefeasible :: !Bool
  , brProvenance :: !(Maybe (Unique, Maybe SrcRange))
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data BConclusion = MkBConclusion
  { bcSign :: !Bool              -- ^ 'False' = classical negative conclusion @-p@
  , bcPred :: !BName
  , bcArgs :: ![BTerm]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | One condition-position goal. Each constructor is a block in the
-- condition drawer; the mapping from 'L4.Relational.IR.RGoal' is
-- "L4.Blawx.Lower"'s classification step (see @p1-design\/emit-plan.md@ §4
-- for the goal-by-goal table and @p1-design\/risks.md@ for where it can go
-- wrong).
data BGoal
  = BGCall !Bool !BName ![BTerm]
    -- ^ signed predicate goal: @True@ → @p(…)@, @False@ → classical @-p(…)@
    -- (image of 'L4.Relational.IR.RNotCall' on an input predicate, and of
    -- the boolean-projection-@FALSE@ peephole)
  | BGNaf !BName ![BTerm]
    -- ^ negation as failure @not p(…)@ (image of 'L4.Relational.IR.RNotCall'
    -- on a computed\/auxiliary predicate — R5)
  | BGCompare !BCmpOp !BTerm !BTerm
    -- ^ @blawx_comparison(X,op,Y)@ — numeric operands only (REq dispatch
    -- happens in Lower, by sort)
  | BGUnify !BTerm !BTerm
    -- ^ @X = Y@ — generic equality on atoms\/objects (non-numeric @REq@,
    -- and @RMatch@ discrimination)
  | BGDiseq !BTerm !BTerm
    -- ^ @blawx_diseq(X,Y)@ — non-numeric @RNeq@
  | BGIs !BVar !BArith
    -- ^ @Var is Expr@ (image of @REval@)
  | BGFindall !BVar ![BGoal] !BVar
    -- ^ @findall(Template ,   Goal , List)@ — template var, single-goal body
    -- in v1 (a multi-goal body is factored through an auxiliary predicate by
    -- Lower; see @p1-design\/risks.md@ R7), output list var
  | BGAggregate !BAggFn !BVar !BVar
    -- ^ @\<fn\>_blawx_list(List , Out)@ — list first, out second, matching
    -- 'L4.Relational.IR.RAggregate''s stated order
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data BCmpOp = BEq | BNeq | BGt | BGte | BLt | BLte
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data BAggFn = BCount | BSum | BAverage | BMin | BMax
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | Mirror of 'L4.Relational.IR.RArith' with variables already renamed to
-- 'BVar'. Operand order and association are load-bearing (see @RArith@'s
-- haddock); the emitter parenthesises minimally but never reassociates.
data BArith
  = BANum !Rational   -- ^ must render exactly; non-integral rendering is R7-gated
  | BAVar !BVar
  | BABin !BArithOp !BArith !BArith
  | BANeg !BArith
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data BArithOp = BAdd | BSub | BMul | BDiv
  -- ^ no Mod: Blawx's calculation block has @+ - * \/@ only; @RMod@ is
  -- rejected in Lower with a named diagnostic
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Terms
-- ---------------------------------------------------------------------------

data BTerm
  = BTVar  !BVar
  | BTNum  !Rational   -- ^ see 'BANum' note
  | BTAtom !BName      -- ^ an object, enum constructor, or string-literal atom
  | BTNil
  | BTCons !BTerm !BTerm  -- ^ rendered @[H | T]@ (head_tail block spacing)
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

-- | One BlawxTest row: scenario facts asserted directly in the body (never
-- @fact_scenario@ — R11), optional @false :-@ constraints for @#ASSERT@s,
-- and the query as the final block. The L4-oracle expected value is NOT
-- here — it lives in the tier-1 harness (R11: the oracle stays outside the
-- artifact).
data BTest = MkBTest
  { btName   :: !Text        -- ^ slug, @[-a-zA-Z0-9_]+@ (Django URL converter)
  , btStacks :: ![[BBlock]]  -- ^ facts\/constraints\/abducibles; the 'BQuery'
                             --   must be the last block of the last stack
  , btProv   :: !(Maybe (Unique, Maybe SrcRange))
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
