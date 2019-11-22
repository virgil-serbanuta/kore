module Test.Kore.Strategies.Reachability.Verification
    ( test_reachabilityVerification
    ) where

import Test.Tasty

import Data.Default
    ( def
    )
import Data.Limit
    ( Limit (..)
    )

import qualified Kore.Attribute.Axiom as Attribute
import Kore.Internal.Pattern
    ( Conditional (Conditional)
    )
import Kore.Internal.Pattern as Conditional
    ( Conditional (..)
    )
import Kore.Internal.Pattern as Pattern
import Kore.Internal.Predicate
    ( makeEqualsPredicate_
    , makeNotPredicate
    , makeTruePredicate_
    )
import Kore.Internal.TermLike
import Kore.Step.Rule
    ( AllPathRule (..)
    , OnePathRule (..)
    , ReachabilityRule (..)
    , RewriteRule (..)
    , RulePattern (..)
    )
import Kore.Strategies.Goal

import qualified Test.Kore.Step.MockSymbols as Mock
import Test.Kore.Strategies.Common
import Test.Tasty.HUnit.Ext

test_reachabilityVerification :: [TestTree]
test_reachabilityVerification =
    [ testCase "OnePath: Runs zero steps" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: error a
        actual <- runVerification
            (Limit 0)
            [simpleAxiom Mock.a Mock.b]
            [simpleOnePathClaim Mock.a Mock.b]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.a)
            actual
    , testCase "AllPath: Runs zero steps" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: error a
        actual <- runVerification
            (Limit 0)
            [simpleAxiom Mock.a Mock.b]
            [simpleAllPathClaim Mock.a Mock.b]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.a)
            actual
    , testCase "Mixed: Runs zero steps" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: error a
        actual <- runVerification
            (Limit 0)
            [simpleAxiom Mock.a Mock.b]
            [ simpleOnePathClaim Mock.a Mock.b
            , simpleAllPathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.a)
            actual
    , testCase "OnePath: Runs one step" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: error b
        -- Note that the check that we have reached the destination happens
        -- at the beginning of each step. At the beginning of the first step
        -- the pattern is 'a', so we didn't reach our destination yet, even if
        -- the rewrite transforms 'a' into 'b'. We detect the success at the
        -- beginning of the second step, which does not run here.
        actual <- runVerification
            (Limit 1)
            [simpleAxiom Mock.a Mock.b]
            [simpleOnePathClaim Mock.a Mock.b]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "AllPath: Runs one step" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: error b
        -- Note that the check that we have reached the destination happens
        -- at the beginning of each step. At the beginning of the first step
        -- the pattern is 'a', so we didn't reach our destination yet, even if
        -- the rewrite transforms 'a' into 'b'. We detect the success at the
        -- beginning of the second step, which does not run here.
        actual <- runVerification
            (Limit 1)
            [simpleAxiom Mock.a Mock.b]
            [simpleAllPathClaim Mock.a Mock.b]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "Mixed: Runs one step" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: error b
        -- Note that the check that we have reached the destination happens
        -- at the beginning of each step. At the beginning of the first step
        -- the pattern is 'a', so we didn't reach our destination yet, even if
        -- the rewrite transforms 'a' into 'b'. We detect the success at the
        -- beginning of the second step, which does not run here.
        actual <- runVerification
            (Limit 1)
            [simpleAxiom Mock.a Mock.b]
            [ simpleOnePathClaim Mock.a Mock.b
            , simpleAllPathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "OnePath: Returns first failing claim" $ do
        -- Axiom: a => b or c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 1)
            [simpleAxiom Mock.a (mkOr Mock.b Mock.c)]
            [simpleOnePathClaim Mock.a Mock.d]
        assertEqual ""
            (Left . Pattern.fromTermLike $ Mock.b)
            actual
    , testCase "AllPath: Returns first failing claim" $ do
        -- Axiom: a => b or c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 1)
            [simpleAxiom Mock.a (mkOr Mock.b Mock.c)]
            [simpleAllPathClaim Mock.a Mock.d]
        assertEqual ""
            (Left . Pattern.fromTermLike $ Mock.b)
            actual
    , testCase "Mixed: Returns first failing claim" $ do
        -- Axiom: a => b or c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 1)
            [simpleAxiom Mock.a (mkOr Mock.b Mock.c)]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.a Mock.d
            ]
        assertEqual ""
            (Left . Pattern.fromTermLike $ Mock.b)
            actual
    , testCase "OnePath: Verifies one claim" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 2)
            [simpleAxiom Mock.a Mock.b]
            [simpleOnePathClaim Mock.a Mock.b]
        assertEqual ""
            (Right ())
            actual
    , testCase "AllPath: Verifies one claim" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 2)
            [simpleAxiom Mock.a Mock.b]
            [simpleAllPathClaim Mock.a Mock.b]
        assertEqual ""
            (Right ())
            actual
    , testCase "Mixed: Verifies one claim" $ do
        -- Axiom: a => b
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 2)
            [simpleAxiom Mock.a Mock.b]
            [ simpleOnePathClaim Mock.a Mock.b
            , simpleAllPathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "OnePath: Trusted claim cannot prove itself" $ do
        -- Trusted Claim: a => b
        -- Expected: error a
        actual <- runVerification
            (Limit 4)
            []
            [ simpleOnePathTrustedClaim Mock.a Mock.b
            , simpleOnePathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.a)
            actual
    , testCase "AllPath: Trusted claim cannot prove itself" $ do
        -- Trusted Claim: a => b
        -- Expected: error a
        actual <- runVerification
            (Limit 4)
            []
            [ simpleAllPathTrustedClaim Mock.a Mock.b
            , simpleAllPathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.a)
            actual
    , testCase "Mixed: Trusted claim cannot prove itself" $ do
        -- Trusted Claim: a => b
        -- Expected: error a
        actual <- runVerification
            (Limit 4)
            []
            [ simpleOnePathTrustedClaim Mock.a Mock.b
            , simpleOnePathClaim Mock.a Mock.b
            , simpleAllPathTrustedClaim Mock.a Mock.b
            , simpleAllPathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.a)
            actual
    , testCase "OnePath: Verifies one claim multiple steps" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Claim: a => c
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            ]
            [simpleOnePathClaim Mock.a Mock.c]
        assertEqual ""
            (Right ())
            actual
    , testCase "AllPath: Verifies one claim multiple steps" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Claim: a => c
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            ]
            [simpleAllPathClaim Mock.a Mock.c]
        assertEqual ""
            (Right ())
            actual
    , testCase "Mixed: Verifies one claim multiple steps" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Claim: a => c
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            ]
            [ simpleOnePathClaim Mock.a Mock.c
            , simpleAllPathClaim Mock.a Mock.c
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "OnePath: Verifies one claim stops early" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            ]
            [simpleOnePathClaim Mock.a Mock.c]
        assertEqual ""
            (Right ())
            actual
    , testCase "AllPath: Verifies one claim stops early" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            ]
            [simpleAllPathClaim Mock.a Mock.c]
        assertEqual ""
            (Right ())
            actual
    , testCase "Mixed: Verifies one claim stops early" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            ]
            [ simpleOnePathClaim Mock.a Mock.c
            , simpleAllPathClaim Mock.a Mock.c
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "OnePath: Verifies one claim with branching" $ do
        -- Axiom: constr11(a) => b
        -- Axiom: constr11(x) => b
        -- Axiom: constr10(x) => constr11(x)
        -- Claim: constr10(x) => b
        -- Expected: success
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom (Mock.functionalConstr11 Mock.a) Mock.b
            , simpleAxiom (Mock.functionalConstr11 (mkElemVar Mock.x)) Mock.b
            , simpleAxiom
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                (Mock.functionalConstr11 (mkElemVar Mock.x))
            ]
            [ simpleOnePathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            ]
        assertEqual "" (Right ()) actual
    , testCase "AllPath: Verifies one claim with branching" $ do
        -- Axiom: constr11(a) => b
        -- Axiom: constr11(x) => b
        -- Axiom: constr10(x) => constr11(x)
        -- Claim: constr10(x) => b
        -- Expected: success
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom (Mock.functionalConstr11 Mock.a) Mock.b
            , simpleAxiom (Mock.functionalConstr11 (mkElemVar Mock.x)) Mock.b
            , simpleAxiom
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                (Mock.functionalConstr11 (mkElemVar Mock.x))
            ]
            [ simpleAllPathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            ]
        assertEqual "" (Right ()) actual
    , testCase "Mixed: Verifies one claim with branching" $ do
        -- Axiom: constr11(a) => b
        -- Axiom: constr11(x) => b
        -- Axiom: constr10(x) => constr11(x)
        -- Claim: constr10(x) => b
        -- Expected: success
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom (Mock.functionalConstr11 Mock.a) Mock.b
            , simpleAxiom (Mock.functionalConstr11 (mkElemVar Mock.x)) Mock.b
            , simpleAxiom
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                (Mock.functionalConstr11 (mkElemVar Mock.x))
            ]
            [ simpleOnePathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            , simpleAllPathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            ]
        assertEqual "" (Right ()) actual
    , testCase "OnePath: Partial verification failure" $ do
        -- Axiom: constr11(a) => b
        -- Axiom: constr10(x) => constr11(x)
        -- Claim: constr10(x) => b
        -- Expected: error constr11(x) and x != a
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom (Mock.functionalConstr11 Mock.a) Mock.b
            , simpleAxiom
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                (Mock.functionalConstr11 (mkElemVar Mock.x))
            ]
            [ simpleOnePathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            ]
        assertEqual ""
            (Left Conditional
                { term = Mock.functionalConstr11 (mkElemVar Mock.x)
                , predicate =
                    makeNotPredicate $ makeEqualsPredicate_ (mkElemVar Mock.x) Mock.a
                , substitution = mempty
                }
            )
            actual
    , testCase "AllPath: Partial verification failure" $ do
        -- Axiom: constr11(a) => b
        -- Axiom: constr10(x) => constr11(x)
        -- Claim: constr10(x) => b
        -- Expected: error constr11(x) and x != a
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom (Mock.functionalConstr11 Mock.a) Mock.b
            , simpleAxiom
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                (Mock.functionalConstr11 (mkElemVar Mock.x))
            ]
            [ simpleAllPathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            ]
        assertEqual ""
            (Left Conditional
                { term = Mock.functionalConstr11 (mkElemVar Mock.x)
                , predicate =
                    makeNotPredicate $ makeEqualsPredicate_ (mkElemVar Mock.x) Mock.a
                , substitution = mempty
                }
            )
            actual
    , testCase "Mixed: Partial verification failure" $ do
        -- Axiom: constr11(a) => b
        -- Axiom: constr10(x) => constr11(x)
        -- Claim: constr10(x) => b
        -- Expected: error constr11(x) and x != a
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom (Mock.functionalConstr11 Mock.a) Mock.b
            , simpleAxiom
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                (Mock.functionalConstr11 (mkElemVar Mock.x))
            ]
            [ simpleOnePathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            , simpleAllPathClaim
                (Mock.functionalConstr10 (mkElemVar Mock.x))
                Mock.b
            ]
        assertEqual ""
            (Left Conditional
                { term = Mock.functionalConstr11 (mkElemVar Mock.x)
                , predicate =
                    makeNotPredicate $ makeEqualsPredicate_ (mkElemVar Mock.x) Mock.a
                , substitution = mempty
                }
            )
            actual
    , testCase "OnePath: Verifies two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => c
        -- Claim: d => e
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleOnePathClaim Mock.a Mock.c
            , simpleOnePathClaim Mock.d Mock.e
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "AllPath: Verifies two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => c
        -- Claim: d => e
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleAllPathClaim Mock.a Mock.c
            , simpleAllPathClaim Mock.d Mock.e
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "Mixed: Verifies two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => c
        -- Claim: d => e
        -- Expected: success
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleAllPathClaim Mock.a Mock.c
            , simpleOnePathClaim Mock.d Mock.e
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "OnePath: fails first of two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => e
        -- Claim: d => e
        -- Expected: error c
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleOnePathClaim Mock.a Mock.e
            , simpleOnePathClaim Mock.d Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.c)
            actual
    , testCase "AllPath: fails first of two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => e
        -- Claim: d => e
        -- Expected: error c
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleAllPathClaim Mock.a Mock.e
            , simpleAllPathClaim Mock.d Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.c)
            actual
    , testCase "Mixed: fails first of two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => e
        -- Claim: d => e
        -- Expected: error c
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleOnePathClaim Mock.a Mock.e
            , simpleAllPathClaim Mock.d Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.c)
            actual
    , testCase "OnePath: fails second of two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => c
        -- Claim: d => c
        -- Expected: error e
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleOnePathClaim Mock.a Mock.c
            , simpleOnePathClaim Mock.d Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.e)
            actual
    , testCase "AllPath: fails second of two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => c
        -- Claim: d => c
        -- Expected: error e
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleAllPathClaim Mock.a Mock.c
            , simpleAllPathClaim Mock.d Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.e)
            actual
    , testCase "Mixed: fails second of two claims" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: d => e
        -- Claim: a => c
        -- Claim: d => c
        -- Expected: error e
        actual <- runVerification
            (Limit 3)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.d Mock.e
            ]
            [ simpleOnePathClaim Mock.a Mock.c
            , simpleAllPathClaim Mock.d Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.e)
            actual
    , testCase "OnePath: second proves first but fails" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => c
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleOnePathClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "AllPath: second proves first but fails" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => c
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleAllPathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "Mixed: second proves first but fails" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => c
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleOnePathClaim Mock.b Mock.c
            , simpleAllPathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "Mixed: different claim types so\
               \ second can't prove first" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => c
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "OnePath: first proves second but fails" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: b => c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.b Mock.c
            , simpleOnePathClaim Mock.a Mock.d
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "AllPath: first proves second but fails" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: b => c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleAllPathClaim Mock.b Mock.c
            , simpleAllPathClaim Mock.a Mock.d
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "Mixed: first proves second but fails" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: b => c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.b Mock.c
            , simpleOnePathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.c
            , simpleAllPathClaim Mock.a Mock.d
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "Mixed: first doesn't prove second\
               \ because they are different claim types" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: b => c
        -- Claim: a => d
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.b Mock.c
            , simpleAllPathClaim Mock.a Mock.d
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "OnePath: trusted second proves first" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Trusted Claim: b => c
        -- Expected: success
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleOnePathTrustedClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "AllPath: trusted second proves first" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Trusted Claim: b => c
        -- Expected: success
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleAllPathClaim Mock.a Mock.d
            , simpleAllPathTrustedClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "Mixed: trusted second proves first" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Trusted Claim: b => c
        -- Expected: success
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleOnePathTrustedClaim Mock.b Mock.c
            , simpleAllPathClaim Mock.a Mock.d
            , simpleAllPathTrustedClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Right ())
            actual
    , testCase "Mixed: trusted second doesn't prove first\
               \ because of different claim types" $ do
        -- Axiom: a => b
        -- Axiom: c => d
        -- Claim: a => d
        -- Trusted Claim: b => c
        -- Expected: error b
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleAllPathTrustedClaim Mock.b Mock.c
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.b)
            actual
    , testCase "OnePath: Prefers using claims for rewriting" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => e
        -- Expected: error e
        --    first verification: a=>b=>e,
        --        without second claim would be: a=>b=>c=>d
        --    second verification: b=>c=>d, not visible here
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleOnePathClaim Mock.b Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.e)
            actual
    , testCase "AllPath: Prefers using claims for rewriting" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => e
        -- Expected: error e
        --    first verification: a=>b=>e,
        --        without second claim would be: a=>b=>c=>d
        --    second verification: b=>c=>d, not visible here
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleAllPathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.e)
            actual
    , testCase "Mixed: Prefers using claims for rewriting" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => e
        -- Expected: error e
        --    first verification: a=>b=>e,
        --        without second claim would be: a=>b=>c=>d
        --    second verification: b=>c=>d, not visible here
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleOnePathClaim Mock.b Mock.e
            , simpleAllPathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.e)
            actual
    , testCase "Mixed: Doesn't apply claim because of\
               \ different claim type" $ do
        -- Axiom: a => b
        -- Axiom: b => c
        -- Axiom: c => d
        -- Claim: a => d
        -- Claim: b => e
        -- Expected: error d
        --    first verification: a=>b=>c=>d
        --    second verification: b=>c=>d is now visible here
        actual <- runVerification
            (Limit 4)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.b Mock.c
            , simpleAxiom Mock.c Mock.d
            ]
            [ simpleOnePathClaim Mock.a Mock.d
            , simpleAllPathClaim Mock.b Mock.e
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.d)
            actual
    , testCase "OnePath: Provable using one-path; not provable\
               \ using all-path" $ do
        -- Axioms:
        --     a => b
        --     a => c
        -- Claim: a => b
        -- Expected: success
        actual <- runVerification
            (Limit 5)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.a Mock.c
            ]
            [ simpleOnePathClaim Mock.a Mock.b ]
        assertEqual ""
            (Right ())
            actual
    , testCase "AllPath: Provable using one-path; not provable\
               \ using all-path" $ do
        -- Axioms:
        --     a => b
        --     a => c
        -- Claim: a => b
        -- Expected: error c
        actual <- runVerification
            (Limit 5)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.a Mock.c
            ]
            [ simpleAllPathClaim Mock.a Mock.b ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.c)
            actual
    , testCase "Mixed: Provable using one-path; not provable\
               \ using all-path" $ do
        -- Axioms:
        --     a => b
        --     a => c
        -- Claim: a => b
        -- Expected: error c
        actual <- runVerification
            (Limit 5)
            [ simpleAxiom Mock.a Mock.b
            , simpleAxiom Mock.a Mock.c
            ]
            [ simpleOnePathClaim Mock.a Mock.b
            , simpleAllPathClaim Mock.a Mock.b
            ]
        assertEqual ""
            (Left $ Pattern.fromTermLike Mock.c)
            actual
    ]

