const os = require('os');

/**
 * Colyseus Cloud entry at repo root.
 * The Node app lives under server/; PM2 runs the compiled build from there.
 * See https://docs.colyseus.io/cloud
 */
module.exports = {
  apps: [{
    name: "colyseus-app",
    script: 'server/build/index.js',
    time: true,
    watch: false,
    instances: os.cpus().length,
    exec_mode: 'fork',
    wait_ready: true,
    cwd: __dirname,
  }],
};
