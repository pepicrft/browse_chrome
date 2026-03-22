defmodule Chrona.CDP do
  @moduledoc """
  A minimal Chrome DevTools Protocol client over WebSocket.

  Provides a safe session API and a generic command interface for
  interacting with the Chrome DevTools Protocol.
  """

  use WebSockex

  alias Chrona.Telemetry

  defstruct [:ws_pid, id: 1, pending: %{}]

  @doc """
  Connects to a Chrome DevTools Protocol WebSocket endpoint.
  """
  @spec connect(String.t()) :: {:ok, pid()} | {:error, term()}
  def connect(ws_url) do
    Telemetry.span(
      [:cdp, :connect],
      %{},
      fn ->
        case WebSockex.start_link(ws_url, __MODULE__, %{pending: %{}}) do
          {:ok, pid} -> {:ok, pid}
          {:error, _} = error -> error
        end
      end,
      &Telemetry.status_metadata/1
    )
  end

  @doc """
  Opens a CDP session, runs the given function, and always disconnects afterward.

  Returns the callback result on success, or `{:error, reason}` if the connection
  could not be established.
  """
  @spec with_session(String.t(), (pid() -> result)) :: result | {:error, term()} when result: var
  def with_session(ws_url, fun) when is_function(fun, 1) do
    case connect(ws_url) do
      {:ok, pid} ->
        try do
          fun.(pid)
        after
          disconnect(pid)
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Disconnects from the CDP WebSocket.
  """
  @spec disconnect(pid()) :: :ok
  def disconnect(pid) do
    Telemetry.span(
      [:cdp, :disconnect],
      %{},
      fn ->
        WebSockex.cast(pid, :disconnect)
        :ok
      end,
      &Telemetry.status_metadata/1
    )
  end

  @doc """
  Sends an arbitrary Chrome DevTools Protocol command.

  Returns `{:ok, result}` with the raw CDP response payload.
  """
  @spec command(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def command(pid, method, params \\ %{}) when is_binary(method) and is_map(params) do
    request(pid, method, params)
  end

  @doc """
  Sets the device metrics (viewport size) for the page.
  """
  @spec set_device_metrics(pid(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def set_device_metrics(pid, width, height) do
    command(pid, "Emulation.setDeviceMetricsOverride", %{
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
    case command(pid, "Page.enable", %{}) do
      {:ok, _} -> :ok
      error -> error
    end

    case command(pid, "Page.navigate", %{url: url}) do
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

    case command(pid, "Page.captureScreenshot", params) do
      {:ok, %{"data" => data}} -> {:ok, data}
      error -> error
    end
  end

  defp wait_for_load(pid) do
    # Give the page time to render
    Process.sleep(500)

    case command(pid, "Runtime.evaluate", %{expression: "document.readyState"}) do
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

  defp request(pid, method, params) do
    Telemetry.span(
      [:cdp, :command],
      %{method: method},
      fn ->
        ref = make_ref()
        WebSockex.cast(pid, {:send_command, method, params, self(), ref})

        receive do
          {:cdp_response, ^ref, result} -> {:ok, result}
        after
          10_000 -> {:error, :cdp_timeout}
        end
      end,
      &Telemetry.status_metadata/1
    )
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
