defmodule CapcutMcp.CapCut.PathUtil do
  @moduledoc """
  Path normalization helpers matching CapCut's on-disk `root_meta_info.json`
  convention.

  On Windows, native CapCut entries use forward slashes for `draft_fold_path` /
  `draft_root_path`, but a forward-slash folder path plus a single backslash
  before `draft_content.json` for `draft_json_file`. `Path.join/2` on Windows
  can mix separators — those hybrid paths confuse CapCut's startup validator —
  so anything we write must go through these helpers.

  On macOS, CapCut writes pure forward-slash paths throughout — no backslash
  quirk. Verified against a live `root_meta_info.json` on macOS: every
  `draft_json_file` entry is plain forward-slash, e.g.
  ".../com.lveditor.draft/Teams/draft_info.json". Using the Windows-style
  backslash separator on macOS would corrupt the manifest entry.

  `draft_json_file/1` targets `draft_info.json`, not `draft_content.json`.
  Confirmed by creating a real project through CapCut's own UI and diffing
  its manifest entry: current CapCut (macOS) points `draft_json_file` at
  `draft_info.json` for every newly-created project — `draft_content.json`
  is a legacy filename some pre-existing projects still carry (e.g. a real
  project "MFA Mobile" last touched by Windows CapCut), but CapCut itself
  never re-creates it for new drafts.
  """

  @draft_info_filename "draft_info.json"

  @doc """
  Converts every backslash in `path` to a forward slash.

  Idempotent for paths that already use forward slashes.

      iex> CapcutMcp.CapCut.PathUtil.to_forward("C:\\\\Users\\\\u\\\\Projects")
      "C:/Users/u/Projects"

      iex> CapcutMcp.CapCut.PathUtil.to_forward("C:/already/forward")
      "C:/already/forward"
  """
  @spec to_forward(String.t()) :: String.t()
  def to_forward(path) when is_binary(path), do: String.replace(path, "\\", "/")

  @doc """
  Builds the `draft_json_file` path the way CapCut writes it on the current
  platform, for a newly-created project: Windows gets forward slashes for
  the folder plus a single backslash before `draft_info.json`; every other
  OS (macOS included) gets a pure forward-slash path.

  Platform-dependent output, so no doctest here — see
  `CapcutMcp.CapCut.PathUtilTest` for the per-platform assertions.
  """
  @spec draft_json_file(String.t()) :: String.t()
  def draft_json_file(fold_path) when is_binary(fold_path) do
    case :os.type() do
      {:win32, _} -> to_forward(fold_path) <> "\\" <> @draft_info_filename
      _ -> to_forward(fold_path) <> "/" <> @draft_info_filename
    end
  end

  @doc "Builds the `draft_cover` path — forward-slash, under the project folder."
  @spec draft_cover(String.t()) :: String.t()
  def draft_cover(fold_path) when is_binary(fold_path) do
    to_forward(fold_path) <> "/draft_cover.jpg"
  end
end
