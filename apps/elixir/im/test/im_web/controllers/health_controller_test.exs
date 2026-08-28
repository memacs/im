defmodule IMWeb.HealthControllerTest do
  use IMWeb.ConnCase, async: true

  describe "GET /health/live 存活探针" do
    test "BEAM 存活即返回 200，不触碰数据库", %{conn: conn} do
      conn = get(conn, ~p"/health/live")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "数据库不可用时仍返回 200（存活与就绪解耦）", %{conn: conn} do
      with_failing_checker(fn ->
        conn = get(conn, ~p"/health/live")

        assert json_response(conn, 200) == %{"status" => "ok"}
      end)
    end
  end

  describe "GET /health/ready 就绪探针" do
    test "数据库连通时返回 200", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      assert %{"status" => "ok", "database" => "connected"} = json_response(conn, 200)
    end

    test "数据库不可用时返回 503，便于摘除流量而不重启实例", %{conn: conn} do
      with_failing_checker(fn ->
        conn = get(conn, ~p"/health/ready")

        assert %{"status" => "error"} = json_response(conn, 503)
      end)
    end
  end

  describe "GET /health 兼容入口" do
    test "等价于存活探针，供 release-smoke 使用", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200) == %{"status" => "ok"}
    end
  end

  # 通过 Application 环境注入失败的就绪检查实现（DI，不依赖真实断连）
  defp with_failing_checker(fun) do
    previous = Application.get_env(:im, :health_checker)
    Application.put_env(:im, :health_checker, IMWeb.HealthControllerTest.FailingChecker)

    try do
      fun.()
    after
      if previous do
        Application.put_env(:im, :health_checker, previous)
      else
        Application.delete_env(:im, :health_checker)
      end
    end
  end

  defmodule FailingChecker do
    @moduledoc false
    @behaviour IM.Health.Checker

    @impl true
    def ready?, do: {:error, :connection_refused}
  end
end
