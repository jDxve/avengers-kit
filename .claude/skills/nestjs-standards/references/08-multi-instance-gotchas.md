## 7. Multi-instance gotchas

The moment you run more than one process, these break silently:

- **Cron and scheduled jobs** fire once per instance. Distributed lock, or pin to one
  instance.
- **WebSockets** only reach clients on the same instance. Redis adapter plus sticky sessions.
- **In-memory anything**: rate limit counters, caches, session stores, dedupe maps. Move to
  Redis.
- **Database pool size** multiplies by instance count. Check against the database limit, and
  against the pooler limit if one sits in front.

If you deliberately run a single instance, write that down with the reason. Otherwise
someone scales it later and the bugs look like ghosts.

---

