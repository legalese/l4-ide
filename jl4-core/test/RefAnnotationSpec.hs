{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
module RefAnnotationSpec (spec) where

import Control.Exception (evaluate)
import qualified Data.Text as Text
import GHC.Clock (getMonotonicTime)
import System.CPUTime (getCPUTime)

import Base
import L4.Annotation (getAnno, rangeOf)
import L4.Parser (execProgramParser, execProgramParserWithHintPass)
import L4.Parser.ResolveAnnotation (refWarningMessage)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.Syntax
  ( Anno
  , Decide (..)
  , Expr (..)
  , Module (..)
  , Name
  , Section (..)
  , TopDecl (..)
  , annPmSynthetic
  , annRef
  , annRefs
  , getRef
  , refCitation
  )
import Optics (gplate, toListOf)
import Test.Hspec

-- | The text of the ref nearest a node, if it holds any: what an exporter shows.
nearestRef :: Anno -> Maybe Text
nearestRef anno = getRef <$> view annRef anno

-- | Parse a source snippet and return the @\@ref@ text (if any) attached to
-- the 'Module' node and to the first top-level declaration ('TopDecl').
moduleAndFirstDeclRefs :: Text -> IO (Maybe Text, Maybe Text)
moduleAndFirstDeclRefs src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-module")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m@(MkModule _ _ (MkSection _ _ _ decls)), _, _) -> do
      let moduleRef = nearestRef (getAnno m)
      firstDeclRef <- case decls of
        (d : _) -> pure $ nearestRef (getAnno d)
        []      -> do
          expectationFailure "Expected at least one top-level declaration"
          error "unreachable"
      pure (moduleRef, firstDeclRef)

-- | Parse a source snippet and return the bodies of every top-level @DECIDE@,
-- paired with the raw text of any @\@ref@ annotation attached to that body
-- expression (via its 'Anno'\'s 'Extension').
decideBodyRefs :: Text -> IO [(Expr Name, Maybe Text)]
decideBodyRefs = decideBodyRefs' "file:///ref-annotation-spec"

decideBodyRefs' :: String -> Text -> IO [(Expr Name, Maybe Text)]
decideBodyRefs' uriStr src = do
  let uri = toNormalizedUri (Uri (Text.pack uriStr))
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      pure
        [ (body, nearestRef (getAnno body))
        | Decide _ (MkDecide _ _ _ body) <- decls
        ]

-- | Parse a source snippet and return, for each top-level declaration, the last
-- path segment of every @\@ref@ attached to it, in the order they are held;
-- and the message of every warning about where a @\@ref@ sits, in the order
-- reported.
declRefsAndMessages :: Text -> IO ([[Text]], [Text])
declRefsAndMessages src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-messages")
      segment = Text.takeWhileEnd (/= '/') . Text.strip . getRef
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), _, warnings) ->
      pure
        ( [ fmap segment (view annRefs (getAnno d)) | d <- decls ]
        , mapMaybe refWarningMessage warnings
        )

-- | The citation (as written) of every ref held by ANY node of the module, in
-- the order the traversal meets them.
heldRefs :: Text -> IO [Text]
heldRefs src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-held")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m, _, _) -> pure [ getRef r | a <- toListOf (gplate @Anno) m, r <- view annRefs a ]

-- | Parse a source snippet and return the last path segment of the ref NEAREST
-- each top-level declaration, if it holds any.
declNearestRefs :: Text -> IO [Maybe Text]
declNearestRefs src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-nearest")
      segment = Text.takeWhileEnd (/= '/') . Text.strip
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      pure [ segment <$> nearestRef (getAnno d) | d <- decls ]

-- | Where each ref lands: the line and column at which the node that holds it
-- starts, with the citation's last path segment, in the order the traversal
-- meets them. A ref that lands where the author put the node after it starts
-- at the position of that node's first token.
refPlacements :: Text -> IO [((Int, Int), Text)]
refPlacements src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-placements")
      segment = Text.takeWhileEnd (/= '/') . Text.strip . getRef
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m, _, _) ->
      pure
        [ ((r.start.line, r.start.column), segment ref)
        | a <- toListOf (gplate @Anno) m
        , ref <- view annRefs a
        , Just r <- [rangeOf a]
        ]

