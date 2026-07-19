defmodule CapcutMcp.CapCut.BlendModes do
  @moduledoc """
  Discovers available MixMode (blend mode) resources from the local CapCut installation.

  Reads `MixMode.json` once from disk and caches the result in an ETS table for
  subsequent lookups. The table is owned by the application master (created in
  `CapcutMcp.Application.start/2` via `init_table/0`) so it outlives any
  individual caller process.

  ## Telemetry

  Every disk load (expected exactly once per application lifetime, guarded by
  the ETS cache) emits:

    * `[:capcut_mcp, :blend_modes, :load]`
      * **measurements**: `:duration` (native time units)
      * **metadata**: on success `%{result: :ok, count: integer(), path: String.t()}`,
        on failure `%{result: :error, reason: term()}`

  Useful for confirming the lazy-load path is actually lazy (should only ever
  fire once in production).

  ## macOS support (2026-07-20)

  Windows caches every installed CapCut version side-by-side under
  `%LOCALAPPDATA%\CapCut\Apps\<version>\Resources\MixMode\MixMode.json`, so
  discovery has to scan for the latest version-numbered folder. macOS ships
  one fixed `.app` bundle per install with no such per-version folder --
  confirmed against a real `/Applications/CapCut.app`, `MixMode.json` lives
  directly at `Contents/Resources/MixMode/MixMode.json`. `find_mix_mode_dir/0`
  tries that flat layout first and only falls back to the Windows
  version-scan if it isn't found, and `apps_path/0` auto-detects
  `/Applications/CapCut.app/Contents/Resources` the same way `PathDiscovery`
  auto-detects `~/Movies/CapCut/...` for the projects folder.
  """

  @ets_table :capcut_blend_modes

  @name_labels %{
    "soft_light" => "Soft Light",
    "multiply_blend_mode" => "Multiply",
    "over_lay" => "Overlay",
    "glare_pc" => "Screen",
    "color_filter" => "Color",
    "dark_en" => "Darken",
    "bright_en" => "Lighten",
    "linear_deepening" => "Linear Burn",
    "darken_color" => "Color Burn",
    "color_dodge" => "Color Dodge"
  }

  @doc """
  Initializes the ETS cache table. Idempotent; called once from `Application.start/2`
  so the table is owned by the long-lived application master process.
  """
  @spec init_table() :: :ok
  def init_table do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Returns all available blend modes, reading from disk only on first call."
  @spec list_modes() :: {:ok, [map()]} | {:error, String.t()}
  def list_modes do
    case cached_modes() do
      {:ok, _} = hit -> hit
      :miss -> load_and_cache()
    end
  end

  @doc ~S"""
  Finds a blend mode by nameId (e.g. `"soft_light"`) or display label
  (e.g. `"Screen"`). Case-insensitive.
  """
  @spec find_mode(String.t()) :: {:ok, map()} | {:error, String.t()}
  def find_mode(query) do
    with {:ok, modes} <- list_modes() do
      normalized = String.downcase(query)

      result =
        Enum.find(modes, fn mode ->
          String.downcase(mode.name_id) == normalized ||
            String.downcase(mode.label) == normalized
        end)

      case result do
        nil ->
          available = Enum.map_join(modes, ", ", & &1.name_id)
          {:error, "Unknown blend mode: #{query}. Available: #{available}"}

        mode ->
          {:ok, mode}
      end
    end
  end

  @doc "Clears the cached blend modes, forcing a disk reload on next access."
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    init_table()
    :ets.delete(@ets_table, :modes)
    :ok
  end

  defp cached_modes do
    init_table()

    case :ets.lookup(@ets_table, :modes) do
      [{:modes, modes}] -> {:ok, modes}
      [] -> :miss
    end
  end

  defp load_and_cache do
    init_table()
    start = System.monotonic_time()

    {result, metadata} =
      case find_mix_mode_dir() do
        {:ok, mix_mode_dir} ->
          case read_mix_mode_json(mix_mode_dir) do
            {:ok, modes} ->
              :ets.insert(@ets_table, {:modes, modes})
              {{:ok, modes}, %{result: :ok, count: length(modes), path: mix_mode_dir}}

            {:error, reason} = err ->
              {err, %{result: :error, reason: reason, path: mix_mode_dir}}
          end

        {:error, reason} = err ->
          {err, %{result: :error, reason: reason}}
      end

    :telemetry.execute(
      [:capcut_mcp, :blend_modes, :load],
      %{duration: System.monotonic_time() - start},
      metadata
    )

    result
  end

  defp find_mix_mode_dir do
    with {:ok, apps_path} <- apps_path() do
      # macOS CapCut ships one fixed .app bundle per install with
      # `Contents/Resources/MixMode/MixMode.json` directly -- no
      # version-numbered subdirectory the way Windows' AppData cache has
      # one folder per installed CapCut version. Try the flat layout
      # first (verified against a real /Applications/CapCut.app), then
      # fall back to the Windows version-scan.
      case flat_mix_mode_dir(apps_path) do
        {:ok, dir} -> {:ok, dir}
        {:error, _} -> versioned_mix_mode_dir(apps_path)
      end
    end
  end

  defp flat_mix_mode_dir(apps_path) do
    mix_mode_dir = Path.join([apps_path, "MixMode"])

    if File.exists?(Path.join(mix_mode_dir, "MixMode.json")) do
      {:ok, mix_mode_dir}
    else
      {:error, "No flat MixMode dir at #{mix_mode_dir}"}
    end
  end

  defp versioned_mix_mode_dir(apps_path) do
    with {:ok, entries} <- list_apps_entries(apps_path),
         {:ok, version_dir} <- pick_latest_version(apps_path, entries) do
      verify_mix_mode_dir(apps_path, version_dir)
    end
  end

  defp list_apps_entries(apps_path) do
    case File.ls(apps_path) do
      {:ok, entries} ->
        {:ok, entries}

      {:error, reason} ->
        {:error, "Cannot read CapCut apps directory #{apps_path}: #{inspect(reason)}"}
    end
  end

  defp pick_latest_version(apps_path, entries) do
    case latest_version_dir(entries) do
      nil -> {:error, "No CapCut version found in #{apps_path}"}
      dir -> {:ok, dir}
    end
  end

  defp verify_mix_mode_dir(apps_path, version_dir) do
    mix_mode_dir = Path.join([apps_path, version_dir, "Resources", "MixMode"])

    if File.dir?(mix_mode_dir) do
      {:ok, mix_mode_dir}
    else
      {:error, "MixMode directory not found: #{mix_mode_dir}"}
    end
  end

  defp read_mix_mode_json(mix_mode_dir) do
    json_path = Path.join(mix_mode_dir, "MixMode.json")

    with {:ok, content} <- File.read(json_path),
         {:ok, data} <- Jason.decode(content) do
      modes =
        data
        |> Map.get("resourceList", [])
        |> Enum.flat_map(&decode_mode_entry(&1, mix_mode_dir))

      {:ok, modes}
    end
  end

  # A future or tampered-with MixMode.json entry can omit `nameId` or `path`.
  # Silently drop such entries instead of crashing `Path.join/2` (nil arg) or
  # `find_mode/1`'s `String.downcase(nil)` on subsequent lookups.
  defp decode_mode_entry(%{"nameId" => name_id, "path" => rel_path} = entry, mix_mode_dir)
       when is_binary(name_id) and is_binary(rel_path) do
    [
      %{
        name_id: name_id,
        label: Map.get(@name_labels, name_id, name_id),
        effect_id: entry["effectId"],
        resource_id: entry["resourceId"],
        path: Path.join(mix_mode_dir, rel_path)
      }
    ]
  end

  defp decode_mode_entry(_incomplete, _mix_mode_dir), do: []

  @macos_default_apps_path "/Applications/CapCut.app/Contents/Resources"

  defp apps_path do
    cond do
      present_env?("CAPCUT_APPS_PATH") ->
        {:ok, System.fetch_env!("CAPCUT_APPS_PATH")}

      present_env?("LOCALAPPDATA") ->
        {:ok, Path.join([System.fetch_env!("LOCALAPPDATA"), "CapCut", "Apps"])}

      File.dir?(@macos_default_apps_path) ->
        {:ok, @macos_default_apps_path}

      true ->
        {:error,
         "CapCut apps directory not configured. Set CAPCUT_APPS_PATH or LOCALAPPDATA, " <>
           "or install CapCut to /Applications on macOS."}
    end
  end

  defp latest_version_dir(entries) do
    entries
    |> Enum.filter(&Regex.match?(~r/^\d+(?:\.\d+)+$/, &1))
    |> Enum.max_by(&version_key/1, fn -> nil end)
  end

  defp version_key(version) do
    version
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  defp present_env?(name) do
    name |> System.get_env("") |> String.trim() != ""
  end
end
