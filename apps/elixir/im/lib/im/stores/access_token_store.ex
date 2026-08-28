defmodule IM.Stores.AccessTokenStore do
  @moduledoc "access_tokens 表访问。"

  import Ecto.Query

  alias IM.Auth.TokenCache
  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.AccessToken

  @doc """
  按 hash 查找未删除行。

  ## 示例

      IM.Stores.AccessTokenStore.get_by_hash(hash)
  """
  @spec get_by_hash(String.t()) :: {:ok, AccessToken.t()} | {:error, Error.t()}
  def get_by_hash(token_hash) when is_binary(token_hash) do
    case Repo.get_by(AccessToken, token_hash: token_hash) do
      nil -> {:error, Error.new(:unauthorized, "token not found")}
      token -> {:ok, token}
    end
  end

  @doc """
  插入新 token 行。

  ## 示例

      IM.Stores.AccessTokenStore.insert(%{...})
  """
  @spec insert(map()) :: {:ok, AccessToken.t()} | {:error, Error.t()}
  def insert(attrs) when is_map(attrs) do
    %AccessToken{}
    |> AccessToken.changeset(attrs)
    |> Repo.insert()
    |> wrap()
  end

  @doc """
  吊销单条 token（按 hash）。

  ## 示例

      IM.Stores.AccessTokenStore.revoke_hash(hash)
  """
  @spec revoke_hash(String.t()) :: :ok | {:error, Error.t()}
  def revoke_hash(token_hash) when is_binary(token_hash) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {_, _} =
      from(t in AccessToken,
        where: t.token_hash == ^token_hash and is_nil(t.revoked_at)
      )
      |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    :ok = TokenCache.revoke_hash(token_hash)
    :ok
  end

  @doc """
  吊销设备全部有效 token。

  ## 示例

      IM.Stores.AccessTokenStore.revoke_device("a", "u", "d")
  """
  @spec revoke_device(String.t(), String.t(), String.t()) :: :ok
  def revoke_device(app_key, user_id, device_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    from(t in AccessToken,
      where:
        t.app_key == ^app_key and t.user_id == ^user_id and t.device_id == ^device_id and
          is_nil(t.revoked_at)
    )
    |> Repo.update_all(set: [revoked_at: now, updated_at: now])

    :ok = TokenCache.revoke_device(app_key, user_id, device_id)
    :ok
  end

  defp wrap({:ok, row}), do: {:ok, row}

  defp wrap({:error, %Ecto.Changeset{} = cs}) do
    {:error, Error.new(:internal_error, inspect(cs.errors))}
  end
end
