# Imports users from a CSV with ApplicationImport (config/imports/users.yml).
#
#   Users::ImportService.call(file, dry_run: false, context: {}) # => ApplicationImport::Result
#
# file: an uploaded file, a path or a seekable IO (see ApplicationImport::Source).
# Returns the result when the import completed (with or without skipped rows); raises
# ImportFailedError (422, the result in details) when it failed: a file error or too
# many row errors. Nothing is written by a failed import.
module Users
  class ImportService < ApplicationService
    DEFINITION = :users

    def initialize(file, dry_run: false, context: {})
      super()
      @file = file
      @dry_run = dry_run
      @context = context
    end

    def call
      result = ApplicationImport.run(DEFINITION, @file, context: @context, dry_run: @dry_run)
      info("#{DEFINITION} import #{result.status}#{" (dry run)" if result.dry_run?}: #{result.stats}")
      raise ImportFailedError.new(result) if result.failed?

      result
    end
  end
end
