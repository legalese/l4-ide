-- | Phase 1 milestone check: @parse (print (parse s)) == parse s@ on the AST,
-- for the canonical PROLEG fixtures. Run from the repo root.
module Main (main) where

import Control.Monad (unless)
import qualified Data.Text.IO as TIO
import System.Exit (exitFailure)

import L4.Proleg.Parser (parseProgram)
import L4.Proleg.Print (printProgram)
import L4.Proleg.Syntax (Program (..))

fixtures :: [FilePath]
fixtures =
  [ "jl4-proleg/examples/lease.pl"
  , "jl4-proleg/examples/minor-duress.pl"
  ]

clauseCount :: Program -> Int
clauseCount (Program cs) = length cs

main :: IO ()
main = do
  results <- mapM check fixtures
  unless (and results) exitFailure

check :: FilePath -> IO Bool
check path = do
  src <- TIO.readFile path
  case parseProgram src of
    Left e -> do
      putStrLn ("FAIL parse " ++ path ++ ": " ++ e)
      pure False
    Right prog1 ->
      case parseProgram (printProgram prog1) of
        Left e -> do
          putStrLn ("FAIL reparse-of-print " ++ path ++ ": " ++ e)
          pure False
        Right prog2
          | prog1 == prog2 -> do
              putStrLn
                ( "PASS " ++ path ++ " ("
                    ++ show (clauseCount prog1)
                    ++ " clauses, print/parse roundtrip stable)"
                )
              pure True
          | otherwise -> do
              putStrLn ("FAIL roundtrip mismatch " ++ path)
              pure False