simpleAxiom
    :: TermLike Variable
    -> TermLike Variable
    -> Rule (ReachabilityRule Variable)
simpleAxiom left right =
    ReachabilityRewriteRule $ simpleRewrite left right

simpleOnePathClaim
    :: TermLike Variable
    -> TermLike Variable
    -> ReachabilityRule Variable
simpleOnePathClaim left right =
    OnePath . OnePathRule . getRewriteRule $ simpleRewrite left right

simpleAllPathClaim
    :: TermLike Variable
    -> TermLike Variable
    -> ReachabilityRule Variable
simpleAllPathClaim left right =
    AllPath . AllPathRule . getRewriteRule $ simpleRewrite left right

simpleOnePathTrustedClaim
    :: TermLike Variable
    -> TermLike Variable
    -> ReachabilityRule Variable
simpleOnePathTrustedClaim left right =
    OnePath
    . OnePathRule
    $ RulePattern
            { left = left
            , antiLeft = Nothing
            , right = right
            , requires = makeTruePredicate_
            , ensures = makeTruePredicate_
            , attributes = def
                { Attribute.trusted = Attribute.Trusted True }
            }

simpleAllPathTrustedClaim
    :: TermLike Variable
    -> TermLike Variable
    -> ReachabilityRule Variable
simpleAllPathTrustedClaim left right =
    AllPath
    . AllPathRule
    $ RulePattern
            { left = left
            , antiLeft = Nothing
            , right = right
            , requires = makeTruePredicate_
            , ensures = makeTruePredicate_
            , attributes = def
                { Attribute.trusted = Attribute.Trusted True }
            }
