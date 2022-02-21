
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


# Overrides public/app/models/finding_aid_pdf.rb
# Name change required to get it to load

require 'tempfile'

class FindingAidPDF

  DEPTH_1_LEVELS = ['collection', 'recordgrp', 'series']
  DEPTH_2_LEVELS = ['subgrp', 'subseries', 'subfonds']

  attr_reader :repo_id, :resource_id, :archivesspace, :base_url, :repo_code

  def initialize(repo_id, resource_id, archivesspace_client, base_url)
    @repo_id = repo_id
    @resource_id = resource_id
    @archivesspace = archivesspace_client
    @base_url = base_url

    @resource = archivesspace.get_record("/repositories/#{repo_id}/resources/#{resource_id}")
    @ordered_records = archivesspace.get_record("/repositories/#{repo_id}/resources/#{resource_id}/ordered_records")

    # make sure finding aid title isn't only like /^\n$/
    if @resource.finding_aid['title'] and @resource.finding_aid['title'] =~ /\w/
      @short_title = @resource.finding_aid['title'].lstrip.split("\n")[0].strip
    end
  end

  def suggested_filename
    # Use the EAD ID.  If that's missing, use the 4-part identifier
    filename = (@resource.ead_id || @resource.four_part_identifier.reject(&:blank?).join('_'))

    # no spaces, please.
    filename.gsub(' ', '_') + '.pdf'
  end

  def short_title
    @short_title || suggested_filename
  end

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
          if !found_instance
            first_instance = true
            found_instance = true
          else
            first_instance = false
          end
          if last_indicator != Array(record.instances).first['sub_container']['top_container']['_resolved']['indicator']
            last_indicator = Array(record.instances).first['sub_container']['top_container']['_resolved']['indicator']
            new_box = true
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

    out_html.write(renderer.render_to_string partial: 'footer', layout: false, :locals => {:record => @resource})
    out_html.close

    out_html
  end

  def romanize(n)
    @romans ||= { 1000 => "M", 900 => "CM", 500 => "D", 400 => "CD", 100 => "C", 90 => "XC",
                  50 => "L", 40 => "XL", 10 => "X", 9 => "IX", 5 => "V", 4 => "IV", 1 => "I" }

    roman = ""
    @romans.each do |value, letter|
      roman << letter*(n / value)
      n = n % value
    end

    roman
  end

  def generate
    out_html = source_file

    XMLCleaner.new.clean(out_html.path)

    pdf_file = Tempfile.new
    pdf_file.close

    renderer = org.xhtmlrenderer.pdf.ITextRenderer.new
    renderer.set_document(java.io.File.new(out_html.path))

    # FIXME: We'll need to test this with a reverse proxy in front of it.
    renderer.shared_context.base_url = base_url

    renderer.layout

    pdf_output_stream = java.io.FileOutputStream.new(pdf_file.path)
    renderer.create_pdf(pdf_output_stream)
    pdf_output_stream.close

    out_html.unlink

    pdf_file
  end
end
