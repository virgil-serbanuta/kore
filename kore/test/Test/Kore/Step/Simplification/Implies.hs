module Test.Kore.Step.Simplification.Implies
    ( --t-est_simplifyEvaluated
    ) where
{-
import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Text.Prettyprint.Doc as Pretty
import qualified GHC.Stack as GHC

import qualified Kore.Internal.Condition as Condition
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
    )
import qualified Kore.Internal.Predicate as Predicate
import Kore.Internal.TermLike
import qualified Kore.Step.Simplification.Implies as Implies

import Kore.Unparser

import qualified Test.Kore.Step.MockSymbols as Mock

t-est_simplifyEvaluated :: [TestTree]
t-est_simplifyEvaluated =
    [ ([Pattern.top], [Pattern.top]) `becomes_` Pattern.top
    , ([Pattern.top], []) `becomes_` Pattern.bottom
    , ([], [Pattern.top]) `becomes_` Pattern.top
    , ([], []) `becomes_` Pattern.top

    , ([termA], [termB]) `becomes_` aImpliesB
    , ([equalsXA], [equalsXB]) `becomes_` impliesEqualsXAEqualsXB
    , ([equalsXA], [equalsXB, equalsXC])
        `becomes_` impliesEqualsXAEqualsXBOrimpliesEqualsXAEqualsXC
    , ([equalsXA, equalsXB], [equalsXC])
        `becomes_` equalXAImpliesEqualXCAndEqualXBImpliesEqualXC
    ]
  where
    becomes_
        :: GHC.HasCallStack
        => ([Pattern Variable], [Pattern Variable])
        -> Pattern Variable
        -> TestTree
    becomes_ (firsts, seconds) expected =
        testCase "becomes" $ do
            let actual = simplifyEvaluated first second
            assertBool (message actual) (expected == actual)
      where
        first = OrPattern.fromPatterns firsts
        second = OrPattern.fromPatterns seconds
        message actual =
            (show . Pretty.vsep)
                [ "expected simplification of:"
                , Pretty.indent 4 $ Pretty.vsep $ unparse <$> firsts
                , "->"
                , Pretty.indent 4 $ Pretty.vsep $ unparse <$> seconds
                , "would give:"
                , Pretty.indent 4 $ unparse expected
                , "but got:"
                , Pretty.indent 4 $ unparse actual
                ]

termA :: Pattern Variable
termA = Pattern.fromTermLike Mock.a

termB :: Pattern Variable
termB = Pattern.fromTermLike Mock.b

aImpliesB :: Pattern Variable
aImpliesB = Pattern.fromTermLike (mkImplies Mock.a Mock.b)

equalsXA :: Pattern Variable
equalsXA = fromPredicate equalsXA_

equalsXB :: Pattern Variable
equalsXB = fromPredicate equalsXB_

equalsXC :: Pattern Variable
equalsXC = fromPredicate equalsXC_

equalsXA_ :: Predicate Variable
equalsXA_ = Predicate.makeEqualsPredicate (mkElemVar Mock.x) Mock.a

equalsXB_ :: Predicate Variable
equalsXB_ = Predicate.makeEqualsPredicate (mkElemVar Mock.x) Mock.b

equalsXC_ :: Predicate Variable
equalsXC_ = Predicate.makeEqualsPredicate (mkElemVar Mock.x) Mock.c

equalXAImpliesEqualXB_ :: Predicate Variable
equalXAImpliesEqualXB_ =
    Predicate.makeImpliesPredicate equalsXA_ equalsXB_

equalXAImpliesEqualXC_ :: Predicate Variable
equalXAImpliesEqualXC_ =
    Predicate.makeImpliesPredicate equalsXA_ equalsXC_

equalXBImpliesEqualXC_ :: Predicate Variable
equalXBImpliesEqualXC_ =
    Predicate.makeImpliesPredicate equalsXB_ equalsXC_

equalXAImpliesEqualXCAndEqualXBImpliesEqualXC :: Pattern Variable
equalXAImpliesEqualXCAndEqualXBImpliesEqualXC =
    Pattern.fromTermLike
        (mkAnd
            (Predicate.unwrapPredicate equalXAImpliesEqualXC_)
            (mkAnd
                (Predicate.unwrapPredicate equalXBImpliesEqualXC_)
                mkTop_
            )
        )

impliesEqualsXAEqualsXB :: Pattern Variable
impliesEqualsXAEqualsXB = fromPredicate equalXAImpliesEqualXB_

impliesEqualsXAEqualsXBOrimpliesEqualsXAEqualsXC :: Pattern Variable
impliesEqualsXAEqualsXBOrimpliesEqualsXAEqualsXC = fromPredicate $
    Predicate.makeOrPredicate equalXAImpliesEqualXB_ equalXAImpliesEqualXC_

fromPredicate :: Predicate Variable -> Pattern Variable
fromPredicate =
    Pattern.fromCondition . Condition.fromPredicate

simplifyEvaluated
    :: OrPattern Variable
    -> OrPattern Variable
    -> Pattern Variable
simplifyEvaluated first second =
    Implies.simplifyEvaluated first second
-}
