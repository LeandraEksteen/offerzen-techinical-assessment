# rack-mini-profiler shows a per-request badge with timings and repeated queries in
# development. MINI_PROFILER=off switches it off so it does not distort benchmarks.
if Rails.env.development? && ENV["MINI_PROFILER"] == "off"
  Rack::MiniProfiler.config.enabled = false
end
