class Run < ApplicationRecord
    belongs_to :site
    has_one :site_monitor
    validates :site_id, presence: true

    STATUS_PENDING   = "pending"
    STATUS_RUNNING  = "running"
    STATUS_COMPLETED = "completed"
    STATUS_FAILED   = "failed"
    STATUSES = [STATUS_PENDING, STATUS_RUNNING, STATUS_COMPLETED, STATUS_FAILED].freeze

    validates :status, inclusion: { in: STATUSES }

    def start
        self.started_at = Time.now
        self.status = STATUS_RUNNING
        self.save!
    end

    def complete
        self.finished_at = Time.now
        self.status = STATUS_COMPLETED
        self.save!
    end

    def fail
        self.finished_at = Time.now
        self.status = STATUS_FAILED
        self.save!
    end
end
