defmodule IM.Auth.Password do
  @moduledoc """
  MVP 密码哈希（无新增 hex 依赖）。

  `hash = SHA-256(password <> ":" <> app_key <> ":" <> user_id)` 的小写 hex。
  """

  @doc """
  计算密码哈希。

  ## 示例

      IM.Auth.Password.hash("secret", "app", "u1")
  """
  @spec hash(String.t(), String.t(), String.t()) :: String.t()
  def hash(password, app_key, user_id)
      when is_binary(password) and is_binary(app_key) and is_binary(user_id) do
    :crypto.hash(:sha256, password <> ":" <> app_key <> ":" <> user_id)
    |> Base.encode16(case: :lower)
  end

  @doc """
  常量时间比较密码是否匹配。

  ## 示例

      hash = IM.Auth.Password.hash("secret", "app", "u1")
      true = IM.Auth.Password.verify("secret", "app", "u1", hash)
  """
  @spec verify(String.t(), String.t(), String.t(), String.t() | nil) :: boolean()
  def verify(_password, _app_key, _user_id, nil), do: false

  def verify(password, app_key, user_id, hash) when is_binary(hash) do
    expected = hash(password, app_key, user_id)
    Plug.Crypto.secure_compare(expected, hash)
  end
end
