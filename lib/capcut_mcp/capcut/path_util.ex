defmodule CapcutMcp.CapCut.PathUtil do
  @moduledoc """
  Path normalization helpers matching CapCut's on-disk `root_meta_info.json`
  convention on Windows.

  Native CapCut entries use forward slashes for `draft_fold_path` /
  `draft_root_path`, and a forward-slash folder path plus a single backslash
  before `draft_content.json` for `draft_json_file`. `Path.join/2` on Windows
  can mix separators — those hybrid paths confuse CapCut's startup validator —
  so anything we write must go through these helpers.
  """

  @draft_content_filename "draft_content.json"

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
  Builds the `draft_json_file` path the way CapCut writes it:
  forward slashes for the folder, a single backslash before `draft_content.json`.

      iex> CapcutMcp.CapCut.PathUtil.draft_json_file("C:/Users/u/Projects/MyClip")
      "C:/Users/u/Projects/MyClip\\\\draft_content.json"
  """
  @spec draft_json_file(String.t()) :: String.t()
  def draft_json_file(fold_path) when is_binary(fold_path) do
    to_forward(fold_path) <> "\\" <> @draft_content_filename
  end

  @doc "Builds the `draft_cover` path — forward-slash, under the project folder."
  @spec draft_cover(String.t()) :: String.t()
  def draft_cover(fold_path) when is_binary(fold_path) do
    to_forward(fold_path) <> "/draft_cover.jpg"
  end
end
