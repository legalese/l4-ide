{-# LANGUAGE UnboxedSums, MagicHash #-}
module Sums where
f :: (# Int | Bool #) -> Int
f (# i | #) = i
f (# | b #) = if b then 1 else 0
