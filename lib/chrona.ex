defmodule Chrona do
  @moduledoc """
  Manage headless Chrome instances via the Chrome DevTools Protocol.

  Chrona provides a pool of warm headless Chrome/Chromium browser instances,
  managed through a supervision tree. Each browser is ready to accept commands
  via the Chrome DevTools Protocol without cold-start overhead.

  ## Usage

      # Check out a browser from the pool
      Chrona.checkout(MyApp.ChromaPool, fn browser ->
        result =
          Chrona.CDP.with_session(browser.ws_url, fn cdp ->
            :ok = Chrona.CDP.navigate(cdp, "https://example.com")
            {:ok, data} = Chrona.CDP.capture_screenshot(cdp, "jpeg", 90)
            {:ok, Base.decode64!(data)}
          end)

        {result, :ok}
      end)

  ## Setup

  Add `Chrona.BrowserPool` to your application's supervision tree:

      children = [
        {Chrona.BrowserPool,
         name: MyApp.ChromaPool,
         pool_size: 4,
         chrome_path: "/usr/bin/chromium"}
      ]
  """

  alias Chrona.BrowserPool
  alias Chrona.Telemetry

  @doc """
  Checks out a browser from the pool, runs the given function, and checks it back in.

  The function receives a browser pid and must return a `{result, checkin_instruction}` tuple,
  where `checkin_instruction` is either `:ok` (return browser to pool) or `:remove` (discard it).

  ## Options

    * `:timeout` - checkout timeout in milliseconds (default: `30_000`)

  ## Examples

      Chrona.checkout(MyApp.ChromaPool, fn browser ->
        case Chrona.Browser.capture(browser, html, opts) do
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

    Telemetry.span([:checkout], %{pool: pool, timeout: timeout}, fn ->
      BrowserPool.checkout(pool, fun, timeout)
    end)
  end
end
