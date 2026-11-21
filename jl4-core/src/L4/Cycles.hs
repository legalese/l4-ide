-- | Which definitions in a module call themselves, directly or through each
-- other, and whether each such cycle can be shown to end: a REPORT, not yet a
-- check (#1075, layer 2). Nothing here is emitted as a diagnostic; the report
-- is read off the corpus by the jl4-test harness (@JL4_CYCLE_REPORT@) so the
-- numbers can be looked at before anyone decides what to warn about.
--
-- A cycle is a strongly connected component of the graph whose nodes are the
-- module's definitions (top-level and WHERE\/LET) and whose edges are the
-- references from one definition's body to another. Each edge carries the
-- continuations it sits under: the @HENCE@ and @LEST@ of each obligation
-- between the definition's body and the reference, and a @RECORD@'s @HENCE@.
--
-- See Note [What makes a lap wait] for when a cycle through those
-- continuations is shown to end, Note [The function checks] for the cycles
-- that run through none, and Note [What the graph cannot see] for recursion
-- that names no definition.
module L4.Cycles
  ( -- * Findings
    Finding (..)
  , CycleKind (..)
  , Verdict (..)
  , Proof (..)
  , Doubt (..)
  , Stall (..)
  , Fan (..)
  , Multiplication (..)
  , Continuation (..)
  , Alarm (..)
  , cycleFindings
  , cycleFindingsWith
  , alarms
  , findingClass
  , findingJSON
    -- * The graph, for the walk check
  , Edge (..)
  , Slot (..)
  , moduleEdges
  , plainReferences
    -- * Trusting a callee
  , libraryFile
  , apiLibraryFile
  , trustedLibrary
  , earnedByBody
  ) where

import Base
import qualified Base.Text as Text
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import Data.Either (partitionEithers)
import Data.Graph (SCC (..), stronglyConnComp)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Optics (GPlate, gplate, toListOf)

import L4.Annotation (Anno_ (..), getAnno)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax
import L4.TypeCheck.Environment
  ( andUnique, consUnique, contractUnique, emptyUnique, evalContractUnique, geqUniques, gtUniques, leqUniques
  , listUnique, ltUniques, minusUnique, notUnique, orUnique, plusUnique )
import L4.TypeCheck.Environment.TH (builtinUri)
import L4.TypeCheck.Types (CheckEntity (..), EntityInfo, substituteType)

------------------------------------------------------------------------
-- Findings
------------------------------------------------------------------------

-- | One cycle and what could be shown about it.
data Finding = MkFinding
  { members :: [(Text, Maybe Int)]
    -- ^ each definition in the cycle, with the line it starts on
  , kind    :: CycleKind
  , verdict :: Verdict
  , fan     :: Fan
    -- ^ how many times one pass through a member's body can reach the cycle
    -- again (see Note [Fan-out])
  , nests   :: Bool
    -- ^ a lap can start another cycle of obligations (see Note [Fan-out])
  , multiplies :: Maybe Multiplication
    -- ^ a continuation that, firing once, starts two or more copies of the
    -- cycle at once (see Note [What multiplies])
  }
  deriving stock (Eq, Show)

-- | A @HENCE@, @LEST@ or @RECORD … HENCE@ whose expression joins two or more
-- direct calls of the cycle's members with @RAND@ or @ROR@.
data Multiplication = MkMultiplication
  { rule      :: Text
    -- ^ the member whose body holds the continuation
  , at        :: Maybe SrcRange
    -- ^ the continuation's expression
  , operator  :: Text
    -- ^ @RAND@, @ROR@, or @RAND and ROR@
  , copies    :: Int
    -- ^ how many calls of members the expression joins
  , via       :: Continuation
  , stepsDown :: Maybe (Text, Rational)
    -- ^ when every copy is the rule itself, passed one parameter less a
    -- number written out: that parameter and the number. As written, not a
    -- proof that the parameter reaches a stop
  }
  deriving stock (Eq, Show)

-- | Which continuation, with the modal of the obligation it belongs to.
data Continuation = HenceOf DeonticModal | LestOf DeonticModal | AfterRecord
  deriving stock (Eq, Show)

-- | The three warnings a finding can draw (smucclaw/l4-ide#1075, recursion-limit
-- ruling L3, 2026-11-20). Only a proof feeds the two that cannot be
-- silenced: 'Multiplies' needs a 'Multiplication', 'NoTime' a lap whose every
-- stall is a deadline that gives no time. 'CouldNotCheck' is everything else
-- left unproved, and is the one @\@ends-because@ silences (ruling L4).
data Alarm = Multiplies | NoTime | CouldNotCheck
  deriving stock (Eq, Show)

alarms :: Finding -> [Alarm]
alarms f = [Multiplies | isJust f.multiplies] <> case f.verdict of
  Unproved (Stalled ss) | all isNotPositive ss -> [NoTime]
  Unproved _ -> [CouldNotCheck]
  Proved _ -> []
 where
  isNotPositive = \ case
    NotAfterArming _ -> True
    _ -> False

data CycleKind
  = FunctionCycle
    -- ^ no edge of the cycle sits under a @HENCE@ or @LEST@
  | ObligationCycle
    -- ^ at least one does
  deriving stock (Eq, Show)

data Verdict = Proved Proof | Unproved Doubt
  deriving stock (Eq, Show)

data Proof
  = WaitsEachLap
    -- ^ every lap round the cycle passes a continuation that waits for an
    -- event, which it consumes, or for a deadline later than the last one
  | Structural Int
    -- ^ every call passes a part of what it was given: the parameter at this
    -- position of the first member (see Note [The function checks])
  | Countdown Int
    -- ^ self-recursion on a number that moves by a positive literal towards
    -- a literal bound it is tested against: the parameter at this position
  deriving stock (Eq, Show)

data Doubt
  = NoMeasure
    -- ^ self-recursion, and neither function check applies
  | Mutual
    -- ^ definitions that call each other with no continuation between: v1
    -- does not try
  | Stalled [Stall]
    -- ^ some lap passes only continuations that need not wait; these are why
  | Untraced
    -- ^ a member uses a function no edge follows (Note [What the graph
    -- cannot see]), so the cycle the graph shows may not be the only one
  deriving stock (Eq, Show)

-- | Why a continuation on a lap cannot be shown to wait.
data Stall
  = NotAfterArming Rational
    -- ^ the deadline falls this long after the arming, which is not after it:
    -- @WITHIN 0@ or less, an @AFTER@ below 0 beside a bare @WITHIN@, or @OF
    -- THE DEADLINE@ of such a deadline. It does not move
  | WithinNotLiteral
    -- ^ a @WITHIN@ that is not a number written out: it may shrink (a Zeno
    -- chain) or be zero
  | AnchoredAtInstant
    -- ^ @WITHIN d OF e@: counted from a fixed instant, so already past once
    -- the trace has passed it
  | AnchoredAtJoin
    -- ^ @WITHIN d OF THE JOIN@: not shown either way
  | AnchoredAtDeadline
    -- ^ @OF THE DEADLINE@ where the obligation that will hand this one on is
    -- not the one written around it: the deadline is the hand-off's, read
    -- when it hands on (see Note [What makes a lap wait])
  | OpensNotLiteral
    -- ^ @AFTER@ a date, or a number not written out, beside a bare @WITHIN@:
    -- the window may open at a fixed instant
  | BeforeDate
    -- ^ @BEFORE date@: an instant, already past once the trace has passed it
  | RecordHence
    -- ^ a @RECORD@'s @HENCE@ runs at once
  | BarrierMayBeEmpty
    -- ^ an @EVERY … ONCE ALL HAVE@ @HENCE@ whose roll is not shown to have a
    -- member: a list written out (or a name for one) holding a member built
    -- by the cast's constructor, with no @WHO@ or @WHOSE@ filter. Over an
    -- empty roll it runs at once
  | OwnTrace
    -- ^ the module may run a contract inside an @EVALTRACE@, which runs it on
    -- a trace of its own from that trace's start: no wait, on either trace,
    -- bounds how deep the runs nest (Note [What makes a lap wait])
  deriving stock (Eq, Ord, Show)

data Fan = Fan Int | Unbounded
  deriving stock (Eq, Ord, Show)

-- | Every cycle in the module, with its verdict. Definitions are told apart by
-- their resolved 'Unique', so overloads that share a name are separate nodes.
-- @expand@ applies the module's final substitution: the types the checker
-- records on names still hold inference variables until it is applied. The
-- entity table is the checker's, for what a type named in one holds.
cycleFindings :: (Type' Resolved -> Type' Resolved) -> EntityInfo -> Module Resolved -> [Finding]
cycleFindings = cycleFindingsWith libraryFile

-- | 'cycleFindings', naming the library files a callee may be trusted from
-- (Note [Trusting a callee]): 'libraryFile', or 'apiLibraryFile' for the API's
-- pipeline.
cycleFindingsWith :: (NormalizedUri -> Maybe Text) -> (Type' Resolved -> Type' Resolved) -> EntityInfo -> Module Resolved -> [Finding]
cycleFindingsWith library expand info m@(MkModule _ uri _) = map judge sccs
 where
  trust = moduleTrust library info m
  holds = holdsContract info
  -- may hold an obligation once instantiated: a type variable might be one
  mayHold = maybe False (\ t -> holds t || hasVariable t)
  hasVariable = variableIn (\ n -> Set.member (getUnique n) typeParams || isTypeVariable n)
  isTypeVariable n = case Map.lookup (getUnique n) info of
    Just (_, KnownTypeVariable) -> True
    _ -> Set.member (getUnique n) declarationParams
  typeParams = Set.fromList [getUnique n | d <- decides, (n, Just (Type _)) <- decideParams d]
  -- the parameters of the types declared in scope: a selector's type, read
  -- past its record (@a -> a@ for @run@ of @Wrap a@), still names them
  declarationParams = Set.fromList [getUnique p | (_, KnownType _ ps _) <- Map.elems info, p <- ps]
  nameType b = asum
    [ expand <$> inferredType b
    , case Map.lookup (getUnique b) info of
        Just (_, KnownTerm t _) -> Just t
        _ -> Nothing ]
  -- the names that may carry an obligation into a call: every parameter, and
  -- every section GIVEN a WITH supplies, whose type may hold one
  carriers = Map.fromList $
    [(getUnique n, Fan 1) | d <- decides, (n, ty) <- paramTypes expand d, mayHold ty]
      <> [ (getUnique b, Fan 1)
         | d <- decides, AppNamed _ _ nes order <- universeExpr (bodyOf d)
         , (b, _) <- supplied nes order, mayHold (nameType b) ]
  decides = moduleDecides m
  defs = Map.fromList [(getUnique (decideName d), d) | d <- decides]
  -- whether the module may run a contract on a trace of its own anywhere
  -- (Note [What makes a lap wait]): it names a 'restarter', in a definition,
  -- a declaration or a directive
  restartsHere = any restarter (toList m)
  -- a name whose value may run a contract on a trace of its own: EVALTRACE;
  -- a name from another module whose declared type carries a function with a
  -- parameter that holds an obligation (a function whose parameters hold
  -- none cannot run what it is given as a contract, and cannot name this
  -- module's cycle); and a name of this module whose type carries a function
  -- that may take or give one, since what is supplied for it may be
  -- EVALTRACE or wrap the cycle in one. "Carries" reads through synonyms,
  -- type arguments, record fields and functions that return functions
  -- ('carriesFunction').
  restarter r
    | u == evalContractUnique = True
    | Map.member u defs || u.moduleUri == builtinUri = False
    | kind == Just Constructor = False
    | u.moduleUri /= uri = maybe False (carriesFunction info (takes holds) . field) declared
    | otherwise = any (carriesFunction info (touches (mayHold . Just)) . field) (catMaybes [expand <$> inferredType r, declared])
   where
    u = getUnique r
    declared = case Map.lookup u info of
      Just (_, KnownTerm t _) -> Just t
      _ -> Nothing
    kind = asum
      [ case infoOf r of
          Just (TypeInfo _ k) -> k
          _ -> Nothing
      , case Map.lookup u info of
          Just (_, KnownTerm _ k) -> Just k
          _ -> Nothing ]
    -- a selector only projects: what it gives is its field, and the record
    -- is a name of its own
    field t
      | kind == Just Selector = afterRecord t
      | otherwise = t
    afterRecord = \ case
      Forall _ _ t -> afterRecord t
      Fun _ _ t -> t
      t -> t
  -- a member that uses a function no edge follows (Note [What the graph
  -- cannot see]): the value of a field that holds a function (a projection,
  -- a selector applied, a name a constructor's pattern binds); and, where
  -- some type in scope holds a function that takes or gives that type again,
  -- any function the body names that is not a definition (a parameter, or a
  -- name a lambda or a pattern binds), since it may be such a field's value
  -- handed in
  untracedIn d = any fieldFunction body || (selfHolding && any localFunction body)
   where
    body = universeExpr (bodyOf d)
  fieldFunction = \ case
    Proj _ _ l -> heldFunction l
    App _ l (_ : _) -> heldFunction l
    Consider _ _ brs -> any carries (catMaybes [nameType b | MkBranch _ (When _ pat) _ <- brs, b <- fieldBinders pat])
    _ -> False
  heldFunction l = storedField info l && maybe False (carries . fieldOf) (nameType l)
  localFunction = \ case
    App _ v _ -> isLocalName v && maybe False carries (nameType v)
    AppNamed _ v _ _ -> isLocalName v && maybe False carries (nameType v)
    _ -> False
  isLocalName v =
    let u = getUnique v
    in u.moduleUri == uri && Map.notMember u defs
         && termKind v `notElem` map Just [Constructor, Selector, ComputedSelector, Assumed]
  termKind v = asum
    [ case infoOf v of
        Just (TypeInfo _ k) -> k
        _ -> Nothing
    , case Map.lookup (getUnique v) info of
        Just (_, KnownTerm _ k) -> Just k
        _ -> Nothing ]
  carries = carriesFunction info (\ _ _ -> True)
  -- some type the module can see holds a function whose parameters or
  -- result hold that type again: the only way to build a loop that names
  -- no definition is to apply such a function to such a value
  selfHolding = or
    [ lookIntoDeclaration info (holdsAgain u) u
    | (u, (_, KnownType {})) <- Map.toList info ]
  holdsAgain u = \ case
    Fun _ args r -> any (lookInto info (mentions u)) (r : [t | MkOptionallyNamedType _ _ t <- args])
    _ -> False
  mentions u = \ case
    TyApp _ n _ -> getUnique n == u
    _ -> False
  -- of one function type: a parameter, or a parameter or the result
  takes p args _ = any p args
  touches p args r = any p args || p r
  (bursts, edges) = moduleGraph trust (readThrough m) m
  targets = Map.fromListWith Set.union [(e.from, Set.singleton e.to) | e <- edges]
  sccOf scc = Set.fromList (map (getUnique . decideName) scc)

  sccs = [scc | CyclicSCC scc <- stronglyConnComp
             [ (d, getUnique (decideName d), Set.toList (Map.findWithDefault Set.empty (getUnique (decideName d)) targets))
             | d <- decides ]]
  -- the cycles whose laps arm obligations, by their members
  arming = [sccOf scc | scc <- sccs, armsObligations scc]
  armsObligations scc =
    any (not . null . (.slots)) (internalOf (sccOf scc)) || any (returnsContract holds expand) scc
  internalOf ids = [e | e <- edges, Set.member e.from ids, Set.member e.to ids]
  reachable start = grow start (Set.toList start)
   where
    grow seen [] = seen
    grow seen (n : ns) =
      let new = [t | t <- Set.toList (Map.findWithDefault Set.empty n targets), not (Set.member t seen)]
      in grow (foldr Set.insert seen new) (new <> ns)

  judge scc = MkFinding
    { members = [(decideText d, decideLine d) | d <- scc]
    , kind = if obligation then ObligationCycle else FunctionCycle
    , verdict = v
    , fan = maximum (Fan 0 : accumulates : [fanOf mode defs 3 (Map.fromSet (const (Fan 1)) ids) (bodyOf d) | d <- scc])
    , nests = arms && any (\ other -> other /= ids && not (Set.disjoint other (reachable ids))) arming
    , multiplies = listToMaybe (mapMaybe (multiplication defs ids) bursts)
    }
   where
    ids = sccOf scc
    internal = internalOf ids
    obligation = any (not . null . (.slots)) internal
    arms = armsObligations scc
    mode = if arms then Arms else Evaluates
    -- an obligation handed on round the cycle in a parameter that each lap
    -- doubles (@x (k RAND k)@) multiplies however the cycle itself fans out:
    -- each value a member passes to a member, where the parameter (or the
    -- section GIVEN) may hold an obligation, weighed by how often it uses the
    -- names that carry one, through the WHERE, LET and CONSIDER names around
    -- the call
    accumulates
      | arms = maximum (Fan 0 : [handedOn carriers (bodyOf d) | d <- scc])
      | otherwise = Fan 0
    weigh = fanOf Arms defs 3
    handedOn env e = case e of
      App _ f es -> passed env f (zip (map (paramType f) [0 ..]) es) `max` deeper es
      AppNamed _ f nes order ->
        passed env f ([(paramType f k, x) | (k, x) <- named nes order] <> [(nameType b, x) | (b, x) <- supplied nes order])
          `max` deeper [x | MkNamedExpr _ _ x <- nes]
      Where _ body ds -> handedOn (localsWith weigh env ds) body
      LetIn _ ds body -> handedOn (localsWith weigh env ds) body
      Consider _ x brs ->
        handedOn env x `max` maximum (Fan 0 : [handedOn (boundBy (weigh env x) env lhs) b | MkBranch _ lhs b <- brs])
      _ -> deeper (kids e)
     where
      deeper = maximum . (Fan 0 :) . map (handedOn env)
    passed env f xs
      | Set.member (getUnique f) ids = maximum (Fan 0 : [weigh env x | (ty, x) <- xs, mayHold ty])
      | otherwise = Fan 0
    paramType f j = Map.lookup (getUnique f) defs >>= \ d -> join (snd <$> listToMaybe (drop j (paramTypes expand d)))
    open = filter (not . any cuts . (.slots)) internal
    unguarded = filter (null . (.slots)) open
    stalledOnCycle =
      nubOrd [s | e <- onCycles open, not (null e.slots), Stalls s <- e.slots]
    unguardedOnCycle = onCycles unguarded
    -- a lap that may run on a trace of its own waits on a clock that starts
    -- again, so no wait proves it. The function checks do not use time, so
    -- they prove only a cycle with no lap that waits: beside a self-call
    -- that counts down, a lap through a HENCE under EVALTRACE is not
    -- discharged by the countdown (every edge of the cycle lies on one of
    -- its laps)
    v
      | not (null stalledOnCycle) = Unproved (Stalled stalledOnCycle)
      | restartsHere, any (not . null . (.slots)) internal = Unproved (Stalled [OwnTrace])
      | any untracedIn scc = Unproved Untraced
      | null unguardedOnCycle = Proved WaitsEachLap
      | any (\ e -> e.from /= e.to) unguardedOnCycle =
          maybe (Unproved Mutual) Proved (descent trust info nullaries scc unguardedOnCycle)
      | otherwise = functionVerdict [d | d <- scc, getUnique (decideName d) `elem` map (.from) unguardedOnCycle] unguardedOnCycle

  -- the unguarded self-calls of each self-recursive member must all pass one
  -- check at one parameter position; the verdict names the first member's
  functionVerdict ds es = case mapMaybe (selfProof es) ds of
    proofs | length proofs == length ds, (p : _) <- proofs -> Proved p
    _ -> Unproved NoMeasure

  selfProof es d =
    let calls = [e | e <- es, e.from == getUnique (decideName d)]
    in asum [descent trust info nullaries [d] calls, countdown constants d calls]
  -- the bodies of the definitions that take no argument
  nullaries = Map.fromList [(getUnique (decideName d), bodyOf d) | d <- decides, null (valueParams d)]
  -- the definitions of the module that are a number written out
  constants = Set.fromList
    [getUnique (decideName d) | d <- decides, null (valueParams d), Lit _ NumericLit {} <- [bodyOf d]]

-- | The edges that lie on a cycle of the given edges: those whose target
-- reaches their source, which is a self-call or an edge inside one strongly
-- connected component. One pass over the edges; a search from each edge
-- would be quadratic in them, and reading names through multiplies the
-- edges (a name used 300 times for 300 calls is 90,000).
onCycles :: [Edge] -> [Edge]
onCycles es = filter on es
 where
  nodes = nubOrd (concat [[e.from, e.to] | e <- es])
  next = Map.fromListWith (<>) [(e.from, [e.to]) | e <- es]
  component = Map.fromList
    [ (n, i)
    | (i, CyclicSCC ns) <- zip [0 :: Int ..] (stronglyConnComp [(n, n, Map.findWithDefault [] n next) | n <- nodes])
    , n <- ns ]
  on e = e.from == e.to || maybe False (\ i -> Map.lookup e.to component == Just i) (Map.lookup e.from component)

-- | A short label to count findings by.
findingClass :: Finding -> Text
findingClass f =
  base <> times <> (if f.nests then "+nests" else "")
 where
  -- "+fans" is the fan count alone, high on purpose, which feeds no warning
  -- (Note [Fan-out]); "+multiplies" is the proof (Note [What multiplies])
  times
    | isJust f.multiplies = "+multiplies"
    | f.fan >= Fan 2 = "+fans"
    | otherwise = ""
  k = case f.kind of
    FunctionCycle -> "function"
    ObligationCycle -> "obligation"
  base = k <> ":" <> case f.verdict of
    Proved WaitsEachLap -> "proved-waits"
    Proved (Structural _) -> "proved-structural"
    Proved (Countdown _) -> "proved-countdown"
    Unproved NoMeasure -> "unproved-self"
    Unproved Mutual -> "unproved-mutual"
    Unproved (Stalled ss)
      | all isNotPositive ss -> "no-time"
      | otherwise -> "unproved-stall"
    Unproved Untraced -> "unproved-untraced"
  isNotPositive = \ case
    NotAfterArming _ -> True
    _ -> False

findingJSON :: Finding -> Aeson.Value
findingJSON f = Aeson.object
  [ "class" .= findingClass f
  , "members" .= [Aeson.object ["name" .= n, "line" .= l] | (n, l) <- f.members]
  , "verdict" .= Text.textShow f.verdict
  , "fan" .= case f.fan of
      Fan n -> Aeson.toJSON n
      Unbounded -> Aeson.String "unbounded"
  , "nests" .= f.nests
  , "warnings" .= map (Text.textShow) (alarms f)
  , "multiplies" .= fmap multiplicationJSON f.multiplies
  ]
 where
  multiplicationJSON x = Aeson.object
    [ "rule" .= x.rule
    , "line" .= fmap (\ r -> r.start.line) x.at
    , "operator" .= x.operator
    , "copies" .= x.copies
    , "via" .= Text.textShow x.via
    , "stepsDown" .= fmap fst x.stepsDown
    ]

------------------------------------------------------------------------
-- The graph
------------------------------------------------------------------------

-- | What one continuation between a definition's body and a reference waits
-- for before it runs (see Note [What makes a lap wait]).
data Slot
  = Waits
    -- ^ for an event, which it consumes, or a deadline that moves on
  | NeverRuns
    -- ^ a deadline-driven continuation with no deadline at all
  | Stalls Stall
  deriving stock (Eq, Ord, Show)

-- | When a deadline, or a window's opening, falls.
data When
  = Relative Rational
    -- ^ this long after the arming of the obligation that has it
  | Fixed Stall
    -- ^ not shown to move with the arming, and why
  | Nowhere
    -- ^ there is none

-- | A continuation driven by a deadline waits when the deadline falls a
-- positive amount after the arming.
slotOf :: When -> Slot
slotOf = \ case
  Relative r
    | r > 0 -> Waits
    | otherwise -> Stalls (NotAfterArming r)
  Fixed s -> Stalls s
  Nowhere -> NeverRuns

-- | The earlier of two deadlines, either of which fires the continuation.
earlier :: When -> When -> When
earlier a b = case (a, b) of
  (Nowhere, _) -> b
  (_, Nowhere) -> a
  (Fixed s, _) -> Fixed s
  (_, Fixed s) -> Fixed s
  (Relative x, Relative y) -> Relative (min x y)

-- | An offset counted from another instant.
plus :: When -> When -> When
plus a b = case (a, b) of
  (Relative x, Relative y) -> Relative (x + y)
  (Fixed s, _) -> Fixed s
  (_, Fixed s) -> Fixed s
  _ -> Fixed AnchoredAtDeadline

-- | Both must wait for the result to; a continuation that never runs leaves
-- the other.
both :: Slot -> Slot -> Slot
both a b = case (a, b) of
  (NeverRuns, _) -> b
  (_, NeverRuns) -> a
  (Stalls _, _) -> a
  (_, Stalls _) -> b
  (Waits, Waits) -> Waits

-- | A slot that a lap cannot pass round and round at one instant.
cuts :: Slot -> Bool
cuts = \ case
  Waits -> True
  NeverRuns -> True
  Stalls _ -> False

-- | One reference from a definition's body to a definition of the module.
data Edge = MkEdge
  { from  :: Unique
  , to    :: Unique
  , slots :: [Slot]
    -- ^ the continuations between the body and the reference, outermost first
  , args  :: [(Int, Expr Resolved)]
    -- ^ the arguments, by the callee's parameter position
  , conds :: [(Bool, Expr Resolved)]
    -- ^ the IF tests the reference sits under, each with the branch taken
  , elements :: [(Int, Expr Resolved)]
    -- ^ for a definition passed by name to a function that can hand it only
    -- the elements of a list (@map `the child and his descendants` xs@): the
    -- parameter position the elements go to, and the list
  }

-- | A continuation whose expression joins two or more calls of the module's
-- definitions with @RAND@ or @ROR@ (Note [What multiplies]).
data Burst = MkBurst
  { from     :: Unique
  , via      :: Continuation
  , operator :: Text
  , calls    :: [(Unique, [(Int, Expr Resolved)])]
    -- ^ each call, with its arguments by the callee's parameter position
  , at       :: Maybe SrcRange
  }

-- | The operands an expression joins with @RAND@ and @ROR@, and the operators
-- that join them.
operands :: Expr Resolved -> (Text, [Expr Resolved])
operands x = (spell (nubOrd (ops x)), leaves x)
 where
  ops = \ case
    RAnd _ a b -> "RAND" : ops a <> ops b
    ROr _ a b -> "ROR" : ops a <> ops b
    _ -> []
  leaves = \ case
    RAnd _ a b -> leaves a <> leaves b
    ROr _ a b -> leaves a <> leaves b
    e -> [e]
  spell = \ case
    [o] -> o
    _ -> "RAND and ROR"

-- | An operand that is a call: the name called, and its arguments by the
-- callee's parameter position.
directCall :: Expr Resolved -> Maybe (Resolved, [(Int, Expr Resolved)])
directCall = \ case
  App _ f es -> Just (f, zip [0 ..] es)
  AppNamed _ f nes order -> Just (f, named nes order)
  _ -> Nothing

-- | A continuation of a member that starts two or more copies of the cycle at
-- once: two or more of the calls it joins are of members.
multiplication :: Map Unique (Decide Resolved) -> Set Unique -> Burst -> Maybe Multiplication
multiplication defs ids b
  | Set.member b.from ids, length inCycle >= 2, Just d <- Map.lookup b.from defs =
      Just MkMultiplication
        { rule = decideText d
        , at = b.at
        , operator = b.operator
        , copies = length inCycle
        , via = b.via
        , stepsDown = steps d
        }
  | otherwise = Nothing
 where
  inCycle = [c | c@(u, _) <- b.calls, Set.member u ids]
  -- every copy is the rule itself, passed one parameter less the same
  -- positive number written out
  steps d = case nubOrd (map (step d) inCycle) of
    [Just (k, r)] | Just p <- listToMaybe (drop k (valueParams d)) ->
      Just (unqualifiedNameToText (getOriginal p), r)
    _ -> Nothing
  step d (u, as)
    | u /= b.from = Nothing
    | otherwise = listToMaybe
        [ (k, r)
        | (k, p) <- zip [0 ..] (valueParams d)
        , Just x <- [lookup k as]
        , Just (OpMinus, App _ v [], Lit _ (NumericLit _ r)) <- [binary x]
        , getUnique v == getUnique p, r > 0 ]

-- | Every definition of the module: top-level, in sections, and every
-- WHERE\/LET definition inside them but the ones a definition written as
-- clauses is compiled to (@the result of clause 2@, marked 'PmSynthetic').
-- Those are part of the definition they were written in: the walk reads each
-- one's body where it is bound, so a definition written as clauses is one
-- node, as it is one rule to its author.
moduleDecides :: Module Resolved -> [Decide Resolved]
moduleDecides m = moduleTops m <> moduleLocals m

-- | The top-level definitions, in sections or not.
moduleTops :: Module Resolved -> [Decide Resolved]
moduleTops (MkModule _ _ sec) = sectionDecides sec
 where
  sectionDecides (MkSection _ _ _ _ tds) = concatMap topDecides tds
  topDecides = \ case
    Decide _ d -> [d]
    Section _ s -> sectionDecides s
    _ -> []

-- | Every WHERE\/LET definition inside a top-level one, at any depth, but the
-- bindings a clause group was compiled to.
moduleLocals :: Module Resolved -> [Decide Resolved]
moduleLocals m = filter (not . clausePart) (concatMap locals (moduleTops m))
 where
  locals d = [ld | e <- universeExpr (bodyOf d), ld <- localDecides e]
  localDecides = \ case
    Where _ _ ds -> [d | LocalDecide _ d <- ds]
    LetIn _ ds _ -> [d | LocalDecide _ d <- ds]
    _ -> []

-- | The WHERE and LET definitions that take no argument, each with its body:
-- the cycle check reads each one wherever it is named (Note [A name for an
-- expression]). Left out, and so kept as a definition of its own, whose
-- cycle is reported as it is written: one that reaches itself through
-- others of its kind (@ones MEANS 1 FOLLOWED BY ones@, or two that name each
-- other); and one that, with the names in it read through in turn, is
-- longer than 'readThroughLimit' expressions.
readThrough :: Module Resolved -> Map Unique (Expr Resolved)
readThrough m = Map.filterWithKey (\ u _ -> Map.findWithDefault (readThroughLimit + 1) u sizes <= readThroughLimit) acyclic
 where
  candidates = Map.fromList [(getUnique (decideName d), bodyOf d) | d <- moduleLocals m, null (valueParams d)]
  namedIn b = [u | r@Ref {} <- toList b, let u = getUnique r, Map.member u candidates]
  -- dependencies first ('stronglyConnComp' sorts in reverse topological
  -- order), so each size is known before a name that reads it
  order = stronglyConnComp [(u, u, namedIn b) | (u, b) <- Map.toList candidates]
  acyclic = Map.restrictKeys candidates (Set.fromList [u | AcyclicSCC u <- order])
  sizes = foldl' measure Map.empty [u | AcyclicSCC u <- order]
  measure done u = case Map.lookup u candidates of
    Just b -> Map.insert u (min (readThroughLimit + 1)
      (length (universeExpr b) + sum [Map.findWithDefault (readThroughLimit + 1) v done | v <- namedIn b])) done
    Nothing -> done

-- | How long, in expressions, a name read through may be, with the names in
-- it read through in turn: a bound on the walk, which reads a name's body
-- once for every place it is named.
readThroughLimit :: Int
readThroughLimit = 2000

-- | A binding a definition written as clauses was compiled to.
clausePart :: Decide Resolved -> Bool
clausePart d = isJust (view annPmSynthetic (getAnno d))

-- | Every reference from a definition of the module to another (or itself),
-- each labelled. A WHERE\/LET definition's body is walked as its own node, not
-- as part of the body that holds it.
--
-- Every definition is a node of its own here, the names 'readThrough' gives
-- included, so that 'plainReferences' is a check of the walk alone.
moduleEdges :: EntityInfo -> Module Resolved -> [Edge]
moduleEdges info m = snd (moduleGraph (moduleTrust libraryFile info m) Map.empty m)

-- | The edges, and every continuation whose expression joins two or more
-- calls of the module's definitions (Note [What multiplies]). The names in
-- @through@ are not nodes: each is read, wherever it is named, as its body
-- (Note [A name for an expression]).
moduleGraph :: Trust -> Map Unique (Expr Resolved) -> Module Resolved -> ([Burst], [Edge])
moduleGraph trust through m =
  partitionEithers (concatMap edgesOf [d | d <- decides, not (Map.member (getUnique (decideName d)) through)])
 where
  decides = moduleDecides m
  nodes = Set.fromList [u | d <- decides, let u = getUnique (decideName d), not (Map.member u through)]
  numbers = Map.fromList
    [ (getUnique (decideName d), r)
    | d <- decides, null (valueParams d), Lit _ (NumericLit _ r) <- [bodyOf d] ]
  -- the bodies of the definitions that take no argument, for reading a roll
  -- or a member written as a name
  nullary = Map.fromList
    [(getUnique (decideName d), bodyOf d) | d <- decides, null (valueParams d)]

  edgesOf d = go Nothing [] [] (bodyOf d)
   where
    self = getUnique (decideName d)
    -- od: when the deadline of the obligation that hands this value on falls
    -- (for OF THE DEADLINE), when that is the obligation written around it.
    -- It passes only to where the value handed on is still this expression's
    -- own result: IF and CONSIDER branches, a WHERE or LET body, RAND and ROR
    -- operands. Anywhere else (an argument, a scrutinee, a function value) the
    -- obligation is handed on by whatever receives it, so it is Nothing.
    go :: Maybe When -> [Slot] -> [(Bool, Expr Resolved)] -> Expr Resolved -> [Either Burst Edge]
    go od ss cs e = case e of
      -- a name for an expression is read where it is named, under the tests
      -- and continuations around that place
      App _ f es
        | Just b <- Map.lookup (getUnique f) through ->
            go (if null es then od else Nothing) ss cs b <> concatMap (go Nothing ss cs) es
      App _ f es ->
        let byName =
              [ (i, g, q, x)
              | (i, q, j) <- trust.elementsOf f (length es)
              , App _ g [] <- take 1 (drop i es), Set.member (getUnique g) nodes
              , x <- take 1 (drop j es) ]
            named' = Set.fromList [i | (i, _, _, _) <- byName]
        in ref f (zip [0 ..] es)
             <> concat [refElements g [(q, x)] | (_, g, q, x) <- byName]
             <> concat [go Nothing ss cs x | (i, x) <- zip [0 ..] es, not (Set.member i named')]
      AppNamed _ f nes order ->
        ref f (named nes order) <> concat [go Nothing ss cs x | MkNamedExpr _ _ x <- nes]
      -- a projection onto a computed field calls the selector the field's
      -- MEANS was turned into ('L4.Desugar.desugarComputedFields')
      Proj _ x l -> ref l [(0, x)] <> go Nothing ss cs x
      IfThenElse _ c t f ->
        go Nothing ss cs c <> go od ss ((True, c) : cs) t <> go od ss ((False, c) : cs) f
      MultiWayIf _ gs other ->
        let tests = [g | MkGuardedExpr _ g _ <- gs]
            failed n = [(False, g) | g <- take n tests]
        in concat
             [ go Nothing ss cs g <> go od ss ((True, g) : failed i <> cs) b
             | (i, MkGuardedExpr _ g b) <- zip [0 ..] gs ]
             <> go od ss (failed (length tests) <> cs) other
      Consider _ x brs ->
        go Nothing ss cs x
          <> concat [concatMap (go Nothing ss cs) (kids lhs) <> go od ss cs b | MkBranch _ lhs b <- brs]
      RAnd _ a b -> go od ss cs a <> go od ss cs b
      ROr _ a b -> go od ss cs a <> go od ss cs b
      Regulative _ dn -> deonton od ss cs dn
      Record _ recipient cell value _ mhence ->
        concatMap (go Nothing ss cs) (maybeToList recipient <> [cell, value])
          <> foldMap (go Nothing (ss <> [Stalls RecordHence]) cs) mhence
          <> foldMap (burst (Stalls RecordHence) AfterRecord) mhence
      Where _ body _ -> go od ss cs body
      -- the bindings a clause group was compiled to are read where they are
      -- bound: each stands for the clauses after one, so its value is this
      -- expression's own result
      LetIn _ ds body ->
        concat [go od ss cs (bodyOf ld) | LocalDecide _ ld <- ds, clausePart ld] <> go od ss cs body
      _ -> concatMap (go Nothing ss cs) (kids e)
     where
      -- what the checks read of a call, its arguments and the tests above
      -- it, is read through the names in it, as the walk reads them
      ref f xs
        | Set.member (getUnique f) nodes =
            [Right MkEdge {from = self, to = getUnique f, slots = ss, args = readArgs xs, conds = readConds, elements = []}]
        | otherwise = []
      refElements g xs =
        [Right MkEdge {from = self, to = getUnique g, slots = ss, args = [], conds = readConds, elements = readArgs xs}]
      readArgs xs = [(k, expandNames through x) | (k, x) <- xs]
      readConds = [(b, expandNames through c) | (b, c) <- cs]

    -- a continuation that runs at all, whose expression joins two or more
    -- calls of the module's definitions
    burst slot via x = case operands x of
      (ops, xs)
        | NeverRuns <- slot -> []
        | length calls >= 2 ->
            [Left MkBurst {from = self, via = via, operator = ops, calls = calls, at = (getAnno x).range}]
        | otherwise -> []
       where
        calls = [(getUnique f, as) | o <- xs, Just (f, as) <- [directCall (readName o)], Set.member (getUnique f) nodes]
        -- an operand that is a name read through is the call its body is,
        -- as it was when the name was a member of the cycle of its own; the
        -- RAND or ROR inside such a body is not read (Note [What multiplies])
        readName = \ case
          App _ v [] | Just b <- Map.lookup (getUnique v) through -> readName b
          o -> o

    deonton od ss cs (MkDeonton _ subj act opens due jn hence lest) =
      concatMap (go Nothing ss cs) (kids subj <> kids act <> kids opens <> kids due <> kids jn)
        <> foldMap (go (Just deadline) (ss <> [henceSlot]) cs) hence
        <> foldMap (go (Just deadline) (ss <> [lestSlot]) cs) lest
        <> foldMap (burst henceSlot (HenceOf act.modal)) hence
        <> foldMap (burst lestSlot (LestOf act.modal)) lest
     where
      -- a barrier's join can carry its own deadline beside its members': the
      -- earlier one fires the continuation
      deadline = earlier (timing od (opening od opens) due) joined
      joined = timing od (Relative 0) (joinDeadline jn)
      (actHence, actLest) = case act.modal of
        DMustNot -> (slotOf deadline, mustNotLest)
        _ -> (Waits, slotOf deadline)
      -- a barrier's prohibition also goes to its LEST, with no event, when
      -- the ONCE line's deadline passes ('barrierStateMissed' in the machine)
      mustNotLest = case subj of
        Every {} -> both Waits (slotOf joined)
        Party {} -> Waits
      (henceSlot, lestSlot) = case subj of
        Party {} -> (actHence, actLest)
        Every _ cast _ roll filt -> case jn of
          Just JoinUpon {} -> (actHence, actLest)
          _ | isNothing filt, hasMember cast roll -> (actHence, actLest)
            | otherwise -> (Stalls BarrierMayBeEmpty, actLest)

    -- the roll is a list written out (or a name for one) with a member built
    -- by the cast's constructor, when there is a cast; a WHO or WHOSE filter
    -- could still leave it empty, so a filtered barrier never counts
    hasMember cast roll = case roll >>= written of
      Just (List _ xs) -> any (builtBy (3 :: Int) cast) xs
      _ -> False
    written = \ case
      App _ f [] -> Map.lookup (getUnique f) nullary
      x -> Just x
    builtBy depth cast x = case (cast, x) of
      (Nothing, _) -> True
      (Just c, App _ k _) | getUnique k == getUnique c -> True
      (Just _, App _ v []) | depth > 0, Just b <- Map.lookup (getUnique v) nullary -> builtBy (depth - 1) cast b
      _ -> False

    -- when a deadline falls, measured from the arming. A bare WITHIN counts
    -- from the window's opening (the AFTER, when there is one; Machine.hs,
    -- Contract5), and OF THE DEADLINE from the deadline of the obligation it
    -- continues, itself measured from that one's arming, which is no earlier
    -- than the lap's.
    timing od opened = \ case
      Nothing -> Nowhere
      Just MkBefore {} -> Fixed BeforeDate
      Just (MkDeadline _ e anchor) -> case anchor of
        Just AnchorAt {} -> Fixed AnchoredAtInstant
        Just AnchorJoin {} -> Fixed AnchoredAtJoin
        Just AnchorDeadline {} -> plus (within e) (outer od)
        Just AnchorArming {} -> within e
        Nothing -> plus (within e) opened
    within e = maybe (Fixed WithinNotLiteral) Relative (number e)
    opening od = \ case
      Nothing -> Relative 0
      Just (MkOpening _ off anchor) -> case anchor of
        Just AnchorAt {} -> Fixed AnchoredAtInstant
        Just AnchorJoin {} -> Fixed AnchoredAtJoin
        Just AnchorDeadline {} -> plus (after off) (outer od)
        _ -> after off
    after off = maybe (Fixed OpensNotLiteral) Relative (number off)
    outer = \ case
      Just (Relative o) -> Relative o
      Just (Fixed s) -> Fixed s
      _ -> Fixed AnchoredAtDeadline

    number = \ case
      Lit _ (NumericLit _ r) -> Just r
      App _ f [] -> Map.lookup (getUnique f) numbers
      _ -> Nothing


joinDeadline :: Maybe (Join Resolved) -> Maybe (Deadline Resolved)
joinDeadline = \ case
  Just (JoinOnce _ _ d) -> d
  Just (JoinUpon _ _ d) -> d
  Nothing -> Nothing

-- | The references the labelled walk must find: every 'Ref' to a definition of
-- the module in a top-level body (WHERE\/LET bodies included), as a multiset.
-- CyclesSpec checks that 'moduleEdges' finds exactly these, so a reference the
-- walk skips (in a roll, a filter, a deadline) is a test failure, not a
-- silently missing edge.
plainReferences :: Module Resolved -> [Unique]
plainReferences m@(MkModule _ _ sec) =
  sort [u | d <- topLevel sec, r@Ref {} <- toList (bodyOf d), let u = getUnique r, Set.member u nodes]
 where
  nodes = Set.fromList (map (getUnique . decideName) (moduleDecides m))
  topLevel (MkSection _ _ _ _ tds) = concat
    [ case td of
        Decide _ d -> [d]
        Section _ s -> topLevel s
        _ -> []
    | td <- tds ]

------------------------------------------------------------------------
-- Note [What makes a lap wait]
------------------------------------------------------------------------
-- A lap round a cycle that passes a continuation which WAITS cannot repeat at
-- one instant: an event continuation consumes the event that fires it, and a
-- trace has finitely many; a deadline continuation whose deadline moves on by
-- a positive amount each lap is bounded by the trace's end. Which continuation
-- waits for which, by modal, was measured on self-loops, one per kind
-- (2026-11-20, on the layer-1 binary; #1075):
--
--   * waits for an event: the HENCE of MUST, DO and MAY (performed); the LEST
--     of MUST NOT (broken; the breaking event is consumed, not re-offered);
--     an UPON EACH HENCE; a barrier HENCE over a roll shown to have a member
--     (see 'BarrierMayBeEmpty').
--   * waits for a deadline: the LEST of MUST, DO and MAY; the HENCE of MUST
--     NOT; the LEST of an EVERY … MUST NOT whose ONCE line has a deadline
--     (when that passes the barrier goes to its LEST with no event). The
--     deadline moves on only if it falls a positive amount after the lap's
--     arming: WITHIN a positive number written out (or a name defined as
--     one), unanchored, OF THE ARMING, or OF THE DEADLINE of an obligation
--     whose own deadline moves on. A bare WITHIN beside an AFTER counts from
--     the window's opening, so the AFTER must also be a number written out,
--     not below 0, unanchored, OF THE ARMING or OF such a deadline.
--     WITHIN 0, OF e, BEFORE date, AFTER 2 OF 0, AFTER -5, a cure period
--     WITHIN 5 OF THE DEADLINE of a BEFORE date, and an EVERY … MUST NOT
--     whose ONCE line says WITHIN 0, all stalled or overflowed; a WITHIN that
--     halves each lap ran out of memory.
--   * never runs: a deadline continuation with no deadline at all.
--   * runs at once: a RECORD's HENCE; a barrier HENCE over an empty roll.
--
-- Waiting bounds the laps by the trace's span over the smallest step, which
-- can still be large: a trace 10 long with WITHIN 0.000001 is 10^7 laps, past
-- the frame-depth guard's 10^6, which stops it (measured 2026-11-20).
--
-- THE DEADLINE (and THE ARMING, THE JOIN) name the obligation that HANDS the
-- value on, read when it hands it on ('bindLifecycle' and 'rebindLifecycle'
-- in the machine), not the obligation written around it. They are the same
-- only where the value handed on is the continuation's own result: through an
-- IF or CONSIDER branch, a WHERE or LET body, or a RAND or ROR operand, each
-- measured (2026-11-20: @OF THE DEADLINE@ under @WITHIN 0@ through each ran to
-- a value). An obligation written as an argument to a helper is handed on by
-- the helper's obligation instead: @WITHIN 1 OF THE DEADLINE@ passed to a
-- helper whose own deadline is @WITHIN 1 OF 0@ re-armed the lap at instant 2
-- and was stopped by the stall guard. So an OF THE DEADLINE anywhere else
-- counts as 'AnchoredAtDeadline', and so does one in a definition's body,
-- whose hand-off is whoever names it.
--
-- EVALTRACE runs a contract on a trace of its own, from that trace's start. A
-- lap that passes through one starts again however long either trace waited,
-- and an event it consumed may be on the next run's trace again. Measured
-- (2026-11-20, second and third adversarial passes), each stopped by the
-- frame-depth guard, the thunk loop check or the stall guard: the wait
-- outside the EVALTRACE (@… WITHIN 1 LEST (EVALTRACE x 0 …)@) or inside it
-- (@x MEANS EVALTRACE (… WITHIN 1 LEST x) 0 …@); the wait in another member
-- of the cycle; an event continuation whose event each run supplies again;
-- EVALTRACE inside a helper; and EVALTRACE passed to a helper as a function.
-- Marking the cycle's members was not enough either: the fourth pass reached
-- EVALTRACE through a function typed by a synonym, a function another
-- function returns, and a function carried in a pair or a record, each
-- stopped by the frame-depth guard.
--
-- So the report does not look for the path. A module that names anything
-- that may run a contract on a trace of its own ('restarter'), anywhere (in
-- a definition, a declaration or a directive), has no cycle proved by
-- waiting ('OwnTrace'), whichever edge waits. That is coarse on purpose. It
-- counts EVALTRACE; a name of this module (a parameter, a local, a field, an
-- assumption) whose type carries a function that takes or gives something
-- that may hold an obligation, since what is supplied for it may be
-- EVALTRACE or wrap the cycle in one (measured: @x f n MEANS … LEST ((f n)
-- RAND x f (n PLUS 1))@ with @f@ a definition that EVALTRACEs @x@ was stopped
-- by the frame-depth guard); and a name from another module whose declared
-- type carries a function that takes an obligation. "Carries" reads through
-- synonyms, type arguments, record fields and returned functions
-- ('carriesFunction'). A function from another module that takes no
-- obligation by its declared type is not counted, even where it is
-- instantiated at one (a polymorphic @same v MEANS v@): it cannot run what it
-- is given as a contract, it cannot name this module's cycle, and a function
-- handed to it to do so is named here. An OBLIGATION handed in from another
-- module that wraps the cycle in EVALTRACE is not counted either: to recur
-- it must name itself, so it is a cycle of its own, reported as one there.
-- What this still trusts is the type test, and one escape from it is
-- measured: a function whose type touches no obligation can still run the
-- cycle under EVALTRACE inside itself. With @x f n MEANS … LEST (IF f n THEN
-- x f (n PLUS 1) ELSE FULFILLED)@, @f@ typed @FUNCTION FROM NUMBER TO
-- BOOLEAN@, and @g n MEANS (EVALTRACE (x g n) 0 …) EQUALS FULFILLED@ supplied
-- for it from a module that imports @x@'s, @x@'s module proves @x@ by waiting
-- and the run is stopped by the frame-depth guard (2026-11-20). The loop is
-- @g@'s, and where @g@ names itself to recur, the importing module reports it
-- as an unproved cycle; in the one-module form, the run failed with the same
-- counters when @x@'s call to itself was removed. (In one module the
-- module-wide rule above catches it.) But @g@ need not name itself: through
-- a function held in a field of a type that holds a function of itself, no
-- module reports a cycle. With @DECLARE Box HAS check IS A FUNCTION FROM Box
-- AND NUMBER TO BOOLEAN@, @x b n MEANS … LEST (IF c b n THEN FULFILLED ELSE
-- FULFILLED) WHERE c MEANS b's check@ (which does not call itself), and, in
-- the importing module, @h bx n MEANS (EVALTRACE (x bx n) 0 …) EQUALS
-- FULFILLED@ with @theBox MEANS Box OF h@ traced from @x theBox 0@, neither
-- module has a cycle and the run is stopped by the frame-depth guard
-- (2026-11-21 attack round, obligations t8). Where such a cycle has a member
-- that uses the field, the cycle is not proved (Note [What the graph cannot
-- see]); where it has none, as here, nothing reports it.
--
-- The module-wide rule is a backstop, not something a finding forced: in
-- each shape the fourth pass confirmed, the cycle's own member names the
-- function that hides EVALTRACE, so following references from the members
-- would have caught all five once the type test read through them. It was
-- fixed before that pass ran, as the alternative to a fifth one. Its measured
-- cost: a module that runs its own waiting cycle under EVALTRACE elsewhere
-- loses that cycle's proof. The function checks do not use time, so they
-- still prove what they prove.
--
-- An edge is cut if any continuation between its definition's body and the
-- reference waits or never runs. A cycle is PROVED (it waits each lap) when
-- the edges that are not cut contain no cycle, and otherwise UNPROVED with the
-- reasons found on the uncut cycle's continuations, or with the function
-- checks' verdict when that cycle passes no continuation at all.

------------------------------------------------------------------------
-- Note [What the graph cannot see]
------------------------------------------------------------------------
-- An edge exists only where a body names a definition (a projection onto a
-- computed field names its selector). Recursion that names none is not
-- reported: a function held in a record field and applied to the record
-- (@loop r MEANS apply (r's f) r@ over @Rec WITH f IS loop@), a recursive
-- type whose field is a function from that type, and an obligation COMMITted
-- to the ledger and RECALLed in a LEST. Measured 2026-11-20 on the layer-1
-- binary: the obligation forms, written with WITHIN 0, were stopped by the
-- stall guard in under a second; the function forms ran to a 30-second
-- timeout. The run-time guards (layer 1, the stall guard, the frame-depth
-- guard) are what stop these.
--
-- Such a loop can run beside a cycle the graph does see, and then a proof of
-- that cycle is a false one: with @f n w MEANS CONSIDER n WHEN Zero THEN 0
-- WHEN Suc k THEN (apply (w's run) w) PLUS f k w@ and @w@ built as @Wrap
-- WITH run IS (GIVEN v YIELD f one v)@, the call @f k w@ descends, and the
-- run overflows the frame-depth guard through @w's run@ (2026-11-21 attack
-- round, mutual p10; likewise a cycle proved by waiting whose member calls a
-- function held in a record of a type that holds a function of itself,
-- obligations t2). So a cycle is not proved ('Untraced', which warns "could
-- not check") when one of its members uses
--
--   * the value of a field that holds a function: a projection onto it, its
--     selector applied, or a name a constructor's pattern binds to it; or
--   * where some type in scope holds a function whose parameters or result
--     hold that type again, any function the body names that is not a
--     definition: a parameter, or a name a lambda or a pattern binds. That
--     is the only way to build a loop that names no definition, and the
--     field's value can be handed in from outside the cycle, or caught in a
--     lambda that is.
--
-- Decided by Claude 2026-11-21, pending Meng's review, on the attack
-- round's report. Its cost in proofs, measured on 2026-11-21 by `l4 check` over
-- every tracked .l4 file (1,584 modules, the libraries included) with this
-- rule and with it switched off: none. No cycle there changes class; the
-- attack round's p10 does, as a control that the switch took.

------------------------------------------------------------------------
-- Note [Fan-out]
------------------------------------------------------------------------
-- A cycle that waits each lap can still multiply: @x MEANS … LEST (x RAND x)@
-- starts two copies of itself each lap. Fan-out counts the references to the
-- cycle that one pass through a body can make: RAND, ROR and arguments add;
-- IF, CONSIDER and a multi-way IF take their largest branch; an obligation
-- takes the larger of its HENCE and LEST; an UPON EACH continuation that
-- reaches the cycle counts as unbounded, one copy per member. ROR is counted
-- like RAND although only one side may matter, so the count may be high, never
-- low. It is a count for the report and feeds no warning: it is high on
-- purpose, and a warning that cannot be silenced needs a proof (Note [What
-- multiplies]).
--
-- An obligation runs once for every place it is used, so in a cycle whose laps
-- arm obligations (an obligation cycle, or a function cycle that returns one,
-- or a record, a list or a synonym that holds one: 'holdsContract') a name
-- that stands for one counts once per use:
--
--   * an argument to the module's own helper counts as many times as the
--     helper uses that parameter, three helpers deep (@twice k MEANS k RAND
--     k@ doubles @x … LEST (twice x)@), and as unbounded when the helper is
--     not the module's own; a section GIVEN supplied by WITH counts as often
--     as the helper names it;
--   * a WHERE or LET name, and a name bound by a CONSIDER pattern, counts as
--     often as the expression it names, whichever order the WHERE names come
--     in;
--   * an obligation handed round the cycle in a parameter, or a section
--     GIVEN, that a lap doubles (@x (k RAND k)@, or @k@ named twice through a
--     WHERE name, or held twice in a record) multiplies however the cycle
--     itself fans out. A parameter typed by a type variable counts here, since
--     it may be one.
--
-- In a function cycle whose values are not obligations an argument counts
-- once, being evaluated once however often it is used; a WHERE or LET name
-- still counts once per use, which may be high.
--
-- In both, a reference inside a function value (a @GIVEN … YIELD@, or a
-- definition named without all its arguments) counts as unbounded: it runs
-- once for each time the function is applied, once per item when it is
-- mapped over a list. That is linear over a tree and exponential when the
-- items are copies; the count cannot tell which.
--
-- Fan-out is per cycle. A lap that starts ANOTHER cycle of obligations (a
-- monthly rule whose LEST starts a weekly one) does work that grows with the
-- product of the two, quadratically for one level and cubically for two
-- (measured, 2026-11-20); such a cycle is reported as "+nests".
--
-- No "+multiplies" is NOT a claim that the work is linear. Measured misses,
-- each confirmed by a run (2026-11-20, second adversarial pass):
--
--   * a polymorphic function cycle the module instantiates at DEONTIC
--     (@rep (append ks ks) (n MINUS 1)@ over @LIST OF a@): whether it arms
--     obligations is a fact about the call, and the report judges the
--     definition. Within an obligation cycle a type-variable parameter is
--     counted (above);
--   * growth by one each lap (@x (k RAND new)@, a list consed onto, or a
--     self-renewing obligation handed in and re-armed each lap): quadratic
--     in the trace, one copy more per lap, which a per-lap factor cannot
--     show;
--   * a batch sized by a number the lap doubles (@replicate n …@ with @x (n
--     TIMES 2)@);
--   * a section GIVEN a helper reaches only through another helper counts
--     once.
--
-- Layer 1's limits on open obligations and on applications are what stop
-- these at run time.

data Mode
  = Arms
    -- ^ each use of an obligation arms it again
  | Evaluates
    -- ^ an argument is evaluated once
  deriving stock Eq

fanOf :: Mode -> Map Unique (Decide Resolved) -> Int -> Map Unique Fan -> Expr Resolved -> Fan
fanOf mode defs depth = go
 where
  go env e = case e of
    App _ f es -> call env f (zip [0 ..] es)
    AppNamed _ f nes order ->
      call env f (named nes order)
        `addF` sumF [go env x `mulF` binderUses f b | (b, x) <- supplied nes order]
        `addF` (if isNothing order then sumF [go env x | MkNamedExpr _ _ x <- nes] else Fan 0)
    Proj _ x l -> call env l [(0, x)]
    Lam _ _ body -> case go env body of
      Fan 0 -> Fan 0
      _ -> Unbounded
    IfThenElse _ c t f -> go env c `addF` max (go env t) (go env f)
    MultiWayIf _ gs other ->
      sumF [go env g | MkGuardedExpr _ g _ <- gs]
        `addF` maximum (go env other : [go env b | MkGuardedExpr _ _ b <- gs])
    Consider _ x brs ->
      let n = go env x
          bound lhs
            | mode == Arms = boundBy n env lhs
            | otherwise = env
      in n `addF` maximum (Fan 0 : [go (bound lhs) b | MkBranch _ lhs b <- brs])
    Regulative _ (MkDeonton _ subj act opens due jn hence lest) ->
      sumF (map (go env) (kids subj <> kids act <> kids opens <> kids due <> kids jn))
        `addF` perMember subj jn (max (maybe (Fan 0) (go env) hence) (maybe (Fan 0) (go env) lest))
    Record _ recipient cell value _ mhence ->
      sumF (map (go env) (maybeToList recipient <> [cell, value])) `addF` maybe (Fan 0) (go env) mhence
    Where _ body ds -> go (localsWith go env ds) body
    LetIn _ ds body -> go (localsWith go env ds) body
    _ -> sumF (map (go env) (toListOf (gplate @(Expr Resolved)) e))
  -- a section GIVEN supplied to the module's own helper counts as often as
  -- the helper names it, and at least once (it may reach it through another)
  binderUses f b = case (mode, Map.lookup (getUnique f) defs) of
    (Arms, Just d)
      | depth > 0 -> max (Fan 1) (fanOf Arms defs (depth - 1) (Map.singleton (getUnique b) (Fan 1)) (bodyOf d))
      | otherwise -> Unbounded
    _ -> Fan 1
  call env f xs = case Map.lookup u env of
    Just w
      | length xs < arity -> Unbounded
      | otherwise -> w `addF` args
    Nothing -> case (mode, Map.lookup u defs) of
      (Arms, Just d) | depth > 0 -> sumF [go env x `mulF` uses d k | (k, x) <- xs]
      (Arms, _) | args == Fan 0 -> Fan 0
                | storesOnce f -> args
                | otherwise -> Unbounded
      (Evaluates, _) -> args
   where
    u = getUnique f
    args = sumF (map (go env . snd) xs)
    arity = maybe 0 (length . valueParams) (Map.lookup u defs)
  uses d k = case drop k (valueParams d) of
    p : _ -> fanOf Arms defs (depth - 1) (Map.singleton (getUnique p) (Fan 1)) (bodyOf d)
    [] -> Unbounded
  perMember subj jn n = case (subj, jn) of
    (Every _ _ _ roll _, Just JoinUpon {})
      | n > Fan 0, not (oneMember roll) -> Unbounded
    _ -> n
  oneMember = \ case
    Just (List _ [_]) -> True
    _ -> False

-- | WHERE or LET locals that reach what the env tracks stand for what their
-- bodies reach. A local may name one written after it, so the pass goes
-- round once per local (a local that names itself is over-counted, never
-- under-). A local the env already holds (a member of the cycle) keeps its
-- weight.
localsWith :: (Map Unique Fan -> Expr Resolved -> Fan) -> Map Unique Fan -> [LocalDecl Resolved] -> Map Unique Fan
localsWith weigh env0 ds = iterate pass env0 !! length lds
 where
  lds = [ld | LocalDecide _ ld <- ds, not (Map.member (getUnique (decideName ld)) env0)]
  pass env = foldl' step env lds
  step env ld = case weigh env (bodyOf ld) of
    Fan 0 -> env
    w -> Map.insert (getUnique (decideName ld)) w env

-- | The names a CONSIDER branch binds, each standing for what the scrutinee
-- reaches.
boundBy :: Fan -> Map Unique Fan -> BranchLhs Resolved -> Map Unique Fan
boundBy n env lhs
  | n > Fan 0 = foldr (\ b -> Map.insert (getUnique b) n) env (lhsBinders lhs)
  | otherwise = env

lhsBinders :: BranchLhs Resolved -> [Resolved]
lhsBinders = \ case
  When _ pat -> patBinders pat
  Otherwise _ -> []

addF :: Fan -> Fan -> Fan
addF (Fan a) (Fan b) = Fan (a + b)
addF _ _ = Unbounded

sumF :: [Fan] -> Fan
sumF = foldl' addF (Fan 0)

mulF :: Fan -> Fan -> Fan
mulF (Fan 0) _ = Fan 0
mulF _ (Fan 0) = Fan 0
mulF (Fan a) (Fan b) = Fan (a * b)
mulF _ _ = Unbounded

------------------------------------------------------------------------
-- Note [What multiplies]
------------------------------------------------------------------------
-- A cycle multiplies when one firing of one of its continuations starts two
-- or more copies of it at once: a @HENCE@, a @LEST@ or a @RECORD … HENCE@
-- whose expression, read through @RAND@ and @ROR@, has two or more operands
-- that are calls of the cycle's members (#1075's @LEST (w1 RAND w3)@, or
-- @LEST (b (n MINUS 1) RAND b (n MINUS 1))@). Under @ROR@ every side is open
-- until one is taken, so it counts as @RAND@ does. A continuation that never
-- runs ('NeverRuns') starts nothing.
--
-- What this does not count, on purpose, so that what it does count is a
-- proof:
--   * calls in different continuations. @rent still owed@
--     (doc/tutorials/obligations/several-parties.l4) is three alternatives
--     joined by @ROR@, each calling the rule again from its own @HENCE@: one
--     payment fires one @HENCE@ and starts one copy, so the open alternatives
--     grow by a fixed number per event, not by a factor;
--   * calls through a helper (@twice k MEANS k RAND k@, then @LEST (twice
--     x)@), and calls under an @IF@ or @CONSIDER@ inside the operand. The
--     run-time count of open obligations stops those;
--   * function recursion that fans out (@fib@, a walk over a tree), which
--     starts no obligation.
-- 'stepsDown' says when every copy passes one parameter less a number
-- written out, as the text is written; it does not prove that the parameter
-- reaches a stop (@b n@ above stops at @n EQUALS 0@ only for a whole @n@ from
-- 0 up).

------------------------------------------------------------------------
-- Note [The function checks]
------------------------------------------------------------------------
-- A cycle that passes no continuation is ordinary recursion. Two checks:
--
--   * descent: each member has a parameter position such that every call
--     round the cycle passes, at the callee's position, a PART of what the
--     caller was given at its own, or the very value; and every lap round the
--     cycle passes a strict part at least once (the calls that pass the very
--     value form no cycle of their own). A strict part of a parameter is:
--       - a name a pattern binds inside the value a CONSIDER matches, when
--         that value is itself a part: both sides of @FOLLOWED BY@ and the
--         fields of a constructor (@WHEN Suc p@), but not a pattern that is a
--         bare name for the whole value;
--       - a stored field of a part (@t's children@): a 'Selector', never a
--         computed field, whose MEANS can give anything;
--       - an expression that builds again, from the names a pattern bound,
--         a pattern nested inside one that matches a part: under @WHEN x
--         FOLLOWED BY (y FOLLOWED BY rest)@, @y FOLLOWED BY rest@ is the very
--         tail the match took apart. The same constructors in the same
--         places around the same names; never the outermost pattern, which
--         is the whole value, and never a number or text written in one;
--       - the parameter of a function written in place (@GIVEN c YIELD …@)
--         that is given to a function trusted to apply it only to elements
--         of a list it is also given, when that list is a part. The callee's
--         declared type is where the credit starts, and its body must earn
--         it (Note [Trusting a callee]): @map@, @any@, @all@ and @filter@
--         do, and so does a function of the author's own in the same module
--         whose body does what theirs do.
--     Each member is tried at every position, up to 4,096 combinations.
--     It proves the recursion ends on a finite value. A list a cycle builds
--     from itself (@ones MEANS 1 FOLLOWED BY ones@) is not one, and that
--     cycle is reported on its own.
--     'L4.Dmn.Analysis' keeps its own, narrower TERMINATES check (a tail
--     bound by @FOLLOWED BY@, on self-recursion), which decides what the DMN
--     export will lower; this one decides only what is reported.
--   * countdown: some parameter position where every call passes the
--     parameter MINUS a positive number written out, under an IF that tests
--     the parameter against a number written out from below (GREATER THAN, AT
--     LEAST, or the negation of AT MOST or LESS THAN) — or PLUS, tested from
--     above. The bound may also be a definition of the module that is a
--     number written out (@`Months in a year` MEANS 12@), or another
--     parameter that every call passes on unchanged (@range (low + 1) high@
--     under @IF low > high@). An equality test does not prove it: @n EQUALS
--     0@ never holds for a negative or fractional @n@. Self-recursion only.

------------------------------------------------------------------------
-- Note [Trusting a callee]
------------------------------------------------------------------------
-- Descent credits a function's parameter as an element of a list, and a
-- callee's result as a list of a list's elements, from the callee's
-- declared type ('elementParameters', 'resultSource'): in @FOR ALL a@,
-- @(a -> b) -> LIST OF a -> …@ with @a@ written nowhere else, the callee
-- has no @a@ of its own to pass on. That reading is false, because L4 has
-- values of every type: @REFUSE "…"@, the prelude's @TBD@ and an @ASSUME@
-- of a type variable are each an @a@. So @smuggle f xs MEANS f (REFUSE
-- "…")@ has the type of @any@, and @walk t MEANS smuggle (GIVEN c YIELD walk
-- c) (t's kids)@ was proved while it never ends: laziness carries the
-- refusal round the loop. Likewise a result built as @LIST (REFUSE "…")@
-- for a callee of @filter@'s type (2026-11-21 attack round, parametricity
-- p12, p11, p17, p13). It loops only where the member recurses before it
-- looks at what it was given; p16, which tests first, ends, and is now
-- "could not check" too.
--
-- So the type is where a credit starts, and a callee keeps it only where
-- its body is seen to earn it ('earns'):
--   * the function argument is applied only to names the body bound to the
--     list's elements (a pattern's @x@ in @WHEN x FOLLOWED BY rest@ over the
--     list or what remains of it), or handed on, with the list or a list of
--     its elements, to a callee trusted with both (@map f xs@ in a helper);
--   * what the callee gives is, along every branch, a list of the list's
--     elements: the list or a name for what remains of it, @EMPTY@, an
--     element put before such a list, or what a trusted callee gives of one.
-- A WHERE/LET helper's parameter counts as such a list when every call of
-- it passes one there, and the helper's result when its body gives one, so
-- @foldr@'s @go list@ is read too. The credits of the module's definitions
-- are settled together: each body is read with the others' and its own
-- taken as given, and a credit some body fails to earn is dropped until
-- none is, since @map@ hands its function on to itself.
--
-- An imported function's body is not here to read, so it keeps no credit,
-- with one exception: the library functions 'trustedLibrary' lists. That
-- list is not a judgement made by hand: CyclesSpec checks each library's
-- source and asserts that the list is exactly what 'earnedByBody' finds
-- there. A library is recognised by its URI ('libraryFile'): the copy
-- compiled into the binary, or a file under a checkout's
-- @jl4-core/libraries@.
--
-- Its cost in proofs, measured on 2026-11-21 by `l4 check` over every
-- tracked .l4 file (1,584 modules, the libraries included) with this rule
-- and without it: none. No cycle there changes class; the attack round's
-- p12 does, as a control that the switch took.
--
-- Where this goes wrong, sorted by how it shows:
--   * Loud, as "could not check": a function that does pass only the list's
--     elements but that the rule cannot read so (@sortBy@, through
--     @insertBy@, whose @x IS AN a@ gives it no credit; @nub@, through
--     @deleteBy@); a helper of the author's own imported from another
--     module; and every library function in a pipeline that names its
--     modules @project:/…@, unless it passes 'apiLibraryFile', as the API's
--     does.
--   * Silent: a file of the author's own whose path ends in
--     @jl4-core/libraries/prelude.l4@, and which defines a @map@ of its
--     own, is taken for the library. The editor's @project:/@ names, which
--     resolve to the author's own files first, are not trusted.

------------------------------------------------------------------------
-- Note [A name for an expression]
------------------------------------------------------------------------
-- A WHERE or LET definition that takes no argument is a name for an
-- expression, and the cycle check reads it as one: wherever it is named, the
-- walk reads its body there, under the tests and continuations around that
-- place, and it is not a node of the graph ('readThrough', 'moduleGraph').
-- So
--
--     `factorial of` n MEANS IF n <= 1 THEN 1
--       ELSE LET `previous factorial` IS `factorial of` (n MINUS 1)
--            IN n TIMES `previous factorial`
--
-- is one rule that calls itself with @n MINUS 1@ under @NOT n <= 1@, which
-- the countdown check proves, and not two definitions calling each other,
-- which no check could.
--
-- Read where it is NAMED, not where it is bound. A function written beside
-- the name may be the one that names it:
--
--     f n MEANS h n
--       WHERE
--         h m MEANS again
--         again MEANS h n
--
-- loops in @h@, and reading @again@ where it is bound would credit its call
-- of @h@ to @f@ and lose the cycle. Where it is named, it is @h@ calling @h@
-- with @n@, which nothing proves.
--
-- Two are left as definitions of their own, so that their cycle is reported
-- as written: a name that reaches itself through names of its kind alone
-- (@ones MEANS 1 FOLLOWED BY ones@), which would otherwise vanish from the
-- graph with its loop, and one longer than 'readThroughLimit' expressions
-- once the names in it are read in turn, which bounds the walk.
--
-- The multiplies check reads an operand that is such a name as its body, so
-- @LEST (a RAND b)@ with @a@ and @b@ each a name for a call of the rule counts
-- two copies, as it did when they were members of the cycle. A name whose
-- body is itself a RAND is not opened up: it was not counted before either.
--
-- 'moduleEdges' reads no name through, so that 'plainReferences' still
-- checks the walk and nothing else.

data Grade = Strict | Weak
  deriving stock Eq

descent :: Trust -> EntityInfo -> Map Unique (Expr Resolved) -> [Decide Resolved] -> [Edge] -> Maybe Proof
descent trust info nullaries ds es = listToMaybe [Structural (firstPosition a) | a <- assignments, works a]
 where
  key = getUnique . decideName
  used = Set.fromList (concat [[e.from, e.to] | e <- es])
  members = [d | d <- ds, Set.member (key d) used]
  choices =
    [ (key d, [(k, p, partsOf trust info nullaries d p) | (k, p) <- zip [0 :: Int ..] (valueParams d)])
    | d <- members ]
  assignments
    | null es || product (map (length . snd) choices) > 4096 = []
    | otherwise = map Map.fromList (traverse (\ (u, cs) -> [(u, c) | c <- cs]) choices)
  firstPosition a = case members of
    d : _ | Just (k, _, _) <- Map.lookup (key d) a -> k
    _ -> 0
  works a = all isJust grades && null (onCycles weak)
   where
    grades = map grade es
    weak = [e | (e, Just Weak) <- zip es grades]
    grade e = do
      (_, p, s) <- Map.lookup e.from a
      (k', _, _) <- Map.lookup e.to a
      case (lookup k' e.args, lookup k' e.elements) of
        (Just x, _)
          | strictPart info p s x -> Just Strict
          | partOf info p s x -> Just Weak
        (Nothing, Just xs)
          | elementsWithin trust info nullaries p s xs -> Just Strict
        _ -> Nothing

-- | What a definition's body takes apart of one parameter's value: the names
-- it binds to strict parts, and the patterns nested inside a pattern that
-- matches a part, each of which matched a strict part as a whole.
data Parts = MkParts
  { partNames :: Set Unique
  , partShapes :: [Pattern Resolved]
  }

-- | The strict parts a definition's body binds of the value of one of its
-- parameters (Note [The function checks]).
partsOf :: Trust -> EntityInfo -> Map Unique (Expr Resolved) -> Decide Resolved -> Resolved -> Parts
partsOf trust info nullaries d p = MkParts names shapes
 where
  everyExpr = universeExpr (bodyOf d)
  names = grow Set.empty
  grow s =
    let s' = Set.union s (Set.fromList (step (MkParts s [])))
    in if Set.size s' == Set.size s then s else grow s'
  step s =
    [ getUnique b
    | Consider _ x brs <- everyExpr, partOf info p s x
    , MkBranch _ (When _ pat) _ <- brs, b <- parts pat ]
      -- a bare name for what a CONSIDER takes apart is that value: a strict
      -- part when the value is (@WHEN other@ over the tail @ys@)
      <> [ getUnique b
         | Consider _ x brs <- everyExpr, strictPart info p s x
         , MkBranch _ (When _ (PatVar _ b)) _ <- brs ]
      <> [ getUnique c
         | App _ g xs <- everyExpr
         , (i, q, j) <- trust.elementsOf g (length xs)
         , Lam _ (MkGivenSig _ otns) _ <- take 1 (drop i xs)
         , c <- take 1 (drop q [n | MkOptionallyTypedName _ n mty _ <- otns, not (isTypeParam mty)])
         , x <- take 1 (drop j xs)
         , elementsWithin trust info nullaries p s x ]
  -- the patterns strictly inside one that matches a part, which bind a name
  -- and are not a bare name: @y FOLLOWED BY rest@ in
  -- @WHEN x FOLLOWED BY (y FOLLOWED BY rest)@
  shapes =
    [ q
    | Consider _ x brs <- everyExpr, partOf info p (MkParts names []) x
    , MkBranch _ (When _ pat) _ <- brs, q <- inside pat, isShape q, not (null (patBinders q)) ]
      -- and the whole pattern of a CONSIDER that takes apart a strict part
      -- (@WHEN z FOLLOWED BY zs@ over the tail @ys@), which matched that part
      <> [ pat
         | Consider _ x brs <- everyExpr, strictPart info p (MkParts names []) x
         , MkBranch _ (When _ pat) _ <- brs, isShape pat, not (null (patBinders pat)) ]
  inside = \ case
    PatCons _ a b -> [a, b] <> inside a <> inside b
    PatApp _ _ ps -> ps <> concatMap inside ps
    _ -> []
  isShape = \ case
    PatCons {} -> True
    PatApp {} -> True
    _ -> False
  -- what a pattern binds strictly inside the value it matches: both sides of
  -- a FOLLOWED BY, and the fields of a constructor, but not a pattern that is
  -- a bare name for the whole value
  parts = \ case
    PatCons _ a b -> patBinders a <> patBinders b
    PatApp _ _ ps -> concatMap patBinders ps
    _ -> []
  isTypeParam = \ case
    Just (Type _) -> True
    _ -> False

-- | The parameter's value, or a part of it.
partOf :: EntityInfo -> Resolved -> Parts -> Expr Resolved -> Bool
partOf info p s = \ case
  App _ v [] | getUnique v == getUnique p -> True
  x -> strictPart info p s x

-- | A strict part of the parameter's value.
strictPart :: EntityInfo -> Resolved -> Parts -> Expr Resolved -> Bool
strictPart info p s x = case x of
  App _ v [] | Set.member (getUnique v) s.partNames -> True
  Proj _ y l | storedField info l && partOf info p s y -> True
  App _ f [y] | storedField info f && partOf info p s y -> True
  _ -> any (`rebuilds` x) s.partShapes

-- | The expression builds again, from the names a pattern bound, the value
-- the pattern matched: the same constructors, in the same places, around the
-- same names. A number or text in the pattern is never rebuilt.
rebuilds :: Pattern Resolved -> Expr Resolved -> Bool
rebuilds q x = case (q, x) of
  (PatVar _ n, App _ v []) -> getUnique n == getUnique v
  -- the checker turns an expression's FOLLOWED BY into a call of the builtin
  -- cons, and leaves a pattern's as it is
  (PatCons _ a b, App _ c [ea, eb]) | getUnique c == consUnique -> rebuilds a ea && rebuilds b eb
  (PatCons _ a b, Cons _ ea eb) -> rebuilds a ea && rebuilds b eb
  (PatApp _ k ps, App _ k' es) ->
    getUnique k == getUnique k' && length ps == length es && and (zipWith rebuilds ps es)
  _ -> False

-- | Every element of the list is a strict part of the parameter's value: the
-- list is a part; or it is what a function gives that is trusted to give
-- only elements of one list it is given (@filter@: see 'resultSource' and
-- Note [Trusting a callee]), when that list's elements are; or it is a definition with
-- no parameters whose body is such a list (@`the stocks` MEANS filter …@).
-- Read three definitions deep.
elementsWithin :: Trust -> EntityInfo -> Map Unique (Expr Resolved) -> Resolved -> Parts -> Expr Resolved -> Bool
elementsWithin trust info nullaries p s = go (3 :: Int)
 where
  go depth x
    | partOf info p s x = True
    | depth <= 0 = False
    | otherwise = case x of
        App _ v [] | Just b <- Map.lookup (getUnique v) nullaries -> go (depth - 1) b
        App _ h xs | [j] <- trust.sourceOf h (length xs), y <- xs !! j -> go (depth - 1) y
        _ -> False

-- | For a function of @n@ arguments whose declared type gives a @LIST OF a@
-- that can hold only elements of one argument, a @LIST OF a@: that argument's
-- position. @a@ is a type variable of the function's @FOR ALL@, and every
-- other argument either does not mention it or is a function that only
-- takes an @a@ (a test, as @filter@'s), so the function has no @a@ to put
-- in what it gives but that list's elements, or a value of every type:
-- the credit holds only where 'moduleTrust' keeps it (Note [Trusting a
-- callee]).
resultSource :: EntityInfo -> Resolved -> Int -> [Int]
resultSource info h n = case Map.lookup (getUnique h) info of
  Just (_, KnownTerm (Forall _ vs (Fun _ args (TyApp _ l [TyApp _ a []]))) _)
    | length args == n, getUnique l == listUnique, getUnique a `elem` map getUnique vs ->
        let u = getUnique a
            tys = [t | MkOptionallyNamedType _ _ t <- args]
            listOfA = \ case
              TyApp _ l' [TyApp _ a' []] -> getUnique l' == listUnique && getUnique a' == u
              _ -> False
            onlyTakes = \ case
              Fun _ largs r ->
                occurrences u r == 0
                  && and [isBare t || occurrences u t == 0 | MkOptionallyNamedType _ _ t <- largs]
              t -> occurrences u t == 0
            isBare = \ case
              TyApp _ _ [] -> True
              _ -> False
        in case [j | (j, t) <- zip [0 ..] tys, listOfA t] of
             [j] | and [onlyTakes t | (k, t) <- zip [0 ..] tys, k /= j] -> [j]
             _ -> []
  _ -> []

-- | How often a type variable is written in a type.
occurrences :: Unique -> Type' Resolved -> Int
occurrences u = \ case
  TyApp _ v ts -> (if getUnique v == u then 1 else 0) + sum (map (occurrences u) ts)
  Fun _ as r -> sum [occurrences u t | MkOptionallyNamedType _ _ t <- as] + occurrences u r
  Forall _ _ t -> occurrences u t
  _ -> 0

-- | A field a constructor stores, not a computed one.
storedField :: EntityInfo -> Resolved -> Bool
storedField info f = Selector `elem` kinds && ComputedSelector `notElem` kinds
 where
  kinds = catMaybes
    [ case infoOf f of
        Just (TypeInfo _ k) -> k
        _ -> Nothing
    , case Map.lookup (getUnique f) info of
        Just (_, KnownTerm _ k) -> Just k
        _ -> Nothing ]

-- | For a function of @n@ arguments whose declared type can hand a function
-- argument only the elements of a list argument: the function argument's
-- position, its parameter's, and the list's. The type is @FOR ALL@ some @a@,
-- the function argument takes an @a@, another argument is a @LIST OF a@, and
-- @a@ is written nowhere else among the arguments, so the function has no @a@
-- to pass but the list's elements. What it gives holds an @a@ only as
-- itself or in a list ('plainIn'): a function that gives back a function
-- taking an @a@ (@(a -> b) -> LIST OF a -> (a -> b)@), or a record that may
-- hold one, can hand back the function it was given, and the caller then
-- applies that to anything. A value of every type (@REFUSE@, @TBD@) is an
-- @a@ too, so the credit holds only where 'moduleTrust' keeps it
-- (Note [Trusting a callee]).
elementParameters :: EntityInfo -> Resolved -> Int -> [(Int, Int, Int)]
elementParameters info g n = case Map.lookup (getUnique g) info of
  Just (_, KnownTerm (Forall _ vs (Fun _ args r)) _) | length args == n ->
    let tys = [t | MkOptionallyNamedType _ _ t <- args]
        vars = Set.fromList (map getUnique vs)
    in [ (i, q, j)
       | (i, Fun _ largs _) <- zip [0 ..] tys
       , (q, TyApp _ a []) <- zip [0 ..] [t | MkOptionallyNamedType _ _ t <- largs]
       , Set.member (getUnique a) vars
       , (j, TyApp _ l [TyApp _ a' []]) <- zip [0 ..] tys
       , getUnique l == listUnique, getUnique a' == getUnique a
       , sum (map (occurrences (getUnique a)) tys) == 2
       , plainIn (getUnique a) r ]
  _ -> []

-- | The type holds the type variable only as itself or as what a list
-- holds, however deep: no @a@ at all, @a@, @LIST OF a@, @LIST OF LIST OF a@.
-- Anything else that names it (a function, a pair, a record) might hold a
-- function that takes one.
plainIn :: Unique -> Type' Resolved -> Bool
plainIn u t = occurrences u t == 0 || case t of
  TyApp _ v [] -> getUnique v == u
  TyApp _ l [t'] | getUnique l == listUnique -> plainIn u t'
  _ -> False

-- | What the function checks take on trust of a callee whose body they do
-- not read where it is called: the credit 'elementParameters' and
-- 'resultSource' give it from its declared type, kept only where its body is
-- seen to earn it (Note [Trusting a callee]).
data Trust = MkTrust
  { elementsOf :: Resolved -> Int -> [(Int, Int, Int)]
  , sourceOf :: Resolved -> Int -> [Int]
  }

-- | A credit a callee's declared type gives: 'elementParameters' ('Left') or
-- 'resultSource' ('Right').
type Credit = Either (Int, Int, Int) Int

typeCredits :: EntityInfo -> Resolved -> Int -> [Credit]
typeCredits info f n = map Left (elementParameters info f n) <> map Right (resultSource info f n)

-- | The module's trust (Note [Trusting a callee]). A definition of the
-- module keeps a credit its type gives when its body earns it ('earns'),
-- each body read with the credits of the others and its own taken as given:
-- a credit some body fails to earn is dropped, and the bodies are read
-- again, until none is. A library function keeps its credit when the
-- library is one 'library' names and 'trustedLibrary' lists the function.
-- Any other function keeps none: its body is not here to read.
moduleTrust :: (NormalizedUri -> Maybe Text) -> EntityInfo -> Module Resolved -> Trust
moduleTrust library info m = trustIn honest
 where
  defs = Map.fromList [(getUnique (decideName d), d) | d <- moduleDecides m]
  candidates = Set.fromList
    [(u, c) | (u, d) <- Map.toList defs, c <- typeCredits info (decideName d) (length (valueParams d))]
  honest = settle candidates
  settle s =
    let s' = Set.filter (\ (u, c) -> maybe False (\ d -> earns (trustIn s) d c) (Map.lookup u defs)) s
    in if Set.size s' == Set.size s then s else settle s'
  trustIn s = MkTrust
    { elementsOf = \ g n -> [t | t <- elementParameters info g n, keeps s g (Left t)]
    , sourceOf = \ h n -> [j | j <- resultSource info h n, keeps s h (Right j)] }
  keeps s f c
    | Map.member (getUnique f) defs = Set.member (getUnique f, c) s
    | otherwise = trustedIn library f

-- | The module's definitions whose bodies earn every credit their declared
-- types give, by name: for a library, what 'trustedLibrary' must list.
earnedByBody :: EntityInfo -> Module Resolved -> [Text]
earnedByBody info m = nubOrd
  [ decideText d
  | d <- moduleTops m
  , let cs = typeCredits info (decideName d) (length (valueParams d))
  , not (null cs)
  , all (kept d) cs ]
 where
  trust = moduleTrust (const Nothing) info m
  kept d c =
    let n = length (valueParams d)
    in case c of
      Left t -> t `elem` trust.elementsOf (decideName d) n
      Right j -> j `elem` trust.sourceOf (decideName d) n

-- | The body earns the credit: a function argument is applied only to
-- elements of the list argument, or handed with that list (or a list of its
-- elements) to a callee trusted with both ('Left'); what it gives is a list
-- of the list argument's elements ('Right').
earns :: Trust -> Decide Resolved -> Credit -> Bool
earns trust d = \ case
  Left (i, q, j)
    | Just f <- param i, Just xs <- param j ->
        let s = listParts trust xs d
            uses = length [() | App _ v _ <- everyExpr, same f v] + length [() | AppNamed _ v _ _ <- everyExpr, same f v]
            applied = length [() | App _ v es <- everyExpr, same f v, x <- take 1 (drop q es), item s x]
            handed = length
              [ ()
              | App _ h es <- everyExpr
              , (i', App _ v []) <- zip [0 ..] es, same f v
              , or [ onlyItems trust s x
                   | (i'', q', j') <- trust.elementsOf h (length es), i'' == i', q' == q
                   , x <- take 1 (drop j' es) ] ]
        in uses == applied + handed
  Right j
    | Just xs <- param j -> givesItems trust (listParts trust xs d) (bodyOf d)
  _ -> False
 where
  param k = listToMaybe (drop k (valueParams d))
  everyExpr = universeExpr (bodyOf d)
  same a b = getUnique a == getUnique b

-- | What a body binds of a list parameter's value: the names of lists that
-- hold only its elements, the names of its elements, and the WHERE\/LET
-- definitions whose result is such a list.
data ListParts = MkListParts
  { lists :: Set Unique
  , items :: Set Unique
  , givers :: Set Unique
  }

-- | The list parameter's 'ListParts' in a definition's body. A parameter of
-- a WHERE\/LET definition is such a list when every call of it passes one
-- there, and a WHERE\/LET definition gives one when its body does: both
-- are taken as given and dropped where a call or a body fails, until none
-- does, as a helper that walks the list calls itself on what remains of it.
-- A name bound inside is found as it is everywhere else ('close').
listParts :: Trust -> Resolved -> Decide Resolved -> ListParts
listParts trust xs d = settle (Map.keysSet owners) (Map.keysSet locals)
 where
  everyExpr = universeExpr (bodyOf d)
  locals = Map.fromList
    [ (getUnique (decideName ld), ld)
    | e <- everyExpr
    , ld <- case e of
        Where _ _ ds -> [l | LocalDecide _ l <- ds]
        LetIn _ ds _ -> [l | LocalDecide _ l <- ds]
        _ -> [] ]
  -- each parameter of a WHERE/LET definition: whose it is, and where
  owners = Map.fromList
    [ (getUnique p, (u, k))
    | (u, ld) <- Map.toList locals, (k, p) <- zip [0 :: Int ..] (valueParams ld) ]
  settle ps rs =
    let s = close ps rs
        ps' = Set.filter (passed s) ps
        rs' = Set.filter (\ u -> maybe False (givesItems trust s . bodyOf) (Map.lookup u locals)) rs
    in if ps' == ps && rs' == rs then s else settle ps' rs'
  passed s p = case Map.lookup p owners of
    Just (u, k) ->
      let calls = [es | App _ v es <- everyExpr, getUnique v == u]
      in not (null calls)
           && null [() | AppNamed _ v _ _ <- everyExpr, getUnique v == u]
           && all (maybe False (onlyItems trust s) . listToMaybe . drop k) calls
    Nothing -> False
  close ps rs = grow (MkListParts (Set.insert (getUnique xs) ps) Set.empty rs)
  grow s =
    let s' = step s
    in if Set.size s'.lists == Set.size s.lists && Set.size s'.items == Set.size s.items then s else grow s'
  step s = s
    { lists = Set.union s.lists (Set.fromList (concatMap fst taken))
    , items = Set.union s.items (Set.fromList (concatMap snd taken <> lambdas)) }
   where
    taken =
      [ listPattern pat
      | Consider _ x brs <- everyExpr, onlyItems trust s x
      , MkBranch _ (When _ pat) _ <- brs ]
    -- a function's parameter, where the function is handed with such a list
    -- to a callee trusted to apply it only to the list's elements
    lambdas =
      [ getUnique c
      | App _ g es <- everyExpr
      , (i, q, j) <- trust.elementsOf g (length es)
      , Lam _ (MkGivenSig _ otns) _ <- take 1 (drop i es)
      , c <- take 1 (drop q [n | MkOptionallyTypedName _ n mty _ <- otns, not (isTypeParam mty)])
      , x <- take 1 (drop j es)
      , onlyItems trust s x ]
  isTypeParam = \ case
    Just (Type _) -> True
    _ -> False

-- | What a pattern over a list binds: names for the list again or what
-- remains of it, and names for its elements. A pattern inside an element
-- binds a part of an element, which is neither.
listPattern :: Pattern Resolved -> ([Unique], [Unique])
listPattern = \ case
  PatVar _ n -> ([getUnique n], [])
  PatCons _ a b -> element a <> listPattern b
  PatApp _ c [a, b] | getUnique c == consUnique -> element a <> listPattern b
  _ -> ([], [])
 where
  element = \ case
    PatVar _ n -> ([], [getUnique n])
    _ -> ([], [])

-- | An element of the list: a name the body bound to one.
item :: ListParts -> Expr Resolved -> Bool
item s = \ case
  App _ v [] -> Set.member (getUnique v) s.items
  _ -> False

-- | A list that holds only elements of the list: a name for one, @EMPTY@,
-- a list of elements, an element put before such a list, what a WHERE\/LET
-- definition that gives one gives, or what a callee trusted to give only
-- elements of a list gives of such a list.
onlyItems :: Trust -> ListParts -> Expr Resolved -> Bool
onlyItems trust s = go
 where
  go = \ case
    App _ v [] | Set.member (getUnique v) s.lists -> True
    App _ v [] | getUnique v == emptyUnique -> True
    App _ v _ | Set.member (getUnique v) s.givers -> True
    List _ es -> all (item s) es
    Cons _ a b -> item s a && go b
    App _ c [a, b] | getUnique c == consUnique -> item s a && go b
    App _ h es -> or [go x | j <- trust.sourceOf h (length es), x <- take 1 (drop j es)]
    _ -> False

-- | The body gives only a list of the list's elements, along every branch.
givesItems :: Trust -> ListParts -> Expr Resolved -> Bool
givesItems trust s = go
 where
  go = \ case
    IfThenElse _ _ t e -> go t && go e
    MultiWayIf _ gs o -> all go [b | MkGuardedExpr _ _ b <- gs] && go o
    Consider _ _ brs -> all go [b | MkBranch _ _ b <- brs]
    Where _ b _ -> go b
    LetIn _ _ b -> go b
    x -> onlyItems trust s x

-- | The library functions trusted where they are called, by library file:
-- each one's body earns every credit its declared type gives
-- ('earnedByBody'). CyclesSpec reads each library's source and checks that
-- this is exactly what its bodies earn, so a library edit that changes one
-- fails there rather than here.
trustedLibrary :: Map Text (Set Text)
trustedLibrary = Map.fromList
  [ ( "prelude.l4"
    , Set.fromList
        [ "all", "any", "drop", "dropWhile", "filter", "foldl", "foldr", "map", "mapMaybe"
        , "reverse", "take", "takeWhile", "zipWith" ] ) ]

-- | The function is a library's, the library is one 'library' names, and
-- 'trustedLibrary' lists the function.
trustedIn :: (NormalizedUri -> Maybe Text) -> Resolved -> Bool
trustedIn library f = case library (getUnique f).moduleUri of
  Just file -> maybe False (Set.member (unqualifiedNameToText (getOriginal f))) (Map.lookup file trustedLibrary)
  Nothing -> False

-- | The library file a module is, where no other file can take its place:
-- the copy compiled into the binary (@jl4-embedded:/prelude.l4@), or a file
-- in a checkout's @jl4-core/libraries@ (where @JL4_LIBRARY_PATH@ points in
-- CI). Not @project:/prelude.l4@: the editor resolves that name to the
-- user's own file first.
libraryFile :: NormalizedUri -> Maybe Text
libraryFile u = asum
  [ Text.stripPrefix "jl4-embedded:/" t
  , case Text.breakOnEnd marker t of
      (before, file) | not (Text.null before) -> Just file
      _ -> Nothing ]
 where
  t = (fromNormalizedUri u).getUri
  marker = "/jl4-core/libraries/"

-- | 'libraryFile' for the API's pipeline ("L4.API.VirtualFS"), which names
-- every module @project:/<name>.l4@ and looks a name up among the libraries
-- before the files it is given, so that there @project:/prelude.l4@ is the
-- library.
apiLibraryFile :: NormalizedUri -> Maybe Text
apiLibraryFile u = asum [libraryFile u, Text.stripPrefix "project:/" (fromNormalizedUri u).getUri]

-- | The type of the field a selector gives, read past the record it takes.
fieldOf :: Type' Resolved -> Type' Resolved
fieldOf = \ case
  Forall _ _ t -> fieldOf t
  Fun _ _ t -> t
  t -> t

-- | The names a pattern binds to a constructor's fields, however deep.
fieldBinders :: Pattern Resolved -> [Resolved]
fieldBinders = \ case
  PatApp _ _ ps -> [n | PatVar _ n <- ps] <> concatMap fieldBinders ps
  PatCons _ a b -> fieldBinders a <> fieldBinders b
  _ -> []

-- | Every name a pattern binds.
patBinders :: Pattern Resolved -> [Resolved]
patBinders = \ case
  PatVar _ n -> [n]
  PatApp _ _ ps -> concatMap patBinders ps
  PatCons _ a b -> patBinders a <> patBinders b
  PatExpr _ _ -> []
  PatLit _ _ -> []

countdown :: Set Unique -> Decide Resolved -> [Edge] -> Maybe Proof
countdown constants d calls = Countdown <$> find positionOk positions
 where
  params = valueParams d
  positions = [0 .. length params - 1]
  positionOk k = not (null calls) && (all (steps k Down) calls || all (steps k Up) calls)
  steps k dir e = case (lookup k e.args >>= binary, dir) of
    (Just (OpMinus, App _ v [], Lit _ (NumericLit _ r)), Down) ->
      getUnique v == u && r > 0 && any (bounds Down) facts
    (Just (OpPlus, App _ v [], Lit _ (NumericLit _ r)), Up) ->
      getUnique v == u && r > 0 && any (bounds Up) facts
    _ -> False
   where
    u = getUnique (params !! k)
    facts = concatMap atoms e.conds
    -- a test the branch taken guarantees: conjuncts of a test that held,
    -- disjuncts of one that failed, through NOT
    atoms (pol, c)
      | Just x <- negation c = atoms (not pol, x)
      | Just (OpAnd, a, b) <- binary c, pol = atoms (True, a) <> atoms (True, b)
      | Just (OpOr, a, b) <- binary c, not pol = atoms (False, a) <> atoms (False, b)
      | otherwise = [(pol, c)]
    isU = \ case
      App _ v [] -> getUnique v == u
      _ -> False
    -- a bound that does not move: a number written out, a definition that is
    -- one, or another parameter that every call passes on unchanged
    isLit = \ case
      Lit _ NumericLit {} -> True
      App _ v [] -> Set.member (getUnique v) fixed || Set.member (getUnique v) constants
      _ -> False
    fixed = Set.fromList
      [ getUnique p
      | (j, p) <- zip [0 ..] params, j /= k
      , all (\ c -> case lookup j c.args of
                Just (App _ v []) -> getUnique v == getUnique p
                _ -> False) calls
      ]
    -- the parameter is bounded from below (Down) or above (Up) by a number
    bounds dir' (pol, c) = case binary c of
      Nothing -> False
      Just (op, a, b) -> case (dir', pol, op) of
        (Down, True, OpGt) -> isU a && isLit b
        (Down, True, OpGeq) -> isU a && isLit b
        (Down, True, OpLt) -> isLit a && isU b
        (Down, True, OpLeq) -> isLit a && isU b
        (Down, False, OpLeq) -> isU a && isLit b
        (Down, False, OpLt) -> isU a && isLit b
        (Down, False, OpGt) -> isLit a && isU b
        (Down, False, OpGeq) -> isLit a && isU b
        (Up, True, OpLt) -> isU a && isLit b
        (Up, True, OpLeq) -> isU a && isLit b
        (Up, True, OpGt) -> isLit a && isU b
        (Up, True, OpGeq) -> isLit a && isU b
        (Up, False, OpGeq) -> isU a && isLit b
        (Up, False, OpGt) -> isU a && isLit b
        (Up, False, OpLt) -> isLit a && isU b
        (Up, False, OpLeq) -> isLit a && isU b
        _ -> False

data Direction = Down | Up

-- | The operators the countdown check reads, recognised by the builtin their
-- name resolved to and never by spelling: the type checker turns @n MINUS 1@
-- into an application of the builtin @__MINUS__@, and a definition of the
-- user's own spelled @__MINUS__@ is a different function ('carameliseExpr'
-- in "L4.Desugar" goes by spelling, so this module does not use it).
data Op = OpPlus | OpMinus | OpGt | OpGeq | OpLt | OpLeq | OpAnd | OpOr
  deriving stock Eq

binary :: Expr Resolved -> Maybe (Op, Expr Resolved, Expr Resolved)
binary = \ case
  Plus _ a b -> Just (OpPlus, a, b)
  Minus _ a b -> Just (OpMinus, a, b)
  Gt _ a b -> Just (OpGt, a, b)
  Geq _ a b -> Just (OpGeq, a, b)
  Lt _ a b -> Just (OpLt, a, b)
  Leq _ a b -> Just (OpLeq, a, b)
  And _ a b -> Just (OpAnd, a, b)
  Or _ a b -> Just (OpOr, a, b)
  App _ f [a, b] | Just o <- builtin (getUnique f) -> Just (o, a, b)
  _ -> Nothing
 where
  builtin u
    | u == plusUnique = Just OpPlus
    | u == minusUnique = Just OpMinus
    | u `elem` gtUniques = Just OpGt
    | u `elem` geqUniques = Just OpGeq
    | u `elem` ltUniques = Just OpLt
    | u `elem` leqUniques = Just OpLeq
    | u == andUnique = Just OpAnd
    | u == orUnique = Just OpOr
    | otherwise = Nothing

negation :: Expr Resolved -> Maybe (Expr Resolved)
negation = \ case
  Not _ x -> Just x
  App _ f [x] | getUnique f == notUnique -> Just x
  _ -> Nothing

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ n _ _) _) = n

-- | A definition's body with the type checker's prefix applications of the
-- builtin operators turned back into 'Minus', 'Gt' and the rest
-- ('carameliseExpr'), as 'L4.Dmn.Analysis' reads it: the countdown check
-- matches those forms.
bodyOf :: Decide Resolved -> Expr Resolved
bodyOf (MkDecide _ _ _ b) = b

-- | The parameters a call passes: every GIVEN but a type parameter.
valueParams :: Decide Resolved -> [Resolved]
valueParams d = [n | (n, mty) <- decideParams d, not (isType mty)]
 where
  isType = \ case
    Just (Type _) -> True
    _ -> False

-- | The parameters a call passes, each with its type: as inferred (through
-- the final substitution), or as written when the checker recorded none.
paramTypes :: (Type' Resolved -> Type' Resolved) -> Decide Resolved -> [(Resolved, Maybe (Type' Resolved))]
paramTypes expand d =
  [ (n, asum [expand <$> inferredType n, mty])
  | n <- valueParams d, let mty = join (lookup n (decideParams d)) ]

-- | Does a type hold an obligation: @DEONTIC@ (or its alias @PROVISION@)
-- anywhere in it, or a type whose synonym, or some constructor's field, holds
-- one? Read through the checker's table of the types in scope, imported ones
-- included, so a record with a DEONTIC field and a synonym for DEONTIC both
-- count. A recursive type is looked into once.
holdsContract :: EntityInfo -> Type' Resolved -> Bool
holdsContract info = lookInto info \ case
  TyApp _ n _ -> getUnique n == contractUnique
  _ -> False

-- | Does a type carry a function whose parameters and result (as the
-- predicate is given them) pass: a function type anywhere in it, including
-- a function another function returns, or in a synonym it names, or in a
-- field of some constructor of a type it names?
carriesFunction :: EntityInfo -> ([Type' Resolved] -> Type' Resolved -> Bool) -> Type' Resolved -> Bool
carriesFunction info p = lookInto info \ case
  Fun _ args r -> p [t | MkOptionallyNamedType _ _ t <- args] r
  _ -> False

-- | Does any part of a type pass the test: the type, the types in it, and the
-- body of a synonym or the fields of the constructors of a type it names,
-- read through the checker's table. The type's arguments are put for the
-- declaration's parameters, so the function in @Endo (DEONTIC …)@, with
-- @DECLARE Endo a IS FUNCTION FROM a TO a@, takes an obligation. A named
-- type is looked into once on each path into it, with the arguments it was
-- first met with; the arguments it is met with again are looked into where
-- they are written.
lookInto :: EntityInfo -> (Type' Resolved -> Bool) -> Type' Resolved -> Bool
lookInto info here = fst (lookers info here) Set.empty

-- | Does any part of a declared type pass the test: its synonym's body, or
-- its constructors' fields, with its parameters as they are written.
lookIntoDeclaration :: EntityInfo -> (Type' Resolved -> Bool) -> Unique -> Bool
lookIntoDeclaration info here u = snd (lookers info here) Set.empty u []

lookers
  :: EntityInfo -> (Type' Resolved -> Bool)
  -> (Set Unique -> Type' Resolved -> Bool, Set Unique -> Unique -> [Type' Resolved] -> Bool)
lookers info here = (go, declared)
 where
  fields = Map.fromListWith (<>)
    [ (getUnique h, [(params, args)])
    | (_, KnownTerm cty Constructor) <- Map.elems info
    , (args, TyApp _ h params) <- [split cty] ]
  split = \ case
    Forall _ _ t -> split t
    Fun _ args r -> ([t | MkOptionallyNamedType _ _ t <- args], r)
    t -> ([], t)
  go seen t = here t || case t of
    TyApp _ n ts -> any (go seen) ts || declared seen (getUnique n) ts
    Fun _ args r -> any (go seen) [a | MkOptionallyNamedType _ _ a <- args] || go seen r
    Forall _ _ t' -> go seen t'
    _ -> False
  declared seen u ts
    | Set.member u seen = False
    | otherwise = case Map.lookup u info of
        Just (_, KnownType _ params (Just body)) ->
          go seen' (substituteType (Map.fromList (zip (map getUnique params) ts)) body)
        _ ->
          or [ any (go seen' . substituteType s) args
             | (params, args) <- Map.findWithDefault [] u fields
             , let s = Map.fromList [(getUnique v, t) | (TyApp _ v [], t) <- zip params ts] ]
   where
    seen' = Set.insert u seen

-- | Does a type mention a type variable (as the predicate says), or a
-- variable inference left open?
variableIn :: (Resolved -> Bool) -> Type' Resolved -> Bool
variableIn isVar = go Set.empty
 where
  go bound = \ case
    TyApp _ n ts -> Set.member (getUnique n) bound || isVar n || any (go bound) ts
    Fun _ args r -> any (go bound) [t | MkOptionallyNamedType _ _ t <- args] || go bound r
    Forall _ ns t -> go (foldr (Set.insert . getUnique) bound ns) t
    InfVar {} -> True
    Type _ -> False

-- | Does the definition give an obligation, or anything holding one? Read off
-- the type the checker inferred, so a definition with no GIVETH is not
-- missed, and off the GIVETH as written when the checker recorded none.
returnsContract :: (Type' Resolved -> Bool) -> (Type' Resolved -> Type' Resolved) -> Decide Resolved -> Bool
returnsContract holds expand d@(MkDecide _ (MkTypeSig _ _ mgiveth) _ _) =
  maybe False (holds . resultOf . expand) (inferredType (decideName d))
    || maybe False (\ (MkGivethSig _ ty) -> holds ty) mgiveth
 where
  resultOf = \ case
    Forall _ _ t -> resultOf t
    Fun _ _ t -> resultOf t
    t -> t

-- | The type the checker inferred for a name, when it recorded one.
inferredType :: Resolved -> Maybe (Type' Resolved)
inferredType n = case infoOf n of
  Just (TypeInfo t _) -> Just t
  _ -> Nothing

-- | What the checker recorded on a name, at this occurrence.
infoOf :: Resolved -> Maybe Info
infoOf r = case getActual r of
  MkName ann _ -> view annInfo ann

-- | A head that keeps its arguments once: a builtin (an operator, FOLLOWED
-- BY), a constructor or a selector. A function value passed to one is
-- already counted as unbounded where it is written.
storesOnce :: Resolved -> Bool
storesOnce f = (getUnique f).moduleUri == builtinUri || kindOf `elem` [Just Constructor, Just Selector]
 where
  kindOf = case infoOf f of
    Just (TypeInfo _ k) -> k
    _ -> Nothing

decideParams :: Decide Resolved -> [(Resolved, Maybe (Type' Resolved))]
decideParams (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) _ _) =
  [(n, mty) | MkOptionallyTypedName _ n mty _ <- otns]

decideText :: Decide Resolved -> Text
decideText = unqualifiedNameToText . getOriginal . decideName

decideLine :: Decide Resolved -> Maybe Int
decideLine d = case (getAnno d).range of
  Just (MkSrcRange start _ _ _) -> Just start.line
  Nothing -> Nothing

-- | The arguments of a named application by the callee's parameter position,
-- from the order the type checker stored. A negative position supplies a
-- section's GIVEN and is left out; with no stored order, none is known.
named :: [NamedExpr Resolved] -> Maybe [Int] -> [(Int, Expr Resolved)]
named nes = \ case
  Just order -> [(k, x) | (k, MkNamedExpr _ _ x) <- zip order nes, k >= 0]
  Nothing -> []

-- | The section GIVENs a named application supplies (a negative position in
-- the stored order), each with its value. The name is the GIVEN's own.
supplied :: [NamedExpr Resolved] -> Maybe [Int] -> [(Resolved, Expr Resolved)]
supplied nes = \ case
  Just order -> [(b, x) | (k, MkNamedExpr _ b x) <- zip order nes, k < 0]
  Nothing -> []

-- | The outermost expressions inside any piece of syntax.
kids :: GPlate (Expr Resolved) s => s -> [Expr Resolved]
kids = toListOf (gplate @(Expr Resolved))

universeExpr :: Expr Resolved -> [Expr Resolved]
universeExpr e = e : concatMap universeExpr (toListOf (gplate @(Expr Resolved)) e)

-- | The expression with each name for an expression in the map replaced by
-- what it names, however deep (Note [A name for an expression]): @f next@
-- with @next MEANS n MINUS 1@ is read as @f (n MINUS 1)@. The names in the
-- map name no cycle among themselves, so this ends.
expandNames :: Map Unique (Expr Resolved) -> Expr Resolved -> Expr Resolved
expandNames through
  | Map.null through = id
  | otherwise = go
 where
  go = \ case
    App _ v [] | Just b <- Map.lookup (getUnique v) through -> go b
    e -> over (gplate @(Expr Resolved)) go e
