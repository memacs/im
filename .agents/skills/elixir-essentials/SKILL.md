---
name: elixir-essentials
description: >-
  编写或重构 Elixir 核心代码时使用：模式匹配、case/cond/with、管道、{:ok,_}/{:error,_} 契约。
  IM 项目 @doc 正文用简体中文。适用于未覆盖的更具体技能之外的 .ex/.exs 变更。
file_patterns:
  - "**/*.ex"
  - "**/*.exs"
auto_suggest: true
---

# Elixir 基础规范（IM 项目）

> **语言**：本仓库 `apps/elixir/im` 的 `@moduledoc` / `@doc` **正文用简体中文**；代码标识符与 `@spec` 保持英文。见 [`AGENTS.md`](../../AGENTS.md)「中文优先」。

## 规则（必须遵守）

1. **用模式匹配代替 if/else** 做控制流与数据提取
2. **每个回调函数前加 `@impl true`**（mount、handle_event、handle_info 等）
3. **可失败操作返回 `{:ok, result} | {:error, reason}` 元组**
4. **连续两步及以上可失败操作用 `with`**，不要嵌套 case
5. **两次及以上链式变换用管道 `|>`**
6. **不要嵌套 if/else** — 用 case、cond 或多子句函数
7. **谓词函数以 `?` 结尾**，危险函数以 `!` 结尾
8. **Let it crash** — 不对不可能的状态写防御代码
9. **公共模块须有 `@moduledoc`** — 至少一行中文摘要；相关时链接设计文档
10. **公共函数须有 `@doc`（中文）与 `@spec`** — 供 ExDoc 生成文档；spec 须匹配 `{:ok,_}` / `{:error,_}` 契约；**`@doc` 含 `## 示例` 调用代码**（纯函数可用 `iex>` doctest）
11. **Behaviour 回调须有 `@impl`** — behaviour 未文档化时补中文 `@doc` / `@spec`

---

## Pattern Matching

Pattern matching is the primary control flow mechanism in Elixir. Prefer it over conditional statements.

### Prefer Pattern Matching Over if/else

**Bad:**
```elixir
def process(result) do
  if result.status == :ok do
    result.data
  else
    nil
  end
end
```

**Good:**
```elixir
def process(%{status: :ok, data: data}), do: data
def process(_), do: nil
```

### Use Case for Multiple Patterns

**Bad:**
```elixir
# Nested if inside else — hard to read and not how Elixir expresses multi-way branching
def handle_response(response) do
  if response.status == 200 do
    {:ok, response.body}
  else
    if response.status == 404 do
      {:error, :not_found}
    else
      {:error, :unknown}
    end
  end
end
```

**Good:**
```elixir
def handle_response(%{status: 200, body: body}), do: {:ok, body}
def handle_response(%{status: 404}), do: {:error, :not_found}
def handle_response(_), do: {:error, :unknown}
```

## Pipe Operator

Use the pipe operator `|>` to chain function calls for improved readability.

### Basic Piping

**Bad:**
```elixir
String.upcase(String.trim(user_input))
```

**Good:**
```elixir
user_input
|> String.trim()
|> String.upcase()
```

### Pipe into Function Heads

**Bad:**
```elixir
def process_user(user) do
  validated = validate_user(user)
  transformed = transform_user(validated)
  save_user(transformed)
end
```

**Good:**
```elixir
def process_user(user) do
  user
  |> validate_user()
  |> transform_user()
  |> save_user()
end
```

## With Statement

Use `with` for sequential operations that can fail.

**Bad:**
```elixir
def create_post(params) do
  case validate_params(params) do
    {:ok, valid_params} ->
      case create_changeset(valid_params) do
        {:ok, changeset} ->
          Repo.insert(changeset)
        error -> error
      end
    error -> error
  end
end
```

**Good:**
```elixir
def create_post(params) do
  with {:ok, valid_params} <- validate_params(params),
       {:ok, changeset} <- create_changeset(valid_params),
       {:ok, post} <- Repo.insert(changeset) do
    {:ok, post}
  end
end
```

### With Statement - Inline Error Handling

Handle specific errors in the else block.

