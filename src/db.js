import 'dotenv/config';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@prisma/client';

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  throw new Error('DATABASE_URL is not set — paste the Supabase pooler connection string into .env');
}

// Prisma 7 connects through a driver adapter instead of `url` in the schema.
const adapter = new PrismaPg({ connectionString });

// Single shared PrismaClient — see https://pris.ly/d/help/next-js-best-practices
const globalForPrisma = globalThis;

export const prisma = globalForPrisma.prisma ?? new PrismaClient({ adapter });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;