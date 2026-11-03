{-# LANGUAGE CPP #-}
-- | Query plan computation for WASM: the JavaScript export of the web
-- editor's query planner, 'L4.Decision.EditorQueryPlan.l4QueryPlan'.
module QueryPlanWasm (l4QueryPlan) where

import L4.Decision.EditorQueryPlan (l4QueryPlan)

#if defined(wasm32_HOST_ARCH)
import qualified Data.Text as Text
import GHC.Wasm.Prim (JSString(..), fromJSString, toJSString)
#endif

-- ----------------------------------------------------------------------------
-- JavaScript FFI Exports (WASM backend only)
-- ----------------------------------------------------------------------------

#if defined(wasm32_HOST_ARCH)

foreign export javascript "l4_query_plan"
  js_l4_query_plan :: JSString -> JSString -> JSString -> JSString -> IO JSString

js_l4_query_plan :: JSString -> JSString -> JSString -> JSString -> IO JSString
js_l4_query_plan source uri functionName bindingsJson =
  pure $ toJSString $ Text.unpack $
    l4QueryPlan
      (Text.pack $ fromJSString source)
      (Text.pack $ fromJSString uri)
      (Text.pack $ fromJSString functionName)
      (Text.pack $ fromJSString bindingsJson)

#endif
