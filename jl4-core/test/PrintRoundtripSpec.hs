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
    roundtrips "a string literal with a line break and a tab" ["\"line\\nnext\\tend\""] lineBreakSrc
    roundtrips "a REFUSE body" ["REFUSE \"not modelled\""] refuseBodySrc
    roundtrips "a REFUSE in IF branches" ["THEN REFUSE \"young\"", "ELSE REFUSE \"old\""] refuseBranchSrc
    -- Whole operands, so a bracket around either REFUSE fails the case: the
    -- brackets here are the AND nested in an OR, and nothing else.
    roundtrips "a REFUSE inside AND, OR and PLUS, unbracketed" ["(REFUSE \"left\" AND b) OR REFUSE \"right\"", "1 PLUS REFUSE \"sum\""] refuseOperandSrc
    roundtrips "a REFUSE as a function's argument, unbracketed" ["double OF REFUSE \"argument\""] refuseArgumentSrc
    roundtrips "a REFUSE projected with 's" ["(REFUSE \"no record\")'s amount"] refuseProjectionSrc

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

-- | A raw newline inside a printed string became a layout line break and took
-- the body's indentation, so the re-printed module held a different string
-- (smucclaw/l4-ide#1028). The escape must survive into the printed text.
lineBreakSrc :: T.Text
lineBreakSrc = T.unlines
  [ "GIVEN x IS A NUMBER"
  , "GIVETH A STRING"
  , "DECIDE s x IS"
  , "    IF x > 0"
  , "    THEN \"line\\nnext\\tend\""
  , "    ELSE \"no\""
  ]

-- | A REFUSE prints as the keyword and its literal, and stays one expression
-- wherever it sits: a body, a branch, an operand, an argument.
refuseBodySrc :: T.Text
refuseBodySrc = T.unlines
  [ "GIVETH A NUMBER"
  , "DECIDE r IS REFUSE \"not modelled\""
  ]

refuseBranchSrc :: T.Text
refuseBranchSrc = T.unlines
  [ "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE r x IS"
  , "    IF x > 18"
  , "    THEN REFUSE \"young\""
  , "    ELSE REFUSE \"old\""
  ]

refuseOperandSrc :: T.Text
refuseOperandSrc = T.unlines
  [ "GIVEN b IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE p b IS REFUSE \"left\" AND b OR REFUSE \"right\""
  , ""
  , "GIVETH A NUMBER"
  , "DECIDE n IS 1 PLUS REFUSE \"sum\""
  ]

refuseArgumentSrc :: T.Text
refuseArgumentSrc = T.unlines
  [ "GIVEN x IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE double x IS x TIMES 2"
  , ""
  , "GIVETH A NUMBER"
  , "DECIDE r IS double OF (REFUSE \"argument\")"
  ]

-- | The left of @'s@ is parsed as an atom (a literal, a name or a bracketed
-- expression), so a projected REFUSE must print in brackets.
refuseProjectionSrc :: T.Text
refuseProjectionSrc = T.unlines
  [ "DECLARE Rec HAS amount IS A NUMBER"
  , ""
  , "GIVETH A NUMBER"
  , "DECIDE a IS (REFUSE \"no record\")'s amount"
  ]
