defmodule IM.Log do
  @moduledoc """
  结构化日志统一入口（DD-028 §2.6）。

  对外 API 为**宏**，经 `__CALLER__` 注入调用点；生产仅白名单 event，
  `auth_failed` / `rate_limited` 经 `IM.Log.RateLimit` 采样。
  """

  require Logger

  alias IM.Domain.MessageContext

  @prod_allowed ~w(
    packet_decode_error storage_failed push_failed cluster_dispatch_failed
    handler_crash internal_error packet_error auth_failed rate_limited
    channel_subscribe_denied channel_publish_dropped channel_push_failed
  )a

  @doc """
  把上下文写入当前进程 Logger metadata。

  ## 示例

      IM.Log.put_context(ctx)
  """
  @spec put_context(MessageContext.t()) :: :ok
  def put_context(%MessageContext{} = ctx) do
    Logger.metadata(
      trace_id: ctx.trace_id,
      app_key: ctx.app_key,
      user_id: ctx.user_id,
      device_id: ctx.device_id,
      session_id: ctx.session_id
    )

    :ok
  end

  @doc """
  返回当前进程链路字段。

  ## 示例

      IM.Log.context_metadata()
  """
  @spec context_metadata() :: keyword()
  def context_metadata do
    Logger.metadata()
    |> Keyword.take([:trace_id, :app_key, :user_id, :device_id, :session_id])
  end

  defmacro info(event, fields \\ []) do
    expand_log(:info, event, fields, __CALLER__)
  end

  defmacro warning(event, fields \\ []) do
    expand_log(:warning, event, fields, __CALLER__)
  end

  defmacro error(event, fields \\ []) do
    expand_log(:error, event, fields, __CALLER__)
  end

  defmacro debug(event, fields \\ []) do
    expand_log(:debug, event, fields, __CALLER__)
  end

  defp expand_log(level, event, fields, %Macro.Env{} = env) do
    module = env.module
    file = env.file
    line = env.line

    quote bind_quoted: [
            level: level,
            event: event,
            fields: fields,
            module: module,
            file: file,
            line: line
          ] do
      IM.Log.__log__(level, event, fields, %{module: module, file: file, line: line})
    end
  end

  @doc false
  @spec __log__(atom(), atom(), keyword() | map(), map()) :: :ok
  def __log__(level, event, fields, caller) when is_atom(event) and is_map(caller) do
    fields =
      fields
      |> normalize_fields()
      |> caller_fields(caller)
      |> trim_reason()

    # Elixir 1.19+：`Logger.enabled?/1` 仅接受 pid；用级别比较判断是否值得构造 metadata
    if level_enabled?(level) and allowed?(level, event) and sample?(event, fields) do
      metadata = Keyword.put(fields, :event, event)
      Logger.log(level, fn -> Atom.to_string(event) end, metadata)
    end

    :ok
  end

  defp normalize_fields(fields) when is_list(fields), do: fields

  defp normalize_fields(fields) when is_map(fields) do
    Enum.map(fields, fn {k, v} -> {k, v} end)
  end

  defp caller_fields(fields, %{module: module, file: file, line: line}) do
    Keyword.merge(fields,
      caller_module: module,
      caller_file: Path.basename(file),
      caller_line: line
    )
  end

  defp level_enabled?(level) do
    Logger.compare_levels(level, Logger.level()) != :lt
  end

  defp allowed?(:info, _event), do: not prod?()
  defp allowed?(:debug, _event), do: not prod?()

  defp allowed?(level, event) when level in [:warning, :error] do
    not prod?() or event in @prod_allowed
  end

  defp allowed?(_, _), do: true

  defp prod?, do: Application.get_env(:im, :env) == :prod

  defp sample?(:auth_failed, fields), do: IM.Log.RateLimit.allow?(:auth_failed, fields)
  defp sample?(:rate_limited, fields), do: IM.Log.RateLimit.allow?(:rate_limited, fields)

  defp sample?(:channel_publish_dropped, fields),
    do: IM.Log.RateLimit.allow?(:rate_limited, fields)

  defp sample?(_, _), do: true

  defp trim_reason(fields) do
    case Keyword.fetch(fields, :reason) do
      {:ok, reason} when is_binary(reason) ->
        Keyword.put(fields, :reason, String.slice(reason, 0, 200))

      {:ok, reason} ->
        Keyword.put(fields, :reason, reason |> inspect() |> String.slice(0, 200))

      :error ->
        fields
    end
  end
end
