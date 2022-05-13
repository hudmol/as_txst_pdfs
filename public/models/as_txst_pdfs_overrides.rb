
# patch XMLCleaner to handle pagination descriptions in McCarthy like this:
#   237&238;

class XMLCleaner
  # method indentical to public/app/lib/xml_cleaner.rb except where marked JJJ
  def replace_html_entities(file_path)
    File.open(file_path + ".tmp", "w") do |outfile|
      File.open(file_path) do |infile|
        infile.each_with_index do |line, index|
          line = HTMLEntities.new.decode(line)
          # decode turns &amp; into & so need to undo that here for PDF to work
          # JJJ                                        vvv - added 0-9
          if line.match(/&\s+/) || line.match(/&[A-Za-z0-9]+[^;]/)
            line.gsub!('&', '&amp;')
          end
          outfile.puts(line)
        end
      end
    end
    File.rename(file_path + ".tmp", file_path)
  end
end


# Overrides methods in public/app/models/finding_aid_pdf.rb

class FindingAidPDF

  def source_file
    # We'll use the original controller so we can find and render the PDF
    # partials, but just for its ERB rendering.
    renderer = PdfController.new
    start_time = Time.now

    @repo_code = @resource.repository_information.fetch('top').fetch('repo_code')

    # .length == 1 would be just the resource itself.
    has_children = @ordered_records.entries.length > 1

    out_html = Tempfile.new
    out_html.write(renderer.render_to_string partial: 'header', layout: false, :locals => {:record => @resource})

    out_html.write(renderer.render_to_string partial: 'titlepage', layout: false, :locals => {:record => @resource})

    # Drop the resource and filter the AOs
    series_count = 0;
    toc_aos = @ordered_records.entries.drop(1).select {|entry|
      if entry.depth == 1
        DEPTH_1_LEVELS.include?(entry.level)
      elsif entry.depth == 2
        DEPTH_2_LEVELS.include?(entry.level)
      else
        false
      end
    }.map {|entry|
      if entry.level == 'series'
        series_count += 1
        entry.display_string = 'Series ' + romanize(series_count) + ': ' +  entry.display_string
      end
      entry
    }

    out_html.write(renderer.render_to_string partial: 'toc', layout: false, :locals => {:resource => @resource, :has_children => has_children, :ordered_aos => toc_aos})

    out_html.write(renderer.render_to_string partial: 'resource', layout: false, :locals => {:record => @resource, :has_children => has_children})

    page_size = 50
    depth_counts = {}
    series_count = 0
    found_instance = false
    last_indicator = false

    @ordered_records.entries.drop(1).each_slice(page_size) do |entry_set|
      if AppConfig[:pui_pdf_timeout] && AppConfig[:pui_pdf_timeout] > 0 && (Time.now.to_i - start_time.to_i) >= AppConfig[:pui_pdf_timeout]
        raise TimeoutError.new("PDF generation timed out.  Sorry!")
      end

      uri_set = entry_set.map(&:uri)
      record_set = archivesspace.search_records(uri_set, {}, true).records

      record_set.zip(entry_set).each do |record, entry|
        next unless record.is_a?(ArchivalObject)

        new_box = false

        if !Array(record.instances).empty?
          first_container = Array(record.instances).select{|i| i.has_key?('sub_container')}.first
          if found_instance
            first_instance = false
          else
            if first_container
              first_instance = true
              found_instance = true
            end
          end

          if first_container
            if last_indicator != first_container['sub_container']['top_container']['_resolved']['indicator']
              last_indicator = first_container['sub_container']['top_container']['_resolved']['indicator']
              new_box = true
            end
          end
        end

        depth_counts[entry.depth] ||= 0
        depth_counts[entry.depth] += 1
        series_count += 1 if record.level == 'series'
        out_html.write(renderer.render_to_string partial: 'archival_object', layout: false,
                       :locals => {
                         :record => record,
                         :level => entry.depth,
                         :position => depth_counts[entry.depth],
                         :roman_position => romanize(series_count),
                         :first_instance => first_instance,
                         :new_box => new_box,
                       })
      end
    end

    out_html.write(renderer.render_to_string partial: 'footer', layout: false, :locals => {:record => @resource, :has_children => has_children})
    out_html.close

    out_html
  end

  def romanize(n)
    # sigh

    @romans ||= { 1000 => "M", 900 => "CM", 500 => "D", 400 => "CD", 100 => "C", 90 => "XC",
                  50 => "L", 40 => "XL", 10 => "X", 9 => "IX", 5 => "V", 4 => "IV", 1 => "I" }

    roman = ""
    @romans.each do |value, letter|
      roman << letter*(n / value)
      n = n % value
    end

    roman
  end
end
