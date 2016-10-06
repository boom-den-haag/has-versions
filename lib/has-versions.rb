def has_versions
  extend  VersionExtensions
  include VersionIncludes
end

module VersionExtensions

  def snapshot(version)
    content_with_right_version = []
    content_present_in_this_version = self.where("version <= '#{version}'").group(:uid)
    content_present_in_this_version.each do |c|
      content_with_right_version << self.where(uid: c.uid).where("version <= '#{version}'").order('version DESC').first
    end
    content_with_right_version
  end

  def commitable
    where("commitable=1 AND (state='draft' OR state='deleted')")
  end

end

module VersionIncludes
  def self.included(base)
    base.class_eval do
      scope :uid, lambda { where("uid>0") }
      scope :with_uid, lambda { |uid| where(uid: uid) }
      scope :publication, where(state: 'publication')
      scope :draft, where(state: 'draft')
      scope :history, where(state: 'history')
      scope :with_version, lambda {|version| self.where("version <= '#{version}'") }

      before_create 'before_create_initialization'
      after_create 'after_create_initialization'
      before_save :ensure_uid_is_present, :ensure_state_is_present, :set_commitable_if_changed
    end
  end

  def histories
    self.class.where(uid: uid).where(state: 'history').order('version DESC').all
  end

  def draft
    self.class.where(uid: uid).where(state: 'draft').all.first
  end

  def publication
    self.class.where(uid: uid).where(state: 'publication').all.first
  end

  def draft!
    self.state = 'draft'
    self.version = nil
    save
  end

  def publish!(version)
    return nil unless commitable?
    return nil unless draft? || deleted?
    return nil if publication && publication.version >= version

    publication.historize! if publication

    self.version = version
    self.commitable = false

    if draft?
      self.state = 'publication'
      slugs.destroy_all if self.is_a?(FriendlyId::Slugged::Model) and slugs.any?
      save
      create_draft!
    elsif deleted?
      self.state = 'history'
      save
    end
  end

  def revert!
    if draft? && publication
      draft = publication.create_draft!
      self.destroy
    end
  end

  def restore!
    if history? || publication?
      draft.destroy if draft
      create_draft!
    end
  end

  def commitable!
    self.commitable = true
    save
  end

  def historize!
    if publication?
      self.state = 'history'
      slugs.destroy_all if self.is_a?(FriendlyId::Slugged::Model) and slugs.any?
      save
    end
  end

  def deleted!
    if draft?
      self.state = 'deleted'
      save
    end
  end

  def create_draft!
    unless self.draft.present?
      draft = self.dup
      draft.state = 'draft'
      draft.created_at = Time.now
      draft.updated_at = Time.now
      draft.commitable = false
      draft.cached_slug = nil if draft.respond_to?(:cached_slug=)

      draft.save
    end
  end

  def draft?
    state.eql?('draft')
  end

  def publication?
    state.eql?('publication')
  end

  def deleted?
    state.eql?('deleted')
  end

  def history?
    state.eql?('history')
  end

  def commitable?
    (draft? || deleted?)  && commitable
  end

  def build_a_slug
    return unless publication?
    super
  end

  protected

  def ensure_uid_is_present
    self.uid = self.id if self.uid.blank? && !self.new_record?
  end

  def ensure_state_is_present
    self.state = 'draft' if self.state.blank?
  end

  def set_commitable_if_changed
    unless new_record?
      self.commitable = true if !self.commitable_changed?
    end
    return true
  end

  def before_create_initialization
    self.state = 'draft'
    self.version = nil
    self.commitable = true if self.commitable.nil?
    return true
  end

  def after_create_initialization
    if uid.blank?
      self.uid = id
      save
    end
  end

end
