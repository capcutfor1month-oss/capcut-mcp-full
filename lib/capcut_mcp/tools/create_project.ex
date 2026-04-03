defmodule CapcutMcp.Tools.CreateProject do
  @moduledoc "MCP tool: create a new CapCut draft project."
  alias CapcutMcp.CapCut.ProjectStore

  def definition do
    %{
      "name" => "create_project",
      "description" => "Creates a new empty CapCut draft project.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "Project name"},
          "width" => %{"type" => "integer", "description" => "Canvas width in pixels (default: 1920)"},
          "height" => %{"type" => "integer", "description" => "Canvas height in pixels (default: 1080)"},
          "fps" => %{"type" => "number", "description" => "Frames per second (default: 30)"}
        },
        "required" => ["name"]
      }
    }
  end

  def execute(args) do
    case ProjectStore.create_project(args) do
      {:ok, id} -> {:ok, id}
      {:error, reason} -> {:error, "Failed to create project: #{inspect(reason)}"}
    end
  end
end
