RSpec.describe "Users" do
  let(:json) { response.parsed_body.deep_symbolize_keys }
  let(:valid_params) do
    { user: { email: " New.User@Example.com ", name: "New User", age: 30, role: " Admin " } }
  end

  describe "GET /users" do
    it "lists users in id order with pagination meta" do
      users = create_list(:user, 3)

      get users_path, params: { page: 2, per_page: 2 }

      expect(response).to have_http_status(:ok)
      expect(json[:data].pluck(:id)).to eq([ users.last.id ])
      expect(json[:meta]).to eq(page: 2, per_page: 2, total: 3)
    end

    it "caps per_page" do
      get users_path, params: { per_page: 1000 }

      expect(json[:meta]).to include(page: 1, per_page: UsersController::MAX_PER_PAGE)
    end
  end

  describe "GET /users/:id" do
    it "renders the user" do
      user = create(:user)

      get user_path(user)

      expect(response).to have_http_status(:ok)
      expect(json[:data]).to eq(UserSerializer.new(user).serializable_hash.deep_symbolize_keys)
    end

    it "renders 404 for an unknown id" do
      get user_path(0)

      expect(response).to have_http_status(:not_found)
      expect(json[:error][:code]).to eq("record_not_found")
    end
  end

  describe "POST /users" do
    it "creates a user" do
      expect { post users_path, params: valid_params, as: :json }.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json[:data]).to include(email: "new.user@example.com", name: "New User", role: "admin")
    end

    it "renders 422 with the attribute errors when invalid" do
      expect { post users_path, params: { user: { email: "bad", name: "" } }, as: :json }.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error]).to include(code: "record_invalid")
      expect(json[:error][:details].keys).to include(:email, :name)
    end

    it "renders 400 without user params" do
      post users_path, params: { other: {} }, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("parameter_missing")
    end

    it "ignores attributes that are not permitted" do
      post users_path, params: { user: valid_params[:user].merge(created_by_id: 42) }, as: :json

      expect(User.last.created_by_id).to be_nil
    end
  end

  describe "PATCH /users/:id" do
    it "updates the user" do
      user = create(:user)

      patch user_path(user), params: { user: { name: "Renamed" } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.name).to eq("Renamed")
    end

    it "renders 422 when invalid" do
      user = create(:user)

      patch user_path(user), params: { user: { role: "owner" } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details]).to have_key(:role)
    end
  end

  describe "DELETE /users/:id" do
    it "deletes the user" do
      user = create(:user)

      expect { delete user_path(user) }.to change(User, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "renders 404 for an unknown id" do
      delete user_path(0)

      expect(response).to have_http_status(:not_found)
    end
  end
end
