# browse_chrome

[![Hex.pm](https://img.shields.io/hexpm/v/browse_chrome.svg)](https://hex.pm/packages/browse_chrome)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/browse_chrome)
[![CI](https://github.com/pepicrft/browse_chrome/actions/workflows/chrona.yml/badge.svg)](https://github.com/pepicrft/browse_chrome/actions/workflows/chrona.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Manage headless Chrome instances via the Chrome DevTools Protocol.

BrowseChrome provides a pool of warm headless Chrome/Chromium instances managed through a supervision tree, ready for use via the Chrome DevTools Protocol. It handles Chrome lifecycle and CDP WebSocket communication directly, and now delegates shared browser interface and pool runtime responsibilities to [`Browse`](https://hex.pm/packages/browse).

`Browse` is an internal implementation detail. Configure BrowseChrome through `:browse_chrome`; BrowseChrome passes the relevant pool options down to `Browse` under the hood.

## 📦 Installation

Add `browse_chrome` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:browse_chrome, "~> 0.1.0"}
  ]
end
```

BrowseChrome requires Chrome or Chromium to be installed on the system. It will auto-detect common installation paths, or you can configure it explicitly.

## 🚀 Usage

### Add a pool to your supervision tree

Configure pools through BrowseChrome:

```elixir
config :browse_chrome,
  default_pool: MyApp.BrowseChromePool,
  pools: [
    MyApp.BrowseChromePool: [pool_size: 4, chrome_path: "/usr/bin/chromium"]
  ]
```

Then add the configured pools to your supervision tree:

```elixir
# lib/my_app/application.ex
children = BrowseChrome.children()
```

Or start a pool directly:

```elixir
# lib/my_app/application.ex
children = [
  {BrowseChrome.BrowserPool,
   name: MyApp.BrowseChromePool,
   pool_size: 4,
   chrome_path: "/usr/bin/chromium"}
]
```

BrowseChrome does not start a pool for you. The consumer owns pool supervision and decides how many pools to run, how they are named, and where they live in the supervision tree. `BrowseChrome.BrowserPool` remains the BrowseChrome-facing compatibility wrapper, backed internally by `Browse`, but its configuration now lives under `:browse_chrome`.

### Check out a browser from a pool

```elixir
BrowseChrome.checkout(MyApp.BrowseChromePool, fn browser ->
  # Use BrowseChrome.CDP to interact with the browser
  result =
    with {:ok, ws_url} <- BrowseChrome.Chrome.ws_url(browser) do
      BrowseChrome.CDP.with_session(ws_url, fn cdp ->
        :ok = BrowseChrome.CDP.navigate(cdp, "https://example.com")
        {:ok, screenshot_data} = BrowseChrome.CDP.capture_screenshot(cdp, "jpeg", 90)
        {:ok, Base.decode64!(screenshot_data)}
      end)
    end

  {result, :ok}
end)
```

`BrowseChrome.CDP.with_session/2` is the recommended API. It guarantees the WebSocket is disconnected even if your callback raises or returns early.

If you configured `default_pool`, you can omit the pool name:

```elixir
BrowseChrome.checkout(fn browser ->
  {:ok, browser}
end)
```

### Direct browser management

```elixir
{:ok, browser} = BrowseChrome.Chrome.start_link()

{:ok, jpeg_binary} = BrowseChrome.Chrome.capture(browser, "<h1>Hello!</h1>", width: 1200, height: 630, quality: 90)
```

### Modules

- `BrowseChrome.Chrome` - GenServer managing a single headless Chrome instance
- `BrowseChrome.CDP` - WebSocket client for the Chrome DevTools Protocol
- `BrowseChrome.Browser` - `Browse.Browser` adapter built on BrowseChrome's Chrome worker
- `BrowseChrome.BrowserPool` - BrowseChrome-facing pool wrapper backed by `Browse`

### Use the full CDP surface

The convenience helpers cover common tasks like navigation, viewport setup, and screenshots, but Chrome exposes many more methods than those wrappers.

Use `BrowseChrome.CDP.command/3` to call any CDP method directly:

```elixir
BrowseChrome.checkout(MyApp.BrowseChromePool, fn browser ->
  result =
    with {:ok, ws_url} <- BrowseChrome.Chrome.ws_url(browser) do
      BrowseChrome.CDP.with_session(ws_url, fn cdp ->
        {:ok, version} = BrowseChrome.CDP.command(cdp, "Browser.getVersion")
        {:ok, version}
      end)
    end

  {result, :ok}
end)
```

## ⚙️ Setup

Add `BrowseChrome.BrowserPool` to your application's supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  {BrowseChrome.BrowserPool,
   name: MyApp.BrowseChromePool,
   pool_size: 4,
   chrome_path: "/usr/bin/chromium"}
]
```

Options:
- `:name` - pool name used when checking out browsers
- `:pool_size` - number of warm Chrome instances (default: `2`)
- `:chrome_path` - path to Chrome/Chromium binary (auto-detected if omitted)

The `:browse_chrome, :pools` entries accept the same pool options BrowseChrome passes down to `Browse`, while keeping the `Browse` implementation module internal.

Then pass the pool name or pid to `BrowseChrome.checkout/3`, or use `BrowseChrome.checkout/1` with `:default_pool` configured:

```elixir
BrowseChrome.checkout(MyApp.BrowseChromePool, fn browser ->
  {:ok, :done}
end)
```

## 📡 Telemetry

`Browse` emits [Telemetry](https://hexdocs.pm/telemetry) for pool lifecycle operations such as pool start, checkout, and worker lifecycle.

BrowseChrome emits Telemetry for Chrome-specific operations layered on top:

- `[:browse_chrome, :browser, :init, :start | :stop | :exception]`
- `[:browse_chrome, :browser, :capture, :start | :stop | :exception]`
- `[:browse_chrome, :cdp, :connect, :start | :stop | :exception]`
- `[:browse_chrome, :cdp, :disconnect, :start | :stop | :exception]`
- `[:browse_chrome, :cdp, :command, :start | :stop | :exception]`

Stop and exception events include a `:duration` measurement in native time units. CDP command events include the `:method` metadata field, and browser capture events include `:width`, `:height`, and `:quality`.

```elixir
:telemetry.attach_many(
  "browse_chrome-logger",
  [
    [:browse, :checkout, :stop],
    [:browse_chrome, :browser, :capture, :stop],
    [:browse_chrome, :cdp, :command, :stop]
  ],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "browse_chrome.telemetry")
  end,
  nil
)
```

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
