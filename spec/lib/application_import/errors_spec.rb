RSpec.describe ApplicationImport::Errors do
  describe "hierarchy" do
    {
      ApplicationImport::Errors::Error => StandardError,
      ApplicationImport::Errors::ConfigError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::FileError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::CastError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::RowError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::RowsError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::InvalidClassError => ApplicationImport::Errors::ConfigError,
      ApplicationImport::Errors::InvalidHandlerError => ApplicationImport::Errors::InvalidClassError,
      ApplicationImport::Errors::InvalidRunnerError => ApplicationImport::Errors::InvalidClassError,
      ApplicationImport::Errors::InvalidFileValidatorError => ApplicationImport::Errors::InvalidClassError
    }.each do |error_class, parent|
      it "#{error_class.name.demodulize} inherits #{parent.name}" do
        expect(error_class.superclass).to eq(parent)
      end
    end
  end

  describe ApplicationImport::Errors::FileError do
    it "defaults the code to :invalid_file" do
      error = described_class.new("unreadable")

      expect([ error.message, error.code ]).to eq([ "unreadable", :invalid_file ])
    end

    it "accepts a custom code" do
      expect(described_class.new("bad bytes", code: :invalid_encoding).code).to eq(:invalid_encoding)
    end
  end

  describe "code normalization" do
    it "stores codes as Symbols" do
      expect([
        ApplicationImport::Errors::FileError.new("x", code: "bad").code,
        ApplicationImport::Errors::RowError.new("x", line: 1, code: "required").code,
        ApplicationImport::Errors::RowsError.new("x", lines: [ 1 ], code: "duplicate").code
      ]).to eq(%i[ bad required duplicate ])
    end
  end

  describe "line validation" do
    it "requires RowError line to be an Integer >= 1" do
      [ nil, 0, "2" ].each do |line|
        expect { ApplicationImport::Errors::RowError.new("x", line:) }.to raise_error(ArgumentError, /line must be an Integer >= 1/)
      end
    end

    it "requires RowsError lines to be non-empty Integers >= 1" do
      [ [], nil, [ 2, nil ], [ 0 ] ].each do |lines|
        expect { ApplicationImport::Errors::RowsError.new("x", lines:) }.to raise_error(ArgumentError, /lines must be Integers >= 1/)
      end
    end
  end

  describe ApplicationImport::Errors::RowError do
    it "keeps the line, column and code" do
      error = described_class.new("Email is required", line: 3, column: :email, code: :required)

      expect([ error.message, error.line, error.column, error.code ]).to eq([ "Email is required", 3, "email", :required ])
    end

    it "defaults the column to nil and the code to :invalid_row" do
      error = described_class.new("bad row", line: 2)

      expect([ error.column, error.code ]).to eq([ nil, :invalid_row ])
    end
  end

  describe ApplicationImport::Errors::RowsError do
    it "keeps every conflicting line and column" do
      error = described_class.new("duplicate email", lines: [ 2, 5 ], columns: [ :email ], code: :duplicate)

      expect([ error.message, error.lines, error.columns, error.code ]).to eq([ "duplicate email", [ 2, 5 ], [ "email" ], :duplicate ])
    end

    it "defaults columns to empty and the code to :rows_conflict" do
      error = described_class.new("totals do not match", lines: 4)

      expect([ error.lines, error.columns, error.code ]).to eq([ [ 4 ], [], :rows_conflict ])
    end
  end

  describe ApplicationImport::Errors::InvalidClassError do
    it "builds the message from klass and base" do
      error = described_class.new(klass: String, base: Integer)

      expect([ error.message, error.klass, error.base ]).to eq([ "String must inherit from Integer", String, Integer ])
    end

    it "prefers an explicit message" do
      expect(described_class.new("Nope not found", klass: "Nope", base: Integer).message).to eq("Nope not found")
    end
  end

  {
    ApplicationImport::Errors::InvalidHandlerError => [ :handler, "ApplicationImport::Handler" ],
    ApplicationImport::Errors::InvalidRunnerError => [ :runner, "ApplicationImport::Runner" ],
    ApplicationImport::Errors::InvalidFileValidatorError => [ :file_validator, "ApplicationImport::FileValidator" ]
  }.each do |error_class, (keyword, base)|
    describe error_class do
      it "takes #{keyword}: and defaults base to #{base}" do
        error = error_class.new(keyword => String)

        expect([ error.message, error.public_send(keyword), error.klass, error.base ])
          .to eq([ "String must inherit from #{base}", String, String, base ])
      end

      it "accepts klass: and base: like InvalidClassError" do
        error = error_class.new(klass: "Missing", base: Integer)

        expect([ error.public_send(keyword), error.base ]).to eq([ "Missing", Integer ])
      end
    end
  end
end
