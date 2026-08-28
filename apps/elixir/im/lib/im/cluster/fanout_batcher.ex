defmodule IM.Cluster.FanoutBatcher do
  @moduledoc """
  叶节点本机写出：单条 `CMD_MSG_PUSH`，多条合并为 `CMD_MSG_PUSH_BATCH`（≤ push_batch_max）。
  """

  alias IM.Delivery.Outbound
  alias IM.Group.FanoutConfig
  alias IM.Protocol.{Codec, Push}
  alias Pb.Im.Protocol.{ChatMessage, MsgPushBatch}

  @doc """
  向本机连接写出已预编码的单包二进制（禁止再 encode）。

  ## 示例

      IM.Cluster.FanoutBatcher.deliver_encoded([pid], bin)
  """
  @spec deliver_encoded([pid()], binary(), keyword()) :: :ok
  def deliver_encoded(pids, bin, opts \\ []) when is_list(pids) and is_binary(bin) do
    meta = %{
      priority: Keyword.get(opts, :priority, :normal),
      inbox_seq: Keyword.get(opts, :inbox_seq, 0)
    }

    Enum.each(pids, fn pid ->
      if Process.alive?(pid), do: send(pid, {:im_push, bin, meta})
    end)

    :ok
  end

  @doc """
  向单一连接推送多条 ChatMessage（P5-08）：按 `push_batch_max` 分批 `CMD_MSG_PUSH_BATCH`。

  ## 示例

      IM.Cluster.FanoutBatcher.deliver_messages(pid, messages, trace_id: "t")
  """
  @spec deliver_messages(pid(), [ChatMessage.t()], keyword()) :: :ok | {:error, term()}
  def deliver_messages(pid, messages, opts \\ []) when is_pid(pid) and is_list(messages) do
    max = FanoutConfig.push_batch_max()
    trace_id = Keyword.get(opts, :trace_id, "")

    messages
    |> Enum.map(fn %ChatMessage{} = m ->
      %{
        priority: m.priority,
        inbox_seq: m.inbox_seq || 0,
        message: m
      }
    end)
    |> Outbound.sort_by_priority()
    |> Enum.map(& &1.message)
    |> Enum.chunk_every(max)
    |> Enum.each(fn chunk ->
      case encode_chunk(chunk, trace_id) do
        {:ok, bin} ->
          head = hd(chunk)

          meta = %{
            priority: head.priority,
            inbox_seq: head.inbox_seq || 0
          }

          if Process.alive?(pid), do: send(pid, {:im_push, bin, meta})

        _ ->
          :ok
      end
    end)

    :ok
  end

  defp encode_chunk([one], trace_id) do
    with {:ok, packet} <-
           Push.build(:CMD_MSG_PUSH, one, trace_id: trace_id, route_key: one.conv_id || ""),
         {:ok, bin} <- Codec.encode(packet) do
      {:ok, bin}
    end
  end

  defp encode_chunk(many, trace_id) when length(many) > 1 do
    batch = %MsgPushBatch{messages: many}

    with {:ok, packet} <-
           Push.build(:CMD_MSG_PUSH_BATCH, batch,
             trace_id: trace_id,
             route_key: hd(many).conv_id || ""
           ),
         {:ok, bin} <- Codec.encode(packet) do
      {:ok, bin}
    end
  end
end
