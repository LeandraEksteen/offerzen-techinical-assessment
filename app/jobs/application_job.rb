class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # Never write job arguments to the log.
  self.log_arguments = false

  # Jobs take ids (or records, which serialise to ids), never personal data.
  # The error message deliberately does not include the argument.
  before_enqueue do |job|
    unless job.arguments.all? { |argument| argument.nil? || argument.is_a?(Integer) || argument.is_a?(ActiveRecord::Base) }
      raise ArgumentError, "Job arguments must be ids or records, never personal data"
    end
  end
end
