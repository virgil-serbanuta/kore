{- |
Copyright   : (c) Runtime Verification, 2019
License     : NCSA

-}
module Kore.Internal.OrPredicate
    ( OrPredicate
    , fromPredicates
    , fromPredicate
    , bottom
    , top
    , isFalse
    , isTrue
    , toPredicate
    , eliminateSimplified
    ) where

import qualified Data.Foldable as Foldable

import           Kore.Internal.MultiOr
                 ( MultiOr )
import qualified Kore.Internal.MultiOr as MultiOr
import           Kore.Internal.Predicate
                 ( Predicate )
import qualified Kore.Internal.Predicate as Predicate
import           Kore.Internal.TermLike hiding
                 ( eliminateSimplified )
import qualified Kore.Predicate.Predicate as Syntax
                 ( Predicate )
import qualified Kore.Predicate.Predicate as Syntax.Predicate
import           Kore.TopBottom
                 ( TopBottom (..) )
import           Kore.Unparser


{-| The disjunction of 'Predicate'.
-}
type OrPredicate variable = MultiOr (Predicate variable)

{- | A "disjunction" of one 'Predicate'.
 -}
fromPredicate
    :: Ord variable
    => Predicate variable
    -> OrPredicate variable
fromPredicate = MultiOr.singleton

{- | Disjoin a collection of predicates.
 -}
fromPredicates
    :: (Foldable f, Ord variable)
    => f (Predicate variable)
    -> OrPredicate variable
fromPredicates = MultiOr.make . Foldable.toList

{- | @\\bottom@

@
'isFalse' bottom == True
@

 -}
bottom :: Ord variable => OrPredicate variable
bottom = fromPredicates []

{- | @\\top@

@
'isTrue' top == True
@

 -}
top :: (Ord variable, SortedVariable variable) => OrPredicate variable
top = fromPredicate Predicate.top

{-| 'isFalse' checks if the 'OrPredicate' is composed only of bottom items.
-}
isFalse :: Ord variable => OrPredicate variable -> Bool
isFalse = isBottom

{-| 'isTrue' checks if the 'OrPredicate' has a single top pattern.
-}
isTrue :: Ord variable => OrPredicate variable -> Bool
isTrue = isTop

{-| Transforms an 'Predicate' into a 'Predicate.Predicate'. -}
toPredicate
    ::  ( SortedVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        )
    => MultiOr (Syntax.Predicate variable) -> Syntax.Predicate variable
toPredicate multiOr =
    Syntax.Predicate.makeMultipleOrPredicate (MultiOr.extractPatterns multiOr)

{-|'eliminateSimplified' replaces all SimplifiedF terms with their children
in an OrPredicate.
-}
eliminateSimplified
    :: Ord variable
    => OrPredicate variable
    -> OrPredicate variable
eliminateSimplified = fmap Predicate.eliminateSimplified
