defmodule CapcutMcp.CapCut.ProjectStore do
  use GenServer
  require Logger
  alias CapcutMcp.CapCut.{Reader, Writer, Types.ProjectMeta}

  # ── Client API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list_projects() :: {:ok, [ProjectMeta.t()]} | {:error, term()}
  def list_projects, do: GenServer.call(__MODULE__, :list_projects)

  @spec get_project(String.t()) :: {:ok, map()} | {:error, :not_found | term()}
  def get_project(id), do: GenServer.call(__MODULE__, {:get_project, id})

  @spec update_project(String.t(), map()) :: :ok | {:error, term()}
  def update_project(id, draft), do: GenServer.call(__MODULE__, {:update_project, id, draft})

  @spec create_project(map()) :: {:ok, String.t()} | {:error, term()}
  def create_project(params), do: GenServer.call(__MODULE__, {:create_project, params})

  # ── Server callbacks ─────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    root_path =
      Keyword.get(opts, :root_path) ||
        Application.get_env(:capcut_mcp, :capcut_path)

    {:ok, %{root_path: root_path, cache: %{}}}
  end

  @impl true
  def handle_call(:list_projects, _from, state) do
    {:reply, Reader.list_projects(state.root_path), state}
  end

  @impl true
  def handle_call({:get_project, id}, _from, state) do
    case Map.get(state.cache, id) do
      nil ->
        case load_project(id, state.root_path) do
          {:ok, {path, draft}} ->
            {:reply, {:ok, draft}, %{state | cache: Map.put(state.cache, id, {path, draft})}}

          error ->
            {:reply, error, state}
        end

      {_path, draft} ->
        {:reply, {:ok, draft}, state}
    end
  end

  @impl true
  def handle_call({:update_project, id, draft}, _from, state) do
    case Map.get(state.cache, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {path, _old} ->
        case Writer.write_draft(path, draft) do
          :ok ->
            {:reply, :ok, %{state | cache: Map.put(state.cache, id, {path, draft})}}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:create_project, params}, _from, state) do
    id = generate_uuid()
    name = Map.get(params, "name", "New Project")
    width = Map.get(params, "width", 1920)
    height = Map.get(params, "height", 1080)
    fps = Map.get(params, "fps", 30.0) * 1.0

    dir_name = name |> String.replace(~r/[^\w\s\-]/, "") |> String.replace(" ", "_")
    project_path = Path.join(state.root_path, dir_name)

    with :ok <- File.mkdir_p(project_path),
         draft <- new_draft(id, name, width, height, fps),
         :ok <- Writer.write_draft(project_path, draft),
         :ok <- update_root_meta(state.root_path, id, name, project_path) do
      {:reply, {:ok, id}, %{state | cache: Map.put(state.cache, id, {project_path, draft})}}
    else
      error -> {:reply, error, state}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp load_project(id, root_path) do
    case Reader.list_projects(root_path) do
      {:ok, projects} ->
        case Enum.find(projects, fn p -> p.id == id end) do
          nil ->
            {:error, :not_found}

          %ProjectMeta{path: path} ->
            case Reader.read_draft(path) do
              {:ok, draft} -> {:ok, {path, draft}}
              error -> error
            end
        end

      error ->
        error
    end
  end

  defp update_root_meta(root_path, id, name, project_path) do
    meta_file = Path.join(root_path, "root_meta_info.json")

    existing =
      case File.read(meta_file) do
        {:ok, content} -> Jason.decode!(content)
        _ -> %{"all_draft_store" => [], "draft_ids" => 0, "root_path" => root_path}
      end

    now = System.os_time(:microsecond)
    json_file = Path.join(project_path, "draft_content.json")

    new_entry = %{
      "draft_id" => id,
      "draft_name" => name,
      "draft_fold_path" => project_path,
      "draft_json_file" => json_file,
      "tm_draft_create" => now,
      "tm_draft_modified" => now,
      "tm_draft_removed" => 0,
      "tm_duration" => 0,
      "cloud_draft_sync" => false,
      "draft_is_invisible" => false
    }

    updated = %{
      existing
      | "all_draft_store" => [new_entry | existing["all_draft_store"]],
        "draft_ids" => existing["draft_ids"] + 1
    }

    Writer.write_root_meta(root_path, updated)
  end

  defp new_draft(id, name, width, height, fps) do
    %{
      "id" => id,
      "name" => name,
      "draft_type" => "video",
      "canvas_config" => %{
        "width" => width,
        "height" => height,
        "ratio" => "original",
        "background" => nil
      },
      "fps" => fps,
      "duration" => 0,
      "tracks" => [],
      "materials" => %{
        "videos" => [],
        "audios" => [],
        "texts" => [],
        "images" => [],
        "effects" => [],
        "transitions" => [],
        "stickers" => [],
        "filters" => []
      },
      "keyframes" => %{
        "adjusts" => [],
        "audios" => [],
        "effects" => [],
        "filters" => [],
        "stickers" => [],
        "texts" => [],
        "videos" => []
      },
      "version" => 360_000,
      "new_version" => "163.0.0",
      "create_time" => 0,
      "update_time" => 0
    }
  end

  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    s = <<a::48, 4::4, b::12, 2::2, c::62>> |> Base.encode16(case: :upper)

    "#{String.slice(s, 0, 8)}-#{String.slice(s, 8, 4)}-#{String.slice(s, 12, 4)}-#{String.slice(s, 16, 4)}-#{String.slice(s, 20, 12)}"
  end
end
