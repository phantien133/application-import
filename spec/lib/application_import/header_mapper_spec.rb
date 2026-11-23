RSpec.describe ApplicationImport::HeaderMapper do
  let(:log) { StringIO.new }
  let(:logger) { ActiveSupport::Logger.new(log).tap { |l| l.formatter = ->(severity, _, _, msg) { "#{severity} #{msg}\n" } } }
  let(:result) { ApplicationImport::Result.new }

  def definition(file = {})
    ApplicationImport::Definition.new(:users, {
      "file" => file,
      "columns" => {
        "email" => { "header" => "Email", "aliases" => [ "E-mail" ], "required" => true },
        "name" => { "header" => "Full Name" },
        "age" => { "header" => "Age" }
      }
    })
  end

  def map(headers, file = {})
    described_class.new(definition(file), logger:).call(headers, result)
  end

  def errors
    result.errors.map { |error| [ error.code, error.message, error.details ] }
  end

  describe ".normalize" do
    it "ignores case and surrounding or repeated whitespace" do
      expect(described_class.normalize("  Full \t  NAME ")).to eq("full name")
    end

    it "handles nil and non-ASCII" do
      expect([ described_class.normalize(nil), described_class.normalize("TÊN Đầy") ]).to eq([ "", "tên đầy" ])
    end
  end

  context "with a header row" do
    it "maps headers to column keys by position" do
      header_map = map(%w[ Age Email ])

      expect(header_map.attributes([ "30", "a@example.com" ])).to eq(email: "a@example.com", name: nil, age: "30")
      expect(errors).to eq([])
    end

    it "matches aliases, case and whitespace insensitively" do
      header_map = map([ " e-MAIL ", "full   name" ])

      expect(header_map.attributes(%w[ a b ])).to eq(email: "a", name: "b", age: nil)
    end

    it "reports missing required headers" do
      map(%w[ Age ])

      expect(errors).to eq([ [ :missing_headers, "missing required headers: Email", { headers: [ "Email" ] } ] ])
    end

    it "logs missing optional headers and leaves them nil" do
      header_map = map(%w[ Email ])

      expect(header_map.attributes(%w[ a ])).to eq(email: "a", name: nil, age: nil)
      expect(log.string).to include("INFO [ApplicationImport::HeaderMapper:users] optional headers not found: Full Name, Age")
    end

    it "does not log when every header is present" do
      map([ "Email", "Full Name", "Age" ])

      expect(log.string).to eq("")
    end

    it "reports two headers for the same column" do
      map([ "Email", "E-mail" ])

      expect(errors).to eq([ [ :duplicate_headers, 'header "E-mail" duplicates "Email"', { header: "E-mail", column: "Email" } ] ])
    end

    it "keeps the first of duplicated headers in the map" do
      expect(map([ "Email", "email" ]).attributes(%w[ first second ])[:email]).to eq("first")
    end

    it "reports every problem at once" do
      map([ "Age", "age", "Nope" ])

      expect(errors.map(&:first)).to eq(%i[ duplicate_headers missing_headers ])
    end

    describe "unknown headers" do
      it "skips them by default and logs them" do
        header_map = map([ "Email", "Phone", "Note" ])

        expect(header_map.attributes(%w[ a 123 hi ])).to eq(email: "a", name: nil, age: nil)
        expect(log.string).to include("ignoring unknown headers: Phone, Note")
      end

      context "with unknown_headers: keep" do
        let(:file) { { "unknown_headers" => "keep" } }

        it "passes them through keyed by the stripped header" do
          header_map = map([ "Email", " Phone ", "Note" ], file)

          expect(header_map.attributes(%w[ a 123 hi ])).to eq(:email => "a", :name => nil, :age => nil, "Phone" => "123", "Note" => "hi")
          expect(errors).to eq([])
        end

        it "ignores blank headers with a warning" do
          header_map = map([ "Email", "", nil, "Note" ], file)

          expect(header_map.attributes(%w[ a x y hi ])).to eq(:email => "a", :name => nil, :age => nil, "Note" => "hi")
          expect(log.string).to include("WARN", "ignoring 2 blank headers")
        end

        it "reports repeated unknown headers" do
          map([ "Email", "Note", "Note" ], file)

          expect(errors).to eq([ [ :duplicate_headers, 'header "Note" duplicates "Note"', { header: "Note", column: "Note" } ] ])
        end

        it "still validates the defined columns" do
          map([ "Note" ], file)

          expect(errors.map(&:first)).to eq([ :missing_headers ])
        end
      end
    end

    it "fills cells missing at the end of a row with nil and ignores extra cells" do
      header_map = map(%w[ Email Age ])

      expect([ header_map.attributes([ "a" ]), header_map.attributes(%w[ a 1 extra ]) ])
        .to eq([ { email: "a", name: nil, age: nil }, { email: "a", name: nil, age: "1" } ])
    end
  end

  context "without a header row (headers: false)" do
    it "maps cells to columns by position, ignoring headers and extra cells" do
      header_map = map(%w[ whatever ], "headers" => false)

      expect(header_map.attributes(%w[ a b 3 extra ])).to eq(email: "a", name: "b", age: "3")
      expect(errors).to eq([])
    end

    it "keeps extra cells as column_<n> with unknown_headers: keep" do
      header_map = map([], "headers" => false, "unknown_headers" => "keep")

      expect(header_map.attributes(%w[ a b 3 x y ])).to eq(:email => "a", :name => "b", :age => "3", "column_4" => "x", "column_5" => "y")
      expect(header_map.attributes(%w[ a ])).to eq(email: "a", name: nil, age: nil)
    end
  end

  it "defaults the logger to ApplicationImport.logger" do
    expect(described_class.new(definition).logger).to be(ApplicationImport.logger)
  end
end
