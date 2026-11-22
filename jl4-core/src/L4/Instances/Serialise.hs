{-# LANGUAGE CPP #-}
{-# OPTIONS_GHC -Wno-orphans #-}
module L4.Instances.Serialise () where

#if defined(SERIALISE_ENABLED)
import Codec.Serialise (Serialise (..))
import Language.LSP.Protocol.Types (NormalizedUri, Uri (..), fromNormalizedUri, toNormalizedUri)

-- | Serialize 'Uri' via its 'Text' payload.
instance Serialise Uri where
  encode (Uri t) = encode t
  decode = Uri <$> decode

-- | Serialize 'NormalizedUri' by round-tripping through 'Uri'.
instance Serialise NormalizedUri where
  encode = encode . fromNormalizedUri
  decode = toNormalizedUri <$> decode

-- The instance for annotations is 'Serialise Anno' in "L4.Syntax", beside the
-- 'Extension' it keeps part of.
#endif
