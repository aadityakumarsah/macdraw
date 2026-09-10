-- Fix RLS recursion: membership checks now go through a SECURITY DEFINER
-- helper. Ordinary policies can call it without re-entering RLS on the very
-- table being restricted, which caused "infinite recursion detected in policy
-- for relation WorkspaceMember".

CREATE OR REPLACE FUNCTION public.is_workspace_member(workspace text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."WorkspaceMember" m
        WHERE m."workspaceId" = workspace
          AND m."userId" = auth.uid()::text
    );
$$;

REVOKE ALL ON FUNCTION public.is_workspace_member(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_workspace_member(text) TO anon, authenticated;

-- Rebuild the member policies without self-references.
DROP POLICY IF EXISTS "member_select_related" ON public."WorkspaceMember";
DROP POLICY IF EXISTS "member_insert_self" ON public."WorkspaceMember";

CREATE POLICY "member_select_related" ON public."WorkspaceMember"
    FOR SELECT USING (
        "userId" = auth.uid()::text
        OR public.is_workspace_member("workspaceId")
    );

CREATE POLICY "member_insert_self" ON public."WorkspaceMember"
    FOR INSERT WITH CHECK (
        "userId" = auth.uid()::text
        AND EXISTS (
            SELECT 1 FROM public."Workspace" w
            WHERE w."id" = "WorkspaceMember"."workspaceId"
              AND w."createdBy" = auth.uid()::text
        )
    );

-- Rebuild every membership check in the other tables through the helper.
DROP POLICY IF EXISTS "workspace_select_member" ON public."Workspace";
CREATE POLICY "workspace_select_member" ON public."Workspace"
    FOR SELECT USING (public.is_workspace_member("id"));

DROP POLICY IF EXISTS "page_select_member" ON public."Page";
CREATE POLICY "page_select_member" ON public."Page"
    FOR SELECT USING (public.is_workspace_member("workspaceId"));

DROP POLICY IF EXISTS "page_insert_member" ON public."Page";
CREATE POLICY "page_insert_member" ON public."Page"
    FOR INSERT WITH CHECK (
        "createdBy" = auth.uid()::text
        AND public.is_workspace_member("workspaceId")
    );

DROP POLICY IF EXISTS "page_update_member" ON public."Page";
CREATE POLICY "page_update_member" ON public."Page"
    FOR UPDATE USING (public.is_workspace_member("workspaceId"))
    WITH CHECK (public.is_workspace_member("workspaceId"));

DROP POLICY IF EXISTS "page_delete_member" ON public."Page";
CREATE POLICY "page_delete_member" ON public."Page"
    FOR DELETE USING (public.is_workspace_member("workspaceId"));