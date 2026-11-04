## 3. Structure

### Top level

```
src/
├── main.ts                 bootstrap: pipes, interceptors, filters, CORS, prefix, port
├── app.module.ts           root wiring only
│
├── config/                 env-reading factories, typed, validated at boot
│
├── common/                 cross-cutting INFRASTRUCTURE only, never domain logic
│   ├── guards/             JwtGuard, RolesGuard
│   ├── decorators/         @CurrentUser(), @Roles(), @Public()
│   ├── interceptors/       LoggingInterceptor, TransformInterceptor
│   ├── filters/            GlobalExceptionFilter
│   ├── errors/             base exception classes and filter mapping only,
│   │                       never domain-specific errors (see 4.6)
│   ├── logger/
│   ├── types/
│   └── utils/              pure functions, no I/O
│
├── database/               Drizzle client module and seeds. Migrations are `drizzle-kit generate` output in the root `drizzle/` folder (the `out` in `drizzle.config.ts`), committed. Tables live in each module's `schema/`, and the `schema` option in `drizzle.config.ts` uses a glob over those folders (for example `./src/**/schema/*.ts`)
│
└── modules/                business capabilities
    ├── auth/
    ├── users/
    └── <domain>/
```

**`common/` holds infrastructure, not shared business rules.** If two domains need the same
business logic, it belongs to one of them (and is exported) or in a third domain module.
The test: would this code exist in a different product? If yes it is infrastructure. If no
it is domain.

**Version routes, not folders.** REQUIRED if the API is public or has external consumers.

```ts
app.enableVersioning({ type: VersioningType.URI });

@Controller({ path: 'users', version: '1' })
```

Hardcoding `v1` into folder paths means a future `v2` imports infrastructure out of a `v1`
folder. If the API has one consumer you control, a plain `/api` prefix is fine; add
versioning when you first need to break a contract.

### Domain module

Create subfolders when the module needs them, not in advance. A module with one controller
and one service is two files, and that is correct.

```
<domain>/
├── <domain>.module.ts          providers, imports, explicit exports
├── <domain>.controller.ts      split into controllers/ when audiences diverge
├── <domain>.service.ts         split into services/ when concerns diverge
├── dto/                        when there is more than a couple
├── schema/                     Drizzle table definitions for this domain
└── <domain>.service.spec.ts    tests next to the code
```

---

