import { prisma } from "./db.js";

const email = process.argv[2]?.toLowerCase();
if (!email) {
  console.error("usage: npm run make-admin -- user@example.com");
  process.exit(1);
}

const user = await prisma.user.update({
  where: { email },
  data: { isAdmin: true },
});
console.log(`admin: ${user.email}`);
await prisma.$disconnect();
