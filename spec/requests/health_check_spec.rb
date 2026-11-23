RSpec.describe "Health check" do
  describe "GET /up" do
    it "returns 200 when the app boots" do
      get rails_health_check_path

      expect(response).to have_http_status(:ok)
    end
  end
end
