local handler = require 'busted.outputHandlers.base' ()

-- Factory function to create TestCollector with upvalues for state
local function create_test_collector()
  local TestCollector = {}

  -- State stored as upvalues
  local test_results = {}
  local current_test = nil

  -- Initialize random seed for UUID generation
  math.randomseed(os.time())

  -- Helper function to get monotonic time
  function TestCollector.get_monotonic_time()
    local busted = require 'busted'
    return busted.monotime and busted.monotime() or os.clock()
  end

  -- Helper function to strip ANSI color codes and clean strings
  function TestCollector.clean_string(str)
    if not str then return nil end
    local result = tostring(str)
    -- Strip ANSI color escape sequences
    result = result:gsub('\27%[[%d;]*m', '')
    -- Strip other common escape sequences
    result = result:gsub('\27%[[%a]', '')
    return result
  end

  -- Helper function to extract failure reason (first line only)
  function TestCollector.extract_failure_reason(message)
    if not message then return nil end
    local clean_message = TestCollector.clean_string(message)
    -- Return only the first line as the summary
    local first_line = clean_message:match("([^\r\n]*)")
    return first_line and first_line:match("%S") and first_line or nil
  end

  -- Helper function to build failure_expanded array matching Test Engine schema
  function TestCollector.build_failure_expanded(element, message, trace)
    local expanded = {}
    local backtrace = {}

    if message then
      -- Split message into lines for expanded, cleaning each line
      local clean_message = TestCollector.clean_string(message)
      local lines = {}
      for line in string.gmatch(clean_message, "[^\r\n]+") do
        if line and line:match("%S") then -- only non-empty lines
          table.insert(lines, line)
        end
      end

      -- Skip the first line since it's already in failure_reason
      for i = 2, #lines do
        table.insert(expanded, lines[i])
      end
    end

    if trace and trace.traceback then
      -- Split traceback into lines for backtrace
      for line in string.gmatch(trace.traceback, "[^\r\n]+") do
        if line and line:match("%S") then -- only non-empty lines
          table.insert(backtrace, TestCollector.clean_string(line))
        end
      end
    elseif element and element.trace then
      -- Use element trace if available
      local trace_str = element.trace.short_src .. ":" .. element.trace.currentline
      table.insert(backtrace, trace_str)
    end

    -- Return array format matching Test Engine schema
    return {
      {
        expanded = expanded,
        backtrace = backtrace
      }
    }
  end

  -- Helper function to detect CI environment
  function TestCollector.get_ci_env()
    -- Buildkite
    if os.getenv("BUILDKITE_BUILD_ID") then
      return {
        CI = "buildkite",
        key = os.getenv("BUILDKITE_BUILD_ID"),
        url = os.getenv("BUILDKITE_BUILD_URL"),
        branch = os.getenv("BUILDKITE_BRANCH"),
        commit_sha = os.getenv("BUILDKITE_COMMIT"),
        number = os.getenv("BUILDKITE_BUILD_NUMBER"),
        job_id = os.getenv("BUILDKITE_JOB_ID"),
        message = os.getenv("BUILDKITE_MESSAGE")
      }
      -- GitHub Actions
    elseif os.getenv("GITHUB_RUN_NUMBER") then
      return {
        CI = "github_actions",
        key = string.format("%s-%s-%s",
          os.getenv("GITHUB_ACTION") or "",
          os.getenv("GITHUB_RUN_NUMBER") or "",
          os.getenv("GITHUB_RUN_ATTEMPT") or "1"),
        url = string.format("https://github.com/%s/actions/runs/%s",
          os.getenv("GITHUB_REPOSITORY") or "",
          os.getenv("GITHUB_RUN_ID") or ""),
        branch = os.getenv("GITHUB_REF_NAME"),
        commit_sha = os.getenv("GITHUB_SHA"),
        number = os.getenv("GITHUB_RUN_NUMBER")
      }
      -- CircleCI
    elseif os.getenv("CIRCLE_BUILD_NUM") then
      return {
        CI = "circleci",
        key = string.format("%s-%s",
          os.getenv("CIRCLE_WORKFLOW_ID") or "",
          os.getenv("CIRCLE_BUILD_NUM") or ""),
        url = os.getenv("CIRCLE_BUILD_URL"),
        branch = os.getenv("CIRCLE_BRANCH"),
        commit_sha = os.getenv("CIRCLE_SHA1"),
        number = os.getenv("CIRCLE_BUILD_NUM")
      }
      -- Generic CI
    elseif os.getenv("CI") then
      return {
        CI = "generic",
        key = string.format("lua-busted-%d", os.time())
      }
    else
      return {
        CI = nil,
        key = string.format("lua-busted-%d", os.time())
      }
    end
  end

  -- Helper function to upload data to Buildkite Test Engine using curl
  function TestCollector.upload_to_buildkite(data, api_token, api_url)
    if not api_token or api_token == "" then
      return false, "No API token provided"
    end

    -- Check if curl is available
    local curl_check = os.execute("which curl >/dev/null 2>&1")
    if not curl_check then
      return false, "curl not available - install curl or use test-collector plugin"
    end

    local json = require 'dkjson'
    local payload = {
      format = "json",
      run_env = TestCollector.get_ci_env(),
      data = data
    }

    local json_body = json.encode(payload)

    -- Write JSON to temporary file
    local temp_file = os.tmpname()
    local file = io.open(temp_file, 'w')
    if not file then
      return false, "Could not create temporary file for upload"
    end
    file:write(json_body)
    file:close()

    -- Retry logic
    local max_retries = 3
    local retry_delay = 1

    for attempt = 1, max_retries do
      -- Use curl to upload with timeout and retry settings
      local curl_cmd = string.format(
        'curl -s -w "%%{http_code}" --max-time 30 --retry 0 -X POST -H "Authorization: Token token=\\"%s\\"" -H "Content-Type: application/json" -d @%s %s 2>/dev/null',
        api_token, temp_file, api_url
      )

      local handle = io.popen(curl_cmd, 'r')
      if not handle then
        os.remove(temp_file)
        return false, "Could not execute curl command"
      end

      local result = handle:read('*a')
      local exit_code = handle:close()

      if not exit_code then
        os.remove(temp_file)
        return false, "Could not execute curl command"
      end

      if not result and #result < 3 then
        if attempt < max_retries then
          os.execute(string.format("sleep %d", retry_delay))
          retry_delay = retry_delay * 2
        else
          os.remove(temp_file)
          return false, string.format("Upload failed after %d attempts: No response from server", max_retries)
        end
      end

      -- Extract status code from curl output (last 3 characters)
      local status_code = result:sub(-3)
      local response_body = result:sub(1, -4)

      if status_code == "202" then
        os.remove(temp_file)
        return true, "Upload successful"
      elseif status_code == "401" or status_code == "403" then
        -- Don't retry auth errors
        os.remove(temp_file)
        return false, string.format("Authentication failed (status %s): %s", status_code, response_body)
      elseif attempt < max_retries then
        -- Retry on other errors
        os.execute(string.format("sleep %d", retry_delay))
        retry_delay = retry_delay * 2 -- exponential backoff
      else
        os.remove(temp_file)
        return false,
            string.format("Upload failed after %d attempts (status %s): %s", max_retries, status_code, response_body)
      end
    end

    os.remove(temp_file)
    return false, "Upload failed: Maximum retries exceeded"
  end

  -- Event handlers using upvalues for state
  function TestCollector.handle_test_start(element, parent)
    local test_start_time = TestCollector.get_monotonic_time()

    current_test = {
      scope = parent and handler.getFullName(parent) or nil,
      name = element.name,
      location = element.trace and (element.trace.short_src .. ":" .. element.trace.currentline),
      file_name = element.trace and element.trace.short_src,
      result = "unknown",
      history = {
        start_at = test_start_time,
        end_at = 0,
        duration = 0,
        children = {}
      }
    }

    return nil, true
  end

  function TestCollector.handle_test_end(element, parent, status, debug)
    if current_test then
      local test_end_time = TestCollector.get_monotonic_time()
      current_test.history.end_at = test_end_time
      current_test.history.duration = test_end_time - current_test.history.start_at

      -- Map busted status to Test Engine format
      if status == 'success' then
        current_test.result = "passed"
      elseif status == 'failure' then
        current_test.result = "failed"
      elseif status == 'error' then
        current_test.result = "failed"
      elseif status == 'pending' then
        current_test.result = "skipped"
      else
        current_test.result = "unknown"
      end

      -- Create final test object, removing nil values
      local final_test = {}
      for key, value in pairs(current_test) do
        if value ~= nil then
          final_test[key] = value
        end
      end

      table.insert(test_results, final_test)
      current_test = nil
    end

    return nil, true
  end

  function TestCollector.handle_failure(element, parent, message, trace)
    if current_test then
      current_test.result = "failed"
      current_test.failure_reason = TestCollector.extract_failure_reason(message)
      current_test.failure_expanded = TestCollector.build_failure_expanded(element, message, trace)
    end

    return nil, true
  end

  function TestCollector.handle_error(element, parent, message, trace)
    if current_test then
      current_test.result = "failed"
      current_test.failure_reason = TestCollector.extract_failure_reason(message)
      current_test.failure_expanded = TestCollector.build_failure_expanded(element, message, trace)
    end

    return nil, true
  end

  function TestCollector.handle_exit(config)
    if config.upload_enabled then
      print('\nUploading test results to Buildkite Test Engine...')
      local success, message = TestCollector.upload_to_buildkite(test_results, config.api_token, config.api_url)
      if success then
        print('✅ ' .. message)
      else
        print('💥 ' .. message)
      end
    elseif config.api_token and config.api_token == "" then
      print('\n⚠️  Buildkite Test Engine upload disabled (empty token)')
    else
      local token_var_msg = "BUILDKITE_ANALYTICS_TOKEN"
      if config.custom_token_var and config.custom_token_var ~= "" then
        token_var_msg = config.custom_token_var .. " (or BUILDKITE_ANALYTICS_TOKEN)"
      end
      print('\n💡 To upload to Buildkite Test Engine, set ' .. token_var_msg .. ' environment variable')
    end

    return nil, true
  end

  -- State accessors for testing/debugging
  function TestCollector.get_current_test()
    return current_test
  end

  function TestCollector.get_test_results()
    return test_results
  end

  function TestCollector.reset_state()
    test_results = {}
    current_test = nil
  end

  return TestCollector
end

return create_test_collector
