defmodule IM.AuditTest do
  use IM.DataCase, async: true

  alias IM.Schemas.AuditLog

  test "record 同步写入 audit_logs" do
    assert :ok =
             IM.Audit.record(:auth_login,
               app_key: "demo",
               user_id: "u1",
               device_id: "d1",
               strategy: "token",
               result: :success
             )

    log = Repo.get_by(AuditLog, event: "auth_login", user_id: "u1")
    assert log
    assert log.app_key == "demo"
    assert log.result == "success"
    assert log.strategy == "token"
    assert log.created_at
  end

  test "auth_failed 记录 reason" do
    assert :ok =
             IM.Audit.record(:auth_failed,
               app_key: "demo",
               user_id: "u2",
               result: :failure,
               reason: "invalid_token"
             )

    log = Repo.get_by(AuditLog, event: "auth_failed", user_id: "u2")
    assert log.reason == "invalid_token"
    assert log.result == "failure"
  end

  test "auth_logout 记录登出" do
    assert :ok =
             IM.Audit.record(:auth_logout,
               app_key: "demo",
               user_id: "u3",
               device_id: "d1",
               strategy: "token",
               result: :success,
               reason: "http_logout"
             )

    log = Repo.get_by(AuditLog, event: "auth_logout", user_id: "u3")
    assert log.result == "success"
    assert log.reason == "http_logout"
  end
end
