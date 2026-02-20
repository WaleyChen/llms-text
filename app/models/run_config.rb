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

  def fail_all_runs(error_message)
    ActiveRecord::Base.transaction do
      runs.each do |run|
        run.update!(status: Run::STATUS_FAILED, finished_at: Time.current)
        run.append_debug_logs("RunConfig#fail_all_runs: #{error_message}")
      end
      fail
    end
  end

  def append_debug_logs(lines)
    return if lines.blank?

    self.debug_logs ||= ""
    self.debug_logs += (lines.is_a?(String) ? [lines] : Array(lines)).join("\n")
    self.debug_logs += "\n" unless self.debug_logs.end_with?("\n")
    save!
  end

  # Broadcasts the run config update to the client
  def broadcast_run_config_update
    Rails.logger.info("[Cable] Broadcasting run config update: #{id}, status: #{status}")
    RunConfigChannel.broadcast_to(self, { run_config: as_json })
  rescue => e
    Rails.logger.warn("[Cable] broadcast failed: #{e.message}")
  end
end
