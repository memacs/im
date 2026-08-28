defmodule IM.Services.User do
  @moduledoc """
  用户 provisioning（内部 API / 压测 / 冒烟用）。

  公开 REST 登录仍要求用户已存在；运维与 loadtest 经 `POST /internal/v1/users/:id/provision` 预置。
  """

  alias IM.Auth.Password
  alias IM.Domain.Error
  alias IM.Stores.UserStore

  @doc """
  插入或更新用户密码（幂等）。

  ## 参数

  - `"app_key"` / `"user_id"` / `"password"` 必填
  - `"nickname"` 可选
  """
  @spec provision(map()) :: {:ok, map()} | {:error, Error.t()}
  def provision(params) when is_map(params) do
    with {:ok, fields} <- cast(params) do
      UserStore.ensure(%{
        app_key: fields.app_key,
        user_id: fields.user_id,
        password_hash: Password.hash(fields.password, fields.app_key, fields.user_id),
        nickname: fields.nickname
      })
    end
  end

  defp cast(params) do
    required = ["app_key", "user_id", "password"]

    missing =
      Enum.reject(required, &(present?(params[&1]) or present?(params[String.to_atom(&1)])))

    if missing != [] do
      {:error, Error.new(:msg_invalid, "missing fields: #{Enum.join(missing, ",")}")}
    else
      {:ok,
       %{
         app_key: fetch(params, "app_key"),
         user_id: fetch(params, "user_id"),
         password: fetch(params, "password"),
         nickname: fetch(params, "nickname", fetch(params, "user_id"))
       }}
    end
  end

  defp fetch(params, key, default \\ nil) do
    Map.get(params, key) || Map.get(params, String.to_atom(key)) || default
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(_), do: false
end
