module Kore.Step.Substitution where

import GHC.Stack
    ( HasCallStack
    )

import Kore.Internal.Pattern
    ( Predicate
    )
import Kore.Logger
    ( LogMessage
    , WithLog
    )
import qualified Kore.Predicate.Predicate as Syntax
    ( Predicate
    )
import Kore.Unification.Substitution
    ( Substitution
    )
import Kore.Unification.Unify
    ( MonadUnify
    , SimplifierVariable
    )

mergePredicatesAndSubstitutionsExcept
    ::  ( SimplifierVariable variable
        , HasCallStack
        , MonadUnify unifier
        , WithLog LogMessage unifier
        )
    => [Syntax.Predicate variable]
    -> [Substitution variable]
    -> unifier (Predicate variable)
