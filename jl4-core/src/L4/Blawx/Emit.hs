-- | Render a 'BlawxDoc' to the s(CASP) text Blawx itself would generate.
--
-- __Byte-exactness is the contract__ (BLAWX-EXPORT-SPEC R10\/R12): the Blawx
-- editor regenerates every workspace's @scasp_encoding@ from its blocks on
-- save, so our emitted text must be the fixpoint of that regeneration —
-- including @scasp_generator.js@'s quirks, which are reproduced and never
-- repaired. Reference: generator at Blawx commit @02eded1@, cross-checked
-- byte-for-byte against @life_act.yaml@'s @sec_1_section@ (the one shipped
-- example that matches the current generator; the templates below cite
-- generator line numbers). See @p1-design\/emit-plan.md@ for the derivation.
--
-- Output is built as plain 'Text' (not a @Doc@) so spacing is exact and
-- golden-stable — the same rationale as "L4.OpenFisca.Emit".
--
-- The quirks, so nobody "fixes" them:
--
-- 1. The negative @blawx_defeated@ @#pred@ of the /attribute/ and
--    /relationship/ variants omits "it is not the case that" (generator
--    949\/1020\/1388); the /category/ variant includes it (1099).
-- 2. The "During Positive Neither" frame axiom carries a spurious,
--    self-contradictory @blawx_becomes(-p,datetime(Start))@ goal (generator
--    997, parallels 1068\/1147\/1436) — the axiom can never fire.
-- 3. The "During Negative Neither" frame axiom fails to sign-flip that same
--    goal (generator 1006, parallels 1077\/1156\/1445): it reads
--    @blawx_becomes(-p,…)@ where the sign mirror requires @blawx_becomes(p,…)@.
-- 4. The relationship variant's @#pred@ NLG does not escape @'@ in the
--    /postfix/ slot (generator 1378 escapes only the prefixes); the category
--    and attribute variants escape all slots.
--
-- __One documented deviation__: arithmetic ('renderArith') emits minimal
-- parentheses (@Tmp is 1000 + Bonus@) where the generator's
-- @math_operation@ always emits @( left op right )@ (generator 557-563).
-- This follows the ACCEPTED import exemplar (which used the bare form and
-- ran correctly); no shipped example exercises a calculation line, so
-- there is no generator-output witness either way. It means an
-- arithmetic-bearing rule is not byte-for-byte the fixpoint of generator
-- regeneration — semantics, precedence and association are identical, and
-- P3's @renderXml@ (which will make re-saves possible) is the point at
-- which the parenthesised image must be revisited.
--
-- P1 renders @renderScasp@ and @renderBlawxYaml@ only; @renderXml@ is P3 and
-- every emitted @xml_content@ is meanwhile the empty string (R12 delegated
-- sub-decision, consistent with the executed tier-2 smoke).
module L4.Blawx.Emit
  ( renderScasp
  , renderBlawxYaml
  , renderPlDump
  , renderRuleText
  , renderWorkspaceScasp
  , renderTestScasp
  , renderBlock
  , renderGoal
  , renderTerm
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (isAlphaNum, isDigit)
import Data.Ratio (denominator, numerator)

import L4.Blawx.IR

-- ---------------------------------------------------------------------------
-- Document and workspace assembly
-- ---------------------------------------------------------------------------

-- | The concatenated s(CASP) of every workspace, in document order, separated
-- by one blank line — the ruledoc-level load image. The @.pl@ sibling dump
-- prepends a provenance header and a trailing newline at the CLI; the
-- per-workspace @scasp_encoding@ stored in the @.blawx@ YAML is
-- 'renderWorkspaceScasp', never this.
renderScasp :: BlawxDoc -> Text
renderScasp doc =
  Text.intercalate "\n\n" (map renderWorkspaceScasp doc.bdWorkspaces)

-- | One workspace's @scasp_encoding@, __without__ a trailing newline (stored
-- values end at the final @.@ — emit-plan §1). Blocks chained in one stack
-- are joined with no blank line; separate stacks are separated by one blank
-- line (byte-load-bearing; evidence: @life_act.yaml@'s three declaration
-- blocks run L0–L131 with no internal blank, the rule stack begins after a
-- single blank at L132).
renderWorkspaceScasp :: BWorkspace -> Text
renderWorkspaceScasp ws = renderStacks ws.bwStacks

