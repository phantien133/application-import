# A birthday instead of an age that goes stale. Existing ages are dropped: a birthday
# cannot be derived from them (rollback restores the column, empty).
class ReplaceAgeWithBirthdayOnUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :birthday, :date
    remove_column :users, :age, :integer
  end
end
