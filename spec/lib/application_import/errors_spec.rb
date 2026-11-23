RSpec.describe ApplicationImport::Errors do
  describe "hierarchy" do
    {
      ApplicationImport::Errors::Error => StandardError,
      ApplicationImport::Errors::ConfigError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::FileError => ApplicationImport::Errors::Error,
      ApplicationImport::Errors::CastError => ApplicationImport::Errors::Error,
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
