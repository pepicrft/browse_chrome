defmodule Chrona.CDPTest do
  use ExUnit.Case, async: true

  setup do
    pool = :"chrona_pool_#{System.unique_integer([:positive])}"
    start_supervised!({Chrona.BrowserPool, name: pool, pool_size: 1})
    {:ok, pool: pool}
  end

  describe "connect/1 and disconnect/1" do
    test "connects to and disconnects from a browser's CDP endpoint", %{pool: pool} do
      Chrona.checkout(pool, fn browser ->
        state = :sys.get_state(browser)
        ws_url = state.ws_url

        assert {:ok, cdp} = Chrona.CDP.connect(ws_url)
        assert is_pid(cdp)
        assert :ok = Chrona.CDP.disconnect(cdp)

        {:ok, :ok}
      end)
    end
  end

  describe "navigate/2" do
    @tag :tmp_dir
    test "navigates to a local HTML file", %{tmp_dir: tmp_dir, pool: pool} do
      html_path = Path.join(tmp_dir, "test.html")
      File.write!(html_path, "<html><body><h1>Test</h1></body></html>")

      Chrona.checkout(pool, fn browser ->
        state = :sys.get_state(browser)
        {:ok, cdp} = Chrona.CDP.connect(state.ws_url)

        assert :ok = Chrona.CDP.navigate(cdp, "file://#{html_path}")

        Chrona.CDP.disconnect(cdp)
        {:ok, :ok}
      end)
    end
  end

  describe "capture_screenshot/3" do
    @tag :tmp_dir
    test "captures a screenshot as base64 data", %{tmp_dir: tmp_dir, pool: pool} do
      html_path = Path.join(tmp_dir, "screenshot.html")
      File.write!(html_path, "<html><body style='background: red;'><h1>Screenshot</h1></body></html>")

      Chrona.checkout(pool, fn browser ->
        state = :sys.get_state(browser)
        {:ok, cdp} = Chrona.CDP.connect(state.ws_url)

        :ok = Chrona.CDP.set_device_metrics(cdp, 800, 600)
        :ok = Chrona.CDP.navigate(cdp, "file://#{html_path}")

        assert {:ok, base64_data} = Chrona.CDP.capture_screenshot(cdp, "jpeg", 80)
        assert is_binary(base64_data)

        jpeg_binary = Base.decode64!(base64_data)
        assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg_binary

        Chrona.CDP.disconnect(cdp)
        {:ok, :ok}
      end)
    end
  end
end
