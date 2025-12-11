defmodule PulseTest do
  use ExUnit.Case, async: true

  alias Pulse.Engine
  alias Pulse.Node

  test "input and map2 compute correct values" do
    engine0 = Pulse.new()

    {engine1, a} = Pulse.input(engine0, 2)
    {engine2, b} = Pulse.input(engine1, 3)

    {engine3, sum} =
      Pulse.map2(engine2, a, b, fn x, y ->
        x + y
      end)

    {_engine4, value} = Pulse.get(engine3, sum)

    assert value == 5
  end

  test "incremental recomputation recomputes only affected derived nodes" do
    engine0 = Pulse.new()

    # Node IDs will be:
    #  0: a (input)
    #  1: b (input)
    #  2: e (input)
    #  3: c (derived: a + b)
    #  4: d (derived: c * e)

    {engine1, a} = Pulse.input(engine0, 2)
    {engine2, b} = Pulse.input(engine1, 3)
    {engine3, e} = Pulse.input(engine2, 10)

    {engine4, c} =
      Pulse.map2(engine3, a, b, fn x, y ->
        x + y
      end)

    {engine5, d} =
      Pulse.map2(engine4, c, e, fn c_val, e_val ->
        c_val * e_val
      end)

    # First computation: both c and d must be computed
    {engine6, _value} = Pulse.get(engine5, d)
    %{compute_log: log1} = engine6

    assert Enum.sort(Enum.uniq(log1)) == Enum.sort([3, 4])

    # Reset compute_log (for clean measurement)
    engine6_clean = %Engine{engine6 | compute_log: []}

    # Change only a: this should mark c and d dirty, but not b or e.
    engine7 = Pulse.set(engine6_clean, a, 5)

    {engine8, _value2} = Pulse.get(engine7, d)
    %{compute_log: log2} = engine8

    # Only the derived nodes c (3) and d (4) should recompute
    assert Enum.sort(Enum.uniq(log2)) == Enum.sort([3, 4])
  end
end

