RSpec.describe ApplicationImport::ErrorPolicy do
  it "aborts every code by default" do
    policy = described_class.new

    expect([ policy.default, policy.allow, policy.skip, policy.action_for(:required) ]).to eq([ :abort, [], [], :abort ])
  end

  it "stops a row at its first error by default, collects all with row_errors: :all" do
    expect([ described_class.new.row_errors, described_class.new.collect_all?, described_class.new(row_errors: :all).collect_all? ])
      .to eq([ :first, false, true ])
  end

  it "accepts String codes" do
    expect(described_class.new(allow: %i[ duplicate ]).action_for("duplicate")).to eq(:allow)
  end

  it "maps listed codes to allow or skip and others to the default" do
    policy = described_class.new(default: :skip, allow: %i[ duplicate ], skip: %i[ required ])

    expect(%i[ duplicate required invalid_type ].map { |code| policy.action_for(code) }).to eq(%i[ allow skip skip ])
  end
end
