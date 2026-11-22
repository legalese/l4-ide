-- | Every rule of the standard libraries reads as a sentence.
--
-- This reads the checked module and not the source text, because what matters is
-- where an annotation landed. An @\@nlg@ can sit directly above a rule and still
-- belong to something else, and nothing else reports that: the file checks, the
-- rule has no sentence, and a neighbouring name has one it was never meant to
-- have. Each test here names the rules it found, so a failure says what to fix.
module LibraryNlgSpec (spec) where

import Test.Hspec

import Base
import qualified Base.Text as Text
import Optics (gplate, toListOf, (%), (^.))

import L4.API.EmbeddedLibraries (embeddedLibraries)
import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Nlg (decideNlg, nlgRefs)
import L4.Syntax
import qualified Data.Map.Strict as Map

spec :: Spec
spec = describe "the standard libraries read as prose" $
  for_ (Map.toList embeddedLibraries) $ \ (name, source) ->
    describe (Text.unpack name) $ do
      let rules = case checkWithImports emptyVFS source of
            Left errs -> error (Text.unpack (Text.unlines errs))
            Right r   -> foldTopLevelDecides (: []) r.tcdModule

      it "gives every rule a sentence" $
        [ ruleName d | d <- rules, isNothing (decideNlg Nothing d) ] `shouldBe` []

      it "gives every input of a rule a slot in its sentence" $
        [ (ruleName d, resolvedName a)
        | d@(MkDecide _ _ (MkAppForm _ _ args _) _) <- rules
        , Just nlg <- [decideNlg Nothing d]
        , a <- args
        , getUnique a `notElem` nlgRefs nlg
        ] `shouldBe` []

      it "leaves no sentence on a name inside a rule's body" $
        [ (ruleName d, resolvedName r)
        | d@(MkDecide _ _ _ body) <- rules
        , r <- toListOf (gplate @Resolved) body
        , isJust (getActual r ^. annoOf % annNlg)
        ] `shouldBe` []
 where
  ruleName (MkDecide _ _ (MkAppForm _ n _ _) _) = resolvedName n
  resolvedName = nameToText . getActual
