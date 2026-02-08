--- Legacy re-export shim for backward compatibility
--- All logic now lives in buddy.transport.http.server
--- This file can be removed once all external call sites are migrated.
return require("buddy.transport.http.server")
