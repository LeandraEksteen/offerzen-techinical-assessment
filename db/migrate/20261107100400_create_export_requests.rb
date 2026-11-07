class CreateExportRequests < ActiveRecord::Migration[8.1]
  # A small table: one row per export an admin asks for. It holds the filters
  # (never personal data) so the background job only needs the record id.
  def change
    create_table :export_requests do |t|
      t.references :company, null: false, foreign_key: true
      t.references :admin, null: false, foreign_key: true
      t.string :state, null: false, default: "in_progress"
      t.date :date_from
      t.date :date_to
      t.string :status_filter
      t.integer :row_count
      t.datetime :finished_at

      t.timestamps
    end

    add_index :export_requests, %i[company_id created_at]
    # At most one export per admin can be in progress, even if two clicks race.
    add_index :export_requests, :admin_id, unique: true, where: "state = 'in_progress'",
              name: "index_export_requests_one_in_progress_per_admin"
  end
end
