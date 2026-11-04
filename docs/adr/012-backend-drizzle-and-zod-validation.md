# ADR-012: Backend data layer is Drizzle, validation is Zod

- Status: accepted
- Date: 2026-11-04
- Revisit when: Drizzle or Zod ships a breaking major version, or a project has a requirement they cannot meet

## Context

Dave delegated these choices, and they follow industry practice. The NestJS and React standards and the Dockerfile are written for Drizzle and Zod. Recording the decision stops each project from reopening it and settles how migrations reach a shared database.

## Decision

1. Drizzle is the only ORM and query layer, and only on the backend.
2. Tables live in each module's `schema/` folder. Migrations are `drizzle-kit generate` output in the root `drizzle/` folder, reviewed and committed.
3. Migrations are applied by a separate controlled deploy step (`drizzle-kit migrate`, from the Dockerfile `migrate` stage), never by each app instance at startup.
4. `drizzle-kit push` is allowed only against a local disposable database. Never against a shared, CI, staging or production database. A PR that changes a schema must include the generated migration.
5. Zod is the only validator: `nestjs-zod` on the backend, Zod on the web.
6. Request-body schemas use `.strict()` on every nested object, so an unknown key returns 400. This is an allowlist and blocks mass assignment explicitly. Response schemas strip unknown keys.
7. Environment variables are validated with a Zod schema, not Joi.
8. These are fixed stack choices. Repo convention does not override them, an explicit exception to AGENTS.md rule 4. A repo that differs is flagged for migration, not copied. Until Dave decides, stop and ask before adding data or validation code there, and never add a second ORM or validator on your own.

## Enforcement

| Invariant | Enforced by |
| --- | --- |
| Drizzle is the only ORM | `nestjs-standards` 03-stack.md (mandatory, no alternative). Review of `package.json` |
| Migrations generated, committed, applied once per deploy | `nestjs-standards` 05-rules.md. `devops-engineering` Dockerfile `migrate` stage, run as a job |
| Schema change ships with its migration | Review now. A CI check that `drizzle-kit generate` produces no diff is possible but not written |
| Zod is the only validator, backend | `nestjs-standards` 03-stack.md and 05-rules.md (global `ZodValidationPipe`) |
| Zod is the only validator, web | `react-standards` 03-stack.md |
| Env validated by Zod | `nestjs-standards` 03-stack.md (`validate: (env) => EnvSchema.parse(env)`) |
| Request bodies reject unknown keys | `nestjs-standards` 05-rules.md, and review. No automated check |

## Alternatives considered

- **Prisma, TypeORM, Kysely, MikroORM.** Rejected: a second ORM means a second migration convention and a second testing convention.
- **class-validator, Valibot, ArkType, Joi.** Rejected: two validators double the schemas, and only Zod gives one set of types shared between web and backend.
- **Stripping unknown keys on requests.** Rejected: it hides client mistakes silently. `.strict()` makes the allowlist visible and fails loudly.

## Consequences

- Easier: one migration path, one validator, and request and response types shared from one schema.
- Harder: a team used to Prisma or class-validator must migrate before it can follow the playbook.
- Harder: Drizzle migrations are forward-only. Rollback is redeploying the previous image or fixing forward with a new migration (see the `devops-engineering` skill).
