defmodule BrowseChrome.BrowserTest do
  use ExUnit.Case, async: false

  setup do
    pool = :"browse_pool_#{System.unique_integer([:positive])}"

    start_supervised!(Browse.child_spec(pool, implementation: BrowseChrome.Browser, pool_size: 1))

    {:ok, pool: pool}
  end

  @tag :tmp_dir
  test "supports the Browse 0.3.0 browser actions end to end", %{pool: pool, tmp_dir: tmp_dir} do
    first_page = Path.join(tmp_dir, "page-1.html")
    second_page = Path.join(tmp_dir, "page-2.html")

    File.write!(first_page, first_page_html())
    File.write!(second_page, second_page_html())

    first_url = "file://#{first_page}"
    second_url = "file://#{second_page}"

    Browse.checkout(pool, fn browser ->
      assert :ok = Browse.navigate(browser, first_url)
      assert {:ok, ^first_url} = Browse.current_url(browser)
      assert {:ok, "Page One"} = Browse.title(browser)
      assert :ok = Browse.wait_for(browser, "#delayed", timeout: 5_000)
      assert {:ok, "ready"} = Browse.get_text(browser, "#delayed")

      assert :ok = Browse.fill(browser, "#name", "Alice")
      assert {:ok, "person-name"} = Browse.get_attribute(browser, "#name", "data-kind")
      assert {:ok, "Alice"} = Browse.get_text(browser, "#mirror")

      assert :ok = Browse.select_option(browser, "#choice", "beta")
      assert {:ok, "choice"} = Browse.get_attribute(browser, "#choice", "id")
      assert {:ok, "beta"} = Browse.get_text(browser, "#choice-status")

      assert :ok = Browse.hover(browser, "#hover-target")
      assert {:ok, "hovered"} = Browse.get_text(browser, "#hover-status")

      assert :ok = Browse.click(browser, "#action")
      assert {:ok, "clicked"} = Browse.get_text(browser, "#click-status")

      assert {:ok, html} = Browse.content(browser)
      assert html =~ "Page One"

      assert {:ok, %{"title" => "Page One", "value" => "Alice"}} =
               Browse.evaluate(
                 browser,
                 ~s|({title: document.title, value: document.querySelector("#name").value})|
               )

      assert {:ok, pdf} = Browse.print_to_pdf(browser)
      assert String.starts_with?(pdf, "%PDF-")

      assert :ok = Browse.navigate(browser, second_url)
      assert {:ok, "Page Two"} = Browse.title(browser)

      assert :ok = Browse.go_back(browser)
      assert {:ok, "Page One"} = Browse.title(browser)

      assert :ok = Browse.go_forward(browser)
      assert {:ok, "Page Two"} = Browse.title(browser)

      assert :ok = Browse.reload(browser)
      assert {:ok, "Page Two"} = Browse.title(browser)

      {:ok, :ok}
    end)
  end

  test "manages cookies", %{pool: pool} do
    Browse.checkout(pool, fn browser ->
      cookie = %{"name" => "session", "value" => "abc123"}

      assert :ok = Browse.set_cookie(browser, cookie, url: "https://example.com")

      assert {:ok, cookies} = Browse.get_cookies(browser, url: "https://example.com")
      assert Enum.any?(cookies, &(&1["name"] == "session" and &1["value"] == "abc123"))

      assert :ok = Browse.clear_cookies(browser)

      assert {:ok, cleared_cookies} = Browse.get_cookies(browser, url: "https://example.com")
      refute Enum.any?(cleared_cookies, &(&1["name"] == "session"))

      {:ok, :ok}
    end)
  end

  defp first_page_html do
    """
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Page One</title>
      </head>
      <body>
        <button id="action" onclick="document.querySelector('#click-status').textContent = 'clicked'">
          Click me
        </button>
        <input
          id="name"
          type="text"
          data-kind="person-name"
          value=""
          oninput="document.querySelector('#mirror').textContent = this.value"
        />
        <select
          id="choice"
          onchange="document.querySelector('#choice-status').textContent = this.value"
        >
          <option value="">Pick one</option>
          <option value="alpha">Alpha</option>
          <option value="beta">Beta</option>
        </select>
        <div
          id="hover-target"
          onmouseover="document.querySelector('#hover-status').textContent = 'hovered'"
          style="width: 120px; height: 40px; background: #ddd;"
        >
          Hover target
        </div>
        <div id="mirror"></div>
        <div id="choice-status"></div>
        <div id="hover-status"></div>
        <div id="click-status"></div>
        <div id="delayed" style="display: none;"></div>
        <script>
          setTimeout(() => {
            const element = document.querySelector("#delayed");
            element.style.display = "block";
            element.textContent = "ready";
          }, 250);
        </script>
      </body>
    </html>
    """
  end

  defp second_page_html do
    """
    <html>
      <head>
        <meta charset="utf-8" />
        <title>Page Two</title>
      </head>
      <body>
        <h1>Second Page</h1>
      </body>
    </html>
    """
  end
end
