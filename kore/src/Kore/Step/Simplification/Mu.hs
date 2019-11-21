{-|
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
-}
module Kore.Step.Simplification.Mu
    ( simplify
    ) where

import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
    ( fromTermLike
    , isSimplified
    , toTermLike
    )
import Kore.Internal.TermLike
    ( InternalVariable
    , Mu (Mu)
    , SetVariable
    , mkMu
    )
import qualified Kore.Internal.TermLike as TermLike
    ( markSimplified
    )
import qualified Kore.Internal.TermLike as TermLike.DoNotUse
import Kore.Step.Simplification.Simplifiable
    ( Simplifiable
    , SimplifiedChildren (SimplifiedChildren)
    )
import qualified Kore.Step.Simplification.Simplifiable as Simplifiable
    ( fromOrPattern
    )

{-|'simplify' simplifies a 'Mu' pattern with an 'OrPattern'
child.
-}
simplify
    :: InternalVariable variable
    => Mu variable (SimplifiedChildren variable)
    -> Simplifiable variable
simplify Mu { muVariable, muChild = SimplifiedChildren child } =
    Simplifiable.fromOrPattern (makeEvaluate muVariable <$> child)

{-| evaluates a 'Mu' given its two 'Pattern' children.

See 'simplify' for detailed documentation.
-}
makeEvaluate
    :: InternalVariable variable
    => SetVariable variable
    -> Pattern variable
    -> Pattern variable
makeEvaluate variable patt =
    Pattern.fromTermLike
    $ (if Pattern.isSimplified patt then TermLike.markSimplified else id)
    $ mkMu variable
    $ Pattern.toTermLike patt
