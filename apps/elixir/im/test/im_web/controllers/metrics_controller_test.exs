defmodule IMWeb.MetricsControllerTest do
  use IMWeb.ConnCase, async: false

  alias IM.Telemetry.Websocket

  test "GET /metrics 返回 Prometheus 文本并可观测包计数" do
    Websocket.frame_in(128, 100)
    Websocket.packet_error(2004, "CMD_MSG_SEND")
    IM.Telemetry.Storage.stop(System.monotonic_time() - 1_000_000, :insert, "message_store")
    IM.Telemetry.Delivery.stop(System.monotonic_time() - 1_000_000, recipient_count: 2)
    IM.Telemetry.Cluster.dispatch(1)
    IM.Telemetry.MsgBurn.scheduled()
    IM.Telemetry.MsgBurn.executed(10)

    conn = get(build_conn(), "/metrics")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
    body = response(conn, 200)
    assert body =~ "im_packet_received_total"
    assert body =~ "im_packet_errors_total"
    assert body =~ "im_storage_duration_ms"
    assert body =~ "im_delivery_duration_ms"
    assert body =~ "im_cross_node_dispatch_total"
    assert body =~ "im_msg_burn_scheduled_total"
    assert body =~ "im_msg_burn_executed_total"
    assert body =~ "vm_memory_total"
  end
end
