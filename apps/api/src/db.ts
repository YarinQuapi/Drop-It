import "dotenv/config";
import { PrismaMariaDb } from "@prisma/adapter-mariadb";
import { PrismaClient } from "../generated/prisma/client.js";

const adapter = new PrismaMariaDb({
  host: process.env.DATABASE_HOST,
  user: process.env.DATABASE_USER,
  password: process.env.DATABASE_PASSWORD,
  database: process.env.DATABASE_NAME,
  port: Number(process.env.DATABASE_PORT ?? 3306),
  connectionLimit: 5,
  // MySQL 8's caching_sha2_password needs the server's RSA key for the first
  // login after a MySQL restart. Without this every connection fails until
  // some other client logs in as the same user and warms the server's cache.
  allowPublicKeyRetrieval: true,
});

export const prisma = new PrismaClient({ adapter });
