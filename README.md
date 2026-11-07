# Offerzen Techinical Assessment: safely extending a legacy Assessments module

A Rails 8.1 app (PostgreSQL, TypeScript with Stimulus) for company admins who manage employee ergonomic and health assessments. It was built as a take-home: a company-scoped CSV export, a faster dashboard with a trustworthy score, and a safe status normalisation with a plan for historical data.

- **Why and how it works:** [SOLUTION.md](SOLUTION.md) (design, trade-offs, benchmarks, the status plan).
- **How it was built:** [assessment-log/](assessment-log/README.md) (every prompt, numbered decisions, the spec, one ticket per piece of work).

## Requirements

| Tool | Version |
|---|---|
| Ruby | 3.3.3 (`.ruby-version`) |
| Node.js and Yarn | 24.7.0 (`.node-version`), Yarn 1 |
| PostgreSQL | 16 (tested) |

## 1. Start PostgreSQL

`config/database.yml` connects to `localhost:5433` as the role `postgres` with no password. Either run a server like that, or point the app at yours with environment variables (set them in every shell you use for the app):

```bash
export PGHOST=localhost
export PGPORT=5432          # default in database.yml is 5433
export PGUSER=postgres      # e.g. your own OS user with a Homebrew install
export PGPASSWORD=...       # only if your server asks for one
```

## 2. Set up

```bash
bin/setup --skip-server
```

This installs gems and JavaScript packages and prepares the development database. A fresh database gets a **small** seed (3 companies, 300 assessments) automatically.

## 3. Load the large dataset (optional, about 1 minute)

The performance work was measured on 500,000 assessments across 20 companies (one has 200,000), with deliberately messy statuses and score shapes. The task refuses to run if assessments already exist, and `db:reset` would bring the small seed back, so start from an empty schema:

```bash
bin/rails db:drop db:create db:schema:load assessments:seed
```

Smaller sizes: `bin/rails db:drop db:create db:schema:load assessments:seed TOTAL=5000 COMPANIES=3`. The data is synthetic and deterministic.

## 4. Run the app

```bash
bin/dev                     # Rails server on port 3000 plus the TypeScript build in watch mode
```

or, without foreman, build the JavaScript once and start the server yourself:

```bash
yarn build
bin/rails server -b 127.0.0.1
```

### The job worker
Exports are background jobs. **In development you need nothing extra:** the Rails server process runs them. In production the queue is Solid Queue: run `bin/jobs` as a worker process, or set `SOLID_QUEUE_IN_PUMA` to run it inside Puma (as `config/deploy.yml` does). Production also needs S3-style storage for the files (see SOLUTION.md); neither was exercised outside development.

## 5. Sign in

Open http://localhost:3000 (or http://127.0.0.1:3000, or the port you chose). The seed creates one admin per company:

- email: `admin<N>@company-<N>.example.test`, for example `admin1@company-1.example.test` (company 1, the largest in the big seed);
- password: the development password set in `AssessmentSeeder::DEFAULT_PASSWORD` (`lib/assessment_seeder.rb`). To use your own, run the seed with `SEED_ADMIN_PASSWORD=...` set. It is a development convenience and is not used anywhere else.

What to try:

| Page | What it shows |
|---|---|
| Dashboard | Assessments of your company, 50 per page, filters for date and status, score, and an "Edit status" link per row |
| Exports | Start a CSV export with the same two filters, refresh until it is ready, download it |
| Edit status | A dropdown of the five statuses (a legacy value shows as a note) |

Admins only ever see their own company; another company's ids are a 404.

## Tests and checks

```bash
bin/rails db:test:prepare test    # the test suite
bin/rubocop                       # style (rubocop-rails-omakase)
bin/brakeman --no-pager           # static security scan
bin/bundler-audit                 # gem vulnerabilities
yarn typecheck                    # TypeScript
bin/ci                            # CI steps in one go
```

CI (GitHub Actions) runs rubocop, brakeman, bundler-audit and the tests on every pull request.

## Useful tasks

| Task | What it does |
|---|---|
| `bin/rails assessments:seed` | Seed the large messy dataset (`TOTAL`, `COMPANIES`) |
| `bin/rails scores:report` | Read-only report of how the score reader reads every stored score |
| `bin/rails statuses:report` | Read-only report of the distinct stored statuses, with a count and latest date each |
| `BULLET=off MINI_PROFILER=off RAILS_LOG_LEVEL=warn bin/rails benchmark:dashboard` | Time the dashboard (see `assessment-log/benchmarks/`) |
| `bin/rails benchmark:explain` | `EXPLAIN (ANALYZE, BUFFERS)` of the dashboard's main query |
| `bin/rails dashboard:snapshot` | Print page 1 without emails, to diff against the committed snapshots |

The status rule's cut-over date is an environment variable: `STATUS_CUTOVER_DATE=2026-12-01` (an ISO date; unset means the rule is enforced now). See SOLUTION.md.

## Troubleshooting

- **Cannot connect to PostgreSQL:** check `PGHOST`, `PGPORT` and `PGUSER` above; the default port is 5433, not 5432.
- **`Assessments already exist; run db:reset first` from the seed task:** use the `db:drop db:create db:schema:load assessments:seed` command in step 3 (`db:reset` re-creates the small seed).
- **Timing the dashboard:** stop any stale server on port 3055 first and use the switches shown in the table above.
