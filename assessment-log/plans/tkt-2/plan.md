# TKT-2 plan: PII scrubber service and log hygiene base

Status: plan, not yet approved. Source ticket: `assessment-log/tickets/TKT-2.md`. Spec: `assessment-log/spec/` (Req 12, 13).

## Why this matters
The data is health related. The brief says logs already contain full request parameters and sometimes raw assessment data, and that the export must not let personal identifiers out in raw form. One shared scrubbing service means every later ticket (export, dashboard, score reader, status work) gets the same protection instead of each inventing its own. It is built before them.

## Architecture overview
A small `Pii` module (plain Ruby, no autoloading) with three parts: a registry of declared PII attribute names, a scrubber, and a log formatter. Models declare their PII attributes once through a `PiiAttributes` concern. That one declaration feeds Rails' request parameter filter and `inspect` output. The log formatter runs on every log line, including error logs, in all environments and scrubs email addresses and the values of declared attributes. A job base-class guard keeps arguments to ids. Primary protection is still "do not log data"; the formatter is the backstop.

## Requirements
- Req 12: one declaration per model drives the parameter filter, inspect output and a formatter for logs and error logs; export rows pass through the scrubber as a second guard; job arguments carry ids only.
- Req 13: a test that greps the captured log for leaked values. This ticket delivers the capture helper and checks it on the sign-in and home flows. The export and dashboard flows are checked in TKT-3 and TKT-8.

## Design

| Piece | What it does |
|---|---|
| `lib/pii/registry.rb` | `Pii::Registry` holds declared attribute names per model class name. |
| `lib/pii/scrubber.rb` | `Pii::Scrubber.scrub_text(text)`: redacts email addresses and, for each declared attribute name, the value after it in these shapes: Ruby hash (`"a"=>"v"`), JSON (`"a":"v"`), key-colon (`a: "v"`), SQL equals (`"a" = 'v'`), bind arrays (`["a", "v"]`). Values can be quoted strings, numbers, nil, or JSON objects and arrays (a small bracket matcher handles nesting and quotes). Never raises; unbalanced input is left redacted to the end of the value rather than looping. `Pii::Scrubber.scrub_attributes(model_class, attributes)`: returns the hash with declared attributes replaced by `[REDACTED]`. |
| `lib/pii/log_formatter.rb` | Subclass of Rails' simple log formatter. Formats the line, then scrubs it. Quick exit for lines with no `@` and no declared attribute name. |
| `app/models/concerns/pii_attributes.rb` | `pii_attributes :employee_email, :responses_json` registers names, appends them to `Rails.application.config.filter_parameters` (the same array object Rails reads per request), and adds them to the model's `filter_attributes` so `inspect` shows `[FILTERED]`. |
| Models | `Assessment`: `employee_email`, `responses_json`. `Employee`: `name`, `email`. `Admin`: `email`, `password_digest`. `Company`: none (a company name is not personal). |
| `config/application.rb` | Requires `lib/pii`, excludes it from autoloading, sets `config.log_formatter = Pii::LogFormatter.new`. |
| `config/environments/production.rb` | Line 38 builds its own logger, which ignores `config.log_formatter`; pass the formatter explicitly. |
| `config/initializers/pii.rb` | Loads the models on each code reload so all declarations are registered before the first request in development. |
| `app/jobs/application_job.rb` | Rejects any argument that is not an integer, nil or an ActiveRecord record; sets `log_arguments = false`. |
| `test/test_helper.rb` | `capture_log { }` swaps the Rails loggers for a string logger using the same formatter; `assert_log_clean(log, *values)`. |

**Why a formatter, not only filters:** Rails filters request parameters, SQL bind values and `inspect` output by name, but cannot filter raw text: exception messages (PostgreSQL unique violations quote the value), literal SQL, and ad hoc `logger.info` calls. The formatter catches those.

**Known limits (to go in SOLUTION.md):** positional values in a bulk `INSERT ... VALUES (...)` cannot be matched by attribute name, only emails are caught there, so bulk SQL must not be logged (the seeder already silences it); `as_json`, `pluck` and rendered HTML are not scrubbed; the development error page can show values (development only).

## Changes required (single repo)

| File | Change | Complexity |
|---|---|---|
| `lib/pii.rb`, `lib/pii/registry.rb`, `lib/pii/scrubber.rb`, `lib/pii/log_formatter.rb` (new) | The module | Medium |
| `app/models/concerns/pii_attributes.rb` (new) | Class macro | Low |
| `app/models/{assessment,employee,admin}.rb` | One `pii_attributes` line each | Low |
| `config/application.rb`, `config/environments/production.rb`, `config/initializers/pii.rb` (new) | Wiring | Low |
| `app/jobs/application_job.rb` | Argument guard, no argument logging | Low |
| `test/` | Unit and integration tests, capture helper | Medium |
| `assessment-log/` | Ticket status and results, decision, prompts | Low |

