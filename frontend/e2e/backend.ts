/** Rails fixture seam for the shared browser journeys. */
import { execFileSync, spawn } from "node:child_process"
import { setTimeout as delay } from "node:timers/promises"

function database() {
  const name = process.env.E2E_PGDATABASE ?? "rails_starter_kit_e2e"
  if (!/^[a-z0-9_]*e2e[a-z0-9_]*$/.test(name)) throw new Error("Fixtures require an isolated e2e database")
  return name
}
function backendOptions(apiURL = process.env.E2E_API_URL ?? "http://localhost:4100") {
  return {
    cwd: process.env.E2E_API_DIR ?? new URL("../..", import.meta.url).pathname,
    env: {
      ...process.env,
      RAILS_ENV: "test",
      E2E: "1",
      E2E_PGDATABASE: database(),
      PORT: new URL(apiURL).port,
      API_ORIGIN: apiURL,
      SPA_ORIGIN: process.env.E2E_BASE_URL ?? `http://localhost:${process.env.E2E_VITE_PORT ?? "5174"}`,
    },
  }
}
function run(code: string) {
  const output = execFileSync("bin/rails", ["runner", code], {
    ...backendOptions(), encoding: "utf8", timeout: 30_000,
  })
  return output.trim().split("\n").at(-1)!
}
function uuid(value: string) {
  if (!/^[0-9a-f-]{36}$/.test(value)) throw new Error("Invalid fixture UUID")
  return value
}
export function seedUser(email: string, admin = false): { token: string; expiresAt: string; sudoUntil: string | null } {
  if (!/^[a-z0-9@.-]+$/.test(email)) throw new Error("Invalid fixture email")
  return JSON.parse(run(`
    user = ${admin ? `User.bootstrap_superadmin!(email: "${email}")` : `User.find_by(email: "${email}") || User.create!(email: "${email}", name: "Browser Tester", locale: "en", confirmed_at: Time.current)`}
    request = ActionDispatch::Request.new("REMOTE_ADDR" => "127.0.0.1", "HTTP_USER_AGENT" => "Browser Fixture")
    issued = Session.create_for(user, request)
    session = issued.fetch(:session)
    puts JSON.generate(token: issued.fetch(:token), expiresAt: session.expires_at.utc.iso8601, sudoUntil: session.sudo_until&.utc&.iso8601)
  `))
}
export function expireSudo(sessionId: string) {
  run(`Session.find("${uuid(sessionId)}").update!(sudo_until: 1.minute.ago)`)
}
export function sendOptionalEmail(userId: string) {
  run(`AccountMail.product_update(User.find("${uuid(userId)}"), title: I18n.t("home.title"), summary: I18n.t("home.description"), url: Rails.application.config.x.spa_origin)`)
}
export async function startBillingOffApi() {
  const url = new URL(process.env.E2E_API_OFF_URL ?? "http://localhost:4101")
  const port = Number(url.port)
  if (!Number.isInteger(port) || port < 1) throw new Error("E2E_API_OFF_URL requires a port")
  const options = backendOptions(url.href.replace(/\/$/, ""))
  const child = spawn("bin/rails", ["server", "-b", "127.0.0.1", "-p", String(port), "--pid", `tmp/pids/e2e-off-${port}.pid`], {
    ...options, env: { ...options.env, BILLING_ENABLED: "false" }, stdio: ["ignore", "pipe", "pipe"],
  })
  let diagnostics = ""
  let spawnError: Error | undefined
  child.on("error", (error) => { spawnError = error })
  child.stdout?.on("data", (data) => { diagnostics = (diagnostics + String(data)).slice(-8000) })
  child.stderr?.on("data", (data) => { diagnostics = (diagnostics + String(data)).slice(-8000) })
  const stop = async () => {
    if (child.exitCode !== null || child.signalCode !== null || spawnError) return
    const exited = new Promise<void>((resolve) => child.once("exit", () => resolve()))
    child.kill("SIGTERM")
    const timer = setTimeout(() => child.kill("SIGKILL"), 5000)
    await exited
    clearTimeout(timer)
  }
  try {
    const deadline = Date.now() + 60_000
    while (Date.now() < deadline) {
      if (spawnError) throw spawnError
      if (child.exitCode !== null) throw new Error(`Flag-off API exited: ${child.exitCode}\n${diagnostics}`)
      try {
        const response = await fetch(new URL("/health", url), { signal: AbortSignal.timeout(1000) })
        if (response.ok) return stop
      } catch { /* Wait for Rails to bind its isolated port. */ }
      await delay(250)
    }
    throw new Error(`Flag-off API did not become healthy\n${diagnostics}`)
  } catch (error) {
    await stop()
    throw error
  }
}
