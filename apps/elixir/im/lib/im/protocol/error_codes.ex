defmodule IM.Protocol.ErrorCodes do
  @moduledoc """
  将 `%IM.Domain.Error{}.code` 原子映射为 `proto/common.proto` 的 `ErrorCode`。

  业务层只使用原子；出口（`Reply` / REST Fallback）再转成枚举与数值。
  """

  alias Pb.Im.Protocol.ErrorCode

  @mapping %{
    ok: :CODE_OK,
    unauthorized: :CODE_UNAUTHORIZED,
    kicked: :CODE_KICKED,
    proto_version_unsupported: :CODE_PROTO_VERSION_UNSUPPORTED,
    device_limit_exceeded: :CODE_DEVICE_LIMIT_EXCEEDED,
    msg_invalid: :CODE_MSG_INVALID,
    unknown_cmd: :CODE_MSG_INVALID,
    msg_no_permission: :CODE_MSG_NO_PERMISSION,
    msg_recall_denied: :CODE_MSG_RECALL_DENIED,
    conv_not_found: :CODE_CONV_NOT_FOUND,
    msg_edit_denied: :CODE_MSG_EDIT_DENIED,
    msg_burn_denied: :CODE_MSG_BURN_DENIED,
    group_not_found: :CODE_GROUP_NOT_FOUND,
    group_no_permission: :CODE_GROUP_NO_PERMISSION,
    group_member_limit: :CODE_GROUP_MEMBER_LIMIT,
    group_already_member: :CODE_GROUP_ALREADY_MEMBER,
    group_not_member: :CODE_GROUP_NOT_MEMBER,
    room_not_found: :CODE_ROOM_NOT_FOUND,
    room_no_permission: :CODE_ROOM_NO_PERMISSION,
    room_member_limit: :CODE_ROOM_MEMBER_LIMIT,
    room_already_member: :CODE_ROOM_ALREADY_MEMBER,
    room_not_member: :CODE_ROOM_NOT_MEMBER,
    rate_limited: :CODE_RATE_LIMITED,
    channel_not_found: :CODE_CHANNEL_NOT_FOUND,
    channel_no_permission: :CODE_CHANNEL_NO_PERMISSION,
    channel_rate_limited: :CODE_CHANNEL_RATE_LIMITED,
    friend_self: :CODE_FRIEND_SELF,
    friend_already: :CODE_FRIEND_ALREADY,
    friend_blocked: :CODE_FRIEND_BLOCKED,
    friend_blocked_by_peer: :CODE_FRIEND_BLOCKED_BY_PEER,
    friend_request_not_found: :CODE_FRIEND_REQUEST_NOT_FOUND,
    friend_not_friend: :CODE_FRIEND_NOT_FRIEND,
    friend_no_permission: :CODE_FRIEND_NO_PERMISSION,
    not_implemented: :CODE_INTERNAL_ERROR,
    internal_error: :CODE_INTERNAL_ERROR
  }

  @doc """
  原子错误码 → proto 枚举原子。未知原子回退 `:CODE_INTERNAL_ERROR`。

  ## 示例

      iex> IM.Protocol.ErrorCodes.to_proto(:unauthorized)
      :CODE_UNAUTHORIZED

      iex> IM.Protocol.ErrorCodes.to_proto(:no_such_atom)
      :CODE_INTERNAL_ERROR
  """
  @spec to_proto(atom()) :: atom()
  def to_proto(code) when is_atom(code) do
    Map.get(@mapping, code, :CODE_INTERNAL_ERROR)
  end

  @doc """
  原子错误码 → proto 数值。

  ## 示例

      iex> IM.Protocol.ErrorCodes.to_int(:proto_version_unsupported)
      1003
  """
  @spec to_int(atom()) :: non_neg_integer()
  def to_int(code) when is_atom(code) do
    code
    |> to_proto()
    |> ErrorCode.value()
  end
end
