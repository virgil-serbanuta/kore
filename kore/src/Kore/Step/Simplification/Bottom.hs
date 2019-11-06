{-|
Module      : Kore.Step.Simplification.Bottom
Description : Tools for Bottom pattern simplification.
Copyright   : (c) Runtime Verification, 2018
License     : NCSA
Maintainer  : virgil.serbanuta@runtimeverification.com
Stability   : experimental
Portability : portable
-}
module Kore.Step.Simplification.Bottom
    ( simplify
    ) where

import Kore.Internal.Pattern
    ( Pattern
    )
import qualified Kore.Internal.Pattern as Pattern
    ( bottom
    )
import Kore.Internal.Variable
    ( InternalVariable
    )
import Kore.Sort
import Kore.Syntax.Bottom

{-| simplifies a Bottom pattern, which means returning an always-false or.
-}
simplify :: InternalVariable variable => Bottom Sort child -> Pattern variable
simplify Bottom {} = Pattern.bottom
