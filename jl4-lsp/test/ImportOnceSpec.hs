{-# LANGUAGE PatternSynonyms #-}
-- | A module that several others import is checked and evaluated once, however
-- many import paths lead to it (smucclaw/l4-ide#1008).
--
-- The rules used to be keyed by the chain of importers as well as by the file,
-- so a module reached by k paths was checked k times, and a module that
-- imports every module before it (the shape of a library split into layers) was
-- reached by 2^(n-2) paths. The cost shows as work, not only as time, so these
-- examples count it: every check of a module publishes that module's
-- diagnostics, so the number of copies of one diagnostic in the store is the
-- number of times the module was checked. No example here depends on how fast
-- the machine is.
--
-- The last examples pin what the change must not touch: an import cycle is
-- still reported, and an IMPORT that names nothing is still reported as a
-- missing module and not as a cycle.
module ImportOnceSpec (spec, Mode (..), runTree, withTree, fun, diamond, tour) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import Data.List (nub)
import Data.Maybe (isJust)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectory, getTemporaryDirectory, removeFile, removePathForcibly)
import System.FilePath (takeBaseName, (<.>), (</>))
import System.IO (hClose, openTempFile)

import Language.LSP.Protocol.Types
  ( Diagnostic (..)
  , DiagnosticSeverity (..)
  , NormalizedUri
  , Uri (..)
  , fromNormalizedUri
  , normalizedFilePathToUri
  )

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Syntax (Module (..))
import L4.TracePolicy (lspDefaultPolicy)
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics)
import LSP.L4.Rules (EvaluateLazy (..), SuccessfulTypeCheck (..), TypeCheckResult (..), pattern TypeCheck)

import Test.Hspec

data Mode
  = Check -- ^ type-check the entry file, as @l4 check@ does
  | Run -- ^ and evaluate it, as @l4 run@ does

-- | Write the files (one @name.l4@ per entry) into a directory that no other
-- run shares, hand its path to the action, and remove it afterwards.
--
-- The directory used to be one fixed name per label under the temporary
-- directory, so two runs of this suite on one machine (two gates, two
-- terminals) wrote and deleted each other's files, and one of them failed with
-- a file that did not exist. @openTempFile@ creates its file exclusively, so
-- the name it picks is nobody else's, and the directory takes a name made from
-- that one. The label only makes a stray directory easy to recognise.
withTree :: String -> [(String, T.Text)] -> (FilePath -> IO a) -> IO a
withTree label files act = bracket reserve release \(_, dir) -> do
  forM_ files \(name, src) -> T.writeFile (dir </> name <.> "l4") src
  act dir
 where
  reserve = do
    tmp <- getTemporaryDirectory
    (marker, h) <- openTempFile tmp ("jl4-lsp-test-import-once-" <> label)
    hClose h
    let dir = marker <> ".d"
    createDirectory dir
    pure (marker, dir)
  release (marker, dir) = removePathForcibly dir >> removeFile marker

-- | Write the files into a fresh directory ('withTree') and run the real rules
-- over the entry file. Returns every diagnostic published to the store, across
-- the whole import closure, and the entry file's result.
runTree :: String -> Mode -> [(String, T.Text)] -> String -> IO ([FileDiagnostic], Maybe TypeCheckResult)
runTree label mode files entry = withTree label files \dir -> do
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_logs, diags, mTc) <- oneshotL4ActionAndDiagnostics evalConfig (dir </> entry <.> "l4") \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    case mode of
      Check -> Shake.use TypeCheck uri
      Run -> do
        mtc <- Shake.use SuccessfulTypeCheck uri
        _ <- Shake.use EvaluateLazy uri
        pure mtc
  pure (diags, mTc)

-- | The diagnostics stored for the file called @name@.l4 whose message has the
-- given text in it.
about :: String -> T.Text -> [FileDiagnostic] -> [FileDiagnostic]
about name needle ds =
  [ d
  | d <- ds
  , ("/" <> T.pack name <> ".l4") `T.isSuffixOf` (fromNormalizedUri d.fdFilePath).getUri
  , needle `T.isInfixOf` d.fdLspDiagnostic._message
  ]

-- | A function of one number called @name@ with the given body.
fun :: T.Text -> T.Text -> T.Text
fun name body = T.unlines ["GIVEN x IS A NUMBER", "GIVETH A NUMBER", name <> " x MEANS " <> body, ""]

-- | The module that fails to check: PLUS wants a number on its right.
typeError :: T.Text
typeError = fun "broken" "x PLUS TRUE"

-- | A module that evaluates one directive.
withEval :: T.Text
withEval = fun "base" "x PLUS 100" <> "#EVAL base 1\n"

-- | @bottom@ imported by @left@ and by @right@, both imported by @top@: two
-- paths to @bottom@.
diamond :: T.Text -> [(String, T.Text)]
diamond bottom =
  [ ("bottom", bottom)
  , ("left", "IMPORT bottom\n\n" <> fun "lf" "x PLUS 1")
  , ("right", "IMPORT bottom\n\n" <> fun "rt" "x PLUS 2")
  , ("top", "IMPORT left\nIMPORT right\n\n" <> fun "tp" "lf x PLUS rt x")
  ]

