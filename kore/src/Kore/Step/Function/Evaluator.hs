{-|
Module      : Kore.Step.Function.Evaluator
Description : Evaluates functions in a pattern.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Function.Evaluator
    ( evaluateApplication
    , evaluatePattern
    ) where

import Control.Error
    ( ExceptT
    , exceptT
    , throwE
    )
import Control.Exception
    ( assert
    )
import qualified Control.Monad.Trans as Trans
import qualified Data.Foldable as Foldable
import Data.Function
import qualified Data.Map as Map
import Data.Maybe
    ( fromMaybe
    )
import Data.Text.Prettyprint.Doc
    ( (<+>)
    )
import qualified Data.Text.Prettyprint.Doc as Pretty

import qualified Branch as BranchT
import Kore.Attribute.Hook
import qualified Kore.Attribute.Symbol as Attribute
import Kore.Attribute.Synthetic
import Kore.Debug
import qualified Kore.Internal.Conditional as Conditional
import qualified Kore.Internal.MultiOr as MultiOr
    ( flatten
    , merge
    , mergeAll
    )
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Conditional (..)
    , Pattern
    , Predicate
    )
import qualified Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.Symbol as Symbol
import Kore.Internal.TermLike
import Kore.Logger
    ( LogMessage
    , WithLog
    )
import qualified Kore.Profiler.Profile as Profile
    ( axiomBranching
    , axiomEvaluation
    , equalitySimplification
    , mergeSubstitutions
    , resimplification
    )
import Kore.Step.Axiom.Identifier
    ( AxiomIdentifier
    )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
import qualified Kore.Step.Function.Memo as Memo
import qualified Kore.Step.Merging.OrPattern as OrPattern
import qualified Kore.Step.Simplification.Conditional as Conditional
    ( simplifyPredicate
    )
import Kore.Step.Simplification.Simplify as AttemptedAxiom
    ( AttemptedAxiom (..)
    )
import Kore.Step.Simplification.Simplify as Simplifier
import qualified Kore.Step.Simplification.Simplify as AttemptedAxiomResults
    ( AttemptedAxiomResults (..)
    )
import Kore.TopBottom
import Kore.Unparser

{-| Evaluates functions on an application pattern.
-}
-- TODO (thomas.tuegel): Factor out a "function evaluator" object.
-- See also: Kore.Step.Function.Memo.Self
-- Then add a function,
--   memoize :: Evaluator.Self state -> Memo.Self state -> Evaluator.Self state
-- to add memoization to a function evaluator.
evaluateApplication
    :: forall variable simplifier
    .  (SimplifierVariable variable, MonadSimplify simplifier)
    => Predicate variable
    -- ^ The predicate from the configuration
    -> Predicate variable
    -- ^ Aggregated children predicate and substitution.
    -> Application Symbol (TermLike variable)
    -- ^ The pattern to be evaluated
    -> simplifier (OrPattern variable)
