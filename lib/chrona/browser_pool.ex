defmodule Chrona.BrowserPool do
  @moduledoc """
  Compatibility wrapper around `Browse` for pools of warm `Chrona.Chrome` workers.
  """
  alias Browse
  alias Chrona
  alias Chrona.Browser

  def child_spec(pool) when not is_list(pool) do
    child_spec(pool, [])
  end

  def child_spec(opts) when is_list(opts) do
    {pool, opts} = pool_and_opts(opts)
    Browse.child_spec(pool, opts)
  end

  def child_spec(pool, opts) do
    Browse.child_spec(pool, pool_opts(pool, opts))
  end

  def start_link(pool) when not is_list(pool) do
    start_link(pool, [])
  end

  def start_link(opts) when is_list(opts) do
    {pool, opts} = pool_and_opts(opts)
    Browse.start_link(pool, opts)
  end

  def start_link(pool, opts) do
    Browse.start_link(pool, pool_opts(pool, opts))
  end

  @doc """
  Checks out a warm Browser process, runs the given function with it,
  and checks it back in.
  """
  def checkout(pool, fun, timeout \\ 30_000) do
    Browse.checkout(pool, fn browser -> fun.(unwrap_browser(browser)) end, timeout: timeout)
  end

  defp pool_and_opts(opts) do
    {pool, opts} = Keyword.pop(opts, :name, __MODULE__)
    {pool, pool_opts(pool, opts)}
  end

  defp pool_opts(pool, opts) do
    configured_opts =
      Chrona.configured_pools()
      |> Keyword.get(pool, [])

    configured_opts
    |> Keyword.merge(opts)
    |> Keyword.put_new(:implementation, Browser)
  end

  defp unwrap_browser(%Browse{state: browser}), do: browser
end
