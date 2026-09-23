-- | @l4 render FILE@ — deterministic L4 → document export.
--
-- Emits the 'L4.Export.Document' IR in one of several formats:
--
--   * @json@ — the document IR (consumed by the TS renderers)
--   * @plan@ — the export plan (imports\/rules tree + reachability)
--   * @text@ — a plain-text rendering of the document
--   * @html@ — a standalone, styled HTML document
--   * @akn@  — Akoma Ntoso XML
--
-- The actual rendering lives in 'L4.Export.Render' (in @jl4-core@) so the CLI
-- and the @jl4-lsp@ server share one implementation; this module only handles
-- the CLI surface (option parsing, loading the file, writing output).
--
-- "Don't render unused definitions and rules" is on by default; pass
-- @--include-unused@ to render unreachable imported material too.
module L4.Cli.Render
  ( RenderOptions(..)
  , RenderFormat(..)
  , renderOptionsParser
  , renderCmd
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Export.Document
import L4.Lexer (LangTag (..))
import L4.Syntax (defaultModuleLang)
import qualified L4.Nlg as Nlg
import qualified L4.Parser as Parser
import L4.Export.Render (RenderConfig(..), renderAkn, renderHtml, renderText)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data RenderFormat = FmtJson | FmtPlan | FmtText | FmtHtml | FmtAkn
  deriving (Eq, Show)

data RenderOptions = RenderOptions
  { renderFile           :: FilePath
  , renderFormat         :: RenderFormat
  , renderOutput         :: Maybe FilePath
  , renderIncludeUnused  :: Bool
  , renderNumberSections :: Bool
  , renderNumberClauses  :: Bool
  , renderToc            :: Bool
  , renderLang           :: Maybe LangTag
  , renderFixedNow       :: FixedNowOpt
  }

renderFormatReader :: ReadM RenderFormat
renderFormatReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "json" -> Right FmtJson
    "plan" -> Right FmtPlan
    "text" -> Right FmtText
    "html" -> Right FmtHtml
    "akn"  -> Right FmtAkn
    "xml"  -> Right FmtAkn
    other  -> Left $ "Invalid format: " <> Text.unpack other <> " (expected json|plan|text|html|akn)"

renderOptionsParser :: Parser RenderOptions
renderOptionsParser = RenderOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to render")
  <*> option renderFormatReader
        ( long "format"
       <> metavar "FMT"
       <> value FmtHtml
       <> showDefaultWith (const "html")
       <> help "Output format: json|plan|text|html|akn"
        )
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write to FILE instead of stdout"
            )
        )
  <*> switch
        ( long "include-unused"
       <> help "Also render imported definitions/rules not referenced by this document"
        )
  <*> switch
        ( long "number-sections"
       <> help "Number section headings (§ 1, 1.1, …); off by default"
        )
  <*> switch
        ( long "number-clauses"
       <> help "Number clauses (1.); off by default"
        )
  <*> switch
        ( long "toc"
       <> help "Prepend a linked table of contents (HTML only)"
        )
  <*> langOption "rule"
  <*> fixedNowParser

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

