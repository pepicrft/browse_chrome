defmodule BrowseChrome.Browser do
  @moduledoc false

  @behaviour Browse.Browser

  alias BrowseChrome.CDP
  alias BrowseChrome.Chrome

  @default_wait_timeout 5_000
  @wait_interval 100

  @impl Browse.Browser
  def init(opts) do
    opts
    |> Keyword.delete(:name)
    |> Chrome.start_link()
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
  def print_to_pdf(browser, opts) do
    with_ws_session(browser, fn cdp ->
      params =
        opts
        |> Map.new()
        |> stringify_keys()

      case CDP.command(cdp, "Page.printToPDF", params) do
        {:ok, %{"data" => data}} -> {:ok, Base.decode64!(data)}
        {:ok, result} -> {:error, {:unexpected_response, result}}
        {:error, _} = error -> error
      end
    end)
  end

  @impl Browse.Browser
  def click(browser, locator, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, %{"ok" => true}} <- eval_dom(cdp, click_expression(selector)) do
        :ok
      end
    end)
  end

  @impl Browse.Browser
  def fill(browser, locator, value, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, %{"ok" => true}} <- eval_dom(cdp, fill_expression(selector, value)) do
        :ok
      end
    end)
  end

  @impl Browse.Browser
  def wait_for(browser, locator, opts) do
    timeout = Keyword.get(opts, :timeout, @default_wait_timeout)
    state = Keyword.get(opts, :state, :visible)

    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, predicate} <- wait_predicate(selector, state) do
        wait_until(cdp, predicate, System.monotonic_time(:millisecond) + timeout)
      end
    end)
  end

  @impl Browse.Browser
  def go_back(browser, _opts) do
    with_ws_session(browser, fn cdp -> navigate_history(cdp, -1) end)
  end

  @impl Browse.Browser
  def go_forward(browser, _opts) do
    with_ws_session(browser, fn cdp -> navigate_history(cdp, 1) end)
  end

  @impl Browse.Browser
  def reload(browser, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, _} <- CDP.command(cdp, "Page.reload", %{}) do
        wait_for_document_ready(cdp)
      end
    end)
  end

  @impl Browse.Browser
  def title(browser) do
    with_ws_session(browser, fn cdp -> eval_value(cdp, "document.title") end)
  end

  @impl Browse.Browser
  def select_option(browser, locator, value, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, %{"ok" => true}} <- eval_dom(cdp, select_option_expression(selector, value)) do
        :ok
      end
    end)
  end

  @impl Browse.Browser
  def hover(browser, locator, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, %{"ok" => true}} <- eval_dom(cdp, hover_expression(selector)) do
        :ok
      end
    end)
  end

  @impl Browse.Browser
  def get_text(browser, locator, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, %{"ok" => true, "value" => text}} <- eval_dom(cdp, get_text_expression(selector)) do
        {:ok, text}
      end
    end)
  end

  @impl Browse.Browser
  def get_attribute(browser, locator, name, _opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, selector} <- normalize_locator(locator),
           {:ok, %{"ok" => true} = result} <- eval_dom(cdp, get_attribute_expression(selector, name)) do
        {:ok, Map.get(result, "value")}
      end
    end)
  end

  @impl Browse.Browser
  def get_cookies(browser, opts) do
    with_ws_session(browser, fn cdp ->
      params =
        case cookie_urls(opts) do
          [] -> %{}
          urls -> %{"urls" => urls}
        end

      case CDP.command(cdp, "Network.getCookies", params) do
        {:ok, %{"cookies" => cookies}} -> {:ok, cookies}
        {:ok, result} -> {:error, {:unexpected_response, result}}
        {:error, _} = error -> error
      end
    end)
  end

  @impl Browse.Browser
  def set_cookie(browser, cookie, opts) do
    with_ws_session(browser, fn cdp ->
      with {:ok, params} <- build_cookie_params(cdp, cookie, opts),
           {:ok, %{"success" => true}} <- CDP.command(cdp, "Network.setCookie", params) do
        :ok
      else
        {:ok, %{"success" => false}} -> {:error, :cookie_not_set}
        {:ok, result} -> {:error, {:unexpected_response, result}}
        {:error, _} = error -> error
      end
    end)
  end

  @impl Browse.Browser
  def clear_cookies(browser, _opts) do
    with_ws_session(browser, fn cdp ->
      case CDP.command(cdp, "Network.clearBrowserCookies", %{}) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    end)
  end

  defp with_ws_session(browser, fun) do
    browser
    |> Chrome.ws_url()
    |> case do
      {:ok, ws_url} -> CDP.with_session(ws_url, fun)
      {:error, _} = error -> error
    end
  end

  defp navigate_history(cdp, offset) do
    with {:ok, %{"currentIndex" => current_index, "entries" => entries}} <-
           CDP.command(cdp, "Page.getNavigationHistory", %{}),
         {:ok, entry} <- navigation_entry(entries, current_index + offset),
         {:ok, _} <- CDP.command(cdp, "Page.navigateToHistoryEntry", %{"entryId" => entry["id"]}) do
      wait_for_document_ready(cdp)
    end
  end

  defp navigation_entry(entries, index) do
    case Enum.at(entries, index) do
      nil -> {:error, :navigation_history_unavailable}
      entry -> {:ok, entry}
    end
  end

  defp normalize_locator(locator) when is_binary(locator), do: {:ok, locator}
  defp normalize_locator({:css, locator}) when is_binary(locator), do: {:ok, locator}
  defp normalize_locator(locator), do: {:error, {:unsupported_locator, locator}}

  defp eval_dom(cdp, expression) do
    case eval_value(cdp, expression) do
      {:ok, %{"ok" => true} = result} -> {:ok, result}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, {:dom_error, error}}
      {:ok, result} -> {:error, {:unexpected_response, result}}
      {:error, _} = error -> error
    end
  end

  defp eval_value(cdp, expression) do
    params = %{expression: expression, returnByValue: true, awaitPromise: true}

    case CDP.command(cdp, "Runtime.evaluate", params) do
      {:ok, %{"exceptionDetails" => details}} ->
        {:error, {:javascript_error, details}}

      {:ok, %{"result" => %{"type" => "undefined"}}} ->
        {:ok, nil}

      {:ok, %{"result" => %{"value" => value}}} ->
        {:ok, value}

      {:ok, %{"result" => result}} ->
        {:ok, result}

      {:ok, result} ->
        {:ok, result}

      {:error, _} = error ->
        error
    end
  end

  defp wait_until(cdp, predicate, deadline_ms) do
    case eval_value(cdp, predicate) do
      {:ok, true} ->
        :ok

      {:ok, false} ->
        if System.monotonic_time(:millisecond) >= deadline_ms do
          {:error, :timeout}
        else
          Process.sleep(@wait_interval)
          wait_until(cdp, predicate, deadline_ms)
        end

      {:ok, result} ->
        {:error, {:unexpected_response, result}}

      {:error, _} = error ->
        error
    end
  end

  defp wait_for_document_ready(cdp) do
    wait_until(cdp, "document.readyState === 'complete'", System.monotonic_time(:millisecond) + @default_wait_timeout)
  end

  defp wait_predicate(selector, state) do
    escaped_selector = encode_js(selector)

    case state do
      :attached ->
        {:ok, "document.querySelector(#{escaped_selector}) !== null"}

      :visible ->
        {:ok,
         """
         (() => {
           const element = document.querySelector(#{escaped_selector});
           if (!element) return false;
           const style = window.getComputedStyle(element);
           const rect = element.getBoundingClientRect();
           return style.display !== "none" &&
             style.visibility !== "hidden" &&
             rect.width > 0 &&
             rect.height > 0;
         })()
         """}

      :hidden ->
        {:ok,
         """
         (() => {
           const element = document.querySelector(#{escaped_selector});
           if (!element) return true;
           const style = window.getComputedStyle(element);
           const rect = element.getBoundingClientRect();
           return style.display === "none" ||
             style.visibility === "hidden" ||
             rect.width === 0 ||
             rect.height === 0;
         })()
         """}

      :detached ->
        {:ok, "document.querySelector(#{escaped_selector}) === null"}

      other ->
        {:error, {:unsupported_wait_state, other}}
    end
  end

  defp click_expression(selector) do
    """
    (() => {
      const element = document.querySelector(#{encode_js(selector)});
      if (!element) return {ok: false, error: "element_not_found"};
      element.scrollIntoView({block: "center", inline: "center"});
      element.click();
      return {ok: true};
    })()
    """
  end

  defp fill_expression(selector, value) do
    """
    (() => {
      const element = document.querySelector(#{encode_js(selector)});
      if (!element) return {ok: false, error: "element_not_found"};
      const value = #{encode_js(value)};
      element.scrollIntoView({block: "center", inline: "center"});
      element.focus();
      if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
        element.value = value;
      } else if (element instanceof HTMLSelectElement) {
        element.value = value;
      } else if (element.isContentEditable) {
        element.textContent = value;
      } else {
        return {ok: false, error: "element_not_fillable"};
      }
      element.dispatchEvent(new Event("input", {bubbles: true}));
      element.dispatchEvent(new Event("change", {bubbles: true}));
      return {ok: true};
    })()
    """
  end

  defp select_option_expression(selector, value) do
    """
    (() => {
      const element = document.querySelector(#{encode_js(selector)});
      if (!element) return {ok: false, error: "element_not_found"};
      if (!(element instanceof HTMLSelectElement)) {
        return {ok: false, error: "element_not_select"};
      }
      const value = #{encode_js(value)};
      const option = Array.from(element.options).find((entry) => entry.value === value);
      if (!option) return {ok: false, error: "option_not_found"};
      element.value = value;
      element.dispatchEvent(new Event("input", {bubbles: true}));
      element.dispatchEvent(new Event("change", {bubbles: true}));
      return {ok: true};
    })()
    """
  end

  defp hover_expression(selector) do
    """
    (() => {
      const element = document.querySelector(#{encode_js(selector)});
      if (!element) return {ok: false, error: "element_not_found"};
      element.scrollIntoView({block: "center", inline: "center"});
      const rect = element.getBoundingClientRect();
      const coords = {
        bubbles: true,
        cancelable: true,
        clientX: rect.left + rect.width / 2,
        clientY: rect.top + rect.height / 2
      };
      element.dispatchEvent(new MouseEvent("mouseover", coords));
      element.dispatchEvent(new MouseEvent("mouseenter", coords));
      element.dispatchEvent(new MouseEvent("mousemove", coords));
      return {ok: true};
    })()
    """
  end

  defp get_text_expression(selector) do
    """
    (() => {
      const element = document.querySelector(#{encode_js(selector)});
      if (!element) return {ok: false, error: "element_not_found"};
      return {ok: true, value: (element.innerText ?? element.textContent ?? "").trim()};
    })()
    """
  end

  defp get_attribute_expression(selector, name) do
    """
    (() => {
      const element = document.querySelector(#{encode_js(selector)});
      if (!element) return {ok: false, error: "element_not_found"};
      return {ok: true, value: element.getAttribute(#{encode_js(name)})};
    })()
    """
  end

  defp cookie_urls(opts) do
    Keyword.get_values(opts, :url) ++ List.wrap(Keyword.get(opts, :urls))
  end

  defp build_cookie_params(cdp, cookie, opts) when is_map(cookie) do
    params =
      cookie
      |> stringify_keys()
      |> Map.merge(stringify_keys(Map.new(opts)))

    if Map.has_key?(params, "url") or Map.has_key?(params, "domain") do
      {:ok, params}
    else
      with {:ok, url} <- eval_value(cdp, "window.location.href") do
        {:ok, Map.put(params, "url", url)}
      end
    end
  end

  defp build_cookie_params(_cdp, cookie, _opts), do: {:error, {:invalid_cookie, cookie}}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp encode_js(value), do: JSON.encode!(value)
end
