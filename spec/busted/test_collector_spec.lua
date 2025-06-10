local create_test_collector = require 'buildkite-test-collector.busted.test_collector'

describe("TestCollector", function()
  local TestCollector

  before_each(function()
    -- Create a fresh TestCollector instance for each test
    TestCollector = create_test_collector()
  end)

  describe("get_monotonic_time", function()
    it("should return a number", function()
      local time = TestCollector.get_monotonic_time()
      assert.is_number(time)
    end)

    it("should return increasing values when called multiple times", function()
      local time1 = TestCollector.get_monotonic_time()
      local time2 = TestCollector.get_monotonic_time()
      assert.is_true(time2 >= time1)
    end)
  end)

  describe("clean_string", function()
    it("should return nil for nil input", function()
      assert.is_nil(TestCollector.clean_string(nil))
    end)

    it("should convert non-string inputs to string", function()
      assert.equals("123", TestCollector.clean_string(123))
      assert.equals("true", TestCollector.clean_string(true))
    end)

    it("should strip ANSI color codes", function()
      local input = "\27[31mRed text\27[0m"
      local expected = "Red text"
      assert.equals(expected, TestCollector.clean_string(input))
    end)

    it("should strip multiple ANSI color codes", function()
      local input = "\27[31;1mBold red\27[32mGreen\27[0mNormal"
      local expected = "Bold redGreenNormal"
      assert.equals(expected, TestCollector.clean_string(input))
    end)

    it("should strip other escape sequences", function()
      local input = "\27[AUp arrow escape"
      local expected = "Up arrow escape"
      assert.equals(expected, TestCollector.clean_string(input))
    end)

    it("should handle strings without escape sequences", function()
      local input = "Normal text"
      assert.equals(input, TestCollector.clean_string(input))
    end)
  end)

  describe("extract_failure_reason", function()
    it("should return nil for nil input", function()
      assert.is_nil(TestCollector.extract_failure_reason(nil))
    end)

    it("should return first line of message", function()
      local message = "First line\nSecond line\nThird line"
      assert.equals("First line", TestCollector.extract_failure_reason(message))
    end)

    it("should handle single line messages", function()
      local message = "Single line error"
      assert.equals("Single line error", TestCollector.extract_failure_reason(message))
    end)

    it("should strip ANSI codes from first line", function()
      local message = "\27[31mRed error\27[0m\nSecond line"
      assert.equals("Red error", TestCollector.extract_failure_reason(message))
    end)

    it("should return nil for empty or whitespace-only strings", function()
      assert.is_nil(TestCollector.extract_failure_reason(""))
      assert.is_nil(TestCollector.extract_failure_reason("   "))
      assert.is_nil(TestCollector.extract_failure_reason("\n\n"))
    end)

    it("should handle carriage return line endings", function()
      local message = "First line\r\nSecond line"
      assert.equals("First line", TestCollector.extract_failure_reason(message))
    end)
  end)

  describe("build_failure_expanded", function()
    it("should return array format with expanded and backtrace", function()
      local result = TestCollector.build_failure_expanded(nil, nil, nil)
      assert.is_table(result)
      assert.equals(1, #result)
      assert.is_table(result[1].expanded)
      assert.is_table(result[1].backtrace)
    end)

    it("should extract lines from message excluding first line", function()
      local message = "First line\nSecond line\nThird line"
      local result = TestCollector.build_failure_expanded(nil, message, nil)

      assert.equals(2, #result[1].expanded)
      assert.equals("Second line", result[1].expanded[1])
      assert.equals("Third line", result[1].expanded[2])
    end)

    it("should skip empty lines in message", function()
      local message = "First line\n\nSecond line\n   \nThird line"
      local result = TestCollector.build_failure_expanded(nil, message, nil)

      assert.equals(2, #result[1].expanded)
      assert.equals("Second line", result[1].expanded[1])
      assert.equals("Third line", result[1].expanded[2])
    end)

    it("should extract backtrace from trace.traceback", function()
      local trace = { traceback = "stack line 1\nstack line 2\nstack line 3" }
      local result = TestCollector.build_failure_expanded(nil, nil, trace)

      assert.equals(3, #result[1].backtrace)
      assert.equals("stack line 1", result[1].backtrace[1])
      assert.equals("stack line 2", result[1].backtrace[2])
      assert.equals("stack line 3", result[1].backtrace[3])
    end)

    it("should use element trace if trace.traceback not available", function()
      local element = {
        trace = {
          short_src = "test.lua",
          currentline = 42
        }
      }
      local result = TestCollector.build_failure_expanded(element, nil, nil)

      assert.equals(1, #result[1].backtrace)
      assert.equals("test.lua:42", result[1].backtrace[1])
    end)

    it("should clean ANSI codes from message and backtrace", function()
      local message = "First line\n\27[31mSecond line\27[0m"
      local trace = { traceback = "\27[32mstack line\27[0m" }
      local result = TestCollector.build_failure_expanded(nil, message, trace)

      assert.equals("Second line", result[1].expanded[1])
      assert.equals("stack line", result[1].backtrace[1])
    end)
  end)

  describe("get_ci_env", function()
    local original_getenv
    
    before_each(function()
      -- Store original os.getenv
      original_getenv = os.getenv
    end)
    
    after_each(function()
      -- Restore original os.getenv
      os.getenv = original_getenv
    end)

    it("should detect Buildkite environment", function()
      os.getenv = function(var)
        local env_vars = {
          BUILDKITE_BUILD_ID = "build-123",
          BUILDKITE_BUILD_URL = "https://buildkite.com/build",
          BUILDKITE_BRANCH = "main"
        }
        return env_vars[var]
      end
      
      local result = TestCollector.get_ci_env()
      assert.equals("buildkite", result.CI)
      assert.equals("build-123", result.key)
      assert.equals("https://buildkite.com/build", result.url)
      assert.equals("main", result.branch)
    end)

    it("should detect GitHub Actions environment", function()
      os.getenv = function(var)
        local env_vars = {
          GITHUB_RUN_NUMBER = "123",
          GITHUB_ACTION = "test",
          GITHUB_RUN_ATTEMPT = "1",
          GITHUB_REPOSITORY = "owner/repo",
          GITHUB_RUN_ID = "456"
        }
        return env_vars[var]
      end
      
      local result = TestCollector.get_ci_env()
      assert.equals("github_actions", result.CI)
      assert.equals("test-123-1", result.key)
      assert.equals("https://github.com/owner/repo/actions/runs/456", result.url)
    end)

    it("should detect CircleCI environment", function()
      os.getenv = function(var)
        local env_vars = {
          CIRCLE_BUILD_NUM = "123",
          CIRCLE_WORKFLOW_ID = "workflow-456",
          CIRCLE_BUILD_URL = "https://circleci.com/build"
        }
        return env_vars[var]
      end
      
      local result = TestCollector.get_ci_env()
      assert.equals("circleci", result.CI)
      assert.equals("workflow-456-123", result.key)
      assert.equals("https://circleci.com/build", result.url)
    end)

    it("should detect generic CI environment", function()
      os.getenv = function(var)
        if var == "CI" then return "true" end
        return nil
      end
      
      local result = TestCollector.get_ci_env()
      assert.equals("generic", result.CI)
      assert.is_string(result.key)
      assert.is_true(result.key:match("lua%-busted%-%d+") ~= nil)
    end)

    it("should handle no CI environment", function()
      os.getenv = function(var) return nil end
      
      local result = TestCollector.get_ci_env()
      assert.is_nil(result.CI)
      assert.is_string(result.key)
      assert.is_true(result.key:match("lua%-busted%-%d+") ~= nil)
    end)
  end)

  describe("handle_test_start", function()
    it("should create current_test with basic properties", function()
      local element = { name = "test name" }
      local parent = nil

      TestCollector.handle_test_start(element, parent)
      local current = TestCollector.get_current_test()

      assert.is_not_nil(current)
      assert.equals("test name", current.name)
      assert.is_nil(current.scope)
      assert.equals("unknown", current.result)
    end)

    it("should set scope when parent exists", function()
      local element = { name = "test name" }
      local parent = { name = "describe block" }
      
      TestCollector.handle_test_start(element, parent)
      local current = TestCollector.get_current_test()
      
      -- The actual scope will be "describe block" from the mock handler
      assert.equals("describe block", current.scope)
    end)

    it("should set location and file_name from trace", function()
      local element = {
        name = "test name",
        trace = {
          short_src = "test.lua",
          currentline = 42
        }
      }

      TestCollector.handle_test_start(element, nil)
      local current = TestCollector.get_current_test()

      assert.equals("test.lua:42", current.location)
      assert.equals("test.lua", current.file_name)
    end)

    it("should initialize history with start time", function()
      local element = { name = "test name" }

      TestCollector.handle_test_start(element, nil)
      local current = TestCollector.get_current_test()

      assert.is_number(current.history.start_at)
      assert.equals(0, current.history.end_at)
      assert.equals(0, current.history.duration)
      assert.is_table(current.history.children)
    end)
  end)

  describe("handle_test_end", function()
    before_each(function()
      -- Setup a current test
      local element = { name = "test name" }
      TestCollector.handle_test_start(element, nil)
    end)

    it("should complete test timing and add to results", function()
      TestCollector.handle_test_end(nil, nil, "success", nil)

      local results = TestCollector.get_test_results()
      assert.equals(1, #results)

      local test = results[1]
      assert.is_number(test.history.end_at)
      assert.is_number(test.history.duration)
      assert.is_true(test.history.duration >= 0)
    end)

    it("should map success status to passed", function()
      TestCollector.handle_test_end(nil, nil, "success", nil)

      local results = TestCollector.get_test_results()
      assert.equals("passed", results[1].result)
    end)

    it("should map failure status to failed", function()
      TestCollector.handle_test_end(nil, nil, "failure", nil)

      local results = TestCollector.get_test_results()
      assert.equals("failed", results[1].result)
    end)

    it("should map error status to failed", function()
      TestCollector.handle_test_end(nil, nil, "error", nil)

      local results = TestCollector.get_test_results()
      assert.equals("failed", results[1].result)
    end)

    it("should map pending status to skipped", function()
      TestCollector.handle_test_end(nil, nil, "pending", nil)

      local results = TestCollector.get_test_results()
      assert.equals("skipped", results[1].result)
    end)

    it("should map unknown status to unknown", function()
      TestCollector.handle_test_end(nil, nil, "weird_status", nil)

      local results = TestCollector.get_test_results()
      assert.equals("unknown", results[1].result)
    end)

    it("should clear current_test after completion", function()
      TestCollector.handle_test_end(nil, nil, "success", nil)

      assert.is_nil(TestCollector.get_current_test())
    end)

    it("should handle no current test gracefully", function()
      TestCollector.reset_state() -- Clear current test

      -- Should not error
      TestCollector.handle_test_end(nil, nil, "success", nil)

      local results = TestCollector.get_test_results()
      assert.equals(0, #results)
    end)
  end)

  describe("handle_failure", function()
    before_each(function()
      local element = { name = "test name" }
      TestCollector.handle_test_start(element, nil)
    end)

    it("should set result to failed", function()
      TestCollector.handle_failure(nil, nil, "error message", nil)

      local current = TestCollector.get_current_test()
      assert.equals("failed", current.result)
    end)

    it("should extract failure reason from message", function()
      local message = "First line error\nSecond line details"
      TestCollector.handle_failure(nil, nil, message, nil)

      local current = TestCollector.get_current_test()
      assert.equals("First line error", current.failure_reason)
    end)

    it("should build failure_expanded", function()
      local message = "First line error\nSecond line details"
      local trace = { traceback = "stack trace line" }
      TestCollector.handle_failure(nil, nil, message, trace)

      local current = TestCollector.get_current_test()
      assert.is_table(current.failure_expanded)
      assert.equals(1, #current.failure_expanded)
    end)

    it("should handle no current test gracefully", function()
      TestCollector.reset_state()

      -- Should not error
      TestCollector.handle_failure(nil, nil, "error", nil)
    end)
  end)

  describe("handle_error", function()
    before_each(function()
      local element = { name = "test name" }
      TestCollector.handle_test_start(element, nil)
    end)

    it("should set result to failed", function()
      TestCollector.handle_error(nil, nil, "error message", nil)

      local current = TestCollector.get_current_test()
      assert.equals("failed", current.result)
    end)

    it("should extract failure reason from message", function()
      local message = "First line error\nSecond line details"
      TestCollector.handle_error(nil, nil, message, nil)

      local current = TestCollector.get_current_test()
      assert.equals("First line error", current.failure_reason)
    end)

    it("should build failure_expanded", function()
      local message = "First line error\nSecond line details"
      local trace = { traceback = "stack trace line" }
      TestCollector.handle_error(nil, nil, message, trace)

      local current = TestCollector.get_current_test()
      assert.is_table(current.failure_expanded)
      assert.equals(1, #current.failure_expanded)
    end)

    it("should handle no current test gracefully", function()
      TestCollector.reset_state()

      -- Should not error
      TestCollector.handle_error(nil, nil, "error", nil)
    end)
  end)

  describe("upload_to_buildkite", function()
    it("should return false for empty token", function()
      local success, message = TestCollector.upload_to_buildkite({}, "", "http://test.com")
      assert.is_false(success)
      assert.equals("No API token provided", message)
    end)

    it("should return false for nil token", function()
      local success, message = TestCollector.upload_to_buildkite({}, nil, "http://test.com")
      assert.is_false(success)
      assert.equals("No API token provided", message)
    end)

    -- Note: Testing actual curl execution would require mocking or integration tests
    -- These tests focus on the input validation and error handling logic
  end)



  describe("state management", function()
    it("should initialize with empty state", function()
      assert.is_nil(TestCollector.get_current_test())
      assert.equals(0, #TestCollector.get_test_results())
    end)

    it("should reset state properly", function()
      -- Create some state
      local element = { name = "test" }
      TestCollector.handle_test_start(element, nil)
      TestCollector.handle_test_end(nil, nil, "success", nil)

      assert.equals(1, #TestCollector.get_test_results())

      -- Reset state
      TestCollector.reset_state()

      assert.is_nil(TestCollector.get_current_test())
      assert.equals(0, #TestCollector.get_test_results())
    end)

    it("should maintain state independence between instances", function()
      local TestCollector2 = create_test_collector()

      -- Modify first instance
      local element = { name = "test1" }
      TestCollector.handle_test_start(element, nil)

      -- Second instance should be independent
      assert.is_nil(TestCollector2.get_current_test())
      assert.equals(0, #TestCollector2.get_test_results())
    end)
  end)
end)
