class CreateAdmins < ActiveRecord::Migration[8.1]
  def change
    create_table :admins do |t|
      t.references :company, null: false, foreign_key: true
      t.string :email, null: false
      t.string :password_digest, null: false

      t.timestamps
    end
    add_index :admins, :email, unique: true
  end
end
