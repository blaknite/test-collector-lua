# Custom Busted Output Handlers

This directory contains custom output handlers for the Busted Lua testing framework.

## test_engine.lua

A custom output handler that combines intelligent terminal display with direct upload to Buildkite Test Engine, providing rich test analytics and failure diagnostics for CI/CD integration.

### Usage

#### Basic usage:
```bash
busted -o buildkite-test-collector.busted
```

#### In Buildkite pipeline:
```yaml
steps:
  - name: ":lua: busted"
    command: busted -o buildkite-test-collector.busted
    env:
      BUILDKITE_ANALYTICS_TOKEN: "${YOUR_API_TOKEN}"
```

### Features

- **Smart Terminal Output**: Automatically detects terminal UTF-8 support and uses appropriate handler (`utfTerminal` for modern terminals, `plainTerminal` for CI environments like Buildkite web UI)
- **Direct Upload to Buildkite Test Engine**: Uploads test results directly to Buildkite Test Engine without requiring plugins or intermediate files
- **Rich Failure Diagnostics**: Captures detailed failure information with `failure_expanded` containing:
  - Detailed error messages and diffs
  - Complete stack traces with file locations
  - Line-by-line breakdown for better debugging
- **Single Test Run**: No need to run tests twice - get both terminal output and analytics upload in one execution
- **Complete Test Metadata**: Each test includes:
  - File locations and line numbers
  - Test scopes and hierarchical organization
  - Precise timing information
- **Automatic Retry Logic**: Built-in retry mechanism with exponential backoff for reliable uploads
- **CI/CD Ready**: Optimized for Buildkite Test Engine analytics with automatic CI environment detection

### How It Works

The handler:
1. **Detects terminal capabilities** using `term.isatty()` and environment checks
2. **Creates appropriate terminal handler** (`utfTerminal` or `plainTerminal`) for display
3. **Subscribes to Busted events** to collect test execution data in real-time
4. **Captures timing data** using Busted's monotonic time functions
5. **Detects CI environment** (Buildkite, GitHub Actions, CircleCI, etc.)
6. **Processes failures and errors** into detailed diagnostic information
7. **Uploads directly** to Buildkite Test Engine using curl with retry logic

### Buildkite Test Engine Integration

This handler is specifically designed for Buildkite's Test Engine, providing:

- **Test Analytics**: Historical performance and reliability metrics
- **Flaky Test Detection**: Automatic identification of unstable tests
- **Failure Analysis**: Rich diagnostic information with expandable details
- **Performance Tracking**: Test duration trends and optimization insights
- **Team Collaboration**: Shared test insights across development teams

### Upload Schema

The uploaded data follows the [Buildkite Test Engine specification](https://buildkite.com/docs/test-engine/importing-json):

```json
{
  "format": "json",
  "run_env": {
    "CI": "buildkite",
    "key": "build-id",
    "url": "build-url",
    "branch": "main",
    "commit_sha": "abc123",
    "number": "42"
  },
  "data": [
    {
      "scope": "Test Suite Name",
      "name": "specific test description",
      "location": "./spec/file_spec.lua:42",
      "file_name": "./spec/file_spec.lua",
      "result": "passed|failed|skipped",
      "failure_reason": "Short error summary (if failed)",
      "failure_expanded": [
        {
          "expanded": ["Detailed", "error", "lines"],
          "backtrace": ["Stack", "trace", "lines"]
        }
      ],
      "history": {
        "start_at": 12345.678,
        "end_at": 12345.789,
        "duration": 0.111,
        "children": []
      }
    }
  ]
}
```

### Environment Variables

Configure the handler using these environment variables:

- **`BUILDKITE_ANALYTICS_TOKEN`**: Your Test Engine API token (required for upload)
- **`BUILDKITE_ANALYTICS_TOKEN_VAR`**: Custom environment variable name containing the API token (optional)
- **`BUILDKITE_ANALYTICS_URL`**: Custom API endpoint (optional, defaults to `https://analytics-api.buildkite.com/v1/uploads`)

#### Custom Token Variable

If you need to use a different environment variable name for your API token, set `BUILDKITE_ANALYTICS_TOKEN_VAR`:

```yaml
# Using a custom token variable
env:
  BUILDKITE_ANALYTICS_TOKEN_VAR: "MY_CUSTOM_TOKEN"
  MY_CUSTOM_TOKEN: "${SECRET_API_TOKEN}"
```

This is useful when:
- Your organization uses standardized secret names
- You need to avoid conflicts with other tools
- You want to maintain consistent naming conventions

### Upload Behavior

- **With API token**: Automatically uploads test results after test completion
- **Without API token**: Displays helpful message about setting the token
- **Upload failure**: Shows error details but doesn't fail the test run
- **Network issues**: Retries with exponential backoff (3 attempts max)
- **Authentication errors**: Fails immediately with clear error message

### Requirements

- **curl**: Required for uploading results (automatically checked)
- **Lua libraries**: `term`, `dkjson` (typically available in Busted environments)
- **API token**: Buildkite Test Engine token for uploads

### Troubleshooting

**Upload fails with "curl not available":**
- Install curl: `apt-get install curl` or `brew install curl`
- Or use the test-collector plugin as fallback

**Authentication errors:**
- Verify your API token is correct
- Check that the token has Test Engine permissions
- Ensure the token environment variable is set correctly

**Network timeouts:**
- The handler automatically retries with exponential backoff
- Check your network connectivity and firewall settings
- Verify the API URL is accessible from your CI environment
