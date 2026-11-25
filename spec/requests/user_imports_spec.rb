# The HTTP side of POST /users/import: params handed to Users::ImportService and how
# its outcome is rendered. What the import does with files is in
# spec/services/users/import_service_spec.rb.
RSpec.describe "User imports" do
  let(:json) { response.parsed_body.deep_symbolize_keys }
  let(:file) { fixture_file_upload("users/valid.csv", "text/csv") }
  let(:result) do
    ApplicationImport::Result.new.tap do |result|
      result.increment(:total, 2).increment(:invalid).increment(:written)
      result.add_row_error(line: 3, column: :email, code: :invalid_format, message: "Email has an invalid format")
    end
  end

  # As rendered: JSON values (symbols become strings).
  def serialized(result)
    JSON.parse(ImportResultSerializer.new(result).serialize, symbolize_names: true)
  end

  before { allow(Users::ImportService).to receive(:call).and_return(result) }

  describe "POST /users/import" do
    it "hands the uploaded file to the service, not a dry run by default" do
      post import_users_path, params: { file: }

      expect(Users::ImportService).to have_received(:call)
        .with(an_instance_of(ActionDispatch::Http::UploadedFile).and(have_attributes(original_filename: "valid.csv")), dry_run: false)
    end

    it "passes dry_run" do
      post import_users_path, params: { file:, dry_run: "true" }

      expect(Users::ImportService).to have_received(:call).with(anything, dry_run: true)
    end

    it "renders the result with 200" do
      post import_users_path, params: { file: }

      expect(response).to have_http_status(:ok)
      expect(json).to eq(data: serialized(result))
    end

    it "renders a failed import as 422 import_failed with the result in details" do
      failed = ApplicationImport::Result.new.halt!.add_file_error(:missing_headers, "missing required headers: Email")
      allow(Users::ImportService).to receive(:call).and_raise(ImportFailedError.new(failed))

      post import_users_path, params: { file: }

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq(error: { code: "import_failed", message: "Import failed", details: serialized(failed) })
    end

    it "renders 400 without a file" do
      post import_users_path

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("parameter_missing")
      expect(Users::ImportService).not_to have_received(:call)
    end

    it "renders 400 for a dry_run that is not a boolean" do
      post import_users_path, params: { file:, dry_run: "maybe" }

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("invalid_parameter")
      expect(Users::ImportService).not_to have_received(:call)
    end
  end
end
