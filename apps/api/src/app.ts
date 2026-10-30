import cookieParser from "cookie-parser";
import cors from "cors";
import express from "express";
import { sendError } from "./http.js";
import { appleHealthRouter } from "./routes/apple-health.js";
import { authRouter } from "./routes/auth.js";
import { daysRouter } from "./routes/days.js";
import { fastingRouter } from "./routes/fasting.js";
import { foodsRouter } from "./routes/foods.js";
import { profileRouter } from "./routes/profile.js";
import { rbacRouter } from "./routes/rbac.js";
import { weeksRouter } from "./routes/weeks.js";
import { weightsRouter } from "./routes/weights.js";

export function createApp() {
  const app = express();
  app.use(
    cors({
      origin: [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:5174",
        "http://127.0.0.1:5174",
        "http://localhost:5175",
        "http://127.0.0.1:5175",
        "https://drop-it.yarinlevi.dev",
        "https://api-dropit.yarinlevi.dev",
      ],
      credentials: true,
    }),
  );
  app.use(express.json({ limit: "1mb" }));
  app.use(cookieParser());
  app.get("/api/health", (_req, res) => {
    res.json({ ok: true });
  });
  app.use("/api/auth", authRouter);
  app.use("/api/profile", profileRouter);
  app.use("/api/foods", foodsRouter);
  app.use("/api/days", daysRouter);
  app.use("/api/weeks", weeksRouter);
  app.use("/api/weights", weightsRouter);
  app.use("/api/fasting", fastingRouter);
  app.use("/api/apple-health", appleHealthRouter);
  app.use("/api/rbac", rbacRouter);
  app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
    sendError(err, res);
  });
  return app;
}
