{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A definition that refuses on only some paths is neither a question nor an
-- always-refusal. Whether a call to it refuses turns on what it is given, or on
-- rules the query plan does not read, so the plan can neither ask it nor report
-- its refusal: a leaf that reaches one is a refusal the plan cannot read.
--
-- The first half is the map of such definitions, from the module alone. The
-- second is the core ladder (the one the browser's plan is built from) drawing a
-- rule that reads one, in each of the three drawings.
module RefusalSpec (spec) where

import Test.Hspec
import Control.Monad (forM_, when)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Refusal (alwaysRefusing, sometimesRefusing)
import L4.Syntax
  ( AppForm (..)
  , Decide (..)
  , Module
  , Resolved
  , Unique
  , foldDecides
  , foldTopLevelDecides
  , getOriginal
  , getUnique
  , rawName
  , rawNameToText
  )
import L4.Viz.Ladder (getRefusingAtoms, getUnreadableRefusals, visualizeByNameSpelledOut, visualizeByNameWithState)

-- | Rules that always refuse, rules that refuse on some path, and rules that do
-- not refuse, each named for what it checks. A local rule is named apart from
-- every other, since the map is keyed by unique and a name here is a label.
mapSource :: Text
mapSource =
  Text.unlines
    [ "GIVETH A BOOLEAN"
    , "open MEANS FALSE"
    , ""
    , "GIVETH A BOOLEAN"
    , "always MEANS REFUSE \"always\""
    , ""
    , "GIVETH A BOOLEAN"
    , "alsoAlways MEANS always"
    , ""
    , "GIVETH A BOOLEAN"
    , "alwaysUnderWhere MEANS"
    , "  innerAlways"
    , "  WHERE"
    , "    innerAlways MEANS REFUSE \"under where\""
    , ""
    , "GIVETH A BOOLEAN"
    , "alwaysUnderLet MEANS"
    , "  LET keptAlways BE always"
    , "  IN keptAlways"
    , ""
    , "GIVETH A BOOLEAN"
    , "otherArm MEANS IF open THEN TRUE ELSE REFUSE \"other arm\""
    , ""
    , "GIVETH A BOOLEAN"
    , "viaName MEANS otherArm"
    , ""
    , "GIVETH A BOOLEAN"
    , "viaNameAndMore MEANS open AND otherArm"
    , ""
    , "GIVEN person IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "withInput person MEANS person AND otherArm"
    , ""
    , "GIVEN person IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "withInputRefusing person MEANS IF person THEN TRUE ELSE REFUSE \"with input\""
    , ""
    , "GIVETH A BOOLEAN"
    , "viaInputCall MEANS withInputRefusing TRUE"
    , ""
    , "GIVETH A BOOLEAN"
    , "besideAlways MEANS open AND always"
    , ""
    , "GIVETH A BOOLEAN"
    , "someUnderWhere MEANS"
    , "  IF open THEN TRUE ELSE innerSome"
    , "  WHERE"
    , "    innerSome MEANS REFUSE \"local\""
    , ""
    , "GIVETH A BOOLEAN"
    , "someUnderLet MEANS"
    , "  LET keptSome BE (IF open THEN TRUE ELSE REFUSE \"let\")"
    , "  IN keptSome AND open"
    , ""
    , "GIVETH A BOOLEAN"
    , "cycleA MEANS cycleB"
    , ""
    , "GIVETH A BOOLEAN"
    , "cycleB MEANS cycleA"
    , ""
    , "GIVETH A BOOLEAN"
    , "cycleTouchingA MEANS cycleTouchingB OR otherArm"
    , ""
    , "GIVETH A BOOLEAN"
    , "cycleTouchingB MEANS cycleTouchingA"
    , ""
    , "GIVETH A BOOLEAN"
    , "clean MEANS open AND TRUE"
    , ""
    , "GIVETH A BOOLEAN"
    , "viaClean MEANS clean OR open"
    ]

-- | Every definition of a module, local ones included, by unique and name.
definitions :: Module Resolved -> [(Unique, Text)]
definitions m =
  [ (getUnique n, rawNameToText (rawName (getOriginal n)))
  | MkDecide _ _ (MkAppForm _ n _ _) _ <- foldTopLevelDecides (foldDecides pure) m
  ]

-- | The names a map holds, with the reason each carries, in name order.
named :: Module Resolved -> Map.Map Unique Text -> [(Text, Text)]
named m found = List.sort [(name, reason) | (u, name) <- definitions m, Just reason <- [Map.lookup u found]]

-- | Rules for the ladder half: each queried rule reads one of the rules above it.
ladderSource :: Text
ladderSource =
  Text.unlines
    [ "GIVEN person IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "`the person is insured` person MEANS"
    , "  IF person THEN TRUE"
    , "  ELSE REFUSE \"insurance is not modelled\""
    , ""
    , "GIVEN amount IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "`the amount is allowed` amount MEANS"
    , "  IF amount GREATER THAN 0 THEN TRUE"
    , "  ELSE REFUSE \"an amount of nothing is not modelled\""
    , ""
    , "GIVETH A BOOLEAN"
    , "`the scheme is open` MEANS FALSE"
    , ""
    , "GIVETH A BOOLEAN"
    , "`the residence test is met` MEANS"
    , "  IF `the scheme is open` THEN TRUE"
    , "  ELSE REFUSE \"residence is not modelled\""
    , ""
    , "GIVETH A BOOLEAN"
    , "`the residence test is reached` MEANS `the residence test is met`"
    , ""
    , "GIVETH A BOOLEAN"
    , "`the claim is refused` MEANS REFUSE \"the claim is refused\""
    , ""
    , "GIVEN person IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "`the person is covered` person MEANS person"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      applicant IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "callWithInput adult applicant MEANS adult AND `the person is insured` applicant"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      applicant IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "callWithNamedInput adult applicant MEANS adult AND `the person is insured` WITH person IS applicant"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      amount IS A NUMBER"
    , "GIVETH A BOOLEAN"
    , "callWithNumber adult amount MEANS adult AND `the amount is allowed` amount"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "noInputs adult MEANS adult AND `the residence test is met`"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "throughAnother adult MEANS adult AND `the residence test is reached`"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "alwaysRefuses adult MEANS adult AND `the claim is refused`"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "      applicant IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "cannotRefuse adult applicant MEANS adult AND `the person is covered` applicant"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "notRead adult MEANS adult AND `the scheme is open`"
    , ""
    , "GIVEN adult IS A BOOLEAN"
    , "GIVETH A BOOLEAN"
    , "itself adult MEANS IF adult THEN TRUE ELSE `the claim is refused`"
    ]

-- | How a rule is drawn: simplified, as written, or as written with each
-- @IMPLIES@ and @IF@ spelled out.
data Drawing = Simplified | AsWritten | SpelledOut
  deriving stock (Show, Eq, Enum, Bounded)

spec :: Spec
spec = do
  describe "the definitions that refuse on only some paths" $ do
    (m, always, sometimes) <- runIO $ case checkWithImports emptyVFS mapSource of
      Left errs -> fail (Text.unpack (Text.unlines errs))
      Right r ->
        let al = alwaysRefusing r.tcdModule
         in pure (r.tcdModule, al, sometimesRefusing al r.tcdModule)

    it "holds a REFUSE on one arm of an IF, and names it as the reason" $
      lookup "otherArm" (named m sometimes) `shouldBe` Just "other arm"

    it "holds a rule that names one, as a rule of no inputs, beside another operand, or called with inputs" $ do
      let found = named m sometimes
      (lookup "viaName" found, lookup "viaNameAndMore" found, lookup "withInput" found)
        `shouldBe` (Just "other arm", Just "other arm", Just "other arm")

    it "holds a rule with inputs that refuses on a path, and a rule that calls it" $ do
      let found = named m sometimes
      (lookup "withInputRefusing" found, lookup "viaInputCall" found)
        `shouldBe` (Just "with input", Just "with input")

    it "holds a rule that reads an always-refusing rule beside another operand, which no always-refusal follows" $
      lookup "besideAlways" (named m sometimes) `shouldBe` Just "always"

    it "reads under a WHERE and under a LET" $ do
      let found = named m sometimes
      (lookup "someUnderWhere" found, lookup "someUnderLet" found, lookup "keptSome" found)
        `shouldBe` (Just "local", Just "let", Just "let")

    it "never lets a cycle of rules that only name each other join" $ do
      let found = map fst (named m sometimes)
      ("cycleA" `elem` found, "cycleB" `elem` found) `shouldBe` (False, False)

    it "lets a cycle that touches a refusal join, every member of it" $ do
      let found = named m sometimes
      (lookup "cycleTouchingA" found, lookup "cycleTouchingB" found)
        `shouldBe` (Just "other arm", Just "other arm")

    it "leaves out the rules that always refuse, whatever they are wrapped in" $ do
      let alwaysNames = map fst (named m always)
          sometimesNames = map fst (named m sometimes)
      List.sort alwaysNames
        `shouldBe` List.sort ["always", "alsoAlways", "alwaysUnderWhere", "innerAlways", "alwaysUnderLet", "keptAlways", "innerSome"]
      [n | n <- sometimesNames, n `elem` alwaysNames] `shouldBe` []

    it "leaves out rules that cannot refuse, and rules that only read them" $ do
      let found = map fst (named m sometimes)
      [n | n <- ["open", "clean", "viaClean"], n `elem` found] `shouldBe` []

    it "holds exactly these rules" $
      map fst (named m sometimes)
        `shouldBe` List.sort
          [ "otherArm", "viaName", "viaNameAndMore", "withInput", "withInputRefusing", "viaInputCall"
          , "besideAlways", "someUnderWhere", "someUnderLet", "keptSome", "cycleTouchingA", "cycleTouchingB" ]

  describe "the core ladder, on a rule that reads one that refuses on only some paths" $
    forM_ [minBound .. maxBound :: Drawing] \drawing ->
      describe (show drawing) $ do
        let draw fn = case checkWithImports emptyVFS ladderSource of
              Left errs -> Left (Text.unlines errs)
              Right r ->
                let uri = r.tcdUri
                    drawn = case drawing of
                      Simplified -> visualizeByNameWithState uri "t.l4" 1 r.tcdModule r.tcdSubstitution True fn
                      AsWritten -> visualizeByNameWithState uri "t.l4" 1 r.tcdModule r.tcdSubstitution False fn
                      SpelledOut -> visualizeByNameSpelledOut uri "t.l4" 1 r.tcdModule r.tcdSubstitution fn
                 in either (Left . Text.pack . show) Right drawn

            unreadable fn = case draw fn of
              Left e -> Left (Text.unpack e)
              Right (_, state) -> Right (List.nub (getUnreadableRefusals state))

        forM_
          [ ("a call with a Boolean input", "callWithInput", "`the person is insured` OF applicant", "insurance is not modelled")
          , ("a call with a named input", "callWithNamedInput", "`the person is insured` WITH person IS applicant", "insurance is not modelled")
          , ("a call with a NUMBER input", "callWithNumber", "`the amount is allowed` OF amount", "an amount of nothing is not modelled")
          , ("a rule of no inputs", "noInputs", "`the residence test is met`", "residence is not modelled")
          , ("a rule of no inputs reached through another", "throughAnother", "`the residence test is reached`", "residence is not modelled")
          ] \(what, fn, leaf, reason) ->
            it ("cannot read " <> what) $
              unreadable fn `shouldBe` Right [(leaf, reason)]

        forM_
          [ ("a rule that always refuses is a refusing leaf, not an unreadable one", "alwaysRefuses")
          , ("a call to a rule that cannot refuse is a question", "cannotRefuse")
          , ("a rule of no inputs that cannot refuse is a question", "notRead")
          ] \(what, fn) ->
            it ("reads: " <> what) $
              unreadable fn `shouldBe` Right []

        it "marks the always-refusing rule as a refusing leaf" $
          case draw "alwaysRefuses" of
            Left e -> expectationFailure (Text.unpack e)
            Right (_, state) -> length (getRefusingAtoms state) `shouldBe` 1

        -- Drawn simplified, a Boolean IF is one leaf that holds the refusal on its
        -- arm, which the plan cannot read; the service redraws such a rule with
        -- the IF spelled out, and that drawing reads it.
        when (drawing == SpelledOut) $
          it "reads a rule whose own IF has a refusing arm" $
            unreadable "itself" `shouldBe` Right []
