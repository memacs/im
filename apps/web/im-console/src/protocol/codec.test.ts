import { describe, expect, it } from "vitest";
import {
  CodecError,
  CmdType,
  decodePacket,
  encodePacket,
  im,
  setNegotiatedCompression,
} from "./codec";

describe("Packet Codec", () => {
  it("round-trip 关键字段", () => {
    const bin = encodePacket({
      cmd: CmdType.CMD_MSG_SEND,
      seq: 7,
      ts: 1_700_000_000_000,
      cid: "cid-1",
      traceId: "tr-1",
      payload: Uint8Array.from([9, 8, 7]),
      routeKey: "u_1",
    });
    const decoded = decodePacket(bin);
    expect(decoded.ver).toBe(im.protocol.ProtoVersion.PROTO_VERSION_V1);
    expect(decoded.cmd).toBe(CmdType.CMD_MSG_SEND);
    expect(Number(decoded.seq)).toBe(7);
    expect(Number(decoded.ts)).toBe(1_700_000_000_000);
    expect(decoded.cid).toBe("cid-1");
    expect(decoded.traceId).toBe("tr-1");
    expect(decoded.routeKey).toBe("u_1");
    expect(Array.from(decoded.payload)).toEqual([9, 8, 7]);
  });

  it("ver≠1 抛 proto_version_unsupported", () => {
    const bad = im.protocol.Packet.encode(
      im.protocol.Packet.create({ ver: 99, cmd: 1, seq: 1 }),
    ).finish();
    expect(() => decodePacket(bad)).toThrow(CodecError);
    try {
      decodePacket(bad);
    } catch (e) {
      expect((e as CodecError).code).toBe("proto_version_unsupported");
    }
  });

  it("损坏帧抛 msg_invalid", () => {
    expect(() => decodePacket(Uint8Array.from([0xff, 0xfe, 0xfd]))).toThrow(
      CodecError,
    );
  });

  it("GZIP payload round-trip（协商后）", () => {
    setNegotiatedCompression(
      im.protocol.PayloadCompression.PAYLOAD_COMPRESSION_GZIP,
    );
    const raw = new TextEncoder().encode('{"hello":"world"}');
    const bin = encodePacket({
      cmd: CmdType.CMD_MSG_SEND,
      seq: 2,
      ts: 1,
      payload: raw,
    });
    const decoded = decodePacket(bin);
    expect(decoded.compression).toBe(
      im.protocol.PayloadCompression.PAYLOAD_COMPRESSION_GZIP,
    );
    expect(new TextDecoder().decode(decoded.payload ?? new Uint8Array())).toBe(
      '{"hello":"world"}',
    );
    setNegotiatedCompression(
      im.protocol.PayloadCompression.PAYLOAD_COMPRESSION_NONE,
    );
  });
});
