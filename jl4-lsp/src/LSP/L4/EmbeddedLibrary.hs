{-# LANGUAGE DataKinds #-}

{-| The @l4/embeddedLibrary@ request: the source of a standard-library module
this binary carries, by its @jl4-embedded:@ URI.

An embedded module has no file on disk, so go-to-definition into @prelude@
answers with @jl4-embedded:\/prelude.l4@ (see 'Shake.embeddedLibraryUri'), and
an editor that is handed that URI has nothing to open. This is how a client
reads it.

The text is looked up in the same map the build graph reads
('Shake.embeddedLibraryText'), so what an editor shows is, by construction, the
text whose ranges the server's definitions and hovers refer to.
-}
module LSP.L4.EmbeddedLibrary
  ( EmbeddedLibraryMethodName
  , EmbeddedLibraryParams (..)
  , EmbeddedLibraryResponse (..)
  , embeddedLibraryResponse
  ) where

import Base
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import GHC.TypeLits (Symbol)

import qualified LSP.Core.Shake as Shake

type EmbeddedLibraryMethodName :: Symbol
type EmbeddedLibraryMethodName = "l4/embeddedLibrary"

newtype EmbeddedLibraryParams = EmbeddedLibraryParams
  { uri :: Text
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON EmbeddedLibraryParams where
  toJSON p = object ["uri" .= p.uri]

instance FromJSON EmbeddedLibraryParams where
  parseJSON = withObject "EmbeddedLibraryParams" $ \obj ->
    EmbeddedLibraryParams <$> obj .: "uri"

newtype EmbeddedLibraryResponse = EmbeddedLibraryResponse
  { text :: Text
  }
  deriving stock (Eq, Show, Generic)

instance ToJSON EmbeddedLibraryResponse where
  toJSON r = object ["text" .= r.text]

instance FromJSON EmbeddedLibraryResponse where
  parseJSON = withObject "EmbeddedLibraryResponse" $ \obj ->
    EmbeddedLibraryResponse <$> obj .: "text"

-- | 'Nothing' for a URI that does not name an embedded module: another scheme,
-- or a module this binary does not carry.
embeddedLibraryResponse :: EmbeddedLibraryParams -> Maybe EmbeddedLibraryResponse
embeddedLibraryResponse p =
  EmbeddedLibraryResponse <$> Shake.embeddedLibraryText (toNormalizedUri (Uri p.uri))
