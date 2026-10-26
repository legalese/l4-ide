-- | What @l4 deploy@ uploads, and what each file is called in the zip.
--
-- The service keeps the folder structure of the zip, so the zip keeps the
-- folders too. Each file is named by its path below the folder that every
-- collected file shares, with @/@ between the parts; when they all sit in one
-- folder that is the plain file name.
--
-- The service looks an @IMPORT@ up in two places only: beside the importing
-- file and at the top of the zip (the folder every file shares).
-- @l4@ looks in more places than that (@JL4_LIBRARY_PATH@, the per-user library
-- folder), so a library it found in some other folder of the project would be
-- uploaded under that folder, would be found by @l4@, and would not be found by
-- the service: the deploy says it is ready and every call fails.
-- So the plan checks, for each @IMPORT@ line, that the file it resolved to ends
-- up in one of those two places, and refuses the deploy when it does not
-- ('UnreachableImport').
-- Every line is judged, whatever it is written as: this version of @l4@ and the
-- service both read a name written with a @/@ (@IMPORT `lib\/shared`@) as the
-- bare name of its last part (@shared@), so such a line is looked up in the same
-- two places as a bare one (measured 2026-10-26: @l4 check@ answers "I could not
-- find a module with this name: helper" for @IMPORT `sub\/helper`@ with
-- @sub\/helper.l4@ in place, and the service logs "Resolving import: zdefs" for
-- @IMPORT `lib\/zdefs`@).
-- A version of l4 with path imports would need this rule revisited.
--
-- The service does not find a file beside its importer when the first folder of
-- the file's path in the zip has, in its name, a space, a letter outside A to Z,
-- or one of @# ' + ( ) % , = \@ & ! $ ; [ ]@.
-- The cause is in the resolver the service shares with the language server:
-- the candidate beside the importer is a relative path, and a relative path
-- cannot be spelled in a @file:@ URI that reads back, because the part before
-- its first @\/@ lands in the URI's authority, which is read back without
-- un-escaping (@roundTrippingFileUri@).
-- That is a residual of the fix for smucclaw\/l4-ide#971, which is closed, and
-- no issue tracks it yet.
-- Measured 2026-10-26 with hand-built zips on the service of this branch: a
-- bundle with the folder called @a@, @my-dir_2.x@, @v1.2@ or @a~b@ answers; with
-- the folder called @my dir@, @dossier é@, a Hebrew name, @a#b@ or @a'b@ it does
-- not (the deploy says "ready", every call answers "zmark is not in scope"; the
-- as-built note, @specs\/as-built\/import-resolution.md@, lists the other
-- characters).
-- Only the first folder of the path decides: with @ok\/my dir@ and with
-- @ok\/dossier é@ the service answers, because the escape is not in the first
-- part.
-- A file at the top of the zip is found whatever its importer's folder is
-- called, so only the folders below the top matter.
-- Until the service finds those files, the plan refuses an imported file when a
-- folder of its path has a character other than ASCII letters, digits, @.@, @-@
-- and @_@ in its name ('UnsafeFolder').
-- That stops every name measured to fail, and it judges every folder of the
-- path, not only the first.
-- So it also stops a few names the service would find: @ok\/my dir@, because
-- only the first folder decides there, and @a~b@, which answers.
-- A file at the top whose own name has a space or such a letter is not found
-- either (the same cause; one in a folder is: @a\/my mod.l4@ answers); the plan
-- does not judge it.
--
-- Both checks assume a service that looks a bare @IMPORT@ up at the top of the
-- upload (@bundleRoot@ in @jl4-service\/src\/Backend\/Jl4.hs@).
-- A service built before the commit that makes the bundle root the top of the
-- upload looks a bare @IMPORT@ up from the folder of the first file of the
-- upload in alphabetical order, not at the top, when it compiles the bundle and
-- answers a call on the direct path; a call on the wrapper path (a request with
-- a @{}@ in an input) looks from the folder of the function's own file instead
-- (see @jl4-service\/test\/BundleRootSpec.hs@).
-- A project that the old flat upload deployed and that worked (@a\/main.l4@
-- importing @defs@, with @defs.l4@ at the top, found through
-- @JL4_LIBRARY_PATH@) is uploaded now as @a\/main.l4@ and @defs.l4@; such an old
-- service deploys that as "ready", and every call answers "zmark is not in
-- scope" (measured by a reviewer, 2026-10-26).
-- The default target of @l4 deploy@ is Legalese Cloud (@L4.Cli.Cloud@).
-- Nothing here or in @L4.Cli.Deploy@ checks the version of the service.
-- Whether the service has to be released before this tool is not decided.
--
-- The /project root/ bounds the upload: a collected file outside it stops the
-- deploy ('OutsideRoot'). Nothing is skipped, flattened or renamed to make a
-- deploy go through. The exceptions are the standard library: a module that has
-- no file (the copy built into @l4@), and a file whose bytes are those of the
-- built-in copy of the module of its name ('leaveOutBuiltIn'). The service has
-- exactly that module built in, so uploading the file adds nothing: it is not
-- uploaded, not judged for where it sits, and does not count as outside the root.
-- That bound is new with keeping folders: the flat upload before it
-- (@jl4\/app\/L4\/Cli\/Deploy.hs@ at 977691b36) had no project root and no check
-- of where a collected file lay, so it uploaded a file from a folder outside the
-- project, such as a shared library found through @JL4_LIBRARY_PATH@, under its
-- plain file name. A project that did that is stopped now.
--
-- Nothing here touches the network, the terminal or the typechecker, so the
-- cases are tested directly (@tests-cli/CliTest/Deploy.hs@).
module L4.Cli.DeployPlan
  ( PlanError(..)
  , Unreachable(..)
  , Unfindable(..)
  , ImportEdge(..)
  , Hints(..)
  , renderPlanError
  , projectRoot
  , leaveOutBuiltIn
  , planBundle
  , distinctNames
  , readBundle
  ) where

