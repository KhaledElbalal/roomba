# Roomba API — Conventions & Design

Conventions for the Rails API backing the Roomba dashboard. Hand this to Claude
Code as the authority on *how* the API is structured; it complements the
schema/telemetry README (the *what*) and the build PLAN (the *steps*).

Frontend and backend are separate apps. Next.js (shadcn/ui + Recharts +
TanStack Query) authenticates with Neon Auth and calls this Rails API with the
Neon Auth JWT as a Bearer token. Rails is API-only.

## Design principles

1. **RESTful resources, not RPC.** Runs and artifacts are resources; express
   them as nested REST routes. Analytics that aren't resources (DORA, cost) get
   a `metrics` namespace with named actions — the idiomatic exception.
2. **Skinny controllers.** A controller does three things: authenticate, read
   params, hand off. No SQL, no aggregation logic in controllers.
3. **Logic in plain objects (POROs).** Aggregation lives in **query objects**
   (`Metrics::DoraQuery#call` → Hash). Each is unit-testable without the web
   stack. This is the single most important convention here.
4. **Explicit serializers.** Never `render json: model`. Use a serializer so the
   JSON shape is intentional and secret-bearing columns
   (`api_key_secret_ref`, `env_secret_ref`) can never leak.
5. **Scopes for reusable filters.** `Run.for_user(id)`, `Run.in_range(r)`,
   `Run.succeeded` — composable ActiveRecord scopes the query objects chain.
6. **One base controller** for cross-cutting concerns: JWT auth, JSON format,
   error→status mapping.

## Routing

```ruby
# config/routes.rb
namespace :api do
  resources :runs, only: [:index, :show, :create] do
    resources :artifacts, only: [:index]   # nested: artifacts belong to a run
  end

  namespace :metrics do
    get :dora
    get :usage
    get :cost
    get :timeseries
  end
end
```

Resulting endpoints (all JSON, all scoped to the authenticated user):

| method | path | purpose |
|---|---|---|
| GET | `/api/runs` | paginated, filterable run list |
| GET | `/api/runs/:id` | one run + its artifact timeline |
| GET | `/api/runs/:id/artifacts` | filtered artifact stream (`?type=llm_call`) |
| POST | `/api/runs` | create/trigger a run (write side) |
| GET | `/api/metrics/dora` | lead time, deploy freq, CFR, MTTR |
| GET | `/api/metrics/usage` | run counts, success rate, queue wait |
| GET | `/api/metrics/cost` | spend + tokens, by model/provider, fallback share |
| GET | `/api/metrics/timeseries` | points for a named metric over an interval |

Query params: `range` (`7d`/`30d`/`month`), `group_by` (`repo`/`model`/`provider`),
`interval` (`day`/`week`), plus standard `page`/`per_page` on list endpoints.

The frontend sends `Authorization: Bearer <neon_auth_jwt>`. Rails verifies it
against Neon Auth's JWKS endpoint. Specifics that differ from typical Rails JWT
tutorials:

- **Algorithm is EdDSA (Ed25519), NOT RS256.** Most Rails JWT guides assume
  RS256 — do not copy those. The `jwt` gem supports EdDSA but needs `rbnacl`
  (libsodium) for Ed25519. Add both gems.
- **Verify via JWKS:** read the `kid` from the JWT header, fetch the JWKS from
  the Neon Auth JWKS URL, find the matching key, verify the signature. Cache the
  JWKS (it rarely rotates); refetch on a `kid` miss.
- **Claims to validate:** `iss` must equal your Neon Auth URL origin (e.g. if
  the auth URL is `https://ep-xx.aws.neon.tech/neondb/auth`, the issuer is
  `https://ep-xx.aws.neon.tech`); check `aud`; check `exp`. The user id is the
  `sub` claim (a UUID matching `neon_auth.users_sync.id`).
- Put all of this behind one concern so controllers just call `current_user`.

```ruby
# app/controllers/concerns/authenticatable.rb
module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate!
  end

  private

  def authenticate!
    token = request.headers["Authorization"]&.remove(/\ABearer /)
    return unauthorized! if token.blank?

    @current_user_id = NeonAuthToken.new(token).user_id  # PORO: JWKS verify, EdDSA
    unauthorized! if @current_user_id.blank?
  rescue NeonAuthToken::InvalidToken
    unauthorized!
  end

  def current_user_id = @current_user_id
  def unauthorized! = render(json: { error: "unauthorized" }, status: :unauthorized)
end
```

`NeonAuthToken` is a PORO (`app/lib/neon_auth_token.rb`) wrapping the EdDSA/JWKS
verification. It returns the `sub` claim or raises `InvalidToken`. Keep the
crypto in one place.

> Note: this validates JWTs at the **app layer**. Neon also offers DB-layer RLS
> via `pg_session_jwt` if you use the Data API directly — out of scope here
> since the dashboard goes through Rails, but worth knowing it exists.

## Base controller

```ruby
# app/controllers/api/base_controller.rb
module Api
  class BaseController < ActionController::API
    include Authenticatable

    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActionController::ParameterMissing, with: :bad_request

    private

    def not_found  = render(json: { error: "not_found" }, status: :not_found)
    def bad_request(e) = render(json: { error: e.message }, status: :bad_request)

    def range_param = RangeParam.parse(params[:range]) # PORO -> a Time range
  end
end
```

