module TemporalContextSpec (spec) where

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import L4.TemporalContext
  ( CtxReads (..)
  , EvalClause (..)
  , ReadObs (..)
  , TemporalContext (..)
  , applyEvalClauses
  , hasReads
  , initialTemporalContext
  , noReads
  , validFor
  )
import Test.Hspec

spec :: Spec
spec = do
  applyEvalClausesSpec
  readObsSpec
  ctxReadsSpec
  validForSpec

applyEvalClausesSpec :: Spec
applyEvalClausesSpec = describe "applyEvalClauses with UnderRulesEffectiveAt" $ do
  let targetDay = fromGregorian 2024 5 5
      systemNow = UTCTime (fromGregorian 2024 1 1) (secondsToDiffTime 0)

  it "preserves an existing encoding timestamp" $ do
    let pinnedEncoding = UTCTime (fromGregorian 2023 12 31) (secondsToDiffTime 3600)
        ctxWithEncoding =
          (initialTemporalContext systemNow)
            { tcRuleEncodingTime = Just pinnedEncoding
            }
        updated = applyEvalClauses [UnderRulesEffectiveAt targetDay] ctxWithEncoding
    updated.tcRuleEncodingTime `shouldBe` Just pinnedEncoding
    updated.tcRuleValidTime `shouldBe` Just targetDay
    updated.tcRuleVersionTime `shouldBe` Just targetDay

  it "defaults encoding time to the target day when missing" $ do
    let updated = applyEvalClauses [UnderRulesEffectiveAt targetDay] (initialTemporalContext systemNow)
        expectedEncoding = UTCTime targetDay (secondsToDiffTime 0)
    updated.tcRuleEncodingTime `shouldBe` Just expectedEncoding

-- ----------------------------------------------------------------------------
-- T6: context-read fingerprints
-- ----------------------------------------------------------------------------

t1, t2 :: UTCTime
t1 = UTCTime (fromGregorian 2025 1 31) (secondsToDiffTime 56730)
t2 = UTCTime (fromGregorian 2020 1 1) (secondsToDiffTime 0)

readObsSpec :: Spec
readObsSpec = describe "ReadObs Semigroup/Monoid" $ do
  it "NotRead is the identity" $ do
    (NotRead <> ReadEq t1) `shouldBe` ReadEq t1
    (ReadEq t1 <> NotRead) `shouldBe` ReadEq t1
    (NotRead <> NotRead) `shouldBe` (NotRead :: ReadObs UTCTime)
    (mempty :: ReadObs UTCTime) `shouldBe` NotRead

  it "agreeing observations merge" $
    (ReadEq t1 <> ReadEq t1) `shouldBe` ReadEq t1

  it "conflicting observations become ReadMixed" $
    (ReadEq t1 <> ReadEq t2) `shouldBe` ReadMixed

  it "ReadMixed absorbs everything" $ do
    (ReadMixed <> ReadEq t1) `shouldBe` ReadMixed
    (ReadEq t1 <> ReadMixed) `shouldBe` ReadMixed
    (ReadMixed <> NotRead) `shouldBe` (ReadMixed :: ReadObs UTCTime)
    (NotRead <> ReadMixed) `shouldBe` (ReadMixed :: ReadObs UTCTime)

  it "is associative on a mixed sample" $ do
    let xs = [NotRead, ReadEq t1, ReadEq t2, ReadMixed]
    sequence_
      [ ((a <> b) <> c) `shouldBe` (a <> (b <> c))
      | a <- xs, b <- xs, c <- xs
      ]

ctxReadsSpec :: Spec
ctxReadsSpec = describe "CtxReads pointwise Monoid" $ do
  let sysOnly = noReads { crSystemTime = ReadEq t1 }
      tzOnly = noReads { crDocumentTimezone = ReadEq (Just "Etc/UTC") }

  it "noReads is the identity" $ do
    (noReads <> sysOnly) `shouldBe` sysOnly
    (sysOnly <> noReads) `shouldBe` sysOnly

  it "merges axes pointwise" $
    (sysOnly <> tzOnly)
      `shouldBe` MkCtxReads
        { crSystemTime = ReadEq t1
        , crDocumentTimezone = ReadEq (Just "Etc/UTC")
        }

  it "hasReads distinguishes empty from non-empty" $ do
    hasReads noReads `shouldBe` False
    hasReads sysOnly `shouldBe` True
    hasReads tzOnly `shouldBe` True

