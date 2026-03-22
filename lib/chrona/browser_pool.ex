defmodule Chrona.BrowserPool do
  @moduledoc """
  Compatibility wrapper around `Browse` for pools of warm `Chrona.Browser` workers.
  """
  alias Browse
  alias Chrona.BrowseBackend

  def child_spec(opts) do
    {pool, opts} = pool_and_opts(opts)
    Browse.child_spec(pool, opts)
  end

  def start_link(opts) do
    {pool, opts} = pool_and_opts(opts)
    Browse.start_link(pool, opts)
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
    {pool, Keyword.put_new(opts, :implementation, BrowseBackend)}
  end

  defp unwrap_browser(%Browse{state: browser}), do: browser
end
