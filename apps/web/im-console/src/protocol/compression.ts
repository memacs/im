import { gzip, ungzip } from "pako";
import { im } from "./generated.js";

const { PayloadCompression } = im.protocol;

/** 与 AuthResp.payloadCompression 对齐；AUTH 前为 NONE。 */
let negotiatedOutbound = PayloadCompression.PAYLOAD_COMPRESSION_NONE;

export function setNegotiatedCompression(
  value: im.protocol.PayloadCompression | number | null | undefined,
) {
  negotiatedOutbound =
    value ?? PayloadCompression.PAYLOAD_COMPRESSION_NONE;
}

export function getNegotiatedCompression(): im.protocol.PayloadCompression {
  return negotiatedOutbound;
}

export function compressPayload(
  payload: Uint8Array,
  compression: im.protocol.PayloadCompression | number,
): Uint8Array {
  if (
    compression === PayloadCompression.PAYLOAD_COMPRESSION_GZIP &&
    payload.byteLength > 0
  ) {
    return gzip(payload);
  }
  return payload;
}

export function decompressPayload(
  payload: Uint8Array,
  compression: im.protocol.PayloadCompression | number,
): Uint8Array {
  if (
    compression === PayloadCompression.PAYLOAD_COMPRESSION_GZIP &&
    payload.byteLength > 0
  ) {
    return ungzip(payload);
  }
  return payload;
}
