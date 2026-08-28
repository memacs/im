defmodule IM.Client.Protocol.TraceCoverageTest do
  @moduledoc false
  use ExUnit.Case, async: true

  @protocol_dir Path.join([__DIR__])

  @expected_trace_cases [
    "auth_guard_test/未鉴权发心跳静默关闭",
    "auth_guard_test/未鉴权发 MSG_SEND 静默关闭",
    "auth_guard_test/鉴权超时静默关闭",
    "auth_guard_test/已鉴权再发 AUTH",
    "auth_guard_test/无效 token",
    "auth_guard_test/已吊销 token",
    "auth_guard_test/token 与 user_id 不匹配",
    "auth_guard_test/token 与 device_id 不匹配",
    "auth_guard_test/过期 token",
    "auth_guard_test/封禁设备 AUTH",
    "auth_guard_test/连接中 token 过期 CMD_KICK",
    "channel_test/订阅与 publish",
    "cluster_test/跨节点 PUSH 单聊",
    "cluster_test/跨节点 erpc 转发",
    "connection_test/REST 登录 + WS AUTH + 心跳",
    "connection_test/登出 DELETE sessions",
    "connection_test/GET metrics",
    "conversation_test/REST 会话列表未读与已读同步",
    "conversation_test/群聊会话列表未读",
    "extensions_test/已读回执",
    "extensions_test/编辑消息",
    "extensions_test/撤回消息",
    "extensions_test/透传指令",
    "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH",
    "friend_policy_test/require_friend_to_send",
    "friend_test/添加-接受-列表-备注-删除",
    "friend_test/拒绝好友请求",
    "friend_test/拉黑与取消拉黑",
    "friend_test/好友请求列表",
    "group_test/群生命周期与群消息",
    "offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取",
    "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK",
    "private_message_test/批量 ACK",
    "private_message_test/REST 发消息双通道",
    "private_message_test/client_msg_id 幂等",
    "room_test/聊天室生命周期与广播",
    "session_test/内部 kick 在线设备收到 CMD_KICK",
    "session_test/同平台超限 reject 鉴权失败",
    "session_test/同平台超限 kick_oldest 踢掉旧设备",
    "stream_test/MSG_STREAM 四段推送至对端",
    "stream_test/流式透传 stream_start/chunk/end",
    "stream_test/MSG_STREAM 离线拉取"
  ]

  @tag :trace_coverage
  test "protocol E2E 用例均声明 @tag trace_case" do
    declared = scan_trace_cases()
    expected = Enum.sort(@expected_trace_cases)

    assert declared == expected,
           """
           trace_case 声明与 trace_coverage 清单不一致。
           新增/重命名 E2E 用例时，请同时更新：
           1. 对应用例的 @tag trace_case
           2. test/im_client/protocol/trace_coverage_test.exs 中的 @expected_trace_cases
           3. 运行 PGPORT=15432 TRACE_EXPORT=1 CLUSTER_E2E=1 mix test.trace 更新文档

           缺少: #{inspect(expected -- declared)}
           多余: #{inspect(declared -- expected)}
           """
  end

  @tag :trace_coverage
  test "导出的 JSON 覆盖全部 trace_case（若文件存在）" do
    json_path = IM.ProtocolTraceRegistry.json_path()

    if File.exists?(json_path) do
      cases =
        json_path
        |> File.read!()
        |> Jason.decode!()
        |> Enum.map(& &1["case"])
        |> Enum.uniq()
        |> Enum.sort()

      expected = Enum.sort(@expected_trace_cases)

      assert cases == expected,
             "protocol-e2e-traces.json 与用例清单不一致；请运行 mix test.trace 重新导出"
    end
  end

  defp scan_trace_cases do
    @protocol_dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, "_test.exs"))
    |> Enum.reject(&(&1 == "trace_coverage_test.exs"))
    |> Enum.flat_map(fn file ->
      @protocol_dir
      |> Path.join(file)
      |> File.read!()
      |> then(&Regex.scan(~r/@tag trace_case: "([^"]+)"/, &1))
      |> Enum.map(fn [_, case_id] -> case_id end)
    end)
    |> Enum.sort()
  end
end
