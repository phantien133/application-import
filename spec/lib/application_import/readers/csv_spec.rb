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

    context "with padded header names" do
      let(:content) { " Email , Name\nx,y\n" }

      it "strips them" do
        reader.to_a

        expect(reader.headers).to eq(%w[ Email Name ])
      end
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

      it "counts lines the same way, turning line breaks into LF" do
        expect(rows).to eq([ [ 2, [ "a", "two\nlines" ] ], [ 5, %w[ b x ] ] ])
      end
    end

    context "with mixed LF, CRLF and CR line endings" do
      let(:content) { "Email,Note\na,1\r\nb,\"x\r\ny\"\rc,3\n\r\nd,4" }

      it "parses every record with its physical line" do
        expect(rows).to eq([ [ 2, %w[ a 1 ] ], [ 3, [ "b", "x\ny" ] ], [ 5, %w[ c 3 ] ], [ 7, %w[ d 4 ] ] ])
      end
    end

    context "with mixed line endings and an explicit row_sep" do
      let(:file_config) { { "csv" => { "row_sep" => "\r\n" } } }
      let(:content) { "Email,Note\r\na,\"x\ny\"\r\nb,2\r\n" }

      it "does not normalize, keeping LF inside values" do
        expect(rows.map(&:last)).to eq([ [ "a", "x\ny" ], %w[ b 2 ] ])
      end
    end

    context "with row_sep given through passthrough" do
      let(:file_config) { { "csv" => { "passthrough" => { "row_sep" => "\r\n" } } } }
      let(:content) { "Email\r\na\r\n" }

      it "does not normalize either" do
        expect(rows.map(&:last)).to eq([ [ "a" ] ])
      end
    end
  end

  describe "blank records" do
    let(:content) { "Email,Name\na,b\n,\n , \n\nc,d\n" }

    it "are skipped" do
      expect(rows).to eq([ [ 2, %w[ a b ] ], [ 6, %w[ c d ] ] ])
    end
  end

  context "with empty cells" do
    let(:content) { "Email,Name\na,\nb,\"\"\n" }

    it "keeps unquoted ones as nil and quoted ones as empty strings" do
      expect(rows).to eq([ [ 2, [ "a", nil ] ], [ 3, [ "b", "" ] ] ])
    end
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

  context "with skip_lines given through passthrough" do
    it "is rejected: the reader manages skipped lines itself" do
      expect { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "file" => { "csv" => { "passthrough" => { "skip_lines" => "#" } } } }) }
        .to raise_error(ApplicationImport::Errors::ConfigError, /file.csv.passthrough has options the reader manages: skip_lines/)
    end
  end

  context "with max_field_size" do
    let(:file_config) { { "csv" => { "max_field_size" => 3 } } }
    let(:content) { "Email\ntoolong\n" }

    it "rejects longer fields as field_too_large" do
      expect(file_error.first).to eq(:field_too_large)
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

  describe "streaming" do
    it "streams the source through the gate on every iteration and parses from its tempfile" do
      paths = []
      allow(::CSV).to receive(:new).and_wrap_original { |original, io, **options| (paths << io.path) && original.call(io, **options) }

      2.times { reader.to_a }

      expect(paths.size).to eq(2)
      expect(paths).to all(satisfy { |path| !File.exist?(path) })
    end

    it "removes the tempfile when the consumer stops early" do
      path = nil
      allow(::CSV).to receive(:new).and_wrap_original { |original, io, **options| (path = io.path) && original.call(io, **options) }

      expect(reader.first.line).to eq(2)
      expect(File.exist?(path)).to be(false)
    end

    context "with a big file" do
      let(:content) { "Email,Name\n" + ("a@example.com,Ann\n" * 30_000) }

      it "yields every row with its line" do
        lines = reader.map(&:line)

        expect([ lines.size, lines.first, lines.last ]).to eq([ 30_000, 2, 30_001 ])
      end
    end
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

  context "with comment lines holding quotes" do
    let(:file_config) { { "csv" => { "skip_lines" => '\A#' } } }
    let(:content) { "# don't \"quote\nEmail,Name\na,b\n" }

    it "skips them before the parser (no malformed_csv)" do
      expect([ rows, reader.headers ]).to eq([ [ [ 3, %w[ a b ] ] ], %w[ Email Name ] ])
    end
  end

  context "with skip_lines matching inside a quoted value" do
    let(:file_config) { { "csv" => { "skip_lines" => "^#" } } }
    let(:content) { "Email,Note\na,\"first\n# kept\"\n# dropped\nb,c\n" }

    it "keeps the value and still reports physical lines" do
      expect(rows).to eq([ [ 2, [ "a", "first\n# kept" ] ], [ 5, %w[ b c ] ] ])
    end
  end

  context "with skip_lines matching the whole file" do
    let(:file_config) { { "csv" => { "skip_lines" => "." } } }

    it "raises empty_file (every line blanked)" do
      expect(file_error).to eq([ :empty_file, "file is empty" ])
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

  describe "#open / #close" do
    it "keep nothing open: files are opened and closed within each" do
      expect([ reader.open, reader.close ]).to eq([ reader, reader ])
      expect(rows).to eq([ [ 2, [ "a@example.com", "Ann" ] ], [ 3, [ "b@example.com", "Bob" ] ] ])
    end
  end
end
