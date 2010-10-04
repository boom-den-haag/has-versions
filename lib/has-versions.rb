def has_versions
  extend  VersionExtensions
  include VersionIncludes
end

module VersionExtensions

  def snapshot( version )
    content_with_right_version = []
    content_present_in_this_version = self.where("version <= '#{version}'").group(:uid)
    content_present_in_this_version.each do |c|
      content_with_right_version << self.where(:uid => c.uid).where("version <= '#{version}'").order('version DESC').first
    end
    return content_with_right_version
  end

  def commitable
    draft.where("commitable=1")
  end  
  
end

module VersionIncludes
  def self.included(base)
    base.class_eval do
      
      # has_many :histories, :class_name => self.name, :primary_key => :uid, :foreign_key => :uid, :conditions => {:state => 'history' }
    
      # has_one :draft, :class_name => self.name, :primary_key => :uid, :foreign_key => :uid, :conditions => {:state => 'draft' }
    
      # has_one :publication, :class_name => self.name, :primary_key => :uid, :foreign_key => :uid, :conditions => {:state => 'publication' }
    
      scope :uid, lambda {|uid| where(:uid =>uid) }
      scope :publication, where(:state=>'publication')
      scope :draft, where(:state=>'draft')
      scope :with_version, lambda {|version| self.where("version <= '#{version}'") }
      
      before_create 'before_create_initialization'
      before_save :ensure_uid_is_present, :ensure_state_is_present, :set_commitable_if_changed

    end
  end

  def histories
    self.class.where(:uid=>uid).where(:state=>'history').order('version DESC').all
  end

  def draft
    self.class.where(:uid=>uid).where(:state=>'draft').all.first
  end

  def publication
    self.class.where(:uid=>uid).where(:state=>'publication').all.first
  end
  
  def draft!
    self.state = 'draft'
    self.version = nil
    self.save
  end

  def publish!(version)

    return nil unless draft? || deleted?
    return nil if publication && publication.version >= version

    if self.is_a?(FriendlyId::Slugged::Model) && publication
      Slug.update_all({:sluggable_id => self.id}, {:sluggable_id => publication.id, :sluggable_type => publication.class.name})
    end
    publication.historize! if publication

    self.version = version
    self.commitable = false

    if draft?
      self.state = 'publication'
      self.save
      create_draft!
    elsif deleted?
      self.state = 'history'
      self.save
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
    self.save
  end  
 
  def historize!
    if publication?
      self.state = 'history'
      self.cached_slug = nil if self.respond_to?(:cached_slug=)
      self.save
    end
  end
  
  def deleted!
    if draft?
      self.state = 'deleted'
      self.save
    end
  end
  
  def create_draft!
    unless self.draft.present?
      draft = self.clone
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
    draft? && commitable
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
    self.commitable = false
    return true
  end


  
end