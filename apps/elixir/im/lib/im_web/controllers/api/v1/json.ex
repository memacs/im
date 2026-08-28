defmodule IMWeb.Api.V1.Json do
  @moduledoc "将 Dispatch/Service 结果转为 REST JSON（proto 字段语义）。"

  @doc "递归把 struct / list / map 转为可 JSON 编码的值。"
  @spec encode(term()) :: term()
  def encode(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__unknown_fields__])
    |> Map.new(fn {k, v} -> {k, encode(v)} end)
  end

  def encode(list) when is_list(list), do: Enum.map(list, &encode/1)

  def encode(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {k, encode(v)}
      {k, v} -> {k, encode(v)}
    end)
  end

  def encode(bin) when is_binary(bin) do
    if String.valid?(bin), do: bin, else: Base.encode64(bin)
  end

  def encode(other), do: other

  @doc "从 params 取字符串。"
  def str(params, key, default \\ "") do
    case Map.get(params, key) || Map.get(params, to_atom(key)) do
      nil -> default
      v -> to_string(v)
    end
  end

  @doc "从 params 取整数。"
  def int(params, key, default \\ 0) do
    case Map.get(params, key) || Map.get(params, to_atom(key)) do
      nil -> default
      n when is_integer(n) -> n
      n when is_binary(n) -> String.to_integer(n)
      _ -> default
    end
  end

  defp to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp to_atom(key) when is_atom(key), do: key
end
