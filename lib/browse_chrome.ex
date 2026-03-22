defmodule BrowseChrome do
  @moduledoc """
  Manage headless Chrome instances via the Chrome DevTools Protocol.

  BrowseChrome provides a pool of warm headless Chrome/Chromium browser instances,
  managed through a supervision tree. Each browser is ready to accept commands
  via the Chrome DevTools Protocol without cold-start overhead, with pool and
  browser lifecycle integration delegated to `Browse`.

  ## Usage

      # Check out a browser from the pool
      BrowseChrome.checkout(MyApp.ChromaPool, fn browser ->
        result =
          with {:ok, ws_url} <- BrowseChrome.Chrome.ws_url(browser) do
            BrowseChrome.CDP.with_session(ws_url, fn cdp ->
              :ok = BrowseChrome.CDP.navigate(cdp, "https://example.com")
              {:ok, data} = BrowseChrome.CDP.capture_screenshot(cdp, "jpeg", 90)
              {:ok, Base.decode64!(data)}
            end)
          end

        {result, :ok}
      end)

  ## Setup

  Configure BrowseChrome-managed pools under `:browse_chrome`:

      config :browse_chrome,
        default_pool: MyApp.ChromaPool,
        pools: [
          MyApp.ChromaPool: [pool_size: 4, chrome_path: "/usr/bin/chromium"]
        ]

  Then add the configured pools to your supervision tree:

      children = BrowseChrome.children()

  You can also add `BrowseChrome.BrowserPool` directly to your application's
  supervision tree:

      children = [
        {BrowseChrome.BrowserPool,
         name: MyApp.ChromaPool,
         pool_size: 4,
         chrome_path: "/usr/bin/chromium"}
      ]
  """

  alias BrowseChrome.BrowserPool

  @doc """
  Builds child specs from pools configured under `:browse_chrome`.
  """
  @spec children() :: [Supervisor.child_spec()]
  def children do
    configured_pools()
    |> Keyword.keys()
    |> Enum.map(&BrowserPool.child_spec/1)
  end

  @doc """
  Checks out a browser from the configured default pool.

  ## Options

    * `:timeout` - checkout timeout in milliseconds (default: `30_000`)
  """
  @spec checkout((pid() -> term()), keyword()) :: term()
  def checkout(fun, opts) when is_function(fun, 1) and is_list(opts) do
    checkout(default_pool!(), fun, opts)
  end

  @doc """
  Checks out a browser from the configured default pool.
  """
  @spec checkout((pid() -> term())) :: term()
  def checkout(fun) when is_function(fun, 1) do
    checkout(default_pool!(), fun, [])
  end

  @doc """
  Checks out a browser from the pool, runs the given function, and checks it back in.

  The function receives a browser pid and must return a `{result, checkin_instruction}` tuple,
  where `checkin_instruction` is either `:ok` (return browser to pool) or `:remove` (discard it).

  ## Options

    * `:timeout` - checkout timeout in milliseconds (default: `30_000`)

  ## Examples

      BrowseChrome.checkout(MyApp.ChromaPool, fn browser ->
        case BrowseChrome.Chrome.capture(browser, html, opts) do
          {:ok, _} = ok -> {ok, :ok}
          {:error, _} = error -> {error, :remove}
        end
      end)
  """
  @spec checkout(
          NimblePool.pool(),
          fun :: (pid() -> {term(), :ok | :remove}),
          keyword()
        ) :: term()
  def checkout(pool, fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    BrowserPool.checkout(pool, fun, timeout)
  end

  @spec default_pool!() :: NimblePool.pool()
  def default_pool! do
    Application.fetch_env!(:browse_chrome, :default_pool)
  end

  @spec configured_pools() :: keyword()
  def configured_pools do
    Application.get_env(:browse_chrome, :pools, [])
  end
end
