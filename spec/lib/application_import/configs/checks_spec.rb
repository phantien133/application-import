RSpec.describe ApplicationImport::Configs::Checks do
  subject(:checker) do
    Class.new do
      include ApplicationImport::Configs::Checks

      attr_reader :errors

      def initialize
        @errors = []
      end

      def check(name, *args, **kwargs)
        send(name, *args, **kwargs)
      end
    end.new
  end

  describe "#add_error" do
    it "records the path and message and returns nil" do
      expect(checker.check(:add_error, "file.max_size", "is invalid")).to be_nil
      expect(checker.errors).to eq([ "file.max_size is invalid" ])
    end
  end

  describe "#check_keys" do
    it "reports unknown keys" do
      checker.check(:check_keys, { "a" => 1, "b" => 2, "c" => 3 }, %w[ a ], "file")

      expect(checker.errors).to eq([ "file has unknown keys: b, c" ])
    end

    it "accepts allowed keys" do
      checker.check(:check_keys, { "a" => 1 }, %w[ a b ], "file")

      expect(checker.errors).to be_empty
    end
  end

  describe "#mapping" do
    it "returns hashes, maps nil to an empty hash and rejects other values" do
      expect([ checker.check(:mapping, { "a" => 1 }, "file"), checker.check(:mapping, nil, "file"),
        checker.check(:mapping, [ 1 ], "file") ]).to eq([ { "a" => 1 }, {}, {} ])
      expect(checker.errors).to eq([ "file must be a mapping" ])
    end
  end

  describe "#one_of" do
    it "returns the value as a Symbol when allowed" do
      expect([ checker.check(:one_of, "csv", %w[ csv xlsx ], "format"), checker.check(:one_of, :xlsx, %w[ csv xlsx ], "format") ])
        .to eq(%i[ csv xlsx ])
    end

    it "reports values not allowed" do
      expect(checker.check(:one_of, "pdf", %w[ csv xlsx ], "format")).to be_nil
      expect(checker.errors).to eq([ "format must be one of csv, xlsx" ])
    end
  end

  describe "#class_name" do
    it "returns nil for nil and the name for a non-blank String" do
      expect([ checker.check(:class_name, nil, "handler"), checker.check(:class_name, "Imports::X", "handler") ])
        .to eq([ nil, "Imports::X" ])
    end

    it "rejects blank and non-String values" do
      checker.check(:class_name, "", "handler")
      checker.check(:class_name, 1, "handler")

      expect(checker.errors).to eq([ "handler must be a class name" ] * 2)
    end
  end

  describe "#integer" do
    it "accepts integers at or above min" do
      expect([ checker.check(:integer, 1, "max_size"), checker.check(:integer, 0, "min_length", min: 0) ]).to eq([ 1, 0 ])
    end

    it "rejects integers below min and non-integers" do
      checker.check(:integer, 0, "max_size")
      checker.check(:integer, "5", "max_size")

      expect(checker.errors).to eq([ "max_size must be an integer >= 1" ] * 2)
    end
  end

  describe "#boolean" do
    it "accepts true and false only" do
      expect([ checker.check(:boolean, true, "required"), checker.check(:boolean, false, "required"),
        checker.check(:boolean, "yes", "required") ]).to eq([ true, false, nil ])
      expect(checker.errors).to eq([ "required must be true or false" ])
    end
  end

  describe "#names" do
    it "returns a list of Strings from a name or a list of names" do
      expect([ checker.check(:names, "email", "keys"), checker.check(:names, [ :email, "name" ], "keys") ])
        .to eq([ [ "email" ], [ "email", "name" ] ])
    end

    it "rejects empty lists and non-name items" do
      expect([ checker.check(:names, [], "keys"), checker.check(:names, [ 1 ], "keys") ]).to eq([ [], [] ])
      expect(checker.errors).to eq([ "keys must be a non-empty list of names" ] * 2)
    end
  end

  describe "#check_columns" do
    it "reports keys that are not columns" do
      checker.check(:check_columns, %i[ email phone ], %i[ email ], "keys")

      expect(checker.errors).to eq([ "keys references unknown columns: phone" ])
    end
  end

  describe "#regexp" do
    it "compiles a pattern and returns nil for nil" do
      expect([ checker.check(:regexp, '\A\d+\z', "pattern"), checker.check(:regexp, nil, "pattern") ]).to eq([ /\A\d+\z/, nil ])
    end

    it "reports invalid patterns" do
      expect(checker.check(:regexp, "[", "pattern")).to be_nil
      expect(checker.errors.first).to start_with("pattern is not a valid regexp:")
    end
  end
end
