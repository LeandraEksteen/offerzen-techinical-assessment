require "test_helper"

class ExportRequestTest < ActiveSupport::TestCase
  setup do
    @company = create_company
    @admin = create_admin(company: @company)
  end

  # UT-13
  test "an admin cannot start a second export while one is in progress" do
    create_export(company: @company, admin: @admin)
    second = ExportRequest.new(company: @company, admin: @admin)

    assert_not second.valid?
    assert_includes second.errors.full_messages, "An export is already in progress."
  end

  test "the database index blocks a race past the validation" do
    create_export(company: @company, admin: @admin)

    assert_raises(ActiveRecord::RecordNotUnique) do
      ExportRequest.new(company: @company, admin: @admin).save!(validate: false)
    end
  end

  test "a finished export does not block the next one" do
    create_export(company: @company, admin: @admin, state: :ready)

    assert_nothing_raised { create_export(company: @company, admin: @admin) }
  end

  # UT-14
  test "an export in progress for more than 30 minutes counts as failed" do
    export = create_export(company: @company, admin: @admin)

    travel 29.minutes
    ExportRequest.sweep_stale
    assert export.reload.in_progress?

    travel 2.minutes
    ExportRequest.sweep_stale
    assert export.reload.failed?
    assert_nothing_raised { create_export(company: @company, admin: @admin) }
  end

  # UT-15
  test "an export past its retention shows as expired and cannot be downloaded" do
    export = create_export(company: @company, admin: @admin, state: :ready)
    export.file.attach(io: StringIO.new("assessment_id\n"), filename: "x.csv", content_type: "text/csv")
    assert export.downloadable?

    travel 8.days

    assert_equal "expired", export.shown_state
    assert_not export.downloadable?
  end

  test "the history keeps the 20 most recent first" do
    25.times { |n| create_export(company: @company, admin: @admin, state: :ready, row_count: n) }

    recent = ExportRequest.where(company: @company).recent

    assert_equal 20, recent.size
    assert_equal 24, recent.first.row_count
  end
end
