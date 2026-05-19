require 'opentelemetry'

module MerObservability
  # Ruby runtime metrics emitter via OpenTelemetry observable gauges.
  # The SDK invokes the provided callbacks at each metric export cycle
  # (interval is controlled by PeriodicMetricReader in setup.rb).
  #
  # The OTel metrics SDK is still in beta — semantic names follow the proposal
  # at https://opentelemetry.io/docs/specs/semconv/runtime/ but may evolve.
  module RuntimeMetrics
    METER_NAME = 'mer_observability.ruby_runtime'.freeze

    class << self
      def install!
        meter = OpenTelemetry.meter_provider.meter(METER_NAME, version: MerObservability::VERSION)
        register_gauges(meter)
        true
      rescue StandardError => e
        warn "[MerObservability] runtime metrics setup failed: #{e.message}"
        false
      end

      private

      def register_gauges(meter)
        gauge_specs.each do |spec|
          meter.create_observable_gauge(spec[:name],
                                        callback: spec[:callback],
                                        unit: spec[:unit],
                                        description: spec[:description])
        end
      end

      def gauge_specs
        gc_gauge_specs + system_gauge_specs
      end

      def gc_gauge_specs
        [
          { name: 'ruby.gc.count',           unit: '1', description: 'Total GC runs',
            callback: ->(o) { o.observe(GC.stat[:count].to_i) } },
          { name: 'ruby.gc.major_count',     unit: '1', description: 'Major GC runs',
            callback: ->(o) { o.observe(GC.stat[:major_gc_count].to_i) } },
          { name: 'ruby.gc.minor_count',     unit: '1', description: 'Minor GC runs',
            callback: ->(o) { o.observe(GC.stat[:minor_gc_count].to_i) } },
          { name: 'ruby.gc.heap_live_slots', unit: '1', description: 'Live heap slots',
            callback: ->(o) { o.observe(GC.stat[:heap_live_slots].to_i) } },
          { name: 'ruby.gc.heap_free_slots', unit: '1', description: 'Free heap slots',
            callback: ->(o) { o.observe(GC.stat[:heap_free_slots].to_i) } }
        ]
      end

      def system_gauge_specs
        [
          { name: 'ruby.threads.count',     unit: '1',  description: 'Active Ruby threads',
            callback: ->(o) { o.observe(Thread.list.count) } },
          { name: 'ruby.process.rss_bytes', unit: 'By', description: 'Process resident set size (Linux only)',
            callback: ->(o) { o.observe(read_rss_bytes) } }
        ]
      end

      def read_rss_bytes
        status_path = '/proc/self/status'
        return 0 unless File.exist?(status_path)

        File.foreach(status_path) do |line|
          next unless line.start_with?('VmRSS:')

          kb = line.split[1].to_i
          return kb * 1024
        end
        0
      rescue StandardError
        0
      end
    end
  end
end
