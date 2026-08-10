{-# LANGUAGE OverloadedStrings #-}

-- | Round-trip coverage for the 'L4.Print.prettyLayout' whole-module printer
-- (compiler review target T10): parse source, print it, and re-parse the
-- printed output. 'prettyLayout' is the printer the REPL and jl4-service use to
-- reconstruct a module; unlike ExactPrint (which feeds the @.ep.golden@ files)
-- it is exercised by no golden, so these unparseable-output regressions
-- (@DIVIDED@ without @BY@, a dropped @TIMEZONE IS@, and a GIVEN signature
-- jammed onto @DECLARE@/@ASSUME@) had no test guarding them.
module PrintRoundtripSpec (spec) where

import Base

import qualified Data.Text as T
import L4.Parser (execProgramParserWithHintPass)
import L4.Print (prettyLayout)
import Test.Hspec

spec :: Spec
spec =
  describe "prettyLayout output re-parses (review T10)" $ do
    roundtrips "DIVIDED BY" ["DIVIDED BY"] dividedSrc
    roundtrips "prefix EXPONENT power" [] exponentSrc
    roundtrips "TIMEZONE IS declaration" ["TIMEZONE IS"] timezoneSrc
    roundtrips "GIVEN-parametrised DECLARE" [] declareSrc
    roundtrips "GIVEN-parametrised ASSUME" [] assumeSrc

-- | Assert that @src@ parses, its 'prettyLayout' contains every @mustContain@
-- fragment, and that printed output parses again. A pure re-parse check catches
-- the DIVIDED/DECLARE/ASSUME breaks; TIMEZONE loss is silent (the rest still
-- parses), so it is pinned with a containment assertion.
roundtrips :: String -> [T.Text] -> T.Text -> Spec
roundtrips name mustContain src =
  it ("round-trips " <> name) $ do
    let uri = toNormalizedUri (Uri "file:///print-roundtrip-spec")
    case execProgramParserWithHintPass uri src of
      Left errs -> expectationFailure ("fixture source failed to parse: " <> show errs)
      Right (modul, _hints, _warnings) -> do
        let printed = prettyLayout modul
        for_ mustContain $ \needle ->
          unless (needle `T.isInfixOf` printed) $
            expectationFailure $
              "printed output is missing " <> show needle <> ":\n" <> T.unpack printed
        case execProgramParserWithHintPass uri printed of
          Left errs ->
            expectationFailure $
              "prettyLayout output did NOT re-parse:\n--- printed ---\n"
                <> T.unpack printed
                <> "\n--- errors ---\n"
                <> show errs
          Right _ -> pure ()

dividedSrc :: T.Text
dividedSrc = T.unlines
  [ "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE half x IS x DIVIDED BY 2"
  ]

exponentSrc :: T.Text
exponentSrc = T.unlines
  [ "GIVETH A NUMBER"
  , "DECIDE e IS EXPONENT 2 10"
  ]

timezoneSrc :: T.Text
timezoneSrc = T.unlines
  [ "TIMEZONE IS \"Asia/Singapore\""
  , "GIVETH A NUMBER"
  , "DECIDE answer IS 42"
  ]

declareSrc :: T.Text
declareSrc = T.unlines
  [ "GIVEN a IS A TYPE"
  , "DECLARE Pair a HAS"
  , "    fst IS AN a"
  , "    snd IS AN a"
  ]

assumeSrc :: T.Text
assumeSrc = T.unlines
  [ "GIVEN a IS A TYPE"
  , "ASSUME emptyThing IS LIST OF a"
  ]
