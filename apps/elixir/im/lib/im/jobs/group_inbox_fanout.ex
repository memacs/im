defmodule IM.Jobs.GroupInboxFanout do
  @moduledoc """
  群 inbox 异步写扩散（P5-11）。经 Oban `IM.Workers.GroupInboxFanout` 执行。
  """

  alias IM.Stores.MessageStore

  @doc """
  异步为其余成员写 inbox。`body_attrs` 须含已落库的 msg 元数据。

  ## 示例

      IM.Jobs.GroupInboxFanout.enqueue(attrs, ["u2", "u3"])
  """
  @spec enqueue(map(), [String.t()]) :: :ok
  def enqueue(body_attrs, recipient_user_ids)
      when is_map(body_attrs) and is_list(recipient_user_ids) do
    args = %{
      "body_attrs" => stringify_keys(body_attrs),
      "recipient_user_ids" => recipient_user_ids
    }

    case args |> IM.Workers.GroupInboxFanout.new() |> Oban.insert() do
      {:ok, _} ->
        :ok

      {:error, _} ->
        _ = run(body_attrs, recipient_user_ids)
        :ok
    end
  end

  @doc false
  def run(body_attrs, recipient_user_ids) do
    start = System.monotonic_time()

    case MessageStore.insert_inbox_rows(body_attrs, recipient_user_ids) do
      :ok ->
        :telemetry.execute(
          [:im, :group, :inbox_fanout],
          %{duration: System.monotonic_time() - start, count: length(recipient_user_ids)},
          %{}
        )

        :ok

      {:error, reason} ->
        :telemetry.execute([:im, :group, :inbox_fanout_error], %{count: 1}, %{
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {to_string(k), stringify_value(v)}
    end)
  end

  defp stringify_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp stringify_value(v), do: v
end
