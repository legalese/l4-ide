-- | Lower a typechecked L4 module to the Catala surface IR.
--
-- The accepted source fragment is spec §6, verbatim: @DECLARE@ records and
-- enums; first-order, non-recursive, monomorphic @GIVEN@\/@GIVETH@\/@MEANS@\/
-- @DECIDE@ functions over @BOOLEAN@\/@NUMBER@\/@DATE@\/records\/enums\/@MAYBE@\/
-- lists; @CONSIDER@\/@BRANCH@\/@IF@\/@WHERE@; prelude list combinators with
-- literal-lambda or named-function arguments; uninspected @STRING@ fields and
-- parameters under R11's elision; @ASSUME@d inputs; @\@export@\/@\@desc@\/
-- @TYPICALLY@ annotations.
--
-- Everything else — string /computation/, recursion, function-typed parameters,
-- @DEONTIC@\/@PARTY@, @#TRACE@, ledger\/effect keywords, temporal pins — is
-- rejected with a 'LowerError' naming the construct and its source range. Errors
-- are batched, not first-error-wins: the accumulating 'V' applicative below
-- collects every independent failure in one pass, and the CLI prints them the
-- way @l4 openfisca@ prints its "cannot compile these decisions" list.
--
-- Emission split (R1, §8.1): every @\@export@ decision becomes a Catala /scope/
-- whose inputs are its @GIVEN@ parameters (the subject record passed whole,
-- R1a) plus any module-level @ASSUME@ it reaches, and whose single @output@
-- carries the result; every /reachable/ non-exported helper becomes a private
-- toplevel @declaration … depends on … equals@; unreachable code is not
-- emitted at all.
--
-- Both renderings of every rule are constructed (R4, §8.4): the Mode A
-- boolean\/if-else reference rendering always, and the Mode B exception ladder
-- wherever one is derivable. Mode B is the /emitted/ rendering wherever the
-- module can also carry the machine-checked equivalence scopes §8.4's gate
-- demands ('L4.Catala.Equivalence' builds them); where it cannot — no ladder
-- shape, or more atomic conditions than the exhaustive grid's cap — the rule
-- falls back to Mode A, @rdFallback@ names the reason, and the reason is
-- written both into the artifact and onto the CLI's stderr. Fallbacks are
-- warned, never silent.
--
-- The emitted file is a literate weave (R8, §8.8): L4 @§@ headers become
-- Markdown headings, inert scaffolding and @\@ref@ citations become the law
-- text sitting immediately before the fence they annotate, and @\@desc@ becomes
-- a @#[description]@ attribute on the declaration.
module L4.Catala.Lower
  ( lowerModule
  , lowerModuleWith
  , LowerOptions (..)
  , defaultLowerOptions
  , LowerError (..)
  , renderLowerError
  ) where

import Base
import Control.Applicative ((<|>))
import Data.Ratio (denominator, numerator)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

import Optics (cosmosOf, gplate, toListOf, (^.))

import L4.Annotation (getAnno, rangeOf)
import L4.Catala.Equivalence (EqvUnit (..), equivalenceUnit)
import L4.Catala.IR
import L4.Export
  ( ExportedFunction (..), ParsedDesc (..), getExportedFunctions
  , isNonexhaustiveDecide, parseDescText )
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..), prettySrcRange)
import L4.Syntax
import qualified L4.TypeCheck.Environment as TC

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

-- | A reason a definition could not be compiled to Catala.
data LowerError = LowerError
  { errFn    :: !Text              -- ^ the offending definition (empty = module-level)
  , errRange :: !(Maybe SrcRange)  -- ^ where in the L4 source it sits
  , errMsg   :: !Text
  }
  deriving stock (Eq, Show)

renderLowerError :: LowerError -> Text
renderLowerError e = prefix <> e.errMsg <> suffix
 where
  prefix | Text.null e.errFn = ""
         | otherwise         = "in `" <> e.errFn <> "`: "
  suffix = maybe "" (\r -> " (" <> prettySrcRange r <> ")") e.errRange

-- ---------------------------------------------------------------------------
-- An accumulating applicative, so all errors are reported at once (§6)
-- ---------------------------------------------------------------------------

newtype V a = V (Either [LowerError] a)
  deriving stock (Functor)

instance Applicative V where
  pure = V . Right
  V a <*> V b = V $ case (a, b) of
    (Left e1, Left e2) -> Left (e1 <> e2)
    (Left e1, _)       -> Left e1
    (_, Left e2)       -> Left e2
    (Right f, Right x) -> Right (f x)

runV :: V a -> Either [LowerError] a
runV (V e) = e

-- | Sequential composition, for the places where the second step needs the
-- first step's value. Short-circuits, as it must.
vThen :: V a -> (a -> V b) -> V b
vThen (V (Left e))  _ = V (Left e)
vThen (V (Right a)) f = f a

vBad :: [LowerError] -> V a
vBad = V . Left

vErr :: Maybe SrcRange -> Text -> V a
vErr r m = vBad [LowerError "" r m]

-- | Re-attribute every otherwise-anonymous error in a subtree to a definition.
vIn :: Text -> V a -> V a
vIn fn (V (Left es)) =
  V (Left [ e { errFn = if Text.null e.errFn then fn else e.errFn } | e <- es ])
vIn _ ok = ok

-- | Run several independent lowerings, keeping every error.
vList :: [V a] -> V [a]
vList = sequenceA

-- ---------------------------------------------------------------------------
-- What the module scan finds
-- ---------------------------------------------------------------------------

-- | A field's fate in the emitted structure.
data FieldStatus
  = FEmitted !CatType
  | FElidedString            -- ^ R11: a @STRING@ that nothing inspects
  | FElidedComputed          -- ^ a @MEANS@ field: Catala structures carry data only
  | FUnsupported !Text       -- ^ a type with no Catala counterpart at all
  deriving stock (Eq, Show)

data RecField = RecField
  { rfName   :: !Text
  , rfL4     :: !Text
  , rfUnique :: !Unique
  , rfStatus :: !FieldStatus
  , rfDesc   :: !(Maybe Text)
  }

data RecordInfo = RecordInfo
  { riName   :: !Text
  , riL4     :: !Text
  , riDesc   :: !(Maybe Text)
  , riFields :: ![RecField]
  }

data ConInfo = ConInfo
  { ciEnum    :: !Text          -- ^ the enumeration this constructor belongs to
  , ciCase    :: !Text          -- ^ mangled constructor name
  , ciL4      :: !Text
  , ciPayload :: !Bool
  }

