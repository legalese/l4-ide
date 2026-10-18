module UUID5Spec (spec) where

import Test.Hspec
import L4.Crypto.UUID5
import L4.Crypto.SHA1
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import Control.Exception (evaluate)
import Numeric (showHex)
import System.Timeout (timeout)

-- Helper to show ByteString as hex
toHex :: BS.ByteString -> String
toHex = concatMap (\b -> let s = showHex b "" in if length s == 1 then '0':s else s) . BS.unpack

spec :: Spec
spec = do
  describe "SHA1" $ do
    -- Test vectors from RFC 3174
    it "hashes empty string correctly" $ do
      -- SHA1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
      toHex (sha1 "") `shouldBe` "da39a3ee5e6b4b0d3255bfef95601890afd80709"
    
    it "hashes 'abc' correctly" $ do
      -- SHA1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
      toHex (sha1 "abc") `shouldBe` "a9993e364706816aba3e25717850c26c9cd0d89d"

    -- The two vectors above fit in one 64-byte block. These do not, and the
    -- message schedule is rebuilt for every block, so they are what pins it.
    it "hashes the two-block FIPS 180 vector correctly" $ do
      toHex (sha1 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
        `shouldBe` "84983e441c3bd26ebaae4aa1f95129e5e54670f1"

    -- A schedule word is the XOR of four earlier ones, and the first
    -- implementation computed each one afresh from the message every time it was
    -- read: about 1.4 million word computations per 64-byte block, so 3.4 ms a
    -- block and 54 s for this input (15,625 blocks). The schedule is now built
    -- once per block, and this takes about 21 ms (both measured on one machine
    -- with ghc -O1, 2026-10-12). The limit is 1 s: about 50 times the new time,
    -- so a loaded CI runner does not trip it, and about 50 times under the old
    -- one, so a return to the old recursion does.
    it "hashes one million 'a' (FIPS 180) correctly, and in well under a second" $ do
      r <- timeout 1000000 (evaluate (toHex (sha1 (BS.replicate 1000000 97))))
      r `shouldBe` Just "34aa973cd4c4daa4f61eeb2bdbad27316534016f"

    -- Digests of a fixed byte pattern, taken from the implementation that
    -- recomputed the schedule (before the change that memoised it) and checked
    -- against Python's hashlib. The lengths straddle the padding boundaries: 55
    -- bytes is the longest message that pads into one block, 56 the shortest that
    -- needs a second, and each multiple of 64 adds a block of its own.
    it "gives the digests it gave before the message schedule was memoised" $ do
      let pattern n = BS.pack [fromIntegral ((i * 7 + 3) `mod` (251 :: Int)) | i <- [0 .. n - 1]]
          pinned =
            [ (55, "8829dc293fb52f1477aa7323310a5bcf949ce4f8")
            , (56, "3c440665799f6f245108a068a11e59507d4f9e2c")
            , (63, "5e2cdca8ef9552e40ad2228153e778e586eebc50")
            , (64, "24d0ab86ac7542b26241687c97b79ae2cc22ac90")
            , (65, "f71ba60012ec8015b3d5ba56798c4ff43aeb8beb")
            , (119, "ea44537c014a6f0d332e845ed7f9331ae45440c5")
            , (120, "939b2cbff515552d0bc4cfa0c332a57f9fce7736")
            , (127, "f5b00f038e9a8ef4711336bba10726c553d46063")
            , (128, "0a1d410f25f3840e4498a2ad922fea55bb4b79da")
            , (1000, "576418509284cbe426fa53fa4aa8da5fee1ab095")
            , (100000, "b7555387ac439464653af06a617526b53bb6eeaa")
            ]
      [(n, toHex (sha1 (pattern n))) | (n, _) <- pinned] `shouldBe` pinned

  describe "UUID5" $ do
    it "generates a valid UUIDv5 format" $ do
      let result = T.unpack $ toText $ generateNamed namespaceURL $ TE.encodeUtf8 "test"
      -- UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      length result `shouldBe` 36
      -- Check dashes are in correct positions
      result !! 8 `shouldBe` '-'
      result !! 13 `shouldBe` '-'
      result !! 18 `shouldBe` '-'
      result !! 23 `shouldBe` '-'
      -- Version should be 5 (position 14, 0-indexed)
      result !! 14 `shouldBe` '5'
      -- Variant should be 8, 9, a, or b (position 19, 0-indexed)
      result !! 19 `shouldSatisfy` (`elem` ("89ab" :: String))

    it "generates deterministic UUIDs" $ do
      let result1 = toText $ generateNamed namespaceURL $ TE.encodeUtf8 "http://example.com"
      let result2 = toText $ generateNamed namespaceURL $ TE.encodeUtf8 "http://example.com"
      result1 `shouldBe` result2

    it "generates different UUIDs for different inputs" $ do
      let result1 = toText $ generateNamed namespaceURL $ TE.encodeUtf8 "test1"
      let result2 = toText $ generateNamed namespaceURL $ TE.encodeUtf8 "test2"
      result1 `shouldNotBe` result2

    it "generates different UUIDs for different namespaces" $ do
      let result1 = toText $ generateNamed namespaceURL $ TE.encodeUtf8 "test"
      let result2 = toText $ generateNamed namespaceDNS $ TE.encodeUtf8 "test"
      result1 `shouldNotBe` result2
