RSpec.describe "User imports" do
  let(:json) { response.parsed_body.deep_symbolize_keys }
  let(:header) { "Email,Name,Age,Balance,Active,Phone,Role,Nickname,Joined" }

  def upload(*lines, filename: "users.csv")
    file = Tempfile.new([ File.basename(filename, ".*"), File.extname(filename) ])
    file.write([ header, *lines ].join("\n"))
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/csv", original_filename: filename)
  end

  def import(file, **params)
    post import_users_path, params: { file:, **params }
  end

  describe "POST /users/import" do
    it "creates the users of the file" do
      file = upload("Ann@Example.com,Ann Lee,30,1234.5,yes,0912345678,Admin,ann,2026-01-02",
        "bob@example.com,Bob,,,,,,,")

      expect { import(file) }.to change(User, :count).by(2)

      expect(response).to have_http_status(:ok)
      expect(json[:data]).to include(status: "completed", dry_run: false, errors_count: 0, errors: [])
      expect(json[:data][:stats]).to eq(total: 2, valid: 2, invalid: 0, written: 2)
    end

    it "casts the cells and fills the defaults of blank ones" do
      import(upload("Ann@Example.com,Ann Lee,30,1234.5,yes,0912345678,Admin,ann,2026-01-02", "bob@example.com,Bob,,,,,,,"))

      expect(User.find_by!(email: "ann@example.com")).to have_attributes(name: "Ann Lee", age: 30, balance: 1234.5,
        active: true, role: "admin", created_on: Date.new(2026, 1, 2))
      expect(User.find_by!(email: "bob@example.com")).to have_attributes(age: nil, role: "member", active: true, balance: 0)
    end

    it "reports a row with several checks failing once, at its first failing check" do
      import(upload("bob@example.com,Bob,abc,,,,owner,,"))

      expect(json[:data][:errors].pluck(:code)).to eq(%w[ invalid_type ])
    end

    it "updates users whose email already exists" do
      user = create(:user, email: "ann@example.com", name: "Old Name")

      expect { import(upload("ANN@example.com,New Name,31,,,,,,")) }.not_to change(User, :count)

      expect(json[:data][:stats]).to include(written: 1)
      expect(user.reload).to have_attributes(name: "New Name", age: 31)
    end

    it "skips invalid rows and reports their errors" do
      file = upload("not-an-email,Ann,30,,,,,,", "bob@example.com,Bob,abc,,,,owner,,", "carl@example.com,Carl,,,,,,,",
        "Carl@example.com,Carl Again,,,,,,,")

      expect { import(file) }.to change(User, :count).by(1)

      expect(json[:data]).to include(status: "completed_with_errors", errors_count: 3)
      expect(json[:data][:stats]).to eq(total: 4, valid: 1, invalid: 3, written: 1)
      expect(json[:data][:errors].map { |error| error.values_at(:line, :column, :code) }).to contain_exactly(
        [ 2, "email", "invalid_format" ], [ 3, "age", "invalid_type" ], [ 5, "email", "duplicate" ]
      )
    end

    it "writes nothing in a dry run" do
      expect { import(upload("ann@example.com,Ann,,,,,,,"), dry_run: "true") }.not_to change(User, :count)

      expect(json[:data]).to include(status: "completed", dry_run: true)
      expect(json[:data][:stats]).to include(valid: 1, written: 0)
    end

    it "renders 422 import_failed when the file is rejected" do
      import(upload("ann@example.com,Ann,,,,,,,", filename: "users.txt"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error]).to include(code: "import_failed")
      expect(json[:error][:details][:errors].first).to include(code: "invalid_format")
    end

    it "renders 422 import_failed when required headers are missing" do
      header.replace("Name,Age")

      import(upload("Ann,30"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json[:error][:details][:errors].first).to include(code: "missing_headers")
    end

    it "renders 400 for a dry_run that is not a boolean" do
      expect { import(upload("ann@example.com,Ann,,,,,,,"), dry_run: "maybe") }.not_to change(User, :count)

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("invalid_parameter")
    end

    it "renders 400 without a file" do
      post import_users_path

      expect(response).to have_http_status(:bad_request)
      expect(json[:error][:code]).to eq("parameter_missing")
    end
  end
end
