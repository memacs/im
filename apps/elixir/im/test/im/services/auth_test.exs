defmodule IM.Services.AuthTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.Error
  alias IM.Services.Auth
  alias Pb.Im.Protocol.AuthReq

  test "有效 token 返回 AuthResp 与 context" do
    %{token: token, app_key: app_key, user_id: user_id, device_id: device_id} = AuthFixtures.login!()

    req = %AuthReq{
      app_key: app_key,
      user_id: user_id,
      token: token,
      device_id: device_id,
      platform: "ios",
      sdk_ver: "1.0"
    }

    assert {:ok, %{resp: resp, context: ctx}} = Auth.authenticate(req, "tr-1")
    assert resp.user_id == user_id
    assert resp.clear_local_data == false
    assert resp.payload_compression == :PAYLOAD_COMPRESSION_NONE
    assert ctx.trace_id == "tr-1"
    assert ctx.device_id == device_id
  end

  test "无效 token 失败" do
    req = %AuthReq{token: "nope", user_id: "u", device_id: "d", platform: "ios"}
    assert {:error, %Error{code: :unauthorized}} = Auth.authenticate(req, "t")
  end
end
