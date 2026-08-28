defmodule IM.Hooks.Pipeline do
  @moduledoc """
  Hook 流水线（P9-04）。

  - `pre_send`：同步、可拦截；按配置顺序执行
  - 异常策略：`hooks.on_exception` 为 `:fail_closed`（默认拦截）或 `:fail_open`（记日志后继续）
  """

  require IM.Log

  alias IM.Domain.{Error, MessageContext}
  alias Pb.Im.Protocol.ChatMessage

  @doc """
  执行 pre_send 链，返回可能被改写的消息。

  ## 示例

      {:ok, msg} = IM.Hooks.Pipeline.run_pre_send(msg, ctx)
  """
  @spec run_pre_send(ChatMessage.t(), MessageContext.t()) ::
          {:ok, ChatMessage.t()} | {:error, Error.t()}
  def run_pre_send(%ChatMessage{} = msg, %MessageContext{} = ctx) do
    msg
    |> then(fn m ->
      Enum.reduce_while(pre_send_hooks(), {:ok, m}, fn hook, {:ok, acc} ->
        invoke_pre_send(hook, acc, ctx)
      end)
    end)
  end

  defp invoke_pre_send(hook, msg, ctx) do
    try do
      result =
        cond do
          function_exported?(hook, :pre_send, 2) -> hook.pre_send(msg, ctx)
          function_exported?(hook, :run, 2) -> hook.run(msg, ctx)
          true -> {:error, Error.new(:internal_error, "invalid hook #{inspect(hook)}")}
        end

      case normalize(result, msg) do
        {:ok, new_msg} -> {:cont, {:ok, new_msg}}
        {:error, %Error{} = err} -> {:halt, {:error, err}}
      end
    rescue
      e ->
        IM.Log.error(:internal_error,
          reason: "hook_failed: #{inspect(hook)}: #{Exception.message(e)}"
        )

        case on_exception() do
          :fail_open ->
            {:cont, {:ok, msg}}

          :fail_closed ->
            {:halt, {:error, Error.new(:internal_error, "hook failed: #{inspect(hook)}")}}
        end
    catch
      kind, reason ->
        IM.Log.error(:internal_error,
          reason: "hook_failed: #{inspect(hook)}: #{kind}: #{inspect(reason)}"
        )

        case on_exception() do
          :fail_open ->
            {:cont, {:ok, msg}}

          :fail_closed ->
            {:halt, {:error, Error.new(:internal_error, "hook failed: #{inspect(hook)}")}}
        end
    end
  end

  defp normalize(:ok, msg), do: {:ok, msg}
  defp normalize({:ok, %ChatMessage{} = msg}, _), do: {:ok, msg}
  defp normalize({:error, %Error{} = err}, _), do: {:error, err}

  defp normalize({:error, reason}, _) when is_atom(reason),
    do: {:error, Error.new(reason, Atom.to_string(reason))}

  defp normalize({:error, reason}, _) when is_binary(reason),
    do: {:error, Error.new(:msg_invalid, reason)}

  defp normalize({:reject, reason}, _),
    do: {:error, Error.new(:msg_invalid, "rejected: #{inspect(reason)}")}

  defp normalize(other, _),
    do: {:error, Error.new(:internal_error, "bad hook result: #{inspect(other)}")}

  defp pre_send_hooks do
    cfg = Application.get_env(:im, :hooks, [])
    from_list = Keyword.get(cfg, :pre_send, [])

    legacy =
      case Application.get_env(:im, :pre_send_hook) do
        nil -> []
        mod -> [mod]
      end

    (from_list ++ legacy)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp on_exception do
    cfg = Application.get_env(:im, :hooks, [])

    case Keyword.get(cfg, :on_exception, :fail_closed) do
      :fail_open -> :fail_open
      _ -> :fail_closed
    end
  end
end
