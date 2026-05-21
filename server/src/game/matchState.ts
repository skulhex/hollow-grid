import {
  ACTION_BUILD_CONNECTION_MODULE,
  ACTION_BUILD_REPAIR_MODULE,
  ACTION_CLEAR_NODE,
  ACTION_BREAK_NODE,
  ACTION_HACKER_HACK,
  ACTION_PLACE_NODE,
  ACTION_REPAIR_NODE,
  ACTION_SKIP,
  ACTION_STRIKER_ATTACK,
  ACTION_UPGRADE_DEFENDER,
  ACTION_UPGRADE_HACKER,
  ACTION_UPGRADE_HARVESTER,
  ACTION_UPGRADE_STRIKER,
  CONNECTION_ACTIONS_PER_TURN,
  CONTROL_POINT,
  DEFENDER_UPGRADE_RESOURCE_COST,
  DIRECTIONS,
  HACKER_UPGRADE_RESOURCE_COST,
  HARVESTER_RESOURCE_GAIN,
  HARVESTER_UPGRADE_RESOURCE_COST,
  INVALID_CELL,
  MODULE_BUILD_RESOURCE_COST,
  MODULE_CONNECTION,
  MODULE_REPAIR,
  NODE_CONDUIT,
  NODE_DEFENDER,
  NODE_HACKER,
  NODE_HARVESTER,
  NODE_ROLE_ACTION_CHARGES_PER_TURN,
  NODE_STRIKER,
  OBJECT_CORE,
  OBJECT_MODULE,
  OBJECT_NODE,
  PLAYER_ONE,
  PLAYER_TWO,
  PLAYERS,
  REPAIR_ACTIONS_PER_TURN,
  START_CORE_HP,
  START_RESOURCE,
  STRIKER_CORE_DAMAGE,
  STRIKER_UPGRADE_RESOURCE_COST,
  isPlayerId,
  otherPlayer,
  playerLabel
} from "./constants.js";
import {
  actionToPayload,
  addCells,
  cellKey,
  cloneCell,
  containsCell as containsCellInRadius,
  parseAction,
  sameCell,
  isValidActionShape
} from "./gameAction.js";
import type {
  ActionPayload,
  ApplyResult,
  Cell,
  GameObject,
  ModuleKind,
  ModuleObject,
  NodeObject,
  NodeRole,
  NormalizedAction,
  PlayerId,
  Snapshot
} from "./types.js";

export class MatchState {
  readonly boardRadius: number;
  private objects = new Map<string, GameObject>();
  private coreHp: Record<PlayerId, number> = { player_1: START_CORE_HP, player_2: START_CORE_HP };
  private resources: Record<PlayerId, number> = { player_1: START_RESOURCE, player_2: START_RESOURCE };
  private endedTurnThisRound: Record<PlayerId, boolean> = { player_1: false, player_2: false };

  currentPlayer: PlayerId = PLAYER_ONE;
  finished = false;
  statusMessage = "Player 1: build, repair, upgrade, or end turn";
  turnNumber = 1;
  roundNumber = 1;
  connectionActionsLeft = CONNECTION_ACTIONS_PER_TURN;
  repairActionsLeft = REPAIR_ACTIONS_PER_TURN;
  upkeepMessage = "Upkeep: ready";
  moveHistory: Array<Record<string, unknown>> = [];

  constructor(boardRadius = 3) {
    this.boardRadius = boardRadius;
    this.setupMatch();
  }

  setupMatch(): void {
    this.objects.clear();
    this.coreHp = { player_1: START_CORE_HP, player_2: START_CORE_HP };
    this.resources = { player_1: START_RESOURCE, player_2: START_RESOURCE };
    this.resetRoundActions();
    this.currentPlayer = PLAYER_ONE;
    this.resetTurnActionLimits();
    this.upkeepMessage = "Upkeep: ready";
    this.finished = false;
    this.statusMessage = `${playerLabel(this.currentPlayer)}: build, repair, upgrade, or end turn`;
    this.turnNumber = 1;
    this.roundNumber = 1;
    this.moveHistory = [];

    this.addObject({ q: -this.boardRadius, r: 0 }, OBJECT_CORE, PLAYER_ONE);
    this.addObject({ q: this.boardRadius, r: 0 }, OBJECT_CORE, PLAYER_TWO);
    this.updateActiveNodes();
  }

  toSnapshot(): Snapshot {
    return {
      players: [...PLAYERS],
      current_player: this.currentPlayer,
      turn: this.turnNumber,
      round: this.roundNumber,
      core_hp: { ...this.coreHp },
      resources: { ...this.resources },
      action_limits: {
        connection_actions_left: this.connectionActionsLeft,
        repair_actions_left: this.repairActionsLeft
      },
      objects: this.objectsToSnapshot(),
      finished: this.finished,
      status_message: this.statusMessage
    };
  }

