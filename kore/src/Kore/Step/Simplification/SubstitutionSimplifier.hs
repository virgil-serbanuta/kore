{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

 -}

module Kore.Step.Simplification.SubstitutionSimplifier
    ( SubstitutionSimplifier (..)
    , substitutionSimplifier
    , simplifySubstitutionWorker
    , MakeAnd (..)
    , deduplicateSubstitution
    , simplifyAnds
    ) where

import Control.Applicative
    ( Alternative (..)
    )
import qualified Control.Comonad.Trans.Cofree as Cofree
import Control.Error
    ( MaybeT
    , maybeT
    )
import Control.Exception as Exception
import qualified Control.Lens as Lens
import Control.Monad
    ( foldM
    , (>=>)
    )
import Control.Monad.State.Strict
    ( StateT
    , runStateT
    )
import qualified Control.Monad.Trans as Trans
import Data.Function
    ( (&)
    )
import qualified Data.Functor.Foldable as Recursive
import Data.Generics.Product
import Data.List.NonEmpty
    ( NonEmpty (..)
    )
import qualified Data.List.NonEmpty as NonEmpty
import Data.Map.Strict
    ( Map
    )
import qualified Data.Map.Strict as Map
import Data.Maybe
    ( isJust
    )
import Data.Monoid
    ( Any (..)
    )
import qualified GHC.Generics as GHC

import Branch
    ( BranchT
    )
import qualified Branch
import Kore.Internal.Condition
    ( Condition
    )
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional
import Kore.Internal.OrCondition
    ( OrCondition
    )
import qualified Kore.Internal.OrCondition as OrCondition
import Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.TermLike
    ( And (..)
    , TermLike
    , TermLikeF (..)
    , mkAnd
    )
import qualified Kore.Internal.TermLike as TermLike
import Kore.Step.Simplification.Simplify
    ( MonadSimplify
    , simplifyConditionalTerm
    , simplifyTerm
    )
import Kore.Substitute
    ( SubstitutionVariable
    )
import qualified Kore.TopBottom as TopBottom
import Kore.Unification.Substitution
    ( Normalization (..)
    , SingleSubstitution
    , Substitution
    )
import qualified Kore.Unification.Substitution as Substitution
import Kore.Unification.SubstitutionNormalization
    ( normalize
    )
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    , isSetVar
    )

newtype SubstitutionSimplifier simplifier =
    SubstitutionSimplifier
        { simplifySubstitution
            :: forall variable
            .  SubstitutionVariable variable
            => Substitution variable
            -> simplifier (OrCondition variable)
        }

{- | A 'SubstitutionSimplifier' to use during simplification.

If the 'Substitution' cannot be normalized, this simplifier moves the
denormalized part into the predicate, but returns the normalized part as a
substitution.

 -}
substitutionSimplifier
    :: forall simplifier
    .  MonadSimplify simplifier
    => SubstitutionSimplifier simplifier
substitutionSimplifier =
    SubstitutionSimplifier wrapper
  where
    wrapper
        :: forall variable
        .  SubstitutionVariable variable
        => Substitution variable
        -> simplifier (OrCondition variable)
    wrapper substitution =
        fmap OrCondition.fromConditions . Branch.gather $ do
            (predicate, result) <- worker substitution & maybeT empty return
            let condition = Condition.fromNormalizationSimplified result
            let condition' = Condition.fromPredicate predicate <> condition
            TopBottom.guardAgainstBottom condition'
            return condition'
      where
        worker = simplifySubstitutionWorker simplifierMakeAnd

-- * Implementation

-- | Interface for constructing a simplified 'And' pattern.
newtype MakeAnd monad =
    MakeAnd
        { makeAnd
            :: forall variable
            .  SubstitutionVariable variable
            => TermLike variable
            -> TermLike variable
            -> Condition variable
            -> monad (Pattern variable)
            -- ^ Construct a simplified 'And' pattern of two 'TermLike's under
            -- the given 'Predicate.Predicate'.
        }

simplifierMakeAnd :: MonadSimplify simplifier => MakeAnd (BranchT simplifier)
simplifierMakeAnd =
    MakeAnd { makeAnd }
  where
    makeAnd termLike1 termLike2 condition = do
        simplified <-
            mkAnd termLike1 termLike2
            & simplifyConditionalTerm condition
        TopBottom.guardAgainstBottom simplified
        return simplified

