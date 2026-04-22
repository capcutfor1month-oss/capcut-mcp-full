defmodule CapcutMcp.CapCut.ManifestRoundtripPropertyTest do
  @moduledoc """
  Property coverage for the two manifest invariants CapCut uses as startup
  consistency checks:

    1. Every `all_draft_store` entry exposes the full 32-key schema.
    2. `draft_ids` always equals `length(all_draft_store)`.

  Covered at the pure-data layer: `ManifestSchema.new_entry/1` for invariant #1,
  and the shape built by `update_root_meta` / `apply_remaining` is exercised
  in `project_store_test.exs` (which stands up a real ProjectStore GenServer
  and is expensive to property-drive).
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CapcutMcp.CapCut.{ManifestSchema, PathUtil}

  @canonical_keys ManifestSchema.keys()

  describe "ManifestSchema.new_entry/1 (property)" do
    property "always returns the canonical 32-key shape regardless of opts" do
      check all opts <- opts_gen(), max_runs: 200 do
        entry = ManifestSchema.new_entry(opts)

        assert Enum.sort(Map.keys(entry)) == @canonical_keys
        assert map_size(entry) == 32
      end
    end

    property "passes caller-provided identity and timestamps through unchanged" do
      check all opts <- opts_gen(), max_runs: 200 do
        entry = ManifestSchema.new_entry(opts)

        assert entry["draft_id"] == opts[:draft_id]
        assert entry["draft_name"] == opts[:draft_name]
        assert entry["tm_draft_create"] == opts[:now_us]
        assert entry["tm_draft_modified"] == opts[:now_us]
      end
    end

    property "never leaks a backslash into draft_fold_path, draft_root_path, or draft_cover" do
      # Phase 2 guarantee: caller passes already-normalized paths through
      # PathUtil.to_forward/1; the schema itself must not re-introduce
      # backslashes.
      check all opts <- opts_gen(), max_runs: 200 do
        entry = ManifestSchema.new_entry(opts)

        refute String.contains?(entry["draft_fold_path"], "\\")
        refute String.contains?(entry["draft_root_path"], "\\")
        refute String.contains?(entry["draft_cover"], "\\")
      end
    end
  end

  # Generates any plausible argument shape for `new_entry/1`: arbitrary names
  # and ids, Windows-hybrid folder paths that are then normalized the same
  # way ProjectStore does it in production.
  defp opts_gen do
    gen all id <- uuid_like_gen(),
            name <- name_gen(),
            fold_raw <- windows_path_gen(),
            root_raw <- windows_path_gen(),
            now <- StreamData.integer(1_700_000_000_000_000..1_800_000_000_000_000) do
      fold = PathUtil.to_forward(fold_raw)
      root = PathUtil.to_forward(root_raw)

      [
        draft_id: id,
        draft_name: name,
        fold_path: fold,
        json_file: PathUtil.draft_json_file(fold),
        cover_path: PathUtil.draft_cover(fold),
        root_path: root,
        now_us: now
      ]
    end
  end

  defp uuid_like_gen do
    StreamData.string(:alphanumeric, min_length: 4, max_length: 24)
  end

  defp name_gen do
    StreamData.string(:alphanumeric, min_length: 1, max_length: 32)
  end

  # A plausible Windows-side path with both separators, matching what
  # `Path.join/2` produces on Windows when given an env-var-derived root.
  defp windows_path_gen do
    gen all segments <-
              StreamData.list_of(
                StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
                min_length: 1,
                max_length: 5
              ),
            separator <- StreamData.member_of(["\\", "/"]) do
      "C:" <> separator <> Enum.join(segments, separator)
    end
  end
end
