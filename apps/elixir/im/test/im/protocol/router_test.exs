defmodule IM.Protocol.RouterTest do
  use ExUnit.Case, async: false

  alias IM.Domain.Error
  alias IM.Protocol.{Cmd, Router}
  alias Pb.Im.Protocol.CmdType

  defmodule StubCommand do
    @moduledoc false
    def handle(_packet, _socket), do: :ok
  end

  setup do
    previous = Application.get_env(:im, :protocol_command_handlers)
    Application.put_env(:im, :protocol_command_handlers, %{})

    on_exit(fn ->
      if previous do
        Application.put_env(:im, :protocol_command_handlers, previous)
      else
        Application.delete_env(:im, :protocol_command_handlers)
      end
    end)

    :ok
  end

  describe "route/1" do
    test "命中注入的 handler 模块" do
      cmd = CmdType.value(:CMD_HEARTBEAT_REQ)
      Application.put_env(:im, :protocol_command_handlers, %{cmd => StubCommand})

      assert {:ok, StubCommand} = Router.route(cmd)
    end

    test "未注册 cmd 返回 unknown_cmd" do
      assert {:error, %Error{code: :unknown_cmd, ref_cmd: 65_535}} = Router.route(65_535)
    end
  end

  describe "Cmd 互转" do
    test "已知 cmd 原子与数值互转" do
      assert {:ok, :CMD_MSG_SEND} = Cmd.to_atom(100)
      assert {:ok, 100} = Cmd.to_value(:CMD_MSG_SEND)
      assert {:ok, :CMD_ERROR} = Cmd.to_atom(CmdType.value(:CMD_ERROR))
    end

    test "未知数值不崩溃" do
      assert {:error, %Error{code: :unknown_cmd}} = Cmd.to_atom(65_535)
    end

    test "未知原子返回错误" do
      assert {:error, %Error{code: :unknown_cmd}} = Cmd.to_value(:CMD_DOES_NOT_EXIST)
    end
  end
end
