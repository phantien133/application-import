RSpec.describe "Health" do
  describe "GET /health" do
    let(:json) { response.parsed_body.deep_symbolize_keys }

    it "renders 200 with each check when the dependencies are up" do
      freeze_time do
        get health_path

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
        expect(json[:data][:status]).to eq("ok")
        expect(json[:data][:checks].transform_values { |check| check[:status] }).to eq(database: "ok", redis: "skipped")
        expect(json[:meta]).to eq(time: Time.current.iso8601)
      end
    end

    it "renders 503 with the failing check when a dependency is down" do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(ActiveRecord::ConnectionNotEstablished, "db host down")

      get health_path

      expect(response).to have_http_status(:service_unavailable)
      expect(json[:error]).to include(code: "service_unavailable", message: "Some dependencies are unavailable")
      expect(json[:error][:details][:checks][:database]).to include(status: "error", error: "ActiveRecord::ConnectionNotEstablished")
      expect(response.body).not_to include("db host down")
    end
  end
end
