class FormatParser::PDFParser
  include FormatParser::IOUtils

  # First 9 bytes of a PDF should be in this format, according to:
  #
  #  https://stackoverflow.com/questions/3108201/detect-if-pdf-file-is-correct-header-pdf
  #
  # There are however exceptions, which are left out for now.
  #
  PDF_MARKER = /%PDF-1\.[0-8]{1}/

  # Page counts have different markers depending on
  # the PDF type. There is not a single common way of solving
  # this. The only way of solving this correctly is by adding
  # different types of PDF's in the specs.
  #
  COUNT_MARKERS = ['Count ']
  EOF_MARKER    = '%EOF'

  def call(io)
    io = FormatParser::IOConstraint.new(io)

    return unless safe_read(io, 9) =~ PDF_MARKER

    io.seek(io.size - 5)
#    return unless safe_read(io, 5) == '%%EOF'

    xref_offset = locate_xref_table_offset(io)
    return unless xref_offset

    io.seek(xref_offset)
    xref_table = parse_xref_table(io)

    # return unless xref_table.any?
    xref_table.each do |xref|
      io.seek(xref.offset)
      $stderr.puts io.read(xref.length_limit).inspect
    end

    raise "nope"
    FormatParser::Document.new(
      format: :pdf,
      page_count: attributes[:page_count]
    )
  end

  def locate_xref_table_offset(io)
    # Read the "tail" of the PDF and find the 'startxref' declaration
    assumed_xref_table_size = 1024
    tail_pos = io.size - assumed_xref_table_size
    tail_pos = 0 if tail_pos < 0
    io.seek(tail_pos)
    tail = io.read(assumed_xref_table_size)

    # Find the "startxref" declaration and read the first group of integers after it
    start_xref_index = tail.index('startxref')
    return unless start_xref_index

    startxref = tail.byteslice(start_xref_index, 1024)[/\d+/]
    return unless startxref

    startxref.to_i
  end

  XRef = Struct.new(:idx, :offset, :generation_number, :entry_type, :length_limit)
  def parse_xref_table(io)
    xref_table = []
    starting_idx = 0
    num_objects_cross_check = nil
    while line = read_until_linebreak(io, char_limit: 32)
      case line
      when /xref/
        # Starts the cross-reference table
      when /^(\d+) (\d+)$/
        # Defines the starting number of the object and the number of objects in the table
        starting_idx = $1.to_i
        num_objects_cross_check = $2.to_i
      when /^(\d{10}) (\d{5}) (\w)$/
        # The actual object offset. Set the length limit to a ridiculous value since we don't know it
        xref_table << XRef.new(starting_idx + xref_table.length, $1.to_i, $2.to_i, $3, 99999999)
      when /trailer/
        break
      end
    end

    # Check if the number of xrefs we got makes sense
    if num_objects_cross_check && num_objects_cross_check != xref_table.length
      raise "The xref table was declared to contain #{num_objects_cross_check} object refs but contained #{xref_table.length}"
    end

    # Reject all disabled objects
    xref_table.reject! {|e| e.entry_type == 'f' }

    # Sort sequentially in ascending offset in document order
    xref_table.sort_by!(&:offset)

    # Update the limits which will tell us how much we need to read to have the entire object
    pairwise(xref_table) do |xref_a, xref_b|
      xref_a.length_limit = xref_b.offset - xref_a.offset
    end

    xref_table.each do |x|
      $stderr.puts x.inspect
    end
    
    xref_table
  end

  def pairwise(enum)
    pair = []
    enum.each do |e|
      pair << e
      if pair.length == 2
        yield(pair.first, pair.last)
        pair.shift
      end
    end
  end

  def read_until_linebreak(io, char_limit: 32)
    buf = StringIO.new(''.b)
    char_limit.times do
      char = safe_read(io, 1).force_encoding(Encoding::BINARY)
      if char == "\n"
        break
      else
        buf << char
      end
    end
    buf.string.strip
  end

  FormatParser.register_parser self, natures: :document, formats: :pdf
end