import Base.Text (Text)
import qualified Base.Text as Text
import Control.Exception (IOException, try)
import Control.Monad (guard)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.Char (isAscii, isAlphaNum, toLower)
import Data.List (find, isPrefixOf, nub, nubBy)
import System.FilePath
  ( isAbsolute
  , joinPath
  , splitDirectories
  , splitDrive
  , takeBaseName
  , takeExtension
  )
import System.IO.Error (ioeGetErrorType)

-- | Why a bundle cannot be made.
data PlanError
  = NotAFile Text FilePath
    -- ^ A module (named as the typechecker knows it) whose file path is not
    -- absolute, so there is nothing to read it from.
  | OutsideRoot FilePath [FilePath]
    -- ^ The project root, and the files that lie outside it.
  | UnreachableImport [Unreachable]
    -- ^ @IMPORT@s whose file would be uploaded where the service does not look
    -- for it.
  | UnsafeFolder [Unfindable]
    -- ^ Imported files in a folder whose name the service may not be able to
    -- look into.
  | SameName FilePath FilePath FilePath
    -- ^ Two files that would both be stored under one name.
  deriving stock (Eq, Show)

-- | One bare @IMPORT@ that the service would not resolve.
data Unreachable = Unreachable
  { importerName :: FilePath
    -- ^ The importing file, as it is named in the zip.
  , written :: Text
    -- ^ The module name as the importing file writes it.
  , importedName :: FilePath
    -- ^ The file it resolved to, as it is named in the zip.
  , importedFile :: FilePath
    -- ^ The same file on this machine.
  }
  deriving stock (Eq, Show)

-- | An imported file that the service may not find beside its importer,
-- because of the name of its folder.
data Unfindable = Unfindable
  { fileName :: FilePath
    -- ^ The file, as it is named in the zip.
  , folderName :: FilePath
    -- ^ The folder part of that name.
  , onDisk :: FilePath
    -- ^ The same file on this machine.
  }
  deriving stock (Eq, Show)

-- | What the messages need to know about the machine the deploy ran on, which
-- decides what advice is true.
newtype Hints = Hints
  { libraryPathSet :: Bool
    -- ^ Whether @JL4_LIBRARY_PATH@ is set in the environment of the deploy.
  }
  deriving stock (Eq, Show)

-- | One @IMPORT@ line of a collected file, after @l4@ resolved it to a file.
data ImportEdge = ImportEdge
  { importer :: FilePath
    -- ^ The file the line is in.
  , written :: Text
    -- ^ The module name as the line writes it.
  , imported :: FilePath
    -- ^ The file the name resolved to.
  }
  deriving stock (Eq, Show)