  applyAction(rawAction: unknown): ApplyResult {
    const action = parseAction(rawAction);

    if (!isValidActionShape(action)) {
      this.statusMessage = "Invalid action";
      return this.result(false, this.statusMessage, action);
    }

    if (this.finished) {
      return this.result(false, this.statusMessage, action);
    }

    if (!isPlayerId(action.player) || action.player !== this.currentPlayer) {
      this.statusMessage = `Expected ${playerLabel(this.currentPlayer)}, got ${playerLabel(action.player)}`;
      return this.result(false, this.statusMessage, action);
    }

    switch (action.type) {
      case ACTION_PLACE_NODE:
        return this.applyPlaceNode(action);
      case ACTION_REPAIR_NODE:
        return this.applyRepairNode(action);
      case ACTION_BREAK_NODE:
        return this.applyBreakNode(action);
      case ACTION_CLEAR_NODE:
        return this.applyClearNode(action);
      case ACTION_UPGRADE_HARVESTER:
        return this.applyUpgradeNode(action, NODE_HARVESTER);
      case ACTION_UPGRADE_STRIKER:
        return this.applyUpgradeNode(action, NODE_STRIKER);
      case ACTION_UPGRADE_DEFENDER:
        return this.applyUpgradeNode(action, NODE_DEFENDER);
      case ACTION_UPGRADE_HACKER:
        return this.applyUpgradeNode(action, NODE_HACKER);
      case ACTION_BUILD_CONNECTION_MODULE:
        return this.applyBuildModule(action, MODULE_CONNECTION);
      case ACTION_BUILD_REPAIR_MODULE:
        return this.applyBuildModule(action, MODULE_REPAIR);
      case ACTION_STRIKER_ATTACK:
        return this.applyStrikerAttack(action);
      case ACTION_HACKER_HACK:
        return this.applyHackerHack(action);
      case ACTION_SKIP:
        return this.applySkip(action);
      default:
        this.statusMessage = `Unknown action: ${action.type}`;
        return this.result(false, this.statusMessage, action);
    }
  }

  canPlaceNode(cell: Cell): boolean {
    if (!this.containsCell(cell)) return false;
    if (this.isControlPoint(cell)) return false;
    if (this.hasObject(cell)) return false;
    return this.hasActiveNetworkNeighbor(this.currentPlayer, cell);
  }

  canBuildModule(cell: Cell): boolean {
    return this.canBuildModuleForPlayer(this.currentPlayer, cell);
  }

  canRepairNode(cell: Cell): boolean {
    if (!this.containsCell(cell)) return false;

    const object = this.getObject(cell);
    if (!object) return false;
    if (object.type !== OBJECT_NODE && object.type !== OBJECT_MODULE) return false;
    if (object.owner !== this.currentPlayer) return false;
    return object.disabled;
  }

  canUpgradeNode(cell: Cell): boolean {
    return this.canUpgradeNodeForPlayer(this.currentPlayer, cell);
  }

  canStrikerAttack(sourceCell: Cell, targetCell: Cell): boolean {
    return this.canStrikerAttackForPlayer(this.currentPlayer, sourceCell, targetCell);
  }

  canHackerHack(sourceCell: Cell, targetCell: Cell): boolean {
    return this.canHackerHackForPlayer(this.currentPlayer, sourceCell, targetCell);
  }

  containsCell(cell: Cell): boolean {
    return containsCellInRadius(cell, this.boardRadius);
  }

  getObject(cell: Cell): GameObject | undefined {
    return this.objects.get(cellKey(cell));
  }

  private hasObject(cell: Cell): boolean {
    return this.objects.has(cellKey(cell));
  }

  private isControlPoint(cell: Cell): boolean {
    return sameCell(cell, CONTROL_POINT);
  }

  private applyPlaceNode(action: NormalizedAction): ApplyResult {
    if (!this.canPlaceNode(action.cell)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot place there`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.canAffordAction(this.currentPlayer, action.type)) {
      this.statusMessage = this.actionLimitRequirementMessage(action.type);
      return this.result(false, this.statusMessage, action);
    }

    this.spendConnectionAction();
    this.addObject(action.cell, OBJECT_NODE, this.currentPlayer);
    this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} placed a node`);
    return this.result(true, this.statusMessage, action);
  }

  private applyRepairNode(action: NormalizedAction): ApplyResult {
    if (!this.canRepairNode(action.cell)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot repair that object`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.canAffordAction(this.currentPlayer, action.type)) {
      this.statusMessage = this.actionLimitRequirementMessage(action.type);
      return this.result(false, this.statusMessage, action);
    }

    this.spendRepairAction();
    const object = this.getObject(action.cell);
    if (object) {
      object.disabled = false;
      if (object.type === OBJECT_MODULE) {
        object.ready = false;
      }
    }
    this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} repaired a ${this.objectTypeLabel(this.getObject(action.cell))}`);
    return this.result(true, this.statusMessage, action);
  }

  private applyBuildModule(action: NormalizedAction, moduleKind: ModuleKind): ApplyResult {
    if (!this.canBuildModule(action.cell)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot build a module there`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.canAffordTargetAction(this.currentPlayer, action.type, action.cell)) {
      const moduleCost = this.actionTargetResourceCost(this.currentPlayer, action.type, action.cell);
      this.statusMessage = this.actionResourceRequirementMessage(action.type, moduleCost);
      return this.result(false, this.statusMessage, action);
    }

    this.spendResource(this.currentPlayer, this.actionResourceCost(action.type));
    this.addObject(action.cell, OBJECT_MODULE, this.currentPlayer, moduleKind);
    this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} built a ${this.moduleKindLabel(moduleKind)} Module`);
    return this.result(true, this.statusMessage, action);
  }

