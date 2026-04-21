defmodule CapcutMcp.CapCut.ProjectStore do
  @moduledoc """
  Cache + mutation gateway for CapCut draft projects.

  Reads go **directly through ETS** (`:read_concurrency`, no process bottleneck).
  Writes are serialized through the owning `GenServer` so atomic-write semantics
  and cache consistency stay intact. The ETS table is `:protected` and owned by
  this process, so only the server can mutate it; the outside world can only
  read.

  ## Telemetry

  Every cache operation emits one of:

    * `[:capcut_mcp, :cache, :hit]`  — metadata: `%{id: String.t()}`
    * `[:capcut_mcp, :cache, :miss]` — metadata: `%{id: String.t()}`
    * `[:capcut_mcp, :cache, :write]` — metadata:
      `%{id: String.t(), reason: :load | :update | :create}`

  Measurements are always `%{count: 1}` — attach a counter handler to derive
  the cache hit-rate.
  """

  use GenServer
  require Logger
  alias CapcutMcp.CapCut.{Draft, PathDiscovery, ProjectMeta, Reader, Writer}
  alias CapcutMcp.Tools.TimelineHelper

  @table :capcut_project_cache

  # ── Client API ──────────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec list_projects() :: {:ok, [ProjectMeta.t()]} | {:error, term()}
  def list_projects, do: GenServer.call(__MODULE__, :list_projects)

  @spec get_project(String.t()) :: {:ok, map()} | {:error, :not_found | term()}
  def get_project(id) do
    case cache_lookup(id) do
      {:ok, _path, draft} -> {:ok, draft}
      :miss -> GenServer.call(__MODULE__, {:load_project, id})
    end
  end

  @spec update_project(String.t(), map()) :: :ok | {:error, term()}
  def update_project(id, draft), do: GenServer.call(__MODULE__, {:update_project, id, draft})

  @spec create_project(map()) :: {:ok, String.t()} | {:error, term()}
  def create_project(params), do: GenServer.call(__MODULE__, {:create_project, params})

  # ── Server callbacks ─────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])

    root_path = resolve_root_path(opts)
    {:ok, %{root_path: root_path}}
  end

  @impl true
  def handle_call(:list_projects, _from, state) do
    case require_root_path(state) do
      {:ok, root} -> {:reply, Reader.list_projects(root), state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  @impl true
  def handle_call({:load_project, id}, _from, state) do
    case cache_lookup(id) do
      {:ok, _path, draft} ->
        {:reply, {:ok, draft}, state}

      :miss ->
        with {:ok, root} <- require_root_path(state),
             {:ok, {path, draft}} <- load_project(id, root) do
          cache_put(id, path, draft, :load)
          {:reply, {:ok, draft}, state}
        else
          {:error, _} = error -> {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:update_project, id, draft}, _from, state) do
    with {:ok, root} <- require_root_path(state),
         {:ok, path} <- ensure_path(id, root),
         :ok <- Writer.write_draft(path, draft) do
      cache_put(id, path, draft, :update)
      {:reply, :ok, state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:create_project, params}, _from, state) do
    case require_root_path(state) do
      {:ok, root} -> {:reply, do_create_project(root, params), state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  defp do_create_project(root, params) do
    id = generate_uuid()
    name = Map.get(params, "name", "New Project")

    draft =
      Draft.new(
        id: id,
        name: name,
        width: Map.get(params, "width", 1920),
        height: Map.get(params, "height", 1080),
        fps: Map.get(params, "fps", 30.0)
      )

    draft_map = Draft.to_json(draft)
    project_path = Path.join(root, sanitize_dir_name(name))

    with :ok <- File.mkdir_p(project_path),
         :ok <- Writer.write_draft(project_path, draft_map),
         :ok <- update_root_meta(root, id, name, project_path) do
      cache_put(id, project_path, draft_map, :create)
      {:ok, id}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  @spec resolve_root_path(keyword()) :: Path.t() | nil
  defp resolve_root_path(opts) do
    case Keyword.get(opts, :root_path) do
      path when is_binary(path) ->
        path

      _ ->
        case PathDiscovery.discover() do
          {:ok, path} ->
            path

          {:error, reason} ->
            Logger.warning(
              "CapCut path not configured — tool calls will return an error " <>
                "until CAPCUT_PATH is set or CapCut is installed. #{reason}"
            )

            nil
        end
    end
  end

  @spec require_root_path(%{root_path: Path.t() | nil}) ::
          {:ok, Path.t()} | {:error, String.t()}
  defp require_root_path(%{root_path: path}) when is_binary(path), do: {:ok, path}

  defp require_root_path(%{root_path: nil}) do
    case PathDiscovery.discover() do
      {:ok, path} -> {:ok, path}
      {:error, reason} -> {:error, "CapCut path not configured. #{reason}"}
    end
  end

  # The ETS table is created synchronously in `init/1`, so by the time any
  # caller reaches this function the table is guaranteed to exist — no
  # defensive rescue needed. If the `ProjectStore` is not running at all,
  # `get_project/1`'s fallback `GenServer.call` will surface that as a clean
  # `:noproc` error, which is the correct signal.
  @spec cache_lookup(String.t()) :: {:ok, Path.t(), map()} | :miss
  defp cache_lookup(id) do
    case :ets.lookup(@table, id) do
      [{^id, path, draft}] ->
        emit_cache_event(:hit, %{id: id})
        {:ok, path, draft}

      [] ->
        emit_cache_event(:miss, %{id: id})
        :miss
    end
  end

  @spec cache_put(String.t(), Path.t(), map(), :load | :update | :create) :: true
  defp cache_put(id, path, draft, reason) do
    emit_cache_event(:write, %{id: id, reason: reason})
    :ets.insert(@table, {id, path, draft})
  end

  defp emit_cache_event(kind, metadata) do
    :telemetry.execute([:capcut_mcp, :cache, kind], %{count: 1}, metadata)
  end

  @spec ensure_path(String.t(), Path.t()) :: {:ok, Path.t()} | {:error, term()}
  defp ensure_path(id, root_path) do
    case cache_lookup(id) do
      {:ok, path, _draft} ->
        {:ok, path}

      :miss ->
        with {:ok, {path, draft}} <- load_project(id, root_path) do
          cache_put(id, path, draft, :load)
          {:ok, path}
        end
    end
  end

  @spec load_project(String.t(), Path.t()) ::
          {:ok, {Path.t(), map()}} | {:error, :not_found | term()}
  defp load_project(id, root_path) do
    with {:ok, projects} <- Reader.list_projects(root_path),
         %ProjectMeta{path: path} <- Enum.find(projects, &(&1.id == id)),
         {:ok, draft} <- Reader.read_draft(path) do
      {:ok, {path, draft}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp update_root_meta(root_path, id, name, project_path) do
    meta_file = Path.join(root_path, "root_meta_info.json")
    default_meta = %{"all_draft_store" => [], "draft_ids" => 0, "root_path" => root_path}

    existing =
      with {:ok, content} <- File.read(meta_file),
           {:ok, data} <- Jason.decode(content) do
        data
      else
        _ -> default_meta
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

  defp sanitize_dir_name(name) do
    safe =
      name
      |> String.replace(~r/[^\w\s\-]/u, "")
      |> String.replace(" ", "_")

    if safe == "", do: "Untitled_#{System.unique_integer([:positive])}", else: safe
  end

  defp generate_uuid, do: TimelineHelper.generate_uuid()
end
