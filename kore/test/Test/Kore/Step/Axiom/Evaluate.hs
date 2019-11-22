module Test.Kore.Step.Axiom.Evaluate
    ( test_evaluateAxioms
    ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Control.Lens as Lens
import qualified Data.Foldable as Foldable
import Data.Function
import Data.Generics.Product
import Data.Generics.Wrapped
import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified GHC.Stack as GHC

import Kore.Attribute.Axiom.Concrete
import qualified Kore.Internal.Condition as Condition
import Kore.Internal.Conditional as Conditional
import Kore.Internal.OrPattern
    ( OrPattern
    )
import qualified Kore.Internal.OrPattern as OrPattern
import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( Predicate
    , makeAndPredicate
    , makeEqualsPredicate_
    , makeFalsePredicate_
    , makeNotPredicate
    , makeOrPredicate
    , makeTruePredicate_
    )
import Kore.Internal.TermLike
import qualified Kore.Step.Axiom.Evaluate as Kore
import qualified Kore.Step.Result as Results
import Kore.Step.Rule
    ( EqualityRule (..)
    , RulePattern (..)
    , rulePattern
    )
import Kore.Step.Simplification.Simplify
import Kore.Unparser

import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Kore.Step.Simplification

test_evaluateAxioms :: [TestTree]
test_evaluateAxioms =
    [ applies "F(x) => G(x) applies to F(x)"
        [axiom_ (f x) (g x)]
        (f x, makeTruePredicate_)
        [Pattern.fromTermLikeUnsorted $ g x]
    , doesn'tApply "F(x) => G(x) [concrete] doesn't apply to F(x)"
        [axiom_ (f x) (g x) & concreteEqualityRule]
        (f x, makeTruePredicate_)
    , doesn'tApply "F(x) => G(x) doesn't apply to F(top)"
        [axiom_ (f x) (g x)]
        (f mkTop_, makeTruePredicate_)
    , applies "F(x) => G(x) [concrete] apply to F(a)"
        [axiom_ (f x) (g x) & concreteEqualityRule]
        (f a, makeTruePredicate_)
        [Pattern.fromTermLikeUnsorted $ g a]
    , doesn'tApply "F(x) => G(x) requires \\bottom doesn't apply to F(x)"
        [axiom (f x) (g x) makeFalsePredicate_]
        (f x, makeTruePredicate_)
    , doesn'tApply "Σ(X, X) => G(X) doesn't apply to Σ(Y, Z) -- no narrowing"
        [axiom_ (sigma x x) (g x)]
        (sigma y z, makeTruePredicate_)
    , doesn'tApply
        -- using SMT
        "Σ(X, Y) => A requires (X > 0 and not Y > 0) doesn't apply to Σ(Z, Z)"
        [axiom (sigma x y) a (positive x `andNot` positive y)]
        (sigma z z, makeTruePredicate_)
    , applies
        -- using SMT
        "Σ(X, Y) => A requires (X > 0 or not Y > 0) applies to Σ(Z, Z)"
        [axiom (sigma x y) a (positive x `orNot` positive y)]
        (sigma a a, makeTruePredicate_)
        -- SMT not used to simplify trivial constraints
        [a `andRequires` (positive a `orNot` positive a)]
    , doesn'tApply
        -- using SMT
        "f(X) => A requires (X > 0) doesn't apply to f(Z) and (not (Z > 0))"
        [axiom (f x) a (positive x)]
        (f z, makeNotPredicate (positive z))
    , applies
        -- using SMT
        "f(X) => A requires (X > 0) applies to f(Z) and (Z > 0)"
        [axiom (f x) a (positive x)]
        (f z, positive z)
        [a `andRequires` (positive z)]
    ]

-- * Test data

f, g :: TermLike Variable -> TermLike Variable
f = Mock.functionalConstr10
g = Mock.functionalConstr11

sigma :: TermLike Variable -> TermLike Variable -> TermLike Variable
sigma = Mock.functionalConstr20

x, y, z :: TermLike Variable
x = mkElemVar Mock.x
y = mkElemVar Mock.y
z = mkElemVar Mock.z

a :: TermLike Variable
a = Mock.a

positive :: TermLike Variable -> Predicate Variable
positive u =
    makeEqualsPredicate_
        (Mock.lessInt
            (Mock.fTestInt u)  -- wrap the given term for sort agreement
            (Mock.builtinInt 0)
        )
        (Mock.builtinBool False)

andNot, orNot
    :: Predicate Variable
    -> Predicate Variable
    -> Predicate Variable
andNot p1 p2 = makeAndPredicate p1 (makeNotPredicate p2)
orNot p1 p2 = makeOrPredicate p1 (makeNotPredicate p2)

andRequires
    :: TermLike Variable
    -> Predicate Variable
    -> Pattern Variable
andRequires term requires =
    Conditional {term, predicate = requires, substitution = mempty}

-- * Helpers

axiom
    :: TermLike Variable
    -> TermLike Variable
    -> Predicate Variable
    -> EqualityRule Variable
axiom left right predicate =
    EqualityRule (rulePattern left right) { requires = predicate }

axiom_
    :: TermLike Variable
    -> TermLike Variable
    -> EqualityRule Variable
axiom_ left right = axiom left right makeTruePredicate_

concreteEqualityRule :: EqualityRule Variable -> EqualityRule Variable
concreteEqualityRule =
    Lens.set
        (_Unwrapped . field @"attributes" . field @"concrete")
        (Concrete True)

-- * Test forms

withAttempted
    :: (AttemptedAxiom Variable -> Assertion)
    -> TestName
    -> [EqualityRule Variable]
    -> (TermLike Variable, Predicate Variable)
    -> TestTree
withAttempted check comment axioms termLikeAndPredicate =
    testCase comment (evaluateAxioms axioms termLikeAndPredicate >>= check)

applies
    :: GHC.HasCallStack
    => TestName
    -> [EqualityRule Variable]
    -> (TermLike Variable, Predicate Variable)
    -> [Pattern Variable]
    -> TestTree
applies testName axioms termLikeAndPredicate results =
    withAttempted check testName axioms termLikeAndPredicate
  where
    check attempted = do
        actual <- expectApplied attempted
        expectNoRemainders actual
        expectResults actual
    expectApplied NotApplicable     = assertFailure "Expected Applied"
    expectApplied (Applied actual) = return actual
    expectNoRemainders =
        assertEqualOrPattern "Expected no remainders" OrPattern.bottom
        . Lens.view (field @"remainders")
    expect = OrPattern.fromPatterns results
    expectResults =
        assertEqualOrPattern "Expected results" expect
        . Lens.view (field @"results")

assertEqualOrPattern
    :: GHC.HasCallStack
    => String
    -> OrPattern Variable
    -> OrPattern Variable
    -> IO ()
assertEqualOrPattern message expect actual
  | expect == actual = return ()
  | otherwise =
    (assertFailure . show . Pretty.vsep)
        [ Pretty.pretty message
        , "expected:"
        , Pretty.indent 4 . Pretty.vsep $ unparse <$> Foldable.toList expect
        , "actual:"
        , Pretty.indent 4 . Pretty.vsep $ unparse <$> Foldable.toList actual
        ]

doesn'tApply
    :: GHC.HasCallStack
    => TestName
    -> [EqualityRule Variable]
    -> (TermLike Variable, Predicate Variable)
    -> TestTree
doesn'tApply =
    withAttempted (assertBool "Expected NotApplicable" . isNotApplicable)

-- * Test environment

evaluateAxioms
    :: [EqualityRule Variable]
    -> (TermLike Variable, Predicate Variable)
    -> IO (AttemptedAxiom Variable)
evaluateAxioms axioms (termLike, predicate) =
    runSimplifier Mock.env . fmap Results.toAttemptedAxiom
    $ Kore.evaluateAxioms axioms termLike predicate
