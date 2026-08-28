defmodule IM.Protocol.ErrorCodesTest do
  use ExUnit.Case, async: true

  alias IM.Protocol.ErrorCodes
  alias Pb.Im.Protocol.{AuthResp, ErrorCode, KickNotify, KickReason, PayloadCompression}

  describe "to_proto/1 与 to_int/1" do
    test "已定义原子映射到 proto 数值" do
      assert ErrorCodes.to_proto(:unauthorized) == :CODE_UNAUTHORIZED
      assert ErrorCodes.to_int(:unauthorized) == 1001
      assert ErrorCodes.to_int(:proto_version_unsupported) == 1003
      assert ErrorCodes.to_int(:msg_invalid) == 2001
      assert ErrorCodes.to_int(:unknown_cmd) == 2001
      assert ErrorCodes.to_int(:friend_blocked_by_peer) == 7004
      assert ErrorCodes.to_int(:not_implemented) == 9000
    end

    test "未知原子回退 INTERNAL_ERROR" do
      assert ErrorCodes.to_proto(:totally_unknown) == :CODE_INTERNAL_ERROR
      assert ErrorCodes.to_int(:totally_unknown) == ErrorCode.value(:CODE_INTERNAL_ERROR)
    end
  end

  describe "AuthResp / KickNotify 字段与 proto 对齐" do
    test "AuthResp 含 clear_local_data 与 payload_compression" do
      resp = %AuthResp{
        user_id: "u1",
        clear_local_data: true,
        payload_compression: :PAYLOAD_COMPRESSION_NONE,
        server_time: 1
      }

      assert resp |> AuthResp.encode() |> AuthResp.decode() == resp
      assert PayloadCompression.value(:PAYLOAD_COMPRESSION_NONE) == 1
    end

    test "KickNotify 含 reason_code 枚举" do
      notify = %KickNotify{
        reason: "dup",
        reason_code: :KICK_REASON_DUPLICATE_LOGIN,
        clear_local_data: true,
        timestamp: 2
      }

      assert notify |> KickNotify.encode() |> KickNotify.decode() == notify
      assert KickReason.value(:KICK_REASON_TOKEN_EXPIRED) == 5
    end
  end
end
