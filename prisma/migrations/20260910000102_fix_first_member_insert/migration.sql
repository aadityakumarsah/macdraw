-- Second RLS fix: inserting the *first* member row of a workspace was blocked
-- because the WITH CHECK subquery (SELECT workspace) is subject to the
-- workspace SELECT policy, which requires membership that does not exist yet.
-- A SECURITY DEFINER helper answers the only question we need here — "did the
-- current user create this workspace?" — without going through RLS.

CREATE OR REPLACE FUNCTION public.is_workspace_creator(workspace text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
    SELECT EXISTS (
        SELECT 1 FROM public."Workspace" w
        WHERE w."id" = workspace
          AND w."createdBy" = auth.uid()::text
    );
$$;

REVOKE ALL ON FUNCTION public.is_workspace_creator(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_workspace_creator(text) TO anon, authenticated;

DROP POLICY IF EXISTS "member_insert_self" ON public."WorkspaceMember";
CREATE POLICY "member_insert_self" ON public."WorkspaceMember"
    FOR INSERT WITH CHECK (
        "userId" = auth.uid()::text
        AND public.is_workspace_creator("workspaceId")
    );