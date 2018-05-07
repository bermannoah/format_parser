# Implements as_json as returning a Hash
# containing the return values of all the
# reader methods of an object that have
# associated pair writer methods.
#
#   class Foo
#     include AttributesJSON
#     attr_accessor :number_of_bars
#   end
#   the_foo = Foo.new
#   the_foo.number_of_bars = 42
#   the_foo.as_json #=> {:number_of_bars => 42}
module FormatParser::AttributesJSON
  UNICODE_REPLACEMENT_CHAR = [0xFFFD].pack('U')
  MAXIMUM_JSON_NESTING_WHEN_SANITIZING = 512

  # Implements a sane default `as_json` for an object
  # that accessors defined
  def as_json(root: false)
    h = {}
    h['nature'] = nature if respond_to?(:nature) # Needed for file info structs
    methods.grep(/\w\=$/).each_with_object(h) do |attr_writer_method_name, h|
      reader_method_name = attr_writer_method_name.to_s.gsub(/\=$/, '')
      attribute_value = public_send(reader_method_name)
      # When calling as_json on our members there is no need to pass
      # the root: option given to us by the caller
      unwrapped_attribute_value = attribute_value.respond_to?(:as_json) ? attribute_value.as_json : attribute_value
      sanitized_value = _sanitize_json_value(unwrapped_attribute_value)
      h[reader_method_name] = sanitized_value
    end
    if root
      {'format_parser_file_info' => h}
    else
      h
    end
  end

  # Used for sanitizing values that are sourced to `JSON::Generator::State#generate`
  # The reason we need to do this is as follows: `JSON.generate / JSON.dump / JSON.pretty_generate`
  # use a totally different code path than `"foo".to_json(generator_state)`. We cannot predict
  # which one of these two ways our users will be using, and at the same time we need to prevent
  # invalid Strings (ones which cannot be encoded into UTF-8) as well as Float::INFINITY values
  # from being passed to the JSON encoder. Since we cannot override the JSON generator with
  # these additions, instead we will deep-convert the entire object being output to make sure
  # it is up to snuff.
  def _sanitize_json_value(value, nesting = 0)
    raise ArgumentError, 'Nested JSON-ish structure too deep' if nesting > MAXIMUM_JSON_NESTING_WHEN_SANITIZING
    case value
    when Float::INFINITY
      nil
    when String
      value.encode(Encoding::UTF_8, undef: :replace, replace: UNICODE_REPLACEMENT_CHAR)
    when Hash
      Hash[value.map { |k, v| [_sanitize_json_value(k, nesting + 1), _sanitize_json_value(v, nesting + 1)] }]
    when Array
      value.map { |v| _sanitize_json_value(v, nesting + 1) }
    when Struct
      _sanitize_json_value(value.to_h, nesting + 1)
    else
      value
    end
  end

  # Implements to_json with sane defaults, with or without arguments
  def to_json(*maybe_generator_state)
    as_json(root: false).to_json(*maybe_generator_state)
  end
end
