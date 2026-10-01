-- | Target intermediate representation for the @l4 export yscript@ backend.
--
-- yscript's own executable fragment is pure propositional logic (see
-- @specs\/research\/DATALEX-YSCRIPT-RESEARCH.md@ §B\/§D and
-- @specs\/todo\/YSCRIPT-EXPORT-SPEC.md@ R1\/R2): a handful of @RULE ...
-- PROVIDES ... ONLY IF <conjunction\/disjunction>@ blocks over named
-- propositions. This IR mirrors that directly — there is no separate
-- \"package\" or \"module\" wrapper the way OpenFisca\/Docassemble need one,
-- because a yscript codebase is just a sequence of 'YsRule's.
--
-- 'L4.Yscript.Lower' produces a @['YsRule']@ from a typechecked
-- @Module Resolved@; 'L4.Yscript.Emit' renders it to yscript source text.
module L4.Yscript.IR
  ( YsExpr (..)
  , YsRule (..)
  ) where

import Base

-- | The body of a @RULE@'s @ONLY IF@ clause: a conjunction\/disjunction of
-- named propositions (R2). Deliberately has no constructor for @NOT@,
-- @IMPLIES@ or @EQUALS@ — those are refused during lowering, not represented
-- here (R2's ruling is that yscript's own negation spelling is unverified, so
-- there is nothing for this IR to carry even provisionally).
data YsExpr
  = YAtom !Text
    -- ^ A bare proposition: either another 'YsRule's own 'provides' text (a
    -- reference to a sibling rule, per yscript's cross-rule composition). or
    -- the text of a leaf @ASSUME BOOLEAN@ fact (R3) that no @RULE@ is ever
    -- emitted for.
  | YAnd !YsExpr !YsExpr
  | YOr  !YsExpr !YsExpr
  deriving stock (Eq, Show, Generic)

-- | One @RULE ... PROVIDES ... ONLY IF ...@ block — the yscript rendering of
-- a single in-fragment nullary @DECIDE@\/@MEANS@ (R1).
data YsRule = YsRule
  { label     :: !Text
    -- ^ The text after @RULE@ and before @PROVIDES@. Taken from the
    -- defining @DECIDE@'s @\@ref@ citation when present, falling back to its
    -- bare L4 name otherwise (R4).
  , provides  :: !Text
    -- ^ The proposition text after @PROVIDES@ — the @DECIDE@'s own name,
    -- verbatim (R4: L4's natural mixfix-sentence house style already reads
    -- as English, so this needs no separate rendering).
  , condition :: !YsExpr
    -- ^ The @ONLY IF@ clause.
  }
  deriving stock (Eq, Show, Generic)
