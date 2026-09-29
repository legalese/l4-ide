-- | Target intermediate representation for the OpenFisca backend.
--
-- An OpenFisca model is a set of /variables/ defined on /entities/ over time
-- /periods/. Each variable optionally carries a @formula@ computing its value
-- from other variables. This mirrors L4's decision-rule subset: a @DECIDE@ /
-- @MEANS@ over a subject and a period is exactly an OpenFisca variable.
--
-- The IR is deliberately small: 'L4.OpenFisca.Lower' produces it from a
-- typechecked @Module Resolved@, and 'L4.OpenFisca.Emit' renders it to a
-- single self-contained Python module.
module L4.OpenFisca.IR
  ( OFType (..)
  , OFPeriod (..)
  , OFRole (..)
  , OFEntity (..)
  , OFVariable (..)
  , OFExpr (..)
  , OFBinOp (..)
  , OFCmpOp (..)
  , OFBracket (..)
  , OFScaleParam (..)
  , OFScalarParam (..)
  , OFEnumDef (..)
  , OFPackage (..)
  , subExprs
  , readsVariables
  , usesParams
  , variableRefs
  ) where

import Base

-- | OpenFisca @value_type@s. @OFEnum class default@ carries the Python enum
-- class name and its default member (for @default_value@).
data OFType = OFFloat | OFInt | OFBool | OFStr | OFEnum Text Text
  deriving stock (Eq, Show, Generic)

-- | An @enum@ declaration: a Python class name and its members as
-- (python attribute, original string value) pairs.
data OFEnumDef = OFEnumDef
  { enName    :: !Text
  , enMembers :: ![(Text, Text)]
  }
  deriving stock (Eq, Show, Generic)

-- | OpenFisca @definition_period@.
data OFPeriod = OFMonth | OFYear | OFEternity
  deriving stock (Eq, Show, Generic)

-- | A role within a group entity (e.g. @adult@ / @child@ in a household),
-- derived from a @LIST OF Person@ field.
data OFRole = OFRole
  { roleKey    :: !Text  -- ^ singular key, e.g. @"adult"@; constant is @Entity.ADULT@
  , rolePlural :: !Text  -- ^ plural used in situations, e.g. @"adults"@
  , roleLabel  :: !Text
  }
  deriving stock (Eq, Show, Generic)

-- | An OpenFisca entity. @entRoles@ empty ⇒ the individual (person) entity;
-- non-empty ⇒ a group entity whose members fill those roles.
data OFEntity = OFEntity
  { entKey      :: !Text  -- ^ build_entity key, e.g. @"person"@
  , entPlural   :: !Text  -- ^ e.g. @"persons"@
  , entPy       :: !Text  -- ^ the Python variable bound to the entity, e.g. @Person@
  , entLabel    :: !Text
  , entIsPerson :: !Bool
  , entRoles    :: ![OFRole]
  }
  deriving stock (Eq, Show, Generic)

-- | An OpenFisca variable. @varFormula = Nothing@ marks an /input/ variable
-- (a leaf set by the caller); @Just@ marks a /computed/ variable.
data OFVariable = OFVariable
  { varName    :: !Text          -- ^ variable name == Python class name (sanitised)
  , varL4      :: !Text          -- ^ the original (un-sanitised) L4 name, for collision detection
  , varType    :: !OFType
  , varEntity  :: !Text          -- ^ owning entity's Python name ('entPy')
  , varEntKey  :: !Text          -- ^ owning entity's key (the formula's first arg name)
  , varPeriod  :: !OFPeriod
  , varLabel   :: !Text
  , varFormula :: !(Maybe OFExpr)        -- ^ the undated @formula@; Nothing = input variable
  , varDated   :: ![(Text, OFExpr)]      -- ^ dated @formula_YYYY_MM@ overrides (ISO date → body)
  }
  deriving stock (Eq, Show, Generic)

data OFBinOp = OFAdd | OFSub | OFMul | OFDiv | OFMod
  deriving stock (Eq, Show, Generic)

data OFCmpOp = OFLt | OFLeq | OFGt | OFGeq | OFEq | OFNeq
  deriving stock (Eq, Show, Generic)

