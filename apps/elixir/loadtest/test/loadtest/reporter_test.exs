defmodule IM.LoadTest.ReporterTest do
  use ExUnit.Case, async: true

  alias IM.LoadTest.Reporter

  test "汇总成功率与分位数" do
    rows = [
      {{:ok, :connect_auth}, 8},
      {{:err, :connect_auth}, 2},
      {{:sample, :connect_auth, 1}, 10},
      {{:sample, :connect_auth, 2}, 20},
      {{:sample, :connect_auth, 3}, 30},
      {{:sample, :connect_auth, 4}, 40},
      {{:err_reason, :connect_auth, ":timeout"}, 2}
    ]

    report = Reporter.build("connection_load", 1000, rows)
    assert report.scenario == "connection_load"
    assert report.ops.connect_auth.success == 8
    assert report.ops.connect_auth.failure == 2
    assert report.ops.connect_auth.latency.p50_ms == 20
    assert report.qps == 8.0
  end
end
