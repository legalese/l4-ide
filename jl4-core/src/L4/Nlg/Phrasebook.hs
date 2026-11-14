-- | The frame words of a linearization, per language.
--
-- An @\@nlg@ herald supplies the author's own sentence for a rule. Everything
-- else in a linearized line is supplied by 'L4.Nlg' itself: the "is equal to"
-- between two sides, the "with" before a call's arguments, the "not", the
-- "the sum of … and …". Those are the FRAME words, and until this module they
-- were English whatever language the heralds were in, so a Hebrew document
-- read @‹Hebrew sentence› is equal to ‹value›@.
--
-- A phrasebook maps an English frame PHRASE, as a word sequence, to its
-- rendering. Phrases rather than words, because the words do not translate
-- one at a time: "is equal to" is one Hebrew expression (@שווה ל־@), and "is"
-- on its own is another. 'L4.Nlg.localize' matches the longest phrase first.
--
-- __What this is not.__ It is a lexicon, not a grammar. Word order stays the
-- English linearizer's, so a Hebrew line keeps English constituent order
-- around its frame words; and a phrase has one rendering regardless of
-- context, so "by" reads the same after "dividing" as after "breach". That is
-- a first cut, and it is stated here so nobody mistakes it for the finished
-- thing.
--
-- __The Hebrew is an unreviewed draft.__ It was written by a model and has
-- not been read by a Hebrew-speaking lawyer. Treat every entry as a proposal.
--
-- A phrase with no entry stays English, and 'L4.Nlg.localize' reports it,
-- so a gap is visible rather than silent.
module L4.Nlg.Phrasebook
  ( Phrasebook
  , phrasebookFor
  , maqaf
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map

import L4.Lexer (LangTag, langPrimary)

-- | English phrase, as its words, to the rendering.
type Phrasebook = Map.Map [Text] Text

-- | The phrasebook for a language, or 'Nothing' when frame words should stay
-- as they are: English, and any language we have no table for.
--
-- A language with no table is deliberately 'Nothing' rather than an empty
-- map. An empty map would report every frame word as missing, which is true
-- but useless; 'Nothing' says "not localized", and the caller can say that
-- once.
--
-- The table is the language's, whatever region or script the tag adds, so
-- @he-IL@ gets the Hebrew table as @he@ does: a Hebrew wording tagged @he-IL@
-- is never joined by English frame words.
phrasebookFor :: LangTag -> Maybe Phrasebook
phrasebookFor tag
  | Text.toLower (langPrimary tag) == "he" = Just hebrew
  | otherwise                              = Nothing

-- | U+05BE HEBREW PUNCTUATION MAQAF. A rendering ending in it is a prefix
-- ("ל־", "מ־", "ו־") and is written against the next word, with no space.
maqaf :: Char
maqaf = '\x05BE'

hebrew :: Phrasebook
hebrew = Map.fromList [ (Text.words en, he) | (en, he) <- entries ]
 where
  entries :: [(Text, Text)]
  entries =
    -- comparison
    [ ("is equal to",        "שווה ל־")
    , ("is greater than",    "גדול מ־")
    , ("is less than",       "קטן מ־")
    , ("is at least",        "הוא לפחות")
    , ("is at most",         "הוא לכל היותר")
    , ("is exactly",         "הוא בדיוק")
    , ("is",                 "הוא")
    -- connectives
    , ("not",                "לא")
    , ("and",                "ו־")
    , ("or",                 "או")
    , ("implies",            "גורר")
    , ("if",                 "אם")
    , ("then",               "אז")
    , ("else",               "אחרת")
    , ("otherwise",          "אחרת")
    , ("provided that",      "ובלבד ש־")
    , ("hence",              "ומכאן")
    , ("lest",               "שאם לא כן")
    , ("because",            "משום ש־")
    -- calls
    , ("with",               "עם")
    , ("where",              "כאשר")
    , ("given",              "בהינתן")
    -- arithmetic
    , ("the sum of",         "הסכום של")
    , ("the difference between", "ההפרש בין")
    , ("the product of",     "המכפלה של")
    , ("the result of dividing", "תוצאת החלוקה של")
    , ("the result of",      "תוצאת")
    , ("by",                 "על ידי")
    , ("modulo",             "מודולו")
    , ("followed by",        "ואחריו")
    , ("list of",            "הרשימה")
    -- case analysis
    , ("consider the case distinctions of", "בחינת המקרים של")
    , ("when",               "כאשר")
    , ("in any other case",  "בכל מקרה אחר")
    , ("has",                "עם")
    , ("minus",              "פחות")
    -- what l4 render says around a rule
    , ("means",              "פירושו")
    , ("equals",             "שווה ל־")
    , ("consists of",        "מורכב מ־")
    , ("means one of",       "הוא אחד מאלה")
    , ("provides that",      "קובע כי")
    , ("depends on",         "תלוי ב־")
    , ("depending on",       "בהתאם ל־")
    , ("is decided as follows", "נקבע כדלקמן")
    , ("all of the following", "כל אלה")
    , ("any of the following", "אחד מאלה")
    , ("the following",      "אלה")
    , ("a list of the following", "רשימה של אלה")
    , ("the sum of the following", "הסכום של אלה")
    , ("the product of the following", "המכפלה של אלה")
    , ("none of the following holds", "אף אחד מאלה אינו מתקיים")
    , ("it is not the case that all of the following hold", "לא מתקיימים כל אלה")
    , ("otherwise, if",      "אחרת, אם")
    , ("once that is done,", "לאחר שנעשה כן,")
    , ("failing that,",      "אם לא נעשה כן,")
    , ("if that is done,",   "אם נעשה כן,")
    , ("if that is not done,", "אם לא נעשה כן,")
    , ("condition",          "תנאי")
    , ("result",             "תוצאה")
    , ("source",             "מקור")
    , ("schedule",           "תוספת")
    , ("definitions",        "הגדרות")
    , ("assumptions",        "הנחות")
    , ("provisions",         "הוראות")
    , ("interpretation",     "פרשנות")
    , ("imported definitions", "הגדרות מיובאות")
    , ("in this document, unless the context otherwise requires:", "במסמך זה, אלא אם כן ההקשר מחייב אחרת:")
    , ("the following are taken as given:", "להלן הנחות היסוד:")
    -- what l4 render says inside a rule
    , ("is more than",       "גדול מ־")
    , ("is not",             "אינו")
    , ("is one of",          "הוא אחד מ־")
    , ("is not one of",      "אינו אחד מ־")
    , ("is false",           "אינו נכון")
    , ("is absent",          "חסר")
    , ("absent",             "חסר")
    , ("is empty",           "ריק")
    , ("is present, with the value", "קיים, בערך")
    , ("is any value, called", "הוא ערך כלשהו, בשם")
    , ("it",                 "זה")
    , ("starts with",        "מתחיל ב־")
    , ("it is not the case that", "לא מתקיים ש־")
    , ("it is not the case that both", "לא מתקיימים שניהם:")
    , ("it is not the case that all of:", "לא מתקיימים כל אלה:")
    , ("either",             "או")
    , ("both",               "גם")
    , ("neither",            "לא")
    , ("nor",                "ולא")
    , ("all of:",            "כל אלה:")
    , ("any of:",            "אחד מאלה:")
    , ("none of:",           "אף אחד מאלה:")
    , ("for",                "עבור")
    , ("at least one item",  "לפחות פריט אחד")
    , ("every item",         "כל פריט")
    , ("the items",          "הפריטים")
    , ("is such that",       "כך ש־")
    , ("such that",          "כך ש־")
    , ("for each item",      "עבור כל פריט")
    , ("is in breach",       "מפר")
    , ("the obligation is breached", "החובה הופרה")
    , ("immediately",        "מיד")
    -- the words for a field's type
    , ("number",             "מספר")
    , ("whole number",       "מספר שלם")
    , ("text",               "טקסט")
    , ("yes or no",          "כן או לא")
    , ("date",               "תאריך")
    , ("time",               "שעה")
    , ("date and time",      "תאריך ושעה")
    , ("amount of money",    "סכום כסף")
    , ("percentage",         "אחוז")
    , ("if any",             "אם יש")
    -- deontics and time
    , ("must",               "חייב")
    , ("may",                "רשאי")
    , ("must not",           "אסור לו")
    , ("party",              "הצד")
    , ("every",              "כל")
    , ("who",                "אשר")
    , ("within",             "בתוך")
    , ("before",             "לפני")
    , ("after",              "לאחר")
    , ("of",                 "של")
    , ("of that",            "מאותו מועד")
    , ("the deadline",       "המועד האחרון")
    , ("the arming",         "ההפעלה")
    , ("the join",           "ההצטרפות")
    , ("in",                 "ב־")
    , ("all",                "כל")
    -- ledgers. The possessive ("'s", "official's") has no entry on purpose:
    -- Hebrew puts the owner after the thing owned, which a lexicon cannot
    -- reorder, so it stays English and is reported.
    , ("record",             "רשום")
    , ("commit",             "רשום רשמית")
    , ("recall",             "אחזר")
    , ("breach",             "הפרה")
    -- months, as they follow a day: "16 ביולי 2025"
    , ("January", "בינואר"), ("February", "בפברואר"), ("March", "במרץ")
    , ("April", "באפריל"), ("May", "במאי"), ("June", "ביוני")
    , ("July", "ביולי"), ("August", "באוגוסט"), ("September", "בספטמבר")
    , ("October", "באוקטובר"), ("November", "בנובמבר"), ("December", "בדצמבר")
    -- traces
    , ("executing contract", "ביצוע החוזה")
    , ("at",                 "במועד")
    , ("did",                "ביצע")
    , ("with the following events:", "עם האירועים הבאים:")
    , ("the model refuses to answer:", "המודל מסרב להשיב:")
    , ("the following must refuse:",   "הביטוי הבא חייב לסרב:")
    ]
