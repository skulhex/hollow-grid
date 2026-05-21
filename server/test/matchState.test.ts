import { describe, expect, it } from "vitest";
import { MatchState } from "../src/game/matchState.js";
import type { ActionPayload, Cell, PlayerId } from "../src/game/types.js";

describe("MatchState", () => {
  it("creates the initial match snapshot", () => {
    const state = new MatchState();
    const snapshot = state.toSnapshot();

    expect(snapshot.players).toEqual(["player_1", "player_2"]);
    expect(snapshot.current_player).toBe("player_1");
    expect(snapshot.turn).toBe(1);
    expect(snapshot.round).toBe(1);
    expect(snapshot.core_hp).toEqual({ player_1: 5, player_2: 5 });
    expect(snapshot.resources).toEqual({ player_1: 1, player_2: 1 });
    expect(snapshot.action_limits).toEqual({ connection_actions_left: 1, repair_actions_left: 1 });
    expect(snapshot.objects).toEqual([
      { cell: { q: -3, r: 0 }, type: "core", owner: "player_1", active: true, disabled: false },
      { cell: { q: 3, r: 0 }, type: "core", owner: "player_2", active: true, disabled: false }
    ]);
  });

  it("places a node, spends the connection action, and updates the active network", () => {
    const state = new MatchState();
    const result = state.applyAction(action("place_node", "player_1", { q: -2, r: 0 }));

    expect(result.ok).toBe(true);
    expect(result.snapshot.action_limits.connection_actions_left).toBe(0);
    expect(result.snapshot.turn).toBe(2);
    expect(result.snapshot.objects).toContainEqual({
      cell: { q: -2, r: 0 },
      type: "node",
      owner: "player_1",
      active: true,
      disabled: false,
      role: "conduit",
      ready: false,
      action_charges: 0
    });
  });

  it("rejects an action from the wrong current player without changing state", () => {
    const state = new MatchState();
    const before = state.toSnapshot();
    const result = state.applyAction(action("place_node", "player_2", { q: 2, r: 0 }));

    expect(result.ok).toBe(false);
    expect(result.message).toBe("Expected Player 1, got Player 2");
    expect(state.toSnapshot()).toEqual({ ...before, status_message: result.message });
  });

  it("advances turns and applies upkeep", () => {
    const state = new MatchState();
    expect(state.applyAction({ type: "skip", player: "player_1" }).ok).toBe(true);

    const snapshot = state.toSnapshot();
    expect(snapshot.current_player).toBe("player_2");
    expect(snapshot.turn).toBe(2);
    expect(snapshot.action_limits).toEqual({ connection_actions_left: 1, repair_actions_left: 1 });
    expect(snapshot.status_message).toBe("Player 1 ended turn. Upkeep: Player 2 ready");
  });

  it("makes Harvester upgrades free and keeps other role upgrades paid", () => {
    const state = new MatchState();

    expect(state.applyAction(action("place_node", "player_1", { q: -2, r: 0 })).ok).toBe(true);
    const tooFar = state.applyAction(action("upgrade_harvester", "player_1", { q: -2, r: 0 }));
    expect(tooFar.ok).toBe(false);
    expect(tooFar.snapshot.resources.player_1).toBe(1);

    skip(state, "player_1");
    skip(state, "player_2");

    expect(state.applyAction(action("place_node", "player_1", { q: -1, r: 0 })).ok).toBe(true);
    const harvester = state.applyAction(action("upgrade_harvester", "player_1", { q: -1, r: 0 }));
    expect(harvester.ok).toBe(true);
    expect(harvester.snapshot.resources.player_1).toBe(1);
  });

  it("applies paid role upgrade costs and readies role nodes on the next owner upkeep", () => {
    const state = new MatchState();

    expect(state.applyAction(action("place_node", "player_1", { q: -2, r: 0 })).ok).toBe(true);
    const upgrade = state.applyAction(action("upgrade_striker", "player_1", { q: -2, r: 0 }));
    expect(upgrade.ok).toBe(true);
    expect(upgrade.snapshot.resources.player_1).toBe(0);
    expect(upgrade.snapshot.objects.find((object) => object.cell.q === -2 && object.cell.r === 0)).toMatchObject({
      role: "striker",
      ready: false,
      action_charges: 0
    });

    skip(state, "player_1");
    skip(state, "player_2");

    expect(state.toSnapshot().objects.find((object) => object.cell.q === -2 && object.cell.r === 0)).toMatchObject({
      role: "striker",
      ready: true,
      action_charges: 1
    });
  });

  it("uses Harvester income and module readiness for action-limit bonuses", () => {
    const state = new MatchState();

    expect(state.applyAction(action("place_node", "player_1", { q: -2, r: 0 })).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");

    expect(state.applyAction(action("place_node", "player_1", { q: -1, r: 0 })).ok).toBe(true);
    expect(state.applyAction(action("upgrade_harvester", "player_1", { q: -1, r: 0 })).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");

    expect(state.toSnapshot().resources.player_1).toBe(2);

    while (state.toSnapshot().resources.player_1 < 5) {
      skip(state, "player_1");
      skip(state, "player_2");
    }

    expect(state.applyAction(action("build_connection_module", "player_1", { q: -2, r: 1 })).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");

    expect(state.toSnapshot().action_limits.connection_actions_left).toBe(2);
  });

  it("resolves Striker attacks, Hacker hacks, Defender blocks, and core damage", () => {
    const state = new MatchState();

    buildPlayerOneToEnemyCore(state);
    expect(state.applyAction(action("upgrade_striker", "player_1", { q: 2, r: 0 })).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");

    const hit = state.applyAction({
      type: "striker_attack",
      player: "player_1",
      source_cell: { q: 2, r: 0 },
      cell: { q: 3, r: 0 }
    });
    expect(hit.ok).toBe(true);
    expect(hit.snapshot.core_hp.player_2).toBe(4);

    skip(state, "player_1");
    expect(state.applyAction(action("place_node", "player_2", { q: 3, r: -1 })).ok).toBe(true);
    expect(state.applyAction(action("upgrade_defender", "player_2", { q: 3, r: -1 })).ok).toBe(true);
    skip(state, "player_2");
    skip(state, "player_1");
    skip(state, "player_2");

    const blockedHit = state.applyAction({
      type: "striker_attack",
      player: "player_1",
      source_cell: { q: 2, r: 0 },
      cell: { q: 3, r: 0 }
    });
    expect(blockedHit.ok).toBe(true);
    expect(blockedHit.message).toBe("Player 2 Defender blocked a Striker attack");
    expect(blockedHit.snapshot.core_hp.player_2).toBe(4);

    skip(state, "player_1");
    expect(state.applyAction(action("place_node", "player_2", { q: 2, r: -1 })).ok).toBe(true);
    skip(state, "player_2");
    expect(state.applyAction(action("upgrade_hacker", "player_1", { q: 1, r: 0 })).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");
    expect(state.applyAction({ type: "break_node", player: "player_1", cell: { q: 2, r: -1 } }).ok).toBe(true);
    const hack = state.applyAction({
      type: "hacker_hack",
      player: "player_1",
      source_cell: { q: 1, r: 0 },
      cell: { q: 2, r: -1 }
    });
    expect(hack.ok).toBe(true);
    expect(hack.snapshot.objects.find((object) => object.cell.q === 2 && object.cell.r === -1)).toMatchObject({
      owner: "player_1",
      disabled: true,
      active: false
    });
  });

  it("finishes when a core reaches zero HP", () => {
    const state = new MatchState();

    buildPlayerOneToEnemyCore(state);
    expect(state.applyAction(action("upgrade_striker", "player_1", { q: 2, r: 0 })).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");

    for (let i = 0; i < 5; i += 1) {
      const result = state.applyAction({
        type: "striker_attack",
        player: "player_1",
        source_cell: { q: 2, r: 0 },
        cell: { q: 3, r: 0 }
      });
      expect(result.ok).toBe(true);

      if (i < 4) {
        skip(state, "player_1");
        skip(state, "player_2");
      }
    }

    const snapshot = state.toSnapshot();
    expect(snapshot.finished).toBe(true);
    expect(snapshot.core_hp.player_2).toBe(0);
    expect(snapshot.status_message).toContain("Player 1 wins");
  });
});

function action(type: string, player: PlayerId, cell: Cell): ActionPayload {
  return { type, player, cell };
}

function skip(state: MatchState, player: PlayerId): void {
  const result = state.applyAction({ type: "skip", player });
  expect(result.ok).toBe(true);
}

function buildPlayerOneToEnemyCore(state: MatchState): void {
  expect(state.applyAction(action("place_node", "player_1", { q: -2, r: 0 })).ok).toBe(true);
  skip(state, "player_1");
  skip(state, "player_2");

  expect(state.applyAction(action("place_node", "player_1", { q: -1, r: 0 })).ok).toBe(true);
  expect(state.applyAction(action("upgrade_harvester", "player_1", { q: -1, r: 0 })).ok).toBe(true);
  skip(state, "player_1");
  skip(state, "player_2");

  const path: Cell[] = [
    { q: -1, r: 1 },
    { q: 0, r: 1 },
    { q: 1, r: 0 },
    { q: 2, r: 0 }
  ];

  for (const cell of path) {
    expect(state.applyAction(action("place_node", "player_1", cell)).ok).toBe(true);
    skip(state, "player_1");
    skip(state, "player_2");
  }
}
