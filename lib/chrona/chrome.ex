defmodule Chrona.Chrome do
  @moduledoc """
  A GenServer that manages a headless Chrome/Chromium instance.

  Each worker owns a single Chrome process and its CDP WebSocket URL.
  Screenshots are taken via `capture/3` which is a synchronous GenServer call.
  """

  use GenServer

  alias Chrona.CDP
  alias Chrona.Telemetry

  # Client API

  @doc """
  Starts a Chrome process that launches a headless Chrome instance.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Captures a screenshot of the given HTML content as a JPEG binary.
  """
  @spec capture(pid(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def capture(browser, html, opts) do
    metadata = %{
      width: Keyword.fetch!(opts, :width),
      height: Keyword.fetch!(opts, :height),
      quality: Keyword.fetch!(opts, :quality)
    }

    Telemetry.span(
      [:browser, :capture],
      metadata,
      fn ->
        GenServer.call(browser, {:capture, html, opts}, 30_000)
      end,
      &Telemetry.status_metadata/1
    )
  end

  @doc """
  Returns the browser worker's Chrome DevTools Protocol WebSocket URL.
  """
  @spec ws_url(pid()) :: {:ok, String.t()} | {:error, :browser_unavailable}
  def ws_url(browser) when is_pid(browser) do
    {:ok, :sys.get_state(browser).ws_url}
  catch
    :exit, _reason -> {:error, :browser_unavailable}
  end

  # GenServer Callbacks

  @impl GenServer
  def init(opts) do
    chrome_path = Keyword.get(opts, :chrome_path) || find_chrome()

    Telemetry.span(
      [:browser, :init],
      %{chrome_path: chrome_path},
      fn ->
        if is_nil(chrome_path) do
          {:stop, :chrome_not_found}
        else
          port = find_available_port()
          {:ok, user_data_dir} = Briefly.create(directory: true)

          args = [
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "--hide-scrollbars",
            "--remote-debugging-port=#{port}",
            "--user-data-dir=#{user_data_dir}",
            "about:blank"
          ]

          chrome_pid =
            spawn_link(fn ->
              MuonTrap.cmd(chrome_path, args, stderr_to_stdout: true)
            end)

          case wait_for_devtools(port) do
            {:ok, ws_url} ->
              {:ok, %{chrome_pid: chrome_pid, ws_url: ws_url}}

            {:error, reason} ->
              {:stop, reason}
          end
        end
      end,
      &Telemetry.status_metadata/1
    )
  end

  @impl GenServer
  def handle_call({:capture, html, opts}, _from, state) do
    width = Keyword.fetch!(opts, :width)
    height = Keyword.fetch!(opts, :height)
    quality = Keyword.fetch!(opts, :quality)

    {:ok, html_path} = Briefly.create(extname: ".html")
    File.write!(html_path, html)
    file_url = "file://#{html_path}"

    result = take_screenshot(state.ws_url, file_url, width, height, quality)
    {:reply, result, state}
  end

  @impl GenServer
  def terminate(_reason, %{chrome_pid: chrome_pid}) do
    Process.exit(chrome_pid, :kill)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # Private

  defp take_screenshot(ws_url, file_url, width, height, quality) do
    with {:ok, data} <-
           CDP.with_session(ws_url, fn cdp ->
             with :ok <- CDP.set_device_metrics(cdp, width, height),
                  :ok <- CDP.navigate(cdp, file_url) do
               CDP.capture_screenshot(cdp, "jpeg", quality)
             end
           end) do
      {:ok, Base.decode64!(data)}
    end
  end

  defp find_chrome do
    paths =
      case :os.type() do
        {:unix, :darwin} ->
          [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary"
          ]

        {:unix, _} ->
          [
            "google-chrome",
            "google-chrome-stable",
            "chromium",
            "chromium-browser"
          ]

        {:win32, _} ->
          [
            "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
            "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe"
          ]
      end

    Enum.find(paths, fn path ->
      case System.find_executable(path) do
        nil -> File.exists?(path)
        _ -> true
      end
    end)
  end

  defp find_available_port do
    {:ok, socket} = :gen_tcp.listen(0, reuseaddr: true)
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  defp wait_for_devtools(port, attempts \\ 100) do
    wait_for_devtools(port, attempts, 0)
  end

  defp wait_for_devtools(_port, max_attempts, attempt) when attempt >= max_attempts do
    {:error, :devtools_timeout}
  end

  defp wait_for_devtools(port, max_attempts, attempt) do
    url = ~c"http://127.0.0.1:#{port}/json/list"

    case :httpc.request(:get, {url, []}, [timeout: 1000], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        targets = JSON.decode!(to_string(body))

        case Enum.find(targets, &(&1["type"] == "page")) do
          %{"webSocketDebuggerUrl" => ws_url} -> {:ok, ws_url}
          _ -> retry_devtools(port, max_attempts, attempt)
        end

      _ ->
        retry_devtools(port, max_attempts, attempt)
    end
  end

  defp retry_devtools(port, max_attempts, attempt) do
    Process.sleep(100)
    wait_for_devtools(port, max_attempts, attempt + 1)
  end
end
