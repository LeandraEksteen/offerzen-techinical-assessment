class Admin < ApplicationRecord
  include PiiAttributes

  belongs_to :company
  has_secure_password

  pii_attributes :email, :password_digest

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true
end
