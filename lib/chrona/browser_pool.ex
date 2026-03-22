defmodule Chrona.BrowserPool do
  @moduledoc """
  A NimblePool that manages a pool of warm headless Chrome instances.

  Each pool resource is a `Chrona.Browser` GenServer process,
  ready to accept commands without cold-start overhead.
  """

  @behaviour NimblePool

  alias Chrona.Browser

  def child_spec(opts) do
    name = Keyword.get(opts, :name, __MODULE__)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  def start_link(opts) do
    {pool_size, worker_opts} = Keyword.pop!(opts, :pool_size)
    {name, worker_opts} = Keyword.pop(worker_opts, :name)

    pool_opts =
      [worker: {__MODULE__, worker_opts}, pool_size: pool_size]
      |> maybe_put_name(name)

    NimblePool.start_link(pool_opts)
  end

  @doc """
  Checks out a warm Browser process, runs the given function with it,
  and checks it back in.
  """
  def checkout(pool, fun, timeout \\ 30_000) do
    NimblePool.checkout!(
      pool,
      :checkout,
      fn _from, browser ->
        fun.(browser)
      end,
      timeout
    )
  end

  # NimblePool Callbacks

  @impl NimblePool
  def init_worker(opts) do
    case Browser.start_link(opts) do
      {:ok, browser} ->
        {:ok, browser, opts}

      {:error, reason} ->
        raise "failed to start browser worker: #{inspect(reason)}"
    end
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, browser, pool_state) do
    {:ok, browser, browser, pool_state}
  end

  @impl NimblePool
  def handle_checkin(:ok, _from, browser, pool_state) do
    {:ok, browser, pool_state}
  end

  def handle_checkin(:remove, _from, _browser, pool_state) do
    {:remove, :closed, pool_state}
  end

  @impl NimblePool
  def terminate_worker(_reason, browser, pool_state) do
    GenServer.stop(browser, :normal)
    {:ok, pool_state}
  end

  defp maybe_put_name(opts, nil), do: opts
  defp maybe_put_name(opts, name), do: Keyword.put(opts, :name, name)
end
