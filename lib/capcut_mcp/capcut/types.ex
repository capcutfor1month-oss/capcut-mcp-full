defmodule CapcutMcp.CapCut.Types do
  @moduledoc "Domain types for CapCut project data."

  defmodule ProjectMeta do
    @moduledoc """
    Represents metadata for a single CapCut draft project.

    Fields:
    - `:id` - unique project identifier (required)
    - `:name` - human-readable project name (required)
    - `:path` - absolute filesystem path to the draft directory (required)
    - `:modified_at` - last modification timestamp in microseconds (optional)
    - `:duration_ms` - total timeline duration in milliseconds (optional)
    """

    @type t :: %__MODULE__{
      id: String.t(),
      name: String.t(),
      path: String.t(),
      modified_at: integer() | nil,
      duration_ms: integer() | nil
    }

    @enforce_keys [:id, :name, :path]
    defstruct [:id, :name, :path, :modified_at, :duration_ms]
  end
end
