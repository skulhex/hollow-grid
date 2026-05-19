import {
  ACTION_BUILD_CONNECTION_MODULE,
  ACTION_BUILD_REPAIR_MODULE,
  ACTION_HACKER_HACK,
  ACTION_PLACE_NODE,
  ACTION_REPAIR_NODE,
  ACTION_SKIP,
  ACTION_STRIKER_ATTACK,
  ACTION_UPGRADE_DEFENDER,
  ACTION_UPGRADE_HACKER,
  ACTION_UPGRADE_HARVESTER,
  ACTION_UPGRADE_STRIKER,
  ALL_ACTION_TYPES,
  PUBLIC_ACTION_TYPES
} from "./constants.js";
import type { ActionPayload, Cell, NormalizedAction, PublicActionType } from "./types.js";

export const ZERO_CELL: Cell = { q: 0, r: 0 };

export function parseAction(raw: unknown): NormalizedAction {
  if (!isRecord(raw)) {
    return emptyAction(true);
  }

  const action: NormalizedAction = {
    type: typeof raw.type === "string" ? raw.type : "",
    player: typeof raw.player === "string" ? raw.player : "",
    cell: { ...ZERO_CELL },
    hasCell: false,
    sourceCell: { ...ZERO_CELL },
    hasSourceCell: false,
    invalidShape: false
  };

  if ("cell" in raw) {
    if (!isValidCellPayload(raw.cell)) {
      action.invalidShape = true;
      return action;
    }

    action.cell = parseCell(raw.cell);
    action.hasCell = true;
  }

  if ("source_cell" in raw) {
    if (!isValidCellPayload(raw.source_cell)) {
      action.invalidShape = true;
      return action;
    }

    action.sourceCell = parseCell(raw.source_cell);
    action.hasSourceCell = true;
  }

  return action;
}

export function isValidActionShape(action: NormalizedAction): boolean {
  if (action.invalidShape || action.player.length === 0) {
    return false;
  }

  if (action.type === ACTION_SKIP) {
    return !action.hasCell && !action.hasSourceCell;
  }

  if (action.type === ACTION_STRIKER_ATTACK || action.type === ACTION_HACKER_HACK) {
    return action.hasCell && action.hasSourceCell;
  }

  return (
    ALL_ACTION_TYPES.includes(action.type as never) &&
    action.type !== ACTION_SKIP &&
    action.hasCell &&
    !action.hasSourceCell
  );
}

export function isPublicActionType(type: string): type is PublicActionType {
  return PUBLIC_ACTION_TYPES.includes(type as PublicActionType);
}

export function isValidPublicActionShape(raw: unknown): boolean {
  const action = parseAction(raw);
  return isValidActionShape(action) && isPublicActionType(action.type);
}

export function actionToPayload(action: NormalizedAction): Required<Pick<ActionPayload, "type" | "player">> & {
  cell?: Cell;
  source_cell?: Cell;
} {
  const payload: Required<Pick<ActionPayload, "type" | "player">> & {
    cell?: Cell;
    source_cell?: Cell;
  } = {
    type: action.type,
    player: action.player
  };

  if (action.hasCell) {
    payload.cell = { ...action.cell };
  }

  if (action.hasSourceCell) {
    payload.source_cell = { ...action.sourceCell };
  }

  return payload;
}

export function makeAction(type: PublicActionType, player: string, cell?: Cell, sourceCell?: Cell): ActionPayload {
  const action: ActionPayload = { type, player };

  if (cell) {
    action.cell = { ...cell };
  }

  if (sourceCell) {
    action.source_cell = { ...sourceCell };
  }

  return action;
}

export function isValidCellPayload(raw: unknown): raw is Cell {
  if (!isRecord(raw)) {
    return false;
  }

  return isIntLike(raw.q) && isIntLike(raw.r);
}

export function parseCell(raw: unknown): Cell {
  if (!isValidCellPayload(raw)) {
    return { ...ZERO_CELL };
  }

  return {
    q: Number(raw.q),
    r: Number(raw.r)
  };
}

export function sameCell(first: Cell, second: Cell): boolean {
  return first.q === second.q && first.r === second.r;
}

export function addCells(first: Cell, second: Cell): Cell {
  return {
    q: first.q + second.q,
    r: first.r + second.r
  };
}

export function cellKey(cell: Cell): string {
  return `${cell.q},${cell.r}`;
}

export function cloneCell(cell: Cell): Cell {
  return { q: cell.q, r: cell.r };
}

export function containsCell(cell: Cell, radius: number): boolean {
  return Math.abs(cell.q) <= radius && Math.abs(cell.r) <= radius && Math.abs(cell.q + cell.r) <= radius;
}

function emptyAction(invalidShape: boolean): NormalizedAction {
  return {
    type: "",
    player: "",
    cell: { ...ZERO_CELL },
    hasCell: false,
    sourceCell: { ...ZERO_CELL },
    hasSourceCell: false,
    invalidShape
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isIntLike(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value) && Number.isInteger(value);
}

export const actionTypes = {
  placeNode: ACTION_PLACE_NODE,
  repairNode: ACTION_REPAIR_NODE,
  upgradeHarvester: ACTION_UPGRADE_HARVESTER,
  upgradeStriker: ACTION_UPGRADE_STRIKER,
  upgradeDefender: ACTION_UPGRADE_DEFENDER,
  upgradeHacker: ACTION_UPGRADE_HACKER,
  buildConnectionModule: ACTION_BUILD_CONNECTION_MODULE,
  buildRepairModule: ACTION_BUILD_REPAIR_MODULE,
  strikerAttack: ACTION_STRIKER_ATTACK,
  hackerHack: ACTION_HACKER_HACK,
  skip: ACTION_SKIP
} as const;
