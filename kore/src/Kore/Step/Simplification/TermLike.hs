{- |
Copyright   : (c) Runtime Verification, 2018
License     : NCSA

-}
module Kore.Step.Simplification.TermLike
    ( simplify
    , simplifyToOr
    , simplifyInternal
    ) where

import Control.Comonad.Trans.Cofree
    ( CofreeF ((:<))
    )
import qualified Control.Exception as Exception
import qualified Control.Lens.Combinators as Lens
import Control.Monad
    ( unless
    )
import Data.Functor.Const
import qualified Data.Functor.Foldable as Recursive
import qualified Data.Map as Map
import Data.Maybe
    ( fromMaybe
    )
import qualified Data.Set as Set
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified GHC.Stack as GHC

import qualified Branch as BranchT
    ( gather
    , scatter
    )
import qualified Kore.Attribute.Pattern.FreeVariables as FreeVariables
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Conditional
    ( Conditional (Conditional)
    )
import qualified Kore.Internal.Conditional as Conditional
    ( andCondition
    )
import qualified Kore.Internal.MultiOr as MultiOr
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern as Pattern
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.TermLike
    ( TermLike
    , TermLikeF (..)
    , termLikeSort
    )
import qualified Kore.Internal.TermLike as TermLike
import Kore.Internal.Variable
    ( InternalVariable
    )
import qualified Kore.Profiler.Profile as Profiler
    ( identifierSimplification
    )
import Kore.Sort
    ( Sort
    )
import qualified Kore.Step.Axiom.Identifier as AxiomIdentifier
    ( matchAxiomIdentifier
    )
import qualified Kore.Step.Simplification.And as And
    ( simplify
    )
import qualified Kore.Step.Simplification.Application as Application
    ( simplify
    )
import qualified Kore.Step.Simplification.Bottom as Bottom
    ( simplify
    )
import qualified Kore.Step.Simplification.Builtin as Builtin
    ( simplify
    )
import qualified Kore.Step.Simplification.Ceil as Ceil
    ( simplify
    )
import qualified Kore.Step.Simplification.DomainValue as DomainValue
    ( simplify
    )
import qualified Kore.Step.Simplification.Equals as Equals
    ( simplify
    )
import qualified Kore.Step.Simplification.Exists as Exists
    ( simplify
    )
import qualified Kore.Step.Simplification.Floor as Floor
    ( simplify
    )
import qualified Kore.Step.Simplification.Forall as Forall
    ( simplify
    )
import qualified Kore.Step.Simplification.Iff as Iff
    ( simplify
    )
import qualified Kore.Step.Simplification.Implies as Implies
    ( simplify
    )
import qualified Kore.Step.Simplification.In as In
    ( simplify
    )
import qualified Kore.Step.Simplification.Inhabitant as Inhabitant
    ( simplify
    )
import qualified Kore.Step.Simplification.InternalBytes as InternalBytes
    ( simplify
    )
import qualified Kore.Step.Simplification.Mu as Mu
    ( simplify
    )
import qualified Kore.Step.Simplification.Next as Next
    ( simplify
    )
import qualified Kore.Step.Simplification.Not as Not
    ( simplify
    )
import qualified Kore.Step.Simplification.Nu as Nu
    ( simplify
    )
import qualified Kore.Step.Simplification.Or as Or
    ( simplify
    )
import qualified Kore.Step.Simplification.Rewrites as Rewrites
    ( simplify
    )
import Kore.Step.Simplification.Simplify
import qualified Kore.Step.Simplification.StringLiteral as StringLiteral
    ( simplify
    )
import qualified Kore.Step.Simplification.Top as Top
    ( simplify
    )
import qualified Kore.Step.Simplification.Variable as Variable
    ( simplify
    )
import Kore.TopBottom
    ( TopBottom (..)
    )
import qualified Kore.Unification.Substitution as Substitution
    ( toMap
    )
