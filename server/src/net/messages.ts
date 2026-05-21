import type { ActionPayload, PlayerId, Snapshot } from "../game/types.js";

export type ClientMessage =
  | { type: "create_room" }
  | { type: "join_room"; room_code: string; player?: PlayerId }
  | { type: "action"; action: ActionPayload };

export type ServerMessage =
  | { type: "room_created"; room_code: string; player: PlayerId; snapshot: Snapshot }
  | { type: "joined"; room_code: string; player: PlayerId; snapshot: Snapshot }
  | { type: "player_joined"; players: PlayerId[]; snapshot: Snapshot }
  | { type: "presence_updated"; players: PlayerId[]; connected_players: PlayerId[]; snapshot: Snapshot }
  | { type: "snapshot"; snapshot: Snapshot }
  | { type: "error"; message: string };

export function parseClientMessage(raw: string): ClientMessage | undefined {
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch {
    return undefined;
  }

  if (!isRecord(parsed) || typeof parsed.type !== "string") {
    return undefined;
  }

  if (parsed.type === "create_room") {
    return { type: "create_room" };
  }

  if (parsed.type === "join_room" && typeof parsed.room_code === "string") {
    const player = typeof parsed.player === "string" && isPlayerId(parsed.player) ? parsed.player : undefined;
    return { type: "join_room", room_code: parsed.room_code, player };
  }

  if (parsed.type === "action" && isRecord(parsed.action)) {
    return { type: "action", action: parsed.action as unknown as ActionPayload };
  }

  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isPlayerId(player: string): player is PlayerId {
  return player === "player_1" || player === "player_2";
}
