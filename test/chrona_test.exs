defmodule ChronaTest do
  use ExUnit.Case, async: false

  setup do
    original_default_pool = Application.get_env(:chrona, :default_pool)
    original_pools = Application.get_env(:chrona, :pools)

    pool = :"chrona_pool_#{System.unique_integer([:positive])}"
    start_supervised!({Chrona.BrowserPool, name: pool, pool_size: 1})

    on_exit(fn ->
      if original_default_pool == nil do
        Application.delete_env(:chrona, :default_pool)
      else
        Application.put_env(:chrona, :default_pool, original_default_pool)
      end

      if original_pools == nil do
        Application.delete_env(:chrona, :pools)
      else
        Application.put_env(:chrona, :pools, original_pools)
      end
    end)

    {:ok, pool: pool}
  end

  test "children builds child specs from Chrona configuration" do
    pool = :"chrona_pool_#{System.unique_integer([:positive])}"

    Application.put_env(:chrona, :pools, [{pool, [pool_size: 1]}])

    assert [%{id: ^pool, start: {Browse, :start_link, [^pool, opts]}}] = Chrona.children()
    assert Keyword.fetch!(opts, :pool_size) == 1
    assert Keyword.fetch!(opts, :implementation) == Chrona.Browser
  end

  test "checkout uses the configured default pool" do
    pool = :"chrona_pool_#{System.unique_integer([:positive])}"
    start_supervised!({Chrona.BrowserPool, name: pool, pool_size: 1})

    Application.put_env(:chrona, :default_pool, pool)

    result =
      Chrona.checkout(fn browser ->
        assert is_pid(browser)
        {:ok, :ok}
      end)

    assert result == :ok
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
          case Chrona.Chrome.capture(browser, html, width: 1200, height: 630, quality: 90) do
            {:ok, _} = ok -> {ok, :ok}
            {:error, _} = error -> {error, :remove}
          end
        end)

      assert {:ok, jpeg_binary} = result
      assert <<0xFF, 0xD8, 0xFF, _rest::binary>> = jpeg_binary
    end
  end
end
