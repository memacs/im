defmodule IM.LoadTest.Scenarios.GroupFanout do
  @moduledoc """
  大群扇出压测（LT-30 / P10-02）：建群 → `CHAT_GROUP` SEND。

  默认小规模本地可跑；5000 人群 P99 < 200ms 需目标环境实测。
  """

  alias IM.Client
  alias IM.Client.Protocol.Codec
  alias IM.Client.REST
  alias IM.LoadTest.{Metrics, Reporter, UserBootstrap}
  alias Pb.Im.Protocol.GroupCreateResp

  @doc """
  运行 group_fanout。

  ## opts

  - `:users` — 成员数（默认 20；大群用 5000）
  - `:iterations` — 群主发送条数
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    users = Keyword.get(opts, :users, 20)
    iterations = Keyword.get(opts, :iterations, 5)
    app_key = Keyword.fetch!(opts, :app_key)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    password = Keyword.get(opts, :password, "password")
    prefix = Keyword.get(opts, :user_prefix, "lt_gf_")

    Metrics.reset()
    t0 = System.monotonic_time(:millisecond)

    owner_id = "#{prefix}owner"
    member_ids = for i <- 1..users, do: "#{prefix}#{i}"

    with :ok <- ensure_users(base_url, app_key, password, [owner_id | member_ids]),
         {:ok, owner_session} <-
           REST.create_session(base_url, %{
             app_key: app_key,
             user_id: owner_id,
             password: password,
             device_id: "gf-owner"
           }),
         ws_url <-
           (List.wrap(owner_session.websocket_urls) ++
              [Keyword.get(opts, :ws_url), "ws://localhost:4000/ws"])
           |> Enum.find(&(is_binary(&1) and &1 != "")),
         {:ok, owner} <- Client.start_link(url: ws_url),
         :ok <- Client.connect(owner),
         {:ok, _} <-
           Client.authenticate(owner, %{
             app_key: app_key,
             user_id: owner_id,
             token: owner_session.access_token,
             device_id: "gf-owner"
           }),
         {:ok, create_pkt} <-
           Client.create_group(owner, %{
             name: "gf-#{System.unique_integer([:positive])}",
             member_uids: member_ids
           }),
         {:ok, group_id} <- group_id_from(create_pkt) do
      Enum.each(1..iterations, fn i ->
        t = System.monotonic_time(:millisecond)

        result =
          Client.send_message(owner, %{
            to: group_id,
            chat_type: :CHAT_GROUP,
            content: "gf-#{i}",
            client_msg_id: "gf-#{i}-#{System.unique_integer([:positive])}"
          })

        elapsed = System.monotonic_time(:millisecond) - t

        case result do
          {:ok, _} -> Metrics.success(:group_fanout_send, elapsed)
          {:error, reason} -> Metrics.failure(:group_fanout_send, reason)
        end
      end)

      Client.disconnect(owner)
      duration = System.monotonic_time(:millisecond) - t0
      report = Reporter.build("group_fanout", duration, Metrics.snapshot())
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
          device_id: "gf-#{uid}"
        }
      end

    UserBootstrap.ensure_users(configs)
  end

  defp group_id_from(packet) do
    case Codec.decode_payload(packet, GroupCreateResp) do
      {:ok, %{group_id: id}} when is_binary(id) and id != "" -> {:ok, id}
      other -> {:error, {:bad_group_create, other}}
    end
  end
end
