class Employee < ApplicationRecord
  include PiiAttributes

  belongs_to :company
  has_many :assessments, dependent: :destroy

  pii_attributes :name, :email

  validates :name, :email, presence: true
end