-- | The message for a refusal. The 'Hints' choose which advice is true on this
-- machine.
renderPlanError :: Hints -> PlanError -> Text
renderPlanError hints = \case
  NotAFile m p ->
    "Cannot upload " <> m <> ": its file path " <> Text.pack p <> " is not absolute."
  OutsideRoot root outside ->
    Text.unlines $
      [ case outside of
          [_] -> "This file lies outside the project folder " <> Text.pack root <> ", so it cannot be uploaded:"
          _ -> "These files lie outside the project folder " <> Text.pack root <> ", so they cannot be uploaded:"
      ]
      <> [ "  " <> Text.pack f | f <- outside ]
      <> [ "The project folder is the folder l4 was run from when the file being deployed is inside it and that folder is not the top of a drive; otherwise it is the file's own folder."
         , "To deploy a library that lives elsewhere, put it inside the project folder, beside the file that imports it."
         ]
      <> libraryAdvice hints
      <> [ line
         | hints.libraryPathSet
         , line <-
             [ "JL4_LIBRARY_PATH is set, so l4 reads the standard library from files on disk instead of the copy built into l4."
             , "A standard library file that is exactly the copy built into l4 is left out of the upload and stops nothing, so a file listed above is not a standard library file, or differs from the built-in copy."
             , "If one of those files is a standard library file, unset JL4_LIBRARY_PATH and try again: the deployed service has the standard library built in and does not need it uploaded."
             ]
         ]
  UnreachableImport us ->
    Text.unlines $
      [ case us of
          [_] -> "The deployed service would not find a library this file imports:"
          _ -> "The deployed service would not find libraries these files import:"
      ]
      <> [ "  " <> Text.pack u.importerName <> " imports " <> u.written <> ", which would be uploaded as "
             <> Text.pack u.importedName <> " (from " <> Text.pack u.importedFile <> "), in the folder "
             <> Text.pack (folderOf u.importedName)
         | u <- us ]
      <> [ "The deployed service looks an IMPORT up only beside the file that imports it and at the top of the upload (the folder that holds all the uploaded files)."
         , "It looks nowhere else, so the deploy would say it is ready and every call would then fail."
         , "Put each library beside the file that imports it, and deploy again."
         ]
      <> libraryAdvice hints
  UnsafeFolder us ->
    Text.unlines $
      [ case us of
          [_] -> "The deployed service may not find a file that is imported, because of the name of the folder it is in:"
          _ -> "The deployed service may not find files that are imported, because of the names of the folders they are in:"
      ]
      <> [ "  " <> Text.pack u.fileName <> " (from " <> Text.pack u.onDisk <> "), in the folder " <> Text.pack u.folderName
         | u <- us ]
      <> [ "The deployed service does not find a file beside the file that imports it when the first folder of the file's path in the upload has a space, a letter outside A to Z, or one of # ' + ( ) % , = @ & ! $ ; [ ] in its name."
         , "The deploy would say it is ready, and every call would then fail."
         , "l4 stops at any character other than a letter from A to Z, a digit, '.', '-' or '_' in any folder of the path, not only the first, so it also stops a few names the service would find, for example ok/my dir and a~b."
         , "Rename the folder to use only letters, digits, '.', '-' and '_', and deploy again."
         ]
  SameName n a b ->
    "These files would both be stored as \"" <> Text.pack n <> "\" in the upload: "
      <> Text.pack a <> " and " <> Text.pack b <> "."

-- | What to do about a library that is not where the service looks, shared by
-- the two refusals about one.
-- @l4@ reads @JL4_LIBRARY_PATH@ before the folder of the importing file and the
-- per-user library folder after it, so a copy beside the importing file is used
-- in the second case and ignored in the first.
-- The variable is mentioned only when it is set: with it unset, the library came
-- from the project or the per-user library folder.
libraryAdvice :: Hints -> [Text]
libraryAdvice hints =
  [ "A deployed service reads only the files that are uploaded." ]
  <> [ if hints.libraryPathSet
         then "It does not read JL4_LIBRARY_PATH or the per-user library folder (jl4/libraries in $XDG_DATA_HOME, or in ~/.local/share), where l4 may have found a library."
         else "It does not read the per-user library folder (jl4/libraries in $XDG_DATA_HOME, or in ~/.local/share), where l4 may have found a library."
     ]
  <> [ "l4 reads a library from JL4_LIBRARY_PATH before it reads one beside the importing file, so with that variable set a copy in the project is not used: unset the variable, or move the file instead of copying it."
     | hints.libraryPathSet ]
  <> [ "A library from the per-user library folder is read after the one beside the importing file, so a copy there is enough." ]

