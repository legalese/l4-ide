-- | Reading what @l4 run@, @l4 batch@, @l4 trace@ and jl4-repl give.
module Agreement.Cli
  ( parseRunText
  , parseRunJson
  , runBatch
  , parseDotRoots
  , dotRoot
  , traceRefusalPrefix
  , traceAsciiReply
  , lineOfLocation
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Read as TR
import System.FilePath ((</>))

import Agreement.Process (runIn)
import Agreement.Verdict

-- | The line a location "file:line:column-…" names, where what follows the
-- column is a column on the same line or a line and a column.
lineOfLocation :: T.Text -> Maybe Int
lineOfLocation loc = case T.splitOn ":" loc of
  _ : l : _ | Right (n, "") <- TR.decimal l -> Just n
  _ -> Nothing

-- | What @l4 run@ prints for each directive, by the line of the directive:
-- each block "Evaluation[n] @ file:line:column-…", then "Result:" and the
-- result two columns in, then "Trace:".
parseRunText :: T.Text -> Map.Map Int Seen
parseRunText out = Map.fromList (go (T.lines (T.filter (/= '\r') out)))
 where
  go ls = case dropWhile (not . isHeader) ls of
    [] -> []
    h : rest ->
      let (block, more) = break isHeader rest
       in case lineOfLocation (T.strip (snd (T.breakOnEnd "@ " h))) of
            Just n -> (n, seenOfResult (resultOf block)) : go more
            Nothing -> go more
  isHeader l = "Evaluation[" `T.isPrefixOf` l
  resultOf block =
    let afterResult = drop 1 (dropWhile (/= "Result:") block)
        content = takeWhile (/= "Trace:") afterResult
     in T.intercalate "\n" (map (T.drop 2) (dropTrailingBlank content))
  dropTrailingBlank = reverse . dropWhile (T.null . T.strip) . reverse
  seenOfResult t
    | Just r <- refusalText 0 t = SeenRefused r
    | t == "assertion satisfied" = SeenHolds
    | otherwise = SeenText t

-- | What @l4 run --json@ gives for each directive, by its line.
parseRunJson :: T.Text -> Either String (Map.Map Int Seen)
parseRunJson out = do
  v <- Aeson.eitherDecodeStrict (TE.encodeUtf8 out)
  case field "results" v of
    Just (Aeson.Array rs) ->
      Map.fromList <$> traverse one (toList rs)
    _ -> Left ("no results in " <> show v)
 where
  one r = case (field "range" r, field "kind" r) of
    (Just (Aeson.String rng), Just (Aeson.String kind))
      | Just n <- lineOfLocation rng -> Right (n, seenOf kind r)
    _ -> Left ("a result with no range or kind: " <> show r)
  seenOf kind r = case (kind, field "value" r, field "reason" r) of
    ("refused", _, Just (Aeson.String reason)) -> SeenRefused reason
    ("value", Just (Aeson.String t), _) -> SeenText t
    ("error", Just (Aeson.String t), _) -> SeenRaised t
    ("assertion", Just (Aeson.Bool True), _) -> SeenHolds
    _ -> SeenText (T.pack (show r))

field :: T.Text -> Aeson.Value -> Maybe Aeson.Value
field k = \case
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

-- | @l4 batch@ over the cases of one rule, a row of inputs for each and no
-- `pad`, which a row may leave out: the verdict of each row, in order.
runBatch :: FilePath -> FilePath -> FilePath -> FilePath -> T.Text -> [[(T.Text, Aeson.Value)]] -> IO (Either String [Seen])
runBatch l4 dir file rowsFile ruleName rows = do
  LBS.writeFile rowsFile (Aeson.encode [Aeson.object [(Key.fromText k, v) | (k, v) <- row] | row <- rows])
  (_, out, err) <- runIn dir l4 ["batch", dir </> file, "-e", T.unpack ruleName, "--inputs", rowsFile, "-c"] ""
  let parsed = [Aeson.eitherDecodeStrict (TE.encodeUtf8 l) | l <- T.lines out, "{" `T.isPrefixOf` l]
  case sequence parsed of
    Left e -> pure (Left (e <> " in " <> T.unpack out))
    Right vs
      | length vs /= length rows -> pure (Left ("rows " <> show (length rows) <> ", answers: " <> T.unpack out <> T.unpack err))
      | otherwise -> pure (Right (map seenOfRow vs))
 where
  seenOfRow v =
    let result = case field "output" v of
          Just (Aeson.Array os) | o : _ <- toList os -> field "result" o
          _ -> Nothing
     in case (field "status" v, result) of
          (Just "success", Just r) -> SeenJson r
          (Just "refused", Just r) | Just (Aeson.String reason) <- field "refused" r >>= field "reason" -> SeenRefused reason
          (Just "error", Just r) | Just (Aeson.String e) <- field "error" r -> SeenRaised e
          _ -> SeenText (T.pack (show v))

-- | The label of node 0 of each graph in a GraphViz text, in order, with
-- GraphViz's escapes read: the call, and what the trace says it gives.
parseDotRoots :: T.Text -> [(T.Text, Seen)]
parseDotRoots out =
  [ dotRoot (unescape (dropQuote rest))
  | l <- T.lines (T.filter (/= '\r') out)
  , Just rest <- [T.stripPrefix "    0 [label=\"" l]
  ]
 where
  dropQuote t = if "\"" `T.isSuffixOf` t then T.dropEnd 1 t else t

-- | A root's label: the call, a rule of box-drawing dashes, and the outcome,
-- one of "↯ refused: " and the reason, "<error>", or the answer.
dotRoot :: T.Text -> (T.Text, Seen)
dotRoot label =
  let (call, rest) = T.breakOn "\n" label
      outcome = T.drop 1 (snd (T.breakOn "\n" (T.drop 1 rest)))
   in (call, seenOfOutcome outcome)
 where
  seenOfOutcome o
    | Just r <- T.stripPrefix traceRefusalPrefix o = SeenRefused r
    | o == "<error>" = SeenRaised ""
    | otherwise = SeenText o

-- | What a trace prints before a refusal's reason, at the step that refuses.
traceRefusalPrefix :: T.Text
traceRefusalPrefix = "↯ refused: "

unescape :: T.Text -> T.Text
unescape = T.pack . go . T.unpack
 where
  go = \case
    '\\' : 'n' : cs -> '\n' : go cs
    '\\' : 'l' : cs -> '\n' : go cs
    '\\' : c : cs -> c : go cs
    c : cs -> c : go cs
    [] -> []

-- | The REPL's reply to @:traceascii@, without the trace below it.
traceAsciiReply :: T.Text -> Seen
traceAsciiReply t =
  let reply = fst (T.breakOn "\n\nTrace:" t)
   in case T.stripPrefix "Result: " reply of
        Just answer -> SeenText answer
        Nothing -> replReply reply
