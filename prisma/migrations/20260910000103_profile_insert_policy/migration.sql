-- Fresh accounts have no profile row, but WorkspaceMember.userId has a foreign
-- key to UserProfile.id, so the profile must exist BEFORE a membership insert.
-- Users must be able to create their own profile row (RLS), which the original
-- migration omitted (it only added select/update policies).

CREATE POLICY "user_profile_insert_own" ON "UserProfile"
    FOR INSERT WITH CHECK (auth.uid()::text = "id");