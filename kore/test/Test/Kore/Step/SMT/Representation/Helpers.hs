module Test.Kore.Step.SMT.Representation.Helpers
    ( declarationsAre
    , smtForSortIs
    , smtForSymbolIs
    , testsForModule
    ) where

import Test.Tasty
import Test.Tasty.HUnit

import qualified Data.Map as Map

import qualified Kore.Attribute.Axiom as Attribute
    ( Axiom
    )
import qualified Kore.Attribute.Symbol as Attribute
    ( Symbol
    )
import Kore.IndexedModule.IndexedModule
    ( VerifiedModule
    )
import qualified Kore.Step.SMT.AST as AST
    ( Declarations (Declarations)
    , Sort (Sort)
    , Symbol (Symbol)
    )
import qualified Kore.Step.SMT.AST as AST.DoNotUse
import qualified Kore.Syntax.Id as Kore
    ( Id
    )
import qualified SMT.AST as AST
    ( showSExpr
    )

import Test.Kore.Comparators ()
import Test.Tasty.HUnit.Extensions

testsForModule
    :: String
    ->  (  VerifiedModule Attribute.Symbol Attribute.Axiom
        -> AST.Declarations sort symbol name
        )
    -> VerifiedModule Attribute.Symbol Attribute.Axiom
    -> [AST.Declarations sort symbol name -> TestTree]
    -> TestTree
testsForModule name functionToTest indexedModule tests =
    testGroup name (map (\f -> f declarations) tests)
  where
    declarations = functionToTest indexedModule

declarationsAre
    ::  ( HasCallStack
        , EqualWithExplanation sort, Show sort
        , EqualWithExplanation symbol, Show symbol
        , EqualWithExplanation name, Show name
        )
    => AST.Declarations sort symbol name
    -> AST.Declarations sort symbol name
    -> TestTree
declarationsAre expected actual =
    testCase "declarationsAre" (assertEqualWithExplanation "" expected actual)

smtForSortIs
    :: HasCallStack
    => Kore.Id
    -> String
    -> AST.Declarations sort symbol name
    -> TestTree
smtForSortIs
    sortId
    expectedSExpr
    AST.Declarations {sorts}
  =
    testCase "smtForSortIs" $
        case Map.lookup sortId sorts of
            Nothing ->
                assertFailure
                    (  "Key (" ++ show sortId
                    ++ ") not found in (" ++ show (Map.keysSet sorts)
                    ++ ")"
                    )
            Just AST.Sort {smtFromSortArgs} ->
                assertEqualWithExplanation
                    ""
                    (Just expectedSExpr)
                    (AST.showSExpr <$> smtFromSortArgs Map.empty [])

smtForSymbolIs
    :: HasCallStack
    => Kore.Id
    -> String
    -> AST.Declarations sort symbol name
    -> TestTree
smtForSymbolIs
    sortId
    expectedSExpr
    AST.Declarations {symbols}
  =
    testCase "smtForSymbolIs" $
        case Map.lookup sortId symbols of
            Nothing ->
                assertFailure
                    (  "Key (" ++ show sortId
                    ++ ") not found in (" ++ show (Map.keysSet symbols)
                    ++ ")"
                    )
            Just AST.Symbol {smtFromSortArgs} ->
                assertEqualWithExplanation
                    ""
                    (Just expectedSExpr)
                    (AST.showSExpr <$> smtFromSortArgs Map.empty [])