-- | One test's @scasp_encoding@: same stack layout as a workspace (facts and
-- constraints in their stacks, the @?- …@ query the last line of the last
-- stack — the reasoner scans for it there and chops the final @.@ blindly).
renderTestScasp :: BTest -> Text
renderTestScasp t = renderStacks t.btStacks

-- | Empty stacks contribute no bytes and are filtered rather than rendered as
-- stray blank lines (a test with no scenario facts still carries the empty
-- facts stack structurally — see 'L4.Blawx.IR.BTest').
renderStacks :: [[BBlock]] -> Text
renderStacks stacks =
  Text.intercalate "\n\n" (map renderStack (filter (not . null) stacks))
 where
  renderStack = Text.intercalate "\n" . map renderBlock

-- ---------------------------------------------------------------------------
-- The .blawx YAML stream (R1) and the sibling .pl dump
-- ---------------------------------------------------------------------------

-- | The import-shaped @.blawx@ fixture stream: one flat Django-dumpdata-style
-- YAML list — exactly one @blawx.ruledoc@ FIRST (placeholder pk and owner;
-- @\/import\/@ remaps pk, owner and each ruledoc FK), then the
-- @blawx.workspace@ rows in document order, then the @blawx.blawxtest@ rows.
-- @akoma_ntoso@\/@navtree@\/@rule_slug@ are omitted (recomputed by
-- @pre_save@); every @xml_content@ is @''@ in P1 (R12 delegated
-- sub-decision). Field order per model mirrors the ACCEPTED exemplar
-- (@p1-design\/emit-plan.md@ §6).
--
-- Hand-rolled and line-oriented — no YAML library — for golden stability:
-- encodings are @|-@ block scalars (strip chomping realises \"no trailing
-- newline inside the encodings\") indented six spaces, @rule_text@ is one
-- double-quoted @\\n@-escaped line, and placeholder pks number 1..n per
-- model.
renderBlawxYaml :: BlawxDoc -> Text
renderBlawxYaml doc =
  Text.unlines (ruledocRow <> concat wsRows <> concat testRows)
 where
  ruledocRow =
    [ "- model: blawx.ruledoc"
    , "  pk: 1"
    , "  fields:"
    , "    ruledoc_name: " <> yamlScalar doc.bdName
    , "    rule_text: " <> yamlDoubleQuoted (renderRuleText doc.bdRuleText)
    , "    scasp_encoding: ''"
    , "    tutorial: ''"
    , "    owner: 1"
    , "    published: true"
    ]
  wsRows =
    [ [ "- model: blawx.workspace"
      , "  pk: " <> Text.textShow (k :: Int)
      , "  fields:"
      , "    ruledoc: 1"
      , "    workspace_name: " <> renderSectionRef ws.bwName
      , "    xml_content: ''"
      ]
        <> yamlEncoding (renderWorkspaceScasp ws)
    | (k, ws) <- zip [1 ..] doc.bdWorkspaces
    ]
  testRows =
    [ [ "- model: blawx.blawxtest"
      , "  pk: " <> Text.textShow (k :: Int)
      , "  fields:"
      , "    ruledoc: 1"
      , "    test_name: " <> yamlScalar t.btName
      , "    xml_content: ''"
      ]
        <> yamlEncoding (renderTestScasp t)
        <> [ "    tutorial: ''"
           , "    view: ''"
           , "    fact_scenario: ''"
           ]
    | (k, t) <- zip [1 ..] doc.bdTests
    ]

-- | A @scasp_encoding@ field: a @|-@ block scalar with every line indented
-- six spaces (blank lines stay empty — YAML forbids nothing, but trailing
-- whitespace would be noise), or @''@ when the encoding is empty.
yamlEncoding :: Text -> [Text]
yamlEncoding enc
  | Text.null enc = ["    scasp_encoding: ''"]
  | otherwise =
      "    scasp_encoding: |-"
        : [ if Text.null ln then "" else "      " <> ln
          | ln <- Text.splitOn "\n" enc
          ]

-- | A plain scalar where safe, a double-quoted one otherwise. Names here are
-- module titles and test slugs; the plain set is deliberately conservative —
-- and excludes everything a YAML 1.1 loader would type as non-string: the
-- boolean\/null lexemes (@true@\/@no@\/@on@\/@null@\/…, case-insensitive)
-- and numeric-looking texts (@2020@, @1.5@, @-3@), which @yaml.safe_load@
-- would hand Django as a bool\/int\/float where a CharField expects a string.
yamlScalar :: Text -> Text
yamlScalar t
  | plainSafe = t
  | otherwise = yamlDoubleQuoted t
 where
  plainSafe = case Text.uncons t of
    Nothing -> False
    Just (c, _) ->
      (isAlphaNum c)
        && Text.all (\x -> isAlphaNum x || x `elem` (" _.()-" :: String)) t
        && not (" " `Text.isSuffixOf` t)
        && not yamlTyped
  yamlTyped = Text.toLower t `elem` yamlLexemes || numericLike
  yamlLexemes =
    [ "true", "false", "yes", "no", "on", "off", "null", "none", "~" ] :: [Text]
  numericLike =
    Text.all (\x -> isDigit x || x `elem` (".+-eE_" :: String)) t

yamlDoubleQuoted :: Text -> Text
yamlDoubleQuoted t = "\"" <> Text.concatMap esc t <> "\""
 where
  esc = \case
    '\\' -> "\\\\"
    '"'  -> "\\\""
    '\n' -> "\\n"
    c    -> Text.singleton c

-- | The CLEAN @rule_text@ (R4): title, blank line, flat numbered sections —
-- section /n/ yields AKN eId @sec_n@, hence workspace @sec_n_section@. The
-- eId prediction was verified two ways: against the container's regenerated
-- AKN in the tier-2 smoke (hand-capitalized exemplar), and by running
-- clean-law 0.0.4's @generate_akn@ over every golden's synthesized
-- @rule_text@ (each parses, and its eIds match the emitted workspace names
-- exactly — CLEAN requires the uppercase-initial title Lower now
-- guarantees). Newlines are @\\n@; no sub-provisions, no indentation.
renderRuleText :: BRuleText -> Text
renderRuleText rt =
  rt.brTitle
    <> Text.concat
         [ "\n\n" <> Text.intercalate "\n" numbered
         | let numbered =
                 [ Text.textShow s.bsNumber <> ". " <> s.bsText
                 | s <- rt.brSections
                 ]
         , not (null numbered)
         ]

-- | The sibling @.pl@ dump (R1 \"dump the pl also alongside\"): a provenance
-- header, then the ruledoc-level concatenation of every workspace's encoding
-- ('renderScasp'), with a trailing newline (it is a standalone file, not a
-- stored encoding). No test encodings and no dedup pass — it is the
-- reasoner's pre-test load image; the tier-1 harness supplies libraries,
-- dedup, test facts and the query.
-- The second header line is the R5 epistemics disclosure the ruled spec
-- (§8.5, "as proposed") requires in the emitted header.
renderPlDump :: Text -> BlawxDoc -> Text
renderPlDump source doc =
  "% generated by l4 blawx from " <> source
    <> " — raw concatenated s(CASP); tests live in the .blawx / tier-1 harness\n"
    <> "% epistemics (R5): an input that is neither asserted, denied, nor \
       \abducible yields NO MODEL (loud), never a silent false\n\n"
    <> renderScasp doc
    <> "\n"

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------

-- | One block's s(CASP) image, without a trailing newline. An
-- 'BAttributedRule' contains internal blank lines (the generator emits the
-- triple as three rules separated by blank lines inside one block).
renderBlock :: BBlock -> Text
renderBlock = \case
  BDeclareCategory d     -> declarationBlock (categoryVariant d)
  BDeclareAttribute d    -> declarationBlock (attributeVariant d)
  BDeclareRelationship d -> declarationBlock (relationshipVariant d)
  BAttributedRule r      -> ruleTriple r
  BFact sign p args      -> (if sign then "" else "-") <> atomApp p args <> "."
  BConstraint goals      ->
    -- multi-goal join is ",\n" per the generator's unattributed_constraint
    -- (scasp_generator.js:346-359, same join as attributed_rule); Lower
    -- currently emits single-goal constraints only, so the join is latent
    "false :- " <> Text.intercalate ",\n" (map renderGoal goals) <> "."
  BAbducible p args      -> "#abducible " <> atomApp p args <> "."
  BQuery p args          -> "?- " <> atomApp p args <> "."

-- ---------------------------------------------------------------------------
-- Declaration blocks: the 44-line templates
-- ---------------------------------------------------------------------------

-- | What the four declaration variants share, extracted from their block
-- fields: 3 header lines + the pieces the 21 @#pred@ lines and 20 frame
-- axioms are assembled from. 3 + 21 + 20 = 44 lines exactly (R10).
data DeclVariant = MkDeclVariant
  { dvHeader :: ![Text]  -- ^ ontology fact, @*_nlg@ fact, @:- dynamic@ (in that order)
  , dvName   :: !Text    -- ^ the predicate atom
  , dvArgs   :: !Text    -- ^ @\"X\"@ \/ @\"X,Y\"@ \/ @\"Y,X\"@ \/ @\"A,B,…\"@
  , dvNlg    :: !Text    -- ^ the trimmed, escaped NLG sentence with @\@(V)@ slots
  , dvNegDefeatedFull :: !Bool
    -- ^ 'True' (category only): the negative @blawx_defeated@ @#pred@ keeps
    -- "it is not the case that" — quirk 1 in the module header
  }

-- | @new_category_declaration@ (generator 1082–1159; life_act L0–L43).
categoryVariant :: BCategoryDecl -> DeclVariant
categoryVariant d =
  MkDeclVariant
    { dvHeader =
        [ "blawx_category(" <> n <> ")."
        , "blawx_category_nlg(" <> n <> ",\"" <> d.bcPrefix <> "\",\"" <> d.bcPostfix <> "\")."
        , ":- dynamic " <> n <> "/1."
        ]
    , dvName = n
    , dvArgs = "X"
    , dvNlg  = Text.strip (escQuote d.bcPrefix <> " @(X) " <> escQuote d.bcPostfix)
    , dvNegDefeatedFull = True
    }
 where
  n = bNameText d.bcName

-- | @new_attribute_declaration@, both arms (generator 919–1078; life_act
-- L44–L87 boolean, L88–L131 value).
attributeVariant :: BAttributeDecl -> DeclVariant
attributeVariant d = case d.baType of
  BVBoolean ->
    MkDeclVariant
      { dvHeader =
          [ "blawx_attribute(" <> cat <> "," <> n <> ",boolean)."
          , "blawx_attribute_nlg(" <> n <> ",not_applicable,\"" <> d.baPrefix
              <> "\",not_applicable,\"" <> d.baPostfix <> "\")."
          , ":- dynamic " <> n <> "/1."
          ]
      , dvName = n
      , dvArgs = "X"
      , dvNlg  = Text.strip (escQuote d.baPrefix <> " @(X) " <> escQuote d.baPostfix)
      , dvNegDefeatedFull = False
      }
  ty ->
    MkDeclVariant
      { dvHeader =
          [ "blawx_attribute(" <> cat <> "," <> n <> "," <> renderValueType ty <> ")."
          , "blawx_attribute_nlg(" <> n <> "," <> orderAtom <> ",\"" <> d.baPrefix
              <> "\",\"" <> d.baInfix <> "\",\"" <> d.baPostfix <> "\")."
          , ":- dynamic " <> n <> "/2."
          ]
      , dvName = n
      , dvArgs = case d.baOrder of BOrderOV -> "X,Y"; BOrderVO -> "Y,X"
        -- NLG placeholders stay @(X) then @(Y) regardless of order; only the
        -- argument positions swap (generator 934–941).
      , dvNlg  = Text.strip
          (escQuote d.baPrefix <> " @(X) " <> escQuote d.baInfix
             <> " @(Y) " <> escQuote d.baPostfix)
      , dvNegDefeatedFull = False
      }
 where
  n = bNameText d.baName
  cat = bNameText d.baCategory
  orderAtom = case d.baOrder of BOrderOV -> "ov"; BOrderVO -> "vo"

-- | @relationship_declaration@ (generator 1339–1448). Argument variables are
-- @A@–@J@ in order (1371); note quirk 4: the postfix NLG slot is NOT escaped.
relationshipVariant :: BRelationshipDecl -> DeclVariant
relationshipVariant d =
  MkDeclVariant
    { dvHeader =
        [ "blawx_relationship(" <> n <> ","
            <> Text.intercalate "," (map renderValueType d.brTypes) <> ")."
        , "blawx_relationship_nlg(" <> n <> ","
            <> Text.concat [ "\"" <> p <> "\"," | p <- d.brPrefixes ]
            <> "\"" <> d.brPostfix <> "\")."
        , ":- dynamic " <> n <> "/" <> Text.textShow arity <> "."
        ]
    , dvName = n
    , dvArgs = Text.intercalate "," vars
    , dvNlg  = Text.strip
        (Text.concat [ escQuote p <> " @(" <> v <> ") " | (p, v) <- zip d.brPrefixes vars ]
           <> d.brPostfix)
    , dvNegDefeatedFull = False
    }
 where
  n = bNameText d.brName
  arity = length d.brTypes
  vars = take arity ["A","B","C","D","E","F","G","H","I","J"]

-- | Assemble the 44 lines of a declaration block.
declarationBlock :: DeclVariant -> Text
declarationBlock v =
  Text.intercalate "\n" (v.dvHeader <> predLines v <> frameAxioms v)

-- | The 21 @#pred@ NLG annotations, in generator order.
predLines :: DeclVariant -> [Text]
predLines v =
  [ "#pred " <> goal <> " :: '" <> nlg <> "'."
  , "#pred holds(user," <> flat <> ") :: 'it is provided as a fact that " <> nlg <> "'."
  , "#pred holds(user,-" <> flat <> ") :: 'it is provided as a fact that it is not the case that " <> nlg <> "'."
  , "#pred holds(Z," <> flat <> ") :: 'the conclusion in @(Z) that " <> nlg <> " holds'."
  , "#pred holds(Z,-" <> flat <> ") :: 'the conclusion in @(Z) that it is not the case that " <> nlg <> " holds'."
  , "#pred according_to(Z," <> flat <> ") :: 'according to @(Z), " <> nlg <> "'."
  , "#pred according_to(Z,-" <> flat <> ") :: 'according to @(Z), it is not the case that " <> nlg <> "'."
  , "#pred blawx_defeated(Z," <> flat <> ") :: 'the conclusion in @(Z) that " <> nlg <> " is defeated'."
  , "#pred blawx_defeated(Z,-" <> flat <> ") :: 'the conclusion in @(Z) that " <> negDefeated <> " is defeated'."
  , "#pred blawx_initially(" <> goal <> ") :: 'that " <> nlg <> " holds initially'."
  , "#pred blawx_initially(-" <> goal <> ") :: 'that it is not the case that " <> nlg <> " holds initially'."
  , "#pred blawx_ultimately(" <> goal <> ") :: 'that " <> nlg <> " holds ultimately'."
  , "#pred blawx_ultimately(-" <> goal <> ") :: 'that it is not the case that " <> nlg <> " holds ultimately'."
  , "#pred blawx_as_of(" <> goal <> ",T) :: 'that " <> nlg <> " holds at @(T)'."
  , "#pred blawx_as_of(-" <> goal <> ",T) :: 'that it is not the case that " <> nlg <> " holds at @(T)'."
  , "#pred blawx_during(T1," <> goal <> ",T2) :: 'that " <> nlg <> " held between @(T1) and @(T2)'."
  , "#pred blawx_during(T1,-" <> goal <> ",T2) :: 'that it is not the case that " <> nlg <> " held between @(T1) and @(T2)'."
  , "#pred blawx_becomes(" <> goal <> ",T) :: 'that " <> nlg <> " became true at @(T)'."
  , "#pred blawx_becomes(-" <> goal <> ",T) :: 'that it is not the case that " <> nlg <> " became true at @(T)'."
  , "#pred blawx_not_interrupted(Start," <> goal <> ",End) :: '" <> nlg <> " remained the case between @(Start) and @(End)'."
  , "#pred blawx_not_interrupted(Start,-" <> goal <> ",End) :: 'it is not the case that " <> nlg <> " remained the case between @(Start) and @(End)'."
  ]
 where
  goal = v.dvName <> "(" <> v.dvArgs <> ")"
  flat = v.dvName <> "," <> v.dvArgs
  nlg  = v.dvNlg
  negDefeated  -- quirk 1
    | v.dvNegDefeatedFull = "it is not the case that " <> nlg
    | otherwise           = nlg

-- | The 20 temporal frame axioms, in generator order, with the generator's
-- exact (and deliberately inconsistent) micro-spacing. @p@ = the positive
-- goal, @n@ = its @-@-prefixed form. Quirks 2 and 3 (module header) live in
-- the last of the "During Positive" and "During Negative" quartets.
frameAxioms :: DeclVariant -> [Text]
frameAxioms v =
  [ -- not interrupted: between / before-end / before-eot / ever (8)
    "blawx_not_interrupted(datetime(Start)," <> p <> ",datetime(End)) :- Start \\= bot, End \\= eot, findall(Time,blawx_becomes(" <> n <> ",datetime(Time)),Times),blawx_list_not_between(Times,Start,End)."
  , "blawx_not_interrupted(datetime(Start)," <> n <> ",datetime(End)) :- Start \\= bot, End \\= eot, findall(Time,blawx_becomes(" <> p <> ",datetime(Time)),Times),blawx_list_not_between(Times,Start,End)."
  , "blawx_not_interrupted(datetime(bot)," <> p <> ",datetime(End)) :- End \\= eot, findall(Time,blawx_becomes(" <> n <> ",datetime(Time)),Times),blawx_list_not_before(Times,End)."
  , "blawx_not_interrupted(datetime(bot)," <> n <> ",datetime(End)) :- End \\= eot, findall(Time,blawx_becomes(" <> p <> ",datetime(Time)),Times),blawx_list_not_before(Times,End)."
  , "blawx_not_interrupted(datetime(Start)," <> p <> ",datetime(eot)) :- Start \\= bot, findall(Time,blawx_becomes(" <> n <> ",datetime(Time)),Times),blawx_list_not_after(Times,Start)."
  , "blawx_not_interrupted(datetime(Start)," <> n <> ",datetime(eot)) :- Start \\= bot, findall(Time,blawx_becomes(" <> p <> ",datetime(Time)),Times),blawx_list_not_after(Times,Start)."
  , "blawx_not_interrupted(datetime(bot)," <> p <> ",datetime(eot)) :- blawx_initially(" <> p <> "), blawx_ultimately(" <> p <> "), findall(Time,blawx_becomes(" <> n <> ",datetime(Time)),[])."
  , "blawx_not_interrupted(datetime(bot)," <> n <> ",datetime(eot)) :- blawx_initially(" <> n <> "), blawx_ultimately(" <> n <> "), findall(Time,blawx_becomes(" <> p <> ",datetime(Time)),[])."
    -- as of (4); note the comma-tight @Time,blawx_not_interrupted@
  , "blawx_as_of(" <> p <> ",datetime(Time)) :- blawx_initially(" <> p <> "), BeforeT #< Time,blawx_not_interrupted(datetime(bot)," <> p <> ",datetime(BeforeT))."
  , "blawx_as_of(" <> p <> ",datetime(Time)) :- blawx_becomes(" <> p <> ",datetime(BeforeT)),BeforeT #< Time,blawx_not_interrupted(datetime(BeforeT)," <> p <> ",datetime(Time))."
  , "blawx_as_of(" <> n <> ",datetime(Time)) :- blawx_initially(" <> n <> "), BeforeT #< Time,blawx_not_interrupted(datetime(bot)," <> n <> ",datetime(BeforeT))."
  , "blawx_as_of(" <> n <> ",datetime(Time)) :- blawx_becomes(" <> n <> ",datetime(BeforeT)),BeforeT #< Time,blawx_not_interrupted(datetime(BeforeT)," <> n <> ",datetime(Time))."
    -- during positive: both / end / start / neither (4)
  , "blawx_during(datetime(Start)," <> p <> ",datetime(End)) :- blawx_becomes(" <> p <> ",datetime(Start)), blawx_becomes(" <> n <> ",datetime(End)), Start #< End, blawx_not_interrupted(datetime(Start)," <> p <> ",datetime(End))."
  , "blawx_during(datetime(bot)," <> p <> ",datetime(End)) :- blawx_initially(" <> p <> "), blawx_becomes(" <> n <> ",datetime(End)), blawx_not_interrupted(datetime(bot)," <> p <> ",datetime(End))."
  , "blawx_during(datetime(Start)," <> p <> ",datetime(eot)) :- blawx_ultimately(" <> p <> "), blawx_becomes(" <> n <> ",datetime(Start)), blawx_not_interrupted(datetime(Start)," <> p <> ",datetime(eot))."
    -- quirk 2: the spurious, self-contradictory becomes-goal (generator 997)
  , "blawx_during(datetime(bot)," <> p <> ",datetime(eot)) :- blawx_initially(" <> p <> "), blawx_ultimately(" <> p <> "), blawx_becomes(" <> n <> ",datetime(Start)), blawx_not_interrupted(datetime(bot)," <> p <> ",datetime(eot))."
    -- during negative: both / end / start / neither (4)
  , "blawx_during(datetime(Start)," <> n <> ",datetime(End)) :- blawx_becomes(" <> n <> ",datetime(Start)), blawx_becomes(" <> p <> ",datetime(End)), Start #< End, blawx_not_interrupted(datetime(Start)," <> n <> ",datetime(End))."
  , "blawx_during(datetime(bot)," <> n <> ",datetime(End)) :- blawx_initially(" <> n <> "), blawx_becomes(" <> p <> ",datetime(End)), blawx_not_interrupted(datetime(bot)," <> n <> ",datetime(End))."
  , "blawx_during(datetime(Start)," <> n <> ",datetime(eot)) :- blawx_ultimately(" <> n <> "), blawx_becomes(" <> p <> ",datetime(Start)), blawx_not_interrupted(datetime(Start)," <> n <> ",datetime(eot))."
    -- quirk 3: NOT sign-flipped — stays -p where the mirror needs p (generator 1006)
  , "blawx_during(datetime(bot)," <> n <> ",datetime(eot)) :- blawx_initially(" <> n <> "), blawx_ultimately(" <> n <> "), blawx_becomes(" <> n <> ",datetime(Start)), blawx_not_interrupted(datetime(bot)," <> n <> ",datetime(eot))."
  ]
 where
  p = v.dvName <> "(" <> v.dvArgs <> ")"
  n = "-" <> p

renderValueType :: BValueType -> Text
renderValueType = \case
  BVBoolean    -> "boolean"
  BVNumber     -> "number"
  BVDate       -> "date"
  BVTime       -> "time"
  BVDatetime   -> "datetime"
  BVDuration   -> "duration"
  BVList       -> "list"
  BVCategory n -> bNameText n

-- ---------------------------------------------------------------------------
-- The attributed-rule triple
-- ---------------------------------------------------------------------------

-- | The defeasibility triple (generator 1168–1241): @according_to@ rule,
-- @holds@ bridge, bare-predicate rule — with the flattened conclusion
-- (@deconstruct_term@), the exact @% BLAWX CHECK DUPLICATES@ dedup markers,
-- one blank line between the three rules, and the two-space indent on the
-- third rule (Blockly @statementToCode@ leaking through; byte-significant).
ruleTriple :: BRule -> Text
ruleTriple r =
  firstRule <> "\n\n" <> secondRule <> "\n\n" <> thirdRule
 where
  sec  = renderSectionRef r.brSection
  c    = r.brConclusion
  sign = if c.bcSign then "" else "-"
  -- deconstruct_term: functor (sign-prefixed), then its args, comma-joined,
  -- each trimmed
  flat = Text.intercalate "," (sign <> bNameText c.bcPred : map renderTerm c.bcArgs)
  unflat = sign <> atomApp c.bcPred c.bcArgs
  -- conditions joined ",\n", first on the head line; an empty condition list
  -- reproduces the generator's own degenerate ") :- ." (Lower never emits one:
  -- the category guard is always first)
  firstRule =
    "according_to(" <> sec <> "," <> flat <> ") :- "
      <> Text.intercalate ",\n" (map renderGoal r.brConditions) <> "."
  secondRule =
    "% BLAWX CHECK DUPLICATES\n"
      <> "holds(" <> sec <> "," <> flat <> ") :- according_to(" <> sec <> "," <> flat <> ")"
      <> (if r.brDefeasible
            then ", not blawx_defeated(" <> sec <> "," <> flat <> ")"
            else "")
      <> "."
  thirdRule =
    "% BLAWX CHECK DUPLICATES\n"
      <> "  " <> unflat <> " :- holds(" <> sec <> "," <> flat <> ")."

renderSectionRef :: BSectionRef -> Text
renderSectionRef = \case
  BRoot  -> "root_section"
  BSec i -> "sec_" <> Text.textShow i <> "_section"

-- ---------------------------------------------------------------------------
-- Goals, terms, arithmetic
-- ---------------------------------------------------------------------------

-- | One condition-position goal (emit-plan §4). The @findall@ three-space gap
-- after the first @ , @ is the Blockly statement indent leaking through
-- (generator 882) and is byte-significant.
renderGoal :: BGoal -> Text
renderGoal = \case
  BGCall True  pr args -> atomApp pr args
  BGCall False pr args -> "-" <> atomApp pr args
  BGNaf pr args        -> "not " <> atomApp pr args
  BGCompare op x y ->
    "blawx_comparison(" <> renderTerm x <> "," <> cmpAtom op <> "," <> renderTerm y <> ")"
  BGUnify x y -> renderTerm x <> " = " <> renderTerm y
  BGDiseq x y -> "blawx_diseq(" <> renderTerm x <> "," <> renderTerm y <> ")"
  BGIs (MkBVar out) e -> out <> " is " <> renderArith 0 e
  BGFindall (MkBVar tmpl) body (MkBVar out) ->
    -- v1 bodies are single-goal by construction (Lower factors multi-goal
    -- bodies through an auxiliary predicate); the "," join below is for
    -- totality, not fidelity
    "findall(" <> tmpl <> " ,   "
      <> Text.intercalate "," (map renderGoal body)
      <> " , " <> out <> ")"
  BGAggregate fn (MkBVar list) (MkBVar out) ->
    aggAtom fn <> "_blawx_list(" <> list <> " , " <> out <> ")"

cmpAtom :: BCmpOp -> Text
cmpAtom = \case
  BEq  -> "eq"
  BNeq -> "neq"
  BGt  -> "gt"
  BGte -> "gte"
  BLt  -> "lt"
  BLte -> "lte"

aggAtom :: BAggFn -> Text
aggAtom = \case
  BCount   -> "count"
  BSum     -> "sum"
  BAverage -> "average"
  BMin     -> "min"
  BMax     -> "max"

renderTerm :: BTerm -> Text
renderTerm = \case
  BTVar (MkBVar v) -> v
  BTNum q          -> renderRational q
  BTAtom n         -> bNameText n
  BTNil            -> "[]"
  BTCons h t       -> "[" <> renderTerm h <> " | " <> renderTerm t <> "]"

-- | An integral 'Rational' renders as its integer text. A non-integral one
-- renders @num\/den@ — reachable only if Lower's R7 gate is lifted (the
-- measurement is re-run as part of P1; until then Lower rejects non-integral
-- literals with a named diagnostic, so this arm is totality, not policy).
renderRational :: Rational -> Text
renderRational q
  | denominator q == 1 = Text.textShow (numerator q)
  | otherwise          = Text.textShow (numerator q) <> "/" <> Text.textShow (denominator q)

