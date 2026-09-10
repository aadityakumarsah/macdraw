let seq = 0;

export function genPageId(): string {
  seq += 1;
  return `page_${Date.now().toString(36)}_${(Math.random() * 0xffffff).toString(36).padStart(6, "0")}`;
}

export function genWorkspaceId(): string {
  return `workspace_${Date.now().toString(36)}_${(Math.random() * 0xffffff).toString(36).padStart(6, "0")}`;
}

export function genMemberId(): string {
  return `member_${Date.now().toString(36)}_${(Math.random() * 0xffffff).toString(36).padStart(6, "0")}`;
}

export function timeAgo(iso: string): string {
  const then = new Date(iso).getTime();
  if (Number.isNaN(then)) return "";
  const s = Math.max(0, Math.floor((Date.now() - then) / 1000));
  if (s < 45) return "just now";
  const m = Math.floor(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.floor(m / 60);
  if (h < 24) return `${h} hr${h > 1 ? "s" : ""} ago`;
  const d = Math.floor(h / 24);
  if (d < 7) return d === 1 ? "yesterday" : `${d} days ago`;
  return new Date(iso).toLocaleDateString();
}

export function initials(email?: string | null): string {
  if (!email) return "?";
  const base = email.split("@")[0];
  const parts = base.split(/[._-]/);
  return (parts[0]?.[0] ?? "?") + (parts[1]?.[0] ?? "");
}