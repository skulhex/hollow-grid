import { afterEach, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { HollowGridServer } from "../src/net/hollowGridServer.js";
import type { ServerMessage } from "../src/net/messages.js";

describe("HollowGridServer WebSocket protocol", () => {
  let server: HollowGridServer | undefined;
  const clients: WebSocket[] = [];

  afterEach(async () => {
    for (const client of clients.splice(0)) {
      client.close();
    }
    await server?.close();
    server = undefined;
  });

  it("serves a health check endpoint", async () => {
    server = await startServer();

    const response = await fetch(`${server.url().replace(/^ws:/, "http:")}/healthz`);

    expect(response.status).toBe(200);
    expect(await response.text()).toBe("ok\n");
  });

  it("creates and joins a two-player room", async () => {
    server = await startServer();
    const playerOne = await connect(server.url());
    const playerTwo = await connect(server.url());
    clients.push(playerOne, playerTwo);

    playerOne.send(JSON.stringify({ type: "create_room" }));
    const created = await nextMessage(playerOne);
    expect(created.type).toBe("room_created");
    if (created.type !== "room_created") throw new Error("Expected room_created");
    expect(created.player).toBe("player_1");

    playerTwo.send(JSON.stringify({ type: "join_room", room_code: created.room_code }));
    const joined = await nextMessage(playerTwo);
    expect(joined.type).toBe("joined");
    if (joined.type !== "joined") throw new Error("Expected joined");
    expect(joined.player).toBe("player_2");

    const notified = await nextMessage(playerOne);
    expect(notified.type).toBe("player_joined");
    if (notified.type !== "player_joined") throw new Error("Expected player_joined");
    expect(notified.players).toEqual(["player_1", "player_2"]);
  });

  it("rejects a third player from a full room", async () => {
    server = await startServer();
    const playerOne = await connect(server.url());
    const playerTwo = await connect(server.url());
    const third = await connect(server.url());
    clients.push(playerOne, playerTwo, third);

    playerOne.send(JSON.stringify({ type: "create_room" }));
    const created = await nextMessage(playerOne);
    if (created.type !== "room_created") throw new Error("Expected room_created");

    playerTwo.send(JSON.stringify({ type: "join_room", room_code: created.room_code }));
    await nextMessage(playerTwo);
    await nextMessage(playerOne);

    third.send(JSON.stringify({ type: "join_room", room_code: created.room_code }));
    const rejected = await nextMessage(third);
    expect(rejected).toEqual({ type: "error", message: "Room is full" });
  });

  it("rejects wrong socket/player actions and broadcasts accepted snapshots", async () => {
    server = await startServer();
    const playerOne = await connect(server.url());
    const playerTwo = await connect(server.url());
    clients.push(playerOne, playerTwo);

    playerOne.send(JSON.stringify({ type: "create_room" }));
    const created = await nextMessage(playerOne);
    if (created.type !== "room_created") throw new Error("Expected room_created");

    playerTwo.send(JSON.stringify({ type: "join_room", room_code: created.room_code }));
    await nextMessage(playerTwo);
    await nextMessage(playerOne);

    playerTwo.send(
      JSON.stringify({
        type: "action",
        action: { type: "place_node", player: "player_1", cell: { q: -2, r: 0 } }
      })
    );
    expect(await nextMessage(playerTwo)).toEqual({
      type: "error",
      message: "Socket is assigned player_2, got player_1"
    });

    playerOne.send(
      JSON.stringify({
        type: "action",
        action: { type: "place_node", player: "player_1", cell: { q: -2, r: 0 } }
      })
    );

    const p1Snapshot = await nextMessage(playerOne);
    const p2Snapshot = await nextMessage(playerTwo);
    expect(p1Snapshot.type).toBe("snapshot");
    expect(p2Snapshot.type).toBe("snapshot");
    if (p1Snapshot.type !== "snapshot" || p2Snapshot.type !== "snapshot") throw new Error("Expected snapshots");
    expect(p1Snapshot.snapshot.turn).toBe(2);
    expect(p2Snapshot.snapshot.turn).toBe(2);
    expect(p1Snapshot.snapshot.objects).toContainEqual({
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

  it("rejects internal actions at the transport boundary", async () => {
    server = await startServer();
    const playerOne = await connect(server.url());
    clients.push(playerOne);

    playerOne.send(JSON.stringify({ type: "create_room" }));
    await nextMessage(playerOne);

    playerOne.send(
      JSON.stringify({
        type: "action",
        action: { type: "break_node", player: "player_1", cell: { q: 2, r: 0 } }
      })
    );

    expect(await nextMessage(playerOne)).toEqual({ type: "error", message: "Invalid action" });
  });
});

async function startServer(): Promise<HollowGridServer> {
  const server = new HollowGridServer();
  await server.listen({ port: 0 });
  return server;
}

function connect(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}

function nextMessage(socket: WebSocket): Promise<ServerMessage> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("Timed out waiting for WebSocket message")), 1000);
    socket.once("message", (data) => {
      clearTimeout(timer);
      resolve(JSON.parse(data.toString("utf8")) as ServerMessage);
    });
    socket.once("error", reject);
  });
}
