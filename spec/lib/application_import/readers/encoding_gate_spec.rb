RSpec.describe ApplicationImport::Readers::EncodingGate do
  subject(:gate) { described_class.new(definition, logger:) }

  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:encoding) { nil }
  let(:definition) do
    file = encoding ? { "encoding" => encoding } : {}
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "file" => file })
  end

  def read(bytes)
    gate.call(ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new(bytes.b)))
  end

  def rejection(bytes)
    read(bytes)
  rescue ApplicationImport::Errors::FileError => e
    [ e.code, e.message ]
  end

  context "with the default UTF-8 encoding" do
    it "returns UTF-8 content unchanged" do
      text = read("email\nnguyễn@example.com\n")

      expect([ text.content, text.content.encoding, text.encoding, text.bom ])
        .to eq([ "email\nnguyễn@example.com\n", Encoding::UTF_8, Encoding::UTF_8, false ])
    end

    it "strips a UTF-8 BOM" do
      text = read("\xEF\xBB\xBFemail\n")

      expect([ text.content, text.bom ]).to eq([ "email\n", true ])
    end

    it "rejects invalid UTF-8 and points at the first bad line" do
      expect(rejection("email\nok\nbad\xFF\n")).to eq([
        :invalid_encoding, "file is not valid UTF-8 (first invalid byte on line 3) [encoding: UTF-8]"
      ])
    end

    it "rejects a Shift_JIS file read as UTF-8" do
      expect(rejection("名前\n".encode("Shift_JIS")).first).to eq(:invalid_encoding)
    end

    it "rejects NUL bytes (UTF-16 without BOM)" do
      expect(rejection("email\n".encode("UTF-16LE"))).to eq([
        :invalid_encoding, "file contains NUL bytes (UTF-16 without BOM or a binary file?) [encoding: UTF-8]"
      ])
    end

    it "logs every rejection as a warning" do
      rejection("bad\xFF")

      expect(log.string).to start_with("WARN [ApplicationImport::Readers::EncodingGate:users] rejected: file is not valid UTF-8")
    end
  end

  context "with a configured single-byte or multi-byte encoding" do
    let(:encoding) { "Shift_JIS" }

    it "transcodes to UTF-8" do
      text = read("名前,年齢\n".encode("Shift_JIS"))

      expect([ text.content, text.content.encoding, text.encoding ]).to eq([ "名前,年齢\n", Encoding::UTF_8, Encoding::Shift_JIS ])
    end

    it "rejects bytes that are invalid in that encoding" do
      expect(rejection("a\n\x82\n").first(2)).to eq([ :invalid_encoding, "file is not valid Shift_JIS (first invalid byte on line 2) [encoding: Shift_JIS]" ])
    end
  end

  context "with Windows-1252" do
    let(:encoding) { "Windows-1252" }

    it "transcodes accented characters" do
      expect(read("caf\xE9\n").content).to eq("café\n")
    end

    it "rejects bytes with no UTF-8 mapping" do
      expect(rejection("a\x81\n")).to match([ :invalid_encoding, /cannot be converted from Windows-1252 to UTF-8|not valid Windows-1252/ ])
    end
  end

  context "with a BOM" do
    it "reads UTF-16LE and warns that the configured encoding is ignored" do
      text = read("\xFF\xFE".b + "email\n名前\n".encode("UTF-16LE").b)

      expect([ text.content, text.encoding, text.bom ]).to eq([ "email\n名前\n", Encoding::UTF_16LE, true ])
      expect(log.string).to include("WARN", "file has a UTF-16LE BOM, ignoring the configured encoding UTF-8")
    end

    it "reads UTF-16BE" do
      expect(read("\xFE\xFF".b + "email\n".encode("UTF-16BE").b).content).to eq("email\n")
    end

    it "does not warn when the BOM matches the configured encoding" do
      read("\xEF\xBB\xBFemail\n")

      expect(log.string).to eq("")
    end

    it "rejects a truncated UTF-16 body" do
      expect(rejection("\xFF\xFE".b + "ab".encode("UTF-16LE").b + "\x00".b).first).to eq(:invalid_encoding)
    end
  end

  context "with a dummy encoding and no BOM" do
    let(:encoding) { "UTF-16" }

    it "asks for a BOM" do
      expect(rejection("e\x00".b)).to eq([ :invalid_encoding, "UTF-16 needs a BOM to be read [encoding: UTF-16]" ])
    end
  end

  describe "empty content" do
    [ "", "\xEF\xBB\xBF", " \n\r\n\t" ].each do |bytes|
      it "rejects #{bytes.inspect}" do
        expect(rejection(bytes)).to eq([ :empty_file, "file is empty" ])
      end
    end
  end

  it "reads a path-backed source" do
    Tempfile.create([ "u", ".csv" ]) do |file|
      file.binmode.write("\xEF\xBB\xBFemail\n") && file.flush

      expect(gate.call(ApplicationImport::Source.build(file.path)).content).to eq("email\n")
    end
  end

  describe "UTF-8 content" do
    it "accepts 4-byte characters" do
      expect(read("email\n😀@example.com\n").content).to eq("email\n😀@example.com\n")
    end

    it "rejects an overlong or truncated sequence at the end of the file" do
      expect(rejection("ok\n\xE2\x82").first).to eq(:invalid_encoding)
    end

    it "returns a UTF-8 String even from binary bytes" do
      expect(read("a".b).content.encoding).to eq(Encoding::UTF_8)
    end
  end

  context "with ISO-8859-1" do
    let(:encoding) { "ISO-8859-1" }

    it "maps every byte" do
      expect(read("\xC0\xFF\n").content).to eq("Àÿ\n")
    end
  end

  context "with a configured encoding that contains NUL after transcoding" do
    let(:encoding) { "Shift_JIS" }

    it "rejects NUL bytes" do
      expect(rejection("a\x00b\n").first(2)).to eq([ :invalid_encoding, "file contains NUL bytes (UTF-16 without BOM or a binary file?) [encoding: Shift_JIS]" ])
    end
  end

  context "with a UTF-8 BOM but another configured encoding" do
    let(:encoding) { "Shift_JIS" }

    it "reads as UTF-8 and warns" do
      text = read("\xEF\xBB\xBF名前\n")

      expect([ text.content, text.encoding ]).to eq([ "名前\n", Encoding::UTF_8 ])
      expect(log.string).to include("file has a UTF-8 BOM, ignoring the configured encoding Shift_JIS")
    end
  end

  context "with an invalid UTF-16 body" do
    it "rejects it without a line hint (not ASCII compatible)" do
      bytes = "\xFF\xFE".b + "\x00\xD8\x41\x00".b

      expect(rejection(bytes)).to eq([ :invalid_encoding, "file is not valid UTF-16LE [encoding: UTF-16LE]" ])
    end
  end

  context "with a UTF-32 dummy encoding and no BOM" do
    let(:encoding) { "UTF-32" }

    it "asks for a BOM" do
      expect(rejection("a\x00\x00\x00").last).to eq("UTF-32 needs a BOM to be read [encoding: UTF-32]")
    end
  end

  it "returns an immutable Text" do
    expect(read("email\n")).to be_frozen
  end

  it "uses the definition's import name in the log prefix" do
    rejection("\xFF")

    expect(log.string).to include("[ApplicationImport::Readers::EncodingGate:users]")
  end

  it "defaults the logger to ApplicationImport.logger" do
    expect(described_class.new(definition).logger).to be(ApplicationImport.logger)
  end
end
