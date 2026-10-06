module Hover where

import Base

import qualified Base.Text as Text
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import qualified LSP.L4.Rules as Rules
import qualified LSP.L4.Actions as Actions
import LSP.Core.PositionMapping (zeroMapping)
import Language.LSP.Protocol.Types
import System.FilePath
import Test.Hspec
import Test.Hspec.Golden
import L4.EvaluateLazy (EvalConfig)

hoverTests :: EvalConfig -> [FilePath] -> FilePath -> Spec
hoverTests evalConfig files root = do
  forM_ files $ \inputFile -> do
    let testCase = makeRelative root inputFile
    let goldenDir = takeDirectory inputFile </> "tests"
    it testCase $ do
      hoverGolden evalConfig goldenDir inputFile

hoverGolden :: EvalConfig -> String -> FilePath -> IO (Golden Text)
hoverGolden evalConfig dir inputFile = do
  (errs, (nfp, mtcRes)) <- oneshotL4ActionAndErrors evalConfig inputFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    tcResult <- Shake.use Rules.TypeCheck uri
    pure (nfp, tcResult)

  let
    output = case mtcRes of
      Nothing -> "TypeCheck returned Nothing\n" <> Text.unlines errs
      Just tcRes ->
        let
          nuri = normalizedFilePathToUri nfp
          hoverPositions = positionsFor (takeFileName inputFile)
          hoverResults = map (getHoverAt tcRes nuri) hoverPositions
        in
          Text.unlines hoverResults

  pure
    Golden
      { output
      , encodePretty = Text.unpack
      , writeToFile = Text.writeFile
      , readFromFile = Text.readFile
      , goldenFile = dir </> takeFileName inputFile -<.> "hover.golden"
      , actualFile = Just (dir </> takeFileName inputFile -<.> "hover.actual")
      , failFirstTime = True
      }
 where
  -- Each fixture pins its own positions (zero-based line and column).
  positionsFor :: FilePath -> [(Position, Text)]
  positionsFor = \ case
    "desc-hover.l4" ->
      [ (Position 4 6, "age")
      , (Position 5 6, "income")
      , (Position 6 6, "hasInsurance")
      , (Position 15 6, "name")
      , (Position 16 6, "salary")
      , (Position 21 32, "name-ref")
        -- R5 (IMPLICIT-PROPS-DESIGN §11.7): a BARE opened field. The
        -- elaborated `employee's name` carries the bare read's range on
        -- BOTH the projection and its record operand, so this pin is
        -- what says hover still answers with the field's type rather
        -- than with the record the operand names.
      , (Position 28 24, "bare-opened-field")
      ]
    -- smucclaw/l4-ide#979: hover shows the OUTPUT meaning of a herald, as
    -- decided by 'L4.Nlg.promoteHeadInputNlg'.
    "nlg-site-hover.l4" ->
      [ (Position 7 3, "head-input-rule")
      , (Position 7 13, "head-input-input")
      , (Position 5 7, "head-input-given")
      , (Position 8 10, "head-input-body-ref")
      , (Position 12 7, "given-gloss-input")
      , (Position 13 9, "given-gloss-rule")
      , (Position 13 22, "given-gloss-body-ref")
      , (Position 17 30, "head-input-call-site")
        -- Controls: the sites #979 did not move must hover as before.
      , (Position 24 9, "declaration-rule")
      , (Position 21 7, "declaration-given")
      , (Position 24 23, "declaration-body-ref")
      , (Position 29 9, "head-name-rule")
      , (Position 27 7, "head-name-given")
      , (Position 30 6, "head-name-body-ref")
      , (Position 33 6, "given-name-tyvar")
      , (Position 34 6, "given-name-input")
      , (Position 36 3, "given-name-rule")
      , (Position 40 27, "declaration-call-site")
      , (Position 41 27, "head-name-call-site")
        -- smucclaw/l4-ide#978: a herald claimed by an AKA name.
      , (Position 49 3, "aka-rule")
      , (Position 49 12, "aka-input")
      , (Position 49 25, "aka-alias")
      , (Position 53 28, "aka-call-site")
      ]
    other -> error ("Hover.positionsFor: no positions pinned for " <> other)

  getHoverAt tcRes nuri (pos, label) =
    let mHover = Actions.typeHover pos nuri tcRes zeroMapping
    in  label <> ": " <> formatHover mHover

  formatHover Nothing = "No hover"
  formatHover (Just (Hover (InL (MarkupContent _ content)) _)) =
    Text.replace "\n" " | " content
  formatHover (Just (Hover (InR _) _)) = "MarkedString hover (legacy)"
