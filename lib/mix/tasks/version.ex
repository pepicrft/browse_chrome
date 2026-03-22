defmodule Mix.Tasks.Version do
  @shortdoc "Manage the project version in mix.exs"
  @moduledoc """
  Manage the project version in mix.exs.

  ## Usage

      mix version current          # Print the current version
      mix version bump 1.2.3 minor # Bump the given version (prints 1.3.0)
      mix version set 2.0.0        # Update @version in mix.exs
  """

  use Mix.Task

  @version_marker ~s(@version ")

  @impl Mix.Task
  def run(["current"]) do
    mix_exs()
    |> current_version!()
    |> IO.puts()
  end

  def run(["bump", version, part]) do
    version
    |> Version.parse!()
    |> bump(part)
    |> to_string()
    |> IO.puts()
  end

  def run(["set", version]) do
    path = "mix.exs"
    contents = File.read!(path)
    current = current_version!(contents)

    if current == version do
      IO.puts(version)
    else
      updated = String.replace(contents, ~s(@version "#{current}"), ~s(@version "#{version}"), global: false)

      if contents == updated do
        Mix.raise("Unable to update #{path} to #{version}")
      end

      File.write!(path, updated)
      IO.puts(version)
    end
  end

  def run(_args) do
    Mix.raise("usage: mix version [current|bump <version> <major|minor|patch>|set <version>]")
  end

  defp mix_exs do
    File.read!("mix.exs")
  end

  defp current_version!(contents) do
    case extract_version(contents) do
      {:ok, version} -> version
      :error -> Mix.raise("Unable to find @version in mix.exs")
    end
  end

  defp extract_version(contents) do
    with [_, rest] <- String.split(contents, @version_marker, parts: 2),
         [version, _] <- String.split(rest, ~s("), parts: 2) do
      {:ok, version}
    else
      _ -> :error
    end
  end

  defp bump(version, "major"), do: %{version | major: version.major + 1, minor: 0, patch: 0}
  defp bump(version, "minor"), do: %{version | minor: version.minor + 1, patch: 0}
  defp bump(version, "patch"), do: %{version | patch: version.patch + 1}
  defp bump(_version, part), do: Mix.raise("Unknown bump type: #{part}")
end
