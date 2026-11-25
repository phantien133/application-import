class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.integer :age
      t.decimal :balance, precision: 12, scale: 2, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :phone
      t.string :role, null: false, default: "member"
      t.string :nickname
      t.string :label
      t.date :created_on
      t.datetime :last_login_at
      t.bigint :created_by_id

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :created_by_id
  end
end
