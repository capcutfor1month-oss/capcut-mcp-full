defmodule CapcutMcp.Tools.ListTextAnimations do
  @moduledoc "MCP tool: list the curated text animation names available to add_text_animation."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.TextAnimations

  @impl true
  def definition do
    %{
      "name" => "list_text_animations",
      "description" =>
        "Lists the text animation names available to add_text_animation (intro and outro).",
      "inputSchema" => %{"type" => "object", "properties" => %{}, "required" => []}
    }
  end

  @impl true
  def execute(_args) do
    %{in: intros, out: outros} = TextAnimations.names()

    text =
      "Intro animations: #{Enum.join(Enum.sort(intros), ", ")}\n" <>
        "Outro animations: #{Enum.join(Enum.sort(outros), ", ")}"

    {:ok, text}
  end
end