Every API controller inherits `Api::BaseController`. Auth, error mapping, and
param parsing live here once.

## Controllers (skinny)

```ruby
# app/controllers/api/metrics_controller.rb
module Api
  class MetricsController < Api::BaseController
    def dora
      render json: Metrics::DoraQuery.new(user_id: current_user_id, range: range_param).call
    end

    def cost
      render json: Metrics::CostQuery.new(
        user_id: current_user_id, range: range_param, group_by: params[:group_by]
      ).call
    end
    # usage, timeseries: same pattern
  end
end

# app/controllers/api/runs_controller.rb
module Api
  class RunsController < Api::BaseController
    def index
      runs = Run.for_user(current_user_id)
                .filter_by(status: params[:status], repo: params[:repo])
                .page(params[:page])
      render json: RunSerializer.collection(runs)
    end

    def show
      run = Run.for_user(current_user_id).find(params[:id])
      render json: RunSerializer.new(run, include_artifacts: true)
    end
  end
end
```

## Query objects (where the real work is)

One class per metric group, each returning a plain Hash. Methods map 1:1 to the
SQL in the telemetry README.

```ruby
# app/queries/metrics/dora_query.rb
module Metrics
  class DoraQuery
    def initialize(user_id:, range:)
      @user_id = user_id
      @range   = range
    end

    def call
      {
        lead_time_median_seconds: lead_time_median,
        deployment_frequency:     deploy_frequency,
        change_failure_rate:      change_failure_rate,
        mttr_seconds:             mttr
      }
    end

    private

    def scope = Run.for_user(@user_id).in_range(@range)

    def deploy_frequency
      scope.where.not(deployed_at: nil).group_by_day(:deployed_at).count
    end
    # lead_time_median, change_failure_rate, mttr: each its own private method
  end
end
```

Test these directly: build runs in a factory, call `.call`, assert the Hash. No
HTTP, no controller.

## Model scopes

```ruby
# app/models/run.rb
class Run < ApplicationRecord
  belongs_to :linear_task, optional: true
  has_many :artifacts, -> { order(:sequence) }, dependent: :destroy

  enum :status, { queued: "queued", running: "running",
                  succeeded: "succeeded", failed: "failed" }

  scope :for_user, ->(uid) { where(user_id: uid) }
  scope :in_range, ->(r)   { where(created_at: r) }

  def self.filter_by(status: nil, repo: nil)
    rel = all
    rel = rel.where(status: status)     if status.present?
    rel = rel.where(github_repo: repo)  if repo.present?
    rel
  end
end
```

## Serializers

Use an explicit serializer gem (`alba` or `blueprinter` — both idiomatic and
fast). Whitelist fields; never expose `*_secret_ref`.

```ruby
# app/serializers/run_serializer.rb  (alba style)
class RunSerializer
  include Alba::Resource
  attributes :id, :status, :github_repo, :github_pr_url,
             :started_at, :finished_at, :deployed_at,
             :cost_usd, :tokens_used, :user_rating, :changes_requested
  # NOT exposed: env_secret_ref, user_id internals, llm_provider api refs
  one :linear_task, serializer: LinearTaskSerializer
  many :artifacts, serializer: ArtifactSerializer, if: ->(_, opts) { opts[:include_artifacts] }
end
```

Metrics endpoints return aggregation-shaped JSON, not raw rows:

```jsonc
// GET /api/metrics/dora?range=30d
{ "lead_time_median_seconds": 5400, "deployment_frequency": { "2026-06-01": 3, ... },
  "change_failure_rate": 0.08, "mttr_seconds": 1320 }

// GET /api/metrics/cost?range=month&group_by=model
{ "total_usd": 42.17, "by_group": [ { "key": "gpt-4o", "spend_usd": 30.1, "tokens": 1200000 }, ... ],
  "fallback_share": 0.12 }

// GET /api/runs?page=1
{ "data": [ { ...run... } ], "page": 1, "per_page": 25, "total": 134 }
```

Keep keys snake_case in the API; let the frontend map if it prefers camelCase.

## Testing expectations
- Query objects: unit specs, no HTTP. The DORA/cost math is the highest-value
  thing to test.
- Request specs for each endpoint: auth required (401 without token), correct
  shape, user scoping (user A cannot read user B's runs).
- `NeonAuthToken`: spec the reject paths (expired, wrong issuer, bad signature).


## Commenting policy

Comment only when the code can't speak for itself. The test is: would a competent
Rails dev be momentarily confused or make a wrong assumption without this line? If
yes, comment. If the comment just restates what the next line plainly does, omit
it.

**Write a comment when:**
- The *why* is non-obvious: a constraint, a gotcha, a deliberate trade-off, or a
  decision that looks wrong until you know the reason. (e.g. "EdDSA not RS256 —
  Neon Auth signs with Ed25519"; "delete only after the block succeeds, so a
  failure re-delivers via the visibility timeout".)
- There's a subtle ordering or invariant the code depends on (e.g. "create the
  row before enqueueing — closes the lost-message window").
- A value or branch encodes domain knowledge a reader wouldn't infer (a magic
  threshold, a provider quirk, a spec requirement like "FR-4 idempotency").

**Do NOT comment when:**
- It restates the code: `# find the user` above `User.find(id)`.
- The method/variable name already says it: a `deploy_frequency` method needs no
  `# computes deployment frequency`.
- It narrates structure: `# loop over runs`, `# return the hash`.

