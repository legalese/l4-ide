{-# LANGUAGE UnboxedSums #-}
module Main where
data Plot = Plot { tenure :: (# () | () #) } deriving Show
main :: IO ()
main = print (Plot (# () | #))
