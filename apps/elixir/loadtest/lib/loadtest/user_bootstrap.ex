defmodule IM.LoadTest.UserBootstrap do
  @moduledoc """
  压测用户预置：内部 provision + REST 登录。

  loadtest 不依赖 `:im`，经 `POST /internal/v1/users/:id/provision` 创建用户。
  """

  alias IM.Client.REST

  @doc "确保单个用户存在并返回会话。"
  @spec ensure_user(map()) :: {:ok, map()} | {:error, term()}
  def ensure_user(cfg) when is_map(cfg) do
    base_url = Map.fetch!(cfg, :base_url)
    app_key = Map.fetch!(cfg, :app_key)
    user_id = Map.fetch!(cfg, :user_id)
    password = Map.get(cfg, :password, "password")
    device_id = Map.get(cfg, :device_id, "lt-dev")

    with :ok <- provision(base_url, app_key, user_id, password),
         {:ok, session} <-
           REST.create_session(base_url, %{
             app_key: app_key,
             user_id: user_id,
             password: password,
             device_id: device_id,
             platform: Map.get(cfg, :platform, "loadtest"),
             sdk_ver: Map.get(cfg, :sdk_ver, "0.1.0")
           }) do
      {:ok, session}
    end
  end

  @doc "批量 ensure，按 user_id 去重。"
  @spec ensure_users([map()]) :: :ok | {:error, term()}
  def ensure_users(configs) when is_list(configs) do
    configs
    |> Enum.uniq_by(& &1.user_id)
    |> Enum.reduce_while(:ok, fn cfg, :ok ->
      case ensure_user(cfg) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec provision(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def provision(base_url, app_key, user_id, password) do
    case REST.provision_user(base_url, %{
           app_key: app_key,
           user_id: user_id,
           password: password,
           nickname: user_id
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
