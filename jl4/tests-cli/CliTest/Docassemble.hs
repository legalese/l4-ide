-- | Black-box tests for @l4 export docassemble@ (the bare interview,
-- @--package@, citations and the glossary, the M2 repairs, and M4 breadth),
-- with the fixtures and helpers only they use. Split out of @Main.hs@ so a
-- release can be sliced per backend.
module CliTest.Docassemble (spec, fixtures) where

import Control.Monad (unless, when)
import Data.List (findIndex, isInfixOf, isPrefixOf, sort)
import qualified Data.ByteString as BS
import qualified Data.Text as T
import System.Directory
  ( copyFile
  , createDirectoryIfMissing
  , doesDirectoryExist
  , doesFileExist
  , getTemporaryDirectory
  , listDirectory
  , removePathForcibly
  )
import System.Exit (ExitCode(..))
import System.FilePath ((</>))
import Test.Hspec

import qualified L4.Docassemble.Emit as DAEmit

import CliTest.Common

----------------------------------------------------------------------------
-- `l4 export docassemble` (M2): the package tree, citations and the glossary
--
-- Everything in this section pins DOCASSEMBLE-EXPORT-SPEC.md §10 (M2) and the
-- two rulings it leans on, R11 (§8.11, artifact shape) and R9 (§8.9, emission
-- hygiene). The M1 surface — six byte-golden examples plus the not-ok/
-- refusals — is pinned separately, in `describe "l4 export docassemble"`, and must
-- stay green through M2: packaging is an ADDITIONAL artifact shape, not a
-- change to the bare one.
----------------------------------------------------------------------------

daExampleDir :: FilePath
daExampleDir = "examples/docassemble"

-- | The M2 example: three sub-decisions, each with a statutory @\@ref@,
-- conjoined by AND so a FALSE first conjunct short-circuits the other two
-- away. Its second citation uses the inline @\<\< \>\>@ ref form and its third
-- is deliberately Mako-hostile.
daCitationsSource :: FilePath
daCitationsSource = daExampleDir </> "citations.l4"

