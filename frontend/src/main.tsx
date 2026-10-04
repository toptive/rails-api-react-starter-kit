import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { App } from "./app"
import { i18n } from "./i18n"

document.title = i18n.t("app.name")
createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>)
