{-# LANGUAGE UnboxedSums, MagicHash #-}
module Main where

-- An anonymous, unboxed sum as a record field's type.
data Plot = Plot { owner :: String, tenure :: (# () | () | () #) }

describe :: Plot -> String
describe p = case tenure p of
  (# () | | #) -> "owner"
  (# | () | #) -> "tenant"
  (# | | () #) -> "lodger"

main :: IO ()
main = putStrLn (describe (Plot "Ann" (# | () | #)))
