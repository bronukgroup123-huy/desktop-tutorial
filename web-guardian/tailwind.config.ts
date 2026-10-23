import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./src/pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/components/**/*.{js,ts,jsx,tsx,mdx}",
    "./src/app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        brand: {
          50: "#f0fdf4",
          100: "#dcfce7",
          500: "#22c55e",
          600: "#16a34a",
          700: "#15803d",
        },
        // Палітра з web-guardian/public/landing.html (макет Грибного Радару).
        cream: {
          50: "rgb(251 248 241 / <alpha-value>)",
          100: "rgb(247 244 236 / <alpha-value>)",
          200: "rgb(245 230 208 / <alpha-value>)",
          300: "rgb(229 223 208 / <alpha-value>)",
          400: "rgb(234 227 210 / <alpha-value>)",
        },
        forest: {
          dark: "rgb(47 74 58 / <alpha-value>)",
          DEFAULT: "rgb(74 107 84 / <alpha-value>)",
          light: "rgb(220 230 220 / <alpha-value>)",
        },
        amberbrand: "rgb(201 122 43 / <alpha-value>)",
        bark: "rgb(139 94 52 / <alpha-value>)",
        sos: "rgb(168 71 31 / <alpha-value>)",
        ink: {
          DEFAULT: "rgb(30 30 26 / <alpha-value>)",
          muted: "rgb(107 102 89 / <alpha-value>)",
        },
      },
      fontFamily: {
        serif: ["Fraunces", "Georgia", "serif"],
        sans: ["Inter", "system-ui", "sans-serif"],
      },
      boxShadow: {
        soft: "0 4px 20px rgba(47, 74, 58, 0.06)",
        lift: "0 10px 30px rgba(47, 74, 58, 0.10)",
        shell: "0 40px 100px rgba(47, 74, 58, 0.18), 0 8px 24px rgba(47, 74, 58, 0.10)",
      },
    },
  },
  plugins: [],
};

export default config;
