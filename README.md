# 🌐 Chrona

[![Hex.pm](https://img.shields.io/hexpm/v/chrona.svg)](https://hex.pm/packages/chrona)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/chrona)
[![CI](https://github.com/pepicrft/chrona/actions/workflows/chrona.yml/badge.svg)](https://github.com/pepicrft/chrona/actions/workflows/chrona.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Manage headless Chrome instances via the Chrome DevTools Protocol.

Chrona provides a pool of warm headless Chrome/Chromium instances managed through a supervision tree, ready for use via the Chrome DevTools Protocol. It handles browser lifecycle, CDP WebSocket communication, and pool management so you can focus on what you want to do with the browser.

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

### Check out a browser from the pool

```elixir
Chrona.checkout(fn browser ->
  # Use Chrona.CDP to interact with the browser
  {:ok, cdp} = Chrona.CDP.connect(browser.ws_url)
  :ok = Chrona.CDP.navigate(cdp, "https://example.com")
  {:ok, screenshot_data} = Chrona.CDP.capture_screenshot(cdp, "jpeg", 90)
  Chrona.CDP.disconnect(cdp)

  {{:ok, Base.decode64!(screenshot_data)}, :ok}
end)
```

### Direct browser management

```elixir
# Start a standalone browser instance
{:ok, browser} = Chrona.Browser.start_link()

# Capture a screenshot
{:ok, jpeg_binary} = Chrona.Browser.capture(browser, "<h1>Hello!</h1>", width: 1200, height: 630, quality: 90)
```

### Modules

- `Chrona.Browser` - GenServer managing a single headless Chrome instance
- `Chrona.CDP` - WebSocket client for the Chrome DevTools Protocol
- `Chrona.BrowserPool` - NimblePool for warm Chrome instances

## ⚙️ Setup

Add `Chrona.BrowserPool` to your application's supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  {Chrona.BrowserPool, pool_size: 4, chrome_path: "/usr/bin/chromium"}
]
```

Options:
- `:pool_size` - number of warm Chrome instances (default: `2`)
- `:chrome_path` - path to Chrome/Chromium binary (auto-detected if omitted)

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
