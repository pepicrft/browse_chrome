defmodule ChronaTest do
  use ExUnit.Case, async: true

  setup do
    pool = :"chrona_pool_#{System.unique_integer([:positive])}"
    start_supervised!({Chrona.BrowserPool, name: pool, pool_size: 1})
    {:ok, pool: pool}
  end

  describe "checkout/3" do
    test "checks out a browser from the pool and runs the function", %{pool: pool} do
      result =
        Chrona.checkout(pool, fn browser ->
          assert is_pid(browser)
          {:ok, :ok}
        end)

      assert result == :ok
    end

    test "captures a screenshot through checkout", %{pool: pool} do
      html = """
      <html>
        <body style="width: 1200px; height: 630px; background: #667eea;">
          <h1 style="color: white;">Hello, Chrona!</h1>
        </body>
      </html>
      """

      result =
        Chrona.checkout(pool, fn browser ->
          case Chrona.Browser.capture(browser, html, width: 1200, height: 630, quality: 90) do
            {:ok, _} = ok -> {ok, :ok}
            {:error, _} = error -> {error, :remove}
          end
        end)

      assert {:ok, jpeg_binary} = result
      assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg_binary
    end
  end
end
