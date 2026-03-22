defmodule Chrona.BrowseBackend do
  @moduledoc false

  @behaviour Browse.Browser

  alias Chrona.Browser
  alias Chrona.CDP

  @impl Browse.Browser
  def init(opts) do
    opts
    |> Keyword.delete(:name)
    |> Browser.start_link()
  end

  @impl Browse.Browser
  def terminate(_reason, browser) when is_pid(browser) do
    GenServer.stop(browser, :normal)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @impl Browse.Browser
  def navigate(browser, url, _opts) do
    with_ws_session(browser, fn cdp -> CDP.navigate(cdp, url) end)
  end

  @impl Browse.Browser
  def current_url(browser) do
    with_ws_session(browser, fn cdp ->
      case CDP.command(cdp, "Runtime.evaluate", %{expression: "window.location.href"}) do
        {:ok, %{"result" => %{"value" => url}}} -> {:ok, url}
        {:ok, result} -> {:error, {:unexpected_response, result}}
        {:error, _} = error -> error
      end
    end)
  end

  @impl Browse.Browser
  def content(browser) do
    with_ws_session(browser, fn cdp ->
      case CDP.command(cdp, "Runtime.evaluate", %{expression: "document.documentElement.outerHTML"}) do
        {:ok, %{"result" => %{"value" => html}}} -> {:ok, html}
        {:ok, result} -> {:error, {:unexpected_response, result}}
        {:error, _} = error -> error
      end
    end)
  end

  @impl Browse.Browser
  def evaluate(browser, script, _opts) do
    with_ws_session(browser, fn cdp ->
      case CDP.command(cdp, "Runtime.evaluate", %{expression: script, returnByValue: true}) do
        {:ok, %{"result" => %{"value" => value}}} -> {:ok, value}
        {:ok, %{"result" => result}} -> {:ok, result}
        {:ok, result} -> {:ok, result}
        {:error, _} = error -> error
      end
    end)
  end

  @impl Browse.Browser
  def capture_screenshot(browser, opts) do
    quality = Keyword.get(opts, :quality, 90)
    format = Keyword.get(opts, :format, "png")

    with_ws_session(browser, fn cdp ->
      with {:ok, data} <- CDP.capture_screenshot(cdp, format, quality) do
        {:ok, Base.decode64!(data)}
      end
    end)
  end

  @impl Browse.Browser
  def print_to_pdf(_browser, _opts), do: {:error, :unsupported}

  @impl Browse.Browser
  def click(_browser, _locator, _opts), do: {:error, :unsupported}

  @impl Browse.Browser
  def fill(_browser, _locator, _value, _opts), do: {:error, :unsupported}

  @impl Browse.Browser
  def wait_for(_browser, _locator, _opts), do: {:error, :unsupported}

  defp with_ws_session(browser, fun) do
    browser
    |> browser_ws_url()
    |> case do
      {:ok, ws_url} -> CDP.with_session(ws_url, fun)
      {:error, _} = error -> error
    end
  end

  defp browser_ws_url(browser) when is_pid(browser) do
    {:ok, :sys.get_state(browser).ws_url}
  catch
    :exit, _reason -> {:error, :browser_unavailable}
  end
end
