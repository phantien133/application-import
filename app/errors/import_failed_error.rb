# An import that failed (file error, too many row errors): 422 import_failed with the
# serialized result (status, stats, errors) in details.
class ImportFailedError < UnprocessableError
  attr_reader :result

  def initialize(result, message = "Import failed")
    @result = result
    super(message, code: :import_failed, details: ImportResultSerializer.new(result).serializable_hash)
  end
end
