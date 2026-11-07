# Declare a model's personal data once:
#
#   pii_attributes :employee_email, :responses_json
#
# That single declaration:
#   * registers the names for Pii::Scrubber (logs, error logs, export guard);
#   * adds them to Rails' request parameter filter (global, by name);
#   * adds them to the model's filter_attributes, so `inspect` shows [FILTERED].
module PiiAttributes
  extend ActiveSupport::Concern

  class_methods do
    def pii_attributes(*names)
      names = names.map(&:to_sym)
      new_names = names.map(&:to_s) - Pii::Registry.all_names
      Pii::Registry.register(self.name, names)
      self.filter_attributes += (names - filter_attributes)

      # Rails reads this same array on every request, so adding to it here
      # takes effect without a restart. Rails may already have compiled the
      # symbols in it into one regexp, so "already there?" is answered by our
      # own registry rather than by looking in the array.
      new_names.each { |attribute| Rails.application.config.filter_parameters << attribute.to_sym }
    end

    def pii_attribute_names
      Pii::Registry.attributes_for(name)
    end
  end
end
