import { defineConfig, devices } from "@playwright/test";

// The browser tests run against the development server (`mix dev`, see
// dev.exs). The web server command builds the bundle and the dev node
// modules first, and starts the server without watchers or live reload.
// It has its own port (4098, or E2E_PORT), so that a `mix dev` with
// watchers on 4099 is never the server of a run.
const port = Number(process.env.E2E_PORT ?? 4098);
const baseURL = `http://127.0.0.1:${port}`;

export default defineConfig({
  testDir: "./specs",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 2 : 0,
  reporter: "list",
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: "mix do kotoba.build + esbuild kotoba_dev_nodes + dev",
    cwd: "..",
    url: baseURL,
    env: { PORT: String(port), KOTOBA_DEV_WATCH: "false" },
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    stdout: "ignore",
    stderr: "pipe",
  },
});
