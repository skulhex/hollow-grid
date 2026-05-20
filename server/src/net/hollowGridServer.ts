import { createServer, type Server as HttpServer } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { PLAYER_ONE, PLAYER_TWO, isPlayerId } from "../game/constants.js";
import { isPublicActionType, isValidPublicActionShape, parseAction } from "../game/gameAction.js";
import { MatchState } from "../game/matchState.js";
import type { PlayerId, Snapshot } from "../game/types.js";
import { parseClientMessage, type ClientMessage, type ServerMessage } from "./messages.js";

interface ClientSession {
  socket: WebSocket;
  roomCode?: string;
  player?: PlayerId;
}

interface Room {
  code: string;
  state: MatchState;
  players: Partial<Record<PlayerId, ClientSession>>;
}

export interface HollowGridServerOptions {
  port?: number;
  host?: string;
}

export class HollowGridServer {
  private readonly httpServer: HttpServer;
  private readonly wss: WebSocketServer;
  private readonly rooms = new Map<string, Room>();
  private readonly sessions = new Map<WebSocket, ClientSession>();

  constructor() {
    this.httpServer = createServer((request, response) => {
      if (request.url === "/healthz") {
        response.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
        response.end("ok\n");
        return;
      }

      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("not found\n");
    });
    this.wss = new WebSocketServer({ server: this.httpServer });
    this.wss.on("connection", (socket) => this.handleConnection(socket));
  }

  listen(options: HollowGridServerOptions = {}): Promise<void> {
    const port = options.port ?? 8787;
    const host = options.host ?? "127.0.0.1";

    return new Promise((resolve, reject) => {
      const onError = (error: Error): void => {
        this.httpServer.off("listening", onListening);
        reject(error);
      };
      const onListening = (): void => {
        this.httpServer.off("error", onError);
        resolve();
      };

      this.httpServer.once("error", onError);
      this.httpServer.once("listening", onListening);
      this.httpServer.listen(port, host);
    });
  }

  close(): Promise<void> {
    for (const socket of this.sessions.keys()) {
      socket.close();
    }

    return new Promise((resolve, reject) => {
      this.wss.close((wssError) => {
        if (wssError) {
          reject(wssError);
          return;
        }

        this.httpServer.close((httpError) => {
          if (httpError && "code" in httpError && httpError.code !== "ERR_SERVER_NOT_RUNNING") {
            reject(httpError);
            return;
          }

          resolve();
        });
      });
    });
  }

  url(): string {
    const address = this.httpServer.address();
    if (!address || typeof address === "string") {
      throw new Error("Server is not listening on a TCP port");
    }

    const host = address.address === "::" || address.address === "0.0.0.0" ? "127.0.0.1" : address.address;
    return `ws://${host}:${address.port}`;
  }

  private handleConnection(socket: WebSocket): void {
    const session: ClientSession = { socket };
    this.sessions.set(socket, session);

    socket.on("message", (data) => {
      const raw = typeof data === "string" ? data : data.toString("utf8");
      const message = parseClientMessage(raw);

      if (!message) {
        this.send(session, { type: "error", message: "Invalid message" });
        return;
      }

      this.handleMessage(session, message);
    });

    socket.on("close", () => this.handleClose(session));
  }

  private handleMessage(session: ClientSession, message: ClientMessage): void {
    switch (message.type) {
      case "create_room":
        this.createRoom(session);
        return;
      case "join_room":
        this.joinRoom(session, message.room_code);
        return;
      case "action":
        this.handleAction(session, message.action);
        return;
    }
  }

  private createRoom(session: ClientSession): void {
    if (session.roomCode) {
      this.send(session, { type: "error", message: "Socket is already in a room" });
      return;
    }

    const code = this.generateRoomCode();
    const room: Room = {
      code,
      state: new MatchState(),
      players: {}
    };

    session.roomCode = code;
    session.player = PLAYER_ONE;
    room.players[PLAYER_ONE] = session;
    this.rooms.set(code, room);

    this.send(session, {
      type: "room_created",
      room_code: code,
      player: PLAYER_ONE,
      snapshot: room.state.toSnapshot()
    });
  }

  private joinRoom(session: ClientSession, rawRoomCode: string): void {
    if (session.roomCode) {
      this.send(session, { type: "error", message: "Socket is already in a room" });
      return;
    }

    const roomCode = rawRoomCode.trim().toUpperCase();
    const room = this.rooms.get(roomCode);

    if (!room) {
      this.send(session, { type: "error", message: "Room not found" });
      return;
    }

    if (room.players[PLAYER_TWO]) {
      this.send(session, { type: "error", message: "Room is full" });
      return;
    }

    session.roomCode = roomCode;
    session.player = PLAYER_TWO;
    room.players[PLAYER_TWO] = session;

    const snapshot = room.state.toSnapshot();
    this.send(session, {
      type: "joined",
      room_code: roomCode,
      player: PLAYER_TWO,
      snapshot
    });
    this.broadcast(room, {
      type: "player_joined",
      players: [PLAYER_ONE, PLAYER_TWO],
      snapshot
    });
  }

  private handleAction(session: ClientSession, rawAction: unknown): void {
    const room = this.sessionRoom(session);
    if (!room || !session.player) {
      this.send(session, { type: "error", message: "Socket is not in a room" });
      return;
    }

    const action = parseAction(rawAction);
    if (!isValidPublicActionShape(rawAction) || !isPublicActionType(action.type)) {
      this.send(session, { type: "error", message: "Invalid action" });
      return;
    }

    if (!isPlayerId(action.player)) {
      this.send(session, { type: "error", message: "Invalid player" });
      return;
    }

    if (action.player !== session.player) {
      this.send(session, { type: "error", message: `Socket is assigned ${session.player}, got ${action.player}` });
      return;
    }

    const result = room.state.applyAction(rawAction);
    if (!result.ok) {
      this.send(session, { type: "error", message: result.message });
      return;
    }

    this.broadcastSnapshot(room, result.snapshot);
  }

  private handleClose(session: ClientSession): void {
    this.sessions.delete(session.socket);

    const room = this.sessionRoom(session);
    if (!room || !session.player) {
      return;
    }

    delete room.players[session.player];

    if (!room.players[PLAYER_ONE] && !room.players[PLAYER_TWO]) {
      this.rooms.delete(room.code);
    }
  }

  private sessionRoom(session: ClientSession): Room | undefined {
    if (!session.roomCode) return undefined;
    return this.rooms.get(session.roomCode);
  }

  private broadcastSnapshot(room: Room, snapshot: Snapshot): void {
    this.broadcast(room, { type: "snapshot", snapshot });
  }

  private broadcast(room: Room, message: ServerMessage): void {
    for (const session of Object.values(room.players)) {
      if (session) {
        this.send(session, message);
      }
    }
  }

  private send(session: ClientSession, message: ServerMessage): void {
    if (session.socket.readyState === WebSocket.OPEN) {
      session.socket.send(JSON.stringify(message));
    }
  }

  private generateRoomCode(): string {
    const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    for (let attempt = 0; attempt < 100; attempt += 1) {
      let code = "";
      for (let i = 0; i < 6; i += 1) {
        code += alphabet[Math.floor(Math.random() * alphabet.length)];
      }

      if (!this.rooms.has(code)) {
        return code;
      }
    }

    throw new Error("Unable to generate unique room code");
  }
}
