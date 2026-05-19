export type PlayerId = "player_1" | "player_2";

export type ObjectType = "core" | "node" | "module";
export type NodeRole = "conduit" | "harvester" | "striker" | "defender" | "hacker";
export type ModuleKind = "connection" | "repair";

export type PublicActionType =
  | "place_node"
  | "repair_node"
  | "upgrade_harvester"
  | "upgrade_striker"
  | "upgrade_defender"
  | "upgrade_hacker"
  | "build_connection_module"
  | "build_repair_module"
  | "striker_attack"
  | "hacker_hack"
  | "skip";

export type InternalActionType = "break_node" | "clear_node";
export type ActionType = PublicActionType | InternalActionType;

export interface Cell {
  q: number;
  r: number;
}

export interface ActionPayload {
  type: string;
  player: string;
  cell?: unknown;
  source_cell?: unknown;
}

export interface NormalizedAction {
  type: string;
  player: string;
  cell: Cell;
  hasCell: boolean;
  sourceCell: Cell;
  hasSourceCell: boolean;
  invalidShape: boolean;
}

export interface BaseGameObject {
  cell: Cell;
  type: ObjectType;
  owner: PlayerId;
  active: boolean;
  disabled: boolean;
}

export interface CoreObject extends BaseGameObject {
  type: "core";
}

export interface NodeObject extends BaseGameObject {
  type: "node";
  role: NodeRole;
  ready: boolean;
  action_charges: number;
}

export interface ModuleObject extends BaseGameObject {
  type: "module";
  module_kind: ModuleKind;
  ready: boolean;
}

export type GameObject = CoreObject | NodeObject | ModuleObject;

export type SnapshotObject =
  | CoreObject
  | NodeObject
  | ModuleObject;

export interface Snapshot {
  players: PlayerId[];
  current_player: PlayerId;
  turn: number;
  round: number;
  core_hp: Record<PlayerId, number>;
  resources: Record<PlayerId, number>;
  action_limits: {
    connection_actions_left: number;
    repair_actions_left: number;
  };
  objects: SnapshotObject[];
  finished: boolean;
  status_message: string;
}

export interface ApplyResult {
  ok: boolean;
  message: string;
  snapshot: Snapshot;
  action?: {
    type: string;
    player: string;
    cell?: Cell;
    source_cell?: Cell;
  };
}
