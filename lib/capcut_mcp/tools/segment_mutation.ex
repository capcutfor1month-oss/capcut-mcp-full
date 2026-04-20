defmodule CapcutMcp.Tools.SegmentMutation do
  @moduledoc """
  High-level helper for the recurring "load draft → mutate one segment → persist" pattern
  used by every `set_clip_*` / `move_clip` / `trim_clip` tool.

  Using this in a tool collapses ~10 lines of `with`-chain boilerplate to a single call:

      SegmentMutation.run(project_id, clip_id, &Map.put(&1, "volume", 0.5),
        success: "Volume set on segment \#{clip_id}.",
        require_clip: false)

  The `:require_clip` option rejects text/audio segments that lack a `"clip"` object
  (transforms and opacity only make sense on video segments).
  """

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.{TimelineHelper, ToolArgs}

  @type option :: {:success, String.t()} | {:require_clip, boolean()} | {:clip_error, String.t()}
  @type options :: [option()]

  @doc """
  Loads the draft, applies `update_fn` to the segment identified by `clip_id`, persists
  the result, and returns a tool-friendly `{:ok, msg} | {:error, msg}` tuple.

  ## Options
    * `:success` — human-readable success message (required)
    * `:require_clip` — if `true`, the segment must have a `"clip"` map (default: `false`)
    * `:clip_error` — error message when `:require_clip` fails
  """
  @spec run(String.t(), String.t(), (map() -> map()), options()) ::
          {:ok, String.t()} | {:error, String.t()}
  def run(project_id, clip_id, update_fn, opts) when is_function(update_fn, 1) do
    success = Keyword.fetch!(opts, :success)
    require_clip? = Keyword.get(opts, :require_clip, false)

    clip_error =
      Keyword.get(
        opts,
        :clip_error,
        "Segment has no clip object (audio segments are not supported)"
      )

    with {:ok, draft} <- ProjectStore.get_project(project_id),
         :ok <- maybe_require_clip(draft, clip_id, require_clip?, clip_error),
         {:ok, updated} <- TimelineHelper.update_segment(draft, clip_id, update_fn),
         :ok <- ProjectStore.update_project(project_id, updated) do
      {:ok, success}
    end
    |> ToolArgs.format_tool_result(project_id)
  end

  defp maybe_require_clip(_draft, _clip_id, false, _err), do: :ok

  defp maybe_require_clip(draft, clip_id, true, err) do
    with {:ok, {_t, _s, segment}} <- TimelineHelper.find_segment(draft, clip_id) do
      case segment do
        %{"clip" => clip} when is_map(clip) -> :ok
        _ -> {:error, err}
      end
    end
  end

  @doc """
  Runs a caller-provided `update_draft_fn` that returns `{:ok, updated_draft}` or `{:error, _}`.
  Useful for tools that mutate the draft at a level beyond a single segment (e.g. adding an
  effect material + updating `extra_material_refs` atomically).
  """
  @spec run_draft(String.t(), (map() -> {:ok, map()} | {:error, term()}), options()) ::
          {:ok, String.t()} | {:error, String.t()}
  def run_draft(project_id, update_draft_fn, opts) when is_function(update_draft_fn, 1) do
    success = Keyword.fetch!(opts, :success)

    with {:ok, draft} <- ProjectStore.get_project(project_id),
         {:ok, updated} <- update_draft_fn.(draft),
         :ok <- ProjectStore.update_project(project_id, updated) do
      {:ok, success}
    end
    |> ToolArgs.format_tool_result(project_id)
  end
end
