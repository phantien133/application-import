RSpec.describe UserSerializer do
  subject(:json) { described_class.new(user).serializable_hash.deep_symbolize_keys }

  let(:user) do
    build_stubbed(:user, balance: BigDecimal("1234.5"), birthday: Date.new(1996, 3, 4), created_on: Date.new(2026, 1, 2),
      last_login_at: Time.utc(2026, 11, 25, 9, 29, 35, 123_456), created_at: Time.utc(2026, 1, 1))
  end

  it "renders exactly the public attributes" do
    expect(json.keys).to eq(%i[ id email name active phone role nickname label created_by_id balance birthday created_on
      last_login_at created_at updated_at ])
  end

  it "renders decimals as strings with 2 decimals" do
    expect(json[:balance]).to eq("1234.50")
  end

  it "renders dates as ISO 8601" do
    expect(json.values_at(:birthday, :created_on)).to eq(%w[ 1996-03-04 2026-01-02 ])
  end

  it "renders times as ISO 8601 UTC with milliseconds" do
    expect(json.values_at(:last_login_at, :created_at)).to eq([ "2026-11-25T09:29:35.123Z", "2026-01-01T00:00:00.000Z" ])
  end

  it "keeps nil values" do
    user.assign_attributes(balance: nil, created_on: nil, updated_at: nil)
    expect(json.values_at(:balance, :created_on, :updated_at)).to all(be_nil)
  end

  it "serializes a collection as an array" do
    expect(described_class.new([ user, user ]).serializable_hash.size).to eq(2)
  end
end
