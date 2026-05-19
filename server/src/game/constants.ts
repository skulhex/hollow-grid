import type { ActionType, Cell, ModuleKind, NodeRole, PlayerId, PublicActionType } from "./types.js";

export const PLAYER_ONE: PlayerId = "player_1";
export const PLAYER_TWO: PlayerId = "player_2";
export const PLAYERS: PlayerId[] = [PLAYER_ONE, PLAYER_TWO];

export const OBJECT_CORE = "core";
export const OBJECT_NODE = "node";
export const OBJECT_MODULE = "module";

export const NODE_CONDUIT: NodeRole = "conduit";
export const NODE_HARVESTER: NodeRole = "harvester";
export const NODE_STRIKER: NodeRole = "striker";
export const NODE_DEFENDER: NodeRole = "defender";
export const NODE_HACKER: NodeRole = "hacker";

export const MODULE_CONNECTION: ModuleKind = "connection";
export const MODULE_REPAIR: ModuleKind = "repair";

export const ACTION_PLACE_NODE = "place_node";
export const ACTION_REPAIR_NODE = "repair_node";
export const ACTION_BREAK_NODE = "break_node";
export const ACTION_CLEAR_NODE = "clear_node";
export const ACTION_UPGRADE_HARVESTER = "upgrade_harvester";
export const ACTION_UPGRADE_STRIKER = "upgrade_striker";
export const ACTION_UPGRADE_DEFENDER = "upgrade_defender";
export const ACTION_UPGRADE_HACKER = "upgrade_hacker";
export const ACTION_BUILD_CONNECTION_MODULE = "build_connection_module";
export const ACTION_BUILD_REPAIR_MODULE = "build_repair_module";
export const ACTION_STRIKER_ATTACK = "striker_attack";
export const ACTION_HACKER_HACK = "hacker_hack";
export const ACTION_SKIP = "skip";

export const PUBLIC_ACTION_TYPES: readonly PublicActionType[] = [
  ACTION_PLACE_NODE,
  ACTION_REPAIR_NODE,
  ACTION_UPGRADE_HARVESTER,
  ACTION_UPGRADE_STRIKER,
  ACTION_UPGRADE_DEFENDER,
  ACTION_UPGRADE_HACKER,
  ACTION_BUILD_CONNECTION_MODULE,
  ACTION_BUILD_REPAIR_MODULE,
  ACTION_STRIKER_ATTACK,
  ACTION_HACKER_HACK,
  ACTION_SKIP
];

export const ALL_ACTION_TYPES: readonly ActionType[] = [
  ...PUBLIC_ACTION_TYPES,
  ACTION_BREAK_NODE,
  ACTION_CLEAR_NODE
];

export const DIRECTIONS: readonly Cell[] = [
  { q: 1, r: 0 },
  { q: 1, r: -1 },
  { q: 0, r: -1 },
  { q: -1, r: 0 },
  { q: -1, r: 1 },
  { q: 0, r: 1 }
];

export const CONTROL_POINT: Cell = { q: 0, r: 0 };
export const INVALID_CELL: Cell = { q: 999, r: 999 };

export const START_CORE_HP = 5;
export const START_RESOURCE = 1;
export const CONNECTION_ACTIONS_PER_TURN = 1;
export const REPAIR_ACTIONS_PER_TURN = 1;
export const NODE_ROLE_ACTION_CHARGES_PER_TURN = 1;
export const HARVESTER_RESOURCE_GAIN = 1;
export const HARVESTER_UPGRADE_RESOURCE_COST = 1;
export const STRIKER_UPGRADE_RESOURCE_COST = 1;
export const DEFENDER_UPGRADE_RESOURCE_COST = 1;
export const HACKER_UPGRADE_RESOURCE_COST = 1;
export const MODULE_BUILD_RESOURCE_COST = 5;
export const STRIKER_CORE_DAMAGE = 1;

export function playerLabel(player: string): string {
  if (player === PLAYER_ONE) return "Player 1";
  if (player === PLAYER_TWO) return "Player 2";
  return player;
}

export function otherPlayer(player: PlayerId): PlayerId {
  return player === PLAYER_ONE ? PLAYER_TWO : PLAYER_ONE;
}

export function isPlayerId(player: string): player is PlayerId {
  return player === PLAYER_ONE || player === PLAYER_TWO;
}