data DecideInfo = DecideInfo
  { diUnique  :: !Unique
  , diName    :: !Text
  , diGivens  :: ![OptionallyTypedName Resolved]
  , diAppArgs :: ![Resolved]
  , diGiveth  :: !(Maybe (Type' Resolved))
  , diBody    :: !(Expr Resolved)
  , diNonexh  :: !Bool
  , diDesc    :: !(Maybe Text)
  , diRef     :: !(Maybe Text)
  , diRange   :: !(Maybe SrcRange)
  }

data AssumeInfo = AssumeInfo
  { aiName  :: !Text        -- ^ mangled Catala input-variable name
  , aiL4    :: !Text
  , aiType  :: !(Maybe (Type' Resolved))
  , aiRange :: !(Maybe SrcRange)
  }

-- | An exported decision's Catala calling convention.
data ScopeSig = ScopeSig
  { ssScope   :: !Text
  , ssL4      :: !Text          -- ^ the L4 name, so a mangling clash can name both sides
  , ssParams  :: ![(Text, Bool)]  -- ^ per @GIVEN@, in order: name, and whether it survives (R11)
  , ssAssumes :: ![Text]          -- ^ extra @input@s from module-level @ASSUME@s, in order
  , ssOutput  :: !Text
  }

-- | A private toplevel helper's calling convention.
data HelperSig = HelperSig
  { hsName   :: !Text
  , hsL4     :: !Text
  , hsParams :: ![(Text, Bool)]
  }

-- ---------------------------------------------------------------------------
-- The lowering context
-- ---------------------------------------------------------------------------

data Ctx = Ctx
  { cxVars     :: !(Map Unique Text)          -- ^ in-scope values (inputs, binders, lets)
  , cxCons     :: !(Map Unique ConInfo)
  , cxCases    :: !(Map Text [Text])          -- ^ enumeration → its constructors, in order
  , cxTypes    :: !(Map Unique Text)          -- ^ every type declared in this module
  , cxRecords  :: !(Map Unique RecordInfo)    -- ^ keyed by the type's /and/ the constructor's unique
  , cxFields   :: !(Map Unique RecField)
  , cxScopes   :: !(Map Unique ScopeSig)
  , cxHelpers  :: !(Map Unique HelperSig)
  , cxAssumes  :: !(Map Unique AssumeInfo)
  , cxAssumeOK :: !Bool                       -- ^ may this body read an @ASSUME@? (scopes yes)
  , cxElided   :: !(Map Unique Text)          -- ^ elided string values → why
  , cxDecides  :: !(Map Unique DecideInfo)
  , cxNonexh   :: !Bool                       -- ^ the enclosing decision carries @\@nonexhaustive@
  , cxBoolOnly :: !Bool                       -- ^ @--boolean-only@: never emit a ladder (§8.4)
  }

-- | The name Catala's @optional of@ enumeration answers to in 'cxCases'.
maybeEnum :: Text
maybeEnum = "#optional"

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- | Knobs the CLI exposes.
newtype LowerOptions = LowerOptions
  { loBooleanOnly :: Bool
    -- ^ §8.4's escape flag: emit only the Mode A boolean rendering, and with it
    -- no exception ladders and none of the equivalence apparatus that exists to
    -- check them. The ladders are still /derived/ (so the fallback notes stay
    -- accurate); they are simply not what the artifact says.
  }
  deriving stock (Eq, Show)

defaultLowerOptions :: LowerOptions
defaultLowerOptions = LowerOptions { loBooleanOnly = False }

lowerModule :: Module Resolved -> Either [LowerError] CatModule
lowerModule = lowerModuleWith defaultLowerOptions

lowerModuleWith :: LowerOptions -> Module Resolved -> Either [LowerError] CatModule
lowerModuleWith opts mod' = case getExportedFunctions mod' of
  []  -> Left [LowerError "" Nothing "no @export-annotated DECIDE found to compile to Catala"]
  efs -> runV (buildModule opts mod' efs)

buildModule :: LowerOptions -> Module Resolved -> [ExportedFunction] -> V CatModule
buildModule opts mod' efs =
  recursionErrors decides reach *> (collectEnums mod' `vThen` assemble)
 where
  decides   = collectDecides mod'
  assumes   = collectAssumes mod'
  typeNames = collectTypeNames mod'
  records   = collectRecords mod'
  fieldMap  = Map.fromList
    [ (f.rfUnique, f) | ri <- dedupOn (.riL4) (Map.elems records), f <- ri.riFields ]
  consMap   = enumConstructors mod'
  exportUs  = [ getUnique (decideName ef.exportDecide) | ef <- efs ]

  -- R1: only what an @export decision reaches is emitted at all.
  reach    = reachableFrom decides exportUs
  helpers  = mapMaybe (`Map.lookup` decides) [ u | u <- reach, u `notElem` exportUs ]

  -- R11: string-shaped parameters and ASSUMEs are elided, with a per-site note.
  elided = Map.fromList $
       [ (getUnique (givenName g), elisionNote di.diName (givenText g))
       | u <- reach, di <- maybeToList (Map.lookup u decides)
       , g <- di.diGivens, Just t <- [givenType g], isStringType t ]
    <> [ (u, "module-level ASSUME `" <> ai.aiL4
            <> "` is a STRING; elided from every scope input (R11)")
       | (u, ai) <- Map.toList assumes, Just t <- [ai.aiType], isStringType t ]

  -- Signatures must exist before any body is lowered: a cross-decision call
  -- renders as `(output of S with { … }).v` and needs the callee's input names.
  assumeUse = assumeClosure decides assumes elided exportUs
  sigs = Map.fromList
    [ ( eu
      , ScopeSig
          { ssScope   = catUpper ef.exportName
          , ssL4      = ef.exportName
          , ssParams  = paramsOf elided (Map.lookup eu decides)
          , ssAssumes = [ ai.aiName
                        | au <- Map.findWithDefault [] eu assumeUse
                        , ai <- maybeToList (Map.lookup au assumes) ]
          , ssOutput  = catIdent ef.exportName
          } )
    | ef <- efs, let eu = getUnique (decideName ef.exportDecide)
    ]
  hsigs = Map.fromList
    [ (di.diUnique, HelperSig (catIdent di.diName) di.diName (paramsOf elided (Just di)))
    | di <- helpers
    ]

  structs =
    [ CatStruct
        { stName   = ri.riName
        , stL4     = ri.riL4
        , stDesc   = ri.riDesc
        , stFields = [ CatField f.rfName f.rfL4 t f.rfDesc
                     | f <- ri.riFields, FEmitted t <- [f.rfStatus] ]
        }
    | ri <- dedupOn (.riL4) (Map.elems records)
    ]

  -- R11 and its neighbours: every field that does not survive into the emitted
  -- structure is named, so the shape divergence is disclosed rather than silent.
  fieldNotes =
    [ "field `" <> f.rfL4 <> "` of `" <> ri.riL4 <> "` " <> why
    | ri <- dedupOn (.riL4) (Map.elems records), f <- ri.riFields
    , why <- case f.rfStatus of
        FEmitted _      -> []
        FElidedString   -> ["is a STRING; Catala has no string type, so it is elided from the \
                            \emitted structure (R11). Reading it is an error."]
        FElidedComputed -> ["is a computed (MEANS) field; Catala structures carry data only, so it \
                            \is not emitted."]
        FUnsupported m  -> ["was not emitted: " <> m]
    ]

  sectionPaths = Map.fromList
    [ (getUnique fnRes, path)
    | (path, Decide _ (MkDecide _ _ (MkAppForm _ fnRes _ _) _)) <- topDeclsWithPath mod'
    ]

  assemble enums =
    let ctx = Ctx
          { cxVars     = Map.empty
          , cxCons     = consMap
          , cxCases    = Map.fromList [ (e.enName, map (.caName) e.enCases) | e <- enums ]
                           <> Map.singleton maybeEnum ["Present", "Absent"]
          , cxTypes    = typeNames
          , cxRecords  = records
          , cxFields   = fieldMap
          , cxScopes   = sigs
          , cxHelpers  = hsigs
          , cxAssumes  = assumes
          , cxAssumeOK = False
          , cxElided   = elided
          , cxDecides  = decides
          , cxNonexh   = False
          , cxBoolOnly = opts.loBooleanOnly
          }
        modTitle = catUpper (dropExt (moduleSource mod'))
    in (\lowered tops ->
          let (tests, testNotes) = collectTests ctx decides mod'
              eqvs               = concatMap eqvUnitsOf lowered
              notes = nub (  fieldNotes
                          <> Map.elems elided
                          <> concatMap (.lsNotes) lowered
                          <> testNotes )
          in CatModule
               { modName     = modTitle
               , modSource   = moduleSource mod'
               , modWarnings = notes
               , modSegments = weave modTitle (moduleSource mod') notes structs enums
                                     tops lowered eqvs tests
               })
       <$> vList [ lowerExport ctx assumes assumeUse decides sectionPaths ef | ef <- efs ]
       <*> vList [ lowerHelper ctx di | di <- helpers ]
       <*  collisionCheck structs enums sigs hsigs generatedNames

  -- The names the equivalence harness (R4) and the test emitter (R7) will claim.
  -- They are predictable from the export list, so they can join the collision
  -- check before anything is lowered.
  generatedNames =
       [ ( catUpper ef.exportName <> "Eqv" <> sfx
         , "<generated equivalence scope for `" <> ef.exportName <> "`>" )
       | ef <- efs, sfx <- ["Row", "ModeA", "ModeB", "Agree", "Grid"] ]
    <> [ ("Test" <> tshow i, "<generated #EVAL test scope " <> tshow i <> ">")
       | i <- [1 .. length [ () | Directive _ _ <- topDecls mod' ]] ]

elisionNote :: Text -> Text -> Text
elisionNote fn p =
  "parameter `" <> p <> "` of `" <> fn <> "` is a STRING; Catala has no string type, so it is "
  <> "elided from the emitted signature (R11). Any use of its value is an error."

paramsOf :: Map Unique Text -> Maybe DecideInfo -> [(Text, Bool)]
paramsOf elided = \case
  Nothing -> []
  Just di ->
    [ (catIdent (givenText g), not (Map.member (getUnique (givenName g)) elided))
    | g <- di.diGivens
    ]

-- ---------------------------------------------------------------------------
-- The literate weave (R8, §8.8)
-- ---------------------------------------------------------------------------

-- | Lay the emitted module out as a literate document.
--
-- One @catala-metadata@ fence carries every public declaration (Catala resolves
-- declarations and definitions independently of file order, checked against the
-- real toolchain), and the rest of the file alternates law text with the code
-- it governs: a decision's @§@ section becomes a Markdown heading, its inert
-- scaffolding and @\@ref@ citation become the prose immediately above its
-- fence, and each Mode B rewrite's equivalence apparatus follows the rule it
-- checks.
weave
  :: Text -> Text -> [Text]
  -> [CatStruct] -> [CatEnum] -> [CatTopdef]
  -> [LoweredScope] -> [(Text, EqvUnit)] -> [TestUnit]
  -> [CatSegment]
weave title source notes structs enums tops lowered eqvs tests =
     [ SegProse header ]
  <> [ SegProse noteBlock | not (null notes) ]
  <> [ SegMetadata metadata ]
  <> [ SegCode (map (ItemDecl . DTopdef) tops) | not (null tops) ]
  <> concat (snd (mapAccumL scopeSegments [] lowered))
  <> testSegments
 where
  header =
    [ "# " <> title
    , ""
    , "Generated by `l4 catala` from `" <> source <> "`."
    , "Do not edit by hand; regenerate from the L4 source instead."
    ]

  noteBlock =
    "Notes from the lowering — divergences between this artifact and its L4 source"
    : "are disclosed here rather than left to be discovered (R10, R11, §8.4):"
    : ""
    : [ "- " <> n | n <- notes ]

  metadata =
       map DStruct structs
    <> map DEnum enums
    <> [ DScope ls.lsDecl | ls <- lowered ]
    <> concat [ eu.euDecls | (_, eu) <- eqvs ]
    <> [ DScope t.tuDecl | t <- tests ]

  -- Emit a heading for each newly entered § level, then the decision itself.
  scopeSegments prev ls =
    let shared    = length (takeWhile id (zipWith (==) prev ls.lsPath))
        newHeads  = [ heading (i + 2) s
                    | (i, s) <- drop shared (zip [0 :: Int ..] ls.lsPath) ]
        lvl = length ls.lsPath + 2
        body =
             [ SegProse (trimTrailingBlanks
                          (  heading lvl ("`" <> ls.lsL4 <> "`")
                          <> [ "" ]
                          <> maybe [] (\d -> [d]) ls.lsDesc
                          <> ls.lsLaw ))
             , SegCode [ItemScope ls.lsBody]
             ]
        eqvBlocks = concat
          [ [ SegProse eu.euProse, SegCode eu.euItems, SegTestCli eu.euTest ]
          | (owner, eu) <- eqvs, owner == ls.lsBody.sbName
          ]
    in (ls.lsPath, [ SegProse h | h <- newHeads ] <> body <> eqvBlocks)

  heading n t = [ Text.replicate n "#" <> " " <> t ]

  trimTrailingBlanks = reverse . dropWhile Text.null . reverse

  testSegments
    | null tests = []
    | otherwise =
           [ SegProse
               [ "## Tests"
               , ""
               , "One scope per `#EVAL` / `#ASSERT` directive in the L4 source, with the"
               , "arguments the directive supplied. The expected values below were computed"
               , "by L4's own evaluator, so `clerk test` compares the two languages rather"
               , "than comparing Catala with itself (R7, §8.7)."
               ] ]
        <> concat [ [ SegCode [ItemScope t.tuBody], SegTestCli t.tuCli ] | t <- tests ]

-- | The law text that annotates a decision: its inert scaffolding, in source
-- order, followed by its @\@ref@ citation.
lawText :: DecideInfo -> [Text]
lawText di = case body <> citation of
  [] -> []
  ls -> ls
 where
  body = case inertTexts di.diBody of
    [] -> []
    ts -> "" : ts <> [""]
  citation = case di.diRef of
    Nothing -> []
    Just r  -> ["", "*Source: " <> r <> ".*"]

-- | Inert scaffolding, in source order. @Inert@ nodes carry the verbatim
-- statute text an isomorphic L4 encoding keeps beside its logic; the Catala
-- weave is where that text belongs on the far side (§4.9).
inertTexts :: Expr Resolved -> [Text]
inertTexts e =
  [ t
  | (_, t) <- sortOn fst
      [ (rangeStart (rangeOf x), Text.strip txt)
      | x <- toListOf (cosmosOf (gplate @(Expr Resolved))) e
      , Inert _ txt _ <- [x]
      , not (Text.null (Text.strip txt))
      ]
  ]
 where
  rangeStart :: Maybe SrcRange -> Maybe (Int, Int)
  rangeStart = fmap (\r -> (r.start.line, r.start.column))

-- ---------------------------------------------------------------------------
-- The equivalence apparatus (R4, §8.4)
-- ---------------------------------------------------------------------------

-- | Every Mode B rewrite in one scope, paired with the scope that owns it.
eqvUnitsOf :: LoweredScope -> [(Text, EqvUnit)]
eqvUnitsOf ls =
  [ (ls.lsBody.sbName, eu)
  | (i, rd) <- zip [0 :: Int ..] ls.lsBody.sbRules
  , Just eqv <- [rd.rdEqv]
  , eu <- maybeToList (equivalenceUnit (base i) (human i) eqv)
  ]
 where
  base i  = ls.lsBody.sbName <> "Eqv" <> (if i == 0 then "" else tshow i)
  human i = ls.lsL4 <> (if i == 0 then "" else " / " <> ruleVar i)
  ruleVar i = maybe "" (.rdVar) (listToMaybe (drop i ls.lsBody.sbRules))

-- ---------------------------------------------------------------------------
-- Tests (R7, §8.7)
-- ---------------------------------------------------------------------------

-- | One @#[test]@ scope wrapping one L4 directive.
data TestUnit = TestUnit
  { tuDecl :: !CatScopeDecl
  , tuBody :: !CatScopeBody
  , tuCli  :: !CatTestCli
  }

-- | Turn each @#EVAL@ / @#ASSERT@ over an exported decision into a @#[test]@
-- scope with the directive's literal arguments.
--
-- A directive that does not lower — one that reads an @ASSUME@d input, or whose
-- head is not a decision this module exports — is skipped with a note rather
-- than failing the emission: a module's testability is not a precondition for
-- its compilation.
collectTests :: Ctx -> Map Unique DecideInfo -> Module Resolved -> ([TestUnit], [Text])
collectTests ctx decides mod' = go (1 :: Int) [ d | Directive _ d <- topDecls mod' ] [] []
 where
  go _ [] us ns = (reverse us, reverse ns)
  go i (d : ds) us ns = case plan i d of
    Right u        -> go (i + 1) ds (u : us) ns
    Left Nothing   -> go i ds us ns
    Left (Just n)  -> go i ds us (n : ns)

  plan i d = case d of
    LazyEval ann e      -> build i (rangeOf ann) e (resultType e)
    LazyEvalTrace ann e -> build i (rangeOf ann) e (resultType e)
    Assert ann e        -> build i (rangeOf ann) e (Just TBool)
    Check {}            -> Left Nothing
    Contract {}         -> Left (Just contractNote)

  contractNote =
    "a `#TRACE`/contract directive has no Catala counterpart (Catala models no deontic layer, \
    \§5.1), so no test scope was emitted for it"

  build i rng e mty = case mty of
    Nothing -> Left (Just (skipNote i "its result type could not be determined — a test scope \
                                      \wraps a call to an @export decision (§8.7)"))
    Just ty -> case runV (lowerExpr ctx e) of
      Left errs -> Left (Just (skipNote i (Text.intercalate "; " [ x.errMsg | x <- errs ])))
      Right ce  -> Right TestUnit
        { tuDecl = CatScopeDecl
            { sdName   = name
            , sdL4     = name
            , sdDesc   = Just ("Test " <> tshow i <> ", from the L4 directive at "
                               <> maybe "an unknown position" prettySrcRange rng <> ".")
            , sdIsTest = True
            , sdVars   = [ CatScopeVar "result" "result" VarOutput (ShContent ty) Nothing ]
            }
        , tuBody = CatScopeBody name
            [ CatRuleDef
                { rdVar = "result"
                , rdModeA = [CatClause ClPlain Nothing (ConsEquals ce)]
                , rdModeB = Nothing, rdEmitted = ModeA
                , rdFallback = Nothing, rdEqv = Nothing
                } ]
        -- See 'L4.Catala.Equivalence' for why @--disable-warnings@ is here.
        , tuCli = CatTestCli ("catala test-scope " <> name <> " --disable-warnings -F json") [] rng
        }
     where
      name = "Test" <> tshow i

  skipNote i why =
    "directive " <> tshow i <> " did not become a Catala `#[test]` scope: " <> why

  -- The declared result type of the decision the directive calls. Everything
  -- else is out of R7's shape ("the test scope wraps the scope under test").
  resultType e = do
    r <- case e of
      App _ r' _        -> Just r'
      AppNamed _ r' _ _ -> Just r'
      _                 -> Nothing
    di <- Map.lookup (getUnique r) decides
    t  <- di.diGiveth
    case runV (lowerType ctx di.diRange t) of
      Right ty -> Just ty
      Left _   -> Nothing

-- ---------------------------------------------------------------------------
-- Reachability, recursion (R6), and ASSUME propagation
-- ---------------------------------------------------------------------------

-- | Every 'Resolved' occurring anywhere in a decision's body, its @WHERE@
-- bindings included: @Expr@ is 'Foldable' over its name parameter, so this
-- over-approximates the reference set, which is exactly what a call graph wants.
bodyRefs :: DecideInfo -> Set Unique
bodyRefs di = Set.fromList (map getUnique (toList di.diBody))

reachableFrom :: Map Unique DecideInfo -> [Unique] -> [Unique]
reachableFrom decides = go []
 where
  go acc [] = reverse acc
  go acc (u : us)
    | u `elem` acc = go acc us
    | otherwise    =
        let next = case Map.lookup u decides of
              Nothing -> []
              Just di -> [ v | v <- Set.toList (bodyRefs di), Map.member v decides ]
        in go (u : acc) (us <> next)

-- | R6: reject every cycle in the reachable call graph, naming it.
recursionErrors :: Map Unique DecideInfo -> [Unique] -> V ()
recursionErrors decides reach = case cycles of
  [] -> pure ()
  cs -> vBad
    [ LowerError (nameOf h) (Map.lookup h decides >>= (.diRange))
        ( "recursion has no Catala counterpart (R6, §8.6): "
        <> Text.intercalate " → " (map nameOf (c <> [h]))
        <> ". Rewrite it with a list combinator (`sum`, `all`, `any`, `foldl`, …)." )
    | c <- cs, h <- take 1 c
    ]
 where
  nameOf u = maybe "?" (.diName) (Map.lookup u decides)
  succs u = case Map.lookup u decides of
    Nothing -> []
    Just di -> [ v | v <- Set.toList (bodyRefs di), v `elem` reach ]
  cycles = dedupOn Set.fromList (mapMaybe (findCycle []) reach)
  findCycle path u
    | u `elem` path = Just (dropWhile (/= u) (reverse path))
    | otherwise     = listToMaybe (mapMaybe (findCycle (u : path)) (succs u))

-- | Which module-level @ASSUME@s each exported decision needs as scope inputs:
-- its own, plus (transitively) those of every exported decision it calls,
-- because the call site is what has to supply them.
assumeClosure
  :: Map Unique DecideInfo -> Map Unique AssumeInfo -> Map Unique Text -> [Unique]
  -> Map Unique [Unique]
assumeClosure decides assumes elided exportUs = fixpoint initial
 where
  live = [ u | u <- Map.keys assumes, not (Map.member u elided) ]
  refsOf u = maybe Set.empty bodyRefs (Map.lookup u decides)
  direct u = [ a | a <- live, Set.member a (refsOf u) ]
  callees u = [ v | v <- exportUs, v /= u, Set.member v (refsOf u) ]
  initial = Map.fromList [ (u, direct u) | u <- exportUs ]
  step m = Map.fromList
    [ (u, [ a | a <- live, a `elem` reachable ])
    | u <- exportUs
    , let reachable = Map.findWithDefault [] u m
                        <> concatMap (\v -> Map.findWithDefault [] v m) (callees u)
    ]
  fixpoint m = let m' = step m in if m' == m then m else fixpoint m'

-- ---------------------------------------------------------------------------
-- Collision checking
-- ---------------------------------------------------------------------------

-- | Distinct L4 names that mangle to one Catala name would silently conflate in
-- Catala's flat namespaces; reject that, as the OpenFisca backend does. Catala
-- keeps capitalised names (structures, enumerations, scopes) in one namespace
-- and lowercase toplevels in another, and each structure's fields in their own.
collisionCheck
  :: [CatStruct] -> [CatEnum] -> Map Unique ScopeSig -> Map Unique HelperSig
  -> [(Text, Text)] -> V ()
collisionCheck structs enums sigs hsigs generated = case clashes of
  [] -> pure ()
  cs -> vBad cs
 where
  clashes =
       report "capitalised (structure / enumeration / scope)"
         (  [ (s.stName, s.stL4) | s <- structs ]
         <> [ (e.enName, e.enL4) | e <- enums ]
         <> [ (sg.ssScope, sg.ssL4) | sg <- Map.elems sigs ]
         <> generated )
    <> report "toplevel helper" [ (h.hsName, h.hsL4) | h <- Map.elems hsigs ]
    <> concat [ report ("field of structure `" <> s.stName <> "`")
                  [ (f.fdName, f.fdL4) | f <- s.stFields ]
              | s <- structs ]
  report what pairs =
    [ LowerError "" Nothing
        ( "name collision in the " <> what <> " namespace: distinct L4 definitions ("
        <> Text.intercalate ", " [ "`" <> o <> "`" | o <- origs ]
        <> ") both compile to the Catala name `" <> mangled <> "` — rename one." )
    | (mangled, origs) <- nameCollisions pairs
    ]

-- ---------------------------------------------------------------------------
-- Exported decisions → scopes (R1)
-- ---------------------------------------------------------------------------

-- | An exported decision's emitted scope, plus everything the literate weave
-- needs to place it: the L4 name, the @§@ section path it sits under, and the
-- law text that annotates it (R8).
data LoweredScope = LoweredScope
  { lsDecl  :: !CatScopeDecl
  , lsBody  :: !CatScopeBody
  , lsNotes :: ![Text]
  , lsL4    :: !Text
  , lsDesc  :: !(Maybe Text)
  , lsPath  :: ![Text]
  , lsLaw   :: ![Text]
  }

lowerExport
  :: Ctx
  -> Map Unique AssumeInfo
  -> Map Unique [Unique]
  -> Map Unique DecideInfo
  -> Map Unique [Text]
  -> ExportedFunction
  -> V LoweredScope
lowerExport ctx assumes assumeUse decides paths ef =
  case Map.lookup u decides of
    Nothing -> vBad [LowerError ef.exportName Nothing
                      "exported decision not found among this module's top-level DECIDEs"]
    Just di -> vIn di.diName (lowerExportDi ctx assumes assumeUse di ef path)
 where
  u    = getUnique (decideName ef.exportDecide)
  path = Map.findWithDefault [] u paths

lowerExportDi
  :: Ctx -> Map Unique AssumeInfo -> Map Unique [Unique] -> DecideInfo -> ExportedFunction
  -> [Text] -> V LoweredScope
lowerExportDi outer assumes assumeUse di ef path =
  vList (map checkGivenShape di.diGivens) *> retType `vThen` build
 where
  assumeUs = Map.findWithDefault [] di.diUnique assumeUse
  assumeVs = mapMaybe (`Map.lookup` assumes) assumeUs

  bodyCtx = outer
    { cxVars = Map.fromList
        (  [ (getUnique (givenName g), catIdent (givenText g))
           | g <- di.diGivens, not (Map.member (getUnique (givenName g)) outer.cxElided) ]
        <> [ (getUnique r, catIdent (givenText g))
           | (r, g) <- zip di.diAppArgs di.diGivens
           , not (Map.member (getUnique (givenName g)) outer.cxElided) ]
        <> [ (u, ai.aiName) | (u, ai) <- zip assumeUs assumeVs ] )
    , cxAssumeOK = True
    , cxNonexh   = di.diNonexh
    }

  retType = case di.diGiveth of
    Nothing -> vBad [LowerError di.diName di.diRange
                      "no GIVETH: Catala needs the declared result type of an exported decision"]
    Just t  -> lowerType outer di.diRange t

  build retTy =
    let outShape = case retTy of TBool -> ShCondition; t -> ShContent t
        outName  = catIdent di.diName
        desc     = if Text.null ef.exportDescription then di.diDesc
                     else Just ef.exportDescription
    in (\inputs assumeInputs defaults mainRule -> LoweredScope
          { lsDecl = CatScopeDecl
              { sdName   = catUpper di.diName
              , sdL4     = di.diName
              , sdDesc   = desc
              , sdIsTest = False
              , sdVars   = concat inputs <> assumeInputs <>
                  [ CatScopeVar outName di.diName VarOutput outShape Nothing ]
              }
          , lsBody  = CatScopeBody (catUpper di.diName) (catMaybes defaults <> [mainRule])
          , lsNotes = modeNotes di.diName mainRule
          , lsL4    = di.diName
          , lsDesc  = desc
          , lsPath  = path
          , lsLaw   = lawText di
          })
       <$> vList (map scopeInput di.diGivens)
       <*> vList (map assumeInput assumeVs)
       <*> vList (map typicallyDefault di.diGivens)
       <*> lowerRule bodyCtx outName outShape di.diBody

  checkGivenShape g = case givenType g of
    Nothing -> vBad [LowerError di.diName di.diRange
                      ("parameter `" <> givenText g <> "` has no declared type; "
                       <> "Catala scope inputs must be typed")]
    Just (Type {}) -> vBad [LowerError di.diName di.diRange
                             ("parameter `" <> givenText g <> "` is a TYPE parameter; polymorphic "
                              <> "decisions are not lowered in v1 — monomorphise it (§4.2)")]
    Just _ -> pure ()

  scopeInput g
    | Map.member (getUnique (givenName g)) outer.cxElided = pure []
    | otherwise = case givenType g of
        Nothing -> pure []            -- already reported by checkGivenShape
        Just t  -> (\ty -> [ CatScopeVar
                               (catIdent (givenText g)) (givenText g)
                               -- R10: a TYPICALLY default becomes a caller-overridable `context`.
                               (if isJust (givenTypically g) then VarContext else VarInput)
                               (ShContent ty) Nothing ])
                   <$> lowerType outer di.diRange t

  assumeInput ai = case ai.aiType of
    Nothing -> vBad [LowerError di.diName ai.aiRange
                      ("ASSUME `" <> ai.aiL4 <> "` has no declared type")]
    Just t  -> (\ty -> CatScopeVar ai.aiName ai.aiL4 VarInput (ShContent ty) Nothing)
               <$> lowerType outer ai.aiRange t

  -- R10: the scope defines the TYPICALLY value; the caller may override it, and
  -- Catala's default calculus gives the caller's value exception priority.
  typicallyDefault g = case givenTypically g of
    Nothing -> pure Nothing
    Just d  -> (\e -> Just CatRuleDef
                        { rdVar      = catIdent (givenText g)
                        , rdModeA    = [CatClause ClPlain Nothing (ConsEquals e)]
                        , rdModeB    = Nothing
                        , rdEmitted  = ModeA
                        , rdFallback = Nothing
                        , rdEqv      = Nothing
                        })
               <$> lowerExpr bodyCtx d

-- | A fallback from the primary (Mode B) rendering is reported; the ordinary
-- case — a ladder that carries its equivalence grid — is not noise worth
-- printing (§8.4: fallbacks are warned, never silent).
modeNotes :: Text -> CatRuleDef -> [Text]
modeNotes fn rd = case (rd.rdEmitted, rd.rdModeB, rd.rdFallback) of
  (ModeA, Just _, Just why) -> [ "`" <> fn <> "`: " <> why ]
  _                         -> []

-- ---------------------------------------------------------------------------
-- Non-exported reachable helpers → private toplevels (R1)
-- ---------------------------------------------------------------------------

lowerHelper :: Ctx -> DecideInfo -> V CatTopdef
lowerHelper outer di = vIn di.diName $ case di.diGiveth of
  Nothing -> vBad [LowerError di.diName di.diRange
                    ("helper `" <> di.diName <> "` has no GIVETH; a Catala toplevel declaration "
                     <> "needs its result type stated")]
  Just gt -> CatTopdef (catIdent di.diName) di.diName di.diDesc
               <$> (concat <$> vList (map param di.diGivens))
               <*> lowerType outer di.diRange gt
               <*> lowerExpr bodyCtx di.diBody
 where
  bodyCtx = outer
    { cxVars = Map.fromList
        (  [ (getUnique (givenName g), catIdent (givenText g))
           | g <- di.diGivens, not (Map.member (getUnique (givenName g)) outer.cxElided) ]
        <> [ (getUnique r, catIdent (givenText g))
           | (r, g) <- zip di.diAppArgs di.diGivens
           , not (Map.member (getUnique (givenName g)) outer.cxElided) ] )
    , cxAssumeOK = False
    , cxNonexh   = di.diNonexh
    }
  param g
    | Map.member (getUnique (givenName g)) outer.cxElided = pure []
    | otherwise = case givenType g of
        Nothing -> vBad [LowerError di.diName di.diRange
                          ("parameter `" <> givenText g <> "` of helper `" <> di.diName
                           <> "` has no declared type")]
        Just (Type {}) -> vBad [LowerError di.diName di.diRange
                                 ("helper `" <> di.diName <> "` is polymorphic (`" <> givenText g
                                  <> " IS A TYPE`); Catala toplevels are monomorphic in v1 "
                                  <> "(R5, §4.2)")]
        Just t -> (\ty -> [(catIdent (givenText g), ty)]) <$> lowerType outer di.diRange t

-- ---------------------------------------------------------------------------
-- Rules: Mode A always, Mode B where derivable (R4)
-- ---------------------------------------------------------------------------

-- | R4: the exception ladder is the primary rendering wherever the module can
-- also carry the equivalence apparatus that re-checks it. Where it cannot, the
-- boolean reference rendering is emitted and the reason is recorded — as a
-- comment in the artifact and as a warning on stderr.
lowerRule :: Ctx -> Text -> CatVarShape -> Expr Resolved -> V CatRuleDef
lowerRule ctx var shape body =
  (\modeA modeB -> case modeB of
      Nothing -> CatRuleDef
        { rdVar = var, rdModeA = modeA, rdModeB = Nothing
        , rdEmitted = ModeA, rdEqv = Nothing
        , rdFallback = Just "no exception ladder is derivable for this rule's shape"
        }
      Just (clauses, _) | ctx.cxBoolOnly -> CatRuleDef
        { rdVar = var, rdModeA = modeA, rdModeB = Just clauses
        , rdEmitted = ModeA, rdEqv = Nothing
        , rdFallback = Just "--boolean-only: the Mode A reference rendering was requested"
        }
      Just (clauses, eqv)
        | n <- eqvAtomCount eqv, n > 0, n <= eqvRowLimit -> CatRuleDef
            { rdVar = var, rdModeA = modeA, rdModeB = Just clauses
            , rdEmitted = ModeB, rdFallback = Nothing, rdEqv = Just eqv
            }
        | otherwise -> CatRuleDef
            { rdVar = var, rdModeA = modeA, rdModeB = Just clauses
            , rdEmitted = ModeA, rdEqv = Nothing
            , rdFallback = Just
                ( "an exception ladder was derived, but it ranges over "
                <> tshow (eqvAtomCount eqv) <> " atomic conditions and §8.4's standing "
                <> "equivalence check enumerates them exhaustively (cap: " <> tshow eqvRowLimit
                <> "). An unchecked ladder is the one thing R4 will not ship, so the boolean "
                <> "reference rendering is emitted instead." )
            }
  )
  <$> plainClauses
  <*> modeBClauses ctx var shape body
 where
  plainClauses =
    (\e -> [ case shape of
               ShCondition -> CatClause ClPlain (Just e) ConsFulfilled
               ShContent _ -> CatClause ClPlain Nothing (ConsEquals e) ])
    <$> lowerExpr ctx body

-- | Derive the exception-ladder rendering of a rule, when its shape admits one.
--
-- Three shapes do (§4.4, §8.4):
--
--   * a boolean decision written @c UNLESS d@ — after desugaring, @c AND NOT d@
--     — becomes a base rule plus one @not fulfilled@ exception per proviso,
--     chained so that two provisos firing at once cannot raise Catala's
--     @Conflict@;
--   * a @BRANCH@ cascade or an @IF@ becomes a priority ladder over its arms:
--     the @OTHERWISE@ is the base and arm /i/ is an exception to arm /i+1/, so
--     Catala's "the exception wins" reproduces L4's first-match;
--   * a @CONSIDER@ over literals is the same thing with equality guards.
--
-- Anything else yields 'Nothing', and the rule is emitted in Mode A.
modeBClauses :: Ctx -> Text -> CatVarShape -> Expr Resolved -> V (Maybe ([CatClause], CatEqv))
modeBClauses ctx var shape body = case shape of
  ShCondition
    | Just (base, provisos) <- peelProvisos body ->
        (\b ps -> Just (provisoLadder var b ps, CatEqv (EqvProviso (length ps)) (b : ps)))
          <$> lowerExpr ctx base <*> vList (map (lowerExpr ctx) provisos)
  _ | Just (arms, dflt) <- cascadeArms body ->
        (\as d -> (,) <$> armLadder var shape as d <*> eqvOf as d)
          <$> vList [ (,) <$> lowerExpr ctx c <*> lowerExpr ctx v | (c, v) <- arms ]
          <*> lowerExpr ctx dflt
  _ -> pure Nothing
 where
  eqvOf as d = case shape of
    ShContent _ -> Just (CatEqv (EqvArmsValue (length as)) (map fst as))
    ShCondition -> do
      d' <- boolOf d
      ks <- traverse (boolOf . snd) as
      pure (CatEqv (EqvArmsCond ks d') (map fst as))
  boolOf = \case
    ELit (LBool b) -> Just b
    _              -> Nothing

-- | @c AND NOT d1 AND NOT d2 …@ → @(c, [d1, d2, …])@, or 'Nothing' when there is
-- no trailing negated conjunct to make a proviso out of.
peelProvisos :: Expr Resolved -> Maybe (Expr Resolved, [Expr Resolved])
peelProvisos e0 = case go e0 of
  (_, []) -> Nothing
  r       -> Just r
 where
  go x = case asAnd x of
    Just (a, b) | Just d <- asNot b -> let (base, ds) = go a in (base, ds <> [d])
    _ -> (x, [])

asAnd :: Expr Resolved -> Maybe (Expr Resolved, Expr Resolved)
asAnd = \case
  And _ a b                              -> Just (a, b)
  App _ r [a, b] | isBuiltinNamed r "__AND__" -> Just (a, b)
  _                                      -> Nothing

asNot :: Expr Resolved -> Maybe (Expr Resolved)
asNot = \case
  Not _ a                             -> Just a
  App _ r [a] | isBuiltinNamed r "__NOT__" -> Just a
  _                                   -> Nothing

isBuiltinNamed :: Resolved -> Text -> Bool
isBuiltinNamed r nm = plainName r == nm || unqualifiedNameToText (getActual r) == nm

-- | The first-match arms of a @BRANCH@, an @IF@, or a literal @CONSIDER@.
cascadeArms :: Expr Resolved -> Maybe ([(Expr Resolved, Expr Resolved)], Expr Resolved)
cascadeArms = \case
  MultiWayIf _ guards oth -> Just ([ (c, b) | MkGuardedExpr _ c b <- guards ], oth)
  IfThenElse _ c t e      -> Just ([(c, t)], e)
  e@(Consider {})         -> litConsiderArms e
  _                       -> Nothing

-- | A @CONSIDER@ whose patterns are all literals is an equality cascade; Catala
-- patterns are constructor-only, so this is the shape §4.3 sends to @if@/@else@.
litConsiderArms :: Expr Resolved -> Maybe ([(Expr Resolved, Expr Resolved)], Expr Resolved)
litConsiderArms (Consider ann scrut branches)
  | not (null whens), [oth] <- others, length whens + 1 == length branches =
      Just ([ (Equals ann scrut (Lit ann l), b) | (l, b) <- whens ], oth)
 where
  whens  = [ (l, b) | MkBranch _ (When _ (PatLit _ l)) b <- branches ]
  others = [ b      | MkBranch _ (Otherwise _)         b <- branches ]
litConsiderArms _ = Nothing

-- ---------------------------------------------------------------------------
-- Types (R2, R11)
-- ---------------------------------------------------------------------------

-- | Lower an L4 type. @NUMBER@ becomes @decimal@ uniformly and @money@ is never
-- inferred (R2, §8.2); @STRING@ has no Catala counterpart at all and survives
-- only by elision at the field\/parameter level (R11, §8.11), so reaching here
-- means it was used where a type is structurally required.
lowerType :: Ctx -> Maybe SrcRange -> Type' Resolved -> V CatType
lowerType ctx rng = go
 where
  bad = vErr rng
  go = \case
    TyApp _ name args ->
      let u  = getUnique name
          nm = plainName name
          lo = Text.toLower nm
      in case args of
        [inner] | u == TC.listUnique  || lo `elem` ["list", "list of", "listof"] -> TList <$> go inner
                | u == TC.maybeUnique || lo `elem` ["maybe", "maybe of"]         -> TOption <$> go inner
        []
          | u == TC.booleanUnique || lo `elem` ["boolean", "bool"] -> pure TBool
          | u == TC.numberUnique  || lo == "number"                -> pure TDecimal
          | u == TC.dateUnique    || lo == "date"                  -> pure TDate
          | u == TC.stringUnique  || lo `elem` ["string", "text"]  ->
              bad "`STRING` has no Catala counterpart (§4.8): a string that is never inspected is \
                  \elided at the field or parameter level (R11), but it cannot appear inside a type."
          | Map.member u ctx.cxTypes || Map.member u ctx.cxRecords -> pure (TNamed (catUpper nm))
        _ -> bad ("type `" <> nm <> "` is outside the v1 Catala fragment (§6)")
    Fun {}    -> bad "function-typed values are not expressible in Catala (R5, §8.5)"
    Forall {} -> bad "polymorphic types are not lowered in v1 — monomorphise the helper (§4.2)"
    InfVar {} -> bad "unresolved type: the typechecker did not pin this type down"
    Type {}   -> bad "the type of types is not a Catala type"

-- | A context-free type lowering, used by the declaration scan, which runs
-- before the full context exists. A named type is accepted on sight; a
-- genuinely unknown one is caught at every use site by 'lowerType'.
lowerTypeBare :: Type' Resolved -> V CatType
lowerTypeBare = go
 where
  bad = vErr Nothing
  go = \case
    TyApp _ name args ->
      let u  = getUnique name
          nm = plainName name
          lo = Text.toLower nm
      in case args of
        [inner] | u == TC.listUnique  || lo `elem` ["list", "list of", "listof"] -> TList <$> go inner
                | u == TC.maybeUnique || lo `elem` ["maybe", "maybe of"]         -> TOption <$> go inner
        []
          | u == TC.booleanUnique || lo `elem` ["boolean", "bool"] -> pure TBool
          | u == TC.numberUnique  || lo == "number"                -> pure TDecimal
          | u == TC.dateUnique    || lo == "date"                  -> pure TDate
          | u == TC.stringUnique  || lo `elem` ["string", "text"]  -> bad "STRING"
          | otherwise                                              -> pure (TNamed (catUpper nm))
        _ -> bad ("type `" <> nm <> "` is outside the v1 Catala fragment (§6)")
    _ -> bad "this type is outside the v1 Catala fragment (§6)"

-- | @STRING@-shaped, for R11's elision test.
isStringType :: Type' Resolved -> Bool
isStringType = \case
  TyApp _ n [] ->
    getUnique n == TC.stringUnique || Text.toLower (canonText n) `elem` ["string", "text"]
  _ -> False

-- ---------------------------------------------------------------------------
-- Expressions
-- ---------------------------------------------------------------------------

lowerExpr :: Ctx -> Expr Resolved -> V CatExpr
lowerExpr ctx = go
 where
  bad e m = vErr (rangeOf e) m

  go e = case e of
    -- Both spellings of the operators appear: L4 desugars infix syntax into
    -- builtin applications after name resolution, but the constructors survive
    -- in some positions, so each is handled twice.
    And _ a b          -> EBin BAnd <$> go a <*> go b
    Or _ a b           -> EBin BOr  <$> go a <*> go b
    Not _ a            -> EUn UNot  <$> go a
    Implies _ a b      -> (\x y -> EBin BOr (EUn UNot x) y) <$> go a <*> go b
    Equals _ a b       -> EBin BEq  <$> go a <*> go b
    Leq _ a b          -> EBin BLeq <$> go a <*> go b
    Geq _ a b          -> EBin BGeq <$> go a <*> go b
    Lt  _ a b          -> EBin BLt  <$> go a <*> go b
    Gt  _ a b          -> EBin BGt  <$> go a <*> go b
    Plus _ a b         -> EBin BAdd <$> go a <*> go b
    Minus _ a b        -> EBin BSub <$> go a <*> go b
    Times _ a b        -> EBin BMul <$> go a <*> go b
    DividedBy _ a b    -> EBin BDiv <$> go a <*> go b
    Modulo _ _ _       -> bad e "Catala has no modulo operator on decimals (§4.5)"
    Cons _ x xs        -> (\h t -> EAppend (EList [h]) t) <$> go x <*> go xs
    IfThenElse _ c t f -> EIf <$> go c <*> go t <*> go f
    MultiWayIf _ gs oth ->
      (\arms d -> foldr (\(c, v) acc -> EIf c v acc) d arms)
        <$> vList [ (,) <$> go c <*> go b | MkGuardedExpr _ c b <- gs ]
        <*> go oth
    Consider _ scrut branches -> lowerConsider ctx e scrut branches
    Proj _ inner fld          -> lowerProj e inner fld
    Lit _ (NumericLit _ v)    -> pure (ELit (LDec v))
    Lit _ (StringLit _ _)     ->
      bad e "string literals have no Catala counterpart: Catala has no string type (§4.8)"
    Percent _ p -> case p of
      Lit _ (NumericLit _ v) -> pure (ELit (LDec (v / 100)))
      _                      -> (\x -> EBin BDiv x (ELit (LDec 100))) <$> go p
    List _ es          -> EList <$> vList (map go es)
    Where _ inner ds   -> lowerLocals e ds inner
    LetIn _ ds inner   -> lowerLocals e ds inner
    App _ ref args     -> lowerApp ctx e ref args
    AppNamed _ ref named _ -> lowerNamed e ref named
    -- Inert scaffolding is grammatical filler; L4 evaluates it to its context's
    -- identity element, which is what the emitted Catala should say. (The prose
    -- itself belongs in the literate weave — R8, not yet wired.)
    Inert _ _ InertCtxAnd  -> pure (ELit (LBool True))
    Inert _ _ InertCtxOr   -> pure (ELit (LBool False))
    Inert _ _ InertCtxNone -> pure (ELit (LBool True))
    _ -> bad e (unsupported e)

  -- @x's field@. R11: a field that was elided has no emitted counterpart, so
  -- reading it is exactly the "inspected string" case that stays a hard error.
  lowerProj e inner fld = case Map.lookup (getUnique fld) ctx.cxFields of
    Just f -> case f.rfStatus of
      FEmitted _      -> (\x -> EProj x f.rfName) <$> go inner
      FElidedString   -> bad e ("field `" <> f.rfL4 <> "` is a STRING and was elided from the "
                                <> "emitted structure (R11); reading its value is not expressible "
                                <> "in Catala, which has no string type (§4.8)")
      FElidedComputed -> bad e ("field `" <> f.rfL4 <> "` is a computed (MEANS) field; Catala "
                                <> "structures carry data only — lift it to a helper function")
      FUnsupported m  -> bad e ("field `" <> f.rfL4 <> "` was not emitted: " <> m)
    Nothing -> (\x -> EProj x (catIdent (resolvedToText fld))) <$> go inner

  -- @Applicant WITH age IS 70, …@ — a record built with named fields.
  lowerNamed e ref named = case Map.lookup (getUnique ref) ctx.cxRecords of
    Nothing -> bad e ("named-argument application of `" <> resolvedToText ref
                      <> "` is only supported for record construction")
    Just ri ->
      let byUnique = Map.fromList [ (getUnique f, v) | MkNamedExpr _ f v <- named ]
          byName   = Map.fromList [ (catIdent (resolvedToText f), v) | MkNamedExpr _ f v <- named ]
          pick f   = Map.lookup f.rfUnique byUnique <|> Map.lookup f.rfName byName
      in EStruct ri.riName <$> vList
           [ (,) f.rfName <$> maybe (missingField e ri f) go (pick f)
           | f <- ri.riFields, FEmitted _ <- [f.rfStatus]
           ]

  missingField e ri f =
    bad e ("record `" <> ri.riL4 <> "` is missing field `" <> f.rfL4 <> "`")

  -- @WHERE@ / @LET … IN@: nullary local definitions become Catala's `let … in`
  -- (§4.2). They are emitted in dependency order; a cycle among them is
  -- recursion, and R6 rejects it.
  lowerLocals e decls inner = case traverse asNullaryDecide decls of
    Nothing -> bad e "a WHERE/LET binding with parameters is a local function, and Catala has no \
                     \local function definitions — lift it to a module-level helper (§4.2)"
    Just bs ->
      let keys = Set.fromList [ u | (u, _, _) <- bs ]
          nodes = [ (u, Set.intersection keys (Set.fromList (map getUnique (toList b))), (u, nm, b))
                  | (u, nm, b) <- bs ]
      in case topoSort nodes of
        Left cyc -> bad e ("recursive WHERE/LET bindings have no Catala counterpart (R6): "
                           <> Text.intercalate ", " [ nm | (u, nm, _) <- bs, u `elem` cyc ])
        Right ordered -> foldLets ctx ordered inner

  foldLets c [] inner = lowerExpr c inner
  foldLets c ((u, nm, b) : rest) inner =
    let v = catIdent nm
    in ELet v <$> lowerExpr c b
              <*> foldLets (c { cxVars = Map.insert u v c.cxVars }) rest inner

  asNullaryDecide = \case
    LocalDecide _ (MkDecide _ (MkTypeSig _ (MkGivenSig _ []) _) (MkAppForm _ n [] _) b) ->
      Just (getUnique n, resolvedToText n, b)
    _ -> Nothing

-- | Applications: operators, literals, constructors, records, scope calls,
-- helper calls, prelude combinators (R5) and date builtins (R3).
--
-- The module's own definitions are consulted /before/ the prelude recognisers,
-- so a locally defined @map@ shadows the prelude's, as it should.
lowerApp :: Ctx -> Expr Resolved -> Resolved -> [Expr Resolved] -> V CatExpr
lowerApp ctx e ref args
  | Just mk <- firstOf builtinOp =
      vList (map (lowerExpr ctx) args) `vThen` (either bad pure . mk)
  | u == TC.trueUnique  = pure (ELit (LBool True))
  | u == TC.falseUnique = pure (ELit (LBool False))
  | u == TC.emptyUnique = pure (EList [])
  | u == TC.nothingUnique = pure (ECon "Absent" Nothing)
  | u == TC.justUnique, [a] <- args = ECon "Present" . Just <$> lowerExpr ctx a
  | u == TC.consUnique, [x, xs] <- args =
      (\h t -> EAppend (EList [h]) t) <$> lowerExpr ctx x <*> lowerExpr ctx xs
  | Just v  <- Map.lookup u ctx.cxVars, null args = pure (EVar v)
  | Just w  <- Map.lookup u ctx.cxElided = bad w
  | Just ci <- Map.lookup u ctx.cxCons    = constructor ci
  | Just ri <- Map.lookup u ctx.cxRecords = record ri
  | Just ai <- Map.lookup u ctx.cxAssumes = assumeRef ai
  | Just sg <- Map.lookup u ctx.cxScopes  = scopeCall sg
  | Just hs <- Map.lookup u ctx.cxHelpers = helperCall hs
  | Just r  <- firstOf (\n -> combinator ctx n args)  = r
  | Just r  <- firstOf (\n -> dateBuiltin ctx e n args) = r
  | Map.member u ctx.cxDecides =
      bad ("`" <> nm <> "` is defined in this module but was not collected as a helper; that is a "
           <> "lowering bug, please report it")
  | otherwise =
      bad ("unbound reference `" <> nm <> "`: it is neither a v1-fragment builtin, a prelude "
           <> "combinator absorbed under R5, nor a definition in this module (§6)")
 where
  u   = getUnique ref
  nm  = canonText ref
  bad = vErr (rangeOf e)
  -- Recognisers key on the /bare/ name, and on both spellings of it: a
  -- section-qualified reference carries its section path
  -- ("Prelude.Numeric Aggregates.sum"), and an @AKA@\'d definition answers to
  -- its alias at the defining occurrence (daydate\'s `YMD` is recorded as
  -- "Year month day"), so neither spelling alone finds every prelude function.
  names = nub [ plainName ref, unqualifiedRawNameToText (rawName (getActual ref)) ]
  firstOf :: (Text -> Maybe a) -> Maybe a
  firstOf f = listToMaybe (mapMaybe f names)

  constructor ci = case (ci.ciPayload, args) of
    (False, [])  -> pure (ECon ci.ciCase Nothing)
    (True,  [a]) -> ECon ci.ciCase . Just <$> lowerExpr ctx a
    _ -> bad ("enum constructor `" <> ci.ciL4 <> "` was applied to " <> tshow (length args)
              <> " argument(s); Catala's `content` carries exactly one value")

  record ri
    | length args /= length ri.riFields =
        bad ("record `" <> ri.riL4 <> "` applied to " <> tshow (length args)
             <> " argument(s) but has " <> tshow (length ri.riFields) <> " field(s)")
    | otherwise = EStruct ri.riName <$> vList
        [ (,) f.rfName <$> lowerExpr ctx a
        | (f, a) <- zip ri.riFields args, FEmitted _ <- [f.rfStatus]
        ]

  assumeRef ai
    | not ctx.cxAssumeOK =
        bad ("ASSUMEd input `" <> ai.aiL4 <> "` is only readable inside an @export decision's scope "
             <> "(where it becomes a scope `input`); pass it to this helper as a parameter instead")
    | otherwise = case Map.lookup u ctx.cxVars of
        Just v  -> pure (EVar v)
        Nothing -> bad ("ASSUMEd input `" <> ai.aiL4 <> "` is not an input of this scope")

  scopeCall sg
    | length args /= length sg.ssParams =
        bad ("call to `" <> nm <> "` has " <> tshow (length args) <> " argument(s) but its scope "
             <> "declares " <> tshow (length sg.ssParams))
    | not (null sg.ssAssumes) && not ctx.cxAssumeOK =
        bad ("`" <> nm <> "` reads module-level ASSUMEd inputs, so it can only be called from "
             <> "another @export decision's scope, not from a toplevel helper")
    | otherwise =
        (\bound -> EScopeOut sg.ssScope (bound <> [ (a, EVar a) | a <- sg.ssAssumes ]) sg.ssOutput)
        <$> vList [ (,) p <$> lowerExpr ctx a | ((p, keep), a) <- zip sg.ssParams args, keep ]

  helperCall hs
    | length args /= length hs.hsParams =
        bad ("call to helper `" <> nm <> "` has " <> tshow (length args) <> " argument(s) but it "
             <> "declares " <> tshow (length hs.hsParams))
    | otherwise =
        ECall hs.hsName <$> vList [ lowerExpr ctx a | ((_, keep), a) <- zip hs.hsParams args, keep ]

-- ---------------------------------------------------------------------------
-- CONSIDER (§4.3)
-- ---------------------------------------------------------------------------

lowerConsider :: Ctx -> Expr Resolved -> Expr Resolved -> [Branch Resolved] -> V CatExpr
lowerConsider ctx whole scrut branches
  | any isLit branches = literalChain
  | otherwise          = constructorMatch
 where
  bad = vErr (rangeOf whole)
  isLit (MkBranch _ lhs _) = case lhs of When _ (PatLit _ _) -> True; _ -> False

  literalChain = case litConsiderArms whole of
    Just (arms, dflt) ->
      (\as d -> foldr (\(c, v) acc -> EIf c v acc) d as)
        <$> vList [ (,) <$> lowerExpr ctx c <*> lowerExpr ctx v | (c, v) <- arms ]
        <*> lowerExpr ctx dflt
    Nothing -> bad "a CONSIDER over literals compiles to an if/else chain (Catala patterns are \
                   \constructor-only), so it needs a final OTHERWISE and no other pattern kind (§4.3)"

  constructorMatch =
    vList (map armOf branches) `vThen` \arms0 ->
    lowerExpr ctx scrut `vThen` \s ->
      let named    = [ (ci, a) | (Just ci, a) <- arms0 ]
          wildcard = [ a | (Nothing, a) <- arms0 ]
          enums    = nub [ ci.ciEnum | (ci, _) <- named ]
          arms     = [ a | (_, a) <- named ]
      in case enums of
        _ | null named ->
              bad "a CONSIDER with no constructor pattern is not expressible as a Catala `match` \
                  \(§4.3)"
        [en] ->
          let matched  = [ ci.ciCase | (ci, _) <- named ]
              universe = Map.findWithDefault [] en ctx.cxCases
              missing  = [ c | c <- universe, c `notElem` matched ]
          in if not (null wildcard)
               then pure (EMatch s (arms <> take 1 wildcard))
               else if null missing
                 then pure (EMatch s arms)
                 else if ctx.cxNonexh
                   -- @\@nonexhaustive@: the author asserts these cases cannot arise, and
                   -- Catala's `impossible` says exactly that (§2.1, §4.3).
                   then pure (EMatch s (arms <> map (impossibleArm en) missing))
                   else bad ("this CONSIDER does not cover "
                             <> Text.intercalate ", " [ "`" <> c <> "`" | c <- missing ]
                             <> " of enumeration `" <> en <> "`. Catala rejects a partial match at "
                             <> "typecheck time, so add the arms, add an OTHERWISE, or mark the "
                             <> "definition @nonexhaustive to emit them as `impossible` (§4.3).")
        _ -> bad "this CONSIDER mixes constructors from more than one enumeration"

  impossibleArm en c = CatArm (PCon c Nothing)
    (EImpossible (Just ("`" <> c <> "` of `" <> en
                        <> "` was declared unreachable by @nonexhaustive")))

  armOf (MkBranch _ lhs body) = case lhs of
    Otherwise _ -> (\b -> (Nothing, CatArm PAnything b)) <$> lowerExpr ctx body
    When _ pat  -> case pat of
      PatApp _ con [] -> conInfo con `vThen` \ci ->
        (\b -> (Just ci, CatArm (PCon ci.ciCase Nothing) b)) <$> lowerExpr ctx body
      PatApp _ con [PatVar _ v] -> conInfo con `vThen` \ci ->
        let nmv  = catIdent (resolvedToText v)
            ctx' = ctx { cxVars = Map.insert (getUnique v) nmv ctx.cxVars }
        in (\b -> (Just ci, CatArm (PCon ci.ciCase (Just nmv)) b)) <$> lowerExpr ctx' body
      PatApp _ _ ps ->
        bad ("Catala's `-- C content x` binds at most one payload and does not nest; this arm "
             <> "carries " <> tshow (length ps) <> " sub-pattern(s) (§4.3)")
      PatCons _ _ _ ->
        bad "list patterns (`WHEN x FOLLOWED BY xs`) have no Catala counterpart; they are \
            \structural recursion, which R6 rejects — rewrite with a list combinator (§4.7)"
      PatVar _ _ ->
        bad "a bare variable pattern binds the scrutinee, and Catala's `-- anything` wildcard does \
            \not bind; use a WHERE binding instead (§4.3)"
      PatLit _ _  -> bad "internal: a literal pattern reached the constructor-match path"
      PatExpr _ _ -> bad "expression patterns have no Catala counterpart (§4.3)"

  conInfo con = case Map.lookup (getUnique con) ctx.cxCons of
    Just ci -> pure ci
    Nothing
      | getUnique con == TC.justUnique    -> pure (ConInfo maybeEnum "Present" "JUST" True)
      | getUnique con == TC.nothingUnique -> pure (ConInfo maybeEnum "Absent" "NOTHING" False)
      | getUnique con == TC.emptyUnique   ->
          bad "`WHEN EMPTY` is a list pattern and Catala has none — rewrite with a list combinator \
              \or `number of` (§4.7)"
      | otherwise ->
          bad ("`" <> resolvedToText con <> "` is not a constructor of an enumeration declared in "
               <> "this module, so it has no Catala pattern")

-- ---------------------------------------------------------------------------
-- Prelude combinators (R5, §4.7)
-- ---------------------------------------------------------------------------

-- | Recognise an application of a known prelude combinator and emit Catala's
-- binder form. The lambda a combinator carries is absorbed into that binder
-- syntax; every other higher-order use is rejected (R5, §8.5).
combinator :: Ctx -> Text -> [Expr Resolved] -> Maybe (V CatExpr)
combinator ctx nm args = case (nm, args) of
  ("map",       [f, l]) -> Just (binder1 f l EMapEach)
  ("filter",    [f, l]) -> Just (binder1 f l EFilter)
  ("any",       [f, l]) -> Just (binder1 f l EExists)
  ("all",       [f, l]) -> Just (binder1 f l EForAll)
  ("and",       [l])    -> Just ((\l' -> EForAll "item" l' (EVar "item")) <$> lo l)
  ("or",        [l])    -> Just ((\l' -> EExists "item" l' (EVar "item")) <$> lo l)
  ("sum",       [l])    -> Just ((\l' -> EStdCall "Decimal.sum" [l']) <$> lo l)
  ("product",   [l])    -> Just ((\l' -> EFold "item" "total" l' (ELit (LDec 1))
                                           (EBin BMul (EVar "total") (EVar "item"))) <$> lo l)
  -- `number of` is Catala's only length form and it returns an `integer`; L4's
  -- `count` is a NUMBER, so R2's structurally-forced coercion applies here.
  ("count",     [l])    -> Just (ECoerce TDecimal . ENumberOf <$> lo l)
  ("length",    [l])    -> Just (ECoerce TDecimal . ENumberOf <$> lo l)
  ("null",      [l])    -> Just ((\l' -> EBin BEq (ENumberOf l') (ELit (LInt 0))) <$> lo l)
  ("elem",      [x, l]) -> Just (flip EContains <$> lo x <*> lo l)
  ("append",    [a, b]) -> Just (EAppend <$> lo a <*> lo b)
  ("max",       [a, b]) -> Just (pick BGeq a b)
  ("min",       [a, b]) -> Just (pick BLeq a b)
  ("foldl",     [f, i, l]) -> Just (fold2 f i l)
  ("fromMaybe", [d, x]) -> Just (fromMaybeE d x)
  _ -> Nothing
 where
  lo = lowerExpr ctx
  pick op a b = (\x y -> EIf (EBin op x y) x y) <$> lo a <*> lo b

  -- A one-argument function position: a literal lambda binds directly, a named
  -- one-argument function is applied to a synthesised binder.
  binder1 f l mk = case f of
    Lam _ (MkGivenSig _ [p]) fb ->
      let v    = catIdent (givenText p)
          ctx' = ctx { cxVars = Map.insert (getUnique (givenName p)) v ctx.cxVars }
      in mk v <$> lo l <*> lowerExpr ctx' fb
    Lam _ (MkGivenSig _ ps) _ ->
      vErr (rangeOf f) ("this combinator takes a one-argument function, but the lambda binds "
                        <> tshow (length ps) <> " (R5)")
    App _ r [] ->
      let v = "item_" <> catIdent (unqualifiedRawNameToText (rawName (getOriginal r)))
      in fnRef1 ctx f `vThen` \apply -> mk v <$> lo l <*> pure (apply (EVar v))
    _ -> vErr (rangeOf f)
           "a combinator's function argument must be a literal lambda (GIVEN … YIELD) or a named \
           \one-argument function; no other higher-order code survives (R5, §8.5)"

  fold2 f i l = case f of
    Lam _ (MkGivenSig _ [acc, x]) fb ->
      let va   = catIdent (givenText acc)
          vx   = catIdent (givenText x)
          ctx' = ctx { cxVars = Map.insert (getUnique (givenName acc)) va
                                  (Map.insert (getUnique (givenName x)) vx ctx.cxVars) }
      in EFold vx va <$> lo l <*> lo i <*> lowerExpr ctx' fb
    _ -> vErr (rangeOf f)
           "`foldl` needs a two-argument literal lambda (GIVEN acc, x YIELD …) to absorb into \
           \Catala's `combine all … in … initially … with …` (R5)"

  fromMaybeE d x =
    (\d' x' -> EMatch x' [ CatArm (PCon "Present" (Just "v")) (EVar "v")
                         , CatArm (PCon "Absent" Nothing) d' ])
    <$> lo d <*> lo x

-- | A named one-argument function, as something a combinator binder can apply.
fnRef1 :: Ctx -> Expr Resolved -> V (CatExpr -> CatExpr)
fnRef1 ctx = \case
  App _ r [] | Just hs <- Map.lookup (getUnique r) ctx.cxHelpers, length hs.hsParams == 1 ->
    pure (\a -> ECall hs.hsName [a])
  App _ r [] | Just sg <- Map.lookup (getUnique r) ctx.cxScopes
             , [(p, True)] <- sg.ssParams
             , null sg.ssAssumes ->
    pure (\a -> EScopeOut sg.ssScope [(p, a)] sg.ssOutput)
  f -> vErr (rangeOf f)
         "a combinator's function argument must be a literal lambda or a one-argument definition \
         \from this module (R5, §8.5)"

-- ---------------------------------------------------------------------------
-- Dates (R3, §4.6)
-- ---------------------------------------------------------------------------

-- | The date fragment R3 admits: @YMD@'s bounds-checked construction maps onto
-- native Catala date construction (a date literal when the components are
-- literal, an @impossible@ when they are literal and out of range — which is
-- exactly what @YMD@'s refusal value denotes, §8.3), and the component getters
-- map onto the implicitly-imported @Date@ stdlib module.
--
-- The /lenient/ @Date d m y@ constructor is deliberately absent: its
-- roll-forward overflow rule (Feb 31 ↦ Mar 3) equals neither of Catala's two
-- rounding policies, so R3 calls for an emitted day-granular helper, which this
-- pass does not yet build. Rejecting is the honest option until it does.
dateBuiltin :: Ctx -> Expr Resolved -> Text -> [Expr Resolved] -> Maybe (V CatExpr)
dateBuiltin ctx e nm args = case (nm, args) of
  ("YMD", [y, m, d])
    | Just (yi, mi, di) <- (,,) <$> litInt y <*> litInt m <*> litInt d ->
        Just . pure $
          if validYMD yi (fromInteger mi) (fromInteger di)
            then ELit (LDate yi (fromInteger mi) (fromInteger di))
            else EImpossible (Just ("YMD refused an out-of-range date: " <> tshow yi <> "-"
                                    <> tshow mi <> "-" <> tshow di))
    | otherwise -> Just
        ( (\y' m' d' -> EStdCall "Date.of_year_month_day"
                          [ECoerce TInteger y', ECoerce TInteger m', ECoerce TInteger d'])
          <$> lowerExpr ctx y <*> lowerExpr ctx m <*> lowerExpr ctx d )
  ("DATE_YEAR",  [d]) -> Just (getter "Date.get_year" d)
  ("DATE_MONTH", [d]) -> Just (getter "Date.get_month" d)
  ("DATE_DAY",   [d]) -> Just (getter "Date.get_day" d)
  ("Date", _) -> Just $ vErr (rangeOf e)
    "the lenient `Date d m y` constructor rolls out-of-range components forward (Feb 31 ↦ Mar 3), \
    \which matches neither of Catala's rounding policies; R3 compiles it through an emitted \
    \day-granular helper that this pass does not yet build. Use `YMD year month day` (§4.6)."
  _ -> Nothing
 where
  getter f d = ECoerce TDecimal . EStdCall f . (: []) <$> lowerExpr ctx d
  litInt = \case
    Lit _ (NumericLit _ v) | denominator v == 1 -> Just (numerator v)
    _ -> Nothing

validYMD :: Integer -> Int -> Int -> Bool
validYMD y m d = m >= 1 && m <= 12 && d >= 1 && d <= daysIn m
 where
  leap = (y `mod` 4 == 0 && y `mod` 100 /= 0) || y `mod` 400 == 0
  daysIn k
    | k == 2                = if leap then 29 else 28
    | k `elem` [4, 6, 9, 11] = 30
    | otherwise              = 31

-- ---------------------------------------------------------------------------
-- Builtin operators
-- ---------------------------------------------------------------------------

-- | The builtins L4 desugars its infix operators into.
builtinOp :: Text -> Maybe ([CatExpr] -> Either Text CatExpr)
builtinOp nm = case nm of
  "__PLUS__"    -> Just (bin BAdd)
  "__MINUS__"   -> Just (bin BSub)
  "__TIMES__"   -> Just (bin BMul)
  "__DIVIDE__"  -> Just (bin BDiv)
  "__MODULO__"  -> Just (const (Left "Catala has no modulo operator on decimals (§4.5)"))
  "__EQUALS__"  -> Just (bin BEq)
  "__LEQ__"     -> Just (bin BLeq)
  "__GEQ__"     -> Just (bin BGeq)
  "__LT__"      -> Just (bin BLt)
  "__GT__"      -> Just (bin BGt)
  "__AND__"     -> Just (bin BAnd)
  "__OR__"      -> Just (bin BOr)
  "__NOT__"     -> Just (\case [a] -> Right (EUn UNot a); xs -> arity 1 xs)
  -- Catala has no `implies`; @a => b@ is @(not a) or b@ (§4.3).
  "__IMPLIES__" -> Just (\case [a, b] -> Right (EBin BOr (EUn UNot a) b); xs -> arity 2 xs)
  _             -> Nothing
 where
  bin op = \case [a, b] -> Right (EBin op a b); xs -> arity 2 xs
  arity :: Int -> [CatExpr] -> Either Text CatExpr
  arity n xs = Left ("operator `" <> nm <> "` expected " <> tshow n
                     <> " argument(s), got " <> tshow (length xs))

-- | A short human label for a rejected node, so the diagnostic names the
-- construct rather than the pass that tripped over it (§5.1, §6).
unsupported :: Expr Resolved -> Text
unsupported e = "this construct is outside the v1 Catala fragment (§6): " <> case e of
  Regulative{} -> "a deontic/regulative rule (PARTY / MUST / MAY / SHANT). Catala models no \
                  \obligation, party, or time-bounded action (§5.1)"
  Event{}      -> "EVENT — Catala has no event or trace notion (§5.1)"
  Fetch{}      -> "FETCH — emitted Catala is pure and self-contained (§5.1)"
  Post{}       -> "POST — emitted Catala is pure and self-contained (§5.1)"
  Env{}        -> "an environment lookup — emitted Catala is pure and self-contained (§5.1)"
  Breach{}     -> "BREACH — Catala models no deontic layer (§5.1)"
  RAnd{}       -> "regulative AND — Catala models no deontic layer (§5.1)"
  ROr{}        -> "regulative OR — Catala models no deontic layer (§5.1)"
  Record{}     -> "a ledger RECORD/COMMIT — Catala is pure (§5.1)"
  ReadCell{}   -> "a ledger RECALL — Catala is pure (§5.1)"
  Lam{}        -> "a lambda outside a combinator argument; only combinator absorption survives \
                  \(R5, §8.5)"
  Concat{}     -> "string concatenation — Catala has no string type (§4.8)"
  AsString{}   -> "a string coercion — Catala has no string type (§4.8)"
  _            -> "an expression form with no Catala counterpart"

-- ---------------------------------------------------------------------------
-- Module scanning
-- ---------------------------------------------------------------------------

topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls = map snd . topDeclsWithPath

-- | Every top-level declaration, paired with the titles of the @§@ sections
-- enclosing it, outermost first. R8 turns that path into Markdown headings.
topDeclsWithPath :: Module Resolved -> [([Text], TopDecl Resolved)]
topDeclsWithPath (MkModule _ _ section) = goSection [] section
 where
  goSection path (MkSection _ mname _ ds) =
    let path' = case Text.strip . resolvedToText <$> mname of
          Just t | not (Text.null t) -> path <> [t]
          _                          -> path
    in ds >>= \d -> case d of
         Section _ sub -> goSection path' sub
         other         -> [(path', other)]

-- | Every type declared in the module, keyed by unique.
collectTypeNames :: Module Resolved -> Map Unique Text
collectTypeNames mod' = Map.fromList
  [ (getUnique tyRes, catUpper (resolvedToText tyRes))
  | Declare _ (MkDeclare _ _ (MkAppForm _ tyRes _ _) _) <- topDecls mod'
  ]

-- | Record declarations, keyed by /both/ the type's unique and its
-- constructor's, so a construction site resolves whichever the parser produced.
collectRecords :: Module Resolved -> Map Unique RecordInfo
collectRecords mod' = Map.fromList $ concat
  [ (getUnique tyRes, ri) : [ (getUnique c, ri) | c <- maybeToList mCon ]
  | Declare _ d@(MkDeclare _ _ (MkAppForm _ tyRes _ _) (RecordDecl _ mCon fields)) <- topDecls mod'
  , let ri = RecordInfo
               { riName   = catUpper (resolvedToText tyRes)
               , riL4     = resolvedToText tyRes
               , riDesc   = descOfDeclare d
               , riFields = map fieldOf fields
               }
  ]
 where
  fieldOf tn@(MkTypedName _ fRes ty _ mMeans) =
    RecField (catIdent (resolvedToText fRes)) (resolvedToText fRes) (getUnique fRes)
             (statusOf ty mMeans) (descOfAnno (getAnno tn))
  statusOf ty mMeans
    | isJust mMeans   = FElidedComputed
    | isStringType ty = FElidedString
    | otherwise       = case runV (lowerTypeBare ty) of
        Right t -> FEmitted t
        Left es -> FUnsupported (Text.intercalate "; " [ x.errMsg | x <- es ])

-- | Enumeration declarations. A constructor carrying more than one payload has
-- no Catala shape (@content@ takes exactly one type), so it is an error.
collectEnums :: Module Resolved -> V [CatEnum]
collectEnums mod' = vList
  [ CatEnum (catUpper (resolvedToText tyRes)) (resolvedToText tyRes) (descOfDeclare d)
      <$> vList (map (conCase (resolvedToText tyRes)) cons)
  | Declare _ d@(MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ cons)) <- topDecls mod'
  ]
 where
  conCase tyNm (MkConDecl _ c payload) =
    let cn = resolvedToText c
    in case payload of
      []                       -> pure (CatCase (catUpper cn) cn Nothing)
      [MkTypedName _ _ ty _ _] -> CatCase (catUpper cn) cn . Just <$> vIn tyNm (lowerTypeBare ty)
      _ -> vBad [LowerError tyNm Nothing
                  ("constructor `" <> cn <> "` carries " <> tshow (length payload)
                   <> " payload fields; Catala's `content` takes exactly one type "
                   <> "(declare a structure and carry that instead)")]

-- | Enum constructors, keyed by unique.
enumConstructors :: Module Resolved -> Map Unique ConInfo
enumConstructors mod' = Map.fromList
  [ ( getUnique c
    , ConInfo (catUpper (resolvedToText tyRes)) (catUpper (resolvedToText c))
              (resolvedToText c) (not (null payload)) )
  | Declare _ (MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ cons)) <- topDecls mod'
  , MkConDecl _ c payload <- cons
  ]

collectDecides :: Module Resolved -> Map Unique DecideInfo
collectDecides mod' = Map.fromList
  [ ( getUnique fnRes
    , DecideInfo
        { diUnique  = getUnique fnRes
        , diName    = resolvedToText fnRes
        , diGivens  = givens
        , diAppArgs = appArgs
        , diGiveth  = (\(MkGivethSig _ t) -> t) <$> mGiveth
        , diBody    = body
        , diNonexh  = isNonexhaustiveDecide d
        , diDesc    = descOfDecide d
          -- A leading @ref attaches to whichever node the resolver reached
          -- first, which for a DECIDE is the enclosing 'TopDecl' rather than
          -- the 'Decide' itself; check both, as 'L4.Dmn.Lower' does.
        , diRef     = refOfAnno tdAnn <|> refOfAnno (getAnno d)
        , diRange   = rangeOf d
        } )
  | Decide tdAnn d@(MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth)
                              (MkAppForm _ fnRes appArgs _) body) <- topDecls mod'
  ]

collectAssumes :: Module Resolved -> Map Unique AssumeInfo
collectAssumes mod' = Map.fromList
  [ ( getUnique nRes
    , AssumeInfo
        { aiName  = catIdent (resolvedToText nRes)
        , aiL4    = resolvedToText nRes
        , aiType  = mTy <|> ((\(MkGivethSig _ t) -> t) <$> mGiveth)
        , aiRange = rangeOf a
        } )
  | Assume _ a@(MkAssume _ (MkTypeSig _ _ mGiveth) (MkAppForm _ nRes _ _) mTy _) <- topDecls mod'
  ]

-- | The @\@desc@ text of a declaration, with the leading flag keywords stripped.
descOfDeclare :: Declare Resolved -> Maybe Text
descOfDeclare = descOfAnno . getAnno

descOfDecide :: Decide Resolved -> Maybe Text
descOfDecide = descOfAnno . getAnno

descOfAnno :: Anno -> Maybe Text
descOfAnno a = case a ^. annDesc of
  Nothing   -> Nothing
  Just desc -> let ParsedDesc _ t = parseDescText (getDesc desc)
               in if Text.null t then Nothing else Just t

-- | The @\@ref@ citation attached to a declaration, if any (R8).
refOfAnno :: Anno -> Maybe Text
refOfAnno a = case a ^. annRef of
  Nothing -> Nothing
  Just r  -> let t = stripKeyword (Text.strip (getRef r))
             in if Text.null t then Nothing else Just t
 where
  -- 'getRef' keeps the annotation keyword the citation was written with.
  stripKeyword t = case [ rest | k <- ["@ref-src", "@ref-map", "@ref"]
                               , Just rest <- [Text.stripPrefix k t] ] of
    (rest : _) -> Text.strip rest
    []         -> t

-- | A stable provenance string: the source file's basename, so emitted output
-- does not depend on the invocation path.
moduleSource :: Module Resolved -> Text
moduleSource (MkModule _ uri _) =
  let t = getUri (fromNormalizedUri uri)
  in case reverse (Text.splitOn "/" t) of
       (base : _) | not (Text.null base) -> base
       _                                 -> t

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ r _ _) _) = r

givenName :: OptionallyTypedName Resolved -> Resolved
givenName (MkOptionallyTypedName _ n _ _) = n

givenType :: OptionallyTypedName Resolved -> Maybe (Type' Resolved)
givenType (MkOptionallyTypedName _ _ t _) = t

givenTypically :: OptionallyTypedName Resolved -> Maybe (Expr Resolved)
givenTypically (MkOptionallyTypedName _ _ _ d) = d

givenText :: OptionallyTypedName Resolved -> Text
givenText = resolvedToText . givenName

-- | The name as written at this occurrence (aliases included).
resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

-- | The /defining/ name, stable across @AKA@ aliases.
canonText :: Resolved -> Text
canonText = rawNameToText . rawName . getOriginal

-- | The defining name with any section qualification dropped: this is what the
-- builtin, prelude-combinator and date recognisers match against, because a
-- prelude function reaches us as @Prelude.Numeric Aggregates.sum@.
plainName :: Resolved -> Text
plainName = unqualifiedRawNameToText . rawName . getOriginal

dropExt :: Text -> Text
dropExt t = case Text.breakOnEnd "." t of
  (before, _) | not (Text.null before) -> Text.dropEnd 1 before
  _                                    -> t

dedupOn :: Ord k => (a -> k) -> [a] -> [a]
dedupOn key = go Set.empty
 where
  go _ [] = []
  go seen (x : xs)
    | k `Set.member` seen = go seen xs
    | otherwise           = x : go (Set.insert k seen) xs
    where k = key x

-- | Kahn's algorithm; returns the still-blocked keys on a cycle.
topoSort :: Ord k => [(k, Set k, a)] -> Either [k] [a]
topoSort = go []
 where
  go acc [] = Right (reverse acc)
  go acc pending =
    let keys  = Set.fromList [ k | (k, _, _) <- pending ]
        ready = [ n | n@(_, ds, _) <- pending, Set.null (Set.intersection ds keys) ]
    in case ready of
      [] -> Left [ k | (k, _, _) <- pending ]
      _  -> let readyKeys = Set.fromList [ k | (k, _, _) <- ready ]
            in go (reverse [ a | (_, _, a) <- ready ] <> acc)
                  [ n | n@(k, _, _) <- pending, not (Set.member k readyKeys) ]

tshow :: Show a => a -> Text
tshow = Text.pack . show
