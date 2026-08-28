defmodule IM.WebSocket.ConnectionState do
  @moduledoc """
  单条 WS 连接状态机：`:unauthenticated` | `:authenticated` | `:closing`。

  所有入站 cmd 须先经 `allow?/2`（见 design/auth.md §7）。
  """

  alias IM.Domain.MessageContext
  alias Pb.Im.Protocol.CmdType

  defstruct status: :unauthenticated,
            context: nil,
            token_expires_at: nil,
            last_activity_at: nil,
            compression: :none,
            rooms: MapSet.new(),
            channels: MapSet.new()

  @type status :: :unauthenticated | :authenticated | :closing

  @type t :: %__MODULE__{
          status: status(),
          context: MessageContext.t() | nil,
          token_expires_at: DateTime.t() | nil,
          last_activity_at: integer() | nil,
          compression: atom(),
          rooms: MapSet.t(String.t()),
          channels: MapSet.t(String.t())
        }

  @auth_req CmdType.value(:CMD_AUTH_REQ)
  @heartbeat_req CmdType.value(:CMD_HEARTBEAT_REQ)

  @doc """
  新建未鉴权状态。

  ## 示例

      %IM.WebSocket.ConnectionState{status: :unauthenticated} = IM.WebSocket.ConnectionState.new()
  """
  @spec new() :: t()
  def new do
    %__MODULE__{last_activity_at: monotonic_ms()}
  end

  @doc """
  判断当前状态是否允许该 cmd。

  ## 示例

      :ok = IM.WebSocket.ConnectionState.allow?(:unauthenticated, 1)
  """
  @spec allow?(status() | t(), non_neg_integer()) ::
          :ok | {:error, :silent_close | :already_authenticated | :invalid_cmd}
  def allow?(%__MODULE__{status: status}, cmd), do: allow?(status, cmd)

  def allow?(:unauthenticated, cmd) when cmd == @auth_req, do: :ok
  def allow?(:unauthenticated, _cmd), do: {:error, :silent_close}

  def allow?(:authenticated, cmd) when cmd == @auth_req, do: {:error, :already_authenticated}
  def allow?(:authenticated, cmd) when cmd == @heartbeat_req, do: :ok

  def allow?(:authenticated, cmd) when is_integer(cmd) do
    case IM.Protocol.Router.route(cmd) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :invalid_cmd}
    end
  end

  def allow?(:closing, _cmd), do: {:error, :silent_close}

  @doc """
  鉴权成功转移。

  ## 示例

      IM.WebSocket.ConnectionState.authenticate(state, ctx)
  """
  @spec authenticate(t(), MessageContext.t(), keyword()) :: t()
  def authenticate(%__MODULE__{} = state, %MessageContext{} = ctx, opts \\ []) do
    compression = Keyword.get(opts, :compression, state.compression)
    token_expires_at = Keyword.get(opts, :token_expires_at)

    %{
      state
      | status: :authenticated,
        context: ctx,
        token_expires_at: token_expires_at,
        last_activity_at: monotonic_ms(),
        compression: compression
    }
  end

  @doc """
  标记关闭中。

  ## 示例

      IM.WebSocket.ConnectionState.closing(state)
  """
  @spec closing(t()) :: t()
  def closing(%__MODULE__{} = state), do: %{state | status: :closing}

  @doc """
  刷新空闲计时。

  ## 示例

      IM.WebSocket.ConnectionState.touch(state)
  """
  @spec touch(t()) :: t()
  def touch(%__MODULE__{} = state), do: %{state | last_activity_at: monotonic_ms()}

  @doc """
  记录已加入聊天室。
  """
  @spec join_room(t(), String.t()) :: t()
  def join_room(%__MODULE__{} = state, room_id) when is_binary(room_id) do
    %{state | rooms: MapSet.put(state.rooms, room_id), last_activity_at: monotonic_ms()}
  end

  @doc """
  移除已加入聊天室。
  """
  @spec leave_room(t(), String.t()) :: t()
  def leave_room(%__MODULE__{} = state, room_id) when is_binary(room_id) do
    %{state | rooms: MapSet.delete(state.rooms, room_id), last_activity_at: monotonic_ms()}
  end

  @doc """
  记录已订阅 App Channel。
  """
  @spec join_channel(t(), String.t()) :: t()
  def join_channel(%__MODULE__{} = state, channel_id) when is_binary(channel_id) do
    %{
      state
      | channels: MapSet.put(state.channels, channel_id),
        last_activity_at: monotonic_ms()
    }
  end

  @doc """
  移除 App Channel 订阅记录。
  """
  @spec leave_channel(t(), String.t()) :: t()
  def leave_channel(%__MODULE__{} = state, channel_id) when is_binary(channel_id) do
    %{
      state
      | channels: MapSet.delete(state.channels, channel_id),
        last_activity_at: monotonic_ms()
    }
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
