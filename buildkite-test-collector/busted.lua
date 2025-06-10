local create_test_collector = require 'buildkite-test-collector.test_collector'

-- Main handler function
return function(options)
  local busted = require 'busted'
  local term = require 'term'

  -- Check if terminal supports UTF-8 characters
  local isatty = io.type(io.stdout) == 'file' and term.isatty(io.stdout)
  local supports_utf = isatty and not (package.config:sub(1, 1) == '\\' and not os.getenv("ANSICON"))

  -- Configuration
  local custom_token_var = os.getenv("BUILDKITE_ANALYTICS_TOKEN_VAR")
  local api_token = os.getenv("BUILDKITE_ANALYTICS_TOKEN")

  -- Support custom environment variable for token
  if custom_token_var and custom_token_var ~= "" then
    api_token = api_token or os.getenv(custom_token_var)
  end
  local api_url = os.getenv("BUILDKITE_ANALYTICS_URL") or "https://analytics-api.buildkite.com/v1/uploads"
  local upload_enabled = api_token and api_token ~= ""

  local config = {
    api_token = api_token,
    api_url = api_url,
    upload_enabled = upload_enabled,
    custom_token_var = custom_token_var
  }

  -- Choose appropriate terminal handler based on UTF support
  local terminal_handler_name = supports_utf and 'utfTerminal' or 'plainTerminal'
  local terminal_options = {
    arguments = {}
  }
  local terminal_handler = require('busted.outputHandlers.' .. terminal_handler_name)(terminal_options)

  -- Create test collector instance
  local TestCollector = create_test_collector()

  -- Subscribe to events using extracted handlers
  busted.subscribe({ 'test', 'start' }, function(element, parent)
    return TestCollector.handle_test_start(element, parent)
  end, { predicate = terminal_handler.cancelOnPending })

  busted.subscribe({ 'test', 'end' }, function(element, parent, status, debug)
    return TestCollector.handle_test_end(element, parent, status, debug)
  end, { predicate = terminal_handler.cancelOnPending })

  busted.subscribe({ 'failure', 'it' }, function(element, parent, message, trace)
    return TestCollector.handle_failure(element, parent, message, trace)
  end)

  busted.subscribe({ 'error', 'it' }, function(element, parent, message, trace)
    return TestCollector.handle_error(element, parent, message, trace)
  end)

  busted.subscribe({ 'exit' }, function()
    return TestCollector.handle_exit(config)
  end)

  -- Return the terminal handler for display, our event subscriptions handle JSON generation
  return terminal_handler
end
