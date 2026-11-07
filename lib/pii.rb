# Shared PII scrubbing: a registry of declared PII attributes, a scrubber that
# redacts their values (and email addresses) from text, and a log formatter
# that applies it to every log line.
#
# This is plain Ruby required from config/application.rb (not autoloaded),
# because the logger is built before Rails autoloading is available. It is
# excluded from autoload_lib there.
#
# How it is used:
#   * Models declare PII attributes once with `pii_attributes` (see the
#     PiiAttributes concern). That declaration feeds the request parameter
#     filter, `inspect` output and this scrubber.
#   * The log formatter scrubs every line, including error logs.
#   * The export calls Pii::Scrubber.scrub_attributes as a second guard behind
#     its column allow-list.
#
# The scrubber is a BACKSTOP. The primary protection is not logging data
# (job arguments are ids only, bulk SQL is not logged). Known limits: values
# in positional bulk INSERT SQL cannot be matched by attribute name (only
# email addresses are caught there); as_json, pluck and rendered HTML are not
# scrubbed.
require_relative "pii/registry"
require_relative "pii/scrubber"
require_relative "pii/log_formatter"