validForSpec :: Spec
validForSpec = describe "validFor" $ do
  let ambient = initialTemporalContext t1

  it "an empty fingerprint is valid under any context" $ do
    validFor ambient noReads `shouldBe` True
    validFor (applyEvalClauses [AsOfSystemTime t2] ambient) noReads `shouldBe` True

  it "ReadEq matches / mismatches the current axis value" $ do
    let fp = noReads { crSystemTime = ReadEq t1 }
    validFor ambient fp `shouldBe` True
    validFor (applyEvalClauses [AsOfSystemTime t2] ambient) fp `shouldBe` False

  it "ReadMixed never validates" $ do
    let fp = noReads { crSystemTime = ReadMixed }
    validFor ambient fp `shouldBe` False
    validFor (applyEvalClauses [AsOfSystemTime t2] ambient) fp `shouldBe` False

  it "all read axes must match (mixed-axis combinations)" $ do
    let fp =
          MkCtxReads
            { crSystemTime = ReadEq t1
            , crDocumentTimezone = ReadEq (Just "Etc/UTC")
            }
        withTz = ambient { tcDocumentTimezone = Just "Etc/UTC" }
    validFor withTz fp `shouldBe` True
    -- one axis off: invalid
    validFor withTz { tcDocumentTimezone = Just "Asia/Singapore" } fp `shouldBe` False
    validFor (applyEvalClauses [AsOfSystemTime t2] withTz) fp `shouldBe` False

  it "a fingerprint recorded under AS OF SYSTEM TIME is invalid at ambient, and vice versa" $ do
    let overridden = applyEvalClauses [AsOfSystemTime t2] ambient
        fpInside = noReads { crSystemTime = ReadEq overridden.tcSystemTime }
        fpAmbient = noReads { crSystemTime = ReadEq ambient.tcSystemTime }
    -- direction 1: forced inside, served outside
    validFor overridden fpInside `shouldBe` True
    validFor ambient fpInside `shouldBe` False
    -- direction 2: forced outside, served inside
    validFor ambient fpAmbient `shouldBe` True
    validFor overridden fpAmbient `shouldBe` False

  it "nested overrides invalidate at each level" $ do
    let outer = applyEvalClauses [AsOfSystemTime t2] ambient
        innerTime = UTCTime (fromGregorian 2010 1 1) (secondsToDiffTime 0)
        inner = applyEvalClauses [AsOfSystemTime innerTime] outer
        fpInner = noReads { crSystemTime = ReadEq inner.tcSystemTime }
    validFor inner fpInner `shouldBe` True
    validFor outer fpInner `shouldBe` False
    validFor ambient fpInner `shouldBe` False

  it "iterator-style per-day contexts VALIDATE a systemTime-only fingerprint (sharing preserved)" $ do
    -- WHEN LAST / WHEN NEXT / EVER / ALWAYS override only the (unread)
    -- tcValidTime/tcRule* axes per day; a fingerprint keyed on READ axes
    -- must stay valid so iteration days share caches.
    let day = fromGregorian 2020 6 15
        perDay = applyEvalClauses [UnderValidTime day, UnderRulesEffectiveAt day] ambient
        fp = noReads { crSystemTime = ReadEq ambient.tcSystemTime }
    validFor perDay fp `shouldBe` True

  it "a tcDocumentTimezone change invalidates a tz-reading fingerprint" $ do
    -- covers the pre/post `TIMEZONE IS` case (a NOW forced before the decl
    -- records ReadEq Nothing; after the decl the axis is Just tz)
    let fpNoTz = noReads { crDocumentTimezone = ReadEq Nothing }
    validFor ambient fpNoTz `shouldBe` True
    validFor ambient { tcDocumentTimezone = Just "Asia/Singapore" } fpNoTz `shouldBe` False