simplifyAnds
    ::  forall variable monad
    .   ( SubstitutionVariable variable
        , Monad monad
        )
    => MakeAnd monad
    -> NonEmpty (TermLike variable)
    -> monad (Pattern variable)
simplifyAnds MakeAnd { makeAnd } (NonEmpty.sort -> patterns) = do
    foldM simplifyAnds' Pattern.top patterns
  where
    simplifyAnds'
        :: Pattern variable
        -> TermLike variable
        -> monad (Pattern variable)
    simplifyAnds' intermediate termLike =
        case Cofree.tailF (Recursive.project termLike) of
            AndF And { andFirst, andSecond } ->
                foldM simplifyAnds' intermediate [andFirst, andSecond]
            _ -> do
                simplified <-
                    makeAnd
                        intermediateTerm
                        termLike
                        intermediateCondition
                return (Pattern.andCondition simplified intermediateCondition)
      where
        (intermediateTerm, intermediateCondition) =
            Pattern.splitTerm intermediate

deduplicateSubstitution
    :: forall variable monad
    .   ( SubstitutionVariable variable
        , Monad monad
        )
    =>  MakeAnd monad
    ->  Substitution variable
    ->  monad
            ( Predicate variable
            , Map (UnifiedVariable variable) (TermLike variable)
            )
