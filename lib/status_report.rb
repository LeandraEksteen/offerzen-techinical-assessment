# Read-only report of the statuses assessments hold today, to build the sheet assessors
# check before any historical backfill (a PLAN, see assessment-log/solution-drafts/
# status-backfill.md). It reads in id batches and never writes.
#
#   bin/rails statuses:report
#
# One row per distinct status value AS STORED ("Complete " and "complete" are two rows;
# NULL, empty and blank-only are labelled, not hidden), with how many rows hold it and
# the latest updated_at. When db/status_mapping.yml exists, each row also shows where the
# mapping would send it, and a summary counts rows per canonical status and the unmapped
# remainder.
#
# Privacy: a status column is free text, so a value could be anything. Emails are
# scrubbed, and a value that looks like free text (long, or several words) is shown
# only as "[text, N characters]" and flagged for a human to look at. No ids, no rows,
# no employee data. Share the sheet only after that review.
class StatusReport
  BATCH = 10_000
  MAX_VALUE_LENGTH = 40
  MAX_WORDS = 4

  def initialize(output: $stdout, batch: BATCH, mapping: StatusMapping.load)
    @output = output
    @batch = batch
    @mapping = mapping
  end

  def call
    counts = Hash.new(0)
    latest = {}
    each_row do |status, updated_at|
      counts[status] += 1
      latest[status] = updated_at if latest[status].nil? || updated_at > latest[status]
    end
    print_report(counts, latest)
  end

  private

  def each_row
    last_id = 0
    loop do
      rows = Assessment.where("id > ?", last_id).order(:id).limit(@batch).pluck(:id, :status, :updated_at)
      break if rows.empty?

      rows.each { |_id, status, updated_at| yield status, updated_at }
      last_id = rows.last.first
    end
  end

  def print_report(counts, latest)
    total = counts.values.sum
    @output.puts "Status report: #{total} assessments, #{counts.size} distinct stored values (read only; nothing is written)"
    @output.puts
    @output.puts "Rows | Latest updated_at | Stored value | Maps to | Review"
    sorted(counts).each do |status|
      text, review = display(status)
      @output.puts [ counts[status], latest[status].utc.strftime("%Y-%m-%d %H:%M"), text, target_label(status), review ].join(" | ")
    end
    print_mapping_summary(counts) if @mapping
  end

  # Most rows first; ties by the value as stored so the output is stable.
  def sorted(counts)
    counts.keys.sort_by { |status| [ -counts[status], status.to_s ] }
  end

  # [what to print, review flag]
  def display(status)
    return [ "(NULL)", "" ] if status.nil?
    return [ "(empty)", "" ] if status.empty?
    return [ "(blank only, #{status.length} #{"character".pluralize(status.length)})", "" ] if status.strip.empty?
    return [ "[text, #{status.length} characters]", "REVIEW: looks like free text" ] if free_text?(status)

    [ Pii::Scrubber.scrub_text(status).inspect, "" ]
  end

  def free_text?(status)
    status.length > MAX_VALUE_LENGTH || status.split.size > MAX_WORDS
  end

  def target_label(status)
    return "-" unless @mapping

    @mapping.target_for(status) || "(unmapped)"
  end

  def print_mapping_summary(counts)
    state = @mapping.draft? ? "DRAFT, not approved" : "approved by #{@mapping.approved_by} on #{@mapping.approved_on}"
    @output.puts
    @output.puts "Mapping: db/status_mapping.yml version #{@mapping.version} (#{state})"
    mapped = Hash.new(0)
    unmapped_values = 0
    unmapped_rows = 0
    counts.each do |status, count|
      target = @mapping.target_for(status)
      if target
        mapped[target] += count
      else
        unmapped_values += 1
        unmapped_rows += count
      end
    end
    Assessment::STATUSES.each { |status| @output.puts format("  %-18s %9d rows", status, mapped[status]) }
    @output.puts format("  %-18s %9d rows in %d distinct values (these stay NULL and block the switch)", "unmapped", unmapped_rows, unmapped_values)
  end
end
