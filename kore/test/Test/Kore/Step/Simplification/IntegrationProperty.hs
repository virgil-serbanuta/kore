module Test.Kore.Step.Simplification.IntegrationProperty
    ( test_simplifiesToSimplified
    ) where

import Hedgehog
    ( PropertyT
    , annotate
    , discard
    , forAll
    , property
    , withDiscards
    , withTests
    , (===)
    )
import Test.Tasty
import Test.Tasty.Hedgehog
    ( testProperty
    )

import Control.Exception
    ( ErrorCall (..)
    )
import Control.Monad.Catch
    ( MonadThrow
    , catch
    , throwM
    )
import qualified Control.Monad.Morph as Morph
    ( hoist
    )
import qualified Control.Monad.Trans as Trans
import Data.List
    ( isInfixOf
    )
import qualified Data.Map.Strict as Map
import Debug.Trace
import GHC.Stack
    ( HasCallStack
    )

import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.TermLike
import Kore.Step.Axiom.EvaluationStrategy
    ( simplifierWithFallback
    )
import qualified Kore.Step.Simplification.Data as Simplification
import qualified Kore.Step.Simplification.Pattern as Pattern
    ( simplify
    )
import Kore.Step.Simplification.Simplify
import qualified SMT

import Kore.Unparser
import Test.ConsistentKore
import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Kore.Step.Simplification
import Test.SMT
    ( runSMT
    )

test_simplifiesToSimplified :: TestTree
test_simplifiesToSimplified =
    testPropertyWithSolver "zzzsimplify returns simplified pattern" $ do
        term <- forAll (runTermGen Mock.generatorSetup termLikeGen)
        (annotate . unlines)
            [" ***** unparsed input =", unparseToString term, " ***** "]
        simplified <- catch
            (evaluateT (Pattern.fromTermLike term))
            (exceptionHandler term)
        (===) True (OrPattern.isSimplified simplified)
  where
    -- Discard exceptions that are normal for randomly generated patterns.
    exceptionHandler
        :: (Monad m, MonadThrow m)
        => TermLike Variable
        -> ErrorCall
        -> PropertyT m a
    exceptionHandler term err@(ErrorCallWithLocation message _location)
      | "Unification case that should be handled somewhere else"
        `isInfixOf` message
      = discard
      | otherwise = do
        traceM ("Error for input: " ++ unparseToString term)
        throwM err

evaluateT
    :: Trans.MonadTrans t => Pattern Variable -> t SMT.SMT (OrPattern Variable)
evaluateT = Trans.lift . evaluate

evaluate :: Pattern Variable -> SMT.SMT (OrPattern Variable)
evaluate = evaluateWithAxioms Map.empty

evaluateWithAxioms
    :: BuiltinAndAxiomSimplifierMap
    -> Pattern Variable
    -> SMT.SMT (OrPattern Variable)
evaluateWithAxioms axioms = Simplification.runSimplifier env . Pattern.simplify
  where
    env = Mock.env { simplifierAxioms }
    simplifierAxioms :: BuiltinAndAxiomSimplifierMap
    simplifierAxioms =
        Map.unionWith
            simplifierWithFallback
            Mock.builtinSimplifiers
            axioms

-- TODO: use the one in Test.SMT
testPropertyWithSolver
    :: HasCallStack
    => String
    -> PropertyT SMT.SMT ()
    -> TestTree
testPropertyWithSolver str =
    testProperty str . Hedgehog.withTests 100000 . withDiscards 10000 . Hedgehog.property . Morph.hoist runSMT
