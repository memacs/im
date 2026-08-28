defmodule IM.AuthFixtures do
  @moduledoc false

  alias IM.Auth.Password
  alias IM.Services.Session
  alias IM.Stores.UserStore

  def create_user!(attrs \\ %{}) do
    attrs = Map.new(attrs)
    app_key = Map.get(attrs, :app_key, "app_demo")
    user_id = Map.get(attrs, :user_id, "user_#{System.unique_integer([:positive])}")
    password = Map.get(attrs, :password, "secret")

    {:ok, user} =
      UserStore.ensure(%{
        app_key: app_key,
        user_id: user_id,
        password_hash: Password.hash(password, app_key, user_id),
        nickname: Map.get(attrs, :nickname, user_id)
      })

    %{user: user, password: password, app_key: app_key, user_id: user_id}
  end

  def login!(attrs \\ %{}) do
    attrs = Map.new(attrs)
    %{user: user, password: password, app_key: app_key, user_id: user_id} = create_user!(attrs)
    device_id = Map.get(attrs, :device_id, "device_#{System.unique_integer([:positive])}")
    platform = Map.get(attrs, :platform, "ios")

    {:ok, session} =
      Session.create(%{
        "app_key" => app_key,
        "user_id" => user_id,
        "password" => password,
        "device_id" => device_id,
        "platform" => platform,
        "sdk_ver" => "1.0.0"
      })

    %{
      user: user,
      password: password,
      app_key: app_key,
      user_id: user_id,
      device_id: device_id,
      platform: platform,
      session: session,
      token: session.access_token
    }
  end
end
