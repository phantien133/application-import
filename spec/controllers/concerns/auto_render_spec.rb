RSpec.describe AutoRender, type: :controller do
  controller(ApplicationController) do
    def index
      with_meta(User.order(:id), page: 1)
    end

    def show
      (params[:id] == "plain") ? { id: 1, name: "plain" } : User.find(params[:id])
    end

    def create
      { id: 2 }
    end

    def update
      render json: { custom: true }, status: :accepted
    end

    def destroy
      nil
    end
  end

  let(:json) { response.parsed_body.deep_symbolize_keys }
  let(:user) { create(:user) }

  it "serializes a record with its inferred serializer" do
    get :show, params: { id: user.id }

    expect(response).to have_http_status(:ok)
    expect(json).to eq(data: UserSerializer.new(user).serializable_hash.deep_symbolize_keys)
  end

  it "serializes a relation with the serializer of its model, and renders meta" do
    user

    get :index

    expect(json).to eq(data: UserSerializer.new([ user ]).serializable_hash.map(&:deep_symbolize_keys), meta: { page: 1 })
  end

  it "renders values without a serializer as they are" do
    get :show, params: { id: "plain" }

    expect(json).to eq(data: { id: 1, name: "plain" })
  end

  it "answers create with 201" do
    post :create

    expect(response).to have_http_status(:created)
    expect(json).to eq(data: { id: 2 })
  end

  it "answers nil with 204 and no body" do
    delete :destroy, params: { id: 1 }

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
  end

  it "leaves an action that renders itself alone" do
    patch :update, params: { id: 1 }

    expect(response).to have_http_status(:accepted)
    expect(json).to eq(custom: true)
  end

  it "renders raised errors through ErrorHandling" do
    get :show, params: { id: 0 }

    expect(response).to have_http_status(:not_found)
    expect(json[:error][:code]).to eq("record_not_found")
  end

  context "with serialize_with" do
    controller(ApplicationController) do
      serialize_with(Class.new(ApplicationSerializer) { attributes :email })

      def show
        User.find(params[:id])
      end
    end

    it "uses the declared serializer" do
      get :show, params: { id: user.id }

      expect(json).to eq(data: { email: user.email })
    end
  end
end
