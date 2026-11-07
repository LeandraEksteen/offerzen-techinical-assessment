require "active_support"
require "active_support/logger"

module Pii
  # Scrubs every log line, including error logs, after it is formatted.
  # TaggedLogging extends the formatter instance and adds its tags before
  # calling this, so the whole line is scrubbed.
  class LogFormatter < ActiveSupport::Logger::SimpleFormatter
    def call(severity, timestamp, progname, msg)
      Scrubber.scrub_text(super)
    end
  end
end
