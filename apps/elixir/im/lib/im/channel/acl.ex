defmodule IM.Channel.ACL do
  @moduledoc """
  App Channel 权限：channel_id 格式校验与默认策略。

  见 `docs/design/app-channel.md` §9。
  """

  alias IM.Domain.Error

  @channel_id_re ~r/^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$/

  @doc """
  校验业务 channel_id（`{namespace}:{name}`）。

  ## 示例

      :ok = IM.Channel.ACL.validate_channel_id("fleet:alert")
  """
  @spec validate_channel_id(String.t()) :: :ok | {:error, Error.t()}
  def validate_channel_id(id) when is_binary(id) do
    if Regex.match?(@channel_id_re, id) do
      :ok
    else
      {:error, Error.new(:channel_not_found, "invalid channel_id: #{id}")}
    end
  end

  def validate_channel_id(_), do: {:error, Error.new(:channel_not_found, "invalid channel_id")}

  @doc """
  是否允许订阅。

  ## 示例

      :ok = IM.Channel.ACL.allow_subscribe?("demo", "fleet:alert", "u1")
  """
  @spec allow_subscribe?(String.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def allow_subscribe?(app_key, channel_id, _user_id)
      when is_binary(app_key) and is_binary(channel_id) do
    with :ok <- validate_channel_id(channel_id) do
      if cfg(:subscribe_default, true) do
        :ok
      else
        {:error, Error.new(:channel_no_permission, "subscribe denied")}
      end
    end
  end

  @doc """
  是否允许客户端上行。

  ## 示例

      :ok = IM.Channel.ACL.allow_client_publish?("demo", "fleet:alert", "u1")
  """
  @spec allow_client_publish?(String.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def allow_client_publish?(app_key, channel_id, _user_id)
      when is_binary(app_key) and is_binary(channel_id) do
    with :ok <- validate_channel_id(channel_id) do
      if cfg(:client_publish_default, true) do
        :ok
      else
        {:error, Error.new(:channel_no_permission, "client publish denied")}
      end
    end
  end

  @doc """
  是否允许内部下行（按 caller 白名单）。

  ## 示例

      :ok = IM.Channel.ACL.allow_internal_publish?("demo", "fleet:alert", "ops")
  """
  @spec allow_internal_publish?(String.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def allow_internal_publish?(app_key, channel_id, caller)
      when is_binary(app_key) and is_binary(channel_id) and is_binary(caller) do
    with :ok <- validate_channel_id(channel_id) do
      callers = cfg(:internal_callers, :any)

      cond do
        callers == :any ->
          :ok

        is_list(callers) and caller in callers ->
          :ok

        true ->
          {:error, Error.new(:channel_no_permission, "caller not allowed")}
      end
    end
  end

  defp cfg(key, default) do
    :im
    |> Application.get_env(:channel_acl, [])
    |> Keyword.get(key, default)
  end
end