-- | The folder part of a name in the zip.
folderOf :: FilePath -> FilePath
folderOf n = case break (== '/') (reverse n) of
  (_, '/' : rest) -> reverse rest
  _ -> ""

-- | A path taken apart for comparing: its drive (where there is one), and the
-- directories and file name below it. A drive letter is not case-sensitive,
-- and the typechecker and 'System.Directory.makeAbsolute' do not agree on its
-- case, so it is compared lower-cased.
data Loc = Loc
  { drive :: FilePath
  , key   :: String
  , segs  :: [String]
  }

-- | Split an absolute path, resolving @.@ and @..@ by the letters of the path
-- alone (no link is followed), so @\/a\/..\/b@ and @\/b@ are the same place.
locate :: FilePath -> Loc
locate p = Loc { drive = d, key = map toLower d, segs = reverse (foldl step [] (splitDirectories rest)) }
  where
    (d, rest) = splitDrive p
    step acc = \case
      "." -> acc
      ".." -> drop 1 acc
      s -> s : acc

render :: Loc -> FilePath
render l = joinPath (l.drive : l.segs)

-- | Whether @file@ is below the directory @dir@, by whole path segments:
-- @\/a\/b@ does not contain @\/a\/bc\/x.l4@.
inside :: Loc -> Loc -> Bool
inside dir file = dir.key == file.key && dir.segs `isPrefixOf` file.segs && length dir.segs < length file.segs

-- | The project root: the current folder if the file being deployed lies in
-- it, else that file's own folder. Both arguments are absolute.
--
-- The top of a drive (@\/@, @C:\\@) is never the project root: every file on
-- the drive lies in it, so it would bound nothing and the upload would carry
-- the names of the folders above the project.
projectRoot :: FilePath -> FilePath -> FilePath
projectRoot cwd entry
  | not (null cwdL.segs) && cwdL `inside` entryL = render cwdL
  | otherwise = render (entryL { segs = take (length entryL.segs - 1) entryL.segs })
  where
    cwdL = locate cwd
    entryL = locate entry

-- | Which files to upload, and under which name: the file being deployed
-- first, then its imports in the order given. A module with no file
-- (@Nothing@: the standard library built into @l4@) is left out.
--
-- Arguments: the project root, the file being deployed, each import as the
-- typechecker names it with its file, if it has one, and each @IMPORT@ line of
-- those files with the file it resolved to. Result: each file's name in the zip
-- and its path on disk.
--
-- Every line must resolve to a file that is uploaded beside the importing file
-- or at the top of the upload, where the service looks ('UnreachableImport').
-- A file that is then beside its importer in a folder whose name the service
-- may not be able to look into is refused too ('UnsafeFolder').
-- A line that names a file the plan does not upload is not judged: it can only
-- be one of the modules left out above.
planBundle :: FilePath -> FilePath -> [(Text, Maybe FilePath)] -> [ImportEdge] -> Either PlanError [(FilePath, FilePath)]
planBundle root entry imports edges = do
  rootL <- locate <$> absolute ("the project folder", root)
  files <- traverse absolute ((Text.pack entry, entry) : [ (m, p) | (m, Just p) <- imports ])
  let located = nubBy sameFile (map locate files)
  case [ render f | f <- located, not (rootL `inside` f) ] of
    [] -> pure ()
    outside -> Left (OutsideRoot (render rootL) outside)
  let dirs = [ take (length f.segs - 1) f.segs | f <- located ]
      shared = length (foldr1 commonPrefix dirs)
      -- A file's name in the zip, and the folder part of it.
      nameIn f = joinWith "/" (drop shared f.segs)
      folderIn f = take (length f.segs - shared - 1) (drop shared f.segs)
  case [ Unreachable { importerName = nameIn from, written = e.written, importedName = nameIn to, importedFile = render to }
       | e <- edges
       , Just from <- [lookupFile located (locate e.importer)]
       , Just to <- [lookupFile located (locate e.imported)]
       , not (null (folderIn to))
       , folderIn to /= folderIn from
       ] of
    [] -> pure ()
    us -> Left (UnreachableImport (nubBy (\a b -> (a.importerName, a.written, a.importedName) == (b.importerName, b.written, b.importedName)) us))
  -- Only the file looked up is judged, not the file that looks: the entry file's
  -- folder, or any importer's, does not matter to a lookup that ends at the top.
  case [ Unfindable { fileName = nameIn to, folderName = joinWith "/" (folderIn to), onDisk = render to }
       | e <- edges
       , Just _ <- [lookupFile located (locate e.importer)]
       , Just to <- [lookupFile located (locate e.imported)]
       , any unsafeSegment (folderIn to)
       ] of
    [] -> pure ()
    us -> Left (UnsafeFolder (nubBy (\a b -> a.fileName == b.fileName) us))
  distinctNames [ (nameIn f, render f) | f <- located ]
  where
    absolute (m, p)
      | isAbsolute p = Right p
      | otherwise = Left (NotAFile m p)
    sameFile a b = a.key == b.key && a.segs == b.segs
    lookupFile located l = find (sameFile l) located
    commonPrefix (a : as) (b : bs) | a == b = a : commonPrefix as bs
    commonPrefix _ _ = []
    joinWith sep = foldr1 (\a b -> a <> sep <> b)
    -- A name of a folder that the service is known to look into: letters from A
    -- to Z, digits, and '.', '-' and '_'. Anything else is refused, though the
    -- service was also seen to look into '~' and into a name whose first part is
    -- safe (see the header).
    unsafeSegment = not . all (\c -> isAscii c && (isAlphaNum c || c `elem` (".-_" :: String)))

