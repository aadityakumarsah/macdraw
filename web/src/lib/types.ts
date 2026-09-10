export type Page = {
  id: string;
  workspaceId: string;
  parentId: string | null;
  name: string;
  description: string | null;
  icon: string | null;
  orderIndex: number;
  contentJson: string;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  version: number;
};

export type Workspace = {
  id: string;
  name: string;
  createdBy: string;
  createdAt: string;
  updatedAt: string;
};

export type PageEvent =
  | { event: "INSERT"; new: Page; old: Record<string, never> }
  | { event: "UPDATE"; new: Page; old: Partial<Page> }
  | { event: "DELETE"; old: Page; new: Record<string, never> };

export type ConnectionState = "connecting" | "connected" | "reconnecting" | "closed";