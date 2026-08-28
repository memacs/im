defmodule IM.Client.REST do
  @moduledoc """
  HTTP 辅助：登录与 REST 发消息。
  """

  alias IM.Client.Error

  @doc """
  创建会话。

  ## 参数

  - `base_url`：如 `"http://localhost:4000"`
  - `attrs`：`app_key` / `user_id` / `password` / `device_id` / `platform` / `sdk_ver`
  """
  @spec create_session(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_session(base_url, attrs) when is_binary(base_url) and is_map(attrs) do
    url = String.trim_trailing(base_url, "/") <> "/api/v1/sessions"
    trace_id = Map.get(attrs, :trace_id, Map.get(attrs, "trace_id", generate_trace()))

    body = %{
      app_key: fetch(attrs, :app_key),
      user_id: fetch(attrs, :user_id),
      password: fetch(attrs, :password),
      device_id: fetch(attrs, :device_id, "im-client"),
      platform: fetch(attrs, :platform, "loadtest"),
      sdk_ver: fetch(attrs, :sdk_ver, "0.1.0")
    }

    case Req.post(url,
           json: body,
           headers: [{"x-trace-id", trace_id}, {"content-type", "application/json"}],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        token = body["access_token"] || body[:access_token]
        conn = body["connection"] || body[:connection] || %{}
        urls = conn["websocket_urls"] || conn[:websocket_urls] || []

        if is_binary(token) and token != "" do
          {:ok, %{access_token: token, websocket_urls: List.wrap(urls), raw: body}}
        else
          {:error, Error.new(:login_failed, "missing access_token")}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, Error.new(:login_failed, "status=#{status} body=#{inspect(body)}")}

      {:error, reason} ->
        {:error, Error.new(:login_failed, inspect(reason))}
    end
  end

  @doc "`POST /api/v1/messages`。"
  @spec send_message(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def send_message(base_url, access_token, attrs)
      when is_binary(base_url) and is_binary(access_token) and is_map(attrs) do
    url = String.trim_trailing(base_url, "/") <> "/api/v1/messages"
    trace_id = Map.get(attrs, :trace_id, Map.get(attrs, "trace_id", generate_trace()))

    body =
      %{
        to: fetch(attrs, :to),
        content: fetch(attrs, :content, "ping"),
        client_msg_id: fetch(attrs, :client_msg_id, generate_cid()),
        chat_type: fetch(attrs, :chat_type, "CHAT_PRIVATE"),
        conv_id: fetch(attrs, :conv_id, "")
      }
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
      |> Map.new()

    case Req.post(url,
           json: body,
           headers: [
             {"x-trace-id", trace_id},
             {"authorization", "Bearer #{access_token}"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: resp}} when is_map(resp) ->
        {:ok, resp}

      {:ok, %{status: status, body: body}} ->
        {:error, Error.new(:rest_send_failed, "status=#{status} body=#{inspect(body)}")}

      {:error, reason} ->
        {:error, Error.new(:rest_send_failed, inspect(reason))}
    end
  end

  @doc "`POST /internal/v1/users/:user_id/provision`（需 `X-IM-Caller-Service`）。"
  @spec provision_user(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def provision_user(base_url, attrs) when is_binary(base_url) and is_map(attrs) do
    user_id = fetch(attrs, :user_id)
    url = String.trim_trailing(base_url, "/") <> "/internal/v1/users/#{user_id}/provision"
    trace_id = Map.get(attrs, :trace_id, Map.get(attrs, "trace_id", generate_trace()))
    caller = fetch(attrs, :caller_service, "loadtest")

    body = %{
      app_key: fetch(attrs, :app_key),
      user_id: user_id,
      password: fetch(attrs, :password),
      nickname: fetch(attrs, :nickname, user_id)
    }

    case Req.post(url,
           json: body,
           headers: [
             {"x-trace-id", trace_id},
             {"x-im-caller-service", caller},
             {"content-type", "application/json"}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, Error.new(:rest_failed, "status=#{status} body=#{inspect(body)}")}
      {:error, reason} -> {:error, Error.new(:rest_failed, inspect(reason))}
    end
  end

  @doc "`GET /api/v1/conversations`。"
  @spec list_conversations(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_conversations(base_url, access_token, opts \\ [])
      when is_binary(base_url) and is_binary(access_token) do
    limit = Keyword.get(opts, :limit, 100)
    trace_id = Keyword.get(opts, :trace_id, generate_trace())

    url =
      String.trim_trailing(base_url, "/") <>
        "/api/v1/conversations?" <> URI.encode_query(%{"limit" => limit})

    case Req.get(url,
           headers: [
             {"x-trace-id", trace_id},
             {"authorization", "Bearer #{access_token}"}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, Error.new(:rest_failed, "status=#{status} body=#{inspect(body)}")}
      {:error, reason} -> {:error, Error.new(:rest_failed, inspect(reason))}
    end
  end

  @doc "`POST /api/v1/messages/read`。"
  @spec mark_read(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def mark_read(base_url, access_token, attrs)
      when is_binary(base_url) and is_binary(access_token) and is_map(attrs) do
    url = String.trim_trailing(base_url, "/") <> "/api/v1/messages/read"
    trace_id = Map.get(attrs, :trace_id, Map.get(attrs, "trace_id", generate_trace()))

    body = %{
      conv_id: fetch(attrs, :conv_id),
      conv_seq: fetch(attrs, :conv_seq),
      to: fetch(attrs, :to),
      msg_id: fetch(attrs, :msg_id),
      chat_type: fetch(attrs, :chat_type, "CHAT_PRIVATE")
    }

    case Req.post(url,
           json: body,
           headers: [
             {"x-trace-id", trace_id},
             {"authorization", "Bearer #{access_token}"},
             {"content-type", "application/json"}
           ],
           receive_timeout: 15_000
         ) do
      {:ok, %{status: 200, body: resp}} when is_map(resp) -> {:ok, resp}
      {:ok, %{status: status, body: body}} -> {:error, Error.new(:rest_failed, "status=#{status} body=#{inspect(body)}")}
      {:error, reason} -> {:error, Error.new(:rest_failed, inspect(reason))}
    end
  end

  defp fetch(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp generate_trace do
    "lt-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end

  defp generate_cid do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
