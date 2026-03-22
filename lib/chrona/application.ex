defmodule Chrona.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    pool_size = Application.get_env(:chrona, :pool_size, 2)
    chrome_path = Application.get_env(:chrona, :chrome_path)

    children = [
      {Chrona.BrowserPool, pool_size: pool_size, chrome_path: chrome_path}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Chrona.Supervisor)
  end
end
