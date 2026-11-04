## 2. Stack

### Required for every project

| Concern | Choice |
|---|---|
| Framework | NestJS, TypeScript |
| Database | One, migrated with drizzle-kit (generated SQL migrations, committed) |
| ORM / query layer | Drizzle. Mandatory, no alternative |
| Validation | Zod via `nestjs-zod`. Mandatory, no alternative |
| Logging | Structured: Pino (`nestjs-pino`) or Winston |
| Auth | JWT + Passport, or session-based |
| API docs | OpenAPI via `@nestjs/swagger` |
| Config | `@nestjs/config` with a Zod env schema via `validate: (env) => EnvSchema.parse(env)`, never the Joi-based `validationSchema` |

### Add when a requirement justifies it

| Infrastructure | Add it when |
|---|---|
| Redis | You need shared cache, distributed locks, or rate limiting across instances |
| Queue (BullMQ) | You have work that is slow, retryable, or must survive a restart |
| WebSockets | You need server-push. Polling is often enough |
| Object storage | You accept uploads |
| Multiple instances | One instance cannot carry the load, or you need zero-downtime deploys |
| Distributed tracing | You have more than one service to trace across |

A single-instance monolith on Postgres with no Redis and no queue is a legitimate
production architecture. Do not add infrastructure to satisfy this document.

---

