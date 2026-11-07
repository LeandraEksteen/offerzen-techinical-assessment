require "csv"

# Writes one company's assessments as CSV, in batches, to an IO.
#
# Privacy: only the fixed COLUMNS below can leave the system. No email, no
# free text, no raw responses_json. Only the score's candidate keys are read from
# the database (see ScoreReader), so the free-text answers never reach Ruby. Rows also
# pass through Pii::Scrubber as a second guard, and building refuses to start
# if any column is a declared PII attribute.
#
# The score is whatever ScoreReader reads (the same as the dashboard shows), or blank
# when there is no valid score.
class AssessmentCsvExport
  COLUMNS = %w[ assessment_id assessment_date created_at status score employee_id ].freeze
  BATCH_SIZE = 5_000
  # A text cell starting with one of these can be run as a formula by a
  # spreadsheet, so it gets a leading apostrophe.
  FORMULA_PREFIXES = [ "=", "+", "-", "@", "\t", "\r" ].freeze

  def initialize(export_request, batch_size: BATCH_SIZE)
    @export_request = export_request
    @batch_size = batch_size
    self.class.ensure_no_pii!(COLUMNS)
  end

  # Refuses columns that the Assessment model declares as personal data.
  def self.ensure_no_pii!(columns)
    pii_columns = columns.map(&:to_s) & Pii::Registry.attributes_for("Assessment")
    raise "Export columns include personal data: #{pii_columns.join(', ')}" if pii_columns.any?
  end

  # Returns the number of data rows written.
  def write_to(io)
    csv = CSV.new(io)
    csv << COLUMNS
    count = 0
    last_id = 0
    loop do
      rows = batch(last_id)
      break if rows.empty?

      rows.each do |row|
        csv << build_row(row)
        count += 1
      end
      last_id = rows.last.first
    end
    count
  end

  def self.neutralise(value)
    text = value.to_s
    FORMULA_PREFIXES.any? { |prefix| text.start_with?(prefix) } ? "'#{text}" : text
  end

  private

  # One company's rows after last_id, in id order. The company comes from the
  # export request, which came from the signed-in admin.
  def batch(last_id)
    scope = @export_request.company.assessments
                           .matching(date_from: @export_request.date_from, date_to: @export_request.date_to, status: @export_request.status_filter)
                           .where("assessments.id > ?", last_id)
    scope.reorder("assessments.id").limit(@batch_size)
         .pluck(:id, :assessment_date, :created_at, :status, :employee_id, *ScoreReader.candidate_sql.map { |sql| Arel.sql(sql) })
  end

  def build_row(row)
    id, date, created, status, employee_id, *candidates = row
    values = { "assessment_id" => id, "assessment_date" => date&.iso8601, "created_at" => created&.utc&.iso8601,
               "status" => self.class.neutralise(status), "score" => ScoreReader.read(candidates).score, "employee_id" => employee_id }
    safe = Pii::Scrubber.scrub_attributes(Assessment, values)
    COLUMNS.map { |column| safe[column] }
  end
end
