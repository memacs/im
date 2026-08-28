defmodule IM.AppConfig.InvalidatorTest do
  use IM.DataCase, async: false

  alias IM.Repo
  alias IM.Schemas.AppConfig
  alias IM.Stores.AppConfigStore

  test "invalidate_local 清除 ETS 后从 PG 回源最新值" do
    AppConfigStore.clear_cache()

    assert {:ok, row} =
             AppConfigStore.put("app_demo", "friend", "require_friend_to_send", true)

    assert AppConfigStore.get_boolean("app_demo", "friend", "require_friend_to_send", false)

    row
    |> AppConfig.changeset(%{config_value: "false"})
    |> Repo.update!()

    # ETS 仍为 true（stale）
    assert AppConfigStore.get_boolean("app_demo", "friend", "require_friend_to_send", false)

    :ok = AppConfigStore.invalidate_local("app_demo", "friend", "require_friend_to_send")

    refute AppConfigStore.get_boolean("app_demo", "friend", "require_friend_to_send", false)
  end
end
