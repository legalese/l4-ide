-- | L4 AST → MLIR IR lowering.
--
-- Traverses a typechecked L4 module and produces MLIR operations using
-- the func, arith, scf, and cf dialects. Each L4 DECIDE becomes a
-- func.func, each expression becomes a sequence of SSA operations.
--
-- The lowering runs in a monadic context ('LowerM') that tracks:
--   * Fresh SSA value / block counters
--   * Variable bindings (L4 name → MLIR Value)
--   * Type environment (record/enum layouts)
--   * Accumulated operations (current block)
module L4.MLIR.Lower
  ( lowerModule
  , lowerProgram
  , lowerProgramWithInfo
  , lowerProgramWithDiagnostics
  , dedupAndSynthExterns
  ) where

import L4.MLIR.IR
import L4.MLIR.Types
import L4.MLIR.Dialect.Func
import L4.MLIR.Dialect.Arith
import L4.MLIR.Dialect.SCF
import L4.MLIR.Dialect.LLVM
import qualified L4.MLIR.Schema as Schema
import L4.MLIR.ABI (l4Value)
import qualified L4.Export as Export

import L4.Syntax
  ( Module(..), Section(..), TopDecl(..), Decide(..), Declare(..)
  , Assume(..)
  , Expr(..), Lit(..), Pattern(..), Branch(..), BranchLhs(..)
  , TypeSig(..), GivenSig(..), GivethSig(..), AppForm(..)
  , TypeDecl(..), ConDecl(..), TypedName(..), OptionallyTypedName(..)
  , Type'(..), Resolved(..), RawName(..), Name(..)
  , LocalDecl(..), GuardedExpr(..)
  , NamedExpr(..), InertContext(..), OptionallyNamedType(..)
  , Info(..)
  , rawName, rawNameToText, getActual
  , Unique, getUnique
  )
import L4.Annotation (HasSrcRange, emptyAnno, rangeOf)
import L4.Parser.SrcSpan (SrcRange(..))
import L4.TypeCheck.Types (InfoMap, EntityInfo, CheckEntity(..))
import qualified L4.Utils.IntervalMap as IV

import Control.Monad (forM_, forM, unless, when)
import Control.Monad.State.Strict
import Data.List (zip4)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ratio (numerator, denominator)
import qualified Data.Set as Set
import qualified Data.Text as Text

-- ---------------------------------------------------------------------------
-- Lowering monad
-- ---------------------------------------------------------------------------

