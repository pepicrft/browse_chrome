defmodule Chrona.CDPTest do
  use ExUnit.Case, async: true

  setup do
    pool = :"chrona_pool_#{System.unique_integer([:positive])}"
    start_supervised!({Chrona.BrowserPool, name: pool, pool_size: 1})
    {:ok, pool: pool}
  end

  describe "with_session/2" do
    test "disconnects automatically after the callback returns", %{pool: pool} do
      result =
        Chrona.checkout(pool, fn browser ->
          result =
            with {:ok, ws_url} <- Chrona.Chrome.ws_url(browser) do
              Chrona.CDP.with_session(ws_url, fn cdp ->
                assert is_pid(cdp)
                {:ok, cdp}
              end)
            end

          {result, :ok}
        end)

      assert {:ok, cdp_pid} = result
      monitor_ref = Process.monitor(cdp_pid)
      assert_receive {:DOWN, ^monitor_ref, :process, ^cdp_pid, _reason}, 1_000
    end

    test "disconnects automatically when the callback raises", %{pool: pool} do
      assert_raise RuntimeError, "boom", fn ->
        Chrona.checkout(pool, fn browser ->
          with {:ok, ws_url} <- Chrona.Chrome.ws_url(browser) do
            Chrona.CDP.with_session(ws_url, fn cdp ->
              send(self(), {:cdp_pid, cdp})
              raise "boom"
            end)
          end
        end)
      end

      assert_receive {:cdp_pid, cdp_pid}, 1_000
      monitor_ref = Process.monitor(cdp_pid)
      assert_receive {:DOWN, ^monitor_ref, :process, ^cdp_pid, _reason}, 1_000
    end
  end

  describe "connect/1 and disconnect/1" do
    test "connects to and disconnects from a browser's CDP endpoint", %{pool: pool} do
      Chrona.checkout(pool, fn browser ->
        assert {:ok, ws_url} = Chrona.Chrome.ws_url(browser)
        assert {:ok, cdp} = Chrona.CDP.connect(ws_url)
        assert is_pid(cdp)
        assert :ok = Chrona.CDP.disconnect(cdp)

        {:ok, :ok}
      end)
    end
  end

  describe "command/3" do
    test "sends arbitrary CDP methods", %{pool: pool} do
      Chrona.checkout(pool, fn browser ->
        assert {:ok, %{"product" => product}} =
                 (with {:ok, ws_url} <- Chrona.Chrome.ws_url(browser) do
                    Chrona.CDP.with_session(ws_url, fn cdp ->
                      Chrona.CDP.command(cdp, "Browser.getVersion")
                    end)
                  end)

        assert String.starts_with?(product, "Chrome/")
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
        assert :ok =
                 (with {:ok, ws_url} <- Chrona.Chrome.ws_url(browser) do
                    Chrona.CDP.with_session(ws_url, fn cdp ->
                      Chrona.CDP.navigate(cdp, "file://#{html_path}")
                    end)
                  end)

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
        assert {:ok, base64_data} =
                 (with {:ok, ws_url} <- Chrona.Chrome.ws_url(browser) do
                    Chrona.CDP.with_session(ws_url, fn cdp ->
                      :ok = Chrona.CDP.set_device_metrics(cdp, 800, 600)
                      :ok = Chrona.CDP.navigate(cdp, "file://#{html_path}")
                      Chrona.CDP.capture_screenshot(cdp, "jpeg", 80)
                    end)
                  end)

        assert is_binary(base64_data)

        jpeg_binary = Base.decode64!(base64_data)
        assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg_binary
        {:ok, :ok}
      end)
    end
  end
end