-- | @n@ modules @m1@ .. @mn@, each importing the prelude and every module
-- before it, so @m1@ is reached by 2^(n-2) paths from @mn@. @m1@ is the given
-- text.
tour :: Int -> T.Text -> [(String, T.Text)]
tour n first =
  [ ("m" <> show k, header k <> if k == 1 then first else fun ("f" <> T.pack (show k)) (T.pack (show k)))
  | k <- [1 .. n]
  ]
 where
  header k = T.unlines (map ("IMPORT " <>) ("prelude" : [T.pack ("m" <> show j) | j <- [1 .. k - 1]])) <> "\n"

moduleUris :: TypeCheckResult -> [NormalizedUri]
moduleUris tc = [u | d <- tc.dependencies, let MkModule _ u _ = d.module']

spec :: Spec
spec = do
  checkedOnce
  evaluatedOnce
  cyclesAndMissingModules

checkedOnce :: Spec
checkedOnce = describe "a module reached by more than one import path" $ do
  it "reports its type error once when two paths lead to it" $ do
    (diags, _) <- runTree "diamond-check" Check (diamond typeError) "top"
    length (about "bottom" "second argument of PLUS" diags) `shouldBe` 1

  it "reports its type error once when 2^4 paths lead to it" $ do
    -- Six modules, each importing the five before it: m1 is reached by
    -- 2^(6-2) = 16 paths. Checked once per path it was reported 16 times.
    (diags, _) <- runTree "tour-check" Check (tour 6 typeError) "m6"
    length (about "m1" "second argument of PLUS" diags) `shouldBe` 1

  it "is listed once among the modules the importer depends on" $ do
    -- The prelude and m1 .. m5. The list used to hold a module once per path:
    -- 2^6 - 1 = 63 entries for these six.
    (_, mTc) <- runTree "tour-closure" Check (tour 6 (fun "ok" "1")) "m6"
    case mTc of
      Nothing -> expectationFailure "m6 did not type-check"
      Just tc -> do
        let uris = moduleUris tc
        length uris `shouldBe` length (nub uris)
        length [u | u <- uris, takeBaseName (T.unpack (fromNormalizedUri u).getUri) `elem` ["m1", "m2", "m3", "m4", "m5"]]
          `shouldBe` 5

evaluatedOnce :: Spec
evaluatedOnce = describe "a module reached by more than one import path, when the importer is run" $ do
  -- Running the importer type-checks it, then evaluates it on top of the
  -- evaluated heaps of its imports. The evaluation of an import used to
  -- recurse under a call stack of its own, as the type check did.
  it "reports its type error once when two paths lead to it" $ do
    (diags, _) <- runTree "diamond-run" Run (diamond typeError) "top"
    length (about "bottom" "second argument of PLUS" diags) `shouldBe` 1

  it "reports its type error once when 2^3 paths lead to it" $ do
    (diags, _) <- runTree "tour-run" Run (tour 5 typeError) "m5"
    length (about "m1" "second argument of PLUS" diags) `shouldBe` 1

cyclesAndMissingModules :: Spec
cyclesAndMissingModules = describe "what the change leaves as it was" $ do
  -- No rule follows an import into a ring, so the engine never sees one: the
  -- error is on the IMPORT, in words, and names the files of the ring. Before
  -- that the engine stopped the ring and published a StackException on one of
  -- its files, or, with two threads in the ring at once, hung.
  forM_
    [ ("a file that imports itself", "self", [("selfie", "IMPORT selfie\n\n" <> fun "f" "x")], "selfie")
    , ( "two files that import each other"
      , "ring2"
      , [("ra", "IMPORT rb\n\n" <> fun "fa" "x"), ("rb", "IMPORT ra\n\n" <> fun "fb" "x")]
      , "ra"
      )
    , ( "three files in a ring"
      , "ring3"
      , [ ("r3a", "IMPORT r3b\n\n" <> fun "fa" "x")
        , ("r3b", "IMPORT r3c\n\n" <> fun "fb" "x")
        , ("r3c", "IMPORT r3a\n\n" <> fun "fc" "x")
        ]
      , "r3a"
      )
    ] \(what, label, files, entry) ->
    it ("still reports an import cycle: " <> what) $ do
      (diags, _) <- runTree label Run files entry
      [ d
        | d <- diags
        , d.fdLspDiagnostic._severity == Just DiagnosticSeverity_Error
        , any (`T.isInfixOf` d.fdLspDiagnostic._message) ["ring of imports", "cannot import itself"]
        ]
        `shouldSatisfy` (not . null)
      length [d | d <- diags, "StackException" `T.isInfixOf` d.fdLspDiagnostic._message] `shouldBe` 0

  it "reports an IMPORT that names no module as a missing module, not as a cycle" $ do
    -- GetImports gives an IMPORT that resolves to nothing the importing file's
    -- own URI, a placeholder. Read as a dependency it would be a file that
    -- depends on itself.
    (diags, mTc) <- runTree "missing" Run [("lonely", "IMPORT nosuchmodule\n\n" <> withEval)] "lonely"
    length (about "lonely" "I could not find a module with this name: nosuchmodule" diags) `shouldBe` 1
    length (about "lonely" "StackException" diags) `shouldBe` 0
    length (about "lonely" "depends on itself" diags) `shouldBe` 0
    -- the rest of the file is still checked and run
    isJust mTc `shouldBe` True
    length (about "lonely" "101" diags) `shouldBe` 1
