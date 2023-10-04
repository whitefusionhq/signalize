require "signalize"

module Signalize
  class Struct
    module Accessors
      def members
        @members ||= []
      end

      def signal_accessor(*names)
        names.each do |name|
          members.push(name.to_sym) unless members.find { _1 == name.to_sym }
          signal_getter_name = "#{name}_signal".freeze
          ivar_name = "@#{name}".freeze
  
          define_method "#{name}_signal" do
            instance_variable_get(ivar_name)
          end
  
          define_method name do
            send(signal_getter_name)&.value
          end
  
          define_method "#{name}=" do |val|
            if instance_variable_defined?(ivar_name)
              raise Signalize::Error, "Cannot assign a signal to a signal value" if val.is_a?(Signalize::Signal)
  
              sig = instance_variable_get(ivar_name)
              if sig.is_a?(Signalize::Computed)
                raise Signalize::Error, "Cannot set value of computed signal `#{ivar_name.delete_prefix("@")}'"
              end
  
              sig.value = val
            else
              val = Signalize.signal(val) unless val.is_a?(Signalize::Computed)
              instance_variable_set(ivar_name, val)
            end
          end
        end
      end
    end
  
    extend Accessors
  
    def self.define(*names, &block)
      Class.new(self).tap do |struct|
        struct.signal_accessor(*names)
        struct.class_eval(&block) if block
      end
    end

    def initialize(**data)
      # The below code is all to replicate native Ruby ergonomics
      unknown_keys = data.keys - members
      unless unknown_keys.empty?
        plural_suffix = unknown_keys.length > 1 ? "s" : ""
        raise ArgumentError, "unknown keyword#{plural_suffix}: #{unknown_keys.map { ":#{_1}" }.join(", ")}"
      end

      missing_keys = members - data.keys
      unless missing_keys.empty?
        plural_suffix = missing_keys.length > 1 ? "s" : ""
        raise ArgumentError, "missing keyword#{plural_suffix}: #{missing_keys.map { ":#{_1}" }.join(", ")}"
      end

      # Initialize with keyword arguments
      data.each do |k, v|
        send("#{k}=", v)
      end
    end

    def members = self.class.members

    def deconstruct_keys(...) = to_h.deconstruct_keys(...)

    def to_h = members.each_with_object({}) { _2[_1] = send("#{_1}_signal").peek }

    def inspect
      var_peeks = instance_variables.filter_map do |var_name|
        var = instance_variable_get(var_name)
        "#{var_name.to_s.delete_prefix("@")}=#{var.peek.inspect}" if var.is_a?(Signalize::Signal)
      end.join(", ")
  
      "#<#{self.class}#{var_peeks.empty? ? nil : " #{var_peeks}"}>"
    end

    def to_s
      inspect
    end
  end
end
