-- | The community @l4@: the command line of "L4.Cli.Main" with nothing added
-- to it. An executable that adds commands is another @main@ in another
-- package; see "L4.Cli.Extensions".
module Main (main) where

import L4.Cli.Extensions (noExtensions)
import L4.Cli.Main (mainWith)

main :: IO ()
main = mainWith noExtensions
