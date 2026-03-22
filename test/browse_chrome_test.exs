defmodule BrowseChromeTest do
  use ExUnit.Case, async: false

  setup do
    original_default_pool = Application.get_env(:browse_chrome, :default_pool)
    original_pools = Application.get_env(:browse_chrome, :pools)

    pool = :"browse_chrome_pool_#{System.unique_integer([:positive])}"
    start_supervised!({BrowseChrome.BrowserPool, name: pool, pool_size: 1})

    on_exit(fn ->
      if original_default_pool == nil do
        Application.delete_env(:browse_chrome, :default_pool)
      else
        Application.put_env(:browse_chrome, :default_pool, original_default_pool)
      end

      if original_pools == nil do
        Application.delete_env(:browse_chrome, :pools)
      else
        Application.put_env(:browse_chrome, :pools, original_pools)
      end
    end)

    {:ok, pool: pool}
  end

  test "children builds child specs from BrowseChrome configuration" do
    pool = :"browse_chrome_pool_#{System.unique_integer([:positive])}"

    Application.put_env(:browse_chrome, :pools, [{pool, [pool_size: 1]}])

    assert [%{id: ^pool, start: {Browse, :start_link, [^pool, opts]}}] = BrowseChrome.children()
    assert Keyword.fetch!(opts, :pool_size) == 1
    assert Keyword.fetch!(opts, :implementation) == BrowseChrome.Browser
  end

  test "checkout uses the configured default pool" do
    pool = :"browse_chrome_pool_#{System.unique_integer([:positive])}"
    start_supervised!({BrowseChrome.BrowserPool, name: pool, pool_size: 1})

    Application.put_env(:browse_chrome, :default_pool, pool)

    result =
      BrowseChrome.checkout(fn browser ->
        assert is_pid(browser)
        {:ok, :ok}
      end)

    assert result == :ok
  end

  describe "checkout/3" do
    test "checks out a browser from the pool and runs the function", %{pool: pool} do
      result =
        BrowseChrome.checkout(pool, fn browser ->
          assert is_pid(browser)
          {:ok, :ok}
        end)

      assert result == :ok
    end

    test "captures a screenshot through checkout", %{pool: pool} do
      html = """
      <html>
        <body style="width: 1200px; height: 630px; background: #667eea;">
          <h1 style="color: white;">Hello, BrowseChrome!</h1>
        </body>
      </html>
      """

      result =
        BrowseChrome.checkout(pool, fn browser ->
          case BrowseChrome.Chrome.capture(browser, html, width: 1200, height: 630, quality: 90) do
            {:ok, _} = ok -> {ok, :ok}
            {:error, _} = error -> {error, :remove}
          end
        end)

      assert {:ok, jpeg_binary} = result
      assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg_binary
    end
  end
end
