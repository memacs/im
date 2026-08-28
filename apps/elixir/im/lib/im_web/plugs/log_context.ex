defmodule IMWeb.Plugs.LogContext do
  @moduledoc """
  将 REST 请求上下文写入 Logger metadata（DD-028 §2.6）。
  """

  @behaviour Plug

  alias IM.Domain.MessageContext

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{assigns: assigns} = conn, _opts) do
    case Map.get(assigns, :message_context) do
      %MessageContext{} = ctx ->
        IM.Log.put_context(ctx)

      _ ->
        trace_id = Map.get(assigns, :trace_id)

        if is_binary(trace_id) and trace_id != "" do
          IM.Log.put_trace_id(trace_id)
        end
    end

    conn
  end
end
