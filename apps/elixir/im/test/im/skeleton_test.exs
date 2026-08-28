defmodule IM.SkeletonTest do
  @moduledoc """
  P0-05 骨架契约。

  这些模块目前只有签名没有实现，本测试锁定的是**契约形状**：
  分层入口存在、未实现路径统一返回 `IM.Domain.Error`、
  `MessageContext` 的必填键不会被悄悄放宽。

  Phase 1+ 每落地一个模块，就把对应用例从这里搬到该模块自己的测试文件。
  """
  use ExUnit.Case, async: true

  alias IM.Domain.{Error, MessageContext}

  describe "IM.Domain.MessageContext" do
    test "缺少必填键直接编译期/构造期报错" do
      assert_raise ArgumentError, fn ->
        struct!(MessageContext, user_id: "u_1")
      end
    end

    test "四个必填键齐全即可构造" do
      ctx = %MessageContext{
        app_key: "app_1",
        user_id: "u_1",
        device_id: "d_1",
        trace_id: "t_1"
      }

      assert ctx.session_id == nil
      assert ctx.node == nil
    end
  end

  describe "IM.Domain.Error" do
    test "not_implemented/1 携带触发它的命令字" do
      assert %Error{code: :not_implemented, ref_cmd: 100} = Error.not_implemented(100)
    end

    test "new/3 保留人类可读描述" do
      err = Error.new(:permission_denied, "not a group member", ref_cmd: 600)
      assert err.code == :permission_denied
      assert err.msg == "not a group member"
      assert err.ref_cmd == 600
    end
  end

  describe "分层入口存在且未实现路径一致" do
    setup do
      ctx = %MessageContext{app_key: "a", user_id: "u", device_id: "d", trace_id: "t"}
      %{ctx: ctx}
    end

    test "Dispatch.execute/3 是 WS 与 REST 的唯一业务入口", %{ctx: ctx} do
      assert {:error, %Error{code: :not_implemented, ref_cmd: 100}} =
               IM.Application.Dispatch.execute(100, %{}, ctx)
    end

    test "Protocol.Codec 双向编解码待 Phase 1 实现" do
      assert {:error, %Error{code: :not_implemented}} = IM.Protocol.Codec.decode(<<>>)
      assert {:error, %Error{code: :not_implemented}} = IM.Protocol.Codec.encode(%{})
    end

    test "Protocol.Router 按 cmd 选 Command 模块" do
      assert {:error, %Error{code: :not_implemented}} = IM.Protocol.Router.route(100)
    end

    test "Ingress.Http 是 REST 侧适配，不含业务" do
      assert {:error, %Error{code: :not_implemented}} =
               IM.Ingress.Http.dispatch(%{}, 100, fn _ -> {:ok, %{}} end)
    end

    test "Delivery.Router 负责下行扇出，与 Dispatch 无关", %{ctx: ctx} do
      assert {:error, %Error{code: :not_implemented}} = IM.Delivery.Router.deliver(%{}, ctx)
    end
  end
end
