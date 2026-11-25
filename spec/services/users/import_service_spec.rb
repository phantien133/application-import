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

  # A failed import: ImportFailedError carrying the failed result with the file error
  # `code`, nothing written. Needs `call` (the subject).
  shared_examples "a rejected import" do |code|
    it "raises ImportFailedError with the #{code} result and writes nothing" do
      expect { call }.to raise_error(ImportFailedError) { |error|
        expect(error).to have_attributes(code: :import_failed, status: :unprocessable_content)
        expect(error.result).to be_failed
        expect(error.result.errors.map(&:code)).to eq([ code ])
      }
      expect(User.count).to eq(0)
    end
  end

  describe "#call" do
    subject(:call) { described_class.new(file, dry_run:).call }

    let(:file) { file_fixture("users/#{file_name}") }
    let(:dry_run) { false }
    let(:valid_row) { "ann@example.com,Ann,1990-01-01,,0900000001,,ann," }

    context "with a valid file" do
      let(:file_name) { "valid.csv" }

      it "creates every user and completes" do
        expect { call }.to change(User, :count).by(2)
        expect(call).to have_attributes(status: :completed, errors: [], stats: { total: 2, valid: 2, invalid: 0, written: 2 })
      end

      it "casts the cells and normalizes email and role" do
        call

        expect(User.find_by!(email: "ann@example.com")).to have_attributes(name: "Ann Lee", birthday: Date.new(1996, 3, 4),
          active: true, phone: "0912345678", role: "admin", nickname: "ann", created_on: Date.new(2026, 1, 2))
      end

      it "fills the defaults of blank optional cells" do
        call

        expect(User.find_by!(email: "bob@example.com")).to have_attributes(active: true, role: "member")
      end

      it "leaves balance to the database default" do
        call

        expect(User.pluck(:balance)).to all(eq(0))
      end
    end

    context "with invalid rows" do
      let(:file_name) { "invalid_rows.csv" }

      it "writes the valid rows and reports each invalid one at its first failing check" do
        expect { call }.to change(User, :count).by(1)
        expect(call).to have_attributes(status: :completed_with_errors, stats: { total: 8, valid: 1, invalid: 7, written: 1 })
        expect(error_rows(call)).to contain_exactly(
          [ 2, "email", :invalid_format ], [ 3, "birthday", :invalid_type ], [ 4, "name", :too_short ],
          [ 5, "role", :inclusion ], [ 7, "email", :duplicate ], [ 8, "email", :required ],
          [ 9, "birthday", :required ], [ 9, "phone", :required ], [ 9, "nickname", :required ]
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
          expect(call.errors.map(&:code).uniq).to contain_exactly(:invalid_format, :invalid_type, :too_short, :inclusion,
            :duplicate, :required)
        end
      end

      context "when several checks of a row fail (row_errors: first)" do
        let(:file) { csv_file("bad-email,Bob,abc,,0900000001,owner,bob,") }

        it "reports every column error of the first failing check, not the later model check" do
          expect(error_rows(call)).to contain_exactly([ 2, "email", :invalid_format ], [ 2, "birthday", :invalid_type ])
          expect(call.stats).to include(invalid: 1)
        end
      end

      context "when a row passes the column rules but fails the model validation" do
        let(:file) { csv_file("ann@example.com,Ann,1990-01-01,,0900000001,owner,ann,") }

        it "reports the model error" do
          expect(error_rows(call)).to eq([ [ 2, "role", :inclusion ] ])
        end
      end

      context "when a row has an email of a blocked domain (custom validator)" do
        let(:file) { csv_file("ann@mailinator.com,Ann,1990-01-01,,0900000001,,ann,", "bob@example.com,Bob,1990-01-01,,0900000002,,bob,") }

        it "skips that row with blocked_domain and writes the others" do
          expect { call }.to change(User, :count).by(1)
          expect(error_rows(call)).to eq([ [ 2, "email", :blocked_domain ] ])
        end
      end

      context "with exactly max_errors (1000) row errors" do
        let(:file) { csv_file(valid_row, *Array.new(1000) { |index| "bad-#{index},Bob,1990-01-01,,0900000002,,bob," }) }

        it "completes and writes the valid rows" do
          expect { call }.to change(User, :count).by(1)
          expect(call).to have_attributes(status: :completed_with_errors, stats: include(invalid: 1000, written: 1))
        end
      end

      context "with more than max_errors (1000) row errors" do
        let(:file) { csv_file(valid_row, *Array.new(1001) { |index| "bad-#{index},Bob,1990-01-01,,0900000002,,bob," }) }

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
        expect(user.reload).to have_attributes(name: "Ann Updated", birthday: Date.new(1995, 5, 6), active: false, phone: "0911111111",
          role: "guest", nickname: "annie")
      end

      it "keeps their balance" do
        user = create(:user, email: "ann@example.com", balance: 500)

        call

        expect(user.reload.balance).to eq(500)
      end
    end

    context "when birthday, phone or nickname is blank" do
      let(:file) { csv_file("ann@example.com,Ann,,,,,,", "bob@example.com,Bob,1990-01-01,,0900000002,,bob,") }

      it "reports each as required and skips the row" do
        expect { call }.to change(User, :count).by(1)
        expect(error_rows(call)).to contain_exactly([ 2, "birthday", :required ], [ 2, "phone", :required ], [ 2, "nickname", :required ])
      end
    end

    context "when the birthday is out of range" do
      let(:file) do
        csv_file("ann@example.com,Ann,#{Date.current + 1},,0900000001,,ann,", "bob@example.com,Bob,1875-12-31,,0900000002,,bob,")
      end

      it "rejects a future birthday (model) and one before 1876 (column rule)" do
        expect(error_rows(call)).to contain_exactly([ 2, "birthday", :less_than_or_equal_to ], [ 3, "birthday", :too_small ])
      end
    end

    context "without the Birthday, Phone or Nickname header" do
      let(:file) do
        Tempfile.new([ "users", ".csv" ]).tap do |csv|
          csv.write("Email,Name\nann@example.com,Ann\n")
          csv.rewind
        end
      end

      it_behaves_like "a rejected import", :missing_headers

      it "names the missing headers" do
        expect { call }.to raise_error(ImportFailedError) { |error|
          expect(error.result.errors.first.details).to eq(headers: %w[ Birthday Phone Nickname ])
        }
      end
    end

    context "with aliased and unknown headers" do
      let(:file_name) { "aliases_and_unknown_headers.csv" }

      it "matches aliases in any case and order, and ignores unknown headers (Balance included)" do
        expect(call.status).to eq(:completed)
        expect(User.find_by!(email: "ann@example.com")).to have_attributes(name: "Ann", birthday: Date.new(1996, 3, 4), balance: 0)
      end
    end

    context "with a file of another format" do
      let(:file_name) { "users.txt" }

      it_behaves_like "a rejected import", :invalid_format
    end

    context "with required headers missing" do
      let(:file_name) { "missing_headers.csv" }

      it_behaves_like "a rejected import", :missing_headers
    end

    context "with a header row only" do
      let(:file_name) { "header_only.csv" }

      it_behaves_like "a rejected import", :empty_file
    end
  end
end
