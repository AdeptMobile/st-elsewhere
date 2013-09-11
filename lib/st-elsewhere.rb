module StElsewhere

  # Specifies a one-to-many association across database connections.
  # This was inspired by the original StEsleware project, but has since been largely reworked by Adept Mobile

  attr_accessor :associations_elsewhere
  def has_many_elsewhere(association_id, options = {}, &extension)
    association_class = (options[:class_name] || association_id.to_s).classify.constantize
    through = options[:through]
    raise ArgumentError.new("You must include :through => association for has_many_elsewhere") if not through
    self.associations_elsewhere ||= [association_id]
    collection_accessor_methods_elsewhere(association_id, association_class, through)
  end

  # Dynamically adds all accessor methods for the has_many_elsewhere association
  def collection_accessor_methods_elsewhere(association_id, association_class, through)
    association_singular = association_id.to_s.singularize
    association_plural   = association_id.to_s
    association_collection = []
    through_association_singular = through.to_s.singularize
    my_class       = self
    my_foreign_key = self.to_s.foreign_key
    target_association_class = association_class
    target_association_foreign_key = association_class.to_s.foreign_key

    # Bar#event_ids
    define_method("#{association_singular}_ids") do
      #Bar.bar_events.map -> event_id
      self.send( "#{through.to_s.pluralize}" ).map{|through_instance| through_instance.send( "#{association_singular}_id" )}
    end

    # Bar#event_ids=
    define_method("#{association_singular}_ids=") do |new_association_ids|
      self.send("#{association_plural}=", new_association_ids)
    end

    # Bar#events
    define_method("#{association_plural}") do
      if self.new_record? #we don't need to check the DB if this is a new record
        return association_collection
      else
        return target_association_class.find( self.send( "#{association_singular}_ids" ) )
      end
    end

    # Bar#events=
    define_method("#{association_plural}=") do |new_associations|
      if self.new_record?
        association_collection = new_associations
      else #we can save this
        unless association_collection.nil? || association_collection.empty?
          #this will happen on_create as there will still be associations in memory but not in the DB
          #in this case, ignore new_associations and use 
          desired_association_ids = self.class.associations_to_association_ids( association_collection )
          association_collection = []
        else
          #self.
          desired_association_ids = self.class.associations_to_association_ids( new_associations )
        end

        #self.event_ids
        current_association_ids = self.send( "#{association_singular}_ids" )

        removed_target_association_ids  = current_association_ids - desired_association_ids
        new_target_association_ids      = desired_association_ids - current_association_ids

        logger.info "StElsewhere: removing associations #{removed_target_association_ids}"
        through_class = through.to_s.singularize.camelize.constantize #get "BarEvent"
        self.send("remove_#{association_singular}_associations", through_class, removed_target_association_ids) unless removed_target_association_ids.empty?
        logger.info "StElsewhere: adding associations #{new_target_association_ids}"
        self.send("add_#{association_singular}_associations", new_target_association_ids) unless new_target_association_ids.empty?
      end
    end

    ###########
    # PRIVATE #
    ###########

    # Hospital#remove_doctor_associations (private)
    define_method("remove_#{association_singular}_associations") do |through_class, removed_target_associations|
      association_instances_to_remove =
        through_class.send("find_all_by_#{my_foreign_key}_and_#{target_association_foreign_key}", self.id, removed_target_associations)
      through_class.delete(association_instances_to_remove)
    end

    # Hospital#add_doctor_associations (private)
    define_method("add_#{association_singular}_associations") do |target_association_ids|
      through_class = through.to_s.singularize.camelize.constantize
      targets_to_add = target_association_class.find(target_association_ids)
      targets_to_add.each do |target_association|
        new_association = through_class.new(my_foreign_key => self.id, target_association_foreign_key => target_association.id)
        new_association.save
      end
    end

    private "remove_#{association_singular}_associations".to_sym, "add_#{association_singular}_associations".to_sym

  end
  
  def save
    result = super
    #save our associations
    unless self.class.associations_elsewhere.empty?
      self.class.associations_elsewhere.each do |association|
        self.send("#{association.to_s.pluralize}=", self.send("#{association.to_s.pluralize}") )
      end
    end
    result
  end

  def save!
    result = super
    #save our associations
    unless self.class.associations_elsewhere.empty?
      self.class.associations_elsewhere.each do |association|
        self.send("#{association.to_s.pluralize}=", self.send("#{association.to_s.pluralize}") )
      end
    end
    result
  end

  #The associations could be a collection of objects, ids, or the string of the object id
  #this function should normalize that into an array of ids
  def associations_to_association_ids(associations)
    ids = []
    if associations && !associations.empty?
      associations.reject!{|a| a.to_s.empty? }
      associations.each do |association|
        association_class = association.class.to_s
        ids << case association_class
              when "String"
                association.to_i
              when "Fixnum"
                association
              else
                association.id
        end
      end
    end
    ids
  end

  private :collection_accessor_methods_elsewhere

end

ActiveRecord::Base.extend StElsewhere