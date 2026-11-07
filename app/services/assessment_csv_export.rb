require "csv"

# Writes one company's assessments as CSV, in batches, to an IO.
#
# Privacy: only the fixed COLUMNS below can leave the system. No email, no
# free text, no raw responses_json. The score is read INSIDE the database and
# only if it is a JSON number, so score free text never reaches Ruby. Rows also
# pass through Pii::Scrubber as a second guard, and building refuses to start
# if any column is a declared PII attribute.
#
# Until the score contract (a later ticket) replaces it, only a top-level
# numeric "score" is exported; anything else is blank.
class AssessmentCsvExport
  COLUMNS = %w[ assessment_id assessment_date created_at status score employee_id ].freeze
  BATCH_SIZE = 5_000
  # A text cell starting with one of these can be run as a formula by a
  # spreadsheet, so it gets a leading apostrophe.
  FORMULA_PREFIXES = [ "=", "+", "-", "@", "\t", "\r" ].freeze
  SCORE_SQL = "CASE WHEN jsonb_typeof(responses_json->'score') = 'number' " \
              "THEN (responses_json->'score')::text END".freeze

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
    scope = @export_request.company.assessments.where("assessments.id > ?", last_id)
    scope = scope.where("assessments.assessment_date >= ?", @export_request.date_from) if @export_request.date_from
    scope = scope.where("assessments.assessment_date <= ?", @export_request.date_to) if @export_request.date_to
    scope = scope.where(*Array(StatusOptions.condition(@export_request.status_filter))) if @export_request.status_filter
    scope.reorder("assessments.id").limit(@batch_size)
         .pluck(:id, :assessment_date, :created_at, :status, Arel.sql(SCORE_SQL), :employee_id)
  end

  def build_row(row)
    id, date, created, status, score, employee_id = row
    values = { "assessment_id" => id, "assessment_date" => date&.iso8601, "created_at" => created&.utc&.iso8601,
               "status" => self.class.neutralise(status), "score" => score, "employee_id" => employee_id }
    safe = Pii::Scrubber.scrub_attributes(Assessment, values)
    COLUMNS.map { |column| safe[column] }
  end
end
