# POST /users/import (multipart): imports a users CSV (Users::ImportService), synchronously.
#   file     the CSV (required; missing -> 400 parameter_missing)
#   dry_run  true: run every check, write nothing
# completed / completed_with_errors -> 200 with the result (skipped rows in errors);
# failed (file error, too many errors) -> 422 import_failed, the result in details.
class UserImportsController < ApplicationController
  serialize_with ImportResultSerializer
  boolean_param :dry_run

  def create
    with_meta(Users::ImportService.call(params.require(:file), dry_run:), status: :ok)
  end
end
