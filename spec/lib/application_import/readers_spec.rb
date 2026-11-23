RSpec.describe ApplicationImport::Readers do
  let(:logger) { ActiveSupport::Logger.new(nil) }
  let(:source) { ApplicationImport::Source.new(filename: "u.xlsx", io: StringIO.new("email\n")) }

  def definition(file = {})
    ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "file" => file })
  end

  it "defaults to the CSV reader, whatever the file extension" do
    reader = described_class.for(definition, source, logger:)

    expect([ reader.class, reader.definition, reader.source, reader.logger ])
      .to eq([ ApplicationImport::Readers::Csv, reader.definition, source, logger ])
  end

  it "picks the reader from file.format" do
    expect(described_class.for(definition("format" => "xlsx"), source)).to be_a(ApplicationImport::Readers::Xlsx)
  end

  it "uses a custom file.reader over file.format" do
    custom = stub_const("UsersReader", Class.new(ApplicationImport::Readers::Base))

    expect(described_class.for(definition("reader" => "UsersReader", "format" => "xlsx"), source, logger:))
      .to have_attributes(class: custom, logger:)
  end

  it "accepts a custom reader that inherits a built-in one and rewrites part of it" do
    stub_const("SemicolonReader", Class.new(ApplicationImport::Readers::Csv) do
      private

      def each_record
        super { |line, values| yield line, values.flat_map { |value| value.to_s.split(";") } }
      end
    end)
    source = ApplicationImport::Source.new(filename: "u.csv", io: StringIO.new("email;name\na;b\n"))

    reader = described_class.for(definition("reader" => "SemicolonReader"), source, logger:)

    expect([ reader.map(&:values), reader.headers ]).to eq([ [ %w[ a b ] ], %w[ email name ] ])
  end

  it "defaults the logger to ApplicationImport.logger" do
    expect(described_class.for(definition, source).logger).to be(ApplicationImport.logger)
  end

  describe ".reader_class" do
    it "maps formats to reader classes, nil meaning csv" do
      expect([ described_class.reader_class(nil), described_class.reader_class(:csv), described_class.reader_class("xlsx") ])
        .to eq([ ApplicationImport::Readers::Csv, ApplicationImport::Readers::Csv, ApplicationImport::Readers::Xlsx ])
    end

    it "has a reader for every supported format" do
      expect(described_class::READERS.keys.map(&:to_s)).to match_array(ApplicationImport::Constants::FORMATS)
    end

    it "raises ConfigError for an unknown format" do
      expect { described_class.reader_class(:pdf) }.to raise_error(ApplicationImport::Errors::ConfigError, "no reader for format pdf")
    end
  end

  it "accepts the format as a String" do
    expect(described_class.reader_class("csv")).to eq(ApplicationImport::Readers::Csv)
  end

  it "builds the reader with the given source" do
    expect(described_class.for(definition, source, logger:).source).to be(source)
  end
end
