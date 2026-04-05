defmodule CapcutMcp.CapCut.BlendModes do
  @moduledoc """
  Discovers available MixMode (blend mode) resources from the local CapCut installation.
  Reads MixMode.json once from disk and caches the result in an ETS table for subsequent lookups.
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

  @doc "Returns all available blend modes, reading from disk only on first call."
  @spec list_modes() :: {:ok, [map()]} | {:error, String.t()}
  def list_modes do
    case cached_modes() do
      {:ok, _} = hit -> hit
      :miss -> load_and_cache()
    end
  end

  @doc "Finds a blend mode by nameId (e.g. \"soft_light\") or display label (e.g. \"Screen\"). Case-insensitive."
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
    if ets_exists?(), do: :ets.delete_all_objects(@ets_table)
    :ok
  end

  defp cached_modes do
    if ets_exists?() do
      case :ets.lookup(@ets_table, :modes) do
        [{:modes, modes}] -> {:ok, modes}
        [] -> :miss
      end
    else
      :miss
    end
  end

  defp load_and_cache do
    ensure_ets()

    with {:ok, mix_mode_dir} <- find_mix_mode_dir(),
         {:ok, modes} <- read_mix_mode_json(mix_mode_dir) do
      :ets.insert(@ets_table, {:modes, modes})
      {:ok, modes}
    end
  end

  defp ensure_ets do
    unless ets_exists?() do
      :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  defp ets_exists?, do: :ets.whereis(@ets_table) != :undefined

  defp find_mix_mode_dir do
    with {:ok, apps_path} <- apps_path() do
      case File.ls(apps_path) do
        {:ok, entries} ->
          case latest_version_dir(entries) do
            nil ->
              {:error, "No CapCut version found in #{apps_path}"}

            dir ->
              mix_mode_dir = Path.join([apps_path, dir, "Resources", "MixMode"])

              if File.dir?(mix_mode_dir),
                do: {:ok, mix_mode_dir},
                else: {:error, "MixMode directory not found: #{mix_mode_dir}"}
          end

        {:error, reason} ->
          {:error, "Cannot read CapCut apps directory #{apps_path}: #{inspect(reason)}"}
      end
    end
  end

  defp read_mix_mode_json(mix_mode_dir) do
    json_path = Path.join(mix_mode_dir, "MixMode.json")

    with {:ok, content} <- File.read(json_path),
         {:ok, data} <- Jason.decode(content) do
      modes =
        data
        |> Map.get("resourceList", [])
        |> Enum.map(fn entry ->
          name_id = entry["nameId"]

          %{
            name_id: name_id,
            label: Map.get(@name_labels, name_id, name_id),
            effect_id: entry["effectId"],
            resource_id: entry["resourceId"],
            path: Path.join(mix_mode_dir, entry["path"])
          }
        end)

      {:ok, modes}
    end
  end

  defp apps_path do
    cond do
      present_env?("CAPCUT_APPS_PATH") ->
        {:ok, System.fetch_env!("CAPCUT_APPS_PATH")}

      present_env?("LOCALAPPDATA") ->
        {:ok, Path.join([System.fetch_env!("LOCALAPPDATA"), "CapCut", "Apps"])}

      true ->
        {:error, "CapCut apps directory not configured. Set CAPCUT_APPS_PATH or LOCALAPPDATA."}
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
