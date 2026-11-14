{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A file that imports @daydate@, directly or through @datetime@, and
-- defines its own @YMD@ or @Year month day@ that takes three numbers and
-- gives a DATE has two meanings for the name, which no argument or context
-- tells apart, and fails to check at each place it uses the name, with
-- "There are multiple definitions for the identifier".
--
-- This is what @doc/reference/libraries/daydate.md@ tells an author, who
-- should rename their own definition. The check is the type checker's, which
-- this module does not change; the spec holds the page's statement.
--
-- How long such a file takes to check, when it uses the name many times in
-- one rule, is not tested: the page gives the measurements, and a test that
-- runs for a minute is not worth the guard.
module YmdOwnDefinitionSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.TypeCheck (prettyCheckErrorWithContext, severity)
import L4.TypeCheck.Types (Severity (..))

-- | The text of each error the type checker reports for the source, or the
-- failure to read it.
errorsOf :: Text -> IO [Text]
errorsOf src = case checkWithImports emptyVFS src of
  Left errs -> expectationFailure ("the module did not parse:\n" <> Text.unpack (Text.unlines errs)) >> pure []
  Right r -> pure [ Text.unlines (prettyCheckErrorWithContext e) | e <- r.tcdErrors, severity e == SError ]

-- | A module that imports the library, defines the name of three numbers
-- that gives a DATE, and uses it once.
usingOwn :: Text -> Text -> Text
usingOwn library name = Text.unlines
  [ "IMPORT " <> library
  , ""
  , "GIVEN year IS A NUMBER"
  , "      month IS A NUMBER"
  , "      day IS A NUMBER"
  , "GIVETH A DATE"
  , "`" <> name <> "` year month day MEANS Date day month year"
  , ""
  , "GIVETH A DATE"
  , "`the due date` MEANS `" <> name <> "` 2026 7 28"
  ]

spec :: Spec
spec = describe "a file that defines its own YMD of three numbers that gives a DATE" $ do
  let multiple = "There are multiple definitions for the identifier"
  mapM_
    (\ (library, name) ->
      it ("fails to check where it uses " <> Text.unpack name <> ", after IMPORT " <> Text.unpack library) $ do
        errs <- errorsOf (usingOwn library name)
        length errs `shouldBe` 1
        mapM_ (\ e -> do
                 e `shouldSatisfy` Text.isInfixOf multiple
                 e `shouldSatisfy` Text.isInfixOf (printed name)) errs)
    [ ("daydate", "YMD")
    , ("daydate", "Year month day")
    , ("datetime", "YMD")
    ]

  -- The controls: the page's advice, to rename the definition, makes the file
  -- check, and so does leaving it uncalled, so the failure above is the clash
  -- of the two meanings at the place the name is used, and not the file.
  it "checks once its own definition has another name" $
    errorsOf (usingOwn "daydate" "YMDx") `shouldReturn` []
  it "checks where it does not use the name" $ do
    let uncalled = Text.unlines (take 7 (Text.lines (usingOwn "daydate" "YMD")))
    errorsOf uncalled `shouldReturn` []
  where
    -- The error prints a name with a space in backticks, and one without not.
    printed name = if Text.any (== ' ') name then "`" <> name <> "`" else name