import Kore.Unparser
    ( unparse
    , unparseToString
    )
import qualified Kore.Variables.Binding as Binding
import Kore.Variables.Fresh
    ( refreshVariable
    )
import Kore.Variables.UnifiedVariable
    ( UnifiedVariable (..)
    )

-- TODO(virgil): Add a Simplifiable class and make all pattern types
-- instances of that.

{-|'simplify' simplifies a `TermLike`, returning a 'Pattern'.
-}
simplify
    ::  ( GHC.HasCallStack
        , SimplifierVariable variable
        , MonadSimplify simplifier
        )
    =>  TermLike variable
    ->  Condition variable
    ->  simplifier (Pattern variable)
simplify patt predicate = do
    orPatt <- simplifyToOr predicate patt
    return (OrPattern.toPattern orPatt)

{-|'simplifyToOr' simplifies a TermLike variable, returning an
'OrPattern'.
-}
simplifyToOr
    ::  ( GHC.HasCallStack
        , SimplifierVariable variable
        , MonadSimplify simplifier
        )
    =>  Condition variable
    ->  TermLike variable
    ->  simplifier (OrPattern variable)
simplifyToOr predicate term =
    localSimplifierTermLike (const simplifier)
        . simplifyInternal term
        $ predicate
  where
    simplifier = termLikeSimplifier simplifyToOr

simplifyInternal
    ::  forall variable simplifier
    .   ( GHC.HasCallStack
        , SimplifierVariable variable
        , MonadSimplify simplifier
        )
    =>  TermLike variable
    ->  Condition variable
    ->  simplifier (OrPattern variable)