data LowerState = LowerState
  { nextValue  :: !ValueId
  , nextBlock  :: !BlockId
  , bindings   :: Map Text Value    -- L4 name → SSA value
  , bindingTypes :: Map Text MLIRType  -- L4 name → MLIR type
  , bindingL4Types :: Map Text (Type' Resolved)
    -- L4 name → original L4 'Type''. Populated alongside 'bindingTypes'
    -- by 'lowerDecide' (for function params) and 'lowerLocalDecl' (for
    -- WHERE/LET locals). Used by 'isNumberExpr' so a @Var@ reference
    -- to a NUMBER-typed param inside a @<fn>$trace@ body routes its
    -- comparison through @__l4_rat_cmp@ instead of falling through to
    -- the raw f64 bit-pattern path — which would otherwise compare the
    -- rational-handle indices as f64, almost always producing the
    -- wrong truth value.
  , listElemTypes :: Map Text MLIRType -- L4 name → list element type (for LIST OF T)
  , typeEnv    :: TypeEnv           -- Record/enum layouts
  , currentOps :: [Operation]       -- Ops accumulated in current block (reversed)
  , globals    :: [Operation]       -- Top-level global declarations
  , functions  :: [Operation]       -- Collected func.func operations
  , stringPool :: Map Text Text     -- String literal → global name
  , nextString :: !Int              -- Counter for string global names
  , funcSigs   :: Map Text ([MLIRType], MLIRType)  -- Known function signatures
  , funcListElems :: Map Text [Maybe MLIRType]  -- Known list element types per arg
    -- | The bundle-wide L4 type map: the typechecker's checked type for
    -- every known term — top-level and local DECIDE heads, ASSUMEs — keyed
    -- by 'Unique', across the main module AND every dependency. 'funcSigs'
    -- records only MLIR-level types, and under the uniform ABI those are
    -- all @f64@ — so a comparison whose operand is a helper's CALL RESULT
    -- used to be unclassifiable and 'lowerCmp' refused (daydate's
    -- @is weekend@ compares the helper result @`Weekday of` d@ against the
    -- constant @Saturday@, which is why @is-a-weekday@ routed to the
    -- fallback). 'classifyOperand' uses this map to recover the callee's
    -- L4-level result type at any 'App' operand. Derived from the
    -- typechecker's 'EntityInfo' (must be the SUBSTITUTED one — see
    -- 'applyFinalSubstitution' in the LSP rules; an un-substituted map is
    -- full of 'InfVar's for MEANS bindings). Empty when the caller has no
    -- typecheck result (the plain 'lowerProgram' entry point).
  , funcL4Types :: !(Map Unique (Type' Resolved))
    -- | User-declared type SYNONYMS (@DECLARE Foo IS A STRING@), keyed by
    -- the synonym's name, mapping to its underlying 'Type''. The lowering
    -- otherwise ERASES synonym decls (see 'lowerModuleDecls'), so a
    -- comparison operand typed @Foo@ (recovered from 'bindingL4Types' when
    -- the 'InfoMap' misses) would reach 'classifyL4Type' as an opaque
    -- 'TyApp' head and be mis-read as 'CmpOther' — a raw @arith.cmpf@ on
    -- what is actually a string /pointer/. 'classifyOperand' unfolds
    -- through this map so @Foo@ resolves to STRING → 'CmpString' →
    -- @__l4_str_eq@/@__l4_str_cmp@. Genuine builtin DATE\/TIME are NOT
    -- synonyms, so they are absent here and keep their 'CmpOther' serial
    -- semantics. (@britishcitizen5@: @DECLARE Date IS A STRING@,
    -- @DECLARE Place IS A STRING@.)
  , typeSynonyms :: !(Map Text (Type' Resolved))
    -- | Ground-truth type info from the jl4-core typechecker. Every
    -- expression's inferred 'Type'' Resolved' is stored here, keyed by
    -- source range. Use 'typeOfExpr' to look up the type of any
    -- expression rather than re-inferring from the syntactic shape.
  , sourceTypeMap :: !InfoMap
    -- | Helpers introduced by @WHERE@ / @LET IN@ clauses that were
    -- lambda-lifted to top-level @func.func@s. For each lifted helper
    -- this stores the list of outer-scope variables it captured, in
    -- the order the captures were prepended as extra leading
    -- parameters. Call sites must prepend the corresponding current
    -- bindings before emitting the call.
  , localCaptures :: Map Text [Text]
    -- | For each @\@export@-decorated DECIDE, the extra ASSUME-derived
    -- parameters (Resolved name + L4 type) that should be appended to
    -- the function's ABI arg list. Keyed by sanitized function name.
    -- Non-exported DECIDEs aren't in this map, so they fall back to
    -- the original extern-based ASSUME model.
  , exportAssumeArgs :: Map Text [(Resolved, Type' Resolved)]
    -- | The function currently being lowered, as its sanitized WASM
    -- symbol name (matching 'Schema.wasmSymbol'). Set by 'lowerDecide'
    -- so 'markUnsupported' can attribute a diagnostic to the right
    -- export. 'Nothing' outside any function body.
  , currentFunction :: Maybe Text
    -- | Per-function diagnostics: sanitized WASM symbol name → reasons
    -- the function cannot be faithfully compiled (e.g. it contains a
    -- regulative/deontic/IO construct the backend doesn't support). The
    -- pipeline threads these into the schema so flagged functions are
    -- marked @supported: false@ and routed to a fallback evaluator
    -- instead of silently returning FALSE. Empty ⇒ everything lowered
    -- cleanly.
  , diagnostics :: Map Text [Text]
    -- | M5 slice 2C — true while we're lowering the body of a `<fn>$trace`
    -- clone. When set, 'lowerExpr' brackets each traceable subexpression
    -- with @__l4_trace_enter(id)@ / @__l4_trace_exit(box, kind)@ using
    -- 'traceNodeMap' to look up the compile-time-assigned node ID.
    -- False during the untraced `<fn>` pass so the fast path stays
    -- untouched.
  , tracing :: !Bool
    -- | Per-traceable-subexpression metadata in the function currently
    -- being lowered. Same shape jl4-service's @simplifyEvalTrace@ would
    -- preserve. Built once per function by 'Schema.collectTraceNodes' and
    -- consumed by 'lowerExpr' through 'rangeOf'.
  , traceNodeMap :: !(Map Schema.TraceRangeKey (Int, Int))
    -- | Node ID of the innermost @__l4_trace_enter@ that hasn't been
    -- matched by a @__l4_trace_exit@ yet. When the 'lowerExpr' wrapper
    -- sees an inner expression whose rangeMap lookup returns this same
    -- id, it skips the duplicate enter/exit — needed because the parser
    -- sometimes gives @NOT P@ and the inner @P@ the same 'SrcRange', so
    -- both wrappers would otherwise emit a second nested frame on top
    -- of the same trace node.
  , openTraceNode :: !(Maybe Int)
    -- | M5 slice 4D (call-site translation) — sanitized function name
    -- ⟶ ordered list of its parameter source names (e.g.
    -- @"annual_interest_rate"@ ⟶ @["profile"]@). At each function call
    -- in trace mode, the App-case helper uses this to pair each
    -- compound static-path arg with the callee's parameter name and
    -- emit a @__l4_trace_push_arg_path(callee-param, caller-path)@
    -- call before the wasm call (and a @_pop_@ after), so the
    -- helper's marker paths (@\"profile.bankruptcy history\"@) rewrite
    -- to the caller's view (@\"req.applicant.bankruptcy history\"@).
  , funcParams :: !(Map Text [Text])
    -- | Names of DECIDEs currently being lowered (the enclosing chain).
    -- A zero-arg WHERE/LET binding whose body free-vars intersect this
    -- set is potentially mutually recursive — eager evaluation would
    -- loop, so 'lowerLocalDecl' lambda-lifts it instead.
  , pendingDecide :: !(Set.Set Text)
    -- | Mangled symbols already claimed by an emitted @func.func@ body,
    -- keyed by @(sanitizedName, arity)@ — the exact tuple
    -- 'dedupAndSynthExterns' mangles to a single WASM symbol
    -- (@name__$arity@). L4 allows ad-hoc overloading, so two genuinely
    -- different top-level definitions can share a name AND an arity
    -- (e.g. @daydate@'s four arity-1 @Date@ overloads, distinguished
    -- only by their parameter *type*). The dedup post-pass keeps just
    -- the FIRST body per mangled symbol and silently drops the rest, so
    -- calls that meant a later overload would dispatch to the wrong
    -- body. We can't disambiguate by type at the f64 ABI, so when a
    -- second body collides on this key we 'markUnsupported' both the
    -- prior and the current definition (keyed by their shared
    -- 'Schema.wasmSymbol') — fail loud instead of silently wrong.
    --
    -- The value records WHICH definition claimed the symbol (its
    -- 'Unique'), because a repeat is only a collision if it comes from a
    -- *different* definition. The same DECIDE legitimately reaches
    -- 'lowerDecide' twice — a lambda-lifted WHERE/LET helper is lowered
    -- once for its parent's untraced body and again for the parent's
    -- @$trace@ clone — and keying on the symbol alone reported that
    -- benign re-emission as an overload collision against itself.
  , emittedBodies :: !(Map (Text, Int) Unique)
    -- Disambiguated WASM symbols for same-arity overload sets. The
    -- arity-only mangle ('dedupAndSynthExterns') cannot separate two
    -- overloads with the SAME name AND arity but different argument types
    -- (e.g. @daydate@'s @Weekday of@ on NUMBER vs DATE), so they'd collapse
    -- to one symbol and dispatch to whichever body won the dedup. The
    -- typechecker already gives each overload a distinct 'getUnique', so we
    -- map that unique to a per-group-indexed symbol (@name__ovN@) and use it
    -- at BOTH the definition and every call site (which carries the same
    -- unique — name resolution links a 'Ref' to its 'Def's unique). Computed
    -- once by 'computeOverloadSymbols'; only populated for groups with no
    -- @\@export@ member (an exported same-arity collision is API-ambiguous
    -- and stays 'markUnsupported'). Names absent here use their plain symbol.
  , overloadSymbols :: !(Map Unique Text)
    -- | Static call graph over L4-level functions: caller's WASM symbol ⟶
    -- the symbols it calls directly. Recorded by 'callL4' / 'callL4Direct'
    -- (the two choke points for an L4→L4 @func.call@; runtime intrinsics
    -- are excluded — they can't carry diagnostics). Used by
    -- 'propagateDiagnostics' to lift a helper's unsupported-construct
    -- diagnostic up to every exported function that transitively calls it:
    -- 'markUnsupported' keys a diagnostic on the *enclosing* function, but
    -- 'Schema.applyDiagnostics' only downgrades entries in @bundleExports@,
    -- so an unsupported HELPER would be silently invoked by a still-
    -- @supported: true@ export. Fail loud instead: the export inherits the
    -- diagnostic and routes to the fallback evaluator.
  , callGraph :: !(Map Text (Set.Set Text))
    -- | Counter feeding 'localSymbolFor', which hands each lambda-lifted
    -- WHERE/LET helper its own WASM symbol. Local helper names are not
    -- globally unique — @prelude@ alone defines ten different recursive
    -- @go@ helpers (inside @sum@, @product@, @count@, @reverse@,
    -- @groupPairs@, …). They all sanitized to the bare symbol @go@ and, at
    -- the same arity, collapsed to ONE body under the arity-only mangle:
    -- @count@'s @go@ won, so @sum@ returned the list LENGTH and @product@
    -- returned length+1. Numbering each lifted helper keeps the bodies
    -- distinct. (The unique is memoized in 'overloadSymbols' so the
    -- untraced and @$trace@ lowerings of one helper agree on its symbol.)
  , nextLocalSym :: !Int
  }

type LowerM a = State LowerState a

initState :: InfoMap -> LowerState
initState info = LowerState
  { nextValue = 0
  , nextBlock = 0
  , bindings = Map.empty
  , bindingTypes = Map.empty
  , bindingL4Types = Map.empty
  , listElemTypes = Map.empty
  , typeEnv = emptyTypeEnv
  , currentOps = []
  , globals = []
  , functions = []
  , stringPool = Map.empty
  , nextString = 0
  , funcSigs = Map.empty
  , funcListElems = Map.empty
  , funcL4Types = Map.empty
  , typeSynonyms = Map.empty
  , sourceTypeMap = info
  , localCaptures = Map.empty
  , exportAssumeArgs = Map.empty
  , currentFunction = Nothing
  , diagnostics = Map.empty
  , tracing = False
  , traceNodeMap = Map.empty
  , openTraceNode = Nothing
  , funcParams = Map.empty
  , pendingDecide = Set.empty
  , emittedBodies = Map.empty
  , overloadSymbols = Map.empty
  , callGraph = Map.empty
  , nextLocalSym = 0
  }

-- | Look up the ground-truth type for an expression using the typechecker's
-- InfoMap.
--
-- Queries by the expression's full source range. Multiple intervals can
-- share a start position (a @Proj@ and its subject, a binary op and its
-- left operand, etc.), so 'IV.smallestContaining' alone would pick the
-- leftmost sub-term instead of *this* expression. We prefer an interval
-- whose range matches exactly our expression's range.
typeOfExpr :: HasSrcRange e => e -> LowerM (Maybe (Type' Resolved))
typeOfExpr e = do
  info <- gets (.sourceTypeMap)
  case rangeOf e of
    Nothing -> pure Nothing
    Just range -> do
      -- Only accept an *exact* range match. The typechecker records
      -- TypeInfo at each node's own range; approximate matches tend to
      -- pick a containing expression with a different type.
      let exactMatches =
            [ ty
            | (iv, TypeInfo ty _) <- IV.search range.start info
            , IV.intervalLow iv == range.start
            , IV.intervalHigh iv == range.end
            ]
      pure $ case exactMatches of
        (ty : _) -> Just ty
        []       -> Nothing


-- ---------------------------------------------------------------------------
-- ABI boxing / unboxing (see "L4.MLIR.ABI")
-- ---------------------------------------------------------------------------

-- | Under the uniform f64 ABI, every SSA value is already f64, so
-- boxing at the call-site / function-boundary is a no-op. These
-- helpers are retained to keep the call-convention call sites
-- self-documenting — the compiler knows where the conceptual
-- boundary is even though no real coercion needs to happen.
boxABI :: MLIRType -> Value -> LowerM Value
boxABI _ src = pure src

unboxABI :: MLIRType -> Value -> LowerM Value
unboxABI _ src = pure src

-- | Call another L4 function (local or extern) through the uniform f64
-- ABI. Boxes each native-typed argument to 'l4Value', emits the call
-- with an all-@f64@ signature, then unboxes the f64 return to the
-- caller's expected native type.
--
-- This is the /only/ way the lowering should invoke an L4 function.
-- Calls to runtime support routines ('__l4_*' helpers) that aren't
-- part of the L4 ABI can still use 'funcCall' directly.
-- | Call a runtime support routine (@__l4_*@). Every arg and the result
-- use the uniform f64 ABI; the host runtime (Node / Wasmtime) is
-- responsible for reinterpret-casting pointer payloads.
runtimeCall :: Text -> [Expr Resolved] -> LowerM Value
runtimeCall name es = do
  vs <- forM es (\e -> lowerExpr e l4NumberType)
  let tys = replicate (length vs) l4NumberType
  emitVal $ \vid -> funcCall [vid] name vs tys [l4NumberType]

-- | Apply a prelude helper with a lowered L4 body by routing through
-- 'callL4', so the trace pass picks the @\<name\>$trace@ variant
-- instead of jumping into the runtime fast path. Returns its result
-- as an f64 (the uniform ABI), which the caller then unboxes / uses
-- as a NUMBER handle as appropriate.
callPreludeL4 :: Text -> [Expr Resolved] -> LowerM Value
callPreludeL4 funcN args = do
  sigs <- gets (.funcSigs)
  let retTy = case Map.lookup funcN sigs of
        Just (_, r) -> r
        Nothing     -> l4NumberType
  argPairs <- forM args $ \arg -> do
    ty <- inferExprTypeM arg
    v  <- lowerExpr arg ty
    pure (v, ty)
  callL4 funcN argPairs retTy

-- | Record a @caller ⟶ callee@ edge in the static 'callGraph', so
-- 'propagateDiagnostics' can lift an unsupported helper's diagnostic up to
-- the exports that reach it. No-op outside a function body (no caller to
-- attribute the edge to). The *untraced* symbol is recorded: @fn@ and
-- @fn$trace@ are the same L4 function and share its diagnostics.
recordCallEdge :: Text -> LowerM ()
recordCallEdge callee = do
  mfn <- gets (.currentFunction)
  forM_ mfn $ \caller ->
    modify' $ \s ->
      s { callGraph = Map.insertWith Set.union caller (Set.singleton callee) s.callGraph }

callL4 :: Text -> [(Value, MLIRType)] -> MLIRType -> LowerM Value
callL4 callee args retTy = do
  recordCallEdge callee
  -- Internal callers of @export functions don't supply the ASSUME-derived
  -- args themselves; synthesise each by calling the ASSUME's own extern,
  -- preserving the pre-@export behaviour (the wasm host satisfies the
  -- import). Host calls supply the values directly and never hit this
  -- path (they enter through the function boundary, not callL4).
  fullArgs <- appendAssumeExternArgs callee args
  -- Box each arg at the call site.
  boxed <- forM fullArgs $ \(v, t) -> boxABI t v
  -- Emit the call with uniform f64 signature.
  let nArgs = length fullArgs
      sigArgs = replicate nArgs l4Value
  -- M5 slice 4A — when we're lowering inside `<fn>$trace`, route nested
  -- L4 calls to the callee's `$trace` variant so the recursive trace
  -- tree exists in `tracePool` too. The untraced `<fn>` pass leaves
  -- 'tracing' false and continues to call the fast `callee` symbol.
  tracingNow <- gets (.tracing)
  let actualCallee = if tracingNow then callee <> "$trace" else callee
  boxedResult <- emitVal $ \vid ->
    funcCall [vid] actualCallee boxed sigArgs [l4Value]
  -- Unbox the return to the expected native type.
  unboxABI retTy boxedResult

-- | Same as 'callL4' but never routes through @<callee>$trace@ — even
-- when tracing is enabled. Used by 0-arg @App@ in trace mode so the
-- helper's body events stay out of the parent's trace pool (jl4-core
-- treats a bare Var lookup as a single leaf with the helper's already-
-- evaluated value; we mirror that by force-tracing the call site and
-- calling the regular function inside).
callL4Direct :: Text -> [(Value, MLIRType)] -> MLIRType -> LowerM Value
callL4Direct callee args retTy = do
  recordCallEdge callee
  fullArgs <- appendAssumeExternArgs callee args
  boxed <- forM fullArgs $ \(v, t) -> boxABI t v
  let nArgs = length fullArgs
      sigArgs = replicate nArgs l4Value
  boxedResult <- emitVal $ \vid ->
    funcCall [vid] callee boxed sigArgs [l4Value]
  unboxABI retTy boxedResult

-- | For callees that were registered with extra ASSUME-derived parameters
-- (see 'exportAssumeArgs'), append one extern call per extra parameter so
-- the call site matches the callee's extended arity.
appendAssumeExternArgs :: Text -> [(Value, MLIRType)] -> LowerM [(Value, MLIRType)]
appendAssumeExternArgs callee args = do
  extras <- Map.findWithDefault [] callee <$> gets (.exportAssumeArgs)
  if null extras then pure args
  else do
    env <- gets (.typeEnv)
    extraPairs <- forM extras $ \(assumeRes, assumeTy) -> do
      let externName = sanitizeName (resolvedName assumeRes)
          mlTy = l4TypeToMLIR env assumeTy
      v <- emitVal $ \vid -> funcCall [vid] externName [] [] [l4Value]
      pure (v, mlTy)
    pure (args ++ extraPairs)

-- | Allocate a fresh SSA value.
fresh :: LowerM ValueId
fresh = do
  s <- get
  let vid = s.nextValue
  put s { nextValue = vid + 1 }
  pure vid

-- | Allocate a fresh block ID.
freshBlockId :: LowerM BlockId
freshBlockId = do
  s <- get
  let bid = s.nextBlock
  put s { nextBlock = bid + 1 }
  pure bid

-- | Emit an operation into the current block.
emit :: Operation -> LowerM ()
emit op = modify' $ \s -> s { currentOps = op : s.currentOps }

-- | Emit an operation and return its single result value.
emitVal :: (ValueId -> Operation) -> LowerM Value
emitVal mkOp_ = do
  vid <- fresh
  emit (mkOp_ vid)
  pure (SSAValue vid)

-- | Bind an L4 name to an SSA value.
-- Note: 'bind' (type-erased) is intentionally no longer exported. Use
-- 'bindTy' to preserve the variable's MLIR type in 'bindingTypes'.
_bind :: Text -> Value -> LowerM ()
_bind name val = modify' $ \s -> s { bindings = Map.insert name val s.bindings }

-- | Bind an L4 name with type info.
bindTy :: Text -> Value -> MLIRType -> LowerM ()
bindTy name val ty = modify' $ \s -> s
  { bindings = Map.insert name val s.bindings
  , bindingTypes = Map.insert name ty s.bindingTypes
  }

-- | Bind a list element type for a variable.
bindListElem :: Text -> MLIRType -> LowerM ()
bindListElem name ty = modify' $ \s -> s { listElemTypes = Map.insert name ty s.listElemTypes }

-- | Look up a bound name.
lookupVar :: Text -> LowerM (Maybe Value)
lookupVar name = gets $ Map.lookup name . (.bindings)

-- | Run a computation with local bindings (scoped).
withScope :: LowerM a -> LowerM a
withScope action = do
  savedBindings <- gets (.bindings)
  savedTypes <- gets (.bindingTypes)
  savedL4Types <- gets (.bindingL4Types)
  savedListTys <- gets (.listElemTypes)
  result <- action
  modify' $ \s -> s
    { bindings = savedBindings
    , bindingTypes = savedTypes
    , bindingL4Types = savedL4Types
    , listElemTypes = savedListTys
    }
  pure result

-- | Collect operations emitted during an action.
collectOps :: LowerM a -> LowerM (a, [Operation])
collectOps action = do
  saved <- gets (.currentOps)
  modify' $ \s -> s { currentOps = [] }
  result <- action
  ops <- gets (reverse . (.currentOps))
  modify' $ \s -> s { currentOps = saved }
  pure (result, ops)

-- | Register a string literal and return its global name.
internString :: Text -> LowerM Text
internString str = do
  pool <- gets (.stringPool)
  case Map.lookup str pool of
    Just name -> pure name
    Nothing -> do
      idx <- gets (.nextString)
      let name = "__str_" <> Text.pack (show idx)
      modify' $ \s -> s
        { stringPool = Map.insert str name s.stringPool
        , nextString = idx + 1
        , globals = llvmGlobalString name str : s.globals
        }
      pure name

-- | Record that the function currently being lowered contains a
-- construct the MLIR backend cannot faithfully compile, then emit a
-- uniform-ABI FALSE (0.0) so the IR stays well-formed.
--
-- This is the difference between *silent* and *loud* degradation: the
-- old behaviour emitted 0.0 with no record, so a deployment containing
-- (say) a deontic rule compiled "successfully" and returned a wrong
-- FALSE answer. Now the enclosing function is flagged (keyed by its
-- sanitized WASM symbol, matching 'Schema.wasmSymbol') and the pipeline
-- marks the schema export @supported: false@ so the proxy routes it to
-- a fallback evaluator. See FEATURE-PARITY-PLAN.md (M1a).
markUnsupported :: Text -> LowerM Value
markUnsupported reason = do
  mfn <- gets (.currentFunction)
  forM_ mfn $ \fn ->
    modify' $ \s ->
      s { diagnostics = Map.insertWith (\new old -> old ++ new) fn [reason] s.diagnostics }
  emitVal $ \vid -> arithConstantFloat vid 0.0

-- ---------------------------------------------------------------------------
-- Module lowering
-- ---------------------------------------------------------------------------

-- | Lower an L4 program (module + dependencies) to MLIR.
--
-- For each dependency module we only register *types* and *function
-- signatures* (as extern declarations) — not the function bodies.
-- That gives the main module everything it needs to type-check calls
-- into imported functions while keeping each symbol defined exactly
-- once and avoiding the wasm-ld @redefinition of symbol@ error.
--
-- Before emitting any extern declarations, we collect the set of names
-- the main module will define locally, so that a dep re-declaration of
-- the same name (common in files that shadow prelude helpers) doesn't
-- produce a duplicate symbol.
lowerProgram :: Module Resolved -> [Module Resolved] -> MLIRModule
lowerProgram = lowerProgramWithInfo IV.empty Map.empty

-- | Like 'lowerProgram' but threads the typechecker's 'InfoMap' and
-- (substituted) 'EntityInfo' through so the lowering can query
-- ground-truth types for every expression and every known term.
-- This is the preferred entry point — callers that already have a
-- 'TypeCheckResult' should pass its @infoMap@ and @entityInfo@ fields
-- here.
lowerProgramWithInfo :: InfoMap -> EntityInfo -> Module Resolved -> [Module Resolved] -> MLIRModule
lowerProgramWithInfo info entInfo mainMod deps =
  fst (lowerProgramWithDiagnostics info entInfo mainMod deps)

-- | Like 'lowerProgramWithInfo' but also returns the per-function
-- lowering diagnostics — a map from sanitized WASM symbol name to the
-- reasons that function cannot be faithfully compiled (unsupported
-- regulative/IO/lambda constructs). An empty map means every function
-- lowered cleanly. The pipeline threads these into the schema so the
-- proxy can mark exports @supported: false@ and route them to a
-- fallback evaluator instead of trusting a WASM module that would
-- silently return FALSE.
lowerProgramWithDiagnostics
  :: InfoMap -> EntityInfo -> Module Resolved -> [Module Resolved] -> (MLIRModule, Map Text [Text])
lowerProgramWithDiagnostics info entInfo mainMod deps =
  let mainNames = collectLocalNames mainMod
      exportArgs = collectExportAssumeArgs mainMod
      initial = (initState info)
        { exportAssumeArgs = exportArgs
        , overloadSymbols  = computeOverloadSymbols (mainMod : deps)
        , funcL4Types      = knownTermTypes entInfo
        , typeSynonyms     = Map.unions (map collectTypeSynonyms (mainMod : deps))
        }
      finalState = execState (do
        forM_ deps (registerDependencyModule mainNames)
        lowerModuleDecls mainMod
        ) initial
      rawOps = reverse finalState.globals ++ reverse finalState.functions
      diags = propagateDiagnostics finalState.callGraph finalState.diagnostics
  in (MLIRModule { moduleOps = rawOps }, diags)

-- | Project the typechecker's 'EntityInfo' down to the 'funcL4Types' map:
-- every 'KnownTerm' entity's checked type, keyed by its 'Unique'. This is
-- ground truth for the L4-level type of any resolved reference — a 'Ref'
-- shares its 'Def's unique, so a call site's head 'Resolved' looks up the
-- callee's own checked type, across module boundaries and irrespective of
-- the f64 ABI erasure in 'funcSigs'.
knownTermTypes :: EntityInfo -> Map Unique (Type' Resolved)
knownTermTypes = Map.mapMaybe $ \(_, entity) -> case entity of
  KnownTerm ty _ -> Just ty
  _              -> Nothing

-- | Collect user-declared type SYNONYMS (@DECLARE Foo IS A STRING@) from a
-- module, keyed by the synonym's name. Populates 'LowerState.typeSynonyms'
-- so 'classifyOperand' can unfold a synonym-typed comparison operand to its
-- underlying scalar (STRING\/NUMBER\/…) rather than mis-classifying the
-- opaque 'TyApp' head as 'CmpOther'. Record\/enum declares are not
-- synonyms and are skipped; genuine builtin DATE\/TIME are not declares at
-- all, so they never appear here and keep their serial semantics.
collectTypeSynonyms :: Module Resolved -> Map Text (Type' Resolved)
collectTypeSynonyms (MkModule _ _ section) = Map.fromList (goSection section)
  where
    goSection (MkSection _ _ _ decls) = concatMap goDecl decls
    goDecl = \case
      Declare _ (MkDeclare _ _ (MkAppForm _ name _ _) (SynonymDecl _ inner)) ->
        [(resolvedName name, inner)]
      Section _ sub -> goSection sub
      _ -> []

-- | Lift each unsupported-construct diagnostic to every function that
-- transitively calls the function it was raised in.
--
-- 'markUnsupported' attributes a diagnostic to the *enclosing* function, but
-- 'Schema.applyDiagnostics' only downgrades entries in @bundleExports@. A
-- helper is not an export, so without this pass an exported function whose
-- helper contains an unsupported construct stays @supported: true@ and the
-- proxy happily runs a WASM module that cannot evaluate it — the helper's
-- fail-closed 0.0/FALSE surfaces as a silently wrong ANSWER rather than a
-- refusal. (Concretely: @daydate@'s @is weekend@ compares a helper-result
-- NUMBER that 'lowerCmp' can't classify, so it raises a diagnostic — but the
-- exported @is a weekday@ that calls it did not inherit it.)
--
-- Fail loud instead: an export that reaches an unsupported helper is itself
-- unsupported, and routes to the fallback evaluator. The reason names the
-- helper so the refusal is diagnosable.
--
-- Cycles (self- and mutual recursion) are fine — reachability is computed
-- with a visited set. A function that is its own ancestor doesn't get a
-- propagated copy of its own reason; its direct one already says it.
propagateDiagnostics :: Map Text (Set.Set Text) -> Map Text [Text] -> Map Text [Text]
propagateDiagnostics cg direct = Map.unionWith (++) direct propagated
  where
    -- Reverse the call graph: callee ⟶ its direct callers.
    callers :: Map Text (Set.Set Text)
    callers = Map.fromListWith Set.union
      [ (callee, Set.singleton caller)
      | (caller, callees) <- Map.toList cg
      , callee <- Set.toList callees
      ]

    -- Every function that transitively calls @fn@ (BFS over the reverse
    -- edges; @seen@ terminates on recursion).
    ancestorsOf :: Text -> Set.Set Text
    ancestorsOf fn = go Set.empty [fn]
      where
        go seen [] = seen
        go seen (f : rest)
          | f `Set.member` seen = go seen rest
          | otherwise =
              let ups = Map.findWithDefault Set.empty f callers
              in go (Set.insert f seen) (Set.toList ups ++ rest)

    propagated :: Map Text [Text]
    propagated = Map.fromListWith (++)
      [ (caller, [reasonFor helper reasons])
      | (helper, reasons) <- Map.toList direct
      , caller <- Set.toList (ancestorsOf helper)
      , caller /= helper
      ]

    reasonFor helper reasons =
      "depends on '" <> helper <> "', which the WASM backend cannot compile: "
        <> Text.intercalate "; " reasons

-- | For every @\@export@-decorated DECIDE in the main module, collect the
-- ASSUME declarations it references. These get promoted to function-level
-- parameters at the ABI boundary so hosts can supply their values without
-- going through the extern-import mechanism used by non-exported DECIDEs.
collectExportAssumeArgs :: Module Resolved -> Map Text [(Resolved, Type' Resolved)]
collectExportAssumeArgs mod' = Map.fromList
  [ (sanitizeName (resolvedName fnName), args)
  | decide@(MkDecide _ _ (MkAppForm _ fnName _ _) _) <- exportedDecides
  , let args = Export.extractAssumeParamResolveds mod' decide
  , not (null args)
  ]
 where
  exportedDecides = goSection sect
  MkModule _ _ sect = mod'
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d | Export.isExportedDecide d -> [d]
    Section _ s -> goSection s
    _ -> []

-- | Every DECIDE in a module, descending into nested sections.
allModuleDecides :: Module Resolved -> [Decide Resolved]
allModuleDecides (MkModule _ _ sect) = goSection sect
  where
    goSection (MkSection _ _ _ decls) = concatMap goDecl decls
    goDecl (Decide _ d)  = [d]
    goDecl (Section _ s) = goSection s
    goDecl _             = []

-- | Compute the disambiguated WASM symbol for every same-arity overload that
-- needs one. Two DECIDEs sharing a sanitized name AND arity (but differing in
-- argument type — which the f64 ABI erases) would collapse to one symbol under
-- the arity-only mangle; here we give each a distinct @name__ovN@ keyed on its
-- 'getUnique'. Call sites carry the same unique (a 'Ref' shares its 'Def's
-- unique), so definition and call agree. Groups that contain an @\@export@
-- member are left out: an exported same-arity collision is ambiguous at the
-- JSON API and stays 'markUnsupported' (routed to fallback), and skipping them
-- also avoids desyncing 'Schema.wasmSymbol' for exports. See 'overloadSymbols'.
computeOverloadSymbols :: [Module Resolved] -> Map Unique Text
computeOverloadSymbols mods =
  let decides = concatMap allModuleDecides mods
      entries =
        [ ((sanitizeName (resolvedName h), arity), (getUnique h, Export.isExportedDecide d))
        | d@(MkDecide _ _ af _) <- decides
        , let h = appFormHead' af
              arity = length (appFormParams af)
        ]
      byKey = Map.fromListWith (flip (++)) [ (k, [v]) | (k, v) <- entries ]
  in Map.fromList
       [ (u, base <> "__ov" <> Text.pack (show idx))
       | ((base, _arity), members) <- Map.toList byKey
       , let distinct = dedupByUnique members
       , length distinct > 1          -- a genuine same-arity overload set
       , not (any snd distinct)        -- and none of them is @export'd
       , (idx, (u, _)) <- zip [(0 :: Int) ..] distinct
       ]
  where
    -- Distinct by unique, first occurrence wins, source order preserved.
    dedupByUnique = go Set.empty
      where
        go _ [] = []
        go seen ((u, ex) : rest)
          | Set.member u seen = go seen rest
          | otherwise         = (u, ex) : go (Set.insert u seen) rest

-- | The WASM symbol for a resolved function reference\/definition: the
-- per-overload disambiguated name when it belongs to a same-arity overload
-- set ('overloadSymbols'), otherwise the plain sanitized name. Use this
-- everywhere a function symbol is derived from a 'Resolved' so a definition
-- and its call sites agree.
symbolFor :: Resolved -> LowerM Text
symbolFor r = do
  ov <- gets (.overloadSymbols)
  pure (Map.findWithDefault (sanitizeName (resolvedName r)) (getUnique r) ov)

-- | The WASM symbol for a lambda-lifted WHERE/LET helper, allocating a fresh
-- numbered one on first sight and memoizing it under the helper's 'Unique'.
--
-- Local helper names are scoped in L4 but FLAT once lifted to a top-level
-- @func.func@, and they are anything but unique: @prelude@ defines ten
-- separate recursive @go@ helpers. Lifting them all to the bare symbol @go@
-- made the arity-only mangle collapse every arity-2 @go@ into one body —
-- silently giving @sum@, @product@, @reverse@, @dictSize@, @dictDelete@ and
-- @groupPairs@ whichever body happened to win (@count@'s), so @sum@ returned
-- the list length. Numbering them keeps each body its own symbol.
--
-- Memoizing on the 'Unique' (rather than allocating per call) is what makes
-- the untraced and @$trace@ lowerings of the same helper — and every call
-- site, which reaches this through 'symbolFor' because a 'Ref' shares its
-- 'Def's unique — all agree on one symbol.
localSymbolFor :: Resolved -> LowerM Text
localSymbolFor r = do
  ov <- gets (.overloadSymbols)
  let u = getUnique r
  case Map.lookup u ov of
    Just sym -> pure sym
    Nothing  -> do
      n <- gets (.nextLocalSym)
      let sym = sanitizeName (resolvedName r) <> "__loc" <> Text.pack (show n)
      modify' $ \s -> s
        { overloadSymbols = Map.insert u sym s.overloadSymbols
        , nextLocalSym    = n + 1
        }
      pure sym

-- | Final pass run by 'L4.MLIR.Pipeline' once all operations — including
-- runtime builtins — have been assembled. It handles three consumers
-- of MLIR symbol names that don't naturally agree:
--
--   1. @func.func@ bodies — the lowering may emit several bodies with
--      the same L4 name because L4 supports ad-hoc overloading (the
--      @daydate@ library has 'Date', 'Time', 'Datetime' with 1, 2, 3
--      and 4 parameters). WASM/MLIR don't allow duplicate symbols.
--   2. @func.func@ extern declarations inherited from dep modules —
--      may report the wrong arity when the dep has overloaded names.
--   3. @func.call@ sites — the consumer — signatures must match exactly.
--
-- We resolve all of these by __arity-based name mangling__: every
-- @name@ that has more than one definition is rewritten as
-- @name__$arity@ everywhere — in definitions, externs, *and* in call
-- sites. After mangling there's exactly one definition per sanitized
-- symbol. Names used with only a single arity keep their original
-- name (zero-overhead path for the common case).
dedupAndSynthExterns :: [Operation] -> [Operation]
dedupAndSynthExterns ops =
  let isRuntimeBuiltin n = "__l4_" `Text.isPrefixOf` n || "__str_" `Text.isPrefixOf` n

      -- Collect every arity *any name* shows up with — whether from a
      -- @func.func@ declaration/body or a @func.call@ site. Call-site
      -- arities are authoritative (the caller's signature must match)
      -- so we include them when deciding whether to mangle.
      defArities =
        [ (funcSymName op, funcArity op)
        | op <- ops
        , op.opName == "func.func"
        , not (isRuntimeBuiltin (funcSymName op))
        , not (Text.null (funcSymName op))
        ]
      callSiteArities =
        [ (funcCalleeName op, length op.opOperands)
        | op <- allOps ops
        , op.opName == "func.call"
        , let callee = funcCalleeName op
        , not (Text.null callee)
        , not (isRuntimeBuiltin callee)
        ]
      allAritiesByName = Map.fromListWith Set.union
        [ (name, Set.singleton arity)
        | (name, arity) <- defArities <> callSiteArities
        ]

      -- A name needs mangling iff it's referenced at more than one
      -- distinct arity across its bodies, externs, and call sites.
      overloaded = Set.fromList
        [ name
        | (name, arities) <- Map.toList allAritiesByName
        , Set.size arities > 1
        ]

      -- Compute the mangled name for a call site or declaration. If
      -- the name isn't overloaded, return it unchanged.
      mangled :: Text -> Int -> Text
      mangled name arity
        | name `Set.member` overloaded = name <> "__" <> Text.pack (show arity)
        | otherwise = name

      -- Rewrite every func.func and func.call to use the mangled name.
      mangleOp :: Operation -> Operation
      mangleOp op
        | op.opName == "func.func" =
            let name = funcSymName op
                arity = funcArity op
            in op
              { opAttributes = map (mangleAttr "sym_name" (mangled name arity)) op.opAttributes
              , opRegions = map mangleRegion op.opRegions
              }
        | op.opName == "func.call" =
            let name = funcCalleeName op
                arity = length op.opOperands
            in op
              { opAttributes = map (mangleAttrSymRef "callee" (mangled name arity)) op.opAttributes
              }
        | otherwise = op { opRegions = map mangleRegion op.opRegions }

      mangleAttr key newValue na
        | na.attrName == key = na { attrValue = StringAttr newValue }
        | otherwise = na

      mangleAttrSymRef key newValue na
        | na.attrName == key = na { attrValue = FlatSymbolRefAttr newValue }
        | otherwise = na

      mangleRegion r = r { regionBlocks = map mangleBlock r.regionBlocks }
      mangleBlock b  = b { blockOps = map mangleOp b.blockOps }

      mangledOps = map mangleOp ops

      -- Now every symbol has a unique name. Collect defined bodies and
      -- generate uniform-ABI externs for any called name that still
      -- lacks a definition. Runtime builtins pass through verbatim.
      callArities = Map.fromList
        [ (callee, length op.opOperands)
        | op <- allOps mangledOps
        , op.opName == "func.call"
        , let callee = funcCalleeName op
        , not (Text.null callee)
        ]
      definedBodies = Set.fromList
        [ funcSymName op
        | op <- mangledOps
        , op.opName == "func.func"
        , not (null op.opRegions)
        ]

      keepBody op         = op.opName == "func.func" && not (null op.opRegions)
      keepRuntimeExtern op = op.opName == "func.func"
        && null op.opRegions && isRuntimeBuiltin (funcSymName op)
      keepNonFunc op      = op.opName /= "func.func"

      bodies         = filter keepBody mangledOps
      runtimeExterns = filter keepRuntimeExtern mangledOps
      others         = filter keepNonFunc mangledOps

      synthExterns =
        [ mkExternFunc name (replicate arity l4Value) l4Value
        | (name, arity) <- Map.toList callArities
        , name `Set.notMember` definedBodies
        , not (isRuntimeBuiltin name)
        ]
  in others <> dedupByName (runtimeExterns <> synthExterns) <> dedupByName bodies

-- | Count the declared parameters of a @func.func@ operation by reading
-- its @function_type@ attribute.
funcArity :: Operation -> Int
funcArity op =
  case [ft | NamedAttribute k (TypeAttr ft) <- op.opAttributes, k == "function_type"] of
    (FunctionType args _ : _) -> length args
    _ -> 0

-- | The symbol referenced by a @func.call@'s @callee@ attribute.
funcCalleeName :: Operation -> Text
funcCalleeName op =
  case [s | NamedAttribute k (FlatSymbolRefAttr s) <- op.opAttributes, k == "callee"] of
    (s : _) -> s
    []      -> ""

-- | Keep only the first @func.func@ occurrence per @sym_name@.
dedupByName :: [Operation] -> [Operation]
dedupByName = go Set.empty
  where
    go _ [] = []
    go seen (op : rest)
      | op.opName == "func.func" =
          let name = funcSymName op
          in if Text.null name || name `Set.member` seen
               then go seen rest
               else op : go (Set.insert name seen) rest
      | otherwise = op : go seen rest

funcSymName :: Operation -> Text
funcSymName op =
  case [s | NamedAttribute k (StringAttr s) <- op.opAttributes, k == "sym_name"] of
    (s : _) -> s
    []      -> ""


-- | Recursively walk all operations (including those inside regions).
allOps :: [Operation] -> [Operation]
allOps = concatMap walk
  where
    walk op = op : concatMap (concatMap walk . (.blockOps)) (concatMap (.regionBlocks) op.opRegions)


-- | Collect the sanitized names of everything the module will define locally.
-- Covers DECIDEs, ASSUMEs, and local-function DECIDEs inside WHERE / LET.
collectLocalNames :: Module Resolved -> Set.Set Text
collectLocalNames (MkModule _ _ section) = goSection section
  where
    goSection (MkSection _ _ _ decls) = foldr (Set.union . goDecl) Set.empty decls
    goDecl = \case
      Decide _ (MkDecide _ _ appForm _) ->
        Set.singleton (sanitizeName (resolvedName (appFormHead' appForm)))
      Assume _ (MkAssume _ _ appForm _ _) ->
        Set.singleton (sanitizeName (resolvedName (appFormHead' appForm)))
      Section _ s -> goSection s
      _ -> Set.empty

-- | Walk a dependency module: register record/enum declarations and
-- function signatures, and emit @func.func private@ extern declarations
-- for every @DECIDE@ and @ASSUME@ that the main module does not itself
-- define. No function bodies are emitted.
registerDependencyModule :: Set.Set Text -> Module Resolved -> LowerM ()
registerDependencyModule skipLocal (MkModule _ _ section) = go section
  where
    go (MkSection _ _ _ decls) = forM_ decls processDep

    processDep :: TopDecl Resolved -> LowerM ()
    processDep = \case
      Declare _ d -> lowerDeclare d
      Decide _ d  -> processDepDecide d
      Assume _ a  -> registerExternAssume a
      Section _ s -> go s
      _ -> pure ()

    shouldSkip :: Text -> LowerM Bool
    shouldSkip name = do
      existing <- gets (Map.lookup name . (.funcSigs))
      pure (Set.member name skipLocal || existing /= Nothing)

    -- For a dep 'Decide' we emit a real function body when the type
    -- signature is free of function-typed parameters (the MLIR backend
    -- doesn't yet support higher-order calls). Otherwise we fall back
    -- to an extern declaration — the call site will get a symbolic
    -- reference that fails at link time if actually invoked, but won't
    -- break the module for unrelated calls.
    processDepDecide :: Decide Resolved -> LowerM ()
    processDepDecide decide@(MkDecide _ typeSig appForm _) = do
      name <- symbolFor (appFormHead' appForm)
      skip <- shouldSkip name
      unless skip $
        if sigHasFunctionParam typeSig
          then registerExternDecide decide
          else lowerDecide decide

    registerExternDecide :: Decide Resolved -> LowerM ()
    registerExternDecide (MkDecide _ typeSig appForm _body) = do
      env <- gets (.typeEnv)
      name <- symbolFor (appFormHead' appForm)
      let (argTypes, sigRetType) = sigToTypesEnv env typeSig
          retType = if hasGiveth typeSig then sigRetType else l4NumberType
          argListElems = listElementsFromSig env typeSig
          declOp = mkExternFunc name argTypes retType
      modify' $ \s -> s
        { funcSigs = Map.insert name (argTypes, retType) s.funcSigs
        , funcListElems = Map.insert name argListElems s.funcListElems
        , globals = declOp : s.globals
        }

    registerExternAssume :: Assume Resolved -> LowerM ()
    registerExternAssume (MkAssume _ typeSig appForm _ _) = do
      env <- gets (.typeEnv)
      let name = sanitizeName (resolvedName (appFormHead' appForm))
          (_, retType) = sigToTypesEnv env typeSig
          declOp = mkExternFunc name [] retType
      skip <- shouldSkip name
      unless skip $ modify' $ \s -> s
        { funcSigs = Map.insert name ([], retType) s.funcSigs
        , globals = declOp : s.globals
        }

-- | Build a @func.func private@ external declaration (no body).
-- All argument and return types are the uniform 'l4Value' ABI type
-- (see "L4.MLIR.ABI"). Call sites are responsible for boxing their
-- arguments and unboxing the return value back to the expected native
-- type.
mkExternFunc :: Text -> [MLIRType] -> MLIRType -> Operation
mkExternFunc name argTypes _retType =
  let n = length argTypes
      uniformArgs = replicate n l4Value
  in mkExternFunc' name uniformArgs l4Value

mkExternFunc' :: Text -> [MLIRType] -> MLIRType -> Operation
mkExternFunc' name argTypes retType = Operation
  { opResults = []
  , opName = "func.func"
  , opOperands = []
  , opAttributes =
      [ NamedAttribute "sym_name" (StringAttr name)
      , NamedAttribute "function_type" (TypeAttr (FunctionType argTypes [retType]))
      , NamedAttribute "sym_visibility" (StringAttr "private")
      ]
  , opResultTypes = []
  , opOperandTypes = []
  , opRegions = []
  , opSuccessors = []
  }

-- | Lower a single L4 module.
lowerModule :: Module Resolved -> MLIRModule
lowerModule m = lowerProgram m []

-- | Process all top-level declarations in a module.
lowerModuleDecls :: Module Resolved -> LowerM ()
lowerModuleDecls (MkModule _ _ section) = lowerSection section

lowerSection :: Section Resolved -> LowerM ()
lowerSection (MkSection _ _ _ decls) = do
  -- Three-pass: (1) register types, (2) register function signatures, (3) lower bodies
  forM_ decls registerTypeDecl
  forM_ decls registerFuncSig
  forM_ decls lowerTopDecl

-- | Pre-pass: register type declarations so they're available during lowering.
registerTypeDecl :: TopDecl Resolved -> LowerM ()
registerTypeDecl (Declare _ decl) = lowerDeclare decl
registerTypeDecl (Section _ sect) = do
  let MkSection _ _ _ ds = sect
  forM_ ds registerTypeDecl
registerTypeDecl _ = pure ()

-- | Pre-pass: register function signatures so calls can look up arg types.
registerFuncSig :: TopDecl Resolved -> LowerM ()
registerFuncSig (Decide _ (MkDecide _ typeSig appForm body)) = do
  env <- gets (.typeEnv)
  name <- symbolFor (appFormHead' appForm)
  let (argTypes, sigRetType) = sigToTypesEnv env typeSig
      argListElems = listElementsFromSig env typeSig
  -- Exported DECIDEs that reference module-level ASSUMEs get those ASSUMEs
  -- appended as extra arguments in the ABI.
  extraArgs <- Map.findWithDefault [] name <$> gets (.exportAssumeArgs)
  let extraArgTypes = [l4TypeToMLIR env ty | (_, ty) <- extraArgs]
      extraListElems = [Nothing | _ <- extraArgs]
  -- For MEANS bindings, infer type statefully (may reference other registered bindings)
  inferredRet <- inferExprTypeM body
  let retType = if hasGiveth typeSig then sigRetType else inferredRet
  modify' $ \s -> s
    { funcSigs = Map.insert name (argTypes ++ extraArgTypes, retType) s.funcSigs
    , funcListElems = Map.insert name (argListElems ++ extraListElems) s.funcListElems
    }
registerFuncSig (Section _ sect) = do
  let MkSection _ _ _ ds = sect
  forM_ ds registerFuncSig
registerFuncSig _ = pure ()

-- | Extract list element types from a function signature's parameters.
-- For each parameter, returns Just (element type) if parameter is LIST OF T, else Nothing.
listElementsFromSig :: TypeEnv -> TypeSig Resolved -> [Maybe MLIRType]
listElementsFromSig env (MkTypeSig _ (MkGivenSig _ params) _) =
  map paramListElem params
  where
    paramListElem (MkOptionallyTypedName _ _ (Just ty) _) = listOfElem env ty
    paramListElem _ = Nothing

-- | If a type is LIST OF T, return Just (MLIR type of T).
listOfElem :: TypeEnv -> Type' Resolved -> Maybe MLIRType
listOfElem env (TyApp _ n [inner]) | rawNameToText (rawName (getActual n)) == "LIST" =
  Just (l4TypeToMLIR env inner)
listOfElem _ _ = Nothing

lowerTopDecl :: TopDecl Resolved -> LowerM ()
lowerTopDecl = \case
  Declare _ decl -> lowerDeclare decl
  Decide _ decl  -> lowerDecide decl
  Section _ sect -> lowerSection sect
  Assume _ assume -> lowerAssume assume
  Directive _ _  -> pure ()
  Import _ _     -> pure ()
  -- 'TIMEZONE IS <expr>' establishes the document default timezone and
  -- must be visible to library helpers that reference the name
  -- 'TIMEZONE' (notably 'Datetime' constructors that take no explicit
  -- tz). Emit a zero-arg function that evaluates the expression and
  -- returns the IANA string pointer.
  Timezone _ expr -> lowerTimezoneDirective expr

-- | Emit a zero-arg 'TIMEZONE()' function whose body returns the
-- IANA-tz string specified by the 'TIMEZONE IS ...' directive.
lowerTimezoneDirective :: Expr Resolved -> LowerM ()
lowerTimezoneDirective expr = do
  let retType = l4NumberType
  entryBlock <- freshBlockId
  withScope $ do
    (resultVal, bodyOps) <- collectOps $ lowerExpr expr retType
    (boxedResult, boxOps) <- collectOps $ boxABI retType resultVal
    let retOp = funcReturn [boxedResult] [l4Value]
        block = Block
          { blockId = entryBlock
          , blockArgs = []
          , blockOps = bodyOps ++ boxOps ++ [retOp]
          }
        region = Region [block]
        funcOp = funcFunc "TIMEZONE" [] [l4Value] region
    modify' $ \s -> s
      { functions = funcOp : s.functions
      , funcSigs = Map.insert "TIMEZONE" ([], retType) s.funcSigs
      }

-- | An @ASSUME@ declaration in L4 is an external parameter — a value
-- that must be supplied by the caller/host. We emit it as an MLIR
-- @func.func private@ declaration (no body) so that references to
-- this name in the compiled module resolve to a valid WASM import
-- that the runtime host can satisfy.
lowerAssume :: Assume Resolved -> LowerM ()
lowerAssume (MkAssume _ typeSig appForm mType _mTypically) = do
  env <- gets (.typeEnv)
  let name = sanitizeName (resolvedName (appFormHead' appForm))
      -- An ASSUME may have arity, either via its GIVEN sig or its
      -- optional explicit type annotation (e.g. @ASSUME f IS A FUNCTION
      -- FROM Foo TO Bar@). Use whichever carries arity information.
      (sigArgs, sigRet) = sigToTypesEnv env typeSig
      (argTypes, retType) = case mType of
        -- Explicit @IS A FUNCTION FROM a AND b TO r@: use the function type
        Just (Fun _ fArgs fRet) ->
          ( [l4TypeToMLIR env (funArgTy a) | a <- fArgs]
          , l4TypeToMLIR env fRet )
        -- Explicit non-function type: zero-arg accessor of that type
        Just ty | null sigArgs -> ([], l4TypeToMLIR env ty)
        -- Otherwise fall back to the GIVEN signature (may still have args)
        _ -> (sigArgs, sigRet)
      declOp = mkExternFunc name argTypes retType
  modify' $ \s -> s
    { funcSigs = Map.insert name (argTypes, retType) s.funcSigs
    , globals  = declOp : s.globals
    }
  where
    funArgTy (MkOptionallyNamedType _ _ ty) = ty

-- ---------------------------------------------------------------------------
-- Type declarations
-- ---------------------------------------------------------------------------

lowerDeclare :: Declare Resolved -> LowerM ()
lowerDeclare (MkDeclare _ _ appForm typeDecl) = do
  env <- gets (.typeEnv)
  let name = resolvedName (appFormHead' appForm)
  case typeDecl of
    RecordDecl _ _ fields -> do
      let fieldInfos = [(fieldName f, l4TypeToMLIR env (fieldType f)) | f <- fields]
      modify' $ \s -> s { typeEnv = registerRecord name fieldInfos s.typeEnv }

    EnumDecl _ variants -> do
      let variantInfos = zipWith (\(MkConDecl _ n _) i -> (resolvedName n, i)) variants [0..]
      modify' $ \s -> s { typeEnv = registerEnum name variantInfos s.typeEnv }

    SynonymDecl _ _ -> pure ()  -- Type synonyms are erased
  where
    fieldName :: TypedName Resolved -> Text
    fieldName (MkTypedName _ n _ _ _) = resolvedName n

    fieldType :: TypedName Resolved -> Type' Resolved
    fieldType (MkTypedName _ _ ty _ _) = ty

-- ---------------------------------------------------------------------------
-- Function/decision lowering
-- ---------------------------------------------------------------------------

-- | M5 slice 2B: kind byte the runtime uses to render the trace's
-- @Result: …@ line. Constants must match @renderTraceResult@ in
-- @runtime/jl4-runtime.mjs@. The discriminator is the *L4 semantic* type
-- of the value, not its MLIR wire type — every kind is f64 on the wire.
traceResultKindForRetType :: TypeSig Resolved -> Int
traceResultKindForRetType (MkTypeSig _ _ (Just (MkGivethSig _ ty))) = traceResultKindForL4Type ty
traceResultKindForRetType _ = 3

traceResultKindForL4Type :: Type' Resolved -> Int
traceResultKindForL4Type t = case t of
  TyApp _ n _
    | resolvedName n `elem` ["NUMBER", "number"]   -> 0
    | resolvedName n `elem` ["BOOLEAN", "boolean"] -> 1
    | resolvedName n `elem` ["STRING", "string"]   -> 2
  _ -> 3

-- | Emit @__l4_trace_enter(nodeId)@ — a void runtime call. The lowering
-- passes nodeId as a plain @arith.constant@ f64 value (not a bit-cast),
-- and the runtime reads it back with @Number(nodeIdF)@.
emitTraceEnter :: Int -> LowerM ()
emitTraceEnter nodeId = do
  nodeVal <- emitVal $ \vid -> arithConstantFloat vid (fromIntegral nodeId)
  emit $ funcCall [] "__l4_trace_enter" [nodeVal] [l4NumberType] []

-- | Emit @__l4_trace_exit(resultBox, kind)@. The result box is the f64
-- the function would have returned; the runtime renders it according to
-- the kind byte (matches @traceResultKindForL4Type@).
emitTraceExit :: Value -> Int -> LowerM ()
emitTraceExit resultVal kind = do
  kindVal <- emitVal $ \vid -> arithConstantFloat vid (fromIntegral kind)
  emit $ funcCall [] "__l4_trace_exit" [resultVal, kindVal] [l4NumberType, l4NumberType] []

-- | M5 slice 4D — emit @__l4_trace_push_arg_path(paramName, callerPath)@
-- before a call. Kept as a dead-code helper (no current callers after
-- slice 4E switched mark_forced to value-pointer identity, which makes
-- path translation unnecessary) so the runtime ABI surface stays
-- discoverable in one place.
_emitTracePushArgPath :: Text -> Text -> LowerM ()
_emitTracePushArgPath paramName callerPath = do
  paramGlobal <- internString paramName
  pathGlobal  <- internString callerPath
  paramPtr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
    [NamedAttribute "global_name" (FlatSymbolRefAttr paramGlobal)]
    [PointerType] []
  pathPtr  <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
    [NamedAttribute "global_name" (FlatSymbolRefAttr pathGlobal)]
    [PointerType] []
  paramPtrF <- ptrToF64 paramPtr
  pathPtrF  <- ptrToF64 pathPtr
  emit $ funcCall [] "__l4_trace_push_arg_path" [paramPtrF, pathPtrF]
    [l4NumberType, l4NumberType] []

_emitTracePopArgPaths :: LowerM ()
_emitTracePopArgPaths =
  emit $ funcCall [] "__l4_trace_pop_arg_paths" [] [] []

lowerDecide :: Decide Resolved -> LowerM ()
lowerDecide (MkDecide _ typeSig appForm body) = do
  env <- gets (.typeEnv)
  funcName <- symbolFor (appFormHead' appForm)
  let givenParams = appFormParams appForm
      (givenArgTypes, sigRetType) = sigToTypesEnv env typeSig
      listElemTys = listElementsFromSig env typeSig
      -- M5 slice 2B: kind byte we'll pass to `__l4_trace_exit` in the
      -- instrumented `<fn>$trace` clone; derived from the GIVETH type so
      -- the runtime knows whether the result f64 is a rational handle, a
      -- raw boolean, a string pointer, or "other".
      traceKind = traceResultKindForRetType typeSig
  -- M5 slice 4D (call-site translation) — register the source param
  -- names for this function so callers can pair caller-static-paths
  -- with the right helper-param name.
  modify' $ \s -> s
    { funcParams = Map.insert funcName (map resolvedName givenParams) s.funcParams }
  -- Attribute any unsupported-construct diagnostics raised while lowering
  -- this body to this function. Saved/restored so a WHERE/LET helper that
  -- recurses through 'lowerDecide' doesn't leak its name back to us.
  oldCurrentFn <- gets (.currentFunction)
  oldPending <- gets (.pendingDecide)
  let rawDecideName = resolvedName (appFormHead' appForm)
  modify' $ \s -> s
    { currentFunction = Just funcName
    , pendingDecide = Set.insert rawDecideName oldPending
    }
  -- Fail-closed at the ABI boundary for a return value the WASM side cannot
  -- marshal (an enum-with-data lowered as a bare tag, or a record/list/
  -- optional transitively containing one) is enforced in 'buildExport'
  -- (see 'unmarshallableReturn'): it keys on the ENRICHED return type via
  -- 'typeToRetSchema', so it also catches inferred returns (no GIVETH) and
  -- nested enum-with-data that a syntactic-GIVETH check here would miss.
  --
  -- If this DECIDE is @export-decorated and references ASSUMEs, those
  -- ASSUMEs become additional ABI parameters (see 'collectExportAssumeArgs').
  -- They're appended after the GIVEN params so existing call sites for
  -- non-exported callers still match.
  extraAssumeArgs <- Map.findWithDefault [] funcName <$> gets (.exportAssumeArgs)
  let extraParams   = map fst extraAssumeArgs
      extraArgTypes = [l4TypeToMLIR env ty | (_, ty) <- extraAssumeArgs]
      params    = givenParams ++ extraParams
      argTypes  = givenArgTypes ++ extraArgTypes

  -- Respect the signature we already registered in 'registerFuncSig'
  -- so call-site types match the definition — without that, a MEANS
  -- binding that returns a struct would be called as @() -> f64@ but
  -- return @StructType "Foo" …@, causing a type mismatch.
  registeredSigs <- gets (.funcSigs)
  inferredRet <- case Map.lookup funcName registeredSigs of
    Just (_, r) | not (hasGiveth typeSig) -> pure r
    _ -> inferExprTypeM body
  let retType = if hasGiveth typeSig then sigRetType else inferredRet

  -- ABI boundary: every function arg and return is the uniform
  -- 'l4Value' type. Boxing/unboxing at entry and exit is emitted
  -- inline so the function body can use native MLIR types freely.
  entryBlock <- freshBlockId

  -- Allocate one SSA id per param — this is the boxed (f64) arg
  -- presented at the block header. We then unbox it to the native
  -- type the body expects and bind the L4 name to the unboxed value.
  boxedArgIds <- forM params $ \_ -> fresh

  let paramL4Tys =
        [ case oParam of
            MkOptionallyTypedName _ _ (Just ty) _ -> Just ty
            _ -> Nothing
        | oParam <- givenSigParams typeSig
        ]
      -- Pad to match @params@'s length (which may include extra
      -- ASSUME-derived params we don't have explicit L4 types for).
      paddedL4Tys = paramL4Tys ++ replicate (length params - length paramL4Tys) Nothing
  withScope $ do
    -- Collect the ops that unbox each boxed arg into its native form.
    (nativeArgs, unboxOps) <- collectOps $
      forM (zip4 params boxedArgIds argTypes paddedL4Tys) $ \(paramName, boxedId, paramTy, mL4Ty) -> do
        let name = resolvedName paramName
            boxedVal = SSAValue boxedId
        nativeVal <- unboxABI paramTy boxedVal
        bindTy name nativeVal paramTy
        -- M5 — record the L4 source type so 'isNumberExpr' can route
        -- comparisons on @Var@ references to NUMBER-typed params
        -- through @__l4_rat_cmp@. Without this, the body's @x AT
        -- LEAST y@ compares rational-pool indices as raw f64 and
        -- almost always returns FALSE.
        case mL4Ty of
          Just l4Ty -> modify' $ \s -> s
            { bindingL4Types = Map.insert name l4Ty s.bindingL4Types }
          Nothing -> pure ()
        pure (name, nativeVal, paramTy)

    -- Bind list element types where known
    forM_ (zip nativeArgs listElemTys) $ \((name, _, _), mElemTy) -> do
      case mElemTy of
        Just elemTy -> bindListElem name elemTy
        Nothing -> pure ()

    -- Lower the body expression
    (resultVal, bodyOps) <- collectOps $ lowerExpr body retType

    -- Box the body result into the ABI return type.
    (boxedResult, boxOps) <- collectOps $ boxABI retType resultVal

    let retOp = funcReturn [boxedResult] [l4Value]
        block = Block
          { blockId = entryBlock
          , blockArgs = [(vid, l4Value) | vid <- boxedArgIds]
          , blockOps = unboxOps ++ bodyOps ++ boxOps ++ [retOp]
          }
        region = Region [block]
        funcOp = funcFunc funcName
          [(vid, l4Value) | vid <- boxedArgIds]
          [l4Value]
          region

    modify' $ \s -> s { functions = funcOp : s.functions }

  -- Same-arity overload collision: 'dedupAndSynthExterns' mangles a
  -- function symbol to @name__$arity@ when (and only when) the name is
  -- used at more than one arity, then keeps just the FIRST body per
  -- mangled symbol. If a *second* genuinely-different top-level body
  -- shares this name AND arity (ad-hoc overloads distinguished only by
  -- parameter type — e.g. @daydate@'s four arity-1 @Date@ overloads),
  -- the dedup silently drops it, so a call meaning the later overload
  -- dispatches to the wrong body. We can't disambiguate by type across
  -- the f64 ABI, so fail loud: flag the export @supported: false@
  -- (keyed by 'Schema.wasmSymbol', which equals @funcName@) and let the
  -- proxy route it to a fallback evaluator. This runs *outside* the
  -- @withScope@ body block so 'markUnsupported' still attributes to
  -- @currentFunction@ (= @Just funcName@).
  let bodyArity = length params
      bodyUnique = getUnique (appFormHead' appForm)
  -- A symbol already claimed by THIS definition is a benign re-emission
  -- (the untraced pass and the @$trace@ clone both run 'lowerDecide' for a
  -- lifted local helper); only a *different* definition is a real collision.
  claimedBy <- gets (Map.lookup (funcName, bodyArity) . (.emittedBodies))
  let seenBefore = maybe False (/= bodyUnique) claimedBy
  modify' $ \s -> s
    { emittedBodies = Map.insert (funcName, bodyArity) bodyUnique s.emittedBodies }
  when seenBefore $ do
    _ <- markUnsupported $
      "ad-hoc overload collision: multiple definitions of " <> funcName
        <> " at arity " <> Text.pack (show bodyArity)
        <> " share one WASM symbol and cannot be disambiguated by the WASM backend"
    pure ()

  -- M5 slice 2C — emit `<funcName>$trace`, a structurally identical clone
  -- with per-subexpression trace instrumentation. Each traceable
  -- subexpression (per 'Schema.collectTraceNodes') gets bracketed by
  -- @__l4_trace_enter(nodeId)@ / @__l4_trace_exit(box, kind)@ via the
  -- 'lowerExpr' wrapper, which consults 'traceNodeMap' to find the
  -- compile-time-assigned ID. The metadata in the schema's
  -- @traceMeta.nodes@ array shares this ID space.
  traceEntryBlock <- freshBlockId
  traceBoxedArgIds <- forM params $ \_ -> fresh
  -- Walk the body once to assign node IDs + collect per-range metadata,
  -- mirroring the schema's walk (deterministic ⇒ IDs agree).
  info <- gets (.sourceTypeMap)
  -- The lowering only needs the rangeMap (to drive enter/exit
  -- emission); the schema side builds the per-node metadata with
  -- the real declares map. Passing 'Map.empty' here keeps the walk
  -- deterministic (same IDs) without duplicating the declare
  -- threading into LowerState — proj metadata in nodes themselves
  -- comes from the schema-side walk.
  -- M5 — same param-type map the schema's 'buildTraceMetaFromDecide'
  -- builds. The two walks must agree on every node's kind because the
  -- runtime indexes 'traceMeta.nodes' by 'tnId' for text but reads the
  -- kind byte from this rangeMap at trace_exit emission time. If we
  -- passed @Map.empty@ here (as the original M5 slice did), a Var
  -- like @x@ in @max@'s body would be classified kind=3 (compound),
  -- and the runtime would render its boxed NUMBER as a raw f64 even
  -- though the schema correctly tagged it kind=0.
  let bodyParamTypeMap = Map.fromList
        [ (resolvedName p, ty)
        | (p, Just ty) <- zip params paddedL4Tys
        ]
      bodyUnannotatedParams = Set.fromList
        [ resolvedName p
        | (p, Nothing) <- zip params paddedL4Tys
        ]
      -- 'collectTraceNodes' optionally takes a function-name → return-type
      -- map for App-call kind classification (see Schema). The lowering
      -- doesn't have that map handy at this point (it's built per-bundle
      -- in 'bundleExports'); we pass 'Map.empty', which only affects
      -- result-kind defaults for inter-function calls — the schema's
      -- own walk has the full map, and the runtime reads kinds from
      -- the schema's 'traceMeta.nodes' for its rendering. The wasm
      -- side reads kinds via the lowering's @rangeMap@ at emit time,
      -- so any classification mismatch here surfaces as a wrong kind
      -- byte to @__l4_trace_exit@ — but only for kinds the schema's
      -- syntactic dispatch already covered (Plus/Geq/Var-via-paramType
      -- already match between both walks because the syntactic path
      -- doesn't consult either Map).
      (bodyTraceNodes, rangeMap) = Schema.collectTraceNodes info Map.empty bodyParamTypeMap Map.empty bodyUnannotatedParams Set.empty body
      -- M5 slice 4A — the fn-value node's ID is allocated by the
      -- schema's 'buildTraceMeta' as @length bodyNodes@. The lowering
      -- computes the same number so the runtime metadata and the
      -- emitted code agree.
      fnValueNodeId = length bodyTraceNodes
  withScope $ do
    (nativeArgs, unboxOpsT) <- collectOps $
      forM (zip4 params traceBoxedArgIds argTypes paddedL4Tys) $ \(paramName, boxedId, paramTy, mL4Ty) -> do
        let name = resolvedName paramName
            boxedVal = SSAValue boxedId
        nativeVal <- unboxABI paramTy boxedVal
        bindTy name nativeVal paramTy
        -- See the non-trace pass for why this matters: a Var in trace
        -- mode hits @lowerCmp@'s @isNumberExpr@ check, and without an
        -- L4 type recorded here the check fails for prelude helpers
        -- (whose param types are absent from the main module's
        -- 'InfoMap').
        case mL4Ty of
          Just l4Ty -> modify' $ \s -> s
            { bindingL4Types = Map.insert name l4Ty s.bindingL4Types }
          Nothing -> pure ()
        pure (name, nativeVal, paramTy)
    forM_ (zip nativeArgs listElemTys) $ \((name, _, _), mElemTy) -> do
      case mElemTy of
        Just elemTy -> bindListElem name elemTy
        Nothing -> pure ()
    -- Flip on tracing for the duration of this body lowering. The
    -- per-call wrapper inside 'lowerExpr' picks it up and brackets
    -- each traceable subexpression. Saved/restored around the call so
    -- nested WHERE/LET helpers (which call lowerDecide recursively)
    -- get their own tracing state.
    oldTracing <- gets (.tracing)
    oldMap     <- gets (.traceNodeMap)
    modify' $ \s -> s { tracing = True, traceNodeMap = rangeMap }
    -- M5 slice 4A — bracket the body with a function-context marker so
    -- the runtime knows whose `traceMeta.nodes` to resolve node IDs
    -- against. Inside the brackets:
    --   1. emit the fn-value frame (renders as `Result: <function>`);
    --   2. lower the body normally (the wrapper instruments each
    --      traceable sub-expression);
    --   3. emit the matching `exit_fn`.
    -- The fn-name is interned in the wasm's string pool once per
    -- function, so the call is cheap.
    -- Intern @<funcName>__<postClosureArity>@ so the runtime's
    -- @fnStack@ key matches the schema's @helperTraceMeta@ key
    -- shape ('Schema.bundleExports' uses the same always-mangle
    -- convention). Without this, two prelude WHERE helpers that
    -- share a sanitized name (e.g. @go@ in @foldr@ vs @go@ in
    -- @count@) would push the bare "go" onto @fnStack@ and the
    -- runtime would resolve all of them against whichever schema
    -- entry won the source-order race.
    let symKey = funcName <> "__" <> Text.pack (show (length params))
    fnSymGlobal <- internString symKey
    (_, fnSetupOps) <- collectOps $ do
      symPtr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
        [NamedAttribute "global_name" (FlatSymbolRefAttr fnSymGlobal)]
        [PointerType] []
      symPtrF <- ptrToF64 symPtr
      emit $ funcCall [] "__l4_trace_enter_fn" [symPtrF] [l4NumberType] []
      emitTraceEnter fnValueNodeId
      -- The "fn value" payload is conceptually `<function>`; we pass a
      -- zero box and kind=4 (= "<function>") so the runtime renders
      -- @Result: \<function\>@ regardless of the raw bits.
      zeroF <- emitVal $ \vid -> arithConstantFloat vid 0.0
      kindF <- emitVal $ \vid -> arithConstantFloat vid 4.0
      emit $ funcCall [] "__l4_trace_exit" [zeroF, kindF] [l4NumberType, l4NumberType] []
    (resultValT, bodyOpsT)  <- collectOps $ lowerExpr body retType
    (boxedResultT, boxOpsT) <- collectOps $ boxABI retType resultValT
    (_, fnTeardownOps) <- collectOps $
      emit $ funcCall [] "__l4_trace_exit_fn" [] [] []
    modify' $ \s -> s { tracing = oldTracing, traceNodeMap = oldMap }
    -- 'traceKind' here is the function's overall return-type kind. It
    -- coincides with the body root's per-node kind (which the wrapper
    -- already used inside 'lowerExpr'), so no additional outer exit is
    -- needed — the root frame is the tree's root.
    let retOpT = funcReturn [boxedResultT] [l4Value]
        traceBlock = Block
          { blockId = traceEntryBlock
          , blockArgs = [(vid, l4Value) | vid <- traceBoxedArgIds]
          , blockOps = unboxOpsT ++ fnSetupOps ++ bodyOpsT ++ boxOpsT ++ fnTeardownOps ++ [retOpT]
          }
        traceRegion = Region [traceBlock]
        traceFuncOp = funcFunc (funcName <> "$trace")
          [(vid, l4Value) | vid <- traceBoxedArgIds]
          [l4Value]
          traceRegion
    modify' $ \s -> s { functions = traceFuncOp : s.functions }

  modify' $ \s -> s
    { currentFunction = oldCurrentFn
    , pendingDecide = oldPending
    }
  -- 'traceKind' was used by the slice-2B body-root instrumentation;
  -- in slice 2C the per-node 'lowerExpr' wrapper carries the kind from
  -- 'traceNodeMap'. Keep the binding referenced so it remains live
  -- without re-introducing a warning when slice 2D may need it again.
  _ <- pure traceKind
  pure ()

-- | Extract argument types and return type from a type signature.
sigToTypesEnv :: TypeEnv -> TypeSig Resolved -> ([MLIRType], MLIRType)
sigToTypesEnv env (MkTypeSig _ givenSig mGiveth) =
  let argTypes = case givenSig of
        MkGivenSig _ params -> map paramToMLIR params
      retType = case mGiveth of
        Just (MkGivethSig _ ty) -> l4TypeToMLIR env ty
        Nothing -> l4BoolType  -- L4 DECIDE ... IF has implicit boolean return
  in (argTypes, retType)
  where
    paramToMLIR (MkOptionallyTypedName _ _ (Just ty) _) = l4TypeToMLIR env ty
    paramToMLIR (MkOptionallyTypedName _ _ Nothing _) = l4NumberType  -- default

hasGiveth :: TypeSig Resolved -> Bool
hasGiveth (MkTypeSig _ _ (Just _)) = True
hasGiveth _ = False

-- | Does any parameter of this signature have a function type? Such
-- decls require higher-order function support, which the MLIR backend
-- doesn't yet implement; we keep them as externs instead of lowering.
sigHasFunctionParam :: TypeSig Resolved -> Bool
sigHasFunctionParam (MkTypeSig _ (MkGivenSig _ params) _) =
  any hasFunTy params
  where
    hasFunTy (MkOptionallyTypedName _ _ (Just ty) _) = isFunType ty
    hasFunTy _ = False
    isFunType (Fun {})       = True
    isFunType (Forall _ _ t) = isFunType t
    isFunType _              = False

-- | Stateful type inference.
--
-- First consults the jl4-core typechecker's 'InfoMap' for the
-- ground-truth type of the expression. If the lookup returns a
-- concrete MLIR type, use it. If the InfoMap returns 'Nothing' (no
-- record for this node) or a non-informative type (like a generic
-- type variable or @NoneType@), fall back to the syntactic heuristic.
-- This gives us ground-truth precision where it exists without
-- regressing on nodes the typechecker didn't annotate.
inferExprTypeM :: Expr Resolved -> LowerM MLIRType
inferExprTypeM expr = do
  heuristicTy <- inferExprTypeHeuristic expr
  if isInformativeType heuristicTy
    then pure heuristicTy
    else do
      mTy <- typeOfExpr expr
      case mTy of
        Just ty -> do
          env <- gets (.typeEnv)
          pure (l4TypeToMLIR env ty)
        Nothing -> pure heuristicTy

-- | An MLIR type is informative if it carries real structure (e.g.
-- a concrete record, a float, a pointer to a list) rather than the
-- fallback defaults used when we have no idea.
isInformativeType :: MLIRType -> Bool
isInformativeType NoneType       = False
isInformativeType (NamedType _)  = False
isInformativeType _              = True

-- | Syntactic fallback when the typechecker didn't record a type for
-- this node. Kept as a backstop for synthesized expressions only.
inferExprTypeHeuristic :: Expr Resolved -> LowerM MLIRType
inferExprTypeHeuristic expr = do
  env <- gets (.typeEnv)
  case expr of
    App _ n [] -> do
      -- Variable ref or nullary call.
      -- First check for built-in nullary constructors that produce
      -- known types — the pure 'inferExprType' defaults @App _ _ _@ to
      -- f64 so without these cases a function like
      --     @DECIDE foo IS TRUE@
      -- would be inferred to return f64 while the body actually
      -- produces i1, breaking the ABI return-boxing.
      let name = resolvedName n
      case name of
        -- Uniform f64 ABI: every nullary form resolves to f64.
        "TRUE"    -> pure l4NumberType
        "FALSE"   -> pure l4NumberType
        "EMPTY"   -> pure l4NumberType
        "NOTHING" -> pure l4NumberType
        _ -> do
          mTy <- gets (Map.lookup name . (.bindingTypes))
          case mTy of
            Just ty -> pure ty
            Nothing -> do
              sigs <- gets (.funcSigs)
              case Map.lookup (sanitizeName name) sigs of
                Just (_, r) -> pure r
                Nothing -> case lookupEnumTag name env of
                  Just _ -> pure l4NumberType
                  Nothing -> pure (resolveInferredType env (inferExprType expr))
    App _ n args -> do
      let name = resolvedName n
      case lookupRecordFields name env of
        Just fs | length fs == length args ->
          pure (StructType name (map snd fs))
        -- Uniform f64 ABI: every expression resolves to f64.
        -- The only remaining dispatch here is for callee lookups in the
        -- registered-signature map, so we preserve cross-function arity info.
        _ -> do
          sigs <- gets (.funcSigs)
          case Map.lookup (sanitizeName name) sigs of
            Just (_, r) -> pure r
            Nothing     -> pure l4NumberType
    AppNamed _ n _ _ -> do
      -- Record construction
      let name = rawNameToText (rawName (getActual n))
      pure (resolveInferredType env (NamedType name))
    Cons _ _ _ -> pure l4NumberType
    List _ _ -> pure l4NumberType
    Proj _ _ field -> do
      -- Field access: find the field's type in the type env
      let fieldName = resolvedName field
      pure (findFieldType fieldName env)
    -- Recurse through structural wrappers whose type equals their payload's.
    -- 'inferExprType' is pure and can't re-enter the stateful path, so we
    -- dispatch these here directly — otherwise 'Where'/'LetIn'/etc. fall
    -- through to 'inferExprType' where 'App __AND__' isn't recognised and
    -- the whole expression is defaulted to f64.
    Where _ e _ -> inferExprTypeHeuristic e
    LetIn _ _ e -> inferExprTypeHeuristic e
    IfThenElse _ _ t _ -> inferExprTypeHeuristic t
    Consider _ _ branches -> case branches of
      (MkBranch _ _ e : _) -> inferExprTypeHeuristic e
      [] -> pure l4NumberType
    MultiWayIf _ _ e -> inferExprTypeHeuristic e
    Percent _ _ -> pure l4NumberType
    _ -> pure (resolveInferredType env (inferExprType expr))

-- | Find the MLIR type of a field (searches all records in env).
findFieldType :: Text -> TypeEnv -> MLIRType
findFieldType fieldName env =
  case [ ty
       | (_, fields) <- Map.toList env.records
       , (fname, ty) <- fields
       , fname == fieldName
       ] of
    (t : _) -> t
    [] -> l4NumberType

-- | Resolve NamedType references to concrete struct types using the type env.
resolveInferredType :: TypeEnv -> MLIRType -> MLIRType
resolveInferredType env (NamedType name) =
  case lookupRecordFields name env of
    Just fields -> StructType name (map snd fields)
    Nothing -> case lookupEnumVariants name env of
      Just _ -> IntegerType 32
      Nothing -> NamedType name
resolveInferredType _ ty = ty

-- | Under the uniform f64 ABI, every SSA value produced by 'lowerExpr'
-- is an @f64@ — so expression type inference almost always reduces to
-- "f64". The distinct constructor cases below are retained only for
-- sub-expression *identity* on compound constructors (e.g.
-- 'AppNamed' reports the record's named type, used by the schema
-- emitter for client documentation).
inferExprType :: Expr Resolved -> MLIRType
-- Everything is f64 under the uniform ABI. The 'AppNamed' case
-- retains its record name because 'L4.MLIR.Schema' reads it to emit
-- the JSON type for client consumption.
inferExprType (AppNamed _ n _ _) = NamedType (rawNameToText (rawName (getActual n)))
inferExprType _ = l4NumberType

-- ---------------------------------------------------------------------------
-- Expression lowering
-- ---------------------------------------------------------------------------

-- | Lower an L4 expression, producing an SSA value of the expected type.
-- | M5 slice 2C — top-level 'lowerExpr' wrapper. In tracing mode, looks
-- up the expression's compile-time-assigned trace node ID (via
-- 'traceNodeMap', keyed by source range) and brackets the lowered body
-- with @__l4_trace_enter(id)@ / @__l4_trace_exit(box, kind)@. The
-- untraced @<fn>@ pass leaves 'tracing' false, so the fast path stays
-- exactly the same wasm it did before slice 2C.
--
-- The 'traceable' check in @collectTraceNodes@ is the single source of
-- truth for which expressions get a node — if @traceNodeMap@ has no
-- entry for an expression's range, we just lower it without bracketing.
lowerExpr :: Expr Resolved -> MLIRType -> LowerM Value
lowerExpr expr expectedTy = do
  tracingNow <- gets (.tracing)
  if not tracingNow
    then lowerExprCases expr expectedTy
    else do
      rmap <- gets (.traceNodeMap)
      let mEntry = case rangeOf expr of
            Just rng -> Map.lookup (rng, Schema.exprDisambiguator expr) rmap
            Nothing  -> Nothing
      case mEntry of
        Just (nodeId, kind) -> do
          -- Skip the wrapper when the same node is already open — see
          -- 'openTraceNode' on 'LowerState'. The parser sometimes
          -- collapses a unary operator and its inner expression into
          -- a shared 'SrcRange'; Schema's 'rangeMap' keeps the outer
          -- entry, so 'lowerExpr' on the inner returns the same id
          -- and would emit a duplicate frame on top of the outer's.
          alreadyOpen <- gets (.openTraceNode)
          if alreadyOpen == Just nodeId
            then lowerExprCases expr expectedTy
            else do
              modify' $ \s -> s { openTraceNode = Just nodeId }
              emitTraceEnter nodeId
              result <- lowerExprCases expr expectedTy
              -- For a force-traced @Var@ (App with no args) that resolves to
              -- a local-binding, refine the schema's best-guess kind using
              -- the binding's MLIR type. The schema can't always classify a
              -- @Var@ inside a helper whose 'TypeSig' has un-annotated
              -- params (e.g. prelude's @go acc l MEANS …@ in @count@) and
              -- defaults to kind 3, which would make the runtime read the
              -- NUMBER's f64 bits as a raw pointer. The runtime uses the
              -- emitted kind here as an override when the schema's kind is
              -- the default 3.
              actualKind <- case (kind, expr) of
                (3, App _ n []) -> do
                  let nm = resolvedName n
                  mMlirTy <- gets (Map.lookup nm . (.bindingTypes))
                  pure $ case mMlirTy of
                    Just ty
                      | ty == l4NumberType -> 0
                      | ty == l4BoolType   -> 1
                      | ty == l4StringType -> 2
                    _ -> kind
                _ -> pure kind
              emitTraceExit result actualKind
              modify' $ \s -> s { openTraceNode = alreadyOpen }
              pure result
        Nothing ->
          lowerExprCases expr expectedTy

-- | The actual per-shape lowering. Was 'lowerExpr' before slice 2C
-- factored the trace bracketing out into the wrapper above.
lowerExprCases :: Expr Resolved -> MLIRType -> LowerM Value
lowerExprCases expr expectedTy = case expr of
  -- Literals
  Lit _ lit -> lowerLit lit expectedTy

  -- Variable reference
  App _ n [] -> do
    let name = resolvedName n
    funcN <- symbolFor n
    mVal <- lookupVar name
    case mVal of
      Just val -> pure val
      Nothing -> case name of
        -- Boolean literals (uniform f64 ABI: 0.0 / 1.0)
        "TRUE"  -> do
          i1 <- emitVal $ \vid -> arithConstantBool vid True
          boxBoolI1 i1
        "FALSE" -> do
          i1 <- emitVal $ \vid -> arithConstantBool vid False
          boxBoolI1 i1
        -- MAYBE NOTHING — a 2-slot record [tag=0.0 (false), value=0.0].
        "NOTHING" -> do
          mb <- allocSlots 2
          zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
          storeSlot mb 0 zero
          storeSlot mb 1 zero
          pure mb
        -- Empty list: null pointer encoded as f64(0.0)
        "EMPTY" -> nullListF64
        -- Nullary temporal intrinsics — built-in names that take no
        -- arguments and return a scalar (date/time serial).
        "TODAY"       -> emitVal $ \vid -> funcCall [vid] "__l4_today_serial" [] [] [l4NumberType]
        "NOW"         -> emitVal $ \vid -> funcCall [vid] "__l4_now_serial"   [] [] [l4NumberType]
        "CURRENTTIME" -> emitVal $ \vid -> funcCall [vid] "__l4_current_time" [] [] [l4NumberType]
        _ -> do
          env <- gets (.typeEnv)
          case lookupEnumTag name env of
            -- Enum tag: a plain number under the uniform f64 ABI
            Just tag -> emitVal $ \vid -> arithConstantFloat vid (fromIntegral tag)
            Nothing -> do
              -- Lambda-lifted zero-arg WHERE/LET binding — prepend the
              -- captured outer-scope values as the call's leading args,
              -- mirroring the multi-arg App case below.
              captures <- gets (.localCaptures)
              sigs <- gets (.funcSigs)
              let retTy = case Map.lookup funcN sigs of
                    Just (_, r) -> r
                    Nothing     -> expectedTy
              case Map.lookup funcN captures of
                Just capturedNames -> do
                  capturedVals <- forM capturedNames $ \cn -> do
                    mV <- lookupVar cn
                    case mV of
                      Just v -> pure v
                      Nothing -> emitNumberLiteral 0
                  let capturePairs = [(v, l4NumberType) | v <- capturedVals]
                  callL4 funcN capturePairs retTy
                Nothing -> do
                  -- Nullary call through the uniform f64 ABI. In trace mode,
                  -- skip the @$trace@ dispatch so the helper's body events
                  -- don't pollute the parent's trace pool — jl4-core renders
                  -- a bare Var lookup as a single leaf. The leaf itself is
                  -- emitted by the parent's force-trace wrapper (e.g. the
                  -- CONSIDER branch-body @App _ _ []@ case in 'Schema'
                  -- 'foldBranches').
                  tracingNow <- gets (.tracing)
                  if tracingNow
                    then callL4Direct funcN [] retTy
                    else callL4 funcN [] retTy

  -- Function application
  App _ n args -> do
    let rawName_ = resolvedName n
    funcN <- symbolFor n
    env <- gets (.typeEnv)
    -- Closure conversion for @WHERE@ / @LET IN@ helpers: when the
    -- callee was lambda-lifted with captured outer-scope variables,
    -- prepend their current bindings to the call's args. See
    -- 'lowerLocalDecl' for where the capture list is recorded.
    captures <- gets (.localCaptures)
    case Map.lookup funcN captures of
      Just capturedNames -> do
        capturedVals <- forM capturedNames $ \cn -> do
          mV <- lookupVar cn
          case mV of
            Just v -> pure v
            -- Unreachable in well-typed L4 (capture is resolved at
            -- lambda-lift time). Emit a NUMBER-zero handle rather than a
            -- raw f64 0.0 so a NUMBER consumer doesn't alias pool handle 0.
            Nothing -> emitNumberLiteral 0
        userArgPairs <- forM args $ \arg -> do
          ty <- inferExprTypeM arg
          v  <- lowerExpr arg ty
          pure (v, ty)
        let capturePairs = [(v, l4NumberType) | v <- capturedVals]
            retTy = l4NumberType
        callL4 funcN (capturePairs <> userArgPairs) retTy
      Nothing ->
       case lookupRecordFields rawName_ env of
        Just fields | length fields == length args ->
          lowerPositionalRecord rawName_ fields args
        _ ->
         case lookupEnumTag rawName_ env of
          -- Enum constructor tag — encoded as f64 for the uniform ABI.
          Just tag -> emitVal $ \vid -> arithConstantFloat vid (fromIntegral tag)
          Nothing ->
           -- Prelude intrinsics and runtime calls.
           case (rawName_, args) of
            ("__PLUS__", [a, b])    -> lowerRatBinop "__l4_rat_add" a b
            ("__MINUS__", [a, b])   -> lowerRatBinop "__l4_rat_sub" a b
            ("__TIMES__", [a, b])   -> lowerRatBinop "__l4_rat_mul" a b
            ("__DIVIDE__", [a, b])  -> lowerRatBinop "__l4_rat_div" a b
            ("__MODULO__", [a, b])  -> lowerRatBinop "__l4_rat_mod" a b
            ("__GEQ__", [a, b])     -> lowerCmp OGE a b
            ("__LEQ__", [a, b])     -> lowerCmp OLE a b
            ("__GT__", [a, b])      -> lowerCmp OGT a b
            ("__LT__", [a, b])      -> lowerCmp OLT a b
            ("__EQUALS__", [a, b])  -> lowerCmp OEQ a b
            -- M5 slice 4D: short-circuit so __l4_mark_forced markers
            -- in the rhs only fire when lhs actually demands it,
            -- matching jl4-core's lazy AND/OR evaluation.
            ("__AND__", [a, b])     -> lowerAndShortCircuit a b
            ("__OR__", [a, b])      -> lowerOrShortCircuit  a b
            ("__NOT__", [a])        -> do
              innerF64 <- lowerExpr a l4NumberType
              innerI1 <- unboxBoolI1 innerF64
              trueBit <- emitVal $ \vid -> arithConstantBool vid True
              notI1 <- emitVal $ \vid -> arithXori vid innerI1 trueBit
              boxBoolI1 notI1
            ("__CONS__", [hd, tl])  -> do
              hdVal <- lowerExpr hd l4NumberType
              tlVal <- lowerExpr tl l4NumberType
              lowerListConsTy l4NumberType hdVal tlVal
            -- Prelude helpers with a lowered L4 body. In trace mode we
            -- skip the runtime-call fast path so the call routes through
            -- `callL4` (line 232) and hits @<name>$trace@ — otherwise
            -- the trace tree would be missing the helper's body subtree.
            ("min", args'@[a, b]) -> do
              tracingNow <- gets (.tracing)
              if tracingNow
                then callPreludeL4 funcN args'
                else do
                  aVal <- lowerExpr a l4NumberType
                  bVal <- lowerExpr b l4NumberType
                  emitVal $ \vid -> funcCall [vid] "__l4_min"
                    [aVal, bVal] [l4NumberType, l4NumberType] [l4NumberType]
            ("max", args'@[a, b]) -> do
              tracingNow <- gets (.tracing)
              if tracingNow
                then callPreludeL4 funcN args'
                else do
                  aVal <- lowerExpr a l4NumberType
                  bVal <- lowerExpr b l4NumberType
                  emitVal $ \vid -> funcCall [vid] "__l4_max"
                    [aVal, bVal] [l4NumberType, l4NumberType] [l4NumberType]
            ("count", args'@[a]) -> do
              tracingNow <- gets (.tracing)
              if tracingNow
                then callPreludeL4 funcN args'
                else do
                  aVal <- lowerExpr a l4NumberType
                  emitVal $ \vid -> funcCall [vid] "__l4_list_count"
                    [aVal] [l4NumberType] [l4NumberType]
            ("JUST", [inner]) -> do
              innerVal <- lowerExpr inner l4NumberType
              mb <- allocSlots 2
              one <- emitVal $ \vid -> arithConstantFloat vid 1.0
              storeSlot mb 0 one
              storeSlot mb 1 innerVal
              pure mb
            -- EITHER's LEFT / RIGHT — a payload-carrying builtin ADT
            -- (prelude: @x IS AN EITHER a b@) represented exactly like
            -- MAYBE: a 2-slot record [tag, payload]. LEFT is tagged 0.0,
            -- RIGHT 1.0 — mirroring NOTHING/JUST's false/true tag — so the
            -- CONSIDER lowering ('testPatternTy'/'bindPatternTy') can
            -- dispatch on the tag and read the payload from slot 1. These
            -- fire only for the builtin: a user-declared constructor named
            -- LEFT/RIGHT is caught above by 'lookupRecordFields' /
            -- 'lookupEnumTag' HERE, and — crucially — the matching side
            -- ('testPatternTy'/'bindPatternTy') applies the SAME lookup-
            -- first ordering via 'isUserConstructor', so construction and
            -- matching agree on the representation.
            ("LEFT", [inner]) -> do
              innerVal <- lowerExpr inner l4NumberType
              e <- allocSlots 2
              zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
              storeSlot e 0 zero
              storeSlot e 1 innerVal
              pure e
            ("RIGHT", [inner]) -> do
              innerVal <- lowerExpr inner l4NumberType
              e <- allocSlots 2
              one <- emitVal $ \vid -> arithConstantFloat vid 1.0
              storeSlot e 0 one
              storeSlot e 1 innerVal
              pure e
            -- DATE / TIME / DATETIME primitives. These don't need a fresh
            -- extern synthesized (we declare them in Runtime.Builtins); we
            -- just route the call directly so the f64 ABI is bypassed
            -- (they already use f64 natively).
            ("DATE_FROM_DMY",    [d_, m_, y_]) -> runtimeCall "__l4_date_from_dmy"    [d_, m_, y_]
            ("DATE_FROM_SERIAL", [n_])         -> runtimeCall "__l4_date_from_serial" [n_]
            ("DATE_SERIAL",      [d_])         -> runtimeCall "__l4_date_serial"      [d_]
            ("DATE_DAY",         [d_])         -> runtimeCall "__l4_date_day"         [d_]
            ("DATE_MONTH",       [d_])         -> runtimeCall "__l4_date_month"       [d_]
            ("DATE_YEAR",        [d_])         -> runtimeCall "__l4_date_year"        [d_]
            ("DATEVALUE",        [s_])         -> runtimeCall "__l4_datevalue"        [s_]
            ("TODATE",           [s_])         -> runtimeCall "__l4_to_date"          [s_]
            ("TIME_FROM_HMS",    [h_, m_, s_]) -> runtimeCall "__l4_time_from_hms"    [h_, m_, s_]
            ("TIME_FROM_SERIAL", [n_])         -> runtimeCall "__l4_time_from_serial" [n_]
            ("TIME_SERIAL",      [t_])         -> runtimeCall "__l4_time_serial"      [t_]
            ("TIME_HOUR",        [t_])         -> runtimeCall "__l4_time_hour"        [t_]
            ("TIME_MINUTE",      [t_])         -> runtimeCall "__l4_time_minute"      [t_]
            ("TIME_SECOND",      [t_])         -> runtimeCall "__l4_time_second"      [t_]
            ("TOTIME",           [s_])         -> runtimeCall "__l4_to_time"          [s_]
            ("DATETIME_FROM_DTZ",[d_, t_, z_]) -> runtimeCall "__l4_datetime_from_dtz"[d_, t_, z_]
            ("DATETIME_DATE",    [dt_])        -> runtimeCall "__l4_datetime_date"    [dt_]
            ("DATETIME_TIME",    [dt_])        -> runtimeCall "__l4_datetime_time"    [dt_]
            ("DATETIME_TZ",      [dt_])        -> runtimeCall "__l4_datetime_tz"      [dt_]
            ("DATETIME_SERIAL",  [dt_])        -> runtimeCall "__l4_datetime_serial"  [dt_]
            ("TODATETIME",       [s_])         -> runtimeCall "__l4_to_datetime"      [s_]
            -- Numeric intrinsics (uppercase prelude aliases that L4 users
            -- can call directly; the lowercase 'min'/'max'/'abs' entries
            -- above handle the prelude's lowercased wrappers).
            ("FLOOR",       [n_])              -> runtimeCall "__l4_floor"      [n_]
            ("CEILING",     [n_])              -> runtimeCall "__l4_ceil"       [n_]
            ("ROUND",       [n_])              -> runtimeCall "__l4_round"      [n_]
            ("ABS",         [n_])              -> runtimeCall "__l4_abs"        [n_]
            ("POW",         [a_, b_])          -> runtimeCall "__l4_pow"        [a_, b_]
            ("EXPONENT",    [a_, b_])          -> runtimeCall "__l4_pow"        [a_, b_]
            ("MIN",         [a_, b_])          -> runtimeCall "__l4_min"        [a_, b_]
            ("MAX",         [a_, b_])          -> runtimeCall "__l4_max"        [a_, b_]
            ("SQRT",        [n_])              -> runtimeCall "__l4_sqrt"       [n_]
            ("LN",          [n_])              -> runtimeCall "__l4_ln"         [n_]
            ("LOG10",       [n_])              -> runtimeCall "__l4_log10"      [n_]
            ("SIN",         [n_])              -> runtimeCall "__l4_sin"        [n_]
            ("COS",         [n_])              -> runtimeCall "__l4_cos"        [n_]
            ("TAN",         [n_])              -> runtimeCall "__l4_tan"        [n_]
            ("ASIN",        [n_])              -> runtimeCall "__l4_asin"       [n_]
            ("ACOS",        [n_])              -> runtimeCall "__l4_acos"       [n_]
            ("ATAN",        [n_])              -> runtimeCall "__l4_atan"       [n_]
            ("TRUNC",       [a_, b_])          -> runtimeCall "__l4_trunc"      [a_, b_]
            ("IS INTEGER",  [n_])              -> runtimeCall "__l4_is_integer" [n_]
            -- String intrinsics.
            ("STRINGLENGTH",[s_])              -> runtimeCall "__l4_string_length" [s_]
            ("TOUPPER",     [s_])              -> runtimeCall "__l4_to_upper"     [s_]
            ("TOLOWER",     [s_])              -> runtimeCall "__l4_to_lower"     [s_]
            ("TRIM",        [s_])              -> runtimeCall "__l4_trim"         [s_]
            ("CONTAINS",    [a_, b_])          -> runtimeCall "__l4_contains"     [a_, b_]
            ("STARTSWITH",  [a_, b_])          -> runtimeCall "__l4_starts_with"  [a_, b_]
            ("ENDSWITH",    [a_, b_])          -> runtimeCall "__l4_ends_with"    [a_, b_]
            ("INDEXOF",     [a_, b_])          -> runtimeCall "__l4_index_of"     [a_, b_]
            ("CHARAT",      [a_, b_])          -> runtimeCall "__l4_char_at"      [a_, b_]
            ("SUBSTRING",   [a_, b_, c_])      -> runtimeCall "__l4_substring"    [a_, b_, c_]
            ("REPLACE",     [a_, b_, c_])      -> runtimeCall "__l4_replace"      [a_, b_, c_]
            -- Conversion.
            ("TOSTRING",    [v_])              -> runtimeCall "__l4_to_string"    [v_]
            ("TONUMBER",    [s_])              -> runtimeCall "__l4_to_number"    [s_]
            -- JSON.
            ("JSONENCODE",  [v_])              -> runtimeCall "__l4_json_encode"  [v_]
            ("JSONDECODE",  [s_])              -> runtimeCall "__l4_json_decode"  [s_]
            -- General function application: uniform f64 ABI via callL4.
            -- M5 slice 4E: no per-call path translation needed — the
            -- mark_forced ABI uses value-pointer identity so a
            -- helper's Proj on its local param hits the same JS
            -- object the caller marshaled.
            _ -> do
              sigs <- gets (.funcSigs)
              let retTy = case Map.lookup funcN sigs of
                    Just (_, r) -> r
                    Nothing     -> expectedTy
              argPairs <- forM args $ \arg -> do
                ty <- inferExprTypeM arg
                v  <- lowerExpr arg ty
                pure (v, ty)
              callL4 funcN argPairs retTy

  -- Named application (WITH syntax for record construction)
  AppNamed _ n namedArgs _ -> lowerRecordConstruction n namedArgs expectedTy

  -- Arithmetic — all routed through the exact-rational runtime.
  Plus _ lhs rhs -> lowerRatBinop "__l4_rat_add" lhs rhs
  Minus _ lhs rhs -> lowerRatBinop "__l4_rat_sub" lhs rhs
  Times _ lhs rhs -> lowerRatBinop "__l4_rat_mul" lhs rhs
  DividedBy _ lhs rhs -> lowerRatBinop "__l4_rat_div" lhs rhs
  Modulo _ lhs rhs -> lowerRatBinop "__l4_rat_mod" lhs rhs

  -- Comparisons
  Equals _ lhs rhs -> lowerCmp OEQ lhs rhs
  Lt _ lhs rhs -> lowerCmp OLT lhs rhs
  Gt _ lhs rhs -> lowerCmp OGT lhs rhs
  Leq _ lhs rhs -> lowerCmp OLE lhs rhs
  Geq _ lhs rhs -> lowerCmp OGE lhs rhs

  -- Boolean logic
  -- M5 slice 4D: short-circuit so __l4_mark_forced markers in the rhs
  -- only fire when lhs demands it (jl4-core's lazy AND/OR).
  And _ lhs rhs -> lowerAndShortCircuit lhs rhs
  Or  _ lhs rhs -> lowerOrShortCircuit  lhs rhs
  Not _ inner -> do
    innerF64 <- lowerExpr inner l4NumberType
    innerI1 <- unboxBoolI1 innerF64
    trueBit <- emitVal $ \vid -> arithConstantBool vid True
    notI1 <- emitVal $ \vid -> arithXori vid innerI1 trueBit
    boxBoolI1 notI1

  Implies _ lhs rhs -> do
    -- A IMPLIES B  =  NOT A OR B
    lhsF64 <- lowerExpr lhs l4NumberType
    rhsF64 <- lowerExpr rhs l4NumberType
    lhsI1 <- unboxBoolI1 lhsF64
    rhsI1 <- unboxBoolI1 rhsF64
    trueBit <- emitVal $ \vid -> arithConstantBool vid True
    notLhs <- emitVal $ \vid -> arithXori vid lhsI1 trueBit
    resI1 <- emitVal $ \vid -> arithOri vid notLhs rhsI1
    boxBoolI1 resI1

  -- Conditionals
  IfThenElse _ cond then_ else_ -> do
    condF64 <- lowerExpr cond l4NumberType
    condI1 <- unboxBoolI1 condF64
    -- All SSA values in the scf.if region follow the uniform f64 ABI.
    (thenVal, thenOps) <- collectOps $ lowerExpr then_ l4NumberType
    (elseVal, elseOps) <- collectOps $ lowerExpr else_ l4NumberType
    let thenBlock = Block 0 [] (thenOps ++ [scfYield [thenVal] [l4NumberType]])
        elseBlock = Block 0 [] (elseOps ++ [scfYield [elseVal] [l4NumberType]])
        thenRegion = Region [thenBlock]
        elseRegion = Region [elseBlock]
    emitVal $ \vid -> scfIf [vid] condI1 thenRegion elseRegion [l4NumberType]

  -- Pattern matching (CONSIDER ... WHEN)
  Consider _ scrutinee branches -> lowerConsider scrutinee branches expectedTy

  -- Record field projection (foo's `field name`)
  Proj _ record field -> lowerProjection record field expectedTy

  -- WHERE clause — local helpers may be multi-arg functions, may be
  -- mutually recursive, and may capture outer-scope variables. They
  -- are lambda-lifted with explicit closure parameters.
  Where _ body locals -> withScope $ do
    forM_ locals (lowerLocalDecl LocalScopeWhere)
    lowerExpr body expectedTy

  -- LET ... IN ... — value bindings (single-use, typically). By L4
  -- convention these are inlined at their use sites rather than
  -- lifted to new top-level functions. Inlining gives the body
  -- transparent access to the caller's scope and avoids the cost of
  -- closure conversion where it isn't needed.
  LetIn _ locals body -> withScope $ do
    forM_ locals (lowerLocalDecl LocalScopeLetIn)
    lowerExpr body expectedTy

  -- Percent (x% = x / 100) — exact rational division.
  Percent _ inner -> do
    val <- lowerExpr inner l4NumberType
    hundred <- emitNumberLiteral 100
    emitRatBinop "__l4_rat_div" val hundred

  -- List literal
  List _ elems -> lowerListLiteral elems expectedTy

  -- List cons (FOLLOWED BY)
  Cons _ hd tl -> do
    hdVal <- lowerExpr hd l4NumberType
    tlVal <- lowerExpr tl l4NumberType
    lowerListConsTy l4NumberType hdVal tlVal

  -- Lambda
  Lam _ givenSig body -> lowerLambda givenSig body expectedTy

  -- Multi-way if (BRANCH ... WHEN guard THEN expr)
  MultiWayIf _ guards otherwise_ -> lowerMultiWayIf guards otherwise_ expectedTy

  -- String concatenation
  Concat _ parts -> lowerConcat parts

  -- String coercion
  AsString _ inner -> do
    -- Call runtime toString
    val <- lowerExpr inner l4NumberType
    emitVal $ \vid -> funcCall [vid] "__l4_to_string" [val] [l4NumberType] [l4NumberType]

  -- Inert text (grammatical scaffolding) — evaluates to identity for
  -- its context. Under the uniform f64 ABI we emit the boolean
  -- identity directly as f64 (0.0 or 1.0).
  Inert _ _ ctx -> case ctx of
    InertCtxAnd  -> emitVal $ \vid -> arithConstantFloat vid 1.0
    InertCtxOr   -> emitVal $ \vid -> arithConstantFloat vid 0.0
    InertCtxNone -> emitVal $ \vid -> arithConstantFloat vid 1.0

  -- M6: 'Regulative' / 'Breach' compile to a placeholder body (0.0).
  -- The runtime detects deontic functions via @schema.isDeontic@ and
  -- routes them to a JS-side interpreter that walks the
  -- @deonticContract@ tree against the request's @events@ stream —
  -- the wasm body is never invoked, so the placeholder is harmless.
  -- (Event-replay loop intentionally lives in JS so a future
  -- log-stream sink can resume from a checkpointed intermediate
  -- state without re-instantiating wasm.)
  Regulative{} -> emitVal $ \vid -> arithConstantFloat vid 0.0
  Breach{}     -> emitVal $ \vid -> arithConstantFloat vid 0.0
  -- Event / IO constructs still aren't supported — they don't have a
  -- runtime interpretation in the schema yet.
  Event{}      -> markUnsupported "EVENT construct not supported by the WASM backend"
  Fetch{}      -> markUnsupported "FETCH (IO) not supported by the WASM backend"
  Post{}       -> markUnsupported "POST (IO) not supported by the WASM backend"
  Env{}        -> markUnsupported "ENV not supported by the WASM backend"
  Record{}     -> markUnsupported "RECORD/COMMIT (ledger write) not supported by the WASM backend"
  ReadCell{}   -> markUnsupported "RECALL (ledger read) not supported by the WASM backend"

  -- RAnd/ROr (regulative and/or — same as boolean for compiled code)
  RAnd _ lhs rhs -> lowerBoolop arithAndi lhs rhs
  ROr _ lhs rhs -> lowerBoolop arithOri lhs rhs

-- | Emit a NUMBER literal as an exact rational handle (M4 slice 2b). The
-- L4 typechecker hands us a 'Rational', which we serialise to its canonical
-- @"<num>/<den>"@ text, intern in the string pool, then route through
-- @__l4_rat_parse@. This preserves the literal's full arbitrary precision
-- (no @fromRational :: Double@ truncation) and lets the runtime build the
-- exact BigInt rational. Used by 'lowerLit (NumericLit ...)' and the
-- internal-constant call sites (Percent, etc.).
emitNumberLiteral :: Rational -> LowerM Value
emitNumberLiteral r = do
  let txt = Text.pack (show (numerator r) <> "/" <> show (denominator r))
  globalName <- internString txt
  ptr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
    [NamedAttribute "global_name" (FlatSymbolRefAttr globalName)]
    [PointerType] []
  ptrF64 <- ptrToF64 ptr
  emitVal $ \vid -> funcCall [vid] "__l4_rat_parse"
    [ptrF64] [l4NumberType] [l4NumberType]

-- | Emit a binary rational op (@__l4_rat_add@ / @_sub@ / @_mul@ / @_div@ /
-- @_mod@). Both operands and the result are rational handles.
emitRatBinop :: Text -> Value -> Value -> LowerM Value
emitRatBinop fn a b =
  emitVal $ \vid -> funcCall [vid] fn [a, b]
    [l4NumberType, l4NumberType] [l4NumberType]

-- | The DATE\/TIME serial kind of an arithmetic operand, if any.
data SerialKind = SKDate | SKTime

-- | Resolve whether an operand is DATE- or TIME-typed, reusing the same
-- evidence ladder as 'classifyOperand': the typechecker's 'InfoMap'
-- ('typeOfExpr'), then the recorded source type of a bare @Var@
-- ('bindingL4Types'). Returns 'Nothing' for NUMBER (the overwhelmingly common
-- operand) and anything that isn't a date\/time — those need no bridging.
operandDateTimeKind :: Expr Resolved -> LowerM (Maybe SerialKind)
operandDateTimeKind e = do
  mt <- typeOfExpr e
  case mt >>= serialKind of
    Just k  -> pure (Just k)
    Nothing -> case e of
      App _ n [] -> do
        mL4 <- gets (Map.lookup (resolvedName n) . (.bindingL4Types))
        pure (mL4 >>= serialKind)
      _ -> pure Nothing
  where
    serialKind t
      | isDateType t = Just SKDate
      | isTimeType t = Just SKTime
      | otherwise    = Nothing

-- | serial (raw f64) → rational handle, via the runtime's own bridge
-- (@__l4_date_serial@ / @__l4_time_serial@ each do @ratFromInt(Number(d))@).
serialToHandle :: SerialKind -> Value -> LowerM Value
serialToHandle k v = emitVal $ \vid ->
  funcCall [vid] (serialBuiltin k) [v] [l4NumberType] [l4NumberType]
  where serialBuiltin SKDate = "__l4_date_serial"
        serialBuiltin SKTime = "__l4_time_serial"

-- | rational handle → serial (raw f64), the inverse bridge
-- (@__l4_date_from_serial@ / @__l4_time_from_serial@).
handleToSerial :: SerialKind -> Value -> LowerM Value
handleToSerial k v = emitVal $ \vid ->
  funcCall [vid] (fromSerialBuiltin k) [v] [l4NumberType] [l4NumberType]
  where fromSerialBuiltin SKDate = "__l4_date_from_serial"
        fromSerialBuiltin SKTime = "__l4_time_from_serial"

boxIfSerial :: Maybe SerialKind -> Value -> LowerM Value
boxIfSerial Nothing  v = pure v
boxIfSerial (Just k) v = serialToHandle k v

-- | Lower @PLUS@\/@MINUS@\/@TIMES@\/@DIVIDE@\/@MODULO@ through the exact-rational
-- runtime. DATE\/TIME operands arrive as raw f64 serials but @__l4_rat_*@
-- expects rational-pool handles, so any dated operand is boxed serial→handle
-- first (otherwise the rat op @ratUnbox@es the serial as a bogus pool index →
-- the @reading 'num' of undefined@ crash). The result of an /additive/ op with
-- exactly one dated operand is itself a DATE\/TIME (@date + n@, @date - n@), so
-- it is unboxed handle→serial; @date - date@ (both dated) is a day-count and
-- stays a NUMBER handle; non-additive ops never yield a date.
lowerRatBinop :: Text -> Expr Resolved -> Expr Resolved -> LowerM Value
lowerRatBinop fn lhs rhs = do
  lhsK <- operandDateTimeKind lhs
  rhsK <- operandDateTimeKind rhs
  lhsVal <- lowerExpr lhs l4NumberType >>= boxIfSerial lhsK
  rhsVal <- lowerExpr rhs l4NumberType >>= boxIfSerial rhsK
  result <- emitRatBinop fn lhsVal rhsVal
  case (fn `elem` ["__l4_rat_add", "__l4_rat_sub"], lhsK, rhsK) of
    (True, Just k,  Nothing) -> handleToSerial k result
    (True, Nothing, Just k)  -> handleToSerial k result
    _                        -> pure result

-- | Lower a literal.
lowerLit :: Lit -> MLIRType -> LowerM Value
lowerLit (NumericLit _ r) _ = emitNumberLiteral r
lowerLit (StringLit _ s) _
  -- A string literal containing an embedded NUL (U+0000) would be emitted
  -- as a NUL-terminated global and truncated at the embedded NUL by the
  -- host's C-string reader — a silent wrong answer vs. jl4-service's
  -- Data.Text. Runtime-produced strings recover their true length from a
  -- side table, but a compiler global has no such record, so refuse the
  -- enclosing function instead (routes to the fallback evaluator).
  | Text.elem '\0' s =
      markUnsupported
        "STRING literal contains an embedded NUL (U+0000), which the WASM \
        \backend's C-string ABI cannot represent faithfully"
lowerLit (StringLit _ s) _ = do
  -- Intern the string, take its address (@!llvm.ptr@), then box to f64
  -- so it can live as a uniform-ABI SSA value.
  globalName <- internString s
  ptr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
    [NamedAttribute "global_name" (FlatSymbolRefAttr globalName)]
    [PointerType] []
  ptrToF64 ptr

-- | Syntactic-shape NUMBER recognition. Conservative — only returns True
-- when the shape /must/ produce a NUMBER. Used as a fallback when the
-- typechecker's 'InfoMap' is missing or imprecise for a given node.
isNumberExprShape :: Expr Resolved -> Bool
isNumberExprShape = \case
  Lit _ (NumericLit _ _) -> True
  Plus{}      -> True
  Minus{}     -> True
  Times{}     -> True
  DividedBy{} -> True
  Modulo{}    -> True
  Percent{}   -> True
  App _ n _ -> case resolvedName n of
    "__PLUS__"    -> True
    "__MINUS__"   -> True
    "__TIMES__"   -> True
    "__DIVIDE__"  -> True
    "__MODULO__"  -> True
    _             -> False
  _ -> False

-- | The comparison-relevant class of an operand's L4 type. Drives the
-- 'lowerCmp' / 'dispatchEqualsByType' dispatch:
--
--   * 'CmpNumber' — a rational-pool /handle/. Ordered and equality
--     comparisons MUST go through @__l4_rat_cmp@; the raw f64 is a pool
--     index, so 'arith.cmpf' on it compares handle bit-patterns.
--   * 'CmpString' — a string-pool /pointer/. Equality MUST go through
--     @__l4_str_eq@ (content equality) and ordering through
--     @__l4_str_cmp@ (code-point lexicographic); the raw f64 is a
--     pointer, so 'arith.cmpf' compares addresses, not contents.
--   * 'CmpOther' — a value whose raw f64 /is/ its comparison key:
--     BOOLEAN (0.0\/1.0), enum tag (small int), DATE\/TIME serial. For
--     these the legacy 'arith.cmpf' on the f64 is correct.
data CmpClass = CmpNumber | CmpString | CmpOther
  deriving (Eq)

-- | Resolve an operand's 'CmpClass' as reliably as possible. Combines, in
-- order of confidence:
--
--   1. the typechecker's 'InfoMap' (exact-range match via 'typeOfExpr');
--   2. the recorded source-level type of a bare @Var@ reference
--      ('bindingL4Types' — populated for GIVEN params and WHERE\/LET
--      locals), which covers the very common case where the 'InfoMap'
--      has no exact-range entry for a leaf @Var@;
--   3. the callee's checked type from the bundle-wide 'funcL4Types' map,
--      for any 'App' operand — a helper CALL RESULT, or a bare reference
--      to a zero-arg definition ('entityResultClass'); and
--   4. structural shape inference ('structuralClass') for literals and
--      builtins whose result type is fixed by their shape.
--
-- Returns 'Nothing' only when the type genuinely cannot be determined by
-- any of these — the residual case 'lowerCmp' refuses to compile rather
-- than emit an unsound 'arith.cmpf' on a possible handle\/pointer.
-- | Unfold a user-declared type SYNONYM chain to its underlying 'Type''.
-- @DECLARE Date IS A STRING@ resolves @Date@ → STRING so the classifiers
-- (which match builtin scalar names) see through the alias. Cycle-guarded.
-- Builtin DATE\/TIME are not in the map, so they are returned unchanged.
unfoldSynT :: Map Text (Type' Resolved) -> Type' Resolved -> Type' Resolved
unfoldSynT syns = go Set.empty
  where
    go visited ty = case ty of
      TyApp _ name []
        | let nm = resolvedName name
        , not (Set.member nm visited)
        , Just inner <- Map.lookup nm syns
        -> go (Set.insert nm visited) inner
      _ -> ty

classifyOperand :: Expr Resolved -> LowerM (Maybe CmpClass)
classifyOperand e = do
  syns <- gets (.typeSynonyms)
  let classify = classifyL4Type . unfoldSynT syns
  mt <- typeOfExpr e
  -- IMPORTANT: the 'InfoMap' we read is *not* run through the final
  -- substitution (unlike the LSP path), so 'typeOfExpr' frequently
  -- returns @Just (InfVar …)@ — an un-resolved inference variable — for
  -- leaf @Var@s. An 'InfVar' carries no usable class, so we must NOT let
  -- it short-circuit the 'bindingL4Types' / structural fallbacks (doing
  -- so was the original STRING-equality bug: the @Just InfVar@ was read
  -- as "not a string" and fell through to a raw 'arith.cmpf' on the
  -- string pointer). 'classifyL4Type' returns 'Nothing' for any
  -- non-concrete type, so only a fully-resolved @TyApp@ head is trusted
  -- here; everything else falls through.
  case mt >>= classify of
    Just cls -> pure (Just cls)
    Nothing  -> case e of
      -- A bare @Var@ reference (App with no args): the 'InfoMap' often
      -- lacks an exact-range entry — or carries only an 'InfVar' — for
      -- the leaf, but 'bindingL4Types' records the param's\/local's
      -- resolved source type. If that misses too (e.g. a reference to a
      -- zero-arg top-level MEANS constant like daydate's @Saturday@),
      -- fall through to the entity map.
      App _ n [] -> do
        let name = resolvedName n
        mL4Ty <- gets (Map.lookup name . (.bindingL4Types))
        case mL4Ty >>= classify of
          Just cls -> pure (Just cls)
          Nothing  -> entityOrStructural n 0
      -- A call: the operand's type is the callee's RESULT type, which
      -- the f64 'funcSigs' erase but 'funcL4Types' preserves.
      App _ n args -> entityOrStructural n (length args)
      _ -> pure (structuralClass e)
  where
    entityOrStructural n nargs = do
      mCls <- entityResultClass n nargs
      case mCls of
        Just cls -> pure (Just cls)
        Nothing  -> pure (structuralClass e)

-- | Classify an 'App' operand by the callee's typechecker-recorded type
-- from the bundle-wide 'funcL4Types' map: look up the head's 'Unique',
-- reduce the recorded type to the RESULT type at this application's arity,
-- and classify it — conservatively, via 'classifyGroundType'.
entityResultClass :: Resolved -> Int -> LowerM (Maybe CmpClass)
entityResultClass n nargs = do
  types <- gets (.funcL4Types)
  syns  <- gets (.typeSynonyms)
  pure $ Map.lookup (getUnique n) types
           >>= resultTypeAtArity nargs
           >>= classifyGroundType . unfoldSynT syns

-- | The type an application results in, given the callee's recorded type
-- and the number of arguments applied. Conservative: only a SATURATED
-- application of a 'Fun' reduces to its return type; a partial (or over-)
-- application yields 'Nothing' rather than a guess. A 'Forall' wrapper is
-- stripped first (prelude helpers like @count@ are polymorphic — their
-- 'Fun' body may still name type variables, which 'classifyGroundType'
-- refuses downstream).
resultTypeAtArity :: Int -> Type' Resolved -> Maybe (Type' Resolved)
resultTypeAtArity nargs (Forall _ _ ty) = resultTypeAtArity nargs ty
resultTypeAtArity 0 ty = Just ty
resultTypeAtArity nargs (Fun _ args ret)
  | nargs == length args = Just ret
resultTypeAtArity _ _ = Nothing

-- | Conservative classifier for entity-derived types. Unlike
-- 'classifyL4Type' — which may trust any resolved 'TyApp' head as
-- 'CmpOther' — this accepts only the closed set of builtin scalar heads.
-- An entity's recorded type is the DEFINITION's generic type, and a type
-- VARIABLE reference is syntactically indistinguishable from a nullary
-- type constructor ('TyApp' with no args): trusting one as 'CmpOther'
-- would emit a raw @arith.cmpf@ on what is a rational-pool handle at the
-- instantiated type (e.g. a @LIST OF a -> a@ helper used on NUMBERs) — a
-- silent wrong answer, the exact bug class this branch exists to kill.
-- Enum\/record\/type-variable results therefore refuse here: a routed
-- fallback beats a misclassified comparison.
classifyGroundType :: Type' Resolved -> Maybe CmpClass
classifyGroundType t
  | isNumberType t  = Just CmpNumber
  | isStringType t  = Just CmpString
  | isBooleanType t = Just CmpOther
  | isDateType t    = Just CmpOther
  | isTimeType t    = Just CmpOther
  | otherwise       = Nothing

-- | Classify a resolved L4 type into a 'CmpClass'. NUMBER and STRING are
-- the handle\/pointer ABIs that need a runtime call. Returns 'Nothing'
-- for any /non-concrete/ type — an inference variable ('InfVar'), a
-- function type, a @Forall@, or the kind @Type@ — so the caller falls
-- through to a more reliable source rather than mis-reading an
-- un-substituted 'InfVar' as @CmpOther@.
classifyL4Type :: Type' Resolved -> Maybe CmpClass
classifyL4Type t
  | isNumberType t = Just CmpNumber
  | isStringType t = Just CmpString
  | isConcreteType t = Just CmpOther
  | otherwise      = Nothing

-- | A type is "concrete" for comparison purposes when it is a fully
-- applied type constructor (a @TyApp@ with a resolved head) — i.e. a
-- BOOLEAN, an enum, a DATE\/TIME, a record, etc. whose raw f64 /is/ its
-- comparison key. Inference variables and arrow\/forall types are not
-- concrete and must not be trusted as @CmpOther@.
isConcreteType :: Type' Resolved -> Bool
isConcreteType TyApp{} = True
isConcreteType _       = False

-- | Structural inference, used only when neither the 'InfoMap' nor
-- 'bindingL4Types' resolved the operand. Conservative: returns 'Just'
-- only when the shape /must/ produce a NUMBER or STRING. Never claims
-- 'CmpOther' — an unrecognised shape stays 'Nothing' so the caller can
-- fail loud rather than guess.
structuralClass :: Expr Resolved -> Maybe CmpClass
structuralClass e
  | isNumberExprShape e = Just CmpNumber
  | otherwise = case e of
      Lit _ (StringLit _ _) -> Just CmpString
      Concat{}              -> Just CmpString
      AsString{}            -> Just CmpString
      App _ n _ -> case resolvedName n of
        "__l4_str_concat" -> Just CmpString
        "__l4_to_string"  -> Just CmpString
        _                 -> Nothing
      _ -> Nothing

-- | Combine the two operands' resolved 'CmpClass'es into the comparison's
-- class. A concrete NUMBER\/STRING on /either/ side fixes the comparison
-- (the two operands must share a type to have type-checked), so a known
-- side rescues an unresolved one. 'Nothing' (both unresolved) is the only
-- case the caller must refuse.
combineCmpClass :: Maybe CmpClass -> Maybe CmpClass -> Maybe CmpClass
combineCmpClass a b
  | Just CmpNumber `elem` [a, b] = Just CmpNumber
  | Just CmpString `elem` [a, b] = Just CmpString
  | Just CmpOther  `elem` [a, b] = Just CmpOther
  | otherwise                    = Nothing

isNumberType :: Type' Resolved -> Bool
isNumberType t = case t of
  TyApp _ n _ -> nameMatches n ["NUMBER", "number"]
  _ -> False

isStringType :: Type' Resolved -> Bool
isStringType t = case t of
  TyApp _ n _ -> nameMatches n ["STRING", "string"]
  _ -> False

isBooleanType :: Type' Resolved -> Bool
isBooleanType t = case t of
  TyApp _ n _ -> nameMatches n ["BOOLEAN", "boolean"]
  _ -> False

-- | DATE\/TIME are NUMBER-compatible in jl4-core (a date /is/ its day-serial,
-- a time /is/ its second-serial — see @libraries/daydate.l4@, which does
-- @DATE PLUS NUMBER@ etc. directly). But in this backend a DATE\/TIME value
-- flows as a /raw f64 serial/ (the date intrinsics — @__l4_date_serial@,
-- @make-date@, weekday — all read\/write the bare serial), whereas the generic
-- rational ops @__l4_rat_*@ operate on rational-pool /handles/. So a DATE\/TIME
-- operand of @MINUS@\/@PLUS@\/… must be boxed serial→handle before the op (and
-- a DATE\/TIME /result/ unboxed handle→serial after). 'lowerRatBinop' does this
-- bridging; these predicates and 'operandDateTimeKind' detect when to.
-- Case-insensitive, mirroring the schema emitter's @Text.toLower@ name match.
isDateType :: Type' Resolved -> Bool
isDateType t = case t of
  TyApp _ n _ -> Text.toLower (resolvedName n) == "date"
  _ -> False

isTimeType :: Type' Resolved -> Bool
isTimeType t = case t of
  TyApp _ n _ -> Text.toLower (resolvedName n) == "time"
  _ -> False

nameMatches :: Resolved -> [Text] -> Bool
nameMatches r names = resolvedName r `elem` names

-- | Lower a comparison. Dispatches on the operand's resolved 'CmpClass'
-- ('classifyOperand' + 'combineCmpClass'):
--
--   * NUMBER → @__l4_rat_cmp@ returning -1.0\/0.0\/1.0 (f64-ABI); compare
--     against 0.0 with @arith.cmpf@ to get the @i1@ truth value with the
--     same predicate the source used. Works for both ordered and equality
--     comparisons.
--   * STRING ==\/!= → @__l4_str_eq@ returning 0.0\/1.0 (f64-ABI); compare
--     against 1.0 (or 0.0, for !=) to get @i1@.
--   * STRING ordered (\<, \<=, \>, \>=) → @__l4_str_cmp@ returning
--     -1.0\/0.0\/1.0 (f64-ABI); compare against 0.0 with the source
--     predicate. Comparison is lexicographic by Unicode code point,
--     matching jl4-core's Data.Text Ord — the raw f64 is a string-pool
--     /pointer/, so a direct 'arith.cmpf' would order addresses, not
--     contents; the runtime call reads the pooled contents instead.
--   * 'CmpOther' (BOOLEAN, enum tag, DATE\/TIME serial) → legacy
--     @arith.cmpf@ on the raw f64, which /is/ the correct comparison key
--     for these.
--   * Unresolvable (neither side's type could be determined) → /fail
--     loud/. The raw f64 might be a rational handle or a string pointer;
--     an 'arith.cmpf' on it would compare handle\/pointer bit-patterns and
--     "almost always" yield the wrong boolean. A refused compile is
--     acceptable; a silent wrong boolean on a legal\/financial rule is
--     not.
--
-- The native @i1@ result is then lifted to the uniform-ABI f64 truth value
-- (0.0 = false, 1.0 = true) via 'boxBoolI1'.
lowerCmp :: CmpfPredicate -> Expr Resolved -> Expr Resolved -> LowerM Value
lowerCmp pred_ lhs rhs = do
  clsLhs <- classifyOperand lhs
  clsRhs <- classifyOperand rhs
  case combineCmpClass clsLhs clsRhs of
    Just CmpNumber -> do
      -- A NUMBER is a rational-pool handle: never compare the handles
      -- directly. @__l4_rat_cmp@ returns -1.0\/0.0\/1.0; re-applying the
      -- source predicate against 0.0 recovers the intended truth value.
      lhsVal <- lowerExpr lhs l4NumberType
      rhsVal <- lowerExpr rhs l4NumberType
      cmpF <- emitVal $ \vid -> funcCall [vid] "__l4_rat_cmp"
        [lhsVal, rhsVal] [l4NumberType, l4NumberType] [l4NumberType]
      zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
      i1Val <- emitVal $ \vid -> arithCmpf vid pred_ cmpF zero
      boxBoolI1 i1Val
    Just CmpString -> case pred_ of
      OEQ -> lowerStringEq lhs rhs False
      ONE -> lowerStringEq lhs rhs True
      _   -> do
        -- Ordered STRING comparison (<, <=, >, >=). A STRING is a
        -- string-pool /pointer/: never compare the pointers directly.
        -- @__l4_str_cmp@ returns -1.0\/0.0\/1.0 (lexicographic by
        -- Unicode code point, matching jl4-core's Data.Text Ord);
        -- re-applying the source predicate against 0.0 recovers the
        -- intended truth value — exactly like the CmpNumber arm does
        -- with @__l4_rat_cmp@.
        lhsVal <- lowerExpr lhs l4NumberType
        rhsVal <- lowerExpr rhs l4NumberType
        cmpF <- emitVal $ \vid -> funcCall [vid] "__l4_str_cmp"
          [lhsVal, rhsVal] [l4NumberType, l4NumberType] [l4NumberType]
        zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
        i1Val <- emitVal $ \vid -> arithCmpf vid pred_ cmpF zero
        boxBoolI1 i1Val
    Just CmpOther -> do
      -- BOOLEAN / enum tag / DATE / TIME serial: the raw f64 is the
      -- comparison key, so the direct arith.cmpf is correct.
      lhsVal <- lowerExpr lhs l4NumberType
      rhsVal <- lowerExpr rhs l4NumberType
      i1Val <- emitVal $ \vid -> arithCmpf vid pred_ lhsVal rhsVal
      boxBoolI1 i1Val
    Nothing -> markUnsupported
      "comparison on a value whose type could not be resolved; emitting a \
      \raw arith.cmpf would be unsound on the rational-handle / \
      \string-pointer ABI (the f64 may be a pool handle or pointer, not a \
      \comparable numeric value)"

-- | Lower STRING equality (==) or inequality (!=) through @__l4_str_eq@
-- (content equality). The runtime returns 0.0\/1.0; we compare that
-- against 1.0 (for ==) or 0.0 (for !=) to get the @i1@ truth value.
lowerStringEq :: Expr Resolved -> Expr Resolved -> Bool -> LowerM Value
lowerStringEq lhs rhs invert = do
  lhsVal <- lowerExpr lhs l4NumberType
  rhsVal <- lowerExpr rhs l4NumberType
  eqF <- emitVal $ \vid -> funcCall [vid] "__l4_str_eq"
    [lhsVal, rhsVal] [l4NumberType, l4NumberType] [l4NumberType]
  cmpAgainst <- emitVal $ \vid ->
    arithConstantFloat vid (if invert then 0.0 else 1.0)
  i1Val <- emitVal $ \vid -> arithCmpf vid OEQ eqF cmpAgainst
  boxBoolI1 i1Val

-- | Lower a boolean binary operation. Operands arrive as f64 (encoded
-- as 0.0 / 1.0). We unbox each to @i1@, run the native op, then box
-- the @i1@ result back to f64.
-- | Lower an eager boolean op (arith.andi / arith.ori) — historical
-- entry point; kept for non-AND/OR call sites (RAnd, ROr, etc.).
lowerBoolop :: (ValueId -> Value -> Value -> Operation) -> Expr Resolved -> Expr Resolved -> LowerM Value
lowerBoolop mkBoolop lhs rhs = do
  lhsF64 <- lowerExpr lhs l4NumberType
  rhsF64 <- lowerExpr rhs l4NumberType
  lhsI1 <- unboxBoolI1 lhsF64
  rhsI1 <- unboxBoolI1 rhsF64
  resultI1 <- emitVal $ \vid -> mkBoolop vid lhsI1 rhsI1
  boxBoolI1 resultI1

-- | M5 slice 4D — short-circuit AND. Evaluates @lhs@ first; only
-- evaluates @rhs@ when @lhs@ is true. Wraps @rhs@ in an scf.if then-
-- region so its lowered ops (including any @__l4_mark_forced@ markers
-- from nested @Proj@s) execute only on the live branch — bringing
-- the runtime's `forcedFields` set in line with jl4-core's lazy
-- evaluation.
lowerAndShortCircuit :: Expr Resolved -> Expr Resolved -> LowerM Value
lowerAndShortCircuit lhs rhs = do
  lhsF64 <- lowerExpr lhs l4NumberType
  lhsI1  <- unboxBoolI1 lhsF64
  -- Then branch: evaluate rhs and yield its f64-boxed bool.
  (rhsF64, rhsOps) <- collectOps $ lowerExpr rhs l4NumberType
  -- Else branch: yield a fresh f64-boxed FALSE (no rhs eval).
  (falseF64, elseOps) <- collectOps $ do
    f <- emitVal $ \vid -> arithConstantBool vid False
    boxBoolI1 f
  let thenBlock = Block 0 [] (rhsOps  ++ [scfYield [rhsF64]   [l4NumberType]])
      elseBlock = Block 0 [] (elseOps ++ [scfYield [falseF64] [l4NumberType]])
  emitVal $ \vid -> scfIf [vid] lhsI1 (Region [thenBlock]) (Region [elseBlock]) [l4NumberType]

-- | M5 slice 4D — short-circuit OR. Mirror of 'lowerAndShortCircuit'
-- with TRUE for the else-branch fallback.
lowerOrShortCircuit :: Expr Resolved -> Expr Resolved -> LowerM Value
lowerOrShortCircuit lhs rhs = do
  lhsF64 <- lowerExpr lhs l4NumberType
  lhsI1  <- unboxBoolI1 lhsF64
  -- Then branch: yield a fresh f64-boxed TRUE (no rhs eval).
  (trueF64, thenOps) <- collectOps $ do
    t <- emitVal $ \vid -> arithConstantBool vid True
    boxBoolI1 t
  -- Else branch: evaluate rhs.
  (rhsF64, rhsOps) <- collectOps $ lowerExpr rhs l4NumberType
  let thenBlock = Block 0 [] (thenOps ++ [scfYield [trueF64] [l4NumberType]])
      elseBlock = Block 0 [] (rhsOps  ++ [scfYield [rhsF64]  [l4NumberType]])
  emitVal $ \vid -> scfIf [vid] lhsI1 (Region [thenBlock]) (Region [elseBlock]) [l4NumberType]

-- | Promote an @i1@ SSA value to @f64@ (0.0 / 1.0).
boxBoolI1 :: Value -> LowerM Value
boxBoolI1 i1Val =
  emitVal $ \vid -> mkOp [vid] "arith.uitofp" [i1Val] []
    [l4NumberType] [IntegerType 1]

-- | Demote an @f64@ (0.0 / nonzero) back to @i1@ for native boolean ops.
unboxBoolI1 :: Value -> LowerM Value
unboxBoolI1 f64Val = do
  zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
  emitVal $ \vid -> arithCmpf vid ONE f64Val zero

-- | Lower CONSIDER/WHEN pattern matching.
lowerConsider :: Expr Resolved -> [Branch Resolved] -> MLIRType -> LowerM Value
lowerConsider scrutinee branches _expectedTy = do
  scrutVal <- lowerExpr scrutinee l4NumberType
  lowerBranches scrutVal branches

-- | Lower CONSIDER branches. The scrutinee is f64; all branch results
-- are f64 (uniform ABI), so the synthesised @scf.if@ yields f64.
--
-- The no-branch fallthrough used to emit @arith.constant 0.0 : f64@, which
-- under the rational-handle ABI would alias the very first rational the
-- pool ever allocated (handle index 0). Emit a fresh NUMBER-zero handle
-- instead, so the value is safe to consume as a NUMBER. The cost is one
-- @__l4_rat_parse \"0\/1\"@ per branch-exhausted CONSIDER, which is
-- unreachable in well-typed L4 anyway.
--
-- Only a *bare* @OTHERWISE@ branch is executed unconditionally. A
-- guarded @WHEN p@ branch — even the LAST one — is always tested via
-- 'testPatternTy' (its else arm is the branch-exhausted fallthrough).
-- An earlier version short-circuited a trailing single @WHEN@ branch
-- as an unconditional fallthrough, which skipped its guard entirely
-- and could match values the pattern rejects.
lowerBranches :: Value -> [Branch Resolved] -> LowerM Value
lowerBranches _ [] = emitNumberLiteral 0
lowerBranches _scrutVal [MkBranch _ (Otherwise _) body] =
  lowerExpr body l4NumberType
lowerBranches scrutVal (MkBranch _ branchLhs body : rest) = do
  case branchLhs of
    Otherwise _ -> lowerExpr body l4NumberType
    When _ pat -> do
      matchVal <- testPatternTy scrutVal l4NumberType pat
      (thenVal, thenOps) <- collectOps $ withScope $ do
        bindPatternTy scrutVal l4NumberType l4NumberType pat
        lowerExpr body l4NumberType
      (elseVal, elseOps) <- collectOps $ lowerBranches scrutVal rest
      let thenBlock = Block 0 [] (thenOps ++ [scfYield [thenVal] [l4NumberType]])
          elseBlock = Block 0 [] (elseOps ++ [scfYield [elseVal] [l4NumberType]])
      emitVal $ \vid -> scfIf [vid] matchVal (Region [thenBlock]) (Region [elseBlock]) [l4NumberType]

-- | Test a pattern against a scrutinee of known type.
-- ---------------------------------------------------------------------------
-- Pattern matching under the uniform f64 ABI
-- ---------------------------------------------------------------------------
--
-- All scrutinees are f64. Tests produce an i1 (for feeding scf.if).
-- Bindings bind f64 values extracted via 'loadSlot'.
-- Conventions by pattern shape:
--   * PatApp "NOTHING" []   — scrutinee is a MAYBE record (ptr→[tag,value]).
--       Match if tag == 0.0 (i.e. unboxBoolI1 tag == false).
--   * PatApp "JUST"    [p]  — match if tag == 1.0. Bind p to slot 1.
--   * PatApp "EMPTY"   []   — scrutinee is a list ptr. Match if ptr is null.
--   * PatCons _ hd tl       — scrutinee is non-null list ptr.
--                             Bind hd=slot 0, tl=slot 1.
--   * PatApp con []         — enum constructor: match if scrutinee == tag.
--   * PatApp con args       — enum-with-data constructor: match the tag.
--                             Args bind to slots starting at 1 (slot 0 = tag).
--   * PatLit (Numeric n)    — match if scrutinee == n.
--   * PatLit (String s)     — match if @__l4_str_eq scrut s == 1.0@.
--   * PatVar _              — always matches, binds the scrutinee as-is.
--   * PatExpr _             — markUnsupported (the WASM backend can't
--                             evaluate an arbitrary computed-expression
--                             pattern as a guard).

testPatternTy :: Value -> MLIRType -> Pattern Resolved -> LowerM Value
testPatternTy = go
  where
    go _ _ (PatVar _ _) = trueI1
    go scrutF64 _ (PatApp _ con []) = do
      let name = resolvedName con
      env <- gets (.typeEnv)
      -- User-declared constructors win over the builtin string cases.
      -- The CONSTRUCTION path ('lowerExpr' App) resolves a constructor by
      -- consulting 'lookupRecordFields' / 'lookupEnumTag' BEFORE the
      -- prelude string intrinsics, so a user enum/record whose constructor
      -- happens to be named NOTHING/EMPTY is built with the user layout.
      -- We must mirror that ordering here or construction and matching
      -- would use different representations (see the LEFT/RIGHT shadow
      -- regression). Only a name that is NOT a user constructor can be the
      -- prelude builtin, so the string cases are then safe.
      if isUserConstructor name env
        then case lookupEnumTag name env of
          Just tag -> enumTagCmpF64 scrutF64 tag
          -- A user record constructor (nullary in a CONSIDER position) has
          -- no enum tag; fail closed rather than guess a tag.
          Nothing  -> unsupportedMatch (unresolvedEnumReason name)
        else case name of
          "NOTHING" -> do
            tag <- loadSlot scrutF64 0
            tagI1 <- unboxBoolI1 tag
            trueI1v <- trueI1
            emitVal $ \vid -> arithXori vid tagI1 trueI1v
          "EMPTY" -> do
            zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
            emitVal $ \vid -> arithCmpf vid OEQ scrutF64 zero
          _ -> unsupportedMatch (unresolvedEnumReason name)
    go scrutF64 _ (PatApp _ con [_]) = do
      let name = resolvedName con
      env <- gets (.typeEnv)
      -- User-declared constructors win over the builtin JUST/LEFT/RIGHT
      -- string cases, mirroring the CONSTRUCTION path's lookup-first
      -- ordering (see the arity-0 arm and 'lowerExpr'). Only a name absent
      -- from the user's records/enums can be the prelude builtin, so the
      -- string cases are safe.
      --
      -- A user constructor reaching THIS arm binds a payload (arity 1): it
      -- is either a record constructor or an @ONE OF … HAS …@ enum-with-
      -- data variant. The construction path lowers such a constructor to a
      -- BARE enum tag (see 'lowerExpr': the 'lookupEnumTag' arm discards the
      -- argument), so there is no payload slot to bind — reading one yields
      -- a tag-as-handle (garbage / runtime trap). We therefore REFUSE
      -- (fail-closed → the export is 'supported:false' and the caller routes
      -- to the reference evaluator) rather than emit a silent wrong answer.
      if isUserConstructor name env
        then unsupportedMatch (payloadCtorReason name)
        else case name of
          "JUST" -> do
            tag <- loadSlot scrutF64 0
            unboxBoolI1 tag
          -- EITHER RIGHT — matches when the tag slot is 1.0 (see the LEFT/
          -- RIGHT construction in 'lowerExpr'); binds the payload in
          -- 'bindPatternTy'. Same [tag, payload] layout as MAYBE's JUST.
          "RIGHT" -> do
            tag <- loadSlot scrutF64 0
            unboxBoolI1 tag
          -- EITHER LEFT — matches when the tag slot is 0.0 (NOT the tag),
          -- mirroring the NOTHING test.
          "LEFT" -> do
            tag <- loadSlot scrutF64 0
            tagI1 <- unboxBoolI1 tag
            trueBit <- trueI1
            emitVal $ \vid -> arithXori vid tagI1 trueBit
          _ -> unsupportedMatch (unresolvedEnumReason name)
    go _ _ (PatApp _ con _) = do
      -- Arity ≥ 2: necessarily a user constructor carrying multiple fields
      -- (no builtin has this shape). As in the arity-1 case, the payload is
      -- lowered as a bare tag with no slots, so destructuring it is unsound
      -- — refuse rather than compute a silent wrong.
      let name = resolvedName con
      unsupportedMatch (payloadCtorReason name)
    go scrutF64 _ (PatLit _ (NumericLit _ r)) = do
      -- The scrutinee is a NUMBER handle; compare for equality via
      -- @__l4_rat_cmp@ against the literal's handle.
      lit <- emitNumberLiteral r
      cmpF <- emitVal $ \vid -> funcCall [vid] "__l4_rat_cmp"
        [scrutF64, lit] [l4NumberType, l4NumberType] [l4NumberType]
      zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
      emitVal $ \vid -> arithCmpf vid OEQ cmpF zero
    go _ _ (PatLit _ (StringLit _ s)) | Text.elem '\0' s =
      -- A NUL-containing literal pattern would truncate at the embedded
      -- NUL in the compiler global and mis-match; refuse instead.
      unsupportedMatch
        "CONSIDER STRING pattern contains an embedded NUL (U+0000), which \
        \the WASM backend's C-string ABI cannot represent faithfully"
    go scrutF64 _ (PatLit _ (StringLit _ s)) = do
      -- The scrutinee is a STRING handle (boxed @!llvm.ptr@). Intern the
      -- literal, box its address the same way 'lowerLit' does, then ask
      -- the runtime for content equality via @__l4_str_eq@ (the same
      -- idiom 'dispatchEqualsByType' uses for @EQUALS@ on strings). The
      -- call returns 1.0 for equal / 0.0 for unequal; match iff == 1.0.
      globalName <- internString s
      ptr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
        [NamedAttribute "global_name" (FlatSymbolRefAttr globalName)]
        [PointerType] []
      litF64 <- ptrToF64 ptr
      eqF <- emitVal $ \vid -> funcCall [vid] "__l4_str_eq"
        [scrutF64, litF64] [l4NumberType, l4NumberType] [l4NumberType]
      one <- emitVal $ \vid -> arithConstantFloat vid 1.0
      emitVal $ \vid -> arithCmpf vid OEQ eqF one
    go scrutF64 _ (PatCons _ _ _) = do
      -- List is non-null: scrutinee != 0.0
      zero <- emitVal $ \vid -> arithConstantFloat vid 0.0
      emitVal $ \vid -> arithCmpf vid ONE scrutF64 zero
    go _ _ (PatExpr _ _) =
      unsupportedMatch
        "CONSIDER with a computed-expression pattern is not supported by the WASM backend"

    -- | Reason string for a constructor tag that the lowering can't
    -- resolve to a concrete enum index. Such a pattern used to always
    -- match (returning @trueI1@), which silently mis-evaluated the
    -- CONSIDER; now we flag the enclosing function unsupported instead.
    unresolvedEnumReason name =
      "CONSIDER pattern constructor " <> name
        <> " could not be resolved to an enum tag by the WASM backend"

    -- | Reason for refusing a CONSIDER that destructures a user-declared
    -- constructor which carries a payload (a record constructor, or an
    -- @ONE OF … HAS …@ enum-with-data variant). The construction path
    -- lowers such a constructor to a bare enum tag with no payload slots,
    -- so binding the payload here would read garbage. Fail closed.
    payloadCtorReason name =
      "CONSIDER destructuring the payload-carrying user constructor "
        <> name
        <> " is not supported by the WASM backend (enum-with-data / record "
        <> "constructors are lowered as a bare tag, so the payload cannot be "
        <> "bound)"


-- | Record an unsupported-pattern diagnostic against the enclosing
-- function (via 'markUnsupported'), then return a FALSE @i1@ so the
-- synthesised @scf.if@ stays well-typed (its condition must be @i1@,
-- not the @f64@ 0.0 'markUnsupported' yields). Fail-closed: the branch
-- never matches, and the export is flagged @supported: false@ so the
-- proxy routes the call to a fallback evaluator rather than trusting a
-- WASM module that can't evaluate this pattern.
unsupportedMatch :: Text -> LowerM Value
unsupportedMatch reason = do
  _ <- markUnsupported reason
  falseI1

-- | Compare an f64-scrutinee against an enum tag (as f64).
enumTagCmpF64 :: Value -> Integer -> LowerM Value
enumTagCmpF64 scrutF64 tag = do
  tagVal <- emitVal $ \vid -> arithConstantFloat vid (fromIntegral tag)
  emitVal $ \vid -> arithCmpf vid OEQ scrutF64 tagVal

trueI1 :: LowerM Value
trueI1 = emitVal $ \vid -> arithConstantBool vid True

falseI1 :: LowerM Value
falseI1 = emitVal $ \vid -> arithConstantBool vid False

-- | Bind pattern variables under the uniform f64 ABI. The scrutinee and
-- all bound values are f64 — enum-tag / maybe / list destructuring is
-- implemented by 'loadSlot'.
bindPatternTy :: Value -> MLIRType -> MLIRType -> Pattern Resolved -> LowerM ()
bindPatternTy val _ _ (PatVar _ n) = bindTy (resolvedName n) val l4NumberType
bindPatternTy val _ _ (PatCons _ hd tl) = do
  hdVal <- loadSlot val 0
  tlVal <- loadSlot val 1
  bindPatternTy hdVal l4NumberType l4NumberType hd
  bindPatternTy tlVal l4NumberType l4NumberType tl
bindPatternTy val _ _ (PatApp _ con [innerPat]) = do
  let name = resolvedName con
  env <- gets (.typeEnv)
  -- Mirror the CONSTRUCTION path and 'testPatternTy': a user-declared
  -- constructor (record/enum) named JUST/LEFT/RIGHT must NOT read slot 1
  -- of the builtin [tag, payload] layout — its value uses the user layout.
  -- Fall through to the generic binder, exactly as before ledger #10.
  if isUserConstructor name env
    then bindPatternTy val l4NumberType l4NumberType innerPat
    else case name of
      "JUST" -> do
        innerVal <- loadSlot val 1
        bindPatternTy innerVal l4NumberType l4NumberType innerPat
      -- EITHER LEFT / RIGHT both carry their payload in slot 1 of the
      -- 2-slot [tag, payload] record (see 'lowerExpr' construction).
      "LEFT" -> do
        innerVal <- loadSlot val 1
        bindPatternTy innerVal l4NumberType l4NumberType innerPat
      "RIGHT" -> do
        innerVal <- loadSlot val 1
        bindPatternTy innerVal l4NumberType l4NumberType innerPat
      _ -> bindPatternTy val l4NumberType l4NumberType innerPat
bindPatternTy val _ _ (PatApp _ _ pats) =
  -- Enum-with-data constructor: slot 0 is the tag, bind args at 1..n.
  forM_ (zip [1..] pats) $ \(i, p) -> do
    v <- loadSlot val i
    bindPatternTy v l4NumberType l4NumberType p
bindPatternTy _ _ _ (PatLit _ _) = pure ()
bindPatternTy _ _ _ (PatExpr _ _) = pure ()


-- | Bind pattern variables into scope.

-- ---------------------------------------------------------------------------
-- Record / list / maybe storage under the uniform f64 ABI
-- ---------------------------------------------------------------------------
--
-- Compound L4 values (records, lists, MAYBE) live in linear memory as
-- arrays of f64 slots (8 bytes each, naturally aligned for @f64@
-- loads). Each field is a boxed f64 — a number stays as itself, a
-- boolean is 0.0/1.0, a string or nested record/list/maybe is a
-- pointer-bitcast-to-f64. The SSA-level value for any compound
-- is therefore just an f64 containing the pointer to its first slot.
--
-- This keeps the entire SSA value universe flat @f64@ while still
-- supporting compound L4 semantics.

-- | Number of linear-memory bytes needed for @n@ f64 slots.
slotBytes :: Int -> Int
slotBytes n = n * 8

-- | Allocate @n@ f64 slots in linear memory and return the head pointer
-- as an f64 (bitcast through i64).
allocSlots :: Int -> LowerM Value
allocSlots n = do
  size <- emitVal $ \vid -> arithConstantInt vid (fromIntegral (slotBytes n))
  ptr  <- emitVal $ \vid -> funcCall [vid] "__l4_alloc" [size]
                                [IntegerType 64] [PointerType]
  ptrToF64 ptr

-- | Write an f64 value into slot @i@ of a boxed pointer.
storeSlot :: Value -> Int -> Value -> LowerM ()
storeSlot boxedPtr idx v = do
  ptr <- f64ToPtr boxedPtr
  off <- emitVal $ \vid -> arithConstantInt vid (fromIntegral (slotBytes idx))
  slot <- emitVal $ \vid -> llvmGetelementptr vid ptr [off] (IntegerType 8)
  emit $ llvmStore v slot l4NumberType

-- | Read an f64 value from slot @i@ of a boxed pointer.
loadSlot :: Value -> Int -> LowerM Value
loadSlot boxedPtr idx = do
  ptr <- f64ToPtr boxedPtr
  off <- emitVal $ \vid -> arithConstantInt vid (fromIntegral (slotBytes idx))
  slot <- emitVal $ \vid -> llvmGetelementptr vid ptr [off] (IntegerType 8)
  emitVal $ \vid -> llvmLoad vid slot l4NumberType

-- | Bitcast an @!llvm.ptr@ to @f64@ (via i64).
ptrToF64 :: Value -> LowerM Value
ptrToF64 ptr = do
  intV <- emitVal $ \vid -> mkOp [vid] "llvm.ptrtoint" [ptr] []
    [IntegerType 64] [PointerType]
  emitVal $ \vid -> mkOp [vid] "arith.bitcast" [intV] []
    [l4NumberType] [IntegerType 64]

-- | Bitcast an f64 back to @!llvm.ptr@ (via i64).
f64ToPtr :: Value -> LowerM Value
f64ToPtr f = do
  intV <- emitVal $ \vid -> mkOp [vid] "arith.bitcast" [f] []
    [IntegerType 64] [l4NumberType]
  emitVal $ \vid -> mkOp [vid] "llvm.inttoptr" [intV] []
    [PointerType] [IntegerType 64]

-- | Lower positional record construction: @Person "Alice" 30@.
-- All field values are f64 (boxed under the uniform ABI), stored in
-- consecutive linear-memory slots.
lowerPositionalRecord :: Text -> [(Text, MLIRType)] -> [Expr Resolved] -> LowerM Value
lowerPositionalRecord _conName fields argExprs = do
  let n = length fields
  recPtr <- allocSlots n
  forM_ (zip [0..] argExprs) $ \(idx, argExpr) -> do
    argVal <- lowerExpr argExpr l4NumberType
    storeSlot recPtr idx argVal
  pure recPtr

-- | Lower @Record WITH field IS value, ...@ construction. Fields may
-- appear in any order; we dispatch to the declaration-order slot
-- using the registered record layout.
lowerRecordConstruction :: Resolved -> [NamedExpr Resolved] -> MLIRType -> LowerM Value
lowerRecordConstruction con namedArgs _expectedTy = do
  env <- gets (.typeEnv)
  let conName = resolvedName con
      fieldMap = case lookupRecordFields conName env of
        Just fs -> Map.fromList (zip (map fst fs) [0 :: Int ..])
        Nothing -> Map.empty
      n = case lookupRecordFields conName env of
        Just fs -> length fs
        Nothing -> length namedArgs
  recPtr <- allocSlots n
  forM_ namedArgs $ \(MkNamedExpr _ fieldN fieldExpr) -> do
    let fieldName = resolvedName fieldN
        idx = Map.findWithDefault 0 fieldName fieldMap
    fieldVal <- lowerExpr fieldExpr l4NumberType
    storeSlot recPtr idx fieldVal
  pure recPtr

-- | Lower a record field projection (@record's \`field name\`@).
-- Under the uniform f64 ABI: the record is an f64-boxed pointer; we
-- compute the slot index from the declared layout and load the f64
-- directly.
lowerProjection :: Expr Resolved -> Resolved -> MLIRType -> LowerM Value
lowerProjection record field _expectedTy = do
  env <- gets (.typeEnv)
  let fieldName = resolvedName field
      (_, fieldIdx) = findFieldInEnv fieldName env
  recordVal <- lowerExpr record l4NumberType
  -- M5 slice 4E — when emitting `<fn>$trace`, mark this field
  -- forced. The marker carries the record's wasm pointer (recordVal
  -- itself, f64-boxed) so the runtime resolves it back to the
  -- exact JS object the marshaler registered — no path strings, no
  -- helper-call translation needed.
  tracingNow <- gets (.tracing)
  when tracingNow $ emitMarkForcedValue recordVal fieldName
  loadSlot recordVal fieldIdx

-- | Emit @__l4_mark_forced(recordValue, fieldNamePtr)@. The
-- @recordValue@ is the f64-boxed wasm pointer of the record being
-- projected into; the runtime looks it up in `valueByPtr` to find
-- the originating JS object and attaches `.__forced.add(field)`.
emitMarkForcedValue :: Value -> Text -> LowerM ()
emitMarkForcedValue recordVal fieldTxt = do
  fieldGlobal <- internString fieldTxt
  fieldPtr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
    [NamedAttribute "global_name" (FlatSymbolRefAttr fieldGlobal)]
    [PointerType] []
  fieldPtrF <- ptrToF64 fieldPtr
  emit $ funcCall [] "__l4_mark_forced" [recordVal, fieldPtrF]
    [l4NumberType, l4NumberType] []

-- | Find which record contains a field and return the struct type + index.
-- Falls back to an anonymous single-field struct if the field can't be
-- located (e.g., field defined in a not-yet-registered imported module).
findFieldInEnv :: Text -> TypeEnv -> (MLIRType, Int)
findFieldInEnv fieldName env =
  case [ (StructType rname (map snd fields), idx)
       | (rname, fields) <- Map.toList env.records
       , (idx, (fname, _)) <- zip [0..] fields
       , fname == fieldName
       ] of
    ((ty, idx) : _) -> (ty, idx)
    [] -> (StructType "l4.unknown" [l4NumberType], 0)

-- | Lower a list literal @[a, b, c]@.
-- Empty list is f64(0.0) which bitcasts to a null pointer; cons nodes
-- are 2-slot records [value, next] stored in linear memory.
lowerListLiteral :: [Expr Resolved] -> MLIRType -> LowerM Value
lowerListLiteral [] _ = nullListF64
lowerListLiteral (x : xs) _ = do
  hdVal <- lowerExpr x l4NumberType
  tlVal <- lowerListLiteral xs l4NumberType
  lowerListConsTy l4NumberType hdVal tlVal

-- | Construct a list cons node: a 2-slot record @[value, next]@.
-- The @elemTy@ parameter is kept for call-site API compatibility but
-- is always f64 under the uniform ABI.
lowerListConsTy :: MLIRType -> Value -> Value -> LowerM Value
lowerListConsTy _elemTy hd tl = do
  node <- allocSlots 2
  storeSlot node 0 hd
  storeSlot node 1 tl
  pure node

-- | The empty-list sentinel: f64(0.0), which bitcasts to a null pointer.
nullListF64 :: LowerM Value
nullListF64 = emitVal $ \vid -> arithConstantFloat vid 0.0


-- | Lower a local declaration (WHERE clause).
-- | L4 local scopes ('WHERE', 'LET IN') are lowered identically: a
-- zero-arg binding is evaluated inline; a multi-arg helper is
-- lambda-lifted to a top-level @func.func@ with its free variables
-- prepended as explicit parameters (closure conversion).
--
-- __Why not inline @LET IN@?__ Inlining looks appealing because 'LET'
-- typically binds a single-use value — but inlining substitutes the
-- /expression/, so if the bound expression allocates (e.g. constructs
-- a record), each use site gets a fresh allocation; pointer identity
-- is lost. It also blows up code size when a helper is called many
-- times, and loops at compile time for recursive bindings. Closure
-- conversion is the semantically-correct choice for both forms.
--
-- The 'LocalScope' tag is retained for documentation / future
-- scope-specific behaviour but both variants go through the same path
-- today.
data LocalScope = LocalScopeWhere | LocalScopeLetIn
  deriving (Eq, Show)

lowerLocalDecl :: LocalScope -> LocalDecl Resolved -> LowerM ()
lowerLocalDecl _scope (LocalDecide _anno decide@(MkDecide dAnno ts appForm body)) = do
  let name = resolvedName (appFormHead' appForm)
      params = appFormParams appForm
  -- Detect zero-arg WHERE/LET bindings whose body recursively reaches
  -- back into something that calls this binding (directly or via the
  -- enclosing function). Eager evaluation of such a binding would
  -- compile a non-terminating call chain — IF/ELSE never gets to short-
  -- circuit because the binding body runs at scope entry. We lambda-
  -- lift these to a zero-arg helper with closure-converted captures so
  -- the body only fires at use sites that the surrounding control flow
  -- actually demands.
  --
  -- "Self-referential" here means either the binding refers to itself
  -- or it calls a function whose definition is still being lowered
  -- (i.e. it's in 'pendingDecide' — the enclosing DECIDE chain).
  pendingNames <- gets (.pendingDecide)
  let bodyFree = freeVarsOfExpr body Set.empty
      isSelfRef = name `Set.member` bodyFree
      isMutualRec = any (`Set.member` bodyFree) pendingNames
      shouldLift = isSelfRef || isMutualRec
  case params of
    [] | shouldLift -> do
      funcN <- localSymbolFor (appFormHead' appForm)
      knownTopLevels <- gets (Set.fromList . Map.keys . (.funcSigs))
      currentBindings <- gets (Map.keysSet . (.bindings))
      l4TyMap <- gets (.bindingL4Types)
      let freeInBody = freeVarsOfExpr body
            (knownTopLevels <> Set.singleton name)
          captured = [v | v <- Set.toList freeInBody, v `Set.member` currentBindings]
          headRes = appFormHead' appForm
          mkParam c = MkOptionallyTypedName emptyAnno
                        (renameResolved c headRes)
                        (Map.lookup c l4TyMap)
                        Nothing
          extraParams = case givenSigParams ts of
            (template:_) -> [synthParam c template | c <- captured]
            -- Zero-arg WHERE/LET bindings have no GIVEN clause, so we
            -- can't clone an existing param as the template. Synthesise
            -- one per capture using the outer-scope L4 type we recorded
            -- in 'bindingL4Types' (falls back to untyped, which
            -- 'lowerDecide' coerces to the uniform f64 ABI).
            []           -> [mkParam c | c <- captured]
          newAppForm = extendAppFormWith captured appForm
          newTs = extendTypeSigWith extraParams ts
      modify' $ \s -> s
        { localCaptures = Map.insert funcN captured s.localCaptures
        }
      lowerDecide (MkDecide dAnno newTs newAppForm body)
    [] -> do
      -- Zero-arg binding — evaluate once and bind the value.
      -- M5 — in trace mode, wrap the rhs evaluation with a
      -- binding-wrapper trace node so the resulting Reasoning matches
      -- jl4-core's @labelExample (Just resolved)@ output. The wrapper
      -- node was allocated by 'Schema.collectTraceNodes' keyed off
      -- the Decide's range; we look it up here and bracket
      -- @lowerExpr body@ with @__l4_trace_enter(id)@ /
      -- @__l4_trace_exit(value, kind)@.
      bodyTy <- inferExprTypeM body
      tracingNow <- gets (.tracing)
      tnMap <- gets (.traceNodeMap)
      let mWrapperEntry = case rangeOf decide of
            Just rng -> Map.lookup (rng, Nothing) tnMap
            Nothing  -> Nothing
      case (tracingNow, mWrapperEntry) of
        (True, Just (wrapperId, wrapperKind)) -> do
          emitTraceEnter wrapperId
          val <- lowerExpr body bodyTy
          boxedVal <- boxABI bodyTy val
          emitTraceExit boxedVal wrapperKind
          bindTy name val bodyTy
        _ -> do
          val <- lowerExpr body bodyTy
          bindTy name val bodyTy
    _ -> do
      funcN <- localSymbolFor (appFormHead' appForm)
      let paramSet = Set.fromList (map resolvedName params)
      knownTopLevels <- gets (Set.fromList . Map.keys . (.funcSigs))
      currentBindings <- gets (Map.keysSet . (.bindings))
      let freeInBody = freeVarsOfExpr body
            (paramSet <> knownTopLevels <> Set.singleton name)
          captured = [v | v <- Set.toList freeInBody, v `Set.member` currentBindings]
          extraParams = case givenSigParams ts of
            (template:_) -> [synthParam c template | c <- captured]
            []           -> []
          newAppForm = extendAppFormWith captured appForm
          newTs = extendTypeSigWith extraParams ts

      modify' $ \s -> s
        { localCaptures = Map.insert funcN captured s.localCaptures
        }
      lowerDecide (MkDecide dAnno newTs newAppForm body)
lowerLocalDecl _ (LocalAssume _ _) = pure ()

-- | Collect names referenced as values in an expression, minus a
-- known-bound set. Used by 'lowerLocalDecl' for free-variable analysis.
freeVarsOfExpr :: Expr Resolved -> Set.Set Text -> Set.Set Text
freeVarsOfExpr expr0 bound0 = go bound0 expr0
  where
    go bound = \case
      App _ n [] ->
        let nm = resolvedName n
        in if nm `Set.member` bound
             then Set.empty
             else Set.singleton nm
      App _ n args ->
        let nm = resolvedName n
            self = if nm `Set.member` bound
                     then Set.empty
                     else Set.singleton nm
        in Set.unions (self : map (go bound) args)
      AppNamed _ _ named _ ->
        Set.unions [go bound e | MkNamedExpr _ _ e <- named]
      And _ a b        -> Set.union (go bound a) (go bound b)
      Or _ a b         -> Set.union (go bound a) (go bound b)
      RAnd _ a b       -> Set.union (go bound a) (go bound b)
      ROr _ a b        -> Set.union (go bound a) (go bound b)
      Implies _ a b    -> Set.union (go bound a) (go bound b)
      Equals _ a b     -> Set.union (go bound a) (go bound b)
      Not _ a          -> go bound a
      Plus _ a b       -> Set.union (go bound a) (go bound b)
      Minus _ a b      -> Set.union (go bound a) (go bound b)
      Times _ a b      -> Set.union (go bound a) (go bound b)
      DividedBy _ a b  -> Set.union (go bound a) (go bound b)
      Modulo _ a b     -> Set.union (go bound a) (go bound b)
      Cons _ a b       -> Set.union (go bound a) (go bound b)
      Leq _ a b        -> Set.union (go bound a) (go bound b)
      Geq _ a b        -> Set.union (go bound a) (go bound b)
      Lt _ a b         -> Set.union (go bound a) (go bound b)
      Gt _ a b         -> Set.union (go bound a) (go bound b)
      Proj _ r _       -> go bound r
      IfThenElse _ c t e -> Set.unions [go bound c, go bound t, go bound e]
      MultiWayIf _ guards e -> Set.unions (go bound e : [Set.union (go bound g) (go bound b) | MkGuardedExpr _ g b <- guards])
      Consider _ s branches ->
        Set.union (go bound s) $ Set.unions
          [ go (bound <> patternBinds p) b | MkBranch _ (When _ p) b <- branches ]
          <> Set.unions [ go bound b | MkBranch _ (Otherwise _) b <- branches ]
      Where _ b locals ->
        let (newBound, localFrees) = foldl stepLocal (bound, Set.empty) locals
        in Set.union (go newBound b) localFrees
      LetIn _ locals b ->
        let (newBound, localFrees) = foldl stepLocal (bound, Set.empty) locals
        in Set.union (go newBound b) localFrees
      Percent _ a   -> go bound a
      List _ xs     -> Set.unions (map (go bound) xs)
      Concat _ xs   -> Set.unions (map (go bound) xs)
      AsString _ a  -> go bound a
      Lam _ (MkGivenSig _ lamParams) b ->
        go (bound <> Set.fromList [resolvedName p | MkOptionallyTypedName _ p _ _ <- lamParams]) b
      Lit{} -> Set.empty
      Inert{} -> Set.empty
      Regulative{} -> Set.empty
      Event{} -> Set.empty
      Fetch _ a -> go bound a
      Env _ a -> go bound a
      Post _ a b c -> Set.unions [go bound a, go bound b, go bound c]
      Record _ mParty cell val _ mHence -> Set.unions ([go bound cell, go bound val] <> maybe [] (\p -> [go bound p]) mParty <> maybe [] (\k -> [go bound k]) mHence)
      ReadCell _ mParty _ _ cell -> Set.unions ([go bound cell] <> maybe [] (\p -> [go bound p]) mParty)
      Breach _ ma mb -> Set.unions (maybe Set.empty (go bound) ma : [maybe Set.empty (go bound) mb])

    stepLocal (bnd, frees) (LocalDecide _ (MkDecide _ _ af bdy)) =
      let nm = resolvedName (appFormHead' af)
          inner = go (bnd <> Set.fromList (map resolvedName (appFormParams af))) bdy
      in (Set.insert nm bnd, frees <> inner)
    stepLocal (bnd, frees) (LocalAssume _ (MkAssume _ _ af _ _)) =
      (Set.insert (resolvedName (appFormHead' af)) bnd, frees)

    patternBinds :: Pattern Resolved -> Set.Set Text
    patternBinds = \case
      PatVar _ n -> Set.singleton (resolvedName n)
      PatApp _ _ pats -> Set.unions (map patternBinds pats)
      PatCons _ h t -> Set.union (patternBinds h) (patternBinds t)
      PatExpr _ _ -> Set.empty
      PatLit _ _ -> Set.empty

-- | Helpers for synthesising extended AppForm / TypeSig / params with
-- captured variables prepended.

givenSigParams :: TypeSig Resolved -> [OptionallyTypedName Resolved]
givenSigParams (MkTypeSig _ (MkGivenSig _ ps) _) = ps

synthParam :: Text -> OptionallyTypedName Resolved -> OptionallyTypedName Resolved
synthParam newName (MkOptionallyTypedName ann templateName mTy _mTypically) =
  -- Clone the template's Resolved structure but substitute the raw name.
  -- (The Resolved unique is reused; two bindings with the same unique is
  -- fine because MLIR doesn't see L4 uniques — only our sanitized names.)
  MkOptionallyTypedName ann (renameResolved newName templateName) mTy Nothing

renameResolved :: Text -> Resolved -> Resolved
renameResolved newName r = case r of
  Def u n        -> Def u (setRawName newName n)
  Ref n u o      -> Ref (setRawName newName n) u o
  OutOfScope u n -> OutOfScope u (setRawName newName n)

setRawName :: Text -> Name -> Name
setRawName t (MkName ann _) = MkName ann (NormalName t)

extendAppFormWith :: [Text] -> AppForm Resolved -> AppForm Resolved
extendAppFormWith extras (MkAppForm ann headR userParams maka) =
  let newParams = [ renameResolved t headR | t <- extras ] <> userParams
  in MkAppForm ann headR newParams maka

extendTypeSigWith :: [OptionallyTypedName Resolved] -> TypeSig Resolved -> TypeSig Resolved
extendTypeSigWith extras (MkTypeSig ann (MkGivenSig gAnn ps) mGiv) =
  MkTypeSig ann (MkGivenSig gAnn (extras <> ps)) mGiv

-- | Lower a lambda expression.
lowerLambda :: GivenSig Resolved -> Expr Resolved -> MLIRType -> LowerM Value
lowerLambda (MkGivenSig _ _params) _body _expectedTy =
  -- Lambdas aren't lowered yet (higher-order support is incomplete). Flag
  -- the enclosing function instead of silently emitting FALSE.
  markUnsupported "lambda / higher-order function not supported by the WASM backend"

-- | Lower a multi-way if (BRANCH ... WHEN guard THEN expr).
lowerMultiWayIf :: [GuardedExpr Resolved] -> Expr Resolved -> MLIRType -> LowerM Value
lowerMultiWayIf [] otherwise_ _ty = lowerExpr otherwise_ l4NumberType
lowerMultiWayIf (MkGuardedExpr _ guard_ body : rest) otherwise_ _ty = do
  condF64 <- lowerExpr guard_ l4NumberType
  condI1 <- unboxBoolI1 condF64
  (thenVal, thenOps) <- collectOps $ lowerExpr body l4NumberType
  (elseVal, elseOps) <- collectOps $ lowerMultiWayIf rest otherwise_ l4NumberType
  let thenBlock = Block 0 [] (thenOps ++ [scfYield [thenVal] [l4NumberType]])
      elseBlock = Block 0 [] (elseOps ++ [scfYield [elseVal] [l4NumberType]])
  emitVal $ \vid -> scfIf [vid] condI1 (Region [thenBlock]) (Region [elseBlock]) [l4NumberType]

-- | Lower string concatenation.
lowerConcat :: [Expr Resolved] -> LowerM Value
lowerConcat [] = do
  -- Empty string: intern the zero-length constant and box as f64 pointer.
  globalName <- internString ""
  ptr <- emitVal $ \vid -> mkOp [vid] "llvm.mlir.addressof" []
    [NamedAttribute "global_name" (FlatSymbolRefAttr globalName)]
    [PointerType] []
  ptrToF64 ptr
lowerConcat [x] = lowerExpr x l4NumberType
lowerConcat (x : xs) = do
  xVal <- lowerExpr x l4NumberType
  restVal <- lowerConcat xs
  emitVal $ \vid -> funcCall [vid] "__l4_str_concat"
    [xVal, restVal] [l4NumberType, l4NumberType] [l4NumberType]

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

resolvedName :: Resolved -> Text
resolvedName r = rawNameToText (rawName (getActual r))

appFormHead' :: AppForm Resolved -> Resolved
appFormHead' (MkAppForm _ n _ _) = n

appFormParams :: AppForm Resolved -> [Resolved]
appFormParams (MkAppForm _ _ ps _) = ps

-- | Sanitize an L4 name for use as a WASM export symbol.
--
-- Delegates to 'L4.MLIR.Schema.sanitizeWasmSymbol' so function symbol
-- names in the emitted WASM match the names recorded in the
-- accompanying @.schema.json@ exactly. See 'L4.MLIR.Schema' for the
-- full discussion of the two-layer sanitization (API name vs symbol).
sanitizeName :: Text -> Text
sanitizeName = Schema.sanitizeWasmSymbol

-- | True iff @name@ is a constructor the user DECLAREd in this bundle —
-- either a record constructor (@lookupRecordFields@) or an @ONE OF@ enum
-- variant (@lookupEnumTag@). The prelude builtins (JUST/NOTHING/LEFT/RIGHT/
-- EMPTY) are never registered in the 'TypeEnv', so this is False for them.
-- The CONSIDER lowering uses this to give user constructors priority over
-- the builtin string cases, matching the construction path's ordering and
-- so keeping construction and pattern-matching on the SAME representation
-- (a user @LEFT/RIGHT@ enum must not be read as the builtin EITHER's
-- [tag, payload] slot record — that was the ledger #10 shadow regression).
isUserConstructor :: Text -> TypeEnv -> Bool
isUserConstructor name env =
  case lookupRecordFields name env of
    Just _  -> True
    Nothing -> case lookupEnumTag name env of
      Just _  -> True
      Nothing -> False

lookupEnumTag :: Text -> TypeEnv -> Maybe Integer
lookupEnumTag name env =
  case [ tag | (_, variants) <- Map.toList env.enums
       , (vname, tag) <- variants
       , vname == name
       ] of
    (t : _) -> Just t
    [] -> Nothing