evaluateApplication
    configurationPredicate
    childrenPredicate
    (evaluateSortInjection -> application)
  = finishT $ do
    Foldable.for_ canMemoize recallOrPattern
    substitutionSimplifier <- Simplifier.askSimplifierPredicate
    simplifier <- Simplifier.askSimplifierTermLike
    axiomIdToEvaluator <- Simplifier.askSimplifierAxioms
    let
        unevaluatedSimplifier
          | Just hook <- getHook (Attribute.hook symbolAttributes)
          -- TODO (thomas.tuegel): Factor out a second function evaluator and
          -- remove this check. At startup, the definition's rules are
          -- simplified using Matching Logic only (no function
          -- evaluation). During this stage, all the hooks are expected to be
          -- missing, so that is not an error. If any function evaluators are
          -- present, we assume that startup is finished, but we should really
          -- have a separate evaluator for startup.
          , (not . null) axiomIdToEvaluator
          =
            (error . show . Pretty.vsep)
                [ "Attempted to evaluate missing hook:" <+> Pretty.pretty hook
                , "for symbol:" <+> unparse symbol
                ]
          | otherwise = return unevaluated

        maybeEvaluatedSimplifier =
            maybeEvaluatePattern
                substitutionSimplifier
                simplifier
                axiomIdToEvaluator
                childrenPredicate
                termLike
                unevaluated
                configurationPredicate

    results <- maybeEvaluatedSimplifier & maybe unevaluatedSimplifier Trans.lift
    Foldable.for_ canMemoize (recordOrPattern results)
    return results
  where
    finishT :: ExceptT r simplifier r -> simplifier r
    finishT = exceptT return return

    Application { applicationSymbolOrAlias = symbol } = application
    Symbol { symbolAttributes } = symbol

    termLike = synthesize (ApplySymbolF application)
    unevaluated =
        OrPattern.fromPattern $ Pattern.withCondition termLike childrenPredicate

    canMemoize
      | Symbol.isMemo symbol
      , isTop childrenPredicate
      , isTop configurationPredicate
      = traverse asConcrete application
      | otherwise
      = Nothing

    recallOrPattern key = do
        Memo.Self { recall } <- askMemo
        maybeTermLike <- recall key
        let maybeOrPattern =
                OrPattern.fromTermLike . fromConcrete <$> maybeTermLike
        Foldable.for_ maybeOrPattern throwE

    recordOrPattern orPattern key
      | [result] <- OrPattern.toPatterns orPattern
      , Just term <- asConcrete (Pattern.term result)
      -- If the pattern and predicate are concrete, then we expect the predicate
      -- to be fully-evaluated, so it must be Top. It may not be fully-evaluated
      -- due to some uninterpreted function or an unsolved unification problem;
      -- these are not errors, but they are unusual enough that we don't want to
      -- deal with them here.
      , isTop (Pattern.predicate result)
      -- We already checked that childrenPredicate has no substitutions, so we
      -- don't expect the result to have any substitutions either. As with the
      -- predicate, it might be possible to have a substitution in some cases,
      -- but they are unusual enough that we don't need to deal with them here.
      , isTop (Pattern.substitution result)
      = do
        Memo.Self { record } <- askMemo
        record key term
      | otherwise
      = return ()

