class RunConfig < ApplicationRecord
  has_many :runs, dependent: :destroy

  validates :url, presence: true, format: { with: URI::Parser.new.make_regexp }
  validates :url, uniqueness: true
  validates :url, length: { maximum: 2048 }
end
