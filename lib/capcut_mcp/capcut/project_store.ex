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
      {:ok, _path, _meta, draft} -> {:ok, draft}
      :miss -> GenServer.call(__MODULE__, {:load_project, id})
    end
  end

  @doc """
  Like `get_project/1` but returns the `ProjectMeta` (from `root_meta_info.json`)
  alongside the draft map. Tools that render project identity should use this —
  `draft_content.json`'s internal `"id"` and `"name"` can diverge from what the
  manifest says, and only the manifest's values are stable addresses.
  """
  @spec get_project_with_meta(String.t()) ::
          {:ok, %{meta: ProjectMeta.t(), draft: map()}} | {:error, :not_found | term()}
  def get_project_with_meta(id) do
    case cache_lookup(id) do
      {:ok, _path, meta, draft} -> {:ok, %{meta: meta, draft: draft}}
      :miss -> GenServer.call(__MODULE__, {:load_project_with_meta, id})
    end
  end

  @spec update_project(String.t(), map()) :: :ok | {:error, term()}
  def update_project(id, draft), do: GenServer.call(__MODULE__, {:update_project, id, draft})

  @spec create_project(map()) :: {:ok, String.t()} | {:error, term()}
  def create_project(params), do: GenServer.call(__MODULE__, {:create_project, params})

  @doc """
  Removes a project from `root_meta_info.json` and (by default) deletes its
  folder on disk. Pass `keep_files: true` to leave the folder intact.

  Refuses to delete any folder whose `draft_fold_path` lies outside the
  configured CapCut root — such entries indicate a corrupt or hand-edited
  manifest and must not trigger a destructive recursive delete.
  """
  @spec remove_project(String.t(), keyword()) ::
          :ok | {:error, :not_found | :path_outside_root | term()}
  def remove_project(id, opts \\ []),
    do: GenServer.call(__MODULE__, {:remove_project, id, opts})

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
      {:ok, _path, _meta, draft} ->
        {:reply, {:ok, draft}, state}

      :miss ->
        with {:ok, root} <- require_root_path(state),
             {:ok, {path, meta, draft}} <- load_project(id, root) do
          cache_put(id, path, meta, draft, :load)
          {:reply, {:ok, draft}, state}
        else
          {:error, _} = error -> {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:load_project_with_meta, id}, _from, state) do
    case cache_lookup(id) do
      {:ok, _path, meta, draft} ->
        {:reply, {:ok, %{meta: meta, draft: draft}}, state}

      :miss ->
        with {:ok, root} <- require_root_path(state),
             {:ok, {path, meta, draft}} <- load_project(id, root) do
          cache_put(id, path, meta, draft, :load)
          {:reply, {:ok, %{meta: meta, draft: draft}}, state}
        else
          {:error, _} = error -> {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:update_project, id, draft}, _from, state) do
    with {:ok, root} <- require_root_path(state),
         {:ok, {path, meta}} <- ensure_path_with_meta(id, root),
         :ok <- Writer.write_draft(path, draft) do
      cache_put(id, path, meta, draft, :update)
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

  @impl true
  def handle_call({:remove_project, id, opts}, _from, state) do
    with {:ok, root} <- require_root_path(state),
         :ok <- do_remove_project(root, id, opts) do
      :ets.delete(@table, id)
      {:reply, :ok, state}
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  defp do_create_project(root, params) do
    id = generate_uuid()
    name = Map.get(params, "name", "New Project")

    with {:ok, draft} <-
           Draft.new(
             id: id,
             name: name,
             width: Map.get(params, "width", 1920),
             height: Map.get(params, "height", 1080),
             fps: Map.get(params, "fps", 30.0)
           ) do
      draft_map = Draft.to_json(draft)
      project_path = Path.join(root, sanitize_dir_name(name))

      with :ok <- File.mkdir_p(project_path),
           :ok <- Writer.write_draft(project_path, draft_map),
           :ok <- update_root_meta(root, id, name, project_path) do
        meta = %ProjectMeta{
          id: id,
          name: name,
          path: project_path,
          modified_at: System.os_time(:microsecond),
          duration_ms: 0
        }

        cache_put(id, project_path, meta, draft_map, :create)
        {:ok, id}
      end
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
  @spec cache_lookup(String.t()) :: {:ok, Path.t(), ProjectMeta.t(), map()} | :miss
  defp cache_lookup(id) do
    case :ets.lookup(@table, id) do
      [{^id, path, meta, draft}] ->
        emit_cache_event(:hit, %{id: id})
        {:ok, path, meta, draft}

      [] ->
        emit_cache_event(:miss, %{id: id})
        :miss
    end
  end

  @spec cache_put(String.t(), Path.t(), ProjectMeta.t(), map(), :load | :update | :create) :: true
  defp cache_put(id, path, meta, draft, reason) do
    emit_cache_event(:write, %{id: id, reason: reason})
    :ets.insert(@table, {id, path, meta, draft})
  end

  defp emit_cache_event(kind, metadata) do
    :telemetry.execute([:capcut_mcp, :cache, kind], %{count: 1}, metadata)
  end

  @spec ensure_path_with_meta(String.t(), Path.t()) ::
          {:ok, {Path.t(), ProjectMeta.t()}} | {:error, term()}
  defp ensure_path_with_meta(id, root_path) do
    case cache_lookup(id) do
      {:ok, path, meta, _draft} ->
        {:ok, {path, meta}}

      :miss ->
        with {:ok, {path, meta, draft}} <- load_project(id, root_path) do
          cache_put(id, path, meta, draft, :load)
          {:ok, {path, meta}}
        end
    end
  end

  @spec load_project(String.t(), Path.t()) ::
          {:ok, {Path.t(), ProjectMeta.t(), map()}} | {:error, :not_found | term()}
  defp load_project(id, root_path) do
    with {:ok, projects} <- Reader.list_projects(root_path),
         %ProjectMeta{path: path} = meta <- Enum.find(projects, &(&1.id == id)),
         {:ok, draft} <- Reader.read_draft(path) do
      {:ok, {path, meta, draft}}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp update_root_meta(root_path, id, name, project_path) do
    meta_file = Path.join(root_path, "root_meta_info.json")

    existing =
      with {:ok, content} <- File.read(meta_file),
           {:ok, data} when is_map(data) <- Jason.decode(content) do
        data
      else
        _ -> %{}
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

    # Use Map.update/4 with defaults so a foreign-shaped but valid JSON — e.g. a
    # future CapCut version that drops one of these keys — doesn't crash the
    # GenServer.
    updated =
      existing
      |> Map.put_new("root_path", root_path)
      |> Map.update("all_draft_store", [new_entry], fn
        list when is_list(list) -> [new_entry | list]
        _ -> [new_entry]
      end)
      |> Map.update("draft_ids", 1, fn
        n when is_integer(n) -> n + 1
        _ -> 1
      end)

    Writer.write_root_meta(root_path, updated)
  end

  @spec do_remove_project(Path.t(), String.t(), keyword()) ::
          :ok | {:error, :not_found | :path_outside_root | term()}
  defp do_remove_project(root, id, opts) do
    meta_file = Path.join(root, "root_meta_info.json")

    with {:ok, content} <- File.read(meta_file),
         {:ok, data} when is_map(data) <- Jason.decode(content),
         {:ok, entry, remaining} <- extract_entry(data, id),
         :ok <- maybe_delete_folder(entry, root, Keyword.get(opts, :keep_files, false)) do
      Writer.write_root_meta(root, apply_remaining(data, remaining), backup: true)
    end
  end

  defp extract_entry(data, id) do
    store = Map.get(data, "all_draft_store", [])

    with true <- is_list(store),
         {[entry], remaining} <-
           Enum.split_with(store, fn
             %{"draft_id" => ^id} -> true
             _ -> false
           end) do
      {:ok, entry, remaining}
    else
      _ -> {:error, :not_found}
    end
  end

  defp apply_remaining(data, remaining) do
    data
    |> Map.put("all_draft_store", remaining)
    |> Map.update("draft_ids", length(remaining), fn
      n when is_integer(n) and n > 0 -> n - 1
      _ -> length(remaining)
    end)
  end

  defp maybe_delete_folder(_entry, _root, true), do: :ok

  defp maybe_delete_folder(%{"draft_fold_path" => path}, root, false) when is_binary(path) do
    if Reader.path_under_root?(path, Path.expand(root)) do
      case File.rm_rf(path) do
        {:ok, _} -> :ok
        {:error, reason, _} -> {:error, reason}
      end
    else
      {:error, :path_outside_root}
    end
  end

  # Entry without a draft_fold_path — nothing to remove on disk, not a failure.
  defp maybe_delete_folder(_entry, _root, false), do: :ok

  defp sanitize_dir_name(name) do
    safe =
      name
      |> String.replace(~r/[^\w\s\-]/u, "")
      |> String.replace(" ", "_")

    if safe == "", do: "Untitled_#{System.unique_integer([:positive])}", else: safe
  end

  defp generate_uuid, do: TimelineHelper.generate_uuid()
end
