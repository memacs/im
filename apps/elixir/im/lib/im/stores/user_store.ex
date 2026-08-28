defmodule IM.Stores.UserStore do
  @moduledoc "用户读写。"

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.User

  @doc """
  按租户用户 ID 查找。

  ## 示例

      IM.Stores.UserStore.get("app", "u1")
  """
  @spec get(String.t(), String.t()) :: {:ok, User.t()} | {:error, Error.t()}
  def get(app_key, user_id) do
    case Repo.get_by(User, app_key: app_key, user_id: user_id) do
      nil -> {:error, Error.new(:unauthorized, "user not found")}
      user -> {:ok, user}
    end
  end

  @doc """
  插入或按唯一键返回已有用户（测试/种子用）。

  ## 示例

      {:ok, user} = IM.Stores.UserStore.ensure(%{app_key: "a", user_id: "u", password_hash: "x"})
  """
  @spec ensure(map()) :: {:ok, User.t()} | {:error, Error.t()}
  def ensure(attrs) when is_map(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:password_hash, :nickname, :updated_at]},
      conflict_target: [:app_key, :user_id],
      returning: true
    )
    |> wrap_changeset()
  end

  defp wrap_changeset({:ok, user}), do: {:ok, user}

  defp wrap_changeset({:error, %Ecto.Changeset{} = cs}) do
    {:error, Error.new(:msg_invalid, inspect(cs.errors))}
  end
end
