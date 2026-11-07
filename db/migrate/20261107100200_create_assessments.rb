class CreateAssessments < ActiveRecord::Migration[8.1]
  # Deliberately no secondary indexes (only the primary key). This mimics a
  # legacy table so the Task 2 baseline is honest; the composite index
  # (company_id, assessment_date) is added later by its own ticket.
  # status and responses_json are intentionally loose: nullable, no constraint.
  def change
    create_table :assessments do |t|
      t.references :company, null: false, foreign_key: true, index: false
      t.references :employee, null: false, foreign_key: true, index: false
      t.string :employee_email
      t.text :status
      t.jsonb :responses_json
      t.date :assessment_date, null: false

      t.timestamps
    end
  end
end
