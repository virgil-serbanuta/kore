{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

Representation of program configurations as conditional patterns.
-}
module Kore.Internal.Pattern
    ( Pattern
    , fromPredicate
    , fromPredicateSorted
    , toPredicate
    , bottom
    , bottomOf
    , isBottom
    , isTop
    , eliminateSimplified
    , Kore.Internal.Pattern.mapVariables
    , splitTerm
    , toTermLike
    , top
    , topOf
    , fromTermLike
    , Kore.Internal.Pattern.freeVariables
    , Kore.Internal.Pattern.freeElementVariables
    -- * Re-exports
    , Conditional (..)
    , Conditional.andCondition
    , Conditional.withCondition
    , Conditional.withoutTerm
    , Predicate
    ) where

import GHC.Stack
       ( HasCallStack )

import           Kore.Attribute.Pattern.FreeVariables
                 ( FreeVariables, getFreeElementVariables )
import           Kore.Internal.Conditional
                 ( Conditional (..) )
import qualified Kore.Internal.Conditional as Conditional
import           Kore.Internal.Predicate
                 ( Predicate )
import           Kore.Internal.TermLike
                 ( ElementVariable, Sort, SortedVariable, TermLike, mkAnd,
                 mkBottom, mkBottom_, mkTop, mkTop_, termLikeSort )
import qualified Kore.Internal.TermLike as TermLike
import qualified Kore.Predicate.Predicate as Syntax
                 ( Predicate )
import qualified Kore.Predicate.Predicate as Syntax.Predicate
import           Kore.TopBottom
                 ( TopBottom (..) )
import qualified Kore.Unification.Substitution as Substitution
import           Kore.Unparser

{- | The conjunction of a pattern, predicate, and substitution.

The form of @Pattern@ is intended to be a convenient representation of a
program configuration for Kore execution.

 -}
type Pattern variable = Conditional variable (TermLike variable)

fromPredicate
    :: (Ord variable, SortedVariable variable)
    => Predicate variable
    -> Pattern variable
fromPredicate = (<$) mkTop_

fromPredicateSorted
    :: (Ord variable, SortedVariable variable)
    => Sort
    -> Predicate variable
    -> Pattern variable
fromPredicateSorted sort = (<$) (mkTop sort)

freeVariables
    :: Ord variable
    => Pattern variable
    -> FreeVariables variable
freeVariables = Conditional.freeVariables TermLike.freeVariables

freeElementVariables
    :: Ord variable
    => Pattern variable
    -> [ElementVariable variable]
freeElementVariables =
    getFreeElementVariables . Kore.Internal.Pattern.freeVariables

{-|'mapVariables' transforms all variables, including the quantified ones,
in an Pattern.
-}
mapVariables
    :: (Ord variableFrom, Ord variableTo)
    => (variableFrom -> variableTo)
    -> Pattern variableFrom
    -> Pattern variableTo
mapVariables
    variableMapper
    Conditional { term, predicate, substitution }
  =
    Conditional
        { term = TermLike.mapVariables variableMapper term
        , predicate = Syntax.Predicate.mapVariables variableMapper predicate
        , substitution =
            Substitution.mapVariables variableMapper substitution
        }

{-|'eliminateSimplified' replaces all SimplifiedF terms with their children
in an Pattern.
-}
eliminateSimplified
    :: Ord variable
    => Pattern variable
    -> Pattern variable
eliminateSimplified
    Conditional { term, predicate, substitution }
  = Conditional
        { term = TermLike.eliminateSimplified term
        , predicate = Syntax.Predicate.eliminateSimplified predicate
        , substitution = Substitution.eliminateSimplified substitution
        }

{- | Convert an 'Pattern' to an ordinary 'TermLike'.

Conversion relies on the interpretation of 'Pattern' as a conjunction of
patterns. Conversion erases the distinction between terms, predicates, and
substitutions; this function should be used with care where that distinction is
important.

 -}
toTermLike
    ::  forall variable.
        ( SortedVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        , HasCallStack
        )
    => Pattern variable -> TermLike variable
toTermLike Conditional { term, predicate, substitution } =
    simpleAnd
        (simpleAnd term predicate)
        (Syntax.Predicate.fromSubstitution substitution)
  where
    -- TODO: Most likely I defined this somewhere.
    simpleAnd
        :: TermLike variable
        -> Syntax.Predicate variable
        -> TermLike variable
    simpleAnd pattern' predicate'
      | isTop predicate'    = pattern'
      | isBottom predicate' = mkBottom sort
      | isTop pattern'      = predicateTermLike
      | isBottom pattern'   = pattern'
      | otherwise           = mkAnd pattern' predicateTermLike
      where
        predicateTermLike = Syntax.Predicate.fromPredicate sort predicate'
        sort = termLikeSort pattern'

{-|'bottom' is an expanded pattern that has a bottom condition and that
should become Bottom when transformed to a ML pattern.
-}
bottom :: (Ord variable, SortedVariable variable) => Pattern variable
bottom =
    Conditional
        { term      = mkBottom_
        , predicate = Syntax.Predicate.makeFalsePredicate
        , substitution = mempty
        }

{- | An 'Pattern' where the 'term' is 'Bottom' of the given 'Sort'.

The 'predicate' is set to 'makeFalsePredicate'.

 -}
bottomOf :: (Ord variable, SortedVariable variable) => Sort -> Pattern variable
bottomOf resultSort =
    Conditional
        { term      = mkBottom resultSort
        , predicate = Syntax.Predicate.makeFalsePredicate
        , substitution = mempty
        }

{-|'top' is an expanded pattern that has a top condition and that
should become Top when transformed to a ML pattern.
-}
top :: (Ord variable, SortedVariable variable) => Pattern variable
top =
    Conditional
        { term      = mkTop_
        , predicate = Syntax.Predicate.makeTruePredicate
        , substitution = mempty
        }

{- | An 'Pattern' where the 'term' is 'Top' of the given 'Sort'.
 -}
topOf :: (Ord variable, SortedVariable variable) => Sort -> Pattern variable
topOf resultSort =
    Conditional
        { term      = mkTop resultSort
        , predicate = Syntax.Predicate.makeTruePredicate
        , substitution = mempty
        }

{- | Construct an 'Pattern' from a 'TermLike'.

The resulting @Pattern@ has a true predicate and an empty
substitution, unless it is trivially 'Bottom'.

See also: 'makeTruePredicate', 'pure'

 -}
fromTermLike
    :: (Ord variable, SortedVariable variable)
    => TermLike variable
    -> Pattern variable
fromTermLike term
  | isBottom term = bottom
  | otherwise =
    Conditional
        { term
        , predicate = Syntax.Predicate.makeTruePredicate
        , substitution = mempty
        }

toPredicate
    ::  ( SortedVariable variable
        , Ord variable
        , Show variable
        , Unparse variable
        )
    => Pattern variable
    -> Syntax.Predicate variable
toPredicate = Conditional.toPredicate

splitTerm :: Pattern variable -> (TermLike variable, Predicate variable)
splitTerm = Conditional.splitTerm
