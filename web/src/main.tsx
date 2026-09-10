import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App";
import { ThemeProvider } from "@/lib/theme";
import { PagesProvider } from "@/context/PagesContext";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <ThemeProvider>
      <PagesProvider>
        <App />
      </PagesProvider>
    </ThemeProvider>
  </StrictMode>,
);