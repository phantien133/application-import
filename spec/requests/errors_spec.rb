RSpec.describe "Errors raised outside controller actions" do
  # Test env shows detailed (debug) exceptions; production does not, and that
  # is the path config.exceptions_app (ErrorsController) serves.
  around do |example|
    env_config = Rails.application.env_config
    original = env_config["action_dispatch.show_detailed_exceptions"]
    env_config["action_dispatch.show_detailed_exceptions"] = false
    example.run
  ensure
    env_config["action_dispatch.show_detailed_exceptions"] = original
  end

  let(:json) { response.parsed_body.deep_symbolize_keys }

  it "renders an unknown route as a 404 error envelope" do
    get "/does-not-exist"

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/json")
    expect(json).to eq(error: { code: "routing_error", message: 'No route matches [GET] "/does-not-exist"' })
  end

  it "renders a malformed request body (ParseError, mapped to 400) as an error envelope" do
    env = Rack::MockRequest.env_for("/400")
    env["action_dispatch.exception"] = ActionDispatch::Http::Parameters::ParseError.new("unexpected token at '{not json'")

    status, _headers, body = Rails.application.config.exceptions_app.call(env)

    expect(status).to eq(400)
    expect(JSON.parse(body.each.to_a.join, symbolize_names: true))
      .to eq(error: { code: "parse_error", message: "unexpected token at '{not json'" })
  end

  it "hides the message of server errors" do
    env = Rack::MockRequest.env_for("/500")
    env["action_dispatch.exception"] = RuntimeError.new("secret internals")

    status, _headers, body = Rails.application.config.exceptions_app.call(env)

    expect(status).to eq(500)
    expect(JSON.parse(body.each.to_a.join, symbolize_names: true))
      .to eq(error: { code: "unexpected_error", message: "Internal server error" })
  end
end
