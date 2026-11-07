ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    TEST_PASSWORD = "test-only-password".freeze

    # Add more helper methods to be used by all tests here...
    def create_company(name: "Test Company")
      Company.create!(name: name)
    end

    def create_admin(company: create_company, email: "admin@example.test")
      Admin.create!(company: company, email: email, password: TEST_PASSWORD)
    end

    # Runs the block with every Rails logger swapped for one string logger that
    # uses the same PII-scrubbing formatter as the app, and returns what was
    # logged. Use with assert_log_clean to prove no value leaked.
    # Pass scrub: false to see what Rails itself would log without the formatter.
    def capture_log(scrub: true)
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      logger.level = Logger::DEBUG
      logger.formatter = scrub ? Pii::LogFormatter.new : ActiveSupport::Logger::SimpleFormatter.new
      holders = [ Rails, ActiveRecord::Base, ActionController::Base, ActionView::Base, ActiveJob::Base ]
      originals = holders.map(&:logger)
      holders.each { |holder| holder.logger = logger }
      begin
        yield
      ensure
        holders.zip(originals).each { |holder, original| holder.logger = original }
      end
      io.string
    end

    def assert_log_clean(log, *values)
      values.each { |value| assert_not_includes log, value, "log leaked #{value.length} characters of a sensitive value" }
    end

    def create_export(company:, admin:, **attributes)
      ExportRequest.create!({ company: company, admin: admin }.merge(attributes))
    end

    # Runs the export for a request into memory and returns the parsed CSV.
    def export_csv(export, **options)
      io = StringIO.new
      AssessmentCsvExport.new(export, **options).write_to(io)
      CSV.parse(io.string, headers: true)
    end

    # Makes building the export fail with the given message, then restores it.
    def with_failing_export(message)
      original = AssessmentCsvExport.method(:new)
      AssessmentCsvExport.define_singleton_method(:new) { |*| raise message }
      yield
    ensure
      AssessmentCsvExport.define_singleton_method(:new, original)
    end

    def create_assessment(company:, **attributes)
      employee = company.employees.create!(name: "Test Employee", email: "employee@example.test")
      Assessment.create!({ company: company, employee: employee, assessment_date: Date.current }.merge(attributes))
    end
  end
end

class ActionDispatch::IntegrationTest
  def sign_in_as(admin)
    post session_url, params: { email: admin.email, password: TEST_PASSWORD }
  end
end
