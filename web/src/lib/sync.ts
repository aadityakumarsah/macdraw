import type { SupabaseClient, RealtimeChannel } from "@supabase/supabase-js";
import { genMemberId, genPageId, genWorkspaceId } from "@/lib/format";
import type { ConnectionState, Page, PageEvent, Workspace } from "@/lib/types";

type Subscriber = (event: PageEvent) => void;
type StatusListener = (state: ConnectionState) => void;

/**
 * PageSyncService — the single synchronization abstraction for React Roadmap.
 *
 * SERVER (Supabase + RLS)  = source of truth
 * this layer               = data access + realtime reconciliation
 * React state              = transient presentation cache
 *
 * Pages are reconciled by stable page id: an event for an id we already know
 * updates it; unknown ids are inserted; deletes remove. Realtime filters to the
 * active workspace so we never see another workspace's pages.
 */
export class PageSyncService {
  private channel: RealtimeChannel | null = null;
  private listeners = new Set<Subscriber>();
  private statusListeners = new Set<StatusListener>();

  constructor(private readonly supabase: SupabaseClient) {}

  private async uid(): Promise<string> {
    const { data, error } = await this.supabase.auth.getUser();
    if (error || !data.user) throw new Error("Not signed in");
    return data.user.id;
  }

  async getOrCreateWorkspace(): Promise<Workspace> {
    const user = await this.uid();

    // 1. use profile default if present
    const { data: profile } = await this.supabase
      .from("UserProfile")
      .select("defaultWorkspaceId")
      .eq("id", user)
      .maybeSingle();
    if (profile?.defaultWorkspaceId) {
      const { data: ws } = await this.supabase
        .from("Workspace")
        .select("*")
        .eq("id", profile.defaultWorkspaceId)
        .maybeSingle();
      if (ws) return ws;
    }

    // 2. fall back to an existing membership
    const { data: member } = await this.supabase
      .from("WorkspaceMember")
      .select("workspaceId")
      .eq("userId", user)
      .limit(1)
      .maybeSingle();
    if (member?.workspaceId) {
      const { data: ws } = await this.supabase
        .from("Workspace")
        .select("*")
        .eq("id", member.workspaceId)
        .maybeSingle();
      if (ws) return ws;
    }

    // 3. create the user's default workspace (insert + own membership, RLS gated)
    const workspace: Workspace = {
      id: genWorkspaceId(),
      name: "Aaditya's Team",
      createdBy: user,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };
    // The profile row must exist BEFORE the membership insert (FK on userId),
    // so fresh sign-ups get one created (and claimed) first.
    const { data: me } = await this.supabase.auth.getUser();
    const now = new Date().toISOString();
    const { error: pErr } = await this.supabase.from("UserProfile").upsert(
      { id: user, email: me?.user?.email ?? null, name: me?.user?.email?.split("@")[0] ?? null, updatedAt: now },
      { onConflict: "id" },
    );
    if (pErr) throw pErr;
    const { error: wsErr } = await this.supabase.from("Workspace").insert(workspace);
    if (wsErr) throw wsErr;
    const { error: mErr } = await this.supabase.from("WorkspaceMember").insert({
      id: genMemberId(),
      workspaceId: workspace.id,
      userId: user,
      role: "owner",
    });
    if (mErr) throw mErr;
    // Point the profile at the new workspace so later loads skip this bootstrap.
    const { error: linkErr } = await this.supabase
      .from("UserProfile")
      .update({ defaultWorkspaceId: workspace.id, updatedAt: now })
      .eq("id", user);
    if (linkErr) throw linkErr;
    return workspace;
  }

  /**
   * First-run bootstrap: if a fresh workspace has no pages, seed the welcoming
   * "react roadmap" page the dashboard has always shown.
   */
  async ensureSeedPage(workspaceId: string): Promise<void> {
    const { data, count } = await this.supabase
      .from("Page")
      .select("id", { count: "exact", head: true })
      .eq("workspaceId", workspaceId)
      .is("deletedAt", null);
    if (count && count > 0) return;
    await this.createPage(workspaceId, { name: "react roadmap", description: "" });
  }

  async fetchPages(workspaceId: string): Promise<Page[]> {
    const { data, error } = await this.supabase
      .from("Page")
      .select("*")
      .eq("workspaceId", workspaceId)
      .is("deletedAt", null)
      .order("orderIndex", { ascending: true });
    if (error) throw error;
    return (data ?? []) as Page[];
  }

