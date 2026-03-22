# 🌐 Chrona

[![Hex.pm](https://img.shields.io/hexpm/v/chrona.svg)](https://hex.pm/packages/chrona)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/chrona)
[![CI](https://github.com/pepicrft/chrona/actions/workflows/chrona.yml/badge.svg)](https://github.com/pepicrft/chrona/actions/workflows/chrona.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Manage headless Chrome instances via the Chrome DevTools Protocol.

Chrona provides a pool of warm headless Chrome/Chromium instances managed through a supervision tree, ready for use via the Chrome DevTools Protocol. It handles Chrome lifecycle and CDP WebSocket communication directly, and now delegates shared browser interface and pool runtime responsibilities to [`Browse`](https://hex.pm/packages/browse).

`Browse` is an internal implementation detail. Configure Chrona through `:chrona`; Chrona passes the relevant pool options down to `Browse` under the hood.

## 📦 Installation

Add `chrona` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:chrona, "~> 0.1.0"}
  ]
end
```

Chrona requires Chrome or Chromium to be installed on the system. It will auto-detect common installation paths, or you can configure it explicitly.

## 🚀 Usage

### Add a pool to your supervision tree

Configure pools through Chrona:

```elixir
config :chrona,
  default_pool: MyApp.ChromaPool,
  pools: [
    MyApp.ChromaPool: [pool_size: 4, chrome_path: "/usr/bin/chromium"]
  ]
```

Then add the configured pools to your supervision tree:

```elixir
# lib/my_app/application.ex
children = Chrona.children()
```

Or start a pool directly:

```elixir
# lib/my_app/application.ex
children = [
  {Chrona.BrowserPool,
   name: MyApp.ChromaPool,
   pool_size: 4,
   chrome_path: "/usr/bin/chromium"}
]
```

Chrona does not start a pool for you. The consumer owns pool supervision and decides how many pools to run, how they are named, and where they live in the supervision tree. `Chrona.BrowserPool` remains the Chrona-facing compatibility wrapper, backed internally by `Browse`, but its configuration now lives under `:chrona`.

### Check out a browser from a pool

```elixir
Chrona.checkout(MyApp.ChromaPool, fn browser ->
  # Use Chrona.CDP to interact with the browser
  result =
    Chrona.CDP.with_session(browser.ws_url, fn cdp ->
      :ok = Chrona.CDP.navigate(cdp, "https://example.com")
      {:ok, screenshot_data} = Chrona.CDP.capture_screenshot(cdp, "jpeg", 90)
      {:ok, Base.decode64!(screenshot_data)}
    end)

  {result, :ok}
end)
```

`Chrona.CDP.with_session/2` is the recommended API. It guarantees the WebSocket is disconnected even if your callback raises or returns early.

If you configured `default_pool`, you can omit the pool name:

```elixir
Chrona.checkout(fn browser ->
  {:ok, browser}
end)
```

### Direct browser management

```elixir
{:ok, browser} = Chrona.Chrome.start_link()

{:ok, jpeg_binary} = Chrona.Chrome.capture(browser, "<h1>Hello!</h1>", width: 1200, height: 630, quality: 90)
```

### Modules

- `Chrona.Chrome` - GenServer managing a single headless Chrome instance
- `Chrona.CDP` - WebSocket client for the Chrome DevTools Protocol
- `Chrona.Browser` - `Browse.Browser` adapter built on Chrona's Chrome worker
- `Chrona.BrowserPool` - Chrona-facing pool wrapper backed by `Browse`

### Use the full CDP surface

The convenience helpers cover common tasks like navigation, viewport setup, and screenshots, but Chrome exposes many more methods than those wrappers.

Use `Chrona.CDP.command/3` to call any CDP method directly:

```elixir
Chrona.checkout(MyApp.ChromaPool, fn browser ->
  result =
    Chrona.CDP.with_session(browser.ws_url, fn cdp ->
      {:ok, version} = Chrona.CDP.command(cdp, "Browser.getVersion")
      {:ok, version}
    end)

  {result, :ok}
end)
```

## ⚙️ Setup

Add `Chrona.BrowserPool` to your application's supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  {Chrona.BrowserPool,
   name: MyApp.ChromaPool,
   pool_size: 4,
   chrome_path: "/usr/bin/chromium"}
]
```

Options:
- `:name` - pool name used when checking out browsers
- `:pool_size` - number of warm Chrome instances (default: `2`)
- `:chrome_path` - path to Chrome/Chromium binary (auto-detected if omitted)

The `:chrona, :pools` entries accept the same pool options Chrona passes down to `Browse`, while keeping the `Browse` implementation module internal.

Then pass the pool name or pid to `Chrona.checkout/3`, or use `Chrona.checkout/1` with `:default_pool` configured:

```elixir
Chrona.checkout(MyApp.ChromaPool, fn browser ->
  {:ok, :done}
end)
```

## 📡 Telemetry

Chrona emits [Telemetry](https://hexdocs.pm/telemetry) events for its main lifecycle operations:

- `[:chrona, :checkout, :start | :stop | :exception]`
- `[:chrona, :browser, :init, :start | :stop | :exception]`
- `[:chrona, :browser, :capture, :start | :stop | :exception]`
- `[:chrona, :cdp, :connect, :start | :stop | :exception]`
- `[:chrona, :cdp, :disconnect, :start | :stop | :exception]`
- `[:chrona, :cdp, :command, :start | :stop | :exception]`

Stop and exception events include a `:duration` measurement in native time units. CDP command events include the `:method` metadata field, and browser capture events include `:width`, `:height`, and `:quality`.

```elixir
:telemetry.attach_many(
  "chrona-logger",
  [
    [:chrona, :checkout, :stop],
    [:chrona, :browser, :capture, :stop],
    [:chrona, :cdp, :command, :stop]
  ],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "chrona.telemetry")
  end,
  nil
)
```

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
