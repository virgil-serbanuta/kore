{-|
Module      : Kore.Step.Simplification.Implies
Description : Tools for Implies pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Implies
    ( simplify
    , simplifyEvaluated
    ) where

import qualified Kore.Internal.MultiOr as MultiOr
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.TermLike as TermLike
import Kore.Step.Simplification.Simplify
    ( SimplifierVariable
    )

{-|'simplify' simplifies an 'Implies' pattern with 'OrPattern'
children.

Right now this uses the following simplifications:

* a -> (b or c) = (a -> b) or (a -> c)
* bottom -> b = top
* top -> b = b
* a -> top = top
* a -> bottom = not a

and it has a special case for children with top terms.
-}
simplify
    :: SimplifierVariable variable
    => Implies Sort (OrPattern variable)
    -> Pattern variable
simplify Implies { impliesFirst = first, impliesSecond = second } =
    simplifyEvaluated first second

{-| simplifies an Implies given its two 'OrPattern' children.

See 'simplify' for details.
-}
-- TODO: Maybe transform this to (not a) \/ b
{- TODO (virgil): Preserve pattern sorts under simplification.

One way to preserve the required sort annotations is to make 'simplifyEvaluated'
take an argument of type

> CofreeF (Implies Sort) (Attribute.Pattern variable) (OrPattern variable)

instead of two 'OrPattern' arguments. The type of 'makeEvaluate' may
be changed analogously. The 'Attribute.Pattern' annotation will eventually cache
information besides the pattern sort, which will make it even more useful to
carry around.

-}
simplifyEvaluated
    :: SimplifierVariable variable
    => OrPattern variable
    -> OrPattern variable
    -> Pattern variable
simplifyEvaluated first second
  | OrPattern.isTrue first   = OrPattern.toPattern second
  | OrPattern.isFalse first  = Pattern.top
  | OrPattern.isTrue second  = Pattern.top
  | OrPattern.isFalse second =
    Pattern.fromTermLike (mkNot (OrPattern.toTermLike first))
  | otherwise =
    (OrPattern.toPattern . OrPattern.fromPatterns)
        (map
            (simplifyEvaluateHalfImplies first)
            (OrPattern.toPatterns second)
        )

simplifyEvaluateHalfImplies
    :: SimplifierVariable variable
    => OrPattern variable
    -> Pattern variable
    -> Pattern variable
simplifyEvaluateHalfImplies
    first
    second
  | OrPattern.isTrue first  = second
  | OrPattern.isFalse first = Pattern.top
  | Pattern.isTop second    = Pattern.top
  | Pattern.isBottom second =
    Pattern.fromTermLike (mkNot (OrPattern.toTermLike first))
  | otherwise =
    case MultiOr.extractPatterns first of
        [firstP] -> makeEvaluateImplies firstP second
        firstPatterns -> distributeEvaluateImplies firstPatterns second

distributeEvaluateImplies
    :: SimplifierVariable variable
    => [Pattern variable]
    -> Pattern variable
    -> Pattern variable
distributeEvaluateImplies firsts second =
    Pattern.fromTermLike
        (foldr
            (\first merged -> mkAnd
                (Pattern.toTermLike $ makeEvaluateImplies first second)
                merged
            )
            mkTop_
            firsts
        )

makeEvaluateImplies
    :: InternalVariable variable
    => Pattern variable
    -> Pattern variable
    -> Pattern variable
makeEvaluateImplies
    first second
  | Pattern.isTop first =
    second
  | Pattern.isBottom first =
    Pattern.top
  | Pattern.isTop second =
    Pattern.top
  | Pattern.isBottom second =
    Pattern.fromTermLike (mkNot (Pattern.toTermLike first))
  | otherwise =
    makeEvaluateImpliesNonBool first second

makeEvaluateImpliesNonBool
    :: InternalVariable variable
    => Pattern variable
    -> Pattern variable
    -> Pattern variable
makeEvaluateImpliesNonBool
    pattern1@Conditional
        { term = firstTerm
        , predicate = firstPredicate
        , substitution = firstSubstitution
        }
    pattern2@Conditional
        { term = secondTerm
        , predicate = secondPredicate
        , substitution = secondSubstitution
        }
  | isTop firstTerm, isTop secondTerm =
    Conditional
        { term = firstTerm
        , predicate =
            Predicate.markSimplified
            $ Predicate.makeImpliesPredicate
                (Predicate.makeAndPredicate
                    firstPredicate
                    (Predicate.fromSubstitution firstSubstitution)
                )
                (Predicate.makeAndPredicate
                    secondPredicate
                    (Predicate.fromSubstitution secondSubstitution)
                )
        , substitution = mempty
        }
  | otherwise =
    -- TODO (thomas.tuegel): Maybe this should be an error?
    Conditional
        { term =
            TermLike.markSimplified
            $ mkImplies
                (Pattern.toTermLike pattern1)
                (Pattern.toTermLike pattern2)
        , predicate = Predicate.makeTruePredicate
        , substitution = mempty
        }
