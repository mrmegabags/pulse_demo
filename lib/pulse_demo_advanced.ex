defmodule PulseDemoAdvanced do
  @moduledoc """
  Advanced financial example demonstrating incremental computation with Pulse.

  Inputs (market + position data):
    * spot_fx         – current spot price
    * interest_rate   – interest rate (toy, not used in formula here)
    * volatility      – implied volatility
    * time_to_maturity (ttm)
    * position_size   – size of position
    * previous_value  – previous portfolio value

  Derived:
    * price            = f(spot, vol)              (toy pricing formula)
    * delta            = price / spot              (toy sensitivity)
    * vega             = price * vol * 0.1         (toy sensitivity)
    * theta            = -price * ttm * 0.05       (toy sensitivity)
    * var              = price * vol * sqrt(10)    (toy VaR)
    * portfolio_value  = price * position_size
    * pnl              = portfolio_value - previous_value
  """

  alias Pulse

  def main do
    IO.puts("\n=== Pulse: Portfolio Risk Engine (Incremental) ===\n")

    engine0 = Pulse.new()

    # Inputs
    {engine1, spot_fx} = Pulse.input(engine0, 100.0)
    {engine2, interest_rate} = Pulse.input(engine1, 0.02)
    {engine3, volatility} = Pulse.input(engine2, 0.30)
    {engine4, ttm} = Pulse.input(engine3, 0.5)
    {engine5, position_size} = Pulse.input(engine4, 10_000.0)
    {engine6, previous_value} = Pulse.input(engine5, 950_000.0)

    # Price: a toy options-like formula depending on spot and volatility
    {engine7, price} =
      Pulse.map2(engine6, spot_fx, volatility, fn spot, vol ->
        spot * (1.0 + vol * 0.2)
      end)

    # Delta: sensitivity to spot (toy)
    {engine8, delta} =
      Pulse.map2(engine7, price, spot_fx, fn price, spot ->
        price / spot
      end)

    # Vega: sensitivity to volatility (toy)
    {engine9, vega} =
      Pulse.map2(engine8, price, volatility, fn price, vol ->
        price * vol * 0.1
      end)

    # Theta: sensitivity to time to maturity (toy)
    {engine10, theta} =
      Pulse.map2(engine9, price, ttm, fn price, t ->
        -price * t * 0.05
      end)

    # Value at risk: toy VaR based on price and volatility
    {engine11, var} =
      Pulse.map2(engine10, price, volatility, fn price, vol ->
        price * vol * :math.sqrt(10.0)
      end)

    # Portfolio value
    {engine12, portfolio_value} =
      Pulse.map2(engine11, price, position_size, fn price, size ->
        price * size
      end)

    # Profit and loss
    {engine13, pnl} =
      Pulse.map2(engine12, portfolio_value, previous_value, fn pv, prev ->
        pv - prev
      end)

    # Initial compute
    {engine14, init_pnl} = Pulse.get(engine13, pnl)
    IO.puts("Initial PnL: #{init_pnl}")

    {engine15, init_delta} = Pulse.get(engine14, delta)
    {engine16, init_vega} = Pulse.get(engine15, vega)
    {engine17, init_var} = Pulse.get(engine16, var)
    {engine17, init_theta} = Pulse.get(engine17, theta)

    IO.puts("Initial Risk:")
    IO.puts("  delta = #{init_delta}")
    IO.puts("  vega  = #{init_vega}")
    IO.puts("  theta = #{init_theta}")
    IO.puts("  VaR   = #{init_var}")

    IO.puts("\n--- Now volatility changes from 0.30 → 0.35 ---\n")

    # Change only volatility
    engine18 = Pulse.set(engine17, volatility, 0.35)

    # Recompute only what depends on volatility (plus what depends on those)
    {engine19, new_pnl} = Pulse.get(engine18, pnl)
    {engine20, new_delta} = Pulse.get(engine19, delta)
    {engine21, new_vega} = Pulse.get(engine20, vega)
    {engine22, new_theta} = Pulse.get(engine21, theta)
    {_engine23, new_var} = Pulse.get(engine22, var)

    IO.puts("Updated PnL (after vol move): #{new_pnl}")
    IO.puts("Updated Risk (after vol move):")
    IO.puts("  delta = #{new_delta}")
    IO.puts("  vega  = #{new_vega}")
    IO.puts("  theta = #{new_theta}")
    IO.puts("  VaR   = #{new_var}")

    IO.puts("""
    \nNotice: spot_fx, interest_rate, time_to_maturity, and position_size
    are NOT recomputed; their values stay cached in the engine.
    Only the subgraph depending on volatility is recomputed.
    """)
  end
end
