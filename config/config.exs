import Config

config :logger, level: :none

config :logger, :console,
  metadata: [:mcp_request_id, :mcp_method, :tool, :request_id],
  format: "$time [$level] $metadata$message\n"

if config_env() == :test do
  config :capcut_mcp,
    start_mcp_server: false,
    start_project_store: false,
    validate_file_exists: false

  # Allow `ExUnit.CaptureLog` to observe `Logger.warning/1` and above.
  # Kept at `:warning` so routine `:info` chatter from the dispatcher stays
  # out of the test log output.
  config :logger, level: :warning
end