-- | For every @\@ref@ and the node that holds it: the line of that node (0 if
-- it has no range), whether the parser generated the node while compiling a
-- group of clauses ('annPmSynthetic'), and the last segment of the citation.
-- Sorted, because a traversal of the tree meets a clause group's parts in the
-- order of its fields and not of the source.
refHolderMarks :: Text -> IO [(Int, Bool, Text)]
refHolderMarks src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-marks")
      -- 'refCitation', not 'getRef': an inline @\<\<…\>\>@ keeps its delimiters in the latter.
      segment = Text.takeWhileEnd (/= '/') . refCitation
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m, _, _) ->
      pure $ sort
        [ (maybe 0 (\ r -> r.start.line) (rangeOf a), isJust (view annPmSynthetic a), segment ref)
        | a <- toListOf (gplate @Anno) m
        , ref <- view annRefs a
        ]

-- | The source range of every node that holds a ref, and the source range of
-- the body of the last top-level @DECIDE@: whether a ref is held by that
-- body's own node.
refHoldersAndBody :: Text -> IO ([Maybe SrcRange], Maybe SrcRange)
refHoldersAndBody src = do
  let uri = toNormalizedUri (Uri "file:///ref-annotation-spec-holders")
  case execProgramParserWithHintPass uri src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (m@(MkModule _ _ (MkSection _ _ _ decls)), _, _) ->
      case reverse [ body | Decide _ (MkDecide _ _ _ body) <- decls ] of
        (body : _) ->
          pure
            ( [ rangeOf a | a <- toListOf (gplate @Anno) m, not (null (view annRefs a)) ]
            , rangeOf (getAnno body)
            )
        [] -> do
          expectationFailure "Expected a DECIDE"
          error "unreachable"

-- | A CPU clock, in picoseconds, as 'getCPUTime' reads it.
type Clock = IO Integer

-- | One step of the CPU clock on Windows, 15.625 ms in picoseconds: every
-- reading there is a multiple of it, so a parse that takes less than a step
-- reads as 0 or as a whole step.
windowsClockStep :: Integer
windowsClockStep = 15625000000

-- | A clock that reads in whole steps, rounding down, as Windows' does.
steppedClock :: Integer -> Clock -> Clock
steppedClock step clock = (\ t -> t `div` step * step) <$> clock

-- | How many steps of the Windows clock a stretch of parses has to span for
-- 'linearTimeRatioOn' to read it: 32 of them are half a second, so that an
-- error of one step is a thirty-second of the reading.
measurableSteps :: Integer
measurableSteps = 32

-- | How long, in seconds of wall-clock time, 'linearTimeRatioOn' looks for a
-- stretch of parses that its clock can measure. The stretch is half a second
-- of CPU time, and a busy machine gives a test a fraction of its wall-clock
-- time, so this leaves room for the test to get one eighth of it.
measurableSearchSeconds :: Double
measurableSearchSeconds = 4.0

-- | Parse @src@ and count its definitions. The warnings are forced as well as
-- the definitions, because they depend on the last state of every pass that
-- attaches annotations to the tree: so each of them has run to the end when
-- the clock stops.
parseCountingDecides :: Text -> IO Int
parseCountingDecides src =
  case execProgramParser (toNormalizedUri (Uri "file:///ref-annotation-spec-timing")) src of
    Left errs -> do
      expectationFailure $ "Parser failed: " <> show errs
      error "unreachable"
    Right (MkModule _ _ (MkSection _ _ _ decls), warnings) -> do
      _ <- evaluate (length warnings)
      pure (length [ () | Decide _ _ <- decls ])

