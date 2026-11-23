RSpec.describe ApplicationImport::HeaderMap do
  it "maps cells by index with every column key present" do
    map = described_class.new(column_keys: %i[ email name ], indexes: { 1 => :email, 2 => "Note" }, width: 3)

    expect(map.attributes([ "x", "a@x.io", "hi" ])).to eq(:email => "a@x.io", :name => nil, "Note" => "hi")
  end

  describe "#extra_cells" do
    let(:map) { described_class.new(column_keys: %i[ email ], indexes: { 0 => :email }, width: 2) }

    it "returns non-blank cells beyond the width as [ index, value ]" do
      expect(map.extra_cells([ "a", "b", "c", nil, " ", "d" ])).to eq([ [ 2, "c" ], [ 5, "d" ] ])
    end

    it "is empty when the row fits, or only blank cells overflow" do
      expect([ map.extra_cells(%w[ a b ]), map.extra_cells([ "a" ]), map.extra_cells([ "a", "b", nil, "" ]) ]).to all(eq([]))
    end

    it "is empty without width (every cell kept)" do
      keep = described_class.new(column_keys: %i[ email ], indexes: { 0 => :email }, keep_extra_from: 1)

      expect([ keep.extra_cells(%w[ a b c ]), keep.attributes(%w[ a b c ]) ]).to eq([ [], { :email => "a", "column_2" => "b", "column_3" => "c" } ])
    end
  end
end