  private applyBreakNode(action: NormalizedAction): ApplyResult {
    if (!this.containsCell(action.cell)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot break that cell`;
      return this.result(false, this.statusMessage, action);
    }

    const object = this.getObject(action.cell);
    if (!object || !this.isDisableTarget(object) || object.disabled || object.owner === this.currentPlayer) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot break that cell`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.hasActiveNetworkNeighbor(this.currentPlayer, action.cell)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} needs an active network neighbor to break that object`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.canAffordAction(this.currentPlayer, action.type)) {
      this.statusMessage = this.actionLimitRequirementMessage(action.type);
      return this.result(false, this.statusMessage, action);
    }

    object.disabled = true;
    object.active = false;
    this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} disabled an enemy ${this.objectTypeLabel(object)}`);
    return this.result(true, this.statusMessage, action);
  }

  private applyClearNode(action: NormalizedAction): ApplyResult {
    if (!this.canClearNode(action.cell)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot clear that cell`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.canAffordTargetAction(this.currentPlayer, action.type, action.cell)) {
      this.statusMessage = this.actionLimitRequirementMessage(action.type);
      return this.result(false, this.statusMessage, action);
    }

    const object = this.getObject(action.cell);
    if (!object) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot clear that cell`;
      return this.result(false, this.statusMessage, action);
    }

    const objectOwner = object.owner;
    const objectLabel = this.objectTypeLabel(object);
    this.objects.delete(cellKey(action.cell));
    const clearMessage =
      objectOwner === this.currentPlayer
        ? `${playerLabel(this.currentPlayer)} cleared a friendly disabled ${objectLabel}`
        : `${playerLabel(this.currentPlayer)} cleared an enemy disabled ${objectLabel}`;

    this.completeSuccessfulAction(action, clearMessage);
    return this.result(true, this.statusMessage, action);
  }

  private applyUpgradeNode(action: NormalizedAction, role: NodeRole): ApplyResult {
    if (!this.canUpgradeNodeToRole(this.currentPlayer, action.cell, role)) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot upgrade that node`;
      return this.result(false, this.statusMessage, action);
    }

    if (!this.canAffordTargetAction(this.currentPlayer, action.type, action.cell)) {
      const upgradeCost = this.actionTargetResourceCost(this.currentPlayer, action.type, action.cell);
      this.statusMessage = this.actionResourceRequirementMessage(action.type, upgradeCost);
      return this.result(false, this.statusMessage, action);
    }

    this.spendResource(this.currentPlayer, this.actionResourceCost(action.type));
    const object = this.getObject(action.cell);
    if (object?.type === OBJECT_NODE) {
      object.role = role;
      object.ready = false;
      object.action_charges = 0;
    }

    this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} upgraded a ${this.nodeRoleLabel(role)}`);
    return this.result(true, this.statusMessage, action);
  }

  private applyStrikerAttack(action: NormalizedAction): ApplyResult {
    if (!this.canStrikerAttackForPlayer(this.currentPlayer, action.sourceCell, action.cell)) {
      this.statusMessage = this.strikerAttackStatusMessage(this.currentPlayer, action.sourceCell, action.cell);
      return this.result(false, this.statusMessage, action);
    }

    const target = this.getObject(action.cell);
    if (!target) {
      this.statusMessage = `${playerLabel(this.currentPlayer)} cannot strike that target`;
      return this.result(false, this.statusMessage, action);
    }

    const defenderCell = this.blockingDefenderCell(this.currentPlayer, action.cell);

    if (!sameCell(defenderCell, INVALID_CELL)) {
      const striker = this.getObject(action.sourceCell);
      const defender = this.getObject(defenderCell);
      if (striker?.type === OBJECT_NODE) striker.action_charges = 0;
      if (defender?.type === OBJECT_NODE) defender.action_charges = 0;
      this.completeSuccessfulAction(action, `${playerLabel(target.owner)} Defender blocked a Striker attack`);
      return this.result(true, this.statusMessage, action);
    }

    if (target.type === OBJECT_NODE || target.type === OBJECT_MODULE) {
      target.disabled = true;
      target.active = false;
      if (target.type === OBJECT_MODULE) target.ready = false;
      const striker = this.getObject(action.sourceCell);
      if (striker?.type === OBJECT_NODE) striker.action_charges = 0;
      this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} Striker disabled an enemy ${this.objectTypeLabel(target)}`);
      return this.result(true, this.statusMessage, action);
    }

    if (target.type === OBJECT_CORE) {
      this.coreHp[target.owner] = Math.max(0, this.coreHp[target.owner] - STRIKER_CORE_DAMAGE);
      const striker = this.getObject(action.sourceCell);
      if (striker?.type === OBJECT_NODE) striker.action_charges = 0;
      this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} Striker hit the enemy Core`);
      this.checkFinishedAfterAction(this.statusMessage);
      return this.result(true, this.statusMessage, action);
    }

    this.statusMessage = `${playerLabel(this.currentPlayer)} cannot strike that target`;
    return this.result(false, this.statusMessage, action);
  }

  private applyHackerHack(action: NormalizedAction): ApplyResult {
    if (!this.canHackerHackForPlayer(this.currentPlayer, action.sourceCell, action.cell)) {
      this.statusMessage = this.hackerHackStatusMessage(this.currentPlayer, action.sourceCell, action.cell);
      return this.result(false, this.statusMessage, action);
    }

    const target = this.getObject(action.cell);
    const hacker = this.getObject(action.sourceCell);
    if (target?.type === OBJECT_NODE) {
      target.owner = this.currentPlayer;
      target.disabled = true;
      target.active = false;
      target.ready = false;
      target.action_charges = 0;
    }
    if (hacker?.type === OBJECT_NODE) {
      hacker.action_charges = 0;
    }

    this.completeSuccessfulAction(action, `${playerLabel(this.currentPlayer)} Hacker took control of a disabled Node`);
    return this.result(true, this.statusMessage, action);
  }

  private applySkip(action: NormalizedAction): ApplyResult {
    this.completeTurn(action, `${playerLabel(this.currentPlayer)} ended turn`);
    return this.result(true, this.statusMessage, action);
  }

  private completeSuccessfulAction(action: NormalizedAction, message: string): void {
    this.recordMove(action, message);
    this.updateActiveNodes();
    this.statusMessage = message;
    this.turnNumber += 1;
  }

  private checkFinishedAfterAction(message: string): void {
    if (this.isDraw()) {
      this.finished = true;
      this.statusMessage = `${message}. Draw: both Cores destroyed`;
      return;
    }

    const winner = this.winner();
    if (winner) {
      this.finished = true;
      this.statusMessage = `${message}. ${playerLabel(winner)} wins`;
    }
  }

  private completeTurn(action: NormalizedAction, message: string): void {
    this.recordMove(action, message);
    this.endedTurnThisRound[action.player as PlayerId] = true;
    this.endTurn(message);
    this.turnNumber += 1;
  }

  private recordMove(action: NormalizedAction, message: string): void {
    this.moveHistory.push({
      turn: this.turnNumber,
      player: action.player,
      type: action.type,
      has_cell: action.hasCell,
      cell: cloneCell(action.cell),
      has_source_cell: action.hasSourceCell,
      source_cell: cloneCell(action.sourceCell),
      message,
      connection_actions_left: this.connectionActionsLeft,
      repair_actions_left: this.repairActionsLeft,
      round: this.roundNumber
    });
  }

  private endTurn(message: string): void {
    this.updateActiveNodes();
    const finalMessage = message;

    if (this.roundReadyToAdvance()) {
      this.roundNumber += 1;
      this.resetRoundActions();
    }

    if (this.isDraw()) {
      this.finished = true;
      this.statusMessage = `${finalMessage}. Draw: both Cores destroyed`;
      return;
    }

    const winner = this.winner();
    if (winner) {
      this.finished = true;
      this.statusMessage = `${finalMessage}. ${playerLabel(winner)} wins`;
      return;
    }

    this.currentPlayer = otherPlayer(this.currentPlayer);
    this.startTurnForPlayer(this.currentPlayer);
    this.statusMessage = `${finalMessage}. ${this.upkeepMessage}`;
  }

  private roundReadyToAdvance(): boolean {
    return this.endedTurnThisRound[PLAYER_ONE] && this.endedTurnThisRound[PLAYER_TWO];
  }

  private resetRoundActions(): void {
    this.endedTurnThisRound = { player_1: false, player_2: false };
  }

  private isDraw(): boolean {
    return this.coreHp[PLAYER_ONE] <= 0 && this.coreHp[PLAYER_TWO] <= 0;
  }

  private winner(): PlayerId | "" {
    if (this.isDraw()) return "";
    if (this.coreHp[PLAYER_ONE] <= 0) return PLAYER_TWO;
    if (this.coreHp[PLAYER_TWO] <= 0) return PLAYER_ONE;
    return "";
  }

  private updateActiveNodes(): void {
    for (const object of this.objects.values()) {
      object.active = object.type === OBJECT_CORE && !object.disabled;
    }

    this.markActiveNetwork(PLAYER_ONE);
    this.markActiveNetwork(PLAYER_TWO);
    this.markActiveModules(PLAYER_ONE);
    this.markActiveModules(PLAYER_TWO);
  }

  private markActiveNetwork(owner: PlayerId): void {
    const queue: Cell[] = [];
    const visited = new Set<string>();

    for (const object of this.objects.values()) {
      if (object.type === OBJECT_CORE && object.owner === owner) {
        queue.push(cloneCell(object.cell));
        visited.add(cellKey(object.cell));
        break;
      }
    }

    while (queue.length > 0) {
      const cell = queue.shift()!;
      const object = this.objects.get(cellKey(cell));
      if (object) {
        object.active = true;
      }

      for (const direction of DIRECTIONS) {
        const neighbor = addCells(cell, direction);
        const key = cellKey(neighbor);
        if (visited.has(key) || !this.objects.has(key)) continue;

        const neighborObject = this.objects.get(key)!;
        if (neighborObject.owner !== owner) continue;
        if (neighborObject.disabled) continue;
        if (!this.isNetworkObject(neighborObject)) continue;

        visited.add(key);
        queue.push(neighbor);
      }
    }
  }

  private markActiveModules(owner: PlayerId): void {
    for (const object of this.objects.values()) {
      if (object.type !== OBJECT_MODULE) continue;
      if (object.owner !== owner) continue;

      if (object.disabled) {
        object.active = false;
        object.ready = false;
        continue;
      }

      object.active = this.hasActiveNetworkNeighbor(owner, object.cell);
      if (!object.active) {
        object.ready = false;
      }
    }
  }

  private canBuildModuleForPlayer(player: PlayerId, cell: Cell): boolean {
    if (!this.containsCell(cell)) return false;
    if (this.isControlPoint(cell)) return false;
    if (this.hasObject(cell)) return false;
    return this.hasActiveNetworkNeighbor(player, cell);
  }

  private canClearNode(cell: Cell): boolean {
    if (!this.containsCell(cell)) return false;

    const object = this.getObject(cell);
    if (!object) return false;
    if (!this.isClearTarget(object)) return false;
    if (!object.disabled) return false;
    if (object.owner === this.currentPlayer) return true;
    return this.hasActiveNetworkNeighbor(this.currentPlayer, cell);
  }

  private canUpgradeNodeForPlayer(player: PlayerId, cell: Cell): boolean {
    if (!this.containsCell(cell)) return false;

    const object = this.getObject(cell);
    if (!object) return false;
    if (object.type !== OBJECT_NODE) return false;
    if (object.owner !== player) return false;
    if (object.disabled) return false;
    if (!object.active) return false;
    return object.role === NODE_CONDUIT;
  }

  private canUpgradeNodeToRole(player: PlayerId, cell: Cell, role: NodeRole): boolean {
    if (!this.canUpgradeNodeForPlayer(player, cell)) return false;
    if (role === NODE_HARVESTER) return this.areNeighbors(cell, CONTROL_POINT);
    return true;
  }

  private canSelectStrikerSource(player: PlayerId, cell: Cell): boolean {
    const object = this.getObject(cell);
    if (!this.containsCell(cell) || !object) return false;
    if (object.type !== OBJECT_NODE) return false;
    if (object.owner !== player) return false;
    if (object.role !== NODE_STRIKER) return false;
    if (object.disabled) return false;
    if (!object.active) return false;
    if (!object.ready) return false;
    return object.action_charges > 0;
  }

  private canSelectHackerSource(player: PlayerId, cell: Cell): boolean {
    const object = this.getObject(cell);
    if (!this.containsCell(cell) || !object) return false;
    if (object.type !== OBJECT_NODE) return false;
    if (object.owner !== player) return false;
    if (object.role !== NODE_HACKER) return false;
    if (object.disabled) return false;
    if (!object.active) return false;
    if (!object.ready) return false;
    return object.action_charges > 0;
  }

  private canStrikerAttackForPlayer(player: PlayerId, sourceCell: Cell, targetCell: Cell): boolean {
    if (!this.canSelectStrikerSource(player, sourceCell)) return false;
    if (!this.containsCell(targetCell)) return false;
    if (sameCell(sourceCell, targetCell)) return false;
    if (!this.areNeighbors(sourceCell, targetCell)) return false;

    const target = this.getObject(targetCell);
    if (!target) return false;
    if (target.owner === player) return false;

    if (target.type === OBJECT_NODE) return !target.disabled;
    if (target.type === OBJECT_MODULE) return !target.disabled && target.active;
    if (target.type === OBJECT_CORE) return true;
    return false;
  }

  private canHackerHackForPlayer(player: PlayerId, sourceCell: Cell, targetCell: Cell): boolean {
    if (!this.canSelectHackerSource(player, sourceCell)) return false;
    if (!this.containsCell(targetCell)) return false;
    if (sameCell(sourceCell, targetCell)) return false;
    if (!this.areNeighbors(sourceCell, targetCell)) return false;

    const target = this.getObject(targetCell);
    if (!target) return false;
    if (target.owner === player) return false;
    if (target.type !== OBJECT_NODE) return false;
    return target.disabled;
  }

  private strikerSourceStatusMessage(player: PlayerId, cell: Cell): string {
    const object = this.getObject(cell);

    if (!object || object.type !== OBJECT_NODE || object.owner !== player || object.role !== NODE_STRIKER) {
      return "Select your ready Striker to attack";
    }
    if (object.disabled) return `${playerLabel(player)} Striker is disabled`;
    if (!object.active) return `${playerLabel(player)} Striker is inactive`;
    if (!object.ready) return `${playerLabel(player)} Striker is not ready`;
    if (object.action_charges <= 0) return `${playerLabel(player)} Striker has no charge`;
    return `${playerLabel(player)} Striker ready`;
  }

  private hackerSourceStatusMessage(player: PlayerId, cell: Cell): string {
    const object = this.getObject(cell);

    if (!object || object.type !== OBJECT_NODE || object.owner !== player || object.role !== NODE_HACKER) {
      return "Select your ready Hacker to hack";
    }
    if (object.disabled) return `${playerLabel(player)} Hacker is disabled`;
    if (!object.active) return `${playerLabel(player)} Hacker is inactive`;
    if (!object.ready) return `${playerLabel(player)} Hacker is not ready`;
    if (object.action_charges <= 0) return `${playerLabel(player)} Hacker has no charge`;
    return `${playerLabel(player)} Hacker ready`;
  }

  private strikerAttackStatusMessage(player: PlayerId, sourceCell: Cell, targetCell: Cell): string {
    if (!this.canSelectStrikerSource(player, sourceCell)) return this.strikerSourceStatusMessage(player, sourceCell);
    if (!this.containsCell(targetCell)) return `${playerLabel(player)} Striker target is outside the board`;
    if (!this.areNeighbors(sourceCell, targetCell)) return `${playerLabel(player)} Striker can only hit adjacent targets`;

    const target = this.getObject(targetCell);
    if (!target) return `${playerLabel(player)} Striker needs an enemy target`;
    if (target.owner === player) return `${playerLabel(player)} Striker cannot target friendly objects`;
    if (this.isDisableTarget(target) && target.disabled) return `${playerLabel(player)} Striker target is already disabled`;
    if (target.type === OBJECT_MODULE && !target.active) return `${playerLabel(player)} Striker target module is inactive`;
    return `${playerLabel(player)} cannot strike that target`;
  }

  private hackerHackStatusMessage(player: PlayerId, sourceCell: Cell, targetCell: Cell): string {
    if (!this.canSelectHackerSource(player, sourceCell)) return this.hackerSourceStatusMessage(player, sourceCell);
    if (!this.containsCell(targetCell)) return `${playerLabel(player)} Hacker target is outside the board`;
    if (!this.areNeighbors(sourceCell, targetCell)) return `${playerLabel(player)} Hacker can only hack adjacent targets`;

    const target = this.getObject(targetCell);
    if (!target) return `${playerLabel(player)} Hacker needs a disabled enemy Node`;
    if (target.owner === player) return `${playerLabel(player)} Hacker cannot target friendly nodes`;
    if (target.type !== OBJECT_NODE) return `${playerLabel(player)} Hacker can only target Nodes`;
    if (!target.disabled) return `${playerLabel(player)} Hacker target must be disabled`;
    return `${playerLabel(player)} cannot hack that target`;
  }

  private blockingDefenderCell(attacker: PlayerId, targetCell: Cell): Cell {
    const target = this.getObject(targetCell);
    if (!target) return cloneCell(INVALID_CELL);

    const targetOwner = target.owner;
    if (targetOwner === attacker) return cloneCell(INVALID_CELL);

    for (const direction of DIRECTIONS) {
      const defenderCell = addCells(targetCell, direction);
      const defender = this.getObject(defenderCell);

      if (!defender) continue;
      if (defender.type !== OBJECT_NODE) continue;
      if (defender.owner !== targetOwner) continue;
      if (defender.role !== NODE_DEFENDER) continue;
      if (defender.disabled) continue;
      if (!defender.active) continue;
      if (!defender.ready) continue;
      if (defender.action_charges > 0) return defenderCell;
    }

    return cloneCell(INVALID_CELL);
  }

  private hasActiveNetworkNeighbor(owner: PlayerId, cell: Cell): boolean {
    for (const direction of DIRECTIONS) {
      const neighborObject = this.getObject(addCells(cell, direction));
      if (!neighborObject) continue;
      if (neighborObject.owner !== owner) continue;
      if (!neighborObject.active) continue;
      if (this.isNetworkObject(neighborObject)) return true;
    }

    return false;
  }

  private areNeighbors(firstCell: Cell, secondCell: Cell): boolean {
    return DIRECTIONS.some((direction) => sameCell(addCells(firstCell, direction), secondCell));
  }

  private isNetworkObject(object: GameObject): boolean {
    return object.type === OBJECT_CORE || object.type === OBJECT_NODE;
  }

  private isDisableTarget(object: GameObject): boolean {
    return object.type === OBJECT_NODE || object.type === OBJECT_MODULE;
  }

  private isClearTarget(object: GameObject): boolean {
    return object.type === OBJECT_NODE || object.type === OBJECT_MODULE;
  }

  private activeModuleBonus(player: PlayerId, moduleKind: ModuleKind): number {
    let bonus = 0;

    for (const object of this.objects.values()) {
      if (object.type !== OBJECT_MODULE) continue;
      if (object.owner !== player) continue;
      if (object.module_kind !== moduleKind) continue;
      if (object.disabled) continue;
      if (object.active && object.ready) bonus += 1;
    }

    return bonus;
  }

  private harvesterResourceGain(player: PlayerId): number {
    let gain = 0;

    for (const direction of DIRECTIONS) {
      const object = this.getObject(addCells(CONTROL_POINT, direction));
      if (!object) continue;
      if (object.owner !== player) continue;
      if (object.type !== OBJECT_NODE) continue;
      if (object.role !== NODE_HARVESTER) continue;
      if (object.disabled) continue;
      if (!object.ready) continue;
      if (object.active) gain += HARVESTER_RESOURCE_GAIN;
    }

    return gain;
  }

  private addObject(cell: Cell, type: "core" | "node" | "module", owner: PlayerId, moduleKind?: ModuleKind): void {
    let object: GameObject;

    if (type === OBJECT_NODE) {
      object = {
        cell: cloneCell(cell),
        type,
        owner,
        active: false,
        disabled: false,
        role: NODE_CONDUIT,
        ready: false,
        action_charges: 0
      };
    } else if (type === OBJECT_MODULE) {
      object = {
        cell: cloneCell(cell),
        type,
        owner,
        active: false,
        disabled: false,
        module_kind: moduleKind ?? MODULE_CONNECTION,
        ready: false
      };
    } else {
      object = {
        cell: cloneCell(cell),
        type,
        owner,
        active: true,
        disabled: false
      };
    }

    this.objects.set(cellKey(cell), object);
  }

  private startTurnForPlayer(player: PlayerId): void {
    this.updateActiveNodes();
    this.readyModulesForPlayer(player);
    this.resetTurnActionLimits(player);

    const chargedNodes = this.resetRoleNodeActionCharges(player);
    const resourceGain = this.harvesterResourceGain(player);
    if (resourceGain > 0) {
      this.resources[player] += resourceGain;
    }

    this.upkeepMessage = this.formatUpkeepMessage(player, resourceGain, chargedNodes);
  }

  private resetRoleNodeActionCharges(player: PlayerId): number {
    let chargedNodes = 0;

    for (const object of this.objects.values()) {
      if (object.type !== OBJECT_NODE) continue;
      if (object.owner !== player) continue;

      if (object.role === NODE_CONDUIT || object.disabled) {
        object.ready = false;
        object.action_charges = 0;
        continue;
      }

      object.ready = true;
      object.action_charges = NODE_ROLE_ACTION_CHARGES_PER_TURN;
      chargedNodes += 1;
    }

    return chargedNodes;
  }

  private readyModulesForPlayer(player: PlayerId): number {
    let readyModules = 0;

    for (const object of this.objects.values()) {
      if (object.type !== OBJECT_MODULE) continue;
      if (object.owner !== player) continue;

      const isReady = object.active && !object.disabled;
      object.ready = isReady;
      if (isReady) readyModules += 1;
    }

    return readyModules;
  }

  private formatUpkeepMessage(player: PlayerId, resourceGain: number, chargedNodes: number): string {
    const messages: string[] = [];

    if (resourceGain > 0) messages.push(`+${resourceGain}R`);
    if (chargedNodes > 0) messages.push(`${chargedNodes} role charge${chargedNodes === 1 ? "" : "s"} ready`);

    const connectionBonus = this.activeModuleBonus(player, MODULE_CONNECTION);
    const repairBonus = this.activeModuleBonus(player, MODULE_REPAIR);

    if (connectionBonus > 0) messages.push(`+${connectionBonus} connection action${connectionBonus === 1 ? "" : "s"}`);
    if (repairBonus > 0) messages.push(`+${repairBonus} repair action${repairBonus === 1 ? "" : "s"}`);
    if (messages.length === 0) messages.push("ready");

    return `Upkeep: ${playerLabel(player)} ${messages.join(", ")}`;
  }

  private resetTurnActionLimits(player: PlayerId = this.currentPlayer): void {
    this.connectionActionsLeft = CONNECTION_ACTIONS_PER_TURN + this.activeModuleBonus(player, MODULE_CONNECTION);
    this.repairActionsLeft = REPAIR_ACTIONS_PER_TURN + this.activeModuleBonus(player, MODULE_REPAIR);
  }

  private spendResource(player: PlayerId, amount: number): void {
    this.resources[player] = Math.max(0, this.resources[player] - amount);
  }

  private spendConnectionAction(): void {
    this.connectionActionsLeft = Math.max(0, this.connectionActionsLeft - 1);
  }

  private spendRepairAction(): void {
    this.repairActionsLeft = Math.max(0, this.repairActionsLeft - 1);
  }

  private canAffordAction(player: PlayerId, actionType: string): boolean {
    if (this.actionUsesResource(actionType)) return this.resources[player] >= this.actionResourceCost(actionType);
    if (this.actionUsesConnectionLimit(actionType)) return this.connectionActionsLeft > 0;
    if (this.actionUsesRepairLimit(actionType)) return this.repairActionsLeft > 0;
    return true;
  }

  private canAffordTargetAction(player: PlayerId, actionType: string, cell: Cell): boolean {
    if (this.actionUsesResource(actionType)) return this.resources[player] >= this.actionTargetResourceCost(player, actionType, cell);
    if (this.actionUsesConnectionLimit(actionType)) return this.connectionActionsLeft > 0;
    if (this.actionUsesRepairLimit(actionType)) return this.repairActionsLeft > 0;
    return true;
  }

  private actionResourceCost(actionType: string): number {
    switch (actionType) {
      case ACTION_UPGRADE_HARVESTER:
        return HARVESTER_UPGRADE_RESOURCE_COST;
      case ACTION_UPGRADE_STRIKER:
        return STRIKER_UPGRADE_RESOURCE_COST;
      case ACTION_UPGRADE_DEFENDER:
        return DEFENDER_UPGRADE_RESOURCE_COST;
      case ACTION_UPGRADE_HACKER:
        return HACKER_UPGRADE_RESOURCE_COST;
      case ACTION_BUILD_CONNECTION_MODULE:
      case ACTION_BUILD_REPAIR_MODULE:
        return MODULE_BUILD_RESOURCE_COST;
      default:
        return 0;
    }
  }

  private actionTargetResourceCost(_player: PlayerId, actionType: string, _cell: Cell): number {
    return this.actionResourceCost(actionType);
  }

  private actionUsesResource(actionType: string): boolean {
    return [
      ACTION_UPGRADE_HARVESTER,
      ACTION_UPGRADE_STRIKER,
      ACTION_UPGRADE_DEFENDER,
      ACTION_UPGRADE_HACKER,
      ACTION_BUILD_CONNECTION_MODULE,
      ACTION_BUILD_REPAIR_MODULE
    ].includes(actionType);
  }

  private actionUsesConnectionLimit(actionType: string): boolean {
    return actionType === ACTION_PLACE_NODE;
  }

  private actionUsesRepairLimit(actionType: string): boolean {
    return actionType === ACTION_REPAIR_NODE;
  }

  private actionLimitRequirementMessage(actionType: string): string {
    let limitLabel = "action";
    if (this.actionUsesConnectionLimit(actionType)) limitLabel = "connection action";
    else if (this.actionUsesRepairLimit(actionType)) limitLabel = "repair action";
    return `${playerLabel(this.currentPlayer)} needs a ${limitLabel} to ${this.actionVerb(actionType)}`;
  }

  private actionResourceRequirementMessage(actionType: string, requiredCost = -1): string {
    const cost = requiredCost < 0 ? this.actionResourceCost(actionType) : requiredCost;
    return `${playerLabel(this.currentPlayer)} needs ${cost} Resource to ${this.actionVerb(actionType)}`;
  }

  private actionVerb(actionType: string): string {
    switch (actionType) {
      case ACTION_PLACE_NODE:
        return "place";
      case ACTION_REPAIR_NODE:
        return "repair";
      case ACTION_BREAK_NODE:
        return "break";
      case ACTION_CLEAR_NODE:
        return "clear";
      case ACTION_UPGRADE_HARVESTER:
        return "upgrade a Harvester";
      case ACTION_UPGRADE_STRIKER:
        return "upgrade a Striker";
      case ACTION_UPGRADE_DEFENDER:
        return "upgrade a Defender";
      case ACTION_UPGRADE_HACKER:
        return "upgrade a Hacker";
      case ACTION_BUILD_CONNECTION_MODULE:
        return "build a Connection Module";
      case ACTION_BUILD_REPAIR_MODULE:
        return "build a Repair Module";
      case ACTION_STRIKER_ATTACK:
        return "strike";
      case ACTION_HACKER_HACK:
        return "hack";
      case ACTION_SKIP:
        return "skip";
      default:
        return actionType;
    }
  }

  private nodeRoleLabel(role: NodeRole): string {
    switch (role) {
      case NODE_HARVESTER:
        return "Harvester";
      case NODE_STRIKER:
        return "Striker";
      case NODE_DEFENDER:
        return "Defender";
      case NODE_HACKER:
        return "Hacker";
      default:
        return "Conduit";
    }
  }

  private moduleKindLabel(moduleKind: ModuleKind): string {
    switch (moduleKind) {
      case MODULE_CONNECTION:
        return "Connection";
      case MODULE_REPAIR:
        return "Repair";
      default:
        return moduleKind;
    }
  }

  private objectTypeLabel(object: GameObject | undefined): string {
    if (!object) return "object";
    if (object.type === OBJECT_MODULE) return `${this.moduleKindLabel(object.module_kind).toLowerCase()} module`;
    if (object.type === OBJECT_NODE) return "node";
    if (object.type === OBJECT_CORE) return "Core";
    return "object";
  }

  private objectsToSnapshot(): Snapshot["objects"] {
    return Array.from(this.objects.values())
      .map((object) => this.objectToSnapshot(object))
      .sort((first, second) => {
        if (first.cell.q === second.cell.q) return first.cell.r - second.cell.r;
        return first.cell.q - second.cell.q;
      });
  }

  private objectToSnapshot(object: GameObject): Snapshot["objects"][number] {
    if (object.type === OBJECT_NODE) {
      const snapshot: NodeObject = {
        cell: cloneCell(object.cell),
        type: object.type,
        owner: object.owner,
        active: object.active,
        disabled: object.disabled,
        role: object.role,
        ready: object.ready,
        action_charges: object.action_charges
      };
      return snapshot;
    }

    if (object.type === OBJECT_MODULE) {
      const snapshot: ModuleObject = {
        cell: cloneCell(object.cell),
        type: object.type,
        owner: object.owner,
        active: object.active,
        disabled: object.disabled,
        module_kind: object.module_kind,
        ready: object.ready
      };
      return snapshot;
    }

    return {
      cell: cloneCell(object.cell),
      type: object.type,
      owner: object.owner,
      active: object.active,
      disabled: object.disabled
    };
  }

  private result(ok: boolean, message: string, action?: NormalizedAction): ApplyResult {
    const result: ApplyResult = {
      ok,
      message,
      snapshot: this.toSnapshot()
    };

    if (action) {
      result.action = actionToPayload(action);
    }

    return result;
  }
}

export function applyAction(state: MatchState, action: ActionPayload): ApplyResult {
  return state.applyAction(action);
}
