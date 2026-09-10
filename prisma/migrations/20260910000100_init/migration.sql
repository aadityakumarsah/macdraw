-- DATABASE MIGRATION: init (pages / workspaces / members / user profiles)
-- Shared canonical model for the Mac app and React Roadmap.
-- Generated to match prisma/schema.prisma plus RLS + Realtime infrastructure.

-- ============================================================
-- SCHEMA
-- ============================================================

CREATE TABLE "UserProfile" (
    "id" TEXT NOT NULL,
    "email" TEXT,
    "name" TEXT,
    "theme" TEXT NOT NULL DEFAULT 'dark',
    "defaultWorkspaceId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "UserProfile_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "Workspace" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "createdBy" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "Workspace_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "WorkspaceMember" (
    "id" TEXT NOT NULL,
    "workspaceId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "role" TEXT NOT NULL DEFAULT 'member',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "WorkspaceMember_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "Page" (
    "id" TEXT NOT NULL,
    "workspaceId" TEXT NOT NULL,
    "parentId" TEXT,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "icon" TEXT,
    "orderIndex" INTEGER NOT NULL DEFAULT 0,
    "contentJson" TEXT NOT NULL DEFAULT '{}',
    "createdBy" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "deletedAt" TIMESTAMP(3),
    "version" INTEGER NOT NULL DEFAULT 1,
    CONSTRAINT "Page_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "WorkspaceMember_workspaceId_userId_key" ON "WorkspaceMember"("workspaceId", "userId");
CREATE INDEX "Page_workspaceId_deletedAt_idx" ON "Page"("workspaceId", "deletedAt");
CREATE INDEX "Page_workspaceId_orderIndex_idx" ON "Page"("workspaceId", "orderIndex");

ALTER TABLE "WorkspaceMember"
    ADD CONSTRAINT "WorkspaceMember_workspaceId_fkey"
    FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "WorkspaceMember"
    ADD CONSTRAINT "WorkspaceMember_userId_fkey"
    FOREIGN KEY ("userId") REFERENCES "UserProfile"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "Page"
    ADD CONSTRAINT "Page_workspaceId_fkey"
    FOREIGN KEY ("workspaceId") REFERENCES "Workspace"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE "UserProfile" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Workspace" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "WorkspaceMember" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Page" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_profile_select_own" ON "UserProfile"
    FOR SELECT USING (auth.uid()::text = "id");
CREATE POLICY "user_profile_update_own" ON "UserProfile"
    FOR UPDATE USING (auth.uid()::text = "id")
    WITH CHECK (auth.uid()::text = "id");

-- Workspaces: readable by members, insertable by their creator, deletable by owners.
CREATE POLICY "workspace_select_member" ON "Workspace"
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM "WorkspaceMember" m
            WHERE m."workspaceId" = "Workspace"."id"
              AND m."userId" = auth.uid()::text
        )
    );
CREATE POLICY "workspace_insert_creator" ON "Workspace"
    FOR INSERT WITH CHECK ("createdBy" = auth.uid()::text);

-- Members: your own rows are yours; also let an owner read a workspace's roster.
CREATE POLICY "member_select_related" ON "WorkspaceMember"
    FOR SELECT USING (
        "userId" = auth.uid()::text
        OR EXISTS (
            SELECT 1 FROM "WorkspaceMember" mine
            WHERE mine."workspaceId" = "WorkspaceMember"."workspaceId"
              AND mine."userId" = auth.uid()::text
        )
    );
-- Self-provision: a user may add themselves to a workspace they created.
CREATE POLICY "member_insert_self" ON "WorkspaceMember"
    FOR INSERT WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1 FROM "Workspace" w
            WHERE w."id" = "WorkspaceMember"."workspaceId"
              AND w."createdBy" = auth.uid()::text
        )
    );
CREATE POLICY "member_update_own" ON "WorkspaceMember"
    FOR UPDATE USING ("userId" = auth.uid()::text);
CREATE POLICY "member_delete_own" ON "WorkspaceMember"
    FOR DELETE USING ("userId" = auth.uid()::text);

-- Pages: everything is gated on workspace membership.
CREATE POLICY "page_select_member" ON "Page"
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM "WorkspaceMember" m
            WHERE m."workspaceId" = "Page"."workspaceId"
              AND m."userId" = auth.uid()::text
        )
    );
CREATE POLICY "page_insert_member" ON "Page"
    FOR INSERT WITH CHECK (
        "createdBy" = auth.uid()::text
        AND EXISTS (
            SELECT 1 FROM "WorkspaceMember" m
            WHERE m."workspaceId" = "Page"."workspaceId"
              AND m."userId" = auth.uid()::text
        )
    );
CREATE POLICY "page_update_member" ON "Page"
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM "WorkspaceMember" m
            WHERE m."workspaceId" = "Page"."workspaceId"
              AND m."userId" = auth.uid()::text
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM "WorkspaceMember" m
            WHERE m."workspaceId" = "Page"."workspaceId"
              AND m."userId" = auth.uid()::text
        )
    );
CREATE POLICY "page_delete_member" ON "Page"
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM "WorkspaceMember" m
            WHERE m."workspaceId" = "Page"."workspaceId"
              AND m."userId" = auth.uid()::text
        )
    );

-- ============================================================
-- GRANTS (row-level security enforces the actual access control)
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON "UserProfile", "Workspace", "WorkspaceMember", "Page"
    TO anon, authenticated;

-- ============================================================
-- REALTIME — broadcast page changes to subscribed clients.
-- Realtime respects RLS: subscribers only receive rows they may select.
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public."Page";