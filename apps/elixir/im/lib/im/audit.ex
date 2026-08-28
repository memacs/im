defmodule IM.Audit do
  @moduledoc """
  业务审计异步落库（DD-028 / auth-module §8）。

  与 stdout `IM.Log` 分离；主路径仅投递 Task，不阻塞 ACK。
  """

  require IM.Log

  alias IM.Repo
  alias IM.Schemas.AuditLog

  @doc """
  记录审计事件。默认经 `IM.TaskSupervisor` 异步插入。

  ## 示例

      IM.Audit.record(:auth_login,
        app_key: "demo",
        user_id: "u1",
        device_id: "d1",
        result: :success,
        strategy: "token"
      )
  """
  @spec record(atom(), keyword()) :: :ok
  def record(event, fields \\ []) when is_atom(event) and is_list(fields) do
    attrs = build_attrs(event, fields)

    if Application.get_env(:im, :audit_sync, false) do
      persist(attrs)
    else
      _ =
        Task.Supervisor.start_child(IM.TaskSupervisor, fn ->
          persist(attrs)
        end)
    end

    :ok
  end

  defp build_attrs(event, fields) do
    %{
      event: Atom.to_string(event),
      app_key: blank_to_nil(fields[:app_key]),
      user_id: blank_to_nil(fields[:user_id]),
      device_id: blank_to_nil(fields[:device_id]),
      strategy: fields[:strategy] && to_string(fields[:strategy]),
      result: normalize_result(fields[:result]),
      reason: fields[:reason] && fields[:reason] |> to_string() |> String.slice(0, 256),
      client_ip: blank_to_nil(fields[:client_ip]),
      user_agent: blank_to_nil(fields[:user_agent]),
      created_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp persist(attrs) do
    case %AuditLog{} |> AuditLog.changeset(attrs) |> Repo.insert() do
      {:ok, _} ->
        :ok

      {:error, changeset} ->
        IM.Log.error(:internal_error,
          reason: "audit_insert_failed: #{inspect(changeset.errors)}"
        )
    end
  end

  defp normalize_result(:success), do: "success"
  defp normalize_result(:failure), do: "failure"
  defp normalize_result(r) when is_binary(r), do: r
  defp normalize_result(r) when is_atom(r), do: Atom.to_string(r)
  defp normalize_result(_), do: "unknown"

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v) when is_binary(v), do: v
  defp blank_to_nil(v), do: to_string(v)
end
