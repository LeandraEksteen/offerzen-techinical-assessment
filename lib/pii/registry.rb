module Pii
  # Which attributes each model has declared as personal data.
  module Registry
    @attributes = {}
    @mutex = Mutex.new

    class << self
      # Idempotent, so reloading models in development is safe.
      def register(class_name, names)
        @mutex.synchronize do
          @attributes[class_name.to_s] = (@attributes.fetch(class_name.to_s, []) | names.map(&:to_s))
        end
      end

      def attributes_for(class_name)
        @mutex.synchronize { @attributes.fetch(class_name.to_s, []).dup }
      end

      def all_names
        @mutex.synchronize { @attributes.values.flatten.uniq }
      end
    end
  end
end
