RSpec.describe ApplicationImport::Readers::EncodingGate do
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:definition) do
    file = encoding ? { "encoding" => encoding } : {}
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "file" => file })
  end

  def encoding
    nil
  end

  def gate(**options)
    described_class.new(definition, logger:, **options)
  end

  # Content, source encoding and BOM flag of the gated text.
  def read(bytes, **options)
    source = ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(bytes.b))
    gate(**options).call(source) { |text| [ text.io.read, text.encoding, text.bom ] }
  end

  def rejection(bytes, **options)
    read(bytes, **options)
  rescue ApplicationImport::Errors::FileError => e
    [ e.code, e.message ]
  end

  describe "#call" do
    it "yields a rewound UTF-8 tempfile and returns the block value" do
      source = ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("email\n"))
      seen = nil

      value = gate.call(source) do |text|
        seen = text
        [ text.io.pos, text.io.external_encoding, text.io.read, text.io.path ]
      end

      expect(value.first(3)).to eq([ 0, Encoding::UTF_8, "email\n" ])
      expect(seen).to be_frozen
      expect(File.exist?(value.last)).to be(false)
    end

    it "removes the tempfile when the block raises" do
      path = nil
      source = ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("email\n"))

      expect { gate.call(source) { |text| (path = text.io.path) && raise("boom") } }.to raise_error("boom")
      expect(File.exist?(path)).to be(false)
    end

    it "does not yield when the content is rejected" do
      source = ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("\xFF".b))
      yielded = false

      expect { gate.call(source) { yielded = true } }.to raise_error(ApplicationImport::Errors::FileError)
      expect(yielded).to be(false)
    end

    it "reads a path-backed source" do
      Tempfile.create([ "u", ".csv" ]) do |file|
        file.binmode.write("\xEF\xBB\xBFemail\n") && file.flush

        expect(gate.call(ApplicationImport::Source.build(file.path)) { |text| text.io.read }).to eq("email\n")
      end
    end
  end

  context "with the default UTF-8 encoding" do
    it "returns UTF-8 content unchanged" do
      expect(read("email\nnguyễn@example.com\n")).to eq([ "email\nnguyễn@example.com\n", Encoding::UTF_8, false ])
    end

    it "strips a UTF-8 BOM" do
      expect(read("\xEF\xBB\xBFemail\n")).to eq([ "email\n", Encoding::UTF_8, true ])
    end

    it "accepts 4-byte characters" do
      expect(read("😀@example.com\n").first).to eq("😀@example.com\n")
    end

    it "rejects invalid UTF-8 and points at the first bad line" do
      expect(rejection("email\nok\nbad\xFF\n")).to eq([
        :invalid_encoding, "file is not valid UTF-8 (first invalid byte on line 3) [encoding: UTF-8]"
      ])
    end

    it "rejects a truncated sequence at the end of the file" do
      expect(rejection("ok\n\xE2\x82")).to eq([ :invalid_encoding, "file is not valid UTF-8 (first invalid byte on line 2) [encoding: UTF-8]" ])
    end

    it "rejects a Shift_JIS file read as UTF-8" do
      expect(rejection("名前\n".encode("Shift_JIS")).first).to eq(:invalid_encoding)
    end

    it "rejects NUL bytes (UTF-16 without BOM)" do
      expect(rejection("email\n".encode("UTF-16LE"))).to eq([
        :invalid_encoding, "file contains NUL bytes (UTF-16 without BOM or a binary file?) [encoding: UTF-8]"
      ])
    end

    it "logs every rejection as a warning with the import name" do
      rejection("bad\xFF")

      expect(log.string).to start_with("WARN [ApplicationImport::Readers::EncodingGate:users] rejected: file is not valid UTF-8")
    end
  end

  context "with Shift_JIS" do
    def encoding
      "Shift_JIS"
    end

    it "transcodes to UTF-8" do
      expect(read("名前,年齢\n".encode("Shift_JIS"))).to eq([ "名前,年齢\n", Encoding::Shift_JIS, false ])
    end

    it "rejects bytes that are invalid in that encoding, with the line" do
      expect(rejection("a\n\x82\n")).to eq([
        :invalid_encoding, "file is not valid Shift_JIS (first invalid byte on line 2) [encoding: Shift_JIS]"
      ])
    end

    it "rejects a character cut at the end of the file" do
      expect(rejection("a\n\x96".b).first).to eq(:invalid_encoding)
    end

    it "rejects NUL bytes" do
      expect(rejection("a\x00b\n").last).to eq("file contains NUL bytes (UTF-16 without BOM or a binary file?) [encoding: Shift_JIS]")
    end
  end

  context "with Windows-1252" do
    def encoding
      "Windows-1252"
    end

    it "transcodes accented characters" do
      expect(read("caf\xE9\n").first).to eq("café\n")
    end

    it "rejects bytes with no UTF-8 mapping" do
      expect(rejection("ok\na\x81\n")).to eq([
        :invalid_encoding, "file cannot be converted from Windows-1252 to UTF-8 (first invalid byte on line 2) [encoding: Windows-1252]"
      ])
    end
  end

  context "with ISO-8859-1" do
    def encoding
      "ISO-8859-1"
    end

    it "maps every byte" do
      expect(read("\xC0\xFF\n").first).to eq("Àÿ\n")
    end
  end

  context "with a BOM" do
    it "reads UTF-16LE and warns that the configured encoding is ignored" do
      expect(read("\xFF\xFE".b + "email\n名前\n".encode("UTF-16LE").b)).to eq([ "email\n名前\n", Encoding::UTF_16LE, true ])
      expect(log.string).to include("WARN", "file has a UTF-16LE BOM, ignoring the configured encoding UTF-8")
    end

    it "reads UTF-16BE" do
      expect(read("\xFE\xFF".b + "email\n".encode("UTF-16BE").b).first).to eq("email\n")
    end

    it "does not warn when the BOM matches the configured encoding" do
      read("\xEF\xBB\xBFemail\n")

      expect(log.string).to eq("")
    end

    it "rejects an invalid UTF-16 body with the line" do
      bytes = "\xFF\xFE".b + "a\n".encode("UTF-16LE").b + "\x00\xD8\x41\x00".b

      expect(rejection(bytes)).to eq([ :invalid_encoding, "file is not valid UTF-16LE (first invalid byte on line 2) [encoding: UTF-16LE]" ])
    end

    it "rejects a truncated UTF-16 body" do
      expect(rejection("\xFF\xFE".b + "ab".encode("UTF-16LE").b + "\x00".b).first).to eq(:invalid_encoding)
    end

    context "when another encoding is configured" do
      def encoding
        "Shift_JIS"
      end

      it "reads as the BOM says and warns" do
        expect(read("\xEF\xBB\xBF名前\n").first(2)).to eq([ "名前\n", Encoding::UTF_8 ])
        expect(log.string).to include("file has a UTF-8 BOM, ignoring the configured encoding Shift_JIS")
      end
    end
  end

  context "with a dummy encoding and no BOM" do
    %w[ UTF-16 UTF-32 ].each do |name|
      it "asks for a BOM for #{name}" do
        allow(self).to receive(:encoding).and_return(name)

        expect(rejection("e\x00".b)).to eq([ :invalid_encoding, "#{name} needs a BOM to be read [encoding: #{name}]" ])
      end
    end
  end

  describe "empty content" do
    [ "", "\xEF\xBB\xBF", " \n\r\n\t" ].each do |bytes|
      it "rejects #{bytes.inspect}" do
        expect(rejection(bytes)).to eq([ :empty_file, "file is empty" ])
      end
    end
  end

  describe "newline normalization" do
    it "is off by default" do
      expect([ gate.normalize_newlines?, read("a\r\nb\rc\n").first ]).to eq([ false, "a\r\nb\rc\n" ])
    end

    it "turns CRLF and lone CR into LF" do
      expect(read("a\r\nb\rc\nd\r", normalize_newlines: true).first).to eq("a\nb\nc\nd\n")
    end

    it "keeps a CRLF split across chunks as one newline" do
      expect(read("ab\r\ncd\r\n", normalize_newlines: true, chunk_size: 3).first).to eq("ab\ncd\n")
    end

    it "counts lines after normalization for error hints" do
      expect(rejection("a\r\nb\r\nc\xFF", normalize_newlines: true).last).to include("first invalid byte on line 3")
    end
  end

  describe "streaming in chunks" do
    it "keeps UTF-8 characters split across chunks" do
      expect(read("nguyễn😀名前\n" * 3, chunk_size: 1).first).to eq("nguyễn😀名前\n" * 3)
    end

    it "keeps Shift_JIS characters split across chunks" do
      allow(self).to receive(:encoding).and_return("Shift_JIS")

      expect(read("名前\n年齢\n".encode("Shift_JIS"), chunk_size: 1).first).to eq("名前\n年齢\n")
    end

    it "detects a BOM in the first chunk" do
      expect(read("\xEF\xBB\xBFab\n", chunk_size: 3)).to eq([ "ab\n", Encoding::UTF_8, true ])
    end

    it "reports the line of an invalid byte in a later chunk" do
      expect(rejection("a\nb\nc\n\xFF", chunk_size: 2).last).to include("first invalid byte on line 4")
    end

    it "reads a big file without loading it at once" do
      content = "email,name\n" + ("a@example.com,Ann\n" * 20_000)

      expect(read(content).first.bytesize).to eq(content.bytesize)
    end
  end

  it "defaults the logger to ApplicationImport.logger" do
    expect(described_class.new(definition).logger).to be(ApplicationImport.logger)
  end
end
