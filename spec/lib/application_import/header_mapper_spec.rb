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

    context "with require_all_headers" do
      let(:file) { { "require_all_headers" => true } }

      it "reports every column without header, optional ones included" do
        map(%w[ Age ], file)

        expect(errors).to eq([ [ :missing_headers, "missing required headers: Email, Full Name", { headers: [ "Email", "Full Name" ] } ] ])
        expect(log.string).not_to include("optional headers not found")
      end

      it "passes when every column has a header, in any order" do
        map([ "Age", "Full Name", "e-mail" ], file)

        expect(errors).to eq([])
      end

      it "is ignored without a header row" do
        map([], file.merge("headers" => false))

        expect(errors).to eq([])
      end
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

      context "with unknown_headers: reject" do
        let(:file) { { "unknown_headers" => "reject" } }

        it "reports them all in one error" do
          map([ "Email", "Phone", "Note" ], file)

          expect(errors).to eq([ [ :unknown_headers, "unknown headers: Phone, Note", { headers: %w[ Phone Note ] } ] ])
        end

        it "ignores blank headers with a warning" do
          map([ "Email", "", nil ], file)

          expect(errors).to eq([])
          expect(log.string).to include("ignoring 2 blank headers")
        end

        it "has nothing to reject without a header row" do
          header_map = map([], file.merge("headers" => false))

          expect([ errors, header_map.attributes(%w[ a b c extra ]) ]).to eq([ [], { email: "a", name: "b", age: "c" } ])
        end
      end

      context "with exact headers (require_all_headers + reject)" do
        let(:file) { { "require_all_headers" => true, "unknown_headers" => "reject" } }

        it "passes with every column and nothing else, in any order" do
          map([ "Age", "e-mail", "Full Name" ], file)

          expect(errors).to eq([])
        end

        it "reports both missing and extra headers" do
          map([ "Email", "Phone" ], file)

          expect(errors.map(&:first)).to eq(%i[ missing_headers unknown_headers ])
        end
      end

      context "with unknown_headers: assign" do
        let(:file) { { "unknown_headers" => "assign" } }

        before do
          stub_const("HmUser", Class.new(ApplicationRecord) do
            self.table_name = "hm_users"
            class << self
              def attribute_types
                { "id" => nil, "email" => nil, "phone" => nil }
              end

              def primary_key
                "id"
              end
            end
          end)
        end

        def definition(file = {})
          ApplicationImport::Definition.new(:users, {
            "file" => file, "output" => { "model" => "HmUser" },
            "columns" => { "email" => { "header" => "Email", "required" => true } }
          })
        end

        it "keeps unknown headers like keep" do
          header_map = map([ "Email", "Phone", "Note" ], file)

          expect(header_map.attributes(%w[ a 1 n ])).to eq(:email => "a", "Phone" => "1", "Note" => "n")
        end

        it "logs which headers reach the record and warns about the others" do
          map([ "Email", "Phone", "Note" ], file)

          expect(log.string).to include("INFO", "assigning unknown headers to HmUser as they are: Phone")
          expect(log.string).to include("WARN", "unknown headers not matching a HmUser attribute, kept but not assigned: Note")
        end

        it "keeps extra cells by position without header row" do
          expect(map([], file.merge("headers" => false)).attributes(%w[ a b ])).to eq(:email => "a", "column_2" => "b")
        end
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

    it "sets the width to the header row size" do
      expect(map(%w[ Email Age Other ]).width).to eq(3)
    end

    it "fills cells missing at the end of a row with nil and ignores extra cells" do
      header_map = map(%w[ Email Age ])

      expect([ header_map.attributes([ "a" ]), header_map.attributes(%w[ a 1 extra ]) ])
        .to eq([ { email: "a", name: nil, age: nil }, { email: "a", name: nil, age: "1" } ])
    end
  end

  describe "header_pattern" do
    def definition(file = {})
      ApplicationImport::Definition.new(:users, {
        "file" => file,
        "columns" => {
          "email" => { "header" => "Email", "header_pattern" => '\Ae-?mail( address)?\z', "required" => true },
          "phone" => { "header" => "Phone", "header_pattern" => [ "phone", "\\Atel" ] },
          "note" => { "header" => "Note", "header_pattern" => "no" }
        }
      })
    end

    it "matches headers in any order by regexp, case-insensitively" do
      header_map = map([ "Telephone number", "E-MAIL ADDRESS" ])

      expect(header_map.attributes(%w[ 123 a ])).to eq(email: "a", phone: "123", note: nil)
      expect(errors).to eq([])
    end

    it "prefers an exact name over patterns" do
      header_map = map([ "Note", "Email" ])

      expect(header_map.attributes(%w[ n a ])).to eq(email: "a", phone: nil, note: "n")
    end

    it "reports a header matching the patterns of several columns" do
      map([ "Email", "no phone" ])

      expect(errors).to eq([ [ :ambiguous_headers, 'header "no phone" matches several columns: Phone, Note',
        { header: "no phone", columns: %w[ Phone Note ] } ] ])
    end

    it "reports two headers matching one column" do
      map([ "email", "E-mail address" ])

      expect(errors.map(&:first)).to eq([ :duplicate_headers ])
    end

    it "treats headers matching no pattern as unknown" do
      map([ "Email", "Fax" ])

      expect(log.string).to include("ignoring unknown headers: Fax")
    end

    it "still reports a required column whose pattern matched nothing" do
      map([ "Phone" ])

      expect(errors.map(&:first)).to eq([ :missing_headers ])
    end
  end

  context "without a header row (headers: false)" do
    it "sets the width to the column count, or none when extra cells are kept" do
      expect([ map([], "headers" => false).width, map([], "headers" => false, "unknown_headers" => "keep").width ]).to eq([ 3, nil ])
    end

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
