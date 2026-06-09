-- | Pretty-printer for canonical PROLEG: the "print" half of @parse . print@.
--
-- Output is canonical, not byte-identical to arbitrary input (it normalises
-- layout): rule bodies are printed one conjunct per line. The round-trip law we
-- target is @parse (print p) == p@ on the AST, not @print (parse s) == s@ on text.
module L4.Proleg.Print
  ( printProgram
  , printClause
  , printTerm
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import L4.Proleg.Syntax

-- | Render a whole program, one clause per stanza, blank-line separated.
printProgram :: Program -> Text
printProgram (Program cs) = T.intercalate "\n\n" (map printClause cs) <> "\n"

-- | Render a single clause, terminated by @.@
printClause :: Clause -> Text
printClause = \case
  CRule (Rule h []) -> printTerm h <> "."
  CRule (Rule h bs) ->
    printTerm h <> " <=\n    " <> T.intercalate ",\n    " (map printTerm bs) <> "."
  CException (Exception h e) ->
    "exception(" <> printTerm h <> ", " <> printTerm e <> ")."
  CProc p -> printProc p <> "."
  CFact (Fact t) -> printTerm t <> "."

printProc :: ProcDecl -> Text
printProc = \case
  Allege t p -> "allege(" <> printTerm t <> ", " <> printParty p <> ")"
  ProvideEvidence t p -> "provide_evidence(" <> printTerm t <> ", " <> printParty p <> ")"
  Admission t p -> "admission(" <> printTerm t <> ", " <> printParty p <> ")"
  Plausible t -> "plausible(" <> printTerm t <> ")"

printParty :: Party -> Text
printParty = \case
  Plaintiff -> "plaintiff"
  Defendant -> "defendant"
  PartyTerm t -> printTerm t

-- | Render a term. Atoms are emitted verbatim; quoting is the parser's concern.
printTerm :: Term -> Text
printTerm = \case
  TVar v -> v
  TAtom a -> a
  TInt n -> T.pack (show n)
  TStr s -> "\"" <> s <> "\""
  TComp f args -> f <> "(" <> T.intercalate ", " (map printTerm args) <> ")"
  TList items mtail ->
    "[" <> T.intercalate ", " (map printTerm items) <> printTail mtail <> "]"
  where
    printTail Nothing = ""
    printTail (Just t) = " | " <> printTerm t
