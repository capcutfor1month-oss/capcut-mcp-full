import Config

config :capcut_mcp,
  capcut_path:
    System.get_env(
      "CAPCUT_PATH",
      "C:/Users/tspor/AppData/Local/CapCut/User Data/Projects/com.lveditor.draft"
    )
