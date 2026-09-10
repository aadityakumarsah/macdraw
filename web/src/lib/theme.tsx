import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { supabase } from "@/lib/supabase";

type Theme = "dark" | "light";
type ThemeContextValue = { theme: Theme; toggle: () => void };

const STORAGE_KEY = "macdraw.theme";
const ThemeContext = createContext<ThemeContextValue | null>(null);

function currentTheme(): Theme {
  if (typeof document !== "undefined") {
    return document.documentElement.classList.contains("light") ? "light" : "dark";
  }
  return "dark";
}

/** Persist the user's theme. Mirrors the Mac app's UserDefaults key. */
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => {
    const stored = localStorage.getItem(STORAGE_KEY) as Theme | null;
    if (stored === "light" || stored === "dark") return stored;
    return "dark";
  });

  useEffect(() => {
    const root = document.documentElement;
    root.classList.toggle("light", theme === "light");
    root.classList.toggle("dark", theme === "dark");
    localStorage.setItem(STORAGE_KEY, theme);
    // Best-effort server persistence on the UserProfile (RLS: own row only).
    supabase.auth.getUser().then(({ data }) => {
      if (data.user) {
        supabase.from("UserProfile").update({ theme }).eq("id", data.user.id).then(() => {});
      }
    });
  }, [theme]);

  const toggle = useCallback(() => setTheme((t) => (t === "dark" ? "light" : "dark")), []);

  return <ThemeContext.Provider value={{ theme, toggle }}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}

export const themeStorageKey = STORAGE_KEY;