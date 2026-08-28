defmodule IM.ClientProtocolCase do
  @moduledoc """
  im_client 协议 E2E 用例模板。

  - `async: false` + Sandbox shared，供 WebSocket Handler 读库
  - 依赖 `config/test.exs` 中 `server: true` 的 Bandit 监听
  """

  use ExUnit.CaseTemplate

  alias IM.AuthFixtures
  alias IM.Client.{Assertions, Connection}
  alias IM.Client.Protocol.Codec
  alias Pb.Im.Protocol.CmdType

  using do
    quote do
      use ExUnit.Case, async: false

      import IM.ClientProtocolCase

      alias IM.AuthFixtures
      alias IM.Client.{Assertions, Connection, REST}
      alias IM.Client.Protocol.Codec
      alias Pb.Im.Protocol.CmdType
    end
  end

  setup tags do
    IM.DataCase.setup_sandbox(%{async: false})

    if IM.ProtocolTraceRegistry.enabled?() do
      unless tags[:trace_case], do: raise("missing @tag trace_case when TRACE_EXPORT=1")
      Process.put(:trace_case_id, tags[:trace_case])
      Process.put(:trace_step, 0)
      Process.put(:trace_actor, "client")
    end

    :ok
  end

  @doc "HTTP 基址（如 `http://127.0.0.1:4002`）。"
  @spec base_url() :: String.t()
  def base_url, do: Application.fetch_env!(:im, :protocol_e2e_base_url)

  @doc "WebSocket 地址（如 `ws://127.0.0.1:4002/ws`）。"
  @spec ws_url() :: String.t()
  def ws_url, do: Application.fetch_env!(:im, :protocol_e2e_ws_url)

  @doc """
  创建用户、REST 登录并 WS 鉴权。

  返回 `%{client: pid, login: map, auth: map}`。
  """
  @spec connect_authenticated!(map()) :: %{client: pid(), login: map(), auth: map()}
  def connect_authenticated!(attrs \\ %{}) do
    login = AuthFixtures.login!(attrs)

    {:ok, client} = Connection.start_link(url: ws_url())
    on_exit(fn -> if Process.alive?(client), do: Connection.disconnect(client) end)

    :ok = Connection.connect(client)

    {:ok, auth} =
      Connection.authenticate(client, %{
        app_key: login.app_key,
        user_id: login.user_id,
        token: login.token,
        device_id: login.device_id,
        platform: login.platform
      })

    %{client: client, login: login, auth: auth}
  end

  @doc "同 app_key 下启动并鉴权两个客户端。"
  @spec connect_pair!(map(), map()) :: %{a: map(), b: map()}
  def connect_pair!(attrs_a \\ %{}, attrs_b \\ %{}) do
    a = connect_authenticated!(attrs_a)
    app_key = a.login.app_key
    b = connect_authenticated!(Map.put(attrs_b, :app_key, app_key))
    %{a: a, b: b}
  end

  @doc "仅建立 WS 连接，不发送 AUTH。"
  @spec connect_ws_only!() :: pid()
  def connect_ws_only! do
    {:ok, client} = Connection.start_link(url: ws_url())
    on_exit(fn -> if Process.alive?(client), do: Connection.disconnect(client) end)
    :ok = Connection.connect(client)
    client
  end

  @doc "断言服务端静默关连接（无 `CMD_ERROR`）。"
  @spec assert_silent_close!(pid(), timeout()) :: :ok
  def assert_silent_close!(client, timeout \\ 3_000) do
    assert :ok = Connection.await_disconnected(client, timeout)

    assert {:error, :timeout} =
             Connection.await(client, [cmd: CmdType.value(:CMD_ERROR)], 300)

    :ok
  end

  @doc "解码 Packet.payload 为指定 Protobuf 模块。"
  @spec decode_payload!(Pb.Im.Protocol.Packet.t(), module()) :: struct()
  def decode_payload!(packet, mod) do
    {:ok, body} = Codec.decode_payload(packet, mod)
    body
  end

  @doc "断言响应 cmd 并解码 payload。"
  @spec assert_cmd_resp!(Pb.Im.Protocol.Packet.t(), atom(), module()) :: struct()
  def assert_cmd_resp!(packet, cmd_atom, mod) do
    assert packet.cmd == CmdType.value(cmd_atom)
    decode_payload!(packet, mod)
  end

  @doc "发送单聊文本并返回 ACK_DOWN 中的 msg_id。"
  @spec send_private!(pid(), String.t(), String.t(), keyword()) :: {String.t(), String.t()}
  def send_private!(client, from, to, opts \\ []) do
    content = Keyword.get(opts, :content, "hello")
    cid = Keyword.get(opts, :client_msg_id, unique_id("cm"))

    {:ok, packet} =
      Connection.send_message(client, %{
        from: from,
        to: to,
        chat_type: :CHAT_PRIVATE,
        content: content,
        client_msg_id: cid
      })

    ack = assert_cmd_resp!(packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)
    conv_id = IM.Domain.ConvId.private(from, to)
    {ack.msg_id, conv_id}
  end

  @doc "等待 `CMD_MSG_PUSH` 并解码 ChatMessage。"
  @spec await_push_message!(pid(), timeout()) :: Pb.Im.Protocol.ChatMessage.t()
  def await_push_message!(client, timeout \\ 5_000) do
    {:ok, packet} = Assertions.assert_push(client, timeout: timeout)
    decode_payload!(packet, Pb.Im.Protocol.ChatMessage)
  end

  @doc "按已有 login 会话连接并 WS 鉴权（同一用户多设备）。"
  @spec connect_session!(map()) :: %{client: pid(), login: map(), auth: map()}
  def connect_session!(login) when is_map(login) do
    {:ok, client} = Connection.start_link(url: ws_url())
    on_exit(fn -> if Process.alive?(client), do: Connection.disconnect(client) end)
    :ok = Connection.connect(client)

    {:ok, auth} =
      Connection.authenticate(client, %{
        app_key: login.app_key,
        user_id: login.user_id,
        token: login.token,
        device_id: login.device_id,
        platform: login.platform
      })

    %{client: client, login: login, auth: auth}
  end

  @doc "`POST /internal/v1/users/:user_id/kick`。"
  @spec internal_kick_user!(String.t(), keyword()) :: map()
  def internal_kick_user!(user_id, opts \\ []) when is_binary(user_id) do
    app_key = Keyword.fetch!(opts, :app_key)
    url = base_url() <> "/internal/v1/users/#{user_id}/kick"

    assert {:ok, %Req.Response{status: 200, body: body}} =
             Req.post(url,
               json: %{"app_key" => app_key, "reason" => Keyword.get(opts, :reason, "e2e")},
               headers: [
                 {"x-trace-id", unique_id("tr")},
                 {"x-im-caller-service", "protocol-e2e"}
               ],
               receive_timeout: 10_000
             )

    assert is_map(body)
    body
  end

  @doc "将 access_token 的 expires_at 设为过去（测试过期鉴权）。"
  @spec expire_token!(String.t()) :: :ok
  def expire_token!(plain_token) when is_binary(plain_token) do
    past =
      DateTime.utc_now()
      |> DateTime.add(-3600, :second)
      |> DateTime.truncate(:microsecond)

    set_token_expires_at!(plain_token, past)
  end

  @doc "将 access_token 的 expires_at 设为指定时间（测试连接中过期 KICK）。"
  @spec set_token_expires_at!(String.t(), DateTime.t()) :: :ok
  def set_token_expires_at!(plain_token, %DateTime{} = expires_at) when is_binary(plain_token) do
    hash = IM.Auth.Token.hash(plain_token)
    token = IM.Repo.get_by!(IM.Schemas.AccessToken, token_hash: hash)

    token
    |> Ecto.Changeset.change(%{expires_at: expires_at})
    |> IM.Repo.update!()

    :ok
  end

  @doc "断言 AUTH 被拒：同 seq 返回 `CMD_ERROR` 且随后关连接。"
  @spec assert_auth_rejected!(pid(), map(), atom()) :: Pb.Im.Protocol.ErrorBody.t()
  def assert_auth_rejected!(client, attrs, code_atom \\ :CODE_UNAUTHORIZED) do
    attrs = Map.put_new(attrs, :platform, "ios")

    assert {:error, %IM.Client.Error{code: :auth_failed, packet: packet}} =
             Connection.authenticate(client, attrs)

    err = assert_cmd_error!(packet, code_atom)
    assert err.ref_cmd == CmdType.value(:CMD_AUTH_REQ)
    assert :ok = Connection.await_disconnected(client, 3_000)
    err
  end

  @doc "断言 `CMD_ERROR` 并解码 ErrorBody。"
  @spec assert_cmd_error!(Pb.Im.Protocol.Packet.t(), atom() | nil) :: Pb.Im.Protocol.ErrorBody.t()
  def assert_cmd_error!(packet, code_atom \\ nil) do
    assert packet.cmd == CmdType.value(:CMD_ERROR)
    err = decode_payload!(packet, Pb.Im.Protocol.ErrorBody)

    if code_atom do
      assert err.code == code_atom or err.code == Pb.Im.Protocol.ErrorCode.value(code_atom)
    end

    err
  end

  @doc "发送一块 MSG_STREAM 并返回 ACK 的 msg_id。"
  @spec send_stream_chunk!(pid(), String.t(), String.t(), String.t(), atom(), non_neg_integer(), String.t()) ::
          String.t()
  def send_stream_chunk!(client, from, to, stream_id, status, sequence, chunk) do
    body =
      Pb.Im.Protocol.StreamContent.encode(%Pb.Im.Protocol.StreamContent{
        stream_id: stream_id,
        status: status,
        sequence: sequence,
        chunk: chunk,
        content_type: "text/plain"
      })

    {:ok, packet} =
      Connection.send_message(client, %{
        from: from,
        to: to,
        chat_type: :CHAT_PRIVATE,
        msg_type: :MSG_STREAM,
        content: body,
        client_msg_id: unique_id("sm")
      })

    ack = assert_cmd_resp!(packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)
    ack.msg_id
  end

  @doc "`DELETE /api/v1/sessions/current`。"
  @spec logout!(String.t()) :: :ok
  def logout!(token) when is_binary(token) do
    url = base_url() <> "/api/v1/sessions/current"

    assert {:ok, %Req.Response{status: 204}} =
             Req.delete(url,
               headers: [
                 {"x-trace-id", unique_id("tr")},
                 {"authorization", "Bearer #{token}"}
               ],
               receive_timeout: 10_000
             )

    :ok
  end

  @doc "`POST /internal/v1/channels/:ns/:name/publish`。"
  @spec internal_channel_publish!(String.t(), String.t(), keyword()) :: map()
  def internal_channel_publish!(namespace, name, opts \\ []) do
    app_key = Keyword.fetch!(opts, :app_key)
    payload = Keyword.get(opts, :payload, %{"event" => "test"})
    url = base_url() <> "/internal/v1/channels/#{namespace}/#{name}/publish"

    assert {:ok, %Req.Response{status: 200, body: body}} =
             Req.post(url,
               json: %{"app_key" => app_key, "payload" => payload, "content_type" => "application/json"},
               headers: [
                 {"x-trace-id", unique_id("tr")},
                 {"x-im-caller-service", "protocol-e2e"}
               ],
               receive_timeout: 10_000
             )

    assert is_map(body)
    body
  end

  @spec unique_id(String.t()) :: String.t()
  def unique_id(prefix) do
    prefix <> "-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  @doc "设置当前 trace 步骤的 actor 标识（如 A/B/owner）。"
  @spec trace_as!(String.t()) :: :ok
  def trace_as!(actor) when is_binary(actor) do
    Process.put(:trace_actor, actor)
    :ok
  end

  @doc "记录一条 WS 报文或上行 protobuf 结构到 trace 导出。"
  @spec trace!(String.t(), Pb.Im.Protocol.Packet.t() | struct()) :: :ok
  def trace!(direction, %Pb.Im.Protocol.Packet{} = packet) do
    if IM.ProtocolTraceRegistry.enabled?() do
      IM.ProtocolTraceRegistry.record(build_trace_entry!(direction, %{"packet" => IM.ProtocolTrace.to_map(packet)}))
    end

    :ok
  end

  def trace!(direction, struct) when is_struct(struct) do
    if IM.ProtocolTraceRegistry.enabled?() do
      packet = IM.ProtocolTrace.uplink_packet(struct, next_trace_step!())
      trace!(direction, packet)
    else
      :ok
    end
  end

  @doc "记录 HTTP 请求/响应到 trace 导出。"
  @spec trace_http!(String.t(), map(), map()) :: :ok
  def trace_http!(direction, request, response) when is_map(request) do
    if IM.ProtocolTraceRegistry.enabled?() do
      IM.ProtocolTraceRegistry.record(
        build_trace_entry!(direction, %{
          "http" => %{"request" => stringify_keys(request), "response" => stringify_keys(response)}
        })
      )
    end

    :ok
  end

  @doc "记录无 WS 报文的事件（如静默关连接）。"
  @spec trace_event!(String.t(), map()) :: :ok
  def trace_event!(direction, event) when is_map(event) do
    if IM.ProtocolTraceRegistry.enabled?() do
      IM.ProtocolTraceRegistry.record(build_trace_entry!(direction, %{"event" => stringify_keys(event)}))
    end

    :ok
  end

  defp build_trace_entry!(direction, extra) do
    step = next_trace_step!()

    %{
      "step" => step,
      "case" => Process.get(:trace_case_id),
      "actor" => Process.get(:trace_actor, "client"),
      "direction" => direction,
      "note" => direction
    }
    |> Map.merge(extra)
  end

  defp next_trace_step! do
    step = Process.get(:trace_step, 0) + 1
    Process.put(:trace_step, step)
    step
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {to_string(k), stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