```elixir
def transfer_money(from_id, to_id, amount) do
  with {:ok, from_account} <- get_account(from_id),
       {:ok, to_account} <- get_account(to_id),
       :ok <- validate_balance(from_account, amount),
       {:ok, _} <- debit(from_account, amount),
       {:ok, _} <- credit(to_account, amount) do
    {:ok, :transfer_complete}
  else
    {:error, :insufficient_funds} ->
      {:error, "Not enough money in account"}

    {:error, :not_found} ->
      {:error, "Account not found"}

    error ->
      {:error, "Transfer failed: #{inspect(error)}"}
  end
end
```

## Guards

Use guards for simple type and value checks in function heads.

```elixir
def calculate(x) when is_integer(x) and x > 0 do
  x * 2
end

def calculate(_), do: {:error, :invalid_input}
```

## List Comprehensions

Use `for` comprehensions for complex transformations and filtering.

**Bad (multiple passes):**
```elixir
list
|> Enum.map(&transform/1)
|> Enum.filter(&valid?/1)
|> Enum.map(&format/1)
```

**Good (single pass):**
```elixir
for item <- list,
    transformed = transform(item),
    valid?(transformed) do
  format(transformed)
end
```

## Naming Conventions

- Module names: `PascalCase`
- Function names: `snake_case`
- Variables: `snake_case`
- Atoms: `:snake_case`
- Predicate functions end with `?`: `valid?`, `empty?`
- Dangerous functions end with `!`: `save!`, `update!`

## Tagged Tuples for Error Handling

The idiomatic way to handle success and failure in Elixir.

```elixir
def fetch_user(id) do
  case Repo.get(User, id) do
    nil -> {:error, :not_found}
    user -> {:ok, user}
  end
end

# Usage
case fetch_user(123) do
  {:ok, user} -> IO.puts("Found: #{user.name}")
  {:error, :not_found} -> IO.puts("User not found")
end
```

## Case Statements

Pattern match on results.

```elixir
def process_upload(file) do
  case save_file(file) do
    {:ok, path} ->
      Logger.info("File saved to #{path}")
      create_record(path)

    {:error, :invalid_format} ->
      {:error, "File format not supported"}

    {:error, reason} ->
      Logger.error("Upload failed: #{inspect(reason)}")
      {:error, "Upload failed"}
  end
end
```

## Bang Functions

Functions ending with `!` raise errors instead of returning tuples.

```elixir
# Returns {:ok, user} or {:error, changeset}
def create_user(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert()
end

# Returns user or raises
def create_user!(attrs) do
  %User{}
  |> User.changeset(attrs)
  |> Repo.insert!()
end

# Usage
try do
  user = create_user!(invalid_attrs)
  IO.puts("Created #{user.name}")
rescue
  e in Ecto.InvalidChangesetError ->
    IO.puts("Failed: #{inspect(e)}")
end
```

## Try/Rescue

Catch exceptions when needed (use sparingly).

```elixir
def parse_json(string) do
  try do
    {:ok, Jason.decode!(string)}
  rescue
    Jason.DecodeError -> {:error, :invalid_json}
  end
end
```

> Processes, GenServers, supervision: see the **otp-essentials** skill.

## Validation Errors

Return clear, actionable error messages.

```elixir
def validate_image_upload(file) do
  with :ok <- validate_file_type(file),
       :ok <- validate_file_size(file),
       :ok <- validate_dimensions(file) do
    {:ok, file}
  else
    {:error, :invalid_type} ->
      {:error, "Only JPEG, PNG, and GIF files are allowed"}

    {:error, :too_large} ->
      {:error, "File must be less than 10MB"}

    {:error, :invalid_dimensions} ->
      {:error, "Image must be at least 100x100 pixels"}
  end
end
```

## Changeset Errors

Extract and format Ecto changeset errors.

```elixir
def changeset_errors(changeset) do
  Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end)
end

# Usage
case create_user(attrs) do
  {:ok, user} -> {:ok, user}
  {:error, changeset} ->
    errors = changeset_errors(changeset)
    {:error, errors}
end
```

## Early Returns

Use pattern matching in function heads for early returns.

