defmodule IM.Auth.Token do
  @moduledoc "不透明 access_token 的生成与 hash。"

  @doc """
  生成 URL-safe 明文 token。

  ## 示例

      token = IM.Auth.Token.generate()
      is_binary(token)
  """
  @spec generate() :: String.t()
  def generate do
    Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  @doc """
  SHA-256 hex（小写）作为库内存储键。

  ## 示例

      IM.Auth.Token.hash("abc")
  """
  @spec hash(String.t()) :: String.t()
  def hash(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end
end
