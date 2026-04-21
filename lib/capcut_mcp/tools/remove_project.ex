defmodule CapcutMcp.Tools.RemoveProject do
  @moduledoc "MCP tool: remove a CapCut draft project."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore

  @impl true
  def definition do
    %{
      "name" => "remove_project",
      "description" =>
        "Removes a CapCut draft project: drops it from root_meta_info.json and (by default) deletes its folder. Pass keep_files=true to leave the files on disk.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{
            "type" => "string",
            "description" => "The draft_id of the project (from list_projects)"
          },
          "keep_files" => %{
            "type" => "boolean",
            "description" =>
              "If true, only the root_meta_info.json entry is removed; the project folder stays on disk. Default: false."
          }
        },
        "required" => ["project_id"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id} = args) do
    keep_files = Map.get(args, "keep_files", false)

    case ProjectStore.remove_project(id, keep_files: keep_files) do
      :ok ->
        {:ok, render_success(id, keep_files)}

      {:error, :not_found} ->
        {:error, "Project not found: #{id}"}

      {:error, :path_outside_root} ->
        {:error,
         "Refusing to remove project #{id}: its draft_fold_path in root_meta_info.json " <>
           "points outside the configured CapCut root. Retry with keep_files=true or fix " <>
           "the manifest entry by hand."}

      {:error, reason} ->
        {:error, "Failed to remove project #{id}: #{inspect(reason)}"}
    end
  end

  defp render_success(id, true),
    do: "Project #{id} removed from root_meta_info.json (folder left on disk)."

  defp render_success(id, false),
    do: "Project #{id} removed (entry + folder deleted)."
end
