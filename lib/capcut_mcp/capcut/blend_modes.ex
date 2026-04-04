defmodule CapcutMcp.CapCut.BlendModes do
  @moduledoc """
  Discovers available MixMode (blend mode) resources from the local CapCut installation.
  Reads MixMode.json from the CapCut Resources directory and provides lookup by name.
  """

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

  @doc "Returns all available blend modes as a list of maps with :name, :effect_id, :resource_id, :path."
  @spec list_modes() :: {:ok, [map()]} | {:error, String.t()}
  def list_modes do
    with {:ok, mix_mode_dir} <- find_mix_mode_dir(),
         {:ok, modes} <- read_mix_mode_json(mix_mode_dir) do
      {:ok, modes}
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
    case System.get_env(name) do
      value when is_binary(value) -> String.trim(value) != ""
      _ -> false
    end
  end
end
