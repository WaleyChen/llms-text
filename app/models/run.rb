class Run < ApplicationRecord
  belongs_to :run_config
  validates :run_config_id, presence: true

  after_create_commit :broadcast_run_update
  after_update_commit :broadcast_run_update

  STATUS_PENDING   = "pending"
  STATUS_RUNNING   = "running"
  STATUS_COMPLETED = "completed"
  STATUS_FAILED   = "failed"
  STATUSES = [STATUS_PENDING, STATUS_RUNNING, STATUS_COMPLETED, STATUS_FAILED].freeze

  MODEL_ALL        = "all"
  MODEL_NONE       = "N/A"
  MODEL_CLAUDE_SONNET_4_5 = "claude-sonnet-4-5"
  MODEL_GPT_5_2 = "gpt-5.2"
  MODELS = [MODEL_NONE, MODEL_CLAUDE_SONNET_4_5, MODEL_GPT_5_2].freeze
  LLM_MODELS = [MODEL_CLAUDE_SONNET_4_5, MODEL_GPT_5_2].freeze

  validates :status, inclusion: { in: STATUSES }

  def start
    self.started_at = Time.now
    self.status = STATUS_RUNNING
    self.save!
    broadcast_run_update
  end

  def complete
    self.finished_at = Time.now
    self.status = STATUS_COMPLETED
    self.save!
    broadcast_run_update
  end

  def fail
    self.finished_at = Time.now
    self.status = STATUS_FAILED
    self.save!
    broadcast_run_update
  end

  def append_debug_logs(lines)
    return if lines.blank?

    self.debug_logs ||= ""
    self.debug_logs += (lines.is_a?(String) ? [lines] : Array(lines)).join("\n")
    self.debug_logs += "\n" unless self.debug_logs.end_with?("\n")
    save!
  end

  def append_llms_txt(lines)
    return if lines.blank?

    self.llms_txt ||= ""
    self.llms_txt += (lines.is_a?(String) ? [lines] : Array(lines)).join("\n")
    self.llms_txt += "\n" unless self.llms_txt.end_with?("\n")
    save!
  end

  # Broadcasts the run update to the client
  def broadcast_run_update
    Rails.logger.info("[Cable] Broadcasting run update: #{id}, status: #{status}")
    RunConfigChannel.broadcast_to(run_config, { run: as_json })
  rescue => e
    Rails.logger.warn("[Cable] broadcast failed: #{e.message}")
  end
end
