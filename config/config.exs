import Config

config :capcut_mcp,
  capcut_path:
    System.get_env(
      "CAPCUT_PATH",
      "C:/Users/tspor/AppData/Local/CapCut/User Data/Projects/com.lveditor.draft"
    )

if config_env() == :test do
  config :capcut_mcp, start_mcp_server: false
end