{-| Evaluates axioms on patterns.
-}
evaluatePattern
    ::  forall variable simplifier
    .   ( SimplifierVariable variable
        , MonadSimplify simplifier
        , WithLog LogMessage simplifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from axiom IDs to axiom evaluators
    -> Predicate variable
    -- ^ The predicate from the configuration
    -> Predicate variable
    -- ^ Aggregated children predicate and substitution.
    -> TermLike variable
    -- ^ The pattern to be evaluated
    -> OrPattern variable
    -- ^ The default value
    -> simplifier (OrPattern variable)
evaluatePattern
    substitutionSimplifier
    simplifier
    axiomIdToEvaluator
    configurationPredicate
    childrenPredicate
    patt
    defaultValue
  =
    fromMaybe
        (return defaultValue)
        (maybeEvaluatePattern
            substitutionSimplifier
            simplifier
            axiomIdToEvaluator
            childrenPredicate
            patt
            defaultValue
            configurationPredicate
        )

{-| Evaluates axioms on patterns.

Returns Nothing if there is no axiom for the pattern's identifier.
-}
maybeEvaluatePattern
    ::  forall variable simplifier
    .   ( SimplifierVariable variable
        , MonadSimplify simplifier
        , WithLog LogMessage simplifier
        )
    => PredicateSimplifier
    -> TermLikeSimplifier
    -- ^ Evaluates functions.
    -> BuiltinAndAxiomSimplifierMap
    -- ^ Map from axiom IDs to axiom evaluators
    -> Predicate variable
    -- ^ Aggregated children predicate and substitution.
    -> TermLike variable
    -- ^ The pattern to be evaluated
    -> OrPattern variable
    -- ^ The default value
    -> Predicate variable
    -> Maybe (simplifier (OrPattern variable))
maybeEvaluatePattern
    substitutionSimplifier
    simplifier
    axiomIdToEvaluator
    childrenPredicate
    patt
    defaultValue
    configurationPredicate
  =
    case maybeEvaluator of
        Nothing -> Nothing
        Just (BuiltinAndAxiomSimplifier evaluator) ->
            Just . tracing $ do
                result <- Profile.axiomEvaluation identifier $
                    evaluator
                        substitutionSimplifier
                        simplifier
                        axiomIdToEvaluator
                        patt
                        ( configurationPredicate
                        `Conditional.andCondition` childrenPredicate
                        )
                flattened <- case result of
                    AttemptedAxiom.NotApplicable ->
                        return AttemptedAxiom.NotApplicable
                    AttemptedAxiom.Applied AttemptedAxiomResults
                        { results = orResults
                        , remainders = orRemainders
                        } -> do
                            simplified <-
                                Profile.resimplification
                                    identifier (length orResults)
                                $ mapM simplifyIfNeeded orResults
                            let simplifiedResult = MultiOr.flatten simplified
                            Profile.axiomBranching
                                identifier
                                (length orResults)
                                (length simplifiedResult)
                            return
                                (AttemptedAxiom.Applied AttemptedAxiomResults
                                    { results = simplifiedResult
                                    , remainders = orRemainders
                                    }
                                )
                merged <-
                    Profile.mergeSubstitutions identifier
                    $ mergeWithConditionAndSubstitution
                        childrenPredicate
                        flattened
                case merged of
                    AttemptedAxiom.NotApplicable -> return defaultValue
                    AttemptedAxiom.Applied attemptResults ->
                        return $ MultiOr.merge results remainders
                      where
                        AttemptedAxiomResults { results, remainders } =
                            attemptResults
  where
    identifier :: Maybe AxiomIdentifier
    identifier = AxiomIdentifier.matchAxiomIdentifier patt

    maybeEvaluator :: Maybe BuiltinAndAxiomSimplifier
    maybeEvaluator = do
        identifier' <- identifier
        Map.lookup identifier' axiomIdToEvaluator

    tracing =
        traceNonErrorMonad
            D_Function_evaluatePattern
            [ debugArg "axiomIdentifier" identifier ]
        . Profile.equalitySimplification identifier patt

    unchangedPatt =
        Conditional
            { term         = patt
            , predicate    = predicate
            , substitution = substitution
            }
      where
        Conditional { term = (), predicate, substitution } = childrenPredicate

    simplifyIfNeeded :: Pattern variable -> simplifier (OrPattern variable)
    simplifyIfNeeded toSimplify
      | toSimplify == unchangedPatt =
        return (OrPattern.fromPattern unchangedPatt)
      | otherwise =
        reevaluateFunctions toSimplify

evaluateSortInjection
    :: Ord variable
    => Application Symbol (TermLike variable)
    -> Application Symbol (TermLike variable)
evaluateSortInjection ap
  | Symbol.isSortInjection apHead
  = case apChild of
    App_ apHeadChild grandChildren
      | Symbol.isSortInjection apHeadChild ->
        let
            [fromSort', toSort'] = symbolParams apHeadChild
            apHeadNew = updateSortInjectionSource apHead fromSort'
            resultApp = apHeadNew grandChildren
        in
            assert (toSort' == fromSort) resultApp
    _ -> ap
  | otherwise = ap
  where
    apHead = applicationSymbolOrAlias ap
    [fromSort, _] = symbolParams apHead
    [apChild] = applicationChildren ap
    updateSortInjectionSource head1 fromSort1 children =
        Application
            { applicationSymbolOrAlias =
                Symbol.coerceSortInjection head1 fromSort1 toSort1
            , applicationChildren = children
            }
      where
        [_, toSort1] = symbolParams head1

{-| 'reevaluateFunctions' re-evaluates functions after a user-defined function
was evaluated.
-}
reevaluateFunctions
    ::  ( SimplifierVariable variable
        , MonadSimplify simplifier
        , WithLog LogMessage simplifier
        )
    => Pattern variable
    -- ^ Function evaluation result.
    -> simplifier (OrPattern variable)
reevaluateFunctions rewriting = do
    pattOr <- simplifyTerm (Pattern.term rewriting)
    mergedPatt <-
        OrPattern.mergeWithPredicate (Pattern.withoutTerm rewriting) pattOr
    orResults <-
        BranchT.gather $ traverse Conditional.simplifyPredicate mergedPatt
    return (MultiOr.mergeAll orResults)

{-| Ands the given condition-substitution to the given function evaluation.
-}
mergeWithConditionAndSubstitution
    ::  ( SimplifierVariable variable
        , MonadSimplify simplifier
        , WithLog LogMessage simplifier
        )
    => Predicate variable
    -- ^ Condition and substitution to add.
    -> AttemptedAxiom variable
    -- ^ AttemptedAxiom to which the condition should be added.
    -> simplifier (AttemptedAxiom variable)
mergeWithConditionAndSubstitution _ AttemptedAxiom.NotApplicable =
    return AttemptedAxiom.NotApplicable
mergeWithConditionAndSubstitution
    toMerge
    (AttemptedAxiom.Applied AttemptedAxiomResults { results, remainders })
  = do
    evaluatedResults <- OrPattern.mergeWithPredicate toMerge results
    evaluatedRemainders <- OrPattern.mergeWithPredicate toMerge remainders
    return $ AttemptedAxiom.Applied AttemptedAxiomResults
        { results = evaluatedResults
        , remainders = evaluatedRemainders
        }
