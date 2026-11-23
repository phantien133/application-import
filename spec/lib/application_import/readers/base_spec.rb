RSpec.describe ApplicationImport::Readers::Base do
  let(:records) { [ [ 1, %w[ Email Name ] ], [ 2, [ "a", "b" ] ] ] }
  let(:file_config) { {} }
  let(:reader) do
    list = records
    reader_class = Class.new(described_class) do
      define_method(:each_record) { |&block| list.each { |line, values| block.call(line, values) } }
      private :each_record
    end
    definition = ApplicationImport::Definition.new(:users, {
      "columns" => { "email" => { "header" => "Email" }, "name" => { "header" => "Name" } }, "file" => file_config
    })
    reader_class.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("")), logger: nil)
  end

  it "requires subclasses to implement each_record" do
    definition = ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } })
    base = described_class.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("")))

    expect { base.to_a }.to raise_error(NotImplementedError, "ApplicationImport::Readers::Base#each_record")
  end

  it "turns records into RawRows after the header row" do
    expect([ reader.to_a, reader.headers ]).to eq([ [ ApplicationImport::Readers::RawRow.new(line: 2, values: %w[ a b ]) ], %w[ Email Name ] ])
  end

  context "with non-string cell values (e.g. spreadsheets)" do
    let(:records) { [ [ 1, [ :Email, 1 ] ], [ 2, [ 3, nil ] ], [ 3, [ nil, " " ] ] ] }

    it "stringifies headers, keeps values, skips blank records" do
      expect([ reader.map(&:values), reader.headers ]).to eq([ [ [ 3, nil ] ], %w[ Email 1 ] ])
    end
  end

  context "without a header row" do
    let(:file_config) { { "headers" => false } }

    it "yields every record and maps cells to columns by position" do
      expect(reader.map { |row| row.to_h(reader.headers) })
        .to eq([ { "Email" => "Email", "Name" => "Name" }, { "Email" => "a", "Name" => "b" } ])
    end
  end

  context "with no records" do
    let(:records) { [] }

    it "raises empty_file" do
      expect { reader.to_a }.to raise_error(ApplicationImport::Errors::FileError, "file has no header row")
    end
  end

  describe "#headers?" do
    it "is true by default" do
      expect(reader.headers?).to be(true)
    end

    context "with headers: false" do
      let(:file_config) { { "headers" => false } }

      it "is false and exposes column headers before reading" do
        expect([ reader.headers?, reader.headers ]).to eq([ false, %w[ Email Name ] ])
      end
    end
  end

  describe "#each" do
    it "returns an enumerator without a block" do
      expect(reader.each).to be_an(Enumerator)
    end

    it "returns the reader with a block" do
      expect(reader.each { nil }).to be(reader)
    end

    it "re-reads the header on every iteration" do
      2.times { reader.to_a }

      expect(reader.headers).to eq(%w[ Email Name ])
    end

    it "lets errors raised by each_record through" do
      reader.define_singleton_method(:each_record) { raise ApplicationImport::Errors::FileError.new("boom", code: :malformed_csv) }

      expect { reader.to_a }.to raise_error(ApplicationImport::Errors::FileError, "boom")
    end
  end

  context "with a header row only" do
    let(:records) { [ [ 1, %w[ Email Name ] ], [ 2, [ nil, "" ] ] ] }

    it "raises empty_file for missing data rows" do
      expect { reader.to_a }.to raise_error(ApplicationImport::Errors::FileError, "file has no data rows") { |e| expect(e.code).to eq(:empty_file) }
    end
  end

  context "with headers: false and no records" do
    let(:file_config) { { "headers" => false } }
    let(:records) { [ [ 1, [ nil ] ] ] }

    it "raises empty_file for missing data rows" do
      expect { reader.to_a }.to raise_error(ApplicationImport::Errors::FileError, "file has no data rows")
    end
  end

  context "with nil and padded header cells" do
    let(:records) { [ [ 1, [ " Email ", nil, "Name\t" ] ], [ 2, %w[ a b c ] ] ] }

    it "strips them and turns nil into an empty name" do
      reader.to_a

      expect(reader.headers).to eq([ "Email", "", "Name" ])
    end
  end

  describe "blank records" do
    let(:records) { [ [ 1, %w[ Email ] ], [ 2, [] ], [ 3, [ nil ] ], [ 4, [ " \t" ] ], [ 5, [ "", nil ] ], [ 6, [ 0 ] ], [ 7, [ false ] ] ] }

    it "skips empty, nil and whitespace-only records but keeps falsy non-blank values" do
      expect(reader.map(&:line)).to eq([ 6, 7 ])
    end
  end

  it "exposes definition, source and logger" do
    expect([ reader.definition.name, reader.source.filename, reader.logger ]).to eq([ :users, "u.csv", nil ])
  end

  describe "#on_headers" do
    it "is called with the header row before the first data row and returns the reader" do
      events = []
      expect(reader.on_headers { |headers| events << [ :headers, headers ] }).to be(reader)

      reader.each { |row| events << [ :row, row.line ] }

      expect(events).to eq([ [ :headers, %w[ Email Name ] ], [ :row, 2 ] ])
    end

    context "with a header row only" do
      let(:records) { [ [ 1, %w[ Email Name ] ] ] }

      it "is called before empty_file is raised" do
        seen = nil
        reader.on_headers { |headers| seen = headers }

        expect { reader.to_a }.to raise_error(ApplicationImport::Errors::FileError, "file has no data rows")
        expect(seen).to eq(%w[ Email Name ])
      end
    end

    context "without a header row" do
      let(:file_config) { { "headers" => false } }

      it "is called first with the column headers" do
        events = []
        reader.on_headers { |headers| events << headers }.each { |row| events << row.line }

        expect(events).to eq([ %w[ Email Name ], 1, 2 ])
      end
    end
  end

  describe "#open / #close" do
    it "are no-ops returning the reader by default" do
      expect([ reader.open, reader.close ]).to eq([ reader, reader ])
    end

    it "do not affect reading" do
      reader.open
      rows = reader.to_a
      reader.close

      expect(rows.map(&:line)).to eq([ 2 ])
    end
  end
end
