/**
 * Valley Clash Colyseus server.
 * Binds to all interfaces so other machines on the LAN can connect.
 */
import os from "node:os";
import { listen } from "@colyseus/tools";

import app from "./app.config.js";

const port = Number(process.env.PORT || 2567);

function lanAddresses(): string[] {
    const addresses: string[] = [];
    for (const nets of Object.values(os.networkInterfaces())) {
        if (!nets) {
            continue;
        }
        for (const net of nets) {
            if (net.family === "IPv4" && !net.internal) {
                addresses.push(net.address);
            }
        }
    }
    return addresses;
}

listen(app, port).then(() => {
    console.log(`Valley Clash server listening on 0.0.0.0:${port}`);
    console.log(`Local:  ws://127.0.0.1:${port}`);
    for (const ip of lanAddresses()) {
        console.log(`LAN:    ws://${ip}:${port}`);
    }
    console.log(`Room code: xxxx`);
});
