{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

Representation of program configurations as conditional patterns.
-}
module Kore.Internal.Pattern
    ( Pattern
    , coerceSort
    , patternSort
    , fromCondition
    , fromConditionSorted
    , bottom
    , bottomOf
    , isBottom
    , isTop
    , Kore.Internal.Pattern.mapVariables
    , splitTerm
    , toTermLike
    , top
    , topOf
    , fromTermLike
    , fromTermLikeUnsorted
    , Kore.Internal.Pattern.freeVariables
    , Kore.Internal.Pattern.freeElementVariables
    , isSimplified
    -- * Re-exports
    , Conditional (..)
    , Conditional.andCondition
    , Conditional.isPredicate
    , withCondition
    , Conditional.withoutTerm
    , Condition
    ) where

import GHC.Stack
    ( HasCallStack
    )

import Kore.Attribute.Pattern.FreeVariables
    ( FreeVariables
    , getFreeElementVariables
    )
import Kore.Internal.Condition
    ( Condition
    )
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Conditional
    ( Conditional (..)
    )
import qualified Kore.Internal.Conditional as Conditional
import Kore.Internal.Predicate
    ( Predicate
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.TermLike
    ( ElementVariable
    , InternalVariable
    , Sort
    , TermLike
    , mkAnd
    , mkBottom
    , mkBottom_
    , mkTop
    , mkTop_
    , termLikeSort
    )
import qualified Kore.Internal.TermLike as TermLike
import qualified Kore.Sort as Sort
    ( predicateSort
    )
import Kore.TopBottom
    ( TopBottom (..)
    )
import qualified Kore.Unification.Substitution as Substitution

{- | The conjunction of a pattern, predicate, and substitution.

The form of @Pattern@ is intended to be a convenient representation of a
program configuration for Kore execution.

 -}
type Pattern variable = Conditional variable (TermLike variable)

fromCondition
    :: InternalVariable variable
    => Condition variable
    -> Pattern variable
fromCondition = (<$) mkTop_

fromConditionSorted
    :: InternalVariable variable
    => Sort
    -> Condition variable
    -> Pattern variable
fromConditionSorted sort = (<$) (mkTop sort)

isSimplified :: Pattern variable -> Bool
isSimplified (splitTerm -> (t, p)) =
    TermLike.isSimplified t && Condition.isSimplified p

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
        , predicate = Predicate.mapVariables variableMapper predicate
        , substitution =
            Substitution.mapVariables variableMapper substitution
        }

{- | Convert an 'Pattern' to an ordinary 'TermLike'.

Conversion relies on the interpretation of 'Pattern' as a conjunction of
patterns. Conversion erases the distinction between terms, predicates, and
substitutions; this function should be used with care where that distinction is
important.

 -}
toTermLike
    ::  forall variable
    .  (InternalVariable variable, HasCallStack)
    => Pattern variable -> TermLike variable
toTermLike Conditional { term, predicate, substitution } =
    simpleAnd
        (simpleAnd term predicate)
        (Predicate.fromSubstitution substitution)
  where
    simpleAnd
        :: TermLike variable
        -> Predicate variable
        -> TermLike variable
    simpleAnd pattern' predicate'
      | isTop predicate'    = pattern'
      | isBottom predicate' = mkBottom sort
      | isTop pattern'      = predicateTermLike
      | isBottom pattern'   = pattern'
      | otherwise           = mkAnd pattern' predicateTermLike
      where
        predicateTermLike = Predicate.fromPredicate sort predicate'
        sort = termLikeSort pattern'

{-|'bottom' is an expanded pattern that has a bottom condition and that
should become Bottom when transformed to a ML pattern.
-}
bottom :: InternalVariable variable => Pattern variable
bottom =
    Conditional
        { term      = mkBottom_
        , predicate = Predicate.makeFalsePredicate_
        , substitution = mempty
        }

{- | An 'Pattern' where the 'term' is 'Bottom' of the given 'Sort'.

The 'predicate' is set to 'makeFalsePredicate_'.

 -}
bottomOf :: InternalVariable variable => Sort -> Pattern variable
bottomOf resultSort =
    Conditional
        { term      = mkBottom resultSort
        , predicate = Predicate.makeFalsePredicate_
        , substitution = mempty
        }

{-|'top' is an expanded pattern that has a top condition and that
should become Top when transformed to a ML pattern.
-}
top :: InternalVariable variable => Pattern variable
top =
    Conditional
        { term      = mkTop_
        , predicate = Predicate.makeTruePredicate_
        , substitution = mempty
        }

{- | An 'Pattern' where the 'term' is 'Top' of the given 'Sort'.
 -}
topOf :: InternalVariable variable => Sort -> Pattern variable
topOf resultSort =
    Conditional
        { term      = mkTop resultSort
        , predicate = Predicate.makeTruePredicate resultSort
        , substitution = mempty
        }

{- | Construct an 'Pattern' from a 'TermLike'.

The resulting @Pattern@ has a true predicate and an empty
substitution, unless it is trivially 'Bottom'.

See also: 'makeTruePredicate_', 'pure'

 -}
fromTermLike
    :: InternalVariable variable
    => TermLike variable
    -> Pattern variable
fromTermLike term
  | isBottom term = bottom
  | otherwise =
    Conditional
        { term
        , predicate = Predicate.makeTruePredicate (termLikeSort term)
        , substitution = mempty
        }

fromTermLikeUnsorted
    :: InternalVariable variable
    => TermLike variable
    -> Pattern variable
fromTermLikeUnsorted term
  | isBottom term = bottom
  | otherwise =
    Conditional
        { term
        , predicate = Predicate.makeTruePredicate_
        , substitution = mempty
        }

withCondition
    :: InternalVariable variable
    => TermLike variable
    -> Conditional variable ()
    -- ^ Condition
    -> Pattern variable
withCondition
    term
    Conditional
        { term = ()
        , predicate
        , substitution
        }
  = Conditional
    { term
    , predicate = Predicate.coerceSort (termLikeSort term) predicate
    , substitution
    }

splitTerm :: Pattern variable -> (TermLike variable, Condition variable)
splitTerm = Conditional.splitTerm

coerceSort
    :: (HasCallStack, InternalVariable variable)
    => Sort -> Pattern variable -> Pattern variable
coerceSort
    sort
    Conditional { term, predicate, substitution }
  =
    Conditional
        { term = TermLike.forceSort sort term
        -- Need to override this since a 'ceil' (say) over a predicate is that
        -- predicate with a different sort.
        , predicate = Predicate.coerceSort sort predicate
        , substitution
        }

patternSort :: Pattern variable -> Sort
patternSort Conditional {term, predicate} =
    if termSort == Sort.predicateSort then predicateSort else termSort
  where
    termSort = termLikeSort term
    predicateSort = Predicate.predicateSort predicate
