defmodule CapcutMcp.Tools.SetClipBlendMode do
  @moduledoc "MCP tool: set the blend mode on a video clip."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.{BlendModes, MixModeEffect}
  alias CapcutMcp.Tools.{SegmentMutation, TimelineHelper, ToolArgs}

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
          "clip_id" => %{
            "type" => "string",
            "description" => "The segment ID (from get_timeline)"
          },
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
    with {:ok, value} <- ToolArgs.to_float_safe(Map.get(args, "value", 1.0)),
         {:ok, blend_mode} <- BlendModes.find_mode(mode) do
      SegmentMutation.run_draft(id, &apply_blend_mode(&1, clip_id, blend_mode, value),
        success:
          "Blend mode '#{blend_mode.label}' (#{blend_mode.name_id}) set on segment #{clip_id} with intensity #{value}."
      )
    end
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id", "mode"])}

  defp apply_blend_mode(draft, clip_id, blend_mode, value) do
    with {:ok, {_t, _s, seg}} <- TimelineHelper.find_segment(draft, clip_id),
         :ok <- require_video_segment(seg) do
      effects = get_in(draft, ["materials", "effects"]) || []
      extra_refs = seg["extra_material_refs"] || []

      existing_mix_mode_id =
        Enum.find(extra_refs, fn ref_id ->
          Enum.any?(effects, &match?(%{"id" => ^ref_id, "type" => "mix_mode"}, &1))
        end)

      case existing_mix_mode_id do
        nil -> add_new_mix_mode(draft, clip_id, effects, blend_mode, value)
        existing_id -> update_existing_mix_mode(draft, effects, existing_id, blend_mode, value)
      end
    end
  end

  defp add_new_mix_mode(draft, clip_id, effects, blend_mode, value) do
    effect_id = TimelineHelper.generate_uuid()
    effect = MixModeEffect.build(effect_id, blend_mode, value)
    draft_with_effect = put_in(draft, ["materials", "effects"], effects ++ [effect])

    TimelineHelper.update_segment(draft_with_effect, clip_id, fn seg ->
      Map.update(seg, "extra_material_refs", [effect_id], &(&1 ++ [effect_id]))
    end)
  end

  defp update_existing_mix_mode(draft, effects, existing_id, blend_mode, value) do
    updated_effects =
      Enum.map(effects, fn
        %{"id" => ^existing_id} = e ->
          e
          |> Map.put("effect_id", blend_mode.effect_id)
          |> Map.put("name", blend_mode.label)
          |> Map.put("path", blend_mode.path)
          |> Map.put("resource_id", blend_mode.resource_id)
          |> Map.put("value", value)

        other ->
          other
      end)

    {:ok, put_in(draft, ["materials", "effects"], updated_effects)}
  end

  defp require_video_segment(%{"clip" => clip}) when is_map(clip), do: :ok

  defp require_video_segment(_),
    do: {:error, "Cannot set blend mode: only video segments are supported"}
end
