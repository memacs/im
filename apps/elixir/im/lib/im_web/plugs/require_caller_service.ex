defmodule IMWeb.Plugs.RequireCallerService do
  @moduledoc """
  内部 API：校验 `X-IM-Caller-Service`（格式 + 允许/封禁名单）。

  见 `docs/design/dual-channel-api.md` §4.4.2。
  """

  import Plug.Conn

  @behaviour Plug

  @caller_re ~r/^[a-z0-9][a-z0-9-]{0,63}$/

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_req_header(conn, "x-im-caller-service") do
      [caller] when is_binary(caller) ->
        caller = String.trim(caller) |> String.downcase()

        cond do
          caller == "" ->
            reject(conn, "missing_caller_service")

          not Regex.match?(@caller_re, caller) ->
            reject(conn, "invalid_caller_service")

          blocked?(caller) ->
            reject(conn, "caller_blocked", :forbidden)

          not allowed?(caller) ->
            reject(conn, "caller_not_allowed", :forbidden)

          true ->
            conn
            |> assign(:caller_service, caller)
            |> assign(:client_ip, client_ip(conn))
        end

      _ ->
        reject(conn, "missing_caller_service")
    end
  end

  defp allowed?(caller) do
    case Keyword.get(cfg(), :allowed_callers, :any) do
      :any -> true
      list when is_list(list) -> caller in Enum.map(list, &to_string/1)
      _ -> true
    end
  end

  defp blocked?(caller) do
    blocked = Keyword.get(cfg(), :blocked_callers, [])
    caller in Enum.map(blocked, &to_string/1)
  end

  defp cfg, do: Application.get_env(:im, :internal_api, [])

  defp client_ip(conn) do
    case conn.remote_ip do
      ip when is_tuple(ip) -> ip |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  defp reject(conn, msg, status \\ :bad_request) do
    code = if status == :forbidden, do: 403, else: 400

    conn
    |> put_status(status)
    |> Phoenix.Controller.json(%{code: code, msg: msg})
    |> halt()
  end
end
