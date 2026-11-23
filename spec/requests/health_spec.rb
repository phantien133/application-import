RSpec.describe "Health" do
  describe "GET /health" do
    it "renders the ApiResponse success envelope" do
      freeze_time do
        get health_path

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
        expect(response.parsed_body).to eq(
          "data" => { "status" => "ok" },
          "meta" => { "time" => Time.current.iso8601 }
        )
      end
    end
  end
end
