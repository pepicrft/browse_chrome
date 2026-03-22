defmodule Chrona do
  @moduledoc """
  Manage headless Chrome instances via the Chrome DevTools Protocol.

  Chrona provides a pool of warm headless Chrome/Chromium browser instances,
  managed through a supervision tree. Each browser is ready to accept commands
  via the Chrome DevTools Protocol without cold-start overhead.

  ## Usage

      # Check out a browser from the pool
      Chrona.checkout(fn browser ->
        {:ok, cdp} = Chrona.CDP.connect(browser.ws_url)
        :ok = Chrona.CDP.navigate(cdp, "https://example.com")
        {:ok, data} = Chrona.CDP.capture_screenshot(cdp, "jpeg", 90)
        Chrona.CDP.disconnect(cdp)
        {{:ok, Base.decode64!(data)}, :ok}
      end)

  ## Configuration

      # config/config.exs
      config :chrona,
        pool_size: 4,           # number of warm Chrome instances (default: 2)
        chrome_path: "/usr/bin/chromium"  # auto-detected if omitted
  """

  alias Chrona.BrowserPool

  @doc """
  Checks out a browser from the pool, runs the given function, and checks it back in.

  The function receives a browser pid and must return a `{result, checkin_instruction}` tuple,
  where `checkin_instruction` is either `:ok` (return browser to pool) or `:remove` (discard it).

  ## Options

    * `:timeout` - checkout timeout in milliseconds (default: `30_000`)

  ## Examples

      Chrona.checkout(fn browser ->
        case Chrona.Browser.capture(browser, html, opts) do
          {:ok, _} = ok -> {ok, :ok}
          {:error, _} = error -> {error, :remove}
        end
      end)
  """
  @spec checkout(fun :: (pid() -> {term(), :ok | :remove}), keyword()) :: term()
  def checkout(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    BrowserPool.checkout(fun, timeout)
  end
end
