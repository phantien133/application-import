RSpec.describe ApplicationImport::Source do
  def content
    "email\na@example.com\n"
  end

  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:file_path) { dir.join("users_20260101.CSV").tap { |path| path.write(content) } }

  after { FileUtils.remove_entry(dir) }

  shared_examples "a path-backed source" do
    it "keeps the file path and no io" do
      expect(source.to_h).to eq(expected.merge(io: nil))
    end

    it "reports size from the file system" do
      expect(source.size).to eq(content.bytesize)
    end

    it "opens a fresh binary IO each time and closes it afterwards" do
      opened = []
      2.times { source.open { |io| opened << [ io.binmode?, io.read, io ] } }

      expect(opened.map { |binmode, read, _| [ binmode, read ] }).to eq([ [ true, content ] ] * 2)
      expect(opened.map(&:last)).to all(be_closed)
    end
  end

  shared_examples "an io-backed source" do
    it "keeps the given io" do
      expect(source.to_h).to eq(expected.merge(io: input))
    end

    it "reports size from the io" do
      expect(source.size).to eq(content.bytesize)
    end

    it "rewinds the io before every read and leaves it open" do
      input.read
      reads = Array.new(2) { source.open(&:read) }

      expect(reads).to eq([ content ] * 2)
      expect(input).not_to be_closed
    end
  end

  describe ".build" do
    context "with a String path" do
      subject(:source) { described_class.build(file_path.to_s) }

      let(:expected) { { filename: "users_20260101.CSV", path: file_path.to_s } }

      it_behaves_like "a path-backed source"
    end

    context "with a Pathname" do
      subject(:source) { described_class.build(file_path) }

      let(:expected) { { filename: "users_20260101.CSV", path: file_path.to_s } }

      it_behaves_like "a path-backed source"
    end

    context "with a relative path" do
      subject(:source) { described_class.build(relative) }

      let(:relative) { file_path.relative_path_from(Pathname.pwd).to_s }
      let(:expected) { { filename: "users_20260101.CSV", path: relative } }

      it_behaves_like "a path-backed source"
    end

    context "with a path and an explicit filename" do
      subject(:source) { described_class.build(file_path, filename: "users.csv") }

      let(:expected) { { filename: "users.csv", path: file_path.to_s } }

      it_behaves_like "a path-backed source"
    end

    context "with a missing path" do
      it "raises ArgumentError" do
        expect { described_class.build(dir.join("nope.csv")) }
          .to raise_error(ArgumentError, "import file not found: #{dir.join("nope.csv")}")
      end
    end

    context "with a directory path" do
      it "raises ArgumentError" do
        expect { described_class.build(dir.to_s) }.to raise_error(ArgumentError, /import file not found/)
      end
    end

    context "with a Rack::Test::UploadedFile" do
      subject(:source) { described_class.build(input) }

      let(:input) { Rack::Test::UploadedFile.new(file_path, "text/csv", original_filename: "upload.csv") }
      let(:expected) { { filename: "upload.csv", path: input.tempfile.path } }

      it_behaves_like "a path-backed source"
    end

    context "with an ActionDispatch::Http::UploadedFile" do
      subject(:source) { described_class.build(input) }

      let(:input) do
        tempfile = Tempfile.new([ "upload", ".csv" ]).tap { |file| file.write(content) && file.flush }
        ActionDispatch::Http::UploadedFile.new(tempfile:, filename: "members.csv", type: "text/csv")
      end
      let(:expected) { { filename: "members.csv", path: input.tempfile.path } }

      after { input.tempfile.close! }

      it_behaves_like "a path-backed source"

      it "prefers an explicit filename over the original filename" do
        expect(described_class.build(input, filename: "other.csv").filename).to eq("other.csv")
      end
    end

    context "with a File" do
      subject(:source) { described_class.build(input) }

      let(:input) { File.open(file_path) }
      let(:expected) { { filename: "users_20260101.CSV", path: file_path.to_s } }

      after { input.close }

      it_behaves_like "an io-backed source"
    end

    context "with a Tempfile" do
      subject(:source) { described_class.build(input) }

      let(:input) { Tempfile.new([ "tmp", ".csv" ]).tap { |file| file.write(content) && file.flush } }
      let(:expected) { { filename: File.basename(input.path), path: input.path } }

      after { input.close! }

      it_behaves_like "an io-backed source"
    end

    context "with a StringIO and a filename" do
      subject(:source) { described_class.build(input, filename: "x.csv") }

      let(:input) { StringIO.new(content) }
      let(:expected) { { filename: "x.csv", path: nil } }

      it_behaves_like "an io-backed source"
    end

    context "with a StringIO without a filename" do
      it "raises ArgumentError" do
        expect { described_class.build(StringIO.new(content)) }.to raise_error(ArgumentError, "filename: is required for StringIO")
      end

      it "treats a blank filename as missing" do
        expect { described_class.build(StringIO.new(content), filename: "") }.to raise_error(ArgumentError, /filename: is required/)
      end
    end

    context "with a Source" do
      it "returns it unchanged, ignoring filename" do
        source = described_class.build(file_path)

        expect(described_class.build(source, filename: "other.csv")).to be(source)
      end
    end

    context "with an unsupported object" do
      [ nil, 123, {}, [], Object.new ].each do |value|
        it "raises ArgumentError for #{value.class}" do
          expect { described_class.build(value) }.to raise_error(ArgumentError, "unsupported import file: #{value.class}")
        end
      end
    end
  end

  describe ".new" do
    it "requires a path or an io" do
      expect { described_class.new(filename: "x.csv") }.to raise_error(ArgumentError, "path or io is required")
    end

    it "stringifies filename and path" do
      source = described_class.new(filename: :x, path: file_path)

      expect([ source.filename, source.path ]).to eq([ "x", file_path.to_s ])
    end

    it "is frozen" do
      expect(described_class.new(filename: "x.csv", path: file_path)).to be_frozen
    end
  end

  describe "#extension" do
    {
      "users.csv" => "csv",
      "USERS.CSV" => "csv",
      "users.Xlsx" => "xlsx",
      "archive.tar.gz" => "gz",
      "users" => "",
      ".csv" => ""
    }.each do |filename, extension|
      it "is #{extension.inspect} for #{filename}" do
        expect(described_class.new(filename:, path: file_path).extension).to eq(extension)
      end
    end
  end

  describe "#open" do
    it "returns the block value" do
      expect(described_class.build(file_path).open { |io| io.gets.chomp }).to eq("email")
    end

    it "closes a path-backed file even when the block raises" do
      opened = nil

      expect { described_class.build(file_path).open { |io| (opened = io) && raise("boom") } }.to raise_error("boom")
      expect(opened).to be_closed
    end
  end
end
