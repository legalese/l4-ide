{-# LANGUAGE OverloadedStrings #-}

module MaybeLiftSpec (spec) where

import Test.Hspec

import Backend.MaybeLift (liftTypeText)

spec :: SpecWith ()
spec = describe "MaybeLift" $ do
  describe "liftTypeText" $ do
    -- Primitives get wrapped in MAYBE
    it "lifts BOOLEAN to MAYBE BOOLEAN" $ do
      liftTypeText "BOOLEAN" `shouldBe` "MAYBE BOOLEAN"

    it "lifts NUMBER to MAYBE NUMBER" $ do
      liftTypeText "NUMBER" `shouldBe` "MAYBE NUMBER"

    it "lifts STRING to MAYBE STRING" $ do
      liftTypeText "STRING" `shouldBe` "MAYBE STRING"

    -- DATE gets converted to STRING (JSON has no date type)
    it "lifts DATE to MAYBE STRING" $ do
      liftTypeText "DATE" `shouldBe` "MAYBE STRING"

    -- Already-MAYBE primitives stay as-is (no double-wrap)
    it "keeps MAYBE BOOLEAN unchanged" $ do
      liftTypeText "MAYBE BOOLEAN" `shouldBe` "MAYBE BOOLEAN"

    it "keeps MAYBE NUMBER unchanged" $ do
      liftTypeText "MAYBE NUMBER" `shouldBe` "MAYBE NUMBER"

    it "keeps MAYBE STRING unchanged" $ do
      liftTypeText "MAYBE STRING" `shouldBe` "MAYBE STRING"

    -- MAYBE DATE must become MAYBE STRING for JSON compatibility
    it "converts MAYBE DATE to MAYBE STRING" $ do
      liftTypeText "MAYBE DATE" `shouldBe` "MAYBE STRING"

    -- MAYBE complex types stay as-is (no double-wrap)
    it "keeps MAYBE of custom type unchanged" $ do
      liftTypeText "MAYBE `Corporate Event`" `shouldBe` "MAYBE `Corporate Event`"

    it "keeps MAYBE of record type unchanged" $ do
      liftTypeText "MAYBE Person" `shouldBe` "MAYBE Person"

    -- Custom types get wrapped in MAYBE
    it "lifts custom type to MAYBE" $ do
      liftTypeText "`Corporate Event`" `shouldBe` "MAYBE `Corporate Event`"

    it "lifts record type to MAYBE" $ do
      liftTypeText "Person" `shouldBe` "MAYBE Person"

    -- LIST types
    it "lifts LIST OF NUMBER" $ do
      liftTypeText "LIST OF NUMBER" `shouldBe` "MAYBE (LIST OF (MAYBE NUMBER))"

    it "keeps MAYBE (LIST OF NUMBER) without double-lifting inner elements" $ do
      liftTypeText "MAYBE (LIST OF NUMBER)" `shouldBe` "MAYBE (LIST OF NUMBER)"

    -- prettyLayout prints every type application as `T OF p1, p2`, so this is the
    -- spelling liftTypeToMaybe actually receives. The output must never keep the
    -- OF: in the wrapper's record it would read the next field as an argument.
    it "reads prettyLayout's MAYBE OF NUMBER" $ do
      liftTypeText "MAYBE OF NUMBER" `shouldBe` "MAYBE NUMBER"

    it "converts prettyLayout's MAYBE OF DATE to MAYBE STRING" $ do
      liftTypeText "MAYBE OF DATE" `shouldBe` "MAYBE STRING"

    it "reads prettyLayout's MAYBE OF a record type" $ do
      liftTypeText "MAYBE OF Person" `shouldBe` "MAYBE Person"

    it "reads prettyLayout's MAYBE OF (LIST OF NUMBER)" $ do
      liftTypeText "MAYBE OF (LIST OF NUMBER)" `shouldBe` "MAYBE (LIST OF NUMBER)"

    it "lifts prettyLayout's LIST OF (MAYBE OF NUMBER) without a double MAYBE" $ do
      liftTypeText "LIST OF (MAYBE OF NUMBER)" `shouldBe` "MAYBE (LIST OF (MAYBE NUMBER))"

    it "brackets a type application with more than one argument" $ do
      liftTypeText "EITHER OF STRING, NUMBER" `shouldBe` "MAYBE (EITHER OF STRING, NUMBER)"
