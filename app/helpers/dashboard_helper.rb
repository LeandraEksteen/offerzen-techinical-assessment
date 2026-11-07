module DashboardHelper
  # BASELINE, deliberately naive: the top-level "score" exactly as stored when the
  # JSON is an object, blank otherwise. So "85%", 0.85 or 150 show as they are
  # and a missing score is blank. The score reader that replaces this is a later
  # ticket (TKT-8); it must be the only change to what this column shows.
  def stored_score(assessment)
    json = assessment.responses_json
    json["score"] if json.is_a?(Hash)
  end
end
