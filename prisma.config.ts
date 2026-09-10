import 'dotenv/config';
import { defineConfig } from 'prisma/config';

// Migrations / introspection use the session-mode pooler (DIRECT_URL) so DDL
// never travels through pgbouncer; prisma generate works without either.
const url = process.env.DIRECT_URL ?? process.env.DATABASE_URL;

export default defineConfig({
  schema: 'prisma/schema.prisma',
  ...(url ? { datasource: { url } } : {}),
});