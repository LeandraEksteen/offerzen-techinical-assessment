# Signs in as an admin and requests dashboard pages in-process (a Rails
# integration session, so the full stack runs), measuring each request. Used by
# the benchmark and snapshot tasks. It never prints emails or the password.
class DashboardProbe
  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36".freeze
  Result = Struct.new(:status, :queries, :cache_hits, :ms, :bytes, :rows, keyword_init: true)
  SNAPSHOT_ROWS = 50

  def initialize(email:, password:)
    @session = ActionDispatch::Integration::Session.new(Rails.application)
    @session.host! "localhost"
    sign_in(email, password)
  end

  # Requests the page and returns how long it took, how many SQL queries ran,
  # how many repeated lookups Rails' per-request query cache answered instead,
  # how large the HTML was and how many table rows it holds.
  def measure(path)
    queries = 0
    cache_hits = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if %w[ SCHEMA TRANSACTION ].include?(payload[:name])

      payload[:cached] ? cache_hits += 1 : queries += 1
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    get(path)
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    body = @session.response.body
    Result.new(status: @session.response.status, queries: queries, cache_hits: cache_hits, ms: ms, bytes: body.bytesize, rows: [ body.scan("<tr>").size - 1, 0 ].max)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  # The first rows of the page as plain lines: employee id, date, status, score
  # and a short hash of the email (so no email ever reaches a committed file).
  # Page one, whatever the page size, so later tickets can compare against it.
  def snapshot(path, limit: SNAPSHOT_ROWS)
    get(path)
    head = @session.response.body[0, 400_000]
    Nokogiri::HTML(head).css("tbody tr").first(limit).map do |row|
      email, employee_id, date, status, score = row.css("td").map(&:text)
      [ employee_id, date, status.inspect, score.inspect, Digest::SHA256.hexdigest(email.to_s)[0, 8] ].join(" | ")
    end
  end

  private

  def get(path)
    @session.get(path, headers: { "User-Agent" => USER_AGENT })
  end

  def sign_in(email, password)
    get("/session/new")
    token = Nokogiri::HTML(@session.response.body).at_css("input[name=authenticity_token]")&.[]("value")
    @session.post("/session", params: { authenticity_token: token, email: email, password: password }, headers: { "User-Agent" => USER_AGENT })
    raise "Sign-in failed for the benchmark admin" unless @session.response.redirect?
  end
end
