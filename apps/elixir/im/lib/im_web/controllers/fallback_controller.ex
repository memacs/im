defmodule IMWeb.FallbackController do
  @moduledoc "将 `IM.Domain.Error` 映射为 HTTP JSON（与 ErrorBody 语义对齐）。"

  use IMWeb, :controller

  alias IM.Domain.Error
  alias IM.Protocol.ErrorCodes

  @doc false
  def call(conn, {:error, %Error{} = err}) do
    http = http_status(err.code)

    conn
    |> put_status(http)
    |> json(%{
      code: ErrorCodes.to_int(err.code),
      msg: err.msg || "",
      ref_cmd: err.ref_cmd,
      ref_cid: err.ref_cid
    })
  end

  defp http_status(:unauthorized), do: :unauthorized
  defp http_status(:device_limit_exceeded), do: :forbidden
  defp http_status(:msg_invalid), do: :bad_request
  defp http_status(:group_not_found), do: :not_found
  defp http_status(:group_not_member), do: :forbidden
  defp http_status(:group_no_permission), do: :forbidden
  defp http_status(:friend_not_friend), do: :forbidden
  defp http_status(:friend_blocked), do: :forbidden
  defp http_status(:friend_blocked_by_peer), do: :forbidden
  defp http_status(:rate_limited), do: :too_many_requests
  defp http_status(_), do: :internal_server_error
end