-- | Leave out of the imports each file that is exactly the standard library
-- module of its name built into the service.
--
-- The service has that module built in, so uploading the file adds nothing: it
-- is not uploaded, is not judged for where it sits, and does not count as
-- outside the project root. A file of the same name whose bytes differ is a
-- project file like any other.
--
-- Arguments: the built-in modules by name (as bytes), the bytes of each file
-- that could be read, and the imports as 'planBundle' takes them. Result: the
-- imports with each such file turned into a module with no file, and the names
-- of the modules left out, in order, once each.
-- A file that could not be read is kept, and 'readBundle' says so later.
leaveOutBuiltIn
  :: (Text -> Maybe BS.ByteString)
  -> (FilePath -> Maybe BS.ByteString)
  -> [(Text, Maybe FilePath)]
  -> ([(Text, Maybe FilePath)], [Text])
leaveOutBuiltIn builtIn contents imports = (map fst classified, nub [ n | (_, Just n) <- classified ])
  where
    classified =
      [ case mf >>= sameAsBuiltIn of
          Just n -> ((m, Nothing), Just n)
          Nothing -> ((m, mf), Nothing)
      | (m, mf) <- imports ]
    sameAsBuiltIn f = do
      content <- contents f
      let name = Text.pack (takeBaseName f)
      guard (takeExtension f == ".l4" && builtIn name == Just content)
      pure name

-- | Refuse two files that would share a name in the zip. The names planned
-- above are paths below one folder, so they cannot clash and this is a guard
-- against a mistake in how they are made, not a case a project can reach.
distinctNames :: [(FilePath, FilePath)] -> Either PlanError [(FilePath, FilePath)]
distinctNames named = case [ SameName n a b | (i, (n, a)) <- indexed, (j, (m, b)) <- indexed, i < j, n == m ] of
  err : _ -> Left err
  [] -> Right named
  where
    indexed = zip [0 :: Int ..] named

-- | Read the planned files (each with its name in the zip). A file that
-- cannot be read stops the bundle, and the message names it.
readBundle :: [(FilePath, FilePath)] -> IO (Either Text [(FilePath, BSL.ByteString)])
readBundle = go
  where
    go [] = pure (Right [])
    go ((n, p) : rest) = try (BS.readFile p) >>= \case
      Left (e :: IOException) ->
        pure (Left ("Could not read " <> Text.pack p <> ": " <> Text.pack (show (ioeGetErrorType e)) <> "."))
      Right c -> fmap ((n, BSL.fromStrict c) :) <$> go rest
