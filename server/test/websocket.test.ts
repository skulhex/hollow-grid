import { afterEach, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { HollowGridServer } from "../src/net/hollowGridServer.js";
import type { ServerMessage } from "../src/net/messages.js";

type MessageWaiter = {
  resolve: (message: ServerMessage) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
};

type MessageInbox = {
  messages: ServerMessage[];
  waiters: MessageWaiter[];
  error?: Error;
};

const inboxes = new WeakMap<WebSocket, MessageInbox>();

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
    const joinedBroadcast = await nextMessage(playerTwo);
    expect(joinedBroadcast.type).toBe("player_joined");

    await expectPresence(playerOne, ["player_1", "player_2"]);
    await expectPresence(playerTwo, ["player_1", "player_2"]);
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
    await nextMessage(playerOne);
    await nextMessage(playerTwo);

    third.send(JSON.stringify({ type: "join_room", room_code: created.room_code }));
    const rejected = await nextMessage(third);
    expect(rejected).toEqual({ type: "error", message: "Room is full" });
  });

  it("lets a disconnected player reclaim their slot", async () => {
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
    await nextMessage(playerTwo);
    await expectPresence(playerOne, ["player_1", "player_2"]);
    await expectPresence(playerTwo, ["player_1", "player_2"]);

    playerOne.close();
    await expectPresence(playerTwo, ["player_2"]);

    const rejoinedPlayerOne = await connect(server.url());
    clients.push(rejoinedPlayerOne);
    rejoinedPlayerOne.send(JSON.stringify({ type: "join_room", room_code: created.room_code, player: "player_1" }));

    const rejoined = await nextMessage(rejoinedPlayerOne);
    expect(rejoined.type).toBe("joined");
    if (rejoined.type !== "joined") throw new Error("Expected joined");
    expect(rejoined.player).toBe("player_1");

    await nextMessage(playerTwo);
    await nextMessage(rejoinedPlayerOne);
    await expectPresence(playerTwo, ["player_1", "player_2"]);
    await expectPresence(rejoinedPlayerOne, ["player_1", "player_2"]);

    rejoinedPlayerOne.send(
      JSON.stringify({
        type: "action",
        action: { type: "place_node", player: "player_1", cell: { q: -2, r: 0 } }
      })
    );

    const p1Snapshot = await nextMessage(rejoinedPlayerOne);
    const p2Snapshot = await nextMessage(playerTwo);
    expect(p1Snapshot.type).toBe("snapshot");
    expect(p2Snapshot.type).toBe("snapshot");
  });

  it("rejects reclaiming an occupied preferred slot", async () => {
    server = await startServer();
    const playerOne = await connect(server.url());
    const third = await connect(server.url());
    clients.push(playerOne, third);

    playerOne.send(JSON.stringify({ type: "create_room" }));
    const created = await nextMessage(playerOne);
    if (created.type !== "room_created") throw new Error("Expected room_created");

    third.send(JSON.stringify({ type: "join_room", room_code: created.room_code, player: "player_1" }));
    expect(await nextMessage(third)).toEqual({ type: "error", message: "Player already connected" });
  });

  it("keeps an empty room briefly and expires it after the empty-room TTL", async () => {
    server = new HollowGridServer({ roomEmptyTtlMs: 20 });
    await server.listen({ port: 0 });
    const playerOne = await connect(server.url());
    clients.push(playerOne);

    playerOne.send(JSON.stringify({ type: "create_room" }));
    const created = await nextMessage(playerOne);
    if (created.type !== "room_created") throw new Error("Expected room_created");

    await closeSocket(playerOne);
    await delay(5);

    const quickRejoin = await connect(server.url());
    clients.push(quickRejoin);
    quickRejoin.send(JSON.stringify({ type: "join_room", room_code: created.room_code, player: "player_1" }));
    const rejoined = await nextMessage(quickRejoin);
    expect(rejoined.type).toBe("joined");

    await closeSocket(quickRejoin);
    await delay(30);

    const lateRejoin = await connect(server.url());
    clients.push(lateRejoin);
    lateRejoin.send(JSON.stringify({ type: "join_room", room_code: created.room_code, player: "player_1" }));
    expect(await nextMessage(lateRejoin)).toEqual({ type: "error", message: "Room not found" });
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
    const playerOneNotified = await nextMessage(playerOne);
    const playerTwoNotified = await nextMessage(playerTwo);
    expect(playerOneNotified.type).toBe("player_joined");
    expect(playerTwoNotified.type).toBe("player_joined");
    await expectPresence(playerOne, ["player_1", "player_2"]);
    await expectPresence(playerTwo, ["player_1", "player_2"]);

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
    socket.once("open", () => {
      getInbox(socket);
      resolve(socket);
    });
    socket.once("error", reject);
  });
}

function nextMessage(socket: WebSocket): Promise<ServerMessage> {
  const inbox = getInbox(socket);
  const message = inbox.messages.shift();

  if (message) {
    return Promise.resolve(message);
  }

  if (inbox.error) {
    return Promise.reject(inbox.error);
  }

  return new Promise((resolve, reject) => {
    const waiter: MessageWaiter = {
      resolve,
      reject,
      timer: setTimeout(() => {
        const index = inbox.waiters.indexOf(waiter);
        if (index >= 0) {
          inbox.waiters.splice(index, 1);
        }
        reject(new Error("Timed out waiting for WebSocket message"));
      }, 1000)
    };

    inbox.waiters.push(waiter);
  });
}

async function expectPresence(socket: WebSocket, connectedPlayers: string[]): Promise<void> {
  const presence = await nextMessage(socket);
  expect(presence.type).toBe("presence_updated");
  if (presence.type !== "presence_updated") throw new Error("Expected presence_updated");
  expect(presence.players).toEqual(["player_1", "player_2"]);
  expect(presence.connected_players).toEqual(connectedPlayers);
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function closeSocket(socket: WebSocket): Promise<void> {
  if (socket.readyState === WebSocket.CLOSED) {
    return Promise.resolve();
  }

  return new Promise((resolve) => {
    socket.once("close", () => resolve());
    socket.close();
  });
}

function getInbox(socket: WebSocket): MessageInbox {
  const existing = inboxes.get(socket);
  if (existing) {
    return existing;
  }

  const inbox: MessageInbox = {
    messages: [],
    waiters: []
  };

  socket.on("message", (data) => {
    const message = JSON.parse(data.toString("utf8")) as ServerMessage;
    const waiter = inbox.waiters.shift();

    if (!waiter) {
      inbox.messages.push(message);
      return;
    }

    clearTimeout(waiter.timer);
    waiter.resolve(message);
  });

  socket.on("error", (error) => {
    inbox.error = error;

    for (const waiter of inbox.waiters.splice(0)) {
      clearTimeout(waiter.timer);
      waiter.reject(error);
    }
  });

  inboxes.set(socket, inbox);
  return inbox;
}
