# An ApplicationImport::Result for API responses. Errors are capped at MAX_ERRORS
# (errors_count has the full count); raw-mode records are not rendered.
class ImportResultSerializer < ApplicationSerializer
  MAX_ERRORS = 100

  attributes :status, :stats

  attribute(:dry_run, &:dry_run?)
  attribute(:errors_count) { |result| result.errors.size }
  attribute(:errors) { |result| result.errors.first(MAX_ERRORS).map(&:to_h) }
end
