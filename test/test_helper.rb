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

    def create_assessment(company:, **attributes)
      employee = company.employees.create!(name: "Test Employee", email: "employee@example.test")
      Assessment.create!({ company: company, employee: employee, assessment_date: Date.current }.merge(attributes))
    end
  end
end
