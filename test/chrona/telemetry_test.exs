defmodule Chrona.TelemetryTest do
  use ExUnit.Case, async: false

  setup do
    pool = :"chrona_pool_#{System.unique_integer([:positive])}"
    start_supervised!({Chrona.BrowserPool, name: pool, pool_size: 1})
    handler_id = "chrona-test-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:chrona, :checkout, :start],
        [:chrona, :checkout, :stop],
        [:chrona, :browser, :capture, :start],
        [:chrona, :browser, :capture, :stop],
        [:chrona, :cdp, :command, :start],
        [:chrona, :cdp, :command, :stop]
      ],
      &__MODULE__.handle_event/4,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    {:ok, pool: pool}
  end

  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  test "checkout emits telemetry events", %{pool: pool} do
    assert :ok =
             Chrona.checkout(pool, fn browser ->
               assert is_pid(browser)
               {:ok, :ok}
             end)

    assert_receive {:telemetry_event, [:chrona, :checkout, :start], %{system_time: system_time},
                    %{pool: ^pool, timeout: 30_000}},
                   1_000

    assert is_integer(system_time)

    assert_receive {:telemetry_event, [:chrona, :checkout, :stop], %{duration: duration},
                    %{pool: ^pool, timeout: 30_000}},
                   1_000

    assert is_integer(duration)
    assert duration > 0
  end

  test "browser capture and cdp command emit telemetry events", %{pool: pool} do
    html = "<html><body><h1>Hello telemetry</h1></body></html>"

    assert {:ok, jpeg_binary} =
             Chrona.checkout(pool, fn browser ->
               result = Chrona.Chrome.capture(browser, html, width: 800, height: 600, quality: 85)
               {result, :ok}
             end)

    assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg_binary

    assert_receive {:telemetry_event, [:chrona, :browser, :capture, :start], %{system_time: _},
                    %{width: 800, height: 600, quality: 85}},
                   1_000

    assert_receive {:telemetry_event, [:chrona, :cdp, :command, :start], %{system_time: _},
                    %{method: "Emulation.setDeviceMetricsOverride"}},
                   1_000

    assert_receive {:telemetry_event, [:chrona, :cdp, :command, :stop], %{duration: duration},
                    %{method: "Emulation.setDeviceMetricsOverride", status: :ok}},
                   1_000

    assert is_integer(duration)
    assert duration > 0

    assert_receive {:telemetry_event, [:chrona, :browser, :capture, :stop], %{duration: capture_duration},
                    %{width: 800, height: 600, quality: 85, status: :ok}},
                   1_000

    assert is_integer(capture_duration)
    assert capture_duration > 0
  end
end
