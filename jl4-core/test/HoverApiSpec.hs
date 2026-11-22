-- | The web editor's hover ('L4.API.l4Hover', exported to JavaScript as
-- @l4_hover@) names a residual inference variable as @#CHECK@ and the VS Code
-- hover do, @a@, @b@, …, and not by the checker's internal label (@x4@).
module HoverApiSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TE
import Test.Hspec

import L4.API (l4Hover)

-- | The markdown of the hover at a 0-indexed line and column, if any.
hoverValue :: Text.Text -> Int -> Int -> Maybe Text.Text
hoverValue source line col =
  case Aeson.decode (BSL.fromStrict (TE.encodeUtf8 (l4Hover source line col))) of
    Just (Aeson.Object o)
      | Just (Aeson.Object contents) <- KeyMap.lookup "contents" o
      , Just (Aeson.String value) <- KeyMap.lookup "value" contents
      -> Just value
    _ -> Nothing

spec :: Spec
spec = describe "l4Hover (the web editor's hover)" $ do
  -- column 13 is the `x` after GIVEN
  it "names an inference variable `a`, as #CHECK does" $
    hoverValue "#CHECK GIVEN x YIELD x\n" 0 13 `shouldBe` Just "```\na\n```\n"
