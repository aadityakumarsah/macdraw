import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import { PageSyncService } from "@/lib/sync";
import type { ConnectionState, Page, Workspace } from "@/lib/types";

type PagesContextValue = {
  user: User | null;
  workspace: Workspace | null;
  pages: Page[];
  status: ConnectionState;
  loading: boolean;
  error: string | null;
  activePageId: string | null;
  openPage: (id: string) => void;
  createPage: (name: string, description?: string) => Promise<Page>;
  renamePage: (id: string, name: string) => Promise<void>;
  setPageDescription: (id: string, description: string) => Promise<void>;
  archivePage: (id: string) => Promise<void>;
  duplicatePage: (id: string) => Promise<void>;
  retry: () => void;
};

const PagesContext = createContext<PagesContextValue | null>(null);

export function PagesProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [workspace, setWorkspace] = useState<Workspace | null>(null);
  const [pages, setPages] = useState<Page[]>([]);
  const [status, setStatus] = useState<ConnectionState>("closed");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activePageId, setActivePageId] = useState<string | null>(null);
  const [retryTick, setRetryTick] = useState(0);

  const service = useMemo(() => new PageSyncService(supabase), []);
  const pagesRef = useRef<Page[]>([]);
  pagesRef.current = pages;

  /** Reconcile a realtime/optimistic page into the list — never duplicates. */
  const reconcile = useCallback((eventPage: Page, force = false) => {
    setPages((prev) => {
      const idx = prev.findIndex((p) => p.id === eventPage.id);
      if (idx === -1) {
        if (eventPage.deletedAt) return prev;
        return [...prev, eventPage].sort((a, b) => a.orderIndex - b.orderIndex);
      }
      const existing = prev[idx];
      if (!force && eventPage.deletedAt == null && new Date(eventPage.updatedAt) < new Date(existing.updatedAt)) {
        return prev; // stale realtime event — do not regress
      }
      if (eventPage.deletedAt) {
        const next = [...prev];
        next.splice(idx, 1);
        return next;
      }
      const next = [...prev];
      next[idx] = eventPage;
      return next.sort((a, b) => a.orderIndex - b.orderIndex);
    });
  }, []);

  // auth session
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setUser(data.session?.user ?? null));
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      setUser(session?.user ?? null);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  // load workspace + pages + realtime when signed in
  useEffect(() => {
    if (!user) {
      setPages([]);
      setWorkspace(null);
      setActivePageId(null);
      setLoading(false);
      service.unsubscribe();
      return;
    }
    let cancelled = false;
    let attempts = 0;
    async function load() {
      setLoading(true);
      setError(null);
      try {
        const ws = await service.getOrCreateWorkspace();
        if (cancelled) return;
        setWorkspace(ws);
        await service.ensureSeedPage(ws.id);
        const list = await service.fetchPages(ws.id);
        if (cancelled) return;
        setPages(list);
        setActivePageId((cur) => (list.some((p) => p.id === cur) ? cur : (list[0]?.id ?? null)));
      } catch (e) {
        if (cancelled) return;
        console.error("[Pages] workspace load failed:", e);
        // One transparent retry for transient API/server hiccups before showing
        // the error state — keeps the dashboard from flashing an error spuriously.
        if (attempts === 0 && isTransient(e)) {
          attempts += 1;
          setTimeout(load, 1200);
          return;
        }
        setError(humanize(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    }
    load();

    const offEvent = service.onEvent((ev) => {
      const page = ev.event === "DELETE" ? ev.old : ev.new;
      if (ev.event === "DELETE") {
        setPages((prev) => prev.filter((p) => p.id !== page.id));
        return;
      }
      reconcile(page);
    });
    const offStatus = service.onStatus(setStatus);

    return () => {
      cancelled = true;
      offEvent();
      offStatus();
      service.unsubscribe();
    };
  }, [user, retryTick]);

  // Realtime subscription depends on the (asynchronously resolved) workspace id.
  useEffect(() => {
    if (!user || !workspace?.id) return;
    service.subscribe(workspace.id).catch(() => {});
    return () => service.unsubscribe();
  }, [user, workspace?.id, retryTick]);

  const createPage = useCallback(
    async (name: string, description?: string) => {
      if (!workspace) throw new Error("No workspace");
      const clean = name.trim();
      if (!clean) throw new Error("Page name can't be empty");
      if (clean.length > 120) throw new Error("Page name is too long");
      const page = await service.createPage(workspace.id, { name: clean, description });
      reconcile(page);
      setActivePageId(page.id);
      return page;
    },
    [workspace, service, reconcile],
  );

  const renamePage = useCallback(
    async (id: string, name: string) => {
      if (!workspace) throw new Error("No workspace");
      const clean = name.trim();
      if (!clean) return;
      const page = await service.updatePage(workspace.id, id, { name: clean });
      reconcile(page);
    },
    [workspace, service, reconcile],
  );

  const setPageDescription = useCallback(
    async (id: string, description: string) => {
      if (!workspace) throw new Error("No workspace");
      const page = await service.updatePage(workspace.id, id, { description: description.trim() || null });
      reconcile(page);
    },
    [workspace, service, reconcile],
  );

  const archivePage = useCallback(
    async (id: string) => {
      if (!workspace) throw new Error("No workspace");
      const target = pagesRef.current.find((p) => p.id === id);
      if (!target) return;
      await service.archivePage(workspace.id, id);
      setPages((prev) => prev.filter((p) => p.id !== id));
      setActivePageId((cur) => (cur === id ? (pagesRef.current[0]?.id ?? null) : cur));
    },
    [workspace, service],
  );

  const duplicatePage = useCallback(
    async (id: string) => {
      if (!workspace) throw new Error("No workspace");
      const src = pagesRef.current.find((p) => p.id === id);
      if (!src) return;
      const page = await service.duplicatePage(workspace.id, src);
      reconcile(page);
    },
    [workspace, service, reconcile],
  );

  const openPage = useCallback((id: string) => setActivePageId(id), []);

  const retry = useCallback(() => setRetryTick((t) => t + 1), []);

  const value: PagesContextValue = {
    user,
    workspace,
    pages,
    status,
    loading,
    error,
    activePageId,
    openPage,
    createPage,
    renamePage,
    setPageDescription,
    archivePage,
    duplicatePage,
    retry,
  };

  return <PagesContext.Provider value={value}>{children}</PagesContext.Provider>;
}

export function usePages(): PagesContextValue {
  const ctx = useContext(PagesContext);
  if (!ctx) throw new Error("usePages must be used within PagesProvider");
  return ctx;
}

function isTransient(e: unknown): boolean {
  const err = e as { status?: number; code?: string; message?: string } | Error;
  const msg = (err?.message ?? "").toLowerCase();
  return (
    (typeof err?.status === "number" && (err.status === 429 || err.status >= 500)) ||
    msg.includes("timeout") ||
    msg.includes("failed to fetch") ||
    msg.includes("networkerror") ||
    msg.includes("load failed") ||
    msg.includes("rate limit")
  );
}

function humanize(e: unknown): string {
  if (e instanceof Error) {
    const msg = e.message.toLowerCase();
    if (msg.includes("jwt") || msg.includes("auth") || msg.includes("not signed in"))
      return "Session expired. Please sign in again.";
    if (msg.includes("network") || msg.includes("fetch"))
      return "Couldn't reach the server. Check your connection.";
    if (msg.includes("permission") || msg.includes("rls") || msg.includes("policy"))
      return "You don't have permission to do that.";
  }
  const err = e as { status?: number; message?: string } | null;
  if (err?.status === 429 || err?.message?.toLowerCase().includes("rate limit"))
    return "The sync service is rate-limiting us. Give it a moment, then try again.";
  if (typeof err?.status === "number" && err.status >= 500)
    return "The sync server had a hiccup. Try again.";
  if (err?.message && !err.message.includes("Failed to fetch"))
    return `Something went wrong (${err.message}). Try again.`;
  return "Something went wrong. Try again.";
}