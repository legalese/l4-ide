{-# LANGUAGE OverloadedStrings #-}
-- | The fixtures of @jl4\/tests-cli\/fixtures\/relative-import\/@, written out as
-- sources, so that the browser build's resolver can be run on the programs the
-- CLI is tested on. Shared by "PathImportVfsSpec" and "ApiImportContextSpec".
module PathImportFixtures
  ( rowsMain, rowsHelper, rowsMod, rowsNeighbour, rowsFiles
  , diamondTop, diamondX, diamondY, diamondCore, diamondFiles
  , identityTop, identityCore
  , backMain, backHelper, backMod, backFiles
  ) where

import Data.Text (Text)

import L4.API.VirtualFS (VFS, vfsFromList)


rowsMain, rowsHelper, rowsMod, rowsNeighbour :: Text
rowsMain = "IMPORT `../b/mod`\nIMPORT `./helper`\n\n`answer` MEANS modmarker + helpmarker\n\n#EVAL answer\n"
rowsHelper = "IMPORT prelude\n\nhelpmarker MEANS sum (LIST 10, 20)\n"
rowsMod = "IMPORT prelude\nIMPORT neighbour\n\nmodmarker MEANS sum (LIST 1, 2, 3) + neighbourmarker\n"
rowsNeighbour = "neighbourmarker MEANS 1000\n"

-- | @rows\/a\/main.l4@ is the document; the rest are the files it can reach.
-- @neighbour@ is at the top, because a bare name is found there.
rowsFiles :: VFS
rowsFiles = vfsFromList
  [ ("rows/a/helper.l4", rowsHelper)
  , ("rows/b/mod.l4", rowsMod)
  , ("neighbour.l4", rowsNeighbour)
  ]

diamondTop, diamondX, diamondY, diamondCore :: Text
diamondTop = "IMPORT `a/x`\nIMPORT `b/y`\n\ntopvalue MEANS xvalue + yvalue\n\n#EVAL topvalue\n"
diamondX = "IMPORT `../shared/core`\n\nxvalue MEANS corebad + 1\n"
diamondY = "IMPORT `../shared/core`\n\nyvalue MEANS corebad + 2\n"
diamondCore = "`corebad` MEANS 1 PLUS TRUE\n"

diamondFiles :: VFS
diamondFiles = vfsFromList
  [ ("a/x.l4", diamondX)
  , ("b/y.l4", diamondY)
  , ("shared/core.l4", diamondCore)
  ]

identityTop, identityCore :: Text
identityTop = "IMPORT `sub/../core`\nIMPORT core\n\ntwice MEANS coremarker + coremarker\n\n#EVAL twice\n"
identityCore = "coremarker MEANS 21\n"

backMain, backHelper, backMod :: Text
backMain = "IMPORT `./helper`\nIMPORT `../b/mod`\n\nanswer MEANS modmarker + helpmarker\n\n#EVAL answer\n"
backHelper = "helpmarker MEANS 10\n"
backMod = "IMPORT `../a/helper`\n\nmodmarker MEANS helpmarker + 1\n"


backFiles :: VFS
backFiles = vfsFromList [("a/helper.l4", backHelper), ("b/mod.l4", backMod)]
