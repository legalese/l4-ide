-- | The agreement corpus, @jl4/examples/agreement/@, and what core makes of
-- it: each file's "agreement:" lines read into rules and their cases, the
-- call each case makes, and core's verdict on each directive of a file.
module Agreement.Corpus
  ( Subject (..)
  , Rule (..)
  , Case (..)
  , Expect (..)
  , HeaderError (..)
  , readCorpus
  , helperFiles
  , CoreRun (..)
  , CoreRule (..)
  , Directive (..)
  , runCore
  , evalSource
  , traceSource
  , Call (..)
  , callsOf
  , quoteName
  , coreRule
  , boolAssignments
  , PlanRow (..)
  , planRows
  , isAssert
  , sourceLines
  ) where

import Agreement.Verdict

import Control.Monad (foldM, forM)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import Data.List (nub, sort, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Scientific as Scientific
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (listDirectory)
import System.FilePath (takeBaseName, takeExtension, (</>))

import L4.API.VirtualFS (ResolvedImport (..), TypeCheckWithDepsResult (..), checkWithImportsAndUri, extractImportNames, vfsFromList)
import L4.Annotation (rangeOfNode)
import qualified L4.EvaluateLazy as EL
import L4.Evaluate.ValueLazy (Environment)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Print (extractConstructorFieldNames)
import L4.Refusal (PlanDecline, planDecline, refusalReasons)
import L4.Syntax hiding (Directive)
import L4.TracePolicy (lspDefaultPolicy)
import L4.TypeCheck (severity)
import L4.TypeCheck.Types (CheckResult (..), Severity (..))

-- | A file of the corpus that has "agreement:" lines, or the copy of one
-- whose lines end in CRLF.
data Subject = MkSubject
  { file :: FilePath
  -- ^ its name in the corpus directory
  , moduleName :: T.Text
  , source :: T.Text
  , crlf :: Bool
  , alsoCrlf :: Bool
  , rules :: [Rule]
  }

data Rule = MkRule
  { name :: T.Text
  , mayRefuse :: Maybe [T.Text]
  , plannedFromInputs :: Bool
  , cases :: [Case]
  }

data Case = MkCase
  { inputs :: [(T.Text, Aeson.Value)]
  , expect :: Expect
  , header :: T.Text
  }

data HeaderError = MkHeaderError FilePath T.Text String
  deriving stock (Show)

data HeaderItem
  = AlsoCrlf
  | MayRefuse T.Text [T.Text]
  | PlannedFromInputs T.Text
  | CaseLine T.Text Case

-- | Every file of the corpus, read: the subjects (a file with "agreement:"
-- lines, and the CRLF copy of one that asks for it), the helpers (a file with
-- none), and the lines that could not be read.
readCorpus :: FilePath -> IO ([Subject], [(FilePath, T.Text)], [HeaderError])
readCorpus dir = do
  names <- sort . filter ((== ".l4") . takeExtension) <$> listDirectory dir
  read' <- forM names \n -> do
    src <- TE.decodeUtf8 <$> BS.readFile (dir </> n)
    pure (n, src)
  let parsed =
        [ (n, src, [parseHeaderLine l | l <- mapMaybe (T.stripPrefix "-- agreement: ") (T.lines src)])
        | (n, src) <- read'
        ]
      errors = [MkHeaderError n l e | (n, _, items) <- parsed, Left (l, e) <- items]
      subjects =
        concat
          [ let s = MkSubject
                  { file = n
                  , moduleName = T.pack (takeBaseName n)
                  , source = src
                  , crlf = False
                  , alsoCrlf = any isAlsoCrlf oks
                  , rules = groupRules oks
                  }
                twin = MkSubject
                  { file = takeBaseName n <> "-crlf.l4"
                  , moduleName = T.pack (takeBaseName n) <> "-crlf"
                  , source = T.replace "\n" "\r\n" src
                  , crlf = True
                  , alsoCrlf = False
                  , rules = s.rules
                  }
             in s : [twin | s.alsoCrlf]
          | (n, src, items) <- parsed
          , let oks = [i | Right i <- items]
          , not (null items)
          ]
      helpers = [(n, src) | (n, src, []) <- parsed]
  pure (subjects, helpers, errors)
 where
  isAlsoCrlf = \case
    AlsoCrlf -> True
    _ -> False

-- | The files of the corpus with no "agreement:" line.
helperFiles :: [(FilePath, T.Text)] -> [FilePath]
helperFiles = map fst

groupRules :: [HeaderItem] -> [Rule]
groupRules items =
  [ MkRule
      { name = n
      , mayRefuse = case [rs | MayRefuse m rs <- items, m == n] of
          rs : _ -> Just rs
          [] -> Nothing
      , plannedFromInputs = or [True | PlannedFromInputs m <- items, m == n]
      , cases = [c | CaseLine m c <- items, m == n]
      }
  | n <- nub (mapMaybe ruleOf items)
  ]
 where
  ruleOf = \case
    AlsoCrlf -> Nothing
    MayRefuse n _ -> Just n
    PlannedFromInputs n -> Just n
    CaseLine n _ -> Just n

parseHeaderLine :: T.Text -> Either (T.Text, String) HeaderItem
parseHeaderLine l
  | l == "also run with CRLF line endings" = Right AlsoCrlf
  | otherwise = either (\e -> Left (l, e)) Right do
      (n, rest0) <- ruleName l
      let rest = T.strip rest0
      case T.stripPrefix "may refuse with " rest of
        Just rs -> MayRefuse n <$> decodeText rs
        Nothing
          | rest == "is planned from its inputs" -> Right (PlannedFromInputs n)
          | otherwise -> case T.breakOn " => " rest of
              (obj, arrow) | not (T.null arrow) -> do
                given <- decodeText obj :: Either String Aeson.Object
                ex <- parseExpect (T.drop 4 arrow)
                Right (CaseLine n MkCase {inputs = [(Key.toText k, v) | (k, v) <- KeyMap.toList given], expect = ex, header = l})
              _ -> Left "expected \"may refuse with\", \"is planned from its inputs\", or inputs and \"=>\""
 where
  ruleName t = case T.stripPrefix "`" t of
    Just rest -> case T.breakOn "`" rest of
      (n, close) | not (T.null close) -> Right (n, T.drop 1 close)
      _ -> Left "a rule name opened with ` and not closed"
    Nothing -> case T.break (== ' ') t of
      (n, rest) | not (T.null n) -> Right (n, rest)
      _ -> Left "no rule name"
  parseExpect t
    | t == "answers cut short" = Right AnswersCutShort
    | t == "raises" = Right Raises
    | Just j <- T.stripPrefix "answers " t = Answers <$> decodeText j
    | Just j <- T.stripPrefix "refuses " t = Refuses <$> decodeText j
    | otherwise = Left "expected \"answers\", \"answers cut short\", \"refuses\" or \"raises\""
  decodeText :: Aeson.FromJSON a => T.Text -> Either String a
  decodeText = Aeson.eitherDecodeStrict . TE.encodeUtf8

-- | One call a case makes: the rule, the case, the text of the call, and the
-- line of the directive that makes it in the file 'evalSource' writes.
data Call = MkCall
  { rule :: Rule
  , theCase :: Case
  , text :: T.Text
  , args :: [T.Text]
  -- ^ the arguments as the call writes them
  , line :: Int
  , givens :: [T.Text]
  }

-- | The name as a call spells it.
quoteName :: T.Text -> T.Text
quoteName n = if T.any (== ' ') n then "`" <> n <> "`" else n

-- | The calls a subject's cases make, in order, with the inputs in the
-- order the rule's GIVEN has them, `pad` as NOTHING.
callsOf :: Subject -> Map.Map T.Text [T.Text] -> [Call]
callsOf s givenOf =
  [ MkCall {rule = r, theCase = c, text = T.unwords (quoteName r.name : as), args = as, line = sourceLines s + k, givens = gs}
  | (k, (r, c)) <- zip [1 ..] [(r, c) | r <- s.rules, c <- r.cases]
  , let gs = Map.findWithDefault [] r.name givenOf
        as = map (arg c) gs
  ]
 where
  arg c g
    | g == "pad" = "NOTHING"
    | otherwise = maybe "?" literal (lookup g c.inputs)
  literal = \case
    Aeson.Bool True -> "TRUE"
    Aeson.Bool False -> "FALSE"
    Aeson.Number n -> case Scientific.floatingOrInteger n :: Either Double Integer of
      Right i | i < 0 -> "(0 MINUS " <> T.pack (show (negate i)) <> ")"
      Right i -> T.pack (show i)
      Left d -> T.pack (show d)
    v -> T.pack (show v)

-- | How many lines the subject's text has, so the first directive
-- 'evalSource' adds is on the line after.
sourceLines :: Subject -> Int
sourceLines s = length (T.lines (withFinalNewline s))

withFinalNewline :: Subject -> T.Text
withFinalNewline s = if "\n" `T.isSuffixOf` s.source then s.source else s.source <> nl s

nl :: Subject -> T.Text
nl s = if s.crlf then "\r\n" else "\n"

-- | The subject's text with an #EVAL for each call after it.
evalSource :: Subject -> [Call] -> T.Text
evalSource s calls = withFinalNewline s <> T.concat ["#EVAL " <> c.text <> nl s | c <- calls]

-- | The subject's text with an #EVALTRACE for each call after it.
traceSource :: Subject -> [Call] -> T.Text
traceSource s calls = withFinalNewline s <> T.concat ["#EVALTRACE " <> c.text <> nl s | c <- calls]

-- | A directive of a file, at its line and column, with core's verdict.
data Directive = MkDirective
  { line :: Int
  , column :: Int
  , verdict :: CoreVerdict
  }

-- | What core reads of a rule: its inputs in order, whether it answers a
-- BOOLEAN, the reasons it may refuse with, its decline, and the line its
-- definition starts on.
data CoreRule = MkCoreRule
  { givens :: [T.Text]
  , boolean :: Bool
  , reasons :: [T.Text]
  , decline :: Maybe PlanDecline
  , startLine :: Maybe Int
  , returns :: Maybe T.Text
  -- ^ the name of the type it answers, if that is a type applied to others
  }

data CoreRun = MkCoreRun
  { directives :: [Directive]
  , rulesByName :: Map.Map T.Text CoreRule
  , imports :: [T.Text]
  }

-- | Check and evaluate a text as the subject's module, with every file of
-- the corpus beside it, each module on top of the modules it imports.
runCore :: [(T.Text, T.Text)] -> T.Text -> T.Text -> IO (Either [T.Text] CoreRun)
runCore vfsFiles modName src =
  case checkWithImportsAndUri (vfsFromList vfsFiles) modName src of
    Left errs -> pure (Left errs)
    Right result
      | any ((== SError) . severity) result.tcdErrors -> pure (Left ["the module does not check"])
      | otherwise -> do
          evalConfig <- EL.resolveEvalConfigWithSafeMode Nothing (lspDefaultPolicy defaultGraphVizOptions) True
          importEnv <- evalImports evalConfig result.tcdResolvedImports
          (_env, results) <- EL.execEvalModuleWithEnv evalConfig result.tcdEntityInfo importEnv result.tcdModule
          let fields = extractConstructorFieldNames result.tcdEntityInfo
              mods = result.tcdModule : map (\ri -> ri.riTypeChecked.program) result.tcdResolvedImports
              decides = foldTopLevelDecides (: []) result.tcdModule
          pure $ Right MkCoreRun
            { directives =
                sortOn (.line)
                  [ MkDirective {line = rng.start.line, column = rng.start.column, verdict = coreVerdict fields res}
                  | EL.MkEvalDirectiveResult (Just rng) res _ <- results
                  ]
            , rulesByName = Map.fromList [(decideName d, coreRule mods d) | d <- decides]
            , imports = map (.riModuleName) result.tcdResolvedImports
            }

-- | Evaluate each module a text imports, directly or through another, on
-- top of the modules it imports in turn, as the language server does
-- (GetLazyEvaluationDependenciesFile in LSP.L4.Rules), each once; and give
-- the environment of them all.
evalImports :: EL.EvalConfig -> [ResolvedImport] -> IO Environment
evalImports evalConfig ris = mconcat . Map.elems <$> foldM visit Map.empty (map (.riModuleName) ris)
 where
  byName = Map.fromList [(ri.riModuleName, ri) | ri <- ris]
  -- the environment of a module and of every module beneath it
  visit done n
    | Map.member n done = pure done
    | Just ri <- Map.lookup n byName = do
        let deps = extractImportNames ri.riParsed
        done' <- foldM visit done deps
        let depEnv = mconcat [e | d <- deps, Just e <- [Map.lookup d done']]
        (own, _) <- EL.execEvalModuleWithEnv evalConfig ri.riTypeChecked.entityInfo depEnv ri.riTypeChecked.program
        pure (Map.insert n (own <> depEnv) done')
    | otherwise = pure done

decideName :: Decide Resolved -> T.Text
decideName (MkDecide _ _ (MkAppForm _ n _ _) _) = rawNameToText (rawName (getActual n))

coreRule :: [Module Resolved] -> Decide Resolved -> CoreRule
coreRule mods d@(MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) giveth) _ _) =
  MkCoreRule
    { givens = [rawNameToText (rawName (getActual n)) | MkOptionallyTypedName _ n _ <- otns]
    , boolean = case giveth of
        Just (MkGivethSig _ (TyApp _ t [])) -> rawNameToText (rawName (getActual t)) == "BOOLEAN"
        _ -> False
    , reasons = Set.toList (refusalReasons mods d)
    , decline = planDecline mods d
    , startLine = (\r -> r.start.line) <$> rangeOfNode d
    , returns = case giveth of
        Just (MkGivethSig _ (TyApp _ t _)) -> Just (rawNameToText (rawName (getActual t)))
        _ -> Nothing
    }

-- | Every assignment of TRUE and FALSE to the inputs, pad aside.
boolAssignments :: [T.Text] -> [[(T.Text, Bool)]]
boolAssignments = \case
  [] -> [[]]
  g : gs -> [(g, b) : rest | b <- [True, False], rest <- boolAssignments gs]

-- | A question put to a query planner: a rule, and the inputs bound so far.
data PlanRow = MkPlanRow
  { rule :: Rule
  , bindings :: [(T.Text, Bool)]
  }

-- | The questions for each rule of a subject: the rule with nothing bound,
-- and, for a rule that answers a BOOLEAN, each case's inputs, pad aside.
planRows :: Subject -> Map.Map T.Text CoreRule -> [PlanRow]
planRows s byName =
  concat
    [ MkPlanRow r [] : if isBoolean then [MkPlanRow r (caseBindings c) | c <- r.cases] else []
    | r <- s.rules
    , let isBoolean = maybe False (.boolean) (Map.lookup r.name byName)
    ]
 where
  caseBindings c = [(k, b) | (k, Aeson.Bool b) <- c.inputs]

-- | Whether a line of the file 'evalSource' writes is one of the subject's
-- own, where its directives are its #ASSERTs.
isAssert :: Subject -> Int -> Bool
isAssert s l = l <= sourceLines s
