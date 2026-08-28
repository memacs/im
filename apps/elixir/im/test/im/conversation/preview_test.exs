defmodule IM.Conversation.PreviewTest do
  use ExUnit.Case, async: true

  alias IM.Conversation.Preview

  test "文本截断与非文本类型" do
    long = String.duplicate("a", 300)
    assert String.ends_with?(Preview.from_message(:MSG_TEXT, long), "…")
    assert Preview.from_message(:MSG_IMAGE, nil) == "[图片]"
    assert Preview.from_message(:MSG_TEXT, "hi", true) == "[消息已撤回]"
  end
end
