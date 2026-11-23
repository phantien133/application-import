RSpec.describe ApplicationImport::FileChecker do
  subject(:checker) { described_class.new(definition, logger:) }

  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:definition) { ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil }, "file" => file_config }) }
  let(:file_config) { { "formats" => %w[ csv ], "name_pattern" => '\Ausers_\d{8}\.csv\z', "max_size" => 100 } }
  let(:result) { ApplicationImport::Result.new }

  def source(filename, content = "email\n")
    ApplicationImport::Source.new(filename:, io: StringIO.new(content))
  end

  def check(filename, content = "email\n")
    checker.call(source(filename, content), result)
    result.errors.map { |error| [ error.code, error.message, error.details ] }
  end

  it "exposes the definition and the injected logger" do
    expect([ checker.definition, checker.logger ]).to eq([ definition, logger ])
  end

  it "defaults the logger to ApplicationImport.logger" do
    expect(described_class.new(definition).logger).to be(ApplicationImport.logger)
  end

  it "returns the result" do
    expect(checker.call(source("users_20260101.csv"), result)).to be(result)
  end

  context "when every check passes" do
    it "records no error and logs nothing" do
      expect(check("users_20260101.csv")).to eq([])
      expect(log.string).to eq("")
    end

    it "accepts a size equal to max_size" do
      expect(check("users_20260101.csv", "x" * 100)).to eq([])
    end
  end

  describe "formats" do
    let(:file_config) { { "formats" => %w[ csv xlsx ] } }

    it "accepts any listed format, case-insensitively" do
      expect([ check("a.csv"), check("a.XLSX"), check("a.Csv") ]).to all(eq([]))
    end

    it "rejects an unlisted extension" do
      expect(check("a.txt")).to eq([
        [ :invalid_format, "file format txt is not allowed, expected one of: csv, xlsx", { format: "txt", allowed: %w[ csv xlsx ] } ]
      ])
    end

    it "rejects a filename without extension" do
      expect(check("users").first.first(2)).to eq([ :invalid_format, "file format (none) is not allowed, expected one of: csv, xlsx" ])
    end
  end

  describe "name_pattern" do
    let(:file_config) { { "name_pattern" => '\Ausers_\d{8}\.csv\z' } }

    it "rejects a filename that does not match" do
      expect(check("members.csv")).to eq([
        [ :invalid_name, 'filename members.csv does not match \Ausers_\d{8}\.csv\z',
          { filename: "members.csv", pattern: '\Ausers_\d{8}\.csv\z' } ]
      ])
    end

    it "matches against the filename only" do
      expect(check("users_20260101.csv")).to eq([])
    end
  end

  describe "max_size" do
    let(:file_config) { { "max_size" => 5 } }

    it "rejects a file bigger than max_size" do
      expect(check("a.csv", "123456")).to eq([
        [ :too_large, "file size 6 bytes exceeds the maximum of 5 bytes", { size: 6, max_size: 5 } ]
      ])
    end

    it "measures a path-backed source on disk" do
      Tempfile.create([ "users", ".csv" ]) do |file|
        file.write("123456") && file.flush
        checker.call(ApplicationImport::Source.build(file.path), result)
      end

      expect(result.errors.map(&:code)).to eq([ :too_large ])
    end
  end

  it "records every failing check" do
    expect(check("members.txt", "x" * 101).map(&:first)).to eq(%i[ invalid_format invalid_name too_large ])
  end

  context "when checks are not configured (max_size: null turns its default off)" do
    let(:file_config) { { "max_size" => nil } }

    it "bypasses them, recording no error" do
      expect(check("anything.whatever", "x" * 1_000)).to eq([])
    end

    it "logs one warning per skipped check, tagged with the checker and import name" do
      check("a.csv")

      expect(log.string.lines).to eq([
        "WARN [ApplicationImport::FileChecker:users] file.formats is not configured, skipping the formats check\n",
        "WARN [ApplicationImport::FileChecker:users] file.name_pattern is not configured, skipping the name_pattern check\n",
        "WARN [ApplicationImport::FileChecker:users] file.max_size is not configured, skipping the max_size check\n"
      ])
    end
  end

  it "checks DEFAULT_MAX_SIZE when max_size is absent" do
    stub_const("ApplicationImport::Constants::DEFAULT_MAX_SIZE", 3)
    definition = ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } })
    result = ApplicationImport::Result.new

    described_class.new(definition, logger: Logger.new(nil)).call(ApplicationImport::Source.new(filename: "a.csv", io: StringIO.new("1234")), result)

    expect(result.errors.map(&:code)).to eq(%i[ too_large ])
  end

  it "rejects a filename with a NUL byte as invalid_name, without other checks" do
    result = ApplicationImport::Result.new

    described_class.new(ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } }), logger: Logger.new(nil))
      .call(ApplicationImport::Source.new(filename: "a.csv\0.exe", io: StringIO.new("x")), result)

    expect(result.errors.map(&:code)).to eq(%i[ invalid_name ])
  end

  context "when only some checks are configured" do
    let(:file_config) { { "max_size" => 5 } }

    it "runs those and warns about the others" do
      expect(check("a.txt", "123456").map(&:first)).to eq(%i[ too_large ])
      expect(log.string.scan(/file\.(\w+) is not configured/).flatten).to eq(%w[ formats name_pattern ])
    end
  end

  it "uses the prefix of a subclass" do
    stub_const("UsersFileChecker", Class.new(described_class))
    UsersFileChecker.new(ApplicationImport::Definition.new(:users, { "columns" => { "email" => nil } }), logger:)
      .call(source("a.csv"), result)

    expect(log.string).to start_with("WARN [UsersFileChecker:users]")
  end
end