-- | Every example with a committed @.yml@ and @.fidelity.txt@ golden under
-- @examples/docassemble/expected/@: the six from M1, @citations@ from M2, and
-- the six M4 examples. Each RED phase deliberately left its own goldens
-- unwritten (\"writing a golden before the feature exists would force the
-- implementer to match formatting choices I have no basis to decide\") and each
-- GREEN phase supplied them once the shape was settled.
daBareExamples :: [String]
daBareExamples =
  [ "rodents-and-vermin", "seam", "enum-triage"
  , "defaults", "computed-and-shadow", "assume-via-fn", "citations"
  , "tenant-list", "payload-enum", "maybe-scalars", "statutory-age"
  , "review-checklist", "notice-letter"
  ]

-- | The M4 examples (spec §10: breadth). The assertions below are about SHAPE
-- (which keys, which guards, which idiom) or about BEHAVIOUR (through the R10
-- harness); the byte goldens the GREEN phase added pin the FORMATTING, which
-- shape assertions cannot.
--
-- Each file typechecks and evaluates in L4 (its @#EVAL@s are the oracle).
daListSource, daPayloadSource, daMaybeSource, daDateSource,
  daReviewSource, daLetterSource, daLetterTemplate :: FilePath
daListSource     = daExampleDir </> "tenant-list.l4"
daPayloadSource  = daExampleDir </> "payload-enum.l4"
daMaybeSource    = daExampleDir </> "maybe-scalars.l4"
daDateSource     = daExampleDir </> "statutory-age.l4"
daReviewSource   = daExampleDir </> "review-checklist.l4"
daLetterSource   = daExampleDir </> "notice-letter.l4"
daLetterTemplate = daExampleDir </> "notice-letter.letter.md"

-- | The @not-ok/@ fixtures M4 does NOT own, paired with the diagnostic each
-- must keep. M4 flips exactly two refusals (@maybe-number@ and
-- @just-payload-pattern@, both folded into @maybe-scalars.l4@); these four are
-- out of its scope and a change to any of them is a regression, not progress.
daStillRefused :: [(FilePath, String)]
daStillRefused =
  [ ( "deontic-body.l4"
    , "deontic/regulative rule (PARTY MUST/MAY/SHANT) has no docassemble form" )
  , ( "name-collision.l4"
    , "name collision: `t.notice_period`" )
  , ( "higher-order.l4"
    , "higher-order use of function `is positive`" )
  , ( "seam-ref-via-fn.l4"
    , "seam-shaped export (top-level IMPLIES) is referenced by another decision" )
  ]

-- | The @not-ok/@ fixtures the 2026-08-17 repair pass ADDED, each pinning a
-- refusal that replaced a silently wrong emission. Kept apart from
-- 'daStillRefused', which is the out-of-scope set: these two are M4's own, and
-- both are required to be reported in L4 terms rather than as an internal id
-- collision.
daM4Refused :: [(FilePath, String)]
daM4Refused =
  [ ( "maybe-empty-string.l4"
    , "`WHEN JUST \"\"` on a MAYBE STRING is refused" )
  , ( "payload-name-collision.l4"
    , "name collision: `d.the_reason` is produced by two different question blocks" )
  ]

-- | Emit an M4 example, reporting the refusal VERBATIM when it is still
-- refused. Written fail-first, when every one of these exited 1 with prose
-- naming the milestone that owed the answer; they all emit now, and the
-- verbatim stderr is what makes a REGRESSION legible rather than merely red.
daEmit :: FilePath -> FilePath -> IO String
daEmit bin src = do
  Output code sout serr <- runL4 bin ["export", "docassemble", src]
  case code of
    ExitSuccess   -> pure sout
    ExitFailure n -> do
      expectationFailure $
        "`l4 export docassemble " ++ src ++ "` exited " ++ show n
        ++ ": the M4 construct this example exists for is still refused."
        ++ "\n--- stderr ---\n" ++ serr
      pure ""

-- | Assert at least one of several spellings is present. Used where more than
-- one emission is defensible and the RED phase declines to pick — the gather
-- control questions, for instance, where a @target_number@ shape and a
-- @there_are_any@ + @there_is_another@ shape were both probed working.
shouldContainAny :: String -> String -> [String] -> IO ()
shouldContainAny what haystack needles =
  unless (any (`isInfixOf` haystack) needles) $
    expectationFailure $
      what ++ " contains none of " ++ show needles
      ++ "\n--- got ---\n" ++ haystack

-- | Fixtures for the docassemble repair cases, which are CLI shape probes
-- rather than corpus exhibits and so live beside the other @tests-cli@
-- fixtures, not in @examples/docassemble/@.
daGlossLossSource, daRuntimeCollisionSource :: FilePath
daGlobalShadowSource, daGatheredMaybeSource :: FilePath
daGlossLossSource        = fixtureDir </> "docassemble-glossary-losses.l4"
daRuntimeCollisionSource = fixtureDir </> "docassemble-runtime-collision.l4"
-- The other two thirds of the same namespace hazard (repair pass, 2026-08-17):
-- Python's builtins and `docassemble.base.util`'s star-import.
daGlobalShadowSource     = fixtureDir </> "docassemble-global-shadow.l4"
-- A paired `MAYBE NUMBER` inside a gathered element: the one place the
-- changed-answer repair does NOT reach, declared rather than silent.
daGatheredMaybeSource    = fixtureDir </> "docassemble-gathered-maybe.l4"

-- | The four citations carried by @citations.l4@, herald-stripped: L4's own
-- @\@ref @ prefix and the inline @\<\< \>\>@ delimiters are L4 syntax and must
-- never reach a user-facing docassemble screen.
daCite1, daCite2, daCite3Tail, daCiteGoal :: String
daCite1 = "17 CFR 227.100(a)(1) — offering maximum"
daCite2 = "17 CFR 227.100(a)(3) — sales through one intermediary only"
-- The third citation begins with @%@ and contains a literal @${ … }@, so its
-- emitted spelling depends on which escape the emitter applies; only its
-- stable tail is asserted verbatim, and the hostile halves get their own
-- assertions (see the R9 escaping example).
daCite3Tail = "17 CFR 227.300(a)"
-- The fourth rides on the EXPORTED decide, and therefore on the goal @code:@
-- block. It is what makes the emitted ORDER observable: the emitter puts
-- @explain()@ after the assignment, and the goal's assignment is what pulls on
-- the sub-rules, so the goal completes last and its citation prints last. On
-- the three sub-rules alone the placement is unobservable — moving every
-- @explain()@ above its assignment left the round-trip harness fully green
-- until this citation existed.
daCiteGoal = "17 CFR 227.100 — the crowdfunding exemption"

-- | The generated Python package directory inside a @--package@ tree for
-- @citations.l4@: @docassemble/l4citations@ (R11: @docassemble.l4\<slug\>@).
daPkgInner :: FilePath
daPkgInner = "docassemble" </> "l4citations"

-- | Every regular file under @root@, as sorted paths relative to @root@.
treeFiles :: FilePath -> IO [FilePath]
treeFiles root = sort <$> go ""
 where
  go rel = do
    entries <- sort <$> listDirectory (root </> rel)
    concat <$> mapM (child rel) entries
  child rel e = do
    let r = if null rel then e else rel </> e
    isDir <- doesDirectoryExist (root </> r)
    if isDir then go r else pure [r]

-- | Directories under @root@ (relative paths) holding nothing at all. R11:
-- \"every emitted @data/@ subdirectory carries at least one real file (empty
-- directories survive neither git nor zip)\".
emptyTreeDirs :: FilePath -> IO [FilePath]
emptyTreeDirs root = sort <$> go ""
 where
  go rel = do
    entries <- sort <$> listDirectory (root </> rel)
    let here = [rel | null entries, not (null rel)]
    subs <- concat <$> mapM (child rel) entries
    pure (here ++ subs)
  child rel e = do
    let r = if null rel then e else rel </> e
    isDir <- doesDirectoryExist (root </> r)
    if isDir then go r else pure []

-- | Run @l4 export docassemble FILE --package DIR@ into a FRESH directory and return
-- the written tree's sorted file list.
--
-- The failure message names the milestone deliberately: until M2 lands the
-- option does not exist, and an \"Invalid option\" exit is the honest RED
-- signal, not a broken test.
expectPackage :: FilePath -> FilePath -> FilePath -> IO [FilePath]
expectPackage bin src outDir = do
  removePathForcibly outDir
  Output code sout serr <- runL4 bin ["export", "docassemble", src, "--package", outDir]
  unless (code == ExitSuccess) $
    expectationFailure $
      "`l4 export docassemble " ++ src ++ " --package " ++ outDir ++ "` did not succeed: exited "
      ++ show code
      ++ "\n(M2/R11: --package DIR must write an installable PEP 420 package tree)"
      ++ "\n--- stdout ---\n" ++ sout
      ++ "\n--- stderr ---\n" ++ serr
  isDir <- doesDirectoryExist outDir
  unless isDir $
    expectationFailure ("no package tree was written at " ++ outDir)
  treeFiles outDir

-- | The single emitted block whose @id:@ is exactly @wanted@.
blockWithId :: String -> String -> IO String
blockWithId sout wanted =
  case [ b | b <- yamlBlocks sout, ("id: " ++ wanted) `elem` lines b ] of
    [b] -> pure b
    []  -> do
      expectationFailure $
        "no emitted block carries `id: " ++ wanted ++ "`"
        ++ "\n--- emitted interview ---\n" ++ sout
      pure ""
    bs  -> do
      expectationFailure $
        "expected exactly one block with `id: " ++ wanted
        ++ "`, found " ++ show (length bs)
      pure ""

-- | Assert that @a@ occurs before @b@ inside @haystack@, and that both occur.
-- The half of an ordering claim a pair of @shouldContain'@s cannot make.
shouldPrecede :: String -> String -> String -> String -> IO ()
shouldPrecede what haystack a b =
  case (findSub a, findSub b) of
    (Just i, Just j)
      | i < j     -> pure ()
      | otherwise -> expectationFailure $
          what ++ ": expected " ++ show a ++ " to come before " ++ show b
              ++ ", but it does not\n--- got ---\n" ++ haystack
    _ -> expectationFailure $
      what ++ ": expected both " ++ show a ++ " and " ++ show b
          ++ " to occur\n--- got ---\n" ++ haystack
 where
  findSub n = findIndex (n `isPrefixOf`) (tails' haystack)
  tails' s = s : case s of { [] -> []; (_ : r) -> tails' r }

-- | Files this module's tests need to exist. 'Main.main' checks every
-- module's list before hspec runs anything.
fixtures :: [FilePath]
fixtures =
  [ daCitationsSource
  ]

spec :: FilePath -> Spec
spec bin = do
  describe "l4 export docassemble" $ do
    it "compiles the WHERE-heavy rodents example to its golden interview (R3 survival)" $
      expectGolden bin ["export", "docassemble", "examples/docassemble/rodents-and-vermin.l4"]
                       "examples/docassemble/expected/rodents-and-vermin.yml"

    it "compiles the top-level IMPLIES seam example (R4 verdict driver)" $
      expectGolden bin ["export", "docassemble", "examples/docassemble/seam.l4"]
                       "examples/docassemble/expected/seam.yml"

    it "compiles a 3-way enum CONSIDER to a radio question + elif chain (R6)" $
      expectGolden bin ["export", "docassemble", "examples/docassemble/enum-triage.l4"]
                       "examples/docassemble/expected/enum-triage.yml"

    it "compiles TYPICALLY prefills + MAYBE optionality with Mako-hostile @desc (R7/R8/R9)" $
      expectGolden bin ["export", "docassemble", "examples/docassemble/defaults.l4"]
                       "examples/docassemble/expected/defaults.yml"

    it "keeps attributes out of the DAObject namespace + inlines a computed field (R2)" $
      expectGolden bin ["export", "docassemble", "examples/docassemble/computed-and-shadow.l4"]
                       "examples/docassemble/expected/computed-and-shadow.yml"

    it "emits a question for an ASSUME referenced only through an inlined function (R3)" $
      expectGolden bin ["export", "docassemble", "examples/docassemble/assume-via-fn.l4"]
                       "examples/docassemble/expected/assume-via-fn.yml"

    it "drives the seam scope-first, never as the classical short-circuit (R4)" $ do
      Output code sout _ <- runL4 bin ["export", "docassemble", "examples/docassemble/seam.l4"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("if notice_rule_satisfied_scope:" `isInfixOf`)
      sout `shouldSatisfy` (not . ("not notice_rule_satisfied_scope or" `isInfixOf`))

    it "refuses a deontic body by name (Regulative, Blocking)" $ do
      Output code _ serr <- runL4 bin ["export", "docassemble", "examples/docassemble/not-ok/deontic-body.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("deontic/regulative rule (PARTY MUST/MAY/SHANT) has no docassemble form" `isInfixOf`)

    -- M4 flips the two R8 refusals M1 shipped: `not-ok/maybe-number.l4` and
    -- `not-ok/just-payload-pattern.l4` are now `../maybe-scalars.l4`, a
    -- SUPPORTED example, and their assertions moved to the M4 describe block
    -- below. What is left refusing is `MAYBE <enum>` — see
    -- "still refuses MAYBE of an enum" there, which also pins the diagnostic
    -- against the false claim M4 would otherwise leave behind.

    it "refuses a post-sanitisation name collision, naming both originals" $ do
      Output code _ serr <- runL4 bin ["export", "docassemble", "examples/docassemble/not-ok/name-collision.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("name collision: `t.notice_period`" `isInfixOf`)
      serr `shouldSatisfy` ("L4 `notice period`" `isInfixOf`)
      serr `shouldSatisfy` ("L4 `notice_period`" `isInfixOf`)

    it "refuses a function value passed as data, by the function's own name (R3)" $ do
      Output code _ serr <- runL4 bin ["export", "docassemble", "examples/docassemble/not-ok/higher-order.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("higher-order use of function `is positive`" `isInfixOf`)

    it "refuses a seam-goal reference that travels through an inlined function (R4 guard)" $ do
      Output code _ serr <- runL4 bin ["export", "docassemble", "examples/docassemble/not-ok/seam-ref-via-fn.l4"]
      code `shouldBe` ExitFailure 1
      serr `shouldSatisfy` ("seam-shaped export (top-level IMPLIES) is referenced by another decision" `isInfixOf`)

    it "gates on advisory fidelity notes with --fail-on=advisory" $
      expectFail bin ["export", "docassemble", "examples/docassemble/defaults.l4", "--fail-on=advisory"]

    it "emits only block keys docassemble 1.10.7 recognises (R9.5 vocabulary)" $
      DAEmit.emitterVocabularyViolations `shouldBe` []

    it "fails on a file that does not typecheck" $
      expectFail bin ["export", "docassemble", errorFixture]

    -- M1 regression, tightened for M2: the six goldens above pin STDOUT.
    -- `-o` is a different code path (it also drops the fidelity report into a
    -- sibling .fidelity.txt), and the six committed .fidelity.txt files were
    -- pinned by no test at all. Both are pinned here so that M2's --package
    -- work cannot quietly change the bare artifact.
    it "writes to --output exactly the stdout bytes, plus the committed fidelity sidecar" $
      for_ daBareExamples \stem -> do
        tmp <- getTemporaryDirectory
        let outFile = tmp </> ("l4-da-out-" ++ stem ++ ".yml")
            sidecar = tmp </> ("l4-da-out-" ++ stem ++ ".fidelity.txt")
        removePathForcibly outFile
        removePathForcibly sidecar
        Output code sout serr <-
          runL4 bin ["export", "docassemble", daExampleDir </> (stem ++ ".l4"), "-o", outFile]
        unless (code == ExitSuccess) $
          expectationFailure (stem ++ ": -o run failed\n--- stderr ---\n" ++ serr)
        sout `shouldBe` ""
        written   <- readUtf8 outFile
        goldenYml <- readUtf8 (daExampleDir </> "expected" </> (stem ++ ".yml"))
        unless (written == goldenYml) $
          expectationFailure (stem ++ ": -o bytes differ from the committed golden")
        haveSidecar <- doesFileExist sidecar
        unless haveSidecar $
          expectationFailure (stem ++ ": -o wrote no .fidelity.txt sibling")
        gotReport  <- readUtf8 sidecar
        wantReport <- readUtf8 (daExampleDir </> "expected" </> (stem ++ ".fidelity.txt"))
        unless (gotReport == wantReport) $
          expectationFailure $
            stem ++ ": fidelity sidecar differs from its committed golden"
            ++ "\n--- got ---\n" ++ gotReport ++ "\n--- golden ---\n" ++ wantReport
        removePathForcibly outFile
        removePathForcibly sidecar

  ----------------------------------------------------------------------------
  -- M2 (spec §10): the installable package tree (R11 §8.11)
  --
  -- R11 is explicit that this artifact gets "a shape test, not byte goldens",
  -- so every assertion below is about the SHAPE of the written tree: which
  -- files exist, which must NOT exist, what they say, and that two runs agree.
  ----------------------------------------------------------------------------
  describe "l4 export docassemble --package (M2/R11: the installable package tree)" $ do
    it "writes the PEP 420 shape, including the namespace __init__.py that must be ABSENT" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-shape"
      files <- expectPackage bin daCitationsSource dir
      let wanted =
            [ "pyproject.toml"
            , "MANIFEST.in"
            -- R11 decision 4: the fidelity report is part of the shape, at the
            -- package root under the same-stem convention `-o FILE` uses.
            , "citations.fidelity.txt"
            , daPkgInner </> "__init__.py"
            , daPkgInner </> "l4runtime.py"
            , daPkgInner </> "data" </> "questions" </> "citations.yml"
            , daPkgInner </> "data" </> "sources"   </> "citations.l4"
            ]
      for_ wanted \want ->
        unless (want `elem` files) $
          expectationFailure $
            "package tree is missing " ++ show want
            ++ "\n--- tree ---\n" ++ unlines files
      -- The absence is a REQUIREMENT, not a detail: setuptools' pyproject path
      -- defaults to PEP 420 namespace finding, and a namespace __init__.py
      -- turns `docassemble` into a regular package that shadows the installed
      -- `docassemble.base`. The 1.10.7 exemplar has no such file — verified by
      -- `git ls-tree -r 1b6678384 docassemble_demo/ | grep -c
      -- 'docassemble_demo/docassemble/__init__.py'` => 0.
      let nsInit = "docassemble" </> "__init__.py"
      when (nsInit `elem` files) $
        expectationFailure $
          "package tree contains " ++ show nsInit
          ++ ", which breaks PEP 420 namespace finding (R11)"
      removePathForcibly dir

    it "writes a pyproject.toml naming the package, an SPDX licence, and the Python floor" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-toml"
      _ <- expectPackage bin daCitationsSource dir
      toml <- readUtf8 (dir </> "pyproject.toml")
      let has = shouldContain' "pyproject.toml" toml
      has "docassemble.l4citations"
      has "license = \""            -- PEP 639 SPDX expression, string form
      -- R11: `requires-python >= 3.12` (docassemble_base/pyproject.toml:14 at
      -- 1b6678384). Asserted as ONE substring: `has "requires-python"` and
      -- `has "3.12"` as two independent whole-file checks would be satisfied by
      -- a floor of ">= 3.9" beside any other mention of 3.12 — a comment, a
      -- classifier, a dependency pin — which is not the claim R11 makes.
      has "requires-python = \">= 3.12\""
      has "[tool.setuptools.packages.find]"
      has "where = [\".\"]"
      has "docassemble.base"        -- an installable package depends on the runtime
      removePathForcibly dir

    it "writes a MANIFEST.in grafting the data directory and shipping the report" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-manifest"
      _ <- expectPackage bin daCitationsSource dir
      manifest <- readUtf8 (dir </> "MANIFEST.in")
      shouldContain' "MANIFEST.in" manifest ("graft " ++ (daPkgInner </> "data"))
      -- MANIFEST.in governs the sdist, and a root-level file is not package
      -- data, so without this line R11 decision 4's "and MANIFEST.in includes
      -- it so it ships" is false and nothing would notice.
      shouldContain' "MANIFEST.in" manifest "include citations.fidelity.txt"
      removePathForcibly dir

    it "writes the same fidelity report the bare -o run writes, at the package root" $ do
      -- R11 decision 4 places the report at the package root rather than under
      -- data/. Its CONTENT is pinned for the bare `-o` path by the
      -- daBareExamples golden loop above; this asserts the --package copy is
      -- the same bytes, so the two placements cannot drift.
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-fidelity"
      _ <- expectPackage bin daCitationsSource dir
      got  <- readUtf8 (dir </> "citations.fidelity.txt")
      want <- readUtf8 (daExampleDir </> "expected" </> "citations.fidelity.txt")
      unless (got == want) $
        expectationFailure $
          "the packaged fidelity report differs from the committed golden"
          ++ "\n--- got ---\n" ++ got ++ "\n--- golden ---\n" ++ want
      removePathForcibly dir

    it "writes an l4runtime.py carrying the provenance API its __all__ promises" $ do
      -- Existence was asserted; content was not, and the module is the whole
      -- reason `modules:` exists in the packaged interview (R11 decision 6).
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-runtime"
      _ <- expectPackage bin daCitationsSource dir
      rt <- readUtf8 (dir </> daPkgInner </> "l4runtime.py")
      let has = shouldContain' "l4runtime.py" rt
      has "__all__"
      -- The author's spelling of the source file survives here even though the
      -- on-disk copy is renamed to <slug>.l4 (R11 decision 3).
      has "L4_SOURCE_NAME = 'citations.l4'"
      has "L4_PACKAGE_NAME = 'docassemble.l4citations'"
      has "def l4_source_path():"
      has "def l4_source_text():"
      -- It must define nothing the interview CALLS: the bare and packaged
      -- artifacts have to mean the same thing, so anything the interview needed
      -- would have to work bare too, where there is no runtime module at all.
      yml <- readUtf8 (dir </> daPkgInner </> "data" </> "questions" </> "citations.yml")
      for_ ["l4_source_path(", "l4_source_text(", "L4_SOURCE_NAME"] \name ->
        shouldNotContain' "the packaged interview" yml name
      removePathForcibly dir

    it "writes an __init__.py that opts the package out of docassemble's pre-load scan" $ do
      -- `# do not pre-load` is not decoration: docassemble's package scanner
      -- breaks out of the file on exactly that prefix
      -- (docassemble_webapp/.../packages/helpers.py:63 at 1b6678384), which is
      -- what keeps a generated package from being imported at server start.
      -- It is also byte-for-byte the shape of docassemble_demo's own __init__.
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-init"
      _ <- expectPackage bin daCitationsSource dir
      ini <- readUtf8 (dir </> daPkgInner </> "__init__.py")
      unless ("# do not pre-load" `isPrefixOf` ini) $
        expectationFailure $
          "the generated __init__.py does not open with `# do not pre-load`, so "
          ++ "docassemble's pre-load scan would keep reading it\n--- got ---\n" ++ ini
      removePathForcibly dir

    it "replaces a previous run rather than accumulating beside it" $ do
      -- Writing without deleting meant that regenerating after the .l4 was
      -- RENAMED left the whole previous inner package in the tree, and
      -- `[tool.setuptools.packages.find] where = ["."]` then found both: a
      -- wheel declaring itself docassemble.l4beta shipped an importable
      -- docassemble.l4alpha whose l4_source_text() had no data file behind it.
      -- The slug follows the source basename by design, so a rename is the
      -- designed trigger, and the command reported success throughout.
      tmp <- getTemporaryDirectory
      let srcDir = tmp </> "l4-da-regen-src"
          dir    = tmp </> "l4-da-regen"
          alpha  = srcDir </> "alpha.l4"
          beta   = srcDir </> "beta.l4"
      removePathForcibly srcDir
      removePathForcibly dir
      createDirectoryIfMissing True srcDir
      copyFile daCitationsSource alpha
      copyFile daCitationsSource beta
      _ <- expectPackage bin alpha dir
      -- expectPackage clears the directory first, so regenerate by hand.
      Output code _ serr <- runL4 bin ["export", "docassemble", beta, "--package", dir]
      unless (code == ExitSuccess) $
        expectationFailure ("regeneration failed\n--- stderr ---\n" ++ serr)
      files <- treeFiles dir
      let stale = [ f | f <- files, "l4alpha" `isInfixOf` f ]
      unless (null stale) $
        expectationFailure $
          "regenerating after a rename left the previous package in the tree: "
          ++ show stale ++ "\n--- tree ---\n" ++ unlines files
      unless ((("docassemble" </> "l4beta") </> "l4runtime.py") `elem` files) $
        expectationFailure $
          "the regenerated package is missing\n--- tree ---\n" ++ unlines files
      unless ("beta.fidelity.txt" `elem` files) $
        expectationFailure $
          "the regenerated fidelity report is missing\n--- tree ---\n" ++ unlines files
      unless ("alpha.fidelity.txt" `notElem` files) $
        expectationFailure $
          "the previous run's fidelity report survived regeneration\n--- tree ---\n"
          ++ unlines files
      removePathForcibly srcDir
      removePathForcibly dir

    it "leaves a file the user put in their own package directory alone" $ do
      -- The prune above must not become a licence to delete: guardClobber
      -- establishes that we WROTE this tree, not that we own every file in it.
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-regen-keep"
      _ <- expectPackage bin daCitationsSource dir
      writeFile (dir </> "NOTES.md") "hand-written, not ours\n"
      Output code _ serr <- runL4 bin ["export", "docassemble", daCitationsSource, "--package", dir]
      unless (code == ExitSuccess) $
        expectationFailure ("regeneration failed\n--- stderr ---\n" ++ serr)
      kept <- readUtf8 (dir </> "NOTES.md")
      kept `shouldBe` "hand-written, not ours\n"
      removePathForcibly dir

    it "embeds the .l4 source byte-identically under data/sources (that is what provenance means)" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-provenance"
      _ <- expectPackage bin daCitationsSource dir
      orig   <- BS.readFile daCitationsSource
      copied <- BS.readFile (dir </> daPkgInner </> "data" </> "sources" </> "citations.l4")
      unless (copied == orig) $
        expectationFailure
          "data/sources/citations.l4 is not byte-identical to the input .l4"
      removePathForcibly dir

    it "puts the interview under data/questions and wires the runtime module via modules:" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-questions"
      _ <- expectPackage bin daCitationsSource dir
      yml <- readUtf8 (dir </> daPkgInner </> "data" </> "questions" </> "citations.yml")
      -- It is the interview, not a stub: the driver and the goal block are in it.
      shouldContain' "data/questions/citations.yml" yml "id: driver_offering_exempt"
      shouldContain' "data/questions/citations.yml" yml "id: c_offering_exempt"
      -- R11: the runtime module is a SIBLING of data/, loaded as `.l4runtime`.
      -- The leading dot is package-name concatenation: docassemble execs
      -- `from <question.package><name> import *` (parse.py:8569-8573 at
      -- 1b6678384), so `.l4runtime` resolves to
      -- docassemble.l4citations.l4runtime.
      shouldContain' "data/questions/citations.yml" yml "modules:"
      shouldContain' "data/questions/citations.yml" yml ".l4runtime"
      removePathForcibly dir

    it "leaves no empty directory anywhere in the tree" $ do
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-empties"
      _ <- expectPackage bin daCitationsSource dir
      empties <- emptyTreeDirs dir
      unless (null empties) $
        expectationFailure $
          "empty directories in the package tree (they survive neither git nor "
          ++ "zip, R11): " ++ show empties
      removePathForcibly dir

    it "is deterministic: two runs write identical trees" $ do
      tmp <- getTemporaryDirectory
      let dirA = tmp </> "l4-da-pkg-detA"
          dirB = tmp </> "l4-da-pkg-detB"
      filesA <- expectPackage bin daCitationsSource dirA
      filesB <- expectPackage bin daCitationsSource dirB
      unless (filesA == filesB) $
        expectationFailure $
          "two --package runs wrote different file sets:\n" ++ show filesA
          ++ "\nvs\n" ++ show filesB
      for_ filesA \f -> do
        a <- BS.readFile (dirA </> f)
        b <- BS.readFile (dirB </> f)
        unless (a == b) $
          expectationFailure ("--package is non-deterministic in " ++ show f)
      removePathForcibly dirA
      removePathForcibly dirB

    -- RULING TAKEN BY THIS TEST: --package and --output are two different
    -- artifact shapes (a directory vs a file), and `-o` is already overloaded
    -- house-wide (FILE in eight verbs, DIR in `l4 trace`). Honouring one and
    -- silently ignoring the other is the failure mode with no precedent to
    -- lean on, so the combination is REFUSED by name. The exact phrase is
    -- pinned because optparse's own "Invalid option" message happens to
    -- contain both option names via the usage line, which would let a
    -- generic assertion pass for the wrong reason.
    it "refuses --package together with --output, by name" $ do
      tmp <- getTemporaryDirectory
      let dir  = tmp </> "l4-da-pkg-conflict"
          file = tmp </> "l4-da-pkg-conflict.yml"
      removePathForcibly dir
      removePathForcibly file
      Output code _ serr <-
        runL4 bin ["export", "docassemble", daCitationsSource, "-o", file, "--package", dir]
      code `shouldBe` ExitFailure 1
      shouldContain' "stderr" serr "--package cannot be combined with --output"
      wroteFile <- doesFileExist file
      wroteDir  <- doesDirectoryExist dir
      unless (not wroteFile && not wroteDir) $
        expectationFailure "a refused invocation still wrote an artifact"
      removePathForcibly dir
      removePathForcibly file

    it "derives an ASCII package slug from a hostile filename" $ do
      -- `moduleSource` is a PERCENT-ENCODED URI segment and `pyIdent` keeps
      -- non-ASCII letters, so a slug taken from either inherits `%20`/`%C3%A9`
      -- or a bare `é` — neither is usable as an on-disk Python package name.
      tmp <- getTemporaryDirectory
      let srcDir = tmp </> "l4-da-hostile-src"
          src    = srcDir </> "2024 Café Rules v2.1.l4"
          dir    = tmp </> "l4-da-pkg-hostile"
      removePathForcibly srcDir
      createDirectoryIfMissing True srcDir
      copyFile daCitationsSource src
      _ <- expectPackage bin src dir
      inner <- listDirectory (dir </> "docassemble")
      case filter (/= "__init__.py") inner of
        [pkgName] -> do
          unless ("l4" `isPrefixOf` pkgName) $
            expectationFailure $
              "generated package " ++ show pkgName ++ " is not `l4<slug>` (R11)"
          let ok c = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
          unless (all ok pkgName) $
            expectationFailure $
              "generated package name " ++ show pkgName
              ++ " is not lowercase ASCII alphanumeric; a percent-encoded or "
              ++ "non-ASCII slug is not a usable Python package name"
          toml <- readUtf8 (dir </> "pyproject.toml")
          shouldContain' "pyproject.toml" toml ("docassemble." ++ pkgName)
          -- provenance survives the rename: whatever the source file is called
          -- inside the package, its bytes are the input's bytes
          let srcsDir = dir </> "docassemble" </> pkgName </> "data" </> "sources"
          srcs <- listDirectory srcsDir
          case srcs of
            [one] -> do
              orig   <- BS.readFile src
              copied <- BS.readFile (srcsDir </> one)
              unless (copied == orig) $
                expectationFailure "data/sources copy is not byte-identical"
            other -> expectationFailure $
              "expected exactly one file under data/sources, got " ++ show other
        other -> expectationFailure $
          "expected exactly one generated package under docassemble/, got "
          ++ show other
      removePathForcibly srcDir
      removePathForcibly dir

  ----------------------------------------------------------------------------
  -- M2 (spec §10): @ref citations on the verdict screen, and the glossary
  --
  -- The claim this milestone is worth having for: the verdict screen cites the
  -- law that ACTUALLY decided the case. Short-circuited rules did not decide
  -- anything, so citing them would be citing law that never fired.
  ----------------------------------------------------------------------------
  describe "l4 export docassemble citations (M2: @ref citations and the glossary)" $ do
    it "attaches each rule's own @ref to that rule's own code block, via explain()" $ do
      Output code sout serr <- runL4 bin ["export", "docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)

      -- Rule 1: the plain `@ref` form.
      cap <- blockWithId sout "c_offering_exempt_within_the_annual_cap"
      shouldContain'    "the `within the annual cap` code block" cap "explain("
      shouldContain'    "the `within the annual cap` code block" cap daCite1
      -- A node's Anno carries at most one Ref and the NEAREST preceding ref
      -- wins (`attachRef` in ResolveAnnotation.hs), so "picked up the
      -- neighbour's citation" is a real failure mode and gets its own
      -- assertion.
      shouldNotContain' "the `within the annual cap` code block" cap daCite2
      shouldNotContain' "the `within the annual cap` code block" cap daCite3Tail
      shouldNotContain' "the `within the annual cap` code block" cap daCiteGoal

      -- Rule 2: the inline `<< >>` ref form.
      via <- blockWithId sout "c_offering_exempt_sold_through_a_single_intermediary"
      shouldContain'    "the `sold through a single intermediary` code block" via "explain("
      shouldContain'    "the `sold through a single intermediary` code block" via daCite2
      shouldNotContain' "the `sold through a single intermediary` code block" via daCite1
      shouldNotContain' "the `sold through a single intermediary` code block" via daCite3Tail
      shouldNotContain' "the `sold through a single intermediary` code block" via daCiteGoal

      -- Rule 3: the Mako-hostile ref.
      reg <- blockWithId sout "c_offering_exempt_the_intermediary_is_registered"
      shouldContain'    "the `the intermediary is registered` code block" reg "explain("
      shouldContain'    "the `the intermediary is registered` code block" reg daCite3Tail
      shouldNotContain' "the `the intermediary is registered` code block" reg daCite1
      shouldNotContain' "the `the intermediary is registered` code block" reg daCite2
      shouldNotContain' "the `the intermediary is registered` code block" reg daCiteGoal

      -- The exported DECIDE carries a @ref of its own, which attaches to the
      -- TopDecl node rather than the inner MkDecide and rides onto the GOAL
      -- code block. That path was implemented but exercised by no fixture
      -- until this one; it is also the only place the emitted ORDER is
      -- observable (see `daCiteGoal`).
      goal <- blockWithId sout "c_offering_exempt"
      shouldContain'    "the `offering exempt` goal code block" goal "explain("
      shouldContain'    "the `offering exempt` goal code block" goal daCiteGoal
      shouldNotContain' "the `offering exempt` goal code block" goal daCite1
      shouldNotContain' "the `offering exempt` goal code block" goal daCite2
      shouldNotContain' "the `offering exempt` goal code block" goal daCite3Tail
      -- The design rule the citation list depends on, asserted as a claim: the
      -- explain() call sits AFTER the assignment, because a block whose
      -- assignment raises on an undefined input has decided nothing and
      -- docassemble re-runs it once the input arrives. Cite first and the goal
      -- records itself before the rules it pulls on — measured, and caught by
      -- the round-trip harness's ordered citation list only because the goal
      -- carries a @ref at all.
      for_ [ ("c_offering_exempt_within_the_annual_cap", daCite1)
           , ("c_offering_exempt_sold_through_a_single_intermediary", daCite2)
           , ("c_offering_exempt_the_intermediary_is_registered", daCite3Tail)
           , ("c_offering_exempt", daCiteGoal)
           ] \(bid, cite) -> do
        blk <- blockWithId sout bid
        shouldPrecede ("the " ++ bid ++ " code block") blk " = " "explain('"
        shouldContain' ("the " ++ bid ++ " code block") blk cite

    it "renders logic_explanation() on every verdict screen" $ do
      Output code sout serr <- runL4 bin ["export", "docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      for_ ["ev_offering_exempt_screen_holds", "ev_offering_exempt_screen_fails"] \sid -> do
        blk <- blockWithId sout sid
        shouldContain' ("the " ++ sid ++ " screen") blk "logic_explanation()"

    it "emits one `auto terms:` glossary block, keyed on the L4 defined terms" $ do
      Output code sout serr <- runL4 bin ["export", "docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      case [ b | b <- yamlBlocks sout, "auto terms:" `isInfixOf` b ] of
        [glossary] -> do
          for_
            [ ( "Offering"
              , "A securities offering made in reliance on the crowdfunding exemption" )
            , ( "within the annual cap"
              , "The amount sold in reliance on the exemption in the preceding 12 months does not exceed $5,000,000" )
            , ( "sold through a single intermediary"
              , "The offering is conducted exclusively through a single intermediary" )
            , ( "the intermediary is registered"
              , "The intermediary is registered with the Commission as a funding portal" )
            ] \(term, defn) -> do
              shouldContain' "the `auto terms:` glossary" glossary term
              shouldContain' "the `auto terms:` glossary" glossary defn
          -- docassemble only reads `auto terms` from a block that has no
          -- `question` key: `if 'auto terms' in data and 'question' not in
          -- data` (parse.py:2878 at 1b6678384). A glossary emitted inside a
          -- question block is silently ignored.
          shouldNotContain' "the `auto terms:` glossary block" glossary "question:"
        other -> expectationFailure $
          "expected exactly one `auto terms:` block, found " ++ show (length other)
          ++ "\n--- emitted interview ---\n" ++ sout

    it "strips L4's own `@ref ` herald and the inline `<< >>` delimiters" $ do
      Output code sout serr <- runL4 bin ["export", "docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      -- The inline form's text must ARRIVE …
      shouldContain' "the emitted interview" sout daCite2
      -- … but neither ref spelling may reach a user-facing screen as syntax.
      -- `getRef` does NOT strip the herald (unlike `getDesc`): the payload of
      -- `@ref X` is the text "@ref X", verbatim.
      shouldNotContain' "the emitted interview" sout "@ref "
      shouldNotContain' "the emitted interview" sout "<<17 CFR"
      shouldNotContain' "the emitted interview" sout "intermediary only>>"

    it "escapes Mako-hostile citation text (R9.1, the `defaults` discipline applied to @ref)" $ do
      Output code sout serr <- runL4 bin ["export", "docassemble", daCitationsSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      -- carried at all
      shouldContain' "the emitted interview" sout daCite3Tail
      -- never as a line Mako would read as a control line: the citation begins
      -- with `%`, and a line-leading `%` makes the whole line vanish.
      let hostileControlLine ln =
            "%" `isPrefixOf` dropWhile (`elem` (" \t" :: String)) ln
              && "of the proceeds retained" `isInfixOf` ln
      case filter hostileControlLine (lines sout) of
        [] -> pure ()
        bad -> expectationFailure $
          "citation emitted as a Mako control line (it would vanish from the "
          ++ "screen): " ++ show bad
      -- and never as a LIVE `${ … }` inside a Mako-rendered screen: either the
      -- text is escaped in place (escapeL4) or interpolated at render time.
      for_ ["ev_offering_exempt_screen_holds", "ev_offering_exempt_screen_fails"] \sid -> do
        blk <- blockWithId sout sid
        shouldNotContain' ("the " ++ sid ++ " screen") blk "${ fee_schedule }"

    -- Added by the GREEN phase, which the RED phase asked for by name: the
    -- shape assertions above say what must be true of the M2 emission, and
    -- this pins the exact bytes so a later change to the citation or glossary
    -- rendering has to be deliberate. It is the same `expectGolden` contract
    -- the six M1 examples ride on.
    it "compiles the @ref citations + glossary example to its golden interview" $
      expectGolden bin ["export", "docassemble", daCitationsSource]
                       "examples/docassemble/expected/citations.yml"

    it "declares the M2 block keys in its own emitter vocabulary (R9.5)" $ do
      -- `modules` and `auto terms` are already in the vendored 1.10.7
      -- whitelist; they are NOT yet in the emitter's declaration of what it
      -- writes, so `emitterVocabularyViolations == []` would keep passing
      -- while silently stopping to describe the emitter.
      let declared = map T.unpack DAEmit.emitterKeyVocabulary
          missing  = [k | k <- ["auto terms", "modules"], k `notElem` declared]
      missing `shouldBe` []

    it "keeps block keys and field modifiers in separate vocabularies (R9.5)" $ do
      -- `daRecognisedKeys` is parse.py:1947, the whitelist docassemble applies
      -- to TOP-LEVEL BLOCK KEYS only (parse.py:1946-1948 iterates the block
      -- dict under `if self.interview.debug`); field modifiers are read in a
      -- different place entirely. Checking the two lists together against one
      -- whitelist gave false assurance in both directions: `mandatory` and
      -- `subquestion` are members and yet break a field
      -- (`Syntax error: field label 'mandatory' overwrites previous label`,
      -- measured against 1.10.7), while real modifiers like `show if` are not
      -- members at all. Docassemble has no field-modifier whitelist to vendor,
      -- so the repair is to stop pretending it does.
      let blockKeys = map T.unpack DAEmit.emitterBlockKeys
          modifiers = map T.unpack DAEmit.emitterFieldModifiers
      DAEmit.emitterVocabularyViolations `shouldBe` []
      [k | k <- modifiers, k `elem` blockKeys] `shouldBe` []
      sort (blockKeys ++ modifiers) `shouldBe` sort (map T.unpack DAEmit.emitterKeyVocabulary)

  ----------------------------------------------------------------------------
  -- M2 repair cases: losses that used to be silent, and one that used to
  -- change the answer.
  ----------------------------------------------------------------------------
  describe "l4 export docassemble (M2 repairs: declared losses and reserved names)" $ do
    it "declares both ways an `auto terms:` entry cannot survive, and drops them" $ do
      Output code sout serr <- runL4 bin ["export", "docassemble", daGlossLossSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)

      -- (1) A regex metacharacter in the term. Docassemble interpolates an
      -- `auto terms` key straight into a regex with no re.escape
      -- (parse.py:2908 at 1b6678384): a balanced `(...)` becomes a capture
      -- group whose pattern no longer matches its own term, and an unbalanced
      -- one raises re.error while the Interview is constructed, so the emitted
      -- interview cannot be LOADED at all — while `l4 check` and
      -- `l4 export docassemble` both report success and the report said
      -- "(nothing lost)".
      shouldContain'    "stderr" serr "DA-GLOSS-REGEX"
      shouldContain'    "stderr" serr "s 12(1)"
      shouldNotContain' "the emitted interview" sout "REGEXDROPPEDGLOSS"

      -- (2) Two terms folding onto one key. What that costs is not a duplicate
      -- key but the loser's whole definition.
      shouldContain'    "stderr" serr "DA-GLOSS-COLLIDE"
      shouldContain'    "stderr" serr "folds onto"
      shouldNotContain' "the emitted interview" sout "COLLIDEDROPPEDGLOSS"

      -- What survives: the winner, deterministically the first spelling.
      case [ b | b <- yamlBlocks sout, "auto terms:" `isInfixOf` b ] of
        [glossary] -> do
          shouldContain'    "the glossary" glossary
            "\"Notice\": \"A formal notice served under the Act\""
          shouldNotContain' "the glossary" glossary "s 12(1)"
        other -> expectationFailure $
          "expected exactly one `auto terms:` block, found " ++ show (length other)

    it "reserves the generated runtime module's names, in both artifact shapes" $ do
      -- `modules: [.l4runtime]` is exec'd as `from <pkg>.l4runtime import *`
      -- (parse.py:8572 at 1b6678384) into the interview dict on every assemble
      -- pass. `__all__` bounds WHICH names arrive; it does nothing to stop an
      -- interview variable from being one of them, and the loser is the
      -- interview's — so the packaged artifact asked no question and returned
      -- the opposite verdict to the bare one (R11 decision 6 says the two
      -- shapes must mean the same thing). The bare artifact reserves the name
      -- too, so the shapes cannot disagree about a variable's NAME either.
      Output code sout serr <- runL4 bin ["export", "docassemble", daRuntimeCollisionSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      shouldContain' "the emitted interview" sout "l4_source_text_ = d.filed_on_time"
      case [ ln | ln <- lines sout, "l4_source_text " `isInfixOf` (ln ++ " ") ] of
        [] -> pure ()
        bad -> expectationFailure $
          "an interview variable is spelled exactly like a name the runtime "
          ++ "module star-imports: " ++ show bad

      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-reserved"
      _ <- expectPackage bin daRuntimeCollisionSource dir
      files <- treeFiles dir
      case [ f | f <- files, ("data" </> "questions") `isInfixOf` f ] of
        [ymlPath] -> do
          yml <- readUtf8 (dir </> ymlPath)
          shouldContain' "the packaged interview" yml "l4_source_text_ = d.filed_on_time"
          shouldContain' "the packaged interview" yml ".l4runtime"
        other -> expectationFailure $
          "expected exactly one interview under data/questions, got " ++ show other
      removePathForcibly dir

  ----------------------------------------------------------------------------
  -- M4 (spec §10): breadth. ACCEPTANCE TESTS, WRITTEN FAIL-FIRST.
  --
  -- Every test in this block was RED at the commit that introduced it, and each
  -- was red for a reason the tool stated in words: M1 refused each of these
  -- constructs BY NAME, so the failure was `l4 export docassemble` exiting 1 with
  -- prose naming the milestone that owed the answer — not a missing symbol,
  -- not a typo, not a compile error. `daEmit` still prints that stderr verbatim,
  -- which is what makes a regression legible. The block is GREEN as of
  -- 2026-08-17, together with `m4_acceptance.sh`, its behavioural half.
  --
  -- Three of these tests would still have been red after a naive
  -- implementation, and that is deliberate; they are the ones worth having:
  --
  --   * the leap-day case in "computes statutory age calendar-exactly", where
  --     dateutil's `relativedelta` CLAMPS and L4's `Date` ROLLS FORWARD.
  --     Measured over 27,028 comparisons (every birth date 1970-01-01 to
  --     2006-12-31, tested on the L4 majority date and the day before):
  --     `date_difference(...).years >= 18` disagrees with L4 on 6,629;
  --     `born.plus(years=18) <= assessed` disagrees on 9, all of them
  --     leap-day births; `born <= assessed.minus(years=18)` disagrees on
  --     NONE. The forward form is the wrong one against this oracle.
  --   * "still refuses MAYBE of an enum", which was red not because the
  --     refusal was missing but because the refusal's PROSE became a false
  --     claim the moment MAYBE NUMBER and MAYBE DATE landed.
  --   * the `show if:` spelling, where the `{variable:, is:}` form parses,
  --     renders, and is browser-side JavaScript only — it defines every field
  --     under an API drive and cannot encode a constructor payload at all.
  --
  -- No M4 example carries a byte golden here. See `daListSource` for why.
  ----------------------------------------------------------------------------
  describe "l4 export docassemble (M4: breadth — acceptance)" $ do

    ------------------------------------------------------------------------
    -- A. `LIST OF` via DAList gathering
    ------------------------------------------------------------------------
    it "gathers a LIST OF input as a DAList with a per-element question (A)" $ do
      out <- daEmit bin daListSource

      -- The list must ride as a DAList with an element class. `object_type`
      -- is not decoration: a `DAList.using(complete_attribute=…)` with no
      -- object_type fails on the first element access (ablation-probed
      -- against 1.10.7, variant G).
      shouldContain' "the emitted interview" out "DAList"
      shouldContain' "the emitted interview" out "object_type"

      -- Gather control. Two shapes were probed working and the RED phase
      -- declines to choose: `there_are_any` + `there_is_another` (dropping
      -- EITHER raises DAErrorMissingVariable), or `ask_number` +
      -- `target_number`, which replaces both with a single count question.
      shouldContainAny "the emitted interview" out
        ["there_is_another", "target_number"]

      -- A per-element question. Element attributes are reached either through
      -- a `generic object:` block or through explicitly indexed assignments;
      -- a bare `tenants.age` raises DAAttributeError (probed).
      shouldContainAny "the emitted interview" out
        ["generic object:", "[i]", "for _i in"]

      -- The goal quantifies over the gathered list rather than over a fixed
      -- number of fields. `all` and `any` are the whole list-consumption
      -- surface the docassemble-relevant corpus uses.
      shouldContainAny "the goal code" out ["all(", "any("]

    it "asks a list element's later attribute only when the earlier one leaves it open (A)" $ do
      -- The property the backend sells, at the level where it is provable
      -- from the emission: `the tenant qualifies` is `age AT LEAST 18 AND
      -- signed`, so the signing test must be guarded by the age test WITHIN
      -- one element. Docassemble prunes per element inside a gather (probed:
      -- element 0 aged 17 never had its `has_lease` asked), so a lowering
      -- that evaluates both attributes eagerly — say by building a list of
      -- booleans first — throws that away silently.
      out <- daEmit bin daListSource
      shouldContainAny "the per-element predicate" out
        [ "age >= 18 and", "(x.age >= 18) and", "age >= 18) and" ]
      -- and it must not have been flattened into an eager per-element list
      shouldNotContain' "the emitted interview" out "complete_elements()"

    ------------------------------------------------------------------------
    -- B. constructor payloads via `show if`
    ------------------------------------------------------------------------
    it "emits a payload follow-up gated by a SERVER-SIDE `show if` (B)" $ do
      out <- daEmit bin daPayloadSource

      -- The enum still rides as a radio over constructor-name strings (R6),
      -- with the payload-bearing constructors among the choices.
      shouldContain' "the emitted interview" out "datatype: radio"
      shouldContain' "the emitted interview" out "granted subject to conditions"
      shouldContain' "the emitted interview" out "refused"

      -- Each payload becomes its own follow-up field of its own datatype.
      shouldContain' "the emitted interview" out "the_number_of_conditions"
      shouldContain' "the emitted interview" out "the_stated_ground_of_refusal"

      -- THE CORRECTNESS PIVOT. `show if:` must carry a `code:` sub-key. The
      -- `{variable:, is:}` spelling sets show_if_var/show_if_val and no
      -- showif_code (parse.py:3998-4002 at 1b6678384): it is browser-side
      -- JavaScript, the engine shows every field, and a headless or API drive
      -- DEFINES them all. Only the code form leaves a hidden field genuinely
      -- undefined (parse.py:6316-6325 evals showif_code and sets
      -- extras['ok'][n] = False at 6320/6324).
      shouldContain' "the emitted interview" out "show if:"
      case [ b | b <- yamlBlocks out, "show if:" `isInfixOf` b ] of
        [] -> expectationFailure "no block carries a `show if:` at all"
        blocks -> for_ blocks \b -> do
          shouldContain'    "the `show if:` block" b "code:"
          shouldNotContain' "the `show if:` block" b "is: "

      -- `show if` is FIELD-level only. It is not among the 169 block keys at
      -- parse.py:1947, and an unknown block key is silently ignored — only a
      -- logmessage, and only under debug (parse.py:1945-1948). A block-level
      -- `show if` therefore does nothing AND says nothing.
      for_ (yamlBlocks out) \b ->
        shouldNotContain' "a block" b "\nshow if:"

    it "keeps the constructor radio in its own, earlier question (B)" $ do
      -- HAZARD H1, probed: a `show if: {code: …}` reading a variable that a
      -- field in the SAME question defines is fatal —
      -- `DASourceError: Infinite loop: <var> already looked for`, on every
      -- choice. The radio must be a separate, earlier block.
      out <- daEmit bin daPayloadSource
      for_ (yamlBlocks out) \b ->
        when ("show if:" `isInfixOf` b && "the_outcome" `isInfixOf` b) $
          shouldNotContain' "the payload follow-up block" b "datatype: radio"

    ------------------------------------------------------------------------
    -- C. MAYBE NUMBER / MAYBE DATE via paired is-known questions
    ------------------------------------------------------------------------
    it "pairs each MAYBE NUMBER/DATE with an is-known question (C)" $ do
      out <- daEmit bin daMaybeSource

      -- One L4 field, two docassemble questions: the flag and the value.
      shouldContain' "the emitted interview" out "declared_income"
      shouldContain' "the emitted interview" out "date_last_worked"
      shouldContainAny "the emitted interview" out
        ["declared_income_known", "declared_income_is_known", "has_declared_income"]
      shouldContainAny "the emitted interview" out
        ["date_last_worked_known", "date_last_worked_is_known", "has_date_last_worked"]

      -- The value questions keep their own datatypes.
      shouldContain' "the emitted interview" out "datatype: number"
      shouldContain' "the emitted interview" out "datatype: date"

      -- And each MAYBE value field is guarded, server-side, by its flag.
      -- Without the guard a second consumer reading the value on the absence
      -- path makes docassemble ask the value question anyway, and a blank
      -- submission arrives as 0.0 — a fabricated answer, silently (probed).
      --
      -- Scoped to the two MAYBE fields on purpose. `the qualifying date` is a
      -- PLAIN `DATE` in the same record and must NOT be guarded; requiring a
      -- `show if:` on every date question would demand a defect.
      for_ ["declared_income", "date_last_worked"] \field ->
        case [ b | b <- yamlBlocks out
                 , field `isInfixOf` b
                 , "datatype: number" `isInfixOf` b || "datatype: date" `isInfixOf` b ] of
          [] -> expectationFailure $
            "no value question was emitted for the MAYBE field " ++ show field
          blocks -> for_ blocks \b -> do
            shouldContain' ("the " ++ field ++ " value question") b "show if:"
            shouldContain' ("the " ++ field ++ " value question") b "code:"
      -- and the plain DATE in the same record keeps its unguarded question
      case [ b | b <- yamlBlocks out, "the_qualifying_date" `isInfixOf` b
               , "datatype: date" `isInfixOf` b ] of
        [] -> expectationFailure "the plain DATE field lost its question"
        (b : _) -> shouldNotContain' "the plain DATE question" b "show if:"

    it "reads absence as absence, never as 0 or '' (C)" $ do
      -- What R8 was afraid of, asserted on the emitted code rather than on
      -- the widget: the goal must consult the is-known flag, not merely the
      -- value. `#EVAL` 2 (a real declared income of ZERO) and `#EVAL` 3 (no
      -- declaration at all) disagree in L4; any lowering that reads only the
      -- number cannot tell them apart.
      out <- daEmit bin daMaybeSource
      let goalBlocks = [ b | b <- yamlBlocks out, "the_claim_must_be_referred" `isInfixOf` b ]
      when (null goalBlocks) $
        expectationFailure "no code block sets the goal"
      shouldContainAny "the emitted rule code" (concat goalBlocks)
        ["_known", "_is_known", "has_declared_income"]

    it "lowers `WHEN JUST FALSE` as a payload-VALUE match, not a presence test (C)" $ do
      -- Scope ruling: a match on a MAYBE's payload value is IN M4, under R8.
      -- M1 refused it by name, and before that repair it compiled to
      -- `is None`, reporting TRUE for the unanswered case — which is the
      -- opposite answer. The emitted code must compare the VALUE.
      out <- daEmit bin daMaybeSource
      shouldContainAny "the disclaimer rule" out
        [ "declaration_confirmed is False"
        , "declaration_confirmed == False"
        , "declaration_confirmed) is False" ]

    it "still refuses MAYBE of an enum, and names the enum (C)" $ do
      -- The refusal survives M4 (see the fixture's own header for why). What
      -- must NOT survive is M1's wording: "v1: MAYBE BOOLEAN and MAYBE STRING
      -- only" becomes a false claim in user-facing prose the moment NUMBER
      -- and DATE land, which is precisely the drift CLAUDE.md warns about. So
      -- the diagnostic is required to name what it is refusing.
      Output code _ serr <-
        runL4 bin ["export", "docassemble", "examples/docassemble/not-ok/maybe-enum.l4"]
      code `shouldBe` ExitFailure 1
      shouldContain' "the refusal" serr "MAYBE"
      shouldContain' "the refusal" serr "Severity"
      shouldNotContain' "the refusal" serr "MAYBE BOOLEAN and MAYBE STRING only"

    ------------------------------------------------------------------------
    -- D. date literals and calendar-exact date arithmetic
    ------------------------------------------------------------------------
    it "routes every date literal through as_datetime() (D)" $ do
      -- A `datatype: date` answer enters the interview as
      -- `as_datetime(<submitted string>)` (webapp interview/views.py:1372 at
      -- 1b6678384), i.e. a tz-aware DADateTime. A bare string literal
      -- compared against one raises TypeError — executed:
      -- `as_datetime('2016-05-16') >= '2015-01-01'` is a TypeError, not a
      -- comparison. The failure is loud; it is also certain.
      out <- daEmit bin daDateSource
      shouldContain' "the emitted interview" out "as_datetime("
      shouldContain' "the emitted interview" out "2015-04-01"
      case [ ln | ln <- lines out, "2015-04-01" `isInfixOf` ln ] of
        [] -> expectationFailure "the commencement literal is not emitted at all"
        lns -> for_ lns \ln ->
          shouldContain' "the line carrying the date literal" ln "as_datetime("

    it "computes statutory age calendar-exactly, never via date_difference (D)" $ do
      -- `date_difference(...).years` is
      -- `(delta.days + delta.seconds/86400.0) / 365.2425` — elapsed days over
      -- the MEAN GREGORIAN YEAR, as a float (dates.py:482 at 1b6678384). It
      -- reports 17.99900 on the applicant's own eighteenth birthday. Measured
      -- over every birth date from 1970-01-01 to 2006-12-31 it disagrees with
      -- the L4 oracle on 6,629 of 27,028 comparisons. It must not appear.
      out <- daEmit bin daDateSource
      shouldNotContain' "the emitted interview" out "date_difference"
      shouldNotContain' "the emitted interview" out "365.2425"
      -- and the calendar-exact idiom must be there instead
      shouldContainAny "the emitted interview" out
        [".minus(years=", ".plus(years=", "relativedelta(years="]

    ------------------------------------------------------------------------
    -- E. the `review:` block as a compliance checklist
    ------------------------------------------------------------------------
    it "emits a review block listing every input, answered or not (E)" $ do
      out <- daEmit bin daReviewSource
      shouldContain' "the emitted interview" out "review:"
      -- A review block is only reachable by firing its `event:`
      -- (current_info['action'] = '<event>'); without one the interview simply
      -- ends. Probed.
      case [ b | b <- yamlBlocks out, "review:" `isInfixOf` b ] of
        [] -> expectationFailure "no review block was emitted"
        [rv] -> do
          shouldContain' "the review block" rv "event:"
          -- every L4 input gets a row, including the three that this rule's
          -- short-circuit means are never asked
          for_ [ "the_return_was_filed", "the_return_was_on_time"
               , "the_fee_was_paid", "a_waiver_was_granted" ] $
            shouldContain' "the review block" rv
          -- The recipe that actually renders an unanswered row: a `note:`
          -- carrying showifdef(). A note row has no saveas to evaluate, so it
          -- renders whether or not the variable exists.
          shouldContain' "the review block" rv "note:"
          shouldContain' "the review block" rv "showifdef("
        other -> expectationFailure $
          "expected exactly one review block, found " ++ show (length other)

    it "does NOT reach for `skip undefined: False`, which force-asks (E)" $ do
      -- SPEC CORRECTION, measured. §10 called for a review block "with
      -- `skip undefined: False`". That flag does not make a passive
      -- checklist: it makes the review block FORCE-ASK every undefined
      -- variable it lists — with the flag the row's eval is no longer wrapped
      -- in try/except (parse.py:5876-5904 at 1b6678384), and the probe landed
      -- on the field screen for the unasked variable instead of on a review
      -- screen. The default (absent) is the opposite failure: an undefined row
      -- is silently dropped into a debug log line. Neither is a checklist.
      --
      -- The review block is required to EXIST here as well as to lack the
      -- flag, so this cannot pass vacuously on an interview that emits no
      -- review block at all.
      out <- daEmit bin daReviewSource
      shouldContain'    "the emitted interview" out "review:"
      shouldNotContain' "the emitted interview" out "skip undefined: False"

    ------------------------------------------------------------------------
    -- F. document assembly
    ------------------------------------------------------------------------
    it "assembles a letter from the verdict screen, under a `variable name:` (F)" $ do
      out <- daEmit bin daLetterSource
      shouldContain' "the emitted interview" out "attachment:"
      -- WITHOUT `variable name:` docassemble files the document under
      -- `_internal['docvar'][n]` (parse.py:4997-5003 at 1b6678384) and there
      -- is nothing to assert about afterwards. The hazard this defends
      -- against is not an exception — a raising body propagates and an
      -- unaskable reference propagates, both probed — it is a SUCCESSFUL
      -- EMPTY RENDER: interview completes, variable is a healthy
      -- DAFileCollection, letter is blank, nothing raises and nothing logs.
      shouldContain' "the emitted interview" out "variable name:"
      -- Headless assembly is DOCX- and HTML-capable in the harness venv
      -- (docx and docxtpl present) but there is no LibreOffice/soffice, so a
      -- PDF format would fail at assemble time — and per parse.py:9521-9526
      -- that failure inside a question block is swallowed into a log line.
      -- Scoped to the attachment block: `pdf` is a broad needle and a bare
      -- whole-file negative would be brittle rather than meaningful.
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b -> do
          shouldContain'    "the attachment block" b "valid formats:"
          shouldNotContain' "the attachment block" b "pdf"

      -- The verdict screen must actually reference the document, or it is
      -- never assembled. Asserted on an `event:` block specifically: the
      -- attachment block names the variable itself, so looking for the name
      -- anywhere in the file would be satisfied by the declaration alone.
      let verdictScreens = [ b | b <- yamlBlocks out, "event:" `isInfixOf` b ]
      when (null verdictScreens) $
        expectationFailure "no verdict screen (`event:` block) was emitted"
      shouldContainAny "the verdict screens" (concat verdictScreens)
        ["${ notice_letter }", "${notice_letter}", "notice_letter"]

    it "keeps attachment sub-keys out of the BLOCK-key vocabulary (F/R9.5)" $ do
      -- A third vocabulary. `variable name`, `filename`, `content`,
      -- `valid formats` and `content file` are ATTACHMENT sub-keys, read by
      -- process_attachment (parse.py:4914-5230 at 1b6678384); `name`,
      -- `filename`, `docx template file` and `valid formats` are NOT among
      -- the 169 block keys at parse.py:1947. Adding them to the emitter's
      -- block-key list would break `emitterVocabularyViolations == []`, so
      -- they need their own list with its own oracle — exactly the split M2
      -- already made between block keys and field modifiers.
      out <- daEmit bin daLetterSource
      let known = [ "name", "filename", "description", "variable name"
                  , "valid formats", "content", "content file", "raw"
                  , "docx template file", "pdf template file", "fields"
                  , "metadata", "editable", "skip undefined", "language"
                  , "redact", "template file", "rtf template file"
                  , "docx reference file", "update references", "usedefs"
                  , "initial yaml", "additional yaml", "checkbox export value"
                  , "decimal places" ]
          subKeys b = [ takeWhile (/= ':') (drop 2 ln)
                      | ln <- lines b, "  " `isPrefixOf` ln
                      , not ("   " `isPrefixOf` ln), ':' `elem` ln ]
      -- Required to EXIST as well as to be well-formed, so this cannot pass
      -- vacuously on an interview that emits no attachment at all.
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b ->
          for_ (subKeys b) \k ->
            unless (null k || k `elem` known) $
              expectationFailure $
                "the attachment block uses sub-key " ++ show k
                ++ ", which process_attachment does not read (parse.py:4914-5230 "
                ++ "at 1b6678384). It is not a block key either, so nothing will "
                ++ "warn: an unrecognised attachment sub-key is silently ignored."
                ++ "\n--- block ---\n" ++ b

    it "ships the letter template in the package under data/templates (F/R11)" $ do
      -- The `--package` tree already grafts `<inner>/data` in MANIFEST.in, so
      -- a template dropped under data/templates ships automatically. Note for
      -- the implementer: if the interview references it with `content file:`,
      -- the BARE artifact stops parsing, because content file resolves
      -- through package_template_filename and raises DASourceError when the
      -- file is not found (parse.py:5059-5064 at 1b6678384) — at parse time,
      -- before any question is asked.
      haveTemplate <- doesFileExist daLetterTemplate
      unless haveTemplate $
        expectationFailure (daLetterTemplate ++ " is missing from the corpus")
      tmp <- getTemporaryDirectory
      let dir = tmp </> "l4-da-pkg-letter"
      files <- expectPackage bin daLetterSource dir
      case [ f | f <- files, ("data" </> "templates") `isInfixOf` f ] of
        [] -> expectationFailure $
          "the --package tree ships no data/templates entry; files were "
          ++ show files
        _  -> pure ()
      removePathForcibly dir

    ------------------------------------------------------------------------
    -- G. regression: the boundary of what M4 owns
    --
    -- GREEN today, and it must stay green. This block pre-authorises nothing:
    -- the seven M1/M2 byte goldens are pinned where they already were
    -- (stdout, and again through `-o` with its fidelity sidecar), and the four
    -- refusals below are the ones M4 does not own.
    ------------------------------------------------------------------------
    ------------------------------------------------------------------------
    -- H. added by the GREEN phase, which the RED phase asked for by name
    ------------------------------------------------------------------------
    it "declares the attachment sub-keys it writes, as a THIRD vocabulary (F/R9.5)" $ do
      -- The RED phase could only hard-code the oracle inside its own test,
      -- because `emitterAttachmentKeys` did not exist and adding it would have
      -- been a compile error rather than a red assertion. It exists now, so the
      -- emitter's declaration of what it writes inside an `attachment:` is
      -- checked in both directions: every declared key is one
      -- `process_attachment` reads (parse.py:4914-5230 at 1b6678384), and every
      -- key the emitter actually emits is declared.
      let readByProcessAttachment =
            [ "name", "filename", "description", "variable name"
            , "valid formats", "content", "content file", "raw"
            , "docx template file", "pdf template file", "fields"
            , "metadata", "editable", "skip undefined", "language"
            , "redact", "template file", "rtf template file"
            , "docx reference file", "update references", "usedefs"
            , "initial yaml", "additional yaml", "checkbox export value"
            , "decimal places" ]
          declared = map T.unpack DAEmit.emitterAttachmentKeys
      [k | k <- declared, k `notElem` readByProcessAttachment] `shouldBe` []
      -- and it is NOT folded into the block-key/field-modifier split, because
      -- an attachment sub-key is neither.
      [ k | k <- declared
          , k `elem` map T.unpack DAEmit.emitterKeyVocabulary ] `shouldBe` []

      out <- daEmit bin daLetterSource
      let subKeys b = [ takeWhile (/= ':') (drop 2 ln)
                      | ln <- lines b, "  " `isPrefixOf` ln
                      , not ("   " `isPrefixOf` ln), ':' `elem` ln ]
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b ->
          [ k | k <- subKeys b, not (null k), k `notElem` declared ] `shouldBe` []

    it "unlocks the REAL corpus file that motivated `LIST OF` (A)" $ do
      -- The RED phase listed this as untested and said why it matters: "a green
      -- M4 could pass every test I wrote and still leave both files locked
      -- out", because ONE `LIST OF` field anywhere in a reachable record used
      -- to refuse the whole module. `charity-test.l4` is a 700-line Jersey
      -- charities encoding whose `Entity.purposes` is a `LIST OF Purpose`, and
      -- it is not a fixture written for this backend — which is the point.
      --
      -- It also pins the ETA-REDUCED predicate: the corpus writes
      -- `any \`the purpose is a charitable purpose\` (entity's purposes)`, a
      -- one-parameter decision passed by name rather than a lambda written out
      -- at the call site. No example under examples/docassemble/ does that.
      out <- daEmit bin "examples/canon/je/charities-2014/charity-test.l4"
      shouldContain' "the charities interview" out "DAList"
      shouldContain' "the charities interview" out "object_type"
      shouldContain' "the charities interview" out "for _purpose in entity.purposes"
      -- Nested quantifiers must not share a generator variable: Python scopes
      -- one to its own comprehension, so an inner binder that sanitised onto an
      -- outer one would make the outer's element unreachable from the inner
      -- body. This file nests `any` inside `all` over the same list.
      shouldContain' "the charities interview" out "for _purpose_2 in entity.purposes"

    it "compiles each M4 example to its golden interview" $
      for_ [ daListSource, daPayloadSource, daMaybeSource, daDateSource
           , daReviewSource, daLetterSource ] \src -> do
        let stem = takeWhile (/= '.') (drop (length daExampleDir + 1) src)
        expectGolden bin ["export", "docassemble", src]
          (daExampleDir </> "expected" </> (stem ++ ".yml"))

    it "leaves the four refusals M4 does not own refusing, by their own names (G)" $
      for_ daStillRefused \(fixture, diagnostic) -> do
        Output code _ serr <-
          runL4 bin ["export", "docassemble", "examples/docassemble/not-ok" </> fixture]
        unless (code == ExitFailure 1) $
          expectationFailure $
            fixture ++ " no longer refuses (exit " ++ show code
            ++ "); M4 does not own this refusal"
        shouldContain' (fixture ++ " refusal") serr diagnostic

    ------------------------------------------------------------------------
    -- I. the repair pass (2026-08-17). Five adversarial lenses attacked M4
    -- and an independent skeptic tried to refute each finding; these pin the
    -- five that survived AND changed behaviour. Each one names the measured
    -- failure, not just the shape it wants.
    ------------------------------------------------------------------------
    it "splices the letter template under an explicit indentation indicator (I/F)" $ do
      -- A YAML block scalar with no indentation indicator takes its
      -- indentation from its own FIRST non-empty line. The emitter indents
      -- every template line by a flat four spaces, so a template opening on any
      -- leading whitespace — ONE space is enough, and so is a whitespace-only
      -- first line — set the block indent above four, and the first following
      -- line at exactly four TERMINATED the scalar. The parser then met
      -- template prose where an `attachment:` sub-key must be. Measured against
      -- real docassemble 1.10.7: `parse.Interview` raises `DASourceError` from
      -- parse.py:8352-8360, so the whole interview is unloadable — every
      -- question, in BOTH artifact shapes — while `l4 export docassemble` exits 0.
      --
      -- `|2`, not `|4`: the indicator is an offset from the PARENT node's
      -- indentation and the `attachment:` mapping sits at two.
      --
      -- `notice-letter.letter.md` opens on an indented address block precisely
      -- so the shipped corpus carries the trigger; strip the `2` from the
      -- emitted YAML and the harness cannot even load the interview.
      out <- daEmit bin daLetterSource
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b -> do
          shouldContain'    "the attachment block" b "content: |2"
          shouldNotContain' "the attachment block" b "content: |\n"
      -- and the template really does open indented, or the assertion above is
      -- pinning a shape nothing exercises.
      tpl <- readUtf8 daLetterTemplate
      case dropWhile null (lines tpl) of
        (firstLine : _) | " " `isPrefixOf` firstLine -> pure ()
        other -> expectationFailure $
          daLetterTemplate ++ " no longer opens on an indented line, so the "
          ++ "block-scalar indicator above is no longer exercised by anything: "
          ++ show (take 1 other)

    it "re-assembles the letter when an earlier answer changes (I/F, §8.4)" $ do
      -- §8.4's repair put `reconsider: True` on the derived CODE blocks and
      -- stopped there. An attachment is derived too, and docassemble assembles
      -- one only when the variable it names is SOUGHT (parse.py:9513-9530 at
      -- 1b6678384) — a variable that is already defined is never sought. So the
      -- letter was computed once and outlived every later answer: measured on
      -- this example, changing the notice period from three months to one left
      -- the verdict screen reading `..._screen_fails` above a letter still
      -- saying "Notice period served: 3 month(s)" and "the notice is valid".
      -- A non-flipping edit was stale the same way.
      out <- daEmit bin daLetterSource
      case [ b | b <- yamlBlocks out, "attachment:" `isInfixOf` b ] of
        [] -> expectationFailure "no attachment block was emitted at all"
        blocks -> for_ blocks \b ->
          shouldContain' "the attachment block" b "reconsider: True"

    it "clears a gated answer when the answer that gates it is re-asked (I/B/C, §8.4)" $ do
      -- `show if:` decides whether a gated question is ASKED. It does not
      -- decide whether an answer already given SURVIVES its gate being
      -- withdrawn, and `reconsider:` deletes derived variables only — so after
      -- a review-block Edit the compliance checklist reported, on one screen,
      -- "the outcome: refused" beside "the number of conditions: 9", and
      -- `refused` carries no `the number of conditions` in L4 at all. The
      -- paired MAYBE had the same shape: "is there an answer?: False" beside
      -- "declared income: 2500". `undefine:` fires in `ask` (parse.py:5389) and
      -- is a documented no-op on a variable that is not defined, so it costs
      -- nothing forward and clears exactly the stale answers on a re-ask.
      payload <- daEmit bin daPayloadSource
      case [ b | b <- yamlBlocks payload, "q_d.the_outcome" `isInfixOf` b ] of
        [] -> expectationFailure "no question block for the enum discriminator"
        blocks -> for_ blocks \b -> do
          shouldContain' "the discriminator question" b "undefine:"
          shouldContain' "the discriminator question" b "d.the_number_of_conditions"
          shouldContain' "the discriminator question" b "d.the_stated_ground_of_refusal"
      -- and the payload follow-ups must NOT undefine anything: they gate
      -- nothing, and clearing on every ask would erase the answer being given.
      case [ b | b <- yamlBlocks payload
               , "q_d.the_number_of_conditions" `isInfixOf` b ] of
        [] -> expectationFailure "no question block for the payload follow-up"
        blocks -> for_ blocks \b ->
          shouldNotContain' "the payload follow-up question" b "undefine:"

      maybes <- daEmit bin daMaybeSource
      case [ b | b <- yamlBlocks maybes
               , "q_c.declared_income_known" `isInfixOf` b ] of
        [] -> expectationFailure "no question block for the is-known flag"
        blocks -> for_ blocks \b -> do
          shouldContain' "the is-known question" b "undefine:"
          shouldContain' "the is-known question" b "c.declared_income"

    it "reserves the interview's builtin and util namespaces too (I/R11)" $ do
      -- M2 closed ONE THIRD of this hazard — the `l4runtime` star-import — and
      -- left the two larger thirds open. A goal variable whose name already
      -- resolves is never sought, because docassemble backchains only on
      -- NameError; it resolves to a function object, which is truthy, so the
      -- driver takes the "holds" branch, NO QUESTION IS ASKED, and the fidelity
      -- report says `(nothing lost)`. Measured against real 1.10.7 on an
      -- `@export` named `All`: `screen='All: Holds'`, `questions asked=[]`,
      -- against an L4 `#EVAL` of FALSE. `Today` is worse — it is in the
      -- user_dict for real, via `from docassemble.base.util import *`
      -- (parse.py:131, exec'd at :8523-8524), which the emitter deliberately
      -- does not suppress.
      Output code sout serr <- runL4 bin ["export", "docassemble", daGlobalShadowSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      shouldContain' "the emitted interview" sout "all_ = f.the_box_was_ticked"
      shouldContain' "the emitted interview" sout "today_ = f.the_box_was_ticked"
      let bare = [ ln | ln <- lines sout
                 , any (`isInfixOf` (ln ++ " "))
                       ["all = f.", "today = f.", "if all:", "if today:"] ]
      unless (null bare) $
        expectationFailure $
          "an interview variable is spelled exactly like a name already bound "
          ++ "in the interview's top-level namespace: " ++ show bare

    it "declares, rather than mis-emits, the gather it cannot clear (I/§8.4)" $ do
      -- `ask` runs `substitute_vars` over `reconsider:` and NOT over `undefine:`
      -- (parse.py:5389 beside :5392 at 1b6678384), so an element question's
      -- `<list>[i].<attr>` spelling would reach `undefine()` with the iterator
      -- unresolved. The emitter therefore emits none there — and says so, which
      -- is the difference between a bounded repair and a silent one.
      Output code sout serr <- runL4 bin ["export", "docassemble", daGatheredMaybeSource]
      unless (code == ExitSuccess) $
        expectationFailure ("emit failed\n--- stderr ---\n" ++ serr)
      -- the guard IS emitted on the element's value question …
      shouldContain'    "the emitted interview" sout
        "h.claimants[i].declared_income_known"
      -- … and no `undefine:` reaches it.
      shouldNotContain' "the emitted interview" sout "undefine:"
      -- The omission is declared, per module, naming the gated variable.
      tmp <- getTemporaryDirectory
      let ymlPath = tmp </> "l4-da-gathered-maybe.yml"
          repPath = tmp </> "l4-da-gathered-maybe.fidelity.txt"
      Output code2 _ serr2 <-
        runL4 bin ["export", "docassemble", daGatheredMaybeSource, "-o", ymlPath]
      unless (code2 == ExitSuccess) $
        expectationFailure ("emit -o failed\n--- stderr ---\n" ++ serr2)
      report <- readUtf8 repPath
      shouldContain' "the fidelity report" report "DA-UNDEFINE-LIST"
      shouldContain' "the fidelity report" report "h.claimants[i].declared_income"
      removePathForcibly ymlPath
      removePathForcibly repPath

    it "refuses M4's own two new collisions, by their own names (I)" $
      for_ daM4Refused \(fixture, diagnostic) -> do
        Output code _ serr <-
          runL4 bin ["export", "docassemble", "examples/docassemble/not-ok" </> fixture]
        unless (code == ExitFailure 1) $
          expectationFailure $
            fixture ++ " no longer refuses (exit " ++ show code ++ ")"
        shouldContain' (fixture ++ " refusal") serr diagnostic
        -- Not the internal-error message: a user-authored condition must be
        -- reported in L4 terms, naming what to rename.
        shouldNotContain' (fixture ++ " refusal") serr "internal id collision"
  where
    for_ xs f = mapM_ f xs
