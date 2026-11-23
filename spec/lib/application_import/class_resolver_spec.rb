RSpec.describe ApplicationImport::ClassResolver do
  let(:base) { stub_const("ImportBase", Class.new) }
  let(:fallback) { stub_const("ImportFallback", Class.new) }

  before do
    stub_const("ImportChild", Class.new(base))
    stub_const("ImportOther", Class.new)
    stub_const("ImportModule", Module.new)
  end

  describe ".resolve!" do
    it "returns the default for a blank name" do
      expect([ nil, "", " " ].map { |name| described_class.resolve!(name, base:, default: fallback) })
        .to eq([ fallback, fallback, fallback ])
    end

    it "returns nil for a blank name without default" do
      expect(described_class.resolve!(nil, base:)).to be_nil
    end

    it "resolves a class name, a Symbol or a Class" do
      expect([ "ImportChild", :ImportChild, ImportChild ].map { |name| described_class.resolve!(name, base:) })
        .to eq([ ImportChild, ImportChild, ImportChild ])
    end

    it "accepts the base class itself" do
      expect(described_class.resolve!("ImportBase", base:)).to eq(base)
    end

    it "accepts the base as a class name" do
      base
      expect(described_class.resolve!("ImportChild", base: "ImportBase")).to eq(ImportChild)
    end

    it "raises when the class does not exist" do
      expect { described_class.resolve!("ImportMissing", base:) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "ImportMissing not found") { |error|
          expect([ error.klass, error.base ]).to eq([ "ImportMissing", base ])
        }
    end

    it "raises when the class does not inherit base" do
      expect { described_class.resolve!("ImportOther", base:) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "ImportOther must inherit from ImportBase")
    end

    it "raises when the constant is not a class" do
      expect { described_class.resolve!("ImportModule", base:) }
        .to raise_error(ApplicationImport::Errors::InvalidClassError, "ImportModule must inherit from ImportBase")
    end

    it "raises the given error class" do
      expect { described_class.resolve!("ImportOther", base:, error: ApplicationImport::Errors::InvalidHandlerError) }
        .to raise_error(ApplicationImport::Errors::InvalidHandlerError) { |error| expect(error.handler).to eq(ImportOther) }
    end

    it "does not check the default against base" do
      expect(described_class.resolve!(nil, base:, default: ImportOther)).to eq(ImportOther)
    end
  end
end
