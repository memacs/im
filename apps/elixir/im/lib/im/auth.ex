defmodule IM.Auth do
  @moduledoc """
  Token 校验 Behaviour。默认实现见 `IM.Auth.TokenVerifier`。

  可通过 `config :im, :auth_verifier, Module` 替换（测试 Mock）。
  """

  alias IM.Domain.Error

  @type claims :: %{
          app_key: String.t(),
          user_id: String.t(),
          device_id: String.t(),
          token_hash: String.t(),
          expires_at: DateTime.t()
        }

  @callback verify_token(String.t()) :: {:ok, claims()} | {:error, Error.t()}

  @doc """
  校验明文 token，委托配置的 verifier。

  ## 示例

      IM.Auth.verify_token(access_token)
  """
  @spec verify_token(String.t()) :: {:ok, claims()} | {:error, Error.t()}
  def verify_token(token) when is_binary(token) do
    verifier().verify_token(token)
  end

  defp verifier do
    Application.get_env(:im, :auth_verifier, IM.Auth.TokenVerifier)
  end
end
