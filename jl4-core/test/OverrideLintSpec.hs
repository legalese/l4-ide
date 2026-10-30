{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The derivation lint for override phrases (SUBJECT-TO-NOTWITHSTANDING-SPEC
-- §12.1, ruling D2): a decision whose prose says "Subject to section 6" has to
-- reach a decision for section 6.
--
-- Two halves. The text half reads a piece of prose and says which phrases name
-- a provision and which are only English ("subject to tax"); the precision of
-- the whole lint rests on it, so it is pinned shape by shape. The call-graph
-- half type-checks a small module and judges its decisions.
module OverrideLintSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS
import L4.Lint.Override

-- | One line per mention: the phrase and what became of it.
readMentions :: Text -> [Text]
readMentions t = [ phraseText m.phrase <> ": " <> shape m.klass | m <- findMentions t ]
 where
  shape = \case
    Linted ts   -> "linted " <> Text.intercalate " | " (map renderTarget ts)
    External ts -> "external " <> Text.intercalate " | " (map renderTarget ts)
    Ranged ts   -> "range " <> Text.intercalate " | " (map renderTarget ts)
    OpenClass   -> "open-class"
    NoProvision -> "no provision"

findingsOf :: Text -> IO [Finding]
findingsOf src = case checkWithImports emptyVFS src of
  Left errs -> expectationFailure (Text.unpack (Text.unlines errs)) >> pure []
  Right r   -> pure (lintModule r.tcdModule)

-- | The one-line summary of a finding: host, phrase, target, verdict.
summary :: Finding -> Text
summary f = Text.intercalate " / " [f.decision, phraseText f.phrase, maybe f.written id f.resolved, outcomeText f.outcome]

spec :: Spec
spec = do
  describe "findMentions" do
    it "reads a phrase followed by a section" do
      readMentions "Subject to section 6, where more than one person is appointed" `shouldBe`
        ["subject to: linted section 6"]
    it "keeps the subsection brackets" do
      readMentions "letters of administration may, subject to section 6(1), be granted to the guardian" `shouldBe`
        ["subject to: linted section 6(1)"]
    it "reads a relative subsection reference" do
      readMentions "Subject to subsection (8), in the case of administrations" `shouldBe`
        ["subject to: linted subsection (8)"]
    it "reads an absolute subsection reference" do
      readMentions "the directors may transact business despite subsection 114(3) within s 114(4)" `shouldBe`
        ["despite: linted subsection 114(3)"]
    it "reads the abbreviated noun, with and without a full stop" do
      readMentions "Subject to s.8 the Court may" `shouldBe` ["subject to: linted s 8"]
      readMentions "Notwithstanding reg. 12(2), a licence" `shouldBe` ["notwithstanding: linted reg 12(2)"]
    it "looks through the filler words" do
      readMentions "Notwithstanding anything contained in section 18(g), the court" `shouldBe`
        ["notwithstanding: linted section 18(g)"]
      readMentions "subject to the provisions of section 4" `shouldBe` ["subject to: linted section 4"]
    it "reads a list over and/or" do
      readMentions "subject to sections 6 and 7(1)" `shouldBe` ["subject to: linted sections 6 | sections 7(1)"]
      readMentions "Subject to section 6(1) and (2)" `shouldBe` ["subject to: linted section 6(1) | section 6(2)"]
    it "does not read a comma as a list" do
      readMentions "Subject to section 6, 4 persons may be named" `shouldBe` ["subject to: linted section 6"]
    it "sets a range aside" do
      readMentions "subject to sections 6 to 8" `shouldBe` ["subject to: range sections 6"]
    it "reads a bracketed phrase" do
      readMentions "the grant (subject to section 6) may be made" `shouldBe` ["subject to: linted section 6"]
    it "reads a provision named after a definite description" do
      readMentions "Subject to the exceptions in section 6, a person may inherit" `shouldBe` ["subject to: linted section 6"]
      readMentions "Subject to the limit in section 6, a person may inherit" `shouldBe` ["subject to: linted section 6"]
      readMentions "Subject to the consent required by section 6, a person may inherit" `shouldBe` ["subject to: linted section 6"]
      readMentions "Subject to the approval of the Court under section 6, a person may inherit" `shouldBe` ["subject to: linted section 6"]
    it "reads the hyphenated phrase" do
      readMentions "Subject-to section 6, a person may inherit" `shouldBe` ["subject to: linted section 6"]
    it "reads a Part, a Division or a Chapter as a provision" do
      readMentions "Subject to Part 3, a person may inherit" `shouldBe` ["subject to: linted part 3"]
      readMentions "notwithstanding Division 2A the Board may" `shouldBe` ["notwithstanding: linted division 2a"]
      readMentions "subject to Chapter 4, the Registrar" `shouldBe` ["subject to: linted chapter 4"]
    it "finds the provision a sentence names after a general reference" do
      readMentions "Subject to this section and to section 6, a person may inherit" `shouldBe` ["subject to: linted section 6"]
      readMentions "Subject to the provisions of this Act, and in particular section 6, a person may inherit" `shouldBe`
        ["subject to: linted section 6"]
    it "keeps a general reference general when the provision is not named after it" do
      readMentions "Notwithstanding any other provision of this Act, section 6 applies" `shouldBe` ["notwithstanding: open-class"]
      readMentions "Subject to this Act, the Minister may make rules under section 6" `shouldBe` ["subject to: open-class"]
    it "reads a subsection of a named section as that section's subdivision" do
      readMentions "Subject to subsection (2) of section 6, a person may inherit" `shouldBe` ["subject to: linted section 6(2)"]
      readMentions "Subject to sub-section (2) of section 6, a person may inherit" `shouldBe` ["subject to: linted section 6(2)"]
    it "reads 'except' only with a lead that points at a provision" do
      readMentions "except as provided in section 5, a grant" `shouldBe` ["except: linted section 5"]
      readMentions "except that the grant may be limited" `shouldBe` []
      readMentions "except where the will provides" `shouldBe` []
    it "sets aside a provision of another instrument" do
      readMentions "subject to section 15(d) of the Exchange Act" `shouldBe` ["subject to: external section 15(d)"]
      readMentions "a claimant subject to regulation 2(3) of the 2008 Regulations" `shouldBe` ["subject to: external regulation 2(3)"]
      readMentions "subject to the Land Titles Act, section 12 of that Act" `shouldBe` ["subject to: no provision"]
    it "does not set aside 'of this Act'" do
      readMentions "subject to section 6 of this Act" `shouldBe` ["subject to: linted section 6"]
    it "names an open-class target and does not judge it" do
      readMentions "Notwithstanding any other provision of this Act, the Minister" `shouldBe` ["notwithstanding: open-class"]
      readMentions "subject to the provisions of this Act" `shouldBe` ["subject to: open-class"]
    it "ignores the same words when no provision follows" do
      readMentions "the person is subject to tax in the territory it comes from" `shouldBe` ["subject to: no provision"]
      readMentions "out of reach of or not subject to the process of the court" `shouldBe` ["subject to: no provision"]
      readMentions "my employer cannot find me a suitable vacancy despite reasonable attempts" `shouldBe` ["despite: no provision"]
      readMentions "the original is subject to a trust under section 12 of the Trustee Act" `shouldBe` ["subject to: no provision"]
      readMentions "Subject to the requirement to file reports pursuant to section 13" `shouldBe` ["subject to: no provision"]
      readMentions "subject to tax imposed under section 12" `shouldBe` ["subject to: no provision"]
      readMentions "Subject to the condition that section 6 is complied with, a person may inherit" `shouldBe` ["subject to: no provision"]
      readMentions "subject to the consent of the Minister under section 6 of the Wills Act" `shouldBe` ["subject to: external section 6"]

  describe "provKeyOfName" do
    it "reads the provision a decision is named for" do
      key "s 6(1) — granted to more than 4 persons" `shouldBe` Just "s 6(1)"
      key "section 7(1) lets a court make use of the matter" `shouldBe` Just "s 7(1)"
      key "reg 76.21(2) the number of weeks" `shouldBe` Just "reg 76.21(2)"
      key "Art 13(3) the amendment of purposes" `shouldBe` Just "art 13(3)"
      key "art. 4, the board" `shouldBe` Just "art 4"
      key "s 29(8)(a) — the first limb" `shouldBe` Just "s 29(8)(a)"
      key "s 6A — a section with a letter" `shouldBe` Just "s 6a"
    it "reads nothing from a name that is not a provision" do
      key "the sentence of imprisonment the person is subject to" `shouldBe` Nothing
      key "s is a thing" `shouldBe` Nothing
      key "Schedule IV, Part 2" `shouldBe` Nothing
    it "lets a decision for a section cover its subsections, and the other way round" do
      case traverse provKeyOfName ["s 6 — the whole section", "s 6(1) — one limb", "s 6(2) — another limb", "s 7 — a different section"] of
        Just [s6, s61, s62, s7] -> do
          keyMatches s61 s6 `shouldBe` True
          keyMatches s6 s61 `shouldBe` True
          keyMatches s61 s62 `shouldBe` False
          keyMatches s61 s7 `shouldBe` False
        _ -> expectationFailure "the four names should each read as a provision"

  describe "lintModule" do
    it "flags a 'Subject to section 6' whose body calls no section 6 decision" do
      fs <- findingsOf missing
      map summary (filter (isFinding . (.outcome)) fs) `shouldBe`
        ["s 8(3) — probate may be granted / subject to / s 6 / missing-conjunct"]
      map (.sources) fs `shouldBe` [[SrcRef, SrcText]]
      map (.candidates) fs `shouldBe` [["s 6(1) — granted to more than 4 persons"]]
    it "does not flag the same prose when the body calls the section 6 decision" do
      fs <- findingsOf satisfied
      map summary fs `shouldBe` ["s 8(3) — probate may be granted / subject to / s 6 / wired (direct call)"]
    it "does not take a call to another subsection of the section for the one named" do
      fs <- findingsOf subPartMismatch
      map summary fs `shouldBe` ["s 8(3) — probate may be granted / subject to / s 6(2) / missing-conjunct"]
    it "follows a call through a helper" do
      fs <- findingsOf viaHelper
      map summary fs `shouldBe` ["s 8(3) — probate may be granted / subject to / s 6 / wired (through a helper)"]
    it "reads a phrase from the identifier name alone" do
      fs <- findingsOf nameOnly
      map (\f -> (summary f, f.sources)) fs `shouldBe`
        [("s 8(3) — probate may be granted, subject to section 6 / subject to / s 6 / missing-conjunct", [SrcName])]
    it "reads a phrase from a string in the body alone" do
      fs <- findingsOf textOnly
      map (\f -> (f.outcome, f.sources)) fs `shouldBe` [(MissingConjunct, [SrcText])]
    it "resolves a relative subsection against the decision's own section" do
      fs <- findingsOf relative
      map summary fs `shouldBe` ["s 29(7) — security / subject to / s 29(8) / missing-conjunct"]
    it "reads \"paragraph (N)\" of an article as that article's own subdivision" do
      fs <- findingsOf paragraphOfArticle
      map summary fs `shouldBe` ["Article 29(1) — the offence / subject to / art 29(2) / missing-conjunct"]
    it "does not guess a relative reference for a decision whose name carries no provision" do
      fs <- findingsOf relativeUnnamed
      map (.outcome) fs `shouldBe` [UnresolvedRelative]
    it "says so when no decision encodes the target, and does not call it a finding" do
      fs <- findingsOf targetAbsent
      map (.outcome) fs `shouldBe` [TargetNotEncoded]
    it "treats the decision's own provision as no target" do
      fs <- findingsOf selfRef
      map (.outcome) fs `shouldBe` [SelfReference]
    it "flags a 'Notwithstanding section 7' that no call joins to section 7" do
      fs <- findingsOf notwithstandingUnwired
      map summary (filter (isFinding . (.outcome)) fs) `shouldBe`
        ["s 9 — extensions may be granted / notwithstanding / s 7 / override-unwired"]
    it "accepts the defeat idiom: section 7 calling the prevailing provision" do
      fs <- findingsOf notwithstandingDefeat
      map summary fs `shouldBe` ["s 9 — extensions may be granted / notwithstanding / s 7 / wired (the provision's decision calls this one)"]
    it "accepts a third decision calling both" do
      fs <- findingsOf notwithstandingJoin
      map (.outcome) (filter ((== PhNotwithstanding) . (.phrase)) fs) `shouldBe` [Wired AtJoin]
    it "accepts a third decision that reaches the prevailing provision through a wrapper" do
      fs <- findingsOf notwithstandingWrapperJoin
      map (.outcome) (filter ((== PhNotwithstanding) . (.phrase)) fs) `shouldBe` [Wired AtJoin]
    it "does not let a wrapper join satisfy a 'subject to' the host itself leaves out" do
      fs <- findingsOf subjectToWrapperJoin
      map (.outcome) (filter ((== PhSubjectTo) . (.phrase)) fs) `shouldBe` [MissingConjunct]
    it "judges a Part named after the phrase" do
      fs <- findingsOf partMissing
      map summary fs `shouldBe` ["s 12 — a person may inherit / subject to / part 3 / missing-conjunct"]
    it "reads a phrase that a citation splits over two @ref lines" do
      fs <- findingsOf splitRef
      map (\f -> (summary f, f.sources)) fs `shouldBe`
        [("s 9 — extensions may be granted / notwithstanding / s 7 / override-unwired", [SrcRef])]
    it "reports an open-class target and does not judge it" do
      fs <- findingsOf openClass
      map (.outcome) fs `shouldBe` [OpenClassTarget]
    it "sets aside a decision whose whole body is one quotation: it computes nothing" do
      fs <- findingsOf citationRow
      map (.outcome) fs `shouldBe` [CitationOnly]
    it "still flags a chain of quotations alone, which answers TRUE" do
      fs <- findingsOf quotationsOnly
      map (.outcome) fs `shouldBe` [MissingConjunct]
    it "stays silent on the same words with no provision behind them" do
      fs <- findingsOf plainEnglish
      fs `shouldBe` []
 where
  key n = renderKey <$> provKeyOfName n

preamble :: Text
preamble = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 6(1) — granted to more than 4 persons` n MEANS"
  , "    n GREATER THAN 4"
  , ""
  ]

-- | Section 8(3) says "Subject to section 6" and does not call it.
missing :: Text
missing = preamble <> Text.unlines
  [ "@ref Probate Act s 8(3) — \"Subject to section 6, probate may be granted to one or more of the persons.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted` n MEANS"
  , "        \"Subject to section 6,\""
  , "    ... n GREATER THAN 1"
  ]