```elixir
def process_data(nil), do: {:error, :no_data}
def process_data([]), do: {:error, :empty_list}
def process_data(data) when is_list(data) do
  # Process the list
  {:ok, Enum.map(data, &transform/1)}
end
```

## Avoid Defensive Programming

Don't check for things that can't happen. Let it crash.

**Bad (defensive):**
```elixir
def get_username(user) do
  if user && user.name do
    user.name
  else
    "Unknown"
  end
end
```

**Good (trust your types):**
```elixir
def get_username(%User{name: name}), do: name
```

If the user is nil or doesn't have a name, it's a bug that should crash and be fixed.

## 文档（ExDoc）

IM 项目 **`apps/elixir/im`**：所有**公共** API 必须可生成文档；**`@doc` 正文用简体中文**。

| 元素 | 公共 API | 私有（`defp`） |
|------|----------|----------------|
| `@moduledoc` | **必填**（或 `@moduledoc false` + 理由） | — |
| `@doc` | **必填** | 不需要 |
| `@spec` | **必填** | 可选 |

### 模板

```elixir
defmodule IM.Services.MessageSend do
  @moduledoc """
  单聊/群聊/聊天室消息发送。

  设计：[`message-send-ack.md`](../../../docs/design/message-send-ack.md)
  """

  @type send_result :: {:ok, map()} | {:error, atom()}

  @doc """
  发送一条消息。

  与 `CMD_MSG_SEND` / `POST /api/v1/messages` 共用。

  ## 示例

      ctx = %IM.Domain.MessageContext{
        app_key: "demo",
        user_id: "alice",
        device_id: "d1",
        trace_id: "trace-1"
      }

      MessageSend.send(ctx, %{chat_type: 1, to: "bob", body: "你好"})

  ## 返回值

  - `{:ok, %{msg_id: binary(), conv_seq: integer()}}`
  - `{:error, :invalid}` — 参数不合法
  """
  @spec send(IM.MessageContext.t(), map()) :: send_result()
  def send(context, params) do
    # ...
  end
end
```

### `@doc` 内容

- 首行：一句话做什么
- **`## 示例`**：展示典型调用（缩进代码块或 ` ```elixir ` 围栏）；让读者复制即可理解入参形状
- 必要时：`## 参数`、`## 返回值`、`## 错误`（`:invalid`、`:unauthorized` 等）
- 对应协议时注明 cmd 或 REST 路径
- 纯函数、无副作用：可用 ExDoc `iex>` doctest 代替 `## 示例`

### 何时可省略 `## 示例`

- 一行透传、语义自明的 accessor（如 `user_id/1`）
- Phoenix Controller action（用路由 + 请求体示例写在 moduledoc 或 API 文档即可）
- 必须在 PR 中说明省略理由

### `@spec` 内容

- 与实现一致；优先用已定义的 `@type`（如 `IM.MessageContext.t()`）
- 可失败操作：`{:ok, term()} | {:error, term()}` 或更具体的 reason atom
- 运行 `mix docs` 确认无警告；后续可启用 Dialyzer 校验

### 例外

- `test/**`、`*_test.exs`：不要求
- 纯内部模块：`@moduledoc false` 可接受，但**仍有公共 `def` 时须 `@doc` + `@spec`**
- Phoenix Controller action：公共 action 须 `@doc` + `@spec`（`Plug.Conn.t()` → `Plug.Conn.t()`）

## Immutability

All data structures are immutable. Functions return new values rather than modifying in place.

```elixir
# Always returns a new list
list = [1, 2, 3]
new_list = [0 | list]  # [0, 1, 2, 3]
# list is still [1, 2, 3]
```

## Testing

When writing test files for Elixir modules, invoke `elixir-phoenix-guide:testing-essentials` before writing any `_test.exs` file.

## Anonymous Functions

Use the capture operator `&` for concise anonymous functions.

**Verbose:**
```elixir
Enum.map(list, fn x -> x * 2 end)
```

**Concise:**
```elixir
Enum.map(list, &(&1 * 2))
```

**Named function capture:**
```elixir
Enum.map(users, &User.format/1)
```