simplifyInternal term predicate = do
    result <- simplifyInternalWorker term
    unless (OrPattern.isSimplified result)
        (error $ unlines
            (   [ "Not simplified."
                , "result = "
                ]
            ++ map unparseToString (OrPattern.toPatterns result)
            )
        )
    return result
  where
    tracer termLike = case AxiomIdentifier.matchAxiomIdentifier termLike of
        Nothing -> id
        Just identifier -> Profiler.identifierSimplification identifier

    predicateFreeVars =
        FreeVariables.getFreeVariables $ Condition.freeVariables predicate

    simplifyChildren
        :: Traversable t
        => t (TermLike variable)
        -> simplifier (t (OrPattern variable))
    simplifyChildren = traverse simplifyInternalWorker

    assertConditionSimplified
        :: TermLike variable -> Condition variable -> Condition variable
    assertConditionSimplified originalTerm condition =
        if Condition.isSimplified condition
            then condition
            else (error . unlines)
                [ "Not simplified."
                , "term = "
                , unparseToString originalTerm
                , "condition = "
                , unparseToString condition
                ]

    simplifyInternalWorker
        :: TermLike variable -> simplifier (OrPattern variable)
    simplifyInternalWorker termLike
        | TermLike.isSimplified termLike
        = case Predicate.makePredicate termLike of
            Left _ -> return . OrPattern.fromTermLike $ termLike
            Right termPredicate ->
                return
                $ OrPattern.fromPattern
                $ Pattern.fromCondition
                $ assertConditionSimplified termLike
                $ Condition.fromPredicate termPredicate
        | otherwise
        = assertTermNotPredicate $ tracer termLike $ do
            unfixedTermOr <- descendAndSimplify termLike
            let termOr = fixOrPatternSorts (termLikeSort termLike) unfixedTermOr
            returnIfSimplifiedOrContinue
                termLike
                (OrPattern.toPatterns termOr)
                (do
                    termPredicateList <- BranchT.gather $ do
                        termOrElement <- BranchT.scatter termOr
                        simplified <- simplifyCondition termOrElement
                        return (applyTermSubstitution simplified)

                    returnIfSimplifiedOrContinue
                        termLike
                        termPredicateList
                        (do
                            resultsList <- mapM resimplify termPredicateList
                            return (MultiOr.mergeAll resultsList)
                        )
                )
      where

        resimplify :: Pattern variable -> simplifier (OrPattern variable)
        resimplify result = do
            let (resultTerm, resultPredicate) = Pattern.splitTerm result
            simplified <- simplifyInternalWorker resultTerm
            return ((`Conditional.andCondition` resultPredicate) <$> simplified)

        applyTermSubstitution :: Pattern variable -> Pattern variable
        applyTermSubstitution
            Conditional {term = term', predicate = predicate', substitution}
          =
            Conditional
                { term =
                    TermLike.substitute (Substitution.toMap substitution) term'
                , predicate = predicate'
                , substitution
                }

        assertTermNotPredicate getResults = do
            results <- getResults
            let
                -- The term of a result should never be any predicate other than
                -- Top or Bottom.
                hasPredicateTerm Conditional { term = term' }
                  | isTop term' || isBottom term' = False
                  | otherwise                     = Predicate.isPredicate term'
                unsimplified =
                    filter hasPredicateTerm $ OrPattern.toPatterns results
            if null unsimplified
                then return results
                else (error . show . Pretty.vsep)
                    [ "Incomplete simplification!"
                    , Pretty.indent 2 "input:"
                    , Pretty.indent 4 (unparse termLike)
                    , Pretty.indent 2 "unsimplified results:"
                    , (Pretty.indent 4 . Pretty.vsep)
                        (unparse <$> unsimplified)
                    , "Expected all predicates to be removed from the term."
                    ]

        returnIfSimplifiedOrContinue
            :: TermLike variable
            -> [Pattern variable]
            -> simplifier (OrPattern variable)
            -> simplifier (OrPattern variable)
        returnIfSimplifiedOrContinue originalTerm resultList continuation =
            case resultList of
                [] -> return OrPattern.bottom
                [result] ->
                    returnIfResultSimplifiedOrContinue
                        originalTerm result continuation
                _ -> continuation

        returnIfResultSimplifiedOrContinue
            :: TermLike variable
            -> Pattern variable
            -> simplifier (OrPattern variable)
            -> simplifier (OrPattern variable)
        returnIfResultSimplifiedOrContinue originalTerm result continuation
          | Pattern.isSimplified result
            && isTop resultTerm
            && resultSubstitutionIsEmpty
          = return (OrPattern.fromPattern result)
          | Pattern.isSimplified result
            && isTop resultPredicate
          = return (OrPattern.fromPattern result)
          | isTop resultPredicate && resultTerm == originalTerm
          = return (OrPattern.fromTermLike (TermLike.markSimplified resultTerm))
          | isTop resultTerm && Right resultPredicate == termAsPredicate
          = return
                $ OrPattern.fromPattern
                $ Pattern.fromCondition
                $ Condition.markSimplified resultPredicate
          | otherwise = continuation
          where
            (resultTerm, resultPredicate) = Pattern.splitTerm result
            resultSubstitutionIsEmpty =
                case resultPredicate of
                    Conditional {substitution} -> substitution == mempty
            termAsPredicate =
                Condition.fromPredicate <$> Predicate.makePredicate term

    descendAndSimplify :: TermLike variable -> simplifier (OrPattern variable)
    descendAndSimplify termLike =
        let doNotSimplify =
                Exception.assert (TermLike.isSimplified termLike)
                return (OrPattern.fromTermLike termLike)
            (_ :< termLikeF) = Recursive.project termLike
        in case termLikeF of
            -- Unimplemented cases
            ApplyAliasF _ -> doNotSimplify
            -- Do not simplify non-simplifiable patterns.
            EvaluatedF  _ -> doNotSimplify
            EndiannessF _ -> doNotSimplify
            SignednessF _ -> doNotSimplify
            --
            AndF andF ->
                And.simplify =<< simplifyChildren andF
            ApplySymbolF applySymbolF ->
                Application.simplify predicate
                    =<< simplifyChildren applySymbolF
            CeilF ceilF ->
                Ceil.simplify predicate =<< simplifyChildren ceilF
            EqualsF equalsF ->
                Equals.simplify predicate =<< simplifyChildren equalsF
            ExistsF exists ->
                let fresh =
                        Lens.over
                            Binding.existsBinder
                            refreshBinder
                            exists
                in  Exists.simplify =<< simplifyChildren fresh
            IffF iffF ->
                Iff.simplify =<< simplifyChildren iffF
            ImpliesF impliesF ->
                Implies.simplify =<< simplifyChildren impliesF
            InF inF ->
                In.simplify predicate =<< simplifyChildren inF
            NotF notF ->
                Not.simplify =<< simplifyChildren notF
            --
            BottomF bottomF ->
                Bottom.simplify <$> simplifyChildren bottomF
            BuiltinF builtinF ->
                Builtin.simplify <$> simplifyChildren builtinF
            DomainValueF domainValueF ->
                DomainValue.simplify <$> simplifyChildren domainValueF
            FloorF floorF -> Floor.simplify <$> simplifyChildren floorF
            ForallF forall ->
                let fresh =
                        Lens.over
                            Binding.forallBinder
                            refreshBinder
                            forall
                in  Forall.simplify <$> simplifyChildren fresh
            InhabitantF inhF ->
                Inhabitant.simplify <$> simplifyChildren inhF
            MuF mu ->
                let fresh = Lens.over Binding.muBinder refreshBinder mu
                in  Mu.simplify <$> simplifyChildren fresh
            NuF nu ->
                let fresh = Lens.over Binding.nuBinder refreshBinder nu
                in  Nu.simplify <$> simplifyChildren fresh
            -- TODO(virgil): Move next up through patterns.
            NextF nextF -> Next.simplify <$> simplifyChildren nextF
            OrF orF -> Or.simplify <$> simplifyChildren orF
            RewritesF rewritesF ->
                Rewrites.simplify <$> simplifyChildren rewritesF
            TopF topF -> Top.simplify <$> simplifyChildren topF
            --
            StringLiteralF stringLiteralF ->
                return $ StringLiteral.simplify (getConst stringLiteralF)
            InternalBytesF internalBytesF ->
                return $ InternalBytes.simplify (getConst internalBytesF)
            VariableF variableF ->
                return $ Variable.simplify (getConst variableF)

    refreshBinder
        :: Binding.Binder (UnifiedVariable variable) (TermLike variable)
        -> Binding.Binder (UnifiedVariable variable) (TermLike variable)
    refreshBinder binder@Binding.Binder { binderVariable, binderChild }
      | binderVariable `Set.member` predicateFreeVars =
        let existsFreeVars =
                FreeVariables.getFreeVariables
                $ TermLike.freeVariables binderChild
            fresh =
                fromMaybe (error "guard above ensures result <> Nothing")
                    $ refreshVariable
                        (predicateFreeVars <> existsFreeVars)
                        binderVariable
            freshChild =
                TermLike.substitute
                    (Map.singleton
                        binderVariable
                        (TermLike.mkVar fresh)
                    )
                    binderChild
        in Binding.Binder
            { binderVariable = fresh
            , binderChild = freshChild
            }
      | otherwise = binder

fixOrPatternSorts
    :: InternalVariable variable
    => Sort -> OrPattern variable -> OrPattern variable
fixOrPatternSorts sort =
    OrPattern.fromPatterns
    . map (fixPatternSorts sort)
    . OrPattern.toPatterns

fixPatternSorts
    :: InternalVariable variable
    => Sort -> Pattern variable -> Pattern variable
fixPatternSorts
    sort
    Conditional { term, predicate, substitution }
  =
    Conditional
        { term = TermLike.forceSort sort term
        , predicate = TermLike.forceSort sort <$> predicate
        , substitution
        }
