require 'mime/types'
require 'wand'

module Joint
  autoload :Version, 'joint/version'

  def self.file_name(file)
    file.respond_to?(:original_filename) ? file.original_filename : File.basename(file.path)
  end

  module ClassMethods
    def attachment(name)
      self.class.class_inheritable_accessor :attachment_names
      self.class.attachment_names ||= []
      self.class.attachment_names << name

      after_save     :save_attachments
      before_destroy :destroy_attached_files

      key "#{name}_id".to_sym,   ObjectId
      key "#{name}_name".to_sym, String
      key "#{name}_size".to_sym, Integer
      key "#{name}_type".to_sym, String

      define_method(name) do
        AttachmentProxy.new(self, name)
      end

      define_method("#{name}=") do |file|
        self["#{name}_id"]           = Mongo::ObjectID.new
        self["#{name}_size"]         = File.size(file)
        self["#{name}_type"]         = Wand.wave(file.path)
        self["#{name}_name"]         = Joint.file_name(file)
        attachment_assignments[name] = file
      end
    end
    
    def grid
      @grid ||= Mongo::Grid.new(database)
    end
  end

  module InstanceMethods
    def attachment_assignments
      @attachment_assignments ||= {}
    end

    def grid
      self.class.grid
    end

    private
      def save_attachments
        attachment_assignments.each do |attachment|
          name, file = attachment
          content_type = self["#{name}_type"]

          if file.respond_to?(:read)
            grid.put(file.read, self["#{name}_name"], :content_type => content_type, :_id => self["#{name}_id"])
          end
        end

        @attachment_assignments.clear
      end

      def destroy_attached_files
        self.class.attachment_names.each do |name|
          grid.delete(self["#{name}_id"])
        end
      end
  end

  class AttachmentProxy
    def initialize(instance, name)
      @instance, @name = instance, name
    end

    def id
      @instance.send("#{@name}_id")
    end

    def name
      @instance.send("#{@name}_name")
    end

    def size
      @instance.send("#{@name}_size")
    end

    def type
      @instance.send("#{@name}_type")
    end

    def grid_io
      @grid_io ||= @instance.grid.get(id)
    end

    def method_missing(method, *args, &block)
      grid_io.send(method, *args, &block)
    end
  end
end