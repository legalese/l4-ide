{-# LANGUAGE OverloadedStrings #-}
-- | The term key behind a ladder atomId ("L4.Viz.AtomKey", R3), on modules built
-- by hand, so each case is exactly the situation it names and nothing has to
-- type-check or resolve.
--
-- The rule the key must keep: two different propositions never share a key.
-- The cases are the ways a key could be spelled alike by accident, found by
-- adversarial review of the design (smucclaw/l4-ide#1013).
module AtomKeySpec (spec) where

import Data.Text (Text)
import Test.Hspec

import Base (NormalizedUri, Uri (..), toNormalizedUri)
import L4.Annotation (emptyAnno)
import L4.Syntax
import L4.Viz.AtomKey (mkKeyEnv, termKey)

uri :: Text -> NormalizedUri
uri = toNormalizedUri . Uri

here :: NormalizedUri
here = uri "file:///project/main.l4"

nm :: Text -> Name
nm = MkName emptyAnno . NormalName

u :: Int -> Unique
u n = MkUnique 'c' n here

var :: Resolved -> Expr Resolved
var r = App emptyAnno r []

ref :: Unique -> Text -> Resolved
ref k t = Ref (nm t) k (nm t)

-- | A rule of no result type, with the given parameters and body.
rule :: Unique -> Text -> [Resolved] -> Expr Resolved -> TopDecl Resolved
rule k t params body =
  Decide emptyAnno $
    MkDecide emptyAnno
      (MkTypeSig emptyAnno (MkGivenSig emptyAnno [MkOptionallyTypedName emptyAnno p Nothing Nothing | p <- params]) Nothing)
      (MkAppForm emptyAnno (Def k (nm t)) [] Nothing)
      body

moduleOf :: [TopDecl Resolved] -> Module Resolved
moduleOf decls = MkModule emptyAnno here (MkSection emptyAnno Nothing Nothing Nothing decls)

-- | @Lam [binder] body@.
lam :: Resolved -> Expr Resolved -> Expr Resolved
lam b = Lam emptyAnno (MkGivenSig emptyAnno [MkOptionallyTypedName emptyAnno b Nothing Nothing])

spec :: Spec
spec = describe "L4.Viz.AtomKey.termKey" $ do
  it "two modules that share a file name are two modules (a vendored copy of a library)" $ do
    -- One name, one number, one sort; only the module's URI tells them apart.
    let embedded = MkUnique 'c' 4 (uri "jl4-embedded:/legal-persons.l4")
        vendored = MkUnique 'c' 4 (uri "file:///home/someone/.local/share/jl4/libraries/legal-persons.l4")
        a = var (ref embedded "full name")
        b = var (ref vendored "full name")
        env = mkKeyEnv (moduleOf [rule (u 1) "r" [] (And emptyAnno a b)])
    termKey env a `shouldNotBe` termKey env b

  it "a name cannot spell the ordinal that tells two same-named binders apart" $ do
    -- Two parameters named p, so the second is p's ordinal, and a third named
    -- `p#1`, which is what that ordinal would look like if it were spelled into
    -- the name.
    let p1 = Def (u 2) (nm "p")
        p2 = Def (u 3) (nm "p")
        p3 = Def (u 4) (nm "p#1")
        env = mkKeyEnv (moduleOf [rule (u 1) "r" [p1, p2, p3] (var (ref (u 2) "p"))])
        keys = [termKey env (var (ref k t)) | (k, t) <- [(u 2, "p"), (u 3, "p"), (u 4, "p#1")]]
    length keys `shouldBe` 3
    [(x, y) | (i, x) <- zip [0 :: Int ..] keys, (j, y) <- zip [0 ..] keys, i < j, x == y] `shouldBe` []

  it "a free name cannot spell a bound variable's placeholder" $ do
    -- A module-level rule literally named `bound#0`, against the first variable
    -- bound inside the term, which becomes bound#0.
    let freeName = ref (u 5) "bound#0"
        v = Def (u 6) (nm "v")
        env = mkKeyEnv (moduleOf [rule (u 5) "bound#0" [] (var freeName)])
    termKey env (lam v (var (ref (u 6) "v"))) `shouldNotBe` termKey env (lam v (var freeName))

  it "alpha-equivalent terms share a key; terms that differ do not" $ do
    let v = Def (u 7) (nm "v")
        w = Def (u 8) (nm "w")
        x = ref (u 9) "x"
        env = mkKeyEnv (moduleOf [rule (u 1) "r" [Def (u 9) (nm "x")] (var x)])
    termKey env (lam v (var (ref (u 7) "v"))) `shouldBe` termKey env (lam w (var (ref (u 8) "w")))
    termKey env (lam v (var (ref (u 7) "v"))) `shouldNotBe` termKey env (lam v (var x))

  it "two copies of ONE lambda (as substitution makes them) key as two lambdas written alike" $ do
    let v = Def (u 7) (nm "v")
        copy = lam v (var (ref (u 7) "v"))
        v1 = Def (u 8) (nm "v")
        v2 = Def (u 9) (nm "v")
        env = mkKeyEnv (moduleOf [])
    termKey env (And emptyAnno copy copy)
      `shouldBe` termKey env (And emptyAnno (lam v1 (var (ref (u 8) "v"))) (lam v2 (var (ref (u 9) "v"))))

  it "an untyped parameter's inference variable does not reach the key" $ do
    let inferred k = Lam emptyAnno
          (MkGivenSig emptyAnno [MkOptionallyTypedName emptyAnno (Def (u 7) (nm "t")) (Just (InfVar emptyAnno (NormalName "t") k)) Nothing])
          (var (ref (u 7) "t"))
        env = mkKeyEnv (moduleOf [])
    termKey env (inferred 10) `shouldBe` termKey env (inferred 13)

  it "a call with all its arguments named keys as the positional call" $ do
    let f = ref (u 1) "f"
        x = var (ref (u 2) "x")
        y = var (ref (u 3) "y")
        named order = AppNamed emptyAnno f [MkNamedExpr emptyAnno (ref (u 11) "second") y, MkNamedExpr emptyAnno (ref (u 10) "first") x] (Just order)
        env = mkKeyEnv (moduleOf [rule (u 1) "f" [Def (u 10) (nm "first"), Def (u 11) (nm "second")] x])
    termKey env (named [1, 0]) `shouldBe` termKey env (App emptyAnno f [x, y])
    -- a negative entry supplies a section binder, not a parameter: left alone
    termKey env (named [1, -1]) `shouldNotBe` termKey env (App emptyAnno f [x, y])

  it "renaming a lambda's variable in one place does not move a WHERE local named like it" $ do
    -- rule r: `t AND (GIVEN t YIELD t) ...`, where the first t is a WHERE local
    let local = LocalDecide emptyAnno $
          MkDecide emptyAnno
            (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
            (MkAppForm emptyAnno (Def (u 4) (nm "t")) [] Nothing)
            (var (ref (u 2) "x"))
        build lamName =
          let body = And emptyAnno (var (ref (u 4) "t")) (lam (Def (u 7) (nm lamName)) (var (ref (u 7) lamName)))
           in termKey (mkKeyEnv (moduleOf [rule (u 1) "r" [Def (u 2) (nm "x")] (Where emptyAnno body [local])])) (var (ref (u 4) "t"))
    build "u" `shouldBe` build "t"

  it "renumbering every unique of the module changes no key" $ do
    let build off =
          let p = Def (u (off + 2)) (nm "p")
              body = And emptyAnno (var (ref (u (off + 2)) "p")) (var (ref (u (off + 1)) "other"))
              m = moduleOf [rule (u (off + 1)) "other" [] (var (ref (u (off + 2)) "p")), rule (u (off + 3)) "r" [p] body]
           in termKey (mkKeyEnv m) body
    build 100 `shouldBe` build 0
