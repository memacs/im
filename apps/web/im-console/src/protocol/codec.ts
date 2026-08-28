import { im } from "./generated.js";
import {
  compressPayload,
  decompressPayload,
  getNegotiatedCompression,
} from "./compression.js";

const Packet = im.protocol.Packet;
const ProtoVersion = im.protocol.ProtoVersion;

export type PacketLike = im.protocol.IPacket;
export const CmdType = im.protocol.CmdType;
export const ChatType = im.protocol.ChatType;
export const MsgType = im.protocol.MsgType;
export const AckStatus = im.protocol.AckStatus;

export class CodecError extends Error {
  constructor(
    public code: "proto_version_unsupported" | "msg_invalid",
    message: string,
  ) {
    super(message);
    this.name = "CodecError";
  }
}

/** 解码 WS 二进制帧为 Packet，并校验 ver == 1。 */
export function decodePacket(buf: Uint8Array): im.protocol.Packet {
  let packet: im.protocol.Packet;
  try {
    packet = Packet.decode(buf);
  } catch (e) {
    throw new CodecError("msg_invalid", String(e));
  }
  if (packet.ver !== ProtoVersion.PROTO_VERSION_V1) {
    throw new CodecError(
      "proto_version_unsupported",
      `unsupported protocol version: ${packet.ver}`,
    );
  }
  const raw = packet.payload ?? new Uint8Array();
  packet.payload = decompressPayload(raw, packet.compression ?? 0);
  return packet;
}

/** 编码 Packet 为可下发的 WS 二进制帧（按协商 compression 压缩 payload）。 */
export function encodePacket(attrs: PacketLike): Uint8Array {
  const compression =
    attrs.compression ?? getNegotiatedCompression();
  const rawPayload = attrs.payload ?? new Uint8Array();
  const payload = compressPayload(rawPayload, compression);
  const packet = Packet.create({
    ver: ProtoVersion.PROTO_VERSION_V1,
    compression,
    ...attrs,
    payload,
  });
  if (packet.ver !== ProtoVersion.PROTO_VERSION_V1) {
    throw new CodecError(
      "proto_version_unsupported",
      `unsupported protocol version: ${packet.ver}`,
    );
  }
  return Packet.encode(packet).finish();
}

export function encodeAuthReq(req: im.protocol.IAuthReq): Uint8Array {
  return im.protocol.AuthReq.encode(im.protocol.AuthReq.create(req)).finish();
}

export function decodeAuthResp(buf: Uint8Array): im.protocol.AuthResp {
  return im.protocol.AuthResp.decode(buf);
}

export function encodeHeartbeatReq(clientTime = Date.now()): Uint8Array {
  return im.protocol.HeartbeatReq.encode(
    im.protocol.HeartbeatReq.create({ clientTime }),
  ).finish();
}

export function encodeMsgSend(message: im.protocol.IChatMessage): Uint8Array {
  return im.protocol.MsgSendReq.encode(
    im.protocol.MsgSendReq.create({ message }),
  ).finish();
}

export function decodeChatMessage(buf: Uint8Array): im.protocol.ChatMessage {
  return im.protocol.ChatMessage.decode(buf);
}

export function decodeMsgAck(buf: Uint8Array): im.protocol.MsgAck {
  return im.protocol.MsgAck.decode(buf);
}

export function encodeMsgAck(ack: im.protocol.IMsgAck): Uint8Array {
  return im.protocol.MsgAck.encode(im.protocol.MsgAck.create(ack)).finish();
}

export function encodeMsgAckBatch(body: im.protocol.IMsgAckBatchUp): Uint8Array {
  return im.protocol.MsgAckBatchUp.encode(
    im.protocol.MsgAckBatchUp.create(body),
  ).finish();
}

export function decodeMsgAckBatch(buf: Uint8Array): im.protocol.MsgAckBatchDown {
  return im.protocol.MsgAckBatchDown.decode(buf);
}

export function encodeMsgRead(body: im.protocol.IMsgRead): Uint8Array {
  return im.protocol.MsgRead.encode(im.protocol.MsgRead.create(body)).finish();
}

export function encodeMsgRecall(body: im.protocol.IMsgRecall): Uint8Array {
  return im.protocol.MsgRecall.encode(
    im.protocol.MsgRecall.create(body),
  ).finish();
}

export function encodeMsgEdit(body: im.protocol.IMsgEdit): Uint8Array {
  return im.protocol.MsgEdit.encode(im.protocol.MsgEdit.create(body)).finish();
}

export function encodePassthrough(body: im.protocol.IPassthrough): Uint8Array {
  return im.protocol.Passthrough.encode(
    im.protocol.Passthrough.create(body),
  ).finish();
}

export function encodeOfflinePull(body: im.protocol.IOfflinePullReq): Uint8Array {
  return im.protocol.OfflinePullReq.encode(
    im.protocol.OfflinePullReq.create(body),
  ).finish();
}

export function encodeGroupCreate(body: im.protocol.IGroupCreateReq): Uint8Array {
  return im.protocol.GroupCreateReq.encode(
    im.protocol.GroupCreateReq.create(body),
  ).finish();
}

export function encodeGroupOperate(body: im.protocol.IGroupOperateReq): Uint8Array {
  return im.protocol.GroupOperateReq.encode(
    im.protocol.GroupOperateReq.create(body),
  ).finish();
}

export function encodeRoomCreate(body: im.protocol.IRoomCreateReq): Uint8Array {
  return im.protocol.RoomCreateReq.encode(
    im.protocol.RoomCreateReq.create(body),
  ).finish();
}

export function encodeRoomOperate(body: im.protocol.IRoomOperateReq): Uint8Array {
  return im.protocol.RoomOperateReq.encode(
    im.protocol.RoomOperateReq.create(body),
  ).finish();
}

export function encodeFriendAdd(body: im.protocol.IFriendAddReq): Uint8Array {
  return im.protocol.FriendAddReq.encode(
    im.protocol.FriendAddReq.create(body),
  ).finish();
}

export function encodeFriendList(): Uint8Array {
  return im.protocol.FriendListReq.encode(
    im.protocol.FriendListReq.create({}),
  ).finish();
}

export function encodeChannelSubscribe(ids: string[]): Uint8Array {
  return im.protocol.ChannelSubscribeReq.encode(
    im.protocol.ChannelSubscribeReq.create({ channelIds: ids }),
  ).finish();
}

export function encodeChannelPublish(body: im.protocol.IChannelPublish): Uint8Array {
  return im.protocol.ChannelPublish.encode(
    im.protocol.ChannelPublish.create(body),
  ).finish();
}

export function encodeStreamContent(body: im.protocol.IStreamContent): Uint8Array {
  return im.protocol.StreamContent.encode(
    im.protocol.StreamContent.create(body),
  ).finish();
}

export {
  getNegotiatedCompression,
  setNegotiatedCompression,
} from "./compression.js";

export { im };
