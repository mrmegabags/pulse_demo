---

````markdown
# Pulse: A Tiny Incremental Computation Engine for Elixir

**Pulse** is a lightweight incremental computation engine implemented in pure Elixir.

It lets you build dependency graphs where:

- **input nodes** represent external values (market data, configuration, state),
- **derived nodes** represent pure functions of other nodes.

When an input changes, Pulse efficiently **recomputes only what is necessary**, reusing cached values for everything else. This is useful in pricing engines, analytics pipelines, simulations, dashboards, and any environment requiring incremental updates.

---

## Features

- Pure-functional, immutable engine state.
- Input and derived nodes with cached values.
- Automatic dirty propagation when inputs change.
- Lazy recomputation on `get/2`.
- `compute_log` shows exactly which derived nodes were recomputed.
- Zero dependencies; works on standard Elixir.

---

## Basic Example

```elixir
engine = Pulse.new()

# Inputs
{engine, a} = Pulse.input(engine, 10)
{engine, b} = Pulse.input(engine, 20)

# Derived node
{engine, sum} = Pulse.map2(engine, a, b, fn x, y -> x + y end)

# First read: computes the derived value
{engine, result} = Pulse.get(engine, sum)
IO.puts("Sum = #{result}")   # 30

# Update an input
engine = Pulse.set(engine, a, 100)

# Second read: recomputes only affected nodes
{engine, result2} = Pulse.get(engine, sum)
IO.puts("Updated sum = #{result2}")  # 120

IO.inspect(engine.compute_log, label: "Recomputed nodes")
````

---

## Advanced Example: Portfolio Risk Engine

This repository includes `PulseDemoAdvanced`, which computes:

* price
* delta
* vega
* theta
* VaR
* portfolio value
* PnL

It demonstrates that when one input (e.g., volatility) changes, only the dependent downstream nodes recompute.

### Run the demo

From project root:

```bash
iex -S mix
```

Then:

```elixir
iex> PulseDemoAdvanced.main()
```

You will see output similar to:

```
=== Pulse: Portfolio Risk Engine (Incremental) ===
Initial PnL: ...
Initial Risk:
  delta = ...
  vega  = ...
  theta = ...
  VaR   = ...

--- Now volatility changes from 0.30 → 0.35 ---

Updated PnL (after vol move): ...
Updated Risk:
  delta = ...
  vega  = ...
  theta = ...
  VaR   = ...
```

---

## Installation (as a Mix dependency)

If using Pulse from another project:

```elixir
def deps do
  [
    {:pulse, path: "../pulse"}
  ]
end
```

Or copy `lib/pulse.ex` directly into your project.

---

## API Overview

### `Pulse.new/0`

Create a fresh engine.

### `Pulse.input/2`

Create an input node with an initial value.
Returns `{engine, %Pulse.Node{}}`.

### `Pulse.map2/4`

Create a derived node depending on two other nodes.

### `Pulse.set/3`

Update an input node and mark all dependents as dirty.

### `Pulse.get/2`

Retrieve the current value (recomputing only what is necessary).
Returns `{engine, value}`.

### Engine internals

* `nodes`: dependency graph
* `reverse_edges`: dependents for dirty propagation
* `cache`: cached node values
* `dirty`: set of nodes needing recomputation
* `compute_log`: list of recomputed derived node IDs

---

## Why Incremental Computation?

Pulse demonstrates a simplified version of engines used in:

* financial pricing systems
* FRP (functional reactive programming) frameworks
* build systems (e.g., Bazel, Make)
* incremental compilers
* dependency-driven dashboards

The key benefit: **update cost scales with the size of the affected subgraph, not the entire computation.**

---

## Project Structure

```
lib/
  pulse.ex                  # Core engine
  pulse_demo_advanced.ex   # Advanced demo

mix.exs
README.md
```

---

## Contributing

Contributions are welcome. Ideas include:

* Additional demos (analytics, simulations, UI models)
* Performance improvements
* More derived node combinators (map3, mapN, fanout)
* Batch updates, snapshots, diffing, etc.

---

## License

Specify your preferred license (MIT recommended).

```
