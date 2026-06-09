-- | Abstract syntax for canonical PROLEG (Satoh, JURISIN 2010).
--
-- A PROLEG program is a rulebase (rules + exceptions) plus a factbase
-- (ground facts + the litigation/burden-of-proof predicates). We keep clauses
-- in source order and classify each by shape; the rulebase/factbase split is a
-- view over 'programClauses', not a parse-time partition.
--
-- See @docs/proleg-concrete-syntax.md@ for the grammar this models.
module L4.Proleg.Syntax
  ( Program (..)
  , Clause (..)
  , Rule (..)
  , Exception (..)
  , Fact (..)
  , ProcDecl (..)
  , Party (..)
  , Term (..)
  , Atom
  , Var
  ) where

import Data.Text (Text)

-- | A whole PROLEG program, clauses in source order.
newtype Program = Program
  { programClauses :: [Clause]
  }
  deriving stock (Eq, Show)

-- | Top-level clause forms, discriminated by shape.
data Clause
  = CRule Rule            -- ^ @H \<= B1, ..., Bn.@  (n may be 0)
  | CException Exception   -- ^ @exception(H, E).@
  | CProc ProcDecl         -- ^ @allege/provide_evidence/admission/plausible@
  | CFact Fact             -- ^ a factbase ground atom
  deriving stock (Eq, Show)

-- | A general rule @Head \<= b1, ..., bn@. An empty body is a bare assertion.
data Rule = Rule
  { ruleHead :: Term
  , ruleBody :: [Term]
  }
  deriving stock (Eq, Show)

-- | @exception(Head, Defeater)@: rule @Head@ is defeated when @Defeater@ holds.
data Exception = Exception
  { excHead :: Term
  , excDefeater :: Term
  }
  deriving stock (Eq, Show)

-- | A factbase ground atom (a rule with empty body, viewed as a fact).
newtype Fact = Fact
  { factAtom :: Term
  }
  deriving stock (Eq, Show)

-- | The litigation / burden-of-proof layer of the JUF theory.
data ProcDecl
  = Allege Term Party           -- ^ @allege(F, P)@: party P pleads F (burden of production)
  | ProvideEvidence Term Party  -- ^ @provide_evidence(F, P)@: P supports F with evidence
  | Admission Term Party        -- ^ @admission(F, P)@: P concedes F
  | Plausible Term              -- ^ @plausible(F)@: the standard of proof for F is met
  deriving stock (Eq, Show)

-- | A litigation party. 'PartyTerm' allows first-order party references.
data Party
  = Plaintiff
  | Defendant
  | PartyTerm Term
  deriving stock (Eq, Show)

-- | Prolog terms.
data Term
  = TVar Var                 -- ^ variable: @Buyer@, @_@
  | TAtom Atom               -- ^ atom: @alice@, @'Quoted Atom'@
  | TInt Integer             -- ^ integer literal
  | TStr Text                -- ^ string literal
  | TComp Atom [Term]        -- ^ compound: @functor(arg1, ..., argN)@, N >= 1
  | TList [Term] (Maybe Term) -- ^ list: @[a, b]@ or @[H | T]@ (tail in 'Just')
  deriving stock (Eq, Show)

-- | A PROLEG/Prolog atom (functor or constant), stored verbatim (unquoted form).
type Atom = Text

-- | A PROLEG/Prolog variable name.
type Var = Text
