import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./app"
import { i18n } from "./i18n"

// This entry point is replaced by the shared SPA in the frontend task.
document.title = i18n.t("app.name")
createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>)