-- | A vectorised OpenFisca formula expression (operates on numpy arrays).
data OFExpr
  = OFNum     Rational        -- ^ numeric literal
  | OFStrLit  Text            -- ^ string literal
  | OFBoolLit Bool
  | OFVarRef  Text            -- ^ @<entity>('name', period)@ — read another variable
  | OFLocal   Text            -- ^ a Python local / the @period@ parameter
  | OFMembersVar Text         -- ^ @<group>.members('name', period)@ — a member variable, as an array
  | OFSum     (Maybe Text) OFExpr   -- ^ @<group>.sum(<expr>[, role=<Entity>.<ROLE>])@
  | OFAny     (Maybe Text) OFExpr   -- ^ @<group>.any(<expr>[, role=…])@
  | OFAll     (Maybe Text) OFExpr   -- ^ @<group>.all(<expr>[, role=…])@
  | OFNbPersons (Maybe Text)        -- ^ @<group>.nb_persons([<Entity>.<ROLE>])@
  | OFBin     OFBinOp OFExpr OFExpr
  | OFCmp     OFCmpOp OFExpr OFExpr
  | OFAnd     OFExpr OFExpr
  | OFOr      OFExpr OFExpr
  | OFNot     OFExpr
  | OFNeg     OFExpr
  | OFCond    OFExpr OFExpr OFExpr   -- ^ @np.where(cond, then, else)@
  | OFScaleCalc Text OFExpr         -- ^ @parameters(period).<path>.calc(<income>)@
  | OFEnumLit Text Text             -- ^ @<EnumClass>.<member>@
  | OFNpCall  Text [OFExpr]         -- ^ @np.<fn>(<args>)@ — e.g. maximum/minimum
  | OFPeriodField Text              -- ^ @period.start.<field>@ — e.g. period's year
  | OFParamRef Text                 -- ^ @parameters(period).<path>@ — a scalar parameter
  deriving stock (Eq, Show, Generic)

-- | The immediate subexpressions of an expression.
subExprs :: OFExpr -> [OFExpr]
subExprs = \case
  OFSum _ e       -> [e]
  OFAny _ e       -> [e]
  OFAll _ e       -> [e]
  OFBin _ a b     -> [a, b]
  OFCmp _ a b     -> [a, b]
  OFAnd a b       -> [a, b]
  OFOr a b        -> [a, b]
  OFNot a         -> [a]
  OFNeg a         -> [a]
  OFCond a b c    -> [a, b, c]
  OFScaleCalc _ a -> [a]
  OFNpCall _ as   -> as
  _               -> []

-- | Does the expression read a variable of some entity? One that does is an
-- array of the entity's size; one that does not is a Python or numpy scalar.
readsVariables :: OFExpr -> Bool
readsVariables = \case
  OFVarRef _     -> True
  OFMembersVar _ -> True
  OFNbPersons _  -> True
  OFSum _ _      -> True
  OFAny _ _      -> True
  OFAll _ _      -> True
  e              -> any readsVariables (subExprs e)

-- | Does the expression read a legislation parameter?
usesParams :: OFExpr -> Bool
usesParams = \case
  OFScaleCalc _ _ -> True
  OFParamRef _    -> True
  e               -> any usesParams (subExprs e)

-- | The names of the variables the expression reads, of its own entity or of
-- the members.
variableRefs :: OFExpr -> [Text]
variableRefs = \case
  OFVarRef n     -> [n]
  OFMembersVar n -> [n]
  e              -> concatMap variableRefs (subExprs e)

-- | One bracket of a marginal-rate scale. Threshold and rate are date-indexed
-- time-series (ISO @YYYY-MM-DD@ → value), mirroring OpenFisca's parameter YAML.
data OFBracket = OFBracket
  { brThreshold :: ![(Text, Rational)]
  , brRate      :: ![(Text, Rational)]
  }
  deriving stock (Eq, Show, Generic)

-- | A legislation parameter holding a marginal-rate scale, addressed by a dotted
-- path (e.g. @taxes.social_security_contribution@). Emitted into the
-- 'TaxBenefitSystem' as a @ParameterNode@ so OpenFisca resolves brackets by date.
data OFScaleParam = OFScaleParam
  { spPath     :: !Text
  , spBrackets :: ![OFBracket]
  }
  deriving stock (Eq, Show, Generic)

-- | A scalar legislation parameter: a dotted path and a date-indexed value
-- time-series (ISO date → value), emitted as @{"values": {date: v, …}}@.
data OFScalarParam = OFScalarParam
  { spsPath   :: !Text
  , spsValues :: ![(Text, Rational)]
  }
  deriving stock (Eq, Show, Generic)

data OFPackage = OFPackage
  { pkgSource     :: !Text         -- ^ provenance (source file / module) for the header
  , pkgEntities   :: ![OFEntity]
  , pkgVariables  :: ![OFVariable] -- ^ input variables first, then computed, in stable order
  , pkgParameters :: ![OFScaleParam]
  , pkgScalars    :: ![OFScalarParam]
  , pkgEnums      :: ![OFEnumDef]
  }
  deriving stock (Eq, Show, Generic)
