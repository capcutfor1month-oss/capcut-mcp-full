defmodule CapcutMcp.Tools.SetClipBlendMode do
  @moduledoc "MCP tool: set the blend mode on a video clip."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.{ProjectStore, BlendModes}
  alias CapcutMcp.Tools.{TimelineHelper, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "set_clip_blend_mode",
      "description" =>
        "Sets the blend mode on a video clip. Use 'screen' for transparent-black overlays, " <>
          "'soft_light' for subtle lighting, 'multiply' for darkening, 'overlay' for contrast. " <>
          "Available modes: soft_light, multiply_blend_mode, over_lay, glare_pc (screen), " <>
          "color_filter, dark_en, bright_en, linear_deepening, darken_color, color_dodge.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{"type" => "string", "description" => "The segment ID (from get_timeline)"},
          "mode" => %{
            "type" => "string",
            "description" =>
              "Blend mode name: soft_light, multiply_blend_mode, over_lay, glare_pc (screen), " <>
                "color_filter, dark_en, bright_en, linear_deepening, darken_color, color_dodge"
          },
          "value" => %{
            "type" => "number",
            "description" => "Blend intensity (0.0 to 1.0, default: 1.0)"
          }
        },
        "required" => ["project_id", "clip_id", "mode"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id, "mode" => mode} = args) do
    value = Map.get(args, "value", 1.0)

    with {:ok, blend_mode} <- BlendModes.find_mode(mode),
         {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, {_t, _s, seg}} <- TimelineHelper.find_segment(draft, clip_id),
         :ok <- require_video_segment(seg),
         {:ok, updated_draft} <- apply_blend_mode(draft, clip_id, seg, blend_mode, value),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Blend mode '#{blend_mode.label}' (#{blend_mode.name_id}) set on segment #{clip_id} with intensity #{value}."}
    end
    |> ToolArgs.format_tool_result(id)
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id", "mode"])}

  defp require_video_segment(%{"clip" => clip}) when is_map(clip), do: :ok
  defp require_video_segment(_), do: {:error, "Cannot set blend mode: only video segments are supported"}

  defp apply_blend_mode(draft, clip_id, seg, blend_mode, value) do
    effects = get_in(draft, ["materials", "effects"]) || []
    extra_refs = seg["extra_material_refs"] || []

    # Check if segment already has a mix_mode effect
    existing_mix_mode_id =
      Enum.find(extra_refs, fn ref_id ->
        Enum.any?(effects, fn e -> e["id"] == ref_id && e["type"] == "mix_mode" end)
      end)

    case existing_mix_mode_id do
      nil ->
        # Create new effect and add reference
        effect_id = TimelineHelper.generate_uuid()
        effect = build_mix_mode_effect(effect_id, blend_mode, value)

        updated_draft =
          draft
          |> put_in(["materials", "effects"], effects ++ [effect])

        TimelineHelper.update_segment(updated_draft, clip_id, fn seg ->
          Map.update(seg, "extra_material_refs", [effect_id], &(&1 ++ [effect_id]))
        end)

      existing_id ->
        # Update existing mix_mode effect in-place
        updated_effects =
          Enum.map(effects, fn e ->
            if e["id"] == existing_id do
              e
              |> Map.put("effect_id", blend_mode.effect_id)
              |> Map.put("name", blend_mode.label)
              |> Map.put("path", blend_mode.path)
              |> Map.put("resource_id", blend_mode.resource_id)
              |> Map.put("value", value / 1)
            else
              e
            end
          end)

        {:ok, put_in(draft, ["materials", "effects"], updated_effects)}
    end
  end

  defp build_mix_mode_effect(id, blend_mode, value) do
    %{
      "adjust_params" => [],
      "algorithm_artifact_path" => "",
      "apply_target_type" => 0,
      "beauty_body_auto_preset_id" => "",
      "beauty_face_auto_preset_id" => "",
      "beauty_face_auto_retouch_info" => %{
        "beauty_face_auto_retouch_id" => "",
        "face_id" => []
      },
      "bloom_params" => nil,
      "category_id" => "",
      "category_key" => "",
      "category_name" => "",
      "color_match_info" => %{
        "source_feature_path" => "",
        "target_feature_path" => "",
        "target_image_path" => ""
      },
      "covering_relation_change" => 0,
      "effect_id" => blend_mode.effect_id,
      "enable_skin_tone_correction" => false,
      "exclusion_group" => [],
      "face_adjust_params" => [],
      "formula_id" => "",
      "id" => id,
      "intensity_key" => "",
      "item_effect_type" => 0,
      "lumi_hub_path" => "",
      "multi_language_current" => "",
      "name" => blend_mode.label,
      "panel_id" => "",
      "path" => blend_mode.path,
      "platform" => "all",
      "report_name" => "",
      "request_id" => "",
      "resource_id" => blend_mode.resource_id,
      "smart_color_mode" => 0,
      "source_platform" => 0,
      "sub_category_id" => "",
      "sub_category_name" => "",
      "sub_type" => "none",
      "third_resource_id" => "",
      "time_range" => nil,
      "type" => "mix_mode",
      "value" => value / 1,
      "version" => "",
      "visible" => true
    }
  end
end
