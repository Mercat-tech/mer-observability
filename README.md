# mer-observability

Plug-and-play OpenTelemetry tracing and Ruby runtime metrics for Rails microservices.

## What it does

- Auto-instruments **Rails, ActiveRecord, Sidekiq, Redis, Net::HTTP, Faraday and the `http` gem**
- Captures the **Apartment tenant** as a `tenant` attribute on every span
- Emits **Ruby runtime metrics** (GC, heap, threads, RSS) via the OTel meter
- Provides a **structured JSON log formatter** with common schema across services (stage/prod)
  and a **legacy text formatter** for dev readability (selected automatically per environment)
- Auto-populates `trace_id`, `span_id`, `tenant`, `request_id`, `client_id` and `service` on
  every log line — no manual passing required
- Patches `Sidekiq.logger.formatter` automatically so worker logs share the same schema
- Reads configuration from **environment variables** — zero boilerplate required
- **No-op in development** when `OTEL_EXPORTER_OTLP_ENDPOINT` is not set

## Installation

Add to your `Gemfile`:

```ruby
gem 'mer_observability', github: 'Mercat-tech/mer-observability', branch: 'main'
```

That's it. The Railtie registers itself automatically and calls `OpenTelemetry::SDK.configure` after Rails initializes the logger.

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | **Yes** | — | Collector URL. If absent, the gem is a no-op. |
| `OTEL_SERVICE_NAME` | No | Rails app name (with `-sidekiq` suffix in worker procs) | Name shown in your tracing backend |
| `APP_VERSION` | No | _autodiscovered_ | `service.version` resource attribute |
| `GIT_SHA` | No | _autodiscovered_ | Fallback for `service.version` |
| `RENV` | No | `RAILS_ENV` → `development` | `deployment.environment` (`stage` or `production`) |
| `OTEL_TRACES_SAMPLER_ARG` | No | `1.0` | Trace sampling ratio (0.0–1.0). Uses parent_based(trace_id_ratio_based) |
| `OTEL_LOG_INJECTION` | No | `true` | Inject `trace_id`/`span_id` into `Rails.logger` lines (text formatter only) |
| `MER_LOG_FORMAT` | No | `json` in stage/production, `text` in dev/test | Selects log formatter. Values: `json` or `text` |
| `OTEL_RUBY_RUNTIME_METRICS` | No | `true` | Emit Ruby runtime gauges via OTel meter |
| `OTEL_RUBY_RUNTIME_METRICS_INTERVAL` | No | `30` | Seconds between metric exports |

### Stage / Production example (ECS task)

```hcl
{ name = "OTEL_EXPORTER_OTLP_ENDPOINT", value = "http://<your-otel-collector-host>:4318" }
{ name = "OTEL_SERVICE_NAME",           value = "<your-service-name>" }
{ name = "OTEL_TRACES_SAMPLER_ARG",     value = "0.1" }
```

## Optional configuration block

Environment variables cover all cases. Use the block only for programmatic overrides:

```ruby
# config/initializers/mer_observability.rb
MerObservability.configure do |config|
  config.service_name            = 'my-service'
  config.capture_tenant          = true
  config.sampler_ratio           = 0.1
  config.log_injection           = true
  config.runtime_metrics_enabled = true
end
```

## Tenant capture

Every span automatically receives a `tenant` attribute with the value of `Apartment::Tenant.current`. No extra setup needed. If Apartment is not loaded (e.g. in a non-multitenant service) the attribute is simply omitted.

## Logs

The gem provides a **structured JSON log formatter** for stage/production and a **legacy text
formatter** for development. The factory `MerObservability::Formatter.build` picks one based on
`MER_LOG_FORMAT` (default: json in production/stage, text in dev/test).

Logs themselves are shipped by your existing log driver (Fluent Bit sidecar, awsfirelens, etc.)
— the gem only owns the **format** of each line written to stdout. The OTel Collector receives
them via OTLP and (with a `ParseJSON` processor) parses the JSON body into structured fields
that show up natively as filterable attributes in your tracing backend.

```
Rails.logger → JsonFormatter → stdout → Fluent Bit (awsfirelens) → OTel Collector → SigNoz
```

### Activating the formatter

In each Rails service:

```ruby
# config/environments/production.rb (and stage.rb if you have one)
config.log_formatter = MerObservability::Formatter.build
```

That's the only line you need. The Railtie also auto-patches `Sidekiq.logger.formatter` with
the same factory, so worker logs share the schema without per-service Sidekiq config.

