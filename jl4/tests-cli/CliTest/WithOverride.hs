-- | Black-box tests for smucclaw/l4-ide#1000: an export that overrides a
-- section @GIVEN@ with an inner @WITH@. @l4 run@ answers such a module, and
-- @l4 batch@ used to refuse it with "You are giving named inputs to ... of
-- type NUMBER ... but it is not a function, so it takes none", even when every
-- input was supplied: it redefined the section @GIVEN@ as a plain value, so a
-- rule that read it was no longer a function of it and the @WITH@ had nothing
-- to override. Now a section @GIVEN@ stays in the module and the batch's call
-- supplies it by name, with @WITH@, as @#EVAL@ does; a written @ASSUME@ is
-- still redefined over the row.
--
-- Five of the seven tests fail on a binary built from 35aa3bd67 (measured
-- 2026-11-17), each with a row of status "error"; the two that pass there, the
-- one that runs @l4 run@ and the one that validates, are controls.
module CliTest.WithOverride (spec, fixtures) where

import qualified Data.Aeson as Aeson
import Data.Aeson (Value (..))
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.List (isInfixOf)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import Test.Hspec

import CliTest.Common

dir :: FilePath
dir = "tests-cli" </> "fixtures" </> "batch-with-override"

oneRead, everyRead, writtenToo, noGivens, supplied, omitted, writtenTooRows, noGivensRows :: FilePath
oneRead = dir </> "one-read-one-override.l4"
everyRead = dir </> "every-read-overridden.l4"
writtenToo = dir </> "written-assume-too.l4"
noGivens = dir </> "no-givens.l4"
supplied = dir </> "supplied.json"
omitted = dir </> "omitted.json"
writtenTooRows = dir </> "written-assume-too.json"
noGivensRows = dir </> "no-givens.json"

fixtures :: [FilePath]
fixtures = [oneRead, everyRead, writtenToo, noGivens, supplied, omitted, writtenTooRows, noGivensRows]

-- | Each row `l4 batch` printed, one JSON object per line.
batchRows :: FilePath -> [String] -> IO (ExitCode, [Value])
batchRows bin args = do
  Output code sout _ <- runL4 bin args
  let rows = [ v | l <- lines sout, Right v <- [Aeson.eitherDecode (BSL8.fromStrict (TE.encodeUtf8 (T.pack l)))] ]
  -- a run that printed nothing is not a run that agreed with anything
  length rows `shouldSatisfy` (> 0)
  pure (code, rows)

-- | What a row came to: its status, its result and what it presumed.
summary :: Value -> (Maybe Value, Maybe Value, Maybe Value)
summary row =
  ( objField row "status"
  , case objField row "output" of
      Just (Array rs) | [r] <- foldr (:) [] rs -> objField r "result"
      _ -> Nothing
  , objField row "presumed"
  )

answered :: Integer -> [String] -> (Maybe Value, Maybe Value, Maybe Value)
answered n presumed = (Just (String "success"), Just (Number (fromInteger n)), Just (Array (foldr ((<>) . pure . String . T.pack) mempty presumed)))

spec :: FilePath -> Spec
spec bin = describe "an inner WITH over a section GIVEN, in l4 batch (smucclaw/l4-ide#1000)" $ do
  -- the controls: the answers `l4 run` gives, which batch has to agree with
  it "l4 run answers 103 for the issue's module, and 300 when every read is overridden" $ do
    Output code sout _ <- runL4 bin ["run", oneRead]
    code `shouldBe` ExitSuccess
    sout `shouldSatisfy` ("103" `isInfixOf`)
    Output code' sout' _ <- runL4 bin ["run", everyRead]
    code' `shouldBe` ExitSuccess
    sout' `shouldSatisfy` ("300" `isInfixOf`)

  it "answers the issue's module when every input is supplied, as l4 run does, and exits 0" $ do
    (code, rows) <- batchRows bin ["batch", oneRead, "--inputs", supplied]
    map summary rows `shouldBe` [answered 103 [], answered 115 []]
    code `shouldBe` ExitSuccess

  it "takes the default for the input a row leaves out, lists it as presumed, and still overrides the other read" $ do
    (code, rows) <- batchRows bin ["batch", oneRead, "--inputs", omitted]
    map summary rows `shouldBe` [answered 103 ["r"]]
    code `shouldBe` ExitSuccess

  it "answers a module in which every read is overridden, whether or not the row supplies the input" $ do
    (_, withR) <- batchRows bin ["batch", everyRead, "--inputs", supplied]
    map summary withR `shouldBe` [answered 300 [], answered 310 []]
    (_, without) <- batchRows bin ["batch", everyRead, "--inputs", omitted]
    -- the default is never read, so nothing is presumed
    map summary without `shouldBe` [answered 300 []]

  it "keeps a written ASSUME redefined over the row beside a section GIVEN that is overridden" $ do
    (code, rows) <- batchRows bin ["batch", writtenToo, "--inputs", writtenTooRows]
    map summary rows `shouldBe` [answered 114 [], answered 114 ["r"]]
    code `shouldBe` ExitSuccess

  it "answers an export that has no GIVEN of its own and reads only a section GIVEN" $ do
    (code, rows) <- batchRows bin ["batch", noGivens, "--inputs", noGivensRows]
    map summary rows `shouldBe` [answered 105 [], answered 103 ["r"]]
    code `shouldBe` ExitSuccess

  it "--validate-only accepts the row that evaluates" $ do
    env <- jsonEnvelope bin ["batch", oneRead, "--inputs", omitted, "--validate-only"]
    objField env "status" `shouldBe` Just (String "valid")
