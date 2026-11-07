class Employee < ApplicationRecord
  belongs_to :company
  has_many :assessments, dependent: :destroy

  validates :name, :email, presence: true
end