-- | Arithmetic with the calculation block's @ + @\/@ - @\/@ * @\/@ \/ @
-- spacing, minimal parentheses, never reassociated. The 'Int' is the
-- enclosing precedence context (0 = none).
renderArith :: Int -> BArith -> Text
renderArith ctx = \case
  BANum q -> renderRational q
  BAVar (MkBVar v) -> v
  BANeg e -> "-(" <> renderArith 0 e <> ")"
  BABin op l r ->
    let prec = opPrec op
        rendered =
          renderArith prec l <> " " <> opText op <> " " <> renderArith (prec + 1) r
    in  if prec < ctx then "(" <> rendered <> ")" else rendered
 where
  opPrec = \case
    BAdd -> 1
    BSub -> 1
    BMul -> 2
    BDiv -> 2
  opText = \case
    BAdd -> "+"
    BSub -> "-"
    BMul -> "*"
    BDiv -> "/"

-- ---------------------------------------------------------------------------
-- Shared
-- ---------------------------------------------------------------------------

-- | @p(t1,…,tn)@, comma-tight; a zero-argument predicate is the bare atom.
atomApp :: BName -> [BTerm] -> Text
atomApp p = \case
  []   -> bNameText p
  args -> bNameText p <> "(" <> Text.intercalate "," (map renderTerm args) <> ")"

-- | @'@ → @\'@, applied inside @#pred@ NLG strings only (the @*_nlg@ facts
-- carry the raw slot text).
escQuote :: Text -> Text
escQuote = Text.replace "'" "\\'"
