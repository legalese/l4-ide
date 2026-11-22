-- Copyright (c) 2019 The DAML Authors. All rights reserved.
-- SPDX-License-Identifier: Apache-2.0

{-# LANGUAGE CPP             #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE FieldSelectors #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ViewPatterns #-}

module LSP.Core.Types.Diagnostics (
  LSP.Diagnostic(..),
  ShowDiagnostic(..),
  FileDiagnostic(..),
  fdFilePathL,
  fdLspDiagnosticL,
  fdShouldShowDiagnosticL,
  fdOriginalSourceL,
  messageOfL,
  SomeMessage(..),
  pattern MkSomeMessage,
  IdeResult,
  LSP.DiagnosticSeverity(..),
  DiagnosticStore,
  ideErrorText,
  ideErrorWithSource,
  ideErrorFromLspDiag,
  diagnosticCode,
  diagnosticCodeDescription,
  prettyDiagnostics,
  prettyDiagnostic,
  IdeResultNoDiagnosticsEarlyCutoff,
  attachedReason,
  ) where

import           Control.DeepSeq
import           Control.Lens
import qualified Data.Aeson                     as JSON
import qualified Data.Aeson.Lens                as JSON
import           Data.ByteString                (ByteString)
import           Data.Maybe                     as Maybe
import qualified Data.Text                      as T
import           LSP.Core.Types.Location
import           GHC.Generics
import           Language.LSP.Diagnostics
import           Language.LSP.Protocol.Lens     (data_)
import           Language.LSP.Protocol.Types    as LSP
import           Prettyprinter
import           Type.Reflection
import           System.FilePath                (takeFileName)


-- | The result of an IDE operation. Warnings and errors are in the Diagnostic,
--   and a value is in the Maybe. For operations that throw an error you
--   expect a non-empty list of diagnostics, at least one of which is an error,
--   and a Nothing. For operations that succeed you expect perhaps some warnings
--   and a Just. For operations that depend on other failing operations you may
--   get empty diagnostics and a Nothing, to indicate this phase throws no fresh
--   errors but still failed.
--
--   A rule on a file should only return diagnostics for that given file. It should
--   not propagate diagnostic errors through multiple phases.
type IdeResult v = ([FileDiagnostic], Maybe v)

-- | an IdeResult with a fingerprint
type IdeResultNoDiagnosticsEarlyCutoff  v = (Maybe ByteString, Maybe v)

-- | A stable diagnostic code, as the 'LSP._code' of a diagnostic. Every
-- diagnostic this server reports has one, so that tooling never has to match on
-- message text. For what a code promises, see
-- 'L4.TypeCheck.Types.checkErrorCode'; the list is in
-- @jl4-lsp/DIAGNOSTIC-CODES.md@.
diagnosticCode :: T.Text -> Maybe (Int32 |? T.Text)
diagnosticCode = Just . InR

-- | Where a code is documented, as the 'LSP._codeDescription' of a diagnostic.
-- One formula for every code and no table: a code with no entry of its own on
-- the page still links to the page. An entry takes a code by an explicit anchor
-- in @doc/reference/errors/README.md@.
diagnosticCodeDescription :: T.Text -> Maybe CodeDescription
diagnosticCodeDescription slug = Just CodeDescription
  { _href = Uri ("https://legalese.com/l4/reference/errors#" <> T.replace "/" "-" slug) }

-- | Produce a 'FileDiagnostic' for the given 'NormalizedFilePath'
-- with an error message and its stable code ('diagnosticCode').
ideErrorText :: T.Text -> NormalizedUri -> T.Text -> FileDiagnostic
ideErrorText code nfp msg =
  ideErrorWithSource code (Just "compiler") (Just DiagnosticSeverity_Error) nfp msg

-- | Create a 'FileDiagnostic' from an existing 'LSP.Diagnostic' for a
-- specific 'NormalizedFilePath'.
-- The optional 'MsgEnvelope GhcMessage' is the original error message
-- that was used for creating the 'LSP.Diagnostic'.
-- It is included here, to allow downstream consumers, such as HLS plugins,
-- to provide LSP features based on the structured error messages.
-- Additionally, if available, we insert the ghc error code into the
-- 'LSP.Diagnostic'. These error codes are used in https://errors.haskell.org/
-- to provide documentation and explanations for error messages.
ideErrorFromLspDiag
  :: LSP.Diagnostic
  -> NormalizedUri
  -> FileDiagnostic
ideErrorFromLspDiag lspDiag fdFilePath =
  let fdShouldShowDiagnostic = ShowDiag
      fdLspDiagnostic =
        lspDiag
      fdOriginalSource = NoMessage
  in
  FileDiagnostic {..}

attachedReason :: Traversal' Diagnostic (Maybe JSON.Value)
attachedReason = data_ . non (JSON.object []) . JSON.atKey "attachedReason"

ideErrorWithSource
  :: T.Text
  -> Maybe T.Text
  -> Maybe DiagnosticSeverity
  -> NormalizedUri
  -> T.Text
  -> FileDiagnostic
ideErrorWithSource code source sev fdFilePath msg =
  let lspDiagnostic =
        LSP.Diagnostic {
          _range = noRange,
          _severity = sev,
          _code = diagnosticCode code,
          _source = source,
          _message = msg,
          _relatedInformation = Nothing,
          _tags = Nothing,
          _codeDescription = diagnosticCodeDescription code,
          _data_ = Nothing
        }
  in
  ideErrorFromLspDiag lspDiagnostic fdFilePath

-- | Defines whether a particular diagnostic should be reported
--   back to the user.
--
--   One important use case is "missing signature" code lenses,
--   for which we need to enable the corresponding warning during
--   type checking. However, we do not want to show the warning
--   unless the programmer asks for it (#261).
data ShowDiagnostic
    = ShowDiag  -- ^ Report back to the user
    | HideDiag  -- ^ Hide from user
    deriving (Eq, Ord, Show)

instance NFData ShowDiagnostic where
    rnf = rwhnf

-- | Human readable diagnostics for a specific file.
--
--   This type packages a pretty printed, human readable error message
--   along with the related source location so that we can display the error
--   on either the console or in the IDE at the right source location.
--
--   It also optionally keeps a structured diagnostic message GhcMessage in
--   StructuredMessage.
--
data FileDiagnostic = FileDiagnostic
  { fdFilePath             :: NormalizedUri
  , fdShouldShowDiagnostic :: ShowDiagnostic
  , fdLspDiagnostic        :: Diagnostic
  , fdOriginalSource       :: SomeMessage
  }
  deriving (Eq, Ord, Show, Generic)

instance NFData FileDiagnostic

data SomeMessage
  = NoMessage
  | SomeMessage NfDynamic
  deriving stock (Eq, Ord, Show, Generic)

pattern MkSomeMessage :: (Typeable a, NFData a) => a -> SomeMessage
pattern MkSomeMessage a <- SomeMessage (fromNfDynamic -> Just a) where
  MkSomeMessage a = SomeMessage (toNfDyn a)

instance NFData SomeMessage

data NfDynamic where
  MkNfDynamic :: forall a. (NFData a) => TypeRep a -> a -> NfDynamic

instance NFData NfDynamic where
  rnf (MkNfDynamic t a) = rnf t `seq` rnf a

instance Show NfDynamic where
  show (MkNfDynamic t _) = "MkNfDyn <<<" <> show t <> ">>>"

instance Eq NfDynamic where
  (MkNfDynamic x _) == (MkNfDynamic y _) = SomeTypeRep x == SomeTypeRep y

instance Ord NfDynamic where
  compare (MkNfDynamic x _a) (MkNfDynamic y _b) = compare (SomeTypeRep x) (SomeTypeRep y)

messageOfL :: forall a. (NFData a, Typeable a) => Lens' FileDiagnostic (Maybe a)
messageOfL = lens (\fd -> case fdOriginalSource fd of
      NoMessage -> Nothing
      SomeMessage nfDyn -> fromNfDynamic @a nfDyn
    )
    (\fd b -> fd { fdOriginalSource = case b of
        Nothing -> NoMessage
        Just msg -> SomeMessage $ toNfDyn msg })

-- | Converts an arbitrary value into an object of type 'NfDynamic'.
--
-- The type of the object must be an instance of 'Typeable' and 'NFData', which
-- ensures that only monomorphically-typed objects may be converted to
-- 'NfDynamic'.  To convert a polymorphic object into 'NfDynamic', give it
-- a monomorphic type signature.  For example:
--
-- >    toDyn (id :: Int -> Int)
--
toNfDyn :: (NFData a, Typeable a) => a -> NfDynamic
toNfDyn v = MkNfDynamic typeRep v

-- | Converts a 'NfDynamic' object back into an ordinary Haskell value of
-- the correct type.
fromNfDynamic
        :: forall a. Typeable a
        => NfDynamic    -- ^ the dynamically-typed object
        -> Maybe a      -- ^ returns: @'Just' a@, if the dynamically-typed
                        -- object has the correct type (and @a@ is its value),
                        -- or 'Nothing' otherwise.
fromNfDynamic (MkNfDynamic t v)
  | Just HRefl <- t `eqTypeRep` rep = Just v
  | otherwise                       = Nothing
  where rep = typeRep :: TypeRep a

prettyRange :: Range -> Doc a
prettyRange Range{..} = f _start <> "-" <> f _end
    where f Position{..} = pretty (show $ _line+1) <> colon <> pretty (show $ _character+1)


prettyDiagnostics :: [FileDiagnostic] -> Doc a
prettyDiagnostics = vcat . map prettyDiagnostic

-- | Extract just the filename from a NormalizedUri for display purposes.
-- This ensures consistent output across platforms by removing absolute path prefixes.
uriFileName :: NormalizedUri -> T.Text
uriFileName nuri =
    let uri = fromNormalizedUri nuri
    in case uriToFilePath' uri of
        Just fp -> T.pack (takeFileName fp)
        Nothing -> case T.stripPrefix "file://" (uri.getUri) of
            Just path -> T.pack (takeFileName (T.unpack path))
            Nothing -> uri.getUri

prettyDiagnostic :: FileDiagnostic -> Doc a
prettyDiagnostic FileDiagnostic { fdFilePath, fdShouldShowDiagnostic, fdLspDiagnostic = LSP.Diagnostic{..} } =
    hang 2 $ vcat
        [ slabel_ "File:    " $ pretty (uriFileName fdFilePath)
        , slabel_ "Hidden:  " $ if fdShouldShowDiagnostic == ShowDiag then "no" else "yes"
        , slabel_ "Range:   " $ prettyRange _range
        , slabel_ "Source:  " $ pretty _source
        , slabel_ "Severity:" $ pretty $ show sev
        , slabel_ "Code:    " $ case _code of
                                  Just (InR text) -> pretty text
                                  Just (InL i)    -> pretty i
                                  Nothing         -> "<none>"
        , slabel_ "Message: " $ pretty _message
        ]
    where
        sev = fromMaybe LSP.DiagnosticSeverity_Error _severity

-- | Label a document.
slabel_ :: String -> Doc a -> Doc a
slabel_ t d = nest 2 $ sep [pretty t, d]

makeLensesWith
    (lensRules & lensField .~ mappingNamer (pure . (++ "L")))
    ''FileDiagnostic
