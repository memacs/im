defmodule IM.Cluster.GroupPusherTest do
  use ExUnit.Case, async: false

  alias IM.Cluster.{FanoutBatcher, GroupPusher}
  alias IM.Group.FanoutPolicy
  alias IM.Protocol.{Codec, Push}
  alias IM.UserTracker
  alias Pb.Im.Protocol.ChatMessage

  setup do
    previous = Application.get_env(:im, :group_fanout)

    Application.put_env(
      :im,
      :group_fanout,
      Keyword.merge(previous || [], tree_threshold: 2, branching_factor: 8)
    )

    on_exit(fn ->
      if previous do
        Application.put_env(:im, :group_fanout, previous)
      else
        Application.delete_env(:im, :group_fanout)
      end
    end)

    :ok
  end

  test "FanoutPolicy 阈值判定" do
    assert FanoutPolicy.use_tree_push?(3)
    refute FanoutPolicy.use_tree_push?(2)

    assert FanoutPolicy.storage_mode(%{member_count: 10, storage_mode: "write_fanout"}) ==
             :write_fanout
  end

  test "树状路径推送在线设备" do
    app = "app_push"
    users = for i <- 1..3, do: "u#{i}_#{System.unique_integer([:positive])}"
    parent = self()

    pids =
      Enum.map(users, fn uid ->
        spawn_link(fn ->
          :ok = UserTracker.track(app, uid, "d1", %{platform: "ios"})
          send(parent, {:ready, self()})
          receive_loop(parent)
        end)
      end)

    Enum.each(pids, fn _ -> assert_receive {:ready, _}, 1000 end)
    # 等待 UserTracker 完成跨进程注册后再推送
    Process.sleep(50)

    msg = %ChatMessage{msg_id: "m1", from: "a", to: "g", conv_id: "g:g1", content: "hi"}
    {:ok, packet} = Push.build(:CMD_MSG_PUSH, msg, trace_id: "t")
    {:ok, bin} = Codec.encode(packet)

    assert {:ok, %{tree?: true}} = GroupPusher.push(app, users, bin, force_tree: true)

    for pid <- pids do
      assert_receive {:got, ^pid}, 1000
    end
  end

  test "PUSH_BATCH 多条合并编码" do
    parent = self()

    pid =
      spawn_link(fn ->
        receive do
          {:im_push, bin} ->
            {:ok, packet} = Codec.decode(bin)
            send(parent, {:batch_cmd, packet.cmd})

          {:im_push, bin, _meta} ->
            {:ok, packet} = Codec.decode(bin)
            send(parent, {:batch_cmd, packet.cmd})
        end
      end)

    msgs =
      for i <- 1..3 do
        %ChatMessage{msg_id: "m#{i}", content: "#{i}", conv_id: "g:1"}
      end

    assert :ok = FanoutBatcher.deliver_messages(pid, msgs, trace_id: "tb")
    assert_receive {:batch_cmd, 102}, 500
  end

  defp receive_loop(parent) do
    receive do
      {:im_push, _bin} ->
        send(parent, {:got, self()})
        receive_loop(parent)

      {:im_push, _bin, _meta} ->
        send(parent, {:got, self()})
        receive_loop(parent)
    end
  end
end
