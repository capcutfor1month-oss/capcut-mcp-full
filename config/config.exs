import Config

config :logger, level: :none

if config_env() == :test do
  config :capcut_mcp,
    start_mcp_server: false,
    start_project_store: false,
    validate_file_exists: false
end
