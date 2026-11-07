module Pii
  module Scrubber
    FILTERED = "[FILTERED]".freeze
    FILTERED_EMAIL = "[FILTERED_EMAIL]".freeze
    REDACTED = "[REDACTED]".freeze
    FAILED = "[LOG LINE REMOVED: COULD NOT BE SCRUBBED]".freeze

    EMAIL = /[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}/

    module_function

    # Redacts email addresses and the values of declared PII attributes in
    # these shapes: Ruby hash ("a"=>v), JSON ("a":v), key-colon (a: v),
    # SQL equals ("a" = v) and bind arrays (["a", v]). Values may be quoted
    # strings, bare tokens, or JSON objects and arrays of any depth.
    # Fails closed: if scrubbing itself fails, the line is replaced.
    def scrub_text(text)
      return text unless text.is_a?(String)

      names = Registry.all_names
      result = text
      result = redact_named_values(result, names) if names.any? { |name| text.include?(name) }
      result = result.gsub(EMAIL, FILTERED_EMAIL) if result.include?("@")
      result
    rescue StandardError
      FAILED
    end

    # Second guard for exports: returns the attributes with every declared PII
    # attribute of the model replaced by a marker.
    def scrub_attributes(model_class, attributes)
      names = Registry.attributes_for(model_class.name)
      attributes.to_h { |key, value| [ key, names.include?(key.to_s) ? REDACTED : value ] }
    end

    # Works on bytes so every index lookup is constant time, even with
    # multibyte text. Every delimiter we look for is ASCII.
    def redact_named_values(text, names)
      bytes = text.b
      pattern = patterns_for(names)
      out = "".b
      pos = 0
      while (match = pattern.match(bytes, pos))
        out << bytes[pos...match.end(0)]
        out << FILTERED
        pos = value_end(bytes, match.end(0))
      end
      out << bytes[pos..]
      out.force_encoding(Encoding::UTF_8).scrub
    end

    def patterns_for(names)
      @patterns ||= {}
      @patterns[names.sort] ||= begin
        alternation = names.sort_by { |name| -name.length }.map { |name| Regexp.escape(name) }.join("|")
        keyed = /(?<![A-Za-z0-9_])("?)(?:#{alternation})\1\s*(?:=>|:(?!:)|=(?!>))\s*/
        bind = /\[\s*"(?:#{alternation})"\s*,\s*/
        Regexp.union(keyed, bind)
      end
    end

    # Index just past the value that starts at `index`.
    def value_end(bytes, index)
      case bytes[index]
      when "'", '"' then quoted_end(bytes, index)
      when "{", "[" then balanced_end(bytes, index)
      when nil then index
      else bare_end(bytes, index)
      end
    end

    def bare_end(bytes, index)
      index += 1 while index < bytes.length && !" \t\r\n,)]}".include?(bytes[index])
      index
    end

    # Handles backslash escapes and SQL's doubled quote ('').
    def quoted_end(bytes, start)
      quote = bytes[start]
      index = start + 1
      while index < bytes.length
        char = bytes[index]
        if char == "\\"
          index += 2
        elsif char == quote
          return index + 1 unless bytes[index + 1] == quote

          index += 2 # doubled quote inside the literal
        else
          index += 1
        end
      end
      bytes.length
    end

    # Matching close bracket for { or [, ignoring brackets inside strings.
    # Unbalanced input redacts to the end of the line.
    def balanced_end(bytes, start)
      depth = 0
      index = start
      while index < bytes.length
        char = bytes[index]
        if char == '"' || char == "'"
          index = quoted_end(bytes, index)
          next
        end
        depth += 1 if char == "{" || char == "["
        depth -= 1 if char == "}" || char == "]"
        index += 1
        return index if depth.zero?
      end
      bytes.length
    end
  end
end
