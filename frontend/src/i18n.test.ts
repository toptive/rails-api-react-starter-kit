import { describe, expect, it } from "vitest"
import { i18n } from "./i18n"

describe("the shared translation catalogue", () => {
  it("resolves the API message keys in both languages", () => {
    expect(i18n.t("errors.api.unauthorized", { lng: "en" })).toBe("Sign in to continue.")
    expect(i18n.t("errors.api.unauthorized", { lng: "es" })).toBe("Ingresá para continuar.")
  })

  it("interpolates the CSV's double-brace placeholders", () => {
    expect(i18n.t("validation.length_min", { lng: "en", count: 12 })).toBe("Use at least 12 characters.")
    expect(i18n.t("validation.length_min", { lng: "es", count: 12 })).toBe("Usá al menos 12 caracteres.")
  })
})
