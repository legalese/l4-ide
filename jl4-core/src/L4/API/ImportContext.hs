{-# LANGUAGE OverloadedStrings #-}
-- | What the host of the API tells it about the project: the files a document
-- can import, and where the document lives among them.
--
-- The browser build is a WebAssembly module that keeps this between calls. The
-- host sets it with @l4_set_files@ and @l4_set_document_path@ (see "L4.API"), and
-- every other export reads it when it starts. Files change when the project does;
-- the document's text changes at every keystroke, so the text is an argument of
-- each call and the files are not.
--
-- Nothing here is specific to WebAssembly, so that the whole of it can be tested
-- on a native build. The pure functions of "L4.API" take an 'ImportContext'
-- argument and do not read the shared one; only the foreign exports do.
--
-- @since 0.1
module L4.API.ImportContext
  ( ImportContext(..)
  , defaultImportContext
  , checkInContext
    -- * The context the foreign exports read
  , currentImportContext
  , setImportFiles
  , setImportDocumentPath
  ) where

import Base
import qualified Base.Text as Text
import System.IO.Unsafe (unsafePerformIO)

import L4.API.VirtualFS (TypeCheckWithDepsResult, VFS, checkWithImportsAt, emptyVFS)

-- | The files a document can import, and the document's own path among them.
data ImportContext = ImportContext
  { icFiles :: VFS
  , icDocumentPath :: Text
  }
  deriving stock (Eq, Show)

-- | No files, and the document at the top of them under the name it has always
-- had. Checking in this context is exactly what the API did before it had one.
defaultImportContext :: ImportContext
defaultImportContext = ImportContext
  { icFiles = emptyVFS
  , icDocumentPath = "main"
  }

-- | Type-check a document with import resolution in a context.
checkInContext :: ImportContext -> Text -> Either [Text] TypeCheckWithDepsResult
checkInContext ctx = checkWithImportsAt ctx.icFiles ctx.icDocumentPath

-- | The context the foreign exports read. It is set by the host and nothing else
-- writes it.
importContextRef :: IORef ImportContext
importContextRef = unsafePerformIO (newIORef defaultImportContext)
{-# NOINLINE importContextRef #-}

-- | The context as it is now.
currentImportContext :: IO ImportContext
currentImportContext = readIORef importContextRef

-- | Replace the files. The document's path is kept.
setImportFiles :: VFS -> IO ()
setImportFiles vfs = modifyIORef' importContextRef \ctx -> ctx { icFiles = vfs }

-- | Say where the document lives. The empty path is the document's path before
-- anything was set. The files are kept.
setImportDocumentPath :: Text -> IO ()
setImportDocumentPath path = modifyIORef' importContextRef \ctx ->
  ctx { icDocumentPath = if Text.null path then defaultImportContext.icDocumentPath else path }
