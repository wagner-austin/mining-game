--!nocheck
-- SafeRequire.lua
-- Tiny wrapper to perform dynamic ModuleScript requires without triggering
-- luau-lsp's "Unknown require: unsupported path" analysis warning.

return function(ms)
	return require(ms)
end
