-- | The @l4/embeddedLibrary@ request: how an editor reads a stdlib module that
-- exists only inside the @jl4-lsp@ binary.
--
-- With JL4_LIBRARY_PATH unset, go-to-definition on @sum@ answers
-- @jl4-embedded:\/prelude.l4@, a URI no editor can open on its own. The VS Code
-- extension asks the server for the text instead, and shows it read-only.
--
-- The property that matters is that the text served IS the text compiled into
-- the binary, which is what the build graph reads: the ranges in definitions and
-- hovers refer to it, so a copy that differed by a line would put every jump in
-- the wrong place. The @libraries\/@ folder shipped beside the binary can differ
-- from the embed; the server cannot differ from itself.
module EmbeddedLibrarySpec (spec) where

import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import Data.Text (Text)

import Language.LSP.Protocol.Types (Uri (..), fromNormalizedUri)

import L4.API.EmbeddedLibraries (embeddedLibraries)
import LSP.Core.Shake (embeddedLibraryUri)
import LSP.L4.EmbeddedLibrary

import Test.Hspec

serve :: Text -> Maybe EmbeddedLibraryResponse
serve = embeddedLibraryResponse . EmbeddedLibraryParams

spec :: Spec
spec = describe "l4/embeddedLibrary" $ do

  it "has modules to serve (so the loop below is not vacuous)" $
    Map.size embeddedLibraries `shouldSatisfy` (> 0)

  it "serves, for every module the binary embeds, exactly the text it embeds" $
    forM_ (Map.toList embeddedLibraries) $ \(name, content) ->
      serve (getUri (fromNormalizedUri (embeddedLibraryUri name)))
        `shouldBe` Just (EmbeddedLibraryResponse content)

  -- The spelling go-to-definition returns, written out rather than built from
  -- 'embeddedLibraryUri': the extension's document selector and the editor both
  -- see this string, so it is part of the contract.
  it "answers to the URI go-to-definition returns for the prelude" $
    serve "jl4-embedded:/prelude.l4"
      `shouldBe` Just (EmbeddedLibraryResponse (embeddedLibraries Map.! "prelude"))

  it "refuses a file: URI for a module the binary also embeds" $
    serve "file:///work/prelude.l4" `shouldBe` Nothing

  it "refuses a module the binary does not carry" $
    serve "jl4-embedded:/zz-no-such-library.l4" `shouldBe` Nothing

  it "reads no path out of the URI" $
    serve "jl4-embedded:/../../etc/hosts" `shouldBe` Nothing

  it "speaks {uri} -> {text} on the wire" $ do
    Aeson.decode "{\"uri\":\"jl4-embedded:/prelude.l4\"}"
      `shouldBe` Just (EmbeddedLibraryParams "jl4-embedded:/prelude.l4")
    Aeson.decode (Aeson.encode (EmbeddedLibraryResponse "x"))
      `shouldBe` Just (Aeson.object ["text" Aeson..= ("x" :: Text)])
