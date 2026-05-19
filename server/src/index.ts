import { HollowGridServer } from "./net/hollowGridServer.js";

const port = Number.parseInt(process.env.PORT ?? "8787", 10);
const server = new HollowGridServer();

await server.listen({ port });

console.log(`Hollow Grid server listening on ws://127.0.0.1:${port}`);
