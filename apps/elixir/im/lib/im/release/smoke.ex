defmodule IM.Release.Smoke do
  @moduledoc """
  Release 冒烟：不依赖 Mix，可在容器内 `bin/smoke-messaging` 执行。

  覆盖：建用户 → 发单聊 → 会话列表未读 → 已读清零。
  """

  alias IM.Auth.Password
  alias IM.Domain.MessageContext
  alias IM.Services.{Conversation, Message, MessageRead, Session}
  alias IM.Stores.{ConversationStore, UserStore}
  alias Pb.Im.Protocol.{ChatMessage, MsgRead}

  @app :im
  @default_app "app_demo"
  @default_password "smoke_secret"

  @doc """
  消息与会话未读冒烟。

  ## 示例

      bin/smoke-messaging
      # 或 bin/im eval "IM.Release.Smoke.messaging()"
  """
  @spec messaging() :: :ok
  def messaging do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    app_key = System.get_env("SMOKE_APP_KEY") || @default_app
    password = System.get_env("SMOKE_PASSWORD") || @default_password
    suffix = Integer.to_string(System.system_time(:millisecond))
    alice_id = "smoke_a_#{suffix}"
    bob_id = "smoke_b_#{suffix}"

    :ok = ensure_user(app_key, alice_id, password)
    :ok = ensure_user(app_key, bob_id, password)

    alice_ctx = ctx(app_key, alice_id, "smoke-a")
    bob_ctx = ctx(app_key, bob_id, "smoke-b")

    {:ok, sent} =
      Message.send(
        %ChatMessage{
          chat_type: :CHAT_PRIVATE,
          to: bob_id,
          msg_type: :MSG_TEXT,
          content: "release-smoke",
          client_msg_id: "smoke-#{suffix}"
        },
        alice_ctx
      )

    {:ok, %{total_unread: unread_before}} = Conversation.list(bob_ctx, limit: 20)

    if unread_before < 1 do
      raise "smoke failed: expected recipient unread >= 1, got #{unread_before}"
    end

    {:ok, _} =
      MessageRead.mark(
        %MsgRead{
          chat_type: :CHAT_PRIVATE,
          to: alice_id,
          conv_id: sent.message.conv_id,
          conv_seq: sent.message.conv_seq,
          msg_id: sent.message.msg_id
        },
        bob_ctx
      )

    if ConversationStore.get_unread(app_key, bob_id, sent.message.conv_id) != 0 do
      raise "smoke failed: unread not cleared after read"
    end

    {:ok, %{total_unread: unread_after}} = Conversation.list(bob_ctx, limit: 20)

    if unread_after != 0 do
      raise "smoke failed: expected total_unread 0 after read, got #{unread_after}"
    end

    # 登录路径烟测
    {:ok, _} =
      Session.create(%{
        "app_key" => app_key,
        "user_id" => alice_id,
        "password" => password,
        "device_id" => "smoke-login",
        "platform" => "ios",
        "sdk_ver" => "1.0"
      })

    IO.puts("SMOKE MESSAGING OK")
    :ok
  end

  @doc """
  REST 登录冒烟（`bin/smoke-auth`）。

  预置临时用户并 `Session.create`；WS 鉴权见 im_client / release-smoke-auth.md 手工路径。
  """
  @spec auth() :: :ok
  def auth do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    app_key = System.get_env("SMOKE_APP_KEY") || @default_app
    password = System.get_env("SMOKE_PASSWORD") || @default_password
    user_id = "smoke_auth_#{System.system_time(:millisecond)}"

    :ok = ensure_user(app_key, user_id, password)

    {:ok, session} =
      Session.create(%{
        "app_key" => app_key,
        "user_id" => user_id,
        "password" => password,
        "device_id" => "smoke-auth",
        "platform" => "ios",
        "sdk_ver" => "1.0"
      })

    if not is_binary(session.access_token) or session.access_token == "" do
      raise "smoke auth failed: missing access_token"
    end

    IO.puts("SMOKE AUTH OK")
    :ok
  end

  defp ensure_user(app_key, user_id, password) do
    case UserStore.ensure(%{
           app_key: app_key,
           user_id: user_id,
           password_hash: Password.hash(password, app_key, user_id),
           nickname: user_id
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "smoke ensure_user failed: #{inspect(reason)}"
    end
  end

  defp ctx(app_key, user_id, device_id) do
    %MessageContext{
      app_key: app_key,
      user_id: user_id,
      device_id: device_id,
      session_id: Ecto.UUID.generate(),
      trace_id: "release-smoke",
      node: node(),
      platform: :ios
    }
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.load(@app)
  end
end
