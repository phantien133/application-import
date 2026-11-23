RSpec.describe ErrorHandling, type: :controller do
  let(:json) { response.parsed_body.deep_symbolize_keys }

  controller(ApplicationController) do
    def index
      raise error_to_raise
    end

    private

    def error_to_raise
      self.class.error_to_raise
    end

    class << self
      attr_accessor :error_to_raise
    end
  end

  def request_raising(error)
    controller.class.error_to_raise = error
    get :index
  end

  it "renders ApplicationError subclasses with their code, status and details" do
    request_raising(ForbiddenError.new("no access", details: { role: "guest" }))

    expect(response).to have_http_status(:forbidden)
    expect(json).to eq(error: { code: "forbidden_error", message: "no access", details: { role: "guest" } })
  end

  describe "framework errors (status from Rails rescue_responses, code from class name)" do
    it "maps ActiveRecord::RecordNotFound to 404" do
      request_raising(ActiveRecord::RecordNotFound.new("Couldn't find Job with 'id'=1", "Job"))

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(error: { code: "record_not_found", message: "Couldn't find Job with 'id'=1" })
    end

    it "maps ActiveRecord::RecordInvalid to 422 with validation details" do
      record = ValidatedRecord.invalid
      request_raising(ActiveRecord::RecordInvalid.new(record))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error]).to eq(
        code: "record_invalid",
        message: "Validation failed: Name can't be blank",
        details: { name: [ "can't be blank" ] }
      )
    end

    it "maps ActiveRecord::StaleObjectError to 409" do
      request_raising(ActiveRecord::StaleObjectError.new(ValidatedRecord.new, "update"))

      expect(response).to have_http_status(:conflict)
      expect(json[:error]).to include(code: "stale_object_error", message: /stale object/)
      expect(json[:error]).not_to have_key(:details)
    end

    it "maps ActionController::ParameterMissing to 400" do
      request_raising(ActionController::ParameterMissing.new(:workflow))

      expect(response).to have_http_status(:bad_request)
      expect(json[:error]).to include(code: "parameter_missing", message: /param is missing.*workflow/)
    end

    it "treats unmapped ActiveRecord errors as 500 without leaking SQL" do
      allow(Rails.error).to receive(:report)
      request_raising(ActiveRecord::StatementInvalid.new("PG::UndefinedTable: ERROR: relation \"secrets\" does not exist"))

      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq(error: { code: "unexpected_error", message: "Internal server error" })
    end
  end

  it "hides unexpected errors behind a generic 500 and reports them" do
    error = RuntimeError.new("secret internals")
    allow(Rails.error).to receive(:report)

    request_raising(error)

    expect(response).to have_http_status(:internal_server_error)
    expect(json).to eq(error: { code: "unexpected_error", message: "Internal server error" })
    expect(Rails.error).to have_received(:report).with(error, handled: true)
  end

  describe "handler lookup order" do
    # rescue_from searches bottom-up: StandardError must be declared first or it
    # would swallow every ApplicationError and framework error.
    {
      ForbiddenError.new => :render_application_error,
      ClientError.new => :render_application_error,
      ActiveRecord::RecordNotFound.new => :handle_framework_error,
      ActiveRecord::StatementInvalid.new => :handle_framework_error,
      ActionController::ParameterMissing.new(:id) => :handle_framework_error,
      RuntimeError.new => :handle_unexpected_error
    }.each do |error, handler|
      it "routes #{error.class} to #{handler}" do
        expect(controller.handler_for_rescue(error).name).to eq(handler)
      end
    end
  end

  describe "framework error edge cases" do
    it "maps ActiveRecord::RecordNotSaved to 422 with the record errors" do
      request_raising(ActiveRecord::RecordNotSaved.new("Failed to save the record", ValidatedRecord.invalid))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error]).to eq(
        code: "record_not_saved",
        message: "Failed to save the record",
        details: { name: [ "can't be blank" ] }
      )
    end

    it "resolves the status through ancestors and the code from the subclass name" do
      stub_const("Workflows::DefinitionNotFound", Class.new(ActiveRecord::RecordNotFound))
      request_raising(Workflows::DefinitionNotFound.new("Definition apply not found"))

      expect(response).to have_http_status(:not_found)
      expect(json).to eq(error: { code: "definition_not_found", message: "Definition apply not found" })
    end

    it "honors extra mappings added to config.action_dispatch.rescue_responses" do
      mappings = ActionDispatch::ExceptionWrapper.rescue_responses.merge("ActiveRecord::RecordNotUnique" => :conflict)
      allow(ActionDispatch::ExceptionWrapper).to receive(:rescue_responses).and_return(mappings)
      request_raising(ActiveRecord::RecordNotUnique.new("duplicate"))

      expect(response).to have_http_status(:conflict)
      expect(json[:error]).to eq(code: "record_not_unique", message: "duplicate")
    end
  end

  describe "ApplicationError raised from an action" do
    it "renders the wrapped origin message" do
      request_raising(ClientError.new(origin_error: ArgumentError.new("invalid date"), code: :invalid_date))

      expect(response).to have_http_status(:bad_request)
      expect(json).to eq(error: { code: "invalid_date", message: "invalid date" })
    end
  end

  describe "unexpected errors" do
    it "reports and hides framework errors that Rails maps to 5xx" do
      allow(Rails.error).to receive(:report)
      error = ActiveRecord::ConnectionNotEstablished.new("could not connect to server at 10.0.0.5")
      request_raising(error)

      expect(response).to have_http_status(:internal_server_error)
      expect(json[:error][:message]).to eq("Internal server error")
      expect(Rails.error).to have_received(:report).with(error, handled: true)
    end

    it "re-raises in development to keep the Rails debug page" do
      allow(Rails.env).to receive(:development?).and_return(true)

      expect { request_raising(RuntimeError.new("debug me")) }.to raise_error(RuntimeError, "debug me")
    end

    it "does not re-raise ApplicationError in development" do
      allow(Rails.env).to receive(:development?).and_return(true)
      request_raising(ForbiddenError.new("no access"))

      expect(response).to have_http_status(:forbidden)
    end
  end
end
