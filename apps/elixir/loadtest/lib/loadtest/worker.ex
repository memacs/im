defmodule IM.LoadTest.Worker do
  @moduledoc "虚拟用户：REST 登录 → WS 建连 AUTH → 场景动作。"

  alias IM.Client
  alias IM.Client.REST
  alias IM.LoadTest.Metrics
  alias IM.LoadTest.UserBootstrap

  @doc """
  执行连接压测单用户。

  返回 `:ok` | `{:error, reason}`。
  """
  @spec run_connection(map()) :: :ok | {:error, term()}
  def run_connection(cfg) do
    t0 = System.monotonic_time(:millisecond)

    with {:ok, session} <- login(cfg),
         ws_url <- ws_url(cfg, session),
         {:ok, client} <- Client.start_link(url: ws_url),
         :ok <- Client.connect(client),
         {:ok, _} <-
           Client.authenticate(client, %{
             app_key: cfg.app_key,
             user_id: cfg.user_id,
             token: session.access_token,
             device_id: cfg.device_id,
             platform: Map.get(cfg, :platform, "loadtest"),
             sdk_ver: Map.get(cfg, :sdk_ver, "0.1.0")
           }) do
      elapsed = System.monotonic_time(:millisecond) - t0
      Metrics.success(:connect_auth, elapsed)
      Client.disconnect(client)
      :ok
    else
      {:error, reason} ->
        Metrics.failure(:connect_auth, reason)
        {:error, reason}
    end
  end

  @doc "未读压测发送方：向对端发送 `iterations` 条消息。"
  @spec run_unread_sender(map()) :: :ok | {:error, term()}
  def run_unread_sender(cfg), do: run_message_flood(cfg)

  @doc "未读压测接收方：拉会话列表，可选 mark_read。"
  @spec run_unread_poll(map(), pos_integer(), non_neg_integer()) :: :ok | {:error, term()}
  def run_unread_poll(cfg, poll_i, read_every) do
    with {:ok, session} <- login(cfg) do
      t0 = System.monotonic_time(:millisecond)

      case REST.list_conversations(cfg.base_url, session.access_token, limit: 50) do
        {:ok, body} ->
          elapsed = System.monotonic_time(:millisecond) - t0
          Metrics.success(:conv_list, elapsed)

          if read_every > 0 and rem(poll_i, read_every) == 0 do
            maybe_mark_read(cfg, session.access_token, body)
          end

          :ok

        {:error, reason} ->
          Metrics.failure(:conv_list, reason)
          {:error, reason}
      end
    else
      {:error, reason} ->
        Metrics.failure(:conv_list, reason)
        {:error, reason}
    end
  end

  @doc "执行消息洪水：登录鉴权后发送 `iterations` 条消息。"
  @spec run_message_flood(map()) :: :ok | {:error, term()}
  def run_message_flood(cfg) do
    iterations = Map.get(cfg, :iterations, 10)
    peer = Map.fetch!(cfg, :peer_user_id)

    with {:ok, session} <- login(cfg),
         ws_url <- ws_url(cfg, session),
         {:ok, client} <- Client.start_link(url: ws_url),
         :ok <- Client.connect(client),
         {:ok, _} <-
           Client.authenticate(client, %{
             app_key: cfg.app_key,
             user_id: cfg.user_id,
             token: session.access_token,
             device_id: cfg.device_id
           }) do
      Enum.each(1..iterations, fn i ->
        t0 = System.monotonic_time(:millisecond)

        result =
          Client.send_message(client, %{
            to: peer,
            content: "lt-#{i}",
            client_msg_id: "lt-#{cfg.user_id}-#{i}-#{System.unique_integer([:positive])}"
          })

        elapsed = System.monotonic_time(:millisecond) - t0

        case result do
          {:ok, _} -> Metrics.success(:msg_send, elapsed)
          {:error, reason} -> Metrics.failure(:msg_send, reason)
        end
      end)

      Client.disconnect(client)
      :ok
    else
      {:error, reason} ->
        Metrics.failure(:connect_auth, reason)
        {:error, reason}
    end
  end

  defp login(cfg) do
    case Map.get(cfg, :access_token) do
      token when is_binary(token) and token != "" ->
        {:ok, %{access_token: token, websocket_urls: Map.get(cfg, :websocket_urls, [])}}

      _ ->
        UserBootstrap.ensure_user(cfg)
    end
  end

  defp ws_url(cfg, session) do
    Map.get(cfg, :ws_url) ||
      List.first(session.websocket_urls) ||
      default_ws(cfg.base_url)
  end

  defp default_ws(base_url) do
    base_url
    |> String.replace_prefix("https://", "wss://")
    |> String.replace_prefix("http://", "ws://")
    |> String.trim_trailing("/")
    |> Kernel.<>("/ws")
  end

  defp maybe_mark_read(_cfg, _token, %{"conversations" => []}), do: :ok
  defp maybe_mark_read(_cfg, _token, %{"conversations" => convs}) when not is_list(convs), do: :ok

  defp maybe_mark_read(cfg, token, %{"conversations" => convs}) do
    conv =
      Enum.find(convs, fn c ->
        is_map(c) and Map.get(c, "unread_count", 0) > 0
      end)

    if conv do
      t0 = System.monotonic_time(:millisecond)

      attrs = %{
        conv_id: conv["conv_id"],
        conv_seq: conv["last_msg_seq"] || conv["last_read_conv_seq"] || 0,
        to: conv["peer_id"],
        msg_id: conv["last_msg_id"],
        chat_type: chat_type_name(conv["chat_type"])
      }

      case REST.mark_read(cfg.base_url, token, attrs) do
        {:ok, _} ->
          Metrics.success(:mark_read, System.monotonic_time(:millisecond) - t0)
          :ok

        {:error, reason} ->
          Metrics.failure(:mark_read, reason)
          {:error, reason}
      end
    else
      :ok
    end
  end

  defp maybe_mark_read(_cfg, _token, _), do: :ok

  defp chat_type_name(n) when is_integer(n) do
    case n do
      2 -> "CHAT_GROUP"
      3 -> "CHAT_ROOM"
      _ -> "CHAT_PRIVATE"
    end
  end

  defp chat_type_name(other) when is_binary(other), do: other
  defp chat_type_name(_), do: "CHAT_PRIVATE"
end
