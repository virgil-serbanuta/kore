{-|
Module      : Kore.Step.Simplification.In
Description : Tools for In pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.In
    ( simplify
    ) where

import Kore.Internal.Condition as Condition
    ( Condition
    )
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeInPredicate
    )
import qualified Kore.Internal.Predicate as Predicate
    ( markSimplified
    )
import Kore.Internal.TermLike
import qualified Kore.Step.Simplification.Ceil as Ceil
    ( makeEvaluate
    , simplifyEvaluated
    )
import Kore.Step.Simplification.Simplify

{-|'simplify' simplifies an 'In' pattern with 'OrPattern'
children.

Right now this uses the following simplifications:

* bottom in a = bottom
* a in bottom = bottom
* top in a = ceil(a)
* a in top = ceil(a)

TODO(virgil): It does not have yet a special case for children with top terms.
-}
simplify
    :: (SimplifierVariable variable, MonadSimplify simplifier)
    => Condition variable
    -> In Sort (OrPattern variable)
    -> simplifier (Pattern variable)
simplify predicate In { inContainedChild = first, inContainingChild = second } =
    simplifyEvaluatedIn predicate first second

{- TODO (virgil): Preserve pattern sorts under simplification.

One way to preserve the required sort annotations is to make
'simplifyEvaluatedIn' take an argument of type

> CofreeF (In Sort) (Attribute.Pattern variable) (OrPattern variable)

instead of two 'OrPattern' arguments. The type of 'makeEvaluateIn' may
be changed analogously. The 'Attribute.Pattern' annotation will eventually cache
information besides the pattern sort, which will make it even more useful to
carry around.

-}
simplifyEvaluatedIn
    :: forall variable simplifier
    .  (SimplifierVariable variable, MonadSimplify simplifier)
    => Condition variable
    -> OrPattern variable
    -> OrPattern variable
    -> simplifier (Pattern variable)
simplifyEvaluatedIn predicate first second
  | OrPattern.isFalse first  = return Pattern.bottom
  | OrPattern.isFalse second = return Pattern.bottom

  | OrPattern.isTrue first =
    OrPattern.toPattern <$> Ceil.simplifyEvaluated predicate second
  | OrPattern.isTrue second =
    OrPattern.toPattern <$> Ceil.simplifyEvaluated predicate first

  | otherwise = do
    resultOr <- sequence (makeEvaluateIn predicate <$> first <*> second)
    -- Merge the or if needed, in order to allow its resimplification
    -- by the or simplifier.
    return (OrPattern.toPattern resultOr)

makeEvaluateIn
    :: (SimplifierVariable variable, MonadSimplify simplifier)
    => Condition variable
    -> Pattern variable
    -> Pattern variable
    -> simplifier (Pattern variable)
makeEvaluateIn predicate first second
  | Pattern.isTop first =
    OrPattern.toPattern <$> Ceil.makeEvaluate predicate second
  | Pattern.isTop second =
    OrPattern.toPattern <$> Ceil.makeEvaluate predicate first
  | Pattern.isBottom first || Pattern.isBottom second = return Pattern.bottom
  | otherwise = return $ makeEvaluateNonBoolIn first second

makeEvaluateNonBoolIn
    :: InternalVariable variable
    => Pattern variable
    -> Pattern variable
    -> Pattern variable
makeEvaluateNonBoolIn patt1 patt2 =
    Conditional
        { term = mkTop_
        , predicate =
            Predicate.markSimplified
            $ makeInPredicate
                -- TODO: Wrap in 'contained' and 'container'.
                (Pattern.toTermLike patt1)
                (Pattern.toTermLike patt2)
        , substitution = mempty
        }