  async createPage(
    workspaceId: string,
    input: { name: string; description?: string; contentJson?: string },
  ): Promise<Page> {
    const user = await this.uid();
    const { count } = await this.supabase
      .from("Page")
      .select("id", { count: "exact", head: true })
      .eq("workspaceId", workspaceId)
      .is("deletedAt", null);
    const now = new Date().toISOString();
    const page: Page = {
      id: genPageId(),
      workspaceId,
      parentId: null,
      name: input.name.trim(),
      description: input.description?.trim() || null,
      icon: null,
      orderIndex: count ?? 0,
      contentJson: input.contentJson ?? "{}",
      createdBy: user,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      version: 1,
    };
    const { data, error } = await this.supabase.from("Page").insert(page).select().single();
    if (error) throw error;
    return data as Page;
  }

  /** Optimistic + version-guarded update. Last-write-wins by updatedAt. */
  async updatePage(
    workspaceId: string,
    id: string,
    patch: { name?: string; description?: string | null; contentJson?: string; deletedAt?: string | null },
  ): Promise<Page> {
    const current = await this.fetchPage(id);
    const now = new Date().toISOString();
    const { data, error } = await this.supabase
      .from("Page")
      .update({ ...patch, updatedAt: now, version: (current?.version ?? 0) + 1 })
      .eq("id", id)
      .eq("workspaceId", workspaceId)
      .select()
      .single();
    if (error) throw error;
    return data as Page;
  }

  async fetchPage(id: string): Promise<Page | null> {
    const { data, error } = await this.supabase.from("Page").select("*").eq("id", id).maybeSingle();
    if (error) throw error;
    return (data as Page | null) ?? null;
  }

  /** Soft-delete (archive) — row stays in the DB, hidden from page lists. */
  async archivePage(workspaceId: string, id: string): Promise<void> {
    await this.updatePage(workspaceId, id, { deletedAt: new Date().toISOString() });
  }

  /** Hard delete — only used for explicitly destructive flows. */
  async hardDeletePage(workspaceId: string, id: string): Promise<void> {
    const { error } = await this.supabase
      .from("Page")
      .delete()
      .eq("id", id)
      .eq("workspaceId", workspaceId);
    if (error) throw error;
  }

  /** Duplicate an existing page into the same workspace with a new id. */
  async duplicatePage(workspaceId: string, page: Page): Promise<Page> {
    return this.createPage(workspaceId, {
      name: `${page.name} (copy)`,
      description: page.description ?? "",
      contentJson: page.contentJson,
    });
  }

  onEvent(cb: Subscriber): () => void {
    this.listeners.add(cb);
    return () => this.listeners.delete(cb);
  }

  onStatus(cb: StatusListener): () => void {
    this.statusListeners.add(cb);
    return () => this.statusListeners.delete(cb);
  }

  /**
   * Subscribe to Realtime for one workspace. Always unsubscribe the previous
   * channel first so navigation never piles up listeners.
   */
  async subscribe(workspaceId: string): Promise<void> {
    this.unsubscribe();
    this.setStatus("connecting");
    this.channel = this.supabase
      .channel(`pages:${workspaceId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "Page", filter: `workspaceId=eq.${workspaceId}` },
        (payload) => {
          const event = payload.eventType;
          const record = (payload as { new: Page }).new as Page;
          const old = (payload as { old: Page }).old as Page;
          if (event === "DELETE") {
            this.emit({ event: "DELETE", old, new: {} as Page });
          } else if (event === "INSERT") {
            this.emit({ event: "INSERT", new: record, old: {} });
          } else {
            this.emit({ event: "UPDATE", new: record, old: old ?? {} });
          }
        },
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") this.setStatus("connected");
        else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT")
          this.setStatus("reconnecting");
        else if (status === "CLOSED") this.setStatus("closed");
      });
  }

  unsubscribe(): void {
    if (this.channel) {
      this.supabase.removeChannel(this.channel);
      this.channel = null;
    }
  }

  private emit(event: PageEvent) {
    this.listeners.forEach((cb) => cb(event));
  }

  private setStatus(state: ConnectionState) {
    this.statusListeners.forEach((cb) => cb(state));
  }
}