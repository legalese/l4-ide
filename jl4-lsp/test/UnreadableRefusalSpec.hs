{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The editor's ladder cannot read a refusal that sits behind a rule that
-- refuses on only some paths, whether that rule is called with inputs or named,
-- and says so, as the core ladder does ("RefusalSpec" in @jl4-core@).
--
-- The service's query plan is drawn with this ladder, and answers 400 where it
-- records such a refusal.
module UnreadableRefusalSpec (spec) where

import Control.Monad (forM_)
import qualified Data.List as List
import qualified Data.Text as T

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier)

import L4.Syntax
  ( AppForm (..)
  , Decide (..)
  , Module (..)
  , Resolved
  , Section (..)
  , TopDecl (..)
  , getOriginal
  , rawName
  , rawNameToText
  )
import qualified LSP.L4.Viz.Ladder as Ladder
import LSP.L4.Rules (TypeCheckResult (..))

import CheckSource (checkSource)

import Test.Hspec

-- | The top-level definition with this name.
ruleNamed :: T.Text -> TypeCheckResult -> Decide Resolved
ruleNamed name tc = case [ d | d@(MkDecide _ _ (MkAppForm _ n _ _) _) <- go section, textOf n == name ] of
  d : _ -> d
  []    -> error ("no rule called " <> T.unpack name)
  where
    MkModule _ _ section = tc.module'
    go (MkSection _ _ _ decls) = concatMap top decls
    top = \ case
      Decide _ d -> [d]
      Section _ s -> go s
      _           -> []
    textOf = rawNameToText . rawName . getOriginal

-- | How the editor draws a rule: simplified, as written, or as written with
-- each @IMPLIES@ and @IF@ spelled out.
data Drawing = Simplified | AsWritten | SpelledOut
  deriving stock (Show, Eq, Enum, Bounded)

-- | What the ladder recorded as a refusal it cannot read, in the drawing.
unreadable :: Drawing -> VersionedTextDocumentIdentifier -> TypeCheckResult -> T.Text -> Either T.Text [(T.Text, T.Text)]
unreadable drawing verId tc name =
  either (Left . Ladder.prettyPrintVizError) (Right . List.nub . Ladder.getUnreadableRefusals . snd)
    (Ladder.doVisualize (ruleNamed name tc) (config drawing))
  where
    base simplify = Ladder.mkVizConfig verId tc.module' tc.substitution simplify
    config = \ case
      Simplified -> base True
      AsWritten  -> base False
      SpelledOut -> Ladder.spellingOut (base False)

source :: T.Text
source =
  T.unlines
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
    ]

spec :: Spec
spec = describe "a rule that reads one that refuses on only some paths, in the editor's ladder" $
  forM_ [minBound .. maxBound :: Drawing] \ drawing ->
    describe (show drawing) $ do
      forM_
        [ ("a call with a Boolean input", "callWithInput", "`the person is insured` OF applicant", "insurance is not modelled")
        , ("a call with a named input", "callWithNamedInput", "`the person is insured` WITH person IS applicant", "insurance is not modelled")
        , ("a call with a NUMBER input", "callWithNumber", "`the amount is allowed` OF amount", "an amount of nothing is not modelled")
        , ("a rule of no inputs", "noInputs", "`the residence test is met`", "residence is not modelled")
        , ("a rule of no inputs reached through another", "throughAnother", "`the residence test is reached`", "residence is not modelled")
        ] \ (what, fn, leaf, reason) ->
          it ("cannot read " <> what) $ do
            (verId, tc) <- checkSource "unreadable-refusal" source
            unreadable drawing verId tc fn `shouldBe` Right [(leaf, reason)]

      forM_
        [ ("a rule that always refuses is a refusing leaf, not an unreadable one", "alwaysRefuses")
        , ("a call to a rule that cannot refuse is a question", "cannotRefuse")
        ] \ (what, fn) ->
          it ("reads: " <> what) $ do
            (verId, tc) <- checkSource "unreadable-refusal" source
            unreadable drawing verId tc fn `shouldBe` Right []