-- | A citation row: the body is the statute's sentence and nothing else.
citationRow :: Text
citationRow = preamble <> Text.unlines
  [ "GIVETH A STRING"
  , "`s 8(3) — probate may be granted` MEANS"
  , "    \"Probate is granted, subject to section 6.\""
  ]

-- | The quoted words alone, joined by @...@: they evaluate to the AND identity.
quotationsOnly :: Text
quotationsOnly = preamble <> Text.unlines
  [ "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted` MEANS"
  , "        \"Subject to section 6,\""
  , "    ... \"probate may be granted to one or more of the persons.\""
  ]

satisfied :: Text
satisfied = preamble <> Text.unlines
  [ "@ref Probate Act s 8(3) — \"Subject to section 6, probate may be granted to one or more of the persons.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted` n MEANS"
  , "        \"Subject to section 6,\""
  , "    ... NOT (`s 6(1) — granted to more than 4 persons` n)"
  , "    ... n GREATER THAN 1"
  ]

-- | "Subject to section 6(2)", and the body asks section 6(1) only.
subPartMismatch :: Text
subPartMismatch = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 6(1) — granted to more than 4 persons` n MEANS n GREATER THAN 4"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 6(2) — the grant is limited` n MEANS n EQUALS 0"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted` n MEANS"
  , "        \"Subject to section 6(2),\""
  , "    ... NOT (`s 6(1) — granted to more than 4 persons` n)"
  , "    ... n GREATER THAN 1"
  ]

