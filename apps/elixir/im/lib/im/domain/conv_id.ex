defmodule IM.Domain.ConvId do
  @moduledoc "会话 ID 规则：单聊 `p:{lo}:{hi}`（字典序）。"

  alias IM.Domain.Error

  @doc """
  生成单聊 conv_id。

  ## 示例

      "p:a:b" = IM.Domain.ConvId.private("b", "a")
  """
  @spec private(String.t(), String.t()) :: String.t()
  def private(uid_a, uid_b) when is_binary(uid_a) and is_binary(uid_b) do
    [lo, hi] = Enum.sort([uid_a, uid_b])
    "p:#{lo}:#{hi}"
  end

  @doc """
  校验或回填单聊 conv_id。

  ## 示例

      {:ok, "p:a:b"} = IM.Domain.ConvId.normalize_private("", "a", "b")
  """
  @spec normalize_private(String.t() | nil, String.t(), String.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def normalize_private(conv_id, from, to)
      when is_binary(from) and is_binary(to) and from != "" and to != "" do
    expected = private(from, to)

    cond do
      conv_id in [nil, ""] ->
        {:ok, expected}

      conv_id == expected ->
        {:ok, expected}

      true ->
        {:error, Error.new(:msg_invalid, "conv_id mismatch")}
    end
  end

  def normalize_private(_, _, _), do: {:error, Error.new(:msg_invalid, "from/to required")}

  @doc """
  生成群会话 ID。

  ## 示例

      "g:g1" = IM.Domain.ConvId.group("g1")
  """
  @spec group(String.t()) :: String.t()
  def group(group_id) when is_binary(group_id) and group_id != "", do: "g:#{group_id}"

  @doc """
  校验或回填群 conv_id。

  ## 示例

      {:ok, "g:g1"} = IM.Domain.ConvId.normalize_group("", "g1")
  """
  @spec normalize_group(String.t() | nil, String.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def normalize_group(conv_id, group_id)
      when is_binary(group_id) and group_id != "" do
    expected = group(group_id)

    cond do
      conv_id in [nil, ""] -> {:ok, expected}
      conv_id == expected -> {:ok, expected}
      true -> {:error, Error.new(:msg_invalid, "conv_id mismatch")}
    end
  end

  def normalize_group(_, _), do: {:error, Error.new(:msg_invalid, "group_id required")}

  @doc """
  聊天室 conv_id：`r:{room_id}`。
  """
  @spec room(String.t()) :: String.t()
  def room(room_id) when is_binary(room_id) and room_id != "", do: "r:#{room_id}"

  @spec normalize_room(String.t() | nil, String.t()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def normalize_room(conv_id, room_id)
      when is_binary(room_id) and room_id != "" do
    expected = room(room_id)

    cond do
      conv_id in [nil, ""] -> {:ok, expected}
      conv_id == expected -> {:ok, expected}
      true -> {:error, Error.new(:msg_invalid, "conv_id mismatch")}
    end
  end

  def normalize_room(_, _), do: {:error, Error.new(:msg_invalid, "room_id required")}
end
