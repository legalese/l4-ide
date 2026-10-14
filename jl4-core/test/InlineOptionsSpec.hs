{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | A field that lists its options inline, @`tenure` IS ONE OF Owner, Tenant@
-- (specs/proposals/INLINE-ONE-OF-FIELD-SPEC.md, option C; Note [Inline ONE OF
-- on a field] in "L4.Syntax"): what the function schema publishes for it, and
-- where going to a definition lands. The corpus files
-- @jl4/examples/ok/inline-one-of*.l4@ pin the rest (evaluation, exact print,
-- the module schema and the natural-language output).
module InlineOptionsSpec (spec) where

import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Map.Strict as Map

import L4.API.VirtualFS (checkWithImports, emptyVFS, vfsFromList)
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))
import L4.Export (ExportedFunction(..), getExportedFunctions)
import L4.FindDefinition (findDefinition)
import L4.FunctionSchema (Parameters(..), Parameter(..), parametersFromDecide)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Parser.SrcSpan (SrcPos(..), SrcRange(..))
import L4.Syntax
import Data.Maybe (isJust)

plot :: Text
plot = Text.unlines
  [ "DECLARE Kind IS ONE OF Arable, Pasture"         -- line 1
  , "DECLARE Plot HAS"                               -- line 2
  , "    `the occupier` IS A STRING"                 -- line 3
  , "    `tenure`       IS ONE OF Owner, Tenant TYPICALLY Owner" -- line 4
  , "    `kind`         IS A Kind"                   -- line 5
  , ""
  , "@export whether the plot is owned"              -- line 7
  , "GIVEN p IS A Plot"                              -- line 8
  , "      t IS A `Plot's tenure`"                   -- line 9
  , "GIVETH A BOOLEAN"
  , "`owned` p t MEANS p's tenure EQUALS Owner AND t EQUALS Owner" -- line 11
  ]

-- | The function-schema 'Parameters' of the single export in a snippet.
exportSchema :: Text -> Either [Text] Parameters
exportSchema source =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> case getExportedFunctions r.tcdModule of
      [ef] -> Right (parametersFromDecide r.tcdModule ef.exportDecide)
      efs  -> Left ["expected exactly one export, got " <> Text.pack (show (length efs))]

-- | Every top-level declaration of a checked module, through its sections.
topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls (MkModule _ _ section) = go section
 where
  go (MkSection _ _ _ _ ds) = concatMap (\ d -> d : case d of Section _ s -> go s; _ -> []) ds

-- | The start of the definition found from a 1-based line and column.
definitionAt :: Text -> Int -> Int -> Either [Text] (Maybe (Int, Int))
definitionAt source line column =
  case checkWithImports emptyVFS source of
    Left errs -> Left errs
    Right r -> Right $
      (\ rng -> (rng.start.line, rng.start.column))
        <$> findDefinition (MkSrcPos line column) r.tcdModule

