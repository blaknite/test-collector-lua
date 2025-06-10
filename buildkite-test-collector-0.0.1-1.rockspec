local package_name = "buildkite-test-collector"
local package_version = "0.0.1"
local rockspec_version = "1"

package = package_name
version = package_version .. "-" .. rockspec_version
source = {
   url = "git+https://github.com/blaknite/test-collector-lua.git",
   tag = "v0.0.1"
}
description = {
   summary = "Custom Busted output handler for Buildkite Test Engine integration",
   detailed = [[
      A custom output handler for the Busted Lua testing framework that combines
      intelligent terminal display with direct upload to Buildkite Test Engine.

      Features:
      - Smart terminal output with UTF-8 support detection
      - Direct upload to Buildkite Test Engine without plugins
      - Rich failure diagnostics with detailed stack traces
      - Automatic CI environment detection (Buildkite, GitHub Actions, CircleCI)
      - Built-in retry logic with exponential backoff
      - Single test run for both display and analytics

      Usage: busted -o buildkite-test-collector.busted
   ]],
   homepage = "https://github.com/blaknite/test-collector-lua"
}
dependencies = {
   "lua >= 5.1",
   "busted >= 2.0.0",
   "lua-term >= 0.1",
   "dkjson >= 2.5"
}
build = {
   type = "builtin",
   modules = {
      ["buildkite-test-collector.busted"] = "buildkite-test-collector/busted.lua",
   }
}
