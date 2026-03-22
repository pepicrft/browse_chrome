defmodule BrowseChrome.Telemetry do
  @moduledoc false

  @prefix [:browse_chrome]

  def span(event, metadata, fun, stop_metadata_fun \\ fn _result -> %{} end)
      when is_list(event) and is_map(metadata) and is_function(fun, 0) and is_function(stop_metadata_fun, 1) do
    start_time = System.monotonic_time()

    execute(event ++ [:start], %{system_time: System.system_time()}, metadata)

    try do
      result = fun.()

      execute(
        event ++ [:stop],
        %{duration: System.monotonic_time() - start_time},
        Map.merge(metadata, stop_metadata_fun.(result))
      )

      result
    rescue
      error ->
        stacktrace = __STACKTRACE__

        execute(
          event ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: :error, reason: error, stacktrace: stacktrace})
        )

        reraise error, stacktrace
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__

        execute(
          event ++ [:exception],
          %{duration: System.monotonic_time() - start_time},
          Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: stacktrace})
        )

        :erlang.raise(kind, reason, stacktrace)
    end
  end

  def status_metadata(result) do
    case result do
      :ok -> %{status: :ok}
      {:ok, _value} -> %{status: :ok}
      {:error, reason} -> %{status: :error, error: reason}
      {:stop, reason} -> %{status: :error, error: reason}
      _other -> %{}
    end
  end

  defp execute(event, measurements, metadata) do
    :telemetry.execute(@prefix ++ event, measurements, metadata)
  end
end