### JSON schema

Every JSON log line includes:

| Field | Source | When present |
|---|---|---|
| `timestamp` | UTC ISO8601 with microseconds | always |
| `level` | severity (`DEBUG`/`INFO`/`WARN`/`ERROR`/`FATAL`) | always |
| `service` | `MerObservability.config.service_name` (`mer-X` or `mer-X-sidekiq`) | always |
| `pid` | `$PID` of the emitting process | always |
| `message` | the actual log message text | always (extracted from String or Hash `msg`) |
| `progname` | logger progname | when set by caller |
| `trace_id` | hex string from current OTel span | when a span is active in the context |
| `span_id` | hex string from current OTel span | idem |
| `tenant` | `Apartment::Tenant.current` | when Apartment is loaded and tenant is set |
| `request_id` | first tag of `ActiveSupport::TaggedLogging` | when `config.log_tags` includes `:request_id` |
| `client_id` | from `[CLIENT_ID: x]` tag | when `config.log_tags` includes a `CLIENT_ID:` lambda |
| `exception_class` | the class name when `msg` is an Exception | only for Exception logs |

### Adding custom fields (no infra change required)

Pass a Hash to `Rails.logger.info` (or `warn`, `error`, etc.) and every key becomes a top-level
JSON field — which lands as a queryable log attribute in your backend:

```ruby
Rails.logger.info(message: "Order created", order_id: 42, user_id: 999, store_id: 113)
# JSON: {"timestamp":"...","level":"INFO","service":"mer-core","message":"Order created",
#        "order_id":42,"user_id":999,"store_id":113,...}
```

This is the recommended pattern for structured event logs. Use primitive values (int, string,
bool) for best performance — avoid passing whole ActiveRecord objects, they're expensive to
serialize regardless of formatter.

For unstructured logs, the existing `Rails.logger.info("hello")` pattern keeps working — the
string lands in the `message` field.

### Per-instance presets for auxiliary loggers

Custom loggers (SQS workers, Redis event channels, etc.) can pre-attach context that ships
with every emission:

```ruby
sqs_logger = Logger.new($stdout)
sqs_logger.formatter = MerObservability::Formatter.build(defaults: {
  component: 'sqs',
  queue_url: queue_url,
  message_id: message_id,
  worker: worker_name
})

sqs_logger.info("Processing message")
# JSON includes: component, queue_url, message_id, worker, plus the standard schema
```

### Per-thread log context (`MerObservability.log_context`)

A generic, app-owned extension point. Anything you put in `MerObservability.log_context`
(a per-thread hash) is merged into **every** JSON log line emitted on that thread —
without per-call wiring. The gem does not define what goes here; apps decide.

Typical use: a Sidekiq server middleware that propagates an originating request id so a
worker's logs can be correlated with the request that enqueued the job:

```ruby
# Sidekiq server middleware (app side)
def call(worker, job, queue)
  MerObservability.log_context[:origin_request_id] = job['origin_request_id'] if job['origin_request_id']
  yield
ensure
  MerObservability.reset_log_context!   # clear between jobs on the reused thread
end
```

Every line that worker logs then carries `origin_request_id`. Remember to clear it
(`reset_log_context!`) at the end of the unit of work so it does not leak to the next
job on the same thread. No-op when the context is empty.

### Text formatter (dev only)

When `MER_LOG_FORMAT=text` (the default in development), each line is rendered as the
standard Ruby Logger output **prefixed** with the service name and OTel ids when available:

```
service=mer-core trace_id=4bf92f3577b34da6a3ce929d0e0e4736 span_id=00f067aa0ba902b7 I, [...] INFO -- : Started GET "/api/v1/orders/42"
```

This keeps local terminal output human-readable while preserving log↔trace correlation.

### OTel Collector pipeline (`transform/json_logs`)

For the JSON format to surface correctly in the backend, the OTel Collector deployed alongside
should include a `transform/json_logs` processor that:

1. Parses the body as JSON when it starts with `{`
2. Promotes `service` → `resource.attributes["service.name"]`
3. Promotes `trace_id` / `span_id` → first-class LogRecord fields
4. Promotes `level` → `severity_text` and `severity_number`
5. Promotes `message` → `body`
6. Leaves every other field in `attributes` (so adding new fields in code requires zero infra change)

See `mer-infrastructure/modules/signoz_collector/main.tf` in this organization for the
canonical OTTL implementation.

## Sampling

The default is `OTEL_TRACES_SAMPLER_ARG=1.0` (always on — every trace exported). For production with non-trivial traffic you'll want to lower this:

