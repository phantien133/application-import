RSpec.describe ApiResponse, type: :controller do
  controller(ApplicationController) do
    def index
      render_success([ { id: 1 } ], meta: { page: 1 })
    end

    def show
      render_success
    end

    def create
      render_success({ id: 2 }, status: :created)
    end

    def destroy
      render_error(code: :gone, message: "Already removed", status: :gone)
    end
  end

  let(:json) { response.parsed_body.deep_symbolize_keys }

  it "wraps data and meta" do
    get :index

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(json).to eq(data: [ { id: 1 } ], meta: { page: 1 })
  end

  it "always includes data and omits meta when not given" do
    get :show, params: { id: 1 }

    expect(json).to eq(data: nil)
  end

  it "uses the given status" do
    post :create

    expect(response).to have_http_status(:created)
    expect(json).to eq(data: { id: 2 })
  end

  it "renders errors without details when none are given" do
    delete :destroy, params: { id: 1 }

    expect(response).to have_http_status(:gone)
    expect(json).to eq(error: { code: "gone", message: "Already removed" })
  end
end
