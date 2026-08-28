defmodule IM.Client.Scenario do
  @moduledoc """
  双用户集成测试骨架（仅 `test/support`）。

  分别启动两个 `IM.Client.Connection`；单测可注入 `transport: FakeTransport`。
  """

  alias IM.Client.Connection

  @type pair :: %{a: pid(), b: pid()}

  @doc """
  启动一对客户端（未 connect）。

  ## opts

  - `:url_a` / `:url_b` — WebSocket URL（缺省都用 `:url`）
  - `:transport` — 传输模块
  """
  @spec start_pair(keyword()) :: {:ok, pair()} | {:error, term()}
  def start_pair(opts) do
    url = Keyword.get(opts, :url, "ws://localhost:4000/ws")
    transport = Keyword.get(opts, :transport)
    url_a = Keyword.get(opts, :url_a, url)
    url_b = Keyword.get(opts, :url_b, url)

    a_opts = [url: url_a] ++ if(transport, do: [transport: transport], else: [])
    b_opts = [url: url_b] ++ if(transport, do: [transport: transport], else: [])

    with {:ok, a} <- Connection.start_link(a_opts),
         {:ok, b} <- Connection.start_link(b_opts) do
      {:ok, %{a: a, b: b}}
    end
  end

  @doc "两路 connect。"
  @spec connect_pair(pair()) :: :ok | {:error, term()}
  def connect_pair(%{a: a, b: b}) do
    with :ok <- Connection.connect(a),
         :ok <- Connection.connect(b) do
      :ok
    end
  end

  @doc "分别 authenticate。`attrs_a` / `attrs_b` 为 AUTH 属性 map。"
  @spec authenticate_pair(pair(), map(), map()) :: {:ok, map()} | {:error, term()}
  def authenticate_pair(%{a: a, b: b}, attrs_a, attrs_b) do
    with {:ok, ra} <- Connection.authenticate(a, attrs_a),
         {:ok, rb} <- Connection.authenticate(b, attrs_b) do
      {:ok, %{a: ra, b: rb}}
    end
  end
end
