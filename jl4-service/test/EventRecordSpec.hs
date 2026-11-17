{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | Card O4 (ruled 2026-10-11), option B, after its adversarial review of
-- 2026-11-18: a field an event's party or action record leaves out, where the
-- field has a TYPICALLY, takes its default under soft and is listed in
-- @presumed@ by the path the request wrote it at; under hard it is refused.
--
-- One describe per finding of the review (F1-F4, F7), the robustness cases it
-- asked for, condition 2 of the ruling, and the property the listing has to
-- meet over generated record shapes: the soft answer with a field left out is
-- the soft answer with the field written as its default, and @presumed@ lists
-- exactly the fields left out, each by its path.
module EventRecordSpec (spec) where

import Test.Hspec

import Backend.Api (FnLiteral, ResponseWithReason (..), prettyEvaluatorError)
import IntegrationSpec (evalFunction, withServiceFromSources)
import Types (SimpleResponse (..))

import Control.Monad (forM_, unless)
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import Data.Aeson.Types (Pair)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.String.Interpolate (i)
import Data.Text (Text)
import qualified Data.Text as Text
import Network.HTTP.Client (Manager, Response, responseBody, responseStatus)
import Network.HTTP.Types.Status (statusCode)

-- | What a request was answered: its value and its @presumed@, or the refusal.
type Answer = Either Text (Maybe FnLiteral, [Text])

answerOf :: Response LBS.ByteString -> Answer
answerOf resp = case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
  Just (SimpleResponse r) | statusCode (responseStatus resp) == 200 -> Right (Map.lookup "value" r.fnResult, r.presumed)
  Just (SimpleError e) -> Left (prettyEvaluatorError e)
  _ -> Left (Text.pack (show (responseBody resp)))

-- | Ask a DEONTIC function, from time 0, with the given events.
ask :: String -> Manager -> Text -> Text -> Text -> [Pair] -> [Aeson.Value] -> IO Answer
ask baseUrl mgr deployId fn presumption arguments events =
  answerOf <$> evalFunction baseUrl mgr deployId fn (Aeson.object $
    [ "arguments" .= Aeson.object arguments
    , "startTime" .= (0 :: Int)
    , "events" .= events
    ] <> [ "presumption" .= presumption | presumption /= "soft" ])

event :: Aeson.Value -> Aeson.Value -> Int -> Aeson.Value
event party action at = Aeson.object ["party" .= party, "action" .= action, "at" .= at]

-- | The request was refused, and the refusal names the text.
refusedNaming :: Text -> Answer -> Bool
refusedNaming needle = either (Text.isInfixOf needle) (const False)

str :: Text -> Aeson.Value
str = Aeson.String

num :: Int -> Aeson.Value
num = Aeson.toJSON

obj :: [(Text, Aeson.Value)] -> Aeson.Value
obj kvs = Aeson.object [ Aeson.Key.fromText k .= v | (k, v) <- kvs ]

spec :: Spec
spec = describe "an event's record under option B, after its review (card O4)" do
  let seatbelt = str "wear seatbelt"
      seatFn = "seatbelt requirement"

  -- F1 (blocker): the wrapper wrote a record nested in an event's record inline,
  -- as a field's value, so a field of the outer record written after it joined
  -- the nested one: `home IS Address WITH zip IS 5, note IS 3` gives home a note
  -- of 3 and leaves the party's own note to its default.
  describe "F1: a record nested in an event's record never takes a field written after it" do
    let party extra = obj ([("aname", str "Alice")] <> extra)
        address fs = obj [("Address", obj fs)]
    it "the nested record leaves out a field that the outer record writes after it" do
      withServiceFromSources "o4r-steal" [("event.l4", stealJL4)] \baseUrl mgr -> do
        let driver = ["driver" .= party [("home", obj [("zip", num 5), ("note", num 9)]), ("note", num 3)]]
            gap = party [("home", address [("zip", num 5)]), ("note", num 3)]
            written = party [("home", address [("zip", num 5), ("note", num 9)]), ("note", num 3)]
            go p evs = ask baseUrl mgr "o4r-steal" seatFn p driver evs
        none <- go "soft" []
        viaWritten <- go "soft" [event written seatbelt 0]
        viaGap <- go "soft" [event gap seatbelt 0]
        -- the written event is taken (a request A answered, and B refused as a
        -- defect in the service) ...
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        -- ... and the one that leaves the nested note out answers the same
        fmap fst viaGap `shouldBe` fmap fst viaWritten
        fmap snd viaGap `shouldBe` Right ["events[0].party.home.Address.note"]
        hard <- go "hard" [event gap seatbelt 0]
        hard `shouldSatisfy` refusedNaming "Missing required field 'events[0].party.home.Address.note'"
        hardWritten <- go "hard" [event written seatbelt 0]
        hardWritten `shouldBe` viaWritten
    it "the same with the outer field sorting before the nested record" do
      withServiceFromSources "o4r-steal2" [("event.l4", steal2JL4)] \baseUrl mgr -> do
        let driver = ["driver" .= party [("home", obj [("zip", num 5), ("anote", num 9)]), ("anote", num 3)]]
            gap = party [("home", address [("zip", num 5)]), ("anote", num 3)]
            written = party [("home", address [("zip", num 5), ("anote", num 9)]), ("anote", num 3)]
            go evs = ask baseUrl mgr "o4r-steal2" seatFn "soft" driver evs
        none <- go []
        viaWritten <- go [event written seatbelt 0]
        viaGap <- go [event gap seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.home.Address.anote"])) viaWritten
    it "a nested record with every field written, and one leaving out its default, are both taken" do
      withServiceFromSources "o4r-steal3" [("event.l4", steal3JL4)] \baseUrl mgr -> do
        let driver = ["driver" .= party [("home", obj [("zip", num 5), ("floor", num 1), ("note", num 4)]), ("note", num 3)]]
            written = party [("home", address [("zip", num 5), ("floor", num 1), ("note", num 4)]), ("note", num 3)]
            gap = party [("home", address [("zip", num 5), ("note", num 4)]), ("note", num 3)]
            go p evs = ask baseUrl mgr "o4r-steal3" seatFn p driver evs
        none <- go "soft" []
        viaWritten <- go "soft" [event written seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        hardWritten <- go "hard" [event written seatbelt 0]
        hardWritten `shouldBe` viaWritten
        viaGap <- go "soft" [event gap seatbelt 0]
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.home.Address.floor"])) viaWritten

  -- F2 (major): the normal form of a breach forced the party and action of the
  -- event that revealed it, which only a missed deadline prints (eventParty,
  -- eventAction). An explicit breach (LEST BREACH) does not print that event,
  -- so a default in it did not shape the answer and is not listed.
  describe "F2: a default is listed only where the answer carries the event" do
    let bob = obj [("name", str "Bob")]
        walk extra = obj ([("verb", str "walk")] <> extra)
        alice = ["driver" .= obj [("name", str "Alice")]]
    it "an explicit breach revealed by a late event lists nothing of that event (an action record)" do
      withServiceFromSources "o4r-act" [("event.l4", actJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-act" "drive rule" "soft" alice evs
        viaGap <- go [event bob (walk []) 5]
        viaWeird <- go [event bob (walk [("mode", str "weird")]) 5]
        fmap snd viaWeird `shouldBe` Right []
        viaGap `shouldBe` viaWeird
    it "a missed deadline prints the event that revealed it, so the default it read is listed (an action record)" do
      withServiceFromSources "o4r-act-missed" [("event.l4", actMissedJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-act-missed" "drive rule" "soft" alice evs
        viaGap <- go [event bob (walk []) 5]
        viaPlain <- go [event bob (walk [("mode", str "plain")]) 5]
        viaWeird <- go [event bob (walk [("mode", str "weird")]) 5]
        fmap snd viaPlain `shouldBe` Right []
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].action.mode"])) viaPlain
        -- the answer carries the field: written otherwise, it reads otherwise
        fmap fst viaWeird `shouldNotBe` fmap fst viaPlain
    it "the same for a party record: an explicit breach lists nothing, a missed deadline lists the field" do
      let driver = ["driver" .= obj [("name", str "Alice"), ("licence", str "full")]]
          drive = str "drive"
      withServiceFromSources "o4r-seat-lest" [("event.l4", seatLestJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-seat-lest" seatFn "soft" driver evs
        viaGap <- go [event bob drive 5]
        viaLearner <- go [event (obj [("name", str "Bob"), ("licence", str "learner")]) drive 5]
        fmap snd viaLearner `shouldBe` Right []
        viaGap `shouldBe` viaLearner
      withServiceFromSources "o4r-seat-missed" [("event.l4", seatJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-seat-missed" seatFn "soft" driver evs
        viaGap <- go [event bob drive 5]
        viaFull <- go [event (obj [("name", str "Bob"), ("licence", str "full")]) drive 5]
        viaLearner <- go [event (obj [("name", str "Bob"), ("licence", str "learner")]) drive 5]
        fmap snd viaFull `shouldBe` Right []
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.licence"])) viaFull
        fmap fst viaLearner `shouldNotBe` fmap fst viaFull

  -- F3 (major): hard checked only a record's own TYPICALLY fields, so a default
  -- in a ONE OF constructor's fields, or in the inputs of a rule used where a
  -- constructor is expected, was taken under hard.
  describe "F3: hard refuses a default whatever builds the record" do
    it "a defaulted field of a ONE OF constructor (an enum payload)" do
      withServiceFromSources "o4r-payload" [("event.l4", payloadJL4)] \baseUrl mgr -> do
        let status fs = obj [("active", obj fs)]
            party fs = obj [("name", str "Alice"), ("status", status fs)]
            unused = ["unused" .= (0 :: Int)]
            go p evs = ask baseUrl mgr "o4r-payload" seatFn p unused evs
        none <- go "soft" []
        viaWritten <- go "soft" [event (party [("level", num 3), ("since", num 2020)]) seatbelt 0]
        viaGap <- go "soft" [event (party [("level", num 3)]) seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.status.active.since"])) viaWritten
        hard <- go "hard" [event (party [("level", num 3)]) seatbelt 0]
        hard `shouldSatisfy` refusedNaming "Missing required field 'events[0].party.status.active.since'"
        hardWritten <- go "hard" [event (party [("level", num 3), ("since", num 2020)]) seatbelt 0]
        hardWritten `shouldBe` viaWritten
    it "a rule used where a constructor is expected: soft lists its input's default, hard refuses it" do
      withServiceFromSources "o4r-fnkey" [("event.l4", fnkeyJL4)] \baseUrl mgr -> do
        let party fs = obj [("name", str "Alice"), ("zhome", obj [("mkAddr", obj fs)])]
            driver = ["driver" .= obj [("name", str "Alice"), ("zhome", obj [("zip", num 5), ("floor", num 1)])]]
            go p evs = ask baseUrl mgr "o4r-fnkey" seatFn p driver evs
        none <- go "soft" []
        viaWritten <- go "soft" [event (party [("zip", num 5), ("floor", num 1)]) seatbelt 0]
        viaGap <- go "soft" [event (party [("zip", num 5)]) seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.zhome.mkAddr.floor"])) viaWritten
        hard <- go "hard" [event (party [("zip", num 5)]) seatbelt 0]
        hard `shouldSatisfy` refusedNaming "events[0].party.zhome.mkAddr"

  -- F4 (major): events that wrote the same record shared one definition and so
  -- one default, named by the first event that wrote it, even when only a later
  -- one was read.
  describe "F4: each event has its own record, so the path names the event that was read" do
    let action = obj [("verb", str "drive")]
        alice = ["driver" .= obj [("name", str "Alice")]]
        who nm = obj [("name", str nm)]
    it "two events write one action; Bob's is not read, Alice's is" do
      withServiceFromSources "o4r-shared" [("event.l4", actJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-shared" "drive rule" "soft" alice evs
        bobAlone <- go [event (who "Bob") action 0]
        fmap snd bobAlone `shouldBe` Right []
        both <- go [event (who "Bob") action 0, event (who "Alice") action 0]
        fmap snd both `shouldBe` Right ["events[1].action.mode"]
        -- writing the field in Bob's event does not move the listing
        bobWrites <- go [event (who "Bob") (obj [("verb", str "drive"), ("mode", str "plain")]) 0, event (who "Alice") action 0]
        fmap snd bobWrites `shouldBe` Right ["events[1].action.mode"]
        fmap fst bobWrites `shouldBe` fmap fst both

  -- F7: the machinery compares an event's party before its action, so a party
  -- default was listed for an event skipped because its action did not match.
  -- The reading that lists less is taken (instruction of 2026-11-18, until the
  -- maintainer rules): such an event lists nothing of its party. A default that
  -- a mismatch rests on is still listed.
  describe "F7: an event skipped because its action does not match lists nothing of its party" do
    let driverFull = ["driver" .= obj [("name", str "Alice"), ("licence", str "full")]]
        aliceGap = obj [("name", str "Alice")]
        aliceFull = obj [("name", str "Alice"), ("licence", str "full")]
        drive = str "drive"
    it "a party read in full, then an action that does not match" do
      withServiceFromSources "o4r-skip" [("event.l4", seatJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-skip" seatFn "soft" driverFull evs
        viaGap <- go [event aliceGap drive 0]
        viaWritten <- go [event aliceFull drive 0]
        fmap snd viaWritten `shouldBe` Right []
        viaGap `shouldBe` viaWritten
        thenTaken <- go [event aliceGap drive 0, event aliceFull seatbelt 0]
        fmap snd thenTaken `shouldBe` Right []
    it "still lists a party default that the mismatch rests on" do
      withServiceFromSources "o4r-skip-party" [("event.l4", seatJL4)] \baseUrl mgr -> do
        let learner = ["driver" .= obj [("name", str "Alice"), ("licence", str "learner")]]
        viaGap <- ask baseUrl mgr "o4r-skip-party" seatFn "soft" learner [event aliceGap seatbelt 0]
        fmap snd viaGap `shouldBe` Right ["events[0].party.licence"]
    it "still lists an action default that the mismatch rests on" do
      withServiceFromSources "o4r-skip-action" [("event.l4", actFastJL4)] \baseUrl mgr -> do
        let go evs = ask baseUrl mgr "o4r-skip-action" "drive rule" "soft" ["driver" .= aliceGap] evs
            act fs = obj ([("verb", str "drive")] <> fs)
        viaGap <- go [event aliceGap (act []) 0]
        viaPlain <- go [event aliceGap (act [("mode", str "plain")]) 0]
        fmap snd viaPlain `shouldBe` Right []
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].action.mode"])) viaPlain
        -- written as the act owed, the event is taken: the default decided the mismatch
        viaFast <- go [event aliceGap (act [("mode", str "fast")]) 0]
        fmap snd viaFast `shouldBe` Right []
        fmap fst viaFast `shouldNotBe` fmap fst viaPlain
    -- Nested records are compared field by field too: the second event, which
    -- the MAY compares and skips, lists nothing.
    it "a nested record of a party skipped by its action lists nothing" do
      withServiceFromSources "o4r-skip-nested" [("event.l4", nestedJL4)] \baseUrl mgr -> do
        let home fs = obj [("Address", obj ([("zip", num 5)] <> fs))]
            alice fs = obj [("name", str "Alice"), ("zhome", home fs)]
            arg = ["driver" .= obj [("name", str "Alice"), ("zhome", obj [("zip", num 5), ("floor", num 1)])]]
            go evs = ask baseUrl mgr "o4r-skip-nested" seatFn "soft" arg evs
        viaGap <- go [event (alice []) seatbelt 0, event (alice []) seatbelt 0]
        viaWritten <- go [event (alice [("floor", num 1)]) seatbelt 0, event (alice [("floor", num 1)]) seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.zhome.Address.floor"])) viaWritten
    -- A default that a computation of the rules read while the party was
    -- compared is kept: here the obligation's party is built from the
    -- argument's fields, the built field keeps its value for the next event,
    -- which therefore does not read the default again, and the verdict rests
    -- on it.
    it "keeps a default the obligation's party was computed from, though the event is skipped" do
      withServiceFromSources "o4r-skip-derived" [("event.l4", derivedJL4)] \baseUrl mgr -> do
        let go arg = ask baseUrl mgr "o4r-skip-derived" "copy rule" "soft" ["driver" .= arg] [event aliceFull drive 0, event aliceFull seatbelt 0]
        viaGap <- go aliceGap
        viaWritten <- go aliceFull
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaGap `shouldBe` fmap fst viaWritten
        fmap snd viaGap `shouldSatisfy` either (const False) (any ("licence" `Text.isInfixOf`))
        fmap snd viaGap `shouldSatisfy` either (const False) (not . any ("events[" `Text.isPrefixOf`))
    -- What is taken back for one obligation is a default again: an obligation
    -- run beside it (RAND) that takes the same event rests on it, and lists it,
    -- whichever of the two compares the party first.
    forM_ [("seatbelt first", "o4r-rand-sd", randSeatFirstJL4), ("drive first", "o4r-rand-ds", randDriveFirstJL4)] \(order, deployId, source) ->
      it ("a party taken back for one obligation is listed for the one beside it that takes the event (" <> order <> ")") do
        withServiceFromSources deployId [("event.l4", source)] \baseUrl mgr -> do
          let go evs = ask baseUrl mgr deployId "both rules" "soft" driverFull evs
          viaGap <- go [event aliceGap drive 0, event aliceFull seatbelt 0]
          viaWritten <- go [event aliceFull drive 0, event aliceFull seatbelt 0]
          fmap snd viaWritten `shouldBe` Right []
          viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.licence"])) viaWritten
          unmet <- go [event aliceFull seatbelt 0]
          fmap fst unmet `shouldNotBe` fmap fst viaWritten

  -- The site of a default (a line and a column of the program) is mapped to the
  -- path the request wrote; a mapping that could go wrong must be refused, never
  -- listed. Names and strings that hold " WITH ", characters that are not ASCII,
  -- and tabs.
  describe "a default's site maps to its path, or the request is refused" do
    let party extra = obj ([ ("a WITH b", str "p WITH q"), ("b🙂 WITH", str "🙂 WITH 🙂\tx"), ("ñame", str "Ünal") ] <> extra)
        driver = ["driver" .= party [("zhome", obj [("zip", num 5), ("floor", num 1)])]]
    it "' WITH ' in a field's name and in a string, a tab in a string, and names that are not ASCII, before a nested record" do
      withServiceFromSources "o4r-scan" [("event.l4", scanJL4)] \baseUrl mgr -> do
        let go p evs = ask baseUrl mgr "o4r-scan" seatFn p driver evs
        none <- go "soft" []
        viaWritten <- go "soft" [event (party [("zhome", obj [("Address", obj [("zip", num 5), ("floor", num 1)])])]) seatbelt 0]
        viaGap <- go "soft" [event (party [("zhome", obj [("Address", obj [("zip", num 5)])])]) seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.zhome.Address.floor"])) viaWritten
    it "a tab in a field's name is refused, naming the character" do
      withServiceFromSources "o4r-tab" [("event.l4", seatJL4)] \baseUrl mgr -> do
        refused <- ask baseUrl mgr "o4r-tab" seatFn "soft" ["driver" .= obj [("name", str "Alice"), ("licence", str "full")]]
          [event (obj [("name", str "Alice"), ("li\tcence", str "full")]) seatbelt 0]
        refused `shouldSatisfy` refusedNaming "which L4 cannot write inside a quoted name"

  -- Condition 2 of the ruling: B accepts the nested record clients send today,
  -- keyed by its constructor.
  describe "condition 2: a nested record keyed by its constructor is accepted" do
    it "answers it written in full, and lists the field it leaves out" do
      withServiceFromSources "o4r-cond2" [("event.l4", nestedJL4)] \baseUrl mgr -> do
        let driver = ["driver" .= obj [("name", str "Alice"), ("zhome", obj [("zip", num 5), ("floor", num 1)])]]
            party fs = obj [("name", str "Alice"), ("zhome", obj [("Address", obj fs)])]
            go evs = ask baseUrl mgr "o4r-cond2" seatFn "soft" driver evs
        none <- go []
        viaWritten <- go [event (party [("zip", num 5), ("floor", num 1)]) seatbelt 0]
        fmap snd viaWritten `shouldBe` Right []
        fmap fst viaWritten `shouldNotBe` fmap fst none
        viaGap <- go [event (party [("zip", num 5)]) seatbelt 0]
        viaGap `shouldBe` fmap (\(v, _) -> (v, ["events[0].party.zhome.Address.floor"])) viaWritten

  describe ("the listing property over " <> show (length allShapes) <> " generated record shapes and "
            <> show (sum (map (length . omissions) allShapes)) <> " request pairs (depth 0-2, nested record before and after the same-named field, party and action records)") do
    forM_ shapeGroups \(gid, shapes) ->
      it ("holds for " <> Text.unpack gid <> " (" <> show (length shapes) <> " shapes)") do
        withServiceFromSources gid [("shapes.l4", groupSource shapes)] \baseUrl mgr ->
          forM_ shapes \s -> do
            let go evs = ask baseUrl mgr gid (shapeFn s) "soft" (shapeArguments s) evs
                sorted = fmap (fmap List.sort)
            none <- go []
            written <- go [shapeEvent s []]
            -- the event written in full is taken, and nothing is presumed
            (s, fmap snd written) `shouldBe` (s, Right [])
            unless (fmap fst written /= fmap fst none) $
              expectationFailure ("the written event was not taken for " <> show s <> ": " <> show written)
            forM_ (omissions s) \o -> do
              omitted <- go [shapeEvent s o]
              (s, o, sorted omitted) `shouldBe` (s, o, sorted (fmap (\(v, _) -> (v, map (notePath s) o)) written))

-- ----------------------------------------------------------------------------
-- Generated record shapes
-- ----------------------------------------------------------------------------

data Side = PartySide | ActionSide
  deriving stock (Eq, Show)

-- | An event record and the records nested in it, level 0 being the event's
-- own. Every level has a key field, a @note@ (the same name at every level),
-- and, above the last, a field holding the next level, named @home@ (sorting
-- before @note@) or @zhome@ (sorting after it).
data Shape = Shape
  { number   :: Int
  , side     :: Side
  , defaults :: [Bool]   -- ^ per level: whether its note has a TYPICALLY
  , nests    :: [Text]   -- ^ per level above the last: the field holding the next one
  }
  deriving stock (Eq, Show)

shapeGroups :: [(Text, [Shape])]
shapeGroups =
  [ ( "o4p-" <> sideTag sd <> "-" <> (if null ns then "flat" else Text.intercalate "-" ns)
    , [ Shape n sd ds ns | (n, ds) <- zip [0 ..] (boolVectors (length ns + 1)) ] )
  | sd <- [PartySide, ActionSide]
  , depth <- [0, 1, 2 :: Int]
  , ns <- sequence (replicate depth ["home", "zhome"])
  ]
  where
    sideTag PartySide = "party"
    sideTag ActionSide = "action"
    boolVectors k = sequence (replicate k [False, True])

allShapes :: [Shape]
allShapes = concatMap snd shapeGroups

depthOf :: Shape -> Int
depthOf s = length s.nests

-- | Every non-empty set of levels whose defaulted note the event leaves out.
omissions :: Shape -> [[Int]]
omissions s = filter (not . null) (List.subsequences [ k | (k, True) <- zip [0 ..] s.defaults ])

typeName :: Shape -> Int -> Text
typeName s k = prefix <> tshow s.number
  where
    prefix = case k of
      0 -> if s.side == PartySide then "P" else "Q"
      1 -> "R"
      _ -> "S"

keyField :: Shape -> Int -> Text
keyField s = \case
  0 -> if s.side == PartySide then "aname" else "verb"
  1 -> "zip"
  _ -> "x"

keyJson :: Shape -> Int -> Aeson.Value
keyJson s = \case
  0 -> str (if s.side == PartySide then "Alice" else "drive")
  1 -> num 5
  _ -> num 13

keyL4 :: Shape -> Int -> Text
keyL4 s = \case
  0 -> if s.side == PartySide then "\"Alice\"" else "\"drive\""
  1 -> "5"
  _ -> "13"

noteDefault, noteWritten :: Int -> Int
noteDefault k = [7, 9, 11] !! k
noteWritten k = [3, 4, 6] !! k

hasDefault :: Shape -> Int -> Bool
hasDefault s k = s.defaults !! k

-- | The value a level's note has: its default, or the value written when it has none.
noteValue :: Shape -> Int -> Int
noteValue s k = if hasDefault s k then noteDefault k else noteWritten k

shapeFn :: Shape -> Text
shapeFn s = (if s.side == PartySide then "rp" else "ra") <> tshow s.number

declares :: Shape -> Text
declares s = Text.unlines (concatMap level [0 .. depthOf s])
  where
    level k =
      [ "DECLARE " <> typeName s k <> " HAS"
      , "    " <> keyField s k <> " IS A " <> (if k == 0 then "STRING" else "NUMBER") ]
      <> [ "    " <> s.nests !! k <> " IS A " <> typeName s (k + 1) | k < depthOf s ]
      <> [ "    note IS A NUMBER" <> (if hasDefault s k then " TYPICALLY " <> tshow (noteDefault k) else "")
         , "" ]

rule :: Shape -> Text
rule s = case s.side of
  PartySide -> Text.unlines
    [ "@export shape " <> tshow s.number
    , "GIVEN driver IS A " <> typeName s 0
    , "GIVETH A PROVISION OF " <> typeName s 0 <> ", `Driver Action`"
    , shapeFn s <> " MEANS"
    , "    PARTY driver"
    , "    MUST `wear seatbelt`"
    , "    WITHIN 1"
    , "    HENCE"
    , "        PARTY driver"
    , "        MAY `drive`"
    , "" ]
  ActionSide -> Text.unlines
    [ "@export shape " <> tshow s.number
    , "GIVEN driver IS A Who"
    , "GIVETH A PROVISION OF Who, " <> typeName s 0
    , shapeFn s <> " MEANS"
    , "    PARTY driver"
    , "    MUST " <> pattern 0
    , "    WITHIN 1"
    , "    HENCE FULFILLED"
    , "    LEST BREACH"
    , "" ]
  where
    -- the action's whole value, so that the match reads every field
    pattern k = Text.unwords $
      [ typeName s k, keyL4 s k ]
      <> [ "(" <> pattern (k + 1) <> ")" | k < depthOf s ]
      <> [ tshow (noteValue s k) ]

groupSource :: [Shape] -> Text
groupSource shapes = Text.unlines $
  [ "DECLARE Who HAS"
  , "    name IS A STRING"
  , ""
  , "DECLARE `Driver Action` IS ONE OF"
  , "    `wear seatbelt`"
  , "    `drive`"
  , "" ]
  <> concat [ [declares s, rule s] | s <- shapes ]

-- | A level as the event writes it, nested levels keyed by their constructor,
-- leaving out the note of every level in the list.
eventRecord :: Shape -> [Int] -> Int -> Aeson.Value
eventRecord s omitted k = obj $
  [ (keyField s k, keyJson s k) ]
  <> [ (s.nests !! k, obj [(typeName s (k + 1), eventRecord s omitted (k + 1))]) | k < depthOf s ]
  <> [ ("note", num (noteValue s k)) | k `notElem` omitted ]

-- | A level as the request's arguments give it: every field, nested levels plain.
argumentRecord :: Shape -> Int -> Aeson.Value
argumentRecord s k = obj $
  [ (keyField s k, keyJson s k) ]
  <> [ (s.nests !! k, argumentRecord s (k + 1)) | k < depthOf s ]
  <> [ ("note", num (noteValue s k)) ]

shapeArguments :: Shape -> [Pair]
shapeArguments s = case s.side of
  PartySide -> ["driver" .= argumentRecord s 0]
  ActionSide -> ["driver" .= obj [("name", str "Alice")]]

shapeEvent :: Shape -> [Int] -> Aeson.Value
shapeEvent s omitted = case s.side of
  PartySide -> event (eventRecord s omitted 0) (str "wear seatbelt") 0
  ActionSide -> event (obj [("name", str "Alice")]) (eventRecord s omitted 0) 0

-- | The path the request writes level k's note at.
notePath :: Shape -> Int -> Text
notePath s k =
  "events[0]." <> (if s.side == PartySide then "party" else "action")
  <> mconcat [ "." <> s.nests !! j <> "." <> typeName s (j + 1) | j <- [0 .. k - 1] ]
  <> ".note"

tshow :: Show a => a -> Text
tshow = Text.pack . show

-- ----------------------------------------------------------------------------
-- Fixtures (the review's modules, kept as it wrote them where it wrote one)
-- ----------------------------------------------------------------------------

stealJL4, steal2JL4, steal3JL4, actJL4, actMissedJL4, actFastJL4, seatJL4, seatLestJL4, randSeatFirstJL4, randDriveFirstJL4, derivedJL4, payloadJL4, fnkeyJL4, scanJL4, nestedJL4 :: Text

stealJL4 = [i|
DECLARE Address HAS
    zip IS A NUMBER
    note IS A NUMBER TYPICALLY 9

DECLARE Driver HAS
    aname IS A STRING
    home IS AN Address
    note IS A NUMBER TYPICALLY 7

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

steal2JL4 = [i|
DECLARE Address HAS
    zip IS A NUMBER
    anote IS A NUMBER TYPICALLY 9

DECLARE Driver HAS
    aname IS A STRING
    home IS AN Address
    anote IS A NUMBER TYPICALLY 7

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

steal3JL4 = [i|
DECLARE Address HAS
    zip IS A NUMBER
    floor IS A NUMBER TYPICALLY 1
    note IS A NUMBER

DECLARE Driver HAS
    aname IS A STRING
    home IS AN Address
    note IS A NUMBER TYPICALLY 7

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

actJL4 = [i|
DECLARE Driver HAS
    name IS A STRING

DECLARE Act HAS
    verb IS A STRING
    mode IS A STRING TYPICALLY "plain"

@export default drive rule
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, Act
`drive rule` MEANS
    PARTY driver
    MUST Act "drive" "plain"
    WITHIN 1
    HENCE FULFILLED
    LEST BREACH
|]

-- As 'actJL4' with no LEST: a missed deadline, whose breach prints the event
-- that revealed it.
actMissedJL4 = [i|
DECLARE Driver HAS
    name IS A STRING

DECLARE Act HAS
    verb IS A STRING
    mode IS A STRING TYPICALLY "plain"

@export default drive rule
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, Act
`drive rule` MEANS
    PARTY driver
    MUST Act "drive" "plain"
    WITHIN 1
    HENCE FULFILLED
|]

-- As 'actJL4', where the act owed is not the default: an event that leaves
-- @mode@ out does not match because of the default.
actFastJL4 = [i|
DECLARE Driver HAS
    name IS A STRING

DECLARE Act HAS
    verb IS A STRING
    mode IS A STRING TYPICALLY "plain"

@export default drive rule
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, Act
`drive rule` MEANS
    PARTY driver
    MUST Act "drive" "fast"
    WITHIN 1
    HENCE FULFILLED
    LEST BREACH
|]

seatJL4 = [i|
DECLARE Driver HAS
    name IS A STRING
    licence IS A STRING TYPICALLY "full"

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

derivedJL4 = [i|
DECLARE Driver HAS
    name IS A STRING
    licence IS A STRING TYPICALLY "full"

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

GIVEN d IS A Driver
GIVETH A Driver
`copy of` MEANS Driver WITH name IS d's name, licence IS d's licence

@export default copy rule
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`copy rule` MEANS
    PARTY `copy of` driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE FULFILLED
    LEST BREACH
|]

randSeatFirstJL4 = [i|
DECLARE Driver HAS
    name IS A STRING
    licence IS A STRING TYPICALLY "full"

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default both rules
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`both rules` MEANS
    (PARTY driver MUST `wear seatbelt` WITHIN 1 HENCE FULFILLED LEST BREACH)
    RAND
    (PARTY driver MUST `drive` WITHIN 1 HENCE FULFILLED LEST BREACH)
|]

randDriveFirstJL4 = [i|
DECLARE Driver HAS
    name IS A STRING
    licence IS A STRING TYPICALLY "full"

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default both rules
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`both rules` MEANS
    (PARTY driver MUST `drive` WITHIN 1 HENCE FULFILLED LEST BREACH)
    RAND
    (PARTY driver MUST `wear seatbelt` WITHIN 1 HENCE FULFILLED LEST BREACH)
|]

seatLestJL4 = [i|
DECLARE Driver HAS
    name IS A STRING
    licence IS A STRING TYPICALLY "full"

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
    LEST BREACH
|]

-- The party is the rules' own record, so the event's party is compared with a
-- value the rules wrote in full; its status is a ONE OF constructor with a
-- defaulted field.
payloadJL4 = [i|
DECLARE Status IS ONE OF
    active HAS
        level IS A NUMBER
        since IS A NUMBER TYPICALLY 2020
    suspended

DECLARE Driver HAS
    name IS A STRING
    status IS A Status

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

`the status` MEANS active WITH level IS 3, since IS 2020
`the driver` MEANS Driver WITH name IS "Alice", status IS `the status`

@export default seatbelt requirement
GIVEN unused IS A NUMBER
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY `the driver`
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY `the driver`
        MAY `drive`
|]

fnkeyJL4 = [i|
DECLARE Address HAS
    zip IS A NUMBER
    floor IS A NUMBER

GIVEN zip IS A NUMBER
      floor IS A NUMBER TYPICALLY 1
GIVETH AN Address
mkAddr MEANS Address WITH zip IS zip, floor IS floor

DECLARE Driver HAS
    name IS A STRING
    zhome IS AN Address

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

scanJL4 = [i|
DECLARE Address HAS
    zip IS A NUMBER
    floor IS A NUMBER TYPICALLY 1

DECLARE `Fahrer Ü` HAS
    `a WITH b` IS A STRING
    `b🙂 WITH` IS A STRING
    `ñame` IS A STRING
    zhome IS AN Address

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A `Fahrer Ü`
GIVETH A PROVISION OF `Fahrer Ü`, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]

nestedJL4 = [i|
DECLARE Address HAS
    zip IS A NUMBER
    floor IS A NUMBER TYPICALLY 1

DECLARE Driver HAS
    name IS A STRING
    zhome IS AN Address

DECLARE `Driver Action` IS ONE OF
    `wear seatbelt`
    `drive`

@export default seatbelt requirement
GIVEN driver IS A Driver
GIVETH A PROVISION OF Driver, `Driver Action`
`seatbelt requirement` MEANS
    PARTY driver
    MUST `wear seatbelt`
    WITHIN 1
    HENCE
        PARTY driver
        MAY `drive`
|]