spec :: Spec
spec = do
  describe "function schema" $ do
    it "publishes an inline field's options with no x-l4-type" $
      case exportSchema plot of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          let field f = Map.lookup "p" ps.parameterMap >>= (.parameterProperties) >>= Map.lookup f
          fmap (.parameterEnum) (field "tenure") `shouldBe` Just ["Owner", "Tenant"]
          fmap (.parameterL4Type) (field "tenure") `shouldBe` Just Nothing
          -- a DECLAREd enum keeps its name, as before
          fmap (.parameterL4Type) (field "kind") `shouldBe` Just (Just "Kind")

    it "publishes the default, and leaves the field out of required" $
      case exportSchema plot of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          let p = Map.lookup "p" ps.parameterMap
          fmap (.parameterDefault) (p >>= (.parameterProperties) >>= Map.lookup "tenure")
            `shouldBe` Just (Just "Owner")
          fmap (elem "tenure") (p >>= (.parameterRequired)) `shouldBe` Just False

    it "publishes no x-l4-type for a rule's input that names the generated type" $
      case exportSchema plot of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          fmap (.parameterL4Type) (Map.lookup "t" ps.parameterMap) `shouldBe` Just Nothing
          fmap (.parameterEnum) (Map.lookup "t" ps.parameterMap) `shouldBe` Just ["Owner", "Tenant"]

  -- Review round 1, finding 1: a TYPICALLY on its own line after a list
  -- whose last option has a field went to that inner field.
  describe "a default after a list on several lines" $ do
    let account = Text.unlines
          [ "DECLARE Status IS ONE OF Open, Closed"
          , "DECLARE Account HAS"
          , "  name IS A STRING"
          , "  state IS ONE OF"
          , "      Open"
          , "      Suspended HAS previous IS A Status"
          , "    TYPICALLY Open"
          , ""
          , "@export"
          , "GIVEN a IS AN Account"
          , "GIVETH A STRING"
          , "f a MEANS a's name"
          ]
        accountField ps f = Map.lookup "a" ps.parameterMap >>= (.parameterProperties) >>= Map.lookup f
    it "is the default of the field whose options they are" $
      case exportSchema account of
        Left errs -> expectationFailure (show errs)
        Right ps -> do
          fmap (.parameterDefault) (accountField ps "state") `shouldBe` Just (Just "Open")
          fmap (elem "state") (Map.lookup "a" ps.parameterMap >>= (.parameterRequired)) `shouldBe` Just False

    it "is not the default of the last option's field" $
      case checkWithImports emptyVFS account of
        Left errs -> expectationFailure (show errs)
        Right r ->
          -- the lifted `Account's state`, its option `Suspended`, its field `previous`
          [ isJust mTypically
          | Declare _ (MkDeclare _ _ (MkAppForm _ ty _ _) (EnumDecl _ cds)) <- topDecls r.tcdModule
          , nameToText (getActual ty) == "Account's state"
          , MkConDecl _ con fields <- cds
          , nameToText (getActual con) == "Suspended"
          , MkTypedName _ _ _ _ mTypically _ <- fields
          ] `shouldBe` [False]

  -- Review round 1, finding 4: a same-named type in an imported module is a
  -- clash, as for any same-named type; one in another section is not.
  describe "a clash with the generated name" $ do
    let plotlib = Text.unlines
          [ "DECLARE Plot HAS"
          , "    `tenure` IS ONE OF Owner, Tenant"
          ]
        clashes vfs source = case checkWithImports vfs source of
          Left errs -> Left errs
          Right r -> Right [ () | MkCheckErrorWithContext{kind = InlineOptionsNameClash {}} <- r.tcdErrors ]
    it "is reported for a type of that name in an imported module" $
      clashes (vfsFromList [("plotlib", plotlib)]) (Text.unlines
        [ "IMPORT plotlib"
        , "DECLARE Plot HAS"
        , "    `tenure` IS ONE OF Freehold, Leasehold"
        ]) `shouldBe` Right [()]

    it "is not reported for a type of that name in another section" $
      clashes emptyVFS (Text.unlines
        [ "§ `Plots`"
        , "DECLARE Plot HAS"
        , "    `tenure` IS ONE OF Owner, Tenant"
        , "§ `Elsewhere`"
        , "DECLARE `Plot's tenure` IS ONE OF Freehold, Leasehold"
        ]) `shouldBe` Right []

  describe "going to a definition" $ do
    it "lands on the field's ONE OF from a rule that names the generated type" $
      -- `Plot's tenure` on line 9 starts at column 14; ONE at line 4, column 23
      definitionAt plot 9 18 `shouldBe` Right (Just (4, 23))

    it "lands on the option where the field lists it" $
      -- `Owner` on line 11 starts at column 37; on line 4 at column 30
      definitionAt plot 11 39 `shouldBe` Right (Just (4, 30))
