class RunConfig < ApplicationRecord
  has_many :runs, dependent: :destroy

  validates :url, presence: true, format: { with: URI::Parser.new.make_regexp }
  validates :url, length: { maximum: 2048 }

  after_create_commit :broadcast_run_config_update
  after_update_commit :broadcast_run_config_update

  STATUS_PENDING   = "pending"
  STATUS_CRAWLING   = "crawling"
  STATUS_GENERATING = "generating"
  STATUS_COMPLETED  = "completed"
  STATUS_FAILED    = "failed"
  STATUSES = [STATUS_PENDING, STATUS_CRAWLING, STATUS_GENERATING, STATUS_COMPLETED, STATUS_FAILED].freeze

  def start_crawl
    update!(status: STATUS_CRAWLING)
    broadcast_run_config_update
  end

  def start_generating
    if status == STATUS_CRAWLING
      update!(status: STATUS_GENERATING)
    end
    broadcast_run_config_update
  end

  def complete
    return unless runs.all? { |r| r.status == Run::STATUS_COMPLETED }
    update!(status: STATUS_COMPLETED)
    broadcast_run_config_update
  end

  def fail
    update!(status: STATUS_FAILED)
    broadcast_run_config_update
  end

  # Broadcasts the run config update to the client
  def broadcast_run_config_update
    Rails.logger.info("[Cable] Broadcasting run config update: #{id}, status: #{status}")
    RunConfigChannel.broadcast_to(self, { run_config: as_json })
  rescue => e
    Rails.logger.warn("[Cable] broadcast failed: #{e.message}")
  end
end
