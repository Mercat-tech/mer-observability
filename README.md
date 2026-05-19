# mer-observability

Plug-and-play OpenTelemetry tracing and Ruby runtime metrics for Rails microservices.

## What it does

- Auto-instruments **Rails, ActiveRecord, Sidekiq, Redis, Net::HTTP, Faraday and the `http` gem**
- Captures the **Apartment tenant** as a `tenant` attribute on every span
- Emits **Ruby runtime metrics** (GC, heap, threads, RSS) via the OTel meter
- Injects **`trace_id` and `span_id` into `Rails.logger`** for log↔trace correlation in your tracing backend
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
| `OTEL_LOG_INJECTION` | No | `true` | Inject `trace_id`/`span_id` into `Rails.logger` lines |
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

This gem **only emits traces and runtime metrics** via OTLP. Application logs continue to flow through the existing path:

```
Rails.logger → stdout → log shipper → OTel Collector → your tracing backend
```


What this gem *does* add to your logs is **`trace_id` / `span_id` injection** into every `Rails.logger` line so your backend can correlate logs to traces:

```
trace_id=4bf92f3577b34da6a3ce929d0e0e4736 span_id=00f067aa0ba902b7 I, [...] INFO -- : Started GET "/api/v1/orders/42"
```

To disable injection: `OTEL_LOG_INJECTION=false`.

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
