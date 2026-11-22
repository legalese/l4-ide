{-# LANGUAGE OverloadedStrings #-}
-- | The key of a leaf that is bigger than 'digestThreshold' once its locals are put
-- in ("L4.Viz.AtomKey", WHERE-INLINING-SPEC §10.1, R3c): a digest of the tree the
-- leaf means, worked out without building the tree.
--
-- What it must keep is R3's identity rule: a @LET@ and its body written out where
-- it is used are one proposition, so one key, at any size. And what it must not do
-- is move an id that exists: every leaf at or under the threshold is keyed exactly
-- as it was.
--
-- Terms are built by hand ("AtomKeyFixtures"), so each is the exact size it names.
-- Counts, not clocks: how much work was done, and how long a key is.
module AtomKeyDigestSpec (spec) where

import Data.Char (isAsciiUpper)
import Data.Maybe (isJust)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Numeric (showHex)
import Test.Hspec

import qualified L4.Crypto.SHA1 as SHA1
import L4.Annotation (emptyAnno)
import L4.Syntax
import L4.Viz.AtomKey
  ( DigestStats (..)
  , digestKey
  , digestPrefix
  , digestThreshold
  , inlinedSize
  , termKey
  , termKeyWith
  , textKey
  )
import qualified Data.ByteString as BS

import AtomKeyFixtures

-- | A short stand-in for a key, so a test can pin one.
fingerprint :: Text.Text -> String
fingerprint = concatMap hex . BS.unpack . BS.take 6 . SHA1.sha1 . Text.encodeUtf8
  where
    hex b = let h = showHex b "" in if length h == 1 then '0' : h else h

x :: Expr Resolved
x = var (ref (u 3) "x")

yv :: Expr Resolved
yv = var y

-- | A body of exactly @k@ nodes: AND of @k@ nodes' worth of @y@, under a NOT when
-- @k@ is even.
bodyOfSize :: Int -> Expr Resolved
bodyOfSize k
  | odd k = foldl1 (And emptyAnno) (replicate ((k + 1) `div` 2) yv)
  | otherwise = Not emptyAnno (bodyOfSize (k - 1))

viaLocal :: Expr Resolved -> Expr Resolved
viaLocal body = LetIn emptyAnno [localRule (u 200) "big" [] body] (var (ref (u 200) "big"))

spec :: Spec
spec = describe "the digest key" $ do
  describe "the two kinds of key cannot meet" $ do
    it "a digest key begins with digestPrefix" $ do
      case digestKey env (chainLet 3) of
        Just (k, _) -> k `shouldSatisfy` Text.isPrefixOf digestPrefix
        Nothing -> expectationFailure "a chain of 3 locals was not digested"

    it "a text key begins with the name of a constructor, a capital letter, which digestPrefix is not" $ do
      let terms =
            [ yv
            , And emptyAnno x yv
            , Or emptyAnno (Not emptyAnno x) yv
            , chainLet 1
            , chainLet 5
            , writtenOut 4
            , lamTerm
            ]
      mapM_ (\t -> Text.take 1 (textKey env t) `shouldSatisfy` (\c -> Text.all isAsciiUpper c && not (Text.null c))) terms
      Text.isPrefixOf digestPrefix (textKey env yv) `shouldBe` False
      Text.take 1 digestPrefix `shouldSatisfy` Text.all (not . isAsciiUpper)

  describe "the work grows with the source, not with the tree" $ do
    it "a chain of n locals is digested in work linear in n (n = 8, 16, 24, 32)" $ do
      mapM_
        ( \n -> case digestKey env (chainLet n) of
            Nothing -> expectationFailure ("a chain of " <> show n <> " locals was not digested")
            Just (_, st) -> do
              (n, st.callsEvaluated) `shouldSatisfy` \(m, c) -> c <= 3 * m
              (n, st.nodesDigested) `shouldSatisfy` \(m, c) -> c <= 20 * m
        )
        [8, 16, 24, 32]

    it "the tree such a chain means is far past the threshold, so it is not the tree that is walked" $ do
      inlinedSize (chainLet 32) `shouldBe` digestThreshold + 1

    it "the key of a chain of 32 is the length of a digest, not of a tree" $ do
      case digestKey env (chainLet 32) of
        Just (k, _) -> Text.length k `shouldBe` Text.length digestPrefix + 40
        Nothing -> expectationFailure "not digested"

  describe "a LET and its body written out are one key" $ do
    it "for chains of doubling locals, with the digest forced on (threshold 0)" $ do
      mapM_
        (\k -> termKeyWith 0 env (chainLet k) `shouldBe` termKeyWith 0 env (writtenOut (k - 1)))
        [1 .. 8]
      termKeyWith 0 env (chainLet 4) `shouldSatisfy` Text.isPrefixOf digestPrefix

    it "for a local with parameters, called twice, and for a local that calls a local" $ do
      let n = ref (u 13) "n"
          f = ref (u 10) "f"
          g = ref (u 11) "g"
          call h args = App emptyAnno h args
          fDecl = localRule (u 10) "f" [(u 13, "n")] (And emptyAnno (var n) (Not emptyAnno (var n)))
          written a = And emptyAnno a (Not emptyAnno a)
          twice = LetIn emptyAnno [fDecl] (And emptyAnno (call f [x]) (call f [yv]))
          nested =
            LetIn
              emptyAnno
              [ localRule (u 10) "f" [(u 13, "n")] (And emptyAnno (var n) yv)
              , localRule (u 11) "g" [(u 13, "n")] (And emptyAnno (call f [var n]) (call f [var n]))
              ]
              (call g [x])
          inner = And emptyAnno x yv
      termKeyWith 0 env twice `shouldBe` termKeyWith 0 env (And emptyAnno (written x) (written yv))
      termKeyWith 0 env nested `shouldBe` termKeyWith 0 env (And emptyAnno inner inner)

    it "for scopes inside scopes, and with a local nobody uses" $ do
      let a = ref (u 20) "a"
          b = ref (u 21) "b"
          unused = localRule (u 22) "unused" [] (Not emptyAnno yv)
          term =
            LetIn
              emptyAnno
              [localRule (u 20) "a" [] yv, unused]
              (LetIn emptyAnno [localRule (u 21) "b" [] (And emptyAnno (var a) (var a))] (Or emptyAnno (var b) (var b)))
          ayy = And emptyAnno yv yv
      termKeyWith 0 env term `shouldBe` termKeyWith 0 env (Or emptyAnno ayy ayy)

    it "at the threshold and one node over it, where the key changes kind" $ do
      let at = bodyOfSize digestThreshold
          over = bodyOfSize (digestThreshold + 1)
      inlinedSize (viaLocal at) `shouldBe` digestThreshold
      inlinedSize (viaLocal over) `shouldBe` digestThreshold + 1
      -- at the threshold: the show of the tree, as it has always been
      termKey env (viaLocal at) `shouldBe` termKey env at
      termKey env at `shouldBe` textKey env at
      termKey env at `shouldSatisfy` (not . Text.isPrefixOf digestPrefix)
      -- one node over: a digest, of the same tree however it was written
      termKey env (viaLocal over) `shouldBe` termKey env over
      termKey env over `shouldSatisfy` Text.isPrefixOf digestPrefix

  describe "different trees are different keys" $ do
    it "a different chain, a different connective, a different order of arguments" $ do
      let k = termKeyWith 0 env
          swapped a b = LetIn emptyAnno [localRule (u 10) "g" [(u 13, "a"), (u 14, "b")] (And emptyAnno (var (ref (u 13) "a")) (Not emptyAnno (var (ref (u 14) "b"))))] (App emptyAnno (ref (u 10) "g") [a, b])
      k (chainLet 3) `shouldNotBe` k (chainLet 4)
      k (And emptyAnno x yv) `shouldNotBe` k (Or emptyAnno x yv)
      k (swapped x yv) `shouldNotBe` k (swapped yv x)
      k (swapped x yv) `shouldBe` k (And emptyAnno x (Not emptyAnno yv))

  describe "a term it cannot digest exactly is keyed as text, at any size" $ do
    let recursiveLocal =
          LetIn emptyAnno [localRule (u 10) "f" [(u 13, "n")] (And emptyAnno (App emptyAnno (ref (u 10) "f") [var (ref (u 13) "n")]) yv)] (App emptyAnno (ref (u 10) "f") [x])
        passedAsValue =
          LetIn emptyAnno [localRule (u 10) "f" [(u 13, "n")] (And emptyAnno (var (ref (u 13) "n")) yv)] (App emptyAnno (ref (u 14) "any") [var (ref (u 10) "f")])
        declaredTwice =
          LetIn emptyAnno [localRule (u 10) "f" [] yv] (LetIn emptyAnno [localRule (u 10) "f" [] x] (var (ref (u 10) "f")))
    mapM_
      ( \(label, term) ->
          it label $ do
            digestKey env term `shouldSatisfy` (not . isJust)
            termKeyWith 0 env term `shouldBe` textKey env term
      )
      [ ("a recursive local", recursiveLocal)
      , ("a local passed as a value", passedAsValue)
      , ("a local declared twice", declaredTwice)
      , ("a lambda", lamTerm)
      ]

  describe "a leaf at or under the threshold is keyed as it was" $ do
    it "pinned keys, taken from the build before the digest key existed" $ do
      pinned `shouldBe` [(label, fingerprint (termKey env t)) | (label, t) <- pinTerms]

-- | A lambda: a binder of the term's own.
lamTerm :: Expr Resolved
lamTerm = Lam emptyAnno (MkGivenSig emptyAnno [MkOptionallyTypedName emptyAnno (Def (u 7) (nm "v")) Nothing Nothing]) (var (ref (u 7) "v"))

-- | Terms whose keys must never move.
pinTerms :: [(String, Expr Resolved)]
pinTerms =
  [ ("a variable", yv)
  , ("an AND", And emptyAnno x yv)
  , ("an OR of a NOT", Or emptyAnno (Not emptyAnno x) yv)
  , ("a chain of 1 locals", chainLet 1)
  , ("a chain of 5 locals", chainLet 5)
  , ("a chain of 5, written out", writtenOut 4)
  , ("a lambda", lamTerm)
  , ("a local called twice", twiceCalled)
  ]
  where
    n = ref (u 13) "n"
    f = ref (u 10) "f"
    twiceCalled =
      LetIn
        emptyAnno
        [localRule (u 10) "f" [(u 13, "n")] (And emptyAnno (var n) (Not emptyAnno (var n)))]
        (And emptyAnno (App emptyAnno f [x]) (App emptyAnno f [yv]))

-- | The first six bytes of the SHA-1 of each term's key, taken from the build at the
-- head of the change before this one (6b2ce09e4), where no digest key existed.
pinned :: [(String, String)]
pinned =
  [ ("a variable", "ce0a6a453fbf")
  , ("an AND", "43a4b007d35c")
  , ("an OR of a NOT", "d2ebc858dadc")
  , ("a chain of 1 locals", "ce0a6a453fbf")
  , ("a chain of 5 locals", "239c27be78b2")
  , ("a chain of 5, written out", "239c27be78b2")
  , ("a lambda", "14e1161176e9")
  , ("a local called twice", "a94948953057")
  ]
