{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module ExportValidationSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Control.Monad (forM_)
import Test.Hspec
import Data.List (nubBy, sort)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import Optics (cosmosOf, foldMapOf, gplate, over, toListOf, (^.))
import System.Mem (getAllocationCounter)
import System.Timeout (timeout)

import L4.API (l4Check)
import L4.API.VirtualFS (VFS, checkWithImports, embeddedLibraryNames, emptyVFS, vfsFromList)
import L4.Annotation (getAnno)
import L4.Export (BodyReads(..), ExportedFunction(..), bodyReads, getExportedFunctions, enrichReturnTypes, isExportedDecide, validateExportInputs)
import L4.Import.Resolution (ResolvedImport(..), TypeCheckWithDepsResult(..))
import L4.Print (prettyTypeForDisplay)
import L4.Syntax (AppForm(MkAppForm), Assume, Decide(MkDecide), Expr(App, List, Proj, Where), Info(TypeInfo), LocalDecl(LocalAssume), Module, Resolved(Ref), TermKind(Constructor), Type', Unique(MkUnique), annInfo, getActual, nameToText)
import L4.TypeCheck (prettyCheckErrorWithContext, severity)
import L4.TypeCheck.Types (CheckEntity(KnownTerm), CheckErrorWithContext(..), CheckError(..), CheckResult(..), Severity(..))

-- | Run typecheck on a source snippet and return the list of
-- 'ExportFunctionTypeInput' errors that fired (or 'Left' on fatal failure).
exportFnErrors :: Text -> Either [Text] [CheckErrorWithContext]
exportFnErrors source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right
      [ e
      | e@MkCheckErrorWithContext{kind = ExportFunctionTypeInput _ _} <- r.tcdErrors
      ]

-- | Run typecheck on a source snippet and return the 'ExportEventTypeInput'
-- errors that fired, as (function name, input name) pairs, together with the
-- error text a user sees for the first of them. The snippet can import the
-- modules of the given VFS.
exportEventErrors :: VFS -> Text -> Either [Text] ([(Text, Text)], [Text])
exportEventErrors vfs source =
  case checkWithImports vfs source of
    Left errs -> Left errs
    Right r ->
      let hits =
            [ e
            | e@MkCheckErrorWithContext{kind = ExportEventTypeInput _ _ _} <- r.tcdErrors
            ]
      in Right
        ( [ (nameToText (getActual fn), nameToText (getActual p))
          | MkCheckErrorWithContext{kind = ExportEventTypeInput fn p _} <- hits
          ]
        , concatMap prettyCheckErrorWithContext (take 1 hits)
        )

-- | 'exportEventErrors' on a snippet with no imports, under a watchdog: the
-- walk over a type's fields once took a time that doubled with every level
-- of nesting, so a regression is reported as a failure and not as a hung
-- suite. The pairs only: (function, input).
refusedWithinWatchdog :: Text -> IO [(Text, Text)]
refusedWithinWatchdog src = do
  mb <- timeout (30 * 1000000) $ case exportEventErrors emptyVFS src of
    Left errs -> fail ("Fatal: " ++ show errs)
    Right (hits, _) -> evaluate (length hits) >> pure hits
  maybe (fail "the export check did not finish within 30s") pure mb

-- | The @export errors that say a DEONTIC cannot be an input, as (function,
-- input) pairs, together with the error text a user sees for the first of
-- them. They are told apart by that text, which is what an author reads, so
-- the examples below pin the wording as well as the refusal. The snippet can
-- import the modules of the given VFS.
exportDeonticErrors :: VFS -> Text -> Either [Text] ([(Text, Text)], [Text])
exportDeonticErrors vfs source =
  case checkWithImports vfs source of
    Left errs -> Left errs
    Right r ->
      let hits =
            [ shown
            | e <- r.tcdErrors
            , let shown = prettyCheckErrorWithContext e
            , any ((== "DEONTIC inputs are not supported for @export.") . Text.strip) shown
            ]
          -- the name between the first pair of backticks of the first line
          -- that holds the marker: the function in "...the definition of `f`:",
          -- the input in "The input `x` has a type ..."
          quoted marker ls = case filter (Text.isInfixOf marker) ls of
            (l : _) -> Text.takeWhile (/= '`') (Text.drop 1 (Text.dropWhile (/= '`') l))
            []      -> ""
      in Right
        ( [ (quoted "the definition of" shown, quoted "The input" shown) | shown <- hits ]
        , concat (take 1 hits)
        )

-- | 'exportDeonticErrors' on a snippet with no imports, under the same
-- watchdog as 'refusedWithinWatchdog'. The pairs only: (function, input).
deonticWithinWatchdog :: Text -> IO [(Text, Text)]
deonticWithinWatchdog src = do
  mb <- timeout (30 * 1000000) $ case exportDeonticErrors emptyVFS src of
    Left errs -> fail ("Fatal: " ++ show errs)
    Right (hits, _) -> evaluate (length hits) >> pure hits
  maybe (fail "the export check did not finish within 30s") pure mb

-- | The (function, input) pairs refused as an EVENT, then those refused as a
-- DEONTIC, for one source that can import the modules of the given VFS.
unsendableRefusals :: VFS -> Text -> IO ([(Text, Text)], [(Text, Text)])
unsendableRefusals vfs src = do
  events <- either (fail . ("Fatal: " <>) . show) (pure . fst) (exportEventErrors vfs src)
  duties <- either (fail . ("Fatal: " <>) . show) (pure . fst) (exportDeonticErrors vfs src)
  pure (events, duties)

-- | Whether the check of a source succeeded, and each refusal of an input that a
-- request has no JSON form for, as (what the input holds, function, input,
-- severity), in the order the checker reports them. The severity is the
-- checker's own ('severity'): only an 'SError' blocks a deploy, so a refusal
-- reported as anything less would pass every test that reads the text alone. The snippet can import the modules of the given VFS.
exportBlocks :: VFS -> Text -> IO (Bool, [(Text, Text, Text, Severity)])
exportBlocks vfs src =
  case checkWithImports vfs src of
    Left errs -> fail ("Fatal: " ++ show errs)
    Right r -> pure
      ( r.tcdSuccess
      , [ (what, nameToText (getActual fn), nameToText (getActual p), severity e)
        | e@(MkCheckErrorWithContext kind _) <- r.tcdErrors
        , (what, fn, p) <- case kind of
            ExportEventTypeInput f i _   -> [("EVENT", f, i)]
            ExportDeonticTypeInput f i _ -> [("DEONTIC", f, i)]
            _                          -> []
        ]
      )

-- | Whether the check of a source succeeded, and each refusal of an input that
-- a request has no JSON form for, as (what the input holds, function, input,
-- the rule that reads the input, severity), in the order the checker reports
-- them. The rule that reads the input is named when it is a rule that the
-- exported rule calls, and is empty when the exported rule reads the input
-- itself. All but the severity are read from the text that an author sees.
exportReaders :: Text -> IO (Bool, [(Text, Text, Text, Text, Severity)])
exportReaders = exportReadersWith emptyVFS

-- | 'exportReaders' of a snippet that can import the modules of the given VFS.
exportReadersWith :: VFS -> Text -> IO (Bool, [(Text, Text, Text, Text, Severity)])
exportReadersWith vfs src =
  case checkWithImports vfs src of
    Left errs -> fail ("Fatal: " ++ show errs)
    Right r -> pure
      ( r.tcdSuccess
      , [ (what, quotedAfter "the definition of" shown, quotedAfter "The input" shown, quotedAfter "is an ASSUME that" shown, severity e)
        | e <- r.tcdErrors
        , let shown = prettyCheckErrorWithContext e
        , (what, marker) <- [("EVENT", "EVENT inputs are not supported for @export."), ("DEONTIC", "DEONTIC inputs are not supported for @export.")]
        , any ((== marker) . Text.strip) shown
        ]
      )

-- | 'exportReaders' under the same watchdog as 'refusedWithinWatchdog', for a
-- source that the check must finish: one with rules that call each other, or
-- that many paths of calls reach. The refusals only, without the severity.
readersWithinWatchdog :: Text -> IO [(Text, Text, Text, Text)]
readersWithinWatchdog src = do
  mb <- timeout (30 * 1000000) $ do
    (_, hits) <- exportReaders src
    _ <- evaluate (force (map (\(what, fn, input, reader, _) -> (what, fn, input, reader)) hits))
    pure [ (what, fn, input, reader) | (what, fn, input, reader, _) <- hits ]
  maybe (fail "the export check did not finish within 30s") pure mb

-- | The name between the first pair of backticks that follows the marker, on
-- the first line that holds the marker, or nothing when no line holds it.
quotedAfter :: Text -> [Text] -> Text
quotedAfter marker ls = case filter (Text.isInfixOf marker) ls of
  (l : _) -> Text.takeWhile (/= '`') (Text.drop 1 (Text.dropWhile (/= '`') (snd (Text.breakOn marker l))))
  []      -> ""

-- | Run typecheck on a source snippet and return the exported function
-- names (or 'Left' on fatal failure).
exportedNames :: Text -> Either [Text] [Text]
exportedNames source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right $ map (.exportName) (getExportedFunctions r.tcdModule)

-- | Run typecheck and return the displayed return type of each export,
-- exactly as the deployed schema / LSP would render it.
exportedReturnTypes :: Text -> Either [Text] [(Text, Text)]
exportedReturnTypes source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r ->
      let exps = enrichReturnTypes r.tcdEntityInfo (getExportedFunctions r.tcdModule)
      in Right
        [ (ef.exportName, maybe "unknown" prettyTypeForDisplay ef.exportReturnType)
        | ef <- exps
        ]

-- | The (function, input) pairs that 'exportFnErrors' finds in a snippet.
refusedFunctionInputs :: Text -> Either [Text] [(Text, Text)]
refusedFunctionInputs source =
  fmap
    (\errs ->
      [ (nameToText (getActual fn), nameToText (getActual p))
      | MkCheckErrorWithContext{kind = ExportFunctionTypeInput fn p} <- errs
      ])
    (exportFnErrors source)

-- | A module whose exported rule, `the rule`, has the given body. The module
-- declares what the bodies of 'placesOfARead' use: two parties, two actions,
-- a record, a rule that takes a NUMBER, and the function-typed ASSUME `f`.
readsAt :: [Text] -> Text
readsAt body = Text.unlines (header ++ map ("  " <>) body)
 where
  header =
    [ "DECLARE Person IS ONE OF Alice, Bob"
    , "DECLARE Action IS ONE OF"
    , "  pay HAS amount IS A NUMBER"
    , "  deliver"
    , "DECLARE Box HAS v IS A NUMBER"
    , ""
    , "ASSUME f IS A FUNCTION FROM NUMBER TO NUMBER"
    , ""
    , "GIVEN m IS A NUMBER"
    , "GIVETH A NUMBER"
    , "double m MEANS m * 2"
    , ""
    , "@export The rule"
    , "GIVEN n IS A NUMBER"
    , "      a IS AN Action"
    , "      xs IS A LIST OF NUMBER"
    , "`the rule` n a xs MEANS"
    ]

-- | Each place in the body of a rule where an expression can stand, with a
-- body that calls the ASSUME `f` at that place and nowhere else.
placesOfARead :: [(Text, [Text])]
placesOfARead =
  [ ("the left of AND", ["f n > 0 AND TRUE"])
  , ("the right of AND", ["TRUE AND f n > 0"])
  , ("the left of OR", ["f n > 0 OR TRUE"])
  , ("the right of OR", ["TRUE OR f n > 0"])
  , ("the left of IMPLIES", ["f n > 0 IMPLIES TRUE"])
  , ("the right of IMPLIES", ["TRUE IMPLIES f n > 0"])
  , ("the left of EQUALS", ["f n EQUALS 1"])
  , ("the right of EQUALS", ["1 EQUALS f n"])
  , ("the operand of NOT", ["NOT (f n > 0)"])
  , ("the left of PLUS", ["f n PLUS 1"])
  , ("the right of PLUS", ["1 PLUS f n"])
  , ("the left of MINUS", ["f n MINUS 1"])
  , ("the right of MINUS", ["1 MINUS f n"])
  , ("the left of TIMES", ["f n TIMES 1"])
  , ("the right of TIMES", ["1 TIMES f n"])
  , ("the left of DIVIDED BY", ["f n DIVIDED BY 1"])
  , ("the right of DIVIDED BY", ["1 DIVIDED BY f n"])
  , ("the left of MODULO", ["f n MODULO 1"])
  , ("the right of MODULO", ["1 MODULO f n"])
  , ("the left of FOLLOWED BY", ["f n FOLLOWED BY xs"])
  , ("the right of FOLLOWED BY", ["0 FOLLOWED BY (LIST (f n))"])
  , ("the left of AT MOST", ["f n AT MOST 1"])
  , ("the right of AT MOST", ["1 AT MOST f n"])
  , ("the left of AT LEAST", ["f n AT LEAST 1"])
  , ("the right of AT LEAST", ["1 AT LEAST f n"])
  , ("the left of LESS THAN", ["f n LESS THAN 1"])
  , ("the right of LESS THAN", ["1 LESS THAN f n"])
  , ("the left of GREATER THAN", ["f n GREATER THAN 1"])
  , ("the right of GREATER THAN", ["1 GREATER THAN f n"])
  , ( "the left of RAND"
    , [ "(PARTY Alice MUST deliver WITHIN f n) RAND (PARTY Alice MUST deliver WITHIN 1)"
      ]
    )
  , ( "the right of RAND"
    , [ "(PARTY Alice MUST deliver WITHIN 1) RAND (PARTY Alice MUST deliver WITHIN f n)"
      ]
    )
  , ( "the left of ROR"
    , [ "(PARTY Alice MUST deliver WITHIN f n) ROR (PARTY Alice MUST deliver WITHIN 1)"
      ]
    )
  , ( "the right of ROR"
    , [ "(PARTY Alice MUST deliver WITHIN 1) ROR (PARTY Alice MUST deliver WITHIN f n)"
      ]
    )
  , ("the record of a field read", ["(Box WITH v IS f n)'s v"])
  , ("the body of a lambda", ["g n", "WHERE", "  g MEANS GIVEN x YIELD f x"])
  , ("the argument of a call", ["double (f n)"])
  , ("a named argument", ["Box WITH v IS f n"])
  , ("the condition of IF", ["IF f n > 0 THEN 1 ELSE 2"])
  , ("the THEN of IF", ["IF TRUE THEN f n ELSE 2"])
  , ("the ELSE of IF", ["IF TRUE THEN 1 ELSE f n"])
  , ("the condition of a BRANCH", ["BRANCH", "  IF f n > 0 THEN 1", "  OTHERWISE 2"])
  , ("the value of a BRANCH", ["BRANCH", "  IF TRUE THEN f n", "  OTHERWISE 2"])
  , ("the OTHERWISE of a BRANCH", ["BRANCH", "  IF TRUE THEN 1", "  OTHERWISE f n"])
  , ("what CONSIDER looks at", ["CONSIDER f n", "  WHEN 1 THEN 2", "  OTHERWISE 3"])
  , ("the THEN of a WHEN", ["CONSIDER n", "  WHEN 1 THEN f n", "  OTHERWISE 3"])
  , ("the OTHERWISE of CONSIDER", ["CONSIDER n", "  WHEN 1 THEN 2", "  OTHERWISE f n"])
  , ("an EXACTLY pattern", ["CONSIDER n", "  WHEN EXACTLY f n THEN 1", "  OTHERWISE 2"])
  , ( "an argument of a constructor pattern"
    , [ "CONSIDER a"
      , "  WHEN pay EXACTLY f n THEN 1"
      , "  OTHERWISE 2"
      ]
    )
  , ( "the left of a FOLLOWED BY pattern"
    , [ "CONSIDER xs"
      , "  WHEN (EXACTLY f n) FOLLOWED BY rest THEN 1"
      , "  OTHERWISE 2"
      ]
    )
  , ( "the right of a FOLLOWED BY pattern"
    , [ "CONSIDER xs"
      , "  WHEN x FOLLOWED BY (EXACTLY (LIST (f n))) THEN 1"
      , "  OTHERWISE 2"
      ]
    )
  , ("the party of a duty", ["PARTY (IF f n > 0 THEN Alice ELSE Bob)", "MUST deliver", "WITHIN 1"])
  , ("the action of a duty", ["PARTY Alice", "MUST pay EXACTLY f n", "WITHIN 1"])
  , ("the PROVIDED of a duty", ["PARTY Alice", "MUST pay k PROVIDED k = f n", "WITHIN 1"])
  , ("the WITHIN of a duty", ["PARTY Alice", "MUST deliver", "WITHIN f n"])
  , ( "the HENCE of a duty"
    , [ "PARTY Alice"
      , "MUST deliver"
      , "WITHIN 1"
      , "HENCE (IF f n > 0 THEN FULFILLED ELSE BREACH)"
      ]
    )
  , ( "the LEST of a duty"
    , [ "PARTY Alice"
      , "MUST deliver"
      , "WITHIN 1"
      , "LEST (IF f n > 0 THEN FULFILLED ELSE BREACH)"
      ]
    )
  , ( "the BY of a BREACH"
    , [ "PARTY Alice"
      , "MUST deliver"
      , "WITHIN 1"
      , "LEST BREACH BY (IF f n > 0 THEN Alice ELSE Bob)"
      ]
    )
  , ( "the BECAUSE of a BREACH"
    , [ "PARTY Alice"
      , "MUST deliver"
      , "WITHIN 1"
      , "LEST BREACH BECAUSE ((f n) AS STRING)"
      ]
    )
  , ("the party of an event", ["PARTY (IF f n > 0 THEN Alice ELSE Bob) DOES deliver AT 1"])
  , ("the action of an event", ["PARTY Alice DOES pay (f n) AT 1"])
  , ("the time of an event", ["PARTY Alice DOES deliver AT f n"])
  , ("a percentage", ["f n %"])
  , ("an element of a LIST", ["LIST 1, f n"])
  , ("what a WHERE qualifies", ["f n", "WHERE", "  k MEANS 1"])
  , ("a definition under WHERE", ["k", "WHERE", "  k MEANS f n"])
  , ("a definition under LET", ["LET", "  k IS f n", "IN k"])
  , ("what a LET qualifies", ["LET", "  k IS 1", "IN f k"])
  , ("the address of a FETCH", ["FETCH ((f n) AS STRING)"])
  , ("the name of an ENV", ["ENV ((f n) AS STRING)"])
  , ("the address of a POST", ["POST ((f n) AS STRING) \"h\" \"b\""])
  , ("the headers of a POST", ["POST \"u\" ((f n) AS STRING) \"b\""])
  , ("the body of a POST", ["POST \"u\" \"h\" ((f n) AS STRING)"])
  , ("a part of a CONCAT", ["CONCAT \"a\", ((f n) AS STRING)"])
  , ("the operand of AS STRING", ["(f n) AS STRING"])
  ]

-- | The three lists of 'BodyReads' as a generic traversal of the syntax tree
-- ('gplate') finds them. It meets an expression before the expressions inside
-- it, and those in the order of the fields that hold them, which is the order
-- that 'bodyReads' documents.
genericBodyReads :: Expr Resolved -> ([Resolved], [(Resolved, Type' Resolved)], [Assume Resolved])
genericBodyReads body =
  ( foldMapOf everyExpr reference body
  , foldMapOf everyExpr readType body
  , foldMapOf everyExpr declaredHere body
  )
 where
  everyExpr = cosmosOf (gplate @(Expr Resolved))
  reference = \case
    App _ ref@Ref{} _ -> [ref]
    Proj _ _ ref@Ref{} -> [ref]
    _ -> []
  readType = \case
    App ann ref@Ref{} [] | Just (TypeInfo ty _) <- ann ^. annInfo -> [(ref, ty)]
    _ -> []
  declaredHere = \case
    Where _ _ decls -> [ assume | LocalAssume _ assume <- decls ]
    _ -> []

-- | The rules of a module: every DECIDE that does not stand inside another.
rulesOf :: Module Resolved -> [Decide Resolved]
rulesOf = toListOf (gplate @(Decide Resolved))

-- | Each rule of a module in whose body 'bodyReads' finds something else, or in
-- another order, than 'genericBodyReads': the name of the rule, and the names
-- of the lists that differ.
walkDisagreements :: Module Resolved -> [(Text, [Text])]
walkDisagreements m =
  [ (nameToText (getActual name), differs)
  | MkDecide _ _ (MkAppForm _ name _ _) body <- rulesOf m
  , let found = bodyReads body
        (refs, readsFound, locals) = genericBodyReads body
        differs =
          [ "references" | found.references /= refs ]
          <> [ "readTypes" | found.readTypes /= readsFound ]
          <> [ "localAssumes" | found.localAssumes /= locals ]
  , not (null differs)
  ]

-- | How many references the walk finds in the bodies of the rules of a module,
-- so that an example can tell that it compared some.
referencesWalked :: Module Resolved -> Int
referencesWalked m = sum [ length (bodyReads body).references | MkDecide _ _ _ body <- rulesOf m ]

-- | 'walkDisagreements' of a source that can import the libraries that come
-- with L4, with the number of rules and of references that it compared.
walkDisagreementsOf :: Text -> IO ([(Text, [Text])], Int, Int)
walkDisagreementsOf src = case checkWithImports emptyVFS src of
  Left errs -> fail ("Fatal: " ++ show errs)
  Right r -> pure (walkDisagreements r.tcdModule, length (rulesOf r.tcdModule), referencesWalked r.tcdModule)

spec :: Spec
spec = do
  describe "@export detection" $ do
    it "detects @export when it sits immediately above the function" $ do
      let src = Text.unlines
            [ "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right ["adult"]

    it "detects @export when followed by @desc rows before the function" $ do
      let src = Text.unlines
            [ "@export Check age"
            , "@desc Some description for the function"
            , "@desc Another description line"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right ["adult"]

    it "detects @export with @desc lines both before and after the export line" $ do
      let src = Text.unlines
            [ "@desc Pre-export description"
            , "@export Check age"
            , "@desc Post-export description"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right ["adult"]

    it "does not treat a plain @desc as an export" $ do
      let src = Text.unlines
            [ "@desc Just a description"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF 18 >= 18"
            ]
      exportedNames src `shouldBe` Right []

  describe "validateExportInputs" $ do
    it "rejects @export with a function-typed GIVEN parameter" $ do
      let src = Text.unlines
            [ "@export Apply the predicate"
            , "GIVEN `p` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_given_test` IF `p` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    it "rejects @export that references a function-typed ASSUME" $ do
      let src = Text.unlines
            [ "ASSUME `pred` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , ""
            , "@export Apply assumed predicate"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_assume_test` IF `pred` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    -- `n's f` is a call of f with n as its one input, as `f n` is.
    it "rejects @export that calls a function-typed ASSUME with 's after its input" $ do
      let src = Text.unlines
            [ "ASSUME bump IS A FUNCTION FROM NUMBER TO NUMBER"
            , ""
            , "@export Bump a number, by a call written with 's"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`bumped by genitive` n MEANS n's bump"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    it "accepts @export with only value-typed inputs" $ do
      let src = Text.unlines
            [ "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `adult` IF `age` >= 18"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> fns `shouldBe` []

    it "ignores function-typed ASSUMEs that aren't referenced by any export" $ do
      let src = Text.unlines
            [ "ASSUME `unused_fn` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "ASSUME `age` IS A NUMBER"
            , ""
            , "@export Check age"
            , "GIVETH A BOOLEAN"
            , "DECIDE `check_age` IF `age` >= 18"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> fns `shouldBe` []

    it "ignores function-typed GIVENs on non-@export DECIDEs" $ do
      let src = Text.unlines
            [ "GIVEN `p` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `internal_helper` IF `p` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> fns `shouldBe` []

    it "rejects MAYBE-wrapped function-typed GIVEN" $ do
      let src = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "@export With maybe callback"
            , "GIVEN `cb` IS A MAYBE OF FUNCTION FROM BOOLEAN TO BOOLEAN"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_maybe_test` IF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    it "rejects function-typed input via type synonym" $ do
      let src = Text.unlines
            [ "DECLARE `Pred` IS A FUNCTION FROM BOOLEAN TO BOOLEAN"
            , ""
            , "@export Via synonym"
            , "GIVEN `p` IS A `Pred`"
            , "GIVETH A BOOLEAN"
            , "DECIDE `fn_syn_test` IF `p` OF TRUE"
            ]
      case exportFnErrors src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right fns -> length fns `shouldBe` 1

    -- The check finds the ASSUMEs that an exported rule reads by walking the
    -- rule's body. Each body in 'placesOfARead' calls the function-typed ASSUME
    -- `f` at one place where an expression can stand and nowhere else, so a part
    -- of an expression that the walk passes over lets `f` through, and the
    -- failure names the place.
    it "refuses a function-typed ASSUME wherever in the body it is called" $ do
      let missed =
            [ place
            | (place, body) <- placesOfARead
            , refusedFunctionInputs (readsAt body) /= Right [("the rule", "f")]
            ]
      missed `shouldBe` []

  -- An EVENT has no JSON form: the service's input decoder reads an object
  -- only into a declared record, the builtin EVENT type has none, and so an
  -- exported rule that takes one publishes a bare @object@ schema that no
  -- request can satisfy. The check refuses it where it refuses a function-typed
  -- input, so that `l4 check`, `l4 batch`, `jl4-schema` and the service's
  -- deploy all stop at the same error.
  describe "EVENT-typed inputs of an @export" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        -- the pairs only: (function, input)
        refused vfs src = case exportEventErrors vfs src of
          Left errs -> fail $ "Fatal: " ++ show errs
          Right (hits, _) -> pure hits

    it "rejects a GIVEN of type EVENT, naming the function and the input" $ do
      let src = parties <> Text.unlines
            [ "@export When it happened"
            , "GIVEN `the reported event` IS AN EVENT Person Action"
            , "GIVETH A NUMBER"
            , "`when it happened` `the reported event` MEANS"
            , "  CONSIDER `the reported event`"
            , "  WHEN EVENT party action time THEN time"
            ]
      refused emptyVFS src `shouldReturn` [("when it happened", "the reported event")]

    it "says what is wrong and what to do instead" $ do
      let src = parties <> Text.unlines
            [ "@export When it happened"
            , "GIVEN e IS AN EVENT Person Action"
            , "GIVETH A NUMBER"
            , "`when it happened` e MEANS 1"
            ]
      case exportEventErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `when it happened`:"
            , "  EVENT inputs are not supported for @export."
            , "  The input `e` has a type that contains an EVENT, and a request has no JSON form for an event."
            , "  Give the rule the party, the action and the time as separate inputs, and build the event inside it."
            ]

    it "rejects a LIST OF EVENT" $ do
      let src = parties <> Text.unlines
            [ "@export Any events"
            , "GIVEN es IS A LIST OF EVENT Person Action"
            , "GIVETH A BOOLEAN"
            , "`any events` es MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("any events", "es")]

    it "rejects a MAYBE EVENT" $ do
      let src = parties <> Text.unlines
            [ "@export Maybe an event"
            , "GIVEN me IS A MAYBE (EVENT Person Action)"
            , "GIVETH A BOOLEAN"
            , "`maybe an event` me MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("maybe an event", "me")]

    it "rejects an EVENT under a FOR ALL" $ do
      -- `FOR ALL` is how a type that holds type variables is written out; the
      -- check looks through it, and the EVENT is no less an EVENT for it.
      let src = parties <> Text.unlines
            [ "@export Quantified"
            , "GIVEN q IS FOR ALL a (EVENT Person Action)"
            , "GIVETH A BOOLEAN"
            , "`quantified` q MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("quantified", "q")]

    it "accepts a FOR ALL that holds no EVENT" $ do
      let src = parties <> Text.unlines
            [ "@export Quantified"
            , "GIVEN q IS FOR ALL a LIST OF a"
            , "GIVETH A BOOLEAN"
            , "`quantified` q MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` []

    it "rejects an EVENT reached through a type synonym" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Occurrence IS AN EVENT Person Action"
            , ""
            , "@export Via synonym"
            , "GIVEN o IS AN Occurrence"
            , "GIVETH A BOOLEAN"
            , "`via synonym` o MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("via synonym", "o")]

    it "rejects an EVENT in a field of a record" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Report HAS reported IS AN EVENT Person Action"
            , "                   note IS A STRING"
            , ""
            , "@export Report note"
            , "GIVEN r IS A Report"
            , "GIVETH A STRING"
            , "`report note` r MEANS r's note"
            ]
      refused emptyVFS src `shouldReturn` [("report note", "r")]

    it "rejects an EVENT in a field of a constructor of a sum type" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Entry IS ONE OF"
            , "  unrecorded"
            , "  recorded HAS what IS AN EVENT Person Action"
            , ""
            , "@export Entry kind"
            , "GIVEN x IS AN Entry"
            , "GIVETH A BOOLEAN"
            , "`entry kind` x MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("entry kind", "x")]

    it "rejects an EVENT that sits behind a record of an imported module" $ do
      let lib = parties <> Text.unlines
            [ "DECLARE Report HAS reported IS AN EVENT Person Action"
            , ""
            , "DECLARE Occurrence IS AN EVENT Person Action"
            ]
          src = Text.unlines
            [ "IMPORT lib"
            , ""
            , "@export Report"
            , "GIVEN r IS A Report"
            , "GIVETH A BOOLEAN"
            , "`report` r MEANS TRUE"
            , ""
            , "@export Occurrence"
            , "GIVEN o IS AN Occurrence"
            , "GIVETH A BOOLEAN"
            , "`occurrence` o MEANS TRUE"
            ]
      refused (vfsFromList [("lib", lib)]) src
        `shouldReturn` [("report", "r"), ("occurrence", "o")]

    it "rejects an @export that uses an ASSUME of type EVENT" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `assumed event` IS AN EVENT Person Action"
            , ""
            , "@export Assumed"
            , "GIVETH A BOOLEAN"
            , "`assumed` MEANS"
            , "  CONSIDER `assumed event`"
            , "  WHEN EVENT party action time THEN TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("assumed", "assumed event")]

    it "ignores an ASSUME of type EVENT that no export uses" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `assumed event` IS AN EVENT Person Action"
            , ""
            , "@export Plain"
            , "GIVETH A BOOLEAN"
            , "`plain` MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` []

    it "reports each offending input, once" $ do
      let src = parties <> Text.unlines
            [ "@export Two events"
            , "GIVEN a IS AN EVENT Person Action"
            , "      b IS AN EVENT Person Action"
            , "      n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`two events` a b n MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("two events", "a"), ("two events", "b")]

    it "accepts a rule that takes an EVENT when it is not an @export" $ do
      let src = parties <> Text.unlines
            [ "GIVEN e IS AN EVENT Person Action"
            , "GIVETH A NUMBER"
            , "`when it happened` e MEANS"
            , "  CONSIDER e"
            , "  WHEN EVENT party action time THEN time"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts an @export that builds the event from its parts" $ do
      let src = parties <> Text.unlines
            [ "@export When it happened"
            , "GIVEN who IS A Person"
            , "      what IS AN Action"
            , "      `at time` IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`when it happened` who what `at time` MEANS"
            , "  CONSIDER EVENT who what `at time`"
            , "  WHEN EVENT party action time THEN time"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts an @export whose inputs are records, lists and maybes without an EVENT" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Report HAS who IS A Person"
            , "                   note IS A STRING"
            , "                   others IS A LIST OF Report"
            , ""
            , "@export Report note"
            , "GIVEN r IS A Report"
            , "      m IS A MAYBE NUMBER"
            , "GIVETH A STRING"
            , "`report note` r m MEANS r's note"
            ]
      refused emptyVFS src `shouldReturn` []

    it "terminates on a record that contains itself" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Tree HAS label IS A STRING"
            , "                 children IS A LIST OF Tree"
            , ""
            , "@export Label"
            , "GIVEN t IS A Tree"
            , "GIVETH A STRING"
            , "`label` t MEANS t's label"
            ]
      refused emptyVFS src `shouldReturn` []

    it "terminates on records that contain each other" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Ping HAS pong IS A MAYBE Pong"
            , "                 note IS A STRING"
            , "DECLARE Pong HAS ping IS A MAYBE Ping"
            , ""
            , "@export Note"
            , "GIVEN p IS A Ping"
            , "GIVETH A STRING"
            , "`note` p MEANS p's note"
            ]
      refused emptyVFS src `shouldReturn` []

    it "finds an EVENT in a record that is part of a cycle" $ do
      -- Both are asked for, from either end of the cycle: the EVENT is in a
      -- field of the type that the walk was already inside when it came back
      -- to it.
      let types = parties <> Text.unlines
            [ "DECLARE Ping HAS pong IS A MAYBE Pong"
            , "                 seen IS AN EVENT Person Action"
            , "DECLARE Pong HAS ping IS A MAYBE Ping"
            , ""
            ]
          export name input = Text.unlines
            [ "@export " <> name
            , "GIVEN x IS A " <> input
            , "GIVETH A BOOLEAN"
            , "`" <> name <> "` x MEANS TRUE"
            ]
      refused emptyVFS (types <> export "from ping" "Ping")
        `shouldReturn` [("from ping", "x")]
      refused emptyVFS (types <> export "from pong" "Pong")
        `shouldReturn` [("from pong", "x")]

    it "terminates on synonyms that name each other" $ do
      let src = parties <> Text.unlines
            [ "DECLARE SA IS A SB"
            , "DECLARE SB IS A SA"
            , ""
            , "@export Get"
            , "GIVEN t IS AN SA"
            , "GIVETH A NUMBER"
            , "`get` t MEANS 1"
            ]
      refused emptyVFS src `shouldReturn` []

    it "rejects an EVENT in any constructor of a sum type, the first included" $ do
      -- The constructors of a type are gathered into one list of field types.
      -- An EVENT in the first of them must count as much as one in the last.
      let sumType eventFirst = parties <> Text.unlines
            ( [ "DECLARE Entry IS ONE OF" ]
              <> (if eventFirst
                    then [ "  recorded HAS what IS AN EVENT Person Action"
                         , "  plain HAS n IS A NUMBER"
                         ]
                    else [ "  plain HAS n IS A NUMBER"
                         , "  recorded HAS what IS AN EVENT Person Action"
                         ]
                 )
              <> [ "  unrecorded"
                 , ""
                 , "@export Entry kind"
                 , "GIVEN x IS AN Entry"
                 , "GIVETH A BOOLEAN"
                 , "`entry kind` x MEANS TRUE"
                 ]
            )
      refused emptyVFS (sumType True) `shouldReturn` [("entry kind", "x")]
      refused emptyVFS (sumType False) `shouldReturn` [("entry kind", "x")]

    -- A chain of records in which each has TWO fields of the next one has
    -- 2^n paths from the first record to the last, though only n + 1 types.
    -- The check has to look at each type once, whichever way it got there.
    describe "a chain of records that doubles at every level" $ do
      let depth = 40 :: Int
          typeName i = "T" <> Text.pack (show i)
          chain leafField = Text.unlines $
            [ Text.unlines
                [ "DECLARE " <> typeName i <> " HAS"
                , "  f0 IS A " <> typeName (i + 1)
                , "  f1 IS A " <> typeName (i + 1)
                ]
            | i <- [0 .. depth - 1]
            ]
            <> [ "DECLARE " <> typeName depth <> " HAS " <> leafField ]
          exportFirst = Text.unlines
            [ "@export Chain"
            , "GIVEN t IS A T0"
            , "GIVETH A BOOLEAN"
            , "`chain` t MEANS TRUE"
            ]

      it "is checked in a moment when it holds no EVENT" $ do
        let src = parties <> chain "leaf IS A NUMBER" <> exportFirst
        refusedWithinWatchdog src `shouldReturn` []

      it "is refused when only the last record holds an EVENT" $ do
        let src = parties <> chain "leaf IS AN EVENT Person Action" <> exportFirst
        refusedWithinWatchdog src `shouldReturn` [("chain", "t")]

      it "still finds an EVENT in a later field once the chain has been walked" $ do
        -- The chain holds none. The EVENT is in a field that comes after the
        -- field that leads into the chain, and the last record of the chain
        -- refers back to the record that holds that field. So every record of
        -- the chain leads to the EVENT, but only through a record that the walk
        -- is still looking into, and the walk has been all through the chain
        -- before it gets there.
        let src = parties <> chain "back IS A Root" <> Text.unlines
              [ "DECLARE Root HAS"
              , "  first IS A T0"
              , "  second IS A Side"
              , ""
              , "DECLARE Side HAS later IS AN EVENT Person Action"
              , ""
              , "@export Root"
              , "GIVEN r IS A Root"
              , "GIVETH A BOOLEAN"
              , "`root` r MEANS TRUE"
              ]
        refusedWithinWatchdog src `shouldReturn` [("root", "r")]

  -- A DEONTIC has no JSON form either: a request can say a number, a string, a
  -- list or a record of the right shape, and none of them is a duty. An
  -- exported rule that takes one is refused where an EVENT input is, with its
  -- own words, so that `l4 check`, the editors, `jl4-schema` and the service's
  -- deploy all stop at the same error.
  describe "DEONTIC-typed inputs of an @export" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        -- the pairs only: (function, input)
        refused vfs src = case exportDeonticErrors vfs src of
          Left errs -> fail $ "Fatal: " ++ show errs
          Right (hits, _) -> pure hits
        -- one exported rule with one input `x` of the given type, that reads nothing
        export name input = Text.unlines
          [ "@export " <> name
          , "GIVEN x IS " <> input
          , "GIVETH A BOOLEAN"
          , "`" <> name <> "` x MEANS TRUE"
          ]

    it "rejects a GIVEN of type DEONTIC, naming the function and the input" $ do
      let src = parties <> Text.unlines
            [ "@export Is a duty already fulfilled"
            , "GIVEN `the duty` IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`already fulfilled` `the duty` MEANS"
            , "  CONSIDER `the duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refused emptyVFS src `shouldReturn` [("already fulfilled", "the duty")]

    it "says what is wrong and what to do instead" $ do
      let src = parties <> Text.unlines
            [ "@export Is a duty already fulfilled"
            , "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`already fulfilled` d MEANS TRUE"
            ]
      case exportDeonticErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `already fulfilled`:"
            , "  DEONTIC inputs are not supported for @export."
            , "  The input `d` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC."
            , "  Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it."
            ]

    it "rejects the older spelling PROVISION, which names the same type" $ do
      refused emptyVFS (parties <> export "old spelling" "A PROVISION Person Action")
        `shouldReturn` [("old spelling", "x")]

    it "rejects a LIST OF DEONTIC" $ do
      refused emptyVFS (parties <> export "any duties" "A LIST OF DEONTIC Person Action")
        `shouldReturn` [("any duties", "x")]

    it "rejects a MAYBE DEONTIC" $ do
      refused emptyVFS (parties <> export "maybe a duty" "A MAYBE (DEONTIC Person Action)")
        `shouldReturn` [("maybe a duty", "x")]

    it "rejects a DEONTIC under a FOR ALL" $ do
      refused emptyVFS (parties <> export "quantified" "FOR ALL a (DEONTIC Person Action)")
        `shouldReturn` [("quantified", "x")]

    it "rejects a DEONTIC reached through a type synonym" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Duty IS A DEONTIC Person Action"
            , ""
            ] <> export "via synonym" "A Duty"
      refused emptyVFS src `shouldReturn` [("via synonym", "x")]

    it "rejects a DEONTIC in a field of a record, whichever field it is" $ do
      let record fields = parties <> Text.unlines
            ( [ "DECLARE Agreement HAS" ]
              <> map ("  " <>) fields
              <> [ "" ]
            ) <> export "agreement title" "AN Agreement"
          title = "title IS A STRING"
          terms = "terms IS A DEONTIC Person Action"
          signed = "signed IS A BOOLEAN"
      refused emptyVFS (record [terms, title]) `shouldReturn` [("agreement title", "x")]
      refused emptyVFS (record [title, terms, signed]) `shouldReturn` [("agreement title", "x")]
      refused emptyVFS (record [title, terms]) `shouldReturn` [("agreement title", "x")]

    it "rejects a DEONTIC in any constructor of a sum type, the first included" $ do
      let sumType dutyFirst = parties <> Text.unlines
            ( [ "DECLARE Entry IS ONE OF" ]
              <> (if dutyFirst
                    then [ "  promised HAS what IS A DEONTIC Person Action"
                         , "  plain HAS n IS A NUMBER"
                         ]
                    else [ "  plain HAS n IS A NUMBER"
                         , "  promised HAS what IS A DEONTIC Person Action"
                         ]
                 )
              <> [ "  unrecorded"
                 , ""
                 ]
            ) <> export "entry kind" "AN Entry"
      refused emptyVFS (sumType True) `shouldReturn` [("entry kind", "x")]
      refused emptyVFS (sumType False) `shouldReturn` [("entry kind", "x")]

    it "rejects a DEONTIC that sits behind a record or a synonym of an imported module" $ do
      let lib = parties <> Text.unlines
            [ "DECLARE Agreement HAS terms IS A DEONTIC Person Action"
            , ""
            , "DECLARE Duty IS A DEONTIC Person Action"
            ]
          src = Text.unlines
            [ "IMPORT lib"
            , ""
            , "@export Agreement"
            , "GIVEN a IS AN Agreement"
            , "GIVETH A BOOLEAN"
            , "`agreement` a MEANS TRUE"
            , ""
            , "@export Duty"
            , "GIVEN d IS A Duty"
            , "GIVETH A BOOLEAN"
            , "`duty` d MEANS TRUE"
            ]
      refused (vfsFromList [("lib", lib)]) src
        `shouldReturn` [("agreement", "a"), ("duty", "d")]

    it "rejects an @export that uses an ASSUME of type DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `assumed duty` IS A DEONTIC Person Action"
            , ""
            , "@export Assumed"
            , "GIVETH A BOOLEAN"
            , "`assumed` MEANS"
            , "  CONSIDER `assumed duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refused emptyVFS src `shouldReturn` [("assumed", "assumed duty")]

    it "ignores an ASSUME of type DEONTIC that no export uses" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `assumed duty` IS A DEONTIC Person Action"
            , ""
            , "@export Plain"
            , "GIVETH A BOOLEAN"
            , "`plain` MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` []

    it "reports each offending input, once" $ do
      let src = parties <> Text.unlines
            [ "@export Two duties"
            , "GIVEN a IS A DEONTIC Person Action"
            , "      b IS A DEONTIC Person Action"
            , "      n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`two duties` a b n MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("two duties", "a"), ("two duties", "b")]

    it "refuses an EVENT input and a DEONTIC input of one rule, each with its own words" $ do
      let src = parties <> Text.unlines
            [ "@export Duty and event"
            , "GIVEN d IS A DEONTIC Person Action"
            , "      e IS AN EVENT Person Action"
            , "GIVETH A BOOLEAN"
            , "`duty and event` d e MEANS TRUE"
            ]
      refused emptyVFS src `shouldReturn` [("duty and event", "d")]
      case exportEventErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (hits, _) -> hits `shouldBe` [("duty and event", "e")]

    it "gives one refusal to an input that holds both an EVENT and a DEONTIC, for the first it meets" $ do
      -- A record's fields are read in the order they are written.
      let record dutyFirst = parties <> Text.unlines
            ( [ "DECLARE Case HAS" ]
              <> (if dutyFirst
                    then [ "  terms IS A DEONTIC Person Action"
                         , "  happened IS AN EVENT Person Action"
                         ]
                    else [ "  happened IS AN EVENT Person Action"
                         , "  terms IS A DEONTIC Person Action"
                         ]
                 )
              <> [ "" ]
            ) <> export "the case" "A Case"
          counts src = do
            deontic <- either (fail . show) (pure . fst) (exportDeonticErrors emptyVFS src)
            event <- either (fail . show) (pure . fst) (exportEventErrors emptyVFS src)
            pure (length deontic, length event)
      counts (record True) `shouldReturn` (1, 0)
      counts (record False) `shouldReturn` (0, 1)

    it "accepts a rule that gives a DEONTIC as its answer, from plain inputs" $ do
      let src = parties <> Text.unlines
            [ "@export The duty of a party"
            , "GIVEN who IS A Person"
            , "      what IS AN Action"
            , "      deadline IS A NUMBER"
            , "GIVETH A DEONTIC Person Action"
            , "`the duty` who what deadline MEANS"
            , "  PARTY who"
            , "  MUST EXACTLY what"
            , "  WITHIN deadline"
            , "  HENCE FULFILLED"
            , "  LEST BREACH"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts a rule that takes a DEONTIC when it is not an @export" $ do
      let src = parties <> Text.unlines
            [ "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`already fulfilled` d MEANS"
            , "  CONSIDER d"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts an @export whose inputs are records, lists and maybes without a DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Report HAS who IS A Person"
            , "                   note IS A STRING"
            , "                   others IS A LIST OF Report"
            , ""
            , "@export Report note"
            , "GIVEN r IS A Report"
            , "      m IS A MAYBE NUMBER"
            , "GIVETH A STRING"
            , "`report note` r m MEANS r's note"
            ]
      refused emptyVFS src `shouldReturn` []

    it "accepts the shape the DEONTIC page recommends: exported rules from plain facts, a helper that takes the DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "GIVEN duty IS A DEONTIC Person Action"
            , "      events IS A LIST OF EVENT Person Action"
            , "GIVETH A BOOLEAN"
            , "`is fulfilled by` duty events MEANS"
            , "  CONSIDER EVALTRACE duty 0 events"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , ""
            , "@export Is the duty fulfilled when the party takes the action on a given day"
            , "GIVEN who IS A Person"
            , "      what IS AN Action"
            , "      deadline IS A NUMBER"
            , "      `day taken` IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`duty fulfilled on day` who what deadline `day taken` MEANS"
            , "  `is fulfilled by` (`the duty` who what deadline) (LIST EVENT who what `day taken`)"
            , ""
            , "@export The duty of a party to take an action by a deadline"
            , "GIVEN who IS A Person"
            , "      what IS AN Action"
            , "      deadline IS A NUMBER"
            , "GIVETH A DEONTIC Person Action"
            , "`the duty` who what deadline MEANS"
            , "  PARTY who"
            , "  MUST EXACTLY what"
            , "  WITHIN deadline"
            , "  HENCE FULFILLED"
            , "  LEST BREACH"
            ]
      refused emptyVFS src `shouldReturn` []
      case exportEventErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (hits, _) -> hits `shouldBe` []

    it "accepts an input of a record the author declared, though its name suggests a DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Duty HAS who IS A Person"
            , "                 what IS AN Action"
            , ""
            ] <> export "a duty" "A Duty"
      refused emptyVFS src `shouldReturn` []

    it "terminates on records that contain each other, and finds a DEONTIC in the cycle" $ do
      let types holdDuty = parties <> Text.unlines
            [ "DECLARE Ping HAS pong IS A MAYBE Pong"
            , "                 " <> (if holdDuty then "seen IS A DEONTIC Person Action" else "note IS A STRING")
            , "DECLARE Pong HAS ping IS A MAYBE Ping"
            , ""
            ]
      refused emptyVFS (types False <> export "from ping" "A Ping") `shouldReturn` []
      refused emptyVFS (types True <> export "from ping" "A Ping")
        `shouldReturn` [("from ping", "x")]
      refused emptyVFS (types True <> export "from pong" "A Pong")
        `shouldReturn` [("from pong", "x")]

    -- The same walk as for an EVENT, so the same chain: 40 records that each
    -- have two fields of the next one, 2^40 paths, 41 types.
    describe "a chain of records that doubles at every level" $ do
      let depth = 40 :: Int
          typeName i = "T" <> Text.pack (show i)
          chain leafField = Text.unlines $
            [ Text.unlines
                [ "DECLARE " <> typeName i <> " HAS"
                , "  f0 IS A " <> typeName (i + 1)
                , "  f1 IS A " <> typeName (i + 1)
                ]
            | i <- [0 .. depth - 1]
            ]
            <> [ "DECLARE " <> typeName depth <> " HAS " <> leafField ]
          exportFirst = export "chain" "A T0"

      it "is checked in a moment when it holds no DEONTIC" $ do
        let src = parties <> chain "leaf IS A NUMBER" <> exportFirst
        deonticWithinWatchdog src `shouldReturn` []

      it "is refused when only the last record holds a DEONTIC" $ do
        let src = parties <> chain "leaf IS A DEONTIC Person Action" <> exportFirst
        deonticWithinWatchdog src `shouldReturn` [("chain", "x")]

  -- An input needs no written type: `GIVEN x` leaves it to the checker, which
  -- infers the type from how the rule uses x. A rule that passes x to a helper
  -- that takes a DEONTIC, or looks into it with CONSIDER, has an input of type
  -- DEONTIC all the same, and a request has no JSON form for it. The check
  -- takes the type of such an input from the type that the checker inferred for
  -- the rule.
  describe "an input of an @export that has no written type" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        dutyHelper = Text.unlines
          [ "GIVEN duty IS A DEONTIC Person Action"
          , "GIVETH A BOOLEAN"
          , "`already fulfilled` duty MEANS"
          , "  CONSIDER duty"
          , "  WHEN FULFILLED THEN TRUE"
          , "  OTHERWISE FALSE"
          , ""
          ]
        eventHelper = Text.unlines
          [ "GIVEN e IS AN EVENT Person Action"
          , "GIVETH A NUMBER"
          , "`time of` e MEANS"
          , "  CONSIDER e"
          , "  WHEN EVENT p a t THEN t"
          , ""
          ]
        refusals = unsendableRefusals emptyVFS

    it "rejects an input that is passed to a helper that takes a DEONTIC" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export Is a duty already fulfilled"
            , "GIVEN `the duty`"
            , "GIVETH A BOOLEAN"
            , "`is it fulfilled` `the duty` MEANS `already fulfilled` `the duty`"
            ]
      refusals src `shouldReturn` ([], [("is it fulfilled", "the duty")])

    it "rejects an input that the rule's own body takes apart as a DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "@export Is a duty already fulfilled"
            , "GIVEN `the duty`"
            , "GIVETH A BOOLEAN"
            , "`is it fulfilled` `the duty` MEANS"
            , "  CONSIDER `the duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refusals src `shouldReturn` ([], [("is it fulfilled", "the duty")])

    it "rejects an input that is passed to a helper that takes an EVENT" $ do
      let src = parties <> eventHelper <> Text.unlines
            [ "@export When it happened"
            , "GIVEN `the event`"
            , "GIVETH A NUMBER"
            , "`when` `the event` MEANS `time of` `the event`"
            ]
      refusals src `shouldReturn` ([("when", "the event")], [])

    it "rejects an input whose inferred type holds a DEONTIC in a list" $ do
      let src = parties <> Text.unlines
            [ "GIVEN ds IS A LIST OF DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`any duty` ds MEANS TRUE"
            , ""
            , "@export Any of the duties"
            , "GIVEN `the duties`"
            , "GIVETH A BOOLEAN"
            , "`any of them` `the duties` MEANS `any duty` `the duties`"
            ]
      refusals src `shouldReturn` ([], [("any of them", "the duties")])

    it "names the input and says what to do, in the words of a written type" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export Is a duty already fulfilled"
            , "GIVEN `the duty`"
            , "GIVETH A BOOLEAN"
            , "`is it fulfilled` `the duty` MEANS `already fulfilled` `the duty`"
            ]
      case exportDeonticErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `is it fulfilled`:"
            , "  DEONTIC inputs are not supported for @export."
            , "  The input `the duty` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC."
            , "  Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it."
            ]

    it "refuses each such input once, beside inputs that have a written type" $ do
      let src = parties <> dutyHelper <> eventHelper <> Text.unlines
            [ "@export Three inputs"
            , "GIVEN d"
            , "      n IS A NUMBER"
            , "      e"
            , "GIVETH A BOOLEAN"
            , "`three inputs` d n e MEANS"
            , "  `already fulfilled` d AND `time of` e EQUALS n"
            ]
      refusals src `shouldReturn` ([("three inputs", "e")], [("three inputs", "d")])

    it "finds the input of a rule that also takes a type parameter" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export With a type parameter"
            , "GIVEN a IS A TYPE"
            , "      `the duty`"
            , "      x IS AN a"
            , "GIVETH A BOOLEAN"
            , "`with a parameter` `the duty` x MEANS `already fulfilled` `the duty`"
            ]
      refusals src `shouldReturn` ([], [("with a parameter", "the duty")])

    it "accepts an input that is inferred to be a NUMBER" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export Plus one"
            , "GIVEN n"
            , "GIVETH A NUMBER"
            , "`plus one` n MEANS n + 1"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts an input whose type is left open" $ do
      let src = Text.unlines
            [ "@export Ignores its input"
            , "GIVEN x"
            , "GIVETH A BOOLEAN"
            , "`ignores` x MEANS TRUE"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts an input that is inferred to be a record that holds neither" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Report HAS who IS A Person"
            , "                   note IS A STRING"
            , ""
            , "GIVEN r IS A Report"
            , "GIVETH A STRING"
            , "`the note` r MEANS r's note"
            , ""
            , "@export Report note"
            , "GIVEN r"
            , "GIVETH A STRING"
            , "`report note` r MEANS `the note` r"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts a rule that is not an @export" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "GIVEN d"
            , "GIVETH A BOOLEAN"
            , "`internal` d MEANS `already fulfilled` d"
            ]
      refusals src `shouldReturn` ([], [])

    it "leaves the refusal of a function-typed input to written types, as before" $ do
      -- An input that the rule uses as a function, with no written type, is
      -- not refused as a function-typed input: only a written type is.
      let src = Text.unlines
            [ "@export Apply the predicate"
            , "GIVEN p"
            , "GIVETH A BOOLEAN"
            , "`apply` p MEANS p OF TRUE"
            ]
      exportFnErrors src `shouldBe` Right []

  -- A request cannot set an ASSUME that another module declares: the service
  -- publishes the ASSUMEs of the module itself as inputs, and no others. A rule
  -- that reads an ASSUME of type DEONTIC or EVENT from an imported module has
  -- no value for it, and answers as if it had a default. The check refuses it,
  -- as it refuses the same ASSUME declared in the module itself, whether the
  -- module imports the one that declares it, or imports one that imports it.
  describe "an @export that reads an ASSUME of an imported module" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        facts = parties <> Text.unlines
          [ "DECLARE Agreement HAS terms IS A DEONTIC Person Action"
          , ""
          , "ASSUME `imported duty` IS A DEONTIC Person Action"
          , "ASSUME `imported event` IS AN EVENT Person Action"
          , "ASSUME `imported agreement` IS AN Agreement"
          , "ASSUME `imported number` IS A NUMBER"
          , ""
          , "`standing duty` MEANS"
          , "  PARTY Seller"
          , "  MUST EXACTLY delivery"
          , "  WITHIN 10"
          , "  HENCE FULFILLED"
          , "  LEST BREACH"
          ]
        refusalsWith modules src =
          unsendableRefusals (vfsFromList modules) src
        refusals = refusalsWith [("facts", facts)]
        user body = Text.unlines (["IMPORT facts", ""] <> body)

    it "rejects an ASSUME of type DEONTIC that the body reads" $ do
      let src = user
            [ "@export Uses an imported assume"
            , "GIVETH A BOOLEAN"
            , "`uses imported assume` MEANS"
            , "  CONSIDER `imported duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refusals src `shouldReturn` ([], [("uses imported assume", "imported duty")])

    it "says what is wrong and what to do instead" $ do
      let src = user
            [ "@export Uses an imported assume"
            , "GIVETH A BOOLEAN"
            , "`uses imported assume` MEANS"
            , "  CONSIDER `imported duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      case exportDeonticErrors (vfsFromList [("facts", facts)]) src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `uses imported assume`:"
            , "  DEONTIC inputs are not supported for @export."
            , "  The input `imported duty` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC."
            , "  Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it."
            ]

    it "rejects an ASSUME of type EVENT that the body reads, in a local binding or as the answer" $ do
      let src = user
            [ "@export Reads an imported event"
            , "GIVETH A NUMBER"
            , "`reads imported event` MEANS 1"
            , "  WHERE e MEANS `imported event`"
            , ""
            , "@export Gives an imported event"
            , "GIVETH AN EVENT Person Action"
            , "`gives imported event` MEANS `imported event`"
            ]
      refusals src
        `shouldReturn`
          ( [("reads imported event", "imported event"), ("gives imported event", "imported event")]
          , []
          )

    it "rejects an ASSUME of a record type that holds a DEONTIC" $ do
      let src = user
            [ "@export Reads an imported agreement"
            , "GIVETH A BOOLEAN"
            , "`reads imported agreement` MEANS"
            , "  CONSIDER `imported agreement`'s terms"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refusals src `shouldReturn` ([], [("reads imported agreement", "imported agreement")])

    it "rejects an ASSUME that is imported through a module that imports it" $ do
      let middle = "IMPORT facts\n\nDECLARE Marker IS ONE OF one, two\n"
          src = Text.unlines
            [ "IMPORT middle"
            , ""
            , "@export Uses a chained assume"
            , "GIVETH A BOOLEAN"
            , "`uses chained assume` MEANS"
            , "  CONSIDER `imported duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refusalsWith [("facts", facts), ("middle", middle)] src
        `shouldReturn` ([], [("uses chained assume", "imported duty")])

    it "refuses an ASSUME that the body reads in two places once" $ do
      let src = user
            [ "@export Reads it twice"
            , "GIVETH A BOOLEAN"
            , "`reads it twice` MEANS"
            , "  CONSIDER `imported duty`"
            , "  WHEN FULFILLED THEN"
            , "    CONSIDER `imported duty`"
            , "    WHEN FULFILLED THEN TRUE"
            , "    OTHERWISE FALSE"
            , "  OTHERWISE FALSE"
            ]
      refusals src `shouldReturn` ([], [("reads it twice", "imported duty")])

    it "refuses the input with a written type and the ASSUME that it reads, each once" $ do
      let src = user
            [ "@export Both"
            , "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A NUMBER"
            , "`both` d MEANS"
            , "  CONSIDER `imported event`"
            , "  WHEN EVENT party action time THEN time"
            ]
      refusals src
        `shouldReturn` ([("both", "imported event")], [("both", "d")])

    it "accepts an ASSUME of type DEONTIC or EVENT that no export reads" $ do
      let src = user
            [ "@export Plain"
            , "GIVETH A BOOLEAN"
            , "`plain` MEANS TRUE"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts a rule that reads such an ASSUME when it is not an @export" $ do
      let src = user
            [ "`internal` MEANS"
            , "  CONSIDER `imported duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts an ASSUME of type NUMBER that the body reads" $ do
      let src = user
            [ "@export Uses an imported number"
            , "GIVETH A NUMBER"
            , "`uses imported number` MEANS `imported number` + 1"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts an ASSUME of a function type that the body calls, as the function-type check does" $ do
      -- No request can serve this rule: the ASSUME is a function that has no
      -- definition. The function-type check reads the written types and the
      -- ASSUMEs of the module itself, and the check for an EVENT or a DEONTIC
      -- goes by the type of the ASSUME and not by the type of a call of it, so
      -- neither refuses the rule. The documentation says so.
      let lib = parties <> Text.unlines
            [ "ASSUME `imported maker` IS A FUNCTION FROM NUMBER TO DEONTIC Person Action"
            ]
          src = Text.unlines
            [ "IMPORT lib"
            , ""
            , "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`fulfilled` d MEANS"
            , "  CONSIDER d"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , ""
            , "@export Reads the maker"
            , "GIVETH A BOOLEAN"
            , "`reads the maker` MEANS `fulfilled` (`imported maker` 3)"
            ]
      exportBlocks (vfsFromList [("lib", lib)]) src `shouldReturn` (True, [])

    it "accepts a DEONTIC that the module declares as a value, not as an ASSUME" $ do
      -- `standing duty` has a definition, so it is not an input of anything.
      let src = user
            [ "@export Is the standing duty fulfilled"
            , "GIVETH A BOOLEAN"
            , "`standing duty fulfilled` MEANS"
            , "  CONSIDER `standing duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      refusals src `shouldReturn` ([], [])

    it "accepts a DEONTIC that the same module declares as a value" $ do
      let src = parties <> Text.unlines
            [ "`standing duty` MEANS"
            , "  PARTY Seller"
            , "  MUST EXACTLY delivery"
            , "  WITHIN 10"
            , "  HENCE FULFILLED"
            , "  LEST BREACH"
            , ""
            , "@export Is the standing duty fulfilled"
            , "GIVETH A BOOLEAN"
            , "`standing duty fulfilled` MEANS"
            , "  CONSIDER `standing duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      unsendableRefusals emptyVFS src `shouldReturn` ([], [])

  -- An ASSUME needs no written type either: `ASSUME x` leaves the type to the
  -- checker, which works it out from how the file reads it. A rule that reads
  -- one as a DEONTIC or an EVENT has an input that a request cannot supply, as
  -- one with a written type has. Each example reads the whole answer of the
  -- check: whether it succeeded, and the severity of each refusal.
  describe "an @export that reads an ASSUME that has no written type" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        eventHelper = Text.unlines
          [ "GIVEN e IS AN EVENT Person Action"
          , "GIVETH A NUMBER"
          , "`time of` e MEANS"
          , "  CONSIDER e"
          , "  WHEN EVENT p a t THEN t"
          , ""
          ]

    it "blocks an ASSUME that the body takes apart as a DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `untyped assume`"
            , ""
            , "@export Reads untyped assume"
            , "GIVETH A BOOLEAN"
            , "`reads untyped assume` MEANS"
            , "  CONSIDER `untyped assume`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      exportBlocks emptyVFS src `shouldReturn`
        (False, [("DEONTIC", "reads untyped assume", "untyped assume", SError)])

    it "blocks an ASSUME that the body hands to a helper that takes an EVENT" $ do
      let src = parties <> eventHelper <> Text.unlines
            [ "ASSUME `untyped event`"
            , ""
            , "@export Reads untyped event"
            , "GIVETH A NUMBER"
            , "`reads untyped event` MEANS `time of` `untyped event`"
            ]
      exportBlocks emptyVFS src `shouldReturn`
        (False, [("EVENT", "reads untyped event", "untyped event", SError)])

    it "blocks an ASSUME that an imported module declares with no written type" $ do
      let facts = parties <> Text.unlines
            [ "ASSUME `imported untyped`"
            , ""
            , "GIVETH A BOOLEAN"
            , "`facts read it` MEANS"
            , "  CONSIDER `imported untyped`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
          src = Text.unlines
            [ "IMPORT facts"
            , ""
            , "@export Reads imported untyped"
            , "GIVETH A BOOLEAN"
            , "`reads imported untyped` MEANS"
            , "  CONSIDER `imported untyped`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
      exportBlocks (vfsFromList [("facts", facts)]) src `shouldReturn`
        (False, [("DEONTIC", "reads imported untyped", "imported untyped", SError)])

    it "accepts an ASSUME that the body reads as a NUMBER" $ do
      let src = Text.unlines
            [ "ASSUME `untyped number`"
            , ""
            , "@export Reads untyped number"
            , "GIVETH A NUMBER"
            , "`reads untyped number` MEANS `untyped number` + 1"
            ]
      exportBlocks emptyVFS src `shouldReturn` (True, [])

    it "accepts an ASSUME that is read as a DEONTIC only by a rule that is not an @export" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `untyped assume`"
            , ""
            , "GIVETH A BOOLEAN"
            , "`internal` MEANS"
            , "  CONSIDER `untyped assume`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , ""
            , "@export Plain"
            , "GIVETH A BOOLEAN"
            , "`plain` MEANS TRUE"
            ]
      exportBlocks emptyVFS src `shouldReturn` (True, [])

  -- A polymorphic ASSUME, `GIVEN a IS A TYPE GIVETH AN a ASSUME x`, has a
  -- declared type that holds neither a DEONTIC nor an EVENT: it holds one only
  -- where a rule reads it as one, and each read gives it a type of its own. The
  -- prelude's TBD is one. The check goes by the type at the read, so a read as a
  -- DEONTIC or an EVENT is refused, and a read as anything else is not.
  describe "an @export that reads a polymorphic ASSUME as a DEONTIC or an EVENT" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        dutyHelper = Text.unlines
          [ "GIVEN duty IS A DEONTIC Person Action"
          , "GIVETH A BOOLEAN"
          , "`fulfilled` duty MEANS"
          , "  CONSIDER duty"
          , "  WHEN FULFILLED THEN TRUE"
          , "  OTHERWISE FALSE"
          , ""
          ]
        eventHelper = Text.unlines
          [ "GIVEN e IS AN EVENT Person Action"
          , "GIVETH A NUMBER"
          , "`time of` e MEANS"
          , "  CONSIDER e"
          , "  WHEN EVENT p a t THEN t"
          , ""
          ]
        placeholder = Text.unlines
          [ "GIVEN a IS A TYPE"
          , "GIVETH AN a"
          , "ASSUME `local placeholder`"
          , ""
          ]
        withPrelude body = "IMPORT prelude\n" <> body
        blocks = exportBlocks emptyVFS

    it "blocks the prelude's TBD when the body hands it to a helper that takes a DEONTIC" $ do
      let src = withPrelude (parties <> dutyHelper <> Text.unlines
            [ "@export Reads tbd"
            , "GIVETH A BOOLEAN"
            , "`reads tbd` MEANS `fulfilled` TBD"
            ])
      blocks src `shouldReturn` (False, [("DEONTIC", "reads tbd", "TBD", SError)])

    it "blocks the prelude's TBD when the body takes it apart as a DEONTIC" $ do
      let src = withPrelude (parties <> Text.unlines
            [ "@export Reads tbd in a consider"
            , "GIVETH A BOOLEAN"
            , "`reads tbd in a consider` MEANS"
            , "  CONSIDER TBD"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            ])
      blocks src `shouldReturn` (False, [("DEONTIC", "reads tbd in a consider", "TBD", SError)])

    it "blocks the prelude's TBD when the body hands it to a helper that takes an EVENT" $ do
      let src = withPrelude (parties <> eventHelper <> Text.unlines
            [ "@export Reads tbd as an event"
            , "GIVETH A NUMBER"
            , "`reads tbd as an event` MEANS `time of` TBD"
            ])
      blocks src `shouldReturn` (False, [("EVENT", "reads tbd as an event", "TBD", SError)])

    it "blocks a polymorphic ASSUME of the module itself, as a DEONTIC and as an EVENT" $ do
      let duty = parties <> dutyHelper <> placeholder <> Text.unlines
            [ "@export Reads local placeholder"
            , "GIVETH A BOOLEAN"
            , "`reads local placeholder` MEANS `fulfilled` `local placeholder`"
            ]
          event = parties <> eventHelper <> placeholder <> Text.unlines
            [ "@export Reads local placeholder as an event"
            , "GIVETH A NUMBER"
            , "`reads local placeholder as an event` MEANS `time of` `local placeholder`"
            ]
      blocks duty `shouldReturn`
        (False, [("DEONTIC", "reads local placeholder", "local placeholder", SError)])
      blocks event `shouldReturn`
        (False, [("EVENT", "reads local placeholder as an event", "local placeholder", SError)])

    it "blocks a polymorphic ASSUME that the body reads as a list of duties" $ do
      let src = parties <> placeholder <> Text.unlines
            [ "GIVEN ds IS A LIST OF DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`any duty` ds MEANS TRUE"
            , ""
            , "@export Reads local placeholder as a list"
            , "GIVETH A BOOLEAN"
            , "`reads local placeholder as a list` MEANS `any duty` `local placeholder`"
            ]
      blocks src `shouldReturn`
        (False, [("DEONTIC", "reads local placeholder as a list", "local placeholder", SError)])

    it "refuses it once, however many times the body reads it" $ do
      let src = withPrelude (parties <> dutyHelper <> Text.unlines
            [ "@export Reads tbd twice"
            , "GIVETH A BOOLEAN"
            , "`reads tbd twice` MEANS `fulfilled` TBD AND `fulfilled` TBD"
            ])
      blocks src `shouldReturn` (False, [("DEONTIC", "reads tbd twice", "TBD", SError)])

    it "accepts the prelude's TBD when the body reads it as a NUMBER" $ do
      let src = withPrelude (Text.unlines
            [ "@export Reads tbd as a number"
            , "GIVETH A NUMBER"
            , "`reads tbd as a number` MEANS TBD + 1"
            ])
      blocks src `shouldReturn` (True, [])

    it "accepts a polymorphic ASSUME that the body reads as a NUMBER, whatever another rule reads it as" $ do
      -- Each read gives the ASSUME a type of its own, and the check looks at
      -- the reads in the body of the export only.
      let src = parties <> dutyHelper <> placeholder <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`internal` MEANS `fulfilled` `local placeholder`"
            , ""
            , "@export Reads local placeholder as a number"
            , "GIVETH A NUMBER"
            , "`reads local placeholder as a number` MEANS `local placeholder` + 1"
            ]
      blocks src `shouldReturn` (True, [])

    it "accepts a polymorphic ASSUME whose type at the read is left open" $ do
      let src = withPrelude (Text.unlines
            [ "@export Reads tbd and ignores it"
            , "GIVETH A BOOLEAN"
            , "`reads tbd and ignores it` MEANS TRUE OR (TBD EQUALS TBD)"
            ])
      blocks src `shouldReturn` (True, [])

    it "refuses a polymorphic ASSUME that the body reads first as a NUMBER and then as a DEONTIC" $ do
      -- The reads are looked at one by one: the first is harmless, the second is not.
      let src = parties <> dutyHelper <> placeholder <> Text.unlines
            [ "@export Reads in two ways"
            , "GIVETH A BOOLEAN"
            , "`reads in two ways` MEANS"
            , "  IF `local placeholder` + 1 > 0 THEN `fulfilled` `local placeholder` ELSE FALSE"
            ]
      blocks src `shouldReturn`
        (False, [("DEONTIC", "reads in two ways", "local placeholder", SError)])

    it "names the EVENT when the body reads a polymorphic ASSUME first as an EVENT and then as a DEONTIC" $ do
      let src = parties <> dutyHelper <> eventHelper <> placeholder <> Text.unlines
            [ "@export Reads in two ways"
            , "GIVETH A BOOLEAN"
            , "`reads in two ways` MEANS"
            , "  IF `time of` `local placeholder` > 0 THEN `fulfilled` `local placeholder` ELSE FALSE"
            ]
      blocks src `shouldReturn`
        (False, [("EVENT", "reads in two ways", "local placeholder", SError)])

    it "names the DEONTIC when the body reads a polymorphic ASSUME first as a DEONTIC and then as an EVENT" $ do
      let src = parties <> dutyHelper <> eventHelper <> placeholder <> Text.unlines
            [ "@export Reads in two ways"
            , "GIVETH A BOOLEAN"
            , "`reads in two ways` MEANS"
            , "  IF `fulfilled` `local placeholder` THEN `time of` `local placeholder` > 0 ELSE FALSE"
            ]
      blocks src `shouldReturn`
        (False, [("DEONTIC", "reads in two ways", "local placeholder", SError)])

    it "accepts a rule that is not an @export" $ do
      let src = withPrelude (parties <> dutyHelper <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`internal` MEANS `fulfilled` TBD"
            ])
      blocks src `shouldReturn` (True, [])

  -- When the body reads one ASSUME more than once, the check goes by the reads
  -- in the order that the walk of the body meets them: the first read that
  -- holds an EVENT or a DEONTIC says which of the two the error names, and the
  -- last reference to the ASSUME gives the spelling of its name. The walk meets
  -- what CONSIDER looks at before its branches, what a WHERE qualifies before
  -- the definitions under it, and the time of an event written with AT first
  -- after its party.
  describe "the order in which the check meets the reads of an ASSUME" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        dutyHelper = Text.unlines
          [ "GIVEN duty IS A DEONTIC Person Action"
          , "GIVETH A BOOLEAN"
          , "`fulfilled` duty MEANS"
          , "  CONSIDER duty"
          , "  WHEN FULFILLED THEN TRUE"
          , "  OTHERWISE FALSE"
          , ""
          ]
        eventHelper = Text.unlines
          [ "GIVEN e IS AN EVENT Person Action"
          , "GIVETH A NUMBER"
          , "`time of` e MEANS"
          , "  CONSIDER e"
          , "  WHEN EVENT p a t THEN t"
          , ""
          ]
        placeholder = Text.unlines
          [ "GIVEN a IS A TYPE"
          , "GIVETH AN a"
          , "ASSUME `local placeholder`"
          , ""
          ]
        blocks = exportBlocks emptyVFS
        -- (function, input) as the message spells them
        spelled src = either (fail . ("Fatal: " <>) . show) (pure . fst) (exportDeonticErrors emptyVFS src)

    it "names the EVENT when what CONSIDER looks at reads it as an EVENT, and a branch as a DEONTIC" $ do
      let src = parties <> dutyHelper <> eventHelper <> placeholder <> Text.unlines
            [ "@export Reads in two ways"
            , "GIVETH A BOOLEAN"
            , "`reads in two ways` MEANS"
            , "  CONSIDER `time of` `local placeholder`"
            , "  WHEN 0 THEN `fulfilled` `local placeholder`"
            , "  OTHERWISE FALSE"
            ]
      blocks src `shouldReturn`
        (False, [("EVENT", "reads in two ways", "local placeholder", SError)])

    it "names the EVENT when what a WHERE qualifies reads it as an EVENT, and a definition under it as a DEONTIC" $ do
      let src = parties <> dutyHelper <> eventHelper <> placeholder <> Text.unlines
            [ "@export Reads in two ways"
            , "GIVETH A BOOLEAN"
            , "`reads in two ways` MEANS"
            , "  `time of` `local placeholder` > 0 AND k"
            , "  WHERE"
            , "    k MEANS `fulfilled` `local placeholder`"
            ]
      blocks src `shouldReturn`
        (False, [("EVENT", "reads in two ways", "local placeholder", SError)])

    it "spells the name as a branch of CONSIDER does, not as what CONSIDER looks at does" $ do
      let src = parties <> Text.unlines
            [ "§ `Defs`"
            , "ASSUME `the duty` IS A DEONTIC Person Action"
            , ""
            , "§ `Rules`"
            , "@export Two spellings"
            , "GIVETH A BOOLEAN"
            , "`two spellings` MEANS"
            , "  CONSIDER `Defs`.`the duty`"
            , "  WHEN FULFILLED THEN"
            , "    CONSIDER `the duty`"
            , "    WHEN FULFILLED THEN TRUE"
            , "    OTHERWISE FALSE"
            , "  OTHERWISE FALSE"
            ]
      spelled src `shouldReturn` [("two spellings", "the duty")]

    it "spells the name as the time of an event written with AT first does, not as its party does" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "§ `Defs`"
            , "GIVEN a IS A TYPE"
            , "GIVETH AN a"
            , "ASSUME x"
            , ""
            , "§ `Rules`"
            , "@export At first"
            , "`at first` MEANS"
            , "  AT `Defs`.x PARTY (IF `fulfilled` x THEN Seller ELSE Buyer) DOES delivery"
            ]
      spelled src `shouldReturn` [("at first", "Defs.x")]

  -- An ASSUME can also be declared inside a rule, under WHERE. The checker's
  -- table of what a module declares holds the top-level and the imported
  -- ASSUMEs and not these, so the check finds them in the body, takes their
  -- declared type from the declaration, and goes by the type at each read as
  -- for any other ASSUME.
  describe "an @export that reads an ASSUME that its own WHERE declares" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        dutyHelper = Text.unlines
          [ "GIVEN duty IS A DEONTIC Person Action"
          , "GIVETH A BOOLEAN"
          , "`fulfilled` duty MEANS"
          , "  CONSIDER duty"
          , "  WHEN FULFILLED THEN TRUE"
          , "  OTHERWISE FALSE"
          , ""
          ]
        eventHelper = Text.unlines
          [ "GIVEN e IS AN EVENT Person Action"
          , "GIVETH A NUMBER"
          , "`time of` e MEANS"
          , "  CONSIDER e"
          , "  WHEN EVENT p a t THEN t"
          , ""
          ]
        blocks = exportBlocks emptyVFS

    it "blocks an ASSUME of type DEONTIC" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export Reads local duty"
            , "GIVETH A BOOLEAN"
            , "`reads local duty` MEANS `fulfilled` `local duty`"
            , "  WHERE"
            , "    ASSUME `local duty` IS A DEONTIC Person Action"
            ]
      blocks src `shouldReturn`
        (False, [("DEONTIC", "reads local duty", "local duty", SError)])

    it "blocks an ASSUME of type EVENT" $ do
      let src = parties <> eventHelper <> Text.unlines
            [ "@export Reads local event"
            , "GIVETH A NUMBER"
            , "`reads local event` MEANS `time of` `local event`"
            , "  WHERE"
            , "    ASSUME `local event` IS AN EVENT Person Action"
            ]
      blocks src `shouldReturn`
        (False, [("EVENT", "reads local event", "local event", SError)])

    it "blocks an ASSUME that has no written type, as a DEONTIC and as an EVENT" $ do
      let duty = parties <> dutyHelper <> Text.unlines
            [ "@export Reads local bare"
            , "GIVETH A BOOLEAN"
            , "`reads local bare` MEANS `fulfilled` `local bare`"
            , "  WHERE"
            , "    ASSUME `local bare`"
            ]
          event = parties <> eventHelper <> Text.unlines
            [ "@export Reads local bare event"
            , "GIVETH A NUMBER"
            , "`reads local bare event` MEANS `time of` `local bare`"
            , "  WHERE"
            , "    ASSUME `local bare`"
            ]
      blocks duty `shouldReturn`
        (False, [("DEONTIC", "reads local bare", "local bare", SError)])
      blocks event `shouldReturn`
        (False, [("EVENT", "reads local bare event", "local bare", SError)])

    it "blocks a polymorphic ASSUME that the body reads as a DEONTIC" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export Reads local placeholder"
            , "GIVETH A BOOLEAN"
            , "`reads local placeholder` MEANS `fulfilled` `local placeholder`"
            , "  WHERE"
            , "    GIVEN a IS A TYPE"
            , "    GIVETH AN a"
            , "    ASSUME `local placeholder`"
            ]
      blocks src `shouldReturn`
        (False, [("DEONTIC", "reads local placeholder", "local placeholder", SError)])

    it "blocks an ASSUME that a helper of the body declares in its own WHERE" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "@export Reads inner duty"
            , "GIVETH A BOOLEAN"
            , "`reads inner duty` MEANS helper"
            , "  WHERE"
            , "    helper MEANS `fulfilled` `inner duty`"
            , "      WHERE"
            , "        ASSUME `inner duty` IS A DEONTIC Person Action"
            ]
      blocks src `shouldReturn`
        (False, [("DEONTIC", "reads inner duty", "inner duty", SError)])

    it "refuses an ASSUME that the body reads twice once, and one error for each of two ASSUMEs" $ do
      let src = parties <> dutyHelper <> eventHelper <> Text.unlines
            [ "ASSUME `top duty` IS A DEONTIC Person Action"
            , ""
            , "@export Reads three"
            , "GIVETH A BOOLEAN"
            , "`reads three` MEANS"
            , "  `fulfilled` `local duty` AND `fulfilled` `local duty`"
            , "    AND `fulfilled` `top duty` AND `time of` `local event` > 0"
            , "  WHERE"
            , "    ASSUME `local duty` IS A DEONTIC Person Action"
            , "    ASSUME `local event` IS AN EVENT Person Action"
            ]
      (ok, errs) <- blocks src
      ok `shouldBe` False
      all (\(_, _, _, sev) -> sev == SError) errs `shouldBe` True
      sort [ (what, fn, p) | (what, fn, p, _) <- errs ] `shouldBe`
        [ ("DEONTIC", "reads three", "local duty")
        , ("DEONTIC", "reads three", "top duty")
        , ("EVENT", "reads three", "local event")
        ]

    it "accepts an ASSUME of type NUMBER" $ do
      let src = Text.unlines
            [ "@export Reads local number"
            , "GIVETH A NUMBER"
            , "`reads local number` MEANS `local n` + 1"
            , "  WHERE"
            , "    ASSUME `local n` IS A NUMBER"
            ]
      blocks src `shouldReturn` (True, [])

    it "accepts a polymorphic ASSUME that the body reads as a NUMBER" $ do
      let src = Text.unlines
            [ "@export Reads local placeholder as a number"
            , "GIVETH A NUMBER"
            , "`reads local placeholder as a number` MEANS `local placeholder` + 1"
            , "  WHERE"
            , "    GIVEN a IS A TYPE"
            , "    GIVETH AN a"
            , "    ASSUME `local placeholder`"
            ]
      blocks src `shouldReturn` (True, [])

    it "accepts an ASSUME of type DEONTIC that the body does not read" $ do
      let src = parties <> Text.unlines
            [ "@export Ignores local duty"
            , "GIVETH A BOOLEAN"
            , "`ignores local duty` MEANS TRUE"
            , "  WHERE"
            , "    ASSUME `local duty` IS A DEONTIC Person Action"
            ]
      blocks src `shouldReturn` (True, [])

    it "accepts a rule that is not an @export" $ do
      let src = parties <> dutyHelper <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`internal` MEANS `fulfilled` `local duty`"
            , "  WHERE"
            , "    ASSUME `local duty` IS A DEONTIC Person Action"
            ]
      blocks src `shouldReturn` (True, [])

    it "goes by the ASSUME that the body reads, when a local one has the name of a top-level one" $ do
      -- A name in a WHERE does not hide a top-level one: each read resolves by
      -- its type, so the four ways of declaring the pair differ in which of the
      -- two `shared` the body reads. The check goes by that one.
      let wherePair top local readIt result = parties <> dutyHelper <> Text.unlines
            [ "ASSUME `shared` IS " <> top
            , ""
            , "@export Reads shared"
            , "GIVETH A " <> result
            , "`reads shared` MEANS " <> readIt
            , "  WHERE"
            , "    ASSUME `shared` IS " <> local
            ]
          number = "A NUMBER"
          duty = "A DEONTIC Person Action"
          refusedFor = (False, [("DEONTIC", "reads shared", "shared", SError)])
      -- the body reads the local DEONTIC
      blocks (wherePair number duty "`fulfilled` `shared`" "BOOLEAN") `shouldReturn` refusedFor
      -- the body reads the top-level NUMBER, and the local DEONTIC beside it is not read
      blocks (wherePair number duty "`shared` + 1" "NUMBER") `shouldReturn` (True, [])
      -- the body reads the local NUMBER
      blocks (wherePair duty number "`shared` + 1" "NUMBER") `shouldReturn` (True, [])
      -- the body reads the top-level DEONTIC, and the local NUMBER beside it is not read
      blocks (wherePair duty number "`fulfilled` `shared`" "BOOLEAN") `shouldReturn` refusedFor

  -- A rule that the exported rule calls, directly or through other rules of the
  -- module, can read an ASSUME too. The service lists only the ASSUMEs that the
  -- exported rule reads itself, so a DEONTIC or an EVENT that a helper reads
  -- would be no input at all: the check refuses it as it refuses one that the
  -- exported rule reads, and names the rule that reads it.
  describe "an @export that reaches an ASSUME through a rule that it calls" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          , "ASSUME `the duty` IS A DEONTIC Person Action"
          , "ASSUME `the event` IS AN EVENT Person Action"
          , "ASSUME `the rate` IS A NUMBER"
          , ""
          ]
        dutyReader name = Text.unlines
          [ "GIVETH A BOOLEAN"
          , name <> " MEANS"
          , "  CONSIDER `the duty`"
          , "  WHEN FULFILLED THEN TRUE"
          , "  OTHERWISE FALSE"
          , ""
          ]
        exported name body = Text.unlines
          [ "@export " <> name
          , "GIVETH A BOOLEAN"
          , name <> " MEANS " <> body
          ]

    it "blocks an ASSUME of type DEONTIC that a helper reads, names the helper, and says what to do" $ do
      let src = parties <> dutyReader "`duty fulfilled`" <> exported "`via helper`" "`duty fulfilled`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via helper", "the duty", "duty fulfilled", SError)])
      case exportDeonticErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `via helper`:"
            , "  DEONTIC inputs are not supported for @export."
            , "  The input `the duty` is an ASSUME that `duty fulfilled` reads as a value whose type contains a DEONTIC, and this rule calls `duty fulfilled`, directly or through other rules. A request has no JSON form for a DEONTIC, so give `duty fulfilled` the DEONTIC as an input."
            , "  Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it."
            ]

    it "blocks an ASSUME of type EVENT that a helper reads, names the helper, and says what to do" $ do
      let src = parties <> Text.unlines
            [ "GIVETH A NUMBER"
            , "`event time` MEANS"
            , "  CONSIDER `the event`"
            , "  WHEN EVENT p a t THEN t"
            , "  OTHERWISE 0"
            , ""
            , "@export When"
            , "GIVETH A NUMBER"
            , "`via event helper` MEANS `event time`"
            ]
      exportReaders src `shouldReturn` (False, [("EVENT", "via event helper", "the event", "event time", SError)])
      case exportEventErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `via event helper`:"
            , "  EVENT inputs are not supported for @export."
            , "  The input `the event` is an ASSUME that `event time` reads as a value whose type contains an EVENT, and this rule calls `event time`, directly or through other rules. A request has no JSON form for an event, so give `event time` the event as an input."
            , "  Give the rule the party, the action and the time as separate inputs, and build the event inside it."
            ]

    it "follows a chain of rules, and names the one that reads the ASSUME" $ do
      let src = parties <> dutyReader "`duty fulfilled`" <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`first link` MEANS `second link`"
            , ""
            , "GIVETH A BOOLEAN"
            , "`second link` MEANS `duty fulfilled`"
            , ""
            ] <> exported "`via chain`" "`first link`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via chain", "the duty", "duty fulfilled", SError)])

    it "follows rules that call each other, and finishes" $ do
      let src = parties <> Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "ping n MEANS"
            , "  IF n <= 0"
            , "  THEN CONSIDER `the duty`"
            , "       WHEN FULFILLED THEN TRUE"
            , "       OTHERWISE FALSE"
            , "  ELSE pong (n - 1)"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "pong n MEANS ping (n - 1)"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "loop n MEANS loop n"
            , ""
            ] <> exported "`via recursion`" "pong 3 AND loop 1"
      readersWithinWatchdog src `shouldReturn` [("DEONTIC", "via recursion", "the duty", "ping")]

    it "follows a rule that many paths reach once, and finishes" $ do
      -- every level calls the next one twice, so the paths from the exported
      -- rule to the last level double at every level
      let levels = 60 :: Int
          level :: Int -> Text
          level k = "`level " <> Text.pack (show k) <> "`"
          src = parties <> Text.unlines (concat
            [ [ "GIVETH A BOOLEAN"
              , level k <> " MEANS " <> level (k + 1) <> " AND " <> level (k + 1)
              , ""
              ]
            | k <- [1 .. levels - 1]
            ]) <> dutyReader (level levels) <> exported "`via levels`" (level 1)
      readersWithinWatchdog src `shouldReturn` [("DEONTIC", "via levels", "the duty", "level 60")]

    it "blocks an ASSUME that holds a DEONTIC in a LIST, that a helper reads" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `the duties` IS A LIST OF DEONTIC Person Action"
            , ""
            , "GIVETH A BOOLEAN"
            , "`any duty` MEANS"
            , "  CONSIDER `the duties`"
            , "  WHEN EMPTY THEN FALSE"
            , "  OTHERWISE TRUE"
            , ""
            ] <> exported "`via list helper`" "`any duty`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via list helper", "the duties", "any duty", SError)])

    it "blocks an ASSUME with no written type that a helper reads as a DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "ASSUME `the untyped duty`"
            , ""
            , "GIVETH A BOOLEAN"
            , "`untyped fulfilled` MEANS"
            , "  CONSIDER `the untyped duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , ""
            ] <> exported "`via untyped helper`" "`untyped fulfilled`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via untyped helper", "the untyped duty", "untyped fulfilled", SError)])

    it "blocks an ASSUME of type DEONTIC that the helper's own WHERE declares" $ do
      let src = parties <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`own duty fulfilled` MEANS"
            , "  CONSIDER `own duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , "  WHERE"
            , "    ASSUME `own duty` IS A DEONTIC Person Action"
            , ""
            ] <> exported "`via own duty`" "`own duty fulfilled`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via own duty", "own duty", "own duty fulfilled", SError)])

    it "follows a call under the WHERE of a definition under the rule's own WHERE, and a read there in the helper" $ do
      let nested body = Text.unlines
            [ "  WHERE"
            , "    outer MEANS inner"
            , "      WHERE"
            , "        inner MEANS " <> body
            ]
          callIt = parties <> dutyReader "`duty fulfilled`" <> exported "`via nested call`" "outer" <> nested "`duty fulfilled`"
          readIt = parties <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`nested reader` MEANS outer"
            ] <> nested "`the duty` EQUALS `the duty`" <> "\n" <> exported "`via nested read`" "`nested reader`"
      exportReaders callIt `shouldReturn` (False, [("DEONTIC", "via nested call", "the duty", "duty fulfilled", SError)])
      exportReaders readIt `shouldReturn` (False, [("DEONTIC", "via nested read", "the duty", "nested reader", SError)])

    it "counts a read in a definition under the helper's WHERE that the helper never calls, as for the exported rule's own WHERE" $ do
      let src = parties <> Text.unlines
            [ "GIVETH A NUMBER"
            , "`helper with unused part` MEANS 1"
            , "  WHERE"
            , "    unused MEANS `the duty` EQUALS `the duty`"
            , ""
            , "@export One more"
            , "GIVETH A NUMBER"
            , "`via unused part` MEANS `helper with unused part` + 1"
            ]
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via unused part", "the duty", "helper with unused part", SError)])

    it "follows a rule that the body hands on as a value, as to map" $ do
      let src = "IMPORT prelude\n" <> parties <> Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`check one` n MEANS `the duty` EQUALS `the duty`"
            , ""
            , "@export Checks"
            , "GIVETH A LIST OF BOOLEAN"
            , "`via map` MEANS map `check one` (LIST 1, 2)"
            ]
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via map", "the duty", "check one", SError)])

    it "follows a rule that stands in a section" $ do
      let src = parties <> "§ `Part one`\n" <> dutyReader "`sectioned`" <> "§ `Part two`\n" <> exported "`via section`" "`sectioned`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via section", "the duty", "sectioned", SError)])

    -- `n's f` is a call of the rule f with n as its one input, and a computed
    -- field of a record is a rule whose one input is the record.
    it "follows a call written with 's, a computed field of a record, and such a call one rule away" $ do
      let atReader = Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`duty fulfilled at` n MEANS"
            , "  CONSIDER `the duty`"
            , "  WHEN FULFILLED THEN n > 0"
            , "  OTHERWISE FALSE"
            , ""
            ]
          viaGenitive = parties <> atReader <> Text.unlines
            [ "@export Is the duty fulfilled, by a call written with 's"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`via genitive` n MEANS n's `duty fulfilled at`"
            ]
          viaField = parties <> Text.unlines
            [ "DECLARE Case HAS"
            , "    `case number` IS A NUMBER"
            , "    `duty met` IS A BOOLEAN MEANS `the duty` EQUALS `the duty`"
            , ""
            , "@export Is the duty met, by a computed field"
            , "GIVEN c IS A Case"
            , "GIVETH A BOOLEAN"
            , "`via computed field` c MEANS c's `duty met`"
            ]
          viaMiddle = parties <> atReader <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`genitive middle` MEANS 3's `duty fulfilled at`"
            , ""
            ] <> exported "`via genitive middle`" "`genitive middle`"
      exportReaders viaGenitive `shouldReturn` (False, [("DEONTIC", "via genitive", "the duty", "duty fulfilled at", SError)])
      exportReaders viaField `shouldReturn` (False, [("DEONTIC", "via computed field", "the duty", "duty met", SError)])
      exportReaders viaMiddle `shouldReturn` (False, [("DEONTIC", "via genitive middle", "the duty", "duty fulfilled at", SError)])

    it "follows a rule that reads an ASSUME of an imported module" $ do
      let facts = Text.unlines
            [ "DECLARE Person IS ONE OF Seller, Buyer"
            , "DECLARE Action IS ONE OF delivery, payment"
            , ""
            , "ASSUME `imported duty` IS A DEONTIC Person Action"
            ]
          src = Text.unlines
            [ "IMPORT facts"
            , ""
            , "GIVETH A BOOLEAN"
            , "`imported duty fulfilled` MEANS"
            , "  CONSIDER `imported duty`"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , ""
            ] <> exported "`via imported reader`" "`imported duty fulfilled`"
      exportReadersWith (vfsFromList [("facts", facts)]) src
        `shouldReturn` (False, [("DEONTIC", "via imported reader", "imported duty", "imported duty fulfilled", SError)])

    it "refuses an ASSUME once, however many rules read it, and as the exported rule's own read when it reads it too" $ do
      let twoReaders = parties <> dutyReader "`first reader`" <> dutyReader "`second reader`"
          both = twoReaders <> exported "`via two readers`" "`first reader` AND `second reader`"
          ownToo = twoReaders <> exported "`reads it too`" "`first reader` AND (`the duty` EQUALS `the duty`)"
      (fmap (map (\(what, fn, input, _, sev) -> (what, fn, input, sev))) <$> exportReaders both)
        `shouldReturn` (False, [("DEONTIC", "via two readers", "the duty", SError)])
      exportReaders ownToo `shouldReturn` (False, [("DEONTIC", "reads it too", "the duty", "", SError)])

    it "accepts a helper that reads an ASSUME of type NUMBER" $ do
      let src = parties <> Text.unlines
            [ "GIVETH A NUMBER"
            , "`rate plus one` MEANS `the rate` + 1"
            , ""
            , "@export One more"
            , "GIVETH A NUMBER"
            , "`via number helper` MEANS `rate plus one`"
            ]
      exportReaders src `shouldReturn` (True, [])

    it "does not look at a helper that no exported rule reaches" $ do
      let src = parties <> dutyReader "`duty fulfilled`" <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`internal only` MEANS `duty fulfilled`"
            , ""
            , "@export Unrelated"
            , "GIVETH A NUMBER"
            , "`unrelated` MEANS `the rate` + 1"
            ]
      exportReaders src `shouldReturn` (True, [])

    it "accepts a helper that takes the DEONTIC as an input from a rule that builds it" $ do
      let src = parties <> Text.unlines
            [ "GIVEN duty IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`is fulfilled` duty MEANS"
            , "  CONSIDER duty"
            , "  WHEN FULFILLED THEN TRUE"
            , "  OTHERWISE FALSE"
            , ""
            , "@export Is the duty to deliver fulfilled"
            , "GIVEN deadline IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`via input` deadline MEANS `is fulfilled` (PARTY Seller MUST delivery WITHIN deadline)"
            ]
      exportReaders src `shouldReturn` (True, [])

    -- Following the calls keeps a fact that a rule reaches a read of a DEONTIC
    -- once for each ASSUME, read by the top-level rule that the rule stands in
    -- or by another, and not once for each rule that reads it. Every link of
    -- this chain reads the ASSUME of type DEONTIC and calls the next link, so a
    -- fact for each reader would make the work grow with the square of the
    -- length of the chain. As for the chain of polymorphic readers in the next
    -- group, the test counts what the input check allocates: a chain four times
    -- as long must allocate less than eight times as much.
    it "does not keep a fact for each rule that reads the ASSUME, in a chain of rules that each read a DEONTIC" $ do
      let link :: Int -> Text
          link k = "`link " <> Text.pack (show k) <> "`"
          next links k = if k < links then link (k + 1) <> " (n - 1)" else "FALSE"
          chain links = parties <> Text.unlines (concat
            [ [ "GIVEN n IS A NUMBER"
              , "GIVETH A BOOLEAN"
              , link k <> " n MEANS"
              , "  IF n <= 0"
              , "  THEN CONSIDER `the duty`"
              , "       WHEN FULFILLED THEN TRUE"
              , "       OTHERWISE FALSE"
              , "  ELSE " <> next links k
              , ""
              ]
            | k <- [1 .. links]
            ]) <> Text.unlines
            [ "@export The top rule"
            , "GIVEN x IS A NUMBER"
            , "GIVETH A BOOLEAN"
            , "`top` x MEANS " <> link 1 <> " x"
            ]
          allocatedFor links = do
            r <- either (fail . ("Fatal: " <>) . show) pure (checkWithImports emptyVFS (chain links))
            length [ () | e <- r.tcdErrors, severity e == SError ] `shouldBe` 1
            _ <- evaluate (force r.tcdModule)
            _ <- evaluate (force r.tcdEntityInfo)
            counterBefore <- getAllocationCounter
            refused <- evaluate (length (validateExportInputs r.tcdSubstitution r.tcdEntityInfo r.tcdModule))
            counterAfter <- getAllocationCounter
            refused `shouldBe` 1
            pure (counterBefore - counterAfter)
      short <- allocatedFor 200
      long <- allocatedFor 800
      (long, short) `shouldSatisfy` (\(longer, shorter) -> longer < 8 * shorter)

  -- A polymorphic helper (GIVEN a IS A TYPE) that reads a polymorphic ASSUME at
  -- its own type variable reads it at whatever type each call gives the
  -- variable, so the type at the read holds no DEONTIC even when the call makes
  -- the value one. The check works out what each call gives each variable, from
  -- the types at the call, and goes by that.
  describe "an @export whose polymorphic helper reads a polymorphic ASSUME" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          , "GIVEN a IS A TYPE"
          , "GIVETH AN a"
          , "ASSUME `the placeholder`"
          , ""
          , "GIVEN duty IS A DEONTIC Person Action"
          , "GIVETH A BOOLEAN"
          , "`fulfilled` duty MEANS"
          , "  CONSIDER duty"
          , "  WHEN FULFILLED THEN TRUE"
          , "  OTHERWISE FALSE"
          , ""
          , "GIVEN e IS AN EVENT Person Action"
          , "GIVETH A NUMBER"
          , "`time of` e MEANS"
          , "  CONSIDER e"
          , "  WHEN EVENT p a t THEN t"
          , ""
          , "GIVETH A DEONTIC Person Action"
          , "`the standard duty` MEANS PARTY Seller MUST delivery WITHIN 10"
          , ""
          , "GIVEN a IS A TYPE"
          , "      n IS A NUMBER"
          , "GIVETH AN a"
          , "`top fetch` n MEANS `the placeholder`"
          , ""
          ]
        localFetch = Text.unlines
          [ "  WHERE"
          , "    GIVEN a IS A TYPE"
          , "          n IS A NUMBER"
          , "    GIVETH AN a"
          , "    fetch n MEANS `the placeholder`"
          ]
        exported name giveth body = Text.unlines
          [ "@export " <> name
          , "GIVETH " <> giveth
          , name <> " MEANS " <> body
          ]

    it "blocks a helper under the rule's own WHERE that the call makes read the ASSUME as a DEONTIC" $ do
      let src = parties <> exported "`via local helper`" "A BOOLEAN" "`fulfilled` (fetch 1)" <> localFetch
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via local helper", "the placeholder", "", SError)])
      case exportDeonticErrors emptyVFS src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right (_, msg) ->
          Text.unlines msg `shouldBe` Text.unlines
            [ "I found a problem while checking the definition of `via local helper`:"
            , "  DEONTIC inputs are not supported for @export."
            , "  The input `the placeholder` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC."
            , "  Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it."
            ]

    it "blocks a polymorphic rule of the module that the call makes read the ASSUME as a DEONTIC or an EVENT, and names it" $ do
      exportReaders (parties <> exported "`via top helper`" "A BOOLEAN" "`fulfilled` (`top fetch` 1)")
        `shouldReturn` (False, [("DEONTIC", "via top helper", "the placeholder", "top fetch", SError)])
      exportReaders (parties <> exported "`via event helper`" "A NUMBER" "`time of` (`top fetch` 1)")
        `shouldReturn` (False, [("EVENT", "via event helper", "the placeholder", "top fetch", SError)])

    it "blocks a call that names the helper's inputs (WITH)" $ do
      exportReaders (parties <> exported "`via named call`" "A BOOLEAN" "`fulfilled` (`top fetch` WITH n IS 1)")
        `shouldReturn` (False, [("DEONTIC", "via named call", "the placeholder", "top fetch", SError)])

    it "goes by the inputs that a call names (WITH), in another order than the GIVEN" $ do
      let helpers = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      x IS AN a"
            , "GIVETH A NUMBER"
            , "`count beside` x MEANS"
            , "  CONSIDER LIST x, `the placeholder`"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            , "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "      x IS AN a"
            , "GIVETH A NUMBER"
            , "`count beside two` n x MEANS"
            , "  CONSIDER LIST x, `the placeholder`"
            , "  WHEN EMPTY THEN n"
            , "  OTHERWISE 1"
            , ""
            ]
      -- the helper answers a NUMBER: only the named input gives the variable a type
      exportReaders (helpers <> exported "`via named input`" "A NUMBER" "`count beside` WITH x IS `the standard duty`")
        `shouldReturn` (False, [("DEONTIC", "via named input", "the placeholder", "count beside", SError)])
      exportReaders (helpers <> exported "`via named two`" "A NUMBER" "`count beside two` WITH x IS `the standard duty`, n IS 1")
        `shouldReturn` (False, [("DEONTIC", "via named two", "the placeholder", "count beside two", SError)])
      exportReaders (helpers <> exported "`via named numbers`" "A NUMBER" "`count beside two` WITH x IS 3, n IS 1")
        `shouldReturn` (True, [])

    it "goes by the type of a polymorphic rule that the body hands on as a value, as to map" $ do
      let src = "IMPORT prelude\n" <> parties <> Text.unlines
            [ "GIVEN xs IS A LIST OF DEONTIC Person Action"
            , "GIVETH A NUMBER"
            , "`count list` xs MEANS"
            , "  CONSIDER xs"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            ] <> exported "`via map fetch`" "A NUMBER" "`count list` (map `top fetch` (LIST 1, 2))"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via map fetch", "the placeholder", "top fetch", SError)])

    it "blocks a polymorphic helper that reads the prelude's TBD at a DEONTIC" $ do
      let src = "IMPORT prelude\n" <> parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH AN a"
            , "`tbd fetch` n MEANS TBD"
            , ""
            ] <> exported "`via tbd fetch`" "A BOOLEAN" "`fulfilled` (`tbd fetch` 1)"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via tbd fetch", "TBD", "tbd fetch", SError)])

    -- `n's f` is a call of the rule f with n as its one input, and a computed
    -- field of a record is a rule whose one input is the record.
    it "goes by a call written with 's, and by a computed field of a polymorphic record" $ do
      exportReaders (parties <> exported "`via genitive fetch`" "A BOOLEAN" "`fulfilled` (1's `top fetch`)")
        `shouldReturn` (False, [("DEONTIC", "via genitive fetch", "the placeholder", "top fetch", SError)])
      let holder = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "DECLARE Holder a HAS"
            , "    `holder number` IS A NUMBER"
            , "    `held` IS AN a MEANS `the placeholder`"
            , ""
            ]
      exportReaders (holder <> exported "`via computed held`" "A BOOLEAN" "`fulfilled` ((Holder 1)'s `held`)")
        `shouldReturn` (False, [("DEONTIC", "via computed held", "the placeholder", "held", SError)])
      exportReaders (holder <> exported "`via computed number`" "A NUMBER" "(Holder 1)'s `held` + 1")
        `shouldReturn` (True, [])

    it "follows a polymorphic rule that hands its own type variable on to another" $ do
      let src = parties <> Text.unlines
            [ "GIVEN b IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH A b"
            , "relay n MEANS `top fetch` n"
            , ""
            ] <> exported "`via relay`" "A BOOLEAN" "`fulfilled` (relay 3)"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via relay", "the placeholder", "top fetch", SError)])

    it "goes by the input of the helper as well as by its answer" $ do
      let src = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      x IS AN a"
            , "GIVETH A LIST OF a"
            , "`with placeholder` x MEANS LIST x, `the placeholder`"
            , ""
            ] <> exported "`via input of helper`" "A LIST OF DEONTIC Person Action" "`with placeholder` `the standard duty`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via input of helper", "the placeholder", "with placeholder", SError)])
      -- a helper that answers a NUMBER: only its input gives the variable a type
      let inputOnly = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      x IS AN a"
            , "GIVETH A NUMBER"
            , "`count beside` x MEANS"
            , "  CONSIDER LIST x, `the placeholder`"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            ]
      exportReaders (inputOnly <> exported "`via input only`" "A NUMBER" "`count beside` `the standard duty`")
        `shouldReturn` (False, [("DEONTIC", "via input only", "the placeholder", "count beside", SError)])
      exportReaders (inputOnly <> exported "`number input`" "A NUMBER" "`count beside` 3")
        `shouldReturn` (True, [])

    it "expands a synonym on either side of the call" $ do
      let synonyms = Text.unlines
            [ "DECLARE Cargo a IS A LIST OF a"
            , ""
            , "GIVEN a IS A TYPE"
            , "      xs IS A Cargo a"
            , "GIVETH A NUMBER"
            , "`count with placeholder` xs MEANS"
            , "  CONSIDER `the placeholder` FOLLOWED BY xs"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            , "GIVEN a IS A TYPE"
            , "      xs IS A LIST OF a"
            , "GIVETH A NUMBER"
            , "`count beside placeholder` xs MEANS"
            , "  CONSIDER `the placeholder` FOLLOWED BY xs"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            , "GIVETH A Cargo (DEONTIC Person Action)"
            , "`the cargo` MEANS LIST `the standard duty`"
            , ""
            , "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH A LIST OF a"
            , "`listed` n MEANS LIST `the placeholder`"
            , ""
            , "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH A Cargo a"
            , "`carried` n MEANS LIST `the placeholder`"
            , ""
            , "GIVEN xs IS A Cargo (DEONTIC Person Action)"
            , "GIVETH A NUMBER"
            , "`count cargo` xs MEANS"
            , "  CONSIDER xs"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            , "GIVEN xs IS A LIST OF (DEONTIC Person Action)"
            , "GIVETH A NUMBER"
            , "`count list` xs MEANS"
            , "  CONSIDER xs"
            , "  WHEN EMPTY THEN 0"
            , "  OTHERWISE 1"
            , ""
            ]
      -- the helper declares a synonym, and the call gives it a LIST
      exportReaders (parties <> synonyms <> exported "`via declared synonym`" "A NUMBER" "`count with placeholder` (LIST `the standard duty`)")
        `shouldReturn` (False, [("DEONTIC", "via declared synonym", "the placeholder", "count with placeholder", SError)])
      -- the helper declares a LIST, and the call gives it a synonym
      exportReaders (parties <> synonyms <> exported "`via given synonym`" "A NUMBER" "`count beside placeholder` `the cargo`")
        `shouldReturn` (False, [("DEONTIC", "via given synonym", "the placeholder", "count beside placeholder", SError)])
      -- the helper answers a LIST where the call stands for a synonym: the type
      -- recorded at the call is the synonym, and the helper declares a LIST
      exportReaders (parties <> synonyms <> exported "`via answer synonym`" "A NUMBER" "`count cargo` (`listed` 1)")
        `shouldReturn` (False, [("DEONTIC", "via answer synonym", "the placeholder", "listed", SError)])
      -- the helper answers a synonym where the call stands for a LIST
      exportReaders (parties <> synonyms <> exported "`via declared answer synonym`" "A NUMBER" "`count list` (`carried` 1)")
        `shouldReturn` (False, [("DEONTIC", "via declared answer synonym", "the placeholder", "carried", SError)])

    it "follows a polymorphic helper that calls itself" $ do
      let src = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH AN a"
            , "countdown n MEANS"
            , "  IF n <= 0"
            , "  THEN `the placeholder`"
            , "  ELSE countdown (n - 1)"
            , ""
            ] <> exported "`via recursion`" "A BOOLEAN" "`fulfilled` (countdown 3)"
      readersWithinWatchdog src `shouldReturn` [("DEONTIC", "via recursion", "the placeholder", "countdown")]

    it "follows a rule whose type variable the checker makes up, with no GIVEN a IS A TYPE" $ do
      let src = parties <> Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "`implicit fetch` n MEANS `the placeholder`"
            , ""
            ] <> exported "`via implicit`" "A BOOLEAN" "`fulfilled` (`implicit fetch` 1)"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via implicit", "the placeholder", "implicit fetch", SError)])

    it "goes by a type variable that stands inside a record type" $ do
      let src = parties <> Text.unlines
            [ "DECLARE Box a HAS content IS AN a"
            , ""
            , "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH A Box a"
            , "`boxed` n MEANS Box `the placeholder`"
            , ""
            ] <> exported "`via box`" "A BOOLEAN" "`fulfilled` ((`boxed` 1)'s content)"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via box", "the placeholder", "boxed", SError)])

    it "goes by a type variable of a rule that a definition under its WHERE reads the ASSUME at" $ do
      let src = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH AN a"
            , "`outer fetch` n MEANS inner"
            , "  WHERE"
            , "    inner MEANS `the placeholder`"
            , ""
            ] <> exported "`via outer`" "A BOOLEAN" "`fulfilled` (`outer fetch` 1)"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via outer", "the placeholder", "outer fetch", SError)])

    it "follows a polymorphic rule through a rule that is not exported" $ do
      let src = parties <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`middle` MEANS `fulfilled` (`top fetch` 1)"
            , ""
            ] <> exported "`via middle`" "A BOOLEAN" "`middle`"
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via middle", "the placeholder", "top fetch", SError)])

    it "names no reader when a definition under the rule's own WHERE and a rule of the module both read the ASSUME" $ do
      let src = parties <> exported "`via both`" "A BOOLEAN" "`fulfilled` (`top fetch` 2) AND `fulfilled` (fetch 1)" <> localFetch
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via both", "the placeholder", "", SError)])

    -- A definition under the exported rule's WHERE reads the ASSUME at its own
    -- variable and also calls a rule of the module that reads it, so the two
    -- reads meet in the definition before they cross the call that makes them a
    -- DEONTIC. The read that stands in the exported rule must not give way to
    -- the other one there, whichever of the two rules is written first.
    it "names no reader when a definition under the rule's own WHERE reads the ASSUME and calls a rule of the module that reads it" $ do
      let src = parties <> exported "`via local both`" "A BOOLEAN" "`fulfilled` (fetch 1)" <> Text.unlines
            [ "  WHERE"
            , "    GIVEN a IS A TYPE"
            , "          n IS A NUMBER"
            , "    GIVETH AN a"
            , "    fetch n MEANS IF n > 0 THEN `top fetch` n ELSE `the placeholder`"
            ]
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via local both", "the placeholder", "", SError)])

    it "names no reader when a definition under the rule's own WHERE reads the ASSUME and calls a rule of the module that reads it, written after the exported rule" $ do
      let src = parties <> exported "`via local late`" "A BOOLEAN" "`fulfilled` (fetch 1)" <> Text.unlines
            [ "  WHERE"
            , "    GIVEN a IS A TYPE"
            , "          n IS A NUMBER"
            , "    GIVETH AN a"
            , "    fetch n MEANS IF n > 0 THEN `late fetch` n ELSE `the placeholder`"
            , ""
            , "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH AN a"
            , "`late fetch` n MEANS `the placeholder`"
            ]
      exportReaders src `shouldReturn` (False, [("DEONTIC", "via local late", "the placeholder", "", SError)])

    it "accepts a call that gives the variable the type NUMBER" $ do
      exportReaders (parties <> exported "`via local number`" "A NUMBER" "fetch 1 + 1" <> localFetch)
        `shouldReturn` (True, [])
      exportReaders (parties <> exported "`via top number`" "A NUMBER" "`top fetch` 1 + 1")
        `shouldReturn` (True, [])

    it "accepts a call at NUMBER when only a rule that is not exported calls the same helper at a DEONTIC" $ do
      let src = parties <> Text.unlines
            [ "GIVETH A BOOLEAN"
            , "`not exported` MEANS `fulfilled` (`top fetch` 1)"
            , ""
            ] <> exported "`via shared helper`" "A NUMBER" "`top fetch` 1 + 1"
      exportReaders src `shouldReturn` (True, [])

    it "accepts a helper that takes a DEONTIC but reads the ASSUME at its variable, which the call makes a NUMBER" $ do
      let src = parties <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      duty IS A DEONTIC Person Action"
            , "GIVETH AN a"
            , "`beside the duty` duty MEANS `the placeholder`"
            , ""
            ] <> exported "`via helper that takes a duty`" "A NUMBER" "`beside the duty` `the standard duty` + 1"
      exportReaders src `shouldReturn` (True, [])

    -- Following the calls keeps a fact for a rule once for each ASSUME and each
    -- variable, read by the top-level rule that the rule stands in or by
    -- another, and not once for each rule that reads the ASSUME. Every link of
    -- this chain reads the ASSUME at its own variable and calls the next link,
    -- so a fact for each reader would make the work grow with the square of the
    -- length of the chain. The test counts what the input check allocates,
    -- which does not depend on the load of the machine: a chain four times as
    -- long must allocate less than eight times as much, which a fact for each
    -- reader does not.
    it "does not keep a fact for each rule that reads the ASSUME, in a chain of polymorphic readers" $ do
      let link :: Int -> Text
          link k = "`link " <> Text.pack (show k) <> "`"
          chain links = parties <> Text.unlines (concat
            [ [ "GIVEN a IS A TYPE"
              , "      n IS A NUMBER"
              , "GIVETH AN a"
              , link k <> " n MEANS IF n <= 0 THEN `the placeholder` ELSE " <> link (k + 1) <> " (n - 1)"
              , ""
              ]
            | k <- [1 .. links - 1]
            ]) <> Text.unlines
            [ "GIVEN a IS A TYPE"
            , "      n IS A NUMBER"
            , "GIVETH AN a"
            , link links <> " n MEANS `the placeholder`"
            , ""
            , "@export The top rule"
            , "GIVEN x IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`top` x MEANS " <> link 1 <> " x + 1"
            ]
          allocatedFor links = do
            r <- either (fail . ("Fatal: " <>) . show) pure (checkWithImports emptyVFS (chain links))
            map prettyCheckErrorWithContext [ e | e <- r.tcdErrors, severity e == SError ] `shouldBe` []
            _ <- evaluate (force r.tcdModule)
            _ <- evaluate (force r.tcdEntityInfo)
            counterBefore <- getAllocationCounter
            refused <- evaluate (length (validateExportInputs r.tcdSubstitution r.tcdEntityInfo r.tcdModule))
            counterAfter <- getAllocationCounter
            refused `shouldBe` 0
            pure (counterBefore - counterAfter)
      short <- allocatedFor 200
      long <- allocatedFor 800
      (long, short) `shouldSatisfy` (\(longer, shorter) -> longer < 8 * shorter)

  -- The check looks at every definition that is marked as an export, whichever
  -- way it is marked and wherever it stands.
  describe "which definitions are checked as exports" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        marked mark = parties <> Text.unlines
          [ mark <> " the rule"
          , "GIVEN d IS A DEONTIC Person Action"
          , "GIVETH A BOOLEAN"
          , "`marked` d MEANS TRUE"
          ]
        refused src = snd <$> unsendableRefusals emptyVFS src

    it "refuses an @export default, an @desc export and an @desc default alike" $ do
      forM_ ["@export", "@export default", "@desc export", "@desc default", "@desc DEFAULT"] $ \mark ->
        refused (marked mark) `shouldReturn` [("marked", "d")]

    it "does not check a definition whose @desc says nothing about exporting" $ do
      refused (marked "@desc") `shouldReturn` []

    it "refuses an export that stands in a nested section" $ do
      let src = parties <> Text.unlines
            [ "§ Outer"
            , "§§ Inner"
            , "@export nested"
            , "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`nested` d MEANS TRUE"
            ]
      refused src `shouldReturn` [("nested", "d")]

    it "refuses an export that follows an export that is accepted" $ do
      let src = parties <> Text.unlines
            [ "@export default Fine"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`fine` n MEANS n"
            , ""
            , "§ Later"
            , "@export default Not fine"
            , "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`not fine` d MEANS TRUE"
            ]
      refused src `shouldReturn` [("not fine", "d")]

  -- An input that holds both an EVENT and a DEONTIC is refused for the one that
  -- the walk meets first: the arguments of its type before the fields of the
  -- record, and the fields and constructors in the order they are written.
  describe "which of an EVENT and a DEONTIC an input is refused for, when it holds both" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        export input = Text.unlines
          [ "@export The rule"
          , "GIVEN x IS " <> input
          , "GIVETH A BOOLEAN"
          , "`the rule` x MEANS TRUE"
          ]
        refusals src = unsendableRefusals emptyVFS src
        both = [("the rule", "x")]

    it "reads a type argument before the fields of the record it is an argument of" $ do
      let box fieldType = parties <> Text.unlines
            [ "DECLARE Box a HAS"
            , "  content IS AN a"
            , "  other IS " <> fieldType
            , ""
            ]
      refusals (box "A DEONTIC Person Action" <> export "A Box OF (EVENT Person Action)")
        `shouldReturn` (both, [])
      refusals (box "AN EVENT Person Action" <> export "A Box OF (DEONTIC Person Action)")
        `shouldReturn` ([], both)

    it "reads the constructors of a sum type in the order they are written" $ do
      let entry eventFirst = parties <> Text.unlines
            ( [ "DECLARE Entry IS ONE OF" ]
              <> (if eventFirst
                    then [ "  happened HAS e IS AN EVENT Person Action"
                         , "  promised HAS what IS A DEONTIC Person Action"
                         ]
                    else [ "  promised HAS what IS A DEONTIC Person Action"
                         , "  happened HAS e IS AN EVENT Person Action"
                         ]
                 )
              <> [ "" ]
            ) <> export "AN Entry"
      refusals (entry True) `shouldReturn` (both, [])
      refusals (entry False) `shouldReturn` ([], both)

    it "reads the fields of one constructor in the order they are written" $ do
      let entry eventFirst = parties <> Text.unlines
            ( [ "DECLARE Entry IS ONE OF" ]
              <> (if eventFirst
                    then [ "  both HAS e IS AN EVENT Person Action"
                         , "           what IS A DEONTIC Person Action"
                         ]
                    else [ "  both HAS what IS A DEONTIC Person Action"
                         , "           e IS AN EVENT Person Action"
                         ]
                 )
              <> [ "  neither" , "" ]
            ) <> export "AN Entry"
      refusals (entry True) `shouldReturn` (both, [])
      refusals (entry False) `shouldReturn` ([], both)

  -- The check does not look into a type that leads to neither an EVENT nor a
  -- DEONTIC, and it works out which types lead to one once for the whole
  -- module. That a type leads to one does not depend on the input that is
  -- checked, nor on the way by which the walk came to the type.
  describe "the types that the input check does not look into" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        export name input = Text.unlines
          [ "@export " <> name
          , "GIVEN x IS " <> input
          , "GIVETH A BOOLEAN"
          , "`" <> name <> "` x MEANS TRUE"
          , ""
          ]
        refused src = sort . fst <$> unsendableRefusals emptyVFS src

    it "refuses both of two records that refer to each other, when one of them holds an EVENT" $ do
      let records = parties <> Text.unlines
            [ "DECLARE Outer HAS"
            , "  inner IS AN Inner"
            , "  e IS AN EVENT Person Action"
            , ""
            , "DECLARE Inner HAS back IS AN Outer"
            , ""
            ]
          both = [("takes an inner", "x"), ("takes an outer", "x")]
      refused (records <> export "takes an outer" "AN Outer" <> export "takes an inner" "AN Inner")
        `shouldReturn` both
      refused (records <> export "takes an inner" "AN Inner" <> export "takes an outer" "AN Outer")
        `shouldReturn` both

    it "refuses a record that holds an EVENT, also after the input of another rule led the walk through it" $ do
      let records = parties <> Text.unlines
            [ "DECLARE Inner HAS e IS AN EVENT Person Action"
            , "DECLARE Wrap HAS inner IS AN Inner"
            , ""
            ]
      refused (records <> export "takes a wrap" "A Wrap" <> export "takes an inner" "AN Inner")
        `shouldReturn` [("takes a wrap", "x"), ("takes an inner", "x")]

    -- The check looks at an ASSUME once for each read of it, since each read
    -- of a polymorphic ASSUME has a type of its own. The body here reads `cfg`
    -- more often than a test could afford to check: the module is checked with
    -- one read, and the input check then runs on the module with that body
    -- repeated in a LIST, which it reads as it is. Each read walking the fields
    -- of the record again takes many times as long as the watchdog allows.
    it "does not walk the fields of a record again for each read of an ASSUME of it" $ do
      let width = 4000 :: Int
          readCount = 200000 :: Int
          src = Text.unlines $
            [ "DECLARE Wide HAS" ]
            <> [ "  f" <> Text.pack (show i) <> " IS A NUMBER" | i <- [1 .. width] ]
            <> [ ""
               , "ASSUME cfg IS A Wide"
               , ""
               , "@export Reads cfg"
               , "GIVETH A NUMBER"
               , "`reads cfg` MEANS cfg's f1"
               ]
          readOften decide@(MkDecide ann sig appForm body)
            | isExportedDecide decide =
                MkDecide ann sig appForm (List (getAnno body) (replicate readCount body))
            | otherwise = decide
      r <- either (fail . ("Fatal: " <>) . show) pure (checkWithImports emptyVFS src)
      map prettyCheckErrorWithContext [ e | e <- r.tcdErrors, severity e == SError ] `shouldBe` []
      _ <- evaluate (force r.tcdModule)
      let repeated = over (gplate @(Decide Resolved)) readOften r.tcdModule
      within <- timeout (5 * 1000000) $
        evaluate (length (validateExportInputs r.tcdSubstitution r.tcdEntityInfo repeated))
      within `shouldBe` Just 0

    -- The fields of every type are gathered once for the module, and read in
    -- full the first time the check asks whether a type leads to an EVENT or a
    -- DEONTIC, which one input of type NUMBER makes it ask. The sum type here
    -- has more constructors than a test could afford to check: the module is
    -- checked with two, and the input check then runs with an entity table in
    -- which the first of them is copied under new uniques. Putting the fields
    -- of each constructor behind those of the constructors before it does not
    -- finish within the watchdog.
    it "gathers the fields of a sum type of many constructors in one pass" $ do
      let copies = 64000 :: Int
          src = Text.unlines
            [ "DECLARE Big IS ONE OF"
            , "  first HAS n IS A NUMBER"
            , "  second HAS m IS A NUMBER"
            , ""
            , "@export Plus one"
            , "GIVEN x IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`plus one` x MEANS x + 1"
            ]
      r <- either (fail . ("Fatal: " <>) . show) pure (checkWithImports emptyVFS src)
      map prettyCheckErrorWithContext [ e | e <- r.tcdErrors, severity e == SError ] `shouldBe` []
      (MkUnique s _ uri, copied) <-
        case [ entry | entry@(_, (name, KnownTerm _ Constructor)) <- Map.toList r.tcdEntityInfo, nameToText name == "first" ] of
          [entry] -> pure entry
          entries -> fail ("expected one constructor `first`, found " <> show (length entries))
      let wide = Map.union r.tcdEntityInfo (Map.fromList [ (MkUnique s (negate i) uri, copied) | i <- [1 .. copies] ])
      Map.size wide `shouldBe` Map.size r.tcdEntityInfo + copies
      _ <- evaluate (force r.tcdModule)
      _ <- evaluate (force wide)
      within <- timeout (5 * 1000000) $
        evaluate (length (validateExportInputs r.tcdSubstitution wide r.tcdModule))
      within `shouldBe` Just 0

  -- Which types the check looks into is worked out from the names that a
  -- synonym or a field names, and a name under a FOR ALL counts. A FOR ALL
  -- that is the input's own type is looked through by the walk of the input
  -- itself ("rejects an EVENT under a FOR ALL" above); here it sits one step
  -- further in, where only that working out reaches it.
  describe "an EVENT or a DEONTIC under a FOR ALL in a synonym, a field or a constructor" $ do
    let parties = Text.unlines
          [ "DECLARE Person IS ONE OF Seller, Buyer"
          , "DECLARE Action IS ONE OF delivery, payment"
          , ""
          ]
        export name input = Text.unlines
          [ "@export " <> name
          , "GIVEN x IS " <> input
          , "GIVETH A BOOLEAN"
          , "`" <> name <> "` x MEANS TRUE"
          ]
        quantified builtin = "FOR ALL a (" <> builtin <> " Person Action)"
        synonym builtin = parties <> Text.unlines
          [ "DECLARE Q IS " <> quantified builtin
          , ""
          ] <> export "takes q" "A Q"
        field builtin = parties <> Text.unlines
          [ "DECLARE R HAS f IS " <> quantified builtin
          , ""
          ] <> export "takes r" "AN R"
        constructor builtin = parties <> Text.unlines
          [ "DECLARE S IS ONE OF"
          , "  Mk HAS f IS " <> quantified builtin
          , "  None"
          , ""
          ] <> export "takes s" "AN S"

    it "refuses an EVENT under a FOR ALL that a synonym stands for" $
      unsendableRefusals emptyVFS (synonym "EVENT") `shouldReturn` ([("takes q", "x")], [])

    it "refuses a DEONTIC under a FOR ALL that a synonym stands for" $
      unsendableRefusals emptyVFS (synonym "DEONTIC") `shouldReturn` ([], [("takes q", "x")])

    it "refuses an EVENT under a FOR ALL in a field of a record" $
      unsendableRefusals emptyVFS (field "EVENT") `shouldReturn` ([("takes r", "x")], [])

    it "refuses a DEONTIC under a FOR ALL in a field of a record" $
      unsendableRefusals emptyVFS (field "DEONTIC") `shouldReturn` ([], [("takes r", "x")])

    it "refuses an EVENT under a FOR ALL in a field of a constructor" $
      unsendableRefusals emptyVFS (constructor "EVENT") `shouldReturn` ([("takes s", "x")], [])

    it "refuses a DEONTIC under a FOR ALL in a field of a constructor" $
      unsendableRefusals emptyVFS (constructor "DEONTIC") `shouldReturn` ([], [("takes s", "x")])

  -- The input check reads three lists from the body of an exported rule
  -- ('BodyReads'), and the order of each tells it which input to refuse, for
  -- which type, and how to spell the input's name. 'bodyReads' finds them in one
  -- walk of the body; these examples compare it, list by list and in order,
  -- with a generic traversal of the syntax tree on every rule of a module.
  describe "the walk of the body of an exported rule (bodyReads)" $ do
    it "finds what a generic traversal finds, in the same order, at every place of a read" $ do
      results <- mapM (walkDisagreementsOf . readsAt . snd) placesOfARead
      concat [ d | (d, _, _) <- results ] `shouldBe` []
      -- each module has `double` and `the rule`, and each body calls `f` on an argument
      sum [ rules | (_, rules, _) <- results ] `shouldSatisfy` (>= 2 * length placesOfARead)
      sum [ refs | (_, _, refs) <- results ] `shouldSatisfy` (>= 2 * length placesOfARead)

    it "finds what a generic traversal finds, in the same order, in reads that are written in another order" $ do
      let src = Text.unlines
            [ "DECLARE Person IS ONE OF Seller, Buyer"
            , "DECLARE Action IS ONE OF delivery, payment"
            , ""
            , "§ `Defs`"
            , "GIVEN a IS A TYPE"
            , "GIVETH AN a"
            , "ASSUME x"
            , ""
            , "§ `Rules`"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "double n MEANS n * 2"
            , ""
            , "`at first` MEANS"
            , "  AT `Defs`.x PARTY (IF x THEN Seller ELSE Buyer) DOES delivery"
            , ""
            , "GIVETH A NUMBER"
            , "`nested` MEANS"
            , "  CONSIDER double x"
            , "  WHEN 0 THEN k"
            , "  OTHERWISE double (`Defs`.x + k)"
            , "  WHERE"
            , "    k MEANS"
            , "      CONSIDER x"
            , "      WHEN 1 THEN double x"
            , "      OTHERWISE m"
            , "      WHERE"
            , "        ASSUME m IS A NUMBER"
            ]
      (disagreements, rules, refs) <- walkDisagreementsOf src
      disagreements `shouldBe` []
      rules `shouldBe` 3
      refs `shouldSatisfy` (> 10)

    it "finds what a generic traversal finds, in the same order, in every rule of the libraries that come with L4" $ do
      -- A name with a hyphen in it is written in backticks; a library that does
      -- not import drops out of the list below, so every one must be in it.
      let imported =
            nubBy (\a b -> a.riModuleName == b.riModuleName)
              [ ri
              | name <- embeddedLibraryNames
              , Right r <- [checkWithImports emptyVFS ("IMPORT `" <> name <> "`")]
              , ri <- r.tcdResolvedImports
              ]
      [ name | name <- embeddedLibraryNames, name `notElem` map (.riModuleName) imported ]
        `shouldBe` []
      [ (ri.riModuleName, d) | ri <- imported, d <- walkDisagreements ri.riTypeChecked.program ]
        `shouldBe` []
      sum [ referencesWalked ri.riTypeChecked.program | ri <- imported ] `shouldSatisfy` (> 0)

  -- The web editor runs the same checker and shows its error list: 'l4Check' is
  -- what the WASM language server answers with, an error being severity 1.
  describe "the web editor's check (l4Check) of a DEONTIC input" $ do
    it "reports an error, with the words `l4 check` prints" $ do
      let diagnostics = l4Check $ Text.unlines
            [ "DECLARE Person IS ONE OF Seller, Buyer"
            , "DECLARE Action IS ONE OF delivery, payment"
            , ""
            , "@export Is a duty already fulfilled"
            , "GIVEN d IS A DEONTIC Person Action"
            , "GIVETH A BOOLEAN"
            , "`already fulfilled` d MEANS TRUE"
            ]
      diagnostics `shouldSatisfy` Text.isInfixOf "DEONTIC inputs are not supported for @export."
      diagnostics `shouldSatisfy` Text.isInfixOf "\"severity\":1"
      -- one diagnostic, and none that is not an error
      Text.count "\"severity\"" diagnostics `shouldBe` 1

  describe "exported return type display" $ do
    -- A concrete inferred return type renders normally.
    it "renders a concrete inferred return type" $ do
      let src = Text.unlines
            [ "@export Adds one"
            , "GIVEN `x` IS A NUMBER"
            , "`plus one` MEANS `x` + 1"
            ]
      exportedReturnTypes src `shouldBe` Right [("plus one", "NUMBER")]

    -- A genuinely polymorphic inferred return type must normalise residual
    -- inference variables to stable names (a, b, …), never an edit-order
    -- dependent id like "res184" or "A3" that would make the deployed schema
    -- non-deterministic and trip the breaking-change check.
    it "normalises a residual inference variable to a stable type-variable name" $ do
      let src = Text.unlines
            [ "IMPORT prelude"
            , ""
            , "@export Empty list"
            , "`xs` MEANS EMPTY"
            ]
      case exportedReturnTypes src of
        Left errs -> fail $ "Fatal: " ++ show errs
        Right rts -> do
          rts `shouldBe` [("xs", "LIST OF a")]
          -- And crucially: no raw inference-variable id leaks.
          all (not . Text.isInfixOf "res" . snd) rts `shouldBe` True
