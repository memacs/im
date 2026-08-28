defmodule IM.Domain.Error do
  @moduledoc """
  跨层统一错误值。Service 层向上只返回本结构，由各出口翻译成对应表示：
  WS 出口编码为 `ErrorBody`（`CMD_ERROR`），REST 出口由 FallbackController 转 JSON。

  `code` 用原子而非数值，是为了让业务代码免于硬编码枚举值；
  到出口再映射为 `proto/common.proto` 的 `ErrorCode`（映射表 Phase 1 补齐）。
  """

  defstruct [:code, :msg, :ref_cmd, :ref_cid]

  @type t :: %__MODULE__{
          code: atom(),
          msg: String.t() | nil,
          ref_cmd: non_neg_integer() | nil,
          ref_cid: String.t() | nil
        }

  @doc """
  构造错误。`opts` 支持 `:ref_cmd`（触发失败的命令字）与 `:ref_cid`（原请求幂等 ID）。
  """
  @spec new(atom(), String.t() | nil, keyword()) :: t()
  def new(code, msg \\ nil, opts \\ []) when is_atom(code) do
    %__MODULE__{
      code: code,
      msg: msg,
      ref_cmd: Keyword.get(opts, :ref_cmd),
      ref_cid: Keyword.get(opts, :ref_cid)
    }
  end

  @doc """
  骨架阶段的占位错误：调用路径已接通，但目标能力尚未实现。
  """
  @spec not_implemented(non_neg_integer() | nil) :: t()
  def not_implemented(ref_cmd \\ nil) do
    new(:not_implemented, "not implemented yet", ref_cmd: ref_cmd)
  end
end
