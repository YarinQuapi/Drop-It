import { createApp } from "./app.js";

const port = Number(process.env.PORT ?? 4000);
const host = process.env.HOST ?? "0.0.0.0";
createApp().listen(port, host, () => {
  console.log(`api listening on ${host}:${port}`);
});
