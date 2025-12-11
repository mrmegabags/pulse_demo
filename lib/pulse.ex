defmodule Pulse do
  @moduledoc """
  Pulse: a tiny incremental computation engine in Elixir.

  Concepts:

    * Engine:
        Holds the dependency graph, cached values, and dirty flags.
    * Node:
        A handle to a computation (internally an integer ID).
    * Input nodes:
        Values set from the outside (e.g. market data).
    * Derived nodes:
        Pure functions that depend on other nodes.

  Public API (functional, returns new Engine values):

    * new/0                – create a fresh engine
    * input/2              – create an input node
    * map2/4               – create a derived node from two dependencies
    * set/3                – update an input node
    * get/2                – read a node, recomputing what’s needed

  Internally, we also track `compute_log` so tests can see which
  derived nodes were recomputed (to demonstrate incrementality).
  """

  defmodule Engine do
    @moduledoc false
    defstruct next_id: 0,
              # id => %{deps: [id], kind: :input | {:derived, fun}}
              nodes: %{},
              # id => [ids that depend on this id]
              reverse_edges: %{},
              # id => value
              cache: %{},
              # ids that must be recomputed
              dirty: MapSet.new(),
              # list of derived node IDs that were recomputed (for tests)
              compute_log: []
  end

  defmodule Node do
    @moduledoc """
    A handle to a node in the Pulse graph.
    """
    defstruct [:id]
  end

  # ─────────────────────────────────────────────────────────────
  # Engine construction
  # ─────────────────────────────────────────────────────────────

  @doc """
  Create a fresh, empty engine.
  """
  def new() do
    %Engine{}
  end

  # ─────────────────────────────────────────────────────────────
  # Node creation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Create an input node with an initial value.

  Returns `{engine, %Node{}}`.
  """
  def input(%Engine{} = engine, initial_value) do
    id = engine.next_id

    nodes =
      Map.put(engine.nodes, id, %{
        deps: [],
        kind: :input
      })

    cache = Map.put(engine.cache, id, initial_value)

    node = %Node{id: id}

    {
      %Engine{engine | next_id: id + 1, nodes: nodes, cache: cache},
      node
    }
  end

  @doc """
  Create a derived node that depends on two existing nodes.

  `fun` is a pure function of two values.

  Returns `{engine, %Node{}}`.
  """
  def map2(%Engine{} = engine, %Node{id: id1}, %Node{id: id2}, fun)
      when is_function(fun, 2) do
    id = engine.next_id

    nodes =
      Map.put(engine.nodes, id, %{
        deps: [id1, id2],
        kind: {:derived, fun}
      })

    # register reverse edges: id1 -> id, id2 -> id
    reverse_edges =
      engine.reverse_edges
      |> add_reverse_edge(id1, id)
      |> add_reverse_edge(id2, id)

    # newly created derived nodes start dirty (must be computed on first get/2)
    dirty = MapSet.put(engine.dirty, id)

    node = %Node{id: id}

    {
      %Engine{
        engine
        | next_id: id + 1,
          nodes: nodes,
          reverse_edges: reverse_edges,
          dirty: dirty
      },
      node
    }
  end

  # ─────────────────────────────────────────────────────────────
  # Updating inputs
  # ─────────────────────────────────────────────────────────────

  @doc """
  Update the value of an input node.

  Marks all its transitive dependents (and itself) as dirty, so they will be
  recomputed the next time you call `get/2`.
  """
  def set(%Engine{} = engine, %Node{id: id}, new_value) do
    cache = Map.put(engine.cache, id, new_value)
    dirty = mark_dependents_dirty(engine.reverse_edges, engine.dirty, id)
    %Engine{engine | cache: cache, dirty: dirty}
  end

  # ─────────────────────────────────────────────────────────────
  # Reading with incremental recomputation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Get the current value of a node.

  If the node or its dependencies are dirty, they will be recomputed.
  Otherwise, the cached value is reused.

  Returns `{engine, value}`.
  """
  def get(%Engine{} = engine, %Node{id: id}) do
    {engine, value} = recompute_if_needed(engine, id)
    {engine, value}
  end

  # ─────────────────────────────────────────────────────────────
  # Internal helpers
  # ─────────────────────────────────────────────────────────────

  # Add reverse edge: from -> to
  defp add_reverse_edge(reverse_edges, from, to) do
    updated =
      case Map.get(reverse_edges, from) do
        nil -> [to]
        dependents -> [to | dependents]
      end

    Map.put(reverse_edges, from, updated)
  end

  # Mark all transitive dependents of `id` as dirty (including id itself).
  defp mark_dependents_dirty(reverse_edges, dirty_set, id) do
    do_mark_dependents_dirty(reverse_edges, dirty_set, [id])
  end

  defp do_mark_dependents_dirty(_reverse_edges, dirty_set, []), do: dirty_set

  defp do_mark_dependents_dirty(reverse_edges, dirty_set, [current | rest]) do
    dirty_set = MapSet.put(dirty_set, current)

    next =
      case Map.get(reverse_edges, current) do
        nil -> []
        dependents -> dependents
      end

    do_mark_dependents_dirty(reverse_edges, dirty_set, next ++ rest)
  end

  # Ensure node `id` is up to date (recompute if dirty).
  # Returns `{engine, value}`.
  defp recompute_if_needed(%Engine{} = engine, id) do
    if MapSet.member?(engine.dirty, id) do
      node_def = Map.fetch!(engine.nodes, id)

      case node_def.kind do
        :input ->
          # For inputs, set/3 already updated the cache; just clear dirty flag.
          dirty = MapSet.delete(engine.dirty, id)
          value = Map.fetch!(engine.cache, id)
          {%Engine{engine | dirty: dirty}, value}

        {:derived, fun} ->
          # First ensure dependencies are up to date.
          {engine_after_deps, dep_values} =
            Enum.reduce(node_def.deps, {engine, []}, fn dep_id, {eng_acc, values_acc} ->
              {eng_acc2, dep_value} = recompute_if_needed(eng_acc, dep_id)
              {eng_acc2, [dep_value | values_acc]}
            end)

          dep_values = Enum.reverse(dep_values)

          # Compute new value from dep_values
          [v1, v2] = dep_values
          new_value = fun.(v1, v2)

          cache = Map.put(engine_after_deps.cache, id, new_value)
          dirty = MapSet.delete(engine_after_deps.dirty, id)
          compute_log = [id | engine_after_deps.compute_log]

          {
            %Engine{
              engine_after_deps
              | cache: cache,
                dirty: dirty,
                compute_log: compute_log
            },
            new_value
          }
      end
    else
      # Not dirty: just read from cache
      value = Map.fetch!(engine.cache, id)
      {engine, value}
    end
  end
end

