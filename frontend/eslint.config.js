import js from "@eslint/js"
import tseslint from "typescript-eslint"
import reactHooks from "eslint-plugin-react-hooks"
import globals from "globals"

export default tseslint.config(
  { ignores: ["dist/**", "src/api/generated/**"] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: { globals: { ...globals.browser, ...globals.node } },
    plugins: { "react-hooks": reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "no-restricted-imports": ["error", { paths: ["axios", "react-hook-form"] }],
      "no-restricted-globals": ["error", { name: "fetch", message: "Use the shared API client." }],
      "no-restricted-syntax": ["error",
        { selector: "JSXText[value=/\\S/]", message: "UI text comes from the translation CSV." },
        { selector: "Literal[value=/^#[a-fA-F0-9]{3,8}$/]", message: "Use theme tokens for colours." },
      ],
    },
  },
)