viaHelper :: Text
viaHelper = preamble <> Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`within the limit` n MEANS NOT (`s 6(1) — granted to more than 4 persons` n)"
  , ""
  , "@ref Probate Act s 8(3) — \"Subject to section 6, probate may be granted.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted` n MEANS"
  , "        `within the limit` n"
  , "    AND n GREATER THAN 1"
  ]

nameOnly :: Text
nameOnly = preamble <> Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted, subject to section 6` n MEANS"
  , "    n GREATER THAN 1"
  ]

textOnly :: Text
textOnly = preamble <> Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`probate may be granted` n MEANS"
  , "        \"Subject to section 6, probate may be granted.\""
  , "    ... n GREATER THAN 1"
  ]

relative :: Text
relative = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 29(8) — the exception` n MEANS n EQUALS 0"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 29(7) — security` n MEANS"
  , "        \"Subject to subsection (8), the person shall give security.\""
  , "    ... n GREATER THAN 1"
  ]

relativeUnnamed :: Text
relativeUnnamed = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`give security` n MEANS"
  , "        \"Subject to subsection (8), the person shall give security.\""
  , "    ... n GREATER THAN 1"
  ]

-- | Jersey's Charities Law numbers an Article's subdivisions "paragraphs".
paragraphOfArticle :: Text
paragraphOfArticle = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`Article 29(2) — the exception` n MEANS n EQUALS 0"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`Article 29(1) — the offence` n MEANS"
  , "        \"Subject to paragraph (2),\""
  , "    ... n GREATER THAN 1"
  ]

