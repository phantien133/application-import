# What the users import does with real files (spec/fixtures/files/users). The HTTP side
# (params, rendering) is in spec/requests/user_imports_spec.rb.
RSpec.describe Users::ImportService do
  def error_rows(result)
    result.errors.map { |error| [ error.line, error.column, error.code ] }
  end

  # A users CSV built for the example (fixtures hold the reusable files).
  def csv_file(*rows)
    file = Tempfile.new([ "users", ".csv" ])
    file.write([ file_fixture("users/header_only.csv").read.chomp, *rows ].join("\n"))
    file.rewind
    file
  end

  it_behaves_like "an application service", "file.csv", dry_run: true, context: { user_id: 1 }

  describe "#call" do
    subject(:call) { described_class.new(file, dry_run:).call }

    let(:file) { file_fixture("users/#{file_name}") }
    let(:dry_run) { false }

    context "with a valid file" do
      let(:file_name) { "valid.csv" }

      it "creates every user and completes" do
        expect { call }.to change(User, :count).by(2)
        expect(call).to have_attributes(status: :completed, errors: [], stats: { total: 2, valid: 2, invalid: 0, written: 2 })
      end

      it "casts the cells and normalizes email and role" do
        call

        expect(User.find_by!(email: "ann@example.com")).to have_attributes(name: "Ann Lee", age: 30, balance: 1234.5,
          active: true, phone: "0912345678", role: "admin", nickname: "ann", created_on: Date.new(2026, 1, 2))
      end

      it "fills the defaults of blank cells" do
        call

        expect(User.find_by!(email: "bob@example.com")).to have_attributes(age: nil, balance: 0, active: true, role: "member")
      end
    end

    context "with invalid rows" do
      let(:file_name) { "invalid_rows.csv" }

      it "writes the valid rows and reports each invalid one at its first failing check" do
        expect { call }.to change(User, :count).by(1)
        expect(call).to have_attributes(status: :completed_with_errors, stats: { total: 7, valid: 1, invalid: 6, written: 1 })
        expect(error_rows(call)).to contain_exactly(
          [ 2, "email", :invalid_format ], [ 3, "age", :invalid_type ], [ 4, "name", :too_short ],
          [ 5, "role", :inclusion ], [ 7, "email", :duplicate ], [ 8, "email", :required ]
        )
        expect(User.pluck(:email)).to eq([ "erin@example.com" ])
      end

      context "when dry_run is true" do
        let(:dry_run) { true }

        it "checks every row and writes nothing" do
          expect { call }.not_to change(User, :count)
          expect(call).to have_attributes(dry_run?: true, status: :completed_with_errors, stats: include(valid: 1, written: 0))
        end
      end
    end

    # config/imports/users.yml on_error: default skip, row_errors first, max_errors 1000.
    context "with on_error" do
      context "when a row has errors of any code (default: skip)" do
        let(:file_name) { "invalid_rows.csv" }

        it "drops each row with an error, keeps the run going and completes with errors" do
          expect(call).to have_attributes(status: :completed_with_errors, failed?: false)
          expect(call.errors.map(&:code)).to contain_exactly(:invalid_format, :invalid_type, :too_short, :inclusion,
            :duplicate, :required)
        end
      end

      context "when several checks of a row fail (row_errors: first)" do
        let(:file) { csv_file("bad-email,Bob,abc,,,,owner,,") }

        it "reports every column error of the first failing check, not the later model check" do
          expect(error_rows(call)).to contain_exactly([ 2, "email", :invalid_format ], [ 2, "age", :invalid_type ])
          expect(call.stats).to include(invalid: 1)
        end
      end

      context "when a row passes the column rules but fails the model validation" do
        let(:file) { csv_file("ann@example.com,Ann,,,,,owner,,") }

        it "reports the model error" do
          expect(error_rows(call)).to eq([ [ 2, "role", :inclusion ] ])
        end
      end

      context "with exactly max_errors (1000) row errors" do
        let(:file) { csv_file("ann@example.com,Ann,,,,,,,", *Array.new(1000) { |index| "bad-#{index},Bob,,,,,,," }) }

        it "completes and writes the valid rows" do
          expect { call }.to change(User, :count).by(1)
          expect(call).to have_attributes(status: :completed_with_errors, stats: include(invalid: 1000, written: 1))
        end
      end

      context "with more than max_errors (1000) row errors" do
        let(:file) { csv_file("ann@example.com,Ann,,,,,,,", *Array.new(1001) { |index| "bad-#{index},Bob,,,,,,," }) }

        it "stops with too_many_errors, raises ImportFailedError and writes nothing" do
          expect { call }.to raise_error(ImportFailedError) { |error|
            expect(error.result.errors.select(&:file_level?).map(&:code)).to eq(%i[ too_many_errors ])
            expect(error.result.errors.count { |entry| !entry.file_level? }).to eq(1001)
          }
          expect(User.count).to eq(0)
        end
      end
    end

    context "with users that exist" do
      let(:file_name) { "existing_users.csv" }

      it "updates them by email, whatever its case, and creates the others" do
        user = create(:user, email: "ann@example.com", name: "Ann")

        expect { call }.to change(User, :count).by(1)
        expect(user.reload).to have_attributes(name: "Ann Updated", age: 31, balance: 10, active: false, role: "guest")
      end
    end

    context "with aliased and unknown headers" do
      let(:file_name) { "aliases_and_unknown_headers.csv" }

      it "matches aliases in any case and order, and ignores unknown headers" do
        expect(call.status).to eq(:completed)
        expect(User.find_by!(email: "ann@example.com").name).to eq("Ann")
      end
    end

    {
      "users.txt" => :invalid_format,
      "missing_headers.csv" => :missing_headers,
      "header_only.csv" => :empty_file
    }.each do |name, code|
      context "with a rejected file (#{name})" do
        let(:file_name) { name }

        it "raises ImportFailedError with the #{code} result and writes nothing" do
          expect { call }.to raise_error(ImportFailedError) { |error|
            expect(error).to have_attributes(code: :import_failed, status: :unprocessable_content)
            expect(error.result).to be_failed
            expect(error.result.errors.map(&:code)).to eq([ code ])
          }
          expect(User.count).to eq(0)
        end
      end
    end
  end
end
