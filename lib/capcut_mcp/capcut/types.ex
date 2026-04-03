defmodule CapcutMcp.CapCut.Types do
  defmodule ProjectMeta do
    @enforce_keys [:id, :name, :path]
    defstruct [:id, :name, :path, :modified_at, :duration_ms]
  end
end
