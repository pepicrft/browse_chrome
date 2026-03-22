defmodule ChronaTest do
  use ExUnit.Case, async: true

  describe "checkout/2" do
    test "checks out a browser from the pool and runs the function" do
      result =
        Chrona.checkout(fn browser ->
          assert is_pid(browser)
          {:ok, :ok}
        end)

      assert result == :ok
    end

    test "captures a screenshot through checkout" do
      html = """
      <html>
        <body style="width: 1200px; height: 630px; background: #667eea;">
          <h1 style="color: white;">Hello, Chrona!</h1>
        </body>
      </html>
      """

      result =
        Chrona.checkout(fn browser ->
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
