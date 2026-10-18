-- | The line that names a build ("LSP.L4.BuildInfo"):
-- @\<release\> (\<branch\>, \<commit\>, \<date\>)@, or @dev@.
--
-- 'renderBuildInfo' is the whole format, so it is pinned here with its inputs
-- spelled out. What a built binary prints is pinned where the binaries are run,
-- in @l4-cli-test@'s @buildVersionSpec@ (@jl4/tests-cli/Main.hs@).
module BuildInfoSpec (spec) where

import qualified Data.Text as Text

import LSP.L4.BuildInfo (buildInfoLine, renderBuildInfo)

import Test.Hspec

spec :: Spec
spec = describe "LSP.L4.BuildInfo" $ do
  describe "renderBuildInfo" $ do
    it "is exactly dev when there is no release" $
      renderBuildInfo "" "" "" "" `shouldBe` "dev"

    it "is dev whatever the branch, the commit and the date say, when there is no release" $
      renderBuildInfo "" "unstable" "0123456789abcdef" "2026-10-14" `shouldBe` "dev"

    it "is dev when the release is only white space" $
      renderBuildInfo " \r\n" "main" "0123456" "2026-10-14" `shouldBe` "dev"

    it "is the release, the branch, the commit and the date when all four are given" $
      renderBuildInfo "1.6.91" "main" "0123456" "2026-10-14" `shouldBe` "1.6.91 (main, 0123456, 2026-10-14)"

    it "keeps the first seven characters of the commit" $
      renderBuildInfo "1.6.91" "main" "0123456789abcdef0123456789abcdef01234567" "2026-10-14"
        `shouldBe` "1.6.91 (main, 0123456, 2026-10-14)"

    it "keeps a shorter commit as it is" $
      renderBuildInfo "1.6.91" "main" "abc" "2026-10-14" `shouldBe` "1.6.91 (main, abc, 2026-10-14)"

    it "keeps a branch with a slash in it" $
      renderBuildInfo "1.6.91" "feature/x" "0123456" "2026-10-14" `shouldBe` "1.6.91 (feature/x, 0123456, 2026-10-14)"

    it "says unknown when no branch was given" $
      renderBuildInfo "1.6.91" "" "0123456" "2026-10-14" `shouldBe` "1.6.91 (unknown, 0123456, 2026-10-14)"

    it "leaves out a commit that is missing" $
      renderBuildInfo "1.6.91" "main" "" "2026-10-14" `shouldBe` "1.6.91 (main, 2026-10-14)"

    it "leaves out a date that is missing" $
      renderBuildInfo "1.6.91" "main" "0123456" "" `shouldBe` "1.6.91 (main, 0123456)"

    it "is the release and its branch when the commit and the date are both missing" $
      renderBuildInfo "unstable-20261014-8b2f1a0" "unstable" "" "" `shouldBe` "unstable-20261014-8b2f1a0 (unstable)"

    it "is the release and unknown when nothing but the release is given" $
      renderBuildInfo "1.6.91" "" "" "" `shouldBe` "1.6.91 (unknown)"

    it "loses the white space around each part, so a value from a Windows shell stays one line" $
      renderBuildInfo "1.6.91\r" "main\r" "0123456\r" "2026-10-14\r\n"
        `shouldBe` "1.6.91 (main, 0123456, 2026-10-14)"

    it "turns a line break inside a part into a space, so the line cannot be broken by a variable" $ do
      renderBuildInfo "1.6.91" "ma\nin" "0123456789" "2026-10-14" `shouldBe` "1.6.91 (ma in, 0123456, 2026-10-14)"
      renderBuildInfo "1\n6" "a\r\nb" "c\nd" "e\nf"
        `shouldSatisfy` Text.all (`notElem` ['\n', '\r'])

  describe "buildInfoLine" $ do
    it "is one line" $ do
      buildInfoLine `shouldSatisfy` (not . Text.null)
      buildInfoLine `shouldSatisfy` Text.all (`notElem` ['\n', '\r'])