-- | A parse of no real file: it takes time quadratic in the number of lines
-- and finds one "definition" for each. It is the control for the guard, which
-- must still fail a parse like this on a clock as coarse as Windows' (the
-- work is made up, so that the test does not depend on the parser).
quadraticParse :: Text -> IO Int
quadraticParse src = do
  let k = length (Text.lines src)
  _ <- evaluate (foldl' (+) 0 [1 .. k * k * 20])
  pure k

-- | The time to parse @largeSize@ lines made by @line@ over the time to parse
-- @smallSize@ of them, both in the CPU time that the clock reads; or 'Nothing'
-- if the clock could not measure the small file.
--
-- The small file is parsed over and over in one timed stretch, until the
-- stretch spans 'measurableSteps' steps of the Windows clock (half a second),
-- and its time is the stretch's divided by the number of parses. One parse of
-- 1,000 lines is about four steps there, so a single reading is off by a
-- quarter either way: on Windows, two of 56 runs of the guard that read it
-- once gave 16.5 and 17.0 against a limit of 16 (review of
-- legalese/l4-ide#648). A stretch of 32 steps is off by at most a
-- thirty-second, and the large file, parsed once, is eight times longer than
-- the small one, so it is off by less. If no stretch spans that many steps
-- within 'measurableSearchSeconds' (a clock that never ticks, say) or 4,096
-- parses, there is no ratio. A ratio short of twice the limit is measured again, up to
-- twice, so that one pause does not fail it; each measurement reads the small
-- file again as well as the large one, and the smallest ratio counts.
linearTimeRatioOn :: Clock -> (Text -> IO Int) -> Int -> Int -> Double -> (Int -> Text) -> IO (Maybe Double)
linearTimeRatioOn clock parse smallSize largeSize limit line = do
  let file k = Text.unlines (map line [1 .. k])
      -- The CPU time of @reps@ parses of a file of @k@ lines, in picoseconds.
      timeParses k reps = do
        src <- evaluate (file k)
        _ <- evaluate (Text.length src)
        t0 <- clock
        replicateM_ reps do
          n <- parse src
          n `shouldBe` k
        t1 <- clock
        pure (fromIntegral (t1 - t0) :: Double)
      measurable = fromIntegral (measurableSteps * windowsClockStep) :: Double
      maxReps = 4096 :: Int
  start <- getMonotonicTime
  let -- The number of parses of the small file that fills a measurable stretch.
      repsFor reps = do
        t <- timeParses smallSize reps
        now <- getMonotonicTime
        if t >= measurable
          then pure (Just reps)
          else if reps >= maxReps || now - start >= measurableSearchSeconds
            then pure Nothing
            else repsFor (reps * 2)
  found <- repsFor 1
  case found of
    Nothing -> pure Nothing
    Just reps -> do
      let -- One ratio: the fastest of three stretches of the small file, per
          -- parse, against one parse of the large file.
          measure = do
            stretches <- traverse (const (timeParses smallSize reps)) [1 .. 3 :: Int]
            large <- timeParses largeSize 1
            let small = minimum stretches / fromIntegral reps
            pure (if small <= 0 then Nothing else Just (large / small))
          settle tries = do
            measured <- measure
            case measured of
              Nothing -> pure Nothing
              Just r
                | r < limit || r >= 2 * limit || tries <= (1 :: Int) -> pure (Just r)
                | otherwise -> fmap (min r) <$> settle (tries - 1)
      settle 3

-- | @attachesInLinearTimeOn clock small large limit line@: parsing @large@
-- lines made by @line@ (one definition each) takes less than @limit@ times the
-- CPU time of parsing @small@ lines, as 'linearTimeRatioOn' measures it. If the
-- clock gave no ratio, the test is pending, not failed.
attachesInLinearTimeOn :: Clock -> Int -> Int -> Double -> (Int -> Text) -> Expectation
attachesInLinearTimeOn clock smallSize largeSize limit line = do
  ratio <- linearTimeRatioOn clock parseCountingDecides smallSize largeSize limit line
  case ratio of
    Nothing -> pendingWith "the CPU clock did not tick enough while the small file was parsed, so there is no ratio to judge"
    Just r -> r `shouldSatisfy` (< limit)

-- | A file of @i@ definitions, each with a citation above it.
citedDefinition :: Int -> Text
citedDefinition i =
  "@ref https://example.com/s" <> Text.pack (show i) <> "\nf" <> Text.pack (show i) <> " x MEANS " <> Text.pack (show i)

spec :: Spec
spec = describe "@ref annotations attach to arbitrary AST nodes" $ do
  it "attaches a @ref that precedes an expression to that expression node" $ do
    bodies <-
      decideBodyRefs
        "GIVEN x IS A NUMBER\nDECIDE doubled x IS\n  @ref https://example.com/section-1a\n  x * 2\n"
    case bodies of
      [(_, mRef)] ->
        case mRef of
          Just t -> t `shouldSatisfy` Text.isInfixOf "section-1a"
          Nothing ->
            expectationFailure "Expected a @ref attached to the DECIDE body expression"
      _ -> expectationFailure $ "Expected exactly one DECIDE, got: " <> show (length bodies)

  it "attaches distinct @refs to distinct expression bodies" $ do
    bodies <-
      decideBodyRefs $
        Text.unlines
          [ "GIVEN x IS A NUMBER"
          , "DECIDE doubled x IS"
          , "  @ref https://example.com/section-1a"
          , "  x * 2"
          , ""
          , "GIVEN n IS A NUMBER"
          , "DECIDE isPositive IF"
          , "  @ref https://example.com/section-2a"
          , "  n > 0"
          ]
    let refs = [ mRef | (_, mRef) <- bodies ]
    length refs `shouldBe` 2
    (refs !! 0 >>= \t -> if Text.isInfixOf "section-1a" t then Just () else Nothing)
      `shouldBe` Just ()
    (refs !! 1 >>= \t -> if Text.isInfixOf "section-2a" t then Just () else Nothing)
      `shouldBe` Just ()

  it "leaves the body ref empty when there is no @ref" $ do
    bodies <- decideBodyRefs "DECIDE answer IS 42\n"
    case bodies of
      [(_, mRef)] -> mRef `shouldBe` Nothing
      _ -> expectationFailure $ "Expected exactly one DECIDE, got: " <> show (length bodies)

  -- Regression: a @ref on the line ABOVE the first top-level declaration must
  -- attach to that declaration, NOT be greedily claimed by the enclosing
  -- Module/Section (which share the first declaration's start position because
  -- the leading @ref cluster is excluded from their visible range).
  it "attaches a leading @ref to the first declaration, not the Module" $ do
    (moduleRef, firstDeclRef) <-
      moduleAndFirstDeclRefs $
        Text.unlines
          [ "@ref https://example.com/section-leading"
          , "DECIDE answer IS 42"
          ]
    moduleRef `shouldBe` Nothing
    case firstDeclRef of
      Just t  -> t `shouldSatisfy` Text.isInfixOf "section-leading"
      Nothing ->
        expectationFailure "Expected the leading @ref to attach to the first declaration"

  -- Every @ref that precedes a node is held by that node, in source order. The
  -- pending refs are kept in the order they end, and each node claims those
  -- that precede it from the front of that list, so a mistake in keeping the
  -- order would show here: as a ref on the wrong node, or one reported that
  -- should have attached.
  it "keeps every @ref before a node, in source order, and reports only the one with nothing after it" $ do
    (attached, messages) <-
      declRefsAndMessages $
        Text.unlines
          [ "@ref https://example.com/one"
          , "@ref https://example.com/two"
          , "DECIDE a IS 1"
          , "@ref https://example.com/three"
          , "DECIDE b IS 2"
          , "@ref https://example.com/four"
          ]
    attached `shouldBe` [["one", "two"], ["three"]]
    messages `shouldBe` [endOfFile "https://example.com/four"]

  -- What a reader that shows one citation per node reads is the NEAREST ref,
  -- the one written last (ruled 2026-10-12: in a stack the exporters show the
  -- nearest).
  it "gives a node's nearest ref as the last of those it holds" $ do
    nearest <-
      declNearestRefs $
        Text.unlines
          [ "@ref https://example.com/one"
          , "@ref https://example.com/two"
          , "DECIDE a IS 1"
          , "DECIDE b IS 2"
          ]
    nearest `shouldBe` [Just "two", Nothing]

  describe "a @ref with nothing after it" $ do
    it "says so, naming the citation" $ do
      (attached, messages) <-
        declRefsAndMessages "DECIDE a IS 1\n@ref https://example.com/last\n"
      attached `shouldBe` [[]]
      messages `shouldBe` [endOfFile "https://example.com/last"]

    it "names the citation without its herald, its trailing spaces or a carriage return" $ do
      (_, messages) <-
        declRefsAndMessages "DECIDE a IS 1\r\n@ref https://example.com/crlf   \r\n"
      messages `shouldBe` [endOfFile "https://example.com/crlf"]
      any (Text.any (== '\r')) messages `shouldBe` False

    it "names an inline citation without its angle brackets" $ do
      (_, messages) <- declRefsAndMessages "DECIDE a IS 1\n<<s.5 (1)>>\n"
      messages `shouldBe` [endOfFile "s.5 (1)"]

  describe "a @ref that follows code on its line" $ do
    -- A ref refers to what FOLLOWS it, so one written after code cannot cite
    -- that code; nor is it handed to the next construct, whose citation it
    -- would then silently become. It is attached to nothing (ruled 2026-10-12).
    it "warns, and is attached to nothing" $ do
      (attached, messages) <-
        declRefsAndMessages "DECIDE a IS 1 @ref https://example.com/cite\nDECIDE b IS 2\n"
      attached `shouldBe` [[], []]
      messages `shouldBe` [afterCode "https://example.com/cite" "DECIDE a IS 1"]
      heldRefs "DECIDE a IS 1 @ref https://example.com/cite\nDECIDE b IS 2\n" `shouldReturn` []

    it "warns once, and not also as having nothing after it, at the end of the file" $ do
      (_, messages) <-
        declRefsAndMessages "DECIDE a IS 1 @ref https://example.com/cite\n"
      messages `shouldBe` [afterCode "https://example.com/cite" "DECIDE a IS 1"]

    it "warns about an inline <<...>> at the end of a code line" $ do
      (_, messages) <-
        declRefsAndMessages "GIVEN x IS A BOOLEAN\nDECIDE p IF x <<s.5>>\n  AND TRUE\n"
      messages `shouldBe` [afterCode "s.5" "DECIDE p IF x"]
      heldRefs "GIVEN x IS A BOOLEAN\nDECIDE p IF x <<s.5>>\n  AND TRUE\n" `shouldReturn` []

    it "does not warn about an inline <<...>> in the middle of a line, which binds to the next word" $ do
      (_, messages) <-
        declRefsAndMessages "GIVEN x IS A BOOLEAN\nDECIDE p IF x AND <<s.5>> TRUE\n"
      messages `shouldBe` []
      heldRefs "GIVEN x IS A BOOLEAN\nDECIDE p IF x AND <<s.5>> TRUE\n" `shouldReturn` ["<<s.5>>"]

  describe "a @ref on a line of its own" $ do
    it "binds to the construct below it and draws no warning" $ do
      (attached, messages) <-
        declRefsAndMessages "@ref https://example.com/own\nDECIDE a IS 1\n\n-- a comment\nDECIDE b IS 2\n"
      attached `shouldBe` [["own"], []]
      messages `shouldBe` []

    it "still binds to the construct below it across a blank line and a comment" $ do
      (attached, messages) <-
        declRefsAndMessages "DECIDE a IS 1\n@ref https://example.com/far\n\n-- a comment\n\nDECIDE b IS 2\n"
      attached `shouldBe` [[], ["far"]]
      messages `shouldBe` []

    it "is held by the section heading below it, together with every other @ref above the heading" $ do
      (attached, messages) <-
        declRefsAndMessages $
          Text.unlines
            [ "@ref https://example.com/act"
            , "@ref https://example.com/part"
            , "§ `Part 1`"
            , "DECIDE a IS 1"
            ]
      attached `shouldBe` [["act", "part"]]
      messages `shouldBe` []

  -- The node a ref lands on is the one that starts at the first token after
  -- it, whatever kind of node that is. Each case puts a ref on the line above
  -- a different kind of construct and reads where the node that holds it starts.
  describe "the node a @ref lands on" $ do
    it "is the operand after it, when the ref sits inside an expression" $ do
      refPlacements "DECIDE r IS 1 +\n  @ref https://example.com/operand\n  2\n"
        `shouldReturn` [((3, 3), "operand")]

    it "is the operand after it, inside the LEFT operand of an infix call" $ do
      -- The range of an infix call is its keyword and no more, so the call
      -- starts after its left operand, and used to claim the ref in it.
      refPlacements
        (Text.unlines
          [ "GIVEN a IS A NUMBER, b IS A NUMBER"
          , "GIVETH A NUMBER"
          , "a `plus` b MEANS a + b"
          , ""
          , "DECIDE r IS (1 +"
          , "  @ref https://example.com/two"
          , "  2) `plus` 3"
          ])
        `shouldReturn` [((7, 3), "two")]

    it "is the whole infix call, when the ref sits above the call" $ do
      -- The call's own range is its keyword, but the call starts where its
      -- left operand does, so a ref above the whole call is the call's, and
      -- not its left operand's.
      (holders, bodyRange) <-
        refHoldersAndBody
          (Text.unlines
            [ "GIVEN a IS A NUMBER, b IS A NUMBER"
            , "GIVETH A NUMBER"
            , "a `plus` b MEANS a + b"
            , ""
            , "DECIDE s IS"
            , "  @ref https://example.com/whole"
            , "  (1 + 2) `plus` 3"
            ])
      holders `shouldBe` [bodyRange]

    it "is the type after it" $ do
      refPlacements "GIVEN x IS A\n  @ref https://example.com/type\n  NUMBER\nDECIDE r IS x\n"
        `shouldReturn` [((3, 3), "type")]

    it "is the field after it" $ do
      refPlacements "DECLARE Person HAS\n  @ref https://example.com/field\n  name IS A STRING\n"
        `shouldReturn` [((3, 3), "field")]

    it "is the branch after it, in a CONSIDER" $ do
      refPlacements
        (Text.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE f n IS"
          , "  CONSIDER n"
          , "  @ref https://example.com/branch"
          , "  WHEN 0 THEN 1"
          , "  OTHERWISE 2"
          ])
        `shouldReturn` [((6, 3), "branch")]

    -- A @REFUSE@ is an expression like any other, and takes the ref above it.
    it "is a REFUSE, when the ref sits above it" $ do
      refPlacements
        (Text.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE f n IS"
          , "  @ref https://example.com/refusal"
          , "  REFUSE \"not modelled\""
          ])
        `shouldReturn` [((5, 3), "refusal")]

    it "is a REFUSE in a branch, when the ref sits above it" $ do
      refPlacements
        (Text.unlines
          [ "GIVEN n IS A NUMBER"
          , "GIVETH A NUMBER"
          , "DECIDE f n IS"
          , "  IF n AT LEAST 18"
          , "  THEN 1"
          , "  ELSE"
          , "    @ref https://example.com/refusal"
          , "    REFUSE \"not modelled\""
          ])
        `shouldReturn` [((8, 5), "refusal")]

    -- A group of clauses is compiled to one definition: a CONSIDER on the first
    -- clause, and a local definition, with a range of its own, that holds the
    -- clauses after it and is written after the first clause's body. A ref
    -- inside the first clause, or above a later one, is held by the first node
    -- the drafter wrote after it, and never by that generated definition.
    it "is a node the drafter wrote, in a rule written as clauses" $ do
      holders <-
        refHolderMarks
          (Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A STRING"
            , "@ref https://example.com/above-group"
            , "DECIDE `how many` 0 IS <<in-clause-1>> \"none\""
            , "@ref https://example.com/above-clause-2"
            , "DECIDE `how many` 1 IS \"one\""
            , "@ref https://example.com/above-clause-3"
            , "DECIDE `how many` other IS \"many\""
            ])
      holders
        `shouldBe` [ (4, False, "above-group")
                   , (4, False, "in-clause-1")
                   , (6, False, "above-clause-2")
                   , (8, False, "above-clause-3")
                   ]

  -- An @\@ref@ goes to the first node that starts at or after its end, and
  -- every node visited used to scan every ref not yet claimed, so a file with
  -- a citation on each of n definitions took time quadratic in n: 16,000 of
  -- them took 30 s to check, where the same definitions without citations
  -- took 2 s. With that scan, parsing 8,000 definitions took 44 to 45 times as
  -- long as 1,000 (four runs). Linear is 8 times, so this times 1,000 and
  -- 8,000 lines and fails above 30, which leaves the noise of a busy machine
  -- room on one side and the quadratic scan on the other.
  it "attaches @ref citations in time linear in their number" $
    attachesInLinearTimeOn getCPUTime 1000 8000 30 citedDefinition

  -- The guard above reads the CPU clock. On Windows it ticks every 15.625 ms,
  -- and 1,000 lines parse in about four of those: the small sample was read
  -- once, to within a quarter either way (review of legalese/l4-ide#648). This
  -- runs the guard on a clock that reads as Windows' does; the guard times
  -- enough parses of the small file to span half a second (32 steps).
  it "judges a linear parse linear on a clock that ticks every 15.625 ms" $
    attachesInLinearTimeOn (steppedClock windowsClockStep getCPUTime) 1000 8000 30 citedDefinition

  -- The control for the one above: on the same clock, a parse that takes time
  -- quadratic in the lines is still failed.
  it "still fails a quadratic parse on that clock" $ do
    ratio <- linearTimeRatioOn (steppedClock windowsClockStep getCPUTime) quadraticParse 1000 8000 30 (const "x")
    case ratio of
      Nothing -> pendingWith "the clock did not tick, so there is no ratio to judge"
      Just r -> r `shouldSatisfy` (>= 30)

  -- A clock that never ticks gives no ratio, and the search for a measurable
  -- stretch is bounded, so the guard goes pending within seconds and not
  -- minutes.
  it "gives no ratio within seconds on a clock that never ticks" $ do
    t0 <- getMonotonicTime
    ratio <- linearTimeRatioOn (pure 0) parseCountingDecides 1000 8000 30 citedDefinition
    t1 <- getMonotonicTime
    ratio `shouldBe` Nothing
    (t1 - t0) `shouldSatisfy` (< 30)

  -- The inline `<<…>>` form shares its lexer with `@nlg`'s `[…]` form only in
  -- the sense that both are "an annotation between heralds". They must NOT
  -- share an escape: `L4.Nlg.unescapeNlgText` runs on the NLG linearizer's path
  -- alone, so a backslash consumed on the ref path would be kept for ever and
  -- the pre-escape text would stop being writable.
  --
  -- Both cases below were broken, briefly, by a first cut of the `\%`/`\]`
  -- escape that let `refAnnotation` share the escaping body. Neither had a
  -- witness anywhere in the corpus or the specs, which is why they are here.
  -- An inline @ref attaches to the node that FOLLOWS it, so these put the
  -- annotation above the body rather than after it; trailing it would leave it
  -- unattached and the assertion would be about nothing.
  --
  -- `\>` escapes a right angle bracket (ruled 2026-09-17). Before that a
  -- literal `>>` inside a citation was unrepresentable, because the annotation
  -- terminated at the first one. The decode happens where the parser builds the
  -- 'Ref' node, NOT in the lexer: the token stays verbatim so exactprint
  -- re-emits the citation byte for byte.
  -- The expected values keep their `<<`/`>>`: 'getRef' hands back the
  -- annotation as the lexer captured it, delimiters and all, and every reader
  -- strips them itself ('L4.Docassemble.Lower.citationText' does, with
  -- stripPrefix/stripSuffix — checked, because a reader that split on the FIRST
  -- `>>` would mis-strip a citation that now legitimately contains one; none
  -- does).
  describe "the inline @ref form escapes its closing herald" $ do
    it "keeps a lone > as ordinary text rather than ending the annotation" $ do
      -- Unchanged by the escape, and it must stay that way: a `>` that does not
      -- complete the herald is ordinary text and always has been.
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<s.5 > s.3>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<s.5 > s.3>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "carries a literal >> through an escaped herald, decoded for the reader" $ do
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<see s.5 \\>> onward>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<see s.5 >> onward>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "leaves a backslash that cannot begin an escape as ordinary text" $ do
      -- `\q` is not an escape, so it stays two characters — the same rule the
      -- NLG side follows, and the reason the lexer consumes exactly the set the
      -- decoder honours.
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<see s.5\\q here>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<see s.5\\q here>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "decodes an escaped backslash" $ do
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  <<see s.5 \\\\ here>>\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldBe` "<<see s.5 \\ here>>"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

    it "decodes in the LINE form too, where the herald is not special" $ do
      -- Nothing needs escaping on a line annotation — it runs to end of line —
      -- but the decode is applied at the Ref node, which both forms share, so
      -- the two spellings cannot disagree about what `\>` means.
      bodies <-
        decideBodyRefs
          "GIVEN x IS A BOOLEAN\nDECIDE p IF\n  @ref see s.5 \\> onward\n  x\n"
      case bodies of
        [(_, Just t)] -> t `shouldSatisfy` Text.isInfixOf "s.5 > onward"
        _ -> expectationFailure $ "Expected one DECIDE carrying a @ref, got: " <> show (length bodies)

-- | The message for a @\@ref@ with nothing after it. Quoted in
-- @doc/reference/syntax/README.md@, which is the page to change with it.
endOfFile :: Text -> Text
endOfFile citation =
  "This @ref (`" <> citation <> "`) is at the end of the file, so there is nothing after it to attach to."

-- | The message for a @\@ref@ that follows the given code on its line.
afterCode :: Text -> Text -> Text
afterCode citation code =
  "This @ref (`" <> citation <> "`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `" <> code <> "`."
