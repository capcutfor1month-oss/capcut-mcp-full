defmodule CapcutMcp.CapCut.MixModeEffect do
  @moduledoc """
  Builds CapCut `mix_mode` effect material entries for blend-mode support.

  CapCut's `materials.effects` array stores verbose effect descriptors with
  dozens of fields; this module constructs them from the lean data returned by
  `CapcutMcp.CapCut.BlendModes`. Extracted from `Tools.SetClipBlendMode` so the
  schema template lives with the domain, not the tool.
  """

  @doc "Returns a fresh `mix_mode` effect map with the given id, blend mode, and intensity."
  @spec build(String.t(), map(), number()) :: map()
  def build(id, blend_mode, value) when is_map(blend_mode) and is_number(value) do
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
      "value" => value * 1.0,
      "version" => "",
      "visible" => true
    }
  end
end
