import {
    defineServer,
    defineRoom,
    monitor,
    playground,
    createRouter,
    createEndpoint,
} from "colyseus";

import { GameRoom } from "./rooms/GameRoom.js";

const server = defineServer({
    rooms: {
        // Join / create with options { code: "xxxx" }
        game: defineRoom(GameRoom).filterBy(["code"]),
    },

    routes: createRouter({
        api_hello: createEndpoint("/api/hello", { method: "GET", }, async () => {
            return { message: "Valley Clash Colyseus server" };
        }),
    }),

    express: (app) => {
        app.get("/hi", (_req, res) => {
            res.send("Valley Clash is ready for LAN battles.");
        });

        app.use("/monitor", monitor());

        if (process.env.NODE_ENV !== "production") {
            app.use("/", playground());
        }
    },
});

export default server;
