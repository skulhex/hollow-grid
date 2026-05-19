import { describe, expect, it } from "vitest";
import { isPublicActionType, isValidActionShape, isValidPublicActionShape, parseAction } from "../src/game/gameAction.js";

describe("GameAction", () => {
  it("accepts valid public action shapes", () => {
    expect(isValidPublicActionShape({ type: "place_node", player: "player_1", cell: { q: -2, r: 0 } })).toBe(true);
    expect(isValidPublicActionShape({ type: "skip", player: "player_1" })).toBe(true);
    expect(
      isValidPublicActionShape({
        type: "striker_attack",
        player: "player_1",
        source_cell: { q: -1, r: 0 },
        cell: { q: 0, r: 0 }
      })
    ).toBe(true);
    expect(
      isValidPublicActionShape({
        type: "hacker_hack",
        player: "player_2",
        source_cell: { q: 1, r: 0 },
        cell: { q: 0, r: 0 }
      })
    ).toBe(true);
  });

  it("rejects malformed public action shapes", () => {
    expect(isValidPublicActionShape({ type: "place_node", player: "player_1" })).toBe(false);
    expect(isValidPublicActionShape({ type: "skip", player: "player_1", cell: { q: -2, r: 0 } })).toBe(false);
    expect(isValidPublicActionShape({ type: "place_node", player: "player_1", cell: { q: 1.5, r: 0 } })).toBe(false);
    expect(isValidPublicActionShape({ type: "striker_attack", player: "player_1", cell: { q: 0, r: 0 } })).toBe(false);
  });

  it("keeps internal actions valid for the rules engine but non-public for transport", () => {
    const breakNode = parseAction({ type: "break_node", player: "player_1", cell: { q: 1, r: 0 } });
    const clearNode = parseAction({ type: "clear_node", player: "player_1", cell: { q: 1, r: 0 } });

    expect(isValidActionShape(breakNode)).toBe(true);
    expect(isValidActionShape(clearNode)).toBe(true);
    expect(isPublicActionType(breakNode.type)).toBe(false);
    expect(isPublicActionType(clearNode.type)).toBe(false);
    expect(isValidPublicActionShape({ type: "break_node", player: "player_1", cell: { q: 1, r: 0 } })).toBe(false);
    expect(isValidPublicActionShape({ type: "clear_node", player: "player_1", cell: { q: 1, r: 0 } })).toBe(false);
  });
});
