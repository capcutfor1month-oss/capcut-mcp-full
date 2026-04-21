import Config

# Only override the application env when the operator explicitly set
# CAPCUT_PATH. Without it, `CapcutMcp.CapCut.PathDiscovery.discover/0` falls
# back to `%LOCALAPPDATA%\CapCut\User Data\Projects\com.lveditor.draft`, which
# is the default install location on Windows.
if capcut_path = System.get_env("CAPCUT_PATH") do
  config :capcut_mcp, capcut_path: capcut_path
end
