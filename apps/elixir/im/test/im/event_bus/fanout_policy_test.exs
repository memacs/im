defmodule IM.EventBus.FanoutPolicyTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.EventBus.FanoutPolicy
  alias IM.Services.Group

  setup do
    prev = Application.get_env(:im, :event_bus_kafka)

    on_exit(fn ->
      if prev, do: Application.put_env(:im, :event_bus_kafka, prev), else: Application.delete_env(:im, :event_bus_kafka)
    end)

    :ok
  end

  test "单聊 direct；大群 aggregated；聊天室 room_aggregated" do
    assert {:direct, nil} = FanoutPolicy.resolve(%{chat_type: :CHAT_PRIVATE}, [])
    assert {:room_aggregated, nil} = FanoutPolicy.resolve(%{chat_type: :CHAT_ROOM}, [])

    owner = AuthFixtures.create_user!(user_id: "fp_#{System.unique_integer([:positive])}")
    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    members =
      for _ <- 1..3 do
        AuthFixtures.create_user!(
          app_key: owner.app_key,
          user_id: "m_#{System.unique_integer([:positive])}"
        ).user_id
      end

    assert {:ok, g} =
             Group.create(%{"name" => "small", "member_uids" => members}, ctx)

    assert {:direct, nil} =
             FanoutPolicy.resolve(
               %{chat_type: :CHAT_GROUP, to: g.group_id, app_key: owner.app_key},
               []
             )

    Application.put_env(
      :im,
      :event_bus_kafka,
      Keyword.merge(Application.get_env(:im, :event_bus_kafka, []),
        downstream_group_large_threshold: 2
      )
    )

    assert {:group_aggregated, nil} =
             FanoutPolicy.resolve(
               %{chat_type: :CHAT_GROUP, to: g.group_id, app_key: owner.app_key},
               []
             )
  end
end
