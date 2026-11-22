{-# LANGUAGE ExplicitNamespaces #-}

-- | Regression test for smucclaw/l4-ide#313: LSP hover over a value whose type
-- still contains a residual inference variable (e.g. an un-annotated lambda
-- parameter) used to show @x10@ instead of a clean name.
--
-- The type checker names a fresh variable after the parameter's raw name, and
-- the raw 'L4.Print.prettyLayout' 'InfVar' instance prints @rawName <> uniq@ —
-- so hover surfaced @x10@. 'infoToHover' now renders the hovered type through
-- 'L4.Print.prettyTypeForDisplay', which normalises every inference variable to
-- a stable name (@a@, @b@, …), matching the deployed schema's @returnType@.
--
-- We feed 'infoToHover' the exact 'Type'' shape from the bug report — a function
-- from an un-annotated parameter to itself, @FUNCTION FROM x10 TO x10@ — and
-- assert the produced hover markdown normalises it to @FUNCTION FROM a TO a@ and
-- no longer leaks the raw @x10@. Before the fix this test fails (markdown holds
-- @FUNCTION FROM x10 TO x10@); after it passes.
module HoverDisplaySpec (spec) where

import qualified Data.Text as T

import Language.LSP.Protocol.Types
  ( Hover (..)
  , MarkupContent (..)
  , Position (..)
  , Range (..)
  , Uri (..)
  , toNormalizedUri
  , type (|?) (InL, InR)
  )

import L4.Annotation (emptyAnno)
import L4.Syntax
  ( Info (TypeInfo)
  , Name (MkName)
  , OptionallyNamedType (MkOptionallyNamedType)
  , RawName (NormalName)
  , Resolved (Def)
  , Type' (Forall, Fun, InfVar, TyApp)
  , Unique (MkUnique)
  )
import LSP.L4.Actions (infoToHover)

import Test.Hspec

-- | The inferred type of an identity-like lambda @\\x -> x@ whose parameter @x@
-- was left un-annotated: parameter and result share the same residual inference
-- variable, whose prefix is the parameter's raw name @x@ and whose global uniq
-- is @10@ — exactly what the bug report screenshotted as @FUNCTION FROM x10 TO
-- x10@.
lambdaIdentityType :: Type' Resolved
lambdaIdentityType =
  Fun emptyAnno [MkOptionallyNamedType emptyAnno Nothing infX] infX
  where
    infX = InfVar emptyAnno (NormalName "x") 10

-- | A name the type of which prints as itself, here @a@.
namedA :: Resolved
namedA =
  Def
    (MkUnique 't' 1 (toNormalizedUri (Uri "file:///hover-display-spec")))
    (MkName emptyAnno (NormalName "a"))

-- | The type of @GIVEN `the application` YIELD approved@ in a module that
-- declares a type @a@ with the constructor @approved@: from any type to @a@.
toDeclaredAType :: Type' Resolved
toDeclaredAType =
  Fun emptyAnno [MkOptionallyNamedType emptyAnno Nothing (InfVar emptyAnno (NormalName "the application") 4)]
    (TyApp emptyAnno namedA [])

-- | The hover markdown for a type, with no substitution, NLG or description.
hoverOf :: Type' Resolved -> T.Text
hoverOf ty =
  hoverMarkdown $
    infoToHover
      (toNormalizedUri (Uri "file:///hover-display-spec"))
      mempty
      (Range (Position 0 0) (Position 0 0))
      (TypeInfo ty Nothing)
      Nothing
      Nothing

-- | The markdown body of a hover whose contents are 'MarkupContent'.
hoverMarkdown :: Hover -> T.Text
hoverMarkdown (Hover contents _range) = case contents of
  InL (MarkupContent _kind value) -> value
  InR _                           -> error "HoverDisplaySpec: expected MarkupContent hover contents"

spec :: Spec
spec =
  describe "LSP hover normalises inference variables (smucclaw/l4-ide#313)" $ do
    -- Naming the input `a` as well would print `FUNCTION FROM a TO a`, the
    -- text of the identity function, for a function into the declared `a`.
    it "skips a display name that is already a type in the hovered type" $ do
      hoverOf toDeclaredAType `shouldSatisfy` T.isInfixOf "FUNCTION FROM b TO a"
      hoverOf (Forall emptyAnno [namedA] toDeclaredAType)
        `shouldSatisfy` T.isInfixOf "FOR ALL a FUNCTION FROM b TO a"
    it "renders an un-annotated lambda type as 'a', never 'x10'" $ do
      let hov =
            infoToHover
              (toNormalizedUri (Uri "file:///hover-display-spec"))
              mempty                                   -- empty substitution
              (Range (Position 0 0) (Position 0 0))
              (TypeInfo lambdaIdentityType Nothing)
              Nothing
              Nothing
          md = hoverMarkdown hov
      md `shouldSatisfy` T.isInfixOf "FUNCTION FROM a TO a"
      md `shouldSatisfy` (not . T.isInfixOf "x10")
