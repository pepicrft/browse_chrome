defmodule Chrona.CDP do
  @moduledoc """
  A minimal Chrome DevTools Protocol client over WebSocket.

  Provides just enough CDP functionality to navigate to a page,
  set viewport dimensions, and capture screenshots.
  """

  use WebSockex

  defstruct [:ws_pid, id: 1, pending: %{}]

  @doc """
  Connects to a Chrome DevTools Protocol WebSocket endpoint.
  """
  @spec connect(String.t()) :: {:ok, pid()} | {:error, term()}
  def connect(ws_url) do
    case WebSockex.start_link(ws_url, __MODULE__, %{pending: %{}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, _} = error -> error
    end
  end

  @doc """
  Disconnects from the CDP WebSocket.
  """
  @spec disconnect(pid()) :: :ok
  def disconnect(pid) do
    WebSockex.cast(pid, :disconnect)
    :ok
  end

  @doc """
  Sets the device metrics (viewport size) for the page.
  """
  @spec set_device_metrics(pid(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def set_device_metrics(pid, width, height) do
    send_command(pid, "Emulation.setDeviceMetricsOverride", %{
      width: width,
      height: height,
      deviceScaleFactor: 2,
      mobile: false
    })
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Navigates to the given URL and waits for the page to load.
  """
  @spec navigate(pid(), String.t()) :: :ok | {:error, term()}
  def navigate(pid, url) do
    case send_command(pid, "Page.enable", %{}) do
      {:ok, _} -> :ok
      error -> error
    end

    case send_command(pid, "Page.navigate", %{url: url}) do
      {:ok, _} -> wait_for_load(pid)
      error -> error
    end
  end

  @doc """
  Captures a screenshot of the current page.

  Returns `{:ok, base64_data}` with the base64-encoded image data.
  """
  @spec capture_screenshot(pid(), String.t(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def capture_screenshot(pid, format, quality) do
    params = %{format: format, quality: quality, fromSurface: true}

    case send_command(pid, "Page.captureScreenshot", params) do
      {:ok, %{"data" => data}} -> {:ok, data}
      error -> error
    end
  end

  defp wait_for_load(pid) do
    # Give the page time to render
    Process.sleep(500)

    case send_command(pid, "Runtime.evaluate", %{expression: "document.readyState"}) do
      {:ok, %{"result" => %{"value" => "complete"}}} ->
        # Extra time for any async rendering
        Process.sleep(200)
        :ok

      {:ok, _} ->
        Process.sleep(200)
        wait_for_load(pid)

      error ->
        error
    end
  end

  defp send_command(pid, method, params) do
    ref = make_ref()
    WebSockex.cast(pid, {:send_command, method, params, self(), ref})

    receive do
      {:cdp_response, ^ref, result} -> {:ok, result}
    after
      10_000 -> {:error, :cdp_timeout}
    end
  end

  # WebSockex Callbacks

  @impl WebSockex
  def handle_cast(:disconnect, state) do
    {:close, state}
  end

  @impl WebSockex
  def handle_cast({:send_command, method, params, caller, ref}, state) do
    id = Map.get(state, :next_id, 1)

    message =
      JSON.encode!(%{
        id: id,
        method: method,
        params: params
      })

    new_state =
      state
      |> Map.put(:next_id, id + 1)
      |> Map.update(:pending, %{}, &Map.put(&1, id, {caller, ref}))

    {:reply, {:text, message}, new_state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case JSON.decode(msg) do
      {:ok, %{"id" => id, "result" => result}} ->
        case Map.get(state.pending, id) do
          {caller, ref} ->
            send(caller, {:cdp_response, ref, result})
            {:ok, Map.update!(state, :pending, &Map.delete(&1, id))}

          nil ->
            {:ok, state}
        end

      {:ok, %{"id" => id, "error" => error}} ->
        case Map.get(state.pending, id) do
          {caller, ref} ->
            send(caller, {:cdp_response, ref, {:error, error}})
            {:ok, Map.update!(state, :pending, &Map.delete(&1, id))}

          nil ->
            {:ok, state}
        end

      _ ->
        # Ignore events
        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_disconnect(_connection_status, state) do
    {:ok, state}
  end
end
