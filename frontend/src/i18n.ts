import { createInstance } from "i18next"
import { initReactI18next } from "react-i18next"
import en from "../../i18n/locales/en.json"
import es from "../../i18n/locales/es.json"

export const i18n = createInstance()
await i18n.use(initReactI18next).init({
  resources: { en: { translation: en }, es: { translation: es } },
  lng: "en",
  fallbackLng: "en",
  keySeparator: false,
  interpolation: { escapeValue: false },
})