renderCmd :: RenderOptions -> IO ()
renderCmd opts = do
  evalConfig <- makeEvalConfig opts.renderFixedNow
  -- The token stream as well as the type-check result: the document's language
  -- falls back to the module's own @\@lang@, and that is a declaration in the
  -- token stream (see 'Parser.declaredModuleLang') rather than anything the
  -- resolved AST keeps. 'Rules.GetLexTokens' is what the parse rule itself
  -- consumed, so this re-reads nothing.
  (errs, (mTc, mToks)) <- runOneshot evalConfig opts.renderFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    (,) <$> Shake.use Rules.SuccessfulTypeCheck uri
        <*> Shake.use Rules.GetLexTokens uri

  case mTc of
    Nothing -> do
      putDiagnostics errs
      exitFailure
    Just tc -> do
      -- Surface any diagnostics on stderr, but still render: a document is
      -- useful even when the file has non-fatal issues.
      putDiagnostics errs
      let cfg = defaultExportConfig
                  { dropUnused = not opts.renderIncludeUnused
                  , mixfixHeadings = mixfixHeadingsFromRegistry tc.mixfixRegistry
                  }
          -- The language the document SAYS it is in, in one place: the one
          -- asked for, else the one the module declares, else @en@ (R-M2). The
          -- same order 'localise' below effectively applies to the renderings
          -- themselves — @--lang@ promotes a tagged herald, and with no flag the
          -- default herald is the one @\@lang@ stamped.
          declaredLanguage = fromMaybe defaultModuleLang
                               (Parser.declaredModuleLang . fst =<< mToks)

          -- __A label the document cannot support is not taken.__ A partial
          -- translation is fine and is the point of the flag — a rule with no
          -- rendering in the asked-for language keeps its default one, so a
          -- mostly-Hebrew document is honestly @lang="he"@. But when NOTHING in
          -- the module (or its imports) renders in that language, every sentence
          -- in the body is the fallback, and @lang@ would be a claim with no
          -- support: with @--lang he@ on an all-English encoding, @dir="rtl"@
          -- would then lay English out right to left, moving its full stops to
          -- the wrong end of the line. So the document keeps the language it
          -- declares, and stderr says so.
          --
          -- @want == declaredLanguage@ is checked first and separately: a module
          -- that declares @\@lang he@ and carries no @\@nlg@ at all renders no
          -- Hebrew prose, and asking it for Hebrew is still not a mislabelling.
          carriesRequested want =
            want == declaredLanguage
              || any (Nlg.carriesLanguage want) (tc.module' : rawDeps)
          (docLanguage, unsupportedRequest) = case opts.renderLang of
            Nothing -> (declaredLanguage, Nothing)
            Just want
              | carriesRequested want -> (want, Nothing)
              | otherwise             -> (declaredLanguage, Just want)
          rcfg = MkRenderConfig
                   { numberSections = opts.renderNumberSections
                   , numberClauses  = opts.renderNumberClauses
                   , toc            = opts.renderToc
                   , docLang        = docLanguage
                   }
          -- Choose the language BEFORE building the document, not inside it.
          -- 'selectLanguage' moves the requested rendering into the slot
          -- 'L4.Export.Document' already reads, so every format below becomes
          -- language-aware without one of them being touched — which is the
          -- whole reason selection was built as a rewrite rather than as a
          -- parameter threaded through the exporters.
          --
          -- Applied to the DEPENDENCIES too: a rule rendered here can come
          -- from an imported module, and a document half in one language
          -- because its imports were missed is worse than one in either.
          --
          -- 'selectLanguage' 'Nothing' is the identity, so with no --lang the
          -- output is byte-for-byte what it was.
          localise = Nlg.selectLanguage opts.renderLang
          rawDeps = dedupModules (transitiveDeps tc)
          mainModule = localise tc.module'
          depModules = map localise rawDeps
          doc = buildDocument cfg mainModule depModules
      -- Said only for the formats that carry a document language, so that
      -- `--format text --lang zz` stays byte-identical on BOTH streams.
      case (unsupportedRequest, formatLabelsLanguage opts.renderFormat) of
        (Just (MkLangTag want), True) ->
          let MkLangTag label = docLanguage
          in hPutStrLn stderr $ Text.unpack $
               "l4 render: no renderings in \"" <> want <> "\"; document labelled \""
                 <> label <> "\" instead."
        _ -> pure ()
      case opts.renderFormat of
        FmtJson -> emitBytes opts (Aeson.encode doc)
        FmtPlan -> emitBytes opts (Aeson.encode (buildPlan cfg mainModule depModules))
        FmtText -> emitText opts (renderText rcfg doc)
        FmtHtml -> emitText opts (renderHtml rcfg doc)
        FmtAkn  -> emitText opts (renderAkn rcfg doc)
      exitSuccess

-- | Does this format put the document's language in its output?
--
-- HTML as @\<html lang="…"\>@, Akoma Ntoso as the language component of its
-- Expression-level FRBR URIs. @text@, @json@ and @plan@ carry the chosen
-- WORDINGS but say nothing about which language they are.
formatLabelsLanguage :: RenderFormat -> Bool
formatLabelsLanguage = \ case
  FmtHtml -> True
  FmtAkn  -> True
  FmtJson -> False
  FmtPlan -> False
  FmtText -> False

----------------------------------------------------------------------------
-- Output dispatch
----------------------------------------------------------------------------

emitText :: RenderOptions -> Text -> IO ()
emitText opts t = case opts.renderOutput of
  Just f  -> Text.writeFile f t
  Nothing -> Text.putStr t

emitBytes :: RenderOptions -> BSL8.ByteString -> IO ()
emitBytes opts b = case opts.renderOutput of
  Just f  -> BSL8.writeFile f b
  Nothing -> BSL8.putStrLn b

-- | All transitively-imported modules (the resolved dependency forest).
