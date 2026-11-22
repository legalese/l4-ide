{-# LANGUAGE OverloadedStrings #-}
-- | Terms built by hand for the specs of the term key ("L4.Viz.AtomKey"), so each
-- case is exactly the situation it names and nothing has to type-check or resolve.
module AtomKeyFixtures
  ( here
  , nm
  , u
  , var
  , ref
  , rule
  , moduleOf
  , y
  , env
  , localRule
  , chainLet
  , writtenOut
  ) where

import Data.Text (Text)
import qualified Data.Text as Text

import Base (NormalizedUri, Uri (..), toNormalizedUri)
import L4.Annotation (emptyAnno)
import L4.Syntax
import L4.Viz.AtomKey (KeyEnv, mkKeyEnv)

here :: NormalizedUri
here = toNormalizedUri (Uri "file:///project/main.l4")

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

-- | The one free name the terms below share: an input of the rule @r@.
y :: Resolved
y = ref (u 2) "y"

env :: KeyEnv
env = mkKeyEnv (moduleOf [rule (u 1) "r" [Def (u 2) (nm "y")] (var y)])

-- | A local declaration: @name params MEANS body@.
localRule :: Unique -> Text -> [(Unique, Text)] -> Expr Resolved -> LocalDecl Resolved
localRule k t params body =
  LocalDecide emptyAnno $
    MkDecide emptyAnno
      (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
      (MkAppForm emptyAnno (Def k (nm t)) [Def pk (nm p) | (pk, p) <- params] Nothing)
      body

-- | @LET a0 BE y IN LET a1 BE a0 AND y OR a0 IN ... a(n-1)@: each local names the one
-- before it twice, so what it means doubles with each, and the source does not.
chainLet :: Int -> Expr Resolved
chainLet n = go 0
  where
    go i
      | i == n = var (aRef (n - 1))
      | otherwise = LetIn emptyAnno [localRule (u (100 + i)) ("a" <> Text.pack (show i)) [] (rhs i)] (go (i + 1))
    rhs 0 = var y
    rhs i = Or emptyAnno (And emptyAnno (var (aRef (i - 1))) (var y)) (var (aRef (i - 1)))
    aRef i = ref (u (100 + i)) ("a" <> Text.pack (show i))

-- | The same proposition as @chainLet (i + 1)@, with every local written out.
writtenOut :: Int -> Expr Resolved
writtenOut 0 = var y
writtenOut i = Or emptyAnno (And emptyAnno (writtenOut (i - 1)) (var y)) (writtenOut (i - 1))