```bash
OTEL_TRACES_SAMPLER_ARG=0.1   # keep ~10% of root traces
```

The sampler is **parent-based**: if an upstream service or the frontend marked a trace as sampled, downstream services respect that decision. This guarantees that distributed traces are never broken by sampling.

## Process types: rails vs sidekiq

Rails web processes report `service.name=my-service`. Sidekiq workers report `service.name=my-service-sidekiq`. This makes it trivial to filter web vs background activity in your tracing backend.

To see "all of my-service" across web and worker, filter by `service.name =~ /^my-service/` in your backend's queries.

If you ever want them unified under a single `service.name` with a separate `process.type` resource attribute, the change lives at `lib/mer_observability/configuration.rb` (`default_service_name`).

### Sidekiq.logger formatter

The gem also patches `Sidekiq.logger.formatter` automatically with the same factory output.
This happens inside `Sidekiq.configure_server` so it only takes effect in worker processes,
and is decoupled from how each service configures Sidekiq (some do
`Rails.logger = Sidekiq::Logging.logger`, others don't — the gem covers both).

Result: in production, every line Sidekiq emits (job lifecycle messages, queue heartbeats,
errors, plus your own `Rails.logger.info` calls from inside workers) is emitted as JSON with
`service: "<name>-sidekiq"`.

## Versioning

`service.version` is resolved in this order:

1. `ENV['APP_VERSION']` — explicit override (recommended in CI/CD).
2. `ENV['GIT_SHA']` — common in Docker pipelines.
3. `Rails.root/REVISION` — Heroku-style revision file.
4. `Rails.root/.git/HEAD` — first 12 chars (last resort, dev environments).
5. Fallback: `'unknown'`.

## Runtime metrics

When enabled (`OTEL_RUBY_RUNTIME_METRICS=true`, default), the gem emits these gauges every `OTEL_RUBY_RUNTIME_METRICS_INTERVAL` seconds (default 30):

| Metric | Unit | Source |
|---|---|---|
| `ruby.gc.count` | runs | `GC.stat[:count]` |
| `ruby.gc.major_count` | runs | `GC.stat[:major_gc_count]` |
| `ruby.gc.minor_count` | runs | `GC.stat[:minor_gc_count]` |
| `ruby.gc.heap_live_slots` | slots | `GC.stat[:heap_live_slots]` |
| `ruby.gc.heap_free_slots` | slots | `GC.stat[:heap_free_slots]` |
| `ruby.threads.count` | threads | `Thread.list.count` |
| `ruby.process.rss_bytes` | bytes | `/proc/self/status` (Linux only) |

> ⚠️ The OTel metrics SDK in Ruby is currently in beta. Metric names follow the [semantic conventions proposal](https://opentelemetry.io/docs/specs/semconv/runtime/) but may evolve in future versions of `opentelemetry-metrics-sdk`.

To disable: `OTEL_RUBY_RUNTIME_METRICS=false`.

## HTTP clients

Auto-instrumentation is enabled (when the gem is loaded in the app) for:

| Client | Instrumentation | Notes |
|---|---|---|
| `Net::HTTP` (stdlib) | `opentelemetry-instrumentation-net_http` | Always available |
| `HTTParty` | _via Net::HTTP_ | Inherits Net::HTTP instrumentation transparently |
| `Faraday` | `opentelemetry-instrumentation-faraday` | Activates only if Faraday is in the app's bundle |
| `http` gem (httprb/http) | `opentelemetry-instrumentation-http` | Activates only if the gem is in the app's bundle |

## Troubleshooting

**No traces in your backend**
- Confirm `OTEL_EXPORTER_OTLP_ENDPOINT` is set in the running environment (not just in the Dockerfile).
- From the container: `nc -zv <your-otel-collector-host> 4317` should succeed.
- Check stderr for the `[MerObservability] Setup failed: ...` line.

**Traces arrive but `tenant` is blank**
- Verify `Apartment::Tenant.current` returns the expected value during a request.
- An empty string or nil is dropped silently.

**Runtime metrics not appearing**
- The OTel metrics SDK is in beta. Check stderr for `[MerObservability] runtime metrics setup failed: ...`.
- Verify your backend accepts OTel metrics in addition to traces.
- `ruby.process.rss_bytes` will be `0` outside Linux (macOS dev, etc.).

## Compatibility

Minimum Ruby: **3.3**. Minimum Rails: **7.0**.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

CI runs the same on every PR.
