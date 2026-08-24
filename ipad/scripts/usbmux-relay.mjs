import net from "node:net";

const [listenAddress, rawPort = "27015"] = process.argv.slice(2);
const port = Number(rawPort);
const octets = String(listenAddress ?? "").split(".").map(Number);
const privateAddress = octets.length === 4 && octets.every((part) => Number.isInteger(part) && part >= 0 && part <= 255) && (
  octets[0] === 10 ||
  (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) ||
  (octets[0] === 192 && octets[1] === 168)
);

if (!privateAddress || !Number.isInteger(port) || port < 1024 || port > 65_535) {
  throw new Error("Expected a private IPv4 listen address and an unprivileged TCP port");
}

const sockets = new Set();
const server = net.createServer((client) => {
  const upstream = net.connect({ host: "127.0.0.1", port });
  sockets.add(client);
  sockets.add(upstream);
  client.pipe(upstream);
  upstream.pipe(client);
  const close = () => {
    sockets.delete(client);
    sockets.delete(upstream);
    client.destroy();
    upstream.destroy();
  };
  client.on("error", close);
  upstream.on("error", close);
  client.on("close", close);
  upstream.on("close", close);
});

server.on("error", (error) => {
  console.error(error.message);
  process.exitCode = 1;
});

server.listen(port, listenAddress, () => {
  console.log(`LUMINA_USBMUX_RELAY_READY ${listenAddress}:${port}`);
});

const shutdown = () => {
  for (const socket of sockets) socket.destroy();
  server.close(() => process.exit(0));
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
