defmodule IM.LoadTest.Scenarios.RoomBroadcast do
  @moduledoc "聊天室广播压测（LT-32）：建室 → JOIN → `CHAT_ROOM` SEND。"

  alias IM.Client
  alias IM.Client.Protocol.Codec
  alias IM.Client.REST
  alias IM.LoadTest.{Metrics, Reporter, UserBootstrap}
  alias Pb.Im.Protocol.RoomCreateResp

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    users = Keyword.get(opts, :users, 10)
    iterations = Keyword.get(opts, :iterations, 5)
    app_key = Keyword.fetch!(opts, :app_key)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    password = Keyword.get(opts, :password, "password")
    prefix = Keyword.get(opts, :user_prefix, "lt_rb_")

    Metrics.reset()
    t0 = System.monotonic_time(:millisecond)

    owner_id = "#{prefix}owner"
    member_ids = for i <- 1..users, do: "#{prefix}#{i}"

    with :ok <- ensure_users(base_url, app_key, password, member_ids),
         {:ok, session} <-
           REST.create_session(base_url, %{
             app_key: app_key,
             user_id: owner_id,
             password: password,
             device_id: "rb-owner"
           }),
         ws_url <-
           hd(
             List.wrap(session.websocket_urls) ++
               [Keyword.get(opts, :ws_url, "ws://localhost:4000/ws")]
           ),
         {:ok, client} <- Client.start_link(url: ws_url),
         :ok <- Client.connect(client),
         {:ok, _} <-
           Client.authenticate(client, %{
             app_key: app_key,
             user_id: owner_id,
             token: session.access_token,
             device_id: "rb-owner"
           }),
         {:ok, create_pkt} <-
           Client.create_room(client, %{name: "rb-#{System.unique_integer([:positive])}"}),
         {:ok, room_id} <- room_id_from(create_pkt),
         {:ok, _} <- Client.join_room(client, room_id) do
      Enum.each(1..iterations, fn i ->
        t = System.monotonic_time(:millisecond)

        result =
          Client.send_message(client, %{
            to: room_id,
            content: "rb-#{i}",
            chat_type: :CHAT_ROOM,
            client_msg_id: "rb-#{i}-#{System.unique_integer([:positive])}"
          })

        elapsed = System.monotonic_time(:millisecond) - t

        case result do
          {:ok, _} -> Metrics.success(:room_broadcast_send, elapsed)
          {:error, reason} -> Metrics.failure(:room_broadcast_send, reason)
        end
      end)

      Client.disconnect(client)
      duration = System.monotonic_time(:millisecond) - t0
      report = Reporter.build("room_broadcast", duration, Metrics.snapshot())
      Reporter.write!(report, Keyword.get(opts, :report_path))
      {:ok, report}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_users(base_url, app_key, password, user_ids) do
    configs =
      for uid <- user_ids do
        %{
          base_url: base_url,
          app_key: app_key,
          user_id: uid,
          password: password,
          device_id: "rb-#{uid}"
        }
      end

    UserBootstrap.ensure_users(configs)
  end

  defp room_id_from(packet) do
    case Codec.decode_payload(packet, RoomCreateResp) do
      {:ok, %{room_id: id}} when is_binary(id) and id != "" -> {:ok, id}
      other -> {:error, {:bad_room_create, other}}
    end
  end
end
