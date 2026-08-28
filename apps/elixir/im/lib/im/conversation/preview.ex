defmodule IM.Conversation.Preview do
  @moduledoc "会话列表消息预览文本。"

  alias Pb.Im.Protocol.MsgType

  @max_len 256

  @doc "从消息类型与内容生成预览。"
  @spec from_message(term(), String.t() | nil, boolean()) :: String.t()
  def from_message(msg_type, content, recalled \\ false)

  def from_message(_msg_type, _content, true), do: "[消息已撤回]"

  def from_message(msg_type, content, false) do
    case normalize_type(msg_type) do
      :MSG_TEXT -> truncate(content || "")
      :MSG_IMAGE -> "[图片]"
      :MSG_VIDEO -> "[视频]"
      :MSG_AUDIO -> "[语音]"
      :MSG_FILE -> "[文件]"
      :MSG_LOCATION -> "[位置]"
      :MSG_CUSTOM -> truncate(content || "[自定义消息]")
      :MSG_STREAM -> "[流式消息]"
      _ -> truncate(content || "[消息]")
    end
  end

  @doc "从 MessageBody 字段生成预览。"
  @spec from_body(non_neg_integer(), String.t() | nil, boolean()) :: String.t()
  def from_body(msg_type, content, recalled \\ false) do
    atom =
      case MsgType.key(msg_type) do
        a when is_atom(a) -> a
        _ -> :MSG_TEXT
      end

    from_message(atom, content, recalled)
  end

  defp normalize_type(v) when is_atom(v), do: v

  defp normalize_type(v) when is_integer(v) do
    case MsgType.key(v) do
      a when is_atom(a) -> a
      _ -> :MSG_TEXT
    end
  end

  defp normalize_type(_), do: :MSG_TEXT

  defp truncate(bin) when is_binary(bin) do
    if String.length(bin) <= @max_len do
      bin
    else
      String.slice(bin, 0, @max_len - 1) <> "…"
    end
  end

  defp truncate(_), do: ""
end
