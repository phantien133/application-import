RSpec.describe ApplicationImport::Readers::Csv do
  subject(:reader) { described_class.new(definition, source, logger: ActiveSupport::Logger.new(nil)) }

  let(:file_config) { {} }
  let(:content) { "Email,Name\na@example.com,Ann\nb@example.com,Bob\n" }
  let(:definition) do
    ApplicationImport::Definition.new(:users, {
      "columns" => { "email" => { "header" => "Email" }, "name" => { "header" => "Name" } }, "file" => file_config
    })
  end
  let(:source) { ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(content.b)) }

  def rows
    reader.map { |row| [ row.line, row.values ] }
  end

  def file_error
    reader.to_a
  rescue ApplicationImport::Errors::FileError => e
    [ e.code, e.message ]
  end

  it "is Enumerable and returns an enumerator without a block" do
    expect([ reader.each, reader.first ]).to match([ an_instance_of(Enumerator), ApplicationImport::Readers::RawRow.new(line: 2, values: [ "a@example.com", "Ann" ]) ])
  end

  it "returns itself after iterating" do
    expect(reader.each { nil }).to be(reader)
  end

  context "with a header row (default)" do
    it "reads the header row and yields data rows with their file line" do
      expect(rows).to eq([ [ 2, [ "a@example.com", "Ann" ] ], [ 3, [ "b@example.com", "Bob" ] ] ])
      expect([ reader.headers?, reader.headers ]).to eq([ true, %w[ Email Name ] ])
    end

    it "knows the headers only after reading" do
      expect(reader.headers).to be_nil
    end

    it "strips header names" do
      reader.send(:content).replace(" Email , Name\nx,y\n")
      reader.to_a

      expect(reader.headers).to eq(%w[ Email Name ])
    end

    context "with leading blank lines" do
      let(:content) { "\n,,\nEmail,Name\na,b\n" }

      it "uses the first non-blank record as header" do
        expect([ rows, reader.headers ]).to eq([ [ [ 4, %w[ a b ] ] ], %w[ Email Name ] ])
      end
    end

    context "with a header row only" do
      let(:content) { "Email,Name\n\n" }

      it "raises empty_file" do
        expect(file_error).to eq([ :empty_file, "file has no data rows" ])
      end
    end
  end

  context "without a header row (headers: false)" do
    let(:file_config) { { "headers" => false } }
    let(:content) { "a@example.com,Ann\nb@example.com,Bob,extra\nc@example.com\n" }

    it "yields every record as data from line 1" do
      expect(rows.map(&:first)).to eq([ 1, 2, 3 ])
    end

    it "exposes the column headers in definition order, mapping cells by position" do
      mapped = reader.map { |row| row.to_h(reader.headers) }

      expect([ reader.headers?, reader.headers ]).to eq([ false, %w[ Email Name ] ])
      expect(mapped).to eq([
        { "Email" => "a@example.com", "Name" => "Ann" },
        { "Email" => "b@example.com", "Name" => "Bob" },
        { "Email" => "c@example.com", "Name" => nil }
      ])
    end

    context "when the file has only blank lines and content" do
      let(:content) { "\n\na,b\n" }

      it "keeps physical line numbers" do
        expect(rows).to eq([ [ 3, %w[ a b ] ] ])
      end
    end
  end

  describe "line numbers" do
    let(:content) { "Email,Note\na,\"multi\nline\nnote\"\n\nb,\"x\"\nc,last" }

    it "reports the first physical line of each record, across quoted newlines and blank lines" do
      expect(rows).to eq([ [ 2, [ "a", "multi\nline\nnote" ] ], [ 6, %w[ b x ] ], [ 7, %w[ c last ] ] ])
    end

    context "with CRLF line endings" do
      let(:content) { "Email,Note\r\na,\"two\r\nlines\"\r\n\r\nb,x\r\n" }

      it "counts lines the same way and strips the row separator" do
        expect(rows).to eq([ [ 2, [ "a", "two\r\nlines" ] ], [ 5, %w[ b x ] ] ])
      end
    end
  end

  describe "blank records" do
    let(:content) { "Email,Name\na,b\n,\n , \n\nc,d\n" }

    it "are skipped" do
      expect(rows).to eq([ [ 2, %w[ a b ] ], [ 6, %w[ c d ] ] ])
    end
  end

  it "keeps empty cells as nil and quoted empty cells as empty strings" do
    reader.send(:content).replace("Email,Name\na,\nb,\"\"\n")

    expect(rows).to eq([ [ 2, [ "a", nil ] ], [ 3, [ "b", "" ] ] ])
  end

  context "with csv options" do
    let(:file_config) { { "csv" => { "col_sep" => ";", "quote_char" => "'", "row_sep" => "|" } } }
    let(:content) { "Email;Name|a;'x;y'|" }

    it "passes them to the parser" do
      expect([ rows, reader.headers ]).to eq([ [ [ 2, [ "a", "x;y" ] ] ], %w[ Email Name ] ])
    end
  end

  context "with the validated options" do
    let(:file_config) { { "csv" => { "strip" => true, "skip_lines" => '\A#', "liberal_parsing" => true } } }
    let(:content) { "# exported 2026-01-01\nEmail , Name\n a , say \"hi\" \n" }

    it "passes them to the parser" do
      expect([ rows, reader.headers ]).to eq([ [ [ 3, [ "a", "say \"hi\"" ] ] ], %w[ Email Name ] ])
    end
  end

  context "with skip_lines" do
    let(:file_config) { { "csv" => { "skip_lines" => '\A#' } } }
    let(:content) { "# header comment\nEmail,Name\n# note\na,b\n\n# end\nc,d\n" }

    it "drops matching lines while keeping physical line numbers" do
      expect([ rows, reader.headers ]).to eq([ [ [ 4, %w[ a b ] ], [ 7, %w[ c d ] ] ], %w[ Email Name ] ])
    end

    it "does not treat a skipped first line as the header" do
      reader.to_a

      expect(reader.headers).to eq(%w[ Email Name ])
    end
  end

  context "with skip_lines given as a passthrough string" do
    let(:file_config) { { "csv" => { "passthrough" => { "skip_lines" => "#" } } } }
    let(:content) { "Email,Name\n#,x\na.b,c\n" }

    it "matches it literally and keeps line numbers" do
      expect(rows).to eq([ [ 3, %w[ a.b c ] ] ])
    end
  end

  context "with max_field_size" do
    let(:file_config) { { "csv" => { "max_field_size" => 3 } } }
    let(:content) { "Email\ntoolong\n" }

    it "rejects longer fields as malformed CSV" do
      expect(file_error.first).to eq(:malformed_csv)
    end
  end

  context "with passthrough options" do
    let(:file_config) { { "csv" => { "col_sep" => ",", "passthrough" => { "col_sep" => ";", "empty_value" => "EMPTY" } } } }
    let(:content) { "Email;Name\na;\"\"\n" }

    it "hands them to CSV.new unvalidated, overriding the validated ones" do
      logger = ActiveSupport::Logger.new(log = StringIO.new)
      logger.level = :debug
      reader = described_class.new(definition, source, logger:)

      expect(reader.map(&:values)).to eq([ [ "a", "EMPTY" ] ])
      expect(log.string).to include("passing unvalidated CSV options: col_sep, empty_value")
    end
  end

  context "with an encoding" do
    let(:file_config) { { "encoding" => "Shift_JIS" } }
    let(:content) { "Email,Name\na,名前\n".encode("Shift_JIS") }

    it "reads through the encoding gate as UTF-8" do
      expect(rows).to eq([ [ 2, [ "a", "名前" ] ] ])
      expect(rows.first.last.last.encoding).to eq(Encoding::UTF_8)
    end
  end

  context "with a UTF-8 BOM" do
    let(:content) { "\xEF\xBB\xBFEmail,Name\na,b\n" }

    it "does not leak the BOM into the first header" do
      reader.to_a

      expect(reader.headers.first).to eq("Email")
    end
  end

  context "with invalid encoding" do
    let(:content) { "Email\n\xFF\n" }

    it "raises before yielding any row" do
      yielded = []

      expect { reader.each { |row| yielded << row } }.to raise_error(ApplicationImport::Errors::FileError) { |e| expect(e.code).to eq(:invalid_encoding) }
      expect(yielded).to eq([])
    end
  end

  context "with malformed CSV" do
    let(:content) { "Email,Name\na,\"unclosed\n" }

    it "raises malformed_csv" do
      expect(file_error).to match([ :malformed_csv, /\Amalformed CSV: / ])
    end
  end

  context "with an empty file" do
    let(:content) { "" }

    it "raises empty_file from the gate" do
      expect(file_error).to eq([ :empty_file, "file is empty" ])
    end
  end

  context "with only blank records" do
    let(:content) { ",\n,,\n" }

    it "raises empty_file for the missing header" do
      expect(file_error).to eq([ :empty_file, "file has no header row" ])
    end
  end

  describe "max_rows" do
    let(:file_config) { { "max_rows" => 2 } }

    it "accepts exactly max_rows data rows, the header not counted" do
      expect(rows.size).to eq(2)
    end

    context "when exceeded" do
      let(:content) { "Email,Name\na,1\nb,2\nc,3\n" }

      it "raises too_many_rows after max_rows rows" do
        yielded = []

        expect { reader.each { |row| yielded << row.line } }.to raise_error(ApplicationImport::Errors::FileError, "file has more than 2 data rows")
        expect(yielded).to eq([ 2, 3 ])
      end
    end
  end

  it "can be iterated again" do
    first = reader.to_a

    expect(reader.to_a).to eq(first)
  end

  describe "sources" do
    it "reads a path-backed source" do
      Tempfile.create([ "users", ".csv" ]) do |file|
        file.write("Email,Name\na,b\n") && file.flush
        reader = described_class.new(definition, ApplicationImport::Source.build(file.path), logger: nil)

        expect(reader.map(&:values)).to eq([ %w[ a b ] ])
      end
    end

    context "with a UTF-16LE file with BOM and CRLF" do
      let(:content) { "\xFF\xFE".b + "Email,Name\r\na,名前\r\n".encode("UTF-16LE").b }

      it "reads it through the gate" do
        expect([ rows, reader.headers ]).to eq([ [ [ 2, [ "a", "名前" ] ] ], %w[ Email Name ] ])
      end
    end
  end

  it "reads the source once across iterations" do
    allow(ApplicationImport::Readers::EncodingGate).to receive(:new).and_call_original
    2.times { reader.to_a }

    expect(ApplicationImport::Readers::EncodingGate).to have_received(:new).once
  end

  it "hands its logger to the encoding gate" do
    log = StringIO.new
    reader = described_class.new(definition, ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("\xFF".b)),
      logger: ActiveSupport::Logger.new(log))

    expect { reader.to_a }.to raise_error(ApplicationImport::Errors::FileError)
    expect(log.string).to include("[ApplicationImport::Readers::EncodingGate:users] rejected")
  end

  context "with tab separated values" do
    let(:file_config) { { "csv" => { "col_sep" => "\t" } } }
    let(:content) { "Email\tName\na,b\tc\n" }

    it "splits on tabs only" do
      expect(rows).to eq([ [ 2, [ "a,b", "c" ] ] ])
    end
  end

  context "with strip given as characters" do
    let(:file_config) { { "csv" => { "strip" => "*" } } }
    let(:content) { "Email,Name\n*a*, b \n" }

    it "strips only those characters" do
      expect(rows).to eq([ [ 2, [ "a", " b " ] ] ])
    end
  end

  context "with a stray quote" do
    let(:content) { "Email,Name\na,say \"hi\"\n" }

    it "is malformed without liberal_parsing" do
      expect(file_error.first).to eq(:malformed_csv)
    end
  end

  context "with skip_lines matching the whole file" do
    let(:file_config) { { "csv" => { "skip_lines" => "." } } }

    it "raises empty_file for the missing header" do
      expect(file_error).to eq([ :empty_file, "file has no header row" ])
    end
  end

  context "without a header row and with quoted line breaks" do
    let(:file_config) { { "headers" => false } }
    let(:content) { "a,\"x\ny\"\nb,z\n" }

    it "keeps physical line numbers from line 1" do
      expect(rows).to eq([ [ 1, [ "a", "x\ny" ] ], [ 3, %w[ b z ] ] ])
    end
  end

  context "with passthrough nil_value" do
    let(:file_config) { { "csv" => { "passthrough" => { "nil_value" => "" } } } }
    let(:content) { "Email,Name\na,\n" }

    it "applies the CSV option" do
      expect(rows).to eq([ [ 2, [ "a", "" ] ] ])
    end
  end

  context "with a file without trailing newline" do
    let(:content) { "Email,Name\na,b" }

    it "reads the last record" do
      expect(rows).to eq([ [ 2, %w[ a b ] ] ])
    end
  end

  it "does not mutate the frozen definition options" do
    reader.to_a

    expect(definition.file[:csv]).to be_frozen
  end
end
