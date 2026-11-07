module DashboardHelper
  SCORE_UNAVAILABLE = "Score not available".freeze

  # The score as the reader (ScoreReader) reads it, or "Score not available". It
  # never raises: if anything goes wrong for one row, only that row is affected, and
  # only the error class and the assessment id are logged, never a value.
  def displayed_score(assessment)
    score = assessment.score_outcome.score
    score.nil? ? SCORE_UNAVAILABLE : score
  rescue StandardError => error
    Rails.logger.error("score display failed assessment=#{assessment.id} error=#{error.class}")
    SCORE_UNAVAILABLE
  end

  # Link to another page, keeping only the date and status filters. No other
  # request parameter is copied into a link.
  def dashboard_page_path(page)
    dashboard_path(request.query_parameters.slice("from", "to", "status").merge("page" => page))
  end
end