deduplicateSubstitution makeAnd' =
    worker Predicate.makeTruePredicate_ . checkSetVars . Substitution.toMultiMap
  where
    checkSetVars m
      | isProblematic m = error
        "Found SetVar key with non-singleton list of assignments as value."
      | otherwise = m
        where
            isProblematic = getAny . Map.foldMapWithKey
                (\k v -> Any $ isSetVar k && isNotSingleton v)
            isNotSingleton = not . isJust . getSingleton

    simplifyAnds' = simplifyAnds makeAnd'

    worker
        ::  Predicate variable
        ->  Map (UnifiedVariable variable) (NonEmpty (TermLike variable))
        ->  monad
                ( Predicate variable
                , Map (UnifiedVariable variable) (TermLike variable)
                )
    worker predicate substitutions
      | Just deduplicated <- traverse getSingleton substitutions
      = return (predicate, deduplicated)

      | otherwise = do
        simplified <- collectConditions <$> traverse simplifyAnds' substitutions
        let -- Substitutions de-duplicated by simplification.
            substitutions' = toMultiMap $ Conditional.term simplified
            -- New conditions produced by simplification.
            Conditional { predicate = predicate' } = simplified
            predicate'' = Predicate.makeAndPredicate predicate predicate'
            -- New substitutions produced by simplification.
            Conditional { substitution } = simplified
            substitutions'' =
                Map.unionWith (<>) substitutions'
                $ Substitution.toMultiMap substitution
        worker predicate'' substitutions''

    getSingleton (t :| []) = Just t
    getSingleton _         = Nothing

    toMultiMap :: Map key value -> Map key (NonEmpty value)
    toMultiMap = Map.map (:| [])

    collectConditions
        :: Map key (Conditional variable term)
        -> Conditional variable (Map key term)
    collectConditions = sequenceA

simplifySubstitutionWorker
    :: forall variable simplifier
    .  SubstitutionVariable variable
    => MonadSimplify simplifier
    => MakeAnd simplifier
    -> Substitution variable
    -> MaybeT simplifier (Predicate variable, Normalization variable)
simplifySubstitutionWorker makeAnd' = \substitution -> do
    (result, Private { accum = condition }) <-
        runStateT loop Private
            { count = maxBound
            , accum = Condition.fromSubstitution substitution
            }
    (assertNullSubstitution condition . return)
        (Condition.predicate condition, result)
  where
    assertNullSubstitution =
        Exception.assert . Substitution.null . Condition.substitution

    loop :: Impl variable simplifier (Normalization variable)
    loop = do
        simplified <-
            takeSubstitution
            >>= deduplicate
            >>= return . normalize
            >>= traverse simplifyNormalizationOnce
        substitution <- takeSubstitution
        lastCount <- Lens.use (field @"count")
        case simplified of
            Nothing -> empty
            Just normalization@Normalization { denormalized }
              | not fullySimplified, makingProgress -> do
                Lens.assign (field @"count") thisCount
                addSubstitution substitution
                addSubstitution $ Substitution.wrapNormalization normalization
                loop
              | otherwise -> return normalization
              where
                fullySimplified =
                    null denormalized && Substitution.null substitution
                makingProgress =
                    thisCount < lastCount || null denormalized
                thisCount = length denormalized

    simplifyNormalizationOnce
        ::  Normalization variable
        ->  Impl variable simplifier (Normalization variable)
    simplifyNormalizationOnce =
        return
        >=> simplifyNormalized
        >=> return . Substitution.applyNormalized
        >=> simplifyDenormalized

    simplifyNormalized
        :: Normalization variable
        -> Impl variable simplifier (Normalization variable)
    simplifyNormalized =
        Lens.traverseOf
            (field @"normalized" . Lens.traversed)
            simplifySingleSubstitution

    simplifyDenormalized
        :: Normalization variable
        -> Impl variable simplifier (Normalization variable)
    simplifyDenormalized =
        Lens.traverseOf
            (field @"denormalized" . Lens.traversed)
            simplifySingleSubstitution

    simplifySingleSubstitution
        :: SingleSubstitution variable
        -> Impl variable simplifier (SingleSubstitution variable)
    simplifySingleSubstitution subst@(uVar, termLike) =
        case uVar of
            SetVar _ -> return subst
            ElemVar _
              | TermLike.isSimplified termLike -> return subst
              | otherwise -> do
                termLike' <- simplifyTermLike termLike
                -- simplifyTermLike returns the unsimplified input in the event
                -- that simplification resulted in a disjunction. We may mark
                -- the result simplified anyway because uVar is singular, so:
                --   1. termLike is function-like, so
                --   2. it eventually reduces to a single term, so if it has not
                --   3. we need a substitution to evaluate it, and
                --   4. substitution resets the simplified marker.
                return (uVar, TermLike.markSimplified termLike')

    simplifyTermLike
        :: TermLike variable
        -> Impl variable simplifier (TermLike variable)
    simplifyTermLike termLike = do
        orPattern <- simplifyTerm termLike
        case OrPattern.toPatterns orPattern of
            [        ] -> do
                addCondition Condition.bottom
                return termLike
            [pattern1] -> do
                let (termLike1, condition) = Pattern.splitTerm pattern1
                addCondition condition
                return termLike1
            _          -> return termLike

    deduplicate
        ::  Substitution variable
        ->  Impl variable simplifier
                (Map (UnifiedVariable variable) (TermLike variable))
    deduplicate substitution = do
        (predicate, substitution') <-
            deduplicateSubstitution makeAnd' substitution
            & Trans.lift . Trans.lift
        addPredicate predicate
        return substitution'

data Private variable =
    Private
        { accum :: !(Condition variable)
        -- ^ The current condition, accumulated during simplification.
        , count :: !Int
        -- ^ The current number of denormalized substitutions.
        }
    deriving (GHC.Generic)

{- | The 'Impl'ementation of the generic 'SubstitutionSimplifier'.

The 'MaybeT' transformer layer is used for short-circuiting: if any individual
substitution in unsatisfiable (@\\bottom@) then the entire substitution is also.

 -}
type Impl variable simplifier = StateT (Private variable) (MaybeT simplifier)

addCondition
    :: SubstitutionVariable variable
    => Monad simplifier
    => Condition variable
    -> Impl variable simplifier ()
addCondition condition
  | TopBottom.isBottom condition = empty
  | otherwise =
    Lens.modifying (field @"accum") (mappend condition)

addPredicate
    :: SubstitutionVariable variable
    => Monad simplifier
    => Predicate variable
    -> Impl variable simplifier ()
addPredicate = addCondition . Condition.fromPredicate

addSubstitution
    :: SubstitutionVariable variable
    => Monad simplifier
    => Substitution variable
    -> Impl variable simplifier ()
addSubstitution = addCondition . Condition.fromSubstitution

takeSubstitution
    :: SubstitutionVariable variable
    => Monad simplifier
    => Impl variable simplifier (Substitution variable)
takeSubstitution = do
    substitution <- Lens.use (field @"accum".field @"substitution")
    Lens.assign (field @"accum".field @"substitution") mempty
    return substitution