targetAbsent :: Text
targetAbsent = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 8(3) — probate may be granted` n MEANS"
  , "        \"Subject to section 99,\""
  , "    ... n GREATER THAN 1"
  ]

selfRef :: Text
selfRef = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 114(4) — the provision is subject to subsection 114(4)` n MEANS"
  , "    n GREATER THAN 1"
  ]

-- | Section 9 prevails over section 7 and neither calls the other.
notwithstandingUnwired :: Text
notwithstandingUnwired = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 7 — extensions are barred` n MEANS n GREATER THAN 10"
  , ""
  , "@ref Act s 9 — \"Notwithstanding section 7, the Director may grant extensions.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS n GREATER THAN 1"
  ]

notwithstandingDefeat :: Text
notwithstandingDefeat = Text.unlines
  [ "@ref Act s 9 — \"Notwithstanding section 7, the Director may grant extensions.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS n GREATER THAN 1"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 7 — extensions are barred` n MEANS"
  , "        n GREATER THAN 10"
  , "    AND NOT (`s 9 — extensions may be granted` n)"
  ]

notwithstandingJoin :: Text
notwithstandingJoin = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 7 — extensions are barred` n MEANS n GREATER THAN 10"
  , ""
  , "@ref Act s 9 — \"Notwithstanding section 7, the Director may grant extensions.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS n GREATER THAN 1"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`extensions in the end` n MEANS"
  , "    IF `s 9 — extensions may be granted` n THEN TRUE ELSE NOT (`s 7 — extensions are barred` n)"
  ]

-- | The Jersey charity-test shape: the override sits behind a wrapper, and the
-- decision that combines the two calls the wrapper, not the override.
notwithstandingWrapperJoin :: Text
notwithstandingWrapperJoin = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 7 — extensions are barred` n MEANS n GREATER THAN 10"
  , ""
  , "@ref Act s 9 — \"Notwithstanding section 7, the Director may grant extensions.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS n GREATER THAN 1"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the s 9 override bites` n MEANS `s 9 — extensions may be granted` n"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`extensions in the end` n MEANS"
  , "    IF `the s 9 override bites` n THEN TRUE ELSE NOT (`s 7 — extensions are barred` n)"
  ]

-- | The same wrapper shape for \"subject to\": the host's own body still leaves
-- section 7 out, and a decision elsewhere combining them does not change what
-- the host says.
subjectToWrapperJoin :: Text
subjectToWrapperJoin = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 7 — extensions are barred` n MEANS n GREATER THAN 10"
  , ""
  , "@ref Act s 9 — \"Subject to section 7, the Director may grant extensions.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS n GREATER THAN 1"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the s 9 grant` n MEANS `s 9 — extensions may be granted` n"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`extensions in the end` n MEANS"
  , "    IF `the s 9 grant` n THEN TRUE ELSE NOT (`s 7 — extensions are barred` n)"
  ]

partMissing :: Text
partMissing = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`Part 3 — the limit` n MEANS n GREATER THAN 4"
  , ""
  , "@ref Act s 12 — \"Subject to Part 3, a person may inherit\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 12 — a person may inherit` n MEANS n GREATER THAN 2"
  ]

-- | A long citation wrapped over two @\@ref@ lines splits the phrase from its
-- provision.
splitRef :: Text
splitRef = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 7 — extensions are barred` n MEANS n GREATER THAN 10"
  , ""
  , "@ref Act s 9 — \"Notwithstanding"
  , "@ref section 7, the Director may grant extensions.\""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS n GREATER THAN 1"
  ]

openClass :: Text
openClass = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`s 9 — extensions may be granted` n MEANS"
  , "        \"Notwithstanding any other provision of this Act,\""
  , "    ... n GREATER THAN 1"
  ]

plainEnglish :: Text
plainEnglish = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the person is subject to tax in the territory it comes from` n MEANS"
  , "        \"unless the person is subject to the process of the court,\""
  , "    ... n GREATER THAN 1"
  ]
