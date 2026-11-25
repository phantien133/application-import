RSpec.describe BooleanParams, type: :controller do
  controller(ApplicationController) do
    boolean_param :dry_run
    boolean_param :notify, default: true

    def index
      { dry_run:, notify: }
    end
  end

  let(:json) { response.parsed_body.deep_symbolize_keys }

  def values(**params)
    get(:index, params:)
    json[:data]
  end

  it "uses the defaults when absent or blank" do
    expect([ values, values(dry_run: "", notify: " ") ]).to all(eq(dry_run: false, notify: true))
  end

  it "reads true values" do
    expect(%w[ true TRUE 1 yes on ].map { |value| values(dry_run: value)[:dry_run] }).to all(be(true))
  end

  it "reads false values" do
    expect(%w[ false False 0 no off ].map { |value| values(notify: value)[:notify] }).to all(be(false))
  end

  it "rejects other values with 400 invalid_parameter" do
    get :index, params: { dry_run: "maybe" }

    expect(response).to have_http_status(:bad_request)
    expect(json[:error]).to eq(code: "invalid_parameter", message: "dry_run must be true or false", details: { param: "dry_run" })
  end

  it "defines private readers" do
    expect(controller.class.private_method_defined?(:dry_run)).to be(true)
  end
end
