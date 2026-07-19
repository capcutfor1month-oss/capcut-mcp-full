defmodule CapcutMcp.CapCut.PathDiscovery do
  @moduledoc """
  Locates the CapCut Projects root directory (the folder that contains
  `root_meta_info.json` and one sub-folder per draft).

  Resolution strategy, first match wins:

    1. `:capcut_path` application env — populated from the `CAPCUT_PATH`
       environment variable in `config/runtime.exs`.
    2. `%LOCALAPPDATA%\\CapCut\\User Data\\Projects\\com.lveditor.draft`
       if that directory actually exists on disk (Windows).
    3. `~/Movies/CapCut/User Data/Projects/com.lveditor.draft` if that
       directory actually exists on disk (macOS — this is where the
       desktop app stores drafts; confirmed against a real install).

  If none hit, `discover/0` returns a descriptive error that callers can
  surface to the user verbatim — no need for the caller to re-inspect env
  vars to produce a helpful message.
  """

  @projects_subpath ["CapCut", "User Data", "Projects", "com.lveditor.draft"]
  @macos_subpath ["Movies", "CapCut", "User Data", "Projects", "com.lveditor.draft"]

  @doc """
  Locates the CapCut projects folder.

  Returns `{:ok, path}` on the first successful strategy, or `{:error, reason}`
  with a multi-line explanation listing what was tried.
  """
  @spec discover() :: {:ok, Path.t()} | {:error, String.t()}
  def discover do
    from_app_env() || from_localappdata() || from_macos_default() || {:error, not_found_message()}
  end

  @doc """
  Returns the absolute path the LOCALAPPDATA strategy would use, independent
  of whether the directory exists. Useful for diagnostics and for rendering
  the "expected location" in error messages.
  """
  @spec localappdata_candidate() :: Path.t() | nil
  def localappdata_candidate do
    case System.get_env("LOCALAPPDATA") do
      lad when is_binary(lad) and byte_size(lad) > 0 ->
        Path.join([lad | @projects_subpath])

      _ ->
        nil
    end
  end

  @doc """
  Returns the absolute path the macOS default-location strategy would use,
  independent of whether the directory exists. Useful for diagnostics and
  for rendering the "expected location" in error messages.
  """
  @spec macos_default_candidate() :: Path.t() | nil
  def macos_default_candidate do
    # Deliberately `System.get_env("HOME")`, not `System.user_home/0` —
    # the latter is resolved once at VM boot (via `:init.get_argument/1`)
    # and does not observe a later `System.put_env("HOME", ...)`, which
    # broke test isolation. `System.get_env/1` is a live OS lookup, same
    # as the `LOCALAPPDATA` strategy above.
    case System.get_env("HOME") do
      home when is_binary(home) and byte_size(home) > 0 ->
        Path.join([home | @macos_subpath])

      _ ->
        nil
    end
  end

  defp from_app_env do
    case Application.get_env(:capcut_mcp, :capcut_path) do
      path when is_binary(path) and byte_size(path) > 0 -> {:ok, path}
      _ -> nil
    end
  end

  defp from_localappdata do
    with candidate when is_binary(candidate) <- localappdata_candidate(),
         true <- File.dir?(candidate) do
      {:ok, candidate}
    else
      _ -> nil
    end
  end

  defp from_macos_default do
    with candidate when is_binary(candidate) <- macos_default_candidate(),
         true <- File.dir?(candidate) do
      {:ok, candidate}
    else
      _ -> nil
    end
  end

  defp not_found_message do
    """
    Could not locate the CapCut projects folder. Tried:
      * Application env :capcut_path (set via CAPCUT_PATH environment variable)
      * #{localappdata_candidate() || "%LOCALAPPDATA%\\CapCut\\User Data\\Projects\\com.lveditor.draft (LOCALAPPDATA not set)"}
      * #{macos_default_candidate() || "~/Movies/CapCut/User Data/Projects/com.lveditor.draft (home directory not set)"}

    Set CAPCUT_PATH to the "com.lveditor.draft" folder if CapCut is installed
    somewhere else, or install CapCut so the default location exists.
    """
    |> String.trim_trailing()
  end
end