No migrations.

## Contract summary
None. Single-repo change; boundaries checked are listed in `contract.md`.

## PR strategy
One PR, base `main`, branch `feat/TKT-2/pii-scrubber-log-hygiene`, title `TKT-2 | PII scrubber service and log hygiene base`. Full yaml in `pr-strategy.yaml`.

## Test matrix

| ID | Req | Case | Type | Bucket | PR |
|---|---|---|---|---|---|
| UT-1 | 12 | Declarations register the PII attributes for Assessment, Employee, Admin | positive | unit | 1 |
| UT-2 | 12 | Declared attributes join the request parameter filter and are logged filtered | positive | unit | 1 |
| UT-3 | 12 | `inspect` redacts declared attributes, still shows the id | positive | unit | 1 |
| UT-4 | 12 | `scrub_text` redacts email addresses | positive | unit | 1 |
| UT-5 | 12 | `scrub_text` redacts declared attribute values in the five shapes, including nested JSON blobs | positive | unit | 1 |
| UT-6 | 12 | Ordinary text untouched; nil, non-strings and unbalanced brackets never raise or hang | edge | unit | 1 |
| UT-7 | 12 | `scrub_attributes` replaces declared attributes and keeps the rest | positive | unit | 1 |
| UT-8 | 12, 13 | Formatter scrubs a normal line and an error line carrying an email | positive | unit | 1 |
| UT-9 | 13 | Sign-in and home page leave no email or password in the captured log | positive | unit | 1 |
| UT-10 | 12 | Job with a string, hash or email argument fails to enqueue; ids and records accepted; arguments not logged | negative | unit | 1 |
| UT-11 | 13 | Query with bind values on declared columns does not log the values | edge | unit | 1 |
| MC-1 | 13 | Real server: sign in, load pages, grep the development log for email, password and response text | positive | manual | 1 |
| MC-2 | 12 | Production boot uses the scrubbing formatter | positive | manual | 1 |

## Risks and mitigations
- **Production logger ignores `config.log_formatter`.** Found in `production.rb`. Mitigated by passing the formatter explicitly and checking it in MC-2.
- **Over-redaction.** `Employee#name` is declared, so any request parameter called `name` is filtered everywhere (the parameter filter is global, not per model). Safe but coarse; noted.
- **Parameter filter updated at runtime.** Relies on Rails reading the same `filter_parameters` array per request; UT-2 proves it. In development, models are loaded on each reload by the initializer so declarations exist before the first request.
- **Scrubber cost and regex safety.** A regex on every log line. Quick exit for lines with nothing to scrub, linear scanning only, UT-6 covers hostile input.
- **Autoload clash.** `lib/pii` is required explicitly (the logger is built before autoloading is ready), so it is excluded from `autoload_lib`; otherwise Zeitwerk would also try to manage it.
- **Invariant writers:** none; no stored invariant is introduced.

## Open questions (need your decision)
1. **Global parameter filter.** All declared attribute names, including `name` from `Employee`, join the global parameter filter. Accept that any parameter named `name` is filtered?
2. **Jobs.** `ApplicationJob` raises for any argument other than an integer, nil or a record, and stops logging arguments. Accept this strictness? TKT-3 will then pass an export request id, not filters.
3. **Best-effort scrubber.** Accept the limits above as documented (bulk positional SQL must not be logged; emails are always caught)?
4. **PII list.** `Employee` name and email, `Assessment` employee email and responses, `Admin` email and password digest; company name is not PII. Confirm.

## Out of scope
The export and dashboard flow checks (TKT-3, TKT-8); scrubbing HTML output or API responses; external error reporters (none configured).

## Estimated scope
About 12 files, about 400 lines including tests. Single PR.

## Critic pass
Not run as a separate agent: single repo, no contract items, small scope.

## Self-check
- Req 12 and Req 13 both land in PR 1 and have unit cases; the Req 13 flows for export and dashboard are explicitly deferred to TKT-3 and TKT-8 (named in the ticket).
- No behaviour decision lives only in this plan: the choices above are open questions and will be recorded in DECISIONS.md.

## Implementation notes (added after building)
- Built as planned; no scope change. `pr-strategy.yaml` scope already covered every touched path.
- Found while testing: the scrubber's SQL string scanner first mishandled SQL's doubled quote (`'O''Brien'`); fixed and covered by a test.
- Rails prints filtered parameter values unquoted (`[FILTERED]`), so the test asserts that form.
- Added a test that the parameter filter alone, without the formatter, already hides declared attributes, so the declaration-to-filter wiring is proven separately from the formatter.
- Results: see the 2026-11-07 comment in `tickets/TKT-2.md`.

