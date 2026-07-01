<div align="center">
  <img src="app/assets/images/roomba-lockup.svg" alt="roomba" width="360">
</div>

<p align="center">
  Autonomous coding agents that pick up your Linear issues, ship a PR, and tell you what it cost.
</p>

---

## What is Roomba?

Roomba is a Rails 8 API that runs **autonomous coding agents**. Assign it a
Linear issue and a repo, and it will:

1. Spin up an isolated container (Docker locally, Fargate in production).
2. Clone the repo and hand the issue to an LLM-driven edit loop.
3. Run the repo's test suite.
4. Open a pull request on green — or stop and record why it couldn't.

Every run is bounded (max iterations, wall-clock time, and USD spend), fully
traced (every LLM call, file read/edit, and command is recorded as an
artifact), and costed down to the token. Roomba's dashboard turns that trace
into an instrument: DORA metrics, spend and token usage, and a replayable
timeline for every run — not a vanity chart.

How it works

```
Linear issue ──▶ POST /api/runs ──▶ queued run (Postgres) ──▶ queue (SQS/db)
                                                                    │
                                                                    ▼
                                              runner (Docker locally / Fargate in prod)
                                                                    │
                                                                    ▼
                                    AgentHarness: clone repo → bounded LLM edit loop
                                    (primary provider, fallback on error) → test run
                                                                    │
                                                    tests green ────┴──── tests red / bound tripped
                                                          │                        │
                                                    open GitHub PR          run marked failed
                                                          │                  (reason recorded)
                                                          ▼
                                        run marked succeeded, cost/tokens cached
```

- **Runs** (`agent_runs`) are the top-level unit of work: one Linear issue,
  one target repo, one terminal outcome (`succeeded`/`failed`).
- **Artifacts** (`agent_artifacts`) are the ordered trace of a run —
  `thinking`, `read_file`, `edit_file`, `run_command`, `llm_call` — each
  timestamped so the dashboard can render a waterfall on a shared time axis.
- **Bounds** default to 20 iterations / 30 minutes / $5.00 per run so an
  unattended agent can never run away; callers can tighten or loosen them
  per run.
- **LLM providers** are user-owned and pluggable (BYOK) — a run has a primary and
  an optional fallback, tried in order via a provider chain.
- **Integrations** (GitHub, Linear) are per-user PATs, referenced only via
  a secret ref in AWS Secrets Manager.

## API

All endpoints are namespaced under `/api`, JSON, and scoped to the
authenticated user (`Authorization: Bearer <neon_auth_jwt>`, verified against
Neon Auth's JWKS).


| Method                | Path                      | Purpose                                                |
| --------------------- | ------------------------- | ------------------------------------------------------ |
| GET                   | `/api/me`                 | current authenticated user                             |
| GET/POST              | `/api/runs`               | list / trigger runs                                    |
| GET                   | `/api/runs/:id`           | one run + its artifact timeline                        |
| GET                   | `/api/runs/:id/artifacts` | filtered artifact stream (`?type=llm_call`)            |
| GET/POST/DELETE       | `/api/integrations`       | GitHub/Linear PAT management                           |
| GET/POST/PATCH/DELETE | `/api/llm_providers`      | user's configured LLM providers                        |
| GET                   | `/api/linear/issues`      | picker: list issues via the user's Linear PAT          |
| GET                   | `/api/github/repos`       | picker: list repos via the user's GitHub PAT           |
| GET                   | `/api/metrics/dora`       | lead time, deploy frequency, change failure rate, MTTR |
| GET                   | `/api/metrics/usage`      | run counts, success rate, queue wait                   |
| GET                   | `/api/metrics/cost`       | spend + tokens, by model/provider, fallback share      |
| GET                   | `/api/metrics/timeseries` | points for a named metric over an interval             |

## Architecture

- **Frontend** — Next.js (App Router) + shadcn/ui + TanStack Query, in the
  sibling `roomba-frontend` repo. Authenticates with Neon Auth and calls this
  API with the resulting JWT.
- **API** (this repo) — Rails 8, API-only. Skinny controllers hand off to
  query objects (`Metrics::*Query`) and command objects (`Runs::CreateCommand`);
  serializers keep secret-bearing columns off the wire.
  See [CLAUDE.md](CLAUDE.md) for the full conventions.
- **Database** — a single Neon Postgres instance (app data + `solid_queue`;
  no separate cache/cable databases).
  See [CLAUDE.md](CLAUDE.md) for the full conventions.
- **Queue** — `QUEUE_BACKEND` selects `db` (Solid Queue) or `sqs`; either way
  a run row commits before it's enqueued, so the queue can never reference a
  row that rolled back.
- **Agent runner** — `AGENT_BACKEND` selects `docker` (local) or `fargate`
  (production ECS). `Dockerfile.agent` runs `AgentHarness.run`, one container
  per run.
- **Infrastructure** — AWS (App Runner for the API, ECS Fargate for agent
  runs, SQS, Secrets Manager) provisioned by Terraform in the sibling
  `roomba-infra` repo, plus Neon for Postgres and auth.

## Local development

The full stack (frontend + API + local Postgres) runs via Docker Compose from
`roomba-infra/local/`:

```bash
cd ../roomba-infra/local
./bin/setup       # copy .env.example -> .env, then fill in Neon values
./bin/dev         # docker compose up --build
```

Verify:

```bash
curl -s localhost:3000/up          # -> 200
curl -i localhost:3000/api/me      # -> 401 (no token)
```

Then open `http://localhost:3001`, sign in, and land on `/dashboard`, which
round-trips your session through this API. See
`roomba-infra/local/README.md` for the full setup (Neon project + persistent
dev branch + env vars).

## Testing

```bash
bin/rails db:prepare
bin/rspec
```

Query objects and commands are unit-tested directly (no HTTP); request specs
cover auth, response shape, and per-user scoping for every endpoint.
