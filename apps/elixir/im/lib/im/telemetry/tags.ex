defmodule IM.Telemetry.Tags do
  @moduledoc """
  低基数公共标签：`host` / `node`，以及 cmd / msg_type 规范化。
  """

  alias IM.Protocol.Cmd

  @doc """
  Pod / 宿主机名。

  ## 示例

      IM.Telemetry.Tags.host()
  """
  @spec host() :: String.t()
  def host do
    case System.get_env("HOSTNAME") do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        case :inet.gethostname() do
          {:ok, n} -> List.to_string(n)
          _ -> "unknown"
        end
    end
  end

  @doc """
  BEAM 节点名字符串。

  ## 示例

      IM.Telemetry.Tags.node_name()
  """
  @spec node_name() :: String.t()
  def node_name, do: Node.self() |> Atom.to_string()

  @doc """
  cmd 数值 → 枚举名字符串；未知则数字字符串。

  ## 示例

      "CMD_MSG_SEND" = IM.Telemetry.Tags.cmd_name(100)
  """
  @spec cmd_name(non_neg_integer() | atom() | String.t()) :: String.t()
  def cmd_name(cmd) when is_atom(cmd), do: Atom.to_string(cmd)
  def cmd_name(cmd) when is_binary(cmd), do: cmd

  def cmd_name(cmd) when is_integer(cmd) do
    case Cmd.to_atom(cmd) do
      {:ok, atom} -> Atom.to_string(atom)
      _ -> Integer.to_string(cmd)
    end
  end

  @doc """
  规范化 msg_type 标签（原子/数字/字符串 → 字符串；空为 `"none"`）。

  ## 示例

      "MSG_TEXT" = IM.Telemetry.Tags.msg_type_name(:MSG_TEXT)
  """
  @spec msg_type_name(term()) :: String.t()
  def msg_type_name(nil), do: "none"
  def msg_type_name(:none), do: "none"
  def msg_type_name("none"), do: "none"
  def msg_type_name(t) when is_atom(t), do: Atom.to_string(t)
  def msg_type_name(t) when is_binary(t) and t != "", do: t
  def msg_type_name(t) when is_integer(t), do: Integer.to_string(t)
  def msg_type_name(_), do: "unknown"

  @doc """
  包类指标公共 metadata。

  ## 示例

      IM.Telemetry.Tags.packet_meta(100, :up, :none)
  """
  @spec packet_meta(term(), :up | :down, term()) :: map()
  def packet_meta(cmd, direction, msg_type \\ :none)
      when direction in [:up, :down] do
    %{
      cmd: cmd_name(cmd),
      direction: direction,
      msg_type: msg_type_name(msg_type),
      host: host(),
      node: node_name()
    }
  end
end
