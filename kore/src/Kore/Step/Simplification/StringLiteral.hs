{-|
Module      : Kore.Step.Simplification.StringLiteral
Description : Tools for StringLiteral pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.StringLiteral
    ( simplify
    ) where

import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
    ( fromTermLike
    )
import Kore.Internal.TermLike

{-| 'simplify' simplifies a 'StringLiteral' pattern, which means returning
an or containing a term made of that literal.
-}
simplify :: InternalVariable variable => StringLiteral -> Pattern variable
simplify (StringLiteral str) = Pattern.fromTermLike $ mkStringLiteral str
