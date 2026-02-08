--- Legacy re-export shim for backward compatibility
--- All logic now lives in buddy.transport.router
--- This file can be removed once all external call sites are migrated.
return require("buddy.transport.router")
