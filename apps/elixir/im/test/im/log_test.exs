defmodule IM.LogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require IM.Log

  defmodule Probe do
    require IM.Log

    def warn_packet_error do
      IM.Log.warning(:packet_error, code: 2004, reason: "conv_not_found")
    end

    def warn_auth_failed(fields) do
      IM.Log.warning(:auth_failed, fields)
    end
  end

  setup do
    previous = Application.get_env(:im, :env)
    on_exit(fn -> Application.put_env(:im, :env, previous) end)
    :ok
  end

  test "warning 宏注入业务调用点而非 IM.Log" do
    log =
      capture_log(fn ->
        Probe.warn_packet_error()
      end)

    assert log =~ "packet_error"
    assert log =~ "IM.LogTest.Probe" or log =~ "caller_module=Elixir.IM.LogTest.Probe"
    refute log =~ "caller_module=Elixir.IM.Log"
  end

  test "生产环境拒绝非白名单 event" do
    Application.put_env(:im, :env, :prod)

    log =
      capture_log(fn ->
        IM.Log.warning(:connection_state_violation, reason: "x")
      end)

    refute log =~ "connection_state_violation"
  end

  test "生产环境允许白名单 packet_error" do
    Application.put_env(:im, :env, :prod)

    log =
      capture_log(fn ->
        Probe.warn_packet_error()
      end)

    assert log =~ "packet_error"
  end

  test "auth_failed 在同一 key 窗口内采样" do
    :ok = IM.Log.RateLimit.reset!()
    k = "k-#{System.unique_integer([:positive])}"

    assert IM.Log.RateLimit.allow?(:auth_failed, app_key: k, user_id: "u1")
    refute IM.Log.RateLimit.allow?(:auth_failed, app_key: k, user_id: "u1")
    assert IM.Log.RateLimit.allow?(:auth_failed, app_key: k, user_id: "u2")
  end

  test "put_context 写入 Logger metadata" do
    ctx = %IM.Domain.MessageContext{
      app_key: "demo",
      user_id: "u1",
      device_id: "d1",
      session_id: "s1",
      trace_id: "t1"
    }

    assert :ok = IM.Log.put_context(ctx)
    meta = IM.Log.context_metadata()
    assert meta[:app_key] == "demo"
    assert meta[:trace_id] == "t1"
  end
end
