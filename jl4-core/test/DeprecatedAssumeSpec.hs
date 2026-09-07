{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The @ASSUME@ deprecation warning ('L4.TypeCheck.Types.DeprecatedAssume',
-- IMPLICIT-PROPS-DESIGN.md §11.1.2) at the API boundary: it is a warning and
-- never an error, so a module that carries one is still a successful check
-- through 'checkWithImports' — the gate 'tcdSuccess' used to key on "no
-- diagnostics at all", which made this warning (and every other) fatal
-- through this one API while the LSP, @l4 check@ and the service let the
-- file through. And the role the warning names is read off the declaration's
-- shape: the three shapes below are the three roles.
module DeprecatedAssumeSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import L4.API.VirtualFS
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (AssumeRole (..), CheckError (..), CheckErrorWithContext (..), CheckWarning (..), DeprecatedAssumeInfo (..), Severity (..))

-- | The deprecation warnings a module draws, as (role, suggested line).
deprecations :: Text -> IO (Bool, [(AssumeRole, Maybe Text)])
deprecations source = case checkWithImports emptyVFS source of
  Left errs -> fail ("parse/import: " <> Text.unpack (Text.unlines errs))
  Right r -> pure
    ( r.tcdSuccess
    , [ (info.role, info.replacement)
      | MkCheckErrorWithContext (CheckWarning (DeprecatedAssume info)) _ <- r.tcdErrors
      ]
    )

spec :: Spec
spec = describe "ASSUME deprecation warning" $ do
  it "is a warning, never an error: the module still checks successfully" $ do
    (ok, ws) <- deprecations $ Text.unlines
      [ "ASSUME age IS A NUMBER"
      , "DECIDE `is adult` IF age >= 18"
      ]
    ok `shouldBe` True
    ws `shouldBe` [(AssumeTermRole, Just "GIVEN age IS A NUMBER")]
    case checkWithImports emptyVFS "ASSUME age IS A NUMBER" of
      Left _  -> expectationFailure "did not parse"
      Right r -> map TC.severity r.tcdErrors `shouldBe` [SWarn]

  it "is not drawn by a section GIVEN, which the checker sees through the same node" $ do
    (ok, ws) <- deprecations $ Text.unlines
      [ "§ `Adults`"
      , "    GIVEN age IS A NUMBER"
      , ""
      , "DECIDE `is adult` IF age >= 18"
      ]
    ok `shouldBe` True
    ws `shouldBe` []

  it "names the type role for ASSUME T IS A TYPE, with the head's parameters" $ do
    (_, ws) <- deprecations $ Text.unlines
      [ "ASSUME Person IS A TYPE"
      , "GIVEN a IS A TYPE"
      , "ASSUME Box a IS A TYPE"
      ]
    ws `shouldBe` [(AssumeTypeRole, Just "DECLARE Person"), (AssumeTypeRole, Just "DECLARE Box a")]

  it "names the any-type role when nothing could ever supply a value" $ do
    (_, ws) <- deprecations $ Text.unlines
      [ "GIVEN a IS A TYPE"
      , "ASSUME gap IS AN a"
      , "GIVEN b IS A TYPE"
      , "GIVETH b"
      , "ASSUME bottom"
      ]
    ws `shouldBe` [(AssumeAnyTypeRole, Nothing), (AssumeAnyTypeRole, Nothing)]

  it "still warns on an author-written ASSUME that shares a section GIVEN's name (refuted 2026-09-07)" $ do
    (ok, ws) <- deprecations $ Text.unlines
      [ "§ `Rates`"
      , "    GIVEN income IS A NUMBER"
      , ""
      , "ASSUME income IS A STRING"
      ]
    ok `shouldBe` True
    ws `shouldBe` [(AssumeTermRole, Just "GIVEN income IS A STRING")]

  it "names the keyword head of an infix pattern, not its first input" $ do
    (_, ws) <- deprecations $ Text.unlines
      [ "GIVEN a IS A NUMBER"
      , "      b IS A NUMBER"
      , "ASSUME a `plus` b IS A NUMBER"
      ]
    ws `shouldBe` [(AssumeTermRole, Just "GIVEN plus IS A FUNCTION FROM NUMBER AND NUMBER TO NUMBER")]

  it "treats a function over its own type variable as a term, with a <type> hole" $ do
    (_, ws) <- deprecations $ Text.unlines
      [ "GIVEN a IS A TYPE"
      , "      x IS AN a"
      , "ASSUME identity x IS AN a"
      , "GIVEN b IS A TYPE"
      , "ASSUME age IS A NUMBER"
      , "ASSUME w"
      ]
    ws `shouldBe`
      [ (AssumeTermRole, Just "GIVEN identity IS A <type>")
      , (AssumeTermRole, Just "GIVEN age IS A NUMBER")
      , (AssumeUntypedRole, Just "GIVEN w IS A <type>")
      ]

  it "spells a FOR ALL type without the article, and quotes a keyword name" $ do
    (_, ws) <- deprecations $ Text.unlines
      [ "ASSUME pick IS FOR ALL a A FUNCTION FROM a TO a"
      , "ASSUME `LIST` IS A NUMBER"
      ]
    ws `shouldBe`
      [ (AssumeTermRole, Just "GIVEN pick IS FOR ALL a FUNCTION FROM a TO a")
      , (AssumeTermRole, Just "GIVEN `LIST` IS A NUMBER")
      ]

  it "spells the function type out from the head's inputs, and carries TYPICALLY across" $ do
    (_, ws) <- deprecations $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "ASSUME `is large` n IS A BOOLEAN"
      , "ASSUME rate IS A NUMBER TYPICALLY 0.2"
      ]
    ws `shouldBe`
      [ (AssumeTermRole, Just "GIVEN `is large` IS A FUNCTION FROM NUMBER TO BOOLEAN")
      , (AssumeTermRole, Just "GIVEN rate IS A NUMBER TYPICALLY 0.2")
      ]
