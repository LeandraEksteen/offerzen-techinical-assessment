class Company < ApplicationRecord
  has_many :employees, dependent: :destroy
  has_many :assessments, dependent: :destroy
  has_many :admins, dependent: :destroy
  has_many :export_requests, dependent: :destroy

  validates :name, presence: true
end
